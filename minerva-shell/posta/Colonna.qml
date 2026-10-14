import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// Colonna — scrivere, gli account con le loro cartelle, il filtro.
Item {
    id: colonna

    required property var posta

    readonly property var _icone: ({
        "inbox": "mail", "sent": "share", "drafts": "document", "archive": "archive",
        "spam": "info", "trash": "trash", "other": "folder"
    })
    readonly property var _nomi: ({
        "inbox": "Posta in arrivo", "sent": "Inviata", "drafts": "Bozze", "archive": "Archivio",
        "spam": "Spam", "trash": "Cestino"
    })

    function statoAccount(id) {
        var s = colonna.posta.stati[id];
        if (!s) return "";
        switch (s.phase) {
        case "connecting": return "Collegamento…";
        case "syncing": return "Aggiorno…";
        case "watching": return "";
        case "offline": return "Offline · riprovo tra " + Math.round(s.retryInSeconds || 0) + " s";
        case "authFailed": return "Password non accettata";
        case "oauthReauth": return "Accedi di nuovo con Google";
        case "untrustedCertificate": return "Certificato cambiato";
        case "needsPassword": return "Manca la password";
        case "keyringLocked": return "Portachiavi bloccato";
        case "keyringUnavailable": return "Nessun portachiavi";
        default: return "";
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.sunken
    }

    Pulsante {
        id: scrivi
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space3
        height: 40
        icona: "plus"
        testo: "Scrivi"
        active: true
        onClicked: colonna.posta.scrivi({})
    }

    Flickable {
        id: scorri
        anchors.top: scrivi.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: piede.top
        anchors.topMargin: Theme.Effects.space3
        clip: true
        contentHeight: elenco.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: elenco
            width: scorri.width
            spacing: Theme.Effects.space1

            Repeater {
                model: colonna.posta.accounts
                delegate: Column {
                    id: acc
                    required property var modelData
                    width: elenco.width
                    spacing: 1

                    Item {
                        width: parent.width
                        height: 40
                        Text {
                            x: Theme.Effects.space4
                            y: 10
                            width: parent.width - x - Theme.Effects.space3
                            elide: Text.ElideRight
                            text: acc.modelData.email
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightSemiBold
                            font.letterSpacing: Theme.Typography.trackingLabel
                        }
                        Text {
                            x: Theme.Effects.space4
                            y: 25
                            visible: text !== ""
                            text: colonna.statoAccount(acc.modelData.id)
                            color: {
                                var s = colonna.posta.stati[acc.modelData.id];
                                var ph = s ? s.phase : "";
                                return ph === "connecting" || ph === "syncing" || ph === "offline"
                                       ? Theme.Colors.textFaint : Theme.Colors.danger;
                            }
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            // Gmail che non entra più: un clic e si rifà
                            // l'accesso con Google, con l'indirizzo già scritto.
                            MouseArea {
                                anchors.fill: parent
                                readonly property string fase: {
                                    var s = colonna.posta.stati[acc.modelData.id];
                                    return s ? s.phase : "";
                                }
                                enabled: fase === "oauthReauth"
                                         || (fase === "authFailed" && acc.modelData.provider === "gmail")
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    colonna.posta.nuovoIndirizzo = acc.modelData.email;
                                    colonna.posta.nuovoAccount = true;
                                }
                            }
                        }
                    }

                    Repeater {
                        model: colonna.posta.cartelle.filter(function (f) {
                            return f.accountId === acc.modelData.id;
                        })
                        delegate: Item {
                            id: voce
                            required property var modelData
                            readonly property bool scelta: modelData.id === colonna.posta.cartella
                                                           && colonna.posta.ricerca === ""
                            width: acc.width
                            height: 34
                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.rightMargin: Theme.Effects.space2
                                radius: Theme.Effects.radiusSM
                                color: voce.scelta ? Theme.Colors.selected
                                     : sopra.containsMouse ? Theme.Colors.hover : "transparent"
                            }
                            Ui.Icon {
                                x: Theme.Effects.space4
                                anchors.verticalCenter: parent.verticalCenter
                                name: colonna._icone[voce.modelData.role] || "folder"
                                width: 15; height: 15
                                color: voce.scelta ? Theme.Colors.accent : Theme.Colors.textMuted
                            }
                            Text {
                                x: Theme.Effects.space4 + 24
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - conta.width - Theme.Effects.space5
                                elide: Text.ElideRight
                                text: colonna._nomi[voce.modelData.role] || voce.modelData.name
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: voce.modelData.unread > 0 && voce.modelData.role !== "trash"
                                             && voce.modelData.role !== "spam"
                                             ? Theme.Typography.weightSemiBold : Theme.Typography.weightRegular
                            }
                            Text {
                                id: conta
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.Effects.space4
                                anchors.verticalCenter: parent.verticalCenter
                                visible: voce.modelData.unread > 0 && voce.modelData.role !== "trash"
                                         && voce.modelData.role !== "sent" && voce.modelData.role !== "drafts"
                                text: voce.modelData.unread
                                color: Theme.Colors.accent
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                                font.weight: Theme.Typography.weightSemiBold
                            }
                            MouseArea {
                                id: sopra
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: colonna.posta.scegliCartella(voce.modelData.id)
                            }
                        }
                    }
                    Item { width: 1; height: Theme.Effects.space2 }
                }
            }

            Pulsante {
                x: Theme.Effects.space3
                icona: "plus"
                testo: "Aggiungi un account"
                solido: false
                onClicked: colonna.posta.nuovoAccount = true
            }
        }
    }

    // ── Filtro delle pubblicità ──────────────────────────────────────
    Column {
        id: piede
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space3
        spacing: Theme.Effects.space1

        Text {
            text: "PUBBLICITÀ"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.letterSpacing: Theme.Typography.trackingLabel
        }
        Row {
            spacing: 2
            Repeater {
                model: [["off", "Spento"], ["mark", "Segna"], ["move", "Cestino"]]
                delegate: Pulsante {
                    required property var modelData
                    height: 28
                    horizontalPadding: Theme.Effects.space2
                    testo: modelData[1]
                    solido: false
                    active: colonna.posta.filtro.mode === modelData[0]
                    onClicked: colonna.posta.modoFiltro(modelData[0])
                }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
                var f = colonna.posta.filtro;
                if (!f.mode) return "";
                var oggi = f.today || {};
                var parti = [];
                if (oggi.marked > 0) parti.push(oggi.marked + " segnate oggi");
                if (oggi.moved > 0) parti.push(oggi.moved + " nel Cestino oggi");
                if (f.mode === "move" && !f.trained)
                    parti.push("Sposta solo quelle che Gmail mette in Promozioni finché non ha imparato "
                               + "(" + f.trainedAds + "/" + f.minTrainedPerClass + ")");
                return parti.join(" · ");
            }
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.Colors.edge
    }
}
