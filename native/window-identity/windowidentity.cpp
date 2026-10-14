#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QPointer>
#include <QQmlExtensionPlugin>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTimer>
#include <QtWaylandClient/private/qwaylandwindow_p.h>
#include <qpa/qplatformnativeinterface.h>
#include <wayland-client-core.h>

// wl_surface IDs identify windows within their Wayland connection. Unlike
// titles or process IDs, two FileManager windows cannot share this identity.
class WindowIdentity : public QObject {
    Q_OBJECT
    Q_PROPERTY(QQuickItem *item READ item WRITE setItem NOTIFY itemChanged)
    Q_PROPERTY(quint32 surfaceId READ surfaceId NOTIFY surfaceIdChanged)
    Q_PROPERTY(QString activationToken READ activationToken WRITE setActivationToken NOTIFY activationTokenChanged)
    QPointer<QQuickItem> m_item;
    QPointer<QQuickWindow> m_window;
    quint32 m_surfaceId = 0;
    QString m_activationToken;
    void activatePending() {
        if (m_activationToken.isEmpty() || !m_window || !m_window->isVisible()) return;
        if (QGuiApplication::platformName().startsWith("wayland")) {
            if (!m_surfaceId || !m_window->handle()) return;
            auto *window = static_cast<QtWaylandClient::QWaylandWindow *>(m_window->handle());
            if (!window->shellSurface()) return;
            window->setXdgActivationToken(m_activationToken);
        }
        // Qt consumes the token for this surface, not for another window
        // in the same process. Never mutate the process-wide environment.
        m_window->requestActivate();
        m_activationToken.clear(); emit activationTokenChanged();
    }
    void publish(quint32 id) {
        if (id == m_surfaceId) return;
        m_surfaceId = id;
        emit surfaceIdChanged();
    }
    void update() {
        quint32 id = 0;
        if (m_window && QGuiApplication::platformName().startsWith("wayland")) {
            auto *iface = QGuiApplication::platformNativeInterface();
            auto *surface = static_cast<wl_proxy *>(iface->nativeResourceForWindow("surface", m_window));
            if (surface) id = wl_proxy_get_id(surface);
        }
        publish(id);
        activatePending();
    }
    void attach() {
        if (m_window) { m_window->removeEventFilter(this); disconnect(m_window, nullptr, this, nullptr); }
        m_window = m_item ? m_item->window() : nullptr;
        if (m_window) {
            m_window->installEventFilter(this);
            connect(m_window, &QWindow::visibleChanged, this, [this] { update(); });
            connect(m_window, &QObject::destroyed, this, [this] { publish(0); });
        }
        update();
    }
    bool eventFilter(QObject *object, QEvent *event) override {
        if (object == m_window && event->type() == QEvent::PlatformSurface) {
            auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
            if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) publish(0);
            else QTimer::singleShot(0, this, [this] { update(); });
        }
        return QObject::eventFilter(object, event);
    }
public:
    explicit WindowIdentity(QObject *parent = nullptr) : QObject(parent) {}
    QQuickItem *item() const { return m_item; }
    quint32 surfaceId() const { return m_surfaceId; }
    QString activationToken() const { return m_activationToken; }
    void setActivationToken(const QString &token) {
        static const QRegularExpression valid(QStringLiteral("^[A-Za-z0-9_-]{1,256}$"));
        if (!token.isEmpty() && !valid.match(token).hasMatch()) return;
        if (m_activationToken == token) return;
        m_activationToken = token; emit activationTokenChanged(); update();
    }
    void setItem(QQuickItem *item) {
        if (m_item == item) return;
        if (m_item) disconnect(m_item, nullptr, this, nullptr);
        m_item = item;
        if (item) {
            connect(item, &QQuickItem::windowChanged, this, [this] { attach(); });
            connect(item, &QObject::destroyed, this, [this] { attach(); });
        }
        attach(); emit itemChanged();
    }
signals:
    void itemChanged();
    void surfaceIdChanged();
    void activationTokenChanged();
};

class IdentityPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<WindowIdentity>(uri, 1, 0, "WindowIdentity"); }
};
#include "windowidentity.moc"
