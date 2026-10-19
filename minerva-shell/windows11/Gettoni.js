.pragma library
.import "ColorMath.js" as ColorMath

// I colori di Windows 11, presi dal sorgente e non a occhio.
//
// Il manutentore, 11 ottobre 2026: «i colori delle schede non sono coerenti, in
// Windows sono leggermente in blur: cerca l'esatta combinazione che si adatti
// a tutte le combinazioni di colori di Windows, anche per il colore manuale».
//
// Fonte: microsoft/microsoft-ui-xaml (licenza MIT), commit
// fe9d01273af3382ea570e203ab700772528d98df dell'11 ottobre 2026:
//   controls/dev/CommonStyles/Common_themeresources_any.xaml   (i gettoni)
//   controls/dev/Materials/Acrylic/AcrylicBrush_themeresources.xaml (Acrylic)
//   controls/dev/Materials/Acrylic/AcrylicBrush.cpp/.h  (ricetta, raggio 30,
//                                                        rumore 0,02)
// Copia di lavoro in ../Liquid_test-principale/riferimenti/winui.
//
// I valori sono #AARRGGBB come nel sorgente: i gettoni trasparenti
// (CardBackground, SubtleFill…) si stendono SOPRA un materiale, ed è
// proprio la trasparenza a far vedere il vetro sotto le schede.

var scuro = {
    textPrimary: "#FFFFFFFF",
    textSecondary: "#C5FFFFFF",
    textTertiary: "#87FFFFFF",
    textDisabled: "#5DFFFFFF",
    textOnAccent: "#FF000000",
    textOnAccentSecondary: "#80000000",
    cardBackground: "#0DFFFFFF",
    cardBackgroundSecondary: "#08FFFFFF",
    cardStroke: "#19000000",
    surfaceStrokeFlyout: "#33000000",
    surfaceStroke: "#66757575",
    subtleSecondary: "#0FFFFFFF",
    subtleTertiary: "#0AFFFFFF",
    controlFill: "#0FFFFFFF",
    controlFillSecondary: "#15FFFFFF",
    controlStroke: "#12FFFFFF",
    dividerStroke: "#15FFFFFF",
    layerFill: "#4C3A3A3A",
    solidBase: "#FF202020",
    solidSecondary: "#FF1C1C1C",
    solidTertiary: "#FF282828",
    solidQuarternary: "#FF2C2C2C",
    smoke: "#4D000000",
    critical: "#FFFF99A4",
    success: "#FF6CCB5F",
    caution: "#FFFCE100"
};

var chiaro = {
    textPrimary: "#E4000000",
    textSecondary: "#9E000000",
    textTertiary: "#72000000",
    textDisabled: "#5C000000",
    textOnAccent: "#FFFFFFFF",
    textOnAccentSecondary: "#B3FFFFFF",
    cardBackground: "#B3FFFFFF",
    cardBackgroundSecondary: "#80F6F6F6",
    cardStroke: "#0F000000",
    surfaceStrokeFlyout: "#0F000000",
    surfaceStroke: "#66757575",
    subtleSecondary: "#09000000",
    subtleTertiary: "#06000000",
    controlFill: "#B3FFFFFF",
    controlFillSecondary: "#80F9F9F9",
    controlStroke: "#0F000000",
    dividerStroke: "#0F000000",
    layerFill: "#80FFFFFF",
    solidBase: "#FFF3F3F3",
    solidSecondary: "#FFEEEEEE",
    solidTertiary: "#FFF9F9F9",
    solidQuarternary: "#FFFFFFFF",
    smoke: "#4D000000",
    critical: "#FFC42B1C",
    success: "#FF0F7B0F",
    caution: "#FF9D5D00"
};

// ── Le ricette Acrylic ───────────────────────────────────────────────────
//
// `default`: menu, flyout, Start, calendario, impostazioni rapide.
// `base`:    la barra delle applicazioni (il materiale più «di fondo»).
// `accento`: con «Mostra il colore d'accento su Start e barra»; la tinta è
//            una sfumatura dell'accento (`sfumatura`), non un colore fisso.
// `ripiego` è il colore pieno quando il vetro non c'è (trasparenza spenta,
// risparmio energetico, finestra non attiva): Learn, «Acrylic material».
var acrylic = {
    scuro: {
        "default": { tinta: "#2C2C2C", tintaOpacita: 0.15, luminosita: 0.96, ripiego: "#2C2C2C" },
        "base": { tinta: "#202020", tintaOpacita: 0.5, luminosita: 0.96, ripiego: "#1C1C1C" },
        "accentoDefault": { sfumatura: "dark1", tintaOpacita: 0.8, luminosita: 0.8 },
        "accentoBase": { sfumatura: "dark2", tintaOpacita: 0.8, luminosita: 0.8 }
    },
    chiaro: {
        "default": { tinta: "#FCFCFC", tintaOpacita: 0.0, luminosita: 0.85, ripiego: "#F9F9F9" },
        "base": { tinta: "#F3F3F3", tintaOpacita: 0.0, luminosita: 0.9, ripiego: "#EEEEEE" },
        "accentoDefault": { sfumatura: "light3", tintaOpacita: 0.8, luminosita: 0.9 },
        "accentoBase": { sfumatura: "light3", tintaOpacita: 0.8, luminosita: 0.9 }
    },
    raggio: 30,
    rumore: 0.02
};

// Le sfumature dell'accento che usano i gettoni d'accento (stesso file):
//   riempimento (AccentFillColorDefault): Light2 in scuro, Dark1 in chiaro;
//   testo d'accento (AccentTextFillColorPrimary): Light3 in scuro, Dark2 in chiaro.
var usoAccento = {
    scuro: { riempimento: "light2", testo: "light3" },
    chiaro: { riempimento: "dark1", testo: "dark2" }
};

// L'azzurro di serie di Windows 11 e le sue sei sfumature, come Windows le
// scrive nel registro (`AccentPalette`). Servono a tarare
// `ColorMath.palette`: la formula di Windows non è pubblicata (Learn,
// UIColorType: «generated automatically»).
var azzurroDiSerie = {
    light3: "#99EBFF", light2: "#4CC2FF", light1: "#0091F8",
    accento: "#0078D4",
    dark1: "#0067C0", dark2: "#003E92", dark3: "#001A68"
};

function tema(scuroAttivo) {
    return scuroAttivo ? scuro : chiaro;
}

/// La prima sfumatura scura su cui il testo bianco si legge (≥ 4,5):
/// con un accento chiaro, un giallo, Dark1 è troppo chiaro e si scende.
function sfumaturaLeggibile(palette, nomi) {
    for (var i = 0; i < nomi.length; i++) {
        if (ColorMath.contrast("#ffffff", palette[nomi[i]]) >= 4.5)
            return palette[nomi[i]];
    }
    return palette[nomi[nomi.length - 1]];
}

/// La ricetta Acrylic che il compositore stende dietro la barra e i suoi
/// pannelli (verbo «vetrobarra si <tinta> <op> <lum> <op>»).
///
/// La superficie è una sola, barra e pannelli insieme: si usa la ricetta dei
/// FLYOUT (`default`, o `accentoDefault` con l'accento su Start), che sono
/// la parte grande; la striscia della barra si scurisce da sé in QML
/// (`Style.barra`). Il colore della luminosità è quello della tinta (WinUI,
/// `GetLuminosityColor` quando l'opacità di luminosità è data).
function ricettaVetro(scuroAttivo, accentoSuStart, accento) {
    var r = scuroAttivo ? acrylic.scuro : acrylic.chiaro;
    if (scuroAttivo && accentoSuStart) {
        var tavolozza = String(accento).toLowerCase() === azzurroDiSerie.accento.toLowerCase()
            ? azzurroDiSerie : ColorMath.palette(accento);
        var colore = sfumaturaLeggibile(tavolozza, ["dark1", "dark2", "dark3"]);
        return { tinta: colore, tintaOpacita: r.accentoDefault.tintaOpacita,
                 luminosita: colore, luminositaOpacita: r.accentoDefault.luminosita };
    }
    var d = r["default"];
    return { tinta: d.tinta, tintaOpacita: d.tintaOpacita,
             luminosita: d.tinta, luminositaOpacita: d.luminosita };
}
