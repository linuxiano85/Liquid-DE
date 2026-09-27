pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Compositore — L'UNICO file di Minerva che conosce le parole di Hyprland.
//
// ── Perché esiste ────────────────────────────────────────────────────────
//
// Misurato l'11 agosto 2026: centosei chiamate a `Hyprland.dispatch` e
// `hyprctl` sparse in venticinque file, dodici dei quali importavano
// `Quickshell.Hyprland` di persona. Il 29 luglio si era deciso il contrario —
// una porta sola — e nel frattempo il legame era CRESCIUTO del quaranta per
// cento, perché una regola che non è scritta da nessuna parte non la rispetta
// nessuno.
//
// Non è una questione di eleganza. È la causa di una classe di difetti veri:
// lo stesso 29 luglio c'erano **tre «ingrandisci» diversi** — dalla barra del
// titolo la finestra si fermava sotto la barra della scrivania, dal menu della
// finestra la copriva — perché la stessa intenzione era scritta tre volte, in
// tre punti che non si conoscevano.
//
// ── La divisione del lavoro ──────────────────────────────────────────────
//
//   Compositore   TRADUCE. Sa come si dice in Hyprland «porta questa finestra
//                 davanti». Non sa cosa sia una finestra ridotta a icona, non
//                 tiene elenchi, non ha memoria. Cambiando compositore si
//                 riscrive QUESTO file, e nient'altro.
//
//   Windows       DECIDE. È la politica di Minerva: cosa vuol dire
//                 «ingrandisci» (lo spazio utile meno la cornice), dove nasce
//                 una finestra, cosa succede riducendola a icona. Parla per
//                 intenzioni, e le intenzioni le porta di là.
//
// Senza stato di proposito: così anche una nostra applicazione — che gira in
// un processo suo e non ha nessun motivo di tenere l'elenco delle finestre —
// può chiedere «mettimi a schermo intero» senza tirarsi dietro mezza shell.
Singleton {
    id: comp

    // ══════════════════════════════════════════════════════════════════════
    // Il secondo compositore
    // ══════════════════════════════════════════════════════════════════════
    //
    // Da oggi Minerva parla con DUE compositori: Hyprland, e il nostro
    // `minerva-wayland`. Questo file è già l'unico posto che sa come si dicono
    // le cose a un compositore, quindi è anche l'unico che deve cambiare — che
    // è tutto il motivo per cui esiste (vedi il commento in cima).
    //
    // ── Perché non due file, uno per compositore ─────────────────────────
    //
    // Perché per un mese ci saranno tutti e due, e due file divergono: si
    // corregge un verbo in uno e ci si accorge dell'altro tre settimane dopo,
    // quando si riavvia nell'altro compositore. Con una riga sola per verbo la
    // differenza si vede leggendo.
    //
    // Quando Hyprland uscirà di scena (Tappa 7) si toglie il ramo, non il file.

    /// Vero quando sotto c'è minerva-wayland. Lo dice lui stesso mettendo
    /// `MINERVA_CANALE` nell'ambiente dei programmi che avvia.
    readonly property string percorsoCanale: {
        try {
            return String(Quickshell.env("MINERVA_CANALE") || "");
        } catch (e) {
            return "";
        }
    }
    readonly property bool nostro: comp.percorsoCanale !== ""

    // ── E il terzo caso, che per un anno non è esistito ──────────────────
    //
    // Questo file ha sempre avuto due strade: il nostro compositore, oppure
    // Hyprland. Non ne aveva una terza — e la terza è **tutte le altre
    // scrivanie del mondo**: COSMIC, GNOME, KDE, sway.
    //
    // Sotto una di quelle, `nostro` è falso e si prendeva il ramo di Hyprland,
    // cioè `hyprctl`, cioè un programma che lì non esiste. Le nostre app si
    // aprivano, si vedevano, e i pulsanti della loro barra del titolo **non
    // facevano niente**: niente riduci, niente ingrandisci, niente schermo
    // intero. Nessun errore, nessun avviso: i comandi partivano verso nessuno.
    //
    // Era la causa strutturale di «nemmeno le nostre app su KDE si aprivano»,
    // e la richiesta di Giacomo del 30 agosto 2026: «le nostre app funzionanti
    // su altri desktop environment di qualsiasi tipo».
    //
    // ── Come si esce ─────────────────────────────────────────────────────
    //
    // Non imparando a parlare con ognuna di loro — sarebbe una porta nuova per
    // ogni scrivania, per sempre. Si usa quello che **il protocollo Wayland
    // dà a ogni finestra su sé stessa**: `xdg_toplevel` ha `set_minimized`,
    // `set_maximized` e `set_fullscreen`, e li capiscono tutti i compositori
    // perché sono il protocollo. Il precedente in casa c'è già ed è ottimo:
    // il trascinamento della barra usa `startSystemMove()` per la stessa
    // ragione, e infatti funziona ovunque senza che nessuno l'abbia adattato.
    //
    // Quello che si perde fuori da Minerva è solo ciò che è NOSTRO: «riduci»
    // che va nel pannello delle finestre ridotte, «ingrandisci» che si ferma
    // allo spazio utile invece di coprire la barra. Cose che là non hanno
    // senso, perché là la barra è di qualcun altro.
    /// Vero quando c'è un compositore che ascolta i comandi di Minerva.
    ///
    /// Falso su qualunque altra scrivania — ed è lì che le nostre finestre
    /// devono comandare **sé stesse** invece di chiedere a qualcuno.
    ///
    /// Fino al 1 settembre 2026 era `nostro || c'è Hyprland`. Adesso il
    /// compositore è uno solo, e restano due nomi per la stessa cosa perché
    /// dicono due cose diverse a chi legge: `nostro` è «il canale c'è»,
    /// `comandabile` è «posso chiedere invece di arrangiarmi». Le nostre
    /// finestre girano anche su scrivanie che non sono la nostra, e là questa
    /// risposta è ancora no.
    readonly property bool comandabile: comp.nostro

    /// Il canale è APERTO davvero: c'è qualcuno dall'altra parte.
    ///
    /// Diverso da `nostro`, che dice solo «un percorso me l'hanno dato». La
    /// differenza conta per chi deve sapere se un comando arriva a qualcuno —
    /// per esempio `prove-canale.qml`, che si rifiuta di girare contro la
    /// sessione vera.
    readonly property bool canaleAperto: canale.connected

    Socket {
        id: canale
        path: comp.percorsoCanale
        connected: comp.nostro

        // ── Perché la shell si iscrive, e a una cosa sola ────────────────
        //
        // Le finestre le riceve dal demone, in push, e va bene così: è il
        // demone che OSSERVA. Ma c'è un numero che deve arrivare **subito**,
        // ed è quale scrivania si sta guardando — perché da lui dipende quali
        // barre del titolo si disegnano. Passando dal demone ci mette il suo
        // giro di IPC, e si rivedrebbe il difetto delle «barre che restano»:
        // fra i 150 e i 550 millisecondi di finestra sbagliata, misurati.
        //
        // `ascolta scrivanie` e non `ascolta`: un terminale che cambia titolo
        // a ogni tasto premuto annuncia a ogni tasto premuto, e svegliare per
        // quello il processo che disegna è il conto che questo progetto ha già
        // pagato una volta. Vedi `compositore/src/canale.h`.
        onConnectedChanged: {
            comp._inCorso = [];
            if (canale.connected) {
                // Tre nomi, non tutto: `scrivania` perché da quel numero
                // dipende quali barre del titolo si disegnano, `scorciatoia`
                // perché è la shell che sa cosa voglia dire «cheatsheet», e
                // `coperchio` perché il compositore riferisce il fatto — il
                // coperchio è chiuso — ma la politica (sospendi, blocca, non
                // fare niente) è di chi disegna la scrivania. Un compositore
                // che sospende da sé è una macchina che sparisce senza che
                // nessuno l'abbia chiesto.
                //
                // Non «tutto»: ogni annuncio è una sveglia per questo
                // processo, e iscriversi a quelli che non servono vuol dire
                // una shell che si sveglia a ogni finestra che si muove.
                canale.write("ascolta scrivania scorciatoia coperchio "
                             + "inattivo attivo schermi bordoalto risparmio angolo bordo\n");
                comp._inCorso.push("ascolta");
                comp.chiedi("schermi");
                // Com'è il risparmio adesso: l'annuncio arriva solo quando
                // CAMBIA, e un'app aperta a risparmio già acceso deve
                // saperlo lo stesso (`Core.Vetro.effetto`).
                comp.chiediRisparmio();
                comp.aggiornaScrivanie();
                comp.scorciatoieDaMandare();
                // Tastiera, touchpad e puntatore. Qui e non solo dalla pagina
                // Impostazioni: vedi `applicaIngresso()`, che è il motivo per
                // cui il tocco del trackpad adesso clicca dal primo secondo.
                //
                // Ma SOLO se siamo la scrivania: questo file sta dentro ogni
                // nostra applicazione, e la disposizione della tastiera non è
                // affare del gestore file. Vedi `comp.scrivania`.
                if (comp.scrivania)
                    comp.applicaIngresso();
            }
        }

        parser: SplitParser {
            // Le risposte si leggono anche quando non le si aspetta: un `no …`
            // che nessuno guarda è un comando che non ha funzionato e non l'ha
            // detto a nessuno. È il difetto che in Hyprland si vedeva come
            // «Invalid dispatcher» in un avviso che non fermava niente — e per
            // trovarlo è servito il controllo «la shell gira senza un solo
            // avviso».
            onRead: function (riga) {
                var t = String(riga);
                // Un annuncio non è la risposta a niente: non tocca la coda
                // delle domande, o la sballerebbe di uno per sempre.
                if (t.indexOf("evento ") === 0) {
                    comp._annuncio(t);
                    return;
                }
                if (t.indexOf("no ") === 0)
                    console.warn("[MINERVA][COMPOSITORE] " + t);
                comp._risposta(t);
            }
        }
    }

    /// La riga da mandare, come stringa. A parte dal mandarla, per due motivi
    /// che vanno insieme: si può leggere senza un compositore acceso, e si può
    /// PROVARE — vedi `prove-canale.qml`.
    function _rigaVerbo(verbo, argomenti) {
        var riga = String(verbo);
        if (argomenti !== undefined && argomenti !== null) {
            for (var i = 0; i < argomenti.length; i++)
                riga += " " + argomenti[i];
        }
        return riga;
    }

    /// L'ultima riga mandata al nostro compositore.
    ///
    /// Non è solo per le prove. Con Hyprland, quando un comando era scritto
    /// male, la risposta era «Invalid dispatcher» in un avviso che non fermava
    /// niente: la finestra semplicemente non si muoveva, e per capire cosa le
    /// fosse stato detto bisognava rileggere il codice. Qui lo si legge.
    property string ultimaRiga: ""

    /// I verbi mandati e non ancora risposti, in ordine.
    ///
    /// Il canale non ha numeri di richiesta: il compositore risponde **una
    /// riga per comando, nell'ordine in cui sono arrivati**. Questa coda è
    /// quindi tutto ciò che serve per sapere di chi è quel `ok [...]` — e ci
    /// va OGNI comando, non solo le domande: la risposta a `scrivania 3` è
    /// `ok 3`, e se non occupasse il suo posto in coda si prenderebbe quello
    /// della domanda dopo.
    property var _inCorso: []

    /// Manda un verbo al nostro compositore.
    function _nostro(verbo, argomenti) {
        comp.ultimaRiga = comp._rigaVerbo(verbo, argomenti);
        if (!canale.connected)
            return;
        // Il tetto è una rete, non una regola: se un giorno una risposta non
        // arrivasse, la coda crescerebbe per sempre dentro un processo che
        // non si riavvia mai.
        if (comp._inCorso.length > 64)
            comp._inCorso = comp._inCorso.slice(comp._inCorso.length - 32);
        comp._inCorso.push(String(verbo));
        canale.write(comp.ultimaRiga + "\n");
    }

    /// Una riga di risposta: si guarda a quale comando apparteneva.
    ///
    /// ── E quando la coda si sfasa ────────────────────────────────────────
    ///
    /// Le risposte non hanno un numero: si attribuiscono in ordine di arrivo
    /// (`_inCorso`). Basta un comando che non risponda — o che risponda due
    /// volte — perché da lì in poi ogni risposta finisca sul verbo sbagliato.
    /// All'avvio quella coda contiene una novantina di scorciatoie, e la
    /// pagina Schermi si apriva VUOTA: l'elenco arrivava e veniva attribuito
    /// a una `scorciatoia`. Si riempiva solo cambiando sezione e tornando —
    /// cioè quando la coda si era svuotata. Visto in fotografia il 22
    /// settembre 2026.
    ///
    /// Le risposte lunghe si riconoscono anche dalla FORMA, che è nostra e
    /// non ambigua: un elenco di schermi comincia con `ok [{"nome":`. Quando
    /// la forma parla, vince lei e la coda si allinea a quello che è
    /// davvero arrivato.
    function _risposta(riga) {
        var testo = String(riga);
        var quale = comp._inCorso.length > 0 ? comp._inCorso.shift() : "";
        if (testo.indexOf('ok [{"nome"') === 0 && quale !== "schermi") {
            var dove = comp._inCorso.indexOf("schermi");
            if (dove >= 0) comp._inCorso.splice(dove, 1);
            quale = "schermi";
        }
        if (quale.indexOf("monitori-") === 0) comp.risposta(quale, String(riga));
        if (quale === "schermo-prova" || quale === "schermo-conferma" || quale === "schermo-annulla")
            comp.risposta(quale, String(riga));
        if (quale === "scrivanie" && String(riga).indexOf("ok [") === 0)
            comp._scrivanieNostre = comp.scrivanieDaNostro(riga.substring(3));
        // Gli schermi escono dallo stesso segnale con cui esce la risposta di
        // `hyprctl`: chi ascolta non deve sapere da dove è arrivata.
        if (quale === "schermi" && String(riga).indexOf("ok [") === 0)
            comp.risposta("schermi", riga.substring(3));
        if (quale === "dispositivi" && String(riga).indexOf("ok {") === 0)
            comp.risposta("dispositivi", riga.substring(3));
        // «ok 1211, 94» → «1211, 94», che è parola per parola quello che
        // risponde `hyprctl cursorpos`. Chi legge — il menù del tasto destro
        // — non deve sapere da quale dei due compositori sia arrivata.
        if (quale === "puntatore" && String(riga).indexOf("ok ") === 0)
            comp.risposta("puntatore", riga.substring(3));
        if (quale === "risparmio" && String(riga).indexOf("ok {") === 0)
            comp._risparmioDa(riga.substring(3));
        if (quale === "stato" && String(riga).indexOf("ok {") === 0) {
            try {
                comp.statoCompositore = JSON.parse(riga.substring(3));
            } catch (e5) {
                console.warn("[MINERVA][COMPOSITORE] stato illeggibile: " + riga);
            }
        }
    }

    /// ── Quello che il compositore SA di sé ───────────────────────────────
    ///
    /// Non è un lusso: ci sono cose che il compositore fa o non fa secondo
    /// l'hardware, e che da fuori sono indistinguibili da una manopola
    /// spenta. La luce notturna è il caso da manuale — la tabella dei colori
    /// la prende lo schermo, e uno schermo che non la prende lascia tutto
    /// com'era senza un errore da nessuna parte. È rimasta rotta due
    /// settimane esattamente per questo.
    ///
    /// Dentro ci sono `tinta`, `tintaStrada`, `effetto`, `effettoAlfa`,
    /// `cornice`, `bloccato`. Si chiede quando serve — è una domanda, non un
    /// annuncio — e chi la mostra deve saper stare senza: un oggetto vuoto è
    /// il caso normale finché la risposta non arriva.
    property var statoCompositore: ({})

    /// ── Il modo risparmio ────────────────────────────────────────────────
    ///
    /// A batteria bassa (o col profilo «risparmio energetico») il compositore
    /// abbassa gli effetti da sé: niente blur né trasparenza, la cornice
    /// smette di girare, l'elastico si ferma. `Core.Vetro.effetto` segue. Lo decide LUI — una shell ferma non deve
    /// lasciare gli effetti accesi a batteria scarica — e qui si dice solo la
    /// regola e si ascolta com'è andata.
    ///
    ///   {modo: "mai|auto|sempre", soglia, attivo, motivo: "batteria|profilo|
    ///    chiesto"|null, batteria, percento, scarica, profiloRisparmio}
    ///
    /// Vuoto finché il compositore non ha risposto.
    property var risparmio: ({})

    /// Il risparmio ha cambiato stato. Lo ascolta `shell.qml` per dirlo: un
    /// effetto che si spegne da solo senza una parola sembra un guasto.
    signal risparmioCambiato()

    function regolaRisparmio(modo, soglia) {
        if (!comp.nostro)
            return;
        var m = (modo === "mai" || modo === "sempre") ? modo : "auto";
        var v = Math.round(Number(soglia));
        if (!isFinite(v)) v = 20;
        comp._nostro("risparmio", [m, String(Math.max(5, Math.min(80, v)))]);
    }

    function chiediRisparmio() {
        if (comp.nostro)
            comp._nostro("risparmio", []);
    }

    function _risparmioDa(testo) {
        try {
            comp.risparmio = JSON.parse(testo);
        } catch (e) {
            console.warn("[MINERVA][COMPOSITORE] risparmio illeggibile: " + testo);
        }
    }

    function chiediStato() {
        if (!comp.nostro)
            return;
        comp._nostro("stato", []);
    }

    /// Una riga di annuncio. Qui ne arriva una sola — vedi il commento sul
    /// socket — e trattarne una in più senza dirlo sarebbe il modo di
    /// ritrovarsi la shell sveglia a ogni tasto premuto in un terminale.
    function _annuncio(riga) {
        var t = String(riga);
        // ── Uno schermo è arrivato o se n'è andato ───────────────────────
        //
        // Il compositore lo annuncia (`evento schermi`), e da qui si richiede
        // l'elenco: la risposta esce dallo stesso `risposta("schermi")` di
        // sempre, e la pagina Schermi si aggiorna senza riavviare la
        // sessione — era il difetto del 20 settembre 2026, «se collego uno
        // schermo hdmi devo chiudere sessione e riaprirla». Nessun timer di
        // pausa: la porta non tiene stato (`porta_compositore_test`), e un
        // secondo annuncio nello stesso battito costa una richiesta in più,
        // non un difetto.
        if (t.indexOf("evento schermi ") === 0) {
            Qt.callLater(function () { comp.chiedi("schermi"); });
            return;
        }
        if (t.indexOf("evento scorciatoia ") === 0) {
            try {
                var sc = JSON.parse(t.substring(19));
                if (sc && sc.azione)
                    comp.scorciatoiaPremuta(String(sc.azione));
            } catch (e2) {
                console.warn("[MINERVA][COMPOSITORE] scorciatoia illeggibile: "
                             + t);
            }
            return;
        }
        if (t.indexOf("evento coperchio ") === 0) {
            try {
                var cp = JSON.parse(t.substring(17));
                if (cp)
                    comp.coperchio(cp.chiuso === true);
            } catch (e3) {
                console.warn("[MINERVA][COMPOSITORE] coperchio illeggibile: "
                             + t);
            }
            return;
        }
        // ── L'inattività ─────────────────────────────────────────────
        //
        // Anche qui solo il FATTO: «sono passati tanti secondi senza che
        // nessuno tocchi niente». Cosa farne — abbassare la luce, bloccare,
        // sospendere — lo decide chi ascolta, ed è `shell.qml` leggendo
        // `power.dimAfter`, `power.lockAfter`, `power.suspendAfter`. Stessa
        // divisione del coperchio, e per la stessa ragione: una sospensione
        // decisa dal compositore è una macchina che sparisce.
        if (t.indexOf("evento inattivo ") === 0) {
            try {
                var iv = JSON.parse(t.substring(16));
                if (iv && iv.secondi > 0)
                    comp.inattivo(Number(iv.secondi));
            } catch (e4) {
                console.warn("[MINERVA][COMPOSITORE] inattività illeggibile: "
                             + t);
            }
            return;
        }
        if (t.indexOf("evento attivo") === 0) {
            comp.attivo();
            return;
        }
        if (t.indexOf("evento risparmio ") === 0) {
            comp._risparmioDa(t.substring(17));
            comp.risparmioCambiato();
            return;
        }
        if (t.indexOf("evento angolo ") === 0) {
            var aq = "", as = "";
            try {
                var av = JSON.parse(t.substring(14));
                aq = av && av.quale ? String(av.quale) : "";
                as = av && av.schermo ? String(av.schermo) : "";
            } catch (e6) {}
            if (aq !== "")
                comp.angolo(aq, as);
            return;
        }
        if (t.indexOf("evento bordo ") === 0) {
            var bq = "", bs = "";
            try {
                var bw = JSON.parse(t.substring(13));
                bq = bw && bw.quale ? String(bw.quale) : "";
                bs = bw && bw.schermo ? String(bw.schermo) : "";
            } catch (e7) {}
            if (bq !== "")
                comp.bordo(bq, bs);
            return;
        }
        if (t.indexOf("evento bordoalto ") === 0) {
            var sb = "";
            try {
                var bv = JSON.parse(t.substring(17));
                sb = bv && bv.schermo ? String(bv.schermo) : "";
            } catch (e5) {}
            comp.bordoAlto(sb);
            return;
        }
        if (t.indexOf("evento scrivania ") !== 0)
            return;
        try {
            var d = JSON.parse(t.substring(17));
            if (d && d.attiva > 0) {
                comp._scrivaniaDaEvento = d.attiva;
                // L'elenco di quali scrivanie esistono cambia insieme a
                // questo: chi era vuota adesso si guarda, e va accesa.
                comp.aggiornaScrivanie();
                comp.scrivanieCambiate();
            }
        } catch (e) {
            console.warn("[MINERVA][COMPOSITORE] annuncio illeggibile: " + t);
        }
    }

    // ── Le scorciatoie, mandate al compositore ───────────────────────────
    //
    // Sotto Hyprland i tasti li registra Hyprland leggendo il file che
    // generiamo noi. minerva-wayland non legge nessun file — di proposito: due
    // parser per `config/scorciatoie.minerva` sono due parser che un giorno
    // non sono più d'accordo. Le riceve già masticate dal demone, e a
    // portargliele è la shell, che è quella che ha il canale in mano.
    //
    // Si rimandano tutte da capo a ogni cambiamento del file, precedute da
    // `scorciatoie azzera`: aggiungere e basta vorrebbe dire una tabella che
    // cresce a ogni ricarica, con dentro le regole di ieri.
    function scorciatoieDaMandare() {
        if (!comp.nostro)
            return;
        Ipc.scorciatoieCompositore();
    }

    function mandaScorciatoie(righe) {
        if (!comp.nostro || !righe)
            return;
        for (var i = 0; i < righe.length; i++) {
            var r = String(righe[i]);
            var sp = r.indexOf(" ");
            if (sp < 0) {
                comp._nostro(r, []);
                continue;
            }
            comp._nostro(r.substring(0, sp), [r.substring(sp + 1)]);
        }
    }

    property Connections _scorciatoieDalDemone: Connections {
        target: Ipc
        function onScorciatoieCompositoreArrivate(righe) {
            comp.mandaScorciatoie(righe);
        }
    }

    /// Da `[{"id":1,"nome":"1","finestre":2,"attiva":true},…]` all'elenco che
    /// conosce Minerva. Funzione pura, e quindi provabile senza un
    /// compositore acceso — vedi `prove-canale.qml`.
    function scrivanieDaNostro(json) {
        var fuori = [];
        try {
            var l = JSON.parse(json);
            for (var i = 0; i < l.length; i++)
                fuori.push({ "id": l[i].id,
                             "nome": String(l[i].nome !== undefined
                                            ? l[i].nome : l[i].id),
                             "finestre": l[i].finestre || 0,
                             "attiva": l[i].attiva === true });
        } catch (e) {
            return [];
        }
        return fuori;
    }

    /// Come si nomina una finestra. Hyprland vuole `address:0x…`; un altro
    /// compositore vorrà altro, e chi chiama non deve saperlo.
    ///
    /// Si accettano tutte e due le forme, perché tutte e due esistono già nel
    /// codice: l'indirizzo nudo (`0x55…`) e il selettore intero
    /// (`address:0x55…`, `pid:1234`, `class:kitty`). Riconoscerle qui evita di
    /// dover convertire in venti punti di chiamata — e i venti punti di
    /// chiamata sono esattamente ciò da cui questo file ci sta togliendo.
    function _selettore(chi) {
        var t = String(chi);
        return t.indexOf(":") >= 0 ? t : "address:" + t;
    }

    /// Come si nomina una finestra per minerva-wayland, **compreso il caso di
    /// nessuna**: là «la finestra attiva» si dice `attiva`, ed è una parola,
    /// non un vuoto. `_selettore("")` darebbe `address:`, che il compositore
    /// cercherebbe davvero e non troverebbe — un comando che fallisce con un
    /// messaggio che parla di un indirizzo che nessuno ha scritto.
    function _chi(indirizzo) {
        return indirizzo && indirizzo !== ""
               ? comp._selettore(indirizzo) : "attiva";
    }

    // ── Fuoco e ordine di sovrapposizione ────────────────────────────────

    /// Sposta il fuoco. NON tocca l'ordine di sovrapposizione: per quello c'è
    /// `davanti`, e servono tutte e due — vedi `Windows.focus`.
    function fuoco(indirizzo) {
        if (!indirizzo)
            return;
        comp._nostro("fuoco", [comp._selettore(indirizzo)]);
    }

    /// Porta una finestra in cima alla pila.
    function davanti(indirizzo) {
        if (!indirizzo)
            return;
        comp._nostro("davanti", [comp._selettore(indirizzo)]);
    }

    /// Il fuoco alla finestra di QUESTO processo.
    ///
    /// Lo chiedono le nostre applicazioni quando qualcuno le rilancia mentre
    /// sono già aperte: l'istanza nuova muore subito, e prima di morire fa
    /// venire avanti quella viva. Si va per numero di processo perché
    /// l'indirizzo della propria finestra non lo si conosce da dentro.
    function fuocoAlNostroProcesso() {
        // `pid:` lo capiscono tutti e due, ed è il solo posto dove serve: qui
        // la finestra è nostra e appena aperta, e il suo indirizzo non lo
        // sappiamo ancora. Attenzione però — cinque programmi di Minerva
        // vivono in un processo solo, quindi un pid può nominarne cinque:
        // prende quella più in alto. Chi ha bisogno di essere preciso manda il
        // titolo (vedi `core/TenutaPronta.qml`).
        comp._nostro("fuoco", ["pid:" + Quickshell.processId]);
    }

    // ── Chiudere ─────────────────────────────────────────────────────────

    /// Chiude una finestra. Senza indirizzo, quella che ha il fuoco.
    function chiudi(indirizzo) {
        if (indirizzo)
            comp._nostro("chiudi", [comp._selettore(indirizzo)]);
        else
            comp._nostro("chiudi", ["attiva"]);
    }

    // ── Geometria ────────────────────────────────────────────────────────

    /// Libera una finestra dalla griglia. In Minerva ogni finestra nasce già
    /// libera (vedi `core/WindowRules.qml`); serve per quelle che arrivano
    /// agganciate da una regola altrui.
    ///
    /// ── SPAZIO, non virgola ──────────────────────────────────────────────
    ///
    /// E non è una sottigliezza: **il separatore cambia da comando a comando**.
    /// `movewindowpixel exact X Y,address:…` vuole la virgola perché prima ci
    /// sono i suoi parametri; `setfloating address:…` vuole lo spazio perché
    /// il bersaglio È il suo unico parametro. Sbagliando, Hyprland risponde
    /// `Invalid dispatcher` — a voce bassa, in un avviso che non ferma niente:
    /// la finestra semplicemente non si libera, e non si capisce perché.
    ///
    /// Preso l'11 agosto 2026 dal controllo «la shell gira senza un solo
    /// avviso», che è l'unico ad averlo visto: nessuna prova statica poteva.
    function libera(indirizzo) {
        // ── Non fa NIENTE, ed è una scelta e non una mancanza ────────────
        //
        // In minerva-wayland il tiling non esiste: ogni finestra galleggia
        // già. Questa riga serviva a tirare una finestra fuori dalla griglia
        // di Hyprland, e una griglia non c'è più.
        //
        // La funzione resta perché resta chi la chiama, e chi la chiama sta
        // dicendo una cosa sensata — «questa deve galleggiare». Mandare un
        // verbo per ottenere quello che è già vero sarebbe rumore sul canale
        // e un verbo in più da mantenere.
        void indirizzo;
    }

    /// Sposta l'angolo in alto a sinistra, in pixel assoluti.
    function sposta(indirizzo, x, y) {
        comp._nostro("sposta", [indirizzo ? comp._selettore(indirizzo) : "attiva",
                                Math.round(x), Math.round(y)]);
    }

    /// Cambia la misura, in pixel. È la misura della FINESTRA, non del suo
    /// ingombro: la barra del titolo e la cornice stanno fuori da lei, e chi
    /// chiama deve averle già tolte — vedi `Windows.bordo` e `barSopra`.
    function ridimensiona(indirizzo, larghezza, altezza) {
        comp._nostro("ridimensiona",
                     [indirizzo ? comp._selettore(indirizzo) : "attiva",
                      Math.round(larghezza), Math.round(altezza)]);
    }

    // ── Schermo intero, e i suoi tre significati ─────────────────────────
    //
    // Hyprland ne ha tre, e confonderli è costato giornate:
    //
    //   fullscreen 0            schermo intero VERO: il compositore toglie di
    //                           mezzo tutto, barra della scrivania compresa.
    //   fullscreenstate 1 -1    «ingrandito» per il compositore: rispetta lo
    //                           spazio riservato, e quindi la cornice.
    //   fullscreenstate 0 1     non cambia niente sullo schermo: DICE al
    //                           programma che è ingrandito, e basta. Serve per
    //                           i programmi che si disegnano la cornice da sé
    //                           (Chrome, GNOME) e che altrimenti mostrano il
    //                           pulsante sbagliato.

    /// Schermo intero vero. `acceso` falso lo toglie.
    function schermoIntero(indirizzo, acceso) {
        var chi = indirizzo ? comp._selettore(indirizzo) : "attiva";
        if (acceso === false)
            comp._nostro("schermointero", [chi, 0]);
        else
            comp._nostro("schermointero", [chi, 1]);
    }

    /// Commuta lo schermo intero della finestra indicata (o dell'attiva).
    /// Ingrandisce, o rimette com'era, una finestra: lo stato è del
    /// compositore (`finestra_ingrandisci`). Senza `si` commuta.
    function ingrandisci(indirizzo, si) {
        var argomenti = [indirizzo ? comp._selettore(indirizzo) : "attiva"];
        if (si !== undefined)
            argomenti.push(si ? "si" : "no");
        comp._nostro("ingrandisci", argomenti);
    }

    function commutaSchermoIntero(indirizzo) {
        comp._nostro("schermointero",
                     [indirizzo ? comp._selettore(indirizzo) : "attiva"]);
    }

    // ── Qui c'era «dilloAlProgramma», e non c'è più ──────────────────────
    //
    // Era il «finto schermo intero» di Hyprland: accendeva NEL PROGRAMMA il
    // segno «sei massimizzato» senza che il compositore facesse niente — la
    // casella che fa cedere Chrome e gli fa mostrare «ripristina» al posto di
    // «ingrandisci». Il nostro compositore non ce l'ha e non lo vuole: da noi
    // «ingrandita» è uno stato vero, e il programma lo sa perché glielo dice
    // xdg-shell.
    //
    // Era rimasta come funzione vuota, e una funzione vuota che si continua a
    // chiamare è una bugia lenta: chi legge il codice crede che qualcosa
    // succeda. Se n'è andata insieme ai suoi due punti di chiamata in
    // `core/Windows.qml`.

    // ── E il terzo modo NON si offre ─────────────────────────────────────
    //
    // Qui c'era `ingrandimentoDelCompositore()`, cioè `fullscreenstate 1 -1`.
    // Non la chiamava nessuno, ed è stata tolta di proposito: **quel modo, in
    // Minerva, non si usa.**
    //
    // «Ingrandisci» qui è GEOMETRIA — `Windows.maximize` ridimensiona e
    // sposta, e il plugin fa lo stesso conto. Una finestra nel modo 1 del
    // compositore si prende l'ingresso e lascia le altre disegnate e mute:
    // Giacomo, 12 agosto 2026, «è diventata una finestra fantasma». Il
    // colpevole era proprio quel comando, dentro il plugin.
    //
    // Una porta che offre un attrezzo che non va usato è una porta che invita
    // a usarlo. Se un giorno servisse davvero, va rimesso INSIEME alla ragione
    // per cui stavolta va bene.

    // ── Scrivanie ────────────────────────────────────────────────────────

    // ── Su quale scrivania siamo, e perché non basta chiederlo ───────────
    //
    // `Hyprland.focusedWorkspace` è la risposta giusta, ma arriva TARDI: si
    // popola con `refreshWorkspaces()`, che è asincrona. Fra il cambio di
    // scrivania e la risposta passano dei decimi di secondo, e in quei decimi
    // questa proprietà dice ancora la scrivania di prima.
    //
    // Non è teoria. Il 25 agosto 2026, misurato fotografando lo schermo subito
    // dopo `workspace 2`: la barra del titolo di Konsole **restava disegnata
    // sopra lo sfondo della scrivania vuota** per un tempo fra i 150 e i 550
    // millisecondi. `spine/TitleBars.qml` nasconde le barre delle finestre
    // che non sono su questa scrivania, e per farlo confronta con questo
    // numero: finché il numero è vecchio, le barre restano. Sono le parole di
    // Giacomo, «rimangono dei residui».
    //
    // C'era anche una seconda metà del difetto, peggiore: a chiamare
    // `aggiornaScrivanie()` era `spine/Workspaces.qml`, cioè i pallini sulla
    // barra. Con la barra nascosta o non caricata **nessuno** la chiamava, e
    // il numero non si aggiornava mai.
    //
    // ── Le due strade, come per la finestra attiva ───────────────────────
    //
    // È lo stesso schema di `Windows.activeAddress`, e per la stessa ragione:
    //
    //  · l'EVENTO, che porta il numero e arriva subito;
    //  · l'ELENCO, che ci mette un attimo ma c'è sempre e rimette a posto le
    //    cose se un evento si perde.
    //
    // L'evento vince finché l'elenco non lo raggiunge; quando l'elenco cambia,
    // l'evento si dimentica e si torna alla sorgente autorevole. Se i due non
    // fossero d'accordo vincerebbe comunque il più recente, che è quello che
    // si vuole.

    /// La scrivania detta dall'ultimo evento del compositore, o 0.
    property int _scrivaniaDaEvento: 0

    /// L'elenco delle scrivanie come lo dice minerva-wayland.
    property var _scrivanieNostre: []

    /// La scrivania in uso, o 1 se il compositore non l'ha ancora detto.
    ///
    /// Le due sorgenti valgono per tutti e due i compositori, ed è il punto:
    /// l'EVENTO arriva subito, l'ELENCO ci mette un attimo ma c'è sempre.
    /// Sotto minerva-wayland l'evento è `evento scrivania` e l'elenco è la
    /// risposta a `scrivanie`; sotto Hyprland sono `workspacev2` e
    /// `focusedWorkspace`. Chi legge non deve saperlo.
    readonly property int scrivaniaAttiva: {
        if (comp._scrivaniaDaEvento > 0)
            return comp._scrivaniaDaEvento;
        for (var i = 0; i < comp._scrivanieNostre.length; i++)
            if (comp._scrivanieNostre[i].attiva)
                return comp._scrivanieNostre[i].id;
        return 1;
    }

    /// Il nome dello schermo che ha il fuoco. Serve alla shell per sapere su
    /// quale monitor agisce una scorciatoia, quando gli schermi sono due.
    ///
    /// Sotto minerva-wayland vale `""` **di proposito e dichiarato**: vedi la
    /// riga `monitorAttivo` in `senzaDestinazione`, che dice quanto costa
    /// saperlo davvero e perché su una macchina a schermo singolo il ripiego
    /// di chi la usa è sempre la risposta giusta.
    readonly property string monitorAttivo: ""

    /// Il suo NOME, che in Hyprland può non essere un numero
    /// (`special:minimized` è una scrivania a tutti gli effetti).
    readonly property string nomeScrivaniaAttiva: {
        // In minerva-wayland una scrivania È il suo numero: non ci sono nomi,
        // e non c'è la scrivania di servizio dei ridotti — «ridotta» qui è uno
        // stato della finestra, non un posto dove mandarla.
        return String(comp.scrivaniaAttiva);
    }

    /// Tutte le scrivanie che esistono adesso, come `{ id, nome }`. Ridotte a
    /// questi due campi di proposito: chi le disegna non deve poter dipendere
    /// da com'è fatto l'oggetto di Hyprland.
    readonly property var scrivanie: {
        comp._scosse;
        return comp._scrivanieNostre;
    }

    /// Rilegge l'elenco delle scrivanie dal compositore.
    function aggiornaScrivanie() {
        // È una DOMANDA, e la risposta arriva sul socket: la raccoglie
        // `_risposta()`, che sa a quale comando apparteneva.
        comp._nostro("scrivanie", []);
        comp._scosse++;
    }

    function vaiAScrivania(numero) {
        comp._nostro("scrivania", [numero]);
    }

    /// La scrivania vicina, saltando quelle vuote — è il gesto della rotellina
    /// sopra i pallini della barra.
    function scrivaniaVicina(avanti) {
        comp._nostro("scrivania", [avanti ? "avanti" : "indietro"]);
    }

    /// Manda una finestra su una scrivania. `silenzioso` vuol dire senza
    /// seguirla.
    function portaAScrivania(indirizzo, scrivania, silenzioso) {
        var verbo = silenzioso ? "movetoworkspacesilent" : "movetoworkspace";
        comp._nostro("portaascrivania",
                     [comp._chi(indirizzo), scrivania, silenzioso ? "si" : "no"]);
    }

    /// Riduce a icona, o riporta indietro.
    ///
    /// ── Perché è un verbo suo e non «mandala nella scrivania speciale» ────
    ///
    /// Perché «ridurre a icona» è un'INTENZIONE, e la scrivania speciale è il
    /// modo in cui Hyprland la realizza. Qui c'era il modo: `minimize()`
    /// chiamava `portaAScrivania(indirizzo, "special:minimized", true)`, che è
    /// un `dispatch` e basta.
    ///
    /// Sotto il nostro compositore quel `dispatch` non arriva a nessuno: le
    /// scrivanie in `minerva-wayland` non esistono ancora, e la riga se ne
    /// andava in silenzio. Il risultato è la cosa peggiore che possa fare un
    /// «riduci»: la finestra spariva dallo schermo e non c'era modo di
    /// riportarla indietro, perché non era ridotta — era stata mandata da
    /// nessuna parte. Il compositore il verbo `riduci` lo sapeva già fare, e
    /// nessuno glielo chiedeva.
    ///
    /// Ridotta o no, la finestra resta nell'elenco: è quello che permette alla
    /// dock di mostrarla spenta e di riportarla su con un clic. Una finestra
    /// che sparisce dall'elenco è una finestra persa.
    function riduci(indirizzo, si) {
        var giu = si !== false;
        comp._nostro("riduci", [comp._selettore(indirizzo), giu ? "si" : "no"]);
    }

    // ── Configurazione a caldo ───────────────────────────────────────────
    //
    // Le Impostazioni cambiano valori che il compositore tiene suoi: la
    // disposizione della tastiera, la sensibilità del touchpad, i monitor, lo
    // zoom del cursore. Si applicano subito e si riscrivono nel file, che è la
    // memoria vera — vedi `config/hypr/`.

    /// Cambia un valore di configurazione, adesso.
    ///
    /// **Non chiamarla da fuori con una chiave di Hyprland scritta a mano.**
    /// Resta pubblica perché ci sono due cose che una tabella non può coprire
    /// — le righe `monitor`, che sono una sintassi e non un valore, e le
    /// chiavi del nostro plugin — ma tutto il resto ha la sua INTENZIONE qui
    /// sotto, ed è lì che va chiesto.
    ///
    /// Il perché, scritto il 19 agosto 2026: sopra questa funzione c'era
    /// scritto che «chi cambia compositore ha qui l'elenco completo di cosa
    /// deve tradurre». Era falso. L'elenco stava in **otto file**: ventisette
    /// punti che nominavano `decoration:blur:size`, `input:kb_layout`,
    /// `animations:enabled`. I VERBI erano passati dalla porta (106 dispatch
    /// → 0), i SOSTANTIVI no.
    ///
    /// E la dispersione aveva già fatto il suo danno: `animations:enabled`
    /// veniva scritta da tre file che non si conoscevano. È la stessa forma
    /// che in luglio aveva prodotto tre «ingrandisci» diversi.
    // ══════════════════════════════════════════════════════════════════════
    // Le manopole che sotto minerva-wayland non hanno ancora una strada
    // ══════════════════════════════════════════════════════════════════════
    //
    // Una cosa che il compositore non sa ancora fare si dice qui, col perché,
    // invece di sparire in silenzio: chi la chiede lo trova scritto nel
    // registro una volta (`_senzaStrada`). Fino al 27 settembre 2026 qui
    // passava anche `imposta()`, l'imbuto delle chiavi di Hyprland: nessuno
    // la chiamava più, ed è stata tolta.
    readonly property var senzaDestinazione: ({
        "monitorAttivo":
            "quale schermo ha il puntatore. Il compositore lo sa (ogni schermo esce da «schermi» con «attivo»), ma saperlo di continuo vorrebbe dire chiederglielo a ogni movimento del mouse — cioè svegliare la shell per un dato che serve solo quando si preme una scorciatoia. Chi lo usa (shell.qml) ha già il ripiego «il primo schermo», che su una macchina a schermo singolo è sempre quello giusto; con due schermi una scorciatoia può colpire l'altro. Si chiude quando ci sarà un secondo schermo su cui provarlo"
    })

    /// Detto una volta sola. Una manopola si gira decine di volte — a ogni
    /// scatto di un cursore nelle Impostazioni — e una riga per scatto
    /// riempirebbe il registro di una notizia sola ripetuta, che è il modo in
    /// cui un registro smette di servire.
    property var _dettoSenzaStrada: ({})

    function _senzaStrada(cosa) {
        if (comp._dettoSenzaStrada[cosa])
            return;
        comp._dettoSenzaStrada[cosa] = true;
        console.log("[MINERVA][Compositore] «" + cosa + "» non ha una strada "
                    + "sotto minerva-wayland: "
                    + (comp.senzaDestinazione[cosa] || "motivo non dichiarato"));
    }

    // ── Tradurre quello che il compositore RISPONDE ──────────────────────
    //
    // Le intenzioni qui sotto traducono quello che Minerva CHIEDE. Questa
    // traduce il verso opposto: la forma in cui il compositore descrive una
    // finestra.
    //
    // Stava in `core/Windows.qml`, ed era l'ultimo pezzo di vocabolario di
    // Hyprland fuori da questo file: `at`, `size`, `class`, `address`,
    // `focusHistoryID`, `fullscreenClient` sono nomi suoi. La divisione
    // dichiarata da questo progetto è «Compositore **traduce**, Windows
    // **decide**», e finché la forma della risposta si leggeva di là la
    // regola era vera a metà: cambiando compositore i file da riscrivere
    // erano due, non uno.

    // ── Gli schermi, e lo stesso bivio ───────────────────────────────────
    //
    // Stava in `core/Windows.qml`, e leggeva `reserved`, `focused`, `width` —
    // nomi di Hyprland — con la stessa incoerenza per cui la lettura delle
    // finestre è stata spostata qui: la regola dice «Compositore traduce,
    // Windows decide», e finché la forma degli schermi si leggeva di là erano
    // due i file da riscrivere per cambiare compositore.

    /// Uno schermo, come lo conosce Minerva: `{ id, nome, attivo, x, y, w, h,
    /// sx, sy, sw, sh }`, dove `x,y,w,h` è lo spazio UTILE e `sx,sy,sw,sh` il
    /// contorno vero — barre comprese.
    function schermoDaCompositore(m, indice) {
        return comp._schermoDaNostro(m, indice);
    }

    function _schermoDaNostro(m, indice) {
        // Già in pixel logici e già sottratto: il compositore manda il
        // rettangolo utile invece delle quattro zone riservate, perché quel
        // conto lo fa comunque per decidere dove nasce una finestra.
        return {
            "id": indice,
            "nome": m.nome || "",
            "attivo": m.attivo === true,
            "x": m.utileX || 0,
            "y": m.utileY || 0,
            "w": m.utileLarghezza || 0,
            "h": m.utileAltezza || 0,
            "sx": m.x || 0,
            "sy": m.y || 0,
            "sw": m.larghezza || 0,
            "sh": m.altezza || 0
        };
    }


    /// Da come le descrive **minerva-wayland**, a come le conosce Minerva.
    ///
    /// I nomi sono già in italiano perché il compositore è nostro e non aveva
    /// motivo di parlare inglese. Restano comunque una traduzione: `posto` non
    /// è `stack` per caso, ed è qui che si dice che sono la stessa cosa.
    function _finestraDaNostro(c) {
        var titolo = c.titolo || c.classe || "";
        if (titolo.length > 90)
            titolo = c.classe || titolo;

        return {
            "address": c.id || "",
            "pid": c.pid || 0,
            "title": titolo,
            "appClass": c.classe || "",
            "minimized": c.ridotta === true,
            // In minerva-wayland il tiling non c'è: ogni finestra galleggia.
            // Non è un ripiego — è la scelta di Minerva, presa a luglio e
            // scritta in `minerva-finestre-modi`. Il compositore nuovo la
            // eredita, e quindi non ha un bit da mandare.
            "floating": true,
            // `posto` è già l'ordine di sovrapposizione: 0 la finestra
            // attiva. In Hyprland lo stesso numero si chiama
            // `focusHistoryID` e va DEDOTTO; qui l'elenco è la pila.
            "stack": c.posto === undefined ? 9999 : c.posto,
            "fullscreen": c.schermoIntero === true,
            // Il modo grezzo esiste perché Hyprland ne ha tre. Qui i tre stati
            // sono due bit separati, e si ricompongono nella stessa scala per
            // non obbligare chi legge a conoscerne due.
            "modoSchermo": c.schermoIntero === true ? 2
                         : (c.ingrandita === true ? 1 : 0),
            // Fino al 25 agosto qui c'era scritto `1`, perché le scrivanie in
            // minerva-wayland non esistevano. Adesso esistono, e questo numero
            // è quello che dice a `spine/TitleBars.qml` quali barre disegnare:
            // sbagliarlo vuol dire la barra di una finestra che sta altrove
            // disegnata sopra lo sfondo di questa.
            "workspace": c.scrivania || 1,
            "x": c.x || 0, "y": c.y || 0,
            "w": c.larghezza || 0, "h": c.altezza || 0
        };
    }

    /// Da come le descrive **Hyprland**, a come le conosce Minerva.
    ///
    /// Ogni campo qui sotto è una TRADUZIONE, non una decisione: cosa voglia
    /// dire «ingrandita», quale finestra sia nascosta e cosa farne lo decide
    /// `core/Windows.qml`, che riceve già roba in lingua nostra.
    function finestraDaCompositore(c) {
        // Una finestra come la manda il nostro compositore (`finestre`). Qui
        // c'era anche la lettura del formato di Hyprland — `at`, `size`,
        // `focusHistoryID`, «ridotta» come scrivania di servizio — per il mese
        // in cui i compositori erano due. Tolta il 27 settembre 2026.
        return comp._finestraDaNostro(c || {});
    }

    // ── Le intenzioni ────────────────────────────────────────────────────
    //
    // Qui, e in nessun altro posto, sta la tabella fra quello che Minerva
    // vuole e il nome che Hyprland gli dà. Chi cambia compositore riscrive
    // QUESTE funzioni: chi le chiama non si accorge di niente.
    //
    // I nomi sono quello che si vuole ottenere, non come si chiama la
    // manopola.
    //
    // Le animazioni del compositore non hanno un verbo loro: l'interruttore
    // generale (`desktop.animations`) porta a zero l'elastico delle finestre
    // (`shell.qml`, `WindowRules.elastico`), e i movimenti liquidi della
    // Tappa 3 si regoleranno da lì. Qui c'erano sei funzioni che non
    // mandavano niente — gruppi, animazioni «avanzate», scia — con la tabella
    // dei nomi delle animazioni di Hyprland: tolte il 27 settembre 2026.

    /// L'ingrandimento della lente attorno al puntatore. 1 = nessuno.
    function ingrandimentoPuntatore(fattore) {
        // Da noi si chiama «lente», e non ridisegna niente: ritaglia la
        // fetta di schermo da mostrare. Vedi `lente_commit` in main.c —
        // spenta costa esattamente zero, che è la ragione per cui una
        // modifica dentro il percorso del disegno è stata accettabile.
        var k = parseFloat(fattore);
        if (isNaN(k) || k < 1)
            k = 1;
        if (k > 4)
            k = 4;
        comp._nostro("lente", [String(k)]);
    }

    /// ── L'effetto sulle finestre: un corpo solo ─────────────────────────
    ///
    /// `modo` è «nessuno», «vetro» o «blur»; `opacita` va da 0,50 a 1,00 e
    /// conta per tutti e due gli effetti.
    ///
    /// Col vetro il compositore mette la STESSA trasparenza su tutto l'albero
    /// della finestra — la barra che disegna lui e il contenuto del programma
    /// — così che siano un corpo solo invece di due trasparenze attaccate con
    /// una linea in mezzo. È la richiesta di Giacomo del 2 settembre 2026.
    ///
    /// Col blur, in più, quello che sta DIETRO la finestra è sfocato: è un
    /// nodo che il compositore mette sotto di lei, non un ritocco alla
    /// finestra. Ha detto «non ancora» fino al 9 settembre 2026.
    function effetto(modo, opacita) {
        var m = (modo === "vetro" || modo === "blur") ? modo : "nessuno";
        var a = parseFloat(opacita);
        if (isNaN(a) || a < 0.50)
            a = 0.50;
        if (a > 1.00)
            a = 1.00;
        comp._nostro("effetto", [m, a.toFixed(2)]);
    }

    // Qui c'era `sfocatura(accesa, misura, passaggi)`, i tre numeri di
    // Hyprland. Se n'è andata col resto della catena: nessuno la chiamava più,
    // e un buco che non chiama nessuno non è la memoria di una strada — è una
    // strada in meno da leggere. Il suo posto l'ha preso `effetto()`, e la
    // sfocatura vera sarà un passaggio di rendering dentro minerva-wayland,
    // non tre numeri da mandare a qualcun altro.

    /// Il colore del bordo della finestra attiva e di quelle che non lo sono.
    function coloriBordo(attivo, inattivo) {
        // Da noi la cornice è la barra del titolo, e il suo colore si
        // manda col verbo «aspetto» insieme all'altezza e al lato dei
        // pulsanti — una sola andata invece di tre.
        //
        // Si manda solo il colore ATTIVO: la barra non cambia colore
        // quando la finestra perde il fuoco, cambia l'ALFA (0.90 contro
        // 0.70). È la stessa scelta della shell — una finestra spenta non
        // cambia colore, si allontana — e mandare due tinte vorrebbe dire
        // fingere una manopola che non esiste.
        comp.aspettoBarra(undefined, undefined, attivo, undefined);
    }

    /// L'aspetto della barra del titolo nativa: altezza, lato dei pulsanti,
    /// colore del fondo e del testo. `undefined` per non toccarne una.
    ///
    /// Sotto Hyprland non c'è: la barra la disegna il plugin, con le sue
    /// manopole. Qui NON si tace — si dice quale pezzo non ha una strada —
    /// perché un pannello che scrive e non succede niente è il difetto che
    /// questa funzione è nata per chiudere.
    function aspettoBarra(alta, lato, fondo, testo) {
        comp._nostro("aspetto", [
            comp._numeroO(alta),
            (lato === "sinistra" || lato === "destra") ? lato : "-",
            comp._esaO(fondo),
            comp._esaO(testo)
        ]);
    }

    /// La cornice attorno alla finestra attiva.
    ///
    ///   modo     «spento», «fisso» o «gira»
    ///   periodo  millisecondi per un giro intero dello spettro
    ///   colore   la tinta del modo «fisso»
    ///
    /// Sotto Hyprland era `general:col.active_border`, e ci arrivava
    /// `coloriBordo` qui sopra. Sotto minerva-wayland la cornice è l'anello di
    /// sei pixel che serve a prendere la finestra per ridimensionarla: c'era
    /// già, ed era trasparente. Il modo «gira» lo anima il compositore, non
    /// noi — dodici passi al secondo mandati sul canale sarebbero dodici
    /// sveglie al secondo della shell, che è esattamente ciò che si è passato
    /// mesi a togliere.
    function cornice(modo, periodo, colore, spessore) {
        var m = (modo === "fisso" || modo === "gira" || modo === "striscia")
                ? modo : "spento";
        comp._nostro("cornice", [m, comp._numeroO(periodo),
                                 comp._esaO(colore),
                                 comp._numeroO(spessore)]);
    }

    /// ── L'elastico: quanto tremano le finestre ──────────────────────────
    ///
    /// Giacomo, 10 settembre 2026: «voglio le finestre tremolanti».
    ///
    /// Zero spento, uno normale, tre il massimo. Il numero è una forza, e
    /// dentro il compositore vale il contrario di quel che sembra — più forza
    /// vuol dire molla più morbida — ma qui fuori, e sul cursore delle
    /// Impostazioni, è semplicemente «quanto».
    ///
    /// Il compositore applica una deformazione alla superficie durante il
    /// trascinamento e la lascia assestare al rilascio. Il rendering è in
    /// `compositore/src/wobbly.c`; qui passa solo il parametro, non i frame.
    function parametriEffetti(blur, rigidita, smorzamento) {
        if (!comp.nostro) return;
        if (isFinite(blur) && blur >= 0 && blur <= 100)
            comp._nostro("sfocatura", [Number(blur).toFixed(2)]);
        if (isFinite(rigidita) && rigidita >= 0.5 && rigidita <= 2 &&
                isFinite(smorzamento) && smorzamento >= 0.15 && smorzamento <= 0.95)
            comp._nostro("molla", [Number(rigidita).toFixed(2), Number(smorzamento).toFixed(2)]);
    }

    /// Con una finestra che riempie lo schermo la riva chiede Super (`true`)
    /// o risponde sempre (`false`). Vedi `riva_libera` nel compositore.
    function riva(conConsenso) {
        if (!comp.nostro) return;
        comp._nostro("riva", [conConsenso ? "super" : "sempre"]);
    }

    /// Il respiro delle finestre: nascono come una goccia che si posa, e
    /// «riduci» è un risucchio verso la dock. Il compositore lo spegne da sé
    /// col modo risparmio; qui lo spegne l'interruttore delle animazioni.
    function respiro(acceso) {
        comp._nostro("respiro", [acceso ? "si" : "no"]);
    }

    function elastico(forza) {
        var f = Number(forza);
        if (!isFinite(f) || f < 0)
            f = 0;
        if (f > 3)
            f = 3;
        comp._nostro("elastico", [f.toFixed(2)]);
    }

    /// ── I colori che si alternano nel giro ──────────────────────────────
    ///
    /// Giacomo, 9 settembre 2026: «vorrei anche l'effetto rgb come una strip
    /// led e possibilità di scegliere i colori che si alterneranno».
    ///
    /// Un elenco vuoto vuol dire lo SPETTRO intero, che è come la cornice è
    /// nata: chi non sceglie niente vede l'arcobaleno. Da uno in su, il giro
    /// passa per quei colori e per nessun altro.
    ///
    /// I colori storti si buttano QUI e non si mandano: il compositore
    /// rifiuterebbe l'elenco intero per una virgola sbagliata, e chi ha messo
    /// cinque colori si ritroverebbe quelli di prima senza sapere quale dei
    /// cinque non andava.
    function corniceColori(elenco) {
        if (!comp.nostro)
            return;
        var buoni = [];
        for (var i = 0; i < (elenco || []).length; i++) {
            var t = comp._esaO(elenco[i]);
            if (t !== "-" && buoni.indexOf(t) < 0)
                buoni.push(t);
        }
        comp._nostro("cornice", ["colori",
                                 buoni.length > 0 ? buoni.join(",") : "-"]);
    }

    /// Quanto è accesa la cornice sulle finestre che NON hanno il fuoco.
    ///
    /// Zero vuol dire «solo quella attiva», che è come la cornice è nata: il
    /// bordo colorato serve a dire QUALE finestra risponde alla tastiera, e
    /// se sono accese tutte non lo dice più. Con una velatura bassa diventa
    /// invece il contorno di ogni finestra, ed è un altro modo di guardare la
    /// scrivania — il compositore si ferma a 0,60, dove l'attiva smette di
    /// distinguersi.
    function corniceSpente(velatura) {
        if (!comp.nostro)
            return;
        var v = parseFloat(velatura);
        if (isNaN(v) || v < 0)
            v = 0;
        if (v > 0.60)
            v = 0.60;
        comp._nostro("cornice", ["spente", v.toFixed(2)]);
    }

    /// Un numero, o «-» se non lo si sta toccando.
    function _numeroO(v) {
        var x = parseInt(v);
        return (v === undefined || v === null || isNaN(x) || x <= 0)
               ? "-" : String(x);
    }

    /// Un colore in `RRGGBB`, senza cancelletto e senza alfa, o «-».
    ///
    /// Dalla shell i colori arrivano come `#RRGGBB`, `#AARRGGBB` o un nome
    /// Qt. Il compositore vuole sei cifre esadecimali e basta: l'alfa lo
    /// decide lui in base al fuoco, quindi si butta invece di mandarlo e
    /// farlo ignorare in silenzio.
    function _esaO(v) {
        if (v === undefined || v === null)
            return "-";
        var t = String(v).replace("#", "");
        if (t.length === 8)
            t = t.substring(2);
        return /^[0-9a-fA-F]{6}$/.test(t) ? t : "-";
    }

    /// La disposizione della tastiera (`it`, `us`, …).
    function tastiera(disposizione, variante) {
        var d = disposizione === undefined || disposizione === null
                || disposizione === "" ? "-" : String(disposizione);
        comp._nostro("tastiera", [d, variante ? String(variante) : "-"]);
    }

    /// Quanto in fretta un tasto tenuto premuto si ripete, e dopo quanto
    /// comincia.
    function ripetizioneTasti(ritmo, ritardo) {
        comp._nostro("ripetizione", [String(ritmo), String(ritardo)]);
    }

    /// La sensibilità del puntatore. **0 è il neutro**, non il minimo: si va
    /// da −1 a +1, e +1 è il massimo dell'accelerazione.
    function sensibilitaPuntatore(valore) {
        comp._nostro("sensibilita", [String(valore)]);
    }

    /// Le tre manopole del touchpad. Passare `undefined` lascia stare quella.
    function touchpad(scorrimentoNaturale, spentoMentreScrivi, tocco) {
        // Un trattino vuol dire «questa lasciala stare»: è il modo di
        // cambiare UNA manopola senza rimandare anche le altre due, e
        // senza che una manopola mai scelta ne prenda una inventata.
        comp._nostro("touchpad", [comp._siNoForse(scorrimentoNaturale),
                                  comp._siNoForse(spentoMentreScrivi),
                                  comp._siNoForse(tocco)]);
    }

    /// `si`, `no`, oppure `-` per «non detto».
    function _siNoForse(v) {
        if (v === undefined || v === null)
            return "-";
        return v ? "si" : "no";
    }

    // ── Le manopole di ingresso, applicate all'AVVIO ─────────────────────
    //
    // Il difetto che questa funzione chiude, misurato il 30 agosto 2026:
    // **il tocco del trackpad non cliccava**. Non perché il compositore non
    // sapesse farlo — `main.c` chiama `libinput_device_config_tap_set_enabled`
    // — ma perché non gliel'aveva detto nessuno.
    //
    // Sotto Hyprland le manopole arrivano da un FILE, `minerva-input.conf`,
    // letto al suo avvio. minerva-wayland non legge nessun file: le riceve sul
    // canale, e l'unico posto che gliele mandava era la pagina Impostazioni,
    // cioè **solo se aprivi quel pannello e toccavi un cursore**. Appena
    // avviata la sessione, `ingresso.tocco_e_clic` restava a −1 («non detto»),
    // e «non detto» per libinput vuol dire **spento**.
    //
    // Vale identico per la disposizione della tastiera (restava americana), lo
    // scorrimento naturale, lo spegni-mentre-scrivi e la sensibilità.
    //
    // ── Perché aspetta «impostazioniArrivate» ────────────────────────────
    //
    // Perché `Ipc.get()` prima che il demone abbia risposto torna il valore di
    // RIPIEGO, non il tuo. Applicarlo vorrebbe dire scrivere i valori di
    // fabbrica sopra le tue scelte, che è esattamente il difetto che questo
    // progetto ha già pagato una volta: «non si agisce sui valori di ripiego».
    // Quindi si aspettano tutte e due le cose — il canale aperto E le
    // impostazioni vere — in qualunque ordine arrivino.
    //
    // ── Vale per TUTTI E DUE i compositori, di proposito ─────────────────
    //
    // Sotto Hyprland la chiama il pannello Impostazioni, ed è la strada per
    // cui una manopola girata ha effetto SUBITO invece che al prossimo avvio.
    // Farla uscire qui su `!nostro` sarebbe stato un rimedio che rompeva
    // l'altro compositore — chi la chiama automaticamente all'avvio, invece,
    // guarda `nostro`, perché là il file lo legge già Hyprland.
    /// Le app che la barra del titolo se la disegnano da sole.
    ///
    /// Solo per il nostro compositore: sotto Hyprland la stessa lista la legge
    /// il plugin delle barre, che è un altro programma e non passa di qui.
    ///
    /// ── Perché deve viaggiare, invece di stare scritta là ────────────────
    ///
    /// Perché era scritta **in tutti e due i posti**: dieci nomi cablati in
    /// `compositore/src/main.c` e gli stessi dieci in `settings.json` sotto
    /// `windows.csdApps`, che è quella che il pannello Impostazioni modifica.
    /// Aggiungendo un programma dal pannello non succedeva niente, e non c'era
    /// nessun errore da nessuna parte: due copie della stessa lista sono due
    /// liste che un giorno non sono più d'accordo.
    function appConBarraPropria(elenco) {
        if (!comp.nostro)
            return;
        var l = [];
        for (var i = 0; i < (elenco || []).length; i++) {
            var v = String(elenco[i]).trim();
            // Uno spazio dentro un nome spezzerebbe la riga in due argomenti,
            // e il secondo pezzo diventerebbe un nome per conto suo — cioè un
            // programma qualunque che contiene quella sillaba perderebbe la
            // barra. Si saltano dicendolo.
            if (v === "")
                continue;
            if (v.indexOf(" ") >= 0) {
                console.warn("[MINERVA][Compositore] «" + v + "» ha uno spazio "
                             + "dentro: non può stare in «windows.csdApps», e "
                             + "viene saltato.");
                continue;
            }
            l.push(v);
        }
        comp._nostro("csd", l);
    }

    /// Siamo il processo che disegna la scrivania, o una finestra qualunque?
    ///
    /// Il contrassegno lo mette `scripts/minerva-interfaccia`, ed è l'unico che
    /// può saperlo: da dentro QML non c'è modo di distinguere la barra da una
    /// finestra — è lo stesso eseguibile con un file diverso.
    ///
    /// Serve a una cosa sola e importante: le impostazioni di SISTEMA — la
    /// disposizione della tastiera, il tocco del trackpad, l'aspetto delle
    /// barre del titolo — le manda uno solo. Fino al 31 agosto 2026 le mandava
    /// ognuno: aprire il gestore file rimandava al compositore la tastiera e i
    /// colori, e il giorno che è comparso un verbo nuovo ogni app stampava
    /// «verbo sconosciuto» finché il compositore non veniva riavviato.
    /// Predefinito FALSO, e si scrive: `shell.qml` e `greeter.qml` lo mettono
    /// a vero nel loro `Component.onCompleted`.
    ///
    /// Si è provato a dedurlo da `Quickshell.configPath`, e non si può:
    /// `configPath` è un METODO che compone percorsi, non il nome del file in
    /// esecuzione. `String(Quickshell.configPath)` restituisce
    /// «function() { [native code] }» — cioè una guardia che sembra funzionare
    /// e risponde sempre di no, che è il modo peggiore di sbagliare. Misurato,
    /// non supposto.
    ///
    /// Quindi lo dice chi lo sa: la scrivania si dichiara. Chi non dice
    /// niente è una finestra, che è il caso giusto per difetto — una finestra
    /// che tace non riconfigura la sessione di nessuno.
    property bool scrivania: {
        var v = String(Quickshell.env("MINERVA_SCRIVANIA") || "");
        return v !== "" && v !== "0";
    }

    // ── L'altro verso della stessa porta ─────────────────────────────────
    //
    // Le impostazioni di ingresso partono da UN posto solo — la `Connections`
    // qui sotto, che aspetta che le impostazioni arrivino. Ma quella strada ha
    // un ordine implicito dentro: quando le impostazioni arrivano, la
    // scrivania si deve essere già dichiarata. Sono due cose asincrone e
    // indipendenti, e chi arriva prima non lo decide nessuno.
    //
    // Se arrivano al contrario — prima le impostazioni, poi
    // `scrivania = true` — il segnale è già passato e **non torna più**: la
    // tastiera resta americana e il tocco del trackpad non clicca, per tutta
    // la sessione, senza un errore da nessuna parte. È esattamente quello che
    // è successo il 1º settembre 2026, per otto ore.
    //
    // Questa non è la «terza porta» che era stata chiusa apposta: quella era
    // OGNI applicazione che rimandava tutto. Qui la condizione è la stessa di
    // sotto — `scrivania`, cioè la shell e nessun altro — e l'effetto è quello
    // di prima: chi manda resta uno solo. Cambia solo che adesso i due
    // messaggi si possono incrociare senza perdersi.
    onScrivaniaChanged: {
        if (comp.nostro && comp.scrivania && Ipc.impostazioniArrivate) {
            console.debug("[MINERVA][Compositore] la scrivania si è "
                          + "dichiarata dopo le impostazioni: applico "
                          + "l'ingresso adesso.");
            comp.applicaIngresso();
        }
    }

    /// Applica al compositore tutto ciò che riguarda l'ingresso e l'aspetto.
    ///
    /// NON controlla `scrivania`: la pagina Impostazioni la chiama apposta
    /// quando muovi un cursore, e lì il punto è proprio vedere subito
    /// l'effetto. Il controllo sta dove sta la chiamata AUTOMATICA, cioè
    /// all'apertura del canale.
    function applicaIngresso() {
        if (!Ipc.impostazioniArrivate)
            return;
        comp.appConBarraPropria(Ipc.get("windows.csdApps", []));
        // L'aspetto della barra nativa, che fino al 31 agosto 2026 il
        // pannello scriveva e nessuno leggeva.
        comp.aspettoBarra(Ipc.get("windows.titleHeight", 42),
                          Ipc.get("windows.buttonsSide", "destra"),
                          undefined, undefined);
        comp.tastiera(Ipc.get("input.layout", "it"));
        comp.ripetizioneTasti(Ipc.get("input.repeatRate", 25),
                              Ipc.get("input.repeatDelay", 600));
        comp.sensibilitaPuntatore(Ipc.get("input.sensitivity", 0));
        comp.touchpad(Ipc.get("input.naturalScroll", true),
                      Ipc.get("input.disableWhileTyping", true),
                      Ipc.get("input.tapToClick", true));
    }

    property Connections _ingressoAllAvvio: Connections {
        target: Ipc
        function onImpostazioniArrivateChanged() {
            // Due condizioni, e servono tutte e due.
            //
            // `nostro`: sotto Hyprland le stesse manopole arrivano già da
            // `minerva-input.conf`, e rifarle qui sarebbero quattro `hyprctl`
            // a ogni avvio per niente.
            //
            // `scrivania`: questo file sta dentro OGNI nostra applicazione, e
            // le impostazioni arrivano a tutte. Senza questa parola, aprire il
            // gestore file rimandava al compositore la disposizione della
            // tastiera e l'aspetto delle barre — ed era il terzo punto da cui
            // partivano, dopo l'apertura del canale e `WindowRules.write()`.
            // Tre porte per la stessa cosa: chiuderne due su tre non serve a
            // niente, ed è esattamente quello che era successo.
            if (comp.nostro && comp.scrivania) {
                console.debug("[MINERVA][Compositore] applico l'ingresso: "
                              + "tastiera, tocco, sensibilità.");
                comp.applicaIngresso();
                return;
            }
            // ── Perché si dice anche quando NON si fa ────────────────────
            //
            // Il 1º settembre 2026 il tocco del trackpad non cliccava e la
            // tastiera era rimasta americana per otto ore, in una sessione
            // vera. Questa funzione non era stata chiamata — e non c'era una
            // riga da nessuna parte che lo dicesse, perché la strada che non
            // si prende non lascia traccia. Sono servite due ore per capirlo
            // leggendo il codice; con questa riga sarebbero stati due secondi.
            console.debug("[MINERVA][Compositore] ingresso NON applicato: "
                          + "nostro=" + comp.nostro
                          + " scrivania=" + comp.scrivania);
        }
    }

    /// Accende o spegne UN dispositivo per nome. Serve al touchpad, che si
    /// spegne tutto invece che a manopole.
    function dispositivoAcceso(nome, acceso) {
        // La levetta PRIMA, il nome DOPO: il nome è l'unica cosa che può
        // contenere spazi — su questo portatile il touchpad si chiama
        // «ELAN0504:01 04F3:312A Touchpad» — quindi è l'unica che può
        // stare in fondo. Vedi `comando_dispositivo` in main.c: con
        // l'ordine di prima arrivava solo «ELAN0504:01», e la levetta del
        // touchpad non faceva niente.
        comp._nostro("dispositivo", [acceso ? "si" : "no", String(nome)]);
    }

    /// Come è configurato uno schermo: modo (`1920x1080@60`), scala,
    /// rotazione in GRADI, e dove sta.
    ///
    /// ── La rotazione si dice in gradi, e non è un dettaglio ─────────────
    ///
    /// Hyprland la chiama `transform` e la conta da 0 a 7 — dove da 4 in su
    /// sono le versioni specchiate, che non sono rotazioni affatto. Il nostro
    /// compositore la vuole in gradi, come `schermi.conf`. Chi chiede «ruota
    /// di 90» non deve sapere né l'uno né l'altro: qui entra un numero di
    /// gradi, e la traduzione sta in questo file, che è il posto dichiarato
    /// per le traduzioni.
    ///
    /// `x` e `y` si possono omettere: vuol dire «mettilo dove ci sta».
    function schermo(nome, modo, scala, gradi, x, y, prova) {
        var sc = (scala === undefined || scala === null || scala === "")
                 ? 1 : scala;
        var g = comp._gradiInteri(gradi);
        var haPosto = x !== undefined && x !== null
                      && y !== undefined && y !== null;

        var arg = [nome, modo, String(sc), String(g)];
        if (haPosto)
            arg = arg.concat([String(Math.round(x)), String(Math.round(y))]);
        comp._nostro(prova ? "schermo-prova" : "schermo", prova ? [prova].concat(arg) : arg);
    }

    /// Spegne uno schermo.
    function schermoSpento(nome, prova) {
        comp._nostro(prova ? "schermo-prova" : "schermo", prova ? [prova, nome, "spento"] : [nome, "spento"]);
    }

    function confermaSchermo(prova, nome, conferma) {
        comp._nostro(conferma ? "schermo-conferma" : "schermo-annulla", [prova, nome]);
    }

    /// Gradi puliti: 0, 90, 180 o 270. Qualunque altra cosa è «dritto».
    function _gradiInteri(g) {
        var v = Number(g);
        if (!isFinite(v))
            return 0;
        // Niente arrotondamenti: 45 gradi non è «quasi 90», è una cosa che
        // non si può fare, e trasformarlo in 90 vorrebbe dire ruotare lo
        // schermo per un valore che nessuno ha chiesto. Tutto ciò che non è
        // un quarto di giro esatto è «dritto».
        while (v < 0) v += 360;
        v = v % 360;
        return (v === 90 || v === 180 || v === 270) ? v : 0;
    }

    // ── Gli schermi, tradotti una volta sola ─────────────────────────────
    //
    // La pagina Schermi delle Impostazioni parlava il vocabolario di Hyprland
    // a mano: `width`, `refreshRate`, `availableModes`, `transform`,
    // `disabled`. Sotto il nostro compositore non trovava nessuno di quei
    // nomi, e mostrava una pagina vuota — cioè peggio di un errore, perché
    // sembrava che non ci fosse nessuno schermo.
    //
    // Da qui in poi la pagina vede UNA forma sola:
    //
    //     { nome, descrizione, larghezza, altezza, hz, scala, gradi,
    //       x, y, acceso, attivo, modi: ["1920x1080@60", …] }
    //
    // che è il vocabolario di Minerva. La differenza fra i due compositori
    // finisce qui dentro, come tutte le altre.
    function schermiDaTesto(testo) {
        var grezzi = [];
        try {
            grezzi = JSON.parse(String(testo));
        } catch (e) {
            return [];
        }
        if (!Array.isArray(grezzi))
            return [];

        var fuori = [];
        for (var i = 0; i < grezzi.length; i++) {
            var m = grezzi[i];
            if (!m)
                continue;
            fuori.push(comp._schermoNostro(m));
        }
        return fuori;
    }

    function _schermoNostro(m) {
        return {
            "nome": m.nome || "",
            "descrizione": m.descrizione || "",
            "larghezza": m.larghezza || 0,
            "altezza": m.altezza || 0,
            "modoLarghezza": m.modoLarghezza || 0,
            "modoAltezza": m.modoAltezza || 0,
            "hz": m.hz || 0,
            "scala": m.scala || 1,
            "gradi": comp._gradiInteri(m.rotazione || 0),
            "x": m.x || 0,
            "y": m.y || 0,
            "acceso": m.acceso !== false,
            "attivo": m.attivo === true,
            "modi": comp._modiPuliti(m.modi || [])
        };
    }

    // ── Chi è il touchpad, secondo i due compositori ─────────────────────
    //
    // `shell.qml` deve saperne il NOME per poterlo spegnere: è il tasto Fn
    // del portatile, e senza il nome quel tasto non fa niente.
    //
    // Le due risposte lo dicono in due modi, e uno dei due è migliore.
    // Hyprland manda un elenco `mice` e il touchpad si riconosce **dal
    // nome** — un'ipotesi, e su questo portatile è già costata (vedi la
    // memoria `minerva-touchpad-acer`). Il nostro compositore lo chiede a
    // libinput: «questo dispositivo sa contare le dita?». Non è
    // un'euristica, è la domanda giusta.
    //
    // Torna "" se non c'è nessun touchpad, che su un fisso è la verità.
    function touchpadDaTesto(testo) {
        var d = null;
        try {
            d = JSON.parse(String(testo));
        } catch (e) {
            return "";
        }
        if (!d)
            return "";

        // La nostra: `puntatori`, e la risposta viene da libinput.
        if (Array.isArray(d.puntatori)) {
            for (var i = 0; i < d.puntatori.length; i++) {
                if (d.puntatori[i] && d.puntatori[i].touchpad === true)
                    return String(d.puntatori[i].nome || "");
            }
            return "";
        }

        return "";
    }

    /// I modi in una forma sola, `1920x1080@60.000`, senza doppioni esatti.
    ///
    /// La frequenza resta coi suoi tre decimali: 60,000 e 59,990 sono due
    /// modi diversi per lo schermo, e il compositore vuole quello esatto per
    /// applicarlo. A non farli sembrare una scelta a caso ci pensa la pagina
    /// Schermi, che li raggruppa per risoluzione.
    function _modiPuliti(grezzi) {
        var visti = {};
        var fuori = [];
        for (var i = 0; i < grezzi.length; i++) {
            var t = String(grezzi[i]);
            var chiocciola = t.indexOf("@");
            if (chiocciola < 0)
                continue;
            var ris = t.substring(0, chiocciola);
            var hz = Number(t.substring(chiocciola + 1));
            if (!isFinite(hz) || hz <= 0)
                continue;
            var chiave = ris + "@" + hz.toFixed(3);
            if (visti[chiave])
                continue;
            visti[chiave] = true;
            fuori.push(chiave);
        }
        return fuori;
    }


    /// La tinta di tutto lo schermo, in tre moltiplicatori: 1, 1, 1 è il
    /// neutro. È l'altra metà della luce notturna.
    ///
    /// ── Due strade, e non è un ripiego ──────────────────────────────────
    ///
    /// Hyprland ha uno shader su tutto lo schermo; il nostro compositore no,
    /// e non è una mancanza da colmare: per **scaldare i colori** una tabella
    /// è la cosa giusta e costa meno — è la strada di `gammastep`, e quella
    /// del pannello colori di un monitor da vent'anni.
    ///
    /// I tre numeri sono gli stessi: li calcola `core/LuceNotturna.qml` dai
    /// gradi Kelvin, e sotto Hyprland finiscono dentro lo shader. Rifare il
    /// conto qui vorrebbe dire due conti per la stessa cosa, cioè due tinte
    /// diverse il giorno che uno dei due cambia.
    function coloreSchermo(r, g, b) {
        if (!comp.nostro)
            return;
        comp._nostro("colore", [r.toFixed(4), g.toFixed(4), b.toFixed(4)]);
    }

    /// Dice al compositore quali soglie di inattività ci interessano.
    ///
    /// `soglie` è un elenco di secondi, e il compositore lo vuole **crescente
    /// e senza doppioni**: fra una soglia e la successiva lui fa una
    /// sottrazione, e due numeri in disordine la farebbero negativa. Qui si
    /// ordina e si scarta il resto, così chi chiama può passare i tre numeri
    /// del pannello Energia com'escono — anche uguali fra loro, che capita
    /// (blocca e sospendi allo stesso minuto).
    ///
    /// Elenco vuoto = sorveglianza spenta.
    ///
    /// ── Perché non decide il compositore ─────────────────────────────────
    ///
    /// Perché «dopo dieci minuti sospendi» è una politica, e una sospensione
    /// decisa da chi disegna i pixel è una macchina che sparisce senza che
    /// nessuno l'abbia chiesto. Stessa regola del coperchio del portatile:
    /// lui riferisce il fatto, chi ha la politica decide. Fino al 1º settembre
    /// 2026 il conto lo teneva `hypridle`, che è la stessa cosa fatta da un
    /// programma di un altro ambiente con un file di configurazione suo.
    function sorvegliaInattivita(soglie) {
        if (!comp.nostro)
            return;
        var puliti = [];
        for (var i = 0; i < (soglie ? soglie.length : 0); i++) {
            var v = Math.round(Number(soglie[i]));
            if (isFinite(v) && v > 0 && puliti.indexOf(v) < 0)
                puliti.push(v);
        }
        puliti.sort(function(a, b) { return a - b; });
        comp._nostro("inattivita", puliti);
    }

    /// Rilegge la configurazione da capo.
    ///
    /// ── Due compositori, due significati della stessa parola ────────────
    ///
    /// Hyprland tiene la sua configurazione in un file e `reload` vuol dire
    /// «rileggilo». minerva-wayland **non legge nessun file**: tutto quello
    /// che sa gliel'ha detto la shell sul canale. Quindi «ricarica» qui non è
    /// una rilettura, è un **rimandare**: le scorciatoie e le manopole di
    /// ingresso, che sono le due cose che quel file conteneva.
    ///
    /// Prima usciva verso `hyprctl` in tutti e due i casi. La sua unica
    /// chiamante è l'azione del coperchio del portatile in
    /// `settings/sections/Power.qml`, che quindi sotto di noi non faceva
    /// niente — e nessuna riga rossa lo diceva, perché la guardia guardava
    /// `_dispatch()` e `imposta()` e questa usciva da una terza porta.
    function ricarica() {
        comp.scorciatoieDaMandare();
        comp.applicaIngresso();
    }

    /// Il tema e la misura del puntatore. Sono UNA cosa sola: tutti e due i
    /// compositori vogliono l'una e l'altra insieme, perché il gestore dei
    /// cursori si costruisce con entrambe e non c'è modo di cambiarne una
    /// lasciando l'altra.
    function cursore(tema, misura) {
        comp._nostro("cursore", [String(tema), String(misura)]);
    }

    /// Chiude la sessione grafica.
    ///
    /// Passava solo da `hyprctl dispatch exit`: sotto il nostro compositore
    /// non c'è nessun `hyprctl`, quindi «Esci» non faceva niente — e non
    /// c'era nemmeno un errore da leggere, perché il comando non esisteva
    /// proprio. Una sessione da cui non si esce è una sessione che si chiude
    /// col tasto di accensione.
    function esciDallaSessione() {
        comp._nostro("esci", []);
    }

    // ── Una coda, e non un processo riusato ──────────────────────────────
    //
    // Qui c'era `_riga.command = …; _riga.running = true`, e sembrava
    // innocuo. Non lo è: **due chiamate ravvicinate perdono la prima.** Il
    // secondo `command` sovrascrive il primo prima che parta, e non lo dice
    // nessuno — il valore semplicemente non viene applicato.
    //
    // Succedeva già: `settings/sections/Display.qml` imposta il modo dello
    // schermo e SUBITO DOPO la rotazione. Sarebbe rimasta la rotazione, e il
    // modo sarebbe stato ignorato una volta su due, a seconda di come
    // cadevano i tempi. Trovato l'11 agosto 2026 rileggendo questo file per
    // portarci dentro le ultime chiamate.
    //
    // La coda risolve anche il caso vero delle Impostazioni della tastiera:
    // sette valori applicati uno dopo l'altro, in ordine, senza un
    // `hyprctl reload` che rileggerebbe tutto il resto.
    // ── Domande ──────────────────────────────────────────────────────────
    //
    // Le cose che si chiedono al compositore e che nessun altro sa.
    // La risposta arriva sul segnale `risposta(cosa, testo)`: chi chiede
    // guarda `cosa` e ignora il resto.
    //
    // Una corsia per tipo di domanda, e non una coda: le Impostazioni possono
    // interrogare i monitor mentre la barra controlla le estensioni, e con un
    // processo solo la seconda risposta cancellerebbe la prima. Quattro
    // oggetti fermi costano meno di una coda da scrivere e da sbagliare.

    /// `cosa` è uno di: "schermi", "dispositivi", "puntatore", "estensioni",
    /// "animazioni".
    signal risposta(string cosa, string testo)

    function chiedi(cosa) {
        // ── Gli schermi, sotto il nostro compositore ─────────────────────
        //
        // `hyprctl -j monitors` lì dentro non risponde a nessuno: il comando
        // non esiste. La pagina Schermi restava vuota, ed è il modo peggiore
        // di sbagliare — «nessuno schermo rilevato» su un computer che uno
        // schermo ce l'ha davanti.
        if (cosa === "schermi") {
            comp._nostro("schermi", []);
            return;
        }
        // Stessa storia dei monitor: `hyprctl -j devices` lì dentro non
        // risponde a nessuno, e il pannello «Tastiera e mouse» resta senza
        // l'elenco dei dispositivi — cioè senza la levetta del touchpad, che
        // ha bisogno del suo nome.
        if (cosa === "dispositivi") {
            comp._nostro("dispositivi", []);
            return;
        }
        // ── Dov'è il puntatore ───────────────────────────────────────────
        //
        // Il menù del tasto destro si apre dove sta il dito, e per saperlo lo
        // chiede. `hyprctl cursorpos` sotto il nostro compositore non è
        // nessuno: la risposta non arrivava, e il menù cadeva sul suo ripiego
        // — **in alto a sinistra**, lontano dal punto in cui l'avevi chiesto.
        // Il verbo risponde nello stesso formato, apposta: chi legge è lo
        // stesso pezzo di interfaccia per tutti e due i compositori.
        if (cosa === "puntatore") {
            comp._nostro("puntatore", []);
            return;
        }
        // ── E le due che da noi non vogliono dire niente ─────────────────
        //
        // Non si lanciano e non si lasciano cadere nel silenzio: si risponde
        // **vuoto**, subito. Una domanda senza risposta lascia chi ha chiesto
        // ad aspettare per sempre — la barra resterebbe a «sto controllando le
        // estensioni» finché non la si riavvia. Un elenco vuoto è la verità:
        // qui dentro i plugin di Hyprland non esistono, e il motore delle
        // animazioni è la Tappa 5 del compositore.
        if (cosa === "estensioni" || cosa === "animazioni") {
            comp._senzaStrada("chiedi:" + cosa);
            comp.risposta(cosa, "");
            return;
        }

        // ── E qualunque altra cosa NON si lascia cadere ──────────────────
        //
        // Qui sotto c'erano cinque `Process` che lanciavano `hyprctl`. Se ne
        // sono andati con Hyprland, e con loro il rischio peggiore che
        // avevano: `hyprctl` non parla col compositore che ti sta disegnando
        // lo schermo, parla con quello che dice `HYPRLAND_INSTANCE_SIGNATURE`
        // — cioè, dentro una prova annidata, con la sessione VERA.
        //
        // Una domanda che nessuno raccoglie lascia chi ha chiesto ad aspettare
        // per sempre: si risponde vuoto, e si dice che non si sapeva.
        console.warn("[MINERVA][Compositore] non so rispondere a «" + cosa
                     + "»: rispondo vuoto invece di lasciare chi ha chiesto "
                     + "ad aspettare per sempre.");
        comp.risposta(cosa, "");
    }

    // ── Quello che succede, detto in una lingua sola ─────────────────────
    //
    // Il compositore annuncia i cambiamenti su un socket. Le sue parole
    // (`activewindowv2`, `focusedmon`, `createworkspace`) sono sue: chi
    // ascolta deve poter ragionare per fatti, non per nomi di Hyprland.
    //
    // Restano grezzi `evento` e `dati` accanto ai fatti, perché
    // `core/Windows.qml` distingue casi che qui non varrebbe la pena
    // nominare — ma è l'ULTIMO posto che può permetterselo, e sta di là dalla
    // porta insieme a questo file.

    /// Qualcosa è cambiato nelle scrivanie: quale è in uso, o quali esistono.
    signal scrivanieCambiate()
    /// Qualcosa è cambiato nelle finestre: nate, morte, spostate, a fuoco.
    signal finestreCambiate()
    /// L'evento com'è arrivato. Per chi deve guardare i dettagli.
    signal evento(string nome, string dati)

    /// Una scorciatoia di quelle che tocca alla shell: `cheatsheet`,
    /// `launcher`, `control`… Il nome è quello scritto in
    /// `config/scorciatoie.minerva` dopo `minerva:`, ed è lo stesso che
    /// `core/Scorciatoia.qml` mette in `name`. Sotto Hyprland la stessa cosa
    /// arriva per `GlobalShortcut`; qui per il canale.
    signal scorciatoiaPremuta(string nome)

    /// Il coperchio del portatile si è chiuso (o riaperto).
    ///
    /// Solo il FATTO. Cosa farne — sospendere, bloccare, niente — lo decide
    /// chi ascolta, leggendo `power.lidAction`. Sotto Hyprland lo stesso fatto
    /// arriva per un'altra strada (`bindl = , switch:on:Lid Switch`), e per
    /// questo il segnale sta qui: chi lo ascolta non deve sapere sotto quale
    /// compositore sta girando.
    signal coperchio(bool chiuso)

    /// Sono passati `secondi` senza che nessuno tocchi niente.
    ///
    /// Arriva una volta per ogni soglia chiesta con `sorvegliaInattivita()`,
    /// in ordine crescente. Il numero è la soglia, non il tempo vero passato:
    /// serve a chi ascolta per sapere QUALE delle sue tre soglie è scattata
    /// senza doverle riconoscere a occhio.
    signal inattivo(int secondi)

    /// Qualcuno ha toccato qualcosa, dopo che almeno una soglia era scattata.
    ///
    /// Una volta sola per volta: non è un segnale che arriva a ogni tasto
    /// premuto. Se lo fosse, il processo che disegna si sveglierebbe a ogni
    /// tasto premuto — il conto che questo progetto ha già pagato.
    signal attivo()

    /// Il puntatore è arrivato al bordo alto di uno schermo con sopra una
    /// finestra a schermo intero. Lo dice il compositore, una volta per
    /// arrivo: così la barra d'uscita (`spine/FullscreenBar.qml`) non deve
    /// tenere una sua superficie montata sopra il film per accorgersene —
    /// e senza superfici sopra, la finestra va allo schermo direttamente.
    signal bordoAlto(string schermo)

    /// Il puntatore ha sostato in un angolo dello schermo («alto-sx»,
    /// «alto-dx», «basso-sx», «basso-dx»), o se n'è andato («via»). Lo dice
    /// il compositore dopo una sosta di 160 ms, e mai sopra una finestra a
    /// schermo intero o mentre si trascina: cosa si apre lo decide la shell.
    signal angolo(string quale, string schermo)

    /// Il puntatore ha SPINTO contro un bordo dello schermo («destra»): non
    /// una sosta, una spinta oltre il bordo (vedi `bordo_spinto` nel
    /// compositore). Da lì esce il Cassetto degli appunti.
    signal bordo(string quale, string schermo)

    property int _scosse: 0

    // ── Gli eventi grezzi di Hyprland se ne sono andati ─────────────────
    //
    // Qui c'era un `Connections { target: Hyprland }` che traduceva undici
    // nomi suoi — `workspacev2`, `focusedmonv2`, `activewindowv2`,
    // `changefloatingmode` — nei due fatti che interessano a Minerva: «le
    // scrivanie sono cambiate» e «le finestre sono cambiate».
    //
    // minerva-wayland annuncia già quei due fatti per nome sul canale, e la
    // traduzione la fa `_leggiRiga()` qui sopra. Il `v2` in coda a metà di
    // quei nomi racconta da solo perché valeva la pena tenerli lontani dal
    // resto della shell: erano un vocabolario che cambiava sotto i piedi.

}
