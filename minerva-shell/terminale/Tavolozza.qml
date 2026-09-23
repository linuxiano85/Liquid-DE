import QtQuick
import "../theme" as Theme

// Tavolozza — I colori del terminale: i sedici di ANSI, i 256, il vero.
//
// ── Derivata dal tema, non copiata da un altro terminale ───────────────────
//
// Un terminale porta la sua tavolozza come una giacca di un altro colore: il
// blu di Alacritty dentro Minerva «Ametista» è un blu che non c'entra
// niente. Qui i sedici colori nascono dal tema: il blu e il ciano
// dall'accento, il verde/giallo/rosso da `positive`/`warning`/`danger` — gli
// stessi delle barre dei widget e degli esiti — e i grigi dal fondo.
//
// Resta LEGGIBILE, che viene prima della coerenza: i colori normali (0–7)
// sono un po' meno saturi di quelli brillanti (8–15), e su un tema chiaro
// il «bianco» è scuro e il «nero» è chiaro, come deve essere.
//
// Chi vuole altro sceglie una tavolozza con nome (`terminale.tavolozza`), e
// «Minerva» è quella di serie.
QtObject {
    id: tav

    /// `minerva` segue il tema; le altre sono fisse.
    property string nome: "minerva"

    readonly property bool scura: Theme.Colors.scura

    /// I sedici: 0–7 normali, 8–15 brillanti.
    readonly property var sedici: {
        if (tav.nome === "solarizzata")
            return ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                    "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"];
        if (tav.nome === "classica")
            return ["#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
                    "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff"];
        // «minerva»: dal tema.
        var acc = Theme.Colors.accent;
        var alt = Theme.Colors.accentAlt;
        var s = tav.scura;
        function mix(c, verso, q) { return Qt.tint(c, Qt.alpha(verso, q)); }
        var nero    = s ? Qt.lighter(Theme.Colors.base, 1.6) : "#2A2E37";
        var bianco  = s ? "#D9DEE8" : "#3C4250";
        var neroB   = s ? Qt.lighter(Theme.Colors.base, 3.2) : "#6B7280";
        var biancoB = s ? "#F4F6FA" : "#11141B";
        var rosso   = Theme.Colors.danger;
        var verde   = Theme.Colors.positive;
        var giallo  = Theme.Colors.warning;
        var blu     = acc;
        var magenta = alt;
        var ciano   = mix(acc, verde, 0.35);
        return [
            nero,
            mix(rosso, nero, s ? 0.25 : 0.15),
            mix(verde, nero, s ? 0.25 : 0.15),
            mix(giallo, nero, s ? 0.25 : 0.15),
            mix(blu, nero, s ? 0.25 : 0.15),
            mix(magenta, nero, s ? 0.25 : 0.15),
            mix(ciano, nero, s ? 0.25 : 0.15),
            bianco,
            neroB, rosso, verde, giallo, blu, magenta, ciano, biancoB
        ];
    }

    /// Il colore del testo e del fondo «di serie» (SGR 39/49).
    readonly property color testo: Theme.Colors.text
    readonly property color fondo: "transparent"

    /// Da un intero dell'emulatore a un colore. Le celle passano per QUI e
    /// per nessun altro posto: `0` è il tema, `0x01…` uno dei 256, `0x02…`
    /// 24 bit. Il cubo 6×6×6 e la scala di grigi si calcolano, come xterm.
    function colore(v, diSerie) {
        if (v === 0)
            return diSerie;
        var tipo = v >> 24;
        var val = v & 0xffffff;
        if (tipo === 2)
            return Qt.rgba(((val >> 16) & 0xff) / 255, ((val >> 8) & 0xff) / 255, (val & 0xff) / 255, 1);
        var i = val & 0xff;
        if (i < 16)
            return tav.sedici[i];
        if (i >= 232) {
            var g = (8 + (i - 232) * 10) / 255;
            return Qt.rgba(g, g, g, 1);
        }
        var k = i - 16;
        var r = Math.floor(k / 36), gg = Math.floor((k % 36) / 6), b = k % 6;
        function q(n) { return n === 0 ? 0 : (55 + n * 40) / 255; }
        return Qt.rgba(q(r), q(gg), q(b), 1);
    }
}
