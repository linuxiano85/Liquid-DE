import QtQuick
import Quickshell

import "core" as Core

// ProveLuce — La luce notturna, fino al compositore.
//
//     qs -p minerva-shell/prove-luce.qml
//
// ── Perché questa prova esiste ─────────────────────────────────────────────
//
// Il 17 agosto 2026 la luce notturna non funzionava, e non se ne accorgeva
// nessuno guardando: l'impostazione si salvava, il file dello shader NASCEVA
// davvero in ~/.local/state/liquid-de — quindi aprendo la cartella sembrava
// tutto a posto — e `decoration:screen_shader` restava `[[EMPTY]]` per
// sempre. Nessun errore, da nessuna parte.
//
// La causa era `fireShArgs` invece di `shArgs`: i due `fire*` lanciano su un
// `Process` senza stdout, che non emette MAI `done`, e la riga che dice al
// compositore dove sta lo shader aspettava proprio quel `done`.
//
// Quindi si prova l'ULTIMO anello, l'unico che si era rotto: che il
// compositore riceva davvero un percorso. Provare che il file esista non
// avrebbe scoperto niente — quel pezzo funzionava già.
//
// ── Rimette com'era ────────────────────────────────────────────────────────
//
// La prova accende la luce sul serio: per un paio di secondi lo schermo si
// scalda davvero. Alla fine si rimette l'impostazione com'era, accesa o
// spenta che fosse, perché una prova che lascia la scrivania diversa da come
// l'ha trovata è una prova che nessuno vuole far girare.
ShellRoot {
    id: banco

    property int passate: 0
    property int fallite: 0
    property bool comEra: false
    property bool statoLetto: false


    function verifica(nome, condizione, dettaglio) {
        if (condizione) {
            banco.passate++;
            console.log("  ok   " + nome);
        } else {
            banco.fallite++;
            console.log("  NO   " + nome + (dettaglio ? "  → " + dettaglio : ""));
        }
    }

    function fine() {
        console.log("");
        if (banco.fallite > 0)
            console.log("FALLITE " + banco.fallite + " su "
                        + (banco.passate + banco.fallite));
        else
            console.log("TUTTE PASSATE (" + banco.passate + ")");
        Qt.exit(0);
    }

    property bool luceViva: false

    // Si ASPETTA la connessione invece di dare un tempo a caso: con un timer
    // fisso la prova diceva «demone non raggiungibile» perché il canale non
    // aveva ancora fatto in tempo, e poi «TUTTE PASSATE (0)» — cioè il modo
    // più elegante di non provare niente dicendo che è andato tutto bene.
    function comincia() {
        if (banco.avviato)
            return;
        banco.avviato = true;
        console.log("── Prove della luce notturna ─────────────────────────");
        banco.comEra = Core.Ipc.get("display.nightLight", false);

        // ── Cosa prova questo banco, e cosa no ───────────────────────
        //
        // Fino al 1º settembre 2026 qui c'erano due strade. Quella di Hyprland
        // interrogava `hyprctl getoption decoration:screen_shader` e guardava
        // cosa vedeva IL COMPOSITORE; se ne è andata con Hyprland.
        //
        // Resta questa, e la differenza va detta invece che nascosta: qui si
        // guarda quello che gli abbiamo MANDATO — che il verbo `colore` parta,
        // coi numeri giusti, e che spegnendola torni il neutro. Verificare
        // dall'altro capo, dentro minerva-wayland, tocca a
        // `compositore/prova-ingresso.py`, che ha già le prove di quel verbo.
        banco.perNostro();
    }

    property bool avviato: false

    /// La versione per minerva-wayland: si guarda il verbo che parte.
    function perNostro() {
        Core.Ipc.setSetting("display.nightLight", false);
        // I numeri si leggono come NUMERI e non come testo: il compositore
        // scrive «1.0000», e una prova che confronta stringhe fallirebbe il
        // giorno che qualcuno cambia i decimali senza cambiare niente di vero.
        function tre(riga) {
            var p = String(riga).split(" ");
            return (p.length === 4 && p[0] === "colore")
                   ? [parseFloat(p[1]), parseFloat(p[2]), parseFloat(p[3])]
                   : null;
        }

        Core.Compositore.coloreSchermo(1, 1, 1);
        var n = tre(Core.Compositore.ultimaRiga);
        banco.verifica("spenta, il compositore riceve il neutro",
                       n !== null && n[0] === 1 && n[1] === 1 && n[2] === 1,
                       String(Core.Compositore.ultimaRiga));

        // Una tinta calda vera, quella di sera: rossi pieni, blu tolto.
        Core.Compositore.coloreSchermo(1, 0.86, 0.71);
        var c = tre(Core.Compositore.ultimaRiga);
        banco.verifica("accesa, il compositore riceve la tinta calda",
                       c !== null && Math.abs(c[1] - 0.86) < 0.001
                                  && Math.abs(c[2] - 0.71) < 0.001,
                       String(Core.Compositore.ultimaRiga));

        banco.verifica("e il rosso non si tocca mai: si toglie il BLU",
                       c !== null && c[0] === 1 && c[2] < c[1] && c[1] < c[0],
                       "scaldare vuol dire togliere blu, non aggiungere rosso: "
                       + "aggiungerlo schiarirebbe lo schermo invece di "
                       + "ingiallirlo — " + String(Core.Compositore.ultimaRiga));

        Core.Ipc.setSetting("display.nightLight", banco.comEra);
        banco.fine();
    }

    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (Core.Ipc.connected)
                banco.comincia();
        }
    }

    // La rete: se il demone non arriva entro dieci secondi non è una prova
    // saltata, è una prova FALLITA. Un banco che non riesce a provare deve
    // dirlo forte, o la prossima volta nessuno si accorge che non prova più.
    Timer {
        interval: 10000
        running: true
        onTriggered: {
            if (banco.avviato)
                return;
            console.log("── Prove della luce notturna ─────────────────────────");
            banco.verifica("il demone risponde", false,
                           "nessuna connessione entro 10 s: la catena della "
                           + "luce notturna non è stata provata");
            banco.fine();
        }
    }

    Component.onCompleted: {
        // Il singleton va TOCCATO, non solo nominato: un binding su
        // `property var` non basta a istanziarlo, e un singleton che non
        // esiste non reagisce a niente.
        banco.luceViva = Core.LuceNotturna.daApplicare;
        if (Core.Ipc.connected)
            banco.comincia();
    }
}
