pragma Singleton
import QtQuick

// Overlays — Coordinatore dei pannelli che si aprono sopra alla scrivania.
//
// Menu applicazioni, Wi-Fi, appunti, spegnimento e pannelli a schermo intero
// sono finestre layer-shell indipendenti: nessuna sa dell'esistenza delle
// altre, e senza un arbitro si accumulano una sopra l'altra.
//
// Uso, da ciascun pannello:
//
//     onOpened:  Core.Overlays.claim("wifi")
//     Connections {
//         target: Core.Overlays
//         function onDismissOthers(keep) { if (keep !== "wifi") close(); }
//     }
QtObject {
    id: overlays

    /// Nome del pannello attualmente in primo piano ("" se nessuno).
    property string current: ""

    /// Chiede a tutti i pannelli tranne `keep` di chiudersi.
    signal dismissOthers(string keep)

    /// Un pannello dichiara di essere stato aperto e fa chiudere gli altri.
    function claim(name) {
        overlays.current = name;
        overlays.dismissOthers(name);
    }

    /// Un pannello dichiara di essersi chiuso.
    function release(name) {
        if (overlays.current === name)
            overlays.current = "";
    }

}
