#include <iostream>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QUrl>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

// Quickshell non passa un argv utilizzabile al motore Chromium nel banco
// provato il 13 ottobre. Un host Qt esplicito conserva argc/argv reali.
int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 2;
    }
    const auto view = QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1]));
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(3); }, Qt::QueuedConnection);
    engine.load(view);
    const int result = app.exec();
    const bool loaded = !engine.rootObjects().isEmpty()
        && engine.rootObjects().first()->property("loadVerified").toBool();
    std::cout << "LIQUID_WEBENGINE_LOADED=" << loaded << std::endl;
    return loaded ? result : 6;
}
