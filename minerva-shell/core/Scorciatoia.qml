import QtQuick

// Scorciatoia — Una combinazione di tasti registrata nel compositore.
//
// Le trentacinque dichiarazioni sparse per la shell non sanno né devono
// sapere chi porta loro il tasto: quando sotto c'era Hyprland era un suo
// `GlobalShortcut`, oggi è un annuncio sul canale di minerva-wayland, e il
// cambio è passato tutto di qui.
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

    signal pressed()
    signal released()

    // Non è roba da vedere: dichiarata dentro una colonna occuperebbe il
    // proprio posto in fila come qualunque altro elemento.
    visible: false

    // ── Il canale del compositore ────────────────────────────────────────
    //
    // I tasti li intercetta minerva-wayland, che di questa scorciatoia sa solo
    // il nome — `cheatsheet`, `launcher` — e lo annuncia sul canale.
    //
    // `released` arriva solo per le scorciatoie «tieni»: il compositore ne
    // annuncia il rilascio col suffisso `-via`. L'Alt che conferma l'Alt+Tab
    // invece è una scorciatoia a sé, `Alt_L [al-rilascio] -> minerva:
    // switchercommit` (`config/scorciatoie.minerva`), che scatta quando Alt
    // si alza.
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
