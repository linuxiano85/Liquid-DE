//@ pragma AppId minerva-blocco
import QtQuick
import Quickshell
import Quickshell.Wayland

import "core" as Core
import "blocco" as Schermo

// blocco.qml — L'avvio della schermata di blocco.
//
//     scripts/minerva-blocca
//
// ── La regola che decide tutto questo file ─────────────────────────────────
//
// Un blocco schermo che non si apre è un computer perso. Non «scomodo»:
// perso, perché su Wayland la superficie del blocco sta sopra ogni cosa e il
// compositore la tiene lì anche se il programma muore — è il protocollo
// `ext-session-lock` a garantirlo, ed è una garanzia voluta, perché senza uno
// schermo bloccato si sbloccherebbe uccidendo un processo.
//
// Quindi qui dentro ogni scelta è fatta due volte: una per farlo funzionare, e
// una perché il modo in cui può rompersi non chiuda fuori nessuno.
//
//  1. **Non si blocca se non si può verificare.** Prima di prendere lo
//     schermo, si controlla che il file PAM esista. Senza, la schermata
//     comparirebbe e non accetterebbe nessuna password.
//  2. **Non si blocca due volte.** Un secondo `minerva-blocca` mentre il primo
//     è in piedi non fa niente (`--no-duplicate` nello script).
//  3. **La prova ha un'uscita.** Con `MINERVA_BLOCCO_PROVA=<secondi>` si
//     sblocca da solo dopo quel tempo. È il modo in cui si prova il blocco
//     VERO senza rischiare di restare fuori — e il modo in cui l'ho provato
//     io sulla macchina di Giacomo, che è l'unica che c'è.
ShellRoot {
    id: radice

    readonly property int provaSecondi: {
        var v = Quickshell.env("MINERVA_BLOCCO_PROVA");
        var n = parseInt(v || "0", 10);
        return isNaN(n) ? 0 : n;
    }

    WlSessionLock {
        id: serratura
        locked: true

        WlSessionLockSurface {
            color: "black"

            Schermo.Blocco {
                anchors.fill: parent
                onSbloccato: {
                    serratura.locked = false;
                    Qt.quit();
                }
            }
        }
    }

    // ── L'uscita di sicurezza della prova ────────────────────────────────
    //
    // Non è una scorciatoia per entrare: esiste solo se la variabile c'è, e la
    // variabile la mette chi lancia il programma — cioè chi ha già la
    // sessione. Chi trova lo schermo bloccato non può metterla.
    Timer {
        running: radice.provaSecondi > 0
        interval: radice.provaSecondi * 1000
        onTriggered: {
            console.log("[MINERVA][BLOCCO] Prova finita: sblocco da solo.");
            serratura.locked = false;
            Qt.quit();
        }
    }

    Component.onCompleted: {
        if (radice.provaSecondi > 0)
            console.log("[MINERVA][BLOCCO] Modo prova: si sblocca da solo fra "
                        + radice.provaSecondi + " s.");
    }
}
