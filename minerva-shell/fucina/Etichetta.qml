import QtQuick

import "../theme" as Theme

// Una pillola: la fonte di un modulo («legato», «modprobed»…), un preset, lo
// stato di un kernel. Se `scelta` è vera si colora dell'accento; se ha un
// `tono` («buono», «attenzione», «pericolo») prende quel colore.
Rectangle {
    id: pillola

    property string testo: ""
    property bool scelta: false
    property string tono: ""
    property bool cliccabile: false
    property string spiega: ""
    signal premuta()

    readonly property color _tinta: pillola.tono === "buono" ? Theme.Colors.positive
                                  : pillola.tono === "attenzione" ? Theme.Colors.warning
                                  : pillola.tono === "pericolo" ? Theme.Colors.danger
                                  : Theme.Colors.accent

    implicitWidth: nome.implicitWidth + Theme.Effects.space3 * 2
    implicitHeight: 24
    radius: Theme.Effects.radiusFull
    color: pillola.scelta || pillola.tono !== ""
           ? Qt.alpha(pillola._tinta, 0.16)
           : (dito.containsMouse && pillola.cliccabile ? Theme.Colors.hover
                                                       : Theme.Colors.sunken)
    border.width: Theme.Effects.hairline
    border.color: pillola.scelta || pillola.tono !== ""
                  ? Qt.alpha(pillola._tinta, 0.5) : Theme.Colors.edge

    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

    Text {
        id: nome
        anchors.centerIn: parent
        text: pillola.testo
        color: pillola.scelta || pillola.tono !== "" ? pillola._tinta
                                                     : Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeXS
        font.weight: pillola.scelta ? Theme.Typography.weightSemiBold
                                    : Theme.Typography.weightMedium
    }

    MouseArea {
        id: dito
        anchors.fill: parent
        hoverEnabled: true
        enabled: pillola.cliccabile
        cursorShape: pillola.cliccabile ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: pillola.premuta()
    }
}
