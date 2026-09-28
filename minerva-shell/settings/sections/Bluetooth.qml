import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Bluetooth — Accensione, ricerca, accoppiamento e connessione.
//
// `bluetoothctl` è pensato per essere usato a mano, in modo interattivo: si
// entra, si digitano comandi, si legge. Qui lo si usa in modo secco, un
// comando per volta, perché un programma che aspetta risposte in un terminale
// invisibile è un programma che prima o poi si blocca senza dire niente.
//
// Le tre parole vanno tenute distinte perché sono tre cose diverse, e
// confonderle è il motivo per cui il Bluetooth ha fama di essere ostico:
//
//   accoppiato  il computer e il dispositivo si conoscono e si fidano
//   connesso    stanno parlando adesso
//   fidato      si riconnette da solo quando ricompare
Page {
    id: page

    title: "Bluetooth"
    subtitle: Core.Strings.lang === "it"
              ? "Cuffie, altoparlanti, mouse e tastiere senza fili"
              : "Headphones, speakers, mice and wireless keyboards"

    readonly property bool it: Core.Strings.lang === "it"

    // Acceso o spento NON è una proprietà di questa pagina: è la stessa
    // identica cosa che mostra la barra. Prima erano due letture separate con
    // due cadenze diverse e ognuna con la sua ipotesi ottimistica dopo un
    // comando, e per una decina di secondi dicevano il contrario l'una
    // dell'altra — «chi ha ragione dei due?». Adesso la domanda non si può
    // nemmeno più porre: il valore è uno solo.
    readonly property bool powered: Core.SystemState.bluetoothOn
    readonly property bool hasAdapter: Core.SystemState.bluetoothPresent
    /// "", "soft" (si sblocca) oppure "hard" (interruttore fisico).
    readonly property string blocked: Core.SystemState.bluetoothBlock

    property bool scanning: false
    property var devices: []

    // ── Cosa sta succedendo ──────────────────────────────────────────────
    //
    // Accoppiare un dispositivo Bluetooth prende dai cinque ai quindici
    // secondi, e per tutto quel tempo qui non compariva niente: si premeva
    // «Accoppia» e la riga restava identica. Chi guarda preme di nuovo, e
    // premere due volte durante un accoppiamento è il modo più veloce per
    // farlo fallire.

    /// Il dispositivo su cui stiamo lavorando adesso, e che cosa gli stiamo
    /// facendo. Vuoto quando non c'è niente in corso.
    property string busyMac: ""
    property string busyWhat: ""

    /// L'esito dell'ultima cosa fatta, da mostrare in cima.
    property string notice: ""
    property bool noticeBad: false

    function say(text, bad) {
        page.notice = text;
        page.noticeBad = bad === true;
        noticeLife.restart();
    }

    Timer {
        id: noticeLife
        interval: 9000
        onTriggered: page.notice = ""
    }

    Component.onCompleted: refresh()

    Core.Exec { id: action }

    // ── Lettura ──────────────────────────────────────────────────────────

    Core.Exec {
        id: query
        onDone: function(out) {
            if (out === "") {
                page.devices = [];
                return;
            }
            var devs = [];
            var lines = out.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var f = lines[i].split("\t");
                if (f[0] === "ADAPTER") {
                    // Questa pagina legge ogni quattro secondi, lo stato di
                    // sistema ogni dodici: quando è aperta è lei la più
                    // aggiornata, e quello che scopre lo passa a tutti invece
                    // di tenerselo. Aggiornare la barra è il suo dovere, non
                    // un'invasione di campo.
                    Core.SystemState.bluetoothOn = (f[1] === "yes");
                } else if (f[0] === "DEV" && f.length >= 6) {
                    devs.push({
                        "mac": f[1],
                        "name": f[2] || f[1],
                        "paired": f[3] === "yes",
                        "connected": f[4] === "yes",
                        "trusted": f[5] === "yes",
                        "icon": f[6] || ""
                    });
                }
            }
            // Prima i connessi, poi i conosciuti, poi gli sconosciuti: è
            // l'ordine in cui interessano.
            devs.sort(function(a, b) {
                if (a.connected !== b.connected) return a.connected ? -1 : 1;
                if (a.paired !== b.paired) return a.paired ? -1 : 1;
                return a.name.localeCompare(b.name);
            });
            page.devices = devs;
        }
    }

    function refresh() {
        // Una riga per l'adattatore e una per ogni dispositivo, con lo stato
        // già estratto: interrogare `info` per ogni dispositivo separatamente
        // significherebbe una raffica di processi a ogni aggiornamento.
        query.sh(
            "export LC_ALL=C; command -v bluetoothctl >/dev/null || exit 1; " +
            "printf 'ADAPTER\\t%s\\n' " +
            "\"$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}')\"; " +
            "bluetoothctl devices 2>/dev/null | while read -r _ mac name; do " +
            "  info=$(bluetoothctl info \"$mac\" 2>/dev/null); " +
            "  p=$(printf '%s' \"$info\" | awk '/Paired:/{print $2; exit}'); " +
            "  c=$(printf '%s' \"$info\" | awk '/Connected:/{print $2; exit}'); " +
            "  t=$(printf '%s' \"$info\" | awk '/Trusted:/{print $2; exit}'); " +
            "  i=$(printf '%s' \"$info\" | awk '/Icon:/{print $2; exit}'); " +
            "  printf 'DEV\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' " +
            "    \"$mac\" \"$name\" \"${p:-no}\" \"${c:-no}\" \"${t:-no}\" \"$i\"; " +
            "done");
    }

    Timer {
        // Un secondo e due decimi, non quattro secondi.
        //
        // Da quando le Impostazioni sono un processo a sé, questa pagina e
        // l'interruttore nella barra NON condividono più lo stato: sono due
        // copie di `Core.SystemState` in due processi diversi, e ognuna sa
        // solo quello che legge da sola. Spegnendo il Bluetooth dalla barra,
        // questa pagina ci metteva fino a sei secondi ad accorgersene —
        // quattro di attesa più un paio che ci mette `bluetoothctl` a fare
        // davvero la cosa.
        //
        // Questo era un CEROTTO, e la cura vera è arrivata: acceso e spento
        // adesso li tiene il demone e li annuncia a tutti
        // (`Core.SystemState.bluetoothOn`), quindi l'interruttore non
        // aspetta più questo giro. Qui resta solo l'elenco dei dispositivi —
        // e ogni giro lancia un `bluetoothctl info` PER dispositivo: con
        // tre dispositivi erano diciassette processi ogni 1,2 secondi, su un
        // portatile che scalda. Tre secondi bastano per vedere comparire le
        // cuffie appena accese.
        interval: 3000
        // Fermo mentre si sta accoppiando: quella sessione di `bluetoothctl`
        // sta parlando con l'adattatore, e mettersi a interrogarlo ogni
        // quattro secondi nel frattempo è il modo di far fallire proprio la
        // cosa che si sta aspettando.
        running: page.busyMac === ""
        repeat: true
        onTriggered: page.refresh()
    }

    // ── Comandi ──────────────────────────────────────────────────────────

    /// Accende passando dallo stato di sistema, che è lo stesso posto da cui
    /// passa l'interruttore nella barra: due strade diverse per lo stesso
    /// comando sono due modi diversi di sbagliarlo.
    function setPowered(on) {
        Core.SystemState.setBluetooth(on);
        soon.restart();
    }

    /// Accende la ricerca per venti secondi. Lasciarla accesa consuma batteria
    /// e continua a far comparire e sparire dispositivi mentre si prova a
    /// cliccarne uno.
    function scan() {
        if (!page.powered)
            return;
        page.scanning = true;
        action.fireSh("bluetoothctl --timeout 20 scan on >/dev/null 2>&1");
        scanTimer.restart();
    }

    Timer {
        id: scanTimer
        interval: 20000
        onTriggered: { page.scanning = false; page.refresh(); }
    }

    Timer {
        id: soon
        interval: 900
        onTriggered: page.refresh()
    }

    // ── Accoppiare ───────────────────────────────────────────────────────
    //
    // Qui c'erano tre `bluetoothctl` lanciati uno dopo l'altro:
    //
    //     bluetoothctl pair MAC; bluetoothctl trust MAC; bluetoothctl connect MAC
    //
    // e non funzionava quasi mai, perché **non c'era nessun agente**: BlueZ
    // non accoppia niente senza qualcuno che risponda alle sue domande, e
    // `bluetoothctl` registra l'agente solo per la durata della PROPRIA
    // sessione. Corretto il 28 luglio con una sessione sola.
    //
    // Restava però l'altra metà, scritta accanto e mai fatta: quella sessione
    // registrava `agent NoInputNoOutput`, cioè «da questa parte non c'è né
    // tastiera né schermo». Va bene per cuffie e mouse. **Un telefono no**:
    // Android pretende che si confronti un codice a sei cifre, e rifiuta.
    //
    // Giacomo, 18 agosto 2026: «non riesco ad accoppiare il mio Redmi Note 12
    // Pro Plus 5G». Era esattamente quel caso.
    //
    // Adesso l'accoppiamento lo tiene il DEMONE
    // (`minervad/lib/services/bluetooth_pairing_service.dart`), che tiene la
    // sessione aperta, legge le domande e aspetta la risposta. Questa pagina
    // fa solo due cose: chiedere di cominciare, e mostrare il codice.

    /// Il codice che BlueZ vuole far confrontare, o vuoto.
    property string codiceDaConfrontare: ""
    /// Vero quando la domanda non ha un codice: «accetti l'accoppiamento?».
    property bool chiedeSoloConferma: false

    function pair(mac) {
        page.busyMac = mac;
        page.busyWhat = "pair";
        page.codiceDaConfrontare = "";
        page.chiedeSoloConferma = false;
        page.say(page.it ? "Guarda il telefono: sta per chiedere qualcosa."
                         : "Look at the phone: it is about to ask something.",
                 false);
        Core.Ipc.btPair(mac);
    }

    Connections {
        target: Core.Ipc

        function onBtAccoppiamento(d) {
            if (!d) return;
            var it = page.it;

            if (d.stato === "chiede") {
                page.codiceDaConfrontare = d.codice || "";
                page.chiedeSoloConferma = (d.codice || "") === "";
                return;
            }

            page.codiceDaConfrontare = "";
            page.chiedeSoloConferma = false;

            if (d.stato === "fatto") {
                page.busyMac = "";
                page.busyWhat = "";
                page.refresh();
                page.say(d.messaggio || (it ? "Accoppiato." : "Paired."), false);
            } else if (d.stato === "fallito") {
                page.busyMac = "";
                page.busyWhat = "";
                page.refresh();
                page.say(d.error || (it ? "Non è riuscito." : "It did not work."),
                         true);
            }
        }
    }

    // ── La domanda, che è l'unica cosa nuova a schermo ───────────────────
    //
    // Non è una notifica: è una domanda che ferma tutto finché non le si
    // risponde, perché dall'altra parte c'è un telefono che sta aspettando e
    // che dopo un minuto rinuncia.
    Rectangle {
        id: domandaCodice
        parent: page
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: page.codiceDaConfrontare !== "" || page.chiedeSoloConferma
        z: 60

        // Prende i clic, così non si preme niente sotto mentre BlueZ aspetta.
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.Effects.space6, 380)
            height: colonnaCodice.implicitHeight + Theme.Effects.space5 * 2
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            Column {
                id: colonnaCodice
                anchors.centerIn: parent
                width: parent.width - Theme.Effects.space5 * 2
                spacing: Theme.Effects.space3

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.chiedeSoloConferma
                          ? (page.it ? "Il telefono chiede di accoppiarsi. Accetti?"
                                     : "The phone is asking to pair. Accept?")
                          : (page.it ? "Sul telefono c'è scritto questo numero?"
                                     : "Does the phone show this number?")
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightMedium
                }

                // Il codice grande e spaziato: si legge da un telefono tenuto
                // in mano, a mezzo metro, e va confrontato cifra per cifra.
                Text {
                    width: parent.width
                    visible: page.codiceDaConfrontare !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: page.codiceDaConfrontare
                    color: Theme.Colors.accent
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXL
                    font.letterSpacing: 4
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: page.codiceDaConfrontare !== ""
                    text: page.it
                          ? "Se il numero è diverso, rispondi di no: vuol dire "
                            + "che stai accoppiando un altro apparecchio."
                          : "If the number is different, say no: you are "
                            + "pairing something else."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: [ { "id": "no" }, { "id": "si" } ]

                        delegate: Rectangle {
                            id: bottoneCodice
                            required property var modelData

                            width: testoCodice.implicitWidth + Theme.Effects.space5
                            height: 34
                            radius: Theme.Effects.radiusSM
                            color: mouseCodice.containsMouse
                                   ? (bottoneCodice.modelData.id === "si"
                                      ? Qt.alpha(Theme.Colors.accent, 0.25)
                                      : Theme.Colors.raisedHigh)
                                   : Theme.Colors.raised
                            border.width: Theme.Effects.hairline
                            border.color: Theme.Colors.edge

                            Text {
                                id: testoCodice
                                anchors.centerIn: parent
                                text: bottoneCodice.modelData.id === "si"
                                      ? (page.it ? "Sì, è uguale" : "Yes, it matches")
                                      : (page.it ? "No" : "No")
                                color: bottoneCodice.modelData.id === "si"
                                       ? Theme.Colors.accent : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }

                            MouseArea {
                                id: mouseCodice
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    page.codiceDaConfrontare = "";
                                    page.chiedeSoloConferma = false;
                                    Core.Ipc.btPairAnswer(
                                        bottoneCodice.modelData.id === "si");
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Le altre tre azioni ──────────────────────────────────────────────
    //
    // Anche queste dicono com'è andata. Connettere delle cuffie spente
    // falliva in silenzio, e restava una riga che diceva «accoppiato, non
    // connesso» esattamente come prima del clic.

    function connect(mac) {
        page.busyMac = mac;
        page.busyWhat = "connect";
        simple.shArgs("export LC_ALL=C; bluetoothctl connect \"$1\" 2>&1", [mac]);
    }

    function disconnect(mac) {
        page.busyMac = mac;
        page.busyWhat = "disconnect";
        simple.shArgs("export LC_ALL=C; bluetoothctl disconnect \"$1\" 2>&1", [mac]);
    }

    function forget(mac) {
        page.busyMac = mac;
        page.busyWhat = "forget";
        simple.shArgs("export LC_ALL=C; bluetoothctl remove \"$1\" 2>&1", [mac]);
    }

    Core.Exec {
        id: simple
        onDone: function(out) {
            var what = page.busyWhat;
            page.busyMac = "";
            page.busyWhat = "";
            page.refresh();

            var it = page.it;
            var ok = out.indexOf("successful") !== -1
                     || out.indexOf("has been removed") !== -1;
            if (ok) {
                if (what === "connect")
                    page.say(it ? "Collegato." : "Connected.", false);
                else if (what === "forget")
                    page.say(it ? "Dimenticato." : "Forgotten.", false);
                return;
            }
            if (what === "disconnect")
                return;   // scollegare qualcosa di già scollegato non è un guasto
            page.say(it ? "Non è riuscito. Il dispositivo è acceso e vicino?"
                        : "It did not work. Is the device on and nearby?", true);
        }
    }

    /// Icona adatta al tipo di dispositivo, così si riconoscono le cuffie
    /// dal mouse senza leggere il nome.
    function glyph(kind) {
        switch (kind) {
        case "audio-headset":
        case "audio-headphones": return "volume";
        case "audio-card":       return "music";
        case "input-mouse":      return "apps";
        case "input-keyboard":   return "keyboard";
        case "phone":            return "cpu";
        default:                 return "bluetooth";
        }
    }

    // ── Com'è andata ─────────────────────────────────────────────────────

    Rectangle {
        width: parent.width
        height: page.notice !== "" ? noticeText.implicitHeight + Theme.Effects.space4 : 0
        visible: height > 0
        radius: Theme.Effects.radiusSM
        // Il rosso era scritto a mano, un vinaccia scuro all'85 %: col tema
        // chiaro il testo — scuro, perché segue il tema — ci finiva sopra
        // quasi nero su quasi nero, proprio nel messaggio che dice che
        // qualcosa è andato storto. Adesso è un velo del colore del
        // pericolo, come quello verde dell'esito buono.
        color: page.noticeBad ? Qt.alpha(Theme.Colors.danger, 0.14)
                              : Qt.alpha(Theme.Colors.positive, 0.14)
        border.width: 1
        border.color: page.noticeBad ? Qt.alpha(Theme.Colors.danger, 0.5)
                                     : Qt.alpha(Theme.Colors.positive, 0.4)
        // Niente `Behavior` sull'altezza: vedi `ui/Slider.qml`.
        clip: true

        Ui.Icon {
            id: noticeIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            name: page.noticeBad ? "close" : "check"
            color: page.noticeBad ? Theme.Colors.danger : Theme.Colors.positive
        }

        Text {
            id: noticeText
            anchors.left: noticeIcon.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            text: page.notice
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.notice = ""
        }
    }

    // ── Interruttore ─────────────────────────────────────────────────────

    Card {
        heading: "Bluetooth"
        visible: page.hasAdapter

        S.SettingRow {
            width: parent.width
            label: page.it ? "Bluetooth acceso" : "Bluetooth on"
            description: page.blocked === "hard"
                         ? (page.it ? "Bloccato dall'interruttore fisico del computer"
                                    : "Blocked by the computer's physical switch")
                         : (page.it ? "Spento consuma meno batteria"
                                    : "Turning it off saves battery")
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: page.powered
                // L'interruttore fisico non si scavalca via software. Lasciare
                // il comando attivo vorrebbe dire farlo scattare e vederlo
                // tornare indietro da solo, che è il modo peggiore di dire di no.
                enabled: page.blocked !== "hard"
                onToggled: function(v) { page.setPowered(v); }
            }
        }

        // Il blocco software è la trappola vera: `bluetoothctl power on` non
        // fallisce, non fa niente, e l'adattatore resta spento. Da qui si toglie.
        S.SettingRow {
            width: parent.width
            visible: page.blocked === "soft" && !page.powered
            label: page.it ? "Bloccato via software" : "Blocked in software"
            description: page.it
                         ? "Qualcosa ha spento la radio Bluetooth (rfkill). Si riaccende da qui."
                         : "Something switched the Bluetooth radio off (rfkill). Turn it back on here."
            controlWidth: 140

            control: Rectangle {
                width: 140; height: 32
                radius: Theme.Effects.radiusXS
                color: unblockMouse.containsMouse
                       ? Qt.alpha(Theme.Colors.accent, 0.22)
                       : Qt.alpha(Theme.Colors.accent, 0.12)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.45)

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Sblocca" : "Unblock"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: unblockMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setPowered(true)
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: !page.hasAdapter
        wrapMode: Text.WordWrap
        text: page.it
              ? "Nessun adattatore Bluetooth su questo computer."
              : "No Bluetooth adapter on this computer."
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeSM
    }

    // ── Dispositivi ──────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Dispositivi" : "Devices"
        visible: page.hasAdapter && page.powered
        note: page.it
              ? "Per accoppiare qualcosa di nuovo, mettilo in modalità "
                + "accoppiamento (di solito tenendo premuto il suo tasto) e premi «Cerca»."
              : "To pair something new, put it in pairing mode (usually by holding "
                + "its button) and press “Scan”."

        Item {
            width: parent.width
            height: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: page.scanning
                      ? (page.it ? "Cerco dispositivi…" : "Scanning…")
                      // «conosciuti» contava anche quelli appena visti in una
                      // ricerca e mai accoppiati: si contano solo i nostri.
                      : page.devices.filter(function(d) { return d.paired; }).length
                        + (page.it ? " accoppiati" : " paired")
                color: page.scanning ? Theme.Colors.accent : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: scanText.implicitWidth + Theme.Effects.space4
                height: 26
                radius: Theme.Effects.radiusXS
                color: page.scanning ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : scanMouse.containsMouse ? Theme.Colors.hover
                     : Theme.Colors.raisedHigh
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    id: scanText
                    anchors.centerIn: parent
                    text: page.scanning ? (page.it ? "Ricerca in corso" : "Scanning")
                                        : (page.it ? "Cerca dispositivi" : "Scan")
                    color: page.scanning ? Theme.Colors.accent : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                MouseArea {
                    id: scanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !page.scanning
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.scan()
                }
            }
        }

        Repeater {
            model: page.devices

            delegate: Rectangle {
                id: dev
                required property var modelData

                /// Vero mentre stiamo facendo qualcosa a QUESTO dispositivo.
                readonly property bool busy: page.busyMac === modelData.mac

                width: parent.width
                height: 52
                radius: Theme.Effects.radiusSM
                color: modelData.connected ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : devMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    id: devIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 19; height: 19
                    name: page.glyph(dev.modelData.icon)
                    color: dev.modelData.connected ? Theme.Colors.accent
                                                   : Theme.Colors.textFaint
                }

                Column {
                    anchors.left: devIcon.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: devActions.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: dev.modelData.name
                        color: dev.modelData.connected ? Theme.Colors.text
                                                       : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: dev.modelData.connected
                                     ? Theme.Typography.weightSemiBold
                                     : Theme.Typography.weightRegular
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: {
                            // Prima di tutto: cosa sta succedendo adesso.
                            // Un accoppiamento dura una decina di secondi, e
                            // dieci secondi senza un segno sono dieci secondi
                            // in cui sembra tutto rotto.
                            if (dev.busy) {
                                switch (page.busyWhat) {
                                case "pair":       return page.it ? "accoppiamento in corso…" : "pairing…";
                                case "connect":    return page.it ? "mi collego…" : "connecting…";
                                case "disconnect": return page.it ? "mi scollego…" : "disconnecting…";
                                case "forget":     return page.it ? "lo dimentico…" : "forgetting…";
                                }
                            }
                            if (dev.modelData.connected)
                                return page.it ? "connesso" : "connected";
                            if (dev.modelData.paired)
                                return page.it ? "accoppiato, non connesso"
                                               : "paired, not connected";
                            return page.it ? "mai accoppiato" : "never paired";
                        }
                        color: dev.busy ? Theme.Colors.accent
                             : dev.modelData.connected ? Theme.Colors.positive
                             : Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                Row {
                    id: devActions
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.Effects.space2

                    // Azione principale: cambia a seconda di dove siamo.
                    Rectangle {
                        width: mainText.implicitWidth + Theme.Effects.space4
                        height: 28
                        radius: Theme.Effects.radiusXS
                        color: mainMouse.containsMouse
                               ? Qt.alpha(Theme.Colors.accent, 0.22)
                               : Theme.Colors.raisedHigh
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        // Spento mentre si sta lavorando su qualunque
                        // dispositivo: due `bluetoothctl` che si accavallano
                        // sullo stesso adattatore si disturbano a vicenda, e
                        // il secondo clic è quello che fa fallire il primo.
                        opacity: page.busyMac !== "" ? 0.4 : 1

                        Text {
                            id: mainText
                            anchors.centerIn: parent
                            text: dev.busy
                                  ? (page.it ? "Attendi…" : "Wait…")
                                  : dev.modelData.connected
                                    ? (page.it ? "Disconnetti" : "Disconnect")
                                    : dev.modelData.paired
                                      ? (page.it ? "Connetti" : "Connect")
                                      : (page.it ? "Accoppia" : "Pair")
                            color: mainMouse.containsMouse ? Theme.Colors.accent
                                                           : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        MouseArea {
                            id: mainMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: page.busyMac === ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (dev.modelData.connected)
                                    page.disconnect(dev.modelData.mac);
                                else if (dev.modelData.paired)
                                    page.connect(dev.modelData.mac);
                                else
                                    page.pair(dev.modelData.mac);
                            }
                        }
                    }

                    // «Dimentica» solo per i già accoppiati: su uno mai visto
                    // non c'è niente da dimenticare.
                    //
                    // E si chiede conferma: una × da 28 pixel accanto a
                    // «Connetti», premuta per sbaglio, toglieva l'accoppiamento
                    // — e rifarlo vuol dire rimettere il telefono o le cuffie
                    // in modalità accoppiamento e confrontare di nuovo il
                    // codice. Il primo clic chiede «Dimentico?», il secondo
                    // entro quattro secondi dimentica.
                    Rectangle {
                        id: dimentica
                        property bool chiede: false
                        width: chiede ? chiedeTesto.implicitWidth + Theme.Effects.space4 : 28
                        height: 28
                        radius: 14
                        visible: dev.modelData.paired
                        color: dimentica.chiede ? Qt.alpha(Theme.Colors.danger, 0.20)
                             : forgetMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.20)
                             : "transparent"

                        Ui.Icon {
                            anchors.centerIn: parent
                            visible: !dimentica.chiede
                            width: 14; height: 14
                            name: "close"
                            color: forgetMouse.containsMouse ? Theme.Colors.danger
                                                             : Theme.Colors.textFaint
                        }

                        Text {
                            id: chiedeTesto
                            anchors.centerIn: parent
                            visible: dimentica.chiede
                            text: page.it ? "Dimentico?" : "Forget?"
                            color: Theme.Colors.danger
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        Timer {
                            interval: 4000
                            running: dimentica.chiede
                            onTriggered: dimentica.chiede = false
                        }

                        MouseArea {
                            id: forgetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: page.busyMac === ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!dimentica.chiede) {
                                    dimentica.chiede = true;
                                    return;
                                }
                                dimentica.chiede = false;
                                page.forget(dev.modelData.mac);
                            }
                        }
                    }
                }

                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    z: -1
                }
            }
        }

        Text {
            width: parent.width
            visible: page.devices.length === 0
            wrapMode: Text.WordWrap
            text: page.it
                  ? "Nessun dispositivo. Premi «Cerca dispositivi» con quello che "
                    + "vuoi collegare in modalità accoppiamento."
                  : "No devices. Press “Scan” with the thing you want to connect "
                    + "in pairing mode."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }
}
