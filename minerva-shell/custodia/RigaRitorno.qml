import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// RigaRitorno — una riga a cui si può tornare: un salvataggio o un punto.
//
// Il pulsante «torna qui» compare **solo** quando il mouse ci passa sopra. Non
// è un vezzo: sono due liste lunghe di righe quasi identiche, e un pulsante su
// ognuna vorrebbe dire venti pulsanti che fanno la cosa più drastica del
// programma, tutti visibili insieme. Nascosto finché non si punta una riga
// precisa, l'azione resta a un clic ma smette di essere un campo minato.
Rectangle {
    id: riga

    property bool it: true
    property string titolo: ""
    property string quando: ""
    property string marchio: ""

    signal torna()

    implicitHeight: 46
    radius: Theme.Effects.radiusMD
    color: sopra.containsMouse ? Theme.Colors.hover : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }

    MouseArea {
        id: sopra
        anchors.fill: parent
        hoverEnabled: true
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space2
        anchors.right: pulsante.left
        anchors.rightMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: riga.titolo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Row {
            spacing: Theme.Effects.space2

            Text {
                text: Tempo.quandoBreve(riga.quando, riga.it)
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
            Text {
                visible: riga.marchio !== ""
                text: riga.marchio
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }

    Ui.SpineButton {
        id: pulsante
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space1
        anchors.verticalCenter: parent.verticalCenter
        height: 28
        horizontalPadding: Theme.Effects.space3
        opacity: sopra.containsMouse || pulsante.hovered ? 1 : 0
        visible: opacity > 0.01
        onClicked: riga.torna()

        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        content: Text {
            text: riga.it ? "Torna qui" : "Go here"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }
    }
}
