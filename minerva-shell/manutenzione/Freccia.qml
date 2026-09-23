import QtQuick

import "../theme" as Theme

// Freccia — il segno che dice se una sezione è aperta.
//
// Due rettangoli girati e non `Ui.Icon`, per la stessa ragione di `Spunta`:
// le nostre icone sono `Shape`, e col renderer software una `Shape` dentro
// una superficie che scorre dipinge anche **fuori dal ritaglio**, lasciando
// la propria copia sopra il grafico. Un rettangolo il ritaglio lo rispetta.
//
// Gira invece di cambiare disegno: è la stessa cosa in due momenti, e
// ruotandola si vede che si apre.
Item {
    id: freccia

    property bool aperta: false
    property color colore: Theme.Colors.textMuted

    implicitWidth: 16
    implicitHeight: 16

    rotation: freccia.aperta ? 0 : -90
    Behavior on rotation {
        NumberAnimation { duration: Theme.Motion.quick
                          easing.type: Easing.OutCubic }
    }

    Rectangle {
        x: 3.0; y: 5.6
        width: 7; height: 2
        radius: 1
        rotation: 45
        transformOrigin: Item.Left
        color: freccia.colore
    }

    Rectangle {
        x: 13.0; y: 5.6
        width: 7; height: 2
        radius: 1
        rotation: 135
        transformOrigin: Item.Left
        color: freccia.colore
    }
}
