import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// WindowChip — La finestra attiva, con i suoi tre pulsanti.
//
// Riduci a icona, ingrandisci, chiudi: i tre comandi che chiunque abbia usato
// un computer si aspetta di trovare, e che in un compositore a piastrelle non
// esistono da nessuna parte.
//
// Stanno nella barra e non sulla finestra, e la differenza è a favore della
// barra: sono sempre nello stesso punto (il muscolo se lo ricorda), non
// coprono mai il contenuto, e valgono anche per le finestre affiancate, che
// una cornice non ce l'hanno.
//
// Si spengono dalle Impostazioni: chi vive di scorciatoie li trova rumore.
Item {
    id: chip

    property var spine: null

    readonly property bool hasWindow: Core.Windows.hasActive
                                      && Core.Windows.activeTitle !== ""
    readonly property bool enabled_: Core.Ipc.get("windowControls.enabled", true)

    visible: hasWindow && enabled_
    implicitWidth: visible ? row.implicitWidth + Theme.Effects.space2 * 2 : 0
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight

    // Compare scivolando: la barra non deve «sobbalzare» a ogni cambio di
    // finestra, ma il chip che appare dal nulla è peggio.
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusFull
        color: hover.containsMouse ? Theme.Colors.raised : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.Effects.space2

        // Nome della finestra. Il tasto destro apre il menu della finestra.
        //
        // Il tasto sinistro la rendeva libera o affiancata. Non più: il tiling
        // non esiste (`core/WindowRules.qml`), e quel clic era rimasto l'unico
        // modo di affiancare una finestra in un ambiente che poi non sa come
        // rimetterla a posto. Ci si arrivava anche per sbaglio, perché un nome
        // scritto in una barra non sembra un pulsante.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(label.implicitWidth, 240)
            height: 22

            Text {
                id: label
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: Core.Windows.activeTitle
                color: titleMouse.containsMouse ? Theme.Colors.text
                                                : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
            }

            MouseArea {
                id: titleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(m) {
                    chip.menuRequested(mapToGlobal(m.x, m.y));
                }
            }
        }

        // ── I tre pulsanti ───────────────────────────────────────────────
        //
        // Spariscono quando ogni finestra ha la sua barra del titolo. Non per
        // risparmiare spazio: perché gli stessi tre comandi in due punti dello
        // schermo, con due aspetti diversi, sono la cosa che fa sembrare
        // un'interfaccia messa insieme da pezzi. Uno solo, e sulla finestra.
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            visible: !Core.Ipc.get("windows.titleBars", true)

            Repeater {
                model: [
                    { "id": "minimize", "icon": "minimize", "danger": false },
                    { "id": "maximize", "icon": "maximize", "danger": false },
                    { "id": "close",    "icon": "close",    "danger": true }
                ]

                delegate: Rectangle {
                    id: btn
                    required property var modelData

                    width: 22; height: 22
                    radius: 11

                    readonly property color tone: modelData.danger ? Theme.Colors.danger
                                                                   : Theme.Colors.accent

                    color: btnMouse.pressed ? Qt.alpha(tone, 0.32)
                         : btnMouse.containsMouse ? Qt.alpha(tone, 0.18)
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 12; height: 12
                        thickness: 1.9
                        name: btn.modelData.id === "maximize" && Core.Windows.activeMaximized
                              ? "restore" : btn.modelData.icon
                        color: btnMouse.containsMouse ? btn.tone : Theme.Colors.textFaint
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            switch (btn.modelData.id) {
                            case "minimize": Core.Windows.minimize(); break;
                            case "maximize": Core.Windows.toggleMaximize(); break;
                            case "close":    Core.Windows.close(); break;
                            }
                        }
                    }
                }
            }
        }
    }

    /// Il tasto destro sul nome chiede alla shell il menu della finestra.
    signal menuRequested(point where)
}
