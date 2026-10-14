import QtQuick
import "../../windows11" as W

// GrigliaColori — I quadratini dei colori di Impostazioni di Windows 11
// (Colori di Windows, Colori recenti, la tinta unita dello sfondo): 50 × 50,
// 3 px fra l'uno e l'altro, angoli da 4. Quello scelto ha il contorno del
// colore del testo e, in alto a destra, il riquadro con la spunta.
//
// `colori`: [["#0078D4", "Blu"], ...]; `scelto`: "#0078D4".
Flow {
    id: griglia
    property var colori: []
    property string scelto: ""
    signal preso(string colore)
    spacing: 3

    Repeater {
        model: griglia.colori
        delegate: Rectangle {
            id: quadro
            required property var modelData
            readonly property bool attuale: String(modelData[0]).toUpperCase() === String(griglia.scelto).toUpperCase()
            objectName: "colore-" + String(modelData[0]).substring(1).toUpperCase()
            width: 50
            height: 50
            radius: 4
            color: modelData[0]
            border.width: quadro.attuale ? 2 : (presa.containsMouse ? 1 : 0)
            border.color: W.Style.text
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData[1]
            Accessible.checked: quadro.attuale
            Keys.onReturnPressed: griglia.preso(modelData[0])
            Keys.onSpacePressed: griglia.preso(modelData[0])

            // Lo stacco bianco dentro il contorno di quello scelto.
            Rectangle {
                visible: quadro.attuale
                anchors.fill: parent
                anchors.margins: 2
                radius: 2
                color: "transparent"
                border.width: 1
                border.color: W.Style.dark ? "#000000" : "#FFFFFF"
            }
            Rectangle {
                visible: quadro.attuale
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 2
                width: 18
                height: 18
                color: W.Style.text
                W.Glyph {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    name: "check"
                    color: W.Style.dark ? "#000000" : "#FFFFFF"
                }
            }
            MouseArea {
                id: presa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: griglia.preso(quadro.modelData[0])
            }
        }
    }
}
