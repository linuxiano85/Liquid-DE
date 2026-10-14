import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// Componi — scrivere, rispondere, inoltrare.
//
// Il messaggio lo compone e lo spedisce il demone (testo semplice, sempre a
// 7 bit, con i Ccn mai scritti nel messaggio). Qui si raccolgono i campi.
Item {
    id: componi

    required property var posta
    /// { to, cc, subject, text, replyToId } di partenza (risposta, inoltro).
    property var bozza: ({})

    property var allegati: []
    property bool invio: false
    property string errore: ""
    property bool mostraCcn: false

    signal chiuso()
    signal scegliAllegato()

    function aggiungiAllegato(percorso) {
        if (componi.allegati.indexOf(percorso) >= 0) return;
        componi.allegati = componi.allegati.concat([percorso]);
    }

    function _indirizzi(testo) {
        return String(testo).split(/[,;\n]/).map(function (s) { return s.trim(); })
                            .filter(function (s) { return s !== ""; });
    }

    function _motivo(err) {
        var r = err && err.data ? err.data.reason : "";
        switch (r) {
        case "invalidAddress": return err.message;
        case "authFailed": return "Il server di invio non accetta la password.";
        case "tls": return "Connessione sicura al server di invio non riuscita: messaggio non partito.";
        case "offline": return "Server di invio non raggiungibile: il messaggio resta qui, riprova.";
        case "rejected": return "Il server ha rifiutato il messaggio: " + err.message;
        case "tooLarge": return err.message;
        default: return err && err.message ? err.message : "Invio non riuscito.";
        }
    }

    function invia() {
        if (componi.invio) return;
        componi.errore = "";
        var p = {
            "accountId": componi.posta.accountPerScrivere(),
            "to": componi._indirizzi(a.text),
            "cc": componi._indirizzi(cc.text),
            "bcc": componi._indirizzi(ccn.text),
            "subject": oggetto.text,
            "text": testo.text,
            "attachments": componi.allegati
        };
        if (componi.bozza.replyToId) p.replyToId = componi.bozza.replyToId;
        if (p.to.length + p.cc.length + p.bcc.length === 0) {
            componi.errore = "A chi lo mando? Scrivi almeno un indirizzo.";
            return;
        }
        componi.invio = true;
        componi.posta.canale.chiama("message.send", p, function (r) {
            componi.invio = false;
            var rifiutati = r.refused || [];
            componi.posta.dice(rifiutati.length > 0
                ? "Inviato, ma questi indirizzi sono stati rifiutati: " + rifiutati.join(", ")
                : "Messaggio inviato.", rifiutati.length === 0);
            componi.chiuso();
        }, function (err) {
            componi.invio = false;
            componi.errore = componi._motivo(err);
        });
    }

    Component.onCompleted: {
        a.text = (componi.bozza.to || []).join ? (componi.bozza.to || []).join(", ") : (componi.bozza.to || "");
        cc.text = (componi.bozza.cc || []).join(", ");
        oggetto.text = componi.bozza.subject || "";
        testo.text = componi.bozza.text || "";
        if (a.text === "") a.prendiIlFuoco();
        else testo.forceActiveFocus();
        testo.cursorPosition = 0;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.window
    }

    Column {
        id: campi
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        spacing: Theme.Effects.space2

        Row {
            width: parent.width
            spacing: Theme.Effects.space2
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - chiudi.width - parent.spacing
                text: componi.bozza.replyToId ? "Risposta" : "Nuovo messaggio"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightSemiBold
            }
            Pulsante {
                id: chiudi
                icona: "close"
                tooltip: "Chiudi senza inviare"
                onClicked: componi.chiuso()
            }
        }
        Text {
            visible: componi.posta.accounts.length > 1
            text: "Da: " + componi.posta.indirizzoPerScrivere()
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
        Ui.Campo { id: a; width: parent.width; segnaposto: "A (separa gli indirizzi con una virgola)" }
        Row {
            width: parent.width
            spacing: Theme.Effects.space2
            Ui.Campo { id: cc; width: parent.width - ccnPulsante.width - parent.spacing; segnaposto: "Cc" }
            Pulsante {
                id: ccnPulsante
                height: 38
                testo: "Ccn"
                active: componi.mostraCcn
                onClicked: componi.mostraCcn = !componi.mostraCcn
            }
        }
        Ui.Campo {
            id: ccn
            visible: componi.mostraCcn
            width: parent.width
            segnaposto: "Ccn: ricevono il messaggio, ma nessuno lo vede"
        }
        Ui.Campo { id: oggetto; width: parent.width; segnaposto: "Oggetto" }
    }

    Rectangle {
        id: foglio
        anchors.top: campi.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: piede.top
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space2
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        border.color: testo.activeFocus ? Theme.Colors.edgeAccent : Theme.Colors.edge

        Flickable {
            id: scorriTesto
            anchors.fill: parent
            anchors.margins: Theme.Effects.space3
            clip: true
            contentHeight: testo.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            function seguiCursore(r) {
                if (contentY >= r.y) contentY = r.y;
                else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
            }
            TextEdit {
                id: testo
                width: scorriTesto.width
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                selectByMouse: true
                color: Theme.Colors.text
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.35)
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                onCursorRectangleChanged: scorriTesto.seguiCursore(cursorRectangle)
            }
        }
    }

    Column {
        id: piede
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space4
        spacing: Theme.Effects.space2

        Flow {
            width: parent.width
            spacing: Theme.Effects.space2
            Repeater {
                model: componi.allegati
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    height: 30
                    width: nomeAll.implicitWidth + 44
                    radius: 15
                    color: Theme.Colors.raised
                    Text {
                        id: nomeAll
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        text: modelData.split("/").pop()
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    Ui.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        name: "close"
                        width: 10; height: 10
                        color: Theme.Colors.textMuted
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            onClicked: {
                                var c = componi.allegati.slice();
                                c.splice(index, 1);
                                componi.allegati = c;
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: componi.errore !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: componi.errore
            color: Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Row {
            spacing: Theme.Effects.space2
            Pulsante {
                icona: componi.invio ? "clock" : "mail"
                testo: componi.invio ? "Invio…" : "Invia"
                active: !componi.invio
                spento: componi.invio
                onClicked: componi.invia()
            }
            Pulsante {
                icona: "plus"
                testo: "Allega"
                spento: componi.invio
                onClicked: componi.scegliAllegato()
            }
        }
    }
}
