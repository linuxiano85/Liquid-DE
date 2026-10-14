import QtQuick
import QtQuick.Shapes
import "FluentPaths.js" as FluentPaths

Item {
    id: glyph
    property string name: ""
    property color color: Style.text
    property bool alwaysDrawn: true
    implicitWidth: 24
    implicitHeight: 24
    // Una tabella condivisa conserva i tracciati precedenti senza duplicarla.
    readonly property var paths: FluentPaths.paths
    Shape {
        anchors.fill: parent
        scale: parent.width / 24
        transformOrigin: Item.TopLeft
        width: 24
        height: 24
        ShapePath {
            fillColor: glyph.color
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill
            PathSvg {
                path: glyph.paths[glyph.name] || glyph.paths.apps
            }
        }
    }
}
