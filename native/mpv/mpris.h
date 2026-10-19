#pragma once

// MPRIS for Minerva Media: how a Linux player tells the rest of the system
// what it is playing and accepts commands. The shell already listens
// (`minerva-shell/core/Media.qml`): media keys, the Centre, the bars. Media
// did not speak, so none of them saw it.
//
// The QML side owns the playlist and the player; this object only mirrors
// its state on the session bus and turns calls into signals.

#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QObject>
#include <QQmlParserStatus>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>

class MprisServer;

class MprisRootAdaptor : public QDBusAbstractAdaptor {
  Q_OBJECT
  Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
  Q_PROPERTY(bool CanQuit READ canQuit)
  Q_PROPERTY(bool CanRaise READ canRaise)
  Q_PROPERTY(bool HasTrackList READ hasTrackList)
  Q_PROPERTY(QString Identity READ identity)
  Q_PROPERTY(QString DesktopEntry READ desktopEntry)
  Q_PROPERTY(QStringList SupportedUriSchemes READ uriSchemes)
  Q_PROPERTY(QStringList SupportedMimeTypes READ mimeTypes)
  MprisServer *server() const;

public:
  explicit MprisRootAdaptor(MprisServer *parent);
  bool canQuit() const { return true; }
  bool canRaise() const { return true; }
  bool hasTrackList() const { return false; }
  QString identity() const;
  QString desktopEntry() const;
  QStringList uriSchemes() const { return {"file", "https", "http"}; }
  QStringList mimeTypes() const {
    return {"audio/mpeg", "audio/mp4", "audio/ogg", "audio/flac",
            "audio/x-wav", "video/mp4", "video/x-matroska", "video/webm"};
  }
public slots:
  void Raise();
  void Quit();
};

class MprisPlayerAdaptor : public QDBusAbstractAdaptor {
  Q_OBJECT
  Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
  Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
  Q_PROPERTY(double Rate READ rate WRITE setRate)
  Q_PROPERTY(double MinimumRate READ rate)
  Q_PROPERTY(double MaximumRate READ rate)
  Q_PROPERTY(QVariantMap Metadata READ metadata)
  Q_PROPERTY(double Volume READ volume WRITE setVolume)
  Q_PROPERTY(qlonglong Position READ position)
  Q_PROPERTY(bool CanGoNext READ canGoNext)
  Q_PROPERTY(bool CanGoPrevious READ canGoPrevious)
  Q_PROPERTY(bool CanPlay READ canPlay)
  Q_PROPERTY(bool CanPause READ canPause)
  Q_PROPERTY(bool CanSeek READ canSeek)
  Q_PROPERTY(bool CanControl READ canControl)
  MprisServer *server() const;

public:
  explicit MprisPlayerAdaptor(MprisServer *parent);
  QString playbackStatus() const;
  double rate() const { return 1.0; }
  void setRate(double) {}
  QVariantMap metadata() const;
  double volume() const;
  void setVolume(double value);
  qlonglong position() const;
  bool canGoNext() const;
  bool canGoPrevious() const;
  bool canPlay() const;
  bool canPause() const;
  bool canSeek() const;
  bool canControl() const { return true; }
public slots:
  void Next();
  void Previous();
  void Pause();
  void PlayPause();
  void Stop();
  void Play();
  void Seek(qlonglong offsetUs);
  void SetPosition(const QDBusObjectPath &track, qlonglong positionUs);
  void OpenUri(const QString &uri);
signals:
  void Seeked(qlonglong positionUs);
};

class MprisServer : public QObject, public QQmlParserStatus {
  Q_OBJECT
  Q_INTERFACES(QQmlParserStatus)
  Q_PROPERTY(bool active READ active WRITE setActive NOTIFY changed)
  Q_PROPERTY(QString identity MEMBER m_identity NOTIFY changed)
  Q_PROPERTY(QString desktopEntry MEMBER m_desktopEntry NOTIFY changed)
  Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY changed)
  Q_PROPERTY(QString artist READ artist WRITE setArtist NOTIFY changed)
  Q_PROPERTY(QUrl artUrl READ artUrl WRITE setArtUrl NOTIFY changed)
  Q_PROPERTY(qint64 length READ length WRITE setLength NOTIFY changed)
  Q_PROPERTY(qint64 position READ position WRITE setPosition NOTIFY changed)
  Q_PROPERTY(bool playing READ playing WRITE setPlaying NOTIFY changed)
  Q_PROPERTY(bool hasMedia READ hasMedia WRITE setHasMedia NOTIFY changed)
  Q_PROPERTY(bool canGoNext READ canGoNext WRITE setCanGoNext NOTIFY changed)
  Q_PROPERTY(bool canGoPrevious READ canGoPrevious WRITE setCanGoPrevious
                 NOTIFY changed)
  Q_PROPERTY(bool canSeek READ canSeek WRITE setCanSeek NOTIFY changed)
  Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY changed)
  Q_PROPERTY(QString busName READ busName NOTIFY changed)

public:
  explicit MprisServer(QObject *parent = nullptr);
  ~MprisServer() override;
  void classBegin() override {}
  void componentComplete() override;

  bool active() const { return m_active; }
  void setActive(bool value);
  QString identityText() const { return m_identity; }
  QString desktopEntryText() const { return m_desktopEntry; }
  QString title() const { return m_title; }
  void setTitle(const QString &value);
  QString artist() const { return m_artist; }
  void setArtist(const QString &value);
  QUrl artUrl() const { return m_artUrl; }
  void setArtUrl(const QUrl &value);
  qint64 length() const { return m_length; }
  void setLength(qint64 value);
  qint64 position() const { return m_position; }
  void setPosition(qint64 value);
  bool playing() const { return m_playing; }
  void setPlaying(bool value);
  bool hasMedia() const { return m_hasMedia; }
  void setHasMedia(bool value);
  bool canGoNext() const { return m_canNext; }
  void setCanGoNext(bool value);
  bool canGoPrevious() const { return m_canPrevious; }
  void setCanGoPrevious(bool value);
  bool canSeek() const { return m_canSeek; }
  void setCanSeek(bool value);
  double volume() const { return m_volume; }
  void setVolume(double value);
  QString busName() const { return m_busName; }

  QVariantMap metadata() const;
  /// Tells listeners that the position jumped (not for normal playback).
  Q_INVOKABLE void seeked(qint64 positionMs);

signals:
  void changed();
  void raiseRequested();
  void quitRequested();
  void playRequested();
  void pauseRequested();
  void playPauseRequested();
  void stopRequested();
  void nextRequested();
  void previousRequested();
  void seekRequested(qint64 offsetMs);
  void positionRequested(qint64 positionMs);
  void volumeRequested(double volume);
  void openRequested(const QString &uri);

private:
  void publish();
  void withdraw();
  void notify(const char *interface, const QVariantMap &values);
  void notifyPlayer(const QStringList &names);

  MprisPlayerAdaptor *m_player = nullptr;
  bool m_active = true, m_complete = false, m_registered = false;
  QString m_identity = QStringLiteral("Minerva Media");
  QString m_desktopEntry = QStringLiteral("minerva-media");
  QString m_title, m_artist, m_busName;
  QUrl m_artUrl;
  qint64 m_length = 0, m_position = 0;
  bool m_playing = false, m_hasMedia = false, m_canNext = false,
       m_canPrevious = false, m_canSeek = false;
  double m_volume = 1.0;
  unsigned m_track = 0;
};
