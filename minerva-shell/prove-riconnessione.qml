import QtQuick
import Quickshell
import "core" as Core

// ProveRiconnessione — che la shell TORNI, quando il demone se n'è andato.
//
//     scripts/prova-riconnessione.sh
//
// Non si lancia a mano: ha bisogno di un demone da uccidere e da rimettere in
// piedi, e quello lo orchestra lo script. Qui dentro c'è solo la parte che
// guarda.
//
// ── Il guasto che questa prova impedisce di rifare ────────────────────────
//
// 31 agosto 2026. Giacomo: «attualmente sia qui che nella sessione wlroot non
// ho la dock e nemmeno le voci nel menu delle applicazioni.»
//
// Il demone era morto per un istante e il guardiano l'aveva rimesso in piedi
// dopo un secondo. Ma la shell aveva fatto **un solo** tentativo, in quel
// secondo, e poi aveva spento il timer: `socket.connected` legge vero appena
// una connessione è stata CHIESTA, e il ramo `else` del timer si fermava lì.
//
// Da fuori non si vedeva un errore: si vedeva una scrivania senza dock e un
// menù applicazioni vuoto, con la shell viva che rispondeva ai tasti. Nel
// registro, una riga sola — `ServerNotFoundError` — e poi il silenzio, per
// ore, col demone vivo e in ascolto dall'altra parte.
//
// ── Perché si conta DUE volte e non una ───────────────────────────────────
//
// Perché una prova che verifica solo il primo aggancio sarebbe passata anche
// col difetto dentro: il primo aggancio funzionava benissimo. Quello che non
// funzionava era il **secondo**.
ShellRoot {
    id: banco

    /// Quante volte ci si è agganciati al demone davvero — cioè salutati.
    /// `Core.Ipc.connected` è già «salutato», non «socket aperto»: le due cose
    /// sono diverse ed è tutta la faccenda.
    property int agganci: 0
    property bool visto: false

    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (Core.Ipc.connected) {
                banco.agganci++;
                console.log("  ..   aggancio n." + banco.agganci);
                if (banco.agganci >= 2)
                    banco.finisci();
            } else if (banco.agganci > 0) {
                console.log("  ..   il demone se n'è andato, ora si aspetta il "
                            + "ritorno");
            }
        }
    }

    function finisci() {
        if (banco.visto)
            return;
        banco.visto = true;
        if (banco.agganci >= 2) {
            console.log("  ok   la shell è tornata da sola dopo la morte del "
                        + "demone");
            console.log("TUTTE PASSATE (1)");
        } else {
            console.log("  NO   la shell NON è tornata: agganci = "
                        + banco.agganci + " (ne servono 2)");
            console.log("FALLITE");
        }
        Qt.quit();
    }

    // Il tetto. Senza, una shell che non torna terrebbe lo script fermo invece
    // di dirgli che è andata male — e una prova che non finisce non è una
    // prova, è un blocco.
    Timer {
        interval: 25000
        running: true
        onTriggered: banco.finisci()
    }
}
