import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// Tendina — Una scelta fra MOLTE alternative, mostrata chiusa.
//
// `ChoicePicker` mostra tutte le voci insieme, e per tre o quattro è la cosa
// giusta: si vede cosa c'è senza aprire niente. Con venti risoluzioni no:
// venti pulsanti per schermo, moltiplicati per due schermi, e la pagina
// Schermi diventava lunga quanto la stanza. Giacomo, 22 settembre 2026:
// «delle tendine per le risoluzioni e altre multi scelte».
//
// ── Com'è fatta ────────────────────────────────────────────────────────────
//
// Chiusa è un pulsante con la voce scelta e una freccina. Aperta, l'elenco
// non è un figlio di questo oggetto: sta sul `contentItem` della finestra,
// sopra tutto, altrimenti resterebbe ritagliato dalla riga che lo contiene
// e coperto dalla scheda sotto. Lo stesso trucco di `Ui.ToolTipHint`
// (`Window.window`). Un velo trasparente a tutta finestra sotto l'elenco
// chiude al primo clic fuori.
//
// Niente `QtQuick.Controls`: la shell disegna col processore e i suoi
// componenti sono `Rectangle` e `Text`, come tutto il resto delle
// Impostazioni. Tastiera: ↑/↓ scorrono, Invio sceglie, Esc chiude.
Item {
    id: tendina

    /// [{ value: "1920x1080", label: "1920 × 1080" }, …]
    property var options: []
    property string value: ""
    /// Quante voci si vedono senza scorrere.
    property int visibili: 8
    /// Cosa si legge quando `value` non è fra le opzioni.
    property string vuoto: "—"

    signal picked(string value)

    readonly property bool aperta: elenco.parent !== null && elenco.visible

    readonly property string etichetta: {
        for (var i = 0; i < tendina.options.length; i++)
            if (tendina.options[i].value === tendina.value)
                return tendina.options[i].label;
        return tendina.vuoto;
    }

    implicitWidth: parent ? parent.width : 220
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight

    Accessible.role: Accessible.ComboBox
    Accessible.name: tendina.etichetta

    // ── Il pulsante ──────────────────────────────────────────────────────
    Rectangle {
        id: bottone
        anchors.fill: parent
        radius: Theme.Effects.radiusSM
        color: tendina.aperta ? Qt.alpha(Theme.Colors.accent, 0.18)
             : (mouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised)
        border.width: 1
        border.color: tendina.aperta ? Theme.Colors.accent : Theme.Colors.edge
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: freccia.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: tendina.etichetta
            elide: Text.ElideRight
            color: tendina.aperta ? Theme.Colors.accent : Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }

        Ui.Icon {
            id: freccia
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron"
            width: 12; height: 12
            color: Theme.Colors.textMuted
            rotation: tendina.aperta ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.Motion.instant } }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tendina.aperta ? tendina.chiudi() : tendina.apri()
        }
    }

    function apri() {
        var finestra = tendina.Window.window;
        if (!finestra || tendina.options.length === 0)
            return;
        var radice = finestra.contentItem;
        velo.parent = radice;
        elenco.parent = radice;
        var p = tendina.mapToItem(null, 0, tendina.height + 4);
        var alto = Math.min(tendina.options.length, tendina.visibili) * 30 + 8;
        // Sotto se ci sta, altrimenti sopra: un elenco tagliato dal bordo
        // della finestra è un elenco che non si può usare.
        var sotto = p.y + alto <= finestra.height;
        elenco.x = Math.max(0, Math.min(p.x, finestra.width - elenco.width));
        elenco.y = sotto ? p.y : Math.max(0, p.y - tendina.height - 8 - alto);
        elenco.height = alto;
        var i = tendina.indiceDi(tendina.value);
        lista.currentIndex = i;
        if (i >= 0) lista.positionViewAtIndex(i, ListView.Center);
        velo.visible = true;
        elenco.visible = true;
        elenco.forceActiveFocus();
    }

    function chiudi() {
        elenco.visible = false;
        velo.visible = false;
        elenco.parent = null;
        velo.parent = null;
    }

    function indiceDi(v) {
        for (var i = 0; i < tendina.options.length; i++)
            if (tendina.options[i].value === v) return i;
        return -1;
    }

    function scegli(i) {
        if (i < 0 || i >= tendina.options.length) return;
        var v = tendina.options[i].value;
        tendina.chiudi();
        if (v !== tendina.value)
            tendina.picked(v);
    }

    // Se l'oggetto sparisce mentre è aperta (cambio pagina), l'elenco non
    // deve restare orfano sulla finestra.
    Component.onDestruction: tendina.chiudi()

    // ── Il velo, che chiude al clic fuori ────────────────────────────────
    MouseArea {
        id: velo
        parent: null
        visible: false
        anchors.fill: parent
        z: 9998
        onClicked: tendina.chiudi()
        onWheel: function (w) { w.accepted = true; }
    }

    // ── L'elenco ─────────────────────────────────────────────────────────
    Rectangle {
        id: elenco
        parent: null
        visible: false
        z: 9999
        width: Math.max(tendina.width, 160)
        radius: Theme.Effects.radiusMD
        // OPACO, e non una delle velature del tema: questo riquadro galleggia
        // sopra la pagina, e una velatura lascia leggere il testo che sta
        // sotto. Visto in fotografia il 22 settembre 2026 — «1280 × 720»
        // passava in mezzo alle percentuali. Si compone a mano la stessa
        // tinta di `raisedHigh` sopra il fondo della finestra.
        color: elenco.fondo

        /// Il fondo, con l'alfa forzata a uno: ogni tinta del tema è una
        /// VELATURA (`raisedHigh` è `velo(0.09)`), e una velatura qui lascia
        /// leggere quello che sta sotto. Si compone la stessa tinta e poi si
        /// butta via la trasparenza.
        readonly property color fondo: {
            var c = Qt.tint(Theme.Colors.base, Theme.Colors.raisedHigh);
            return Qt.rgba(c.r, c.g, c.b, 1.0);
        }
        border.width: 1
        border.color: Theme.Colors.edge
        focus: true

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape) { tendina.chiudi(); event.accepted = true; }
            else if (event.key === Qt.Key_Down) { lista.incrementCurrentIndex(); event.accepted = true; }
            else if (event.key === Qt.Key_Up) { lista.decrementCurrentIndex(); event.accepted = true; }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                tendina.scegli(lista.currentIndex); event.accepted = true;
            }
        }

        ListView {
            id: lista
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            model: tendina.options
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationWraps: false

            delegate: Rectangle {
                id: voce
                required property var modelData
                required property int index
                width: lista.width
                height: 30
                radius: Theme.Effects.radiusSM
                readonly property bool scelta: voce.modelData.value === tendina.value
                readonly property bool sotto: lista.currentIndex === voce.index
                color: sotto ? Theme.Colors.hover
                     : (scelta ? Qt.alpha(Theme.Colors.accent, 0.12) : "transparent")

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: voce.modelData.label
                    elide: Text.ElideRight
                    color: voce.scelta ? Theme.Colors.accent : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: voce.scelta ? Theme.Typography.weightMedium
                                             : Theme.Typography.weightRegular
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: lista.currentIndex = voce.index
                    onClicked: tendina.scegli(voce.index)
                }
            }
        }

        Ui.Scorrimento {
            bersaglio: lista
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 3
        }
    }
}
