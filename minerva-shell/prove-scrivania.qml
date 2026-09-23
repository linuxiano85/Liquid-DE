import QtQuick
import Quickshell
import "menu"

// ProveScrivania — Le prove della griglia delle icone sulla scrivania.
//
//     qs -p minerva-shell/prove-scrivania.qml
//
// ── Perché proprio questa parte ────────────────────────────────────────────
//
// Perché è un pezzo di interfaccia il cui difetto NON si vede guardando il
// codice, e si vede benissimo guardando lo schermo — cioè il tipo di cosa che
// una macchina deve sorvegliare, o si scopre per caso mesi dopo.
//
// Due difetti veri, uno già capitato e uno trovato scrivendo queste prove:
//
//  1. **tutte nella stessa cella.** Ogni icona senza posto ricordato chiedeva
//     «la prima cella libera» a una mappa che nessuno aggiornava: la prima
//     era libera per tutte, e si accatastavano una sull'altra in alto a
//     sinistra. Una sola si vedeva, le altre sembravano sparite.
//  2. **sotto la barra.** La griglia partiva da y=12 su uno schermo in cui la
//     barra della scrivania si prende i primi 44 pixel. La prima riga nasceva
//     mezza coperta, e nessun errore lo diceva.
//
// `DesktopIcons` si costruisce qui dentro senza finestra e senza demone: le
// impostazioni ripiegano sui valori di fabbrica e `Core.Windows` non risponde,
// che è esattamente la condizione in cui la scrivania si disegna la prima
// volta all'accesso.
ShellRoot {
    id: banco

    property int passate: 0
    property int fallite: 0

    function verifica(nome, condizione, dettaglio) {
        if (condizione) {
            banco.passate++;
            console.log("  ok   " + nome);
        } else {
            banco.fallite++;
            console.log("  NO   " + nome + (dettaglio ? "  → " + dettaglio : ""));
        }
    }

    /// Lo schermo di Giacomo: 1920×1080 a scala 1,25 → 1536×864 logici.
    DesktopIcons {
        id: scrivania
        width: 1536
        height: 864
        // Vuota di proposito: con una cartella vera chiederebbe l'elenco al
        // demone, che qui non c'è.
        cartella: ""

        // Fissate a mano invece che lette dalle impostazioni: queste prove
        // devono dire che cosa fa il codice, non che cosa ha scelto Giacomo
        // stamattina. Con i legami intatti, spegnere l'allineamento sulla
        // macchina vera farebbe fallire una prova qui dentro — e la colpa
        // sembrerebbe del codice.
        autoDisponi: false
        allinea: true
        ordine: "name"
        ordineDesc: false
        lato: 46
    }

    function voce(nome) {
        return { "name": nome, "path": "/tmp/" + nome, "isDir": false,
                 "size": 0, "modified": 0 };
    }

    Component.onCompleted: {
        console.log("── Prove della scrivania ─────────────────────────────");

        var S = scrivania;

        // ── La griglia comincia sotto la barra ────────────────────────────
        //
        // Senza risposta dal compositore il ripiego dev'essere l'altezza della
        // barra, non zero: all'accesso le icone si disegnano PRIMA che
        // `Core.Windows` sappia qualcosa, e partire da zero vuol dire nascere
        // coperti per poi saltare giù un istante dopo.
        verifica("la prima riga sta sotto la barra della scrivania",
                 S.sopra >= 44,
                 "sopra = " + S.sopra);
        verifica("e non così in basso da sprecare una riga",
                 S.sopra < 44 + S.cellaH,
                 "sopra = " + S.sopra + ", cella alta " + S.cellaH);

        // ── Andare e tornare fra celle e pixel ────────────────────────────
        var p = S.puntoDiCella(3, 2);
        var c = S.cellaDiPunto(p.x, p.y);
        verifica("la cella di un punto di cella è quella cella",
                 c.x === 3 && c.y === 2,
                 "tornata (" + c.x + "," + c.y + ")");

        // Appena oltre la metà si intende la cella DOPO: chi lascia un'icona
        // lì dentro sta mirando alla successiva, non a quella da cui esce.
        var oltre = S.cellaDiPunto(p.x + S.cellaW * 0.6, p.y);
        verifica("oltre metà cella si aggancia a quella dopo",
                 oltre.x === 4,
                 "tornata colonna " + oltre.x);

        // ── Nessuna cella per due ─────────────────────────────────────────
        var occupate = {};
        occupate["1,1"] = true;
        var vicina = S.cellaLibera(S.puntoDiCella(1, 1).x,
                                   S.puntoDiCella(1, 1).y, occupate);
        verifica("una cella occupata manda alla più vicina libera",
                 !(vicina.x === 1 && vicina.y === 1),
                 "tornata (" + vicina.x + "," + vicina.y + ")");
        verifica("e la più vicina è davvero adiacente",
                 Math.abs(vicina.x - 1) <= 1 && Math.abs(vicina.y - 1) <= 1,
                 "tornata (" + vicina.x + "," + vicina.y + ")");

        // ── Il difetto #1: tutte in alto a sinistra ───────────────────────
        //
        // Cinque file senza posto ricordato. Devono finire in cinque celle
        // diverse, non cinque volte nella stessa.
        S.entries = [banco.voce("a.txt"), banco.voce("b.txt"),
                     banco.voce("c.txt"), banco.voce("d.txt"),
                     banco.voce("e.txt")];
        var d = S.disposizione;
        var visti = {};
        var doppioni = 0;
        for (var k in d) {
            var chiave = d[k].x + "," + d[k].y;
            if (visti[chiave])
                doppioni++;
            visti[chiave] = true;
        }
        verifica("cinque icone senza posto stanno in cinque posti diversi",
                 doppioni === 0,
                 doppioni + " sovrapposte");
        verifica("e sono tutte dentro lo schermo",
                 d["a.txt"].x >= 0 && d["e.txt"].y >= 0
                 && d["e.txt"].y + S.cellaH <= S.height,
                 "l'ultima a y = " + d["e.txt"].y);

        // In colonna, non in riga: è l'ordine in cui nascono le scrivanie
        // classiche, ed è anche l'unico che lascia libero il centro dello
        // schermo, dove stanno le finestre.
        verifica("si riempiono per colonne, dall'alto in basso",
                 d["a.txt"].x === d["b.txt"].x
                 && d["b.txt"].y === d["a.txt"].y + S.cellaH,
                 "a=(" + d["a.txt"].x + "," + d["a.txt"].y + ") b=("
                 + d["b.txt"].x + "," + d["b.txt"].y + ")");

        // ── Una posizione fuori schermo non è una posizione ───────────────
        //
        // Trascinando un'icona a filo del bordo sinistro si finisce con una x
        // negativa, e ritrovarsela mezza fuori al riavvio è il modo peggiore
        // di «ricordare» dove stava.
        S.posizioni = ({ "a.txt": [-40, 300] });
        var fuori = S.disposizione;
        verifica("una posizione fuori dallo schermo viene rimessa dentro",
                 fuori["a.txt"].x >= 0,
                 "x = " + fuori["a.txt"].x);

        // ── L'allineamento aggancia, la libertà no ────────────────────────
        S.posizioni = ({ "a.txt": [137, 261] });
        var agganciata = S.disposizione["a.txt"];
        var cella = S.cellaDiPunto(137, 261);
        var attesa = S.puntoDiCella(cella.x, cella.y);
        verifica("con l'allineamento acceso l'icona si posa in cella",
                 agganciata.x === attesa.x && agganciata.y === attesa.y,
                 "(" + agganciata.x + "," + agganciata.y + ") invece di ("
                 + attesa.x + "," + attesa.y + ")");

        // ── La disposizione automatica ────────────────────────────────────
        //
        // Ignora del tutto le posizioni ricordate: è l'elenco ordinato a dire
        // dove sta cosa. E non le CANCELLA — spegnendola si deve ritrovare la
        // scrivania com'era.
        S.posizioni = ({ "e.txt": [900, 700] });
        S.autoDisponi = true;
        var auto = S.disposizione;
        verifica("a disposizione automatica il primo in ordine sta in cima",
                 auto["a.txt"].x === S.puntoDiCella(0, 0).x
                 && auto["a.txt"].y === S.puntoDiCella(0, 0).y,
                 "a = (" + auto["a.txt"].x + "," + auto["a.txt"].y + ")");
        verifica("e la posizione ricordata di un altro non conta più",
                 auto["e.txt"].x === S.puntoDiCella(0, 4).x
                 && auto["e.txt"].y === S.puntoDiCella(0, 4).y,
                 "e = (" + auto["e.txt"].x + "," + auto["e.txt"].y + ")");

        S.ordineDesc = true;
        var rovescio = S.disposizione;
        verifica("l'ordine inverso mette l'ultimo in cima",
                 rovescio["e.txt"].x === S.puntoDiCella(0, 0).x
                 && rovescio["e.txt"].y === S.puntoDiCella(0, 0).y,
                 "e = (" + rovescio["e.txt"].x + "," + rovescio["e.txt"].y + ")");

        S.autoDisponi = false;
        S.ordineDesc = false;
        verifica("spegnendola si ritrova la posizione ricordata",
                 S.disposizione["e.txt"].x === S.puntoDiCella(
                     S.cellaDiPunto(900, 700).x, S.cellaDiPunto(900, 700).y).x,
                 "e = (" + S.disposizione["e.txt"].x + ","
                 + S.disposizione["e.txt"].y + ")");

        // ── Conclusione ──────────────────────────────────────────────────
        if (banco.fallite === 0)
            console.log("── TUTTE PASSATE (" + banco.passate + ") ─────────────────────");
        else
            console.log("── FALLITE: " + banco.fallite + " su "
                        + (banco.passate + banco.fallite) + " ──────────────────");
    }
}
