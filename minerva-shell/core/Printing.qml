pragma Singleton
import QtQuick
import Quickshell

// Una sola lettura CUPS condivisa da pannello e notifiche. La ricerca dei
// dispositivi è esplicita: non si svegliano le stampanti di rete a ogni giro.
Item {
    id: printing
    visible: false
    property bool monitoring: false
    readonly property bool it: Strings.lang === "it"
    property var printers: []
    property var jobs: []
    property var discovered: []
    property var drivers: []
    property var packages: []
    property bool packageInstallSupported: true
    property string error: ""
    property string lastResult: ""
    property string lastAction: ""
    property int lastSubmittedJob: 0
    property bool available: false
    property var _warnings: ({})
    property var _deviceReadings: ({})
    readonly property bool busy: command.busy
    // A singleton may be cached under qrc:/qs-blackhole by Quickshell.
    // External programs need a filesystem path, based on the entry point.
    readonly property string helper: (Quickshell.env("LIQUID_DE") || Quickshell.shellDir + "/..") + "/scripts/liquid-print.py"
    signal refreshed()

    function request(data) {
        if (busy) return false;
        lastAction = data.action || "status";
        error = "";
        lastResult = "";
        lastSubmittedJob = 0;
        command.timeoutMs = data.action === "install-driver" ? 600000 : (data.action === "configure" || data.action === "remove") ? 150000 : (data.action === "discover" || data.action === "drivers") ? 60000 : 30000;
        command.start(["python3", "-I", helper, JSON.stringify(data)]);
        return true;
    }
    function refresh() { return request({action:"status"}); }
    function labelReason(reason) {
        var key = String(reason).replace(/-(warning|error|report)$/, "");
        var labels = {
            "media-empty":["Carta esaurita", "Out of paper"],
            "media-low":["Carta in esaurimento", "Paper running low"],
            "media-jam":["Carta inceppata", "Paper jam"],
            "media-needed":["Inserire la carta", "Load paper"],
            "marker-supply-low":["Inchiostro o toner in esaurimento", "Ink or toner running low"],
            "marker-supply-empty":["Inchiostro o toner esaurito", "Ink or toner empty"],
            "toner-low":["Toner in esaurimento", "Toner running low"],
            "toner-empty":["Toner esaurito", "Toner empty"],
            "cover-open":["Coperchio aperto", "Cover open"],
            "door-open":["Sportello aperto", "Door open"],
            "offline":["Stampante non raggiungibile", "Printer unreachable"],
            "connecting-to-device":["Connessione alla stampante", "Connecting to printer"],
            "paused":["Stampante sospesa", "Printer paused"]
        };
        return labels[key] ? labels[key][it ? 0 : 1] : reason;
    }
    function operationError(message) {
        var errors = {
            "failed to connect to server":["Il servizio di stampa CUPS non è raggiungibile. Avvialo e riprova.", "The CUPS printing service is unreachable. Start it and try again."],
            "invalid-printer-name":["Usa un nome che inizi con una lettera o un numero, senza spazi né barre.", "Use a name starting with a letter or digit, without spaces or slashes."],
            "printer-already-exists":["Esiste già una coda con questo nome. Non è stata modificata.", "A queue with this name already exists. It was not changed."],
            "device-already-configured":["Questo collegamento ha già una coda configurata.", "This connection already has a configured queue."],
            "device-no-longer-discovered":["Stampante non più rilevata. Accendila e ripeti la ricerca.", "Printer no longer detected. Turn it on and search again."],
            "driver-not-in-catalog":["Driver non più disponibile. Ripeti la ricerca dei driver.", "Driver no longer available. Search for drivers again."],
            "unsupported-maintenance":["Il driver non espone questa funzione di manutenzione.", "The driver does not expose this maintenance function."],
            "printer-has-active-jobs":["La stampante ha lavori in attesa: attendi che terminino o annullali prima di rimuoverla.", "The printer has pending jobs: wait for completion or cancel them before removal."],
            "unknown-job":["Il lavoro è già terminato oppure non appartiene a questo utente.", "The job has finished or does not belong to this user."],
            "unsupported-color":["Il driver non espone la modalità bianco e nero. La stampa non è stata inviata.", "The driver does not expose monochrome mode. No print job was submitted."],
            "unsupported-device-status":["Questo collegamento non espone una lettura diretta IPP. Restano disponibili i dati comunicati da CUPS.", "This connection does not expose direct IPP status. CUPS data remains available."],
            "device-status-timeout":["La stampante non ha risposto entro 8 secondi. Gli ultimi dati restano visibili con l’ora di lettura.", "The printer did not respond within 8 seconds. Previous data remains visible with its reading time."],
            "device-status-unavailable":["Impossibile leggere lo stato del dispositivo. Verifica che sia acceso e raggiungibile.", "Cannot read device status. Check that it is powered on and reachable."],
            "print-empty-response":["Il servizio di stampa non ha restituito una risposta. Premi Aggiorna e riprova.", "The printing helper returned no response. Refresh and try again."],
            "print-invalid-response":["Il servizio di stampa ha restituito una risposta non valida. I dettagli tecnici sono nel registro delle Impostazioni.", "The printing helper returned an invalid response. Technical details are in the Settings log."],
            "print-helper-failed":["Errore interno del servizio di stampa. I dettagli tecnici sono nel registro delle Impostazioni.", "Internal printing helper error. Technical details are in the Settings log."],
            "print-document-support-missing":["Manca il supporto PDF di Qt per Python. Installa il pacchetto pyside6.", "Qt for Python PDF support is missing. Install the pyside6 package."],
            "unsupported-or-locked-pdf":["Il PDF non è leggibile oppure richiede una password. Aprilo e salvalo sbloccato prima di stamparlo.", "The PDF cannot be read or requires a password. Open it and save an unlocked copy before printing."],
            "invalid-pages":["Indica le pagine nel formato 1,3-5.", "Enter pages in the form 1,3-5."],
            "pages-out-of-range":["L’intervallo indicato non corrisponde alle pagine del documento.", "The range does not match the document pages."]
        };
        return errors[message] ? errors[message][it ? 0 : 1] : message;
    }
    function stateLabel(printer) {
        var reasons = (printer.reasons || []).filter(function(r) { return r !== "none"; });
        if (reasons.length) return reasons.map(labelReason).join(" · ");
        if (printer.state === 5) return it ? "In pausa" : "Stopped";
        if (printer.state === 4) return it ? "In stampa" : "Printing";
        if (printer.state === 3) return it ? "Pronta · nessun errore segnalato" : "Ready · no reported errors";
        return it ? "Stato non disponibile" : "Status unavailable";
    }
    function supplyLabel(supply) {
        var labels = {"Black ink":["Nero", "Black"], "Cyan ink":["Ciano", "Cyan"],
            "Magenta ink":["Magenta", "Magenta"], "Yellow ink":["Giallo", "Yellow"]};
        return labels[supply.name] ? labels[supply.name][it ? 0 : 1] : supply.name;
    }
    function applyPrinters(rows) {
        var cache = {}, output = [];
        for (var row of rows) {
            var key = "printer:" + row.name;
            var previous = _deviceReadings[key];
            if (row.deviceReading) cache[key] = {deviceKey:row.deviceKey, reading:row.deviceReading};
            else if (previous && previous.deviceKey === row.deviceKey) cache[key] = previous;
            if (cache[key]) row.deviceReading = cache[key].reading;
            output.push(row);
        }
        _deviceReadings = cache;
        printers = output;
    }
    function suppliesFor(printer) {
        return printer.deviceReading ? printer.deviceReading.supplies || [] : printer.supplies || [];
    }
    function warn(rows) {
        var next = {};
        for (var printer of rows) {
            var issues = (printer.reasons || []).filter(function(r) {
                return r !== "none" && r !== "connecting-to-device";
            }).map(function(reason) { return {key:reason, text:printing.labelReason(reason)}; });
            var supplies = suppliesFor(printer);
            for (var i = 0; i < supplies.length; i++) {
                var supply = supplies[i];
                if (supply.high) issues.push({key:"waste:" + i, text:supplyLabel(supply) + (it ? ": serbatoio quasi pieno" : ": waste tank almost full")});
                if (supply.low) issues.push({key:"supply:" + i, text:supplyLabel(supply) + ": " + supply.level + "%"});
            }
            // La percentuale può cambiare senza produrre un avviso per ogni
            // punto: si riavvisa soltanto dopo il rientro della condizione.
            for (var issue of issues) {
                var key = printer.name + "\n" + issue.key;
                next[key] = true;
                if (!_warnings[key]) Notifications.daMinerva(printer.description, issue.text);
            }
        }
        _warnings = next;
    }
    Exec {
        id: command
        timeoutMs: 150000
        onCompleted: function(code, out, stderr) {
            if (code !== 0 || stderr) console.warn("[Liquid][Printing] helper result; action=" + printing.lastAction + "; exitCode=" + code + "; characters=" + out.length + "; stderr=" + stderr);
            try {
                if (code !== 0) throw new Error(stderr || (printing.it ? "Il comando di stampa è terminato con errore " : "Printing command failed with code ") + code);
                if (!out.trim()) throw new Error("print-empty-response");
                var result;
                try { result = JSON.parse(out); }
                catch (parseError) {
                    console.warn("[Liquid][Printing] invalid JSON; action=" + printing.lastAction + "; exitCode=" + code + "; characters=" + out.length);
                    throw new Error("print-invalid-response");
                }
                if (!result || !result.ok) throw new Error(result ? result.message || stderr : "print-invalid-response");
                if (result.printers !== undefined) {
                    printing.applyPrinters(result.printers);
                    printing.jobs = result.jobs || [];
                    printing.available = true;
                }
                if (result.discovered !== undefined) printing.discovered = result.discovered;
                if (result.drivers !== undefined) printing.drivers = result.drivers;
                if (result.packages !== undefined) printing.packages = result.packages;
                if (result.packageInstallSupported !== undefined) printing.packageInstallSupported = result.packageInstallSupported;
                if (result.installedPackage) printing.lastResult = (printing.it ? "Pacchetto installato: " : "Installed package: ") + result.installedPackage;
                if (result.removedPrinter) printing.lastResult = (printing.it ? "Stampante rimossa: " : "Removed printer: ") + result.removedPrinter;
                if (result.warning) printing.lastResult += (printing.it ? " · Preferenze personali non ripulite: verificare la stampante predefinita." : " · Personal preferences were not cleared: check the default printer.");
                if (result.submittedJob) {
                    printing.lastSubmittedJob = result.submittedJob;
                    printing.lastResult = (printing.it ? "Lavoro inviato: " : "Submitted job: ") + result.submittedJob;
                }
                if (printing.monitoring) printing.warn(printing.printers);
            } catch (e) {
                if (printing.lastAction === "status") printing.available = false;
                printing.error = (printing.it ? "Operazione non riuscita: " : "Operation failed: ") + printing.operationError(String(e.message || stderr || e));
            }
            printing.refreshed();
        }
    }
    Timer {
        interval: printing.jobs.length ? 5000 : 60000
        running: printing.monitoring
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!printing.busy) printing.refresh()
    }
}
