import "../core" as Core
import "../theme" as Theme
import "../windows11" as Windows
import QtQuick
pragma Singleton

QtObject {
    // Una presentazione locale evita che il preset Windows cambi i colori
    // delle altre app o erediti l'accento Liquid nella selezione dei file.
    readonly property bool windows: Core.DesktopStyle.attuale === "windows"
    readonly property bool dark: Windows.Style.dark
    readonly property string font: windows ? Windows.Style.font : Theme.Typography.fontDisplay
    readonly property color window: windows
        ? Qt.alpha(Windows.Style.base, Theme.Colors.opacitaFinestra(dark))
        : Theme.Colors.window
    readonly property color lettura: windows ? (dark ? "#191919" : "#ffffff") : Theme.Colors.lettura
    readonly property color base: windows ? lettura : Theme.Colors.base
    readonly property color panel: windows ? Windows.Style.field : Theme.Colors.panel
    readonly property color raised: windows ? (dark ? "#2b2b2b" : "#f3f3f3") : Theme.Colors.raised
    readonly property color raisedHigh: windows ? Windows.Style.field : Theme.Colors.raisedHigh
    readonly property color sunken: windows ? Windows.Style.base : Theme.Colors.sunken
    readonly property color text: windows ? Windows.Style.text : Theme.Colors.text
    readonly property color textMuted: windows ? Windows.Style.muted : Theme.Colors.textMuted
    readonly property color textFaint: windows ? Windows.Style.muted : Theme.Colors.textFaint
    readonly property color textOnAccent: windows ? Windows.Style.accentForeground : Theme.Colors.textOnAccent
    readonly property color accent: windows ? Windows.Style.accent : Theme.Colors.accent
    readonly property color accentAlt: windows ? Windows.Style.accent : Theme.Colors.accentAlt
    readonly property color edge: windows ? Windows.Style.edge : Theme.Colors.edge
    readonly property color edgeAccent: windows ? Windows.Style.accentIndicator : Theme.Colors.edgeAccent
    readonly property color hover: windows ? Windows.Style.hover : Theme.Colors.hover
    readonly property color pressed: windows ? Windows.Style.pressed : Theme.Colors.pressed
    readonly property color selected: windows ? Qt.alpha(accent, dark ? 0.28 : 0.14) : Theme.Colors.selected
    readonly property color danger: Theme.Colors.danger
    readonly property color warning: Theme.Colors.warning
    readonly property color scrim: Theme.Colors.scrim
}
