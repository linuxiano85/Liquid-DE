import QtQuick
import Quickshell

import "../theme" as Theme
import "../ui" as Ui
import "../core" as Core

// Lettore — un messaggio aperto.
//
// L'HTML arriva già sanificato dal demone (niente script, niente moduli,
// niente CSS esterno, immagini remote spente) e qui lo disegna il testo
// ricco di Qt, che non esegue codice e non carica niente da solo. È più
// semplice di un browser, ed è il punto: un'email non è una pagina web.
Item {
    id: lettore

    required property var posta
    readonly property var m: lettore.posta.dettaglio

    /// Link ingannevole cliccato: si chiede prima di aprirlo.
    property string sospetto: ""
    property string sospettoVero: ""

    function apriLink(l) {
        if (l.indexOf("mailto:") === 0) {
            var indirizzo = decodeURIComponent(l.substring(7).split("?")[0]);
            lettore.posta.scrivi({ "to": indirizzo });
            return;
        }
        var veri = lettore.m && lettore.m.deceptiveTargets ? lettore.m.deceptiveTargets : {};
        if (veri[l] !== undefined) {
            lettore.sospetto = l;
            lettore.sospettoVero = veri[l];
            return;
        }
        Qt.openUrlExternally(l);
    }

    function dimensione(n) {
        if (n < 1024) return n + " B";
        if (n < 1024 * 1024) return Math.round(n / 1024) + " KB";
        return (n / 1024 / 1024).toFixed(1).replace(".", ",") + " MB";
    }

    function destinatari() {
        var x = lettore.m;
        if (!x) return "";
        var tutti = (x.to || []).concat(x.cc || []);
        return tutti.join(", ");
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.window
    }

    Text {
        anchors.centerIn: parent
        visible: !lettore.m
        text: lettore.posta.aprendo ? "Apro il messaggio…" : "Scegli un messaggio da leggere."
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeMD
    }

    Item {
        anchors.fill: parent
        visible: !!lettore.m

        // ── Azioni ───────────────────────────────────────────────────
        Flow {
            id: azioni
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space3
            spacing: Theme.Effects.space2
            Pulsante { icona: "back"; testo: "Rispondi"; onClicked: lettore.posta.rispondi(false) }
            Pulsante { icona: "user"; testo: "A tutti"; onClicked: lettore.posta.rispondi(true) }
            Pulsante { icona: "share"; testo: "Inoltra"; onClicked: lettore.posta.inoltra() }
            Pulsante {
                icona: "archive"; tooltip: "Archivia"
                spento: !lettore.posta.haCartella("archive") || (lettore.m && lettore.m.folderRole === "archive")
                onClicked: lettore.posta.archivia()
            }
            Pulsante { icona: "trash"; tooltip: lettore.m && lettore.m.folderRole === "trash" ? "Elimina per sempre" : "Nel Cestino"
                       tinta: Theme.Colors.danger; onClicked: lettore.posta.elimina() }
            Pulsante {
                icona: "mail"
                tooltip: "Segna come non letto"
                onClicked: lettore.posta.segna({ "seen": false })
            }
            Pulsante {
                icona: "star"
                tooltip: lettore.m && lettore.m.flagged ? "Togli importante" : "Importante"
                active: !!(lettore.m && lettore.m.flagged)
                onClicked: lettore.posta.segna({ "flagged": !(lettore.m && lettore.m.flagged) })
            }
            Pulsante {
                testo: lettore.m && lettore.m.adMarked ? "Non è pubblicità" : "È pubblicità"
                tinta: Theme.Colors.warning
                onClicked: lettore.posta.pubblicita(!(lettore.m && lettore.m.adMarked))
            }
        }

        // ── Intestazione ─────────────────────────────────────────────
        Column {
            id: testa
            anchors.top: azioni.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space4
            anchors.topMargin: Theme.Effects.space2
            spacing: Theme.Effects.space1
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: lettore.m ? (lettore.m.subject || "(senza oggetto)") : ""
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightSemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: lettore.m ? ((lettore.m.fromName ? lettore.m.fromName + "  <" + lettore.m.fromAddress + ">"
                                                        : (lettore.m.fromAddress || "")))
                                : ""
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: lettore.m ? ("a " + lettore.destinatari() + "  ·  "
                                   + new Date(lettore.m.date).toLocaleString(Qt.locale(Core.Strings.lang === "it" ? "it_IT" : "en_GB"), "dddd d MMMM yyyy, HH:mm"))
                                : ""
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        // ── Avvisi: immagini bloccate, link ingannevoli, protezioni ──
        Column {
            id: avvisi
            anchors.top: testa.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space4
            anchors.topMargin: Theme.Effects.space3
            spacing: Theme.Effects.space2

            Rectangle {
                visible: !!(lettore.m && lettore.m.remoteImagesBlocked > 0 && !lettore.posta.immaginiRemote)
                width: parent.width
                height: 34
                radius: Theme.Effects.radiusSM
                color: Theme.Colors.raised
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    text: (lettore.m ? lettore.m.remoteImagesBlocked : 0) + " immagini remote bloccate"
                          + (lettore.m && lettore.m.trackersRemoved > 0
                             ? " · " + lettore.m.trackersRemoved + " pixel spia tolti" : "")
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                Pulsante {
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    testo: "Mostra"
                    onClicked: lettore.posta.mostraImmagini()
                }
            }
            Rectangle {
                visible: !!(lettore.m && lettore.m.deceptiveLinks > 0)
                width: parent.width
                height: ingannoTesto.implicitHeight + 16
                radius: Theme.Effects.radiusSM
                color: Qt.alpha(Theme.Colors.danger, 0.12)
                Text {
                    id: ingannoTesto
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: Theme.Effects.space3
                    wrapMode: Text.WordWrap
                    text: "Attenzione: " + (lettore.m ? lettore.m.deceptiveLinks : 0)
                          + " link mostrano un indirizzo ma portano altrove. Tipico delle truffe: "
                          + "prima di aprirli te lo chiedo."
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }

        // ── Corpo ────────────────────────────────────────────────────
        Flickable {
            id: scorri
            anchors.top: avvisi.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: allegati.top
            anchors.margins: Theme.Effects.space3
            clip: true
            contentHeight: carta.height
            boundsBehavior: Flickable.StopAtBounds

            // L'HTML delle email presume uno sfondo bianco: lo si mette su un
            // foglio chiaro, anche con il tema scuro (come fanno tutti).
            Rectangle {
                id: carta
                width: scorri.width
                height: corpo.implicitHeight + Theme.Effects.space4 * 2
                radius: Theme.Effects.radiusSM
                color: lettore.html ? "#ffffff" : "transparent"
                Text {
                    id: corpo
                    x: Theme.Effects.space4
                    y: Theme.Effects.space4
                    width: parent.width - Theme.Effects.space4 * 2
                    wrapMode: Text.Wrap
                    textFormat: lettore.html ? Text.RichText : Text.PlainText
                    text: lettore.m ? (lettore.html ? lettore.m.html : (lettore.m.text || "")) : ""
                    color: lettore.html ? "#1f2328" : Theme.Colors.text
                    linkColor: lettore.html ? "#0b57d0" : Theme.Colors.accent
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    onLinkActivated: function (l) { lettore.apriLink(l); }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: corpo.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                    }
                }
            }
        }
        Ui.Scorrimento {
            bersaglio: scorri
            anchors.right: scorri.right
            anchors.top: scorri.top
            anchors.bottom: scorri.bottom
        }

        // ── Allegati ─────────────────────────────────────────────────
        Flow {
            id: allegati
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.Effects.space3
            spacing: Theme.Effects.space2
            height: lettore.visibili.length > 0 ? implicitHeight : 0
            Repeater {
                model: lettore.visibili
                delegate: Rectangle {
                    required property var modelData
                    width: Math.min(280, fila.implicitWidth + Theme.Effects.space3 * 2)
                    height: 44
                    radius: Theme.Effects.radiusSM
                    color: Theme.Colors.raised
                    border.color: Theme.Colors.edge
                    Row {
                        id: fila
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.Effects.space3
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.mime.indexOf("image/") === 0 ? "image"
                                : modelData.mime === "application/pdf" ? "pdf" : "document"
                            width: 18; height: 18
                            color: Theme.Colors.accent
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: Math.min(150, implicitWidth)
                                elide: Text.ElideMiddle
                                text: modelData.filename
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                            Text {
                                text: lettore.dimensione(modelData.size)
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                        Pulsante {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            icona: "download"
                            tooltip: "Salva in Scaricati"
                            onClicked: lettore.posta.salvaAllegato(modelData, false)
                        }
                        Pulsante {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            icona: "expand"
                            tooltip: "Apri"
                            onClicked: lettore.posta.salvaAllegato(modelData, true)
                        }
                    }
                }
            }
        }
    }

    readonly property bool html: !!(lettore.m && lettore.m.html)
    readonly property var visibili: {
        var x = lettore.m;
        if (!x || !x.attachments) return [];
        return x.attachments.filter(function (a) { return a.kind === "file" || a.kind === "message"; });
    }

    // ── Conferma per i link ingannevoli ──────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: lettore.sospetto !== ""
        color: Theme.Colors.scrim
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 40)
            height: dentro.implicitHeight + Theme.Effects.space5 * 2
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.color: Theme.Colors.edge
            Column {
                id: dentro
                anchors.fill: parent
                anchors.margins: Theme.Effects.space5
                spacing: Theme.Effects.space3
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Questo link non va dove dice"
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                    text: "Porta a: " + lettore.sospettoVero + "\n\n" + lettore.sospetto
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                Row {
                    spacing: Theme.Effects.space2
                    Pulsante { testo: "Non aprire"; active: true; onClicked: lettore.sospetto = "" }
                    Pulsante {
                        testo: "Apri comunque"
                        tinta: Theme.Colors.danger
                        onClicked: { Qt.openUrlExternally(lettore.sospetto); lettore.sospetto = ""; }
                    }
                }
            }
        }
    }
}
