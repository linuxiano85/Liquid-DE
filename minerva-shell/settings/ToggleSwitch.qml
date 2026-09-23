import QtQuick
import "../theme" as Theme

// ToggleSwitch — Interruttore acceso/spento.
// Forma e movimento sono quelli che un utente riconosce da telefono e
// da qualunque pannello di sistema: nessuna spiegazione necessaria.
Item {
    id: sw

    property bool checked: false
    signal toggled(bool value)
    function requestToggle() { sw.toggled(!sw.checked); }

    // ── Quello che legge un lettore di schermo ───────────────────────────
    //
    // Un'interfaccia disegnata è fatta di rettangoli colorati: senza queste
    // righe, chi non vede trova un rettangolo e basta. `Accessible.role` dice
    // CHE COS'È, `name` dice quale, `checked` dice com'è messo adesso.
    //
    // Il nome non si scrive qui: lo mette chi usa la levetta, perché è lui a
    // sapere se sta accendendo il Wi-Fi o le animazioni. Chi non lo mette
    // lascia una levetta anonima — ed è meglio saperlo che averla muta.
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: sw.checked
    Accessible.onToggleAction: sw.requestToggle()

    implicitWidth: 52
    implicitHeight: 28

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Qt.alpha(Theme.Colors.accent, 0.35) : Theme.Colors.raisedHigh
        border.width: 1
        border.color: sw.checked ? Theme.Colors.accent : Theme.Colors.edge

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    Rectangle {
        id: knob
        width: parent.height - 8
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 4 : 4
        color: sw.checked ? Theme.Colors.accent : Theme.Colors.textMuted

        Behavior on x {
            NumberAnimation {
                duration: Theme.Motion.instant
                easing.type: Easing.OutCubic
            }
        }
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            sw.requestToggle();
        }
    }
}
