import QtQuick
import QtQuick.Controls
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Destinazioni — dove un progetto va al sicuro, fuori da questo computer.
//
// ── Perché un elenco e non un posto solo ───────────────────────────────────
//
// Parole di Giacomo: «vorrei poter scegliere in fase di caricamento quale
// opzione voglio». Ha ragione, e non è una preferenza: un progetto di codice
// vuole GitHub, 286 GB di immagini ROM vogliono un disco in un cassetto, e chi
// ha entrambe le cose vuole tutte e due.
//
// ── Perché si mostrano i dischi, invece di far scrivere un percorso ────────
//
// Perché il caso vero è «ho attaccato il disco esterno adesso», e chiedere di
// scrivere `/run/media/giacomo/Disco Rosso` a mano trasforma un gesto di un
// secondo in un errore di battitura. La casella per scrivere resta, sotto, per
// chi manda in una cartella di rete o dentro casa propria.
Column {
    id: dest

    property var progetto: ({})
    property string percorso: ""
    property bool it: true
    property var finestra: null

    spacing: Theme.Effects.space2

    property var dischi: []
    property bool apri: false

    // ── GitHub ───────────────────────────────────────────────────────────
    //
    // Qui dentro non passa mai il gettone. Va giù al demone una volta sola,
    // finisce nel portachiavi di sistema, e quello che torna indietro è il
    // nome dell'account. Se questa finestra si chiude non si è perso niente,
    // perché non teneva niente.
    property bool ghCollegato: false
    property string ghChi: ""
    property string ghPerche: ""
    property bool ghAttesa: false
    property bool ghPrivato: true
    property string ghErrore: ""

    // ── Il device flow ─────────────────────────────────────────────────
    //
    // `ghCodice` è quello che si mostra: otto caratteri da confermare sul sito.
    // `ghNostro` non si mostra mai — è il codice con cui il demone chiede a
    // GitHub se hai confermato.
    property string ghCodice: ""
    property string ghNostro: ""
    property bool ghAspettaConferma: false

    Connections {
        target: Core.Ipc
        function onCustodiaGithub(r) {
            if (!r) return;
            dest.ghAttesa = false;
            if (r.ok === false) {
                dest.ghErrore = r.errore || "";
                dest.ghAspettaConferma = false;
                dest.ghCodice = "";
                return;
            }
            dest.ghErrore = "";
            // Primo passo del device flow: c'è un codice da mostrare, e da qui
            // comincia l'attesa. Non si tocca `ghCollegato`: collegati non lo
            // siamo ancora, e dirlo prima sarebbe la bugia più comoda.
            if (r.codice !== undefined && r.nostro !== undefined) {
                dest.ghCodice = String(r.codice);
                dest.ghNostro = String(r.nostro);
                dest.ghAspettaConferma = true;
                // Solo una pagina di GitHub: `dove` arriva dalla risposta di
                // GitHub attraverso il demone, e `xdg-open` aprirebbe anche
                // un `file://` (revisione di sicurezza, 5 ottobre 2026).
                var dove = String(r.dove || "");
                if (dove.indexOf("https://github.com/") !== 0)
                    dove = "https://github.com/login/device";
                Quickshell.execDetached(["xdg-open", dove]);
                Core.Ipc.custodiaGithubAttendi(dest.ghNostro, r.ogni, r.scadeFra);
                return;
            }
            if (r.chi !== undefined) {
                dest.ghCodice = "";
                dest.ghNostro = "";
                dest.ghAspettaConferma = false;
                dest.ghCollegato = true;
                dest.ghChi = String(r.chi);
            } else if (r.collegato === false) {
                dest.ghCollegato = false;
                dest.ghChi = "";
                dest.ghPerche = r.perche || "";
            } else {
                // «dimentica»: nessun nome e nessun perché.
                dest.ghCollegato = false;
                dest.ghChi = "";
            }
        }
        function onCustodiaEsito(r) {
            if (r && r.ok === false && dest.ghAttesa) {
                dest.ghAttesa = false;
                dest.ghErrore = r.errore || "";
            } else if (r && r.ok === true && dest.ghAttesa) {
                dest.ghAttesa = false;
                dest.ghErrore = "";
                dest.apri = false;
            }
        }
    }

    /// Il nome che GitHub accetterebbe, tirato fuori da quello della cartella.
    function nomeSuggerito() {
        var n = String(dest.percorso).split("/").filter(function (x) {
            return x !== "";
        }).pop() || "progetto";
        return n.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
    }

    Connections {
        target: Core.Ipc
        function onVolumesReceived(v) {
            if (!v) return;
            var fuori = [];
            var lista = v.volumes || [];
            for (var i = 0; i < lista.length; i++) {
                // Solo quelli montati: un disco che non è montato non ha un
                // percorso dove scrivere, e offrirlo vorrebbe dire offrire un
                // errore.
                if (lista[i].mounted && String(lista[i].mountPoint) !== "") {
                    fuori.push(lista[i]);
                }
            }
            dest.dischi = fuori;
        }
    }

    function ricaricaDischi() { Core.Ipc.fsVolumes(); }

    // ── Si chiede SUBITO a chi siamo collegati ───────────────────────────
    //
    // Fino all'8 settembre 2026 lo si chiedeva solo premendo «Aggiungerne
    // una». Chi una destinazione GitHub ce l'aveva già quel pulsante non lo
    // premeva mai, e il pannello restava convinto per sempre di non essere
    // collegato: mostrava «per mandare su GitHub serve una chiave» a uno che
    // era entrato dieci minuti prima.
    //
    // Giacomo, quel giorno: «nell'app non vedo se ho effettuato l'accesso, non
    // dà nessuna informazione». Uno stato che c'è e non si vede è come non
    // averlo — ed è la stessa famiglia di difetti che questo progetto passa le
    // giornate a togliere.
    Component.onCompleted: {
        dest.ricaricaDischi();
        Core.Ipc.custodiaGithubChi();
    }

    Text {
        text: dest.it ? "Dove va al sicuro" : "Where it goes to be safe"
        color: Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeSM
        font.letterSpacing: Theme.Typography.trackingLabel
    }

    // ── Quelle che ci sono ───────────────────────────────────────────────

    Repeater {
        model: dest.progetto.destinazioni || []

        Rectangle {
            id: riga
            width: dest.width
            height: riga.daSalvare > 0 ? 70 : 52
            radius: Theme.Effects.radiusMD
            color: sopra.containsMouse ? Theme.Colors.hover
                                       : Theme.Colors.raised
            border.width: 1
            border.color: Theme.Colors.edge

            // ── Quello che NON partirebbe ─────────────────────────────────
            //
            // «Manda adesso» manda i salvataggi, non le modifiche: chi ha
            // cambiato dieci file e non li ha salvati preme, legge «Mandato»,
            // e su GitHub vede le date vecchie. Successo il 18 settembre
            // 2026. Da allora la riga lo dice PRIMA, qui, e non dopo in un
            // messaggio.
            readonly property int daSalvare:
                modelData.tipo === "github"
                    ? ((dest.progetto.stato || ({})).quante || 0) : 0

            MouseArea { id: sopra; anchors.fill: parent; hoverEnabled: true }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space3
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                visible: riga.daSalvare > 0
                elide: Text.ElideRight
                text: dest.it
                      ? (riga.daSalvare === 1
                         ? "Una modifica non è ancora salvata: fuori va solo quello che hai salvato."
                         : riga.daSalvare + " modifiche non sono ancora salvate: fuori va solo quello che hai salvato.")
                      : (riga.daSalvare === 1
                         ? "One change is not saved yet: only what you saved goes out."
                         : riga.daSalvare + " changes are not saved yet: only what you saved goes out.")
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            Ui.Icon {
                id: segno
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                y: 26 - height / 2
                name: modelData.tipo === "github" ? "globe" : "disco"
                width: 17; height: 17
                color: Theme.Colors.textMuted
            }

            Column {
                id: colonna
                anchors.left: segno.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: pulsanti.left
                anchors.rightMargin: Theme.Effects.space2
                y: 26 - height / 2
                spacing: 1

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.nome
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: modelData.dove
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

                // ── E se siamo entrati, si vede da qui ───────────────────
                //
                // Una destinazione GitHub a cui non si è collegati sembra
                // identica a una a cui si è collegati, e la differenza si
                // scopre solo al primo invio che non riesce.
                Row {
                    spacing: Theme.Effects.space2
                    visible: modelData.tipo === "github"

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6
                        radius: 3
                        color: dest.ghCollegato ? Theme.Colors.positive
                                                : Theme.Colors.textFaint
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dest.ghCollegato
                              ? (dest.it ? "collegato come " + dest.ghChi
                                         : "signed in as " + dest.ghChi)
                              : (dest.it ? "non hai ancora fatto l'accesso"
                                         : "not signed in yet")
                        color: dest.ghCollegato ? Theme.Colors.positive
                                                : Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }

            Row {
                id: pulsanti
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space2
                y: 26 - height / 2
                spacing: Theme.Effects.space1

                Ui.SpineButton {
                    height: 32
                    horizontalPadding: Theme.Effects.space3
                    onClicked: Core.Ipc.custodiaManda(dest.percorso,
                                                      modelData.dove)
                    content: Row {
                        spacing: 6
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "share"
                            width: 13; height: 13
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dest.it ? "Manda adesso" : "Send now"
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }

                Ui.SpineButton {
                    width: 32; height: 32
                    opacity: sopra.containsMouse ? 1 : 0
                    visible: opacity > 0.01
                    onClicked: Core.Ipc.custodiaDestinazioneTogli(
                        dest.percorso, modelData.dove)
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.Motion.quick }
                    }
                    content: Ui.Icon {
                        name: "close"
                        width: 12; height: 12
                        color: Theme.Colors.textMuted
                    }
                }
            }
        }
    }

    // ── Aggiungerne una ──────────────────────────────────────────────────

    Ui.SpineButton {
        height: 36
        horizontalPadding: Theme.Effects.space3
        visible: !dest.apri
        onClicked: {
            dest.apri = true;
            dest.ghErrore = "";
            dest.ricaricaDischi();
            Core.Ipc.custodiaGithubChi();
        }
        content: Row {
            spacing: Theme.Effects.space2
            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: "plus"
                width: 14; height: 14
                color: Theme.Colors.textMuted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: dest.it ? "Aggiungi un posto dove mandarlo"
                              : "Add a place to send it"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    Rectangle {
        width: dest.width
        visible: dest.apri
        height: scelta.implicitHeight + Theme.Effects.space4 * 2
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.sunken
        border.width: 1
        border.color: Theme.Colors.edge

        Column {
            id: scelta
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.Effects.space4
            spacing: Theme.Effects.space3

            // I dischi attaccati adesso: un clic, niente da scrivere.
            Text {
                visible: dest.dischi.length > 0
                text: dest.it ? "Attaccati adesso" : "Plugged in now"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: dest.dischi.length > 0

                Repeater {
                    model: dest.dischi

                    Rectangle {
                        width: eti.implicitWidth + Theme.Effects.space3 * 2
                        height: 34
                        radius: 17
                        color: dd.containsMouse ? Theme.Colors.hover
                                                : Theme.Colors.raised
                        border.width: 1
                        border.color: Theme.Colors.edge

                        Row {
                            id: eti
                            anchors.centerIn: parent
                            spacing: Theme.Effects.space2
                            Ui.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.removable ? "chiavetta" : "disco"
                                width: 14; height: 14
                                color: Theme.Colors.textMuted
                            }
                            Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.size
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }

                        MouseArea {
                            id: dd
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Una sottocartella col nome del disco, non la
                                // radice del disco: là dentro ci sarà anche
                                // altro, e la nostra roba deve stare in un
                                // posto che si riconosce.
                                Core.Ipc.custodiaDestinazioneAggiungi(
                                    dest.percorso, "cartella", modelData.name,
                                    modelData.mountPoint + "/Copie di Minerva");
                                dest.apri = false;
                            }
                        }
                    }
                }
            }

            Text {
                visible: dest.dischi.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: dest.it
                      ? "Nessun disco attaccato. Puoi comunque scrivere qui sotto una cartella qualsiasi."
                      : "No disk plugged in. You can still type any folder below."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── E una cartella qualsiasi, scelta guardandola ─────────
            //
            // Non una casella dove incollare un percorso: un percorso scritto
            // a mano è un errore di battitura in attesa, e chi lo incolla ha
            // dovuto prima aprire un'altra finestra per copiarlo. Vedi
            // `ui/Scegli.qml`.
            Ui.SpineButton {
                height: 38
                horizontalPadding: Theme.Effects.space4
                onClicked: {
                    if (!dest.finestra) return;
                    dest.finestra.chiediCartella(
                        "destinazione", "",
                        dest.it ? "Dove vuoi mandare questo progetto?"
                                : "Where should this project go?");
                    dest.apri = false;
                }
                content: Row {
                    spacing: Theme.Effects.space2
                    Ui.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "folder"
                        width: 15; height: 15
                        color: Theme.Colors.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dest.it ? "Scegli una cartella…"
                                      : "Choose a folder…"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                    }
                }
            }

            // ── Su GitHub ────────────────────────────────────────────
            //
            // Una cartella o un disco prendono qualsiasi cosa. GitHub no:
            // prende una storia, rifiuta i file oltre 100 MB, e conserva per
            // sempre ogni versione di ogni file — quindi va offerto solo dove
            // ha senso, e detto perché quando non ce l'ha.

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.Colors.edge
            }

            Text {
                text: "GitHub"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            Text {
                visible: (dest.progetto.motore || "") !== "git"
                width: parent.width
                wrapMode: Text.WordWrap
                text: dest.it
                      ? "GitHub tiene storie, e questo progetto non ne tiene una. Comincia a tenere la storia qui sopra, e poi torna."
                      : "GitHub keeps histories, and this project has none yet."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── Primo passo: la chiave ───────────────────────────────
            //
            // È l'unico momento scomodo di tutto il programma, e non si può
            // togliere: GitHub non ha altro modo di sapere che sei tu. Si può
            // però portarci l'utente per mano, con l'indirizzo già pronto e
            // il permesso giusto già spuntato.
            Column {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: (dest.progetto.motore || "") === "git"
                         && !dest.ghCollegato

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: dest.it
                          ? "Per mandare su GitHub serve una chiave: la crei tu sul loro sito, una volta sola. Io la metto nel portachiavi di questo computer e non la scrivo da nessun'altra parte."
                          : "Sending to GitHub needs a key: you make it on their site, once."
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // ── La strada nuova: entra e basta ───────────────────
                //
                // Giacomo, 8 settembre 2026: «lo fa Antigravity, VS Code e
                // tanti altri. Perché non noi? Siamo di serie B?». Aveva
                // ragione, e dieci minuti dopo il gesto che criticava è finito
                // male: il gettone appena creato è stato incollato dentro una
                // conversazione. Un gesto che si può sbagliare così è un gesto
                // da togliere, non da spiegare meglio.
                Ui.SpineButton {
                    height: 34
                    horizontalPadding: Theme.Effects.space3
                    visible: !dest.ghAspettaConferma
                    onClicked: {
                        dest.ghErrore = "";
                        dest.ghAttesa = true;
                        Core.Ipc.custodiaGithubAccedi();
                    }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "lock"
                            width: 14; height: 14
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dest.it ? "Entra in GitHub"
                                          : "Sign in to GitHub"
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }

                // ── Il codice da confermare ──────────────────────────
                //
                // Grande e in carattere a larghezza fissa: è un codice da
                // LEGGERE e riscrivere, e otto caratteri letti male sono un
                // accesso che non riesce senza dire perché.
                Column {
                    width: parent.width
                    spacing: Theme.Effects.space2
                    visible: dest.ghAspettaConferma && dest.ghCodice !== ""

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: dest.it
                              ? "Ti ho aperto GitHub. Scrivi là questo codice e conferma: appena l'hai fatto, me ne accorgo da solo."
                              : "GitHub is open. Type this code there and confirm."
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Rectangle {
                        width: parent.width
                        height: 46
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: Theme.Colors.accent
                        Text {
                            anchors.centerIn: parent
                            text: dest.ghCodice
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeLG
                            font.letterSpacing: 3
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: dest.it
                              ? "Sto aspettando la tua conferma. Puoi lasciare aperta questa finestra."
                              : "Waiting for your confirmation."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                // ── E la strada vecchia, per chi la vuole ────────────
                Ui.SpineButton {
                    height: 34
                    horizontalPadding: Theme.Effects.space3
                    visible: !dest.ghAspettaConferma
                    onClicked: Quickshell.execDetached(["xdg-open",
                        "https://github.com/settings/tokens/new"
                        + "?scopes=repo&description=Minerva%20Custodia"])
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "globe"
                            width: 14; height: 14
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dest.it ? "Apri GitHub e crea la chiave"
                                          : "Open GitHub and make the key"
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }

                TextField {
                    id: chiave
                    width: parent.width
                    // Password apposta: una chiave di GitHub in chiaro su uno
                    // schermo è una chiave che finisce in una foto.
                    echoMode: TextInput.Password
                    placeholderText: dest.it ? "Incolla qui la chiave"
                                             : "Paste the key here"
                    color: Theme.Colors.text
                    placeholderTextColor: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                    background: Rectangle {
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: chiave.activeFocus
                                      ? Theme.Colors.edgeAccent
                                      : Theme.Colors.edge
                    }
                    onAccepted: collega.clicked()
                }

                Ui.SpineButton {
                    id: collega
                    height: 34
                    horizontalPadding: Theme.Effects.space4
                    enabled: chiave.text.trim() !== "" && !dest.ghAttesa
                    opacity: enabled ? 1 : 0.45
                    onClicked: {
                        if (!enabled) return;
                        dest.ghAttesa = true;
                        dest.ghErrore = "";
                        Core.Ipc.custodiaGithubGettone(chiave.text.trim());
                        // Sparisce dallo schermo subito: da qui in poi vive
                        // solo nel portachiavi.
                        chiave.text = "";
                    }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            width: 15; height: 15
                            color: Theme.Colors.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dest.ghAttesa
                                  ? (dest.it ? "Sto controllando…" : "Checking…")
                                  : (dest.it ? "Collega" : "Connect")
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }
                }
            }

            // ── Secondo passo: l'archivio ────────────────────────────
            Column {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: (dest.progetto.motore || "") === "git"
                         && dest.ghCollegato

                Row {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (dest.it ? "Sei " : "You are ") + dest.ghChi
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    Ui.SpineButton {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        horizontalPadding: Theme.Effects.space2
                        onClicked: Core.Ipc.custodiaGithubDimentica()
                        content: Text {
                            text: dest.it ? "non sono io" : "not me"
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }
                }

                TextField {
                    id: nomeArchivio
                    width: parent.width
                    text: dest.nomeSuggerito()
                    placeholderText: dest.it ? "Come si chiamerà su GitHub"
                                             : "Name on GitHub"
                    color: Theme.Colors.text
                    placeholderTextColor: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                    background: Rectangle {
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: nomeArchivio.activeFocus
                                      ? Theme.Colors.edgeAccent
                                      : Theme.Colors.edge
                    }
                }

                // Privato o pubblico: la scelta più importante della pagina,
                // e l'unica irreversibile nei fatti — quello che è stato
                // pubblico una volta qualcuno l'ha già copiato. Quindi due
                // pulsanti espliciti, e privato acceso di suo.
                Row {
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: [true, false]

                        Rectangle {
                            width: eti2.implicitWidth + Theme.Effects.space3 * 2
                            height: 32
                            radius: 16
                            color: dest.ghPrivato === modelData
                                   ? Theme.Colors.selected
                                   : (pp.containsMouse ? Theme.Colors.hover
                                                       : Theme.Colors.raised)
                            border.width: 1
                            border.color: dest.ghPrivato === modelData
                                          ? Theme.Colors.edgeAccent
                                          : Theme.Colors.edge

                            Row {
                                id: eti2
                                anchors.centerIn: parent
                                spacing: 6
                                Ui.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData ? "lock" : "globe"
                                    width: 13; height: 13
                                    color: dest.ghPrivato === modelData
                                           ? Theme.Colors.accent
                                           : Theme.Colors.textMuted
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                          ? (dest.it ? "Solo mio" : "Private")
                                          : (dest.it ? "Visibile a tutti"
                                                     : "Public")
                                    color: dest.ghPrivato === modelData
                                           ? Theme.Colors.text
                                           : Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeSM
                                }
                            }

                            MouseArea {
                                id: pp
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dest.ghPrivato = modelData
                            }
                        }
                    }
                }

                Ui.SpineButton {
                    height: 38
                    horizontalPadding: Theme.Effects.space4
                    enabled: nomeArchivio.text.trim() !== "" && !dest.ghAttesa
                    opacity: enabled ? 1 : 0.45
                    onClicked: {
                        if (!enabled) return;
                        dest.ghAttesa = true;
                        dest.ghErrore = "";
                        Core.Ipc.custodiaGithubCrea(dest.percorso,
                                                    nomeArchivio.text.trim(),
                                                    dest.ghPrivato);
                    }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            width: 15; height: 15
                            color: Theme.Colors.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dest.ghAttesa
                                  ? (dest.it ? "Sto creando…" : "Creating…")
                                  : (dest.it ? "Crea l'archivio e collegalo"
                                             : "Create the repo and link it")
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }
                }
            }

            Text {
                visible: dest.ghErrore !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: dest.ghErrore
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Ui.SpineButton {
                height: 30
                horizontalPadding: Theme.Effects.space3
                onClicked: dest.apri = false
                content: Text {
                    text: dest.it ? "Lascia stare" : "Never mind"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }
    }
}
