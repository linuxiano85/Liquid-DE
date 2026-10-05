import QtQuick
import "../theme" as Theme
import "../core" as Core

// ToggleTile — Interruttore a piastrella, con etichetta e stato.
//
// La piastrella intera è l'interruttore. Non c'è una levetta separata da
// centrare: quando è accesa la piastrella si colora, quando è spenta resta
// scura. Lo stato si legge dal colore del blocco, non da una posizione.
//
// La riga di sotto dice *cosa* è acceso — il nome della rete, il dispositivo
// collegato — perché sapere che il Bluetooth è acceso serve a poco; serve
// sapere a cosa è collegato.
Rectangle {
    id: tile

    property string icon: ""
    property string label: ""
    /// Che cosa è acceso: il nome della rete, il televisore trovato, «Spento».
    /// È un DATO, e si vede sempre.
    property string detail: ""

    property bool checked: false
    property color accent: Theme.Colors.accent
    property bool enabled: true

    signal toggled(bool value)

    // La piastrella dice tre cose: che cos'è, com'è messa, e il dettaglio —
    // «Wi-Fi, acceso, FASTWEB-9Z4YPG». È l'unico modo di sapere a che rete si
    // è attaccati senza vedere lo schermo.
    Accessible.role: Accessible.CheckBox
    Accessible.name: tile.label
    Accessible.description: tile.detail
    Accessible.checkable: true
    Accessible.checked: tile.checked
    Accessible.onToggleAction: tile.toggled(!tile.checked)

    implicitHeight: 62
    radius: Theme.Effects.radiusMD

    color: !enabled ? Theme.Colors.sunken
         : checked ? Qt.alpha(accent, 0.20)
         : mouse.pressed ? Theme.Colors.pressed
         : mouse.containsMouse ? Theme.Colors.hover
         : Theme.Colors.raised

    border.width: 1
    border.color: checked ? Qt.alpha(accent, 0.45) : "transparent"

    opacity: enabled ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
    Behavior on border.color { ColorAnimation { duration: Theme.Motion.quick } }

    scale: mouse.pressed ? 0.97 : 1.0
    Behavior on scale {
        NumberAnimation { duration: Theme.Motion.instant; easing.type: Easing.OutCubic }
    }

    Icon {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        width: 21; height: 21
        name: tile.icon
        color: tile.checked ? tile.accent : Theme.Colors.textFaint
        Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: tile.label
            elide: Text.ElideRight
            color: tile.checked ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightSemiBold
        }

        Text {
            width: parent.width
            text: tile.detail
            visible: text !== ""
            elide: Text.ElideRight
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: tile.enabled
        cursorShape: Qt.PointingHandCursor
        // Si chiede, non si decide: assegnare `checked` qui spezzava il legame
        // con l'impostazione, e da lì la piastrella non seguiva più i cambi
        // fatti altrove. Lo stato nuovo arriva da chi la usa.
        onClicked: tile.toggled(!tile.checked)
    }
}
