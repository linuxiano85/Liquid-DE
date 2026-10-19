#include "mpris.h"

#include <QCoreApplication>
#include <QDBusConnectionInterface>
#include <QDBusMetaType>
#include <cmath>

namespace {
const QString kPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString kRoot = QStringLiteral("org.mpris.MediaPlayer2");
const QString kPlayer = QStringLiteral("org.mpris.MediaPlayer2.Player");
} // namespace

// ── org.mpris.MediaPlayer2 ─────────────────────────────────────────────────

MprisRootAdaptor::MprisRootAdaptor(MprisServer *parent)
    : QDBusAbstractAdaptor(parent) {}
MprisServer *MprisRootAdaptor::server() const {
  return static_cast<MprisServer *>(parent());
}
QString MprisRootAdaptor::identity() const { return server()->identityText(); }
QString MprisRootAdaptor::desktopEntry() const {
  return server()->desktopEntryText();
}
void MprisRootAdaptor::Raise() { emit server()->raiseRequested(); }
void MprisRootAdaptor::Quit() { emit server()->quitRequested(); }

// ── org.mpris.MediaPlayer2.Player ──────────────────────────────────────────

MprisPlayerAdaptor::MprisPlayerAdaptor(MprisServer *parent)
    : QDBusAbstractAdaptor(parent) {}
MprisServer *MprisPlayerAdaptor::server() const {
  return static_cast<MprisServer *>(parent());
}
QString MprisPlayerAdaptor::playbackStatus() const {
  if (!server()->hasMedia())
    return QStringLiteral("Stopped");
  return server()->playing() ? QStringLiteral("Playing")
                             : QStringLiteral("Paused");
}
QVariantMap MprisPlayerAdaptor::metadata() const { return server()->metadata(); }
double MprisPlayerAdaptor::volume() const { return server()->volume(); }
void MprisPlayerAdaptor::setVolume(double value) {
  if (std::isfinite(value))
    emit server()->volumeRequested(qBound(0.0, value, 1.0));
}
qlonglong MprisPlayerAdaptor::position() const {
  return server()->position() * 1000;
}
bool MprisPlayerAdaptor::canGoNext() const { return server()->canGoNext(); }
bool MprisPlayerAdaptor::canGoPrevious() const {
  return server()->canGoPrevious();
}
bool MprisPlayerAdaptor::canPlay() const { return server()->hasMedia(); }
bool MprisPlayerAdaptor::canPause() const { return server()->hasMedia(); }
bool MprisPlayerAdaptor::canSeek() const { return server()->canSeek(); }
void MprisPlayerAdaptor::Next() { emit server()->nextRequested(); }
void MprisPlayerAdaptor::Previous() { emit server()->previousRequested(); }
void MprisPlayerAdaptor::Pause() { emit server()->pauseRequested(); }
void MprisPlayerAdaptor::PlayPause() { emit server()->playPauseRequested(); }
void MprisPlayerAdaptor::Stop() { emit server()->stopRequested(); }
void MprisPlayerAdaptor::Play() { emit server()->playRequested(); }
void MprisPlayerAdaptor::Seek(qlonglong offsetUs) {
  if (server()->canSeek())
    emit server()->seekRequested(offsetUs / 1000);
}
void MprisPlayerAdaptor::SetPosition(const QDBusObjectPath &track,
                                     qlonglong positionUs) {
  // The specification: ignore a SetPosition meant for another track.
  if (!server()->canSeek() ||
      track.path() != server()->metadata()
                          .value(QStringLiteral("mpris:trackid"))
                          .value<QDBusObjectPath>()
                          .path() ||
      positionUs < 0 || positionUs > server()->length() * 1000)
    return;
  emit server()->positionRequested(positionUs / 1000);
}
void MprisPlayerAdaptor::OpenUri(const QString &uri) {
  emit server()->openRequested(uri);
}

// ── The QML object ─────────────────────────────────────────────────────────

MprisServer::MprisServer(QObject *parent) : QObject(parent) {
  new MprisRootAdaptor(this);
  m_player = new MprisPlayerAdaptor(this);
}

MprisServer::~MprisServer() { withdraw(); }

void MprisServer::componentComplete() {
  m_complete = true;
  if (m_active)
    publish();
}

void MprisServer::setActive(bool value) {
  if (value == m_active)
    return;
  m_active = value;
  if (m_complete)
    value ? publish() : withdraw();
  emit changed();
}

void MprisServer::publish() {
  if (m_registered)
    return;
  auto bus = QDBusConnection::sessionBus();
  if (!bus.isConnected())
    return;
  if (!bus.registerObject(kPath, this, QDBusConnection::ExportAdaptors))
    return;
  // One name per process: two Media windows (the shell can open a second
  // one while the first is closing) must not fight over the same name.
  const QString name = kRoot + QStringLiteral(".minerva_media.instance") +
                       QString::number(QCoreApplication::applicationPid());
  if (!bus.registerService(name)) {
    bus.unregisterObject(kPath);
    return;
  }
  m_busName = name;
  m_registered = true;
  emit changed();
}

void MprisServer::withdraw() {
  if (!m_registered)
    return;
  auto bus = QDBusConnection::sessionBus();
  bus.unregisterService(m_busName);
  bus.unregisterObject(kPath);
  m_registered = false;
  m_busName.clear();
}

void MprisServer::notify(const char *interface, const QVariantMap &values) {
  if (!m_registered || values.isEmpty())
    return;
  auto message = QDBusMessage::createSignal(
      kPath, QStringLiteral("org.freedesktop.DBus.Properties"),
      QStringLiteral("PropertiesChanged"));
  message << QString::fromLatin1(interface) << values << QStringList();
  QDBusConnection::sessionBus().send(message);
}

void MprisServer::notifyPlayer(const QStringList &names) {
  QVariantMap values;
  for (const auto &name : names) {
    if (name == QLatin1String("Metadata"))
      values[name] = metadata();
    else if (name == QLatin1String("PlaybackStatus"))
      values[name] = m_player->playbackStatus();
    else if (name == QLatin1String("Volume"))
      values[name] = m_volume;
    else if (name == QLatin1String("CanGoNext"))
      values[name] = m_canNext;
    else if (name == QLatin1String("CanGoPrevious"))
      values[name] = m_canPrevious;
    else if (name == QLatin1String("CanSeek"))
      values[name] = m_canSeek;
    else if (name == QLatin1String("CanPlay") ||
             name == QLatin1String("CanPause"))
      values[name] = m_hasMedia;
  }
  notify("org.mpris.MediaPlayer2.Player", values);
}

QVariantMap MprisServer::metadata() const {
  QVariantMap map;
  if (!m_hasMedia)
    return map;
  // A new path for each new track: listeners notice the change, and a
  // SetPosition meant for the previous track is recognised and dropped.
  map[QStringLiteral("mpris:trackid")] = QVariant::fromValue(QDBusObjectPath(
      QStringLiteral("/org/minerva/media/track/%1").arg(m_track)));
  if (m_length > 0)
    map[QStringLiteral("mpris:length")] = qlonglong(m_length) * 1000;
  map[QStringLiteral("xesam:title")] = m_title;
  if (!m_artist.isEmpty())
    map[QStringLiteral("xesam:artist")] = QStringList{m_artist};
  if (m_artUrl.isValid() && !m_artUrl.isEmpty())
    map[QStringLiteral("mpris:artUrl")] = m_artUrl.toString();
  return map;
}

void MprisServer::seeked(qint64 positionMs) {
  m_position = qMax<qint64>(0, positionMs);
  if (m_registered)
    emit m_player->Seeked(m_position * 1000);
}

void MprisServer::setTitle(const QString &value) {
  if (value == m_title)
    return;
  m_title = value;
  ++m_track;
  notifyPlayer({QStringLiteral("Metadata")});
  emit changed();
}
void MprisServer::setArtist(const QString &value) {
  if (value == m_artist)
    return;
  m_artist = value;
  notifyPlayer({QStringLiteral("Metadata")});
  emit changed();
}
void MprisServer::setArtUrl(const QUrl &value) {
  if (value == m_artUrl)
    return;
  m_artUrl = value;
  notifyPlayer({QStringLiteral("Metadata")});
  emit changed();
}
void MprisServer::setLength(qint64 value) {
  value = qMax<qint64>(0, value);
  if (value == m_length)
    return;
  m_length = value;
  notifyPlayer({QStringLiteral("Metadata")});
  emit changed();
}
void MprisServer::setPosition(qint64 value) {
  // Polled by listeners (Position is not announced while playing).
  m_position = qMax<qint64>(0, value);
}
void MprisServer::setPlaying(bool value) {
  if (value == m_playing)
    return;
  m_playing = value;
  notifyPlayer({QStringLiteral("PlaybackStatus")});
  emit changed();
}
void MprisServer::setHasMedia(bool value) {
  if (value == m_hasMedia)
    return;
  m_hasMedia = value;
  notifyPlayer({QStringLiteral("PlaybackStatus"), QStringLiteral("Metadata"),
                QStringLiteral("CanPlay"), QStringLiteral("CanPause")});
  emit changed();
}
void MprisServer::setCanGoNext(bool value) {
  if (value == m_canNext)
    return;
  m_canNext = value;
  notifyPlayer({QStringLiteral("CanGoNext")});
  emit changed();
}
void MprisServer::setCanGoPrevious(bool value) {
  if (value == m_canPrevious)
    return;
  m_canPrevious = value;
  notifyPlayer({QStringLiteral("CanGoPrevious")});
  emit changed();
}
void MprisServer::setCanSeek(bool value) {
  if (value == m_canSeek)
    return;
  m_canSeek = value;
  notifyPlayer({QStringLiteral("CanSeek")});
  emit changed();
}
void MprisServer::setVolume(double value) {
  if (!std::isfinite(value))
    return;
  value = qBound(0.0, value, 1.0);
  if (qFuzzyCompare(value + 1, m_volume + 1))
    return;
  m_volume = value;
  notifyPlayer({QStringLiteral("Volume")});
  emit changed();
}
