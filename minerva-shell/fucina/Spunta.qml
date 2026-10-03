import QtQuick

import "../theme" as Theme

// Una casella da spuntare, fatta di soli rettangoli.
//
// Rettangoli e non `Shape`, ed è la lezione di Manutenzione (9 settembre
// 2026): col renderer software una `Shape` dipinge anche fuori dal ritaglio
// del `Flickable`, e scorrendo lascia spunte fantasma dove non ridipinge
// nessuno. Un rettangolo il ritaglio lo rispetta.
//
// `stato`: 0 vuota, 1 piena, 2 in parte (per una famiglia con dentro sia
// moduli tenuti sia tolti). `bloccata`: si vede piena e non si cambia — gli
// essenziali, che senza il computer non si avvia.
Item {
    id: casella

    property int stato: 0
    property bool attiva: true
    property bool bloccata: false

    signal premuta()

    implicitWidth: 22
    implicitHeight: 22

    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusXS
        color: casella.stato === 0
               ? (dito.containsMouse ? Theme.Colors.hover : Theme.Colors.sunken)
               : Qt.alpha(casella.bloccata ? Theme.Colors.textFaint
                                           : Theme.Colors.accent,
                          casella.attiva ? 1.0 : 0.45)
        border.width: casella.stato === 0 ? 1.5 : 0
        border.color: dito.containsMouse ? Theme.Colors.accent
                                         : Theme.Colors.edgeBright

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    Item {
        anchors.fill: parent
        visible: casella.stato === 1

        Rectangle {
            x: 5.2; y: 10.6
            width: 6.6; height: 2.6
            radius: 1.3
            rotation: 45
            transformOrigin: Item.Left
            color: Theme.Colors.textOnAccent
        }

        Rectangle {
            x: 9.2; y: 13.4
            width: 11.4; height: 2.6
            radius: 1.3
            rotation: -50
            transformOrigin: Item.Left
            color: Theme.Colors.textOnAccent
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: casella.stato === 2
        width: 11; height: 2.6
        radius: 1.3
        color: Theme.Colors.textOnAccent
    }

    MouseArea {
        id: dito
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        enabled: casella.attiva && !casella.bloccata
        cursorShape: Qt.PointingHandCursor
        onClicked: casella.premuta()
    }
}
