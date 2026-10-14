import QtQuick
import QtQuick.Controls as Controls
import "../core" as Core

Controls.Slider {
    id: slider
    objectName: "windowsVolumeSlider"
    from: 0
    to: Core.SystemState.volumeCeiling
    value: Core.SystemState.volume
    hoverEnabled: true
    property var changeVolume: function(percent) {
        Core.SystemState.setVolume(percent);
    }
    readonly property bool amplified: value > 100
    readonly property real normalFraction: Math.min(1, 100 / Math.max(1, to))
    readonly property color overdriveColor: Style.critical
    Accessible.name: Style.label("Volume", "Volume")
        + ": " + Math.round(value) + "%"
        + (amplified ? Style.label(" — amplificazione oltre il 100%", " — amplification above 100%") : "")
    onMoved: changeVolume(value)

    // Il 100% resta nello stesso punto della scala mentre si muove il
    // cursore. Il segmento extra è rosso tenue; la parte utilizzata è piena.
    background: Rectangle {
        id: track
        x: slider.leftPadding + 10
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: Math.max(0, slider.availableWidth - 20)
        height: 4
        radius: 2
        color: Style.edge
        Rectangle {
            objectName: "windowsVolumeExtraRange"
            x: slider.normalFraction * track.width
            width: track.width - x
            height: track.height
            radius: 2
            color: Qt.alpha(slider.overdriveColor, 0.3)
            visible: slider.to > 100
        }
        Rectangle {
            width: Math.min(slider.position, slider.normalFraction) * track.width
            height: track.height
            radius: 2
            color: Style.accent
        }
        Rectangle {
            objectName: "windowsVolumeExtraFill"
            x: slider.normalFraction * track.width
            width: Math.max(0, slider.position - slider.normalFraction) * track.width
            height: track.height
            radius: 2
            color: slider.overdriveColor
            visible: slider.amplified
        }
        Rectangle {
            objectName: "windowsVolumeThreshold"
            x: slider.normalFraction * track.width - width / 2
            y: -2
            width: 1
            height: 8
            color: Style.muted
            visible: slider.to > 100
        }
    }
    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: 20
        height: 20
        radius: 10
        color: Style.field
        border.color: Style.edge
        Rectangle {
            objectName: "windowsVolumeHandleInk"
            anchors.centerIn: parent
            width: 12
            height: 12
            radius: 6
            color: slider.amplified ? slider.overdriveColor : Style.accent
        }
    }
    Text {
        objectName: "windowsVolumePercent"
        anchors.right: parent.right
        y: -12
        text: Math.round(slider.value) + "%"
        textFormat: Text.PlainText
        color: slider.amplified ? slider.overdriveColor : Style.muted
        font.family: Style.font
        font.pixelSize: 11 * Style.textScale
    }
}
