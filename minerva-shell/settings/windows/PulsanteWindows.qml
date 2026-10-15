import QtQuick
import "../../windows11" as W

// PulsanteWindows — Il pulsante normale di Impostazioni di Windows 11
// («Sfoglia le foto», «Visualizza colori», «Salva»): almeno 130 × 32, fondo
// dei comandi, filo di contorno con la riga in basso più scura. `accento`:
// il pulsante pieno del colore principale.
Rectangle {
    id: pulsante
    property string testo: ""
    property bool accento: false
    signal premuto()

    implicitWidth: Math.max(130, etichetta.implicitWidth + 24)
    implicitHeight: 32
    width: implicitWidth
    height: implicitHeight
    radius: 4
    color: pulsante.accento ? (presa.pressed ? Qt.darker(W.Style.accent, 1.1) : W.Style.accent)
         : (presa.pressed ? W.Style.gettoni.controlFillSecondary
            : presa.containsMouse ? W.Style.gettoni.controlFillSecondary : W.Style.field)
    border.width: pulsante.accento ? 0 : 1
    border.color: W.Style.gettoni.controlStroke
    opacity: pulsante.enabled ? 1 : 0.5
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: pulsante.testo
    // Un tasto tenuto premuto non deve confermare anche il secondo passo
    // di un ripristino né inviare richieste ripetute al servizio.
    Keys.onReturnPressed: function(event) { if (!event.isAutoRepeat) pulsante.premuto(); }
    Keys.onSpacePressed: function(event) { if (!event.isAutoRepeat) pulsante.premuto(); }

    Rectangle {
        visible: !pulsante.accento
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 4; anchors.rightMargin: 4
        height: 1
        color: W.Style.dark ? "#30FFFFFF" : "#29000000"
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: -3; radius: 7
        color: "transparent"; border.width: 2; border.color: W.Style.text
        visible: pulsante.activeFocus
    }
    Text {
        id: etichetta
        anchors.centerIn: parent
        text: pulsante.testo
        color: pulsante.accento ? W.Style.accentForeground : W.Style.text
        font.family: W.Style.font
        font.pixelSize: 14
    }
    MouseArea {
        id: presa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pulsante.premuto()
    }
}
