import QtQuick
import "../theme" as Theme

// SettingRow — Impalcatura comune di ogni voce delle Impostazioni:
// titolo e descrizione a sinistra, controllo a destra.
//
// Il controllo si assegna alla proprietà `control`:
//
//     SettingRow {
//         label: "Animazioni"
//         control: ToggleSwitch { ... }
//     }
//
// Volutamente NON è la proprietà predefinita: un `default property alias`
// verso `controlHolder.data` catturerebbe anche i figli dichiarati qui
// dentro, che finirebbero dentro sé stessi.
Item {
    id: row

    property string label: ""
    property string searchTerms: ""
    property bool searchHighlighted: false
    Rectangle { anchors.fill: parent; radius: 8; color: Qt.alpha(Theme.Colors.accent, 0.15); visible: row.searchHighlighted; z: -1 }
    property string description: ""

    /// Il controllo mostrato a destra (interruttore, cursore, scelta)
    property alias control: controlHolder.data

    /// Larghezza riservata al controllo
    property int controlWidth: 200

    // La riga è il gruppo: chi legge lo schermo sente prima l'etichetta e la
    // spiegazione, poi il comando che ci sta dentro. Senza il gruppo, comando
    // e testo arrivano come due cose slegate e non si capisce che cosa regola
    // che cosa.
    Accessible.role: Accessible.Grouping
    Accessible.name: row.label
    Accessible.description: row.description

    implicitHeight: Math.max(texts.implicitHeight, controlHolder.childrenRect.height) + 24

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: controlHolder.left
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            width: parent.width
            text: row.label
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightMedium
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            text: row.description
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
    }

    Item {
        id: controlHolder
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: row.controlWidth
        height: childrenRect.height
    }
}
