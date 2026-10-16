//@ pragma AppId minerva-documenti
import QtQuick
import Quickshell
import "core" as Core
import "theme" as Theme
import "printing" as Print

ShellRoot {
    id:app
    property bool started:false
    property bool closing:false
    Component.onCompleted:{Quickshell.watchFiles=false;Qt.callLater(app.start);}
    Theme.LegaTema {}
    Binding {target:Core.Strings;property:"requestedLanguage";value:Core.Ipc.get("general.language","auto")}
    function start() {
        if(started || !Core.Ipc.prontoADipingere)return;
        started=true;
        documents.openUtility(Quickshell.env("MINERVA_DOCUMENT_PATH") || "");
    }
    Connections {target:Core.Ipc;function onProntoADipingereChanged(){app.start();}}
    Print.PrintDialog {
        id:documents
        standalone:true
        onDismissed:app.closing=true
    }
    Timer {
        interval:100;repeat:true;running:app.closing
        onTriggered:if(!documents.backgroundBusy)Qt.quit()
    }
}
