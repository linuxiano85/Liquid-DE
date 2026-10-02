import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// NotificationsPanel — Le notifiche ricevute.
//
// Il modello vive nella shell (una sola coda per tutta la sessione) e viene
// passato qui dalla Spine. Il pannello si limita a mostrarlo: se possedesse
// la lista, chiudendolo si perderebbero le notifiche non lette.
Item {
    id: panel

    property var spine: null

    /// Con la coda vuota la lingua scende appena: quattrocento pixel di nulla
    /// per dire «non è successo niente» sono quattrocento pixel sprecati.
    readonly property real implicitPanelHeight:
        Core.Notifications.items.length === 0
        ? 200
        : Theme.Effects.space5 + 26 + Theme.Effects.space3
          + list.contentHeight + Theme.Effects.space4

    Component.onCompleted: Core.Notifications.markAllRead()

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
            text: (Core.Strings.lang === "it" ? "Notifiche" : "Notifications").toUpperCase()
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightBold
            font.letterSpacing: Theme.Typography.trackingLabel
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: clearText.implicitWidth + Theme.Effects.space3
            height: 24
            radius: Theme.Effects.radiusXS
            visible: Core.Notifications.items.length > 0
            color: clearMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.16) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Text {
                id: clearText
                anchors.centerIn: parent
                text: Core.Strings.lang === "it" ? "Cancella tutte" : "Clear all"
                color: clearMouse.containsMouse ? Theme.Colors.danger : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Core.Notifications.clear()
            }
        }
    }

    // Le notifiche crescono dal basso (`verticalLayoutDirection`), e il
    // pollice lo sa: `Scorrimento` conta da `originY`, non da zero.
    Ui.Scorrimento {
        bersaglio: list
        anchors {
            right: list.right
            top: list.top
            bottom: list.bottom
        }
    }

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.topMargin: Theme.Effects.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        anchors.bottomMargin: Theme.Effects.space4
        clip: true
        spacing: Theme.Effects.space2
        model: Core.Notifications.items
        boundsBehavior: Flickable.StopAtBounds
        verticalLayoutDirection: ListView.BottomToTop   // la più recente in cima

        delegate: Rectangle {
            id: note
            required property var modelData
            required property int index

            /// Cliccando succede qualcosa? Da qui dipendono il puntatore e il
            /// fatto che l'area accetti i clic.
            readonly property bool apribile:
                Core.Notifications.siPuoAprire(note.modelData)

            width: ListView.view.width
            implicitHeight: noteColumn.implicitHeight + Theme.Effects.space4 * 2
            height: implicitHeight
            radius: Theme.Effects.radiusMD
            color: noteMouse.containsMouse ? Theme.Colors.raisedHigh : Theme.Colors.raised
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            readonly property color urgencyTone: {
                if (note.modelData.urgency === 2) return Theme.Colors.danger;
                if (note.modelData.urgency === 0) return Theme.Colors.textFaint;
                return Theme.Colors.accent;
            }

            // Filo verticale colorato: dice l'urgenza senza colorare tutto
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: parent.height - Theme.Effects.space4
                radius: 1.5
                color: note.urgencyTone
            }

            Column {
                id: noteColumn
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space4 + 4
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: note.modelData.appName || ""
                    elide: Text.ElideRight
                    color: note.urgencyTone
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                    font.weight: Theme.Typography.weightBold
                    font.letterSpacing: Theme.Typography.trackingLabel
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: note.modelData.summary || ""
                    elide: Text.ElideRight
                    visible: text !== ""
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightSemiBold
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: note.modelData.body || ""
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            // Chiusura della singola notifica, visibile solo al passaggio
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.Effects.space2
                width: 20; height: 20
                radius: 10
                visible: noteMouse.containsMouse
                color: closeMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.25)
                                                : Theme.Colors.raisedHigh

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 12; height: 12
                    name: "close"
                    color: closeMouse.containsMouse ? Theme.Colors.danger : Theme.Colors.textMuted
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Notifications.remove(note.index)
                }
            }

            // ── Il clic sulla riga APRE ──────────────────────────────
            //
            // Era `acceptedButtons: Qt.NoButton`: serviva solo a far comparire
            // la X al passaggio. Adesso cliccando succede quello che il
            // programma ha chiesto che succeda — l'azione predefinita — o si
            // apre il file di cui la notifica parla.
            //
            // Giacomo, 2 settembre 2026: «e questo per tutte le notifiche»,
            // non solo per l'avviso che compare e sparisce.
            //
            // ── E la X continua a chiudere ───────────────────────────────
            //
            // Questa area riempie tutta la riga ed è dichiarata DOPO il
            // pulsante di chiusura, quindi gli starebbe sopra e gli
            // ruberebbe il clic: la X smetterebbe di chiudere, e nessun
            // errore lo direbbe. `z: -1` la rimette sotto — il pulsante è
            // piccolo e sta in un angolo, il resto della riga resta tutto
            // cliccabile.
            MouseArea {
                id: noteMouse
                anchors.fill: parent
                hoverEnabled: true
                z: -1
                acceptedButtons: note.apribile ? Qt.LeftButton : Qt.NoButton
                cursorShape: note.apribile ? Qt.PointingHandCursor
                                           : Qt.ArrowCursor
                onClicked: {
                    Core.Notifications.apri(note.modelData);
                    // Il pannello si chiude: si è chiesto di andare da
                    // un'altra parte, e restare aperti sopra la finestra
                    // appena aperta sarebbe di intralcio.
                    if (panel.spine)
                        panel.spine.close();
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - Theme.Effects.space6
            spacing: Theme.Effects.space2
            visible: Core.Notifications.items.length === 0

            Ui.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 32
                name: "bell"
                color: Theme.Colors.textFaint
                alwaysDrawn: true
                opacity: 0.5
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Core.Strings.lang === "it" ? "Nessuna notifica" : "No notifications"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }
        }
    }
}
