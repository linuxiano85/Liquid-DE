//@ pragma AppId minerva-posta
import QtQuick
import Quickshell
import "core" as Core
import "theme" as Theme
import "posta" as Mail

ShellRoot {
    id: app
    property bool started: false
    Theme.LegaTema {}
    Binding { target: Core.Strings; property: "requestedLanguage"; value: Core.Ipc.get("general.language", "auto") }
    Mail.Posta {
        id: window
        onRequestClose: Qt.quit()
    }
    function start() {
        if (started || !Core.Ipc.prontoADipingere) return;
        started = true;
        var target = String(Quickshell.env("MINERVA_POSTA_APRI") || "");
        if (target !== "") {
            try { window.apriMailto(target); }
            catch (error) { window.dice("Collegamento mailto non valido.", false); }
        }
    }
    Connections { target: Core.Ipc; function onProntoADipingereChanged() { app.start(); } }
    Component.onCompleted: { Quickshell.watchFiles = false; Qt.callLater(app.start); }
}
