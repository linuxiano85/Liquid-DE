import QtQuick

// A pre-rendered nine-slice: the soft edge stays the same at every panel size.
// No live blur, source capture, timer or continuously updated texture.
Item {
    id: shadow
    property Item surface: parent
    x: -32
    y: -24
    width: surface ? surface.width + 64 : 0
    height: surface ? surface.height + 64 : 0
    z: -1
    BorderImage {
        anchors.fill: parent
        source: Style.dark ? "shadows/flyout-dark.png" : "shadows/flyout-light.png"
        border { left: 40; top: 32; right: 40; bottom: 48 }
        horizontalTileMode: BorderImage.Stretch
        verticalTileMode: BorderImage.Stretch
    }
}
