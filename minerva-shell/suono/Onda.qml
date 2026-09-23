import QtQuick

import "../theme" as Theme

// Onda — Il nastro. È qui che si lavora.
//
// ── PERCHÉ UN'ONDA E NON UNA BARRA DI AVANZAMENTO ──────────────────────────
//
// Una barra di avanzamento dice a che punto sei. Un'onda dice DOVE ANDARE. Chi
// ritaglia una suoneria non cerca «il minuto 1:42», cerca «lì dove riparte
// forte» — e quel punto si vede: è dove la forma si alza di colpo. Con una
// barra liscia lo si trova a orecchio, riascoltando lo stesso passaggio dieci
// volte; con l'onda si trova in un secondo e poi si controlla a orecchio una
// volta sola. È la differenza fra cercare e verificare.
//
// I numeri li calcola il demone con ffmpeg (`audio_service.dart`): in QML non
// c'è modo di leggere i campioni di un mp3.
//
// ── COME È DISEGNATA, E PERCHÉ COSÌ ────────────────────────────────────────
//
// Due tele sovrapposte con lo stesso disegno, una spenta e una accesa, e la
// seconda ritagliata fino al punto in cui si è arrivati. Sembra un giro largo
// rispetto a ridisegnare l'onda a ogni fotogramma con due colori — ma
// ridisegnare 1600 colonne trenta volte al secondo, per il solo gusto di
// spostare un confine di colore, è esattamente il genere di spreco che tiene
// sveglia una macchina. Un ritaglio invece non ridipinge niente: sposta un
// bordo, e lo fa la scheda video.
//
// La stessa ragione vale per il cursore e per la selezione: sono rettangoli,
// non pittura.
Item {
    id: onda

    /// I picchi, da 0 a 100. Ne arrivano più di quante colonne si disegnano:
    /// il condensamento lo fa questa, che è l'unica a sapere quanto è larga.
    property var barre: []
    /// Secondi in tutto.
    property real durata: 0
    /// Dove sta suonando, in secondi.
    property real posizione: 0

    /// Il pezzo scelto, in secondi. `fine <= inizio` vuol dire «niente scelto».
    property real inizio: 0
    property real fine: 0
    readonly property bool selezione: onda.fine > onda.inizio

    /// Larghezza del bersaglio delle maniglie. Generosa di proposito: prendere
    /// il bordo di una selezione è il gesto che si ripete di più, e due pixel
    /// di bersaglio lo rendono un gioco di mira.
    readonly property int presa: 10

    signal cercato(real secondi)
    signal selezionato(real da, real a)

    // ── Da secondi a pixel e ritorno ─────────────────────────────────────

    function x(sec) {
        if (onda.durata <= 0) return 0;
        return Math.max(0, Math.min(onda.width,
                        onda.width * (sec / onda.durata)));
    }

    function sec(px) {
        if (onda.durata <= 0 || onda.width <= 0) return 0;
        return Math.max(0, Math.min(onda.durata,
                        onda.durata * (px / onda.width)));
    }

    // ── Il disegno ───────────────────────────────────────────────────────
    //
    // `passo` è 2 pixel: una colonna e uno spazio. Più fitto diventa una
    // macchia grigia in cui non si distingue più niente, più largo diventa un
    // grafico a barre e si perde la forma.
    readonly property int passo: 2
    readonly property int colonne: Math.max(1, Math.floor(width / passo))

    /// Disegna l'onda in un colore solo. Ci sono due tele identiche, e
    /// cambia solo questo.
    function _dipingi(ctx, tinta) {
        ctx.reset();
        var w = onda.width, h = onda.height;
        ctx.clearRect(0, 0, w, h);
        var dati = onda.barre;
        if (!dati || dati.length === 0 || w <= 0 || h <= 0)
            return;

        var mezzo = h / 2;
        var n = onda.colonne;
        var perColonna = dati.length / n;

        ctx.fillStyle = tinta;
        for (var i = 0; i < n; i++) {
            // Il MASSIMO del gruppo, non la media: una media appiattisce i
            // colpi secchi — una grancassa dura venti millisecondi e in media
            // non esiste, ma è proprio quella che si cerca quando si taglia a
            // tempo.
            var da = Math.floor(i * perColonna);
            var a = Math.min(dati.length, Math.floor((i + 1) * perColonna));
            if (a <= da) a = da + 1;
            var picco = 0;
            for (var k = da; k < a; k++)
                if (dati[k] > picco) picco = dati[k];

            // Mezzo pixel di minimo: il silenzio deve restare una riga, non un
            // buco. Un'onda che si interrompe sembra un file rotto.
            var alt = Math.max(1, (picco / 100) * (mezzo - 2));
            ctx.fillRect(i * onda.passo, mezzo - alt, onda.passo - 1, alt * 2);
        }
    }

    // Lo sfondo del nastro. Sta sotto tutto, e serve a far capire dov'è il
    // bersaglio anche quando il file non è ancora stato letto.
    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
    }

    // La riga di mezzo: lo zero. Senza, un brano piano sembra vuoto invece
    // che piano.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: Theme.Colors.edge
    }

    Canvas {
        id: spenta
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: onda._dipingi(getContext("2d"), Theme.Colors.textFaint)
    }

    // La parte già suonata, accesa. È la stessa onda, ritagliata al cursore.
    Item {
        id: finestra
        height: parent.height
        width: onda.x(onda.posizione)
        clip: true

        Canvas {
            id: accesa
            width: onda.width
            height: onda.height
            renderStrategy: Canvas.Cooperative
            onPaint: onda._dipingi(getContext("2d"), Theme.Colors.accent)
        }
    }

    onBarreChanged: { spenta.requestPaint(); accesa.requestPaint(); }
    onWidthChanged: { spenta.requestPaint(); accesa.requestPaint(); }
    onHeightChanged: { spenta.requestPaint(); accesa.requestPaint(); }

    Connections {
        target: Theme.Colors
        function onAccentChanged() { accesa.requestPaint(); }
        function onSchemeChanged() { spenta.requestPaint(); accesa.requestPaint(); }
    }

    // ── Il pezzo scelto ──────────────────────────────────────────────────
    //
    // Il fuori si spegne invece di accendere il dentro. Sembra la stessa cosa
    // detta al contrario, e non lo è: velando quello che NON si porta via,
    // l'onda scelta resta col suo colore vero, e si continua a vedere la forma
    // di quello che si sta per salvare. Accendendo il dentro, invece, il pezzo
    // scelto diventerebbe l'unico posto in cui il disegno è alterato — cioè
    // proprio dove serve guardare bene.

    Rectangle {
        visible: onda.selezione
        x: 0
        width: onda.x(onda.inizio)
        height: parent.height
        color: Qt.alpha(Theme.Colors.base, 0.62)
    }

    Rectangle {
        visible: onda.selezione
        x: onda.x(onda.fine)
        width: parent.width - x
        height: parent.height
        color: Qt.alpha(Theme.Colors.base, 0.62)
    }

    // Le due maniglie. Sono spesse tre pixel ma si prendono da dieci: il
    // bersaglio è più grande di quello che si vede, come dev'essere.
    Repeater {
        model: onda.selezione ? 2 : 0

        Rectangle {
            required property int index
            readonly property real dove: index === 0 ? onda.inizio : onda.fine

            x: onda.x(dove) - (index === 0 ? 0 : 3)
            width: 3
            height: onda.height
            color: Theme.Colors.accentAlt

            // Il pomello, in mezzo all'altezza: dice che quella riga si
            // prende, invece di lasciarlo scoprire per caso.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: 26
                radius: 4
                color: Theme.Colors.accentAlt
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.base, 0.5)
            }
        }
    }

    // ── Il cursore ───────────────────────────────────────────────────────

    Rectangle {
        x: onda.x(onda.posizione) - 1
        width: 2
        height: parent.height
        color: Theme.Colors.text
        visible: onda.durata > 0

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: 9
            height: 9
            radius: 2
            rotation: 45
            color: Theme.Colors.text
        }
    }

    // ── Le mani ──────────────────────────────────────────────────────────
    //
    // Tre gesti su un solo tasto, e la regola che li separa è UNA: si guarda
    // dove si è premuto.
    //
    //   · sul bordo della selezione → si sposta quel bordo;
    //   · dentro la selezione       → si sposta tutto il pezzo;
    //   · fuori                     → si sceglie un pezzo nuovo.
    //
    // E un clic senza trascinamento non sceglie mai: porta la riproduzione lì.
    // È la distinzione che fa la differenza fra un nastro che si usa e uno che
    // ti cancella la selezione ogni volta che sbagli mira di due pixel.
    MouseArea {
        id: mani
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true

        property string modo: ""      // "inizio", "fine", "sposta", "nuovo"
        property real ancora: 0       // il capo fermo, in secondi
        property real presaDa: 0      // per lo spostamento: quanto dista dall'inizio
        property real partenzaX: 0
        property bool mosso: false

        function _quale(px) {
            if (!onda.selezione) return "nuovo";
            var xi = onda.x(onda.inizio), xf = onda.x(onda.fine);
            if (Math.abs(px - xi) <= onda.presa) return "inizio";
            if (Math.abs(px - xf) <= onda.presa) return "fine";
            if (px > xi && px < xf) return "sposta";
            return "nuovo";
        }

        cursorShape: {
            var q = mani.modo !== "" ? mani.modo : mani._quale(mani.mouseX);
            if (q === "inizio" || q === "fine") return Qt.SizeHorCursor;
            if (q === "sposta") return Qt.OpenHandCursor;
            return Qt.IBeamCursor;
        }

        onPressed: function (m) {
            mani.partenzaX = m.x;
            mani.mosso = false;
            mani.modo = mani._quale(m.x);
            if (mani.modo === "inizio")
                mani.ancora = onda.fine;
            else if (mani.modo === "fine")
                mani.ancora = onda.inizio;
            else if (mani.modo === "sposta")
                mani.presaDa = onda.sec(m.x) - onda.inizio;
            else
                mani.ancora = onda.sec(m.x);
        }

        onPositionChanged: function (m) {
            if (mani.modo === "") return;
            // Quattro pixel di soglia: sotto, è un clic con la mano che trema.
            if (!mani.mosso && Math.abs(m.x - mani.partenzaX) < 4) return;
            mani.mosso = true;

            if (mani.modo === "sposta") {
                var lungo = onda.fine - onda.inizio;
                var da = Math.max(0, Math.min(onda.durata - lungo,
                                              onda.sec(m.x) - mani.presaDa));
                onda.selezionato(da, da + lungo);
                return;
            }

            var qui = onda.sec(m.x);
            onda.selezionato(Math.min(mani.ancora, qui),
                             Math.max(mani.ancora, qui));
        }

        onReleased: function (m) {
            if (!mani.mosso && mani.modo !== "")
                onda.cercato(onda.sec(m.x));
            mani.modo = "";
        }

        // Il doppio clic sceglie tutto: è il gesto che serve quando si è
        // pasticciato e si vuole ricominciare da capo.
        onDoubleClicked: onda.selezionato(0, onda.durata)
    }
}
