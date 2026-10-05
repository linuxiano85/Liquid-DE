pragma Singleton
import QtQuick
import Quickshell
import "." as Core

// Wallpaper — Lo sfondo: quale, e ogni quanto cambia.
//
// Stava sparso in due posti — il pannello Aspetto lo applicava, la scrivania lo
// riapplicava all'avvio — e ognuno dei due sapeva metà della storia. Qui c'è
// tutto: quale immagine, come si applica, e il giro automatico.
//
// ── TRE MODI, NON UNO ────────────────────────────────────────────────────
//
// `minerva`  gli sfondi disegnati per questo ambiente, sei, che stanno tutti
//            in una schermata sola;
// `image`    una fotografia scelta a mano, una e basta;
// `folder`   una cartella che gira da sola, in ordine o a caso.
//
// La distinzione serve a risolvere un difetto preciso: scegliendo una cartella
// con dentro mille fotografie, il pannello ne faceva una griglia da scorrere
// per un minuto buono. Ma chi indica una cartella con mille fotografie non sta
// scegliendo UNA fotografia — sta dicendo «pescale tu». Quindi in quel modo non
// si mostra nessuna griglia: si mostra quella attuale e un pulsante «la
// prossima». La griglia resta solo dove ha senso, cioè sui sei di Minerva.
QtObject {
    id: paper

    readonly property string mode: Core.Ipc.get("desktop.wallpaperMode", "minerva")
    readonly property string current: paper.risolvi(Core.Ipc.get("desktop.wallpaper", ""))
    readonly property string folder: Core.Ipc.get("desktop.wallpaperFolder", "")
    /// Ogni quanti minuti cambia. Zero: mai.
    readonly property int rotateMinutes: Core.Ipc.get("desktop.rotateMinutes", 0)
    readonly property bool rotateRandom: Core.Ipc.get("desktop.rotateRandom", false)

    /// Gli sfondi di Minerva, che viaggiano con la shell.
    readonly property string ownDir: Quickshell.shellDir + "/assets/wallpapers/"
    readonly property var own: [
        { "file": "continuum.png", "it": "Continuum",  "en": "Continuum" },
        { "file": "aurora.png",    "it": "Aurora",     "en": "Aurora" },
        { "file": "orbite.png",    "it": "Orbite",     "en": "Orbits" },
        { "file": "reticolo.png",  "it": "Reticolo",   "en": "Lattice" },
        { "file": "onda.png",      "it": "Onda",       "en": "Wave" },
        { "file": "quiete.png",    "it": "Quiete",     "en": "Quiet" }
    ]

    function ownPath(file) {
        return paper.ownDir + file;
    }

    /// Uno sfondo di Minerva vive dove vive QUESTA shell.
    ///
    /// Si salva come percorso assoluto, e quel percorso porta con sé la
    /// cartella da cui la shell girava quel giorno. Il 4 ottobre 2026 era
    /// `~/Scaricati/Liquid-DE-principale`: spostata la cartella, lo sfondo
    /// puntava al vuoto. Qualunque percorso dentro `minerva-shell/assets/`
    /// si legge quindi dalla shell che sta girando adesso. Le immagini
    /// dell'utente restano come sono.
    function risolvi(path) {
        var segno = "/minerva-shell/assets/";
        var i = String(path).indexOf(segno);
        if (i === -1)
            return path;
        return Quickshell.shellDir + "/assets/" + path.slice(i + segno.length);
    }

    // ── Applicare ────────────────────────────────────────────────────────

    /// Mette lo sfondo. Una riga, perché non c'è più niente da comandare.
    ///
    /// Prima qui c'erano tre comandi a `hyprpaper` più la riscrittura del suo
    /// file di configurazione, e un ciclo di tentativi nella scrivania che
    /// insisteva per dieci secondi perché quel programma poteva non essere
    /// ancora in piedi. Adesso lo sfondo lo disegna `menu/WallpaperLayer.qml`,
    /// che è una superficie di Minerva: si scrive dove sta l'immagine e la
    /// superficie ce la mette, con una dissolvenza. Non c'è nessun processo da
    /// aspettare, nessun file di un altro progetto da tenere aggiornato, e
    /// nessun modo che al riavvio si torni indietro — l'impostazione È lo
    /// stato.
    function apply(path) {
        if (!path || path === "")
            return;
        Core.Ipc.setSetting("desktop.wallpaper", path);
    }

    /// «Questa fotografia è il mio sfondo.»
    ///
    /// Diverso da `apply`, e la differenza conta. `apply` mette l'immagine e
    /// basta: la usano la griglia delle Impostazioni e il giro automatico,
    /// che stanno già dentro un modo. Questa la chiama chi arriva da FUORI —
    /// il gestore file, l'Anteprima, la scrivania — dove il modo in cui si
    /// era può essere qualunque.
    ///
    /// Senza il cambio di modo il gesto tradiva: scegliendo una foto mentre
    /// era acceso «una cartella che gira ogni 5 minuti», l'immagine compariva
    /// e cinque minuti dopo se ne andava senza che nessuno avesse toccato
    /// niente. Sceglierne una a mano vuol dire «questa, e ferma».
    function scegli(path) {
        if (!path || path === "")
            return;
        Core.Ipc.setSetting("desktop.wallpaperMode", "image");
        Core.Ipc.setSetting("desktop.wallpaper", path);
    }

    // ── Il giro automatico ───────────────────────────────────────────────
    //
    // Il giro NON è un privilegio della cartella. Nasce lì perché lì era
    // evidente, ma la domanda giusta è un'altra: che cos'è che gira? Un
    // MAZZO di immagini. Una cartella è un mazzo che sta su un disco; i sei
    // sfondi di Minerva sono un mazzo che viaggia con la shell. Fatta la
    // domanda così, tenere il giro in un modo solo era arbitrario — e infatti
    // in Impostazioni si potevano già scegliere «ogni 5 minuti, a caso» con
    // gli sfondi di Minerva davanti, e non succedeva niente: due comandi che
    // rispondevano al vuoto.
    //
    // Da qui in giù, quindi, non si parla più di cartelle ma di `pool`: chi lo
    // riempie è l'unica cosa che cambia fra un modo e l'altro.

    /// Le immagini fra cui si gira, in ordine stabile.
    property var pool: []
    property int poolAt: -1

    onFolderChanged: paper.rescan()
    onModeChanged: paper.rescan()

    // All'avvio `mode` può NON cambiare mai: se l'impostazione salvata è la
    // stessa di partenza, il segnale non scatta e il mazzo resterebbe vuoto
    // per sempre. Si riempie all'accensione e di nuovo quando il demone
    // risponde, perché prima di allora le impostazioni non si sanno.
    Component.onCompleted: paper.rescan()

    property Connections _daemon: Connections {
        target: Core.Ipc
        function onConnectedChanged() { if (Core.Ipc.connected) paper.rescan(); }
        function onSettingsReceived() { if (paper.pool.length === 0) paper.rescan(); }
    }

    function rescan() {
        if (paper.mode === "minerva") {
            // Nessun disco da interrogare: il mazzo è quello che viaggia con
            // la shell, e l'ordine è quello in cui sono elencati sopra.
            var list = [];
            for (var i = 0; i < paper.own.length; i++)
                list.push(paper.ownPath(paper.own[i].file));
            paper.pool = list;
            paper.poolAt = list.indexOf(paper.current);
            return;
        }
        paper.pool = [];
        paper.poolAt = -1;
        if (paper.mode !== "folder" || paper.folder === "")
            return;
        Core.Ipc.fsList(paper.folder, false, "wallpaperPool");
    }

    /// Se lo sfondo cambia per altra via — la griglia in Impostazioni, il menu
    /// della scrivania — il segnaposto lo segue, altrimenti «la prossima»
    /// ripartirebbe da dove eravamo mezz'ora fa.
    onCurrentChanged: {
        var at = paper.pool.indexOf(paper.current);
        if (at !== -1 && at !== paper.poolAt)
            paper.poolAt = at;
        // E il conto alla rovescia riparte: hai appena scelto tu, sarebbe
        // sgarbato cambiartelo fra dieci secondi.
        paper._rotation.elapsed = 0;
    }

    readonly property var extensions: [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".jxl"]

    function isImage(name) {
        var lower = String(name).toLowerCase();
        for (var i = 0; i < paper.extensions.length; i++) {
            var e = paper.extensions[i];
            if (lower.endsWith(e))
                return true;
        }
        return false;
    }

    property Connections _listing: Connections {
        target: Core.Ipc
        function onFileListingReceived(listing) {
            if (listing.pane !== "wallpaperPool")
                return;
            var found = [];
            var entries = listing.entries || [];
            for (var i = 0; i < entries.length; i++)
                if (!entries[i].isDir && paper.isImage(entries[i].name))
                    found.push(entries[i].path);
            // In ordine alfabetico, sempre: «in ordine» deve voler dire lo
            // stesso ordine domani, e il disco non promette niente.
            found.sort();
            paper.pool = found;
            paper.poolAt = found.indexOf(paper.current);
        }
    }

    /// Le ultime viste, la più recente in fondo. Serve solo al caso: in
    /// ordine, «indietro» si sa calcolare.
    property var history: []

    /// La prossima immagine del mazzo. Fa il giro.
    ///
    /// «Indietro» vuol dire indietro anche a caso, e questo è il punto meno
    /// ovvio di tutta la funzione. Pescando un'altra a caso si otterrebbe una
    /// cosa che si comporta come «avanti» ma si chiama «Precedente»: chi
    /// preme quel tasto ha visto passare uno sfondo che gli piaceva e lo
    /// rivuole, non ne vuole un terzo. Quindi le ultime viste si tengono da
    /// parte, e il tasto le ripercorre.
    function next(step) {
        if (paper.pool.length === 0)
            return;
        var i;
        var back = (step || 1) < 0;

        if (back && paper.rotateRandom && paper.history.length > 0) {
            var h = paper.history.slice();
            i = h.pop();
            paper.history = h;
        } else if (!back && paper.rotateRandom && paper.pool.length > 1) {
            // Mai due volte di fila la stessa: con poche immagini il caso puro
            // ripete, e una ripetizione sembra il giro che si è inceppato.
            do {
                i = Math.floor(Math.random() * paper.pool.length);
            } while (i === paper.poolAt);
            paper._remember(paper.poolAt);
        } else {
            i = (paper.poolAt + (step || 1) + paper.pool.length) % paper.pool.length;
        }

        paper.poolAt = i;
        paper.apply(paper.pool[i]);
    }

    function _remember(at) {
        if (at < 0)
            return;
        var h = paper.history.slice();
        h.push(at);
        // Venti bastano: più indietro di così non torna nessuno, e una lista
        // che cresce per tutta la sessione è una perdita lenta.
        while (h.length > 20)
            h.shift();
        paper.history = h;
    }

    /// Chi tiene il turno di far girare il mazzo.
    ///
    /// Da quando Minerva è più di un processo — il gestore file, le
    /// Impostazioni — questo oggetto esiste in copie diverse che non si vedono
    /// fra loro. Il timer qui sotto però deve battere in UNA sola: due copie
    /// che chiamano `next()` ogni dieci minuti cambiano lo sfondo ogni cinque,
    /// e chi tiene le Impostazioni aperte vedrebbe la scrivania accelerare
    /// senza motivo. La shell è quella che DISEGNA la scrivania, quindi è lei
    /// a prendersi il turno (`Core.Wallpaper.rotates = true` in shell.qml);
    /// tutte le altre copie leggono e basta.
    property bool rotates: false

    property Timer _rotation: Timer {
        // Un solo minuto di risoluzione basta: nessuno regola uno sfondo al
        // secondo, e un timer che scatta di continuo per contare i minuti è
        // lavoro buttato.
        interval: 60000
        repeat: true
        // Non più «se è una cartella», ma «se c'è più di una carta nel mazzo»:
        // con una sola immagine il giro cambierebbe niente al minuto.
        running: paper.rotates && paper.rotateMinutes > 0 && paper.pool.length > 1
        property int elapsed: 0
        onRunningChanged: elapsed = 0
        onTriggered: {
            elapsed += 1;
            if (elapsed < paper.rotateMinutes)
                return;
            elapsed = 0;
            paper.next(1);
        }
    }
}
