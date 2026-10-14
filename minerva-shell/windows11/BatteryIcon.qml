import QtQuick
import "ColorMath.js" as ColorMath

// Il fulmine accanto alla batteria lascia sempre leggibile il riempimento.
// Nessun timer o animazione a riposo.
Item {
    id: battery
    property real percent: -1
    property bool charging: false
    property bool saving: false
    readonly property bool available: isFinite(percent) && percent >= 0
    readonly property real fraction: available ? Math.min(100, percent) / 100 : 0
    readonly property string state: !available ? "absent"
        : charging ? "charging"
        : percent <= 5 ? "critical"
        : saving ? "saving" : "normal"
    // I colori di stato di Windows (SystemFillColorSuccess/Critical/Caution,
    // `Gettoni.js`), resi leggibili sulla barra vera.
    readonly property color ink: state === "charging"
        ? ColorMath.readable(Style.success, Style.taskbarSurface, 3)
        : state === "critical" ? ColorMath.readable(Style.critical, Style.taskbarSurface, 3)
        : state === "saving" ? ColorMath.readable(Style.caution, Style.taskbarSurface, 3)
        : Style.barraTesto
    implicitWidth: charging ? 38 : 24
    implicitHeight: 24
    visible: available
    Rectangle {
        x: 1
        y: 7
        width: 20
        height: 10
        radius: 2.5
        color: "transparent"
        border.width: 1.25
        border.color: battery.ink
    }
    Rectangle {
        x: 21.5
        y: 10
        width: 1.5
        height: 4
        radius: 0.75
        color: battery.ink
    }
    Rectangle {
        objectName: "windowsBatteryFill"
        x: 3
        y: 9
        width: 16 * battery.fraction
        height: 6
        radius: Math.min(1, width / 2)
        color: battery.ink
    }
    Glyph {
        objectName: "windowsBatteryCharging"
        x: 23
        y: 5
        width: 14
        height: 14
        name: "charging"
        color: battery.ink
        visible: battery.charging
    }
}
