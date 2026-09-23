import QtQuick

// RitrattoTondo — Una foto ritagliata tonda, senza scheda video.
//
// ── Perché non `MultiEffect` ────────────────────────────────────────────────
//
// Fino al 18 agosto 2026 il ritratto nelle Impostazioni era una `Image` con
//
//     layer.enabled: true
//     layer.effect: MultiEffect { maskEnabled: true; maskSource: maschera }
//
// che è il modo giusto finché c'è la scheda video: `MultiEffect` è un
// programma per la GPU, e `layer.enabled` chiede al motore grafico di
// disegnare l'oggetto in disparte per poi comporlo.
//
// Provato con `QT_QUICK_BACKEND=software` — cioè quando un'app di Minerva
// disegna col processore per non pagare i 38 MB di pavimento della GPU — **il
// ritratto non diventa quadrato: sparisce del tutto.** E non compare nessun
// avviso, né nel registro né a schermo: la scheda «Il tuo account» mostra il
// nome e uno spazio vuoto dove c'era la faccia.
//
// ── Come si fa invece ───────────────────────────────────────────────────────
//
// `Canvas` disegna con QPainter, che c'è in tutti e due i casi. `arc` più
// `clip` è un ritaglio vero, non una maschera composta dopo: viene identico
// con la GPU e senza.
//
// ── E i pixel li carica `Canvas`, le misure una `Image` nascosta ────────────
//
// Sembra uno spreco caricare due volte lo stesso file, e c'è una ragione per
// ognuno dei due.
//
// `c.drawImage(unaImage, …)` — passare l'elemento `Image` invece dell'indirizzo
// — **non disegna niente**: nessun errore, nessun avviso, un cerchio vuoto.
// Provato il 18 agosto 2026 con la GPU e senza, stesso risultato. Quello che
// funziona è `loadImage(indirizzo)` e poi `drawImage(indirizzo, …)`.
//
// La `Image` nascosta però serve lo stesso, per `sourceSize`: senza sapere
// quanto è grande davvero la foto non si può riempire il cerchio senza
// schiacciare la faccia, e `Canvas` non ha nessun modo di chiederlo.
//
// Sono 76×76 pixel: il doppio caricamento costa meno del codice che servirebbe
// a evitarlo.
//
//     Ui.RitrattoTondo {
//         width: 76; height: 76
//         fonte: page.io.ritratto
//         versione: page.versioneFoto
//     }
Item {
    id: ritratto

    /// Il percorso della foto, senza `file://`: ci pensa questo.
    /// Vuoto vuol dire «nessuna foto»: non si disegna niente, e chi sta sotto
    /// (di solito l'iniziale del nome dentro un cerchio) resta visibile.
    property string fonte: ""

    /// Cambiala per far rileggere il file quando la foto cambia ma il percorso
    /// resta lo stesso. Senza, Qt ridisegna quella di prima: il percorso non è
    /// cambiato e la sua cache non ha motivo di sospettare.
    property int versione: 0

    /// Vera quando c'è davvero una faccia disegnata. Serve a chi deve
    /// nascondere il ripiego.
    readonly property bool pronto: ritratto._disegnato

    /// Vera dal momento in cui la tela ha davvero i pixel in mano.
    property bool _disegnato: false

    /// L'indirizzo completo, uno solo per tutti e due i lettori: se divergessero
    /// la tela disegnerebbe una foto e le misure verrebbero da un'altra.
    readonly property string _url: ritratto.fonte === ""
        ? "" : "file://" + ritratto.fonte + "?v=" + ritratto.versione

    Image {
        id: sorgente
        // Non si vede: è solo il modo di sapere quanto è grande la foto. Il
        // disegno lo fa la tela qui sotto.
        visible: false
        asynchronous: true
        cache: false
        source: ritratto._url
        onStatusChanged: {
            // Un file che non c'è o non è un'immagine: si torna al ripiego
            // invece di lasciare un cerchio vuoto, che sembra un difetto di
            // disegno e non un ritratto che manca.
            //
            // Se ne accorge questa `Image` e non la tela, perché **`Canvas`
            // non ha un segnale per il fallimento**: ha `imageLoaded` e basta,
            // e l'errore si può solo andare a chiedere con `isImageError`. Su
            // un file che non c'è quel segnale non arriva mai, quindi
            // aspettarlo vuol dire aspettare per sempre.
            if (sorgente.status === Image.Error)
                ritratto._disegnato = false;
            tela.requestPaint();
        }
    }

    Canvas {
        id: tela
        anchors.fill: parent

        // `loadImage` è asincrona: la risposta arriva in `onImageLoaded`, e
        // solo lì l'immagine si può disegnare. Chiamare `drawImage` subito
        // dopo `loadImage` disegna il vuoto — a volte, a seconda di quanto è
        // veloce il disco, che è il modo peggiore di sbagliare.
        function _chiedi() {
            ritratto._disegnato = false;
            if (ritratto._url !== "")
                tela.loadImage(ritratto._url);
            tela.requestPaint();
        }

        Component.onCompleted: tela._chiedi()

        Connections {
            target: ritratto
            function on_UrlChanged() { tela._chiedi(); }
        }

        onImageLoaded: {
            ritratto._disegnato = tela.isImageLoaded(ritratto._url);
            tela.requestPaint();
        }

        onPaint: {
            var c = tela.getContext("2d");
            // `reset` e non `clearRect`: il contesto tiene lo stato fra una
            // pennellata e l'altra, e un `clip` rimasto in piedi dal giro
            // prima ritaglierebbe anche la cancellatura.
            c.reset();
            if (ritratto._url === "" || !tela.isImageLoaded(ritratto._url))
                return;

            var l = tela.width, h = tela.height;
            c.save();
            c.beginPath();
            c.arc(l / 2, h / 2, Math.min(l, h) / 2, 0, Math.PI * 2);
            c.clip();

            // Come `Image.PreserveAspectCrop`: si riempie il cerchio e si
            // taglia quello che avanza, invece di schiacciare la faccia dentro
            // un quadrato. E si centra: una foto in orizzontale riempita in
            // altezza, appoggiata a sinistra, mostrerebbe una spalla.
            var iw = sorgente.sourceSize.width;
            var ih = sorgente.sourceSize.height;
            if (iw > 0 && ih > 0) {
                var scala = Math.max(l / iw, h / ih);
                var lw = iw * scala, lh = ih * scala;
                c.drawImage(ritratto._url, (l - lw) / 2, (h - lh) / 2, lw, lh);
            } else {
                // Senza le misure vere si riempie e basta: peggio che
                // centrare, meglio che non disegnare.
                c.drawImage(ritratto._url, 0, 0, l, h);
            }
            c.restore();
        }
    }
}
