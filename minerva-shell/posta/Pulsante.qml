import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// Pulsante — icona e parola, la forma di tutte le azioni della Posta.
// Senza `testo` resta solo l'icona, con il suggerimento al passaggio.
Ui.SpineButton {
    id: p

    property string icona: ""
    property string testo: ""
    property color tinta: Theme.Colors.text
    property bool spento: false

    height: 34
    solido: true
    opacity: p.spento ? 0.4 : 1
    enabled: !p.spento
    horizontalPadding: p.testo === "" ? Theme.Effects.space2 : Theme.Effects.space3

    content: Row {
        spacing: Theme.Effects.space2
        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: p.icona !== ""
            name: p.icona
            width: 15; height: 15
            color: p.tinta
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: p.testo !== ""
            text: p.testo
            color: p.tinta
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }
    }
}
