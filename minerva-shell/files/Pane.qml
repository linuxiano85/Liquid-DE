import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Pane — Un riquadro del gestore file: una cartella, il suo elenco, la sua
// cronologia di navigazione.
//
// I due riquadri sono indipendenti: percorso, selezione, ordinamento e file
// nascosti sono di ciascuno. È tutto il senso della doppia visuale — avere
// due posti aperti contemporaneamente e spostare roba dall'uno all'altro
// senza mai perdere di vista né la partenza né l'arrivo.
Item {
    id: pane

    /// Identificatore univoco, viaggia con le richieste al demone così le
    /// risposte dei due riquadri non si confondono.
    required property string paneId

    /// Di quale cartella è l'elenco che si vede: serve a riconoscere una
    /// rilettura della stessa cartella (vedi `onFileListingReceived`).
    property string _elencoDi: ""

    // ── I tasti avanti e indietro del mouse ──────────────────────────────
    //
    // Ce li ha quasi ogni mouse, e in ogni gestore file fanno quello che
    // fanno nel browser. Accetta SOLO quei due tasti: sinistro e destro
    // passano sotto come se non ci fosse, e agisce sul riquadro sotto il
    // puntatore, che con due riquadri affiancati è quello che si indica.
    MouseArea {
        anchors.fill: parent
        z: 1000
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onClicked: function (e) {
            if (e.button === Qt.BackButton)
                pane.goBack();
            else
                pane.goForward();
        }
    }

    // Chiusa la scheda, il demone smette di guardare la sua cartella.
    Component.onDestruction: Core.Ipc.fsSmettiDiGuardare(pane.paneId)

    /// Vero quando è questo il riquadro che riceve i comandi.
    property bool focused: false

    /// Vero mentre si sta scrivendo un percorso a mano. Chi lo guarda: le
    /// scorciatoie della finestra, che devono farsi da parte — Ctrl+C mentre
    /// si scrive deve copiare il testo, non i file.
    readonly property bool editingPath: pathInput.activeFocus
                                        || filterInput.activeFocus

    property string path: ""

    /// File nascosti accesi o spenti. Sta nelle impostazioni, e non è una
    /// proprietà del riquadro: chi accende i nascosti una volta non li
    /// rivuole spenti alla prossima finestra, e tutte le schede devono
    /// vedere la stessa cosa — altrimenti una scheda mostra metà dei file e
    /// l'altra l'altra metà, e ci si chiede dove sia finita la roba.
    property bool showHidden: Core.Ipc.get("files.showHidden", false)
    property var entries: []
    property string error: ""

    /// Vero se dentro questa cartella si può creare, rinominare e togliere.
    ///
    /// Lo dice il demone (`fs_list` → `scrivibile`), che lo chiede al kernel.
    /// Nasce `true` perché finché l'elenco non è arrivato non c'è motivo di
    /// spegnere i comandi: sarebbero disattivati per un istante a ogni
    /// cartella aperta, e un'interfaccia che tremola insegna a non fidarsi.
    property bool scrivibile: true

    /// Vero quando la finestra è in modalità amministratore. Arriva legata da
    /// `FileManager`: è uno stato della FINESTRA, non della scheda — vedi il
    /// commento su `amministratore` là dentro.
    property bool amministratore: false

    /// La cartella che si sta aspettando dall'aiutante di root. Una per
    /// volta: la finestrella della password è modale, e chiederne due insieme
    /// vorrebbe dire due finestrelle sovrapposte.
    property string attesaRadice: ""

    // ── Come si guarda ───────────────────────────────────────────────────
    //
    // Elenco o griglia, quanto grandi le icone, con che ordine. Partono da
    // quello che si era scelto l'ultima volta (sta nelle impostazioni) ma
    // ognuna è del riquadro: la scheda con le fotografie sta a griglia mentre
    // quella accanto, coi documenti, resta in elenco. È lo stesso motivo per
    // cui percorso e file nascosti sono di ciascuno.

    property string viewMode: Files.defaultView   // "list" | "grid"
    property int zoom: Files.defaultZoom
    property string sortBy: Files.defaultSort     // name | size | modified | type
    property bool sortDesc: Files.defaultSortDesc

    /// Quello che si sta cercando dentro la cartella. Vuoto = si vede tutto.
    property string filter: ""

    /// L'elenco come si vede: filtrato e ordinato. Tutto quello che ragiona
    /// per indici — il cursore, la selezione a intervallo, le frecce — guarda
    /// QUESTO e mai `entries`, altrimenti la terza riga dall'alto e la terza
    /// voce dell'elenco non sono la stessa cosa.
    // ── Ordinare e filtrare sono DUE cose ────────────────────────────────
    //
    // Erano una sola:
    //
    //     shown: Files.filterEntries(Files.sortEntries(entries, by, desc), filtro)
    //
    // e siccome in QML un'associazione si ricalcola tutta quando cambia uno
    // qualunque dei valori che legge, scrivere una lettera nella ricerca
    // rifaceva anche l'ORDINAMENTO — che col filtro non c'entra niente.
    //
    // Misurato il 10 agosto 2026 su quattromila voci: ordinare costa 55 ms,
    // filtrare 1. Sette lettere digitate erano 174 ms di lavoro di cui 168
    // buttati, cioè uno scatto a ogni tasto in una casella di ricerca — che è
    // il posto in cui uno scatto si sente di più, perché si sta guardando
    // proprio lì.
    //
    // Separate, il filtro rilegge un elenco già in ordine e non lo tocca.
    /// Come il demone ha già ordinato l'elenco che ci ha mandato.
    property string ordineDalDemone: ""
    property bool contrarioDalDemone: false

    readonly property var _ordinate: {
        // Già in ordine: non si tocca. Sono i 55 ms della cartella grande, e
        // sono il caso NORMALE — nove volte su dieci si guarda una cartella
        // per nome, dall'alto.
        if (pane.ordineDalDemone === pane.sortBy
            && pane.contrarioDalDemone === pane.sortDesc)
            return pane.entries;
        return Files.sortEntries(pane.entries, pane.sortBy, pane.sortDesc);
    }

    // ── La ricerca nelle sottocartelle ───────────────────────────────────
    //
    // Ctrl+F apre il filtro, che guarda SOLO la cartella aperta e risponde
    // mentre si scrive. È una promessa che si mantiene subito, ed è giusto che
    // resti così.
    //
    // Premendo Invio la stessa parola diventa una ricerca vera: scende nelle
    // sottocartelle, e i risultati arrivano a pezzi mentre cerca. Sono due
    // gesti sulla stessa riga perché sono la stessa domanda fatta due volte —
    // «qui dentro» e poi «no, dappertutto».
    property bool cercando: false
    property var risultati: []
    property bool ricercaFinita: false
    property bool ricercaTroppi: false
    readonly property string idRicerca: "r" + pane.paneId

    function cercaSotto() {
        if (pane.filter.trim() === "")
            return;
        pane.cercando = true;
        pane.ricercaFinita = false;
        pane.ricercaTroppi = false;
        pane.risultati = [];
        pane.cursor = 0;
        pane.cursoreMostrato = false;
        Core.Ipc.fsSearch(pane.idRicerca, pane.path, pane.filter, pane.showHidden);
    }

    function fermaRicerca() {
        if (!pane.cercando)
            return;
        Core.Ipc.fsSearchCancel(pane.idRicerca);
        pane.cercando = false;
        pane.risultati = [];
        pane.ricercaFinita = false;
    }

    property Connections _ricerca: Connections {
        target: Core.Ipc
        function onRicercaAvanza(pezzo) {
            if (!pezzo || pezzo.id !== pane.idRicerca || !pane.cercando)
                return;
            if (pezzo.voci) {
                // Si accoda una copia e non si spinge dentro l'array: in QML
                // modificare un `var` non fa scattare le associazioni, e
                // l'elenco resterebbe fermo mentre i risultati arrivano.
                pane.risultati = pane.risultati.concat(pezzo.voci);
            }
            if (pezzo.fine === true) {
                pane.ricercaFinita = true;
                pane.ricercaTroppi = pezzo.troppi === true;
            }
        }
    }

    readonly property var shown: pane.cercando
        ? pane.risultati
        : Files.filterEntries(pane._ordinate, pane.filter)

    /// Apre la riga di ricerca e ci mette dentro il fuoco.
    function startFilter() {
        pane.activated();
        filterBar.open = true;
        filterInput.forceActiveFocus();
        filterInput.selectAll();
    }

    function stopFilter() {
        pane.fermaRicerca();
        // Si svuota il CAMPO e non la proprietà: appena si scrive dentro un
        // TextInput il legame con la proprietà si rompe (è così che funziona
        // QML), e azzerare solo la proprietà lascerebbe la riga con dentro
        // scritto quello di prima, pronta a rifiltrare alla riapertura.
        filterInput.text = "";
        pane.filter = "";
        filterBar.open = false;
        view.forceActiveFocus();
    }

    readonly property int iconSize: Files.listIconSizes[
        Math.max(0, Math.min(Files.zoomMax, pane.zoom))]
    readonly property int tileSize: Files.gridTileSizes[
        Math.max(0, Math.min(Files.zoomMax, pane.zoom))]

    function setZoom(z) {
        var v = Math.max(0, Math.min(Files.zoomMax, z));
        if (v === pane.zoom)
            return;
        pane.zoom = v;
        Files.rememberView(pane.viewMode, v);
    }

    function setViewMode(m) {
        pane.viewMode = m;
        Files.rememberView(m, pane.zoom);
    }

    /// Cliccare la colonna su cui si sta già ordinando gira il verso: è quello
    /// che fa qualunque tabella, e nessuno lo ha mai dovuto imparare.
    function sortByColumn(by) {
        if (pane.sortBy === by)
            pane.sortDesc = !pane.sortDesc;
        else {
            pane.sortBy = by;
            // Nome e tipo si leggono dalla A alla Z; dimensione e data hanno
            // senso al contrario — «i più grossi» e «gli ultimi toccati» sono
            // le domande per cui si ordina per quelle due.
            pane.sortDesc = (by === "size" || by === "modified");
        }
        Files.rememberSort(pane.sortBy, pane.sortDesc);
    }

    // ── Lo sfondo della cartella ─────────────────────────────────────────
    //
    // GNOME 2 lo faceva e nessuno lo fa più. Giacomo, 12 agosto 2026: «ho
    // nostalgia dai tempi di GNOME 2, lo sfondo dietro le cartelle
    // personalizzabile».
    //
    // Non è nostalgia e basta: è memoria visiva. Si riconosce «Lavoro» prima
    // di leggerne il nome, e funziona meglio di qualunque etichetta.
    //
    // `{tipo: "tinta"|"immagine", valore: "#rrggbb"|"/percorso"}`, oppure
    // niente. Arriva insieme all'elenco, non con una domanda a parte: deve
    // essere già lì quando compaiono le icone.
    property var aspetto: null

    /// Quello che si disegna davvero: la scelta di chi usa il computer se
    /// c'è, altrimenti il motivo che la cartella si merita da sola.
    ///
    /// L'ordine conta: una scelta a mano deve poter TOGLIERE anche il motivo
    /// automatico, e per farlo si salva `{tipo: "niente"}` — che è diverso da
    /// «non ho mai scelto».
    readonly property var aspettoVero: {
        if (pane.aspetto && pane.aspetto.tipo === "niente")
            return null;
        if (pane.aspetto)
            return pane.aspetto;
        if (!Core.Ipc.get("files.sfondiAutomatici", true))
            return null;
        return Files.motivoPerCartella(pane.path);
    }


    /// Percorsi selezionati. Un array e non un indice: si opera su gruppi.
    property var selection: []
    property int cursor: 0

    /// Se il cursore si VEDE.
    ///
    /// Il cursore esiste sempre — la tastiera ha bisogno di un punto da cui
    /// partire — ma disegnarlo appena si apre una cartella faceva sembrare
    /// selezionato il primo file di ogni scheda. Segnalato da Giacomo il
    /// 12 agosto 2026: «quando apro il gestore file c'è sempre qualcosa di
    /// selezionato, e se apro un'altra scheda ogni scheda ha qualcosa di
    /// selezionato, ed è fastidioso».
    ///
    /// Si accende quando qualcuno il cursore lo muove davvero: una freccia,
    /// una battuta per cercare, un clic. Si spegne cambiando cartella,
    /// perché lì il cursore torna in cima da solo e nessuno gliel'ha chiesto.
    property bool cursoreMostrato: false

    // ── Trascinare ───────────────────────────────────────────────────────
    //
    // Giacomo, 12 agosto 2026: «voglio poter trascinare qualsiasi cosa come in
    // KDE, e lasciando mi chiede se copiare o spostare».
    //
    // Il trascinamento è quello VERO del sistema (`Drag.Automatic`): esce dalla
    // finestra, arriva agli altri programmi, e i file che arrivano da fuori
    // entrano qui. La prima versione usava il trascinamento interno di Qt —
    // funzionava fra i due riquadri e moriva sul bordo della finestra, ed è la
    // prima cosa che Giacomo ha provato a fare.
    //
    // Il prezzo è che si parla la lingua di tutti, `text/uri-list`, e non la
    // nostra: chi lascia non ci consegna un oggetto ma un elenco di indirizzi
    // `file://`. Per questo i bersagli leggono `drop.urls` e non `drop.source`.
    //
    // Chi trascina non è la cella ma il riquadro: le celle di una griglia
    // vengono distrutte appena escono dalla vista, e con loro sparirebbe il
    // trascinamento appena l'elenco scorre.
    property bool trascinando: false
    signal rilasciato(var sorgenti, string destinazione)

    /// ── Quello che si porta, sotto il dito ──────────────────────────────
    ///
    /// Fino al 28 settembre 2026 il trascinamento dava un'immagine solo per
    /// le fotografie («un'icona sbagliata è peggio di nessuna icona»): per
    /// tutto il resto sotto il puntatore non c'era niente, e il gesto sembrava
    /// non esistere. Giacomo: «voglio il trascinamento delle icone e cartelle
    /// anche nel file manager che manca da sempre» — funzionava, e non si
    /// vedeva. Adesso si fotografa la cella afferrata (icona e nome, com'è
    /// sullo schermo), come fa la scrivania, e l'immagine sta sotto il dito
    /// nel punto esatto in cui la si è presa (`hotSpot`). Con più file, sulla
    /// cella compare per il tempo della foto quanti sono.
    property string _targaSu: ""
    property int _targaQuante: 0
    property bool _preparando: false

    /// Per le prove: il centro dell'icona di `nome`, in coordinate della
    /// finestra, o null se non si vede. Chi prova un trascinamento deve
    /// sapere DOVE prendere e dove lasciare, e la griglia lo sa solo qui.
    function centroDi(nome) {
        var lista = pane.shown || [];
        for (var i = 0; i < lista.length; i++) {
            if (lista[i].name !== nome)
                continue;
            var cella = view.itemAtIndex(i);
            if (!cella)
                return null;
            return cella.mapToItem(null, cella.width / 2, cella.height / 2);
        }
        return null;
    }

    function iniziaTrascinamento(percorsi, dove, cella, presa) {

        if (percorsi.length === 0 || pane._preparando)
            return;
        fardello.percorsi = percorsi;
        fardello.x = dove.x;
        fardello.y = dove.y;
        if (cella) {
            pane._preparando = true;
            pane._targaSu = cella.modelData.path;
            pane._targaQuante = percorsi.length;
            cella.grabToImage(function (esito) {
                pane._targaSu = "";
                pane._preparando = false;
                // Tenuta viva per tutto il gesto: è un oggetto con un ciclo di
                // vita, non un indirizzo.
                fardello.fotografia = esito;
                fardello.Drag.imageSource = esito.url;
                fardello.Drag.hotSpot = presa || Qt.point(cella.width / 2, cella.height / 2);
                pane.trascinando = true;
            });
            return;
        }
        // ── Si accende e BASTA ───────────────────────────────────────────
        //
        // Qui c'era, subito sotto, `pane.trascinando = false;` con scritto
        // accanto «questa riga non torna finché qualcuno non lascia»:
        // `Drag.active = true` avrebbe fatto partire un ciclo di eventi suo,
        // e la riga dopo si sarebbe eseguita a gesto finito.
        //
        // Non è (più) vero, e misurarlo è stato l'unico modo di saperlo. Con
        // una traccia dentro questa funzione, il registro dice:
        //
        //     [TRASCINA] chiesto per 1 elementi
        //     [TRASCINA] Drag.active spento, il gesto e' finito
        //
        // una riga dietro l'altra, nello stesso istante. `Drag.active` torna
        // subito, e quello spegnimento **annullava il trascinamento un
        // battito dopo averlo acceso**: al compositore non arrivava nessuna
        // richiesta — zero, contate.
        //
        // Si spegne dove va spento: al rilascio del tasto
        // (`finisciTrascinamento`) o se qualcuno ci ruba il gesto
        // (`onCanceled`). Quelle due righe c'erano già e non servivano a
        // niente, perché arrivava prima questa.
        pane.trascinando = true;
    }

    function muoviTrascinamento(dove) {
        fardello.x = dove.x;
        fardello.y = dove.y;
    }

    /// Il rilascio del tasto sulla CELLA. Se nel frattempo è partito il
    /// trascinamento di sistema, qui non c'è niente da fare: quel gesto lo
    /// chiude `Drag.onDragFinished`, che è l'unico che sa davvero quando è
    /// finito. Spegnerlo da qui lo ANNULLEREBBE.
    function finisciTrascinamento() {
        if (pane.trascinando)
            return;
        pane.trascinando = false;
    }

    signal activated()                    // ha ricevuto il fuoco
    signal openRequested(string filePath) // doppio clic su un file
    /// Tasto destro dentro il riquadro. Senza un punto, di proposito.
    ///
    /// Ce l'aveva: `menuRequested(point where)`, e i tre punti che lo
    /// emettevano calcolavano ogni volta un `mapToGlobal(...)`. Nessuno lo
    /// leggeva — chi riceve chiama `openAtCursor()`, che chiede al compositore
    /// dov'è il puntatore (`menu/ContextMenu.qml`). Che fosse morto lo dichiara
    /// il terzo punto d'emissione, che passava un finto `Qt.point(0, 0)`: chi
    /// l'ha scritto sapeva già che non contava.
    signal menuRequested()
    signal closeRequested()               // la × in fondo al percorso
    /// È stato lasciato qualcosa che non era un file di questo computer.
    /// Chi riceve lo dice a schermo: vedi il perché sul `DropArea`.
    signal rilascioSenzaFile()

    /// Mostra la × che chiude la scheda. Falsa quando è rimasta una sola:
    /// un pulsante che chiude l'ultima cosa rimasta lasciando una finestra
    /// vuota è un pulsante che non doveva esserci.
    property bool canClose: false

    // ── Cronologia ───────────────────────────────────────────────────────
    property var history: []
    property int historyIndex: -1

    readonly property bool canGoBack: historyIndex > 0
    readonly property bool canGoForward: historyIndex >= 0
                                         && historyIndex < history.length - 1
    readonly property bool canGoUp: path !== "/" && path !== ""

    function navigate(to, record) {
        if (to === "")
            return;
        pane.path = to;
        pane.selection = [];
        pane.cursor = 0;
        pane.cursoreMostrato = false;
        pane.anchorIndex = -1;
        // Il filtro vale per la cartella in cui è stato scritto. Portarselo
        // dietro cambiando cartella vorrebbe dire arrivare in una cartella
        // piena e vederla quasi vuota, senza capire perché.
        if (pane.filter !== "")
            filterInput.text = "";
        if (record !== false) {
            var h = pane.history.slice(0, pane.historyIndex + 1);
            h.push(to);
            // La cronologia non serve oltre il centinaio di passi, e tenerla
            // illimitata la fa crescere per tutta la sessione.
            if (h.length > 100)
                h.shift();
            pane.history = h;
            pane.historyIndex = h.length - 1;
        }
        reload();
    }

    function goBack() {
        if (!canGoBack)
            return;
        pane.historyIndex--;
        navigate(pane.history[pane.historyIndex], false);
    }

    function goForward() {
        if (!canGoForward)
            return;
        pane.historyIndex++;
        navigate(pane.history[pane.historyIndex], false);
    }

    /// Mostra o nasconde i file nascosti, e lo ricorda. Il pulsante e Ctrl+H.
    function commutaNascosti() {
        Core.Ipc.setSetting("files.showHidden", !pane.showHidden);
        pane.showHidden = !pane.showHidden;
        pane.reload();
    }

    function goUp() {
        if (!canGoUp)
            return;
        var p = pane.path;
        if (p.charAt(p.length - 1) === "/")
            p = p.substring(0, p.length - 1);
        var cut = p.lastIndexOf("/");
        navigate(cut <= 0 ? "/" : p.substring(0, cut));
    }

    /// Vero mentre il percorso è un campo di testo invece che una fila di
    /// briciole. Vedi `Briciole.qml`.
    property bool scrivendoPercorso: false

    function apriPercorsoAMano() {
        pane.activated();
        pane.scrivendoPercorso = true;
        pathInput.forceActiveFocus();
    }

    function reload() {
        Core.Ipc.fsList(pane.path, pane.showHidden, pane.paneId);
    }

    onPathChanged: {
        pane.scrivendoPercorso = false;
        // Cambiando cartella la ricerca non ha più senso: cercava DENTRO
        // quella di prima, e lasciarla accesa mostrerebbe risultati di un
        // posto in cui non si è più.
        pane.fermaRicerca();
    }

    Connections {
        target: Core.Ipc
        // ── Quello che cambia da fuori ───────────────────────────────────
        //
        // Lo scaricamento di Chrome che arriva in «Scaricati», un file salvato
        // da un altro programma, uno cancellato dal terminale: il demone guarda
        // la cartella e lo dice, e il riquadro rilegge come dopo una copia
        // sua. Prima non si vedeva niente finché non si rientrava.
        function onCartellaCambiata(info) {
            if (info.pane === pane.paneId && info.path === pane.path)
                pane.reload();
        }

        function onFileListingReceived(listing) {
            if (listing.pane !== pane.paneId)
                return;
            // ── La stessa cartella riletta non torna in cima ─────────────
            //
            // Un elenco nuovo rifà la griglia, e la griglia riparte
            // dall'alto. Entrando in una cartella è giusto; rileggendo quella
            // in cui si è — un file arrivato da fuori, una copia finita —
            // vuol dire perdere il punto a cui si era arrivati, e durante uno
            // scaricamento saltare in cima a ogni secondo.
            var stessa = pane._elencoDi === pane.path;
            var y = view.contentY;
            pane._elencoDi = pane.path;
            pane.entries = listing.entries || [];
            if (stessa && y > 0)
                Qt.callLater(function () {
                    view.contentY = Math.max(0, Math.min(y, view.contentHeight - view.height));
                });
            if (pane.daSelezionare !== "")
                Qt.callLater(pane._selezionaArrivato);
            // Com'è già ordinato quello che è arrivato. Se combacia con
            // l'ordine chiesto, non c'è niente da riordinare: vedi `_ordinate`.
            pane.ordineDalDemone = listing.ordinatoPer || "";
            pane.contrarioDalDemone = listing.ordinatoAlContrario === true;
            pane.error = listing.error || "";
            pane.aspetto = listing.aspetto || null;
            // `!== false` e non `=== true`: un demone vecchio non manda questo
            // campo, e in quel caso si continua come prima invece di spegnere
            // metà del programma.
            pane.scrivibile = listing.scrivibile !== false;

            // ── Una cartella che non si legge affatto ────────────────────
            //
            // `/root` è `drwx------`: il demone gira come te e da lì non
            // legge niente. Prima restava una cartella vuota con un messaggio
            // d'errore, e la modalità amministratore non serviva a niente
            // perché non si arrivava nemmeno a vedere cosa c'era dentro.
            //
            // Se la modalità è accesa, si richiede la stessa cartella
            // all'aiutante. Non si accende da sola: accendere i privilegi di
            // root in risposta a un errore vorrebbe dire che basta entrare
            // nella cartella giusta per farli comparire.
            if (pane.amministratore && pane.entries.length === 0
                && pane.error !== "") {
                pane.attesaRadice = pane.path;
                Core.Ipc.radiceElenca(pane.path);
            }
        }

        /// L'elenco letto dall'aiutante di root.
        function onRadiceElenco(info) {
            if (!info || String(info.path || "") !== pane.attesaRadice)
                return;
            pane.attesaRadice = "";
            if (info.ok !== true) {
                // Si tiene l'errore che c'era: quello dell'aiutante è
                // «annullato», e sostituirlo cancellerebbe il motivo vero.
                if (info.annullato !== true)
                    pane.error = String(info.error || pane.error);
                return;
            }
            pane.entries = info.entries || [];
            pane.error = "";
            pane.ordineDalDemone = "";
            pane.contrarioDalDemone = false;
            // Resta «non scrivibile»: il cartello rosso «amministratore»
            // dipende da questo, e da root si scrive comunque attraverso
            // l'aiutante. Vedi `operaComeRoot` in FileManager.
            pane.scrivibile = false;
        }
        // Dopo una copia, una rinomina o un cestinamento il contenuto è
        // cambiato: l'elenco si riaggiorna da solo invece di aspettare che
        // qualcuno prema un tasto e si chieda perché non vede il file nuovo.
        function onFileResultReceived() { pane.reload(); }

        // Il gestore file adesso è un processo suo, e un processo nasce PRIMA
        // di essersi collegato al demone: la prima richiesta dell'elenco parte
        // nell'istante in cui la finestra si costruisce e cade nel vuoto —
        // «Demone non raggiungibile, messaggio scartato: fs_list». Restava una
        // cartella vuota che non si riempiva mai, e sembrava una cartella
        // vuota davvero. Appena il collegamento c'è, si richiede.
        function onConnectedChanged() {
            if (Core.Ipc.connected && pane.path !== "")
                pane.reload();
        }
        function onFileJobChanged(job) {
            if (job.state === "done" || job.state === "cancelled")
                pane.reload();
        }
    }

    // ── Selezione ────────────────────────────────────────────────────────

    /// Da dove parte una selezione a intervallo. Senza un punto fermo, lo
    /// Shift+freccia ripetuto prendeva ogni volta solo le due righe attorno al
    /// cursore e lasciava indietro quelle già prese: si selezionavano dieci
    /// righe e ne restavano due. L'ancora è la riga da cui si è partiti, e non
    /// si muove finché non si clicca da un'altra parte.
    property int anchorIndex: -1

    function isSelected(p) {
        return pane.selection.indexOf(p) !== -1;
    }

    function selectOnly(p) {
        pane.selection = [p];
    }

    // ── «Mostra nella cartella» ──────────────────────────────────────────
    //
    // Un altro programma (Chrome, dopo uno scaricamento) chiede di vedere UN
    // file: si apre la sua cartella e lo si trova già scelto. La scelta si
    // può fare solo quando l'elenco è arrivato, quindi il file si ricorda qui.
    property string daSelezionare: ""

    function mostraFile(file) {
        var f = String(file || "");
        if (f === "")
            return;
        var i = f.lastIndexOf("/");
        pane.navigate(i > 0 ? f.substring(0, i) : "/");
        pane.daSelezionare = f;
    }

    function _selezionaArrivato() {
        var f = pane.daSelezionare;
        if (f === "")
            return;
        pane.daSelezionare = "";
        for (var i = 0; i < pane.shown.length; i++) {
            if (pane.shown[i].path !== f)
                continue;
            pane.selectOnly(f);
            pane.cursor = i;
            pane.anchorIndex = i;
            pane.cursoreMostrato = true;
            view.positionViewAtIndex(i, GridView.Contain);
            return;
        }
    }

    function toggleSelection(p) {
        var s = pane.selection.slice();
        var i = s.indexOf(p);
        if (i === -1)
            s.push(p);
        else
            s.splice(i, 1);
        pane.selection = s;
    }

    function extendTo(index) {
        if (pane.shown.length === 0)
            return;
        if (pane.anchorIndex < 0 || pane.anchorIndex >= pane.shown.length)
            pane.anchorIndex = pane.cursor;
        var from = Math.min(pane.anchorIndex, index);
        var to = Math.max(pane.anchorIndex, index);
        var s = [];
        for (var i = Math.max(0, from); i <= to && i < pane.shown.length; i++)
            s.push(pane.shown[i].path);
        pane.selection = s;
    }

    function selectAll() {
        var s = [];
        for (var i = 0; i < pane.shown.length; i++)
            s.push(pane.shown[i].path);
        pane.selection = s;
    }

    /// Quello su cui agire: la selezione, oppure la riga sotto il cursore se
    /// non è stato selezionato niente. Senza questo, premere Canc senza aver
    /// prima cliccato non farebbe nulla e sembrerebbe rotto.
    function operands() {
        if (pane.selection.length > 0)
            return pane.selection;
        // Se il cursore non si vede, non c'è niente su cui agire. Prima si
        // ripiegava comunque sulla riga sotto il cursore: con il cursore
        // invisibile, premere Canc appena aperta una cartella avrebbe buttato
        // nel cestino il primo file senza che niente lo indicasse.
        if (!pane.cursoreMostrato)
            return [];
        var e = pane.shown[pane.cursor];
        return e ? [e.path] : [];
    }


    function openCursor() {
        var e = pane.shown[pane.cursor];
        if (!e)
            return;
        if (e.isDir)
            pane.navigate(e.path);
        else
            pane.openRequested(e.path);
    }

    // ── Aspetto ──────────────────────────────────────────────────────────

    /// Vero quando questo è l'unico riquadro aperto.
    property bool solo: true

    /// L'esito del confronto fra questo riquadro e l'altro, per percorso.
    /// Vuoto quando non si sta confrontando. Lo calcola il gestore file, che
    /// è l'unico che vede tutti e due i riquadri.
    property var esitoConfronto: ({})

    // ── La scatola dentro la scatola ─────────────────────────────────────
    //
    // Il riquadro aveva sempre il suo bordo arrotondato e il suo fondo più
    // scuro. Con DUE riquadri serve — è così che si vede dove finisce uno e
    // comincia l'altro, e quale dei due ha il fuoco. Con UNO solo è una
    // cornice dentro una cornice: la finestra ha già il suo bordo a due
    // millimetri di distanza, e in mezzo resta una striscia di niente che
    // non separa niente.
    //
    // È la ragione per cui il gestore file sembrava «una tabella dentro una
    // scatola» invece di un programma: la lista non arrivava mai ai bordi.
    //
    // In Liquid DE il riquadro è un'isola come la colonna dei posti, anche
    // quando è solo: due isole affiancate sul fondo della finestra, con lo
    // stesso vuoto e lo stesso raggio, non una cornice dentro una cornice.
    // Il bordo colorato resta per dire quale riquadro ha il fuoco quando
    // sono più d'uno.
    Rectangle {
        anchors.fill: parent
        // Il fondo non si toglie mai: senza, sotto l'elenco resterebbe il
        // vetro nudo della finestra e il terminale dietro si leggerebbe
        // ATTRAVERSO i nomi dei file.
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.lettura
        border.width: Theme.Effects.hairline
        // Il riquadro col fuoco si riconosce dal bordo. Non dal colore di
        // sfondo: due sfondi diversi affiancati sembrano due programmi.
        border.color: pane.focused && !pane.solo ? Qt.alpha(Theme.Colors.accent, 0.55)
                                                 : Theme.Colors.edge
        Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function(m) {
            pane.activated();
            if (m.button === Qt.RightButton)
                pane.menuRequested();
            m.accepted = false;
        }
    }

    // ── Percorso ─────────────────────────────────────────────────────────

    Item {
        id: pathBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space3
        height: 34

        // Le tre frecce stanno in una capsula loro: sono un gruppo solo.
        Rectangle {
            anchors.fill: navRow
            anchors.margins: -2
            radius: height / 2
            color: Theme.Colors.raised
        }

        Row {
            id: navRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Repeater {
                model: [
                    { "id": "back",    "icon": "back" },
                    { "id": "forward", "icon": "back" },
                    { "id": "up",      "icon": "chevronUp" }
                ]

                delegate: Rectangle {
                    id: navBtn
                    required property var modelData

                    readonly property bool usable:
                        modelData.id === "back" ? pane.canGoBack
                      : modelData.id === "forward" ? pane.canGoForward
                      : pane.canGoUp

                    width: 30; height: 30
                    radius: height / 2
                    color: navMouse.containsMouse && usable ? Theme.Colors.hover
                                                            : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 15; height: 15
                        name: navBtn.modelData.icon
                        color: navBtn.usable ? Theme.Colors.textMuted : Theme.Colors.textFaint
                        // «Indietro» senza niente dietro non si può premere:
                        // deve vedersi anche con le icone classiche.
                        spenta: !navBtn.usable
                        opacity: navBtn.usable ? 1 : 0.4
                        // «Avanti» è «indietro» specchiato: un tracciato solo
                        // per due frecce che devono essere identiche.
                        rotation: navBtn.modelData.id === "forward" ? 180 : 0
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: navBtn.usable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pane.activated();
                            switch (navBtn.modelData.id) {
                            case "back":    pane.goBack(); break;
                            case "forward": pane.goForward(); break;
                            case "up":      pane.goUp(); break;
                            }
                        }
                    }
                }
            }
        }

        // Percorso scrivibile: cliccarlo lo rende un campo di testo. Le
        // briciole di pane sono comode per risalire, ma quando si sa già dove
        // andare scrivere l'indirizzo è più veloce di qualunque clic.
        //
        // Il testo NON è mai preselezionato. Un campo che si presenta con
        // tutto evidenziato dice «stai per riscrivere tutto» anche quando lo
        // hai solo sfiorato, e in una finestra con più schede aperte due
        // percorsi entrambi evidenziati non lasciano capire su quale si sta
        // per agire. Si seleziona tutto solo se lo si chiede, con Ctrl+A o
        // con un triplo clic — come in qualunque campo di testo.
        Rectangle {
            id: pathBox
            anchors.left: navRow.right
            anchors.leftMargin: Theme.Effects.space2
            anchors.right: closeTab.visible ? closeTab.left : parent.right
            anchors.rightMargin: closeTab.visible ? Theme.Effects.space1 : 0
            anchors.verticalCenter: parent.verticalCenter
            height: 34
            radius: height / 2
            // Una capsula sempre, più chiara quando ci si scrive dentro.
            color: pathInput.activeFocus ? Theme.Colors.raisedHigh : Theme.Colors.raised
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            // ── Le briciole, e sotto il testo ────────────────────────────
            //
            // Si vede una fila di pezzi cliccabili; cliccando l'ultimo, o lo
            // spazio vuoto dopo, o premendo Ctrl+L, la fila lascia il posto al
            // campo di testo con dentro il percorso intero.
            //
            // Sono due modi per due gesti diversi, e servono tutti e due:
            // «risali di due cartelle» si fa toccando un pezzo, «vai in
            // /mnt/disco2/lavoro» si fa scrivendo. Prima c'era solo il
            // secondo, ed era il motivo per cui risalire costava tre gesti.
            Briciole {
                // Le briciole sono la strada più corta per risalire: si
                // prende un file e lo si molla due cartelle più su.
                onRilasciato: function (sorgenti, dove) {
                    pane.rilasciato(sorgenti, dove);
                }
                id: briciole
                anchors.fill: parent
                anchors.leftMargin: Theme.Effects.space3
                anchors.rightMargin: Theme.Effects.space3
                visible: !pane.scrivendoPercorso
                percorso: pane.path
                attivo: pane.focused
                onAndare: function (dove) {
                    pane.activated();
                    pane.navigate(dove);
                }
                onScrivere: pane.apriPercorsoAMano()
            }

            TextInput {
                id: pathInput
                anchors.fill: parent
                anchors.leftMargin: Theme.Effects.space2
                anchors.rightMargin: Theme.Effects.space2
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                visible: pane.scrivendoPercorso
                text: pane.path
                color: pane.focused ? Theme.Colors.text : Theme.Colors.textFaint
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
                selectedTextColor: Theme.Colors.text
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
                selectByMouse: true

                onAccepted: {
                    pane.activated();
                    pane.navigate(text);
                    view.forceActiveFocus();
                }
                onActiveFocusChanged: {
                    if (activeFocus) {
                        pane.activated();
                        // Il cursore in fondo, niente selezione: si arriva qui
                        // per aggiungere un pezzo di percorso molto più spesso
                        // che per buttarlo via.
                        deselect();
                        cursorPosition = text.length;
                    } else {
                        text = pane.path;
                        deselect();
                        // Uscendo si torna alle briciole: un campo di testo
                        // lasciato aperto e spento è il modo in cui una barra
                        // degli indirizzi sembra rotta.
                        pane.scrivendoPercorso = false;
                    }
                }

                Keys.onEscapePressed: {
                    pathInput.text = pane.path;
                    pane.scrivendoPercorso = false;
                    view.forceActiveFocus();
                }
            }
        }

        // La × che chiude la scheda, in fondo al percorso: sta dove sta la
        // chiusura di una finestra, all'estremità destra della sua barra.
        Rectangle {
            id: closeTab
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24
            radius: Theme.Effects.radiusXS
            visible: pane.canClose
            color: closeMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.20)
                                            : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Ui.Icon {
                anchors.centerIn: parent
                width: 12; height: 12
                name: "close"
                color: closeMouse.containsMouse ? Theme.Colors.danger
                                                : Theme.Colors.textFaint
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pane.closeRequested()
            }
        }
    }

    // ── Colonne ──────────────────────────────────────────────────────────
    //
    // Larghezze condivise fra l'intestazione e le righe: sono la stessa
    // tabella, e due numeri scritti in due posti diversi si scollano alla
    // prima modifica.

    /// Quanto spazio prende il nome sotto una piastrella: due righe, sempre lo
    /// stesso, anche quando il nome è corto. Un'altezza che dipende dal nome
    /// farebbe piastrelle di altezze diverse sulla stessa riga.
    readonly property int gridNameHeight: 36
    readonly property int gridPadding: Theme.Effects.space2

    readonly property int sizeColumn: 74
    readonly property int timeColumn: 84
    /// La data sparisce quando il riquadro è stretto. Con quattro schede
    /// aperte ogni riquadro è largo un quarto di finestra, e lì la data si
    /// mangia lo spazio del nome — che è l'unica colonna indispensabile.
    readonly property bool showTime: pane.width > 430

    // ── Cercare dentro la cartella ───────────────────────────────────────
    //
    // Una cartella di Scaricati con quattrocento file si guarda scorrendo, e
    // scorrendo non si trova niente: si trova solo quello che si stava già
    // guardando. Ctrl+F apre questa riga, e da lì in poi l'elenco mostra
    // soltanto ciò che contiene quello che si scrive.
    //
    // Filtra, non cerca: guarda solo QUESTA cartella e non entra nelle
    // sottocartelle. È una promessa che si mantiene subito, mentre si scrive,
    // e una ricerca che scende ricorsivamente non potrebbe farlo.

    Item {
        id: filterBar

        property bool open: false

        anchors.top: pathBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space2
        anchors.rightMargin: Theme.Effects.space2
        height: filterBar.open ? 30 : 0
        visible: height > 0
        clip: true
        Behavior on height { NumberAnimation { duration: Theme.Motion.instant } }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 4
            radius: Theme.Effects.radiusXS
            color: Theme.Colors.raised
            border.width: 1
            border.color: filterInput.activeFocus
                          ? Qt.alpha(Theme.Colors.accent, 0.45)
                          : "transparent"

            Ui.Icon {
                id: filterIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                width: 13; height: 13
                name: "search"
                color: Theme.Colors.textFaint
                alwaysDrawn: true
            }

            TextInput {
                id: filterInput
                anchors.left: filterIcon.right
                anchors.leftMargin: Theme.Effects.space2
                anchors.right: filterCount.left
                anchors.rightMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                text: pane.filter
                color: Theme.Colors.text
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
                selectedTextColor: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
                selectByMouse: true

                onTextChanged: {
                    pane.filter = text;
                    // Il cursore torna in cima a ogni battuta: la prima voce
                    // rimasta è quella che si sta cercando, e premendo Invio
                    // si apre quella.
                    pane.cursor = 0;
                    pane.cursoreMostrato = true;
                    pane.anchorIndex = -1;
                }

                // ── Invio: apre, oppure cerca ────────────────────────
                //
                // Se il filtro ha trovato qualcosa, Invio apre quello — è il
                // gesto di sempre e non si tocca.
                //
                // Se non ha trovato NIENTE, Invio non avrebbe niente da
                // aprire: è il momento esatto in cui uno pensa «allora non è
                // qui», ed è lì che la ricerca nelle sottocartelle serve. Non
                // si impara: capita.
                //
                // Ctrl+Invio la fa partire comunque, anche con dei risultati
                // sotto gli occhi.
                Keys.onEscapePressed: {
                    if (pane.cercando)
                        pane.fermaRicerca();
                    else
                        pane.stopFilter();
                }
                Keys.onReturnPressed: function (e) {
                    if ((e.modifiers & Qt.ControlModifier) || pane.shown.length === 0) {
                        pane.cercaSotto();
                        return;
                    }
                    view.forceActiveFocus();
                    pane.openCursor();
                }
                Keys.onDownPressed: view.forceActiveFocus()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: filterInput.text === ""
                    text: Core.Strings.lang === "it" ? "Filtra questa cartella…"
                                                     : "Filter this folder…"
                    color: Theme.Colors.textFaint
                    font: filterInput.font
                }
            }

            // ── Il conto, e l'offerta di cercare più a fondo ──────────────
            //
            // Quando il filtro non trova niente qui dentro, il numero rosso
            // dice solo che non c'è. Dirlo e basta è la parte facile: la parte
            // utile è dire che si può guardare più in là, e come.
            Text {
                id: filterCount
                anchors.right: filterClose.left
                anchors.rightMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                visible: pane.filter !== ""
                text: {
                    var it = Core.Strings.lang === "it";
                    if (pane.cercando) {
                        if (!pane.ricercaFinita)
                            return (it ? "cerco… " : "searching… ") + pane.shown.length;
                        if (pane.ricercaTroppi)
                            return (it ? "oltre " : "over ") + pane.shown.length;
                        return pane.shown.length + (it ? " trovati" : " found");
                    }
                    if (pane.shown.length === 0)
                        return it ? "niente qui · ↵ cerca dappertutto"
                                  : "nothing here · ↵ search everywhere";
                    return pane.shown.length + " / " + pane.entries.length;
                }
                color: pane.cercando ? Theme.Colors.accent
                     : pane.shown.length === 0 ? Theme.Colors.warning
                     : Theme.Colors.textFaint
                font.family: pane.shown.length === 0 && !pane.cercando
                             ? Theme.Typography.fontDisplay
                             : Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                id: filterClose
                anchors.right: parent.right
                anchors.rightMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                radius: Theme.Effects.radiusXS
                color: filterCloseMouse.containsMouse ? Theme.Colors.hover
                                                      : "transparent"

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 11; height: 11
                    name: "close"
                    color: Theme.Colors.textFaint
                    alwaysDrawn: true
                }

                MouseArea {
                    id: filterCloseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.stopFilter()
                }
            }
        }
    }

    // ── Intestazione delle colonne ───────────────────────────────────────

    // ── Dove sei, scritto grande ─────────────────────────────────────────
    //
    // Sopra c'erano le briciole, alte dodici pixel, in mezzo a due file di
    // pulsanti. Dicono la strada, ma non dicono DOVE SEI: per saperlo si
    // doveva leggere l'ultimo pezzo di una riga piccola.
    //
    // Ogni programma che si guarda con piacere dice in grande il nome della
    // cosa che sta mostrando — una cartella, un album, una casella di posta.
    // È quello che dà a una finestra la sensazione di essere «da qualche
    // parte» invece che di essere un elenco.
    //
    // Accanto, quante cose ci sono. Non nella barra di stato in fondo, dove
    // per leggerlo bisogna guardare da un'altra parte: qui, dove si sta già
    // guardando.
    Item {
        id: titolo
        anchors.top: filterBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.rightMargin: Theme.Effects.space3
        anchors.topMargin: Theme.Effects.space2
        height: 34

        Text {
            id: nomeCartella
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - contaRoba.width
                            - Theme.Effects.space3)
            elide: Text.ElideMiddle
            text: {
                // In ricerca il titolo dice cosa si sta cercando, non dove si
                // è: la cartella la dicono già le briciole due righe sopra, e
                // quello che si ha in testa in quel momento è la parola.
                if (pane.cercando)
                    return "«" + pane.filter + "»";
                var p = String(pane.path || "");
                if (p === "/" || p === "")
                    return "/";
                var casa = Quickshell.env("HOME") || "";
                if (p === casa)
                    return "Home";
                return p.split("/").pop();
            }
            color: pane.focused ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeLG
            font.weight: Theme.Typography.weightSemiBold
            font.letterSpacing: Theme.Typography.trackingTitle
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        }

        Text {
            id: contaRoba
            anchors.left: nomeCartella.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.baseline: nomeCartella.baseline
            text: {
                var n = pane.shown.length;
                var it = Core.Strings.lang === "it";
                // In ricerca «50 di 5» non vuol dire niente: il secondo numero
                // è quanto c'è in QUESTA cartella, e la ricerca guarda altrove.
                if (pane.cercando) {
                    if (!pane.ricercaFinita)
                        return it ? "cerco in tutte le sottocartelle…"
                                  : "searching every subfolder…";
                    if (n === 0)
                        return it ? "niente, da nessuna parte"
                                  : "nothing, anywhere";
                    return it ? (n === 1 ? "1 trovato" : n + " trovati")
                              : (n === 1 ? "1 found" : n + " found");
                }
                if (pane.filter !== "")
                    return it ? n + " di " + pane.entries.length
                              : n + " of " + pane.entries.length;
                if (n === 0)
                    return "";
                return it ? (n === 1 ? "1 elemento" : n + " elementi")
                          : (n === 1 ? "1 item" : n + " items");
            }
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }

        // ── «Sola lettura» ───────────────────────────────────────────────
        //
        // Accanto al nome della cartella, dove si guarda per sapere dove si è.
        // Non è un avviso e non lampeggia: è un'etichetta, come «12 elementi».
        //
        // Serve perché senza di lei una cartella di sistema è
        // indistinguibile da una tua: stessi comandi, stesse icone, stesso
        // tutto, e il rifiuto arriva solo dopo aver premuto. Le voci che non
        // si possono usare adesso spariscono (vedi `paneMenuItems`), ma un
        // comando che manca non spiega perché manca — questa sì.
        //
        // ── E perché NON si vede insieme ad «amministratore» ─────────────
        //
        // Perché fino al 2 settembre 2026 si vedevano tutti e due, e uno
        // copriva l'altro. Erano ancorati allo stesso punto — `contaRoba.right`
        // con lo stesso margine — e le due condizioni si sovrappongono: in
        // modalità amministratore, dentro una cartella non scrivibile, erano
        // veri entrambi.
        //
        // Giacomo, guardandolo: «viene coperto dalla scritta amministratore e
        // quindi non si capisce cosa c'è scritto». È la stessa famiglia delle
        // due «cartella vuota» sovrapposte: due oggetti validi, nessun errore
        // da nessuna parte, e si vede solo guardando lo schermo.
        //
        // Non si affiancano: si SOSTITUISCONO. «Sola lettura» e
        // «amministratore» dicono due cose che non stanno insieme — la prima è
        // «qui non puoi scrivere», la seconda è «qui adesso puoi». Mostrarle
        // accanto vorrebbe dire un cartello che si contraddice.
        Rectangle {
            id: solaLettura
            anchors.left: contaRoba.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: nomeCartella.verticalCenter
            visible: !pane.scrivibile && !pane.amministratore
            width: visible ? solaLetturaTesto.implicitWidth
                             + Theme.Effects.space2 * 2 : 0
            height: 20
            radius: Theme.Effects.radiusXS
            color: Qt.alpha(Theme.Colors.warning, 0.14)
            border.width: Theme.Effects.hairline
            border.color: Qt.alpha(Theme.Colors.warning, 0.4)

            Text {
                id: solaLetturaTesto
                anchors.centerIn: parent
                text: Core.Strings.lang === "it" ? "sola lettura" : "read only"
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.weight: Theme.Typography.weightMedium
            }
        }

        // ── Quando si sta lavorando da amministratore ─────────────────────
        //
        // Deve VEDERSI, e per questo è un cartello e non un'icona: in modalità
        // amministratore un clic sul pulsante sbagliato cancella un file di
        // sistema, e polkit non richiede la password a ogni gesto. La
        // differenza fra «sto guardando» e «sto lavorando da root» non può
        // stare solo nella memoria di chi guarda.
        //
        // Rosso e non giallo: il giallo qui accanto vuol già dire «sola
        // lettura», che è la situazione tranquilla.
        Rectangle {
            id: daRoot
            anchors.left: contaRoba.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: nomeCartella.verticalCenter
            visible: pane.amministratore && !pane.scrivibile
            width: visible ? daRootTesto.implicitWidth
                             + Theme.Effects.space2 * 2 : 0
            height: 20
            radius: Theme.Effects.radiusXS
            color: Qt.alpha(Theme.Colors.danger, 0.18)
            border.width: Theme.Effects.hairline
            border.color: Qt.alpha(Theme.Colors.danger, 0.55)

            Text {
                id: daRootTesto
                anchors.centerIn: parent
                text: Core.Strings.lang === "it" ? "amministratore"
                                                 : "administrator"
                color: Theme.Colors.danger
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.weight: Theme.Typography.weightSemiBold
            }
        }
    }

    Item {
        id: header
        anchors.top: titolo.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space2
        anchors.rightMargin: Theme.Effects.space2
        height: visible ? 22 : 0
        // Solo in elenco: in griglia non ci sono colonne da intitolare, e
        // l'ordinamento si cambia dal pulsante in basso.
        visible: pane.viewMode === "list"

        Repeater {
            model: [
                { "id": "name",     "it": "Nome",       "en": "Name" },
                { "id": "size",     "it": "Dimensione", "en": "Size" },
                { "id": "modified", "it": "Modificato", "en": "Modified" }
            ]

            delegate: Rectangle {
                id: col
                required property var modelData

                readonly property bool active: pane.sortBy === col.modelData.id
                readonly property bool isName: col.modelData.id === "name"
                readonly property bool isSize: col.modelData.id === "size"

                visible: !(col.modelData.id === "modified" && !pane.showTime)

                x: col.isName
                   ? 0
                   : (col.isSize
                      ? header.width - pane.sizeColumn
                        - (pane.showTime ? pane.timeColumn : 0)
                      : header.width - pane.timeColumn)
                width: col.isName
                       ? Math.max(40, header.width - pane.sizeColumn
                                      - (pane.showTime ? pane.timeColumn : 0))
                       : (col.isSize ? pane.sizeColumn : pane.timeColumn)
                height: 20
                radius: Theme.Effects.radiusXS
                color: colMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    // Nome a sinistra, numeri a destra: le colonne di numeri
                    // si leggono allineate a destra, sempre.
                    anchors.left: col.isName ? parent.left : undefined
                    anchors.leftMargin: col.isName
                                        ? Theme.Effects.space2 + pane.iconSize
                                          + Theme.Effects.space2
                                        : 0
                    anchors.right: col.isName ? undefined : parent.right
                    anchors.rightMargin: col.isName ? 0 : Theme.Effects.space2
                    spacing: 3

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Core.Strings.lang === "it" ? col.modelData.it
                                                         : col.modelData.en
                        color: col.active ? Theme.Colors.textMuted
                                          : Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    Ui.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9
                        visible: col.active
                        name: "chevron"
                        thickness: 2.2
                        color: Theme.Colors.accent
                        rotation: pane.sortDesc ? 0 : 180
                    }
                }

                MouseArea {
                    id: colMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pane.activated();
                        pane.sortByColumn(col.modelData.id);
                    }
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.Colors.edge
        }
    }

    // ── Elenco ───────────────────────────────────────────────────────────
    //
    // Una vista sola per tutt'e due le visuali, e non due viste che si
    // scambiano il posto. Una griglia a una colonna sola È un elenco: tenerne
    // due significherebbe scrivere due volte la selezione, il cursore, il
    // doppio clic e il menu del tasto destro — e trovarsi con un elenco che sa
    // fare una cosa che la griglia non sa, senza che nessuno l'abbia deciso.

    // Dove si può lasciare. Uno solo per riquadro: la cartella sotto il
    // puntatore se è una cartella, altrimenti il riquadro stesso.
    // ── Dove si può lasciare ──────────────────────────────────────────────
    //
    // Su TUTTO il riquadro, non solo sull'elenco.
    //
    // Prima era `anchors.fill: view`, cioè la sola lista dei file. Le briciole
    // del percorso, la barra di stato, i margini intorno — un buon terzo di
    // quello che a occhio è «la cartella» — non prendevano niente: si mollava
    // il file lì sopra e non succedeva nulla, senza un motivo visibile. Un
    // bersaglio che si vede più grande di quello che è, è un bersaglio che
    // sbaglia chi lo usa, non chi l'ha disegnato.
    //
    // Le coordinate però restano quelle dell'elenco: per sapere su quale
    // cartella sta il dito bisogna passare da `view`, che dentro il riquadro è
    // spostata e più piccola. Senza la conversione l'evidenziazione indicherebbe
    // la riga sbagliata — e la roba finirebbe dove indicava.
    DropArea {
        id: bersaglio
        anchors.fill: parent
        keys: ["minerva/file", "text/uri-list"]

        /// L'indice della cartella evidenziata, o -1. Serve a far vedere DOVE
        /// finirà la roba: senza, lasciare sopra una cartella o accanto a essa
        /// sono due gesti identici con due esiti diversi.
        property int sopra: -1

        function _sotto(x, y) {
            var p = view.mapFromItem(bersaglio, x, y);
            if (p.x < 0 || p.y < 0 || p.x > view.width || p.y > view.height)
                return -1;
            var i = view.indexAt(p.x + view.contentX, p.y + view.contentY);
            var e = pane.shown[i];
            return (e && e.isDir) ? i : -1;
        }

        onPositionChanged: function (d) { bersaglio.sopra = bersaglio._sotto(d.x, d.y); }
        onExited: bersaglio.sopra = -1
        onDropped: function (d) {
            var dest = pane.path;
            var e = pane.shown[bersaglio.sopra];
            if (e && e.isDir)
                dest = e.path;
            bersaglio.sopra = -1;
            var sorgenti = (d.source && d.source.percorsi)
                           ? d.source.percorsi
                           : Files.percorsiDaUrl(d.urls);
            if (sorgenti.length > 0)
                pane.rilasciato(sorgenti, dest);
            else
                // ── Il rilascio che non portava niente ────────────────────
                //
                // `percorsiDaUrl` tiene solo ciò che comincia per `file://` e
                // butta via il resto senza dirlo, mentre qui si accettava il
                // rilascio comunque. Trascinando un'immagine da una pagina web
                // — che arriva come `https://`, non come file — il gesto
                // riusciva, il puntatore diceva di sì, e non succedeva niente:
                // il modo peggiore di rifiutare, perché sembra un guasto del
                // programma invece di una cosa che non si può fare.
                pane.rilascioSenzaFile();
            d.accept();
        }
    }

    // Lo sfondo di questa cartella. Sta dietro le icone e non prende clic.
    //
    // Quattro forme, e ognuna ha una ragione diversa per esserci:
    //
    //   tinta      una parete di colore. La più semplice, e quella che si
    //              riconosce da più lontano.
    //   vetro      la stessa tinta ma come luce: sfuma dall'alto in basso e
    //              non pesa. Per chi vuole un accento e non un cartellone.
    //   motivo     icone sparse, del tema di Minerva, nella tinta scelta:
    //              note su Musica, fogli su Documenti. È quello che le
    //              cartelle note prendono da sole.
    //   immagine   una foto qualsiasi.
    //
    // L'opacità non è gusto: sopra ci vanno i nomi dei file, e un fondo
    // troppo acceso li mangia. È lo stesso errore che avevamo già fatto col
    // vetro della barra, e stavolta i numeri sono scelti guardando.
    Item {
        id: sfondo
        anchors.fill: view
        visible: pane.aspettoVero !== null
        clip: true

        readonly property var a: pane.aspettoVero
        readonly property string tipo: sfondo.a ? sfondo.a.tipo : ""
        readonly property color tinta: (sfondo.a && sfondo.a.valore
                                        && sfondo.tipo !== "immagine")
                                       ? sfondo.a.valore : Theme.Colors.accent

        // La parete. Serve anche al motivo, che ci si appoggia sopra.
        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusSM
            visible: sfondo.tipo === "tinta" || sfondo.tipo === "motivo"
            color: Qt.tint(Theme.Colors.base, Qt.alpha(sfondo.tinta,
                           sfondo.tipo === "motivo" ? 0.34 : 0.55))
        }

        // Il vetro: la tinta come luce, non come parete. Sfuma e sparisce
        // prima di arrivare in fondo, così l'elenco lungo non ci finisce
        // dentro.
        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusSM
            visible: sfondo.tipo === "vetro"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(sfondo.tinta, 0.42) }
                GradientStop { position: 0.55; color: Qt.alpha(sfondo.tinta, 0.13) }
                GradientStop { position: 1.0; color: Qt.alpha(sfondo.tinta, 0.02) }
            }
        }

        // Le icone sparse.
        //
        // Le posizioni non sono a caso vero: sono una formula sull'indice.
        // Il caso vero cambierebbe a ogni ridisegno, e uno sfondo che si
        // rimescola mentre si scorre è un difetto, non una decorazione.
        // Sono ventiquattro: abbastanza da sembrare sparse, poche abbastanza
        // da non pesare su una cartella con mille file.
        Repeater {
            model: sfondo.tipo === "motivo" ? 24 : 0

            delegate: Ui.Icon {
                required property int index

                readonly property real k: (index * 2654435761) % 1000 / 1000
                readonly property real k2: (index * 40503) % 997 / 997

                name: sfondo.a ? sfondo.a.icona : "folder"
                // Il nostro tracciato, sempre: qui il colore lo scegliamo noi, e
                // un'icona del tema di sistema arriva già colorata e lo ignora.
                alwaysDrawn: true
                color: Qt.lighter(sfondo.tinta, 1.5)
                opacity: 0.13 + k2 * 0.07
                width: 26 + k * 34
                height: width
                x: (index % 6) * (sfondo.width / 6) + k * (sfondo.width / 8)
                y: Math.floor(index / 6) * (sfondo.height / 4) + k2 * (sfondo.height / 9)
                rotation: -22 + k * 44
            }
        }

        // La foto scelta a mano.
        Image {
            anchors.fill: parent
            visible: sfondo.tipo === "immagine"
            source: sfondo.tipo === "immagine" ? "file://" + sfondo.a.valore : ""
            fillMode: Image.PreserveAspectCrop
            // Ridotta in lettura: una foto da 40 megapixel dietro una cartella
            // farebbe dipendere la memoria del gestore file dallo sfondo
            // scelto.
            sourceSize.width: 1280
            asynchronous: true
            cache: true
            opacity: 0.22
        }

        // Il velo, solo sotto una foto: ha zone chiare, e senza velo i nomi
        // dei file ci finiscono sopra e spariscono. Le tinte e i motivi sono
        // già scuriti in partenza e non ne hanno bisogno.
        Rectangle {
            anchors.fill: parent
            visible: sfondo.tipo === "immagine"
            color: Theme.Colors.base
            opacity: 0.45
        }
    }

    // Quello che il puntatore si porta dietro. Un oggetto solo per riquadro,
    // fuori dalla vista: `Drag` vuole un elemento che sopravviva al gesto, e
    // le celle di una griglia vengono distrutte appena escono dalla vista.
    //
    // ── Il trascinamento esce dalla finestra ─────────────────────────────
    //
    // `Drag.Automatic` consegna il gesto al compositore: da lì può arrivare a
    // qualunque programma, e i file degli altri programmi possono arrivare
    // qui. Al primo tentativo non funzionava NIENTE — nemmeno dentro casa — e
    // la ragione era una riga di Qt che nessuno stava leggendo:
    //
    //     QQuickDragAttached: startDrag() drag must be active
    //
    // `Drag.Automatic` non sostituisce `Drag.active`: è `active` a far partire
    // il gesto, e `Automatic` dice soltanto CHI lo porta. Io avevo tolto
    // `active` e chiamavo `startDrag()` su un trascinamento spento. Trovata
    // isolando il caso in una finestra QML di venti righe, fuori da Minerva:
    // quando una cosa non funziona da nessuna parte, il posto dove guardarla
    // è il più piccolo possibile.
    //
    // Accendere `active` fa partire il gesto e NON TORNA finché non si lascia:
    // la riga dopo si esegue a trascinamento finito.
    Item {
        id: fardello
        width: 1
        height: 1
        property var percorsi: []

        Drag.active: pane.trascinando
        Drag.dragType: Drag.Automatic

        // ── Chi spegne il gesto, e perché solo lui ───────────────────────
        //
        // È l'unico segnale che sa quando il trascinamento di SISTEMA è
        // finito. La `MouseArea` non lo sa: appena il gesto parte, Qt le
        // toglie la presa del mouse, e quella perdita le arriva come
        // `onCanceled` — cioè uguale a un'interruzione.
        //
        // Giacomo, 7 settembre 2026: «perché ancora non trascina i file?».
        // Il registro diceva, due righe di fila:
        //
        //     [TR] acceso
        //     [TR] ANNULLATO -> spengo
        //
        // Il gesto partiva davvero — al compositore la richiesta arrivava, e
        // io ieri mi ero fermato a misurare quella — e moriva un istante dopo
        // perché `onCanceled` lo spegneva. La stessa forma del difetto di
        // ieri, entrata da un'altra porta.
        Drag.onDragFinished: {
            pane.trascinando = false;
            fardello.fotografia = null;
            fardello.Drag.imageSource = "";
        }
        /// La fotografia della cella, per la durata del gesto.
        property var fotografia: null
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.mimeData: ({ "text/uri-list": fardello.uriList })
        // L'immagine che segue il puntatore la disegna il compositore, e la
        // vuole da noi: la dà `iniziaTrascinamento`, fotografando la cella.

        readonly property string uriList: {
            var righe = [];
            for (var i = 0; i < fardello.percorsi.length; i++)
                righe.push("file://" + encodeURI(fardello.percorsi[i]));
            return righe.join("\r\n");
        }
    }

    // ── Quando dentro non c'è niente ─────────────────────────────────────
    //
    // Un elenco vuoto dice «non c'è niente» a modo suo: non dice niente. La
    // scritta al centro lo dice per lui.
    //
    // ── Quattro cose diverse, e una sola scritta ─────────────────────────
    //
    // «Non c'è niente da mostrare» ha quattro cause, e confonderle manda a
    // cercare il problema dalla parte sbagliata:
    //
    //   · la cartella **non si è potuta leggere** — è un guasto, e va detto
    //     col suo messaggio e in rosso, non con un «vuoto» che fa pensare
    //     che i file siano spariti;
    //   · il **filtro** non ha trovato niente — è la più insidiosa: la
    //     cartella è piena e sembra svuotata;
    //   · siamo nel **cestino**, e «vuoto» lì è l'unica informazione che
    //     un cestino vuoto ha da dare;
    //   · la cartella è vuota davvero.
    //
    // Questo blocco è UNO. Fino al 1º settembre 2026 ce n'erano due — questo
    // e un secondo dentro la GridView, con la stessa condizione — e a
    // cartella vuota si disegnavano tutti e due, leggermente sfalsati. Vedi
    // il commento rimasto al posto dell'altro.
    Item {
        id: emptyState
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        visible: pane.shown.length === 0

        /// Il filtro nasconde tutto: la cartella ha roba, ma non quella
        /// cercata. Si guarda `entries` e non `shown`, che è il risultato
        /// del filtro e qui è vuoto per definizione.
        readonly property bool filtrando: pane.filter !== ""
                                          && pane.entries.length > 0

        Column {
            anchors.centerIn: parent
            width: parent.width - Theme.Effects.space5
            spacing: Theme.Effects.space2

            Ui.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 42; height: 42
                name: pane.error !== "" ? "close"
                    : emptyState.filtrando ? "search"
                    : Files.inTrash(pane.path) ? "trash"
                    : "folder"
                color: pane.error !== "" ? Theme.Colors.danger
                                         : Theme.Colors.textFaint
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                // Il messaggio di un errore di lettura è una frase intera e
                // può contenere un percorso lungo: senza `wrapMode` esce
                // dai bordi del riquadro.
                wrapMode: Text.WordWrap
                text: {
                    var it = Core.Strings.lang === "it";
                    if (pane.error !== "")
                        return pane.error;
                    if (emptyState.filtrando)
                        return it ? "Nessun file con «" + pane.filter + "» nel nome"
                                  : "No file matching “" + pane.filter + "”";
                    if (Files.inTrash(pane.path))
                        return it ? "Il cestino è vuoto" : "The bin is empty";
                    return it ? "Cartella vuota" : "Empty folder";
                }
                color: pane.error !== "" ? Theme.Colors.danger
                                         : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }
        }
    }

    // ── La barra di scorrimento ──────────────────────────────────────────
    //
    // È il punto che l'ha fatta chiedere: Giacomo, 4 settembre 2026, «nel file
    // manager manca la barretta laterale che posso trascinare con il mouse per
    // spostare la discesa e slitta più velocemente». Una cartella come Camera
    // ha 311 file: senza, si scorreva senza sapere né dove si era né quanto
    // mancava.
    //
    // Sorella della griglia e non sua figlia, ancorata ai suoi BORDI, che
    // stanno fermi mentre il contenuto scorre.
    Ui.Scorrimento {
        bersaglio: view
        anchors {
            right: view.right
            rightMargin: Theme.Effects.space1
            top: view.top
            bottom: view.bottom
        }
    }

    GridView {
        id: view
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        anchors.margins: Theme.Effects.space2
        anchors.topMargin: pane.viewMode === "list" ? 0 : Theme.Effects.space1
        clip: true
        model: pane.shown
        boundsBehavior: Flickable.StopAtBounds
        focus: pane.focused

        // Il passaggio del mouse: una goccia sola che scivola da una cella
        // all'altra (`ui/Goccia.qml`), addosso al contenuto come la cornice
        // della selezione. Sta nel contenuto della griglia, quindi scorre
        // insieme alle celle.
        Ui.Goccia {
            id: gocciaCelle
            margine: view.gridMode ? pane.gridPadding : 0
            radius: view.gridMode ? Theme.Effects.radiusMD : Theme.Effects.radiusSM
            color: Theme.Colors.raised
        }

        // ── Cliccare il vuoto deseleziona ─────────────────────────────────
        //
        // Prima non esisteva: una volta selezionato un file restava
        // selezionato finché non si navigava, e il comando successivo — un
        // Canc, un Ctrl+X — agiva su qualcosa che non si stava più
        // guardando. Su ogni altro gestore file il clic sul vuoto pulisce,
        // e anche il tasto destro sul vuoto riparte da zero.
        //
        // `TapHandler` e non `MouseArea`: un MouseArea si terrebbe la
        // pressione e spegnerebbe lo scorrimento dell'elenco, che è la
        // prima cosa che si fa in un elenco.
        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: function (ep, button) {
                pane.activated();
                view.forceActiveFocus();
                pane.selection = [];
                pane.anchorIndex = -1;
                pane.cursor = 0;
                pane.cursoreMostrato = false;
                if (button === Qt.RightButton)
                    pane.menuRequested();
            }
        }
        // Qualche riga oltre il bordo tenuta pronta: scorrere una cartella di
        // fotografie senza è un lampeggio di riquadri vuoti.
        cacheBuffer: 600

        readonly property bool gridMode: pane.viewMode === "grid"

        /// Quante piastrelle per riga. Si divide la larghezza per la misura
        /// scelta e si distribuisce l'avanzo: le piastrelle diventano un filo
        /// più larghe invece di lasciare una striscia vuota a destra.
        readonly property int columns: gridMode
                                       ? Math.max(1, Math.floor(width / pane.tileSize))
                                       : 1

        // Mai zero: nell'istante prima che il riquadro abbia una larghezza,
        // una cella larga zero manda GridView a dividere per niente.
        cellWidth: Math.max(1, gridMode ? Math.floor(width / columns) : width)
        // In griglia l'altezza è quella dell'immagine PIÙ le due righe di
        // nome, calcolata e non stimata: con una stima per difetto i nomi
        // lunghi scavalcavano la piastrella sotto e la griglia sembrava un
        // testo mal impaginato.
        cellHeight: gridMode
                    ? Math.round(pane.tileSize * 0.80) + pane.gridPadding * 2
                      + pane.gridNameHeight + 4
                    // ── Le righe respirano ───────────────────────────
                    //
                    // Erano `max(26, icona + 11)`: con l'icona da venti, una
                    // riga alta trentuno. Undici pixel per due righe di testo
                    // e un'icona vuol dire che il testo tocca sopra e sotto,
                    // e un elenco così si legge come una tabella di numeri —
                    // che è precisamente l'impressione che dava.
                    //
                    // Sedici invece di undici sono cinque pixel a riga: su
                    // venti righe è mezzo schermo in meno di roba, e si
                    // guadagna tutto in leggibilità.
                    // In ricerca ogni riga porta anche DOVE sta il file:
                    // due righe di testo vogliono qualche pixel in più.
                    : Math.max(pane.cercando ? 44 : 34, pane.iconSize + 16)

        // Ctrl+rotellina ingrandisce, come in qualunque cosa che mostri
        // immagini. Il gestore di gesti vede la rotellina prima della vista,
        // quindi con Ctrl premuto l'elenco non scorre anche.
        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: function (e) {
                pane.activated();
                pane.setZoom(pane.zoom + (e.angleDelta.y > 0 ? 1 : -1));
            }
        }

        function step(delta, extend) {
            if (pane.shown.length === 0)
                return;
            pane.cursoreMostrato = true;
            var target = Math.max(0, Math.min(pane.shown.length - 1,
                                              pane.cursor + delta));
            if (extend)
                pane.extendTo(target);
            else
                pane.anchorIndex = target;
            pane.cursor = target;
            view.positionViewAtIndex(target, GridView.Contain);
        }

        Keys.onUpPressed: function(e) {
            view.step(-view.columns, e.modifiers & Qt.ShiftModifier);
        }
        Keys.onDownPressed: function(e) {
            view.step(view.columns, e.modifiers & Qt.ShiftModifier);
        }
        Keys.onLeftPressed: function(e) {
            if (view.gridMode)
                view.step(-1, e.modifiers & Qt.ShiftModifier);
        }
        Keys.onRightPressed: function(e) {
            if (view.gridMode)
                view.step(1, e.modifiers & Qt.ShiftModifier);
        }
        Keys.onReturnPressed: pane.openCursor()
        Keys.onEnterPressed: pane.openCursor()
        Keys.onSpacePressed: {
            var e = pane.shown[pane.cursor];
            if (e) pane.toggleSelection(e.path);
        }
        Keys.onPressed: function(e) {
            if (e.key === Qt.Key_Backspace) {
                pane.goUp();
                e.accepted = true;
            } else if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                pane.selectAll();
                e.accepted = true;
            } else if (e.key === Qt.Key_L && (e.modifiers & Qt.ControlModifier)) {
                // Ctrl+L scrive il percorso a mano. È la stessa combinazione di
                // ogni browser e di ogni gestore file: chi la conosce non deve
                // impararne un'altra, e chi non la conosce ha comunque il clic
                // sulle briciole.
                pane.apriPercorsoAMano();
                e.accepted = true;
            } else if (e.key === Qt.Key_Home) {
                view.step(-pane.shown.length, e.modifiers & Qt.ShiftModifier);
                e.accepted = true;
            } else if (e.key === Qt.Key_End) {
                view.step(pane.shown.length, e.modifiers & Qt.ShiftModifier);
                e.accepted = true;
            } else if (e.key === Qt.Key_PageDown) {
                view.step(view.columns
                          * Math.max(1, Math.floor(view.height / view.cellHeight)),
                          e.modifiers & Qt.ShiftModifier);
                e.accepted = true;
            } else if (e.key === Qt.Key_PageUp) {
                view.step(-view.columns
                          * Math.max(1, Math.floor(view.height / view.cellHeight)),
                          e.modifiers & Qt.ShiftModifier);
                e.accepted = true;
            } else if (e.key === Qt.Key_Plus && (e.modifiers & Qt.ControlModifier)) {
                pane.setZoom(pane.zoom + 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Minus && (e.modifiers & Qt.ControlModifier)) {
                pane.setZoom(pane.zoom - 1);
                e.accepted = true;
            }
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index

            readonly property bool selected: pane.isSelected(modelData.path)
            readonly property bool atCursor: index === pane.cursor && pane.focused
                                            && pane.cursoreMostrato
            readonly property bool gridMode: view.gridMode

            width: view.cellWidth
            height: view.cellHeight

            // Quanti file si portano, per il tempo della fotografia del
            // trascinamento (vedi `iniziaTrascinamento`).
            Rectangle {
                z: 10
                visible: pane._targaSu === cell.modelData.path && pane._targaQuante > 1
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space2
                width: Math.max(height, conta.implicitWidth + Theme.Effects.space3)
                height: 22
                radius: height / 2
                color: Theme.Colors.accent
                Text {
                    id: conta
                    anchors.centerIn: parent
                    text: pane._targaQuante
                    color: Theme.Colors.textOnAccent
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightBold
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            // La selezione si accende SOLO nel riquadro attivo. Con due o tre
            // schede aperte, ognuna con la propria selezione tutte accese
            // allo stesso modo, non c'è modo di sapere su quale agirà il
            // prossimo comando — e «sposta nel cestino» non è un comando su
            // cui si possa tirare a indovinare. Quella dei riquadri spenti
            // resta visibile appena, quel tanto che basta a ritrovarla
            // tornandoci.
            /// L'esito del confronto per questa riga: "solo", "diverso",
            /// "uguale" o vuoto quando non si sta confrontando.
            readonly property string esito:
                pane.esitoConfronto[cell.modelData.path] || ""

            // ── La cornice sta ADDOSSO al contenuto, non alla cella ──────
            //
            // Fino al 2 settembre 2026 era `anchors.fill: parent` con tre
            // pixel di margine: copriva quasi tutta la cella. In griglia una
            // cella è larga il triplo dell'icona, quindi passando il mouse si
            // accendeva un rettangolo enorme attorno a un'icona piccola, senza
            // niente di vuoto in mezzo.
            //
            // Giacomo: «la parte di cornice selezionabile intorno alle icone è
            // troppo ampia e non hai vuoto intorno alla icona».
            //
            // Adesso il margine è `gridPadding`, che è **lo stesso** con cui
            // sono disposti l'icona e il nome (vedi `thumb.x` e `nameText.x`):
            // la cornice combacia con il contenuto invece di sbordare di
            // cinque pixel per lato. Fra due celle vicine restano sedici pixel
            // di vuoto invece di sei, ed è quello che si vede.
            //
            // Il bersaglio del CLIC non cambia: resta tutta la cella
            // (`cellMouse` riempie il delegato). Si preme dove si è sempre
            // premuto — si vede solo una cosa più piccola e più precisa.
            //
            // In elenco resta a filo: là la riga È il contenuto, e staccarla
            // dai bordi farebbe una scaletta.
            Rectangle {
                id: bg
                anchors.fill: parent
                anchors.margins: cell.gridMode ? pane.gridPadding : 0
                radius: cell.gridMode ? Theme.Effects.radiusMD
                                      : Theme.Effects.radiusSM
                // Il passaggio del mouse lo disegna la goccia della griglia;
                // qui restano le cose che non si muovono col puntatore.
                color: bersaglio.sopra === cell.index
                       ? Qt.alpha(Theme.Colors.accent, 0.34)
                     : cell.selected
                       ? Qt.alpha(Theme.Colors.accent, pane.focused ? 0.22 : 0.07)
                     : cell.atCursor ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
            }

            // ── Il segno del confronto ───────────────────────────────────
            //
            // Una striscia sottile sul bordo sinistro, non un'icona in più:
            // deve dirsi con la coda dell'occhio mentre si scorre l'elenco,
            // non farsi guardare. Tre colori e nessuna scritta — chi confronta
            // due cartelle sa già cosa sta cercando.
            //
            // Quello che c'è di UGUALE non si segna: sarebbe la maggioranza
            // delle righe colorate per dire «niente da fare», e le tre che
            // contano sparirebbero in mezzo.
            Rectangle {
                visible: cell.esito === "solo" || cell.esito === "diverso"
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: cell.gridMode ? 3 : 2
                anchors.bottomMargin: cell.gridMode ? 3 : 2
                width: 3
                radius: 1.5
                color: cell.esito === "solo" ? Theme.Colors.accent
                                             : Theme.Colors.warning
            }

            // ── L'icona, o la fotografia vera ────────────────────────────
            //
            // Un'immagine si riconosce dall'immagine. Un elenco di
            // «foto_2024_0173.jpg» tutti con la stessa icona non dice niente
            // di quello che c'è dentro, ed è il motivo per cui la griglia
            // esiste.
            Item {
                id: thumb
                // In griglia l'icona si solleva di un soffio sotto il
                // puntatore, e ci arriva con la molla.
                scale: cell.gridMode && cellMouse.containsMouse ? 1.06 : 1
                transformOrigin: Item.Bottom
                Behavior on scale {
                    enabled: Theme.Motion.liquido
                    SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                }
                width: cell.gridMode ? cell.width - pane.gridPadding * 2
                                     : pane.iconSize
                height: cell.gridMode
                        ? cell.height - pane.gridPadding * 2 - pane.gridNameHeight - 4
                        : pane.iconSize
                x: cell.gridMode ? pane.gridPadding : Theme.Effects.space2 + 2
                y: cell.gridMode ? pane.gridPadding
                                 : Math.round((cell.height - height) / 2)

                // Il passe-partout dietro la fotografia. Una miniatura in
                // formato verticale dentro una piastrella quadrata lascia due
                // strisce vuote ai lati, e senza un fondo le immagini
                // sembrano appoggiate sul nulla ad altezze diverse. Con il
                // fondo la griglia diventa una griglia di cornici, che è
                // quello che l'occhio si aspetta di vedere.
                Rectangle {
                    anchors.fill: parent
                    visible: cell.gridMode && preview.visible
                    radius: Theme.Effects.radiusXS
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.05)
                }

                Image {
                    id: preview
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    // Asincrona: una cartella di JPEG da 12 megapixel
                    // bloccherebbe l'interfaccia per secondi mentre li
                    // decodifica uno dopo l'altro.
                    asynchronous: true
                    cache: true
                    smooth: true
                    // Niente mipmap: si decodifica già alla misura in cui si
                    // disegna (vedi `sourceSize` qui sotto), quindi non c'è
                    // niente da rimpicciolire — e i livelli intermedi che
                    // mipmap costruisce sono un terzo di memoria video in più
                    // per immagini che nessuno guarderà mai a quella scala.
                    // Sotto i 24 pixel una miniatura è un francobollo
                    // illeggibile pagato con un decodificatore per riga: a
                    // quella misura l'icona dice di più e costa niente.
                    source: (thumb.height >= 24
                             && Core.Ipc.get("files.anteprime", true)
                             && Files.isImage(cell.modelData.name))
                            ? Files.fileUrl(cell.modelData.path) : ""
                    // Si decodifica alla misura in cui si vede, non a quella
                    // vera del file: senza, ogni miniatura tiene in memoria
                    // l'immagine intera.
                    //
                    // Ma **a scatti di 32 pixel**, non alla misura esatta. In
                    // vista a griglia la piastrella è larga quanto la finestra
                    // diviso il numero di colonne: legare la decodifica al
                    // valore esatto vuol dire rileggere dal disco e
                    // ridecodificare TUTTA la cartella a ogni pixel di
                    // trascinamento del bordo. A scatti, il ridimensionamento
                    // è disegno e basta finché non si cambia scalino.
                    //
                    // Si arrotonda per ECCESSO: una miniatura decodificata più
                    // piccola di come si disegna è una miniatura sfocata, e la
                    // sfocatura è l'unico errore che si vede.
                    sourceSize.width: Math.ceil(thumb.width / 32) * 32
                    sourceSize.height: Math.ceil(thumb.height / 32) * 32
                    visible: status === Image.Ready
                }

                Ui.Icon {
                    anchors.centerIn: parent
                    width: cell.gridMode
                           ? Math.min(parent.width, parent.height) * 0.62
                           : parent.width
                    height: width
                    visible: !preview.visible
                    name: Files.iconFor(cell.modelData)
                    thickness: cell.gridMode ? 1.4 : 1.7
                    color: cell.modelData.isDir ? Theme.Colors.accent
                                                : Theme.Colors.textFaint
                }

                // Il collegamento si vede: una freccina in basso a sinistra,
                // come su qualunque sistema dal 1995. Senza, un collegamento
                // rotto sembra un file che non si apre.
                Ui.Icon {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    // Un contrassegno, non un disegno. Legata solo alla misura
                    // dell'icona cresceva con la piastrella: a griglia grande
                    // arrivava a sessanta pixel e si mangiava la fotografia
                    // che doveva contrassegnare. Sotto sta il minimo per
                    // vedersi accanto a un'icona da quindici pixel, sopra il
                    // massimo oltre il quale smette di essere un contrassegno.
                    width: Math.max(9, Math.min(22, parent.width * 0.28))
                    height: width
                    visible: cell.modelData.isLink === true
                    name: "back"
                    thickness: 2.4
                    rotation: 180
                    color: Theme.Colors.accentAlt
                }
            }

            // ── Il nome ──────────────────────────────────────────────────

            Text {
                textFormat: Text.PlainText
                id: nameText
                x: cell.gridMode ? pane.gridPadding
                                 : thumb.x + thumb.width + Theme.Effects.space2
                y: cell.gridMode ? thumb.y + thumb.height + 4
                                 : Math.round((cell.height - implicitHeight) / 2)
                width: cell.gridMode
                       ? cell.width - pane.gridPadding * 2
                       : Math.max(20, sizeText.x - x - Theme.Effects.space2)
                height: cell.gridMode ? pane.gridNameHeight : implicitHeight
                verticalAlignment: Text.AlignTop
                horizontalAlignment: cell.gridMode ? Text.AlignHCenter
                                                   : Text.AlignLeft
                // Il nome si accorcia IN MEZZO: la coda («…v3.pdf») distingue
                // due file molto più dell'inizio, che spesso è identico —
                // «IMG_20260704_1531…». Vale sempre in elenco.
                //
                // In griglia va a capo, ma solo se il nome ha degli spazi in
                // cui andare a capo. «IMG_20260704_153154.jpg» non ne ha:
                // spezzarlo comunque produceva una seconda riga con dentro una
                // lettera sola («…153154.jp» / «g»), che è il modo più brutto
                // possibile di mostrare un nome. Senza spazi si resta su una
                // riga e si accorcia in mezzo come in elenco.
                readonly property bool breakable:
                    cell.modelData.name.indexOf(" ") !== -1
                     || cell.modelData.name.indexOf("-") !== -1

                elide: (cell.gridMode && nameText.breakable) ? Text.ElideRight
                                                            : Text.ElideMiddle
                wrapMode: (cell.gridMode && nameText.breakable) ? Text.Wrap
                                                                : Text.NoWrap
                maximumLineCount: (cell.gridMode && nameText.breakable) ? 2 : 1
                text: cell.modelData.name
                color: cell.selected && pane.focused ? Theme.Colors.text
                     : pane.focused ? Theme.Colors.textMuted
                     : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── Nei risultati di una ricerca, DOVE sta ────────────────────
            //
            // In una cartella il percorso è ovvio: è quello scritto in alto.
            // In una ricerca no, ed è metà dell'informazione: tre file
            // chiamati «appunti.txt» si distinguono solo da dove stanno.
            //
            // Si accorcia dall'inizio: la coda del percorso — le due cartelle
            // che lo contengono — dice molto più della radice, che è la stessa
            // per tutti i risultati.
            Text {
                visible: pane.cercando && !cell.gridMode
                         && cell.modelData.dove !== undefined
                x: nameText.x
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                width: nameText.width
                elide: Text.ElideLeft
                text: {
                    var d = String(cell.modelData.dove || "");
                    if (d.indexOf(pane.path) === 0)
                        d = d.substring(pane.path.length) || "/";
                    return d;
                }
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }

            // ── Le colonne ───────────────────────────────────────────────

            Text {
                id: sizeText
                visible: !cell.gridMode
                x: cell.width - pane.sizeColumn
                   - (pane.showTime ? pane.timeColumn : 0)
                width: pane.sizeColumn - Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: cell.modelData.isDir ? "" : Core.Formato.peso(cell.modelData.size)
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }

            Text {
                visible: !cell.gridMode && pane.showTime
                x: cell.width - pane.timeColumn
                width: pane.timeColumn - Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Files.humanTime(cell.modelData.modified)
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }

            MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onContainsMouseChanged: gocciaCelle.punta(cell, cellMouse.containsMouse)

                /// Da dove è partito il dito. Serve alla soglia: senza, ogni
                /// clic con un tremito di due pixel diventerebbe un
                /// trascinamento, e selezionare un file sarebbe una lotteria.
                property point partenza: Qt.point(0, 0)

                onPositionChanged: function (m) {
                    if (!cellMouse.pressed)
                        return;
                    var p = cell.mapToItem(pane, m.x, m.y);
                    if (pane.trascinando) {
                        pane.muoviTrascinamento(p);
                        return;
                    }
                    if (Math.abs(m.x - cellMouse.partenza.x) < 10
                        && Math.abs(m.y - cellMouse.partenza.y) < 10)
                        return;
                    // Si trascina la selezione se il file toccato ne fa parte,
                    // altrimenti solo lui: trascinare una riga fuori dalla
                    // selezione portandosi dietro la selezione sarebbe spostare
                    // roba che chi trascina non sta guardando.
                    pane.iniziaTrascinamento(
                        pane.isSelected(cell.modelData.path)
                            ? pane.selection.slice()
                            : [cell.modelData.path], p, cell,
                        Qt.point(cellMouse.partenza.x, cellMouse.partenza.y));
                }

                onReleased: pane.finisciTrascinamento()
                // Perdere la presa NON vuol dire che il gesto è finito: se il
                // trascinamento di sistema è partito, è proprio lui ad avercela
                // tolta. Lo chiude `Drag.onDragFinished`.
                onCanceled: {
                    if (!pane.trascinando)
                        pane.trascinando = false;
                }

                onPressed: function(m) {
                    pane.activated();
                    view.forceActiveFocus();
                    pane.cursoreMostrato = true;
                    cellMouse.partenza = Qt.point(m.x, m.y);

                    if (m.button === Qt.RightButton) {
                        // Il tasto destro su una voce non selezionata la
                        // seleziona: altrimenti il menu agirebbe su qualcosa
                        // di diverso da quello su cui si è cliccato.
                        if (!cell.selected) {
                            pane.selectOnly(cell.modelData.path);
                            pane.anchorIndex = cell.index;
                        }
                        pane.cursor = cell.index;
                        pane.menuRequested();
                        return;
                    }

                    if (m.modifiers & Qt.ControlModifier) {
                        pane.toggleSelection(cell.modelData.path);
                        pane.anchorIndex = cell.index;
                    } else if (m.modifiers & Qt.ShiftModifier) {
                        pane.extendTo(cell.index);
                    } else {
                        pane.selectOnly(cell.modelData.path);
                        pane.anchorIndex = cell.index;
                    }
                    pane.cursor = cell.index;
                }

                /// Con «un clic solo per aprire» acceso, il primo clic
                /// apre. Sta in `onClicked` e non in `onPressed` perché
                /// premere è anche l'inizio di un trascinamento: aprire alla
                /// pressione vorrebbe dire aprire ogni volta che si prova a
                /// spostare qualcosa.
                onClicked: function (m) {
                    if (m.button !== Qt.LeftButton)
                        return;
                    if (m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                        return;
                    if (Core.Ipc.get("files.clicSingolo", false))
                        cellMouse.apri();
                }

                onDoubleClicked: cellMouse.apri()

                function apri() {
                    if (cell.modelData.isDir)
                        pane.navigate(cell.modelData.path);
                    else
                        pane.openRequested(cell.modelData.path);
                }
            }
        }

        // ── Qui c'era il SECONDO «Cartella vuota» ────────────────────────
        //
        // Una `Column` con la sua icona e la sua scritta, `visible:
        // pane.shown.length === 0`, dentro la GridView. E c'era anche quella
        // di sopra (`emptyState`), con la stessa condizione: **a cartella
        // vuota si disegnavano tutte e due.**
        //
        // Non si sovrapponevano esattamente — corpo del testo diverso (SM
        // contro MD), icona diversa (34 contro 42), e centrate in due
        // contenitori diversi — quindi il risultato erano due scritte
        // leggermente sfalsate una sopra l'altra. È quello che Giacomo ha
        // visto cancellando tutti i file di una cartella.
        //
        // ── Perché è sopravvissuto quello di FUORI ───────────────────────
        //
        // Perché questo stava dentro un `Flickable`, e i figli di un
        // Flickable finiscono nel suo `contentItem`: `anchors.centerIn:
        // parent` li centra rispetto al CONTENUTO, non rispetto alla vista.
        // Con un modello vuoto il contenuto è alto zero, e la scritta finisce
        // in cima invece che al centro.
        //
        // I tre casi che sapeva distinguere — errore di lettura, filtro senza
        // risultati, cartella vuota davvero — non si sono persi: sono passati
        // nel blocco di fuori, che ne aveva solo due.
    }

    // ── Riga di stato ────────────────────────────────────────────────────

    Item {
        id: statusBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space3
        height: 30

        // I comandi della vista in una capsula; la vista attiva la segna
        // una goccia che scivola da «elenco» a «griglia».
        Rectangle {
            id: capsulaVista
            anchors.fill: viewRow
            anchors.leftMargin: -Theme.Effects.space2
            anchors.rightMargin: -Theme.Effects.space1
            anchors.topMargin: -3
            anchors.bottomMargin: -3
            radius: height / 2
            color: Theme.Colors.raised

            Ui.Goccia {
                id: gocciaVista
                radius: height / 2
                color: Qt.alpha(Theme.Colors.accent, 0.22)
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: viewRow.left
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: {
                var it = Core.Strings.lang === "it";
                var n = pane.shown.length;
                if (pane.selection.length > 0)
                    return pane.selection.length + (it ? " selezionati di " : " selected of ") + n;
                return n + (it ? " elementi" : " items");
            }
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }

        // ── I comandi della visuale ──────────────────────────────────────
        //
        // Stanno in basso a destra, nel riquadro a cui si riferiscono, e non
        // nella barra in alto: sono di QUESTO riquadro, e una scheda a griglia
        // accanto a una a elenco con un unico pulsante in cima non si
        // saprebbe a chi obbedisce.

        Row {
            id: viewRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            // File nascosti — dove è sempre stato.
            Rectangle {
                width: hiddenText.implicitWidth + Theme.Effects.space2
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.Effects.radiusXS
                color: pane.showHidden ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : hiddenMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    id: hiddenText
                    anchors.centerIn: parent
                    text: Core.Strings.lang === "it" ? "nascosti" : "hidden"
                    color: pane.showHidden ? Theme.Colors.accent : Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                MouseArea {
                    id: hiddenMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.commutaNascosti()
                }
            }

            Rectangle {
                width: 1; height: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.Colors.edge
            }

            // Ordinamento, per la griglia che non ha intestazioni di colonna.
            Rectangle {
                id: sortBtn
                width: 20; height: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: pane.viewMode === "grid"
                radius: Theme.Effects.radiusXS
                color: sortMenu.visible ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : sortMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 13; height: 13
                    name: "sort"
                    color: sortMenu.visible ? Theme.Colors.accent
                                            : Theme.Colors.textFaint
                }

                MouseArea {
                    id: sortMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pane.activated();
                        sortMenu.visible = !sortMenu.visible;
                    }
                }
            }

            // Elenco / griglia: due pulsanti, non uno che cambia faccia. Un
            // pulsante solo mostra lo stato ATTUALE o quello FUTURO e non c'è
            // modo di indovinare quale dei due; due, con quello attivo acceso,
            // si leggono senza pensarci.
            Repeater {
                model: [
                    { "id": "list", "icon": "list" },
                    { "id": "grid", "icon": "grid" }
                ]

                delegate: Rectangle {
                    id: modeBtn
                    required property var modelData

                    readonly property bool active: pane.viewMode === modelData.id
                    onActiveChanged: if (modeBtn.active) gocciaVista.attiva = modeBtn
                    Component.onCompleted: if (modeBtn.active) gocciaVista.attiva = modeBtn

                    width: 26; height: 22
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    // La vista attiva la segna la goccia della capsula.
                    color: !modeBtn.active && modeMouse.containsMouse ? Theme.Colors.hover
                                                                      : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 13; height: 13
                        name: modeBtn.modelData.icon
                        thickness: 1.5
                        color: modeBtn.active ? Theme.Colors.accent
                                              : Theme.Colors.textFaint
                    }

                    MouseArea {
                        id: modeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pane.activated();
                            pane.setViewMode(modeBtn.modelData.id);
                        }
                    }
                }
            }

            Rectangle {
                width: 1; height: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.Colors.edge
            }

            // Grandezza delle icone. Cinque scatti e non uno scorrevole: gli
            // scatti sono quelli in cui i nomi stanno e le miniature si
            // vedono, e una misura qualunque in mezzo non aggiunge niente.
            Repeater {
                model: [
                    { "id": "out", "icon": "minus" },
                    { "id": "in",  "icon": "plus" }
                ]

                delegate: Rectangle {
                    id: zoomBtn
                    required property var modelData

                    readonly property bool usable:
                        modelData.id === "in" ? pane.zoom < Files.zoomMax
                                              : pane.zoom > 0

                    width: 20; height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    radius: Theme.Effects.radiusXS
                    opacity: zoomBtn.usable ? 1 : 0.3
                    color: zoomMouse.containsMouse && zoomBtn.usable
                           ? Theme.Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 12; height: 12
                        name: zoomBtn.modelData.icon
                        thickness: 2
                        color: Theme.Colors.textFaint
                        alwaysDrawn: true
                    }

                    MouseArea {
                        id: zoomMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: zoomBtn.usable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pane.activated();
                            pane.setZoom(pane.zoom
                                         + (zoomBtn.modelData.id === "in" ? 1 : -1));
                        }
                    }
                }
            }
        }
    }

    // ── Il menu dell'ordinamento ─────────────────────────────────────────
    //
    // Fuori dalla riga di stato, perché deve poter uscire dalla sua altezza di
    // venti pixel. Sta dentro il riquadro: è una scelta di questo riquadro.

    Rectangle {
        id: sortMenu
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        anchors.rightMargin: Theme.Effects.space2
        anchors.bottomMargin: Theme.Effects.space1
        width: 148
        height: sortColumn.implicitHeight + Theme.Effects.space2 * 2
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge
        visible: false
        z: 5

        Column {
            id: sortColumn
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            spacing: 1

            Repeater {
                model: [
                    { "id": "name",     "it": "Nome",       "en": "Name" },
                    { "id": "size",     "it": "Dimensione", "en": "Size" },
                    { "id": "modified", "it": "Modificato", "en": "Modified" },
                    { "id": "type",     "it": "Tipo",       "en": "Type" }
                ]

                delegate: Rectangle {
                    id: sortRow
                    required property var modelData

                    readonly property bool active: pane.sortBy === modelData.id

                    width: parent.width
                    height: 24
                    radius: Theme.Effects.radiusXS
                    color: sortRowMouse.containsMouse ? Theme.Colors.hover
                                                      : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: Core.Strings.lang === "it" ? sortRow.modelData.it
                                                         : sortRow.modelData.en
                        color: sortRow.active ? Theme.Colors.accent
                                              : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    Ui.Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10
                        visible: sortRow.active
                        name: "chevron"
                        thickness: 2.2
                        color: Theme.Colors.accent
                        rotation: pane.sortDesc ? 0 : 180
                    }

                    MouseArea {
                        id: sortRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.sortByColumn(sortRow.modelData.id)
                    }
                }
            }
        }
    }

    // Un clic altrove chiude il menu. Senza, resta aperto finché non si
    // ricentra il pulsante — e un menu che non si chiude cliccando fuori è la
    // cosa che fa sembrare rotta un'interfaccia.
    MouseArea {
        anchors.fill: parent
        visible: sortMenu.visible
        z: 4
        onPressed: function(m) {
            sortMenu.visible = false;
            m.accepted = false;
        }
    }
}
