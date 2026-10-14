import "../windows11/FluentPaths.js" as Fluent
import "CommandPaths.js" as Commands
import QtQuick
import QtQuick.Shapes
import "../ui" as Ui

Item {
    id: glyph

    property string name: ""
    property color color: FileStyle.text

    implicitWidth: 20
    implicitHeight: 20
    readonly property string vector: Commands.paths[glyph.name] || Fluent.paths[glyph.name] || ""
    Ui.Icon {
        anchors.fill: parent
        visible: glyph.vector === ""
        name: glyph.name
        color: glyph.color
    }

    // Stessa famiglia di vettori della shell Windows, senza conversioni
    // raster che perdono definizione quando cambia la scala del monitor.
    Shape {
        visible: glyph.vector !== ""
        width: 24
        height: 24
        scale: glyph.width / 24
        transformOrigin: Item.TopLeft

        ShapePath {
            fillColor: glyph.color
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill

            PathSvg {
                path: glyph.vector
            }

        }

    }

}
