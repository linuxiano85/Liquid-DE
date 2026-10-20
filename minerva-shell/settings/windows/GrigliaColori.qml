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

    readonly property int colonne: Math.max(1, Math.floor((width + spacing) / (50 + spacing)))
    function sposta(indice) {
        var item = celle.itemAt(Math.max(0, Math.min(celle.count - 1, indice)));
        if (item) item.forceActiveFocus(Qt.TabFocusReason);
    }

    Repeater {
        id: celle
        model: griglia.colori
        delegate: Rectangle {
            id: quadro
            required property var modelData
            required property int index
            readonly property bool attuale: String(modelData[0]).toUpperCase() === String(griglia.scelto).toUpperCase()
            objectName: "colore-" + String(modelData[0]).substring(1).toUpperCase()
            width: Math.min(50, griglia.width)
            height: 50
            radius: 4
            color: modelData[0]
            border.width: quadro.attuale || activeFocus ? 2 : (presa.containsMouse ? 1 : 0)
            border.color: activeFocus ? W.Style.accent : W.Style.text
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData[1]
            Accessible.checkable: true
            Accessible.checked: quadro.attuale
            Accessible.onPressAction: griglia.preso(modelData[0])
            Accessible.onToggleAction: griglia.preso(modelData[0])
            Keys.onReturnPressed: function(event) { if (!event.isAutoRepeat) griglia.preso(modelData[0]); }
            Keys.onSpacePressed: function(event) { if (!event.isAutoRepeat) griglia.preso(modelData[0]); }
            Keys.onLeftPressed: griglia.sposta(index - 1)
            Keys.onRightPressed: griglia.sposta(index + 1)
            Keys.onUpPressed: griglia.sposta(index - griglia.colonne)
            Keys.onDownPressed: griglia.sposta(index + griglia.colonne)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Home) {
                    griglia.sposta(0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    griglia.sposta(celle.count - 1);
                    event.accepted = true;
                }
            }

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
                onClicked: {
                    quadro.forceActiveFocus(Qt.MouseFocusReason);
                    griglia.preso(quadro.modelData[0]);
                }
            }
        }
    }
}
