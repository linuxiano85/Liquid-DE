import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "../menu"

// Viewer — Minerva Anteprima.
//
// ── L'idea, in una riga ──────────────────────────────────────────────────
//
// Non si apre UN'IMMAGINE: si apre un punto dentro una cartella di immagini.
//
// È la differenza fra un visualizzatore che si usa e uno che si chiude subito.
// Chi fa doppio clic sulla terza fotografia di una cartella quasi sempre vuole
// vedere anche la quarta, e un programma che mostra un file solo lo costringe
// a tornare indietro trenta volte. Quindi: aperta un'immagine, la cartella
// intorno diventa l'album, le frecce ci camminano dentro e la striscia in
// basso dice a che punto si è.
//
// L'eccezione è chi ne seleziona sei e le apre insieme: quelle sei SONO
// l'album, e non c'è ragione di aggiungerci il resto della cartella.
//
// ── Che cosa NON fa ──────────────────────────────────────────────────────
//
// Non modifica i file. La rotazione è per guardare, non si scrive su disco: un
// visualizzatore che riscrive un JPEG di nascosto è un visualizzatore che un
// giorno rovina una fotografia. Le uniche azioni che toccano il disco sono
// nel menu del tasto destro, si chiamano per nome, e cestinano invece di
// cancellare.
FloatingWindow {
    id: viewer

    // Non ci si mostra col tema di fabbrica.
    //
    // I colori arrivano dal demone. Finché non sono arrivati, il tema è quello
    // di ripiego (`notte`, ciano): chi ne ha scelto un altro vedeva la
    // finestra aprirsi del colore sbagliato e poi scattare. Misurato, le
    // impostazioni vincevano la corsa per SEDICI MILLISECONDI — un fotogramma,
    // cioè per caso. All'accesso, con più finestre insieme e il demone che sta
    // ancora partendo, quel margine non c'è.
    //
    // `Core.Ipc.prontoADipingere` scade da solo dopo un quarto di secondo, così
    // un demone spento non lascia senza finestra: vedi `core/Ipc.qml`.
    visible: Core.Ipc.prontoADipingere && !viewer.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    //
    // Vera quando il programma c'è ma non si deve vedere: è così che una app
    // «tenuta pronta» aspetta di essere richiamata senza pagare i 422 ms di
    // ricostruzione. La decisione sta tutta in `core/TenutaPronta.qml`, qui
    // c'è solo l'interruttore della luce.
    property bool dormiente: false

    readonly property bool it: Core.Strings.lang === "it"

    /// I file passati da chi ci ha lanciati. Se sono più d'uno, sono l'album.
    property var initialPaths: []
    /// Oppure una cartella da sfogliare per intero.
    property string initialDir: ""

    // ── L'album ──────────────────────────────────────────────────────────
    //
    // Tre pezzi, e conviene tenerli distinti:
    //
    //  · `grezzo`  — tutto quello che si è trovato, nell'ordine del disco;
    //  · `album`   — quello che si vede davvero, filtrato e ordinato;
    //  · `corrente`— il file che si sta guardando, per PERCORSO e non per
    //                posizione.
    //
    // Il punto è l'ultimo. Con un indice, cambiare filtro o ordinamento
    // sposterebbe sotto i piedi la fotografia che si sta guardando: la
    // posizione 3 di ieri è un altro file oggi. Con il percorso, si riordina
    // tutto e si continua a guardare la stessa cosa — che è l'unica cosa che
    // chi guarda si aspetta.
    property var grezzo: []
    property string corrente: ""
    /// Dimensione e data, per file. Arrivano con l'elenco della cartella e
    /// servono a ordinare senza richiedere niente a nessuno.
    property var meta: ({})
    /// Vero quando l'album è stato imposto da fuori (più file selezionati) e
    /// non va sostituito con il contenuto della cartella.
    property bool albumImposto: false

    /// "tutto", "immagini" o "video".
    property string filtro: "tutto"
    /// "nome", "data" o "peso".
    property string ordine: "nome"
    property bool discendente: false

    readonly property var album: {
        var out = [];
        for (var i = 0; i < viewer.grezzo.length; i++) {
            var p = viewer.grezzo[i];
            if (viewer.filtro === "immagini" && !viewer.immagine(p))
                continue;
            if (viewer.filtro === "video" && !viewer.video(p))
                continue;
            out.push(p);
        }
        var m = viewer.meta;
        var chiave = viewer.ordine;
        out.sort(function (a, b) {
            var r = 0;
            if (chiave === "data")
                r = ((m[a] ? m[a].modified : 0) - (m[b] ? m[b].modified : 0));
            else if (chiave === "peso")
                r = ((m[a] ? m[a].size : 0) - (m[b] ? m[b].size : 0));
            // A parità — e sempre, per il nome — si ordina per percorso: due
            // file scritti nello stesso secondo devono comunque avere un
            // ordine, e deve essere lo stesso domani.
            if (r === 0)
                r = a < b ? -1 : (a > b ? 1 : 0);
            return viewer.discendente ? -r : r;
        });
        return out;
    }

    // ── Galleria o visualizzatore ────────────────────────────────────────
    //
    // Lo stesso programma fa due cose, e quale delle due lo dice chi lo apre:
    //
    //     minerva-viewer              → la galleria dei ricordi
    //     minerva-viewer foto.jpg     → il visualizzatore, album = la cartella
    //     minerva-viewer ~/Immagini   → il visualizzatore su quella cartella
    //
    // Non è una finestra nuova né un'applicazione nuova: `minerva-viewer` senza
    // argomenti apriva una finestra VUOTA, e quello era lo spazio da riempire.
    // Così restano com'erano il `.desktop`, l'icona, la voce nella dock e la
    // riga in `core/Apps.qml`.
    readonly property bool inGalleria:
        viewer.grezzo.length === 0 && viewer.corrente === ""

    readonly property int indice: viewer.album.indexOf(viewer.corrente)

    /// Se il filtro ha portato via proprio quello che si stava guardando, si
    /// va sul primo che è rimasto invece di restare su un file che l'album
    /// non contiene più.
    onAlbumChanged: {
        if (viewer.album.length === 0)
            return;
        if (viewer.album.indexOf(viewer.corrente) === -1)
            viewer.corrente = viewer.album[0];
    }

    readonly property string percorso: viewer.corrente
    readonly property string nome: {
        var p = viewer.percorso;
        return p === "" ? "" : p.substring(p.lastIndexOf("/") + 1);
    }
    readonly property string cartella: {
        var p = viewer.percorso;
        var cut = p.lastIndexOf("/");
        return cut > 0 ? p.substring(0, cut) : (p === "" ? "" : "/");
    }

    title: viewer.nome !== ""
           ? viewer.nome + " · " + (viewer.it ? "Anteprima" : "Preview")
           : "Minerva · " + (viewer.it ? "Anteprima" : "Preview")
    implicitWidth: 1180
    implicitHeight: 780
    // ── Il colore lo mette la FINESTRA, e costa quindici megabyte di meno ─
    //
    // Il 2 settembre 2026 qui c'era `color: "transparent"` più un
    // `Ui.FondoFinestra` — un rettangolo a tutta finestra col raggio — per
    // arrotondare gli angoli, che Giacomo aveva chiesto.
    //
    // Funzionava, e si è visto nelle fotografie. Costava però **quindici
    // megabyte per applicazione**, misurati: 55 MB senza, 69-72 con. Provato
    // in quattro modi per isolarne la causa — raggio zero, finestra opaca,
    // senza `z: -1` — e il conto non cambiava: in Qt Quick col renderer
    // software un rettangolo grande quanto la finestra costa così, comunque
    // lo si scriva.
    //
    // Su una scrivania che pesa 430 MB, quindici per applicazione non è un
    // prezzo che si paga per un angolo tondo. Gli angoli si faranno nel
    // COMPOSITORE, dove costano una volta sola e valgono anche per i
    // programmi degli altri — che è poi dove deve stare anche il «corpo
    // unico» fra barra e finestra.
    color: Theme.Colors.window

    signal requestClose()
    onClosed: viewer.requestClose()

    // ── Che cosa sappiamo aprire ─────────────────────────────────────────
    //
    // Si elencano i formati che Qt sa leggere, non quelli che esistono. La
    // stessa lista sta nel file `.desktop`: è la promessa che facciamo al
    // resto del sistema, e le due devono dire la stessa cosa.
    readonly property var estensioni: [
        ".png", ".jpg", ".jpeg", ".jpe", ".gif", ".bmp", ".webp",
        ".tif", ".tiff", ".ico", ".svg", ".svgz", ".ppm", ".pgm", ".xbm", ".xpm"
    ]

    // ── I video ──────────────────────────────────────────────────────────
    //
    // Anteprima **non li riproduce**, e li mostra lo stesso. Non è una via di
    // mezzo per pigrizia: la domanda «che cosa c'è in questa cartella?» non
    // distingue fra una foto e un filmato — quelli di un telefono stanno
    // mescolati nella stessa cartella e sono stati fatti nello stesso
    // pomeriggio — mentre la domanda «fammelo vedere» sì. Quindi i video
    // stanno nel provino, con il loro segno, e chi li apre viene passato al
    // programma che li sa suonare davvero.
    //
    // Un lettore vero qui dentro vorrebbe controlli di riproduzione, audio,
    // sottotitoli, lo schermo che non si spegne: è un altro programma. Il
    // modulo per farlo (QtMultimedia) c'è su questa macchina, quindi è una
    // strada aperta — non una porta chiusa.
    readonly property var estensioniVideo: [
        ".mp4", ".m4v", ".mkv", ".webm", ".mov", ".avi", ".mpg", ".mpeg",
        ".wmv", ".flv", ".ogv", ".3gp"
    ]

    function _finisceCon(nomeFile, lista) {
        var low = String(nomeFile).toLowerCase();
        for (var i = 0; i < lista.length; i++) {
            var e = lista[i];
            if (low.endsWith(e))
                return true;
        }
        return false;
    }

    function immagine(nomeFile) { return viewer._finisceCon(nomeFile, viewer.estensioni); }
    function video(nomeFile)    { return viewer._finisceCon(nomeFile, viewer.estensioniVideo); }
    function media(nomeFile)    { return viewer.immagine(nomeFile) || viewer.video(nomeFile); }

    /// Vero se ci sono video da queste parti: senza, il filtro non serve a
    /// niente e non si mostra. Tre pulsanti di cui due inutili sono peggio di
    /// nessun pulsante.
    readonly property bool ciSonoVideo: {
        for (var i = 0; i < viewer.grezzo.length; i++)
            if (viewer.video(viewer.grezzo[i]))
                return true;
        return false;
    }

    // ── Aprire ───────────────────────────────────────────────────────────

    /// Mostra un file, e costruisci l'album dalla cartella che lo contiene.
    function show(path) {
        if (!path || path === "")
            return;
        if (viewer.grezzo.indexOf(path) !== -1) {
            viewer.corrente = path;
            return;
        }
        // Si mostra SUBITO il file chiesto, con un album di uno: la cartella
        // arriva dal demone qualche decina di millisecondi dopo, e in quelle
        // decine di millisecondi la finestra deve già avere qualcosa dentro.
        viewer.albumImposto = false;
        viewer.grezzo = [path];
        viewer.corrente = path;
        viewer.chiediCartella();
    }

    /// Mostra un elenco di file scelti da chi ci ha lanciati: sono loro
    /// l'album, per intero.
    function showAll(paths) {
        var buoni = [];
        for (var i = 0; i < paths.length; i++)
            if (viewer.media(paths[i]))
                buoni.push(paths[i]);
        if (buoni.length === 0)
            return;
        if (buoni.length === 1) {
            viewer.show(buoni[0]);
            return;
        }
        viewer.albumImposto = true;
        viewer.grezzo = buoni;
        viewer.corrente = buoni[0];
    }

    function chiediCartella() {
        if (viewer.cartella !== "")
            Core.Ipc.fsList(viewer.cartella, false, "viewerAlbum");
    }

    // ── Aprire una cartella intera ───────────────────────────────────────
    //
    // Chiesto da Giacomo: «mettergli sulla finestra una freccetta per aprire
    // una lista per aprire ad esempio una cartella di immagini». Senza, si può
    // arrivare qui solo da fuori — dal gestore file o da un doppio clic — e un
    // programma che non si sa aprire da solo è un programma a metà.
    //
    // I posti non li inventiamo: sono quelli veri dell'utente (`user-dirs.dirs`
    // via il demone), gli stessi che stanno nella barra del gestore file.
    property var luoghi: []
    property string casa: ""

    function apriCartella(dir) {
        if (dir && dir !== "")
            Core.Ipc.fsList(dir, false, "viewerApri");
    }

    function vociApri() {
        var v = [];
        var icone = { "pictures": "image", "downloads": "folder",
                      "documents": "document", "music": "music",
                      "videos": "video" };
        for (var i = 0; i < viewer.luoghi.length; i++) {
            var l = viewer.luoghi[i];
            // Musica e video non contengono immagini: offrirli qui sarebbe
            // offrire una cartella che si aprirà vuota.
            if (l.kind === "music" || l.kind === "videos")
                continue;
            v.push({ "label": l.name, "icon": icone[l.kind] || "folder",
                     "action": "dir:" + l.path });
        }
        if (viewer.casa !== "")
            v.push({ "label": viewer.it ? "Cartella personale" : "Home",
                     "icon": "folder", "action": "dir:" + viewer.casa });
        v.push({ "separator": true });
        v.push({ "label": viewer.it ? "Sfoglia con il gestore file…"
                                    : "Browse with the file manager…",
                 "icon": "apps", "action": "sfoglia" });
        return v;
    }

    // ── Quello che il demone sa del file ─────────────────────────────────
    //
    // Dimensione e programmi che lo sanno aprire. Si chiede a ogni cambio di
    // immagine: è una `stat` e una ricerca in una tabella già in memoria, e
    // ci evita di leggere il disco da qui.
    property var info: null
    onPercorsoChanged: {
        viewer.info = null;

        // La cornice torna, e con niente aperto NON riparte il conto alla
        // rovescia che la nasconde: senza immagine i comandi sono l'unica cosa
        // che si può usare, e nasconderli lascia uno schermo nero e basta.
        viewer.mossoDaPoco = true;

        if (viewer.percorso === "") {
            viewer.percorsoPronto = "";
            quiete.stop();
            return;
        }
        quiete.restart();
        Core.Ipc.fsInfo(viewer.percorso);
        attesaMisure.restart();
    }

    // ── Perché il tavolo riceve il file in ritardo ───────────────────────
    //
    // Di qualche millisecondo, e sono millisecondi che valgono. `Stage` sa
    // decodificare alla misura giusta SOLO se conosce le misure vere del file,
    // e quelle arrivano dal demone. Mandargli il percorso subito vorrebbe dire
    // decodificare tutto — trenta megabyte — e poi rifarlo alla misura buona
    // appena arriva la risposta: il peggio delle due strade.
    //
    // Quindi il percorso passa al tavolo quando arriva la risposta, o dopo un
    // quinto di secondo se il demone non risponde: meglio un'immagine
    // decodificata in grande che nessuna immagine.
    property string percorsoPronto: ""

    Timer {
        id: attesaMisure
        interval: 200
        onTriggered: viewer.percorsoPronto = viewer.percorso
    }

    readonly property int misuraW:
        (viewer.info && viewer.info.path === viewer.percorsoPronto)
        ? (viewer.info.imageWidth || 0) : 0
    readonly property int misuraH:
        (viewer.info && viewer.info.path === viewer.percorsoPronto)
        ? (viewer.info.imageHeight || 0) : 0

    Connections {
        target: Core.Ipc

        function onFileInfoReceived(dati) {
            if (!dati || dati.path !== viewer.percorso)
                return;
            viewer.info = dati;
            // Adesso si sa quanto è grande: il tavolo può decodificarlo alla
            // misura che serve invece che tutto intero.
            attesaMisure.stop();
            viewer.percorsoPronto = viewer.percorso;
        }

        function onPlacesReceived(dati) {
            viewer.luoghi = (dati && dati.places) || [];
            viewer.casa = (dati && dati.home) || "";
        }

        function onFileListingReceived(listing) {
            if (listing.pane !== "viewerApri" && listing.pane !== "viewerAlbum")
                return;
            // Un elenco arrivato per l'album di contorno non deve sovrascrivere
            // un album scelto a mano.
            if (listing.pane === "viewerAlbum" && viewer.albumImposto)
                return;

            var trovati = [];
            var m = {};
            var voci = listing.entries || [];
            for (var i = 0; i < voci.length; i++) {
                var e = voci[i];
                if (e.isDir || !viewer.media(e.name))
                    continue;
                trovati.push(e.path);
                // Data e peso arrivano già qui: ordinare per data senza
                // richiedere niente a nessuno è tutto il vantaggio.
                m[e.path] = { "size": e.size || 0, "modified": e.modified || 0 };
            }

            // Una cartella chiesta dal menu «Apri» o dal gestore file: diventa
            // l'album per intero e si parte dal primo.
            if (listing.pane === "viewerApri") {
                if (trovati.length === 0) {
                    viewer.avviso = viewer.it ? "Nessuna immagine in questa cartella"
                                              : "No images in this folder";
                    avvisoTimer.restart();
                    return;
                }
                viewer.albumImposto = true;
                viewer.meta = m;
                viewer.grezzo = trovati;
                viewer.corrente = viewer.album.length > 0 ? viewer.album[0] : trovati[0];
                return;
            }

            if (trovati.length === 0)
                return;
            viewer.meta = m;
            viewer.grezzo = trovati;
            // Se il file che stiamo guardando non è nell'elenco (cestinato da
            // un altro programma, o nascosto) ci pensa `onAlbumChanged`.
        }
    }

    Component.onCompleted: {
        if (viewer.initialDir !== "")
            viewer.apriCartella(viewer.initialDir);
        else if (viewer.initialPaths.length > 0)
            viewer.showAll(viewer.initialPaths);
        Core.Ipc.fsPlaces();
    }

    /// Un cartello che dura tre secondi, per le cose che non hanno una
    /// finestra a cui appartenere: una cartella aperta e vuota.
    property string avviso: ""
    Timer {
        id: avvisoTimer
        interval: 3000
        onTriggered: viewer.avviso = ""
    }

    // ── Camminare nell'album ─────────────────────────────────────────────

    function vai(passo) {
        if (viewer.album.length <= 1)
            return;
        // Fa il giro. Un album non ha una fine di cui accorgersi: arrivato in
        // fondo, «avanti» che non fa niente sembra un tasto rotto.
        var n = viewer.album.length;
        var da = viewer.indice >= 0 ? viewer.indice : 0;
        viewer.corrente = viewer.album[((da + passo) % n + n) % n];
    }

    function vaiA(i) {
        if (i >= 0 && i < viewer.album.length)
            viewer.corrente = viewer.album[i];
    }

    // ── Le azioni sul file ───────────────────────────────────────────────

    /// Passa da `Core.Wallpaper` e non da `setSetting` diretto: scegliere uno
    /// sfondo a mano è DUE impostazioni, non una. Scritta solo l'immagine, con
    /// «una cartella che gira» acceso la scelta durava fino al giro dopo.
    function comeSfondo(quale) {
        var q = quale || viewer.percorso;
        if (q !== "")
            Core.Wallpaper.scegli(q);
    }

    function mostraNellaCartella(quale) {
        // Dalla galleria la cartella è quella del file su cui si è premuto,
        // non quella dell'album aperto — che nella galleria non c'è.
        var q = quale || "";
        var dove = q !== "" ? q.substring(0, q.lastIndexOf("/"))
                            : viewer.cartella;
        if (dove !== "")
            Quickshell.execDetached(["minerva-files", dove]);
    }

    /// «Apri con…»: i programmi che dichiarano di saper leggere questo tipo,
    /// nell'ordine in cui li mette il demone.
    ///
    /// NON `xdg-open`: è lo script che guarda `XDG_CURRENT_DESKTOP`, non
    /// conosce Minerva e finisce nel ramo generico dove vince il primo che
    /// dichiara di saper leggere tutto — cioè un browser. È lo stesso difetto
    /// per cui il gestore file apriva le fotografie con Chrome, e la cura è la
    /// stessa: chiedere al demone, che applica la specifica per conto suo.
    ///
    /// E noi non siamo fra i candidati: offrire «apri con Anteprima» dentro
    /// Anteprima è una voce che non fa niente.
    function vociApriCon() {
        var v = [];
        var cand = (viewer.info && viewer.info.candidates) || [];
        for (var i = 0; i < cand.length; i++) {
            if (cand[i].id === "minerva-viewer.desktop")
                continue;
            v.push({ "label": cand[i].name,
                     "icon": "apps",
                     "action": "app:" + cand[i].id });
        }
        // Un'azione vuota il menu non la esegue: la voce resta lì a dire che
        // non c'è niente da scegliere, invece di aprire un menu vuoto.
        if (v.length === 0)
            v.push({ "label": viewer.it ? "Nessun altro programma"
                                        : "No other program",
                     "icon": "apps", "action": "" });
        return v;
    }

    /// Cestina, e passa alla successiva.
    ///
    /// Cestina e non cancella: l'unica azione distruttiva di questo programma
    /// deve essere una che si può disfare. E si sposta alla prossima prima di
    /// togliere questa dall'album, o si resterebbe a guardare un file che non
    /// c'è più.
    function cestina(quale) {
        var vittima = quale || viewer.percorso;
        if (vittima === "")
            return;
        // ── Una miniatura della galleria non è la foto aperta ────────────
        //
        // Nella galleria non c'è nessun album da cui uscire e nessuna «foto
        // dopo» su cui andare: si cestina e si richiede il catalogo. Passare
        // di qui con la logica dell'album vorrebbe dire spostarsi su un file
        // che nessuno sta guardando.
        if (vittima !== viewer.percorso) {
            Core.Ipc.fsTrash([vittima]);
            galleriaLoader.ricarica();
            return;
        }
        // Dove andare DOPO si decide adesso, guardando l'album come si vede
        // ora: il successivo, o il precedente se questo era l'ultimo.
        var i = viewer.indice;
        var dopo = "";
        if (viewer.album.length > 1)
            dopo = (i < viewer.album.length - 1) ? viewer.album[i + 1]
                                                 : viewer.album[i - 1];

        Core.Ipc.fsTrash([vittima]);

        var rimasti = viewer.grezzo.slice();
        var g = rimasti.indexOf(vittima);
        if (g !== -1)
            rimasti.splice(g, 1);
        viewer.grezzo = rimasti;
        viewer.corrente = dopo;
    }

    // ── Schermo intero ───────────────────────────────────────────────────
    //
    // Lo schermo intero vero, non «ingrandisci» che lascia le zone
    // riservate: un'immagine a schermo intero deve coprire lo schermo.
    readonly property string me: "pid:" + Quickshell.processId
    readonly property var miaFinestra: Core.Windows.find(viewer.me)
    readonly property bool aTuttoSchermo:
        viewer.miaFinestra !== null && viewer.miaFinestra.fullscreen === true

    function schermoIntero() {
        Core.Compositore.commutaSchermoIntero(viewer.me);
    }

    // ── La cornice ───────────────────────────────────────────────────────

    Ui.WindowTitleBar {
        id: barra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: viewer.title
        onCloseRequested: viewer.requestClose()
    }

    // ── Filtro e ordine ──────────────────────────────────────────────────
    //
    // In alto a destra, di fronte alla targhetta. Sono due pastiglie e non sei
    // pulsanti: la domanda «per cosa sto filtrando?» si fa una volta ogni
    // tanto, e sei bersagli sempre accesi sopra una fotografia sono sei cose
    // che non sono la fotografia.

    readonly property string filtroNome: {
        if (viewer.filtro === "immagini") return viewer.it ? "Immagini" : "Images";
        if (viewer.filtro === "video")    return viewer.it ? "Video" : "Videos";
        return viewer.it ? "Tutto" : "Everything";
    }
    readonly property string ordineNome: {
        var n = viewer.ordine === "data" ? (viewer.it ? "Data" : "Date")
              : viewer.ordine === "peso" ? (viewer.it ? "Peso" : "Size")
              : (viewer.it ? "Nome" : "Name");
        return n + (viewer.discendente ? "  ↓" : "  ↑");
    }

    Row {
        anchors.top: tavolo.top
        anchors.right: tavolo.right
        anchors.margins: Theme.Effects.space3
        spacing: Theme.Effects.space2
        z: 6
        visible: viewer.album.length > 1 && viewer.chromeVisibile
        opacity: viewer.chromeVisibile ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        Chip {
            id: chipFiltro
            // Senza video nella cartella il filtro non ha niente da filtrare.
            visible: viewer.ciSonoVideo
            testo: viewer.filtroNome
            icona: viewer.filtro === "video" ? "video"
                 : viewer.filtro === "immagini" ? "image" : "grid"
            acceso: viewer.filtro !== "tutto"
            onPremuto: {
                var p = chipFiltro.mapToGlobal(chipFiltro.width / 2, chipFiltro.height);
                menuFiltro.openAt(p.x - 60, p.y + 4, [
                    { "label": viewer.it ? "Tutto" : "Everything",
                      "icon": "grid",  "action": "f:tutto" },
                    { "label": viewer.it ? "Solo immagini" : "Images only",
                      "icon": "image", "action": "f:immagini" },
                    { "label": viewer.it ? "Solo video" : "Videos only",
                      "icon": "video", "action": "f:video" }
                ]);
            }
        }

        Chip {
            id: chipOrdine
            testo: viewer.ordineNome
            icona: "sort"
            acceso: viewer.ordine !== "nome" || viewer.discendente
            onPremuto: {
                var p = chipOrdine.mapToGlobal(chipOrdine.width / 2, chipOrdine.height);
                menuOrdine.openAt(p.x - 60, p.y + 4, [
                    { "label": viewer.it ? "Per nome" : "By name",
                      "icon": "sort", "action": "o:nome" },
                    { "label": viewer.it ? "Per data" : "By date",
                      "icon": "timer", "action": "o:data" },
                    { "label": viewer.it ? "Per peso" : "By size",
                      "icon": "archive", "action": "o:peso" },
                    { "separator": true },
                    { "label": viewer.discendente
                              ? (viewer.it ? "Dal primo all'ultimo" : "Ascending")
                              : (viewer.it ? "Dall'ultimo al primo" : "Descending"),
                      "icon": "shuffle", "action": "o:verso" }
                ]);
            }
        }
    }

    ContextMenu {
        id: menuFiltro
        onTriggered: (action) => {
            if (action.indexOf("f:") === 0)
                viewer.filtro = action.substring(2);
        }
    }

    ContextMenu {
        id: menuOrdine
        onTriggered: (action) => {
            if (action.indexOf("o:") !== 0)
                return;
            var v = action.substring(2);
            if (v === "verso")
                viewer.discendente = !viewer.discendente;
            else
                viewer.ordine = v;
        }
    }

    Stage {
        id: tavolo
        visible: !viewer.inGalleria
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: provino.visible ? provino.top : parent.bottom
        // Un video non ha niente da disegnare qui: al suo posto c'è la scheda
        // qui sotto.
        percorso: viewer.video(viewer.percorsoPronto) ? "" : viewer.percorsoPronto
        veroW: viewer.misuraW
        veroH: viewer.misuraH
        onClicSecondario: (x, y) => viewer.apriMenu(x, y)
    }

    // ── La galleria ──────────────────────────────────────────────────────
    //
    // Dentro un `Loader`, e non dichiarata: chi apre una fotografia non deve
    // pagare la costruzione di una galleria che non guarderà. È la stessa
    // lezione del provino a contatto di questo stesso programma — una griglia
    // «invisibile» costruisce lo stesso le sue celle e decodifica lo stesso le
    // sue miniature, e lì valeva 69 MB per una cosa che nessuno aveva aperto.
    Loader {
        id: galleriaLoader
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: viewer.inGalleria
        visible: active

        /// Richiede il catalogo — dopo un cestino, per esempio. Passa di qui e
        /// non dritta alla galleria perché quando non si è nell'album la
        /// galleria non esiste: il `Loader` è spento, e chiamarle un metodo
        /// sarebbe un errore a runtime che il registro si mangia.
        function ricarica() {
            if (galleriaLoader.item)
                galleriaLoader.item.ricarica();
        }

        sourceComponent: Galleria {
            onApri: (p) => viewer.show(p)
            // Il percorso NON si butta via: era il difetto per cui nella
            // galleria il tasto destro non apriva niente.
            onMenu: (p, x, y, pr) => viewer.apriMenuGalleria(p, x, y, pr)
        }
    }

    // ── La scheda di un video ────────────────────────────────────────────
    //
    // Un video sta nell'album — è nella cartella, è stato girato lo stesso
    // pomeriggio delle fotografie — ma qui non si riproduce. Invece di un
    // rettangolo nero che sembra un errore, si dice che cos'è e si offre di
    // aprirlo con chi lo sa suonare.

    Column {
        anchors.centerIn: tavolo
        spacing: Theme.Effects.space3
        visible: viewer.video(viewer.percorso) && !viewer.mostraGriglia
        z: 3

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88
            height: 88
            radius: width / 2
            color: Theme.Colors.raised
            border.width: Theme.Effects.hairline
            border.color: Theme.Colors.edgeAccent

            Ui.Icon {
                anchors.centerIn: parent
                width: 34
                height: 34
                name: "video"
                alwaysDrawn: true
                color: Theme.Colors.accent
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Core.Ipc.openDefault([viewer.percorso])
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: viewer.nome
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeLG
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: viewer.it ? "Premi per riprodurlo"
                            : "Click to play it"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── Il provino a contatto ────────────────────────────────────────────

    /// Vero mentre si guarda tutta la cartella insieme invece di un file solo.
    property bool mostraGriglia: false

    /// Il provino esiste solo mentre lo si guarda.
    ///
    /// Prima stava lì sempre, soltanto invisibile — e una GridView invisibile
    /// costruisce lo stesso le sue celle e decodifica lo stesso le sue
    /// miniature: `visible: false` nasconde, non sospende. Misurato su una
    /// cartella di duecento fotografie: **129 MB di memoria privata senza aver
    /// mai premuto G**, contro i 70 di una foto sola. Adesso chi apre una
    /// fotografia e la guarda non paga niente per una griglia che non ha
    /// chiesto, e chiudendola quella memoria torna indietro.
    ///
    /// Riaprirla non ricomincia da capo: le miniature restano nella cache di
    /// Qt (`cache: true` nelle celle), quindi la seconda volta è disegno e
    /// basta.
    Loader {
        id: contatto
        anchors.fill: tavolo
        z: 4
        active: viewer.mostraGriglia
        visible: viewer.mostraGriglia
        sourceComponent: Griglia {
            album: viewer.album
            indice: viewer.indice
            eVideo: viewer.video
            onScelto: (i) => {
                viewer.vaiA(i);
                viewer.mostraGriglia = false;
            }
        }
    }

    Filmstrip {
        id: provino
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 76
        album: viewer.album
        indice: viewer.indice
        eVideo: viewer.video
        // Si vede quando serve: un album di uno non ha niente da sfogliare, e
        // una striscia con un francobollo solo è settantasei pixel spesi per
        // dire «non c'è altro». Col provino aperto nemmeno: sarebbe la stessa
        // cosa scritta due volte, e ruberebbe spazio proprio a lei.
        visible: viewer.strisciaAccesa && viewer.album.length > 1
                 && !viewer.mostraGriglia
        onScelto: (i) => viewer.vaiA(i)
    }

    /// La striscia si può spegnere, e la scelta si ricorda: chi guarda una
    /// fotografia alla volta la trova d'impiccio, chi cerca fra duecento non
    /// può farne a meno.
    ///
    /// Legata all'impostazione e non tenuta qui: è il demone a ricordarla, e
    /// due Anteprime aperte insieme devono essere d'accordo su com'è fatta.
    readonly property bool strisciaAccesa: Core.Ipc.get("viewer.filmstrip", true)

    function accendiStriscia(v) {
        Core.Ipc.setSetting("viewer.filmstrip", v);
    }

    // ── Le frecce ai bordi ───────────────────────────────────────────────

    Freccia {
        sinistra: true
        cornice: viewer.chromeVisibile
        visible: viewer.album.length > 1
        anchors.left: tavolo.left
        anchors.verticalCenter: tavolo.verticalCenter
        onPremuta: viewer.vai(-1)
    }

    Freccia {
        sinistra: false
        cornice: viewer.chromeVisibile
        visible: viewer.album.length > 1
        anchors.right: tavolo.right
        anchors.verticalCenter: tavolo.verticalCenter
        onPremuta: viewer.vai(1)
    }

    // ── La targhetta ─────────────────────────────────────────────────────
    //
    // Nome, misure e posizione nell'album. Sta in alto a sinistra e non nella
    // barra del titolo perché sono informazioni sull'IMMAGINE, non sulla
    // finestra, e cambiano dieci volte in dieci secondi mentre si sfoglia.

    /// La targhetta si mostra a richiesta, e di suo è spenta.
    ///
    /// Stava sempre in alto a sinistra, sopra la fotografia. Su un ritratto o
    /// su una foto con il soggetto in alto copriva esattamente la parte che si
    /// era venuti a guardare — Giacomo: «alcune cose si dovrebbero nascondere
    /// perché coprono le foto, come ad esempio dettagli». Misure e peso sono
    /// una cosa che si consulta, non che si sorveglia: stanno bene dietro un
    /// pulsante, e il pulsante sta nella barra insieme agli altri.
    property bool mostraDettagli: false

    Rectangle {
        id: targhetta
        anchors.top: tavolo.top
        anchors.left: tavolo.left
        anchors.margins: Theme.Effects.space3
        width: dati.implicitWidth + Theme.Effects.space3 * 2
        height: dati.implicitHeight + Theme.Effects.space2 * 2
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.panel
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        visible: viewer.percorso !== "" && viewer.chromeVisibile
                 && viewer.mostraDettagli
        opacity: viewer.chromeVisibile && viewer.mostraDettagli ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        Text {
            id: dati
            anchors.centerIn: parent
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
            text: {
                var pezzi = [];
                if (tavolo.natW > 0)
                    pezzi.push(tavolo.natW + " × " + tavolo.natH);
                else if (viewer.misuraW > 0)
                    pezzi.push(viewer.misuraW + " × " + viewer.misuraH);
                var peso = viewer.info ? Core.Formato.peso(viewer.info.size) : "";
                if (peso !== "")
                    pezzi.push(peso);
                pezzi.push(Math.round(tavolo.scala * 100) + "%");
                if (viewer.album.length > 1)
                    pezzi.push((viewer.indice + 1) + (viewer.it ? " di " : " of ")
                               + viewer.album.length);
                return pezzi.join("   ·   ");
            }
        }
    }

    // ── Il cartello ──────────────────────────────────────────────────────

    Rectangle {
        anchors.horizontalCenter: tavolo.horizontalCenter
        anchors.top: tavolo.top
        anchors.topMargin: Theme.Effects.space5
        width: testoAvviso.implicitWidth + Theme.Effects.space4 * 2
        height: testoAvviso.implicitHeight + Theme.Effects.space3 * 2
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.panel
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        visible: opacity > 0.01
        opacity: viewer.avviso !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        Text {
            id: testoAvviso
            anchors.centerIn: parent
            text: viewer.avviso
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── Gli strumenti ────────────────────────────────────────────────────

    Rectangle {
        id: strumenti
        anchors.horizontalCenter: tavolo.horizontalCenter
        anchors.bottom: tavolo.bottom
        anchors.bottomMargin: Theme.Effects.space4
        // Sopra il provino: è da qui che ci si esce col mouse, e un pulsante
        // coperto da ciò che deve chiudere è un vicolo cieco.
        z: 6
        width: riga.implicitWidth + Theme.Effects.space3 * 2
        height: Theme.Effects.barHeight
        radius: height / 2
        color: Theme.Colors.panel
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        visible: !viewer.inGalleria && (opacity > 0.01)
        // Visibile ANCHE senza niente aperto, ed è la correzione più
        // importante di questa finestra: la barra conteneva l'unico modo di
        // aprire una cartella, e si nascondeva proprio quando non c'era niente
        // di aperto. Chi lanciava Anteprima dal menù trovava uno schermo nero
        // con scritto «Nessuna immagine aperta» e nessun pulsante da premere —
        // un vicolo cieco. Giacomo: «se lo clicco dal menù mostra uno schermo
        // nero e dice nulla da visualizzare».
        opacity: viewer.chromeVisibile ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        Row {
            id: riga
            anchors.centerIn: parent
            spacing: 2

            // La freccetta per aprire. Icona composta — una cartella con un
            // chevron sotto — perché è l'unico pulsante della barra che apre
            // un ELENCO invece di fare una cosa: il chevron è la promessa che
            // ci sia altro dietro, e senza si preme e si resta sorpresi.
            Ui.SpineButton {
                id: apriBottone
                tooltip: viewer.it ? "Apri una cartella" : "Open a folder"
                onClicked: viewer.apriMenuLuoghi(apriBottone)
                content: Item {
                    width: 30
                    height: 18
                    Ui.Icon {
                        x: 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        name: "folder"
                        alwaysDrawn: true
                        color: Theme.Colors.text
                    }
                    Ui.Icon {
                        x: 19
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11
                        height: 11
                        name: "chevron"
                        alwaysDrawn: true
                        color: Theme.Colors.textMuted
                    }
                }
            }

            Rectangle {
                width: Theme.Effects.hairline
                height: 18
                color: Theme.Colors.edge
                anchors.verticalCenter: parent.verticalCenter
            }

            Strumento {
                icona: "chevron"; giro: 90
                tooltip: viewer.it ? "Precedente" : "Previous"
                spento: viewer.album.length <= 1
                onClicked: viewer.vai(-1)
            }
            Strumento {
                icona: "chevron"; giro: -90
                tooltip: viewer.it ? "Successiva" : "Next"
                spento: viewer.album.length <= 1
                onClicked: viewer.vai(1)
            }

            Rectangle {
                width: Theme.Effects.hairline
                height: 18
                color: Theme.Colors.edge
                anchors.verticalCenter: parent.verticalCenter
            }

            Strumento {
                icona: "minus"
                tooltip: viewer.it ? "Rimpicciolisci" : "Zoom out"
                onClicked: tavolo.zoomDi(1 / 1.4, tavolo.width / 2, tavolo.height / 2)
            }
            Strumento {
                icona: "plus"
                tooltip: viewer.it ? "Ingrandisci" : "Zoom in"
                onClicked: tavolo.zoomDi(1.4, tavolo.width / 2, tavolo.height / 2)
            }
            Strumento {
                icona: "collapse"
                tooltip: viewer.it ? "Adatta alla finestra" : "Fit to window"
                onClicked: tavolo.adattaAllaFinestra()
                active: tavolo.adatta
            }
            Strumento {
                icona: "crop"
                tooltip: viewer.it ? "Dimensione reale" : "Actual size"
                onClicked: tavolo.dimensioneVera()
                active: !tavolo.adatta && Math.abs(tavolo.scala - 1) < 0.01
            }
            Strumento {
                icona: "rotate"
                tooltip: viewer.it ? "Ruota" : "Rotate"
                onClicked: tavolo.rotazione = (tavolo.rotazione + 90) % 360
            }

            Rectangle {
                width: Theme.Effects.hairline
                height: 18
                color: Theme.Colors.edge
                anchors.verticalCenter: parent.verticalCenter
            }

            Strumento {
                // Il provino a contatto: tutta la cartella insieme. È la
                // risposta a «che cosa c'è qui dentro?», che due frecce non
                // danno nemmeno sfogliando per un minuto.
                icona: "grid"
                tooltip: viewer.it ? "Vedile tutte" : "See them all"
                spento: viewer.album.length <= 1
                active: viewer.mostraGriglia
                onClicked: viewer.mostraGriglia = !viewer.mostraGriglia
            }
            Strumento {
                icona: "list"
                tooltip: viewer.it ? "Striscia" : "Filmstrip"
                spento: viewer.album.length <= 1
                active: viewer.strisciaAccesa && viewer.album.length > 1
                onClicked: viewer.accendiStriscia(!viewer.strisciaAccesa)
            }
            Strumento {
                icona: "info"
                tooltip: viewer.it ? "Dettagli dell'immagine" : "Image details"
                spento: viewer.percorso === ""
                active: viewer.mostraDettagli
                onClicked: viewer.mostraDettagli = !viewer.mostraDettagli
            }
            Strumento {
                icona: "screen"
                tooltip: viewer.it ? "Schermo intero" : "Fullscreen"
                active: viewer.aTuttoSchermo
                onClicked: viewer.schermoIntero()
            }
            Strumento {
                icona: "more"
                tooltip: viewer.it ? "Altro" : "More"
                onClicked: viewer.apriMenuDaPulsante(strumenti)
            }
        }
    }

    // ── Quando la cornice sparisce ───────────────────────────────────────
    //
    // Dopo un po' di mouse fermo, e adesso anche in finestra. Prima spariva
    // solo a schermo intero, con questa ragione scritta qui: «nascondere i
    // comandi di una finestra normale è un gioco a indovinelli».
    //
    // Vale ancora, e infatti restano due garanzie che tolgono l'indovinello:
    // la cornice torna al PRIMO movimento del mouse, e non sparisce mai se non
    // c'è un'immagine aperta — cioè proprio quando i comandi sono l'unica cosa
    // che si può usare. In finestra si aspetta più a lungo che a schermo
    // intero: lì si è venuti a guardare, qui si sta ancora lavorando.
    //
    // Giacomo: «anche essa dopo un po' sì deve nascondere e passando con il
    // mouse ricompare».
    // In galleria la cornice del visualizzatore non c'entra niente: gli
    // strumenti sono «ruota», «ritaglia», «ingrandisci» — comandi che agiscono
    // su UNA fotografia aperta, e in galleria non ce n'è nessuna. Senza questa
    // condizione restavano accesi sopra la griglia, fotografati il 30 agosto
    // 2026: una barra di strumenti che non comandano niente.
    readonly property bool chromeVisibile: !viewer.inGalleria
        && (viewer.percorso === "" || viewer.mostraGriglia || viewer.mossoDaPoco)

    property bool mossoDaPoco: true

    Timer {
        id: quiete
        interval: viewer.aTuttoSchermo ? 2500 : 4000
        onTriggered: viewer.mossoDaPoco = false
    }

    MouseArea {
        // Non intercetta niente: sta sopra per SAPERE che il mouse si muove, e
        // lascia passare ogni clic a chi sta sotto.
        anchors.fill: tavolo
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        propagateComposedEvents: true
        onPositionChanged: {
            viewer.mossoDaPoco = true;
            quiete.restart();
        }
    }

    // Cambiando modo la cornice torna e il conto riparte da capo: l'intervallo
    // non è lo stesso nei due casi, e un timer già in corsa finirebbe col
    // tempo sbagliato.
    onATuttoSchermoChanged: {
        viewer.mossoDaPoco = true;
        quiete.restart();
    }

    // ── Niente da guardare ───────────────────────────────────────────────

    Column {
        anchors.centerIn: tavolo
        spacing: Theme.Effects.space3
        // «Nessuna immagine aperta» è vero e inutile in galleria: lì di
        // immagini ce ne sono centinaia, semplicemente non se ne sta
        // guardando una. La galleria ha il suo messaggio, per il suo caso.
        visible: viewer.percorso === "" && !viewer.inGalleria

        Ui.Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 48
            height: 48
            name: "image"
            color: Theme.Colors.textFaint
            alwaysDrawn: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: viewer.it ? "Nessuna immagine aperta" : "No image open"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeLG
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            // Si nomina il pulsante che c'è, invece di mandare altrove: la
            // barra in basso adesso è visibile anche qui, e la cartella si
            // sceglie senza uscire da questa finestra.
            text: viewer.it
                  ? "Premi la cartella qui sotto per sceglierne una,\n"
                  + "oppure trascina qui un'immagine"
                  : "Press the folder button below to choose one,\n"
                  + "or drop an image here"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── Trascinare dentro un'immagine ────────────────────────────────────

    DropArea {
        anchors.fill: tavolo
        onDropped: (drop) => {
            var urls = drop.urls || [];
            var paths = [];
            for (var i = 0; i < urls.length; i++) {
                var u = String(urls[i]);
                if (u.indexOf("file://") === 0)
                    paths.push(decodeURIComponent(u.substring(7)));
            }
            if (paths.length > 0)
                viewer.showAll(paths);
        }
    }

    // ── Il menu del tasto destro ─────────────────────────────────────────

    /// I televisori accesi adesso. Si chiede all'apertura e poi ogni tanto: la
    /// scoperta costa due secondi di rete, e rifarla a ogni clic destro
    /// vorrebbe dire un menu che si apre in ritardo.
    property var schermiTrovati: []

    Timer {
        interval: 120000
        repeat: true
        // Solo con Anteprima davanti: in secondo piano non apre nessun menu.
        running: Qt.application.state === Qt.ApplicationActive
        triggeredOnStart: true
        onTriggered: Core.Ipc.trasmettiCerca()
    }

    Connections {
        target: Core.Ipc
        function onTrasmettiSchermi(elenco) {
            viewer.schermiTrovati = elenco || [];
        }
        function onTrasmettiEsito(e) {
            if (!e)
                return;
            viewer.avviso = e.ok === true
                ? (viewer.it ? "Sto mandando a " + String(e.verso) + "."
                             : "Sending to " + String(e.verso) + ".")
                : String(e.error || (viewer.it ? "Non è andata."
                                               : "It didn't work."));
            avvisoTimer.restart();
        }
    }

    /// Su quale file agisce il menu aperto adesso.
    ///
    /// ── Perché non basta `percorso` ────────────────────────────────────
    ///
    /// Perché nella GALLERIA `percorso` è vuoto per costruzione: `inGalleria`
    /// vuol dire proprio «nessun file aperto». Il tasto destro su una
    /// miniatura mandava qui un percorso che veniva **buttato via**
    /// (`onMenu: (p, x, y) => viewer.apriMenu(x, y)`), e `apriMenu` usciva
    /// subito perché `percorso` era vuoto: nella galleria il menu **non si
    /// apriva affatto**. Trovato rileggendo, il 4 settembre 2026.
    property string menuSu: ""
    /// La foto su cui si è aperto il menu della galleria è fra le preferite?
    /// Decide se la voce dice «aggiungi» o «togli».
    property bool menuPreferito: false

    readonly property string bersaglio:
        viewer.menuSu !== "" ? viewer.menuSu : viewer.percorso

    /// Le voci «Trasmetti a …», una per televisore acceso.
    ///
    /// Una voce per televisore e non un sottomenu: questo menu i sottomenu non
    /// li sa fare, e in una casa i televisori sono due o tre — scriverne il
    /// nome per esteso è anche un clic in meno.
    function vociTrasmetti(quale) {
        var v = [];
        if (!quale || quale === "" || !viewer.media(quale))
            return v;
        for (var i = 0; i < viewer.schermiTrovati.length; i++) {
            var tv = viewer.schermiTrovati[i];
            v.push({ "label": (viewer.it ? "Trasmetti a " : "Cast to ")
                              + String(tv.nome),
                     "icon": "screen",
                     "action": "trasmetti:" + String(tv.id) });
        }
        return v;
    }

    /// Il menu di una miniatura della galleria.
    ///
    /// Non è quello dell'immagine aperta, e la differenza non è pigrizia:
    /// «Apri con…» ha bisogno del tipo del file, che il demone conosce per
    /// quello aperto e non per una miniatura qualunque. Qui c'è «Apri», che
    /// fa la cosa che serve — e nella galleria è anche quella che si vuole.
    function vociGalleria(quale) {
        var v = [];
        v.push({ "label": viewer.it ? "Apri" : "Open",
                 "icon": "image", "action": "apri-questo" });
        // La stella: la galleria la disegnava già sulle preferite, ma non
        // c'era modo di metterla (5 ottobre 2026).
        v.push({ "label": viewer.menuPreferito
                          ? (viewer.it ? "Togli dai preferiti" : "Remove from favourites")
                          : (viewer.it ? "Aggiungi ai preferiti" : "Add to favourites"),
                 "icon": "star", "action": "preferito" });
        var tv = viewer.vociTrasmetti(quale);
        for (var i = 0; i < tv.length; i++)
            v.push(tv[i]);
        v.push({ "separator": true });
        v.push({ "label": viewer.it ? "Imposta come sfondo" : "Set as wallpaper",
                 "icon": "image", "action": "sfondo" });
        v.push({ "label": viewer.it ? "Mostra nella cartella" : "Show in folder",
                 "icon": "folder", "action": "cartella" });
        v.push({ "label": viewer.it ? "Copia il percorso" : "Copy path",
                 "icon": "clipboard", "action": "copia" });
        v.push({ "separator": true });
        v.push({ "label": viewer.it ? "Sposta nel cestino" : "Move to trash",
                 "icon": "trash", "action": "cestina", "danger": true });
        return v;
    }

    function voci() {
        var v = [];
        v.push({ "label": viewer.it ? "Imposta come sfondo" : "Set as wallpaper",
                 "icon": "image", "action": "sfondo" });
        v.push({ "label": viewer.it ? "Mostra nella cartella" : "Show in folder",
                 "icon": "folder", "action": "cartella" });
        v.push({ "label": viewer.it ? "Apri con…" : "Open with…",
                 "icon": "apps", "action": "apri" });
        var tv = viewer.vociTrasmetti(viewer.bersaglio);
        for (var i = 0; i < tv.length; i++)
            v.push(tv[i]);
        v.push({ "separator": true });
        v.push({ "label": viewer.it ? "Copia il percorso" : "Copy path",
                 "icon": "clipboard", "action": "copia" });
        v.push({ "separator": true });
        v.push({ "label": viewer.it ? "Sposta nel cestino" : "Move to trash",
                 "icon": "trash", "action": "cestina", "danger": true });
        return v;
    }

    /// Dove eravamo quando si è aperto il menu: serve al secondo menu, quello
    /// di «Apri con…», che deve comparire nello stesso punto.
    property real menuX: 0
    property real menuY: 0

    function apriMenu(x, y) {
        viewer.menuSu = "";
        if (viewer.percorso === "")
            return;
        // Il menu è una superficie a sé e vuole coordinate dello SCHERMO: le
        // sue e quelle della finestra non sono le stesse, e passargli le
        // seconde lo fa comparire a qualche centinaio di pixel da dove si è
        // cliccato.
        var p = tavolo.mapToGlobal(x, y);
        viewer.menuX = p.x;
        viewer.menuY = p.y;
        menuFile.openAtCursor(viewer.voci());
    }

    /// Il tasto destro su una miniatura della galleria.
    ///
    /// Il percorso arriva e **si tiene**: prima veniva scartato, e il menu non
    /// si apriva affatto.
    function apriMenuGalleria(quale, x, y, preferito) {
        if (!quale || quale === "")
            return;
        viewer.menuSu = quale;
        viewer.menuPreferito = preferito === true;
        // ── Perché NON si usa `openAt` con queste coordinate ────────────
        //
        // Perché non sono coordinate dello schermo. `Miniatura.qml` fa un
        // `mapToGlobal`, ma **su Wayland una finestra non sa dove si trova**:
        // quel «globale» è relativo alla finestra, e il menu comparirebbe
        // spostato di tutta la posizione della finestra. È il difetto che
        // Giacomo aveva descritto come «menu fuori posto», ed è la ragione
        // per cui `openAtCursor` esiste. Provato a scavalcarlo il 4 settembre
        // 2026: il menu non compariva dove si era premuto.
        menuFile.openAtCursor(viewer.vociGalleria(quale));
    }

    function apriMenuDaPulsante(elemento) {
        viewer.menuSu = "";
        var p = elemento.mapToGlobal(elemento.width / 2, 0);
        viewer.menuX = p.x;
        viewer.menuY = p.y;
        menuFile.openAbove(p.x, p.y, viewer.voci());
    }

    function apriMenuLuoghi(elemento) {
        var p = elemento.mapToGlobal(elemento.width / 2, 0);
        menuLuoghi.openAbove(p.x, p.y, viewer.vociApri());
    }

    ContextMenu {
        id: menuLuoghi
        onTriggered: (action) => {
            if (action === "sfoglia") {
                Quickshell.execDetached(["minerva-files",
                                         viewer.cartella !== "" ? viewer.cartella
                                                                : viewer.casa]);
                return;
            }
            if (action.indexOf("dir:") === 0)
                viewer.apriCartella(action.substring(4));
        }
    }

    ContextMenu {
        id: menuFile
        centred: false
        onTriggered: (action) => {
            if (action.indexOf("trasmetti:") === 0) {
                // Il tipo NON si dice: lo trova il demone guardando dentro al
                // file. Un `.mp4` annunciato come fotografia è schermo nero.
                Core.Ipc.trasmettiManda(viewer.bersaglio, action.substring(10));
                viewer.avviso = viewer.it ? "Trasmetto…" : "Casting…";
                avvisoTimer.restart();
                return;
            }
            switch (action) {
            case "apri-questo": viewer.show(viewer.bersaglio); break;
            case "sfondo":   viewer.comeSfondo(viewer.bersaglio); break;
            case "cartella": viewer.mostraNellaCartella(viewer.bersaglio); break;
            case "apri":
                // Un menu non può contenerne un altro, e va bene così: il
                // secondo si apre dove si era, e chi lo guarda vede l'elenco
                // prendere il posto di quello di prima.
                menuApri.openAt(viewer.menuX, viewer.menuY, viewer.vociApriCon());
                break;
            case "copia":
                // `wl-copy` come dappertutto in Minerva: su Wayland gli
                // appunti sono di chi ha il fuoco, e un programma che scrive
                // negli appunti mentre non ce l'ha non scrive niente.
                //
                // Il percorso passa come ARGOMENTO (`$1`), non incollato nella
                // riga: incollato, un file chiamato ``foto`comando`.png``
                // faceva eseguire quel comando a chi ne copiava il percorso.
                Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy",
                                         "sh", viewer.bersaglio]);
                break;
            case "cestina":  viewer.cestina(viewer.bersaglio); break;
            case "preferito":
                Core.Ipc.fotoSegnaPreferito(viewer.bersaglio, !viewer.menuPreferito);
                break;
            }
        }
    }

    ContextMenu {
        id: menuApri
        onTriggered: (action) => {
            if (action.indexOf("app:") !== 0 || viewer.percorso === "")
                return;
            Core.Ipc.openWith(action.substring(4), [viewer.percorso]);
        }
    }

    // ── I tasti ──────────────────────────────────────────────────────────
    //
    // `Shortcut` e non un gestore sull'Item: guardano la finestra intera e non
    // dipendono da chi ha il fuoco dentro. È la stessa ragione per cui li usa
    // il gestore file.

    Shortcut { sequences: ["Right", "Space"]; onActivated: viewer.vai(1) }
    Shortcut { sequences: ["Left", "Backspace"]; onActivated: viewer.vai(-1) }
    Shortcut { sequence: "Home"; onActivated: viewer.vaiA(0) }
    Shortcut { sequence: "End";  onActivated: viewer.vaiA(viewer.album.length - 1) }

    Shortcut {
        sequences: ["+", "=", "Ctrl++", "Ctrl+="]
        onActivated: tavolo.zoomDi(1.4, tavolo.width / 2, tavolo.height / 2)
    }
    Shortcut {
        sequences: ["-", "Ctrl+-"]
        onActivated: tavolo.zoomDi(1 / 1.4, tavolo.width / 2, tavolo.height / 2)
    }
    Shortcut { sequences: ["0", "Ctrl+0"]; onActivated: tavolo.adattaAllaFinestra() }
    Shortcut { sequences: ["1", "Ctrl+1"]; onActivated: tavolo.dimensioneVera() }

    Shortcut { sequence: "R"; onActivated: tavolo.rotazione = (tavolo.rotazione + 90) % 360 }
    Shortcut { sequence: "Shift+R"; onActivated: tavolo.rotazione = (tavolo.rotazione + 270) % 360 }

    Shortcut { sequences: ["F", "F11"]; onActivated: viewer.schermoIntero() }
    Shortcut { sequence: "Delete"; onActivated: viewer.cestina() }
    Shortcut { sequence: "Ctrl+W"; onActivated: viewer.requestClose() }

    // Esc esce dallo schermo intero se ci si è; altrimenti chiude. Un Esc che
    // chiude la finestra mentre si è a schermo intero fa perdere il posto
    // nell'album per aver premuto il tasto che tutti premono per «torna
    // indietro».
    Shortcut { sequence: "G"; onActivated: viewer.mostraGriglia = !viewer.mostraGriglia }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            // In ordine, dal più recente al più antico: prima si chiude quello
            // che si è appena aperto. Un Esc che chiude la finestra mentre si
            // guarda il provino fa perdere il posto per aver premuto il tasto
            // che tutti premono per «torna indietro».
            if (viewer.mostraGriglia)
                viewer.mostraGriglia = false;
            else if (galleriaLoader.item && galleriaLoader.item.quanteScelte > 0)
                galleriaLoader.item.svuotaScelta();
            else if (viewer.aTuttoSchermo)
                viewer.schermoIntero();
            else
                viewer.requestClose();
        }
    }
}
