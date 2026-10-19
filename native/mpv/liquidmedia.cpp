#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFunctions>
#include <QPointer>
#include <QQmlExtensionPlugin>
#include <QQuickFramebufferObject>
#include <QQuickOpenGLUtils>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QThread>
#include <QUrl>
#include <QVariantList>
#include <QtGui/qguiapplication_platform.h>
#include <QtGui/qopenglcontext_platform.h>
// Without X11 headers: their macros (None, Bool, Status) break Qt code.
#define EGL_NO_X11
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <atomic>
#include <clocale>
#include <cmath>
#include <memory>
#include <mpv/client.h>
#include "mpris.h"
#include <mpv/render_gl.h>
#include <mutex>

// Callback targets stay alive until mpv has stopped using their context.
// All cross-thread QObject access is a queued invocation protected while
// posting.
struct WakeTarget {
  std::mutex mutex;
  QObject *target = nullptr;
  const char *method = nullptr;
  static void wake(void *opaque) {
    auto *self = static_cast<WakeTarget *>(opaque);
    self->post(self->method);
  }
  void post(const char *slot) {
    std::lock_guard<std::mutex> lock(mutex);
    if (target)
      QMetaObject::invokeMethod(target, slot, Qt::QueuedConnection);
  }
  void clear() {
    std::lock_guard<std::mutex> lock(mutex);
    target = nullptr;
  }
};

// mpv draws in one OpenGL context of its own, created once. Each Qt window
// has its own context, and two windows do not share textures (Quickshell does
// not set AA_ShareOpenGLContexts). An EGLImage does not care about share
// groups: mpv's frame is a texture exported as an EGLImage, and the window
// showing the video imports it and copies it into its framebuffer. Moving the
// video to the PiP and back changes nothing on mpv's side: no track to turn
// off and on, so a live channel does not go black until its next keyframe.
//
// Without EGL (an X11/GLX session) the old way remains: mpv's context shares
// with the window's, and is rebuilt in the window it moves to.
struct EglApi {
  EGLDisplay display = EGL_NO_DISPLAY;
  PFNEGLCREATEIMAGEKHRPROC createImage = nullptr;
  PFNEGLDESTROYIMAGEKHRPROC destroyImage = nullptr;
  PFNEGLCREATESYNCKHRPROC createSync = nullptr;
  PFNEGLDESTROYSYNCKHRPROC destroySync = nullptr;
  PFNEGLWAITSYNCKHRPROC waitSync = nullptr;
  PFNEGLCLIENTWAITSYNCKHRPROC clientWaitSync = nullptr;
  PFNGLEGLIMAGETARGETTEXTURE2DOESPROC targetTexture = nullptr;

  bool load(QOpenGLContext *qt) {
    if (qEnvironmentVariableIntValue("LIQUID_MPV_NO_EGLIMAGE") == 1)
      return false;
    auto *native = qt->nativeInterface<QNativeInterface::QEGLContext>();
    if (!native || native->display() == EGL_NO_DISPLAY)
      return false;
    display = native->display();
    const QByteArray extensions = eglQueryString(display, EGL_EXTENSIONS);
    if (!extensions.contains("EGL_KHR_gl_texture_2D_image") ||
        !extensions.contains("EGL_KHR_fence_sync") ||
        !qt->hasExtension(QByteArrayLiteral("GL_OES_EGL_image")))
      return false;
    createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
        eglGetProcAddress("eglCreateImageKHR"));
    destroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
        eglGetProcAddress("eglDestroyImageKHR"));
    createSync = reinterpret_cast<PFNEGLCREATESYNCKHRPROC>(
        eglGetProcAddress("eglCreateSyncKHR"));
    destroySync = reinterpret_cast<PFNEGLDESTROYSYNCKHRPROC>(
        eglGetProcAddress("eglDestroySyncKHR"));
    clientWaitSync = reinterpret_cast<PFNEGLCLIENTWAITSYNCKHRPROC>(
        eglGetProcAddress("eglClientWaitSyncKHR"));
    // A GPU-side wait when there is one; otherwise the CPU waits.
    if (extensions.contains("EGL_KHR_wait_sync"))
      waitSync = reinterpret_cast<PFNEGLWAITSYNCKHRPROC>(
          eglGetProcAddress("eglWaitSyncKHR"));
    targetTexture = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
        qt->getProcAddress("glEGLImageTargetTexture2DOES"));
    return createImage && destroyImage && createSync && destroySync &&
           clientWaitSync && targetTexture;
  }
  // Commands after this point in the current context wait for [sync].
  void wait(EGLSyncKHR sync) {
    if (sync == EGL_NO_SYNC_KHR)
      return;
    if (waitSync)
      waitSync(display, sync, 0);
    else
      clientWaitSync(display, sync, EGL_SYNC_FLUSH_COMMANDS_BIT_KHR,
                     EGL_FOREVER_KHR);
    destroySync(display, sync);
  }
  EGLSyncKHR fence() {
    return createSync(display, EGL_SYNC_FENCE_KHR, nullptr);
  }
};

struct MpvSession {
  mpv_handle *handle = nullptr;
  WakeTarget events;
  // The renderer drawing this player. The last surface to draw takes it:
  // closing the PiP hides its window at once, and a hidden window never
  // destroys its renderer, so waiting for the old one to let go left the
  // main window black.
  std::atomic<const void *> owner{nullptr};
  // Held while a render thread uses `context`: a taker on another window's
  // thread waits for the frame in progress.
  std::mutex renderMutex;
  std::atomic_bool renderReady{false};
  std::atomic_uint generation{0};
  bool initialized = false;
  QOffscreenSurface *surface = nullptr;
  std::unique_ptr<QOpenGLContext> context;
  mpv_render_context *renderer = nullptr;
  GLuint fbo = 0;
  // EGLImage path: mpv's frame lives in `target`, exported as `image`.
  bool eglMode = false;
  EglApi egl;
  GLuint target = 0;
  QSize targetSize;
  EGLImageKHR image = EGL_NO_IMAGE_KHR;
  std::atomic_uint imageGeneration{0};
  // Signalled when a window has finished copying the last frame: mpv must
  // not draw the next one into `target` before that.
  EGLSyncKHR readDone = EGL_NO_SYNC_KHR;
  std::mutex frameMutex;
  std::shared_ptr<WakeTarget> frameTarget;

  MpvSession() {
    // Native offscreen surfaces must be created and destroyed on the GUI
    // thread.
    surface = new QOffscreenSurface;
    surface->setFormat(QSurfaceFormat::defaultFormat());
    surface->create();
  }
  static void *resolve(void *, const char *name) {
    return reinterpret_cast<void *>(
        QOpenGLContext::currentContext()->getProcAddress(name));
  }
  static void frameAvailable(void *opaque) {
    auto *self = static_cast<MpvSession *>(opaque);
    std::shared_ptr<WakeTarget> target;
    {
      std::lock_guard<std::mutex> lock(self->frameMutex);
      target = self->frameTarget;
    }
    if (target)
      WakeTarget::wake(target.get());
  }
  void setFrameTarget(const std::shared_ptr<WakeTarget> &target) {
    std::lock_guard<std::mutex> lock(frameMutex);
    frameTarget = target;
  }
  // The video track mpv dropped when its render context went away, to be
  // selected again once the next context exists.
  QByteArray lostVideo;

  // Qt gives each window its own OpenGL context, and without
  // AA_ShareOpenGLContexts (Quickshell does not set it) two windows do not
  // share textures. Moving the surface to another window (the PiP) needs a
  // new mpv render context there. Freeing the old one under a running video
  // counts as a failed track, and a file without audio would stop: turn
  // video off first (requests and the free's own kill share mpv's queue, in
  // order), and select the same track again in ensureRenderer.
  void releaseRenderer() {
    if (context->thread() == nullptr)
      context->moveToThread(QThread::currentThread());
    if (context->makeCurrent(surface)) {
      if (renderer) {
        if (char *vid = mpv_get_property_string(handle, "vid")) {
          if (qstrcmp(vid, "no") != 0) {
            lostVideo = vid;
            const char *off = "no";
            mpv_set_property_async(handle, 0, "vid", MPV_FORMAT_STRING, &off);
          }
          mpv_free(vid);
        }
        mpv_render_context_set_update_callback(renderer, nullptr, nullptr);
        mpv_render_context_free(renderer);
      }
      if (fbo)
        context->extraFunctions()->glDeleteFramebuffers(1, &fbo);
      context->doneCurrent();
    }
    renderer = nullptr;
    fbo = 0;
    renderReady = false;
    context.reset();
  }
  QString ensureRenderer(QOpenGLContext *qt) {
    if (!surface->isValid())
      return QStringLiteral("mpv-offscreen-surface-unavailable");
    if (context && !eglMode && !QOpenGLContext::areSharing(context.get(), qt))
      releaseRenderer();
    if (!context) {
      context = std::make_unique<QOpenGLContext>();
      context->setFormat(qt->format());
      eglMode = egl.load(qt);
      if (!eglMode)
        context->setShareContext(qt);
      if (!context->create()) {
        context.reset();
        return QStringLiteral("mpv-context-create-failed");
      }
    }
    if (context->thread() == nullptr)
      context->moveToThread(QThread::currentThread());
    if (context->thread() != QThread::currentThread() ||
        (!eglMode && !QOpenGLContext::areSharing(context.get(), qt)))
      return QStringLiteral("mpv-incompatible-context-share-group");
    if (!context->makeCurrent(surface))
      return QStringLiteral("mpv-context-make-current-failed");
    if (renderer)
      return {};
    mpv_opengl_init_params init{resolve, nullptr};
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &init},
        {MPV_RENDER_PARAM_INVALID, nullptr},
        {MPV_RENDER_PARAM_INVALID, nullptr}};
#if QT_CONFIG(wayland)
    if (auto *wayland =
            qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>())
      params[2] = {MPV_RENDER_PARAM_WL_DISPLAY, wayland->display()};
#endif
    const auto result = mpv_render_context_create(&renderer, handle, params);
    if (result < 0)
      return QString::fromUtf8(mpv_error_string(result));
    context->extraFunctions()->glGenFramebuffers(1, &fbo);
    mpv_render_context_set_update_callback(renderer, frameAvailable, this);
    if (!lostVideo.isEmpty()) {
      const char *vid = lostVideo.constData();
      mpv_set_property_async(handle, 0, "vid", MPV_FORMAT_STRING, &vid);
      lostVideo.clear();
    }
    renderReady = true;
    events.post("surfaceReady");
    return {};
  }
  // With mpv's context current: `target` at [size], attached to `fbo` and
  // exported. A new size is a new texture and a new image (generation).
  bool prepareTarget(const QSize &size) {
    if (target && targetSize == size)
      return true;
    auto *gl = context->extraFunctions();
    dropTarget();
    gl->glGenTextures(1, &target);
    gl->glBindTexture(GL_TEXTURE_2D, target);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    gl->glTexImage2D(GL_TEXTURE_2D, 0,
                     context->isOpenGLES() ? GL_RGBA : GL_RGBA8, size.width(),
                     size.height(), 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    gl->glBindTexture(GL_TEXTURE_2D, 0);
    gl->glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    gl->glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_2D, target, 0);
    if (gl->glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
      return false;
    auto *native = context->nativeInterface<QNativeInterface::QEGLContext>();
    const EGLint attributes[] = {EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE};
    image = egl.createImage(
        egl.display, native->nativeContext(), EGL_GL_TEXTURE_2D_KHR,
        reinterpret_cast<EGLClientBuffer>(static_cast<quintptr>(target)),
        attributes);
    if (image == EGL_NO_IMAGE_KHR)
      return false;
    targetSize = size;
    ++imageGeneration;
    return true;
  }
  void dropTarget() {
    if (image != EGL_NO_IMAGE_KHR)
      egl.destroyImage(egl.display, image);
    image = EGL_NO_IMAGE_KHR;
    if (target)
      context->extraFunctions()->glDeleteTextures(1, &target);
    target = 0;
    targetSize = {};
  }
  // Between frames the context belongs to no thread, so the next frame may
  // come from any window's render thread.
  void park() {
    if (context && context->thread() == QThread::currentThread()) {
      context->doneCurrent();
      context->moveToThread(nullptr);
    }
  }
  void detach(const void *who) {
    const void *expected = who;
    if (!owner.compare_exchange_strong(expected, nullptr))
      return;
    setFrameTarget(nullptr);
    {
      std::lock_guard<std::mutex> lock(renderMutex);
      park();
    }
    ++generation;
    events.post("surfaceReleased");
  }
  ~MpvSession() {
    events.clear();
    setFrameTarget(nullptr);
    auto *previous = QOpenGLContext::currentContext();
    QSurface *previousSurface = previous ? previous->surface() : nullptr;
    if (context) {
      if (context->thread() == nullptr)
        context->moveToThread(QThread::currentThread());
      if (context->makeCurrent(surface)) {
        if (renderer) {
          mpv_render_context_set_update_callback(renderer, nullptr, nullptr);
          mpv_render_context_free(renderer);
        }
        if (fbo)
          context->extraFunctions()->glDeleteFramebuffers(1, &fbo);
        if (eglMode) {
          if (readDone != EGL_NO_SYNC_KHR)
            egl.destroySync(egl.display, readDone);
          dropTarget();
        }
        context->doneCurrent();
      }
      context.reset();
      if (previous && previousSurface)
        previous->makeCurrent(previousSurface);
    }
    if (surface->thread() == QThread::currentThread())
      delete surface;
    else
      surface->deleteLater();
    if (handle) {
      mpv_set_wakeup_callback(handle, nullptr, nullptr);
      if (initialized)
        mpv_terminate_destroy(handle);
      else
        mpv_destroy(handle);
    }
  }
};

class MpvPlayer : public QObject {
  Q_OBJECT
  static constexpr uint64_t kLoadfileReply = 1;
  Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
  Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY stateChanged)
  Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
  Q_PROPERTY(bool loading READ loading NOTIFY stateChanged)
  Q_PROPERTY(bool seekable READ seekable NOTIFY stateChanged)
  Q_PROPERTY(bool ready READ ready CONSTANT)
  Q_PROPERTY(
      bool audioOnly READ audioOnly WRITE setAudioOnly NOTIFY stateChanged)
  Q_PROPERTY(qint64 position READ position WRITE seek NOTIFY positionChanged)
  Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
  Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
  Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY volumeChanged)
  Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)
  Q_PROPERTY(QString hardwareDecoder READ hardwareDecoder NOTIFY
                 hardwareDecoderChanged)
  Q_PROPERTY(QVariantList tracks READ tracks NOTIFY tracksChanged)
  std::shared_ptr<MpvSession> m_session = std::make_shared<MpvSession>();
  QUrl m_source;
  QString m_error, m_hwdec;
  QVariantList m_tracks;
  qint64 m_position = 0, m_duration = 0;
  double m_volume = 100;
  bool m_paused = true, m_idle = true, m_loading = false, m_seekable = false,
       m_muted = false;
  bool m_ready = false;
  bool m_audioOnly = false, m_pendingLoad = false, m_trace = false;
  qint64 m_pendingSeek = -1;

  void error(int code) {
    if (code >= 0)
      return;
    m_loading = false;
    m_error = QString::fromUtf8(mpv_error_string(code));
    emit errorChanged();
    emit stateChanged();
  }
  void flag(const char *name, bool value) {
    if (!m_ready)
      return;
    int f = value;
    error(mpv_set_property_async(m_session->handle, 0, name, MPV_FORMAT_FLAG,
                                 &f));
  }
  void command(const QList<QByteArray> &args) {
    if (!m_ready)
      return;
    QList<const char *> pointers;
    for (const auto &arg : args)
      pointers.append(arg.constData());
    pointers.append(nullptr);
    // A loadfile's reply can arrive after the next source was requested (TV
    // falling back to a channel's second stream) and would mark the new one
    // as failed. Its failures come with MPV_EVENT_END_FILE anyway.
    const uint64_t tag = args.value(0) == "loadfile" ? kLoadfileReply : 0;
    error(mpv_command_async(m_session->handle, tag, pointers.data()));
  }

public:
  explicit MpvPlayer(QObject *parent = nullptr) : QObject(parent) {
    // libmpv refuses to start under a non-C LC_NUMERIC ("Non-C locale
    // detected"), and Qt sets the locale from the session: it_IT.UTF-8 in
    // il manutentore's. Qt formats numbers with QLocale, not with the C locale.
    std::setlocale(LC_NUMERIC, "C");
    auto *h = m_session->handle = mpv_create();
    if (!h) {
      m_error = QStringLiteral("mpv_create failed");
      return;
    }
    const std::pair<const char *, const char *> options[] = {
        {"config", "no"},
        {"load-scripts", "no"},
        {"terminal", "no"},
        {"input-default-bindings", "no"},
        {"input-vo-keyboard", "no"},
        {"osc", "no"},
        {"vo", "libmpv"},
        {"idle", "yes"},
        {"keep-open", "no"},
        {"pause", "yes"},
        {"hwdec", "auto-safe"},
        {"ytdl", "yes"},
        {"script-opts", "ytdl_hook-ytdl_path=/usr/bin/yt-dlp"},
    };
    for (const auto &option : options) {
      const int result = mpv_set_option_string(h, option.first, option.second);
      if (result < 0) {
        error(result);
        return;
      }
    }
    const int result = mpv_initialize(h);
    if (result < 0) {
      error(result);
      return;
    }
    m_session->initialized = true;
    m_ready = true;
    m_trace = qEnvironmentVariableIntValue("LIQUID_MPV_TRACE") == 1;
    if (m_trace)
      mpv_request_log_messages(h, "v");
    struct Property {
      const char *name;
      mpv_format format;
    };
    const Property properties[] = {
        {"time-pos", MPV_FORMAT_DOUBLE}, {"duration", MPV_FORMAT_DOUBLE},
        {"pause", MPV_FORMAT_FLAG},      {"idle-active", MPV_FORMAT_FLAG},
        {"seekable", MPV_FORMAT_FLAG},   {"volume", MPV_FORMAT_DOUBLE},
        {"mute", MPV_FORMAT_FLAG},       {"hwdec-current", MPV_FORMAT_STRING},
        {"track-list", MPV_FORMAT_NODE}};
    for (const auto &property : properties)
      error(mpv_observe_property(h, 0, property.name, property.format));
    m_session->events.target = this;
    m_session->events.method = "drainEvents";
    mpv_set_wakeup_callback(h, WakeTarget::wake, &m_session->events);
  }
  ~MpvPlayer() override {
    m_session->events.clear();
    // A render surface can outlive its QML player by one render-thread cleanup.
    // Stop playback now; the last shared session owner destroys the handle.
    if (m_ready)
      command({"stop"});
  }
  std::shared_ptr<MpvSession> session() const {
    return m_ready ? m_session : nullptr;
  }
  QUrl source() const { return m_source; }
  bool ready() const { return m_ready; }
  bool audioOnly() const { return m_audioOnly; }
  void setAudioOnly(bool value) {
    if (value == m_audioOnly || !m_ready)
      return;
    m_audioOnly = value;
    const char *mode = value ? "no" : "auto";
    error(mpv_set_property_async(m_session->handle, 0, "vid", MPV_FORMAT_STRING,
                                 &mode));
    // A YouTube page heard without video: yt-dlp fetches only the audio
    // stream instead of a 1080p video that "vid=no" would then throw away.
    // Takes effect at the next loadfile, which is how sources are opened.
    const char *format = value ? "bestaudio/best" : "bestvideo[height<=?1080]+bestaudio/best";
    error(mpv_set_property_async(m_session->handle, 0, "ytdl-format",
                                 MPV_FORMAT_STRING, &format));
    emit stateChanged();
    loadPending();
  }
  void loadPending() {
    if (!m_pendingLoad || (!m_audioOnly && !m_session->renderReady))
      return;
    m_pendingLoad = false;
    const QByteArray target = m_source.isLocalFile()
                                  ? m_source.toLocalFile().toUtf8()
                                  : m_source.toEncoded();
    command({"loadfile", target, "replace"});
  }
  bool paused() const { return m_paused; }
  bool playing() const { return !m_idle && !m_paused && !m_loading; }
  bool loading() const { return m_loading; }
  bool seekable() const { return m_seekable; }
  qint64 position() const { return m_position; }
  qint64 duration() const { return m_duration; }
  double volume() const { return m_volume; }
  bool muted() const { return m_muted; }
  QString errorString() const { return m_error; }
  QString hardwareDecoder() const { return m_hwdec; }
  QVariantList tracks() const { return m_tracks; }
  void setSource(const QUrl &url) {
    if (!m_ready || (url == m_source && m_error.isEmpty()))
      return;
    if (!url.isEmpty() &&
        (!url.isValid() ||
         (!url.isLocalFile() && url.scheme() != QStringLiteral("https") &&
          url.scheme() != QStringLiteral("http")) ||
         !url.userInfo().isEmpty() ||
         (url.isLocalFile() &&
          (!url.host().isEmpty() || url.toLocalFile().contains(QChar(0)))) ||
         (!url.isLocalFile() && url.host().isEmpty()))) {
      m_error = QStringLiteral("unsupported-media-url");
      emit errorChanged();
      return;
    }
    m_source = url;
    m_error.clear();
    m_position = 0;
    m_duration = 0;
    m_loading = !url.isEmpty();
    emit sourceChanged();
    emit errorChanged();
    emit positionChanged();
    emit durationChanged();
    emit stateChanged();
    if (url.isEmpty()) {
      stop();
      return;
    }
    m_pendingLoad = true;
    m_pendingSeek = -1;
    loadPending();
  }
  void setPaused(bool value) { flag("pause", value); }
  void setMuted(bool value) { flag("mute", value); }
  void setVolume(double value) {
    if (!m_ready || !std::isfinite(value))
      return;
    value = qBound(0.0, value, 150.0);
    error(mpv_set_property_async(m_session->handle, 0, "volume",
                                 MPV_FORMAT_DOUBLE, &value));
  }
  Q_INVOKABLE void seek(qint64 ms) {
    if (ms < 0 || ms > 1000000000000000LL)
      return;
    // Idle too: "repeat one" seeks to 0 after the end, then calls play().
    // A seek sent to an idle mpv fails and would show up as errorString.
    if (m_loading || m_idle) {
      m_pendingSeek = ms;
      return;
    }
    command({"seek", QByteArray::number(double(ms) / 1000.0, 'f', 3),
             "absolute+exact"});
  }
  Q_INVOKABLE void play() {
    if (m_idle && !m_loading && !m_source.isEmpty()) {
      m_pendingLoad = true;
      m_loading = true;
      loadPending();
    }
    setPaused(false);
  }
  Q_INVOKABLE void pause() { setPaused(true); }
  Q_INVOKABLE void stop() {
    m_pendingLoad = false;
    m_pendingSeek = -1;
    m_loading = false;
    m_idle = true;
    command({"stop"});
    emit stateChanged();
  }
  Q_INVOKABLE void selectAudioTrack(int id) { selectTrack("aid", id); }
  Q_INVOKABLE void selectSubtitleTrack(int id) { selectTrack("sid", id); }
  void selectTrack(const char *name, int id) {
    if (id < -1 || id > 1000000 || !m_ready)
      return;
    const auto value = id < 0 ? QByteArray("no") : QByteArray::number(id);
    const char *text = value.constData();
    error(mpv_set_property_async(m_session->handle, 0, name, MPV_FORMAT_STRING,
                                 &text));
  }
public slots:
  void surfaceReleased() { emit surfaceAvailable(); }
  void surfaceReady() { loadPending(); }
  void drainEvents() {
    if (!m_ready)
      return;
    for (;;) {
      auto *event = mpv_wait_event(m_session->handle, 0);
      if (event->event_id == MPV_EVENT_NONE)
        break;
      if (m_trace && event->event_id != MPV_EVENT_LOG_MESSAGE &&
          event->event_id != MPV_EVENT_PROPERTY_CHANGE)
        qDebug().noquote() << "[Liquid.Media][event]"
                           << mpv_event_name(event->event_id) << event->error
                           << event->reply_userdata;
      if ((event->event_id == MPV_EVENT_COMMAND_REPLY &&
           event->reply_userdata != kLoadfileReply) ||
          event->event_id == MPV_EVENT_SET_PROPERTY_REPLY)
        error(event->error);
      if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
        auto *message = static_cast<mpv_event_log_message *>(event->data);
        qDebug().noquote() << "[Liquid.Media][mpv]" << message->prefix
                           << message->text;
      }
      if (event->event_id == MPV_EVENT_FILE_LOADED) {
        m_loading = false;
        // Changing track while playing, mpv ends the old file (END_FILE
        // below sets m_idle) and loads the next one without ever going idle:
        // idle-active never changes, and m_idle stayed true. `playing` was
        // false while the song played, MPRIS said Paused and play()
        // reloaded the file from 0 (19 Oct). A loaded file is not idle.
        m_idle = false;
        // The previous source's failure can arrive after the next one was
        // requested (TV falling back to a channel's second stream): a file
        // that loaded is not in error.
        if (!m_error.isEmpty()) {
          m_error.clear();
          emit errorChanged();
        }
        if (m_pendingSeek >= 0) {
          const auto target = m_pendingSeek;
          m_pendingSeek = -1;
          seek(target);
        }
        emit stateChanged();
      }
      if (event->event_id == MPV_EVENT_END_FILE) {
        auto *end = static_cast<mpv_event_end_file *>(event->data);
        m_loading = false;
        m_idle = true;
        emit stateChanged();
        // Without a working audio device mpv still plays the video to the
        // end, then reports the file as failed. It got to the end: that is
        // an ending, or the playlist would stop on every file.
        const bool reachedEnd =
            end->reason == MPV_END_FILE_REASON_EOF ||
            (end->reason == MPV_END_FILE_REASON_ERROR &&
             end->error == MPV_ERROR_AO_INIT_FAILED && m_duration > 0 &&
             m_position >= m_duration - 1500);
        if (end->reason == MPV_END_FILE_REASON_ERROR && !reachedEnd)
          error(end->error);
        if (reachedEnd)
          emit ended();
      }
      if (event->event_id != MPV_EVENT_PROPERTY_CHANGE)
        continue;
      auto *p = static_cast<mpv_event_property *>(event->data);
      if (!p->data)
        continue;
      const QByteArray name(p->name);
      if (p->format == MPV_FORMAT_DOUBLE) {
        const double value = *static_cast<double *>(p->data);
        if (!std::isfinite(value))
          continue;
        if (name == "time-pos") {
          m_position = qint64(qBound(0.0, value * 1000, 1.0e15));
          emit positionChanged();
        }
        if (name == "duration") {
          m_duration = qint64(qBound(0.0, value * 1000, 1.0e15));
          emit durationChanged();
        }
        if (name == "volume") {
          m_volume = value;
          emit volumeChanged();
        }
      } else if (p->format == MPV_FORMAT_FLAG) {
        const bool value = *static_cast<int *>(p->data) != 0;
        if (name == "pause")
          m_paused = value;
        if (name == "idle-active")
          m_idle = value;
        if (name == "seekable")
          m_seekable = value;
        if (name == "mute") {
          m_muted = value;
          emit volumeChanged();
        }
        emit stateChanged();
      } else if (name == "hwdec-current" && p->format == MPV_FORMAT_STRING) {
        m_hwdec = QString::fromUtf8(*static_cast<char **>(p->data));
        emit hardwareDecoderChanged();
      } else if (name == "track-list" && p->format == MPV_FORMAT_NODE) {
        m_tracks.clear();
        const auto *node = static_cast<mpv_node *>(p->data);
        if (node->format == MPV_FORMAT_NODE_ARRAY)
          for (int i = 0; i < node->u.list->num; i++) {
            const auto &track = node->u.list->values[i];
            if (track.format != MPV_FORMAT_NODE_MAP)
              continue;
            QVariantMap row;
            for (int j = 0; j < track.u.list->num; j++) {
              const auto &value = track.u.list->values[j];
              const QString key = QString::fromUtf8(track.u.list->keys[j]);
              if (value.format == MPV_FORMAT_STRING)
                row[key] = QString::fromUtf8(value.u.string);
              if (value.format == MPV_FORMAT_INT64)
                row[key] = qlonglong(value.u.int64);
              if (value.format == MPV_FORMAT_FLAG)
                row[key] = bool(value.u.flag);
            }
            m_tracks.append(row);
          }
        emit tracksChanged();
      }
    }
  }
signals:
  void sourceChanged();
  void stateChanged();
  void positionChanged();
  void durationChanged();
  void volumeChanged();
  void errorChanged();
  void hardwareDecoderChanged();
  void tracksChanged();
  void ended();
  void surfaceAvailable();
};

class MpvSurface;
class MpvRenderer final : public QQuickFramebufferObject::Renderer {
  std::shared_ptr<MpvSession> m_session;
  std::shared_ptr<WakeTarget> m_wake;
  bool m_claimed = false, m_failed = false, m_lost = false;
  unsigned m_failureGeneration = 0;
  // EGLImage path: the window's own texture bound to mpv's image, and the
  // framebuffer it is copied from.
  GLuint m_imported = 0, m_readFbo = 0;
  unsigned m_importedGeneration = 0;
  void release() {
    if (m_claimed && m_session)
      m_session->detach(this);
    m_claimed = false;
    m_lost = false;
  }
  void reportError(const QString &message) {
    if (!m_wake)
      return;
    std::lock_guard<std::mutex> lock(m_wake->mutex);
    if (m_wake->target)
      QMetaObject::invokeMethod(m_wake->target, "setRenderError",
                                Qt::QueuedConnection, Q_ARG(QString, message));
  }

public:
  ~MpvRenderer() override {
    release();
    // Destroyed on the render thread with the window's context current.
    if (auto *qt = QOpenGLContext::currentContext()) {
      if (m_imported)
        qt->extraFunctions()->glDeleteTextures(1, &m_imported);
      if (m_readFbo)
        qt->extraFunctions()->glDeleteFramebuffers(1, &m_readFbo);
    }
  }
  void renderEgl(QOpenGLContext *qt, QSurface *qtSurface);
  void synchronize(QQuickFramebufferObject *item) override;
  QOpenGLFramebufferObject *
  createFramebufferObject(const QSize &size) override {
    QOpenGLFramebufferObjectFormat format;
    format.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
    return new QOpenGLFramebufferObject(size, format);
  }
  void render() override {
    auto *qt = QOpenGLContext::currentContext();
    auto *qtSurface = qt->surface();
    auto *qtGl = qt->extraFunctions();
    qtGl->glClearColor(0, 0, 0, 1);
    qtGl->glClear(GL_COLOR_BUFFER_BIT);
    if (!m_session || m_failed || m_lost) {
      QQuickOpenGLUtils::resetOpenGLState();
      return;
    }
    std::lock_guard<std::mutex> lock(m_session->renderMutex);
    if (m_claimed && m_session->owner.load() != this) {
      // Another window took the player (PiP opened or closed): step aside
      // until this renderer is replaced, or the two would take turns.
      m_claimed = false;
      m_lost = true;
      QQuickOpenGLUtils::resetOpenGLState();
      return;
    }
    if (!m_claimed) {
      m_session->owner.store(this);
      m_claimed = true;
      m_session->setFrameTarget(m_wake);
    }
    if (m_session->context && m_session->eglMode) {
      renderEgl(qt, qtSurface);
      return;
    }
    // GLsync objects and textures are shared; framebuffer objects are not.
    // The persistent mpv context owns its FBO and attaches Qt's shared texture.
    const bool sync = qt->isOpenGLES()
                          ? qt->format().majorVersion() >= 3
                          : qt->hasExtension(QByteArrayLiteral("GL_ARB_sync"));
    if (!sync) {
      m_failed = true;
      reportError(QStringLiteral("mpv-gl-sync-unavailable"));
      return;
    }
    auto before = qtGl->glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    qtGl->glFlush();
    const auto result = m_session->ensureRenderer(qt);
    if (!result.isEmpty()) {
      m_session->park();
      qt->makeCurrent(qtSurface);
      qtGl->glDeleteSync(before);
      m_failed = true;
      reportError(result);
      QQuickOpenGLUtils::resetOpenGLState();
      return;
    }
    if (m_session->eglMode) {
      // Chosen just now, at the first frame.
      qt->makeCurrent(qtSurface);
      qtGl->glDeleteSync(before);
      m_session->park();
      renderEgl(qt, qtSurface);
      return;
    }
    auto *gl = m_session->context->extraFunctions();
    gl->glWaitSync(before, 0, GL_TIMEOUT_IGNORED);
    gl->glDeleteSync(before);
    gl->glBindFramebuffer(GL_FRAMEBUFFER, m_session->fbo);
    gl->glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_2D, framebufferObject()->texture(),
                               0);
    if (gl->glCheckFramebufferStatus(GL_FRAMEBUFFER) !=
        GL_FRAMEBUFFER_COMPLETE) {
      m_session->park();
      qt->makeCurrent(qtSurface);
      m_failed = true;
      reportError(QStringLiteral("mpv-framebuffer-incomplete"));
      return;
    }
    const auto size = framebufferObject()->size();
    mpv_opengl_fbo fbo{int(m_session->fbo), size.width(), size.height(), 0};
    // Qt Quick applies the FBO texture orientation itself.
    int flip = 0, block = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block},
        {MPV_RENDER_PARAM_INVALID, nullptr}};
    mpv_render_context_update(m_session->renderer);
    mpv_render_context_render(m_session->renderer, params);
    auto after = gl->glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    gl->glFlush();
    m_session->park();
    qt->makeCurrent(qtSurface);
    qtGl->glWaitSync(after, 0, GL_TIMEOUT_IGNORED);
    qtGl->glDeleteSync(after);
    reportError(QString());
    QQuickOpenGLUtils::resetOpenGLState();
  }
};

// Called with the session's render mutex held and the window's context
// current.
void MpvRenderer::renderEgl(QOpenGLContext *qt, QSurface *qtSurface) {
  auto &session = *m_session;
  const auto size = framebufferObject()->size();
  auto fail = [&](const char *error) {
    session.park();
    qt->makeCurrent(qtSurface);
    m_failed = true;
    reportError(QString::fromUtf8(error));
    QQuickOpenGLUtils::resetOpenGLState();
  };
  const auto result = session.ensureRenderer(qt);
  if (!result.isEmpty()) {
    session.park();
    qt->makeCurrent(qtSurface);
    m_failed = true;
    reportError(result);
    QQuickOpenGLUtils::resetOpenGLState();
    return;
  }
  // mpv's side.
  session.egl.wait(session.readDone);
  session.readDone = EGL_NO_SYNC_KHR;
  if (!session.prepareTarget(size))
    return fail("mpv-eglimage-unavailable");
  mpv_opengl_fbo fbo{int(session.fbo), size.width(), size.height(), 0};
  int flip = 0, block = 0;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
      {MPV_RENDER_PARAM_FLIP_Y, &flip},
      {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block},
      {MPV_RENDER_PARAM_INVALID, nullptr}};
  mpv_render_context_update(session.renderer);
  mpv_render_context_render(session.renderer, params);
  EGLSyncKHR drawn = session.egl.fence();
  session.context->extraFunctions()->glFlush();
  const unsigned generation = session.imageGeneration;
  EGLImageKHR image = session.image;
  session.park();
  // The window's side.
  qt->makeCurrent(qtSurface);
  auto *gl = qt->extraFunctions();
  if (!m_imported || m_importedGeneration != generation) {
    if (!m_imported)
      gl->glGenTextures(1, &m_imported);
    gl->glBindTexture(GL_TEXTURE_2D, m_imported);
    session.egl.targetTexture(GL_TEXTURE_2D, image);
    gl->glBindTexture(GL_TEXTURE_2D, 0);
    m_importedGeneration = generation;
  }
  if (!m_readFbo)
    gl->glGenFramebuffers(1, &m_readFbo);
  session.egl.wait(drawn);
  gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, m_readFbo);
  gl->glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                             GL_TEXTURE_2D, m_imported, 0);
  gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, framebufferObject()->handle());
  gl->glBlitFramebuffer(0, 0, size.width(), size.height(), 0, 0, size.width(),
                        size.height(), GL_COLOR_BUFFER_BIT, GL_NEAREST);
  session.readDone = session.egl.fence();
  gl->glFlush();
  reportError(QString());
  QQuickOpenGLUtils::resetOpenGLState();
}

class MpvSurface : public QQuickFramebufferObject {
  Q_OBJECT
  Q_PROPERTY(MpvPlayer *player READ player WRITE setPlayer NOTIFY playerChanged)
  Q_PROPERTY(QString renderError READ renderError NOTIFY renderErrorChanged)
  QString m_renderError;
  QPointer<MpvPlayer> m_player;
  QMetaObject::Connection m_destroyed, m_available;

public:
  std::shared_ptr<WakeTarget> wake = std::make_shared<WakeTarget>();
  explicit MpvSurface(QQuickItem *parent = nullptr)
      : QQuickFramebufferObject(parent) {
    wake->target = this;
    wake->method = "requestFrame";
    connect(this, &QQuickItem::windowChanged, this,
            [this](QQuickWindow *window) {
              if (!window)
                return;
              auto check = [this, window] {
                const auto api = window->rendererInterface()->graphicsApi();
                if (api != QSGRendererInterface::Unknown &&
                    api != QSGRendererInterface::OpenGL)
                  setRenderError(QStringLiteral("mpv-opengl-required"));
              };
              connect(window, &QQuickWindow::sceneGraphInitialized, this, check,
                      Qt::QueuedConnection);
              check();
            });
  }
  ~MpvSurface() override { wake->clear(); }
  MpvPlayer *player() const { return m_player; }
  QString renderError() const { return m_renderError; }
  void setPlayer(MpvPlayer *player) {
    if (player == m_player)
      return;
    disconnect(m_destroyed);
    disconnect(m_available);
    m_player = player;
    if (player)
      m_destroyed = connect(player, &QObject::destroyed, this, [this] {
        update();
        emit playerChanged();
      });
    if (player)
      m_available = connect(player, &MpvPlayer::surfaceAvailable, this,
                            &QQuickItem::update);
    update();
    emit playerChanged();
  }
  Renderer *createRenderer() const override { return new MpvRenderer; }
public slots:
  void requestFrame() { update(); }
  void setRenderError(const QString &error) {
    if (error != m_renderError) {
      m_renderError = error;
      emit renderErrorChanged();
    }
  }
signals:
  void playerChanged();
  void renderErrorChanged();
};

void MpvRenderer::synchronize(QQuickFramebufferObject *item) {
  auto *surface = static_cast<MpvSurface *>(item);
  auto session = surface->player() ? surface->player()->session() : nullptr;
  if (session != m_session) {
    release();
    m_session = std::move(session);
    m_failed = false;
    m_lost = false;
  }
  m_wake = surface->wake;
  if (m_session && m_failed && m_session->generation != m_failureGeneration)
    m_failed = false;
}

class MediaPlugin final : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
  void registerTypes(const char *uri) override {
    qmlRegisterType<MpvPlayer>(uri, 1, 0, "MpvPlayer");
    qmlRegisterType<MpvSurface>(uri, 1, 0, "MpvSurface");
    qmlRegisterType<MprisServer>(uri, 1, 0, "MprisServer");
  }
};
#include "liquidmedia.moc"
