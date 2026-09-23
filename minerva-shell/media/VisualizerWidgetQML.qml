import QtQuick
import "../theme" as Theme

// VisualizerWidgetQML — Il disegno che accompagna l'audio.
//
// Non legge la musica: la interpreta. Quattro modi, tutti dipinti a mano su
// una tela — nessuna libreria, nessun campione da analizzare. Quando il
// riproduttore è fermo resta una linea bassa; quando suona, il disegno vive.
//
// Il nome resta quello dello scheletro Python da cui è nato; il corpo non ha
// una riga in comune con lui.
Canvas {
    id: vis

    // ── Dipingere fuori dal filo dell'interfaccia ────────────────────────
    //
    // `Threaded` sposta la pittura su un filo suo: mentre la tela si ridisegna
    // — sedici volte al secondo — la finestra resta reattiva. Col modo
    // predefinito il disegno e i clic si dividono lo stesso filo, e su un
    // disegno un po' costoso si sente subito.
    renderStrategy: Canvas.Threaded

    /// 0 barre, 1 onda, 2 radiale, 3 neon.
    property int modo: 0
    property bool inRiproduzione: false
    property color tinta: Theme.Colors.accent
    property color tintaBassa: Theme.Colors.accentAlt
    /// L'orologio del disegno: avanza quando suona, e le forme si muovono.
    property real fase: 0

    onPaint: {
        var ctx = vis.getContext("2d");
        var w = vis.width;
        var h = vis.height;
        if (!ctx || w <= 0 || h <= 0)
            return;
        ctx.clearRect(0, 0, w, h);
        if (vis.modo === 0)
            vis._barre(ctx, w, h);
        else if (vis.modo === 1)
            vis._onda(ctx, w, h);
        else if (vis.modo === 2)
            vis._radiale(ctx, w, h);
        else
            vis._neon(ctx, w, h);
    }

    Timer {
        interval: 60
        running: vis.inRiproduzione
        repeat: true
        onTriggered: {
            vis.fase += 0.12;
            vis.requestPaint();
        }
    }

    onWidthChanged: vis.requestPaint()
    onHeightChanged: vis.requestPaint()
    onModoChanged: vis.requestPaint()
    onTintaChanged: vis.requestPaint()
    onTintaBassaChanged: vis.requestPaint()

    // ── Gli attrezzi ──────────────────────────────────────────────────────

    /// L'alone attorno a un tratto, ripassandolo invece di sfocarlo.
    ///
    /// ── Perché non `ctx.shadowBlur`, che sarebbe una riga ────────────────
    ///
    /// Perché in Qt la sfocatura di un'ombra su tela **non è un effetto sul
    /// tratto: è una passata su tutta la superficie**, e costa quanto la
    /// tela è grande — non quanto è lungo il tratto. `onda` la chiedeva tre
    /// volte a fotogramma e `neon` due, sedici volte al secondo.
    ///
    /// Il risultato l'ha detto Giacomo il 4 settembre 2026: «2 dei 4 effetti
    /// per audio vanno molto lentamente e sono scattosi» — e i due erano
    /// esattamente **onda e neon**, cioè gli unici due che usavano
    /// `shadowBlur`. `barre` e `radiale`, che non lo usano, andavano lisci.
    ///
    /// Un alone si fa anche ripassando lo stesso tracciato tre volte, sempre
    /// più largo e sempre più trasparente. A occhio è la stessa cosa; per il
    /// processore sono tre tratti invece di tre sfocature a schermo pieno.
    ///
    /// Il tracciato NON si ricostruisce: `stroke()` non lo consuma, quindi si
    /// disegna una volta e si ripassa. Ricostruirlo tre volte butterebbe via
    /// metà del risparmio.
    function _ripassa(ctx, colore, spessore, alone) {
        for (var g = alone; g >= 1; g--) {
            ctx.lineWidth = spessore + g * 2.2;
            ctx.strokeStyle = Qt.alpha(colore, 0.06 + 0.04 * (alone - g));
            ctx.stroke();
        }
    }

    /// Un rettangolo a spigoli vivi diventa un dito; uno arrotondato un tasto.
    function _arrotonda(ctx, x, y, w, h, r) {
        r = Math.max(0, Math.min(r, w / 2, h / 2));
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.arcTo(x + w, y, x + w, y + h, r);
        ctx.arcTo(x + w, y + h, x, y + h, r);
        ctx.arcTo(x, y + h, x, y, r);
        ctx.arcTo(x, y, x + w, y, r);
        ctx.closePath();
    }

    /// Il fattore di «vita» di una barra: quasi nulla da ferma, tutto acceso
    /// quando suona, e diverso per ogni barra.
    function _vita(seme) {
        if (!vis.inRiproduzione)
            return 0.05;
        return 0.06 + 0.94 * Math.abs(Math.sin(vis.fase * 1.3 + seme))
                      * (0.35 + 0.65 * Math.random());
    }

    // ── Barre: l'equalizzatore ────────────────────────────────────────────

    function _barre(ctx, w, h) {
        var n = 26;
        var passo = w / n;
        var grad = ctx.createLinearGradient(0, h, 0, 0);
        grad.addColorStop(0, vis.tintaBassa);
        grad.addColorStop(1, vis.tinta);
        for (var i = 0; i < n; i++) {
            var p = vis._vita(i * 0.55);
            var bh = h * p;
            ctx.fillStyle = grad;
            ctx.globalAlpha = 0.5 + 0.5 * p;
            vis._arrotonda(ctx, i * passo + passo * 0.18, h - bh,
                           passo * 0.64, bh, Math.min(6, passo * 0.32));
            ctx.fill();
        }
        ctx.globalAlpha = 1;
    }

    // ── Onda: tre strati che respirano ────────────────────────────────────

    function _onda(ctx, w, h) {
        var amp = h * (vis.inRiproduzione ? 0.34 : 0.05);
        var strati = [
            { f: 4, fase: 0, vel: 1, amp: 1, col: vis.tinta, spessore: 3, alone: 3 },
            { f: 9, fase: 1.7, vel: 2.3, amp: 0.55, col: vis.tintaBassa, spessore: 2, alone: 2 },
            { f: 15, fase: 3.1, vel: 3.7, amp: 0.3, col: vis.tinta, spessore: 1.2, alone: 1 }
        ];
        for (var k = 0; k < strati.length; k++) {
            var s = strati[k];
            ctx.beginPath();
            // Un punto ogni cinque pixel invece che ogni tre: su una curva
            // che oscilla quattro volte in tutta la larghezza, la differenza
            // non si vede — e sono due punti su cinque in meno da unire.
            for (var x = 0; x <= w; x += 5) {
                var t = x / w;
                var inv = 1 - Math.abs(t * 2 - 1);
                var y = h / 2
                        + Math.sin(t * Math.PI * s.f + vis.fase * s.vel + s.fase)
                          * inv * amp * s.amp;
                if (x === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            vis._ripassa(ctx, s.col, s.spessore, s.alone);
            ctx.lineWidth = s.spessore;
            ctx.strokeStyle = Qt.alpha(s.col, 0.9 - k * 0.25);
            ctx.stroke();
        }
    }

    // ── Radiale: raggi intorno a un centro ────────────────────────────────

    function _radiale(ctx, w, h) {
        var cx = w / 2;
        var cy = h / 2;
        var r = Math.min(w, h) / 2;
        var n = 40;
        for (var i = 0; i < n; i++) {
            var a = (i / n) * Math.PI * 2 + vis.fase * 0.35;
            var p = vis._vita(i * 0.7);
            var len = r * p;
            ctx.strokeStyle = Qt.alpha(i % 2 === 0 ? vis.tinta : vis.tintaBassa, 0.8);
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.moveTo(cx + Math.cos(a) * r * 0.22, cy + Math.sin(a) * r * 0.22);
            ctx.lineTo(cx + Math.cos(a) * (r * 0.22 + len),
                       cy + Math.sin(a) * (r * 0.22 + len));
            ctx.stroke();
        }
        ctx.strokeStyle = Qt.alpha(vis.tinta, 0.5);
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.arc(cx, cy, r * 0.22, 0, Math.PI * 2);
        ctx.stroke();
    }

    // ── Neon: l'oscilloscopio ─────────────────────────────────────────────

    function _neon(ctx, w, h) {
        ctx.strokeStyle = Qt.alpha(vis.tinta, 0.10);
        ctx.lineWidth = 1;
        for (var gx = 0; gx <= w; gx += Math.max(1, w / 10)) {
            ctx.beginPath();
            ctx.moveTo(gx, 0);
            ctx.lineTo(gx, h);
            ctx.stroke();
        }
        for (var gy = 0; gy <= h; gy += Math.max(1, h / 4)) {
            ctx.beginPath();
            ctx.moveTo(0, gy);
            ctx.lineTo(w, gy);
            ctx.stroke();
        }
        var amp = h * (vis.inRiproduzione ? 0.38 : 0.05);
        var tracce = [
            { f: 5, fase: 0, col: vis.tinta, spessore: 2.4, alone: 4 },
            { f: 2.5, fase: 2.2, col: vis.tintaBassa, spessore: 1.6, alone: 2 }
        ];
        for (var k = 0; k < tracce.length; k++) {
            var tr = tracce[k];
            ctx.beginPath();
            for (var x = 0; x <= w; x += 4) {
                var t = x / w;
                var y = h / 2
                        + Math.sin(t * Math.PI * 2 * tr.f + vis.fase * 2 + tr.fase)
                          * amp;
                if (x === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            vis._ripassa(ctx, tr.col, tr.spessore, tr.alone);
            ctx.lineWidth = tr.spessore;
            ctx.strokeStyle = Qt.alpha(tr.col, 0.95);
            ctx.stroke();
        }
    }
}