import QtQuick
import "../theme" as Theme
import "../core" as Core

// Bluetooth — Il tabellone degli apparecchi accoppiati, con la loro batteria.
//
// Giacomo, 14 settembre 2026: «ne vorrei uno simile per il bluetooth con
// icone eccetera». In cima se il Bluetooth è acceso e quanti apparecchi sono
// collegati; poi un apparecchio per riga — il simbolo della sua classe, il
// nome, la batteria se la dice, e una parola.
//
// ── Da dove vengono gli apparecchi ─────────────────────────────────────────
//
// Dal demone, che li chiede a BlueZ sul bus (`system_state_service.dart`,
// `bluetoothDevices`): non un `bluetoothctl` per apparecchio ogni cinque
// secondi. La batteria è `org.bluez.Battery1`, che c'è SOLO per chi è
// connesso e la dichiara — un mouse Logitech sì, un OBD-II no — e quando
// non c'è la riga dice «Connesso» o «Non connesso», non un numero inventato.
//
// ── Le classi di BlueZ, tradotte ───────────────────────────────────────────
//
// `input-mouse`, `input-keyboard`, `input-gaming`, `audio-headset`,
// `audio-headphones`, `audio-card`, `phone`, `computer`: sono le parole
// della specifica, e ognuna ha il suo glifo. Chi non ha classe prende il
// simbolo del Bluetooth, che è vero anche se dice poco.
Tabellone {
    id: bt

    readonly property bool it: Core.Strings.lang === "it"
    readonly property var apparecchi: Core.SystemState.bluetoothDevices || []
    readonly property int connessi: {
        var n = 0;
        for (var i = 0; i < bt.apparecchi.length; i++)
            if (bt.apparecchi[i].connesso) n++;
        return n;
    }

    icona: "bluetooth"
    titolo: "Bluetooth"
    iconaGrande: "bluetooth"
    tinta: Core.SystemState.bluetoothOn ? Theme.Colors.accent
                                        : Theme.Colors.textMuted

    valore: !Core.SystemState.bluetoothPresent
            ? (bt.it ? "Assente" : "Absent")
            : !Core.SystemState.bluetoothOn
              ? (bt.it ? "Spento" : "Off")
              : bt.connessi === 0
                ? (bt.it ? "Acceso" : "On")
                : bt.connessi === 1
                  ? (bt.it ? "1 collegato" : "1 connected")
                  : bt.connessi + (bt.it ? " collegati" : " connected")
    sotto: !Core.SystemState.bluetoothOn ? ""
           : bt.apparecchi.length === 0
             ? (bt.it ? "Nessun apparecchio accoppiato" : "No paired devices")
             : bt.apparecchi.length + (bt.it ? " accoppiati" : " paired")
    quota: -1

    function glifo(classe) {
        var c = String(classe || "");
        if (c.indexOf("mouse") !== -1)        return "mouse";
        if (c.indexOf("keyboard") !== -1)     return "keyboard";
        if (c.indexOf("gaming") !== -1)       return "gamepad";
        if (c.indexOf("headset") !== -1 || c.indexOf("headphones") !== -1)
            return "cuffie";
        if (c.indexOf("audio") !== -1)        return "volume";
        if (c.indexOf("phone") !== -1)        return "telefono";
        if (c.indexOf("computer") !== -1)     return "cursor";
        return "bluetooth";
    }

    /// La parola della batteria: le stesse soglie e gli stessi colori del
    /// widget «Batteria» del computer, in `Contenuto.tinta`.
    function parolaBatteria(p) {
        if (p >= 70) return bt.it ? "Carica alta" : "High charge";
        if (p >= 35) return bt.it ? "Media" : "Medium";
        return bt.it ? "Batteria scarica" : "Low battery";
    }
    function tintaBatteria(p) {
        return p <= 15 ? Theme.Colors.danger
             : p <= 30 ? Theme.Colors.warning
             : Theme.Colors.positive;
    }

    righe: {
        var l = [];
        for (var i = 0; i < bt.apparecchi.length; i++) {
            var a = bt.apparecchi[i];
            var batt = a.batteria !== undefined ? Number(a.batteria) : -1;
            var conn = a.connesso === true;
            l.push({
                "icona": bt.glifo(a.icona),
                "nome": String(a.nome || ""),
                "valore": batt >= 0 ? Math.round(batt) + "%" : "",
                "quota": batt >= 0 ? batt / 100 : -1,
                "tinta": batt >= 0 ? bt.tintaBatteria(batt)
                         : (conn ? Theme.Colors.accent : Theme.Colors.textMuted),
                "stato": batt >= 0 ? bt.parolaBatteria(batt)
                         : (conn ? (bt.it ? "Connesso" : "Connected")
                                 : (bt.it ? "Non connesso" : "Not connected"))
            });
        }
        return l;
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: "Bluetooth"
    Accessible.description: bt.valore + (bt.sotto !== "" ? ", " + bt.sotto : "")
}
