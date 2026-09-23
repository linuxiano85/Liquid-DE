import QtQuick
import "../theme" as Theme

// Scorrimento — La barretta che dice dove sei, e che si può prendere.
//
// ── Perché questo file esiste ────────────────────────────────────────────
//
// Giacomo, 4 settembre 2026: «nel file manager manca la barretta laterale che
// posso trascinare con il mouse per spostare la discesa e slitta più
// velocemente». Contate quel giorno: in tutta la shell c'erano **tre** barre
// di scorrimento, ed erano quelle di serie di Qt, senza niente del nostro
// aspetto. Le altre venticinque superfici che scorrono — la griglia da 311
// file, i processi del monitor, i fusi orari, il testo dell'editor, tutte e
// diciotto le pagine delle Impostazioni — scorrevano **alla cieca**: non si
// sapeva dove si era, non si sapeva quanto mancava, e non c'era niente da
// afferrare per andare in fondo in un gesto.
//
// ── Le tre trappole, tutte già pagate altrove ────────────────────────────
//
// 1. **Si ancora FUORI dalla superficie che scorre, mai dentro.** I figli di
//    un Flickable stanno nel suo contenuto, che si sposta già di `-contentY`
//    per conto proprio: una barra messa lì dentro scorrerebbe via insieme a
//    ciò che dovrebbe misurare. La trappola è scritta per esteso in
//    `editor/Editor.qml:1103` — lì costò un contenuto che si muoveva il
//    doppio.
//
// 2. **`contentHeight` è una STIMA.** Un `ListView` con voci di altezza
//    diversa non sa quanto è alto finché non le ha costruite tutte, e non le
//    costruisce apposta (`spine/Spine.qml:184`). Quindi il pollice può
//    cambiare lunghezza mentre si scorre: è normale e non si combatte. Quello
//    che NON deve fare è saltare, e per questo la lunghezza si anima — ma
//    solo quando non la si sta trascinando.
//
// 3. **Niente effetti.** La shell disegna col processore, e lì `layer.effect`
//    e compagnia non danno errore: fanno sparire l'oggetto
//    (`minervad/test/disegno_senza_gpu_test.dart`). Due rettangoli con un
//    raggio, e basta.
//
// ── Come si usa ──────────────────────────────────────────────────────────
//
//     Flickable { id: rotolo; … }
//
//     Ui.Scorrimento {
//         bersaglio: rotolo
//         anchors { right: rotolo.right; top: rotolo.top; bottom: rotolo.bottom }
//     }
//
// Si ancora ai BORDI del Flickable — quelli stanno fermi — restando suo
// fratello e non suo figlio.
Item {
    id: barra

    /// La superficie che scorre: un `Flickable`, `ListView` o `GridView`.
    property Item bersaglio: null

    /// Orizzontale invece che verticale.
    property bool orizzontale: false

    /// Quanto è lunga la corsa, cioè quanto contenuto c'è oltre la finestra.
    /// Zero o meno vuol dire che ci sta tutto: allora la barra non serve e
    /// non si vede.
    readonly property real _corsa: {
        if (!barra.bersaglio)
            return 0;
        return barra.orizzontale
               ? barra.bersaglio.contentWidth - barra.bersaglio.width
               : barra.bersaglio.contentHeight - barra.bersaglio.height;
    }

    /// Dove siamo, da 0 a 1. Si tiene conto di `originY`/`originX`: un
    /// ListView che cresce anche verso l'alto — le notifiche, che vanno dal
    /// basso — non parte da zero.
    readonly property real _quota: {
        if (barra._corsa <= 0 || !barra.bersaglio)
            return 0;
        var dove = barra.orizzontale
                   ? barra.bersaglio.contentX - barra.bersaglio.originX
                   : barra.bersaglio.contentY - barra.bersaglio.originY;
        return Math.max(0, Math.min(1, dove / barra._corsa));
    }

    /// La lunghezza del pollice è la frazione visibile del contenuto, con un
    /// minimo: sotto i 32 pixel non si prende più con il mouse, e una barra
    /// che non si può afferrare è tornata a essere un disegno.
    readonly property real _lungo: {
        if (!barra.bersaglio || barra._corsa <= 0)
            return 0;
        var finestra = barra.orizzontale ? barra.bersaglio.width
                                         : barra.bersaglio.height;
        var tutto = barra.orizzontale ? barra.bersaglio.contentWidth
                                      : barra.bersaglio.contentHeight;
        var dentro = barra.orizzontale ? barra.width : barra.height;
        // ── Interi, non frazioni ─────────────────────────────────────────
        //
        // Col renderer software un rettangolo alto 87,3 pixel a y = 123,456
        // non si ridisegna pulito: quando si sposta o cambia lunghezza lascia
        // dietro una riga sottile, e la riga resta. Il pollice cambia tutte e
        // due le cose ogni volta che il contenuto cresce o si accorcia —
        // cambiando set di icone, per esempio — e quello che si vede è una
        // scaletta di trattini a mezz'aria.
        //
        // Segnalata da Giacomo il 4 e il 5 settembre 2026 come «tutti quei
        // segni + sovrapposti». Non erano segni: erano i resti del pollice.
        return Math.round(
            Math.max(32, Math.min(dentro, dentro * (finestra / tutto))));
    }

    readonly property bool _serve: barra._corsa > 0

    /// Vero mentre la si sta usando: il pollice si colora e la corsia
    /// compare.
    readonly property bool _inUso: presa.pressed || presa.containsMouse

    // La corsia è larga quanto una spaziatura del vocabolario, non quanto un
    // numero inventato: vedi la regola in cima a `theme/Effects.qml`.
    // Il lato LUNGO lo danno gli ancoraggi di chi la usa (in alto e in basso
    // per una verticale, a sinistra e a destra per una orizzontale); il lato
    // corto viene da qui. Non si assegna `width: undefined` per l'altro verso:
    // in QML non è «lascia stare», è un valore, e spegne il legame.
    implicitWidth: Theme.Effects.space3
    implicitHeight: Theme.Effects.space3

    visible: barra._serve
    // Non riserva spazio quando non serve: le superfici che la useranno sono
    // già disegnate senza, e una barra che compare non deve stringere il
    // contenuto.
    z: 10

    Accessible.role: Accessible.ScrollBar
    Accessible.name: qsTr("Barra di scorrimento")

    // ── La corsia ────────────────────────────────────────────────────────
    //
    // Si vede solo mentre la si usa. Una corsia sempre accesa su ogni lista
    // della scrivania è un tratto scuro in più su venticinque superfici, e la
    // scrivania diventa un modulo da compilare.
    Rectangle {
        id: corsia
        anchors.fill: parent
        // Metà del lato corto, non `radiusFull`: vedi il perché sul pollice.
        radius: Math.min(width, height) / 2
        color: Theme.Colors.sunken
        opacity: barra._inUso ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.Motion.instant }
        }
    }

    // ── Il pollice ───────────────────────────────────────────────────────
    Rectangle {
        id: pollice

        // ── Il raggio si CALCOLA, non si prende dal vocabolario ──────────
        //
        // Qui c'era `Theme.Effects.radiusFull`, che vale 999 ed è il modo di
        // dire «a capsula» in tutta la shell. Su un rettangolo di 6 pixel per
        // 87 non vuol dire niente, e col renderer software — che è quello
        // delle nostre finestre — non viene ridotto in silenzio: viene
        // disegnato, e quello che esce è una **scaletta di piccole croci**
        // lungo tutta la barra.
        //
        // Giacomo, 4 settembre 2026, un'ora dopo che avevo messo le barre
        // dappertutto: «cosa sono tutti quei segno + in impostazioni?». Erano
        // i pollici delle barre nuove.
        //
        // Metà del lato corto è la stessa forma — una capsula — detta in un
        // modo che regge a qualunque misura.
        radius: Math.min(width, height) / 2

        // A riposo è un filo, sotto il dito diventa una maniglia.
        readonly property int spessore: barra._inUso ? Theme.Effects.space2
                                                     : Theme.Effects.space2 - 2

        width: barra.orizzontale ? barra._lungo : spessore
        height: barra.orizzontale ? spessore : barra._lungo
        x: Math.round(barra.orizzontale
                      ? barra._quota * (barra.width - barra._lungo)
                      : (barra.width - width) / 2)
        y: Math.round(barra.orizzontale
                      ? (barra.height - height) / 2
                      : barra._quota * (barra.height - barra._lungo))

        // `velo()` e non un bianco scritto a mano: su un tema chiaro un velo
        // bianco non si vede, e la barra sparirebbe proprio dove serve di più.
        color: presa.pressed ? Theme.Colors.accent
             : presa.containsMouse ? Theme.Colors.velo(0.34)
                                   : Theme.Colors.velo(0.22)

        // Il colore si anima, la MISURA no. Animare la lunghezza del pollice
        // vuol dire ridisegnarlo a decine di misure intermedie, ognuna con il
        // suo raggio: col renderer software ognuna di quelle può lasciare il
        // suo resto. E non serviva a niente — la lunghezza cambia solo quando
        // cambia il contenuto, cioè quando l'utente non sta guardando lì.
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    // ── La presa ─────────────────────────────────────────────────────────
    //
    // Una sola, su tutta la corsia — non una sul pollice e una sulla pista.
    // Con due, il momento in cui il pollice passa sotto il puntatore mentre lo
    // si trascina cambia chi riceve gli eventi, e il trascinamento si spezza.
    MouseArea {
        id: presa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        preventStealing: true

        /// Da dove si è preso il pollice, in pixel dentro il pollice stesso.
        /// Serve perché il pollice non salti sotto il puntatore alla
        /// pressione: si prende dove lo si è preso.
        property real presoA: 0

        function _porta(p) {
            if (!barra.bersaglio || barra._corsa <= 0)
                return;
            var dentro = barra.orizzontale ? barra.width : barra.height;
            var libero = dentro - barra._lungo;
            if (libero <= 0)
                return;
            var f = Math.max(0, Math.min(1, (p - presa.presoA) / libero));
            if (barra.orizzontale)
                barra.bersaglio.contentX = barra.bersaglio.originX + f * barra._corsa;
            else
                barra.bersaglio.contentY = barra.bersaglio.originY + f * barra._corsa;
        }

        onPressed: function (m) {
            var p = barra.orizzontale ? m.x : m.y;
            var inizio = barra._quota * ((barra.orizzontale ? barra.width
                                                            : barra.height)
                                         - barra._lungo);
            if (p >= inizio && p <= inizio + barra._lungo) {
                // Si è premuto SUL pollice: si tiene il punto di presa.
                presa.presoA = p - inizio;
            } else {
                // Si è premuto sulla pista: il pollice ci va, centrato, e da
                // lì si può continuare a trascinare senza rilasciare.
                presa.presoA = barra._lungo / 2;
                presa._porta(p);
            }
        }

        onPositionChanged: function (m) {
            if (!presa.pressed)
                return;
            presa._porta(barra.orizzontale ? m.x : m.y);
        }

        // La rotellina sopra la barra scorre il contenuto, come sopra il
        // contenuto: la barra non è un buco nella superficie.
        onWheel: function (w) {
            if (!barra.bersaglio || barra._corsa <= 0)
                return;
            var passo = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
            var d = -passo / 120 * 60;
            if (barra.orizzontale) {
                barra.bersaglio.contentX = Math.max(
                    barra.bersaglio.originX,
                    Math.min(barra.bersaglio.originX + barra._corsa,
                             barra.bersaglio.contentX + d));
            } else {
                barra.bersaglio.contentY = Math.max(
                    barra.bersaglio.originY,
                    Math.min(barra.bersaglio.originY + barra._corsa,
                             barra.bersaglio.contentY + d));
            }
        }
    }
}
