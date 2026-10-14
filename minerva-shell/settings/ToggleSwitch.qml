import QtQuick
import "../theme" as Theme
import "../core" as Core

// ToggleSwitch — Interruttore acceso/spento.
// Forma e movimento sono quelli che un utente riconosce da telefono e
// da qualunque pannello di sistema: nessuna spiegazione necessaria.
Item {
    id: sw

    property bool checked: false
    activeFocusOnTab: true
    Keys.onSpacePressed: requestToggle()
    Keys.onReturnPressed: requestToggle()
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

    // ── Nel preset Windows ───────────────────────────────────────────────
    //
    // L'interruttore di Windows 11: binario 40 × 20, pallino da 12 che al
    // passaggio cresce a 14, pieno d'accento quando è acceso e solo
    // contornato quando è spento, e «Attivato»/«Disattivato» scritto a
    // sinistra come in Impostazioni. La scritta fa parte del comando: un
    // clic su di lei lo commuta, come in Windows.
    readonly property bool stileWindows: Core.DesktopStyle.attuale === "windows"
    readonly property bool it: Core.Strings.lang === "it"

    implicitWidth: sw.stileWindows ? stato.implicitWidth + 12 + 40 : 52
    implicitHeight: sw.stileWindows ? 20 : 28

    Text {
        id: stato
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: sw.stileWindows
        text: sw.checked ? (sw.it ? "Attivato" : "On") : (sw.it ? "Disattivato" : "Off")
        color: Theme.Colors.text
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeSM
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: 4
        color: "transparent"
        border.width: 2
        border.color: Theme.Colors.text
        visible: sw.activeFocus
    }

    Rectangle {
        id: binario
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: sw.stileWindows
        width: 40
        height: 20
        radius: 10
        color: sw.checked ? (presa.pressed ? Qt.darker(Theme.Colors.accent, 1.12) : Theme.Colors.accent)
                          : (presa.containsMouse ? Theme.Colors.hover : "transparent")
        border.width: sw.checked ? 0 : 1
        border.color: Theme.Colors.textMuted

        Rectangle {
            readonly property real lato: presa.containsMouse ? 14 : 12
            width: presa.pressed ? 17 : lato
            height: lato
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - (20 - height) / 2
                          : (20 - height) / 2
            color: sw.checked ? Theme.Colors.textOnAccent : Theme.Colors.textMuted
            Behavior on x {
                NumberAnimation { duration: Theme.Motion.instant; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        visible: !sw.stileWindows
        radius: height / 2
        color: sw.checked ? Qt.alpha(Theme.Colors.accent, 0.35) : Theme.Colors.raisedHigh
        border.width: 1
        border.color: sw.checked ? Theme.Colors.accent : Theme.Colors.edge

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    Rectangle {
        id: knob
        visible: !sw.stileWindows
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
        id: presa
        anchors.fill: parent
        hoverEnabled: sw.stileWindows
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            sw.requestToggle();
        }
    }
}
