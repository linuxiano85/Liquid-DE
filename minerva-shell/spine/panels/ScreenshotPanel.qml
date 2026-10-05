import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// ScreenshotPanel — Che cosa fotografare, e fra quanto.
//
// Prima il tasto Stamp faceva una cosa sola e la faceva subito: tutto lo
// schermo, adesso. Va benissimo finché è quello che si voleva; il resto delle
// volte si scopre di aver fotografato tre finestre per mostrarne una, e si
// ritaglia a mano dopo.
//
// Qui si sceglie prima. Tre cose sole — tutto, una porzione, una finestra —
// perché sono le tre che esistono davvero; e un ritardo, che serve per
// fotografare quello che sparisce appena si tocca la tastiera: un menu
// aperto, un suggerimento, una tendina.
//
// ── La cosa che rende tutto questo difficile ──────────────────────────────
//
// Questo pannello è disegnato da Minerva, e `grim` fotografa anche i pannelli
// di Minerva. Se si scattasse subito, in ogni schermata ci sarebbe il
// pannello delle schermate. Perciò si chiude PRIMA e si aspetta che sia
// davvero sparito dallo schermo: chiudere è un'animazione, non un istante, e
// scattare durante l'animazione lascia un fantasma semitrasparente in un
// angolo. `chiusuraMs` è quel tempo, e non è una cifra a caso — è la durata
// dell'animazione dei pannelli più un fotogramma di margine.
Item {
    id: panel

    property var spine: null

    readonly property bool it: Core.Strings.lang === "it"

    // `stack` è ancorato con un `topMargin` che la sua `implicitHeight` non
    // conosce: si somma qui, e sotto ci vuole lo stesso respiro.
    readonly property real implicitPanelHeight: stack.implicitHeight
                                                + Theme.Effects.space5
                                                + Theme.Effects.space4

    /// Secondi di attesa scelti. Zero = subito.
    property int ritardo: 0

    readonly property var scelte: [
        { "id": "schermo",  "icon": "screen",
          "it": "Tutto lo schermo",  "en": "Whole screen",
          "itNota": "Così com'è adesso, barra compresa",
          "enNota": "Exactly as it is now, bar included" },
        { "id": "area",     "icon": "crop",
          "it": "Una porzione",      "en": "A region",
          "itNota": "La scegli trascinando col mouse",
          "enNota": "Drag with the mouse to choose it" },
        { "id": "finestra", "icon": "window",
          "it": "Solo una finestra", "en": "A single window",
          "itNota": "Quella attiva, senza il resto della scrivania",
          "enNota": "The active one, without the rest of the desktop" }
    ]

    readonly property var ritardi: [
        { "value": 0,  "it": "Subito", "en": "Now" },
        { "value": 3,  "it": "3 s",    "en": "3 s" },
        { "value": 10, "it": "10 s",   "en": "10 s" }
    ]

    function scatta(modo) {
        // Chiedere e non fare: chi scatta è la shell, che non si chiude
        // insieme a questo pannello. Vedi il commento su
        // `screenshotRequested` in Spine.qml — è il motivo per cui il primo
        // tentativo non scattava mai.
        if (panel.spine)
            panel.spine.screenshotRequested(modo, panel.ritardo);
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
            model: panel.scelte

            delegate: Rectangle {
                id: scelta
                required property var modelData

                width: parent.width
                height: 56
                radius: Theme.Effects.radiusSM

                color: hover.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.11)
                                           : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    id: glyph
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    name: scelta.modelData.icon
                    color: hover.containsMouse ? Theme.Colors.accent
                                               : Theme.Colors.textMuted
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                }

                Column {
                    anchors.left: glyph.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: panel.it ? scelta.modelData.it : scelta.modelData.en
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightMedium
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: panel.it ? scelta.modelData.itNota
                                       : scelta.modelData.enNota
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.scatta(scelta.modelData.id)
                }
            }
        }

        // ── Ritardo ──────────────────────────────────────────────────────

        Item { width: 1; height: Theme.Effects.space2 }

        Text {
            leftPadding: Theme.Effects.space3
            text: panel.it ? "Fra quanto" : "After"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }

        Item { width: 1; height: Theme.Effects.space2 }

        Row {
            leftPadding: Theme.Effects.space3
            spacing: 6

            Repeater {
                model: panel.ritardi

                delegate: Rectangle {
                    id: chip
                    required property var modelData

                    readonly property bool selected: panel.ritardo === chip.modelData.value

                    implicitWidth: chipText.implicitWidth + 24
                    height: 30
                    radius: Theme.Effects.radiusSM

                    color: chip.selected ? Qt.alpha(Theme.Colors.accent, 0.18)
                         : chipMouse.containsMouse ? Theme.Colors.hover
                         : Theme.Colors.raised
                    border.width: 1
                    border.color: chip.selected ? Theme.Colors.accent : Theme.Colors.edge

                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: panel.it ? chip.modelData.it : chip.modelData.en
                        color: chip.selected ? Theme.Colors.accent : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.ritardo = chip.modelData.value
                    }
                }
            }
        }

        Item { width: 1; height: Theme.Effects.space2 }

        // Dove finisce il file. Non è una nota di servizio: senza, la
        // schermata è un lampo e poi non si sa dove sia andata, ed è la prima
        // domanda che si fa chiunque.
        Text {
            leftPadding: Theme.Effects.space3
            rightPadding: Theme.Effects.space3
            width: parent.width
            wrapMode: Text.WordWrap
            text: panel.it
                  ? "Si salva in Immagini › Schermate, e una copia va anche negli appunti."
                  : "Saved in Pictures › Screenshots, and a copy goes to the clipboard too."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }
}
