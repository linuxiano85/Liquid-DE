import QtQuick
import QtQuick.Shapes
import "FluentPaths.js" as FluentPaths

Item {
    id: glyph
    property string name: ""
    property color color: Style.text
    property bool alwaysDrawn: true
    // Il renderer software di Shape può ignorare il ritaglio di ListView.
    // Nei cataloghi scorrevoli si rasterizza lo stesso tracciato tramite SVG,
    // che usa il percorso Image e rispetta il ritaglio anche senza GPU.
    property bool rasterized: false
    implicitWidth: 24
    implicitHeight: 24
    // Una tabella condivisa conserva i tracciati precedenti senza duplicarla.
    readonly property var paths: FluentPaths.paths
    Image {
        anchors.fill: parent
        visible: glyph.rasterized
        sourceSize: Qt.size(Math.max(1, Math.ceil(width * 2)), Math.max(1, Math.ceil(height * 2)))
        fillMode: Image.PreserveAspectFit
        source: !glyph.rasterized ? "" : "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb('
            + Math.round(glyph.color.r * 255) + ',' + Math.round(glyph.color.g * 255) + ','
            + Math.round(glyph.color.b * 255) + ')" fill-opacity="' + glyph.color.a
            + '" d="' + (glyph.paths[glyph.name] || glyph.paths.apps) + '"/></svg>')
    }
    Shape {
        visible: !glyph.rasterized
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
