import QtQuick
import Quickshell
import "../ui" as Ui
Item {
    property string path: ""
    property bool clipSafe: false
    implicitWidth: 32; implicitHeight: 32
    Image {
        id: image; anchors.fill: parent
        source: parent.path === "" ? "" : (/^(file:|image:|qrc:)/.test(parent.path) ? parent.path : (parent.path[0] === "/" ? "file://" + parent.path : Quickshell.iconPath(parent.path)))
        fillMode: Image.PreserveAspectFit; asynchronous: true; mipmap: true
        sourceSize.width: Math.ceil(width * 2); sourceSize.height: Math.ceil(height * 2)
    }
    Glyph { anchors.fill: parent; visible: image.status !== Image.Ready; name: "apps"; color: Style.accentInk; alwaysDrawn: true; rasterized: parent.clipSafe }
}
