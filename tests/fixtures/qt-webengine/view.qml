import QtQuick
import QtQuick.Window
import QtWebEngine

Window {
    id: window
    property bool loadVerified: false
    width: 360
    height: 240
    visible: true
    title: "Prova locale Qt WebEngine"
    WebEngineView {
        id: browser
        anchors.fill: parent
        settings.javascriptEnabled: false
        settings.localContentCanAccessRemoteUrls: false
        settings.localContentCanAccessFileUrls: false
        Component.onCompleted: loadHtml("<html><body><h1>Liquid WebEngine</h1><p>Contenuto locale di prova.</p></body></html>")
        onLoadingChanged: function(request) {
            if (request.status === WebEngineView.LoadSucceededStatus) {
                window.loadVerified = true;
                console.log("LIQUID_WEBENGINE_OK");
                Qt.quit();
            } else if (request.status === WebEngineView.LoadFailedStatus) {
                console.error("LIQUID_WEBENGINE_FAILED", request.errorCode);
                Qt.exit(4);
            }
        }
    }
    Timer {
        interval: 10000
        running: true
        onTriggered: Qt.exit(5)
    }
}
