pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Compositore — L'unico file di Minerva che parla con il compositore.
//
// ── Perché esiste ────────────────────────────────────────────────────────
//
// Ad agosto 2026 i comandi al compositore erano sparsi in venticinque file,
// e la stessa intenzione era scritta più volte: c'erano **tre «ingrandisci»
// diversi**, uno si fermava sotto la barra della scrivania e un altro la
// copriva, perché i tre punti non si conoscevano. Da allora c'è una porta
// sola, ed è questa.
//
// ── La divisione del lavoro ──────────────────────────────────────────────
//
//   Compositore   TRADUCE. Sa come si dice a `minerva-wayland` «porta questa
//                 finestra davanti», sul canale testuale di `MINERVA_CANALE`.
//                 Non sa cosa sia una finestra ridotta a icona, non tiene
//                 elenchi, non ha memoria.
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

    // ── Fuori da Minerva ─────────────────────────────────────────────────
    //
    // Le nostre app girano anche su COSMIC, GNOME, KDE, sway: là `nostro` è
    // falso e non c'è nessuno a cui chiedere. Lì una finestra comanda **sé
    // stessa** con quello che il protocollo dà a tutti: `xdg_toplevel` ha
    // `set_minimized`, `set_maximized` e `set_fullscreen`, come il
    // trascinamento della barra usa `startSystemMove()`. Si perde solo ciò
    // che è nostro: «riduci» nel pannello delle ridotte, «ingrandisci» che si
    // ferma allo spazio utile. Richiesta di Giacomo del 30 agosto 2026: «le
    // nostre app funzionanti su altri desktop environment di qualsiasi tipo».
    /// Vero quando c'è un compositore che ascolta i comandi di Minerva.
    ///
    /// Falso su qualunque altra scrivania — ed è lì che le nostre finestre
    /// devono comandare **sé stesse** invece di chiedere a qualcuno.
    ///
    /// Oggi vale quanto `nostro`; restano due nomi perché dicono due cose
    /// diverse a chi legge: `nostro` è «il canale c'è», `comandabile` è
    /// «posso chiedere invece di arrangiarmi».
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
            if (!canale.connected) {
                comp._riprovaFraPoco();
                return;
            }
            comp._apertoDa = Date.now();
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
                             + "inattivo attivo schermi bordoalto risparmio angolo bordo "
                             + "menufinestra\n");
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

    // ── Riprovare, ma non di corsa ───────────────────────────────────────
    //
    // Il `Socket` di Quickshell si ricollega DA SOLO appena il canale cade,
    // subito e senza pausa. Di solito va benissimo; ma il compositore accetta
    // al più sedici collegamenti (`CLIENTI_MAX` in `compositore/src/canale.c`)
    // e al diciassettesimo risponde «no troppi collegamenti» e chiude. Con sei
    // app tenute pronte e qualche finestra aperta, una shell che riparte
    // entrava in un giro stretto — collega, rifiutato, ricollega — e a ogni
    // giro rimandava `ascolta` e chiedeva di nuovo le scorciatoie al demone:
    // tre processi al cento per cento, e una shell senza canale che non
    // sentiva più `inattivo`, cioè non bloccava più lo schermo da sola.
    // Trovato in revisione il 30 settembre 2026.
    //
    // Adesso chi cade si stacca (`connected = false` ferma il ricollegamento
    // automatico) e riprova dopo un'attesa che raddoppia fino a cinque
    // secondi. Un canale rimasto aperto a lungo che cade riparte dall'attesa
    // breve: è il compositore che si riavvia, non uno che ci rifiuta.
    //
    // Il Timer è a scatto singolo e parte solo quando il canale cade: la
    // porta non si sveglia da sola (la regola è in `porta_compositore_test`,
    // cambiata il 1º ottobre 2026 proprio per lasciar passare questo).
    property double _apertoDa: 0
    property int _attesa: 250

    function _riprovaFraPoco() {
        if (!comp.nostro)
            return;
        var visse = comp._apertoDa > 0 ? Date.now() - comp._apertoDa : 0;
        comp._apertoDa = 0;
        comp._attesa = visse > 10000 ? 250 : Math.min(5000, comp._attesa * 2);
        canale.connected = false;
        comp._riprova.interval = comp._attesa;
        comp._riprova.restart();
    }

    property Timer _riprova: Timer {
        onTriggered: if (comp.nostro) canale.connected = true
    }

    /// La riga da mandare, come stringa. A parte dal mandarla, perché si può
    /// leggere — e provare — senza un compositore acceso.
    ///
    /// ── Una riga è un comando, e ne resta uno ────────────────────────────
    ///
    /// Il canale separa i comandi con l'a capo. Un argomento che ne contiene
    /// uno — il nome di un touchpad scelto da chi ha fatto il dispositivo,
    /// una voce delle impostazioni — avrebbe aggiunto un comando suo, anche
    /// «esci». I caratteri di controllo diventano spazi, e lo si dice
    /// (revisione di sicurezza, 5 ottobre 2026).
    function _rigaVerbo(verbo, argomenti) {
        var riga = String(verbo);
        if (argomenti !== undefined && argomenti !== null) {
            for (var i = 0; i < argomenti.length; i++)
                riga += " " + argomenti[i];
        }
        if (/[\u0000-\u001f\u007f]/.test(riga)) {
            console.warn("[MINERVA][COMPOSITORE] tolti caratteri di controllo da «"
                         + String(verbo) + "»");
            riga = riga.replace(/[\u0000-\u001f\u007f]/g, " ");
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
        //
        // Ma dev'essere una rete che non si tocca quando va tutto bene. Era a
        // 64, tagliava a 32, e all'apertura del canale si mandano una
        // novantina di scorciatoie di fila: il taglio scattava SEMPRE, e le
        // risposte `ok N` ancora in viaggio finivano sulle domande venute
        // dopo — `dispositivi`, `puntatore`, `stato`, `risparmio` perse
        // (30 settembre 2026). A canale aperto il compositore risponde a ogni
        // riga; la rete resta, ma ben sopra quello che si manda davvero.
        if (comp._inCorso.length > 1024)
            comp._inCorso = comp._inCorso.slice(comp._inCorso.length - 512);
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
        // Le risposte che servono a qualcuno escono dal segnale `risposta`,
        // senza il «ok » davanti: chi ascolta riceve solo il dato.
        if (quale === "schermi" && String(riga).indexOf("ok [") === 0)
            comp.risposta("schermi", riga.substring(3));
        if (quale === "dispositivi" && String(riga).indexOf("ok {") === 0)
            comp.risposta("dispositivi", riga.substring(3));
        // «ok 1211, 94» → «1211, 94»: il menù del tasto destro legge le
        // due coordinate e basta.
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
        // spegnere lo schermo, sospendere — lo decide chi ascolta, ed è
        // `shell.qml` leggendo `power.dimAfter`, `power.lockAfter`,
        // `power.screenOffAfter`, `power.suspendAfter`. Stessa
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
        // Tasto destro sulla barra del titolo di una finestra: il menu della
        // finestra lo apre la shell, nel punto del clic.
        if (t.indexOf("evento menufinestra ") === 0) {
            try {
                var mf = JSON.parse(t.substring(20));
                comp.menuFinestra(Number(mf.x) || 0, Number(mf.y) || 0,
                                  String(mf.schermo || ""));
            } catch (e8) {}
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
    // minerva-wayland non legge nessun file di scorciatoie — di proposito: due
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

    /// Come si nomina una finestra al compositore: `address:0x…`, e chi
    /// chiama non deve saperlo.
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

    /// Sposta l'angolo in alto a sinistra, in pixel assoluti.
    function sposta(indirizzo, x, y) {
        comp._nostro("sposta", [indirizzo ? comp._selettore(indirizzo) : "attiva",
                                Math.round(x), Math.round(y)]);
    }

    /// Cambia la misura, in pixel: la stessa che riporta `finestre`, barra
    /// del titolo nativa compresa (`finestra_box` nel compositore).
    function ridimensiona(indirizzo, larghezza, altezza) {
        comp._nostro("ridimensiona",
                     [indirizzo ? comp._selettore(indirizzo) : "attiva",
                      Math.round(larghezza), Math.round(altezza)]);
    }

    // ── Schermo intero e ingrandita ──────────────────────────────────────
    //
    // Sono due stati del compositore, e confonderli è costato giornate:
    //
    //   schermointero   copre tutto, barra della scrivania compresa.
    //   ingrandisci     occupa lo spazio utile: la barra e la dock restano.
    //
    // Sotto Hyprland ce n'era un terzo, «dillo solo al programma»: vedi più
    // giù, dove c'era `dilloAlProgramma`.

    /// Schermo intero vero. `acceso` falso lo toglie.
    function schermoIntero(indirizzo, acceso) {
        var chi = indirizzo ? comp._selettore(indirizzo) : "attiva";
        if (acceso === false)
            comp._nostro("schermointero", [chi, 0]);
        else
            comp._nostro("schermointero", [chi, 1]);
    }

    /// Ingrandisce, o rimette com'era, una finestra: lo stato è del
    /// compositore (`finestra_ingrandisci`). Senza `si` commuta.
    function ingrandisci(indirizzo, si) {
        var argomenti = [indirizzo ? comp._selettore(indirizzo) : "attiva"];
        if (si !== undefined)
            argomenti.push(si ? "si" : "no");
        comp._nostro("ingrandisci", argomenti);
    }

    /// Commuta lo schermo intero della finestra indicata (o dell'attiva).
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

    // ── Su quale scrivania siamo ─────────────────────────────────────────
    //
    // Due strade, come per la finestra attiva (`Windows.activeAddress`):
    //
    //  · l'EVENTO `evento scrivania`, che porta il numero e arriva subito;
    //  · l'ELENCO, la risposta a `scrivanie`, che ci mette un attimo ma c'è
    //    sempre e rimette a posto le cose se un evento si perde.
    //
    // Chiedere soltanto l'elenco non basta: il 25 agosto 2026, fotografando
    // lo schermo subito dopo il cambio di scrivania, le barre del titolo della
    // scrivania di prima restavano disegnate fra i 150 e i 550 millisecondi,
    // il tempo della risposta. Le parole di Giacomo: «rimangono dei residui».

    /// La scrivania detta dall'ultimo evento del compositore, o 0.
    property int _scrivaniaDaEvento: 0

    /// L'elenco delle scrivanie come lo dice minerva-wayland.
    property var _scrivanieNostre: []

    /// La scrivania in uso, o 1 se il compositore non l'ha ancora detto.
    /// Vince l'evento finché l'elenco non lo raggiunge.
    readonly property int scrivaniaAttiva: {
        if (comp._scrivaniaDaEvento > 0)
            return comp._scrivaniaDaEvento;
        for (var i = 0; i < comp._scrivanieNostre.length; i++)
            if (comp._scrivanieNostre[i].attiva)
                return comp._scrivanieNostre[i].id;
        return 1;
    }

    /// Il suo nome. In minerva-wayland una scrivania È il suo numero, e
    /// non c'è una scrivania di servizio per le ridotte: «ridotta» è uno
    /// stato della finestra, non un posto dove mandarla.
    readonly property string nomeScrivaniaAttiva: String(comp.scrivaniaAttiva)

    /// Tutte le scrivanie che esistono adesso, come `{ id, nome }`. Ridotte a
    /// questi due campi di proposito: chi le disegna non deve poter dipendere
    /// da com'è fatta la risposta del compositore.
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

    /// Riduce a icona, o riporta indietro.
    ///
    /// Ridotta o no, la finestra resta nell'elenco: è quello che permette alla
    /// dock di mostrarla spenta e di riportarla su con un clic. Una finestra
    /// che sparisce dall'elenco è una finestra persa.
    function riduci(indirizzo, si) {
        var giu = si !== false;
        // `_chi` e non `_selettore`: senza indirizzo vuol dire «la finestra
        // attiva» (il menu della finestra, `WindowChip`), e `_selettore("")`
        // mandava `address:`, che il compositore rifiutava sempre.
        comp._nostro("riduci", [comp._chi(indirizzo), giu ? "si" : "no"]);
    }

    // ── Configurazione a caldo ───────────────────────────────────────────
    //
    // Le Impostazioni cambiano valori che il compositore tiene suoi: la
    // disposizione della tastiera, la sensibilità del touchpad, i monitor, lo
    // zoom del cursore. Si mandano sul canale e valgono subito; il
    // compositore non legge nessun file, e all'apertura del canale la shell
    // gli rimanda tutto (`applicaIngresso`).

    // ── Tradurre quello che il compositore RISPONDE ──────────────────────
    //
    // Le intenzioni qui sotto traducono quello che Minerva CHIEDE. Questa
    // traduce il verso opposto: la forma in cui il compositore descrive una
    // finestra, e degli schermi. Stavano in `core/Windows.qml`: qui,
    // perché «Compositore traduce, Windows decide».

    /// Uno schermo, come lo conosce Minerva: `{ id, nome, attivo, x, y, w, h,
    /// sx, sy, sw, sh }`, dove `x,y,w,h` è lo spazio UTILE e `sx,sy,sw,sh` il
    /// contorno vero — barre comprese.
    function schermoDaCompositore(m, indice) {
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

    /// Una finestra, da come la descrive minerva-wayland (`finestre`) a come
    /// la conosce Minerva.
    ///
    /// Ogni campo è una TRADUZIONE, non una decisione: cosa voglia dire
    /// «ingrandita», quale finestra sia nascosta e cosa farne lo decide
    /// `core/Windows.qml`. I nomi del compositore sono già in italiano, ma
    /// restano una traduzione: `posto` non è `stack` per caso, ed è qui che
    /// si dice che sono la stessa cosa.
    function finestraDaCompositore(c) {
        c = c || {};
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
            // Non è un ripiego — è la scelta di Minerva, presa a luglio.
            "floating": true,
            // `posto` è già l'ordine di sovrapposizione: 0 la finestra
            // attiva.
            "stack": c.posto === undefined ? 9999 : c.posto,
            "fullscreen": c.schermoIntero === true,
            // I due bit del compositore in una scala sola: 0 normale,
            // 1 ingrandita, 2 schermo intero.
            "modoSchermo": c.schermoIntero === true ? 2
                         : (c.ingrandita === true ? 1 : 0),
            "workspace": c.scrivania || 1,
            "x": c.x || 0, "y": c.y || 0,
            "w": c.larghezza || 0, "h": c.altezza || 0
        };
    }

    // ── Le intenzioni ────────────────────────────────────────────────────
    //
    // Qui, e in nessun altro posto, sta la tabella fra quello che Minerva
    // vuole e il verbo del compositore: chi le chiama non lo sa.
    //
    // I nomi sono quello che si vuole ottenere, non come si chiama la
    // manopola.
    //
    // Le animazioni del compositore non hanno un verbo loro: l'interruttore
    // generale (`desktop.animations`) porta a zero l'elastico delle finestre
    // (`shell.qml`, `WindowRules.elastico`), e i movimenti liquidi della
    // Tappa 3 si regoleranno da lì.

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
    /// `modo` è «nessuno», «vetro» o «acquerello»; `opacita` va da 0,50 a
    /// 1,00 e conta per tutti gli effetti.
    ///
    /// Col vetro il compositore mette la STESSA trasparenza su tutto l'albero
    /// della finestra — la barra che disegna lui e il contenuto del programma
    /// — così che siano un corpo solo invece di due trasparenze attaccate con
    /// una linea in mezzo. È la richiesta di Giacomo del 2 settembre 2026.
    ///
    /// Col blur, in più, quello che sta DIETRO la finestra è sfocato: è un
    /// nodo che il compositore mette sotto di lei, non un ritocco alla
    /// finestra. Ha detto «non ancora» fino al 9 settembre 2026.
    ///
    /// L'acquerello (27 settembre 2026) è un nodo come quello del blur, ma
    /// invece di sfocare prende il COLORE di quello che sta dietro, cella per
    /// cella, e lo stende morbido: niente forme dietro il testo.
    function effetto(modo, opacita) {
        // «blur» è la parola di prima (il blur è stato tolto il 28 settembre
        // 2026): chi la trova ancora nelle impostazioni ha l'acquerello.
        var m = modo === "blur" ? "acquerello"
                : (modo === "vetro" || modo === "acquerello") ? modo : "nessuno";
        var a = parseFloat(opacita);
        if (isNaN(a) || a < 0.50)
            a = 0.50;
        if (a > 1.00)
            a = 1.00;
        comp._nostro("effetto", [m, a.toFixed(2)]);
    }

    /// Il colore del bordo della finestra attiva.
    function coloriBordo(attivo) {
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
    /// È nata per chiudere un difetto: un pannello che scriveva queste
    /// manopole senza che succedesse niente.
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
    /// La cornice è l'anello di sei pixel che serve a prendere la finestra per ridimensionarla: c'era
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
    function parametriEffetti(rigidita, smorzamento) {
        if (!comp.nostro) return;
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

    /// Mercurio: le finestre vicine si fondono con un raccordo morbido e si
    /// staccano allontanandole. Lo disegna il compositore, sotto le finestre.
    function mercurio(acceso) {
        comp._nostro("mercurio", [acceso ? "si" : "no"]);
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
    // Sotto Hyprland le manopole arrivavano da un FILE, `minerva-input.conf`,
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

    /// Le app che la barra del titolo se la disegnano da sole.
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
        comp.aspettoBarra(Ipc.get("windows.titleHeight", 34),
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
            // `nostro`: senza il canale non c'è nessuno a cui mandarle.
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
    /// Il compositore la vuole in gradi, come `schermi.conf`: niente codici
    /// da 0 a 7 dove da 4 in su ci sono le versioni specchiate, che non sono
    /// rotazioni affatto.
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
    // La pagina Schermi delle Impostazioni vede UNA forma sola:
    //
    //     { nome, descrizione, larghezza, altezza, hz, scala, gradi,
    //       x, y, acceso, attivo, modi: ["1920x1080@60", …] }
    //
    // che è il vocabolario di Minerva.
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

    // ── Chi è il touchpad ────────────────────────────────────────────────
    //
    // `shell.qml` deve saperne il NOME per poterlo spegnere: è il tasto Fn
    // del portatile, e senza il nome quel tasto non fa niente.
    //
    // Il compositore lo chiede a libinput: «questo dispositivo sa contare le
    // dita?». Non si indovina dal nome, che su questo portatile è già
    // costato (vedi la memoria `minerva-touchpad-acer`).
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
    /// Il compositore non ha uno shader su tutto lo schermo, e non è una
    /// mancanza: per **scaldare i colori** una tabella è la cosa giusta e
    /// costa meno — è la strada di `gammastep`, e quella del pannello colori
    /// di un monitor da vent'anni. I tre numeri li calcola
    /// `core/LuceNotturna.qml` dai gradi Kelvin.
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

    /// Il tema e la misura del puntatore. Sono UNA cosa sola: tutti e due i
    /// compositori vogliono l'una e l'altra insieme, perché il gestore dei
    /// cursori si costruisce con entrambe e non c'è modo di cambiarne una
    /// lasciando l'altra.
    ///
    /// ── Prima la misura, poi il tema ─────────────────────────────────────
    ///
    /// Il compositore leggeva `cursore <tema> <misura>` a PAROLE: «Bibata
    /// Modern Ice» arrivava come tema «Bibata» e misura «Modern» — cioè 24,
    /// qualunque misura si fosse scelta, e un tema che non esiste. Dal 1º
    /// ottobre 2026 legge anche `cursore <misura> <tema…>`, col tema fino a
    /// fine riga, spazi compresi (`compositore/src/main.c`, verbo `cursore`):
    /// qui si manda quella forma, e il nome arriva intero.
    function cursore(tema, misura) {
        // La misura dev'essere fatta di sole cifre: è così che il compositore
        // distingue la forma nuova da quella vecchia. E niente a-capo nel
        // tema: la riga finisce lì, e il resto diventerebbe un altro comando.
        var mis = Math.round(Number(misura));
        comp._nostro("cursore", [String(mis > 0 ? mis : 24),
                                 String(tema).replace(/[\r\n]+/g, " ").trim()]);
    }

    /// Chiude la sessione grafica.
    ///
    function esciDallaSessione() {
        comp._nostro("esci", []);
    }

    // ── Domande ──────────────────────────────────────────────────────────
    //
    // Le cose che si chiedono al compositore e che nessun altro sa.
    // La risposta arriva sul segnale `risposta(cosa, testo)`: chi chiede
    // guarda `cosa` e ignora il resto.
    //

    /// `cosa` è uno di: "schermi", "dispositivi", "puntatore".
    signal risposta(string cosa, string testo)

    function chiedi(cosa) {
        if (cosa === "schermi") {
            comp._nostro("schermi", []);
            return;
        }
        // L'elenco dei dispositivi serve al pannello «Tastiera e mouse»:
        // la levetta del touchpad ha bisogno del suo nome.
        if (cosa === "dispositivi") {
            comp._nostro("dispositivi", []);
            return;
        }
        // ── Dov'è il puntatore ───────────────────────────────────────────
        //
        // Il menù del tasto destro si apre dove sta il dito, e per saperlo lo
        // chiede. Senza risposta cadrebbe sul suo ripiego, **in alto a
        // sinistra**, lontano dal punto in cui l'avevi chiesto.
        if (cosa === "puntatore") {
            comp._nostro("puntatore", []);
            return;
        }
        // ── E qualunque altra cosa NON si lascia cadere ──────────────────
        //
        // Una domanda che nessuno raccoglie lascia chi ha chiesto ad aspettare
        // per sempre: si risponde vuoto, e si dice che non si sapeva.
        console.warn("[MINERVA][Compositore] non so rispondere a «" + cosa
                     + "»: rispondo vuoto invece di lasciare chi ha chiesto "
                     + "ad aspettare per sempre.");
        comp.risposta(cosa, "");
    }

    // ── Quello che succede ───────────────────────────────────────────────
    //
    // Il compositore annuncia i cambiamenti sul canale (`ascolta …`, vedi
    // sopra): qui diventano segnali con un nome di Minerva.

    /// Qualcosa è cambiato nelle scrivanie: quale è in uso, o quali esistono.
    signal scrivanieCambiate()

    /// Tasto destro sulla barra del titolo di una finestra: la shell apre il
    /// menu della finestra in quel punto. `x` e `y` sono dello schermo
    /// `schermo`, e la finestra ha già il fuoco.
    signal menuFinestra(real x, real y, string schermo)

    /// Una scorciatoia di quelle che tocca alla shell: `cheatsheet`,
    /// `launcher`, `control`… Il nome è quello scritto in
    /// `config/scorciatoie.minerva` dopo `minerva:`, ed è lo stesso che
    /// `core/Scorciatoia.qml` mette in `name`. Arriva per il canale.
    signal scorciatoiaPremuta(string nome)

    /// Il coperchio del portatile si è chiuso (o riaperto).
    ///
    /// Solo il FATTO. Cosa farne — sospendere, bloccare, niente — lo decide
    /// chi ascolta, leggendo `power.lidAction`: il compositore riferisce,
    /// chi ha la politica decide.
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

}
