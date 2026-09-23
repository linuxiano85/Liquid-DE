import QtQuick
import Quickshell
import "core" as Core

// ProveCanale — Che la shell parli col compositore GIUSTO.
//
//     qs -p minerva-shell/prove-canale.qml
//
// ── Perché queste prove esistono ───────────────────────────────────────────
//
// Perché da oggi Minerva parla con due compositori — Hyprland e il nostro — e
// il difetto che si sta comprando è preciso: **credere di provare una
// scrivania mentre se ne comanda un'altra.**
//
// È già successo, in un'altra forma. `Quickshell.Hyprland` non cerca Hyprland
// guardandosi intorno: legge `HYPRLAND_INSTANCE_SIGNATURE` dall'ambiente. La
// prova annidata del compositore ha dovuto togliere quella variabile a mano,
// perché senza, la shell dentro minerva-wayland mandava i suoi comandi al
// Hyprland VERO — e si riconfigurava la scrivania su cui si stava lavorando.
//
// Qui si prova la stessa cosa dall'altro capo: che `core/Compositore.qml`
// scelga la strada in base a `MINERVA_CANALE`, e che i verbi che manda al
// nostro compositore siano quelli che lui capisce.
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

    // ── Come si guarda cosa parte, senza farlo partire ───────────────────
    //
    // Le funzioni di un Singleton QML sono in sola lettura: non si possono
    // sostituire, e il primo tentativo di scrivere queste prove è morto lì.
    //
    // Si guarda invece `Compositore.ultimaRiga`, che il file aggiorna a ogni
    // verbo mandato — anche quando il socket non è collegato. Non è un aggancio
    // per le prove: con Hyprland, un comando scritto male dava «Invalid
    // dispatcher» in un avviso che non fermava niente, e per sapere cosa fosse
    // stato detto alla finestra bisognava rileggere il codice.
    //
    // ── E perché queste prove si lanciano con MINERVA_CANALE ─────────────
    //
    // Perché `Compositore.nostro` è quella variabile: senza, la shell non si
    // considera dentro minerva-wayland e i verbi non partono nemmeno. Il
    // percorso può — anzi DEVE — non esistere: quello che conta è che la
    // variabile ci sia. Se punta a un socket vero, il banco si ferma (più
    // sotto, e c'è scritto perché).
    //
    //     MINERVA_CANALE=/non/esisto qs -p minerva-shell/prove-canale.qml
    //
    // Se manca, queste prove NON si eseguono e lo dicono. Una prova che, per
    // essere eseguita nel modo sbagliato, riconfigura il computer, è peggio di
    // una prova che manca.

    function ultima() {
        return String(Core.Compositore.ultimaRiga);
    }

    Component.onCompleted: {
        console.log("── Prove del canale verso il compositore ──");

        // ── I sostantivi ─────────────────────────────────────────────────
        //
        // Si provano PRIMA della guardia su MINERVA_CANALE, e apposta: sono
        // funzioni pure — leggono un oggetto e ne tornano un altro — e non
        // mandano niente a nessuno. Metterle dietro la guardia vorrebbe dire
        // non provarle mai nel giro normale delle prove.

        var nostra = Core.Compositore.finestraDaCompositore({
            "id": "0x55f1c0", "pid": 4211, "titolo": "Konsole",
            "classe": "org.kde.konsole",
            "x": 100, "y": 60, "larghezza": 800, "altezza": 600,
            "ingrandita": false, "ridotta": true, "schermoIntero": false,
            "posto": 2, "decorata": true
        }, "speciale:minervaridotte");

        banco.verifica("una finestra di minerva-wayland si riconosce da sola",
                       nostra.address === "0x55f1c0" && nostra.pid === 4211,
                       JSON.stringify(nostra));
        banco.verifica("«ridotta» è «minimized», senza scrivanie di servizio",
                       nostra.minimized === true, String(nostra.minimized));
        banco.verifica("«posto» è «stack»", nostra.stack === 2,
                       String(nostra.stack));
        banco.verifica("in minerva-wayland ogni finestra galleggia",
                       nostra.floating === true, String(nostra.floating));
        banco.verifica("classe e misure",
                       nostra.appClass === "org.kde.konsole"
                       && nostra.w === 800 && nostra.h === 600,
                       JSON.stringify(nostra));

        var grande = Core.Compositore.finestraDaCompositore({
            "id": "0x1", "classe": "c", "titolo": "t",
            "ingrandita": true, "schermoIntero": false
        }, "");
        banco.verifica("ingrandita è modo UNO, non schermo intero",
                       grande.modoSchermo === 1 && grande.fullscreen === false,
                       String(grande.modoSchermo));

        var pieno = Core.Compositore.finestraDaCompositore({
            "id": "0x1", "classe": "c", "titolo": "t",
            "ingrandita": false, "schermoIntero": true
        }, "");
        banco.verifica("schermo intero è modo DUE",
                       pieno.modoSchermo === 2 && pieno.fullscreen === true,
                       String(pieno.modoSchermo));

        // E la lingua di Hyprland continua a funzionare: sono due compositori
        // per un mese, non uno dopo l'altro.
        var hypr = Core.Compositore.finestraDaCompositore({
            "address": "0xaa", "pid": 9, "title": "Konsole",
            "class": "konsole", "at": [1, 2], "size": [3, 4],
            "focusHistoryID": 0, "fullscreen": 2,
            "workspace": { "id": 1, "name": "1" }
        }, "speciale:minervaridotte");
        banco.verifica("e una finestra di Hyprland si legge ancora",
                       hypr.address === "0xaa" && hypr.w === 3
                       && hypr.modoSchermo === 2,
                       JSON.stringify(hypr));

        // ── Le scrivanie ─────────────────────────────────────────────────
        //
        // Fino al 25 agosto `workspace` era scritto `1` a mano, perché in
        // minerva-wayland le scrivanie non c'erano. Adesso c'è, e da questo
        // numero dipende quali barre del titolo si disegnano: sbagliarlo vuol
        // dire la barra di una finestra che sta altrove disegnata sopra lo
        // sfondo di questa — «rimangono dei residui».
        var terza = Core.Compositore.finestraDaCompositore({
            "id": "0x9", "classe": "c", "titolo": "t", "scrivania": 3
        }, "");
        banco.verifica("una finestra sa su quale scrivania sta",
                       terza.workspace === 3, String(terza.workspace));

        var senza = Core.Compositore.finestraDaCompositore({
            "id": "0x9", "classe": "c", "titolo": "t"
        }, "");
        banco.verifica("e senza il campo si torna alla prima, non a zero",
                       senza.workspace === 1, String(senza.workspace));

        var elenco = Core.Compositore.scrivanieDaNostro(
            '[{"id":1,"nome":"1","finestre":2,"attiva":false},'
            + '{"id":4,"nome":"4","finestre":0,"attiva":true}]');
        banco.verifica("l'elenco delle scrivanie si legge",
                       elenco.length === 2 && elenco[0].finestre === 2
                       && elenco[1].id === 4 && elenco[1].attiva === true,
                       JSON.stringify(elenco));
        banco.verifica("e una risposta storta non fa cadere niente",
                       Core.Compositore.scrivanieDaNostro("{rotto").length === 0);

        // ── Gli schermi ──────────────────────────────────────────────────
        var sn = Core.Compositore.schermoDaCompositore({
            "nome": "WL-1", "larghezza": 1536, "altezza": 864,
            "x": 0, "y": 0, "scala": 1.25, "acceso": true, "attivo": true,
            "utileX": 0, "utileY": 42,
            "utileLarghezza": 1536, "utileAltezza": 822
        }, 0);
        banco.verifica("lo spazio utile arriva già sottratto e già logico",
                       sn.x === 0 && sn.y === 42
                       && sn.w === 1536 && sn.h === 822,
                       JSON.stringify(sn));
        banco.verifica("e il contorno vero resta intero",
                       sn.sw === 1536 && sn.sh === 864, JSON.stringify(sn));
        banco.verifica("lo schermo attivo", sn.attivo === true
                       && sn.nome === "WL-1", JSON.stringify(sn));

        // Qui c'era la stessa prova sulla forma di Hyprland — `width`,
        // `scale`, `reserved` — perché `schermoDaCompositore` riconosceva due
        // dialetti. Adesso ne parla uno solo, e una prova che passa un JSON
        // che nessuno manderà più non prova niente: se ne è andata con lui.

        var dentro = String(Core.Compositore.percorsoCanale);
        banco.verifica("«nostro» segue MINERVA_CANALE, e nient'altro",
                       Core.Compositore.nostro === (dentro !== ""),
                       "MINERVA_CANALE=«" + dentro + "» nostro="
                       + Core.Compositore.nostro);

        if (!Core.Compositore.nostro) {
            console.log("  ·    SALTATE: senza MINERVA_CANALE non c'è niente");
            console.log("  ·    da provare. Rilancia con:");
            console.log("  ·      MINERVA_CANALE=/non/esisto qs -p "
                        + "minerva-shell/prove-canale.qml");
            banco.fine();
            return;
        }

        // ── E qui ci si FERMA se il canale è quello VERO ─────────────────
        //
        // Questo banco non finge: chiama davvero `Core.Compositore`, e ogni
        // verbo esce sul socket a cui punta `MINERVA_CANALE`. Lanciato dentro
        // la sessione senza precauzioni — cioè nel modo più naturale, un
        // `qs -p` da un terminale — riconfigura la scrivania su cui stai
        // lavorando: touchpad spento, sensibilità cambiata, lente accesa,
        // barre del titolo di un'altra altezza. Successo il 1º settembre
        // 2026, e la sessione è rimasta col tocco del trackpad spento.
        //
        // `prove.sh` lo lancia giusto (`MINERVA_CANALE=/non/esisto`), ma una
        // regola che vive solo dentro chi la rispetta non è una regola.
        //
        // Il controllo è doppio, e il secondo è quello che conta.
        //
        // `canaleAperto` dice «qualcuno ha risposto». È la prova diretta, ma
        // arriva tardi: collegare un socket è asincrono, e qui siamo dentro
        // `Component.onCompleted` — la connessione può essere ancora in volo,
        // e allora la guardia direbbe di no proprio nel momento in cui serve.
        //
        // Perciò si guarda anche **dove punta il percorso**. I socket delle
        // sessioni vere stanno tutti in `$XDG_RUNTIME_DIR` (cioè
        // `/run/user/1000`): è lì che il compositore li crea, sessione vera e
        // sessione annidata comprese. Questo banco non ha mai bisogno di un
        // socket vero — gli basta che la variabile ci sia — quindi un percorso
        // dentro quella cartella è sempre e solo un errore di chi lancia.
        // Questa metà è sincrona e non può arrivare in ritardo.
        var dovePunta = String(Core.Compositore.percorsoCanale);
        var casaDeiSocket = "";
        try {
            casaDeiSocket = String(Quickshell.env("XDG_RUNTIME_DIR") || "");
        } catch (e) {
            casaDeiSocket = "";
        }
        var puntaAllaSessione =
            (casaDeiSocket !== "" && dovePunta.indexOf(casaDeiSocket + "/") === 0)
            || dovePunta.indexOf("/run/user/") === 0;

        if (Core.Compositore.canaleAperto || puntaAllaSessione) {
            console.log("  ·    FERMO: MINERVA_CANALE punta a un socket VIVO");
            console.log("  ·      " + Core.Compositore.percorsoCanale);
            console.log("  ·    Questo banco manda verbi VERI: cambierebbe la");
            console.log("  ·    scrivania su cui stai lavorando. Rilancia con:");
            console.log("  ·      MINERVA_CANALE=/non/esisto qs -p "
                        + "minerva-shell/prove-canale.qml");
            banco.verifica("il banco non gira contro la sessione vera",
                           false, "MINERVA_CANALE=" + dovePunta
                           + (Core.Compositore.canaleAperto
                              ? " (ha risposto qualcuno)"
                              : " (dentro " + casaDeiSocket + ")"));
            banco.fine();
            return;
        }

        // ── I verbi ──────────────────────────────────────────────────────
        //
        // Ogni riga qui sotto è confrontata con quello che `minerva_comando()`
        // sa leggere in `compositore/src/main.c`. Sono due file in due
        // linguaggi diversi che devono dire la stessa parola, ed è esattamente
        // il posto dove una differenza non dà errore: il compositore risponde
        // «no verbo sconosciuto» a voce bassa, e la finestra non si muove.

        Core.Compositore.fuoco("0x55aa");
        banco.verifica("fuoco", banco.ultima() === "fuoco address:0x55aa",
                       banco.ultima());

        Core.Compositore.davanti("0x55aa");
        banco.verifica("davanti", banco.ultima() === "davanti address:0x55aa",
                       banco.ultima());

        Core.Compositore.chiudi("0x55aa");
        banco.verifica("chiudi", banco.ultima() === "chiudi address:0x55aa",
                       banco.ultima());

        // Senza indirizzo vuol dire «quella attiva», ed è la convenzione che
        // il compositore capisce: la parola `attiva` al posto di un indirizzo.
        Core.Compositore.chiudi("");
        banco.verifica("chiudi senza indirizzo dice «attiva»",
                       banco.ultima() === "chiudi attiva", banco.ultima());

        Core.Compositore.sposta("0x55aa", 100.4, 60.6);
        banco.verifica("sposta, con le coordinate arrotondate",
                       banco.ultima() === "sposta address:0x55aa 100 61",
                       banco.ultima());

        Core.Compositore.ridimensiona("0x55aa", 500, 300);
        banco.verifica("ridimensiona",
                       banco.ultima() === "ridimensiona address:0x55aa 500 300",
                       banco.ultima());

        Core.Compositore.schermoIntero("0x55aa", true);
        banco.verifica("schermo intero acceso",
                       banco.ultima() === "schermointero address:0x55aa 1",
                       banco.ultima());

        Core.Compositore.schermoIntero("0x55aa", false);
        banco.verifica("schermo intero spento",
                       banco.ultima() === "schermointero address:0x55aa 0",
                       banco.ultima());

        Core.Compositore.commutaSchermoIntero("0x55aa");
        banco.verifica("schermo intero commutato (senza il terzo campo)",
                       banco.ultima() === "schermointero address:0x55aa",
                       banco.ultima());

        // ── Le scrivanie: i verbi ────────────────────────────────────────
        //
        // Attenzione al plurale: `scrivanie` è la domanda «quali ci sono»,
        // `scrivania` è l'ordine «vai lì». Una lettera di differenza, e sono
        // i due versi opposti della stessa porta.
        Core.Compositore.vaiAScrivania(3);
        banco.verifica("vai alla scrivania",
                       banco.ultima() === "scrivania 3", banco.ultima());

        Core.Compositore.scrivaniaVicina(true);
        banco.verifica("la rotellina in avanti salta le vuote",
                       banco.ultima() === "scrivania avanti", banco.ultima());

        Core.Compositore.scrivaniaVicina(false);
        banco.verifica("e all'indietro",
                       banco.ultima() === "scrivania indietro", banco.ultima());

        Core.Compositore.portaAScrivania("0x55aa", 2, true);
        banco.verifica("porta la finestra là senza seguirla",
                       banco.ultima() === "portaascrivania address:0x55aa 2 si",
                       banco.ultima());

        Core.Compositore.portaAScrivania("0x55aa", 2, false);
        banco.verifica("o seguendola",
                       banco.ultima() === "portaascrivania address:0x55aa 2 no",
                       banco.ultima());

        // Senza indirizzo si dice `attiva`, come per gli altri verbi.
        // `_selettore("")` darebbe `address:`, che il compositore cercherebbe
        // davvero e non troverebbe.
        Core.Compositore.portaAScrivania("", 5, true);
        banco.verifica("e senza indirizzo dice «attiva»",
                       banco.ultima() === "portaascrivania attiva 5 si",
                       banco.ultima());

        Core.Compositore.aggiornaScrivanie();
        banco.verifica("l'elenco si chiede col plurale",
                       banco.ultima() === "scrivanie", banco.ultima());

        // ── L'indirizzo nudo e quello intero valgono uguale ──────────────
        Core.Compositore.fuoco("address:0x55aa");
        banco.verifica("un indirizzo già intero non si raddoppia",
                       banco.ultima() === "fuoco address:0x55aa",
                       banco.ultima());

        // ── Gli schermi ─────────────────────────────────────────────────
        //
        // La pagina Schermi mandava le sue modifiche con `hyprctl keyword`:
        // sotto il nostro compositore non arrivavano a nessuno, e la
        // risoluzione cambiava soltanto al riavvio della sessione.
        Core.Compositore.schermo("eDP-1", "1920x1080@60", 1.25, 0);
        banco.verifica("una modifica dello schermo arriva al compositore",
                       banco.ultima() === "schermo eDP-1 1920x1080@60 1.25 0",
                       banco.ultima());

        Core.Compositore.schermo("DP-2", "1280x720@60", 1, 90, 1920, 0);
        banco.verifica("con la posizione, quando gliela si dà",
                       banco.ultima() === "schermo DP-2 1280x720@60 1 90 1920 0",
                       banco.ultima());

        // ── La rotazione: gradi, non i numeri di Hyprland ────────────────
        //
        // Hyprland la chiama `transform` e la conta da 0 a 3. Passare quel
        // numero al nostro compositore vorrebbe dire chiedergli di ruotare
        // di UN grado — che lui rifiuta, e giustamente. Chi ha ancora in
        // mano i numeri vecchi non deve rompersi in silenzio.
        Core.Compositore.schermo("DP-2", "1280x720@60", 1, 1);
        banco.verifica("un «1» di Hyprland diventa 90 gradi",
                       banco.ultima() === "schermo DP-2 1280x720@60 1 90",
                       banco.ultima());

        Core.Compositore.schermo("DP-2", "1280x720@60", 1, 45);
        banco.verifica("e una rotazione che non è un quarto di giro è «dritto»",
                       banco.ultima() === "schermo DP-2 1280x720@60 1 0",
                       banco.ultima());

        Core.Compositore.schermoSpento("DP-2");
        banco.verifica("spegnere uno schermo è lo stesso verbo",
                       banco.ultima() === "schermo DP-2 spento", banco.ultima());

        Core.Compositore.chiedi("schermi");
        banco.verifica("e l'elenco si chiede sul canale, non con hyprctl",
                       banco.ultima() === "schermi", banco.ultima());

        // ── Le due risposte diventano la stessa cosa ────────────────────
        //
        // È la parte che rendeva vuota la pagina Schermi: sotto il nostro
        // compositore i nomi dei campi sono altri, e chi li leggeva a mano
        // non trovava niente. Un compositore che risponde e una pagina che
        // dice «nessuno schermo rilevato» è peggio di un errore.
        var daHypr = Core.Compositore.schermiDaTesto(JSON.stringify([{
            "name": "eDP-1", "description": "BOE", "width": 1920,
            "height": 1080, "refreshRate": 59.997, "scale": 1.25,
            "transform": 1, "x": 0, "y": 0, "focused": true,
            "availableModes": ["1920x1080@60.00Hz", "1920x1080@59.99Hz"]
        }]));
        banco.verifica("la risposta di Hyprland diventa il nostro vocabolario",
                       daHypr.length === 1 && daHypr[0].nome === "eDP-1"
                       && daHypr[0].larghezza === 1920 && daHypr[0].hz === 60
                       && daHypr[0].gradi === 90 && daHypr[0].acceso === true
                       && daHypr[0].attivo === true,
                       JSON.stringify(daHypr[0]));
        banco.verifica("e due modi che arrotondano uguale diventano uno",
                       daHypr[0].modi.length === 1
                       && daHypr[0].modi[0] === "1920x1080@60",
                       JSON.stringify(daHypr[0].modi));

        var daNostro = Core.Compositore.schermiDaTesto(JSON.stringify([{
            "nome": "WL-1", "descrizione": "Wayland output 1",
            "larghezza": 1280, "altezza": 720, "hz": 60, "scala": 1,
            "rotazione": 270, "x": 0, "y": 0, "acceso": false,
            "attivo": false, "modi": ["1280x720@60"]
        }]));
        banco.verifica("e la risposta del nostro compositore pure",
                       daNostro.length === 1 && daNostro[0].nome === "WL-1"
                       && daNostro[0].larghezza === 1280
                       && daNostro[0].gradi === 270
                       && daNostro[0].acceso === false,
                       JSON.stringify(daNostro[0]));

        banco.verifica("e una risposta storta non fa cadere la pagina",
                       Core.Compositore.schermiDaTesto("non sono JSON").length === 0
                       && Core.Compositore.schermiDaTesto("{}").length === 0,
                       "");

        // ── L'ingresso: tastiera, puntatore, touchpad ───────────────────
        //
        // Le manopole del pannello «Tastiera e mouse» passavano tutte da
        // `imposta()`, cioè da `hyprctl keyword`: sotto il nostro compositore
        // non arrivavano a nessuno. La più visibile è la prima — **senza, la
        // tastiera là dentro resta americana**, e le accentate non si
        // scrivono.
        Core.Compositore.tastiera("it");
        banco.verifica("la disposizione della tastiera arriva al compositore",
                       banco.ultima() === "tastiera it -", banco.ultima());

        Core.Compositore.tastiera("us", "intl");
        banco.verifica("con la variante, quando c'è",
                       banco.ultima() === "tastiera us intl", banco.ultima());

        // Un trattino è «quella di sistema», ed è il modo di TOGLIERE una
        // scelta: senza una parola apposta non si potrebbe dire.
        Core.Compositore.tastiera("");
        banco.verifica("e senza disposizione si torna a quella di sistema",
                       banco.ultima() === "tastiera - -", banco.ultima());

        Core.Compositore.ripetizioneTasti(25, 600);
        banco.verifica("la ripetizione dei tasti",
                       banco.ultima() === "ripetizione 25 600", banco.ultima());

        Core.Compositore.sensibilitaPuntatore(0.2);
        banco.verifica("la sensibilità del puntatore",
                       banco.ultima() === "sensibilita 0.2", banco.ultima());

        Core.Compositore.touchpad(true, true, false);
        banco.verifica("le tre manopole del touchpad",
                       banco.ultima() === "touchpad si si no", banco.ultima());

        // Il trattino non è una formalità: è quello che permette al pannello
        // di cambiare UNA manopola senza rimandare anche le altre due — e
        // senza che una manopola mai scelta ne prenda una inventata.
        Core.Compositore.touchpad(undefined, undefined, true);
        banco.verifica("e «-» per quelle che non si stanno toccando",
                       banco.ultima() === "touchpad - - si", banco.ultima());

        // ── Le manopole all'AVVIO, che è il difetto del 30 agosto ────────
        //
        // Il tocco del trackpad non cliccava, e la causa non era il
        // compositore: era che nessuno gli diceva niente finché non aprivi il
        // pannello Impostazioni. `applicaIngresso()` è la funzione che lo dice
        // all'avvio, e queste due prove sono quelle che avrebbero trovato il
        // difetto prima di te.
        //
        // La prima è un RIFIUTO, ed è la più importante: senza le impostazioni
        // vere del demone, `Ipc.get()` torna i valori di FABBRICA — e
        // scriverli sopra le tue scelte sarebbe peggio del difetto che stiamo
        // riparando. Qui il demone non c'è, quindi non deve partire niente.
        Core.Compositore.touchpad(false, false, false);
        var primaDi = banco.ultima();
        Core.Compositore.applicaIngresso();
        banco.verifica("senza le impostazioni del demone non si applica niente",
                       banco.ultima() === primaDi,
                       "ha mandato «" + banco.ultima() + "» sui valori di ripiego");

        // L'altra metà — «con le impostazioni vere partono tutte e quattro le
        // manopole» — NON si prova qui, e va detto perché invece di lasciare
        // un buco muto: `Ipc.impostazioniArrivate` è in sola lettura e diventa
        // vera solo quando risponde un demone, cioè fuori dal tempo di questo
        // file. Provarla qui vorrebbe dire una prova che non può fallire, che
        // è peggio di nessuna prova. Sta dove c'è un demone vero e un
        // compositore vero: `compositore/prova-ingresso.py`.

        // ── Il nome sta in FONDO, ed è il difetto del 31 agosto 2026 ────
        //
        // Questa riga c'era già, con un nome che aveva lo spazio, e passava —
        // perché controllava solo il testo SPEDITO. Dall'altra parte il
        // compositore lo leggeva con `parola()`, che si ferma al primo
        // spazio: gli arrivava «Elan», e come «acceso o spento» la parola
        // «Touchpad».
        //
        // Nella sessione vera, dove il touchpad si chiama
        // «ELAN0504:01 04F3:312A Touchpad», la levetta del pannello e il
        // tasto Fn non facevano niente. Una prova che guarda solo il proprio
        // lato del filo può passare per mesi con il difetto dall'altro capo:
        // il giro completo si prova in `compositore/prova-ingresso.py`, con
        // un compositore vero che risponde.
        // ── Chi comanda le impostazioni di SISTEMA è UNO SOLO ───────────
        //
        // 31 agosto 2026. `core/Compositore.qml` sta dentro ogni nostra
        // applicazione, e le impostazioni arrivano a tutte: senza una guardia,
        // aprire il gestore file rimandava al compositore la disposizione
        // della tastiera, l'aspetto delle barre del titolo e le regole delle
        // finestre — e lanciava una shell per riscrivere un file di
        // configurazione, a ogni apertura di ogni app.
        //
        // Le porte erano TRE: l'apertura del canale, l'arrivo delle
        // impostazioni, e `WindowRules.write()`. Chiuderne due su tre non
        // serviva a niente, ed è esattamente quello che era successo al primo
        // tentativo.
        //
        // Questo banco NON è la scrivania, quindi `scrivania` deve essere
        // falso: se un giorno diventasse vero per sbaglio — per esempio
        // deducendolo da qualcosa che vale per tutti — questa prova lo dice.
        banco.verifica("una finestra qualunque NON è la scrivania",
                       Core.Compositore.scrivania === false,
                       "scrivania = " + Core.Compositore.scrivania);

        Core.Compositore.dispositivoAcceso("Elan Touchpad", false);
        banco.verifica("spegnere un dispositivo per nome, col nome in fondo",
                       banco.ultima() === "dispositivo no Elan Touchpad",
                       banco.ultima());

        Core.Compositore.dispositivoAcceso("ELAN0504:01 04F3:312A Touchpad",
                                           true);
        banco.verifica("e il nome vero di questo portatile passa intero",
                       banco.ultima()
                           === "dispositivo si ELAN0504:01 04F3:312A Touchpad",
                       banco.ultima());

        Core.Compositore.chiedi("dispositivi");
        banco.verifica("e l'elenco dei dispositivi si chiede sul canale",
                       banco.ultima() === "dispositivi", banco.ultima());

        // ── Chi è il touchpad, dalle due risposte ───────────────────────
        //
        // Serve al tasto Fn del portatile, che senza il nome non fa niente.
        // Hyprland lo fa indovinare dal NOME; il nostro compositore lo chiede
        // a libinput — «sa contare le dita?» — che è la domanda giusta e non
        // un'ipotesi. Su questo portatile l'ipotesi è già costata.
        banco.verifica("il touchpad si riconosce nella risposta del nostro",
                       Core.Compositore.touchpadDaTesto(JSON.stringify({
                           "puntatori": [
                               {"nome": "Mouse USB", "touchpad": false},
                               {"nome": "ELAN0412:00 04F3:3162 Touchpad",
                                "touchpad": true}
                           ]
                       })) === "ELAN0412:00 04F3:3162 Touchpad", "");

        banco.verifica("e in quella di Hyprland, che lo indovina dal nome",
                       Core.Compositore.touchpadDaTesto(JSON.stringify({
                           "mice": [{"name": "usb-mouse"},
                                    {"name": "elan-touchpad"}]
                       })) === "elan-touchpad", "");

        banco.verifica("e senza touchpad si risponde «nessuno», non a caso",
                       Core.Compositore.touchpadDaTesto(JSON.stringify({
                           "puntatori": [{"nome": "Mouse", "touchpad": false}]
                       })) === ""
                       && Core.Compositore.touchpadDaTesto("storto") === "", "");

        // ── La luce notturna ────────────────────────────────────────────
        //
        // Sotto Hyprland è uno shader su tutto lo schermo; sotto il nostro
        // compositore sono tre moltiplicatori e una tabella di colore. I
        // numeri sono gli STESSI — li calcola `core/LuceNotturna.qml` dai
        // gradi Kelvin — e rifare il conto da questa parte vorrebbe dire due
        // tinte diverse il giorno che uno dei due cambia.
        Core.Compositore.coloreSchermo(1, 0.8627, 0.7059);
        banco.verifica("la tinta della luce notturna arriva al compositore",
                       banco.ultima() === "colore 1.0000 0.8627 0.7059",
                       banco.ultima());

        Core.Compositore.coloreSchermo(1, 1, 1);
        banco.verifica("e il neutro la spegne",
                       banco.ultima() === "colore 1.0000 1.0000 1.0000",
                       banco.ultima());

        banco.fine();
    }

    function fine() {
        console.log("──");
        console.log(banco.fallite === 0
                    ? "TUTTE PASSATE (" + banco.passate + ")"
                    : "FALLITE " + banco.fallite + " su "
                      + (banco.passate + banco.fallite));
        Qt.exit(banco.fallite === 0 ? 0 : 1);
    }
}
