import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W

Rectangle {
    id: button
    property string text: ""
    signal clicked()
    readonly property bool windows: Core.DesktopStyle.attuale === "windows"
    implicitWidth: Math.max(110, label.implicitWidth + 24)
    implicitHeight: 34
    width: implicitWidth
    height: implicitHeight
    radius: windows ? 4 : Theme.Effects.radiusSM
    color: windows ? W.Style.field : Theme.Colors.raised
    border.width: 1
    border.color: activeFocus ? (windows ? W.Style.accent : Theme.Colors.accent)
                             : windows ? W.Style.cardStroke : Qt.alpha(Theme.Colors.text, 0.18)
    opacity: enabled ? 1 : 0.45
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: text
    Keys.onReturnPressed: function(event) { if (!event.isAutoRepeat) clicked(); }
    Keys.onSpacePressed: function(event) { if (!event.isAutoRepeat) clicked(); }
    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: button.windows ? W.Style.text : Theme.Colors.text
        font.family: button.windows ? W.Style.font : Theme.Typography.fontDisplay
        font.pixelSize: 14 * (button.windows ? W.Style.textScale : 1)
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: button.clicked() }
}
