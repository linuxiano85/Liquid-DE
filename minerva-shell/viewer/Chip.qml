import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// Chip — Una pastiglia che dice come stanno le cose adesso, e si preme per
// cambiarle.
//
// Non è un pulsante: un pulsante dice che cosa FARÀ, questa dice che cosa È.
// «Immagini ⌄» non è un comando, è lo stato del filtro — e siccome è anche il
// posto da cui si cambia, il chevron promette che dietro c'è dell'altro.
Item {
    id: chip

    property string testo: ""
    property string icona: ""
    /// Vero quando non sta al valore predefinito: si accende, così si vede da
    /// lontano che c'è un filtro attivo e non ci si chiede dove sono finiti i
    /// file che mancano.
    property bool acceso: false

    signal premuto()

    implicitWidth: riga.implicitWidth + Theme.Effects.space3 * 2
    implicitHeight: 28

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: chip.acceso ? Qt.alpha(Theme.Colors.accent, 0.18)
                           : (tocco.containsMouse ? Theme.Colors.raisedHigh
                                                  : Theme.Colors.panel)
        border.width: Theme.Effects.hairline
        border.color: chip.acceso ? Theme.Colors.edgeAccent : Theme.Colors.edge
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    Row {
        id: riga
        anchors.centerIn: parent
        spacing: Theme.Effects.space1

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 13
            height: 13
            visible: chip.icona !== ""
            name: chip.icona
            alwaysDrawn: true
            color: chip.acceso ? Theme.Colors.accent : Theme.Colors.textMuted
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.testo
            color: chip.acceso ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightMedium
        }

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 11
            height: 11
            name: "chevron"
            alwaysDrawn: true
            color: Theme.Colors.textFaint
        }
    }

    MouseArea {
        id: tocco
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.premuto()
    }
}
