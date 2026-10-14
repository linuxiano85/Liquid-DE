.pragma library

function channels(color) {
    if (color && typeof color.r === "number") return [color.r, color.g, color.b];
    var hex = String(color).replace(/^#/, "");
    // #AARRGGBB (i gettoni di Windows, e i colori di Qt con l'alfa): il
    // colore sono le ultime sei cifre.
    if (hex.length === 8)
        hex = hex.slice(2);
    return [0, 2, 4].map(function(offset) { return parseInt(hex.slice(offset, offset + 2), 16) / 255; });
}

/// L'alfa di un colore, da 0 a 1.
function alpha(color) {
    if (color && typeof color.a === "number") return color.a;
    var hex = String(color).replace(/^#/, "");
    return hex.length === 8 ? parseInt(hex.slice(0, 2), 16) / 255 : 1;
}

function hex(rgb) {
    return "#" + rgb.map(function(value) {
        return Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16).padStart(2, "0");
    }).join("");
}

/// Un colore trasparente steso sopra un fondo pieno: il colore che si vede.
/// Serve ai conti di leggibilità, che con un colore trasparente non hanno
/// senso (il gettone del testo chiaro è nero al 89 %).
function over(color, background) {
    var a = alpha(color), c = channels(color), b = channels(background);
    return hex(c.map(function(value, index) { return value * a + b[index] * (1 - a); }));
}

// ── OKLCH ─────────────────────────────────────────────────────────────────
//
// Lo spazio in cui «più chiaro» e «più scuro» si vedono uguali per ogni
// tinta (Björn Ottosson, 2020). Le sfumature dell'accento si fanno qui: in
// RGB un giallo e un blu alla stessa «luminosità» non sembrano affatto
// ugualmente chiari.

function oklch(color) {
    var c = channels(color).map(linear);
    var l = Math.cbrt(0.4122214708 * c[0] + 0.5363325363 * c[1] + 0.0514459929 * c[2]);
    var m = Math.cbrt(0.2119034982 * c[0] + 0.6806995451 * c[1] + 0.1073969566 * c[2]);
    var s = Math.cbrt(0.0883024619 * c[0] + 0.2817188376 * c[1] + 0.6299787005 * c[2]);
    var L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    var a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    var b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    return { l: L, c: Math.sqrt(a * a + b * b), h: Math.atan2(b, a) };
}

function _gamma(value) {
    return value <= 0.0031308 ? value * 12.92 : 1.055 * Math.pow(value, 1 / 2.4) - 0.055;
}

/// [r, g, b] lineari da OKLCH, senza tagliare: fuori da 0…1 vuol dire che il
/// colore non esiste sullo schermo.
function _rgbLineare(L, C, h) {
    var a = C * Math.cos(h), b = C * Math.sin(h);
    var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
    var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
    var s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
}

/// Il colore OKLCH sullo schermo: se è fuori gamma si toglie croma (mai
/// luminosità), così la sfumatura resta chiara o scura quanto deve.
function fromOklch(L, C, h) {
    var basso = 0, alto = C;
    var rgb = _rgbLineare(L, C, h);
    var dentro = function(v) { return v.every(function(x) { return x >= -0.0005 && x <= 1.0005; }); };
    if (!dentro(rgb)) {
        for (var i = 0; i < 24; i++) {
            var meta = (basso + alto) / 2;
            if (dentro(_rgbLineare(L, meta, h)))
                basso = meta;
            else
                alto = meta;
        }
        rgb = _rgbLineare(L, basso, h);
    }
    return hex(rgb.map(function(v) { return _gamma(Math.max(0, Math.min(1, v))); }));
}

// ── Le sei sfumature dell'accento ─────────────────────────────────────────
//
// Windows le genera da sé (Learn, UIColorType: Light1–3, Dark1–3) e la
// formula non è pubblica. Qui sono tarate sull'azzurro di serie (vedi
// `Gettoni.azzurroDiSerie`), misurato in OKLCH:
//
//   - la luminosità di ogni sfumatura sta a una frazione FISSA della strada
//     fra l'accento e un estremo (0,97 sopra, 0,15 sotto). Così l'ordine
//     resta giusto per qualunque colore, anche un giallo già chiaro o un
//     colore manuale molto scuro, dove luminosità assolute si
//     scavalcherebbero;
//   - il croma si scala come nell'azzurro, e si riduce solo se il colore non
//     sta nello schermo;
//   - la tinta resta quella scelta. Windows la sposta un poco (verso il
//     ciano schiarendo l'azzurro), ma come lo faccia sulle altre tinte non è
//     documentato, e inventarlo sarebbe peggio che non farlo.
var _SOPRA = 0.97, _SOTTO = 0.15;
var _passi = {
    light3: { verso: 1, frazione: 0.812, croma: 0.506 },
    light2: { verso: 1, frazione: 0.510, croma: 0.815 },
    light1: { verso: 1, frazione: 0.197, croma: 1.103 },
    dark1: { verso: -1, frazione: 0.125, croma: 0.964 },
    dark2: { verso: -1, frazione: 0.433, croma: 0.901 },
    dark3: { verso: -1, frazione: 0.714, croma: 0.832 }
};

function palette(accent) {
    var base = oklch(accent);
    var out = { accento: hex(channels(accent)) };
    // Un colore manuale quasi bianco o quasi nero (Windows non li accetta
    // nemmeno) darebbe sfumature tutte uguali, o chiare più scure delle
    // scure: le sfumature partono da una luminosità tenuta nel mezzo.
    var centro = Math.max(0.30, Math.min(0.85, base.l));
    for (var nome in _passi) {
        var p = _passi[nome];
        var L = p.verso > 0 ? centro + (_SOPRA - centro) * p.frazione
                            : centro - (centro - _SOTTO) * p.frazione;
        out[nome] = fromOklch(L, base.c * p.croma, base.h);
    }
    return out;
}
function linear(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}
function luminance(color) {
    var c = channels(color);
    return .2126 * linear(c[0]) + .7152 * linear(c[1]) + .0722 * linear(c[2]);
}
function contrast(first, second) {
    var a = luminance(first), b = luminance(second);
    return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
}
function foreground(background) {
    return contrast("#ffffff", background) >= contrast("#000000", background) ? "#ffffff" : "#000000";
}
function mix(first, second, amount) {
    var a = channels(first), b = channels(second);
    return "#" + a.map(function(value, index) {
        return Math.round((value * (1 - amount) + b[index] * amount) * 255).toString(16).padStart(2, "0");
    }).join("");
}
// Preserve the requested hue when possible; only ink and thin indicators need
// a contrast-adjusted variant. Filled controls keep the user's exact color.
function readable(accent, background, minimum) {
    var target = foreground(background);
    for (var step = 0; step <= 100; step++) {
        var candidate = mix(accent, target, step / 100);
        if (contrast(candidate, background) >= minimum) return candidate;
    }
    return target;
}
function darkSurface(accent) {
    var surface = mix("#202020", accent, .45);
    for (var step = 0; step <= 100; step++) {
        var candidate = mix(surface, "#202020", step / 100);
        if (contrast("#f5f5f5", candidate) >= 6) return candidate;
    }
    return "#202020";
}
