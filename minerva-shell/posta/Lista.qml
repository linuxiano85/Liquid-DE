import QtQuick

import "../theme" as Theme
import "../ui" as Ui
import "../core" as Core

// Lista — i messaggi di una cartella (o i risultati di una ricerca), dal
// più recente. Scorrendo in fondo arriva la pagina successiva.
Item {
    id: lista

    required property var posta

    /// Data breve: l'ora se è oggi, il giorno se è quest'anno, altrimenti
    /// la data intera. Come tutti i client, perché è quello che l'occhio cerca.
    function quando(ms) {
        var d = new Date(ms);
        var oggi = new Date();
        if (d.toDateString() === oggi.toDateString())
            return Qt.formatTime(d, "HH:mm");
        var ieri = new Date(oggi.getTime() - 86400000);
        if (d.toDateString() === ieri.toDateString())
            return "ieri";
        if (d.getFullYear() === oggi.getFullYear())
            return d.toLocaleDateString(Qt.locale(Core.Strings.lang === "it" ? "it_IT" : "en_GB"), "d MMM");
        return Qt.formatDate(d, "dd/MM/yy");
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.panel
    }

    // ── Ricerca ──────────────────────────────────────────────────────
    Item {
        id: testa
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        Ui.Campo {
            id: cerca
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            segnaposto: "Cerca in tutta la posta"
            onCambiato: function (t) { ritardo.restart(); }
            onAccettato: { ritardo.stop(); lista.posta.cerca(cerca.text); }
        }
        Timer {
            id: ritardo
            interval: 250
            onTriggered: lista.posta.cerca(cerca.text)
        }
    }

    Text {
        anchors.centerIn: vista
        visible: vista.count === 0
        width: vista.width - Theme.Effects.space6
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: lista.posta.caricando ? "Carico…"
              : lista.posta.ricerca !== "" ? "Nessun messaggio trovato."
              : lista.posta.sincronizzando ? "Scarico la posta…"
              : "Nessun messaggio."
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeSM
    }

    ListView {
        id: vista
        anchors.top: testa.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: lista.posta.messaggi
        boundsBehavior: Flickable.StopAtBounds
        onAtYEndChanged: if (atYEnd && count > 0) lista.posta.altri()

        delegate: Item {
            id: riga
            required property var modelData
            required property int index
            readonly property bool scelto: modelData.id === lista.posta.aperto
            width: vista.width
            height: 84

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.Effects.space1
                anchors.rightMargin: Theme.Effects.space1
                radius: Theme.Effects.radiusSM
                color: riga.scelto ? Theme.Colors.selected
                     : sopra.containsMouse ? Theme.Colors.hover : "transparent"
            }
            // Non letto: punto colorato a sinistra, come ovunque.
            Rectangle {
                visible: !riga.modelData.seen
                x: Theme.Effects.space2
                y: 20
                width: 8; height: 8; radius: 4
                color: Theme.Colors.accent
            }
            Column {
                x: Theme.Effects.space5
                y: Theme.Effects.space2 + 2
                width: riga.width - x - Theme.Effects.space3
                spacing: 2
                Item {
                    width: parent.width
                    height: chi.implicitHeight
                    Text {
                        id: chi
                        anchors.left: parent.left
                        anchors.right: data_.left
                        anchors.rightMargin: Theme.Effects.space2
                        elide: Text.ElideRight
                        text: riga.modelData.fromName || riga.modelData.fromAddress || "(senza mittente)"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: riga.modelData.seen ? Theme.Typography.weightRegular
                                                         : Theme.Typography.weightSemiBold
                    }
                    Text {
                        id: data_
                        anchors.right: parent.right
                        text: lista.quando(riga.modelData.date)
                        color: riga.modelData.seen ? Theme.Colors.textFaint : Theme.Colors.accent
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
                Row {
                    width: parent.width
                    spacing: Theme.Effects.space1
                    Ui.Icon {
                        visible: riga.modelData.flagged
                        anchors.verticalCenter: parent.verticalCenter
                        name: "star"; filled: true
                        width: 12; height: 12
                        color: Theme.Colors.warning
                    }
                    Ui.Icon {
                        visible: riga.modelData.hasAttachments
                        anchors.verticalCenter: parent.verticalCenter
                        name: "link"
                        width: 12; height: 12
                        color: Theme.Colors.textMuted
                    }
                    Rectangle {
                        visible: riga.modelData.adMarked
                        anchors.verticalCenter: parent.verticalCenter
                        width: pub.implicitWidth + 10
                        height: pub.implicitHeight + 2
                        radius: 4
                        color: Qt.alpha(Theme.Colors.warning, 0.18)
                        Text {
                            id: pub
                            anchors.centerIn: parent
                            text: "Pubblicità?"
                            color: Theme.Colors.warning
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }
                    Text {
                        width: parent.width - x
                        elide: Text.ElideRight
                        text: riga.modelData.subject || "(senza oggetto)"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: riga.modelData.seen ? Theme.Typography.weightRegular
                                                         : Theme.Typography.weightMedium
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: riga.modelData.preview
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
            MouseArea {
                id: sopra
                anchors.fill: parent
                hoverEnabled: true
                onClicked: lista.posta.apri(riga.modelData.id)
            }
        }
    }

    Ui.Scorrimento {
        bersaglio: vista
        anchors.right: vista.right
        anchors.top: vista.top
        anchors.bottom: vista.bottom
    }

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.Colors.edge
    }
}
