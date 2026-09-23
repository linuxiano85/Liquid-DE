import QtQuick
import "../theme" as Theme

// Sparkline — Il grafico piccolo dentro una piastrella.
//
// ── Perché un grafico e non solo un numero ──────────────────────────────────
//
// Perché «CPU 34%» non dice niente da solo. Trentaquattro per cento SALENDO da
// cinque è un programma che è appena partito; trentaquattro SCENDENDO da
// novanta è una compilazione che sta finendo. Il numero dice dove sei, la linea
// dice dove stai andando — ed è quasi sempre la seconda che serve.
//
// ── Perché è disegnato a mano e non con una libreria ────────────────────────
//
// Perché serve una cosa sola: una polilinea con un riempimento sotto. `Canvas`
// in QML ridisegna su richiesta e costa quanto un rettangolo; una libreria di
// grafici porterebbe assi, legende, animazioni e temi che qui non servono e che
// bisognerebbe poi spegnere uno per uno per non litigare col design system.
Canvas {
    id: linea

    /// I campioni, dal più vecchio al più recente. Chi la usa ci appende in
    /// coda e taglia in testa.
    property var punti: []

    /// Fondoscala. Se è zero si adatta al massimo dei campioni, che è quello
    /// che serve per grandezze senza tetto — la rete, per dire.
    property real massimo: 100

    property color colore: Theme.Colors.accent

    /// Quanto è marcato il riempimento sotto la linea.
    property real velo: 0.16

    onPuntiChanged: linea.requestPaint()
    onColoreChanged: linea.requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var n = linea.punti.length;
        if (n < 2)
            return;

        // Il fondoscala: quello dichiarato, o il massimo visto più un decimo
        // di respiro — senza, la linea striscia sul bordo alto e non si legge
        // più quanto sta salendo.
        var top = linea.massimo;
        if (top <= 0) {
            top = 0;
            for (var k = 0; k < n; k++)
                if (linea.punti[k] > top)
                    top = linea.punti[k];
            top = top > 0 ? top * 1.1 : 1;
        }

        var passo = linea.width / (n - 1);
        function y(v) {
            var f = Math.max(0, Math.min(1, v / top));
            // Un pixel e mezzo di margine: la linea ha uno spessore, e senza
            // margine la sua metà superiore verrebbe tagliata via.
            return linea.height - 1.5 - f * (linea.height - 3);
        }

        // Il riempimento per primo, o coprirebbe la linea.
        ctx.beginPath();
        ctx.moveTo(0, linea.height);
        for (var i = 0; i < n; i++)
            ctx.lineTo(i * passo, y(linea.punti[i]));
        ctx.lineTo((n - 1) * passo, linea.height);
        ctx.closePath();
        ctx.fillStyle = Qt.alpha(linea.colore, linea.velo);
        ctx.fill();

        ctx.beginPath();
        for (var j = 0; j < n; j++) {
            var px = j * passo, py = y(linea.punti[j]);
            if (j === 0)
                ctx.moveTo(px, py);
            else
                ctx.lineTo(px, py);
        }
        ctx.strokeStyle = linea.colore;
        ctx.lineWidth = 1.6;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.stroke();
    }
}
