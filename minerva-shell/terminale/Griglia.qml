import QtQuick
import "../theme" as Theme

// Griglia — Il disegno delle celle: un Canvas, i tratti, il cursore.
//
// ── Perché un Canvas e non un Text per riga ────────────────────────────────
//
// La shell disegna col processore (`QT_QUICK_BACKEND=software`). Ventiquattro
// `Text` con testo ricco per i colori sarebbero ventiquattro layout di testo
// ricco a ogni fotogramma — e un `cat` ne chiede sessanta al secondo. Un
// `Canvas` è QPainter, cioè esattamente quello con cui la shell disegna
// tutto il resto: si disegna un tratto (celle vicine con lo stesso colore)
// con una `fillText`, e si ridipinge SOLO la riga che è cambiata — il
// Canvas tiene il resto com'era.
//
// ── Le misure ──────────────────────────────────────────────────────────────
//
// La cella si misura una volta, con `measureText("M")` sul carattere
// monospazio del tema: larghezza dall'avanzamento, altezza dal corpo per
// l'interlinea. Da lì escono colonne e righe, che si mandano al motore ogni
// volta che la finestra cambia misura.
Canvas {
    id: griglia

    /// Il motore riempie queste due dall'esterno.
    /// `righe[i]` è una lista di tratti `[testo, fg, bg, fl, colonna]`.
    property var righe: []
    property var cursore: ({ "c": 0, "r": 0, "v": true, "f": 0 })
    property bool haFuoco: true
    /// Da dove prendere i colori.
    property var tavolozza: null

    property string carattere: Theme.Typography.fontMono
    property int corpo: 14

    /// La selezione, in celle: da (c1,r1) a (c2,r2) incluse; `attiva` falsa
    /// quando non c'è.
    property bool selezioneAttiva: false
    property int selC1: 0
    property int selR1: 0
    property int selC2: 0
    property int selR2: 0

    // ── Le misure della cella ────────────────────────────────────────────
    property real cellaL: 8
    property real cellaA: 17
    readonly property int colonne: Math.max(2, Math.floor(width / cellaL))
    readonly property int righeVisibili: Math.max(1, Math.floor(height / cellaA))

    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image

    /// Le righe da ridipingere al prossimo passaggio; vuoto = tutte.
    property var _sporche: ({})
    property bool _tutto: true
    property int _cursoreRigaPrima: -1

    function misura() {
        // Il contesto esiste solo da `available`: chiederlo prima dà un
        // avviso e niente, e la cella resterebbe a otto pixel per sempre.
        if (!griglia.available) return;
        var cr = griglia.getContext("2d");
        if (!cr) return;
        cr.font = griglia.corpo + "px '" + griglia.carattere + "'";
        var m = cr.measureText("M");
        var l = Math.max(4, m.width);
        var a = Math.round(griglia.corpo * 1.28);
        if (l !== griglia.cellaL || a !== griglia.cellaA) {
            griglia.cellaL = l;
            griglia.cellaA = a;
            griglia._tutto = true;
        }
    }

    onCorpoChanged: { griglia.misura(); griglia.requestPaint(); }
    onCarattereChanged: { griglia.misura(); griglia.requestPaint(); }
    onWidthChanged: { griglia._tutto = true; griglia.requestPaint(); }
    onHeightChanged: { griglia._tutto = true; griglia.requestPaint(); }
    onHaFuocoChanged: griglia.ridipingiRiga(griglia.cursore.r)
    onSelezioneAttivaChanged: { griglia._tutto = true; griglia.requestPaint(); }
    onAvailableChanged: if (griglia.available) { griglia.misura(); griglia._tutto = true; griglia.requestPaint(); }

    /// Il motore chiama questa con le righe nuove.
    function aggiorna(elenco, tutte) {
        var r = griglia.righe;
        if (tutte) {
            var nuove = [];
            for (var i = 0; i < elenco.length; i++) nuove[elenco[i][0]] = elenco[i][1];
            griglia.righe = nuove;
            griglia._tutto = true;
        } else {
            for (var k = 0; k < elenco.length; k++) {
                r[elenco[k][0]] = elenco[k][1];
                griglia._sporche[elenco[k][0]] = true;
            }
        }
        griglia.requestPaint();
    }

    function ridipingiRiga(i) {
        griglia._sporche[i] = true;
        griglia.requestPaint();
    }

    onCursoreChanged: {
        if (griglia._cursoreRigaPrima >= 0) griglia._sporche[griglia._cursoreRigaPrima] = true;
        griglia._sporche[griglia.cursore.r] = true;
        griglia._cursoreRigaPrima = griglia.cursore.r;
        griglia.requestPaint();
    }

    function selezionata(c, r) {
        if (!griglia.selezioneAttiva) return false;
        var a = griglia.selR1 * 100000 + griglia.selC1;
        var b = griglia.selR2 * 100000 + griglia.selC2;
        var p = r * 100000 + c;
        if (a > b) { var t = a; a = b; b = t; }
        return p >= a && p <= b;
    }

    onPaint: {
        var cr = griglia.getContext("2d");
        var tav = griglia.tavolozza;
        if (!tav) return;
        var L = griglia.cellaL, A = griglia.cellaA;
        var quante = griglia.righeVisibili;
        var daFare = [];
        if (griglia._tutto) {
            cr.clearRect(0, 0, griglia.width, griglia.height);
            for (var i = 0; i < quante; i++) daFare.push(i);
        } else {
            for (var k in griglia._sporche) daFare.push(parseInt(k));
        }
        griglia._tutto = false;
        griglia._sporche = {};

        var testoBase = tav.testo;
        var fontNorm = griglia.corpo + "px '" + griglia.carattere + "'";
        cr.textBaseline = "alphabetic";
        var salita = Math.round(griglia.corpo * 0.95);

        for (var d = 0; d < daFare.length; d++) {
            var i = daFare[d];
            if (i < 0 || i >= quante) continue;
            var y = i * A;
            cr.clearRect(0, y, griglia.width, A);
            var tratti = griglia.righe[i] || [];

            // Prima tutti i fondi, poi tutto il testo: un glifo che sborda
            // (la `j`, le lettere corsive) non deve finire sotto il fondo
            // della cella accanto.
            for (var t = 0; t < tratti.length; t++) {
                var tr = tratti[t];
                var fl = tr[3];
                var col = tr[4];
                var largo = (fl & 256) ? 2 : tr[0].length;
                var fondo = (fl & 32) ? tav.colore(tr[1], testoBase) : tav.colore(tr[2], null);
                if (fondo !== null && fondo !== undefined) {
                    cr.fillStyle = fondo;
                    cr.fillRect(col * L, y, largo * L, A);
                }
            }
            // La selezione, sopra i fondi e sotto il testo.
            if (griglia.selezioneAttiva) {
                for (var c = 0; c < griglia.colonne; c++) {
                    if (griglia.selezionata(c, i)) {
                        cr.fillStyle = Qt.alpha(Theme.Colors.accent, 0.35);
                        cr.fillRect(c * L, y, L, A);
                    }
                }
            }
            for (var u = 0; u < tratti.length; u++) {
                var tt = tratti[u];
                var f = tt[3];
                if (f & 64) continue; // nascosto
                var x = tt[4] * L;
                var davanti = (f & 32) ? tav.colore(tt[2], null) : tav.colore(tt[1], testoBase);
                if (davanti === null || davanti === undefined)
                    davanti = (f & 32) ? Theme.Colors.base : testoBase;
                var stile = "";
                if (f & 4) stile += "italic ";
                if (f & 1) stile += "bold ";
                cr.font = stile + fontNorm;
                cr.fillStyle = (f & 2) ? Qt.alpha(davanti, 0.6) : davanti;
                if (f & 256) {
                    // Largo: si centra nelle due celle, che il glifo di
                    // solito riempie quasi tutte.
                    cr.fillText(tt[0], x, y + salita);
                } else {
                    // Una lettera per cella, così le colonne restano
                    // allineate anche se il carattere non è davvero
                    // monospazio per quel glifo.
                    for (var g = 0; g < tt[0].length; g++)
                        cr.fillText(tt[0][g], x + g * L, y + salita);
                }
                if (f & 8) {
                    cr.fillRect(x, y + A - 2, (f & 256 ? 2 : tt[0].length) * L, 1);
                }
                if (f & 128) {
                    cr.fillRect(x, y + Math.round(A * 0.55), (f & 256 ? 2 : tt[0].length) * L, 1);
                }
            }

            // Il cursore.
            var cu = griglia.cursore;
            if (cu.v && cu.r === i) {
                var cx = cu.c * L;
                cr.fillStyle = Theme.Colors.accent;
                if (!griglia.haFuoco) {
                    cr.strokeStyle = Theme.Colors.accent;
                    cr.lineWidth = 1;
                    cr.strokeRect(cx + 0.5, y + 0.5, L - 1, A - 1);
                } else if (cu.f === 2) {
                    cr.fillRect(cx, y, 2, A);
                } else if (cu.f === 1) {
                    cr.fillRect(cx, y + A - 2, L, 2);
                } else {
                    cr.fillRect(cx, y, L, A);
                    // Il carattere sotto il cursore, nel colore del fondo,
                    // così resta leggibile.
                    var sotto = griglia.carattereA(cu.c, i);
                    if (sotto !== "") {
                        cr.font = fontNorm;
                        cr.fillStyle = Theme.Colors.textOnAccent;
                        cr.fillText(sotto, cx, y + salita);
                    }
                }
            }
        }
    }

    /// Il carattere nella cella (c, r), o "".
    function carattereA(c, r) {
        var tratti = griglia.righe[r] || [];
        for (var t = 0; t < tratti.length; t++) {
            var tr = tratti[t];
            var inizio = tr[4];
            var n = (tr[3] & 256) ? 2 : tr[0].length;
            if (c >= inizio && c < inizio + n)
                return (tr[3] & 256) ? tr[0] : tr[0][c - inizio];
        }
        return "";
    }

    /// Il testo di una riga, per la copia.
    function testoRiga(r, daC, aC) {
        var tratti = griglia.righe[r] || [];
        var celle = [];
        for (var t = 0; t < tratti.length; t++) {
            var tr = tratti[t];
            if (tr[3] & 256) { celle[tr[4]] = tr[0]; celle[tr[4] + 1] = ""; continue; }
            for (var g = 0; g < tr[0].length; g++) celle[tr[4] + g] = tr[0][g];
        }
        var s = "";
        var fine = aC === undefined ? griglia.colonne - 1 : aC;
        for (var c = (daC || 0); c <= fine; c++) s += celle[c] === undefined ? " " : celle[c];
        return s.replace(/\s+$/, "");
    }

    /// Il testo selezionato, righe separate da a-capo.
    function testoSelezionato() {
        if (!griglia.selezioneAttiva) return "";
        var r1 = griglia.selR1, c1 = griglia.selC1, r2 = griglia.selR2, c2 = griglia.selC2;
        if (r1 > r2 || (r1 === r2 && c1 > c2)) {
            var tr = r1; r1 = r2; r2 = tr; var tc = c1; c1 = c2; c2 = tc;
        }
        var righe = [];
        for (var r = r1; r <= r2; r++) {
            var da = r === r1 ? c1 : 0;
            var a = r === r2 ? c2 : griglia.colonne - 1;
            righe.push(griglia.testoRiga(r, da, a));
        }
        return righe.join("\n");
    }
}
