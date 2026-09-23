import QtQuick
import "../theme" as Theme
import "../core" as Core

// Grafico — La storia di una grandezza, dietro al suo numero.
//
// ── Perché non è un ornamento ──────────────────────────────────────────────
//
// «42 %» non si sa se è tanto. «42 % e sale da un minuto» sì. È tutta la
// differenza fra un widget e un'etichetta, ed è la ragione per cui i widget
// di sistema esistono: non per sapere il numero — quello lo dice il Monitor —
// ma per accorgersi che è successo qualcosa mentre si guardava altrove.
//
// Quattro minuti di storia, quarantotto campioni. Il conto sta in
// `core/Macchina.qml`.
//
// ── Canvas e non Shape ─────────────────────────────────────────────────────
//
// La shell disegna col processore (`QT_QUICK_BACKEND=software`). Lì una
// `Shape` dentro una lista lascia i propri pixel dove non c'è più niente —
// è la famiglia di difetti che questo progetto chiama `minerva-residui-software`
// — mentre un `Canvas` è QPainter, cioè esattamente quello che la shell usa
// per tutto il resto. La dock ci disegna il proprio vetro da settimane.
//
// E si ridipinge quando arriva un campione, cioè ogni cinque secondi: non è
// un'animazione, è un disegno che cambia quando cambia il dato.
Canvas {
    id: grafico

    /// Quale grandezza: `processore`, `memoria`, `gpu`, `rete`.
    required property string quale

    /// Il colore della linea. Lo decide chi lo usa, perché è lo stesso della
    /// barra: due colori diversi per lo stesso valore sono due valori.
    property color tinta: Theme.Colors.accent

    /// Senza vetro dietro la linea va ingrossata: un filo di un pixel sopra
    /// una fotografia si perde nei dettagli.
    property bool nudo: false

    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image

    readonly property var punti: Core.Macchina.storia(grafico.quale)
    readonly property real massimo: Core.Macchina.fondoScala(grafico.quale)

    onPuntiChanged: grafico.requestPaint()
    onTintaChanged: grafico.requestPaint()
    onWidthChanged: grafico.requestPaint()
    onHeightChanged: grafico.requestPaint()

    onPaint: {
        var cr = grafico.getContext("2d");
        cr.reset();
        cr.clearRect(0, 0, grafico.width, grafico.height);

        if (grafico.width <= 1 || grafico.height <= 1)
            return;

        // ── Il pavimento ─────────────────────────────────────────────────
        //
        // Una riga sottilissima sul fondo, sempre. Dice DOVE sta il grafico
        // anche quando il valore è basso: col processore al 4 % la linea
        // corre a tre pixel dal bordo, e senza un pavimento sotto sembra un
        // graffio sulla carta invece che una misura vicina allo zero.
        //
        // È anche il pezzo che si vede mentre la storia si riempie, cioè nei
        // primi quattro minuti: una carta che per quattro minuti non mostra
        // niente sembra rotta.
        cr.strokeStyle = Qt.alpha(grafico.tinta, grafico.nudo ? 0.45 : 0.28);
        cr.lineWidth = 1;
        cr.beginPath();
        cr.moveTo(0, grafico.height - 0.5);
        cr.lineTo(grafico.width, grafico.height - 0.5);
        cr.stroke();

        var p = grafico.punti;
        // Meno di due punti non è una storia: è un punto, e una linea fra un
        // punto e sé stesso non dice niente. Si aspetta il secondo campione
        // invece di disegnare una riga piatta che sembra «tutto fermo».
        if (!p || p.length < 2)
            return;

        var max = grafico.massimo > 0 ? grafico.massimo : 1;
        var passo = grafico.width / (Core.Macchina.quantiRicordi - 1);
        // Si disegna ANCORATI A DESTRA: il campione più nuovo sta sempre sul
        // bordo destro, e la storia entra da lì. Ancorandola a sinistra, un
        // grafico mezzo pieno avrebbe l'adesso in mezzo allo spazio vuoto.
        var primo = grafico.width - (p.length - 1) * passo;

        function ics(i) { return primo + i * passo; }
        function ipsilon(v) {
            var q = Math.max(0, Math.min(1, v / max));
            return grafico.height - q * (grafico.height - 1) - 0.5;
        }

        // Prima il riempimento, poi la linea sopra: un'area sola sarebbe una
        // macchia, una linea sola sparirebbe su uno sfondo mosso.
        cr.beginPath();
        cr.moveTo(ics(0), grafico.height);
        for (var i = 0; i < p.length; i++)
            cr.lineTo(ics(i), ipsilon(p[i]));
        cr.lineTo(ics(p.length - 1), grafico.height);
        cr.closePath();
        // Nudo il riempimento è PIÙ LEGGERO e non più forte, che è il
        // contrario di quel che verrebbe da fare. Senza vetro dietro, un'area
        // al quaranta per cento sopra una fotografia non si legge come una
        // sfumatura: si legge come un rettangolo pieno appoggiato lì — e chi
        // ha scelto «nudo» l'ha fatto per vedere lo sfondo. A tenere la linea
        // leggibile ci pensa il tratto, che nudo è più grosso.
        cr.fillStyle = Qt.alpha(grafico.tinta, grafico.nudo ? 0.22 : 0.30);
        cr.fill();

        cr.beginPath();
        for (var k = 0; k < p.length; k++) {
            if (k === 0)
                cr.moveTo(ics(k), ipsilon(p[k]));
            else
                cr.lineTo(ics(k), ipsilon(p[k]));
        }
        cr.strokeStyle = grafico.tinta;
        cr.lineWidth = grafico.nudo ? 2.0 : 1.8;
        cr.lineJoin = "round";
        cr.stroke();
    }
}
