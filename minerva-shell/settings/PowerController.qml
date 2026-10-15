import QtQuick
import "../core" as Core

// Stato condiviso da Liquid e Windows: il profilo mostrato viene sempre
// riletto dal servizio, non dedotto dal pulsante appena premuto.
Item {
    id: page
    width: 0
    height: 0
    objectName: "gestoreAlimentazione"
    readonly property bool it: Core.Strings.lang === "it"
    property string profile: ""
    property var profiles: []
    property bool selecting: false
    property string queryError: ""
    property string writeError: ""
    readonly property string profileError: writeError || queryError
    readonly property bool busy: selecting || profileQuery.busy || setter.busy

    function reloadProfiles() {
        if (!profileQuery.busy)
            profileQuery.start(["env", "LC_ALL=C", "powerprofilesctl", "list"]);
    }
    function refresh() {
        if (selecting)
            return;
        writeError = "";
        reloadProfiles();
        if (Core.SystemState.hasBattery && !batteryQuery.busy)
            batteryQuery.sh("upower -i \"$(upower -e | grep -m1 BAT)\" 2>/dev/null");
    }
    function setProfile(name) {
        if (busy || profiles.indexOf(name) < 0 || name === profile)
            return false;
        selecting = true;
        writeError = "";
        setter.start(["env", "LC_ALL=C", "powerprofilesctl", "set", name]);
        return true;
    }
    Core.Exec {
        id: profileQuery
        timeoutMs: 5000
        onCompleted: function(code, out, error) {
            var found = [];
            var active = "";
            for (var line of out.split("\n")) {
                var match = line.match(/^\s*(\*)?\s*([a-z-]+):\s*$/);
                if (!match)
                    continue;
                if (found.indexOf(match[2]) < 0)
                    found.push(match[2]);
                if (match[1] === "*")
                    active = match[2];
            }
            page.profiles = code === 0 ? found : [];
            page.profile = code === 0 ? active : "";
            page.queryError = code === 0 && found.length > 0 && active !== "" ? ""
                : error || (page.it ? "Profili energetici non disponibili" : "Power profiles unavailable");
            page.selecting = false;
        }
    }
    Core.Exec {
        id: setter
        timeoutMs: 10000
        onCompleted: function(code, out, error) {
            page.writeError = code === 0 ? "" : error || (page.it ? "Cambio del profilo non riuscito" : "Unable to change power mode");
            page.reloadProfiles();
        }
    }
    readonly property var profileLabels: ({
        "power-saver": { "it": "Risparmio",  "en": "Power saver",
                         "d_it": "Meno consumi, meno prestazioni. La batteria dura di più.",
                         "d_en": "Less power, less performance. The battery lasts longer." },
        "balanced":    { "it": "Equilibrato", "en": "Balanced",
                         "d_it": "Il compromesso di tutti i giorni.",
                         "d_en": "The everyday compromise." },
        "performance": { "it": "Prestazioni", "en": "Performance",
                         "d_it": "Tutto quello che il processore può dare. Scalda e consuma.",
                         "d_en": "Everything the processor can give. It runs hot and drains." }
    })

    // ── Batteria ─────────────────────────────────────────────────────────

    property string batteryState: ""
    property string batteryTimeRaw: ""
    readonly property string batteryTime: page.inItaliano(batteryTimeRaw)
    property string batteryHealth: ""

    // ── `upower` risponde in inglese, e con quattro decimali ─────────────
    //
    // Quello che scriveva era «5,4 hours di autonomia · salute 78,2517 %»:
    // mezza frase in inglese in mezzo a una italiana, e una percentuale di
    // salute della batteria con quattro cifre dopo la virgola, che nessuno
    // guarda e che cambia da sola ogni venti secondi.
    //
    // Numero e unità seguono la lingua dell'interfaccia, anche quando non
    // coincide con quella del processo upower. Il cambio lingua non deve
    // lanciare un altro comando né attendere il prossimo aggiornamento.

    /// «3,2 hours» → «3,2 ore». Se non riconosce l'unità lascia stare: meglio
    /// una parola inglese che una frase inventata.
    function inItaliano(t) {
        var match = String(t).trim().match(/^([0-9]+(?:[.,][0-9]+)?)\s+(hours?|minutes?|seconds?|days?)$/);
        if (!match)
            return t;
        var translated = {hours:"ore",hour:"ora",minutes:"minuti",minute:"minuto",
            seconds:"secondi",second:"secondo",days:"giorni",day:"giorno"};
        var decimals = (match[1].split(/[.,]/)[1] || "").length;
        var number = Number(match[1].replace(",","."));
        return number.toLocaleString(Qt.locale(page.it ? "it_IT" : "en_US"), 'f', Math.min(2,decimals))
            + " " + (page.it ? translated[match[2]] : match[2]);
    }

    /// «78,2517%» → «78%». La salute di una batteria è un numero intero:
    /// le altre cifre sono rumore che si muove da solo.
    function arrotonda(t) {
        var m = String(t).match(/^\s*(-?[0-9]+)[.,]?([0-9]*)\s*%?\s*$/);
        if (!m)
            return t;
        var n = parseFloat(m[1] + "." + (m[2] === "" ? "0" : m[2]));
        return Math.round(n) + "%";
    }

    Core.Exec {
        id: batteryQuery
        onDone: function(out) {
            function field(name) {
                var m = out.match(new RegExp(name + ":\\s*(.+)"));
                return m ? m[1].trim() : "";
            }
            page.batteryState = field("state");
            var full = field("time to full");
            var empty = field("time to empty");
            page.batteryTimeRaw = full !== "" ? full : empty;
            page.batteryHealth = page.arrotonda(field("capacity"));
        }
    }


    Component.onCompleted: refresh()
    Connections {
        target: Core.SystemState
        function onHasBatteryChanged() { page.refresh(); }
        function onBatteryChargingChanged() { page.refresh(); }
    }
    Timer {
        interval: 20000
        running: Qt.application.state === Qt.ApplicationActive
        repeat: true
        onTriggered: page.refresh()
    }
}
