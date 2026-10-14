import QtQuick
import Quickshell.Io
import "." as Core

// Un solo flusso NetworkManager per le due interfacce: conserva la ricerca
// dei profili e l'invio della password su stdin, senza duplicare i segreti.
Item {
    id: page
    objectName: "wifiController"
    visible: false
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
    property bool awaitingPassword: false

    property bool active: true
    property bool initialReadOnly: false
    signal passwordRequested(string ssid)
    signal passwordDismissed()
    Component.onCompleted: if (active) refresh(initialReadOnly)

    Core.Exec { id: action }

    // ── Lettura ──────────────────────────────────────────────────────────

    Core.Exec {
        id: query
        onDone: function(out) {
            page.scanning = false;
            page.wired = "";
            var nets = [];
            var seen = Object.create(null);
            var lines = out.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var p = lines[i].split("\t");
                if (lines[i].indexOf("NET\t") === 0)
                    p = ["NET"].concat(page.campiNmcli(lines[i].substring(4)));
                else if (lines[i].indexOf("WIRED\t") === 0)
                    p = ["WIRED"].concat(page.campiNmcli(lines[i].substring(6)));
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
                    if (p[1] === "ethernet" && p[2] === "connected")
                        page.wired = p[3] || "";
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
                // rete a cui il manutentore È connesso si presentava come una
                // qualsiasi, senza «connesso», e premendola avrebbe provato a
                // riconnettersi.
                //
                // Adesso le righe si FONDONO: il segnale migliore di tutte, e
                // «connesso» se lo dice almeno una.
                var ssid = p[1];
                var attiva = p[4] === "*";
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

    // Il formato terse di nmcli usa : come separatore e \ come escape.
    // Si decodifica prima di interpretare i campi: un SSID può contenerli.
    function campiNmcli(riga) {
        var campi = [];
        var campo = "";
        for (var i = 0; i < riga.length; i++) {
            var c = riga.charAt(i);
            if (c === "\\" && i + 1 < riga.length
                    && (riga.charAt(i + 1) === ":" || riga.charAt(i + 1) === "\\")) {
                campo += riga.charAt(++i);
            } else if (c === ":") {
                campi.push(campo);
                campo = "";
            } else {
                campo += c;
            }
        }
        campi.push(campo);
        return campi;
    }

    /// `soloLettura`: legge l'elenco che NetworkManager ha già, senza fargli
    /// rifare la scansione. `nmcli device wifi list` di suo riscansiona se
    /// l'ultima ha più di trenta secondi, e il giro ogni quindici secondi
    /// qui sotto teneva così la radio a cercare per tutto il tempo che la
    /// pagina restava aperta: la scansione continua è quella che costava
    /// batteria e svegliava tutti (`minerva-prestazioni-svegliarsi`).
    function refresh(soloLettura) {
        // Anche il PRIMO giro sta cercando. Senza questa riga, aprendo la
        // pagina si leggeva «0 reti trovate» per i secondi buoni della
        // scansione: una risposta, e sbagliata, al posto di un'attesa.
        if (!soloLettura)
            page.scanning = true;
        query.sh(
            "export LC_ALL=C; " +
            "printf 'WIFI\\t%s\\n' \"$(nmcli radio wifi 2>/dev/null)\"; " +
            "nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null " +
            "| sed 's/^/WIRED\\t/'; " +
            "nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE device wifi list" +
            (soloLettura ? " --rescan no" : "") + " 2>/dev/null " +
            "| sed 's/^/NET\\t/'");
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
        // Solo con le Impostazioni davanti: ridotte o dietro un'altra
        // finestra non c'è nessuno a guardare. Tornandoci si aggiorna
        // subito (`triggeredOnStart`).
        running: page.active && Qt.application.state === Qt.ApplicationActive
        triggeredOnStart: true
        repeat: true
        onTriggered: if (!page.awaitingPassword && page.collegando === "") page.refresh(true)
    }

    // ── Connessione ──────────────────────────────────────────────────────
    //
    // Il commento qui prometteva «se la rete non risulta attiva, si dice che
    // è andata male», e il codice non lo diceva: `page.error` si scriveva e
    // nessuno lo leggeva. Una password sbagliata non dava nessun segno — la
    // finestrella si chiudeva e la rete restava lì, non connessa, come prima
    // del clic.
    //
    // E l'intestazione della pagina prometteva «se la rete è già nota,
    // connettersi è un clic solo», mentre ogni rete protetta apriva la
    // richiesta della password, anche quella di casa. Adesso si prova prima
    // SENZA: NetworkManager la password di una rete nota ce l'ha. Solo se
    // risponde che manca, si chiede.

    /// La rete a cui ci si sta collegando, per dirlo sulla sua riga.
    property string collegando: ""
    /// Vero se il tentativo in corso è quello senza password su una rete
    /// protetta: se fallisce perché la password manca, la si chiede allora.
    property bool _provaSenzaPassword: false

    // Il segreto non passa per Core.Exec: niente argv, lastCommand o coda.
    property string _wifiSecret: ""
    property string _wifiPrompt: ""
    property string _wifiFailure: ""
    property int _wifiEpoch: 0

    function wifiOutput(data) {
        if (page.collegando === "" || page._wifiSecret === "") return;
        // nmcli 1.46 chiede Password:; le versioni recenti usano il proprio
        // SecretAgent con l'identificatore della proprietà. Non rispondere
        // a prompt per identità, certificati o altre credenziali.
        page._wifiPrompt = (page._wifiPrompt + String(data)).slice(-2048);
        if (!/(^|[\r\n])(?:Password: |[^\r\n]*\(802-11-wireless-security\.(?:psk|wep-key[0-3])\): )[\*\u2022]*$/.test(page._wifiPrompt)) return;
        // Cancella l'eventuale valore precompilato da readline.
        connector.write("\u0015" + page._wifiSecret + "\n");
        page._wifiSecret = "";
        page._wifiPrompt = "";
        connector.stdinEnabled = false;
    }

    function wifiError(data) {
        // Conservare solo una categoria, mai l'uscita completa del processo.
        var t = String(data);
        if (page.mancaLaPassword(t)) page._wifiFailure = "secrets";
        else if (/no network with ssid/i.test(t)) page._wifiFailure = "missing";
        else if (/timeout|timed out/i.test(t)) page._wifiFailure = "timeout";
    }

    function completeWifi(code, epoch) {
        if (page.collegando === "" || epoch !== page._wifiEpoch) return;
        wifiDeadline.stop();
        wifiFailedStart.stop();
        var ssid = page.collegando;
        var senza = page._provaSenzaPassword;
        var failure = page._wifiFailure;
        page._wifiSecret = "";
        page._wifiPrompt = "";
        page._wifiFailure = "";
        connector.stdinEnabled = false;
        page.collegando = "";
        page._provaSenzaPassword = false;
        page.refresh(true);
        if (code === 0) return;
        if (senza && failure === "secrets" && page.wifiOn) {
            page.awaitingPassword = true;
            page.passwordRequested(ssid);
            return;
        }
        page.error = failure === "secrets"
            ? (page.it ? "La password non è stata accettata." : "The password was not accepted.")
            : failure === "missing"
            ? (page.it ? "La rete non si vede più." : "The network is no longer visible.")
            : failure === "timeout"
            ? (page.it ? "La rete non ha risposto in tempo." : "The network did not answer in time.")
            : failure === "lookup"
            ? (page.it ? "Impossibile leggere i profili di rete." : "Cannot read network profiles.")
            : failure === "start"
            ? (page.it ? "Impossibile avviare nmcli." : "Cannot start nmcli.")
            : (page.it ? "Connessione non riuscita." : "Connection failed.");
    }

    function stopWifi() {
        page._wifiEpoch++;
        // Interrompe il client locale. Non promette di annullare una
        // attivazione già consegnata a NetworkManager.
        wifiDeadline.stop();
        wifiFailedStart.stop();
        page._wifiSecret = "";
        page._wifiPrompt = "";
        page._wifiFailure = "";
        page.collegando = "";
        page._provaSenzaPassword = false;
        connector.stdinEnabled = false;
        if (connector.running) connector.signal(9);
        page.awaitingPassword = false;
        page.passwordDismissed();
    }

    Process {
        id: connector
        property int epoch: -1
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { page.wifiOutput(data); }
        }
        stderr: SplitParser {
            onRead: function(data) { page.wifiError(data); }
        }
        onStarted: wifiFailedStart.stop()
        onExited: function(code) {
            var epoch = connector.epoch;
            Qt.callLater(function() { page.completeWifi(code, epoch); });
        }
    }

    Timer {
        id: wifiFailedStart
        interval: 25
        onTriggered: {
            if (page.collegando !== "" && !connector.running) {
                page._wifiFailure = "start";
                page.completeWifi(-1, page._wifiEpoch);
            }
        }
    }
    Timer {
        id: wifiDeadline
        interval: 60000
        onTriggered: {
            page._wifiFailure = "timeout";
            page._wifiSecret = "";
            page._wifiPrompt = "";
            connector.stdinEnabled = false;
            if (connector.running) connector.signal(9);
            else page.completeWifi(-1, page._wifiEpoch);
        }
    }
    onWifiOnChanged: if (!page.wifiOn) page.stopWifi()
    Component.onDestruction: page.stopWifi()

    function mancaLaPassword(testo) {
        return /secrets were required|no secrets|password/i.test(testo);
    }

    // Il profilo salvato si attiva per UUID: connection up crea il
    // SecretAgent anche nelle versioni in cui wifi connect non lo fa.
    Core.Exec {
        id: wifiLookup
        property int epoch: -1
        timeoutMs: 15000
        onCompleted: function(code, out, err) {
            page.profileLookedUp(code, out, wifiLookup.epoch);
        }
    }

    function profileLookedUp(code, out, epoch) {
        if (epoch !== page._wifiEpoch || page.collegando === "") return;
        var uuid = String(out).trim();
        if (code !== 0 || (uuid !== "" && !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid))) {
            page._wifiFailure = "lookup";
            page.completeWifi(-1, epoch);
            return;
        }
        page.startWifiCommand(uuid);
    }

    function startWifiCommand(uuid) {
        var argv = ["env", "LC_ALL=C", "nmcli", "--colors", "no", "--wait", "45"];
        if (page._wifiSecret !== "") argv.push("--ask");
        argv = argv.concat(uuid !== "" ? ["connection", "up", "uuid", uuid]
                                      : ["device", "wifi", "connect", page.collegando]);
        connector.stdinEnabled = page._wifiSecret !== "";
        connector.epoch = page._wifiEpoch;
        connector.command = argv;
        connector.running = true;
        wifiFailedStart.restart();
    }

    // Ricerca senza segreti: i valori esterni sono argomenti, mai codice.
    // --escape no conserva due punti, backslash e spazi del vero SSID.
    function wifiProfileCommand(ssid) {
        return ["env", "LC_ALL=C", "sh", "-c",
            'list=$(timeout -k 1 5 nmcli -t -f UUID,TYPE connection show) || exit 1; '
            + 'printf "%s\\n" "$list" | while IFS=: read -r uuid type; do '
            + 'case "$type" in wifi|802-11-wireless) ;; *) continue;; esac; '
            + 'name=$(timeout -k 1 5 nmcli --escape no -g 802-11-wireless.ssid connection show uuid "$uuid") || exit 1; '
            + 'if [ "$name" = "$1" ]; then printf "%s\\n" "$uuid"; exit 0; fi; done',
            "sh", ssid];
    }

    function connect(ssid, password, protetta) {
        if (page.collegando !== "" || connector.running || wifiLookup.busy || !page.wifiOn) return false;
        if (typeof ssid !== "string" || ssid === "" || /[\u0000\r\n]/.test(ssid)) return false;
        var secret = password === undefined ? "" : String(password);
        // Readline interpreta i tasti di controllo; una sola risposta.
        if (/[\u0000-\u001f\u007f]/.test(secret) || secret.length > 1024) {
            page.error = page.it ? "La password contiene caratteri non supportati."
                                 : "The password contains unsupported characters.";
            return false;
        }
        page.error = "";
        page.awaitingPassword = false;
        page.collegando = ssid;
        page._provaSenzaPassword = secret === "" && protetta === true;
        page._wifiSecret = secret;
        page._wifiPrompt = "";
        page._wifiFailure = "";
        page._wifiEpoch++;
        wifiDeadline.restart();
        if (secret !== "") {
            wifiLookup.epoch = page._wifiEpoch;
            wifiLookup.start(page.wifiProfileCommand(ssid));
        } else {
            page.startWifiCommand("");
        }
        return true;
    }

    /// Si stacca la SCHEDA, non la connessione per nome: il nome della
    /// connessione non è per forza l'SSID («Casa 1», dopo un secondo
    /// collegamento), e `connection down <ssid>` falliva in silenzio.
    function disconnect() {
        page.stopWifi();
        page.error = "";
        action.fireSh(
            "d=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null " +
            "| awk -F: '$2==\"wifi\" {print $1; exit}'); " +
            "[ -n \"$d\" ] && nmcli device disconnect \"$d\" >/dev/null 2>&1");
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
        if (!on) page.stopWifi();
        Core.SystemState.setWifi(on);
        rescanTimer.restart();
    }

    // ── Cavo ─────────────────────────────────────────────────────────────

}
