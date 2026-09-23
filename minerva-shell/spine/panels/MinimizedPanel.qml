import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// MinimizedPanel — Le finestre ridotte a icona.
//
// Senza questo elenco il pulsante «riduci» sarebbe una trappola: la finestra
// sparisce e non c'è modo di riaverla se non conoscendo la scrivania speciale
// dove è finita. Un comando che nasconde qualcosa deve sempre avere accanto il
// comando che la riporta indietro.
Item {
    id: panel

    property var spine: null

    readonly property real implicitPanelHeight:
        Theme.Effects.space5 + 26 + Theme.Effects.space3
        + Math.max(1, Core.Windows.minimized.length) * 45
        + Theme.Effects.space4

    Component.onCompleted: Core.Windows.refresh()

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space5
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: (Core.Strings.lang === "it" ? "Ridotte a icona"
                                              : "Minimised").toUpperCase()
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightBold
            font.letterSpacing: Theme.Typography.trackingLabel
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: allText.implicitWidth + Theme.Effects.space3
            height: 24
            radius: Theme.Effects.radiusXS
            visible: Core.Windows.minimized.length > 1
            color: allMouse.containsMouse ? Theme.Colors.hover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Text {
                id: allText
                anchors.centerIn: parent
                text: Core.Strings.lang === "it" ? "Ripristina tutte" : "Restore all"
                color: allMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: allMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Core.Windows.restoreAll();
                    if (panel.spine)
                        panel.spine.close();
                }
            }
        }
    }

    Ui.Scorrimento {
        bersaglio: elencoRidotte
        anchors {
            right: elencoRidotte.right
            top: elencoRidotte.top
            bottom: elencoRidotte.bottom
        }
    }

    ListView {
        id: elencoRidotte
        anchors.top: header.bottom
        anchors.topMargin: Theme.Effects.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        anchors.bottomMargin: Theme.Effects.space4
        clip: true
        spacing: 1
        model: Core.Windows.minimized
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: entry
            required property var modelData

            width: ListView.view.width
            height: 44
            radius: Theme.Effects.radiusSM
            color: entryMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Ui.Icon {
                id: entryGlyph
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17
                name: "restore"
                color: entryMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textFaint
            }

            Text {
                anchors.left: entryGlyph.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: entry.modelData.title || entry.modelData.appClass
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: entryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Core.Windows.restore(entry.modelData.address);
                    if (panel.spine)
                        panel.spine.close();
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: Core.Windows.minimized.length === 0
            text: Core.Strings.lang === "it" ? "Nessuna finestra ridotta"
                                             : "No minimised windows"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }
}
