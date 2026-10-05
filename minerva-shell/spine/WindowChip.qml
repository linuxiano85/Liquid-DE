import QtQuick
import "../theme" as Theme
import "../core" as Core

// WindowChip — Il titolo della finestra attiva, nella barra della scrivania.
//
// Clic destro: il menu della finestra. I pulsanti riduci, ingrandisci e
// chiudi stanno sulla barra del titolo nativa di ogni finestra, una volta
// sola (5 ottobre 2026: qui c'erano dei doppioni che si vedevano solo con
// le barre spente, e le barre non si spengono più).
//
// Si spegne dalle Impostazioni: chi vive di scorciatoie lo trova rumore.
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
    }

    /// Il tasto destro sul nome chiede alla shell il menu della finestra.
    signal menuRequested(point where)
}
