import QtQuick
import "../theme" as Theme

/// La goccia: UN riquadro solo che scivola, con una molla, sotto la cosa
/// indicata — la voce sotto il puntatore, e quando il puntatore se ne va
/// quella scelta.
///
/// È il gesto liquido di Liquid DE applicato agli elenchi: invece di tante
/// voci che si accendono e si spengono ognuna per conto suo, c'è una goccia
/// che si sposta dall'una all'altra, si allunga quando cambia misura e si
/// posa superando di un soffio. Con le animazioni spente
/// (`Theme.Motion.liquido` falso) salta al posto giusto nello stesso
/// fotogramma.
///
/// Va messa nello STESSO genitore delle voci o in un loro antenato comune, e
/// prima di loro (sotto, nell'ordine di disegno). Le voci la informano:
///
///     onContainsMouseChanged: goccia.punta(voce, containsMouse)
///     attiva: goccia.attiva === voce      // o: goccia.attiva = voce
///
/// Niente shader e niente `layer`: il renderer software li farebbe sparire.
Rectangle {
    id: goccia

    /// La voce sotto il puntatore, se c'è.
    property Item puntata: null
    /// La voce scelta: la goccia ci torna quando il puntatore se ne va.
    property Item attiva: null
    /// Quanto la goccia è più piccola della voce, per lato.
    property real margine: 0

    readonly property Item bersaglio: goccia.puntata ? goccia.puntata : goccia.attiva

    /// Il puntatore entra o esce da una voce.
    function punta(voce, dentro) {
        if (dentro)
            goccia.puntata = voce;
        else if (goccia.puntata === voce)
            goccia.puntata = null;
    }

    color: Theme.Colors.hover
    radius: Theme.Effects.radiusSM
    opacity: goccia.bersaglio ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

    // Dove andare. Si ricalcola quando cambia il bersaglio, e quando il
    // bersaglio si sposta o cambia misura (una colonna che si ridispone, una
    // griglia che si allarga).
    property real _x: 0
    property real _y: 0
    property real _l: 0
    property real _a: 0
    /// Vero per il fotogramma in cui la goccia ricompare: nasce già al suo
    /// posto invece di scivolare da dove era sparita.
    property bool _salta: true

    function _misura() {
        var b = goccia.bersaglio;
        if (!b || !goccia.parent)
            return;
        var p = b.mapToItem(goccia.parent, 0, 0);
        goccia._x = p.x + goccia.margine;
        goccia._y = p.y + goccia.margine;
        goccia._l = Math.max(0, b.width - 2 * goccia.margine);
        goccia._a = Math.max(0, b.height - 2 * goccia.margine);
    }

    onBersaglioChanged: {
        if (!goccia.visible)
            goccia._salta = true;
        goccia._misura();
        goccia._salta = false;
    }
    Connections {
        target: goccia.bersaglio
        ignoreUnknownSignals: true
        function onXChanged() { goccia._misura(); }
        function onYChanged() { goccia._misura(); }
        function onWidthChanged() { goccia._misura(); }
        function onHeightChanged() { goccia._misura(); }
    }

    x: goccia._x
    y: goccia._y
    width: goccia._l
    height: goccia._a

    readonly property bool _molla: Theme.Motion.liquido && !goccia._salta
    Behavior on x {
        enabled: goccia._molla
        SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
    }
    Behavior on y {
        enabled: goccia._molla
        SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
    }
    Behavior on width {
        enabled: goccia._molla
        SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
    }
    Behavior on height {
        enabled: goccia._molla
        SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
    }
}
