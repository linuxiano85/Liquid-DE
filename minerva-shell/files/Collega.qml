import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

// Collega — «Connetti a un server»: una cartella condivisa, un server SFTP o
// FTP, scritto a mano.
//
// Il lavoro vero lo fa il demone (`minervad/lib/services/luoghi_remoti.dart`)
// con gvfs. Qui si chiede solo quello che serve, quando serve:
//
//  · prima l'indirizzo e basta. Molte cartelle di casa sono aperte a tutti,
//    e un server SSH con la chiave non chiede niente: chiedere sempre utente
//    e password farebbe scrivere cose inutili;
//  · se il server le vuole, compaiono utente e password (e il dominio per
//    Samba), e si riprova;
//  · se il server SFTP non è conosciuto, si mostra la domanda di gvfs così
//    com'è, e si va avanti solo con un sì esplicito.
//
// La password non si tiene: chiusa la finestra, la casella si svuota.
Rectangle {
    id: collega

    /// Collegato: la cartella locale dove gvfs lo mostra.
    signal collegato(string percorso)

    color: Theme.Colors.scrim
    visible: false

    readonly property bool it: Core.Strings.lang === "it"

    /// Che cosa si sta chiedendo: "indirizzo", "accesso" o "domanda".
    property string passo: "indirizzo"
    property bool chiedeDominio: false
    property string domanda: ""
    property string errore: ""
    property bool inAttesa: false
    property string richiesta: ""

    function apri() {
        collega.passo = "indirizzo";
        collega.errore = "";
        collega.domanda = "";
        collega.inAttesa = false;
        collega.richiesta = "";
        utente.text = "";
        dominio.text = "";
        password.text = "";
        collega.visible = true;
        indirizzo.prendiIlFuoco();
        indirizzo.seleziona();
    }

    function chiudi() {
        password.text = "";
        collega.inAttesa = false;
        collega.visible = false;
        collega.richiesta = "";
    }

    function prova(fidati) {
        if (indirizzo.text.trim() === "" || collega.inAttesa)
            return;
        collega.errore = "";
        collega.inAttesa = true;
        collega.richiesta = "server-" + Date.now().toString(36)
            + Math.random().toString(36).substring(2);
        Core.Ipc.fsConnetti(indirizzo.text.trim(), utente.text, dominio.text,
                           password.text, fidati === true, collega.richiesta);
    }

    Connections {
        target: Core.Ipc

        function onConnessoReceived(r) {
            if (!collega.inAttesa || r.richiesta !== collega.richiesta)
                return;
            collega.inAttesa = false;
            if (r.ok === true) {
                var dove = r.percorso || "";
                collega.chiudi();
                if (dove !== "")
                    collega.collegato(dove);
                return;
            }
            if (r.domanda) {
                collega.domanda = r.domanda;
                collega.passo = "domanda";
                return;
            }
            if (r.serveAccesso === true) {
                collega.chiedeDominio = r.dominio === true;
                // Una password sbagliata si riscrive; l'utente resta.
                if (collega.passo === "accesso")
                    password.text = "";
                collega.passo = "accesso";
                collega.errore = r.error || "";
                if (utente.text === "")
                    utente.prendiIlFuoco();
                else
                    password.prendiIlFuoco();
                return;
            }
            collega.errore = r.error || (collega.it ? "Collegamento non riuscito."
                                                    : "Connection failed.");
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: collega.chiudi()
    }

    Keys.onEscapePressed: collega.chiudi()

    Rectangle {
        anchors.centerIn: parent
        width: 440
        height: corpo.implicitHeight + Theme.Effects.space5 * 2
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent }

        Column {
            id: corpo
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.Effects.space5
            spacing: Theme.Effects.space3

            Text {
                width: parent.width
                text: collega.it ? "Connetti a un server" : "Connect to a server"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Ui.Campo {
                id: indirizzo
                objectName: "collegaIndirizzo"
                width: parent.width
                modificabile: collega.passo === "indirizzo" && !collega.inAttesa
                segnaposto: "smb://server/cartella  ·  sftp://utente@server"
                onAccettato: collega.prova(false)
                Keys.onEscapePressed: collega.chiudi()
            }

            Text {
                width: parent.width
                visible: collega.passo === "indirizzo"
                wrapMode: Text.WordWrap
                text: collega.it
                      ? "Anche \\\\server\\cartella, come in Windows. Senza protocollo è una cartella condivisa (Samba)."
                      : "\\\\server\\share works too, as on Windows. Without a protocol it is a shared folder (Samba)."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Text {
                width: parent.width
                visible: collega.passo === "indirizzo" && Files.reteMancano.length > 0
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: (collega.it ? "Per le cartelle condivise mancano i pacchetti: "
                                  : "Shared folders need the packages: ")
                      + Files.reteMancano.join(", ")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            // ── Utente e password, solo se il server li chiede ──
            Column {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: collega.passo === "accesso"

                Ui.Campo {
                    id: utente
                    width: parent.width
                    segnaposto: collega.it ? "Utente (vuoto: il tuo)" : "User (empty: yours)"
                    onAccettato: password.prendiIlFuoco()
                    Keys.onEscapePressed: collega.chiudi()
                }

                Ui.Campo {
                    id: dominio
                    width: parent.width
                    visible: collega.chiedeDominio
                    segnaposto: collega.it ? "Dominio (vuoto: WORKGROUP)" : "Domain (empty: WORKGROUP)"
                    onAccettato: password.prendiIlFuoco()
                    Keys.onEscapePressed: collega.chiudi()
                }

                Ui.Campo {
                    id: password
                    width: parent.width
                    nascosto: true
                    segnaposto: "Password"
                    onAccettato: collega.prova(false)
                    Keys.onEscapePressed: collega.chiudi()
                }
            }

            // ── Il server non è conosciuto ──
            Rectangle {
                width: parent.width
                height: testoDomanda.implicitHeight + Theme.Effects.space3 * 2
                visible: collega.passo === "domanda"
                radius: Theme.Effects.radiusSM
                color: Theme.Colors.sunken

                Text {
                    id: testoDomanda
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.Effects.space3
                    wrapMode: Text.WordWrap
                    // Lo scrive il server: testo semplice, mai HTML.
                    textFormat: Text.PlainText
                    text: collega.domanda
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            Text {
                width: parent.width
                visible: collega.errore !== "" || collega.inAttesa
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: collega.inAttesa ? (collega.it ? "Mi collego…" : "Connecting…")
                                       : collega.errore
                color: collega.inAttesa ? Theme.Colors.textMuted : Theme.Colors.danger
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Row {
                anchors.right: parent.right
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "annulla", "testo": collega.it ? "Annulla" : "Cancel", "forte": false },
                        { "id": "vai", "forte": true,
                          "testo": collega.passo === "domanda"
                                   ? (collega.it ? "Fidati e collega" : "Trust and connect")
                                   : (collega.it ? "Collega" : "Connect") }
                    ]

                    delegate: Rectangle {
                        id: bottone
                        required property var modelData

                        readonly property color tono: modelData.forte ? Theme.Colors.accent
                                                                      : Theme.Colors.textMuted

                        width: etichetta.implicitWidth + Theme.Effects.space5
                        height: 34
                        radius: Theme.Effects.radiusXS
                        opacity: modelData.forte && collega.inAttesa ? 0.5 : 1
                        color: mouse.containsMouse ? Qt.alpha(bottone.tono, 0.18)
                                                   : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: etichetta
                            anchors.centerIn: parent
                            text: bottone.modelData.testo
                            color: bottone.modelData.forte ? Theme.Colors.accent : Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (bottone.modelData.id === "annulla")
                                    collega.chiudi();
                                else
                                    collega.prova(collega.passo === "domanda");
                            }
                        }
                    }
                }
            }
        }
    }
}
