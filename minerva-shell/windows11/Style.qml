pragma Singleton
import QtQuick
import "../core" as Core
import "ColorMath.js" as ColorMath
import "Gettoni.js" as Gettoni

// I colori del preset Windows, dai gettoni di Windows 11 (`Gettoni.js`).
//
// Fino all'11 ottobre 2026 erano scelti a occhio: il fondo chiaro era un
// azzurrino (#e7edfa) che Windows non ha, e un accento manuale si scuriva a
// tentativi. il manutentore: «cerca l'esatta combinazione che si adatti a tutte le
// combinazioni di colori di Windows, anche per il colore manuale».
//
// Due famiglie di colori, e non vanno confuse:
//   - i colori PIENI (`text`, `surface`, `field`, `taskbarSurface`…) servono
//     ai conti di leggibilità: un gettone trasparente da solo non ha un
//     contrasto, ce l'ha steso sopra qualcosa (`ColorMath.over`);
//   - i colori TRASPARENTI (`card`, `hover`, `pressed`, `cardStroke`) si
//     dipingono così come sono sopra il materiale, ed è la loro trasparenza a
//     far vedere il vetro sotto le schede, come in Windows.
QtObject {
    id: style

    /// Vero nei processi delle app (Impostazioni, gestore file): seguono la
    /// modalità delle app (`windows11.themeApp`, «Personalizzata» in
    /// Colori) invece di quella di Windows (barra, Start, pannelli).
    property bool perApp: false
    readonly property string temaApp: Core.Ipc.get("windows11.themeApp", "")
    readonly property bool dark: style.perApp && (style.temaApp === "light" || style.temaApp === "dark")
        ? style.temaApp === "dark"
        : Core.Ipc.get("windows11.theme", "light") === "dark"
    readonly property bool it: Core.Strings.lang === "it"
    readonly property var gettoni: Gettoni.tema(style.dark)
    readonly property var ricette: style.dark ? Gettoni.acrylic.scuro : Gettoni.acrylic.chiaro

    // ── L'accento e le sue sei sfumature ─────────────────────────────────
    //
    // «auto» è l'azzurro di serie di Windows 11. Le sfumature le fa
    // `ColorMath.palette`, uguale per l'accento di serie e per uno manuale.
    readonly property string requestedAccent: Core.Ipc.get("windows11.accent", "auto")
    readonly property string accentBase: /^#[0-9a-f]{6}$/i.test(style.requestedAccent)
        ? style.requestedAccent : Gettoni.azzurroDiSerie.accento
    // Per l'azzurro di serie le sfumature vere di Windows (dal registro);
    // per ogni altro colore il generatore tarato su di esse.
    readonly property var palette: style.accentBase.toLowerCase() === Gettoni.azzurroDiSerie.accento.toLowerCase()
        ? Gettoni.azzurroDiSerie : ColorMath.palette(style.accentBase)

    // ── I materiali, pieni ───────────────────────────────────────────────
    //
    // `surface` è il colore di ripiego dell'Acrylic dei flyout (menu, Start,
    // calendario, impostazioni rapide); `base` è lo sfondo delle finestre
    // (SolidBackgroundFillColorBase, il Mica pieno).
    readonly property color surface: style.ricette["default"].ripiego
    readonly property color base: style.gettoni.solidBase.replace(/^#FF/, "#")

    // ── Testo ────────────────────────────────────────────────────────────
    readonly property color text: ColorMath.over(style.gettoni.textPrimary, style.surface)
    readonly property color muted: ColorMath.over(style.gettoni.textSecondary, style.surface)
    readonly property color faint: ColorMath.over(style.gettoni.textTertiary, style.surface)

    // ── Controlli, schede, bordi ─────────────────────────────────────────
    readonly property color field: ColorMath.over(style.gettoni.controlFill, style.surface)
    readonly property color edge: ColorMath.over(style.gettoni.surfaceStroke, style.surface)
    readonly property color divider: style.gettoni.dividerStroke
    readonly property color card: style.gettoni.cardBackground
    readonly property color cardStroke: style.gettoni.cardStroke
    readonly property color hover: style.gettoni.subtleSecondary
    readonly property color pressed: style.gettoni.subtleTertiary

    // ── Colori di stato (batteria, errori) ───────────────────────────────
    readonly property color critical: style.gettoni.critical.replace(/^#FF/, "#")
    readonly property color success: style.gettoni.success.replace(/^#FF/, "#")
    readonly property color caution: style.gettoni.caution.replace(/^#FF/, "#")

    // ── L'accento usato come Windows ─────────────────────────────────────
    //
    // Riempimenti (pulsanti, interruttori, cursori, la selezione): Light2 in
    // scuro, Dark1 in chiaro. Testo d'accento: Light3 in scuro, Dark2 in
    // chiaro. Testo sopra l'accento: nero in scuro, bianco in chiaro, salvo
    // che un colore manuale non lo renda illeggibile.
    readonly property color accent: style.dark ? style.palette.light2 : style.palette.dark1
    readonly property color accentText: style.dark ? style.palette.light3 : style.palette.dark2
    // Avoid an "onAccent" property: its notify signal onAccentChanged collides
    // with Qt's handler for accentChanged and prevents the binding updating.
    readonly property color accentForeground: {
        var voluto = style.gettoni.textOnAccent.replace(/^#FF/, "#");
        return ColorMath.contrast(voluto, style.accent) >= 4.5 ? voluto : ColorMath.foreground(style.accent);
    }
    readonly property color accentInk: ColorMath.readable(style.accentText, style.field, 4.5)

    // ── Accento su Start e barra ─────────────────────────────────────────
    //
    // Come Windows, solo nel tema scuro. Start e flyout prendono la tinta
    // Dark1, la barra Dark2 (AccentAcrylicBackgroundFillColorDefault/Base).
    // Con un accento chiaro (un giallo) Dark1 è troppo chiaro per il testo
    // bianco: si scende alla sfumatura dopo finché il testo si legge.
    readonly property bool accentOnStart: style.dark && Core.Ipc.get("windows11.accentOnStart", false)

    readonly property color startSurface: style.accentOnStart
        ? Gettoni.sfumaturaLeggibile(style.palette, ["dark1", "dark2", "dark3"]) : style.surface
    readonly property color startFooter: ColorMath.over(style.dark ? "#29000000" : "#0B000000", style.startSurface)
    readonly property color startMuted: ColorMath.readable(style.muted, style.startSurface, 4.5)
    readonly property color taskbarSurface: style.accentOnStart
        ? Gettoni.sfumaturaLeggibile(style.palette, ["dark2", "dark3"]) : style.ricette["base"].ripiego
    readonly property color accentIndicator: ColorMath.readable(style.accent, style.taskbarSurface, 3)

    // ── Testo e meteo sulla barra ──
    //
    // Sulla barra colorata con l'accento il simbolo del meteo, che era del
    // colore d'accento, spariva nel fondo (il manutentore, 11 ottobre 2026). Ora
    // ogni tempo ha il suo colore, come in Windows, e tutti passano da
    // `readable` contro il colore vero della barra.
    readonly property color barraTesto: ColorMath.readable(style.dark ? "#ffffff" : style.text, style.taskbarSurface, 4.5)
    readonly property color barraTenue: ColorMath.readable(style.muted, style.taskbarSurface, 4.5)
    function coloreMeteo(codice, giorno, sfondo) {
        var c;
        if (codice === 0 || codice === 1)
            c = giorno === false ? (style.dark ? "#c9d6ff" : "#5b6fb3") : "#f2b01e";
        else if (codice >= 95)
            c = "#f5c400";
        else if ((codice >= 71 && codice <= 77) || codice === 85 || codice === 86)
            c = style.dark ? "#bfe3ff" : "#4b8fd1";
        else if ((codice >= 51 && codice <= 67) || (codice >= 80 && codice <= 82))
            c = style.dark ? "#6cb8ff" : "#2a7fd4";
        else
            c = style.dark ? "#c3ccd6" : "#6b7785";
        return ColorMath.readable(c, sfondo === undefined ? style.taskbarSurface : sfondo, 3);
    }

    // ── Barra e pannelli: il vetro ──
    //
    // `barra` e `pannello` sono i colori da DIPINGERE sopra quello che il
    // compositore stende sfocato dietro (verbo «vetrobarra»). La ricetta di
    // Windows è: sfondo sfocato, poi la LUMINOSITÀ portata a quella della
    // tinta con l'opacità di luminosità (0,96 in scuro, 0,85 in chiaro), poi
    // la tinta. Finché il compositore non fa la fusione di luminosità, qui si
    // stende la tinta con quell'opacità: si vede lo stesso «leggermente in
    // blur» delle schede di Windows.
    readonly property bool acrylic: Core.Ipc.get("windows11.acrylic", true) === true
        && Core.Compositore.vetroBarra && !Core.Vetro.inRisparmio
    /// Il compositore stende la ricetta Acrylic intera (luminosità, tinta,
    /// rumore: `Gettoni.ricettaVetro`). Allora i pannelli NON si dipingono:
    /// il materiale è già il colore giusto, e sopra vanno solo le schede.
    /// Un compositore che sa solo sfocare risponde «ok si» senza «acrylic»,
    /// e qui si stende la tinta con l'opacità di luminosità, il ripiego più
    /// vicino che si può fare senza vedere lo sfondo.
    readonly property bool acrylicVero: style.acrylic && Core.Compositore.vetroAcrylic
    function _vetro(pieno, ricetta) {
        // Non zero: il compositore stende il vetro dove la superficie ha
        // almeno un quarto di alfa (`minerva_dove` in minerva_blur.frag).
        // Un quarto del colore di ripiego sopra un vetro che è già quel
        // colore non si vede, e tiene acceso il vetro sotto tutto il pannello.
        if (style.acrylicVero)
            return Qt.alpha(pieno, 0.25);
        return style.acrylic ? Qt.alpha(pieno, ricetta.luminosita) : pieno;
    }
    // La striscia della barra è il materiale «base», più scuro dei flyout:
    // col vetro vero se ne stende metà sopra la ricetta dei flyout.
    readonly property color barra: style.acrylicVero
        ? Qt.alpha(style.taskbarSurface, 0.5)
        : style._vetro(style.taskbarSurface,
                       style.accentOnStart ? style.ricette["accentoBase"] : style.ricette["base"])
    readonly property color pannello: style._vetro(style.startSurface,
        style.accentOnStart ? style.ricette["accentoDefault"] : style.ricette["default"])
    readonly property color widgetsSurface: style.pannello
    readonly property color pannelloPiede: style.acrylicVero
        ? Qt.alpha(style.startFooter, 0.5)
        : style._vetro(style.startFooter,
                       style.accentOnStart ? style.ricette["accentoDefault"] : style.ricette["default"])

    function foregroundFor(color) { return ColorMath.foreground(color); }
    readonly property bool motionEnabled: Core.Ipc.get("desktop.animations", true)
    readonly property int duration: style.motionEnabled ? 120 : 0
    readonly property int flyoutDuration: style.motionEnabled ? 167 : 0
    readonly property real viewTravel: 24
    readonly property real textScale: Core.Ipc.get("accessibility.textScale", 1)
    property FontLoader regular: FontLoader { source: "fonts/Selawik-Regular.ttf" }
    property FontLoader bold: FontLoader { source: "fonts/Selawik-Bold.ttf" }
    readonly property string font: {
        var families = Qt.fontFamilies();
        if (families.indexOf("Segoe UI Variable") >= 0) return "Segoe UI Variable";
        if (families.indexOf("Segoe UI") >= 0) return "Segoe UI";
        return style.regular.status === FontLoader.Ready ? style.regular.name : "Noto Sans";
    }
    function label(it, en) { return style.it ? it : en; }
}
