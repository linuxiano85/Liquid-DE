import QtQuick
import "../../windows11" as W

// TendinaWindows — La ComboBox di Impostazioni di Windows 11: un pulsante
// con il testo scelto e la freccia; aperta, l'elenco si posa con la voce
// scelta sopra il pulsante, la voce scelta ha il fondo velato e la barretta
// d'accento, come in Windows (foto della macchina di riferimento).
//
// `voci`: [{ "valore": "riempi", "testo": "Riempi", "disponibile": true }].
// Una voce con `disponibile: false` si vede grigia e non si sceglie: è una
// cosa che Windows ha e Liquid non ancora.
Item {
    id: tendina

    property bool classica: false
    readonly property int dimensioneTesto: classica ? 12 : 14
    property var voci: []
    property string valore: ""
    property int evidenziata: -1
    signal scelto(string valore)

    readonly property int indice: {
        for (var i = 0; i < tendina.voci.length; i++)
            if (tendina.voci[i].valore === tendina.valore)
                return i;
        return -1;
    }
    readonly property string testo: tendina.indice >= 0 ? tendina.voci[tendina.indice].testo : ""
    readonly property bool aperta: elenco.visible

    implicitWidth: Math.max(120, misura.implicitWidth + 12 + 34)
    implicitHeight: 32
    width: implicitWidth
    height: implicitHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: tendina.testo
    Keys.onSpacePressed: tendina.apri()
    Keys.onReturnPressed: tendina.apri()
    Keys.onDownPressed: tendina.passo(1)
    Keys.onUpPressed: tendina.passo(-1)

    Text { id: misura; visible: false; font.family: W.Style.font; font.pixelSize: tendina.dimensioneTesto
           text: { var m = ""; for (var i = 0; i < tendina.voci.length; i++) if (tendina.voci[i].testo.length > m.length) m = tendina.voci[i].testo; return m; } }

    function estremo(ultimo) {
        var i = ultimo ? voci.length - 1 : 0;
        var step = ultimo ? -1 : 1;
        while (i >= 0 && i < voci.length) {
            if (voci[i].disponibile !== false) {
                evidenziata = i;
                return;
            }
            i += step;
        }
    }
    function sposta(d) {
        var i = evidenziata;
        for (var k = 0; k < voci.length; k++) {
            i = (i + d + voci.length) % voci.length;
            if (voci[i].disponibile !== false) {
                evidenziata = i;
                return;
            }
        }
    }
    function conferma() {
        if (evidenziata >= 0 && evidenziata < voci.length && voci[evidenziata].disponibile !== false) {
            var v = voci[evidenziata].valore;
            chiudi();
            if (v !== valore)
                scelto(v);
        }
    }
    function passo(d) {
        var i = tendina.indice;
        for (var k = 0; k < tendina.voci.length; k++) {
            i = (i + d + tendina.voci.length) % tendina.voci.length;
            if (tendina.voci[i].disponibile !== false) {
                tendina.scelto(tendina.voci[i].valore);
                return;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: tendina.classica ? 0 : 4
        color: presa.pressed ? W.Style.gettoni.controlFillSecondary
             : presa.containsMouse ? W.Style.gettoni.controlFillSecondary : W.Style.field
        border.width: 1
        border.color: W.Style.gettoni.controlStroke
        // La riga in basso un poco più scura, come i comandi WinUI.
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: 4; anchors.rightMargin: 4
            height: 1
            color: W.Style.dark ? "#30FFFFFF" : "#29000000"
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: 7
            color: "transparent"
            border.width: 2
            border.color: W.Style.text
            visible: tendina.activeFocus
        }
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: freccia.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: tendina.testo
        elide: Text.ElideRight
        color: W.Style.text
        font.family: W.Style.font
        font.pixelSize: tendina.dimensioneTesto
    }
    W.Glyph {
        id: freccia
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        name: "chevron"
        color: W.Style.muted
    }
    MouseArea {
        id: presa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tendina.apri()
    }

    function apri() {
        evidenziata = indice;
        var finestra = tendina.Window.window;
        if (!finestra || tendina.voci.length === 0)
            return;
        velo.parent = finestra.contentItem;
        elenco.parent = finestra.contentItem;
        var alto = tendina.voci.length * 36 + 8;
        var sel = Math.max(0, tendina.indice);
        var p = tendina.mapToItem(null, 0, 0);
        var y = p.y + tendina.height / 2 - (4 + sel * 36 + 18);
        elenco.y = Math.max(4, Math.min(y, finestra.height - alto - 4));
        elenco.x = Math.max(4, Math.min(p.x - 4, finestra.width - elenco.width - 4));
        elenco.height = alto;
        velo.visible = true;
        elenco.visible = true;
        elenco.forceActiveFocus();
    }
    function chiudi() {
        elenco.visible = false;
        velo.visible = false;
        tendina.forceActiveFocus();
    }
    Component.onDestruction: { elenco.visible = false; velo.visible = false; }

    MouseArea {
        id: velo
        parent: null
        visible: false
        anchors.fill: parent
        z: 9998
        onClicked: tendina.chiudi()
        onWheel: function (w) { w.accepted = true; }
    }

    Rectangle {
        id: elenco
        objectName: "tendinaWindowsElenco"
        parent: null
        visible: false
        z: 9999
        width: Math.max(tendina.width + 8, misura.implicitWidth + 48)
        radius: 8
        color: W.Style.dark ? "#2C2C2C" : "#F9F9F9"
        border.width: 1
        border.color: W.Style.gettoni.surfaceStrokeFlyout
        focus: true
        // Il popup prende il focus: deve gestire tutte le scelte anche
        // senza mouse, e restituirlo alla tendina dopo Invio o Esc.
        Keys.onEscapePressed: tendina.chiudi()
        Keys.onUpPressed: tendina.sposta(-1)
        Keys.onDownPressed: tendina.sposta(1)
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                tendina.estremo(event.key === Qt.Key_End);
                event.accepted = true;
            }
        }
        Keys.onReturnPressed: tendina.conferma()
        Keys.onSpacePressed: tendina.conferma()

        Column {
            x: 4
            y: 4
            width: parent.width - 8
            Repeater {
                model: tendina.voci
                delegate: Rectangle {
                    id: voce
                    required property var modelData
                    required property int index
                    readonly property bool scelta: modelData.valore === tendina.valore
                    readonly property bool usabile: modelData.disponibile !== false
                    objectName: "tendinaVoce-" + modelData.valore
                    width: parent.width
                    height: 36
                    radius: 4
                    color: (scelta || (elenco.activeFocus && index === tendina.evidenziata) || (presaVoce.containsMouse && usabile)) ? W.Style.hover : "transparent"
                    Rectangle {
                        visible: voce.scelta
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 16
                        radius: 1.5
                        color: W.Style.accent
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: voce.modelData.testo
                        color: voce.usabile ? W.Style.text : W.Style.faint
                        font.family: W.Style.font
                        font.pixelSize: tendina.dimensioneTesto
                    }
                    MouseArea {
                        id: presaVoce
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: voce.usabile
                        onClicked: {
                            var v = voce.modelData.valore;
                            tendina.chiudi();
                            if (v !== tendina.valore)
                                tendina.scelto(v);
                        }
                    }
                }
            }
        }
    }
}
