import QtQuick

import "../theme" as Theme

// Il pulsante della Fucina: lo stesso di Manutenzione, scritto per esteso.
//
// È un file e non un componente in linea perché lo usano quattro pagine, e un
// componente in linea vive solo nel file che lo dichiara. Copiato e non preso
// da `manutenzione/`: la regola di MODULI.md è che un modulo si butta senza
// riscrivere il resto, e una Fucina che importa Manutenzione cadrebbe con lei.
Rectangle {
    id: pulsante

    property string testo: ""
    property bool primario: false
    /// Rosso: per le cose che non si disfano (togliere un kernel).
    property bool pericolo: false
    property bool attivo: true
    signal scelto()

    implicitWidth: etichetta.implicitWidth + Theme.Effects.space5 * 2
    implicitHeight: 36
    radius: Theme.Effects.radiusMD
    opacity: pulsante.attivo ? 1 : 0.45

    readonly property color _pieno: pulsante.pericolo ? Theme.Colors.danger
                                                      : Theme.Colors.accent
    readonly property bool _colmo: pulsante.primario || pulsante.pericolo

    color: pulsante._colmo
           ? (area.containsMouse && pulsante.attivo
              ? Qt.lighter(pulsante._pieno, 1.12) : pulsante._pieno)
           : (area.containsMouse ? Theme.Colors.hover : Theme.Colors.raised)
    border.width: pulsante._colmo ? 0 : Theme.Effects.hairline
    border.color: Theme.Colors.edge

    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

    Text {
        id: etichetta
        anchors.centerIn: parent
        text: pulsante.testo
        color: pulsante._colmo ? Theme.Colors.textOnAccent : Theme.Colors.text
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeSM
        font.weight: Theme.Typography.weightMedium
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: pulsante.attivo
        cursorShape: Qt.PointingHandCursor
        onClicked: pulsante.scelto()
    }
}
