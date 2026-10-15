import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W

Column {
    id: supplies
    property var items: []
    readonly property bool windows: Core.DesktopStyle.attuale === "windows"
    readonly property bool it: Core.Strings.lang === "it"
    readonly property real scale: windows ? W.Style.textScale : Theme.Typography.scala
    readonly property color textColor: windows ? W.Style.text : Theme.Colors.text
    readonly property color mutedColor: windows ? W.Style.muted : Theme.Colors.textMuted
    spacing: 12
    Text {
        width: parent.width
        text: (supplies.it ? "Consumabili" : "Supplies") + (supplies.items.length ? " · " + supplies.items.length : "")
        color: supplies.textColor
        font.family: supplies.windows ? W.Style.font : Theme.Typography.fontDisplay
        font.pixelSize: 15 * supplies.scale
        font.weight: Font.DemiBold
    }
    Flow {
        width: parent.width
        spacing: 12
        Repeater {
            model: supplies.items
            delegate: Rectangle {
                id: cartridge
                required property var modelData
                required property int index
                objectName: "consumabileStampante-" + index
                width: Math.min(210, supplies.width)
                height: labels.height + 24
                radius: 6
                color: Qt.alpha(supplies.textColor, supplies.windows ? 0.025 : 0.035)
                border.width: 1
                border.color: Qt.alpha(supplies.textColor, 0.12)
                Accessible.role: Accessible.Grouping
                Accessible.name: Core.Printing.supplyLabel(modelData)
                Accessible.description: level.text + " · " + status.text
                Column {
                    id: labels
                    x: 12; y: 12
                    width: parent.width - 24
                    spacing: 8
                    Row {
                        width: parent.width
                        spacing: 8
                        Rectangle {
                            width: 14; height: 14; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: cartridge.modelData.color
                            border.width: 1
                            border.color: Qt.alpha(supplies.textColor, 0.28)
                        }
                        Text {
                            width: parent.width - 22
                            text: Core.Printing.supplyLabel(cartridge.modelData)
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: supplies.textColor
                            font.family: supplies.windows ? W.Style.font : Theme.Typography.fontDisplay
                            font.pixelSize: 14 * supplies.scale
                        }
                    }
                    Text {
                        id: level
                        text: cartridge.modelData.level === null
                            ? (supplies.it ? "Non disponibile" : "Unavailable") : cartridge.modelData.level + "%"
                        color: supplies.textColor
                        font.family: supplies.windows ? W.Style.font : Theme.Typography.fontDisplay
                        font.pixelSize: cartridge.modelData.level === null ? 14 * supplies.scale : 25 * supplies.scale
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        width: parent.width; height: 7; radius: 3
                        color: Qt.alpha(supplies.textColor, 0.12)
                        Rectangle {
                            visible: cartridge.modelData.level !== null
                            width: parent.width * (cartridge.modelData.level || 0) / 100
                            height: parent.height; radius: 3
                            color: cartridge.modelData.color
                            border.width: 1; border.color: Qt.alpha(supplies.textColor, 0.2)
                        }
                    }
                    Text {
                        id: status
                        width: parent.width
                        text: cartridge.modelData.high ? (supplies.it ? "Serbatoio quasi pieno" : "Waste tank almost full")
                            : cartridge.modelData.low ? (supplies.it ? "In esaurimento" : "Running low")
                            : cartridge.modelData.level === null ? (supplies.it ? "Livello non comunicato" : "Level not reported")
                            : (supplies.it ? "Livello dichiarato" : "Reported level")
                        color: supplies.mutedColor
                        wrapMode: Text.Wrap
                        font.family: supplies.windows ? W.Style.font : Theme.Typography.fontDisplay
                        font.pixelSize: 12 * supplies.scale
                    }
                }
            }
        }
    }
}
