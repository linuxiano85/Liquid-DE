pragma Singleton
import QtQuick
import "." as Core

// Windows — Le finestre aperte, viste dalla shell.
//
// È la POLITICA di Minerva sulle finestre: cosa vuol dire «ingrandisci»,
// cosa succede riducendo a icona, come si tiene una finestra dentro lo
// spazio utile. La forma in cui il compositore le descrive la traduce
// `core/Compositore.qml`; qui arriva già in lingua nostra.
QtObject {
    id: windows

    // ── Qual è la finestra attiva ────────────────────────────────────────
    //
    // Quella con `stack === 0` nell'elenco che manda il compositore (il suo
    // `posto`): l'elenco c'è sempre, e rimette a posto le cose anche se un
    // evento si perde. Senza una finestra attiva affidabile si spengono le
    // barre del titolo, la dock non evidenzia il programma in uso e ogni
    // comando senza indirizzo — «riduci», «chiudi», «ingrandisci» dal menu o
    // da una scorciatoia — non fa niente, perché controlla `hasActive`.

    /// Indirizzo della finestra attiva, nella forma `0x…` del compositore.
    property string activeAddress: ""

    /// La finestra attiva, come la vede il compositore, o `null`.
    readonly property var active: windows.find("address:" + windows.activeAddress)

    /// Vero quando la finestra in cima alla pila è ridotta a icona: senza
    /// questo controllo i pulsanti resterebbero nella barra a comandare una
    /// finestra che non si vede.
    readonly property bool activeIsMinimized:
        activeAddress !== "" && _minimizedAddresses.indexOf(activeAddress) !== -1

    readonly property bool hasActive: active !== null && !activeIsMinimized

    /// Titolo della finestra attiva, già ripulito. I terminali ci mettono
    /// dentro il percorso completo, che a metà barra è illeggibile.
    readonly property string activeTitle: {
        if (!windows.hasActive)
            return "";
        var t = windows.active.title || "";
        var cls = windows.active.appClass || "";
        if (t === "" || t.length > 90 || t.indexOf("/") === 0)
            return cls;
        return t;
    }

    /// Vero quando la finestra attiva è già ingrandita.
    readonly property bool activeMaximized:
        windows.isMaximized(windows.find("address:" + windows.activeAddress))

    /// Finestre ridotte a icona.
    property var minimized: []
    property var _minimizedAddresses: []

    /// TUTTE le finestre aperte, ridotte a icona comprese. Le usa la dock per
    /// sapere cosa c'è in giro, e la barra del titolo per sapere dov'è.
    ///
    /// Le finestre di Minerva stessa ci sono, ma marcate: `own` vale true per
    /// il gestore file e per le Impostazioni, che girano dentro il processo
    /// della shell e quindi dichiarano tutte la stessa classe,
    /// `org.quickshell`. Chi le mostra deve saperlo — una classe sola per due
    /// programmi diversi manda a gambe all'aria qualunque abbinamento fatto
    /// sulla classe, e `Core.Apps` le riconosce dal titolo.
    ///
    /// Che si possano chiudere è stato verificato a mano: «chiudi» su una
    /// finestra della shell chiude quella finestra e basta, il processo resta
    /// in piedi. Era il dubbio che le teneva fuori dalla dock.
    property var all: []

    /// Classi che appartengono a Minerva e non a un programma di fuori.
    ///
    /// Le due qui sotto sono il nome che Quickshell dà alle finestre a cui
    /// nessuno ne ha dato uno. Restano perché una finestra della shell può
    /// ancora presentarsi così, ma le APPLICAZIONI di Minerva adesso hanno un
    /// nome proprio — `minerva-files`, `minerva-settings`, `minerva-monitor`,
    /// dichiarato con `//@ pragma AppId` in cima al loro punto d'ingresso — e
    /// si riconoscono dal prefisso.
    readonly property var ownClasses: ["org.quickshell", "quickshell"]

    function isOwn(cls) {
        const C = String(cls || "").toLowerCase();
        return C.indexOf("minerva-") === 0
            || windows.ownClasses.indexOf(C) !== -1;
    }

    // ── L'elenco ─────────────────────────────────────────────────────────
    //
    // Arriva dal demone, che lo rimanda a ogni cambio (`windows_state`).

    /// L'ultimo elenco ricevuto, come testo: solo per accorgersi che il
    /// prossimo è uguale.
    property string _firma: ""

    function _parse(dati) {
        var list = dati;
        if (typeof dati === "string") {
            try {
                list = JSON.parse(dati);
            } catch (e) {
                return;
            }
        }
        if (!Array.isArray(list))
            return;

        // ── Uguale a prima: non si tocca niente ──────────────────────────
        //
        // Il demone manda l'elenco a ogni cambio e, a riposo, circa una volta
        // al secondo anche se non è cambiato niente. Ogni assegnazione di
        // `all` rifà i conti in dock, barra, stanze, schermo intero e barre
        // del titolo, su ogni schermo e in ogni finestra di Minerva. Un
        // confronto costa meno di tutto questo (5 ottobre 2026).
        var firma = JSON.stringify(list);
        if (firma === windows._firma)
            return;
        windows._firma = firma;

        var out = [];
        var addrs = [];
        var every = [];
        var attiva = "";

        for (var i = 0; i < list.length; i++) {
            // La FORMA della risposta la conosce solo la porta: qui arriva
            // già in lingua nostra. Vedi `Compositore.finestraDaCompositore`.
            var entry = Compositore.finestraDaCompositore(list[i]);
            var hidden = entry.minimized;
            entry.own = windows.isOwn(entry.appClass);

            // La finestra attiva è quella toccata per ultima. Si prende da qui
            // e non si crede sulla parola all'evento: gli eventi si possono
            // perdere — una scrivania cambiata mentre la shell si ricarica, un
            // avvio in cui la prima finestra c'era già — e una barra del titolo
            // spenta su una finestra accesa non si corregge da sé.
            if (entry.address !== "" && entry.stack === 0)
                attiva = entry.address;

            every.push(entry);

            if (!hidden)
                continue;
            out.push(entry);
            addrs.push(entry.address);
        }

        windows.all = every;

        // ── La garanzia sullo spazio ─────────────────────────────────────
        //
        // `assicuraSpazio()` tiene ogni finestra dentro lo spazio utile, con
        // la sua barra del titolo sotto la barra della scrivania e non sopra.
        // Sta qui, dove l'elenco delle finestre viene riletto, e vale sempre.
        // Chi trascina è protetto da dentro: `assicuraSpazio` salta le
        // finestre che si sono mosse dall'ultimo giro, e una trascinata si
        // muove a ogni fotogramma.
        windows.assicuraSpazio();
        windows.activeAddress = attiva;
        windows.minimized = out;
        windows._minimizedAddresses = addrs;
    }

    function refresh() {
        Core.Ipc.requestWindows();
    }

    // ── Lo spazio in cui una finestra può stare ──────────────────────────
    //
    // Non è lo schermo: è lo schermo meno ciò che la shell si è riservata —
    // la barra, la dock, e qualunque altra cosa dichiari una zona esclusiva.
    // Il compositore lo manda già calcolato (`utileX`, `utileY`, …).

    property var usable: null

    /// Lo spazio utile di OGNI schermo, non solo di quello attivo.
    ///
    /// ── Perché non basta uno ─────────────────────────────────────────────
    ///
    /// Perché con due monitor «lo spazio in cui una finestra può stare»
    /// dipende da DOVE STA la finestra, e qui c'era invece un rettangolo solo,
    /// quello del monitor col puntatore sopra.
    ///
    /// Il 10 agosto 2026, appena attaccato il secondo schermo, la garanzia che
    /// tiene le finestre dentro lo spazio utile si è messa a trascinare sul
    /// monitor attivo anche le finestre dell'altro: il terminale di Giacomo,
    /// che stava sul portatile, si è ritrovato a x=1536 — cioè appena fuori
    /// dal suo schermo. Una garanzia che sposta le finestre dove non erano è
    /// peggio del difetto che doveva impedire.
    ///
    /// Ora ce n'è uno per monitor, e chi chiede lo spazio dice per quale
    /// finestra lo vuole.
    property var spaziPerMonitor: []

    function _parseMonitors(text) {
        var list;
        try { list = JSON.parse(text); } catch (e) { return; }
        if (!Array.isArray(list) || list.length === 0)
            return;

        // La FORMA della risposta la conosce solo la porta: qui arriva già
        // in lingua nostra, come per le finestre.
        var tutti = [];
        for (var i = 0; i < list.length; i++)
            tutti.push(Compositore.schermoDaCompositore(list[i], i));
        windows.spaziPerMonitor = tutti;

        // `usable` resta lo spazio del monitor ATTIVO: è quello giusto per
        // «ingrandisci» e per l'aggancio ai bordi, che agiscono sempre sulla
        // finestra che si sta guardando. Quello che NON era giusto è usarlo
        // per una finestra qualunque.
        var att = tutti[0];
        for (i = 0; i < tutti.length; i++)
            if (tutti[i].attivo) { att = tutti[i]; break; }
        windows.usable = att;
    }

    /// Lo spazio utile del monitor su cui sta una finestra.
    ///
    /// Si sceglie per POSIZIONE: è quella che si guarda, anche nell'istante
    /// dopo un attacca-e-stacca.
    function spazioPer(w) {
        var tutti = windows.spaziPerMonitor || [];
        if (tutti.length === 0)
            return windows.usable;
        if (tutti.length === 1)
            return tutti[0];

        // Il monitor che contiene il centro della finestra.
        var cx = w.x + w.w / 2;
        var cy = w.y + w.h / 2;
        for (var i = 0; i < tutti.length; i++) {
            var u = tutti[i];
            if (cx >= u.x && cx < u.x + u.w && cy >= u.y && cy < u.y + u.h)
                return u;
        }
        // Il centro non è su nessuno: si prende quello che ne copre di più.
        var migliore = null;
        var massimo = -1;
        for (i = 0; i < tutti.length; i++) {
            u = tutti[i];
            var ox = Math.max(0, Math.min(w.x + w.w, u.x + u.w) - Math.max(w.x, u.x));
            var oy = Math.max(0, Math.min(w.y + w.h, u.y + u.h) - Math.max(w.y, u.y));
            if (ox * oy > massimo) { massimo = ox * oy; migliore = u; }
        }
        return migliore || windows.usable;
    }

    property Connections _ipcState: Connections {
        target: Core.Ipc
        function onWindowsStateReceived(clients) {
            windows._parse(clients);
        }
        function onMonitorsStateReceived(monitorsJson) {
            windows._parseMonitors(monitorsJson);
        }
    }

    function refreshUsable() {
        Core.Ipc.requestMonitors();
    }

    // ── Perché lo spazio utile si rilegge, e non si legge una volta ──────
    //
    // Letto una volta sola all'avvio, sarebbe lo spazio di uno schermo senza
    // barra: la barra non ha ancora dichiarato la propria zona esclusiva, e
    // il compositore risponde onestamente «riservato: niente». «Ingrandisci»
    // fermerebbe allora la finestra con la barra del titolo SOTTO quella
    // della scrivania. Per questo il demone rimanda lo spazio a ogni cambio,
    // e `_initial` qui sotto lo richiede comunque dopo un secondo.

    /// Vero quando la finestra è ingrandita. Lo stato lo tiene il
    /// compositore (`ingrandita`, che arriva come `modoSchermo === 1`): vale
    /// anche se a ingrandirla è stato un aggancio al bordo, un doppio clic
    /// sulla barra o il programma stesso.
    function isMaximized(w) {
        return !!w && w.modoSchermo === 1;
    }

    // ── Nessuna finestra sotto la barra della scrivania ──────────────────
    //
    // La barra della scrivania sta su un livello che copre tutte le finestre.
    // Una finestra portata troppo in alto ci finisce sotto insieme alla propria
    // barra del titolo — e la barra del titolo è la maniglia: sparita quella,
    // la finestra non si può più né spostare, né ingrandire, né chiudere col
    // mouse. Parole di Giacomo: «le finestre sono incollate alla barra e non
    // hanno la barra del titolo, devo chiuderle con super+C».
    //
    // ── Per TUTTE le finestre ────────────────────────────────────────────
    //
    // Anche per quelle di Minerva e per i programmi che si disegnano la barra
    // da soli (Firefox, Chrome, le app GNOME): avere la barra dentro non
    // serve a niente se la finestra sta sotto quella della scrivania. La
    // barra nativa del compositore sta dentro la geometria della finestra,
    // quindi per tutte basta che il bordo alto stia sotto la linea.
    //
    // Va chiamata da UN SOLO processo — la shell — o i tre processi di Minerva
    // manderebbero lo stesso comando tre volte.
    /// Dov'era ogni finestra all'ultimo giro, per capire chi si sta muovendo.
    property var _dovErano: ({})
    /// Quanti giri consecutivi ogni finestra è stata vista FERMA nello stesso
    /// posto. Servono due letture uguali prima di correggere: una sola può
    /// essere la pausa di una mano che trascina piano, o una lettura arrivata
    /// a metà di un movimento che il compositore non ci ha ancora annunciato.
    property var _ferme: ({})

    function assicuraSpazio() {
        var u = windows.usable;
        if (!u)
            return;
        var all = windows.all || [];
        var adesso = {};
        for (var k = 0; k < all.length; k++) {
            if (all[k].address)
                adesso[all[k].address] = all[k].x + "," + all[k].y + ","
                                       + all[k].w + "," + all[k].h;
        }
        var prima = windows._dovErano;
        windows._dovErano = adesso;

        // Via dal contatore chi non c'è più: senza, crescerebbe con gli
        // indirizzi di una giornata intera.
        for (var ind in windows._ferme) {
            if (adesso[ind] === undefined)
                delete windows._ferme[ind];
        }

        for (var i = 0; i < all.length; i++) {
            var w = all[i];

            // Le ingrandite e quelle a schermo intero le mette a posto il
            // compositore: spostarle a mano lo contraddirebbe.
            if (!w.address || w.address === "" || w.minimized || w.modoSchermo !== 0)
                continue;
            if (w.w <= 0 || w.h <= 0)
                continue;

            // ── Non si tocca una finestra che si sta muovendo ────────────
            //
            // Questa garanzia manda «sposta». Il trascinamento col mouse lo
            // fa il compositore, con la sua strada. Se i due agiscono
            // insieme, la finestra viene tirata da due parti: segue la mano a
            // scatti, si ferma, torna indietro. Parole di Giacomo l'11 agosto:
            // «non c'è più un trascinamento libero, vuole per forza stare
            // nelle posizioni degli angoli o tutto lo schermo».
            //
            // Misurato: duecentoventidue pixel di mouse, centocinquanta di
            // finestra, con scarti che cambiavano a ogni passo.
            //
            // Non serve chiedere al compositore se c'è un trascinamento in
            // corso — non lo dice, e non lo dirà. Bastano DUE letture con la
            // stessa geometria: una trascinata cambia posizione a ogni
            // fotogramma, e due risposte uguali di fila vogliono dire che la
            // mano si è fermata davvero. Una sola era il difetto: una
            // trascinata LENTA, o due letture che cadono nello stesso istante
            // di un movimento, e la garanzia correggeva la finestra mentre la
            // si teneva in mano — lo sfarfallio del trascinamento.
            if (prima[w.address] === undefined) {
                // Appena comparsa: non può essere a metà di un trascinamento.
                windows._ferme[w.address] = 0;
            } else if (prima[w.address] !== adesso[w.address]) {
                windows._ferme[w.address] = 0;
                continue;
            } else if ((windows._ferme[w.address] || 0) < 1) {
                windows._ferme[w.address] = (windows._ferme[w.address] || 0) + 1;
                continue;
            }

            // Lo spazio del monitor su cui sta QUESTA finestra, non quello
            // del monitor attivo: vedi `spazioPer()`.
            var r = windows.dentroLoSpazio(w, windows.spazioPer(w), 0);
            if (!r)
                continue;
            // Prima la dimensione e poi la posizione: al contrario, una
            // finestra che cresce dal proprio angolo in alto a sinistra si
            // sposta da sola e finisce fuori posto.
            if (r.w !== Math.round(w.w) || r.h !== Math.round(w.h))
                Compositore.ridimensiona(w.address, r.w, r.h);
            if (r.x !== Math.round(w.x) || r.y !== Math.round(w.y))
                Compositore.sposta(w.address, r.x, r.y);
        }
    }

    // ── Riportare una finestra dentro lo spazio utile ────────────────────
    //
    // Prende una finestra e lo spazio in cui può stare, e restituisce dove
    // andrebbe messa — oppure `null` se ci sta già.
    //
    // ── Perché non basta spingerla giù ───────────────────────────────────
    //
    // Perché è quello che faceva, e da lì nasce il difetto #14.
    //
    // La garanzia guardava un bordo solo: se la finestra stava troppo in alto
    // — sotto la barra della scrivania, senza più maniglia — la spostava giù.
    // Spostare però non è ridimensionare: una finestra alta come TUTTO lo
    // schermo (864) spinta a partire da 44 arriva a 908, cioè quarantaquattro
    // pixel sotto il bordo basso. Esattamente quelli che le si erano tolti in
    // cima.
    //
    // Misurato il 10 agosto 2026 sul gestore file: posizione -2,44, misura
    // 1536x864. Le parole di Giacomo erano «le
    // finestre escono fuori dallo schermo e devo passarle a schermo intero»:
    // il rimedio che aveva trovato è giusto, perché «schermo intero» è
    // l'unico comando che rifà i conti da capo.
    //
    // Quindi si guardano tutti e quattro i bordi, e si RIMPICCIOLISCE prima di
    // spostare — una finestra più grande dello spazio non entra spostandola.
    //
    // È una funzione pura apposta: le prove in `prove-finestre.qml` le passano
    // numeri e non toccano nessuna finestra vera.
    function dentroLoSpazio(w, u, margine) {
        if (!w || !u)
            return null;

        var minY = u.y + (margine || 0);
        var altezzaMax = u.h - (margine || 0);

        var nw = Math.round(Math.min(w.w, u.w));
        var nh = Math.round(Math.min(w.h, altezzaMax));

        // Una finestra non si rimpicciolisce sotto il minimo in cui resta una
        // finestra: sarebbe un rimedio peggiore del difetto.
        //
        // Il minimo però non può MAI essere più grande di com'era: scritto
        // come `max(nw, 240)` gonfiava a 240 una finestrella da 100, che non
        // aveva chiesto niente a nessuno. L'ha trovato la prova «una finestra
        // piccola resta piccola», scritta cinque minuti prima — ed è la
        // ragione per cui `dentroLoSpazio` è una funzione pura.
        nw = Math.max(nw, Math.min(Math.round(w.w), 240, Math.round(u.w)));
        nh = Math.max(nh, Math.min(Math.round(w.h), 160, Math.round(altezzaMax)));

        var nx = Math.round(w.x);
        var ny = Math.round(w.y);
        if (nx + nw > u.x + u.w) nx = u.x + u.w - nw;
        if (ny + nh > u.y + u.h) ny = u.y + u.h - nh;
        if (nx < u.x) nx = Math.round(u.x);
        if (ny < minY) ny = Math.round(minY);

        // Due pixel di tolleranza: senza, un arrotondamento fra pixel logici e
        // fisici basterebbe a far rispedire il comando all'infinito.
        if (Math.abs(nx - w.x) <= 2 && Math.abs(ny - w.y) <= 2
            && Math.abs(nw - w.w) <= 2 && Math.abs(nh - w.h) <= 2)
            return null;

        return { "x": nx, "y": ny, "w": nw, "h": nh };
    }

    /// La finestra indicata da un selettore (`address:0x…` oppure
    /// `pid:1234`), o null. La usa anche ogni finestra di Minerva
    /// per riconoscere sé stessa.
    function find(selector) {
        var all = windows.all || [];
        for (var i = 0; i < all.length; i++) {
            if (selector === "address:" + all[i].address
                || selector === "pid:" + all[i].pid)
                return all[i];
        }
        return null;
    }

    Component.onCompleted: windows.refreshUsable()

    /// Ingrandisce, o rimette com'era. `selector` è `address:0x…` o
    /// `pid:1234`, come per tutti i comandi sulle finestre.
    function maximize(selector) {
        if (!selector)
            return;
        // ── Lo chiede al compositore, e basta ────────────────────────────
        //
        // Il compositore sa farlo (`finestra_ingrandisci`): tiene lui lo
        // stato, dice al programma «sei ingrandito», ricorda la misura di
        // prima, e fa tornare piccola sotto il puntatore una finestra
        // ingrandita che si trascina. Coi conti fatti qui, per lui la
        // finestra era normale e grande, e trascinandola usciva dallo
        // schermo: visto il 27 settembre 2026 col gestore file.
        //
        // Senza «si» o «no» il compositore commuta: ingrandisce una finestra
        // normale e rimette com'era una ingrandita.
        Compositore.ingrandisci(selector);
        refreshSoon.restart();
    }

    // ── Comandi ──────────────────────────────────────────────────────────

    // I comandi accettano un indirizzo: la dock agisce su una finestra
    // qualsiasi, non solo su quella attiva. Senza indirizzo valgono per la
    // finestra attiva, come prima.

    // ── Mostra la scrivania ──────────────────────────────────────────────
    //
    // Il gesto di Windows: si preme una volta e tutto va giù, si preme di
    // nuovo e torna com'era. La differenza fra questo e «riduci tutto» è
    // tutta nella seconda pressione — se non rimette le cose com'erano, non
    // è «mostra la scrivania», è «chiudimi tutto in faccia».
    //
    // Quindi si tiene l'elenco di CHI è stato mandato giù da questo gesto, e
    // si rimette su solo quello. Le finestre che erano già ridotte a icona
    // prima restano dov'erano: non le ha messe via questo comando e non le
    // deve tirare fuori.
    property var _giuPerScrivania: []
    /// La stanza in cui è stato fatto il gesto.
    property int _giuNellaStanza: 0

    // ── E solo nella stanza che si guarda ────────────────────────────────
    //
    // Qui si riducevano TUTTE le finestre, anche quelle delle altre stanze,
    // e al secondo tocco rimetterle su dava il fuoco all'ultima — cioè si
    // finiva in un'altra stanza (PC di prova, 29 settembre 2026). La
    // scrivania che si vuole libera è quella davanti: le altre stanze non si
    // toccano. Se nel frattempo si è cambiata stanza, il gesto ricomincia
    // qui invece di tirare su finestre di là.
    function mostraScrivania() {
        const qui = Compositore.scrivaniaAttiva;
        if (windows._giuPerScrivania.length > 0 && windows._giuNellaStanza === qui) {
            var da = windows._giuPerScrivania.slice();
            windows._giuPerScrivania = [];
            for (var i = 0; i < da.length; i++)
                windows.restore(da[i]);
            return;
        }

        var tutte = windows.all || [];
        var messe = [];
        for (var k = 0; k < tutte.length; k++) {
            var w = tutte[k];
            if (!w.address || w.address === "" || w.minimized || w.workspace !== qui)
                continue;
            messe.push(w.address);
            windows.minimize(w.address);
        }
        windows._giuPerScrivania = messe;
        windows._giuNellaStanza = qui;
    }

    function minimize(address) {
        // Un'INTENZIONE e non un modo: come si riduce a icona lo sa
        // `Compositore.riduci()`.
        if (address)
            Compositore.riduci(address, true);
        else if (windows.hasActive)
            Compositore.riduci("", true);
        else
            return;
        refreshSoon.restart();
    }

    /// Porta una finestra davanti E le dà il fuoco. Sono DUE cose: il fuoco
    /// da solo non tocca l'ordine di sovrapposizione, e il risultato è una
    /// finestra che ha il fuoco e sta dietro a un'altra — si scrive dentro
    /// qualcosa che non si vede, e dalla dock sembra che non sia successo
    /// niente.
    function focus(address) {
        if (!address)
            return;
        Compositore.fuoco(address);
        Compositore.davanti(address);
        refreshSoon.restart();
    }

    /// Ingrandisce o rimette a posto. Accetta un indirizzo: il pulsante sulla
    /// barra del titolo di una finestra QUALSIASI deve agire su quella
    /// finestra, non su quella che ha il fuoco. Senza indirizzo vale per la
    /// finestra attiva.
    function toggleMaximize(address) {
        var a = address || windows.activeAddress;
        if (a === "")
            return;
        windows.maximize("address:" + a);
    }

    function close(address) {
        if (address)
            Compositore.chiudi(address);
        else if (windows.hasActive)
            Compositore.chiudi("");
        else
            return;
        refreshSoon.restart();
    }

    /// Riporta una finestra ridotta a icona sulla scrivania in uso.
    function restore(address) {
        if (!address)
            return;
        Compositore.riduci(address, false);
        // Anche qui il fuoco non basta: una finestra che torna su e resta
        // dietro a quella che c'era sembra non essere tornata affatto.
        windows.focus(address);
    }

    function restoreAll() {
        var all = windows.minimized;
        for (var i = 0; i < all.length; i++)
            restore(all[i].address);
    }

    // ── Aggiornamento ────────────────────────────────────────────────────
    //
    // Dopo un comando si richiede l'elenco, senza aspettare il prossimo invio
    // del demone: così la dock e le barre seguono subito.

    property Timer _refreshSoon: Timer {
        id: refreshSoon
        interval: 150
        onTriggered: windows.refresh()
    }

    property Timer _initial: Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: {
            windows.refresh();
            // E lo spazio utile, che alla nascita di questo singleton era
            // ancora quello di uno schermo senza barra: vedi sopra.
            windows.refreshUsable();
        }
    }
}
