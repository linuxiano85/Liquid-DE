pragma Singleton
import QtQuick
import "." as Core

// Windows — Le finestre aperte, viste dalla shell.
//
// Hyprland non disegna cornici attorno alle finestre: non esistono i tre
// pulsanti in alto a destra. Per chi arriva da Windows o da KDE questa è la
// prima cosa che manca, e non è un vezzo — è il modo in cui si è imparato a
// chiudere e ridurre a icona qualunque cosa.
//
// Qui li ricostruiamo, ma nella barra invece che sulla finestra. Non è un
// ripiego: nella barra sono sempre nello stesso punto, non coprono mai il
// contenuto, e valgono anche per le finestre affiancate dal tiling, che una
// cornice non ce l'hanno per definizione.
//
// «Riduci a icona» non esiste in Hyprland. Lo costruiamo spostando la finestra
// in una scrivania speciale che nessuno guarda mai: sparisce dallo schermo e
// resta viva, che è esattamente cosa vuol dire ridurre a icona.
QtObject {
    id: windows

    // ── Qual è la finestra attiva ────────────────────────────────────────
    //
    // Qui c'era `Hyprland.activeToplevel`, il modello di quickshell. Ed era
    // SEMPRE NULLO.
    //
    // Il motivo è scritto poco più sotto, dove si spiega perché l'elenco delle
    // finestre si legge con `hyprctl clients` e non con `Hyprland.toplevels`:
    // quel modello va popolato con `refreshToplevels()`, e siccome nessuno
    // qui lo chiama mai — non serviva — restava vuoto, e con lui
    // `activeToplevel`.
    //
    // Non dava nessun errore. Dava questo, e per settimane:
    //
    //  · NESSUNA barra del titolo si accendeva mai. La cornice della finestra
    //    la disegna Hyprland con l'accento, quella della barra la disegniamo
    //    noi: con la barra convinta di essere spenta, la linea d'accento
    //    saliva lungo i tre lati della finestra e si spezzava di netto dove
    //    cominciava la barra. È esattamente ciò che Giacomo ha visto e ha
    //    chiamato «la vecchia barra staccata»: non era staccata, era spenta;
    //  · il nome della finestra nella barra di sistema restava vuoto;
    //  · la dock non evidenziava mai il programma in uso;
    //  · e ogni comando senza indirizzo — «riduci», «chiudi», «ingrandisci»
    //    dal menu o da una scorciatoia — non faceva niente, perché controlla
    //    `hasActive` prima di agire.
    //
    // Adesso la risposta arriva dalle STESSE due strade da cui arriva tutto il
    // resto, e nessuna delle due può essere vuota mentre una finestra ha il
    // fuoco:
    //
    //  · l'evento `activewindowv2`, che porta l'indirizzo e arriva subito;
    //  · `focusHistoryID === 0` nell'elenco letto da `hyprctl clients`, che
    //    c'è sempre e rimette a posto le cose se un evento si perde.

    /// Indirizzo della finestra attiva, nella forma `0x…` usata da hyprctl.
    property string activeAddress: ""

    /// La finestra attiva, come la vede il compositore, o `null`.
    readonly property var active: windows.find("address:" + windows.activeAddress)

    /// Vero quando la finestra «attiva» è in realtà già ridotta a icona.
    /// Hyprland continua a considerarla attiva dopo averla spostata nella
    /// scrivania speciale, e senza questo controllo i pulsanti resterebbero
    /// nella barra a comandare una finestra che non si vede più.
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

    // Qui c'era `activeFloating`, che serviva solo a scrivere «Affianca» o
    // «Rendi libera» nel menu della finestra. Con il tiling è sparita anche
    // la domanda: in Minerva le finestre sono libere e basta.

    /// Vero quando la finestra attiva è già ingrandita.
    ///
    /// Qui c'era `fullscreen !== 0`, cioè lo stato di Hyprland, e non poteva
    /// funzionare: «ingrandisci» in Minerva NON è `fullscreen 1` del
    /// compositore — è un comando nostro che porta la finestra ai bordi dello
    /// spazio utile lasciando visibile la barra della scrivania, e che quindi
    /// non accende nessun interruttore di Hyprland. Il risultato era un
    /// pulsante che non cambiava mai segno e una voce di menu che diceva
    /// sempre «Ingrandisci» anche su una finestra già ingrandita.
    readonly property bool activeMaximized:
        windows.isMaximized(windows.find("address:" + windows.activeAddress))

    /// Finestre parcheggiate nella scrivania speciale.
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
    /// Che si possano chiudere è stato verificato a mano: `closewindow` su una
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

    // ── Interrogazione ───────────────────────────────────────────────────
    //
    // L'elenco arriva da `hyprctl -j clients` e non da `Hyprland.toplevels`.
    // Non è pigrizia: `refreshToplevels()` è asincrono e non dice quando ha
    // finito, quindi leggere la lista subito dopo averlo chiamato restituisce
    // lo stato PRECEDENTE — e la finestra appena ridotta a icona non compare
    // mai. Una interrogazione che risponde è più semplice di una che forse
    // ha già risposto.

    // _query rimosso: l'elenco arriva in push dal demone.

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
        windows._niente_ingranditi_dal_compositore();

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
    // la barra in alto, e qualunque altra cosa dichiari una zona esclusiva.
    // Lo dice Hyprland in `hyprctl monitors`, campo `reserved`, nell'ordine
    // sinistra/alto/destra/basso e in pixel logici.
    //
    // Serve per «ingrandisci», che è un comando NOSTRO e non di Hyprland.
    // `fullscreen 1` del compositore si chiama «maximize» ma prende tutto lo
    // schermo, barra della scrivania compresa: provato, restituisce
    // [0,0 1536x864] su un monitor che ne ha 44 riservati in cima. È il
    // difetto per cui il terminale ingrandito copriva la barra e la propria
    // barra del titolo spariva sotto di essa.

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
    /// Si sceglie per POSIZIONE e non per il campo `monitor` di Hyprland: quel
    /// campo dice su quale monitor il compositore considera la finestra, che
    /// nell'istante dopo un attacca-e-stacca non è ancora dove la finestra si
    /// vede. La posizione invece è quella che si guarda.
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
    // Si leggeva una volta sola, all'avvio del componente. Ed è il momento
    // PEGGIORE in cui chiederlo: la shell sta nascendo, e le zone riservate le
    // riserva la shell stessa. Nell'istante in cui questo singleton prende
    // vita, la barra della scrivania non ha ancora dichiarato la propria zona
    // esclusiva, quindi il compositore risponde onestamente «riservato:
    // niente» — e quella risposta restava vera per tutta la sessione.
    //
    // Le conseguenze non somigliano affatto alla causa, ed è per questo che è
    // costato tanto trovarla. Con `usable.y` a zero:
    //
    //  · «ingrandisci» ferma la finestra quarantaquattro pixel troppo in alto,
    //    cioè con la propria barra del titolo SOTTO la barra della scrivania.
    //    La finestra sembra incollata alla barra e senza maniglia, e per
    //    chiuderla non resta che Super+C;
    //  · l'aggancio ai bordi porta allo stesso punto, per la stessa ragione;
    //  · e non capita sempre, ma solo quando la lettura è arrivata prima della
    //    barra — cioè al primo avvio della sessione, e poi mai più. Che è
    //    esattamente quello che si vede: «lo ha fatto al suo primo avvio, nei
    //    successivi non è successo».
    //
    // Una lettura ogni cinque secondi costa un `hyprctl` — le barre del titolo
    // ne fanno uno ogni nove decimi — e non c'è nessun evento del compositore
    // che annunci un cambio di zona riservata.
    // _riletturaSpazio rimosso: le notifiche dello spazio arrivano dal demone.


    // ── Chi ha la barra del titolo SOPRA, e chi dentro ───────────────────
    //
    // Cambia dove una finestra si ferma quando la si ingrandisce, e non è un
    // dettaglio: una finestra con la barra sopra che arriva fino al bordo si
    // porta la propria barra sotto quella della scrivania, e i suoi pulsanti
    // diventano incliccabili. È il difetto che Giacomo aveva descritto come
    // «il terminale se lo metto a schermo intero metà barra del titolo viene
    // coperta dalla barra del desktop».
    //
    // La risposta stava in tre posti che potevano rispondere diversamente:
    // le barre sopra le finestre altrui passavano `true`, quelle dentro le
    // nostre `false`, e il menu della finestra non passava niente perché
    // chiamava un'altra funzione ancora. Adesso la domanda si fa qui, una
    // volta, e chi ingrandisce non deve più saperne niente.

    /// I programmi che la barra del titolo se la disegnano da soli.
    ///
    /// Hyprland non ha decorazioni lato server: dice a ogni programma
    /// «fattela tu», e quasi nessuno lo fa — perciò gliela disegna Minerva.
    /// I browser però sì, e parecchie applicazioni GNOME anche: su quelle la
    /// nostra sarebbe la seconda barra. L'elenco sta nelle impostazioni.
    function disegnaLaSua(appClass) {
        var cls = String(appClass || "").toLowerCase();
        if (cls === "")
            return false;
        var elenco = Core.Ipc.get("windows.csdApps", []);
        for (var i = 0; i < elenco.length; i++) {
            var voce = String(elenco[i] || "").toLowerCase();
            if (voce !== "" && cls.indexOf(voce) !== -1)
                return true;
        }
        return false;
    }

    /// Vero quando la finestra riempie già tutto lo spazio che le compete.
    ///
    /// Si guarda la GEOMETRIA e non un interruttore nostro: così resta giusto
    /// anche se a ingrandirla è stato un aggancio al bordo, un doppio clic
    /// sulla barra o il programma stesso, e il pulsante mostra sempre il segno
    /// che serve.
    ///
    /// Un pixel di tolleranza: lo schermo è ingrandito di un quarto, e fra
    /// pixel logici e fisici gli arrotondamenti non tornano sempre.
    function isMaximized(w) {
        // Lo stato lo tiene il compositore (`ingrandita`, che arriva come
        // `modoSchermo === 1`): niente più indovinarlo dalla geometria.
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

            // `w.fullscreen` è vero solo per lo schermo intero VERO (modo 2),
            // ma il compositore rifiuta di spostare anche le finestre
            // ingrandite (modo 1) — e rifiutando risponde «Window is
            // fullscreen». Il risultato era un comando respinto a ogni giro:
            // centocinquanta avvisi nel registro in una sessione, e altrettante
            // andate e ritorni sul socket per niente.
            if (!w.address || w.address === "" || w.minimized || w.modoSchermo !== 0)
                continue;
            if (w.w <= 0 || w.h <= 0)
                continue;

            // ── Non si tocca una finestra che si sta muovendo ────────────
            //
            // Questa garanzia manda `movewindowpixel`. Il trascinamento col
            // mouse lo fa il compositore, con la sua strada. Se i due agiscono
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
    // Misurato il 10 agosto 2026 sul gestore file, prima riga di `hyprctl
    // clients`: `at: -2,44   size: 1536,864`. Le parole di Giacomo erano «le
    // finestre escono fuori dallo schermo e devo passarle a schermo intero»:
    // il rimedio che aveva trovato è giusto, perché «schermo intero» è
    // l'unico comando che rifà i conti da capo.
    //
    // Quindi si guardano tutti e quattro i bordi, e si RIMPICCIOLISCE prima di
    // spostare — una finestra più grande dello spazio non entra spostandola.
    //
    // È una funzione pura apposta: le prove in `prove-finestre.qml` le passano
    // numeri e non toccano nessuna finestra vera.
    // ── Il modo «ingrandito» del compositore non lo chiede nessuno ───────
    //
    // In Minerva «ingrandisci» è GEOMETRIA: si ridimensiona e si sposta (vedi
    // `maximize`). Il modo 1 di Hyprland non lo usiamo mai — per le finestre
    // che si disegnano da sé si tocca solo il bit del PROGRAMMA
    // (`fullscreenstate 0 1`), non quello del compositore.
    //
    // Quindi una finestra che si trova nel modo 1 ce l'ha messa qualcun
    // altro: il programma stesso, o un comando arrivato da fuori. E costa
    // carissimo, perché in quel modo il compositore manda l'ingresso a LEI:
    // le altre restano disegnate sullo schermo e non ricevono più niente.
    //
    // Giacomo, 12 agosto 2026: «non riesco più a spostare Kate, è diventata
    // una finestra fantasma: è sullo schermo ma non posso chiuderla,
    // spostarla o usarla». Il colpevole non l'abbiamo trovato; la difesa
    // serve comunque.
    //
    // Togliendo il modo, il compositore rimette la finestra alla misura che
    // aveva prima. Qui c'era anche un «e poi la ingrandisco con i conti
    // nostri», e non funzionava: partiva centocinquanta millisecondi dopo e
    // trovava l'elenco delle finestre non ancora riletto, quindi si tirava
    // indietro — sempre. Una cosa che a volte succede e a volte no è peggio
    // di una che non c'è: tolta. Chi vuole la finestra grande preme
    // Super+M, che è il nostro «ingrandisci» e funziona sempre.
    //
    // Si dice ad alta voce: se un giorno scatta di continuo, il registro dirà
    // chi lo mette e si potrà smettere di indovinare.
    function _niente_ingranditi_dal_compositore() {
        var tutte = windows.all || [];
        for (var i = 0; i < tutte.length; i++) {
            var w = tutte[i];
            if (!w.address || w.minimized)
                continue;
            if (w.modoSchermo === 1 && !windows.disegnaLaSua(w.appClass)) {
                if (windows._giaCorrette.indexOf(w.address) !== -1)
                    continue;
                console.log("[MINERVA][FINESTRE] " + (w.appClass || "?")
                            + " era nel modo «ingrandito» del compositore, che "
                            + "noi non chiediamo mai: lo tolgo, e torna alla "
                            + "misura che aveva prima.");
                windows._giaCorrette = windows._giaCorrette.concat([w.address]);
                Compositore.schermoIntero(w.address, false);
            } else if (w.modoSchermo === 0
                       && windows._giaCorrette.indexOf(w.address) !== -1) {
                // Tornata normale: si dimentica, così se ci ricasca la si
                // corregge di nuovo invece di lasciarla lì per sempre.
                windows._giaCorrette = windows._giaCorrette.filter(function (a) {
                    return a !== w.address;
                });
            }
        }
    }

    /// Indirizzi già tolti dal modo «ingrandito» del compositore, per non
    /// combattere all'infinito con un programma che ci ricasca da solo.
    property var _giaCorrette: []

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

    /// La finestra indicata da un selettore di Hyprland (`address:0x…`
    /// oppure `pid:1234`), o null. La usa anche ogni finestra di Minerva
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
        // Qui c'erano centoventi righe che ingrandivano a mano: si leggeva lo
        // spazio libero, si ricordava dov'era la finestra, e si mandavano
        // «ridimensiona» e «sposta» coi conti nostri. Era la strada di quando
        // sotto c'era un compositore che non sapeva farlo. Il nostro lo sa
        // (`finestra_ingrandisci`): tiene lui lo stato, dice al programma
        // «sei ingrandito», ricorda la misura di prima, e — la cosa che coi
        // conti nostri mancava — fa tornare piccola sotto il puntatore una
        // finestra ingrandita che si trascina. Con i pixel spostati a mano per
        // lui la finestra era normale e grande, e trascinandola usciva dallo
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
        // `Compositore.riduci()`, e cambia da un compositore all'altro. Qui
        // c'era «mandala nella scrivania speciale», che è la strada di
        // Hyprland — e sotto il nostro compositore faceva sparire la finestra
        // senza modo di riportarla indietro.
        if (address)
            Compositore.riduci(address, true);
        else if (windows.hasActive)
            Compositore.riduci("", true);
        else
            return;
        refreshSoon.restart();
    }

    /// Porta una finestra davanti E le dà il fuoco. Sono DUE cose, e per anni
    /// qui ce n'era una sola.
    ///
    /// `focuswindow` sposta il fuoco: da quel momento i tasti vanno lì. Non
    /// tocca l'ordine di sovrapposizione. Il risultato è una finestra che ha
    /// il fuoco e sta dietro a un'altra — si scrive dentro qualcosa che non si
    /// vede. Cliccando l'icona nella dock sembra semplicemente che non sia
    /// successo niente.
    ///
    /// `alterzorder top` è il pezzo che mancava.
    ///
    /// ── QUELLO CHE `alterzorder` NON PUÒ FARE ────────────────────────────
    ///
    /// Hyprland disegna in quest'ordine: prima le finestre agganciate alla
    /// griglia, POI tutte quelle libere. Sempre. Una finestra agganciata non
    /// può stare davanti a una libera, qualunque cosa le si chieda — e non
    /// c'è un'impostazione del compositore che lo cambi (cercata: non esiste).
    ///
    /// Quindi con un terminale libero che copre lo schermo, cliccare nella
    /// dock un programma agganciato lo mette a fuoco ma resta dietro. Non è
    /// un difetto di Minerva e non si risolve da qui: si risolve scegliendo
    /// «finestre libere» nelle impostazioni, dove tutto sta in una pila sola
    /// e l'ordine torna a essere una cosa che decidiamo noi.
    function focus(address) {
        if (!address)
            return;
        Compositore.fuoco(address);
        Compositore.davanti(address);
        refreshSoon.restart();
    }

    /// Massimizza o rimette a posto. Accetta un indirizzo, come tutti gli
    /// altri: il pulsante sulla barra del titolo di una finestra QUALSIASI
    /// deve agire su quella finestra, non su quella che ha il fuoco. Erano la
    /// stessa cosa solo finché il fuoco seguiva sempre il clic — e con una
    /// dock che agisce a distanza non è più vero.
    /// Ingrandisce o rimette a posto. Senza indirizzo vale per la finestra
    /// attiva.
    ///
    /// Qui c'era `fullscreenstate 2` (e `fullscreen 1` senza indirizzo), cioè
    /// il «massimizza» di Hyprland — che prende TUTTO lo schermo, barra della
    /// scrivania compresa. Il risultato era che lo stesso comando faceva due
    /// cose diverse a seconda di dove lo si chiedeva: dal pulsante sulla barra
    /// del titolo la finestra si fermava sotto la barra della scrivania, dal
    /// menu della finestra la copriva. Adesso è la stessa cosa da tutte e due
    /// le parti, perché è la stessa funzione.
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

    // Qui c'era `toggleFloating()`, che affiancava o liberava la finestra
    // attiva. Non c'è più perché non c'è più niente da commutare: in Minerva
    // ogni finestra nasce libera e resta libera (vedi `core/WindowRules.qml`).
    // Restava raggiungibile da due posti — il nome della finestra nella barra
    // e il menu della finestra — e da lì si poteva affiancare una finestra in
    // un ambiente che non sa più come rimetterla a posto.

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
    // Si interroga dopo gli eventi del compositore, non a intervalli fissi:
    // chiedere a Hyprland dieci volte al secondo se è cambiato qualcosa costa
    // più di tutto il resto della shell messo insieme.

    property Timer _refreshSoon: Timer {
        id: refreshSoon
        // Hyprland manda l'evento prima di aver finito di spostare la
        // finestra: interrogarlo subito restituisce lo stato precedente.
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
            // ancora quello di uno schermo senza barra: vedi il perché sopra
            // `_riletturaSpazio`. Un secondo e due decimi è tempo più che
            // sufficiente perché la barra abbia riservato il proprio posto, e
            // la rilettura periodica comincia solo al quinto secondo.
            windows.refreshUsable();
        }
    }
}
