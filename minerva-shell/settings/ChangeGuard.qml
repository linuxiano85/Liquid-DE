import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core

// ChangeGuard — «Va bene così?», con il ritorno automatico se nessuno risponde.
//
// Esiste per una sola categoria di modifiche: quelle che possono togliere il
// modo di annullarle. Ruotare lo schermo di 90° è il caso da manuale — il
// puntatore si muove di traverso, le finestre finiscono fuori, e il pannello
// che ha appena fatto il danno è il primo a diventare irraggiungibile. Lo
// stesso vale per una risoluzione che il monitor non regge e per uno schermo
// spento per sbaglio: si resta con una modifica applicata e nessuna maniglia.
//
// La regola è quella di ogni sistema operativo serio: la modifica si applica
// SUBITO — bisogna poterla vedere per giudicarla — ma torna indietro DA SOLA
// dopo pochi secondi se nessuno conferma. Chi vede bene conferma; chi non vede
// più niente non fa nulla e ritrova lo schermo com'era.
//
//     ChangeGuard {
//         id: guard
//         onKept: page.persist()
//         onReverted: page.undo()
//     }
//     ...
//     guard.arm("Lo schermo è ancora leggibile?")
//
// Vive in una finestra propria sul livello più alto e non dentro il pannello
// Impostazioni: dopo una rotazione sbagliata la finestra delle impostazioni può
// essere finita mezza fuori dallo schermo, ed è esattamente il momento in cui
// questa domanda deve restare visibile.
PanelWindow {
    id: guard

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    // Il fuoco esclusivo si giustifica qui e quasi in nessun altro posto: la
    // domanda dura pochi secondi e finisce da sola comunque, e senza il fuoco
    // Invio ed Esc non funzionerebbero proprio quando servono di più.
    WlrLayershell.keyboardFocus: guard.armed ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: armed

    /// Quanti secondi si aspetta prima di tornare indietro da soli.
    property int seconds: 15

    /// Domanda in grande. La si scrive dal punto di vista di chi guarda lo
    /// schermo, non di chi ha scritto il codice: «si legge?» e non
    /// «confermare la trasformazione?».
    property string question: ""
    /// Riga piccola sotto: cosa è stato cambiato, per chi non se lo ricorda.
    property string detail: ""

    readonly property bool it: Core.Strings.lang === "it"

    property bool armed: false
    property int remaining: 0

    signal kept()
    signal reverted()

    function arm(q, d) {
        guard.question = q || (guard.it ? "Lo schermo si vede bene?"
                                        : "Does the display look right?");
        guard.detail = d || "";
        guard.remaining = guard.seconds;
        guard.armed = true;
        countdown.restart();
        deadline.restart();
        keys.forceActiveFocus();
    }

    function keep() {
        if (!guard.armed)
            return;
        countdown.stop();
        guard.armed = false;
        guard.kept();
    }

    function revert() {
        if (!guard.armed)
            return;
        countdown.stop();
        guard.armed = false;
        guard.reverted();
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            guard.remaining--;
            if (guard.remaining <= 0)
                guard.revert();
        }
    }

    // Rete di sicurezza. Questo riquadro tiene la tastiera in esclusiva mentre
    // è a schermo: se per qualunque motivo il conteggio si fermasse, resterebbe
    // lì per sempre e con sé la tastiera di tutto il sistema. Un secondo
    // temporizzatore, che non conta niente e scatta una volta sola, chiude la
    // domanda comunque.
    Timer {
        id: deadline
        interval: guard.seconds * 1000 + 2500
        onTriggered: guard.revert()
    }

    onArmedChanged: if (!armed) deadline.stop()

    // Solo il riquadro è cliccabile: il resto dello schermo resta a chi c'era
    // prima. Bloccare tutto per quindici secondi non aggiungerebbe sicurezza,
    // toglierebbe soltanto la possibilità di guardare cosa è cambiato.
    mask: Region {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: guard.revert()
        Keys.onReturnPressed: guard.keep()
        Keys.onEnterPressed: guard.keep()
    }

    // ── Il riquadro ──────────────────────────────────────────────────────

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        width: 460
        height: content.implicitHeight + Theme.Effects.space5 * 2
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.membrane
        border.width: 1
        border.color: Theme.Colors.edge

        opacity: guard.armed ? 1 : 0
        scale: guard.armed ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.emerge
            }
        }

        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.Effects.space5
            spacing: Theme.Effects.space3

            Text {
                width: parent.width
                text: guard.question
                wrapMode: Text.WordWrap
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightBold
            }

            Text {
                width: parent.width
                visible: guard.detail !== ""
                text: guard.detail
                wrapMode: Text.WordWrap
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                width: parent.width
                text: guard.it
                      ? "Se non rispondi torno com'era fra " + guard.remaining + " s."
                      : "With no answer I'll put it back in " + guard.remaining + " s."
                wrapMode: Text.WordWrap
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            // La barra che si svuota dice il tempo che resta senza doverlo
            // leggere: il numero serve a chi lo cerca, la barra a chi passa.
            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Theme.Colors.sunken

                Rectangle {
                    // A pixel interi, come ogni riempimento animato: vedi
                    // `ui/Slider.qml`.
                    width: Math.round(parent.width * Math.max(0, guard.remaining)
                           / Math.max(1, guard.seconds))
                    height: parent.height
                    radius: parent.radius
                    color: guard.remaining <= 5 ? Theme.Colors.danger
                                                : Theme.Colors.warning
                    // Niente `Behavior` sulla larghezza: vedi `ui/Slider.qml`.
                    // Il conto va giu' di un secondo per volta, e un secondo
                    // e' gia' il suo passo.
                    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
                }
            }

            Item { width: 1; height: Theme.Effects.space1 }

            // «Ripristina» a sinistra e «Mantieni» a destra, ma è Ripristina
            // l'azione che scatta da sola: chi non risponde non sta
            // scegliendo, sta subendo, e va riportato dove stava.
            Row {
                anchors.right: parent.right
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "revert", "primary": false },
                        { "id": "keep",   "primary": true }
                    ]

                    delegate: Rectangle {
                        id: btn
                        required property var modelData

                        readonly property bool primary: modelData.primary
                        readonly property color tone: primary ? Theme.Colors.accent
                                                              : Theme.Colors.textMuted

                        width: btnLabel.implicitWidth + Theme.Effects.space5
                        height: 34
                        radius: Theme.Effects.radiusXS

                        color: btnMouse.containsMouse ? Qt.alpha(tone, 0.18)
                             : primary ? Qt.alpha(tone, 0.10)
                             : "transparent"
                        border.width: primary ? 1 : 0
                        border.color: Qt.alpha(tone, 0.45)

                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: btnLabel
                            anchors.centerIn: parent
                            text: btn.primary ? (guard.it ? "Mantieni" : "Keep it")
                                              : (guard.it ? "Ripristina" : "Put it back")
                            color: btn.primary ? Theme.Colors.text : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeMD
                        }

                        MouseArea {
                            id: btnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (btn.primary)
                                    guard.keep();
                                else
                                    guard.revert();
                            }
                        }
                    }
                }
            }
        }
    }
}
