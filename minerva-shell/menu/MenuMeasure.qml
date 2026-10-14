import QtQuick
import "../theme" as Theme
import "../windows11" as Windows11

// Lo stesso Text che disegna la voce ne misura l'ingombro: evita differenze
// di arrotondamento dei FontMetrics e permette a ogni colonna di adattarsi.
Item {
    id: measure
    property var items: []
    property bool windowsAppearance: false
    property int revision: 0
    readonly property real piuLarga: {
        var revision = measure.revision;
        var width = 0;
        for (var i = 0; i < rows.count; i++) {
            var row = rows.itemAt(i);
            if (row)
                width = Math.max(width, row.quanto);
        }
        return width;
    }
    visible: false
    width: 0
    height: 0

    Repeater {
        id: rows
        model: measure.items
        onItemAdded: measure.revision++
        onItemRemoved: measure.revision++
        delegate: Item {
            required property var modelData
            readonly property real quanto: modelData && modelData.separator !== true
                ? label.implicitWidth + shortcut.implicitWidth
                  + (shortcut.text !== "" ? Theme.Effects.space4 : 0)
                  + (modelData.children ? 20 : 0) : 0
            Text {
                id: label
                textFormat: Text.PlainText
                text: (modelData && modelData.label) || ""
                font.family: measure.windowsAppearance ? Windows11.Style.font : Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: measure.windowsAppearance ? 14 * Windows11.Style.textScale : Theme.Typography.sizeMD
            }
            Text {
                id: shortcut
                text: (modelData && modelData.shortcut) || ""
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }
}
