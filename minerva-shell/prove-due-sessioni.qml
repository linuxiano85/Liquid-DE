import QtQuick
import Quickshell
import "core" as Core

// ProveDueSessioni — Si connette al demone della PROPRIA sessione e lo dice.
//
//     MINERVA_SESSIONE=A qs -p minerva-shell/prove-due-sessioni.qml
//
// Non prova niente da sola: è la metà QML di un controllo che sta in
// `scripts/prove.sh`, dove si accendono due demoni con due nomi di sessione e
// si guarda che due shell trovino ognuna il suo. Il perché sta lì.
//
// Stampa una riga sola, `[DUE] <sessione> ok <porta>`, perché chi la legge è
// uno script.
ShellRoot {
    property int giri: 0

    Timer {
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            giri++;
            if (Core.Ipc.connected) {
                console.log("[DUE] " + Core.Ipc._sessione + " ok "
                            + Core.Ipc.porta);
                Qt.quit();
            } else if (giri > 25) {
                console.log("[DUE] " + Core.Ipc._sessione + " NO "
                            + Core.Ipc.porta);
                Qt.quit();
            }
        }
    }
}
