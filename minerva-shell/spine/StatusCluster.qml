import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// StatusCluster — Rete, audio e batteria in un unico bersaglio.
//
// Tre icone, un solo pulsante, un solo pannello. La tentazione è dare a
// ciascuna il proprio menu — è quello che fanno quasi tutte le barre — ma
// significa che l'utente deve ricordare tre punti diversi da colpire per tre
// cose che, nella sua testa, sono la stessa: «le impostazioni del computer».
//
// La percentuale della batteria è scritta a lettere perché è l'unico numero
// della barra che si controlla di proposito. Rete e audio parlano per icona:
// se ne guarda la forma, non il valore.
Item {
    id: cluster

    property bool active: false
    signal clicked()

    readonly property bool hovered: mouse.containsMouse

    implicitWidth: content.implicitWidth + Theme.Effects.space4 * 2
    implicitHeight: Theme.Effects.barButton

    readonly property color batteryColor: {
        if (Core.SystemState.batteryCharging)
            return Theme.Colors.positive;
        if (Core.SystemState.batteryPercent <= 10)
            return Theme.Colors.danger;
        if (Core.SystemState.batteryPercent <= 25)
            return Theme.Colors.warning;
        return Theme.Colors.textMuted;
    }

    // Alone quando il pannello è aperto
    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 14
        height: parent.height + 14
        radius: height / 2
        color: Theme.Colors.accent
        opacity: cluster.active ? 0.14 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: cluster.active ? Qt.alpha(Theme.Colors.accent, 0.16)
             : mouse.pressed ? Theme.Colors.pressed
             : cluster.hovered ? Theme.Colors.hover
             : Theme.Colors.sunken
        border.width: cluster.active ? 1 : 0
        border.color: Qt.alpha(Theme.Colors.accent, 0.45)

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.Effects.space3

        // ── Rete ─────────────────────────────────────────────────────────
        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 17; height: 17
            name: Core.SystemState.networkWired ? "globe" : "wifi"
            color: Core.SystemState.networkConnected ? Theme.Colors.textMuted
                                                     : Theme.Colors.textFaint
            // Scollegata è uno stato, non una sfumatura: va detto anche
            // all'icona classica, che i nostri colori non li prende.
            spenta: !Core.SystemState.networkConnected
        }

        // ── Bluetooth: presente solo quando è acceso ─────────────────────
        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 15
            name: "bluetooth"
            visible: Core.SystemState.bluetoothOn
            color: Core.SystemState.bluetoothDevice !== "" ? Theme.Colors.accent
                                                           : Theme.Colors.textFaint
        }

        // ── Audio ────────────────────────────────────────────────────────
        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 17; height: 17
            name: (Core.SystemState.muted || Core.SystemState.volume === 0)
                  ? "muted" : "volume"
            color: Core.SystemState.muted ? Theme.Colors.textFaint : Theme.Colors.textMuted
            spenta: Core.SystemState.muted
        }

        // ── Batteria ─────────────────────────────────────────────────────
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1
            visible: Core.SystemState.hasBattery

            Item {
                width: 22; height: 17
                anchors.verticalCenter: parent.verticalCenter

                // Questa resta disegnata da noi anche con le icone classiche,
                // e non è una preferenza di stile: non è un'icona, è uno
                // strumento. Il rettangolo qui sotto riempie la sagoma in
                // proporzione alla carica, con misure prese da QUESTO
                // tracciato. La batteria di un tema è disegnata dove le pare —
                // Breeze la fa tonda — e il riempimento le finisce di
                // traverso, come una barra chiara appoggiata sopra un cerchio.
                Ui.Icon {
                    anchors.fill: parent
                    name: "battery"
                    color: cluster.batteryColor
                    alwaysDrawn: true
                }

                // Riempimento proporzionale dentro la sagoma
                Rectangle {
                    x: 3.2
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4.6
                    width: Math.max(1, 12.2 * Math.max(0, Core.SystemState.batteryPercent) / 100)
                    radius: 1
                    color: cluster.batteryColor

                    Behavior on width {
                        NumberAnimation { duration: Theme.Motion.panel }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Core.SystemState.batteryPercent >= 0
                      ? Core.SystemState.batteryPercent + "%" : ""
                color: cluster.batteryColor
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cluster.clicked()

        // Rotella sul gruppo: regola il volume senza aprire nulla.
        onWheel: function(wheel) {
            Core.SystemState.setVolume(Core.SystemState.volume
                                       + (wheel.angleDelta.y > 0 ? 5 : -5));
        }
    }
}
