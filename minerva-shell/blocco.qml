//@ pragma AppId minerva-blocco
import QtQuick
import Quickshell
import Quickshell.Wayland

import "core" as Core
import "theme" as Theme
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

    // ── La lingua scelta, anche qui ──────────────────────────────────────
    //
    // La scrivania, le Impostazioni e ogni app legano `requestedLanguage` a
    // `general.language`; la schermata di blocco no, e seguiva la lingua DI
    // SISTEMA. Con Minerva in inglese su un sistema italiano «Password
    // sbagliata» e il resto restavano in italiano, unico pezzo della
    // scrivania a farlo (30 settembre 2026). Sono processi diversi e non si
    // leggono le proprietà a vicenda: la riga va ripetuta qui.
    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }

    readonly property int provaSecondi: {
        var v = Quickshell.env("MINERVA_BLOCCO_PROVA");
        var n = parseInt(v || "0", 10);
        return isNaN(n) ? 0 : n;
    }

    // ── La marea ─────────────────────────────────────────────────────────
    //
    // La Riva: «il blocco che sale come una marea». Bloccando, l'aurora e
    // l'ora salgono dal fondo dietro una cresta di luce; sbloccando l'acqua
    // si ritira verso il basso, e solo allora torna la scrivania. Il blocco
    // vero è lo stesso di sempre: cambiano l'ingresso e l'uscita.
    //
    // ── L'uscita non aspetta l'animazione ────────────────────────────────
    //
    // Sbloccare dipende da un TIMER, non dalla fine dell'animazione: un
    // Timer scatta anche se nessuno disegna fotogrammi, un'animazione no. Un
    // blocco che non si apre perché un'animazione si è fermata sarebbe un
    // computer perso (la regola in cima a questo file).
    readonly property bool liquido: Theme.Motion.liquido
    property real livello: radice.liquido ? 0 : 1
    Behavior on livello {
        enabled: radice.liquido
        NumberAnimation {
            duration: radice.livello > 0.5 ? 380 : 720
            easing.type: radice.livello > 0.5 ? Easing.InCubic : Easing.OutCubic
        }
    }

    function esci() {
        radice.livello = 0;
        uscita.start();
    }
    Timer {
        id: uscita
        interval: radice.liquido ? 400 : 0
        onTriggered: {
            serratura.locked = false;
            Qt.quit();
        }
    }

    // Le password sbagliate si contano UNA volta per tutto il blocco, non una
    // per schermo: vedi `blocco/Tentativi.qml`.
    Schermo.Tentativi { id: tentativiComuni }

    WlSessionLock {
        id: serratura
        locked: true

        WlSessionLockSurface {
            id: superficie
            color: "black"

            Connections {
                target: marea.Window.window
                ignoreUnknownSignals: true
                function onFrameSwapped() { radice.parti(); }
            }

            Item {
                id: marea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: superficie.height * radice.livello
                clip: true

                Schermo.Blocco {
                    tentativi: tentativiComuni
                    width: superficie.width
                    height: superficie.height
                    anchors.bottom: parent.bottom
                    onSbloccato: radice.esci()
                }

                // La cresta: una riga di luce sul bordo dell'acqua, che si
                // vede solo mentre sale o scende.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 3
                    visible: radice.livello > 0.001 && radice.livello < 0.999
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.55) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
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
            radice.esci();
        }
    }

    // ── La marea parte dal primo fotogramma VISTO ────────────────────────
    //
    // Partendo in `Component.onCompleted` saliva prima che la superficie
    // fosse sullo schermo: si vedeva solo l'ultimo quinto della salita
    // (misurato il 24 settembre 2026, fotogramma per fotogramma). Parte
    // quando la finestra ha mostrato il primo fotogramma; e comunque entro
    // un secondo, perché un blocco con la password invisibile non si usa.
    property bool partita: false
    function parti() {
        if (radice.partita) return;
        radice.partita = true;
        radice.livello = 1;
    }
    Timer { running: !radice.partita; interval: 1000; onTriggered: radice.parti() }

    Component.onCompleted: {
        if (radice.provaSecondi > 0)
            console.log("[MINERVA][BLOCCO] Modo prova: si sblocca da solo fra "
                        + radice.provaSecondi + " s.");
    }
}
