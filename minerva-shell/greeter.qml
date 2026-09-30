import QtQuick
import Quickshell
import Quickshell.Wayland

import "core" as Core
import "greeter" as Accesso

// greeter.qml — L'avvio della schermata di accesso.
//
// ── Due finestre diverse, e perché ─────────────────────────────────────────
//
// Dentro un greeter (`GREETD_SOCK` esiste) questa è l'UNICA cosa a schermo:
// un livello a schermo intero che si prende la tastiera, perché non c'è
// nient'altro con cui interagire e non deve esserci modo di andarci sotto.
//
// In una sessione normale è una finestra come le altre. Non è una comodità:
// è una regola di sicurezza. Un livello a schermo intero che si prende la
// tastiera, aperto per sbaglio nella sessione di chi sta lavorando, è
// indistinguibile da un blocco schermo che non si sblocca. Una schermata di
// accesso va provata da spenta prima che da accesa, e provarla non deve poter
// rendere il computer inutilizzabile — la stessa regola della sospensione e
// del wifi.
ShellRoot {
    id: radice

    // ── La lingua scelta, anche qui ──────────────────────────────────────
    //
    // La scrivania, le Impostazioni e ogni app legano `requestedLanguage` a
    // `general.language`; la schermata di accesso no, e seguiva la lingua DI
    // SISTEMA. Con Minerva in inglese su un sistema italiano restava in
    // italiano, unico pezzo della scrivania a farlo (30 settembre 2026).
    // Sono processi diversi e non si leggono le proprietà a vicenda: la riga
    // va ripetuta qui.
    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }

    // La schermata di accesso È una scrivania: la disposizione della tastiera
    // qui conta più che altrove, perché è il posto dove si scrive una password
    // che non si vede. Una tastiera americana al login vuol dire una password
    // che «non funziona» senza nessun errore da leggere.
    Component.onCompleted: Core.Compositore.scrivania = true

    // `Quickshell.env` restituisce `null` quando la variabile non c'è.
    readonly property bool dentroUnGreeter: {
        var s = Quickshell.env("GREETD_SOCK");
        return s !== null && s !== undefined && String(s) !== "" && String(s) !== "null";
    }

    // ── La schermata vera ────────────────────────────────────────────────

    LazyLoader {
        active: radice.dentroUnGreeter

        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }

            WlrLayershell.namespace: "minerva-greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore

            color: "black"

            Accesso.Greeter {
                anchors.fill: parent
                finto: false

                // La sessione parte QUANDO IL GREETER FINISCE: chiudere non è
                // un effetto collaterale dell'accesso riuscito, è il gesto che
                // lo completa.
                onFinito: Qt.quit()
            }
        }
    }

    // ── L'anteprima ──────────────────────────────────────────────────────

    LazyLoader {
        active: !radice.dentroUnGreeter

        FloatingWindow {
            // Non ci si mostra col tema di fabbrica: i colori arrivano dal
            // demone e vincono la corsa per pochi millisecondi. Vedi
            // `core/Ipc.qml`.
            visible: Core.Ipc.prontoADipingere

            title: "Minerva · " + (Core.Strings.lang === "it"
                                   ? "Accesso (anteprima)" : "Login (preview)")

            // Le proporzioni dello schermo, in piccolo: una schermata di
            // accesso guardata dentro una finestra quadrata mente su come
            // starà davvero.
            implicitWidth: 1152
            implicitHeight: 648
            color: "black"

            Accesso.Greeter {
                anchors.fill: parent
                finto: true
            }

            // ── Da qui si esce con Esc ───────────────────────────────────
            //
            // Giacomo, 6 settembre 2026: «perché non riesco a chiudere
            // anteprima cliccando su esc o altri modi?».
            //
            // Perché non c'era nessun modo, ed è colpa di come è fatta: la
            // schermata di accesso vera non ha una barra del titolo — non si
            // chiude, si entra — e l'anteprima la mostra tale e quale,
            // ereditando anche il non avere una via d'uscita. Una finestra
            // senza uscita è un difetto, non una fedeltà.
            //
            // Esc e non un pulsante: un pulsante in mezzo alla schermata
            // sarebbe proprio la cosa che l'anteprima non deve mostrare. Nel
            // greeter VERO questa riga non esiste, perché quel ramo è acceso
            // solo quando `dentroUnGreeter` è falso.
            Shortcut {
                sequences: ["Esc", "Ctrl+W"]
                onActivated: Qt.quit()
            }
        }
    }
}
