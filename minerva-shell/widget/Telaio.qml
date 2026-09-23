import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Telaio — La cornice di un widget: dove sta, quanto è grande, come si prende.
//
// ── Le posizioni si salvano in FRAZIONI, non in pixel ──────────────────────
//
// Un widget messo a x=1600 su uno schermo da 1920 sparisce il giorno che
// colleghi un monitor da 1366, e si accavalla con gli altri il giorno che ne
// stacchi uno. Salvato come «l'83 % della larghezza» resta dov'era, su
// qualunque schermo.
//
// È un difetto che si vede solo con due schermi, cioè tardi e lontano dalla
// causa. Costa una divisione adesso.
//
// ── E la misura minima non è prudenza ──────────────────────────────────────
//
// Sotto una certa misura un widget non mostra più il suo numero: mostra un
// numero tagliato, che è peggio di non mostrarlo. Il minimo sta qui e non nel
// widget, o ogni widget nuovo se lo dovrebbe ricordare.
Item {
    id: telaio

    /// Chi è: serve a ritrovarlo nell'elenco salvato.
    required property string identificativo
    /// Che cosa mostra: `processore`, `memoria`, `rete`…
    required property string tipo

    /// Dove sta e quanto è grande, in frazioni dello schermo (0…1).
    property real fx: 0.05
    property real fy: 0.1
    property real fw: 0.16
    property real fh: 0.12

    /// Bloccato: non si prende, non si sposta, non si toglie.
    property bool bloccato: true

    /// ── Con o senza vetro ───────────────────────────────────────────────
    ///
    /// Giacomo, 9 settembre 2026: «voglio poterli avere anche trasparenti e
    /// vedere solo i numeri o grafici senza cornice o vetro perché metti caso
    /// che voglio poter vedere lo sfondo come faccio?».
    ///
    /// Ha ragione: uno sfondo si sceglie per guardarlo, e sei rettangoli
    /// opachi sopra sono sei buchi. Nudo restano i numeri e basta.
    ///
    /// Il prezzo è la leggibilità, e non si finge che non ci sia: senza vetro
    /// dietro, un numero chiaro su una fotografia chiara sparisce. Nudo il
    /// testo si ORLA — `Text.Outline` col colore opposto, che è raster puro e
    /// funziona anche col renderer software, dove uno shader non si
    /// disegnerebbe affatto.
    property bool nudo: false

    /// Chiesto di essere tolto dalla scrivania.
    signal tolto()
    /// Spostato o ridimensionato: chi ascolta salva.
    signal sistemato(real fx, real fy, real fw, real fh)

    /// ── Il tasto destro apre un menù, non cancella ──────────────────────
    ///
    /// Fino a stasera il tasto destro su un widget lo TOGLIEVA, e basta. Era
    /// sbagliato per due ragioni diverse: in tutta Minerva il tasto destro
    /// apre un menù — sulla scrivania, sulla barra, sulle icone, nella dock —
    /// e in nessun altro posto distrugge qualcosa al primo colpo; e un gesto
    /// che si può fare per sbaglio mentre si trascina non può essere quello
    /// che cancella.
    signal menuChiesto(real x, real y)

    /// Mentre si trascina, la riga a cui ci si sta agganciando (−1 nessuna).
    /// Chi ascolta la disegna: una riga dentro un widget largo centoventi
    /// pixel non si vedrebbe, e serve proprio a dire «sei allineato con
    /// QUELLO là in fondo».
    signal guida(real x, real y)

    /// Il lato minimo, in pixel. Sotto, il numero non ci sta.
    readonly property int minimoLargo: 120
    readonly property int minimoAlto: 84

    x: Math.round(telaio.fx * parent.width)
    y: Math.round(telaio.fy * parent.height)
    width: Math.max(telaio.minimoLargo, Math.round(telaio.fw * parent.width))
    height: Math.max(telaio.minimoAlto, Math.round(telaio.fh * parent.height))

    /// Dove sta il contenuto. Chi usa il telaio ci mette dentro il suo widget.
    default property alias contenuto: dentro.data

    // ── Il vetro ─────────────────────────────────────────────────────────
    //
    // La stessa membrana della barra e della dock, e non per simmetria: è la
    // superficie di Minerva, e un widget di un'altra tinta sarebbe un oggetto
    // appoggiato sulla scrivania invece che una parte di lei.
    //
    // Dietro, quando il compositore fa il blur, c'è la sfocatura vera — vedi
    // `WidgetLayer.qml`. È la ragione per cui questo rettangolo può
    // permettersi di essere traslucido senza diventare illeggibile su una
    // fotografia chiara: il conto è quello di stasera, 0,50 → 10,2:1.
    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusLG
        color: telaio.nudo ? "transparent" : Theme.Colors.membrane
        // Nudo il bordo si vede solo mentre lo si sta spostando: sbloccato
        // bisogna sapere dove finisce quello che si sta prendendo, bloccato
        // no — quello è il momento in cui deve sembrare parte dello sfondo.
        border.width: telaio.nudo && telaio.bloccato ? 0 : 1
        border.color: telaio.bloccato ? Theme.Colors.edge
                                      : Theme.Colors.accent

        Item {
            id: dentro
            anchors.fill: parent
            anchors.margins: telaio.nudo ? 2 : Theme.Effects.space3
        }
    }

    // ── Da qui in giù esiste solo da SBLOCCATO ───────────────────────────
    //
    // Non `enabled: false` su un oggetto che resta: `visible: false` lo toglie
    // davvero dall'albero del puntatore. E comunque, bloccati, tutta la
    // superficie non ha zone sensibili (`mask: Region {}` in `WidgetLayer`):
    // questa è la seconda rete, per il caso in cui un widget venga usato
    // altrove.

    // ── I bordi: si ridimensiona da tutti e quattro, come una finestra ─────
    //
    // Giacomo, 14 settembre 2026: «non sono ridimensionabili quando siamo in
    // modalità modifica». C'era una maniglia sola, sedici pixel nell'angolo
    // in basso a destra, e non la trovava nessuno: chi vuole allargare una
    // cosa tira il suo bordo, come fa con ogni finestra. La maniglia resta,
    // come segno che si può; i bordi fanno il lavoro.
    //
    // Dichiarata PRIMA di `presa`, quindi sotto: `presa` ha dieci pixel di
    // margine e lascia proprio questa banda scoperta.
    MouseArea {
        id: bordi
        anchors.fill: parent
        visible: !telaio.bloccato
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        readonly property int banda: 10

        /// Quali lati sotto il puntatore: `l`, `r`, `t`, `b` come lettere
        /// in una stringa. Vuota: nessuno (siamo dentro).
        function lati(x, y) {
            var s = "";
            if (x < banda) s += "l";
            else if (x > width - banda) s += "r";
            if (y < banda) s += "t";
            else if (y > height - banda) s += "b";
            return s;
        }

        property string presi: ""
        property real presoX: 0
        property real presoY: 0
        property int x0: 0
        property int y0: 0
        property int w0: 0
        property int h0: 0

        cursorShape: {
            var s = bordi.pressed ? bordi.presi : bordi.lati(bordi.mouseX, bordi.mouseY);
            if (s === "lt" || s === "rb") return Qt.SizeFDiagCursor;
            if (s === "rt" || s === "lb") return Qt.SizeBDiagCursor;
            if (s === "l" || s === "r") return Qt.SizeHorCursor;
            if (s === "t" || s === "b") return Qt.SizeVerCursor;
            return Qt.ArrowCursor;
        }

        onPressed: function (mouse) {
            bordi.presi = bordi.lati(mouse.x, mouse.y);
            if (bordi.presi === "") { mouse.accepted = false; return; }
            var g = bordi.mapToItem(telaio.parent, mouse.x, mouse.y);
            bordi.presoX = g.x; bordi.presoY = g.y;
            bordi.x0 = telaio.x; bordi.y0 = telaio.y;
            bordi.w0 = telaio.width; bordi.h0 = telaio.height;
        }

        onPositionChanged: function (mouse) {
            if (!bordi.pressed || bordi.presi === "")
                return;
            var g = bordi.mapToItem(telaio.parent, mouse.x, mouse.y);
            var dx = g.x - bordi.presoX;
            var dy = g.y - bordi.presoY;
            var nx = bordi.x0, ny = bordi.y0, nw = bordi.w0, nh = bordi.h0;
            var s = bordi.presi;
            // Si parte SEMPRE dal rettangolo di quando si è premuto, non da
            // quello di adesso: sommando gli spostamenti a ogni evento gli
            // arrotondamenti si accumulano e il bordo scivola.
            if (s.indexOf("l") !== -1) { nx = bordi.x0 + dx; nw = bordi.w0 - dx; }
            if (s.indexOf("r") !== -1) { nw = bordi.w0 + dx; }
            if (s.indexOf("t") !== -1) { ny = bordi.y0 + dy; nh = bordi.h0 - dy; }
            if (s.indexOf("b") !== -1) { nh = bordi.h0 + dy; }

            // I minimi, tenendo fermo il lato che non si sta tirando.
            if (nw < telaio.minimoLargo) {
                if (s.indexOf("l") !== -1) nx = bordi.x0 + bordi.w0 - telaio.minimoLargo;
                nw = telaio.minimoLargo;
            }
            if (nh < telaio.minimoAlto) {
                if (s.indexOf("t") !== -1) ny = bordi.y0 + bordi.h0 - telaio.minimoAlto;
                nh = telaio.minimoAlto;
            }
            // Dentro lo schermo.
            if (nx < 0) { nw += nx; nx = 0; }
            if (ny < 0) { nh += ny; ny = 0; }
            if (nx + nw > telaio.parent.width) nw = telaio.parent.width - nx;
            if (ny + nh > telaio.parent.height) nh = telaio.parent.height - ny;

            // L'aggancio, sul lato che si muove.
            var gx = -1, gy = -1;
            if (s.indexOf("l") !== -1) {
                var al = telaio.lato(nx, true);
                if (al.riga >= 0 && nx + nw - al.dove >= telaio.minimoLargo) { nw = nx + nw - al.dove; nx = al.dove; gx = al.riga; }
            } else if (s.indexOf("r") !== -1) {
                var ar = telaio.lato(nx + nw, true);
                if (ar.riga >= 0 && ar.dove - nx >= telaio.minimoLargo) { nw = ar.dove - nx; gx = ar.riga; }
            }
            if (s.indexOf("t") !== -1) {
                var at = telaio.lato(ny, false);
                if (at.riga >= 0 && ny + nh - at.dove >= telaio.minimoAlto) { nh = ny + nh - at.dove; ny = at.dove; gy = at.riga; }
            } else if (s.indexOf("b") !== -1) {
                var ab = telaio.lato(ny + nh, false);
                if (ab.riga >= 0 && ab.dove - ny >= telaio.minimoAlto) { nh = ab.dove - ny; gy = ab.riga; }
            }

            telaio.x = Math.round(nx); telaio.y = Math.round(ny);
            telaio.width = Math.round(nw); telaio.height = Math.round(nh);
            telaio.guida(gx, gy);
        }

        onReleased: {
            if (bordi.presi === "") return;
            bordi.presi = "";
            telaio.guida(-1, -1);
            telaio.salva();
        }
        onCanceled: { bordi.presi = ""; telaio.guida(-1, -1); }
    }

    MouseArea {
        id: presa
        anchors.fill: parent
        anchors.margins: 10
        visible: !telaio.bloccato
        cursorShape: Qt.SizeAllCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real presoX: 0
        property real presoY: 0

        onPressed: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                var g = presa.mapToItem(telaio.parent, mouse.x, mouse.y);
                telaio.menuChiesto(g.x, g.y);
                return;
            }
            presa.presoX = mouse.x;
            presa.presoY = mouse.y;
        }

        onPositionChanged: function (mouse) {
            if (!presa.pressed || presa.pressedButtons !== Qt.LeftButton)
                return;
            var nx = telaio.x + (mouse.x - presa.presoX);
            var ny = telaio.y + (mouse.y - presa.presoY);
            // Dentro lo schermo, sempre: un widget trascinato fuori non si
            // riprende più, perché per riprenderlo bisognerebbe cliccarci.
            nx = Math.max(0, Math.min(telaio.parent.width - telaio.width, nx));
            ny = Math.max(0, Math.min(telaio.parent.height - telaio.height, ny));

            // L'aggancio. Vedi `magnete()` più sotto.
            var ax = telaio.magnete(nx, nx + telaio.width, true);
            var ay = telaio.magnete(ny, ny + telaio.height, false);
            // L'aggancio può spingere fuori di dieci pixel: si ritaglia dopo,
            // o il widget agganciato al bordo destro esce di quel tanto.
            telaio.x = Math.max(0, Math.min(telaio.parent.width - telaio.width,
                                            ax.dove));
            telaio.y = Math.max(0, Math.min(telaio.parent.height - telaio.height,
                                            ay.dove));
            telaio.guida(ax.riga, ay.riga);
        }

        onReleased: {
            telaio.guida(-1, -1);
            telaio.salva();
        }
        onCanceled: telaio.guida(-1, -1)
    }

    // ── La maniglia per la misura ────────────────────────────────────────
    //
    // Resta come SEGNO: dice «questo si può ridimensionare» a chi guarda.
    // Il lavoro lo fanno i bordi, qui sopra — la maniglia da sola nessuno la
    // trovava (14 settembre 2026).
    Rectangle {
        id: maniglia
        visible: !telaio.bloccato
        width: 16
        height: 16
        radius: 4
        color: misura.pressed ? Theme.Colors.accent : Theme.Colors.raisedHigh
        border.width: 1
        border.color: Theme.Colors.edge
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 2

        MouseArea {
            id: misura
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.SizeFDiagCursor

            property real presoX: 0
            property real presoY: 0

            onPressed: function (mouse) {
                misura.presoX = mouse.x;
                misura.presoY = mouse.y;
            }
            onPositionChanged: function (mouse) {
                if (!misura.pressed)
                    return;
                var nw = telaio.width + (mouse.x - misura.presoX);
                var nh = telaio.height + (mouse.y - misura.presoY);
                nw = Math.max(telaio.minimoLargo,
                              Math.min(telaio.parent.width - telaio.x, nw));
                nh = Math.max(telaio.minimoAlto,
                              Math.min(telaio.parent.height - telaio.y, nh));

                // Anche la misura si aggancia, e allo stesso elenco di righe:
                // due widget affiancati che finiscono alla stessa altezza
                // sono la cosa che si vuole, ed è impossibile a mano. Qui si
                // muove solo il lato destro (e quello basso), quindi si
                // aggancia quello: il sinistro è fermo per definizione.
                var ax = telaio.lato(telaio.x + nw, true);
                var ay = telaio.lato(telaio.y + nh, false);
                if (ax.riga >= 0)
                    nw = Math.max(telaio.minimoLargo, ax.dove - telaio.x);
                if (ay.riga >= 0)
                    nh = Math.max(telaio.minimoAlto, ay.dove - telaio.y);

                telaio.width = nw;
                telaio.height = nh;
                telaio.guida(ax.riga, ay.riga);
            }
            onReleased: {
                telaio.guida(-1, -1);
                telaio.salva();
            }
            onCanceled: telaio.guida(-1, -1)
        }
    }

    // ── L'aggancio ───────────────────────────────────────────────────────
    //
    // Due widget messi a occhio non saranno mai allineati, e la differenza
    // di tre pixel si vede benissimo senza che si capisca cosa non va. Con
    // l'aggancio si allineano da soli, e la riga che compare dice a COSA:
    // senza quella, un widget che «salta» sembra un difetto.
    //
    // Le righe a cui ci si aggancia sono tre famiglie, in quest'ordine di
    // importanza: i bordi dello schermo (con il margine di rispetto), la sua
    // mezzeria, e i bordi e le mezzerie degli ALTRI widget. Non una griglia
    // fissa: una griglia allinea alle sue righe, non alle cose che ci sono.
    //
    // Il margine di rispetto è lo stesso `space6` che tiene le finestre
    // lontane dal bordo: un widget incollato allo spigolo sembra caduto lì.

    /// Quanto vicino bisogna arrivare perché scatti. Dieci pixel: sotto non
    /// si riesce a prenderlo apposta, sopra si aggancia quando non vuoi.
    readonly property int _presa: 10

    /// Il margine dal bordo dello schermo.
    readonly property int _riparo: Theme.Effects.space6

    /// Le righe candidate su un asse. `orizzontale` vero = le ics.
    function _righe(orizzontale) {
        var l = [];
        var quanto = orizzontale ? telaio.parent.width : telaio.parent.height;
        l.push(telaio._riparo);
        l.push(quanto - telaio._riparo);
        l.push(quanto / 2);

        // Gli altri widget: i fratelli dentro lo stesso contenitore. Si
        // riconoscono dall'avere un `identificativo`, che è di questo tipo e
        // di nessun altro — e non dal `objectName`, che nessuno riempie.
        var f = telaio.parent.children;
        for (var i = 0; i < f.length; i++) {
            var v = f[i];
            if (v === telaio || v.identificativo === undefined || !v.visible)
                continue;
            if (orizzontale) {
                l.push(v.x);
                l.push(v.x + v.width);
                l.push(v.x + v.width / 2);
            } else {
                l.push(v.y);
                l.push(v.y + v.height);
                l.push(v.y + v.height / 2);
            }
        }
        return l;
    }

    /// Dato il lato iniziale e finale su un asse, restituisce dove mettersi e
    /// quale riga ha fatto scattare l'aggancio (−1 se nessuna).
    ///
    /// Si prova ad agganciare TRE punti — il bordo iniziale, quello finale e
    /// la mezzeria — perché allineare due widget di larghezza diversa per il
    /// centro è un allineamento vero quanto allinearli per il bordo.
    function magnete(inizio, fine, orizzontale) {
        var righe = telaio._righe(orizzontale);
        var mezzo = (inizio + fine) / 2;
        var lati = [inizio, fine, mezzo];
        var meglio = telaio._presa + 1;
        var dove = inizio;
        var riga = -1;

        for (var i = 0; i < righe.length; i++) {
            for (var k = 0; k < lati.length; k++) {
                var d = Math.abs(lati[k] - righe[i]);
                if (d >= meglio)
                    continue;
                meglio = d;
                riga = righe[i];
                dove = inizio + (righe[i] - lati[k]);
            }
        }
        if (riga < 0)
            return { "dove": inizio, "riga": -1 };
        return { "dove": Math.round(dove), "riga": riga };
    }

    /// Un lato solo, per la maniglia della misura.
    function lato(dove, orizzontale) {
        var righe = telaio._righe(orizzontale);
        var meglio = telaio._presa + 1;
        var riga = -1;
        for (var i = 0; i < righe.length; i++) {
            var d = Math.abs(dove - righe[i]);
            if (d < meglio) {
                meglio = d;
                riga = righe[i];
            }
        }
        return { "dove": riga < 0 ? dove : Math.round(riga), "riga": riga };
    }

    function salva() {
        if (telaio.parent.width <= 0 || telaio.parent.height <= 0)
            return;
        telaio.sistemato(telaio.x / telaio.parent.width,
                         telaio.y / telaio.parent.height,
                         telaio.width / telaio.parent.width,
                         telaio.height / telaio.parent.height);
    }
}
