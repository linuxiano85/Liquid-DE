import QtQuick
import Quickshell
import "terminale" as T

ShellRoot {
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 600; visible: true
        T.Blocchi { id: blocchi; width: 330; height: 580 }
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            for (var i = 1; i <= 250; i++) {
                blocchi.aggiorna({id: i, comando: "printf '<test>'", cartella: "/tmp",
                    stato: "corsa", codice: -1, durata: 0, uscita: "", troncato: false, interattivo: false});
                blocchi.aggiorna({id: i, comando: "printf '<test>'", cartella: "/tmp",
                    stato: "finito", codice: i % 2, durata: 12, uscita: "<test>", troncato: false, interattivo: false});
            }
            if (blocchi.blocchi.length !== 100 || blocchi.blocchi[0].id !== 250
                || blocchi.blocchi[0].stato !== "finito") throw new Error("registro non limitato o non aggiornato");
            fine.start();
        }
    }
    Timer {
        id: fine; interval: 500
        onTriggered: { console.log("BLOCCHI QML OK: 250 comandi, 100 conservati"); Qt.quit(); }
    }
}
