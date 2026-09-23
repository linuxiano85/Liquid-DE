import QtQuick
import Quickshell
import "core" as Core
import "settings" as S

// Banco di analisi: solo processi innocui, nessuna azione di sistema.
ShellRoot {
    id: root
    property int fase: 0
    property int risposte: 0
    property var risultati: []
    property bool valoreEsterno: false
    Core.Exec {
        id: comando
        onDone: function(testo) {
            root.risposte++;
            root.risultati.push(testo);
        }
    }
    S.ToggleSwitch { id: interruttore; checked: root.valoreEsterno }
    Component.onCompleted: {
        interruttore.requestToggle();
        root.valoreEsterno = true;
        root.valoreEsterno = false;
        console.log("AUDIT toggle expected=false actual=" + interruttore.checked);
        comando.start(["/usr/bin/true"]);
    }
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            console.log("AUDIT exec fase=" + root.fase + " risposte=" + root.risposte
                        + " busy=" + comando.busy + " output=" + JSON.stringify(root.risultati));
            root.risposte = 0;
            root.risultati = [];
            root.fase++;
            if (root.fase === 1)
                comando.start(["/usr/bin/sh", "-c", "printf errore; exit 1"]);
            else if (root.fase === 2)
                comando.start(["/minerva-audit-eseguibile-inesistente"]);
            else
                Qt.quit();
        }
    }
}
