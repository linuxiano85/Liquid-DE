import QtQuick
import "../theme" as Theme

// KeyCap — Un singolo tasto disegnato come il tasto fisico di una tastiera.
// Il rilievo rende immediato capire che si tratta di un tasto da premere,
// senza doverlo spiegare a parole.
Rectangle {
    id: cap

    /// Testo già tradotto (es. "Maiusc", "Invio", "←")
    property string label: ""

    /// I modificatori sono resi in tono più tenue dei tasti veri e propri
    property bool isModifier: false

    implicitWidth: Math.max(32, labelText.implicitWidth + 18)
    implicitHeight: 30
    radius: Theme.Effects.radiusSM

    color: isModifier ? Theme.Colors.raised : Qt.alpha(Theme.Colors.accent, 0.16)
    border.width: 1
    border.color: isModifier ? Theme.Colors.edge : Qt.alpha(Theme.Colors.accent, 0.45)

    // Rilievo: una linea chiara in alto e una scura in basso
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        anchors.margins: 1
        height: 1
        color: Theme.Colors.edgeBright
        radius: parent.radius
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: cap.label
        color: cap.isModifier ? Theme.Colors.textMuted : Theme.Colors.accent
        font.family: Theme.Typography.fontMono
        font.pixelSize: Theme.Typography.sizeSM
        font.weight: Theme.Typography.weightMedium
    }
}
