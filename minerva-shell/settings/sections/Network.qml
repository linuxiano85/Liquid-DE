import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Network — Wi-Fi e rete via cavo.
//
// Si appoggia a NetworkManager (`nmcli`), che è quello che gestisce davvero le
// connessioni: reinventarlo significherebbe riscrivere la gestione delle
// password, dei certificati e della riconnessione automatica.
//
// La password si chiede solo quando serve: se la rete è già nota, NetworkManager
// ce l'ha e connettersi è un clic solo.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Rete" : "Network"
    subtitle: Core.Strings.lang === "it"
              ? "Wi-Fi e connessione via cavo"
              : "Wi-Fi and wired connection"

    readonly property bool it: Core.Strings.lang === "it"

    property var networks: []
    property string wired: ""
    /// Lo stato della radio viene dal demone, che lo legge da
    /// `/sys/class/rfkill` e lo manda a tutte le finestre nello stesso
    /// istante. Qui è un legame, non una copia: se qualcuno spegne il Wi-Fi
    /// dal pannello di controllo, questa pagina lo mostra subito.
    readonly property bool wifiOn: Core.SystemState.wifiOn
    property bool scanning: false
    property string error: ""

    Component.onCompleted: refresh()

    Core.Exec { id: action }

    // ── Lettura ──────────────────────────────────────────────────────────

    Core.Exec {
        id: query
        onDone: function(out) {
            page.scanning = false;
            var nets = [];
            var seen = {};
            var lines = out.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var p = lines[i].split("\t");
                if (p.length < 2)
                    continue;
                if (p[0] === "WIFI") {
                    // Non si scrive più `page.wifiOn` da qui: lo stato della
                    // radio è uno solo e lo tiene il demone, che lo legge da
                    // `/sys/class/rfkill` e lo dice a tutte le finestre
                    // insieme. Scriverlo anche qui vorrebbe dire due verità
                    // che si rincorrono, e la pagina che vince è quella che ha
                    // guardato per ultima.
                    continue;
                }
                if (p[0] === "WIRED") {
                    page.wired = p[1] || "";
                    continue;
                }
                if (p[0] !== "NET" || !p[1])
                    continue;
                // ── Una rete, tante righe ───────────────────────────────
                //
                // nmcli elenca un punto d'accesso per riga: la stessa rete
                // compare tre volte, una per banda. Si teneva la PRIMA — che
                // è la più forte, perché nmcli ordina per segnale — e si
                // buttavano le altre.
                //
                // Ma l'asterisco di «sei attaccato a questa» sta sulla riga
                // del punto d'accesso a cui si è attaccati davvero, che non è
                // per forza il più forte: qui la rete di casa era 97 sulla
                // riga scartata e 65 su quella con l'asterisco. Risultato: la
                // rete a cui Giacomo È connesso si presentava come una
                // qualsiasi, senza «connesso», e premendola avrebbe provato a
                // riconnettersi.
                //
                // Adesso le righe si FONDONO: il segnale migliore di tutte, e
                // «connesso» se lo dice almeno una.
                var ssid = p[1];
                var attiva = p[4] === "yes";
                var forza = parseInt(p[2] || "0");
                if (seen[ssid] !== undefined) {
                    var g = nets[seen[ssid]];
                    if (forza > g.signal) g.signal = forza;
                    if (attiva) g.active = true;
                    continue;
                }
                seen[ssid] = nets.length;
                nets.push({
                    "ssid": ssid,
                    "signal": forza,
                    "secure": (p[3] || "") !== "" && p[3] !== "--",
                    "active": attiva
                });
            }
            nets.sort(function(a, b) {
                if (a.active !== b.active) return a.active ? -1 : 1;
                return b.signal - a.signal;
            });
            page.networks = nets;
        }
    }

    function refresh() {
        // Anche il PRIMO giro sta cercando. Senza questa riga, aprendo la
        // pagina si leggeva «0 reti trovate» per i secondi buoni della
        // scansione: una risposta, e sbagliata, al posto di un'attesa.
        page.scanning = true;
        query.sh(
            "export LC_ALL=C; " +
            "printf 'WIFI\\t%s\\n' \"$(nmcli radio wifi 2>/dev/null)\"; " +
            "printf 'WIRED\\t%s\\n' \"$(nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null " +
            "| awk -F: '$1==\"ethernet\" && $2==\"connected\" {print $3}')\"; " +
            "nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE device wifi list 2>/dev/null " +
            "| awk -F: 'NF>=3 {print \"NET\\t\" $1 \"\\t\" $2 \"\\t\" $3 \"\\t\" ($4==\"*\" ? \"yes\" : \"\")}'");
    }

    function rescan() {
        page.scanning = true;
        action.fireSh("nmcli device wifi rescan >/dev/null 2>&1");
        rescanTimer.restart();
    }

    Timer {
        id: rescanTimer
        interval: 2500
        onTriggered: page.refresh()
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: if (!connectDialog.visible) page.refresh()
    }

    // ── Connessione ──────────────────────────────────────────────────────

    Core.Exec {
        id: connector
        onDone: function(out) {
            // nmcli scrive l'errore su stderr, che qui non arriva: se dopo il
            // tentativo la rete non risulta attiva, si dice che è andata male
            // invece di far finta di niente.
            page.refresh();
        }
    }

    function connect(ssid, password) {
        page.error = "";
        var q = "'" + ssid.replace(/'/g, "'\\''") + "'";
        if (password && password !== "") {
            var p = "'" + password.replace(/'/g, "'\\''") + "'";
            connector.sh("nmcli device wifi connect " + q + " password " + p + " 2>&1");
        } else {
            connector.sh("nmcli connection up " + q + " 2>&1 || nmcli device wifi connect "
                         + q + " 2>&1");
        }
    }

    function disconnect(ssid) {
        var q = "'" + ssid.replace(/'/g, "'\\''") + "'";
        action.fireSh("nmcli connection down " + q + " >/dev/null 2>&1");
        rescanTimer.restart();
    }

    // ── Accendere il Wi-Fi passa dal demone, non da `nmcli` ──────────────
    //
    // Qui si lanciava `nmcli radio wifi` per conto proprio. Funzionava — la
    // radio si accendeva — ma **le altre finestre non lo sapevano**: la barra
    // e il pannello di controllo restavano com'erano fino al giro di lettura
    // del demone, fino a dodici secondi dopo. È esattamente il difetto già
    // corretto per il Bluetooth, rimasto qui: una finestra che comanda il
    // sistema da sé non ha modo di avvisare le altre, perché non sa che
    // esistono. Il demone sì.
    function setWifi(on) {
        Core.SystemState.setWifi(on);
        rescanTimer.restart();
    }

    // ── Cavo ─────────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Rete via cavo" : "Wired network"
        visible: page.wired !== ""

        Row {
            width: parent.width
            spacing: Theme.Effects.space3

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                name: "globe"
                color: Theme.Colors.positive
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.wired
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.it ? "connesso" : "connected"
                color: Theme.Colors.positive
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    // ── Wi-Fi ────────────────────────────────────────────────────────────

    Card {
        heading: "Wi-Fi"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Wi-Fi acceso" : "Wi-Fi on"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: page.wifiOn
                onToggled: function(v) { page.setWifi(v); }
            }
        }

        Item {
            width: parent.width
            height: 28
            visible: page.wifiOn

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: page.scanning
                      ? (page.it ? "Cerco le reti…" : "Scanning…")
                      // «1 reti trovate» era la scritta che c'era: il plurale
                      // scritto a mano attaccato a un numero. Con una rete
                      // sola — cioè in casa di Giacomo — si legge sempre.
                      : (page.networks.length + (page.it
                            ? (page.networks.length === 1 ? " rete trovata"
                                                          : " reti trovate")
                            : (page.networks.length === 1 ? " network found"
                                                          : " networks found")))
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: rescanText.implicitWidth + Theme.Effects.space3
                height: 24
                radius: Theme.Effects.radiusXS
                color: rescanMouse.containsMouse ? Theme.Colors.hover : "transparent"

                Text {
                    id: rescanText
                    anchors.centerIn: parent
                    text: page.it ? "Cerca di nuovo" : "Scan again"
                    color: rescanMouse.containsMouse ? Theme.Colors.accent
                                                     : Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.rescan()
                }
            }
        }

        Repeater {
            model: page.wifiOn ? page.networks : []

            delegate: Rectangle {
                id: net
                required property var modelData

                width: parent.width
                height: 46
                radius: Theme.Effects.radiusSM
                color: net.modelData.active ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : netMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // Forza del segnale, in quattro tacche: il numero esatto non
                // aiuta a decidere niente, la tacca sì.
                Row {
                    id: bars
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 3
                            height: 4 + index * 3
                            anchors.bottom: parent.bottom
                            radius: 1.5
                            color: net.modelData.signal >= (index + 1) * 22
                                   ? (net.modelData.active ? Theme.Colors.accent
                                                           : Theme.Colors.textMuted)
                                   : Theme.Colors.raisedHigh
                        }
                    }
                }

                Text {
                    id: netName
                    anchors.left: bars.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: netLock.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: net.modelData.ssid
                          + (net.modelData.active ? (page.it ? "  ·  connesso" : "  ·  connected") : "")
                    color: net.modelData.active ? Theme.Colors.text : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: net.modelData.active ? Theme.Typography.weightSemiBold
                                                      : Theme.Typography.weightRegular
                }

                Ui.Icon {
                    id: netLock
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14
                    name: "lock"
                    visible: net.modelData.secure
                    color: Theme.Colors.textFaint
                    alwaysDrawn: true
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (net.modelData.active) {
                            page.disconnect(net.modelData.ssid);
                        } else if (net.modelData.secure) {
                            connectDialog.open(net.modelData.ssid);
                        } else {
                            page.connect(net.modelData.ssid, "");
                        }
                    }
                }
            }
        }
    }

    // ── Richiesta della password ─────────────────────────────────────────
    //
    // Vive dentro la pagina e non in una finestra a parte: una finestra nuova
    // per tre campi verrebbe affiancata dal tiling e coprirebbe l'elenco delle
    // reti proprio mentre si sta scegliendo.

    Rectangle {
        id: connectDialog
        parent: page
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false
        z: 10

        property string ssid: ""

        function open(s) {
            connectDialog.ssid = s;
            passwordInput.text = "";
            connectDialog.visible = true;
            passwordInput.forceActiveFocus();
        }

        function submit() {
            connectDialog.visible = false;
            page.connect(connectDialog.ssid, passwordInput.text);
        }

        MouseArea {
            anchors.fill: parent
            onClicked: connectDialog.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 380
            height: 168
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Text {
                id: dialogTitle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                elide: Text.ElideRight
                text: connectDialog.ssid
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightSemiBold
            }

            Text {
                id: dialogHint
                anchors.top: dialogTitle.bottom
                anchors.topMargin: 2
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space4
                text: page.it ? "Password della rete" : "Network password"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                id: passwordBox
                anchors.top: dialogHint.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                height: 36
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.45)

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    // Solo ai lati: lo stesso conto della casella del nome nel
                    // gestore file (`files/FileManager.qml`). Con il margine
                    // anche sopra e sotto restavano dodici pixel per un
                    // carattere da sedici, e la password si vedeva tagliata.
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    echoMode: revealMouse.containsMouse ? TextInput.Normal
                                                        : TextInput.Password
                    color: Theme.Colors.text
                    selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD

                    onAccepted: connectDialog.submit()
                    Keys.onEscapePressed: connectDialog.visible = false
                }

                // Occhio per rivelare: tenerlo premuto mostra la password.
                // Un interruttore che la lascia visibile la dimentica visibile.
                Ui.Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: "search"
                    color: revealMouse.containsMouse ? Theme.Colors.accent
                                                     : Theme.Colors.textFaint

                    MouseArea {
                        id: revealMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "cancel",  "primary": false },
                        { "id": "connect", "primary": true }
                    ]

                    delegate: Rectangle {
                        id: dlgBtn
                        required property var modelData

                        width: dlgLabel.implicitWidth + Theme.Effects.space5
                        height: 32
                        radius: Theme.Effects.radiusXS
                        color: modelData.primary
                               ? (dlgMouse.containsMouse ? Theme.Colors.accent
                                                         : Qt.alpha(Theme.Colors.accent, 0.85))
                               : (dlgMouse.containsMouse ? Theme.Colors.hover
                                                         : Theme.Colors.raised)
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: dlgLabel
                            anchors.centerIn: parent
                            text: dlgBtn.modelData.id === "cancel"
                                  ? (page.it ? "Annulla" : "Cancel")
                                  : (page.it ? "Connetti" : "Connect")
                            color: dlgBtn.modelData.primary ? Theme.Colors.textOnAccent
                                                            : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightSemiBold
                        }

                        MouseArea {
                            id: dlgMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (dlgBtn.modelData.id === "cancel")
                                    connectDialog.visible = false;
                                else
                                    connectDialog.submit();
                            }
                        }
                    }
                }
            }
        }
    }
}
