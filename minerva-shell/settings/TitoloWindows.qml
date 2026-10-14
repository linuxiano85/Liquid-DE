import QtQuick
import "../windows11" as W
import "../core" as Core
import "windows/Dati.js" as Dati

Item {
    id: titolo
    property var finestra: null
    height: 48
    readonly property bool puoTornare: !!finestra && finestra.puoTornare

    // Misure lette dall'albero UIA della VM: ricerca a y=8, 516×32;
    // Indietro a (4,6), 40×36. Il campo Liquid aggiungeva un secondo bordo.
    W.Button {
        objectName: "indietroWindows"
        x: 4
        y: 6
        width: 40
        height: 36
        icon: "back"
        enabled: titolo.puoTornare
        tooltip: Dati.t(Core.Strings.lang, "indietro")
        foreground: enabled ? W.Style.text : W.Style.faint
        onClicked: titolo.finestra.indietro()
    }
    Text {
        objectName: "etichettaImpostazioniWindows"
        x: 50
        y: 16
        text: Dati.t(Core.Strings.lang, "impostazioni")
        textFormat: Text.PlainText
        color: W.Style.text
        font.family: W.Style.font
        font.pixelSize: 12
    }
    Rectangle {
        id: cerca
        objectName: "cercaWindows"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: Math.max(0, Math.min(516, parent.width - 400))
        height: 32
        visible: width > 0
        radius: height / 2
        color: W.Style.dark ? "#2D2D2D" : "#FFFFFF"
        border.width: 1
        border.color: W.Style.gettoni.controlStroke
        W.Glyph {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            name: "search"
            color: W.Style.muted
        }
        Text {
            anchors.fill: campo
            verticalAlignment: Text.AlignVCenter
            text: Dati.t(Core.Strings.lang, "cerca")
            textFormat: Text.PlainText
            visible: campo.text === ""
            color: W.Style.muted
            font: campo.font
            elide: Text.ElideRight
        }
        TextInput {
            id: campo
            objectName: "ricercaWindows"
            anchors.left: parent.left
            anchors.leftMargin: 34
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            text: titolo.finestra ? titolo.finestra.ricerca : ""
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 12
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            activeFocusOnTab: true
            selectionColor: W.Style.accent
            selectedTextColor: W.Style.accentForeground
            Accessible.role: Accessible.EditableText
            Accessible.name: Dati.t(Core.Strings.lang, "cerca")
            onTextChanged: {
                if (titolo.finestra && titolo.finestra.ricerca !== text)
                    titolo.finestra.ricerca = text;
            }
            Keys.onEscapePressed: if (titolo.finestra) titolo.finestra.ricerca = ""
        }
    }
}
