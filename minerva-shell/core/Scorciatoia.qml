import QtQuick

// Scorciatoia — Una combinazione di tasti registrata nel compositore.
//
// Esiste per un motivo solo: `GlobalShortcut` era un TIPO di
// `Quickshell.Hyprland`, e finché `shell.qml` lo dichiarava trentacinque
// volte, «cambiare compositore» voleva dire riscrivere anche lui. Con questo
// guscio l'unico file che nominava Hyprland è rimasto `core/Compositore.qml`,
// e questo qui accanto.
//
// **Dal 1 settembre 2026 non lo nomina più nessuno dei due.** Il guscio però
// resta, e non per pigrizia: le trentacinque dichiarazioni sparse per la shell
// non sanno né devono sapere chi porta loro il tasto, ed è quella indifferenza
// che ha reso lo scambio di compositore una sostituzione invece di una
// riscrittura. Il prossimo scambio — se ci sarà — passerà di qui.
//
// Si usa esattamente come prima — `name` e `onPressed` non cambiano nome
// apposta, così la conversione dei punti di chiamata è stata una sostituzione
// e non una riscrittura:
//
//     Core.Scorciatoia {
//         name: "appmenu"
//         onPressed: root.apriSottomarino()
//     }
//
// Il nome NON è la combinazione di tasti: è un'etichetta. Quali tasti la
// scatenino lo decide `config/scorciatoie.minerva`, che è anche il file da cui
// il demone costruisce il pannello F1 — vedi `minervad/lib/services/
// scorciatoie.dart`. Tenerli separati è ciò che permette di cambiare i tasti
// senza toccare il codice.
Item {
    id: scorciatoia

    /// L'etichetta con cui il compositore la conosce.
    property string name: ""

    /// A quale programma apparteneva, nella lingua di Hyprland.
    ///
    /// Non serve più a niente e resta dichiarata perché una trentina di punti
    /// di chiamata la scrivono: toglierla vorrebbe dire un errore QML in ognuno
    /// di quelli, per una proprietà che nessuno legge. Se ne va quando se ne va
    /// l'ultimo che la scrive, non prima.
    property string appid: "quickshell"

    signal pressed()
    signal released()

    // Non è roba da vedere: dichiarata dentro una colonna occuperebbe il
    // proprio posto in fila come qualunque altro elemento.
    visible: false

    // ── Una strada sola: il canale del compositore ───────────────────────
    //
    // I tasti li intercetta minerva-wayland, che di questa scorciatoia sa solo
    // il nome — `cheatsheet`, `launcher` — e lo annuncia sul canale. È lo
    // stesso nome che usava la strada di prima, ed è il motivo per cui questo
    // file è bastato a coprire due compositori senza che nessuno dei
    // trentacinque punti di chiamata se ne accorgesse.
    //
    // ── Che cosa se n'è andato con Hyprland, e cosa costava ──────────────
    //
    // Qui c'era un `Loader` che sotto Hyprland dichiarava un `GlobalShortcut`.
    // Non era gratis tenerlo: dentro minerva-wayland ogni `GlobalShortcut`
    // stampava due righe
    //
    //     The active compositor does not support hyprland_global_shortcuts_v1
    //     GlobalShortcut will not work
    //
    // e con trentasei scorciatoie erano settantadue righe a ogni avvio. Il
    // `Loader` le spegneva; toglierlo del tutto toglie anche il `Loader`.
    //
    // `released` non arriva: il compositore annuncia solo la pressione. Il
    // rilascio che serve — l'Alt che conferma l'Alt+Tab — è una scorciatoia
    // a sé, `Alt_L [al-rilascio] -> minerva: switchercommit`
    // (`config/scorciatoie.minerva`), che scatta quando Alt si alza.
    Connections {
        target: Compositore
        function onScorciatoiaPremuta(nome) {
            if (nome === scorciatoia.name)
                scorciatoia.pressed();
            // Il rilascio di un «tieni» arriva col suffisso `-via`.
            else if (nome === scorciatoia.name + "-via")
                scorciatoia.released();
        }
    }
}
