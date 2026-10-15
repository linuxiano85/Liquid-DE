import QtQuick
import "../../windows11" as W

// Le specifiche non sono campi di modifica: rimangono selezionabili e
// copiabili, con etichette sopra ai valori quando la finestra si restringe.
Column {
    id: tabella
    property var righe: []
    property string prefisso: "specifica"
    width: parent.width
    spacing: 6
    topPadding: 12
    bottomPadding: 16
    Repeater {
        model: tabella.righe
        delegate: Item {
            id: riga
            required property var modelData
            readonly property bool stretta: width < 460
            width: tabella.width
            height: stretta ? etichetta.implicitHeight + valore.implicitHeight + 5 : Math.max(etichetta.implicitHeight, valore.implicitHeight)
            Text {
                id: etichetta
                x: 58
                width: riga.stretta ? parent.width-x-16 : 169
                text: riga.modelData.label
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: W.Style.font
                font.pixelSize: 14 * W.Style.textScale
                color: W.Style.text
            }
            TextEdit {
                id: valore
                objectName: tabella.prefisso + "-" + riga.modelData.key
                x: riga.stretta ? etichetta.x : etichetta.x+etichetta.width
                y: riga.stretta ? etichetta.implicitHeight + 5 : 0
                width: Math.max(1, parent.width-x-16)
                text: String(riga.modelData.value || "")
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                activeFocusOnTab: true
                wrapMode: TextEdit.Wrap
                font.family: W.Style.font
                font.pixelSize: 14 * W.Style.textScale
                color: W.Style.muted
                selectionColor: W.Style.accent
                selectedTextColor: W.Style.accentForeground
                Accessible.name: etichetta.text
            }
        }
    }
}
