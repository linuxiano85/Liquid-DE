import QtQuick
Image {
    source: Qt.resolvedUrl("liquid.svg")
    width: 24; height: 24
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.ceil(width * 2); sourceSize.height: Math.ceil(height * 2)
    smooth: true; mipmap: true
}
