import QtQuick
import "../../windows11" as W

// Lo stato resta legato al demone anche dopo un clic: il controllo chiede
// il cambiamento, senza sostituire il binding con un valore locale.
Item {
    id: casella
    property string testo: ""
    readonly property string titolo: testo
    property bool searchHighlighted: false
    property bool checked: false
    signal scelta(bool value)
    width: parent ? parent.width : implicitWidth
    implicitWidth: etichetta.implicitWidth + 32
    implicitHeight: Math.max(24, etichetta.implicitHeight)
    height: implicitHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: testo
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: if (casella.enabled) casella.scelta(!casella.checked)
    Keys.onSpacePressed: casella.scelta(!casella.checked)
    Keys.onReturnPressed: casella.scelta(!casella.checked)
    opacity: enabled ? 1 : 0.5
    Rectangle {
        id: quadrato
        width: 20
        height: 20
        y: (parent.height-height)/2
        radius: 3
        color: casella.checked ? W.Style.accent : presa.containsMouse ? W.Style.hover : "transparent"
        border.width: casella.checked ? 0 : 1
        border.color: W.Style.muted
        Text {
            anchors.centerIn: parent
            text: "✓"
            font.family: W.Style.font
            font.pixelSize: 16
            font.bold: true
            color: W.Style.accentForeground
            visible: casella.checked
        }
    }
    Text {
        id: etichetta
        x: 32
        width: parent.width-x
        anchors.verticalCenter: parent.verticalCenter
        text: casella.testo
        wrapMode: Text.Wrap
        font.family: W.Style.font
        font.pixelSize: 14
        color: W.Style.text
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        color: "transparent"
        border.width: casella.activeFocus || casella.searchHighlighted ? 2 : 0
        border.color: casella.searchHighlighted ? W.Style.accent : W.Style.text
        radius: 3
    }
    MouseArea {
        id: presa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            casella.forceActiveFocus();
            casella.scelta(!casella.checked);
        }
    }
}
