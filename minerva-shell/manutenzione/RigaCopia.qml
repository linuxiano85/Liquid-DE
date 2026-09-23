import QtQuick

import "../theme" as Theme

// Una copia dentro un gruppo di doppioni.
//
// ── Perché si vede il percorso INTERO ──────────────────────────────────────
//
// Perché tre copie dello stesso video sono tre storie diverse: una l'hai
// messa in `Video/vacanze`, una è caduta in `Scaricati`, una sta dentro lo
// scarico del telefono di luglio. Un elenco di caselle con scritto
// «VID_20260607_215658.mp4» tre volte non è un elenco: è un indovinello.
//
// La cartella si stacca dal nome del file — grigia la strada, chiaro il nome
// — perché quello che si confronta con l'occhio è la strada, e il nome è
// uguale per tutte.
Item {
    id: riga

    property string percorso: ""

    /// Questa è la copia che resta. Non ha la casella: non si può scegliere
    /// di buttare quella che si sta tenendo, e un interruttore che non si può
    /// muovere è un interruttore che non deve esserci.
    property bool tenuta: false

    property bool scelta: false

    signal commutata()
    signal voglioTenerla()

    implicitHeight: 44

    readonly property int _taglio: riga.percorso.lastIndexOf("/")
    readonly property string dove: riga._taglio > 0
                                   ? riga.percorso.substring(0, riga._taglio + 1)
                                   : ""
    readonly property string nome: riga._taglio > 0
                                   ? riga.percorso.substring(riga._taglio + 1)
                                   : riga.percorso

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Theme.Effects.space2
        anchors.rightMargin: -Theme.Effects.space2
        radius: Theme.Effects.radiusSM
        color: riga.tenuta
               ? Qt.alpha(Theme.Colors.positive, 0.12)
               : (riga.scelta
                  ? Qt.alpha(Theme.Colors.danger, 0.14)
                  : (dito.containsMouse ? Theme.Colors.hover : "transparent"))
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    MouseArea {
        id: dito
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: riga.tenuta ? riga.voglioTenerla() : riga.commutata()
    }

    Spunta {
        id: casella
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        visible: !riga.tenuta
        stato: riga.scelta ? 1 : 0
        onPremuta: riga.commutata()
    }

    // Al posto della casella, per quella che resta: un segno che dice
    // «questa rimane», e che si può spostare cliccando un'altra riga.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        visible: riga.tenuta
        width: 22; height: 22
        radius: Theme.Effects.radiusXS
        color: Qt.alpha(Theme.Colors.positive, 0.22)
        border.width: 1.5
        border.color: Theme.Colors.positive
    }

    Column {
        anchors.left: casella.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.right: etichetta.left
        anchors.rightMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: riga.nome
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            elide: Text.ElideMiddle
        }

        Text {
            width: parent.width
            text: riga.dove
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
            elide: Text.ElideMiddle
        }
    }

    Text {
        id: etichetta
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        text: riga.tenuta ? "questa resta"
                          : (riga.scelta ? "nel cestino" : "")
        color: riga.tenuta ? Theme.Colors.positive : Theme.Colors.danger
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeXS
        font.weight: Theme.Typography.weightMedium
    }
}
