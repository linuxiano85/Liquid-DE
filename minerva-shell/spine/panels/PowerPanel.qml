import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// PowerPanel — Blocca, sospendi, esci, riavvia, spegni.
//
// Le azioni distruttive stanno in fondo e chiedono conferma con un secondo
// clic sullo stesso pulsante. Un dialogo separato costringerebbe a spostare
// il puntatore e a leggere una domanda; il secondo clic sullo stesso posto
// interrompe solo chi ha sbagliato mira.
Item {
    id: panel

    property var spine: null

    readonly property real implicitPanelHeight: stack.implicitHeight
                                                + Theme.Effects.space5
                                                + Theme.Effects.space4

    // Staccato: il blocco schermo deve restare in piedi anche se la shell si
    // ricarica sotto, e uno spegnimento non deve dipendere da chi l'ha
    // chiesto. Vedi `run()` in shell.qml.
    function run(argv) {
        if (argv && argv.length > 0)
            Quickshell.execDetached(argv);
        if (panel.spine)
            panel.spine.close();
    }

    // ── Una conferma sola, per tutto il pannello ─────────────────────────
    //
    // L'id della voce che sta aspettando la seconda pressione, o "" se
    // nessuna. Uno stato SOLO, del pannello, ed è tutta la riparazione.
    //
    // Fino al 2 settembre 2026 ogni riga aveva il suo `awaitingConfirm` e
    // nessuno azzerava quello delle altre: si cliccava «Riavvia», compariva
    // «Tocca di nuovo per confermare», poi si cliccava «Spegni» e le righe che
    // chiedevano conferma diventavano DUE. Giacomo l'ha descritto esattamente
    // così: «rimangono 2 voci con la conferma quando invece dovrebbe
    // scomparire da riavvia e stare solo su spegni».
    //
    // Non è pignoleria di aspetto: davanti a due righe che chiedono conferma
    // insieme non si sa più quale delle due si sta per confermare, e questa è
    // la parte del pannello dove sbagliare vuol dire spegnere il computer con
    // del lavoro aperto.
    //
    // Con un solo stato la cosa si risolve da sé: chiedere conferma per una
    // voce toglie automaticamente la conferma all'altra, perché è la stessa
    // variabile.
    property string inAttesa: ""

    function chiediConferma(id) {
        panel.inAttesa = id;
        if (id === "")
            finestraConferma.stop();
        else
            finestraConferma.restart();
    }

    /// La conferma scade da sola: una voce lasciata «armata» e dimenticata è
    /// una voce che al prossimo clic distratto spegne il computer.
    Timer {
        id: finestraConferma
        interval: 3500
        onTriggered: panel.inAttesa = ""
    }

    // Chiudendo il pannello si dimentica tutto: riaprirlo e trovare «Tocca di
    // nuovo per confermare» già acceso vorrebbe dire spegnere il computer con
    // un clic solo, senza averne dati due.
    onVisibleChanged: if (!panel.visible) panel.chiediConferma("")

    readonly property var actions: [
        { "id": "lock",     "icon": "lock",    "it": "Blocca schermo",     "en": "Lock screen",   "danger": false, "confirm": false },
        { "id": "suspend",  "icon": "moon",    "it": "Sospendi",           "en": "Suspend",       "danger": false, "confirm": false },
        { "id": "logout",   "icon": "logout",  "it": "Esci dalla sessione","en": "Log out",       "danger": true,  "confirm": true },
        { "id": "reboot",   "icon": "restart", "it": "Riavvia",            "en": "Restart",       "danger": true,  "confirm": true },
        { "id": "poweroff", "icon": "power",   "it": "Spegni",             "en": "Shut down",     "danger": true,  "confirm": true }
    ]

    function execute(id) {
        switch (id) {
        case "lock":     panel.run(["minerva-blocca"]); break;
        case "suspend":  panel.run(["systemctl", "suspend"]); break;
        case "logout":   Core.Compositore.esciDallaSessione(); break;
        case "reboot":   panel.run(["systemctl", "reboot"]); break;
        case "poweroff": panel.run(["systemctl", "poweroff"]); break;
        }
    }

    Column {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.Effects.space3
        anchors.rightMargin: Theme.Effects.space3
        anchors.topMargin: Theme.Effects.space5
        spacing: Theme.Effects.space1

        Repeater {
            model: panel.actions

            delegate: Rectangle {
                id: action
                required property var modelData
                required property int index

                /// Questa riga sta aspettando la seconda pressione?
                ///
                /// Si LEGGE da `panel.inAttesa` invece di tenersi uno stato
                /// proprio, ed è tutta la riparazione: vedi il commento su
                /// `panel.inAttesa`.
                readonly property bool awaitingConfirm:
                    panel.inAttesa === action.modelData.id

                width: parent.width
                height: 46
                radius: Theme.Effects.radiusSM

                readonly property color tone: modelData.danger ? Theme.Colors.danger
                                                               : Theme.Colors.accent

                color: awaitingConfirm ? Qt.alpha(tone, 0.20)
                     : hover.containsMouse ? Qt.alpha(tone, 0.11)
                     : "transparent"

                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // Ingresso scaglionato: le voci scendono una dopo l'altra
                opacity: 0
                x: 0
                Component.onCompleted: entrance.start()
                NumberAnimation {
                    id: entrance
                    target: action
                    property: "opacity"
                    from: 0; to: 1
                    duration: Theme.Motion.quick
                    easing.type: Easing.OutCubic
                }

                Ui.Icon {
                    id: glyph
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 19; height: 19
                    name: action.modelData.icon
                    color: action.awaitingConfirm || hover.containsMouse
                           ? action.tone : Theme.Colors.textMuted
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                }

                Text {
                    anchors.left: glyph.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight

                    text: action.awaitingConfirm
                          ? (Core.Strings.lang === "it" ? "Tocca di nuovo per confermare"
                                                        : "Tap again to confirm")
                          : (Core.Strings.lang === "it" ? action.modelData.it
                                                        : action.modelData.en)
                    color: action.awaitingConfirm ? action.tone : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightMedium
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!action.modelData.confirm) {
                            panel.chiediConferma("");
                            panel.execute(action.modelData.id);
                        } else if (action.awaitingConfirm) {
                            panel.chiediConferma("");
                            panel.execute(action.modelData.id);
                        } else {
                            panel.chiediConferma(action.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
