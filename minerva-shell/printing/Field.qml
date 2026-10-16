import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W

Rectangle {
    id: field
    property alias text: input.text
    property alias validator: input.validator
    readonly property alias acceptableInput: input.acceptableInput
    readonly property bool windows:Core.DesktopStyle.attuale === "windows"
    implicitHeight:34
    color:windows ? W.Style.field : Theme.Colors.raised
    border.width:1
    border.color:input.activeFocus ? (windows ? W.Style.accent : Theme.Colors.accent) : Qt.alpha(input.color,0.2)
    radius:windows ? 4 : 8
    TextInput {
        id:input
        anchors.fill:parent
        anchors.margins:8
        verticalAlignment:TextInput.AlignVCenter
        selectByMouse:true
        clip:true
        color:field.windows ? W.Style.text : Theme.Colors.text
        selectionColor:field.windows ? W.Style.accent : Theme.Colors.accent
        selectedTextColor:field.windows ? W.Style.accentForeground : Theme.Colors.window
        font.family:field.windows ? W.Style.font : Theme.Typography.fontDisplay
        font.pixelSize:14
        activeFocusOnTab:true
    }
}
