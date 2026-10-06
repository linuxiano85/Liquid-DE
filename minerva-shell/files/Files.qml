pragma Singleton
import QtQuick
import Quickshell
import "../core" as Core

// Files — Ciò che i due riquadri hanno in comune.
//
// Gli appunti dei file stanno qui e non dentro il gestore: «copia» si preme in
// un riquadro e «incolla» nell'altro, quindi il contenuto degli appunti non
// può appartenere a nessuno dei due.
QtObject {
    id: files

    /// La cartella personale, letta dall'ambiente e non chiesta a una shell:
    /// deve valere SUBITO. Un valore che arriva mezzo secondo dopo farebbe
    /// aprire il gestore file su `/home` per poi saltare altrove sotto gli
    /// occhi di chi guarda.
    readonly property string home: {
        var h = Quickshell.env("HOME");
        return (h && h !== "") ? h : "/home";
    }

    // ── La colonna di sinistra ───────────────────────────────────────────
    //
    // Era un elenco scritto a mano: Home, Documenti, Immagini, Musica,
    // Scaricati, Sistema. Funzionava su questa macchina, e solo su questa: i
    // nomi italiani delle cartelle personali esistono perché il sistema è in
    // italiano, e chi le ha spostate su un altro disco vedeva cinque voci che
    // non portavano da nessuna parte. Adesso le cartelle personali le dice il
    // demone leggendo `user-dirs.dirs`, che è il file che lo standard
    // freedesktop dedica esattamente a questa domanda.
    //
    // La colonna ha tre parti, e sono tre cose diverse:
    //   `places`  le cartelle di casa, che ci sono e basta;
    //   `pinned`  i percorsi che ha scelto l'utente, che restano fra le
    //             sessioni perché stanno nelle impostazioni;
    //   `volumes` i dischi, che vanno e vengono e si possono montare.

    /// Le cartelle personali, come le riporta il demone.
    property var userPlaces: []

    /// Fissi: ci sono sempre, e non dipendono da nessuna configurazione.
    readonly property var fixedPlaces: [
        { "icon": "cartella-casa", "it": "Home", "en": "Home", "path": files.home,
          "kind": "home" },
        { "icon": "disco",  "it": "Sistema", "en": "System", "path": "/",
          "kind": "root" }
    ]

    // ── I nomi della colonna di sinistra ─────────────────────────────────
    //
    // Erano sbagliati, ed erano sbagliati in un modo che con le icone di
    // Minerva quasi non si vedeva e con un tema classico acceso diventava
    // ridicolo. Misurato il 18 agosto 2026:
    //
    //     Scaricati  chiedeva  «clipboard»  → una lavagnetta per appunti
    //     Video      chiedeva  «gamepad»    → un joypad
    //     Scrivania  chiedeva  «apps»       → una griglia di quadretti
    //     Sistema    chiedeva  «cpu»        → un processore
    //
    // E intanto i nomi giusti — `cartella-scaricati`, `cartella-video`,
    // `cartella-scrivania` — esistevano già nel demone, nati esattamente per
    // questo, con il ripiego al nostro tratto già scritto in `ui/Icon.qml`.
    // Erano usati dieci righe più in basso, per le icone DENTRO la cartella
    // di casa (`iconeCartelle`), e non qui. Le stesse cartelle avevano quindi
    // due icone diverse a due centimetri di distanza.
    readonly property var placeIcons: ({
        "desktop":   "cartella-scrivania",
        "documents": "cartella-documenti",
        "downloads": "cartella-scaricati",
        "pictures":  "cartella-immagini",
        "music":     "cartella-musica",
        "videos":    "cartella-video",
        "trash":     "trash"
    })

    readonly property var placeNames: ({
        "desktop":   { "it": "Scrivania", "en": "Desktop" },
        "documents": { "it": "Documenti", "en": "Documents" },
        "downloads": { "it": "Scaricati", "en": "Downloads" },
        "pictures":  { "it": "Immagini",  "en": "Pictures" },
        "music":     { "it": "Musica",    "en": "Music" },
        "videos":    { "it": "Video",     "en": "Videos" },
        "trash":     { "it": "Cestino",   "en": "Bin" }
    })

    /// Dove sta il cestino, come lo riporta il demone. Vuoto finché la
    /// risposta non è arrivata.
    ///
    /// Serve per riconoscere «sto guardando dentro il cestino» e cambiare i
    /// comandi di conseguenza. Il percorso NON si costruisce qui: dipende da
    /// `XDG_DATA_HOME`, e una seconda copia della regola è una copia che
    /// prima o poi non coincide più.
    readonly property string trashPath: {
        for (var i = 0; i < files.userPlaces.length; i++)
            if (files.userPlaces[i].kind === "trash")
                return files.userPlaces[i].path;
        return "";
    }

    /// Vero se il percorso è il cestino o sta dentro il cestino.
    function inTrash(path) {
        if (files.trashPath === "" || !path)
            return false;
        return path === files.trashPath
               || path.indexOf(files.trashPath + "/") === 0;
    }

    /// L'elenco completo del primo gruppo: casa, le cartelle personali che
    /// esistono davvero, e la radice.
    readonly property var places: {
        var out = [ files.fixedPlaces[0] ];
        for (var i = 0; i < files.userPlaces.length; i++) {
            var p = files.userPlaces[i];
            // Pubblici e Modelli arrivano per l'icona, non per la barra:
            // due voci in più che quasi nessuno apre. Lo dice il demone.
            if (p.nellaBarra === false)
                continue;
            var names = files.placeNames[p.kind];
            out.push({
                "icon": files.placeIcons[p.kind] || "folder",
                // Se il tipo non è fra quelli che sappiamo nominare si usa il
                // nome vero della cartella: meglio «Scrivania» che niente.
                "it": names ? names.it : p.name,
                "en": names ? names.en : p.name,
                "path": p.path,
                "kind": p.kind,
                // Il cestino porta anche se è vuoto: la voce si abbassa.
                "vuoto": p.vuoto
            });
        }
        out.push(files.fixedPlaces[1]);
        return out;
    }

    // ── Percorsi fissati ─────────────────────────────────────────────────
    //
    // Stanno nelle impostazioni e non in una proprietà: una proprietà nasce
    // col processo, e un percorso «che uso sempre» che sparisce a ogni
    // riavvio della shell non è fissato, è ricordato male.

    readonly property var pinned: Core.Ipc.get("files.pinned", [])

    function isPinned(path) {
        var list = files.pinned;
        for (var i = 0; i < list.length; i++)
            if (list[i] === path)
                return true;
        return false;
    }

    function togglePinned(path) {
        if (!path || path === "")
            return;
        var list = [];
        var found = false;
        for (var i = 0; i < files.pinned.length; i++) {
            if (files.pinned[i] === path) {
                found = true;
                continue;
            }
            list.push(files.pinned[i]);
        }
        if (!found)
            list.push(path);
        Core.Ipc.setSetting("files.pinned", list);
    }

    // ── Come si guarda una cartella ──────────────────────────────────────
    //
    // Elenco o griglia, e quanto grandi le icone. Non è una preferenza
    // estetica: una cartella di fotografie in elenco è una colonna di nomi
    // tutti uguali, e una cartella di duecento documenti in griglia costringe
    // a scorrere per pagine dove un elenco stava in una schermata. Sono due
    // domande diverse fatte alla stessa cartella, e servono entrambe.
    //
    // La scelta si ricorda nelle impostazioni: si sceglie una volta e vale
    // anche domani. Ogni riquadro però può cambiarla per conto suo — la
    // doppia visuale serve proprio a guardare due cose diverse insieme.

    /// Quanto è grande l'icona in elenco, per ognuno dei cinque scatti.
    readonly property var listIconSizes: [15, 20, 26, 34, 44]

    /// Quanto è larga la piastrella in griglia, per gli stessi cinque scatti.
    readonly property var gridTileSizes: [76, 100, 132, 172, 216]

    readonly property int zoomMax: files.listIconSizes.length - 1

    readonly property string defaultView: Core.Ipc.get("files.view", "list")
    readonly property int defaultZoom: Core.Ipc.get("files.zoom", 1)
    readonly property string defaultSort: Core.Ipc.get("files.sort", "name")
    readonly property bool defaultSortDesc: Core.Ipc.get("files.sortDesc", false)

    /// L'ultima scelta fatta in un riquadro diventa quella di partenza per i
    /// prossimi. Chi lavora a griglia apre a griglia.
    function rememberView(mode, zoom) {
        if (mode !== files.defaultView)
            Core.Ipc.setSetting("files.view", mode);
        if (zoom !== files.defaultZoom)
            Core.Ipc.setSetting("files.zoom", zoom);
    }

    function rememberSort(by, desc) {
        if (by !== files.defaultSort)
            Core.Ipc.setSetting("files.sort", by);
        if (desc !== files.defaultSortDesc)
            Core.Ipc.setSetting("files.sortDesc", desc);
    }

    // ── Riconoscere i file dal nome ──────────────────────────────────────
    //
    // Il demone non dice il tipo di ogni voce: chiederglielo vorrebbe dire
    // aprire ogni file di una cartella da mille elementi solo per disegnare
    // un'icona. L'estensione basta e costa zero.

    readonly property var _imageExt: ({
        "png": 1, "jpg": 1, "jpeg": 1, "gif": 1, "bmp": 1, "webp": 1,
        "avif": 1, "tif": 1, "tiff": 1, "ico": 1, "jxl": 1
    })

    readonly property var _kindByExt: ({
        "mp3": "music", "flac": "music", "ogg": "music", "opus": "music",
        "wav": "music", "m4a": "music", "aac": "music", "wma": "music",
        "mid": "music", "midi": "music", "aiff": "music", "ape": "music",
        "mp4": "video", "mkv": "video", "webm": "video", "avi": "video",
        "mov": "video", "wmv": "video", "m4v": "video", "mpg": "video",
        "mpeg": "video", "flv": "video", "3gp": "video",
        "zip": "archive", "tar": "archive", "gz": "archive", "xz": "archive",
        "bz2": "archive", "7z": "archive", "rar": "archive", "zst": "archive",
        "tgz": "archive", "lz4": "archive", "iso": "archive", "img": "archive",
        "deb": "archive", "rpm": "archive", "pkg": "archive", "appimage": "archive",
        "pdf": "pdf",
        "odt": "document", "doc": "document", "docx": "document",
        "rtf": "document", "epub": "document", "mobi": "document",
        "txt": "document", "md": "document", "log": "document",
        "tex": "document", "csv": "table",
        "ods": "table", "xls": "table", "xlsx": "table",
        "odp": "slides", "ppt": "slides", "pptx": "slides", "odg": "slides",
        "svg": "image", "psd": "image", "xcf": "image", "kra": "image",
        "raw": "image", "cr2": "image", "nef": "image", "heic": "image",
        "ttf": "font", "otf": "font", "woff": "font", "woff2": "font",
        // Codice sorgente e configurazione. Uno script si APRE ed è codice:
        // l'icona del terminale diceva «programma da eseguire», che per un
        // `.py` in una cartella di lavoro è quasi sempre falso.
        "sh": "code", "bash": "code", "zsh": "code", "fish": "code",
        "py": "code", "js": "code", "mjs": "code", "jsx": "code",
        "tsx": "code", "c": "code", "h": "code", "cpp": "code",
        "hpp": "code", "cc": "code", "rs": "code", "go": "code",
        "java": "code", "kt": "code", "rb": "code", "php": "code",
        "lua": "code", "dart": "code", "qml": "code", "vim": "code",
        // `.ts` è TypeScript molto più spesso di quanto sia un flusso MPEG,
        // almeno nelle cartelle di chi lo vedrà.
        "ts": "code",
        "json": "code", "xml": "code", "yaml": "code", "yml": "code",
        "toml": "code", "ini": "code", "conf": "code", "cfg": "code",
        "css": "code", "scss": "code", "sql": "code", "patch": "code",
        "desktop": "apps",
        "html": "globe", "htm": "globe", "xhtml": "globe"
    })

    /// L'indirizzo con cui Qt carica un file dal disco. Non basta incollare
    /// «file://» davanti: uno spazio spezza l'indirizzo, e `#` e `?` in un URL
    /// vogliono dire «àncora» e «domanda» — un file che si chiama
    /// «appunti #3.png» verrebbe cercato come «appunti » e non trovato mai.
    function fileUrl(path) {
        return "file://" + encodeURI(path)
                           .replace(/#/g, "%23")
                           .replace(/\?/g, "%3F");
    }

    function extension(name) {
        if (!name)
            return "";
        var cut = name.lastIndexOf(".");
        // Un punto in testa è un file nascosto, non un'estensione.
        if (cut <= 0 || cut === name.length - 1)
            return "";
        return name.substring(cut + 1).toLowerCase();
    }

    /// Vero se il file si può disegnare in miniatura. Il formato lo carica Qt
    /// da solo: si elencano quelli che sa leggere, non quelli che esistono.
    function isImage(name) {
        return files._imageExt[files.extension(name)] === 1;
    }

    /// Il nome dell'icona da usare per una voce.
    /// Da percorso di una cartella speciale a icona. Si costruisce dalle
    /// cartelle che il DEMONE dichiara — le stesse che stanno nella barra
    /// laterale — e non da un elenco di nomi scritto qui: «Scaricati» si
    /// chiama «Downloads» in inglese, «Téléchargements» in francese, e in
    /// nessuna di quelle lingue il nome è una garanzia (una cartella chiamata
    /// «Musica» dentro Documenti non è la cartella della musica).
    /// I nostri nomi delle cartelle di casa. Sono nomi a sé («cartella-musica»
    /// e non «musica») perché la cartella della musica e un file musicale sono
    /// due cose diverse, e ogni tema di icone le disegna diverse.
    readonly property var iconeCartelle: ({
        "documents": "cartella-documenti",
        "downloads": "cartella-scaricati",
        "pictures":  "cartella-immagini",
        "music":     "cartella-musica",
        "videos":    "cartella-video",
        "desktop":   "cartella-scrivania",
        "publicshare": "cartella-pubblici",
        "templates": "cartella-modelli"
    })

    readonly property var iconePerPercorso: {
        var m = {};
        for (var i = 0; i < files.userPlaces.length; i++) {
            var p = files.userPlaces[i];
            if (!p.path)
                continue;
            m[p.path] = files.iconeCartelle[p.kind]
                        || files.placeIcons[p.kind] || "folder";
        }
        return m;
    }

    function iconFor(entry) {
        if (!entry)
            return "document";
        if (entry.isDir) {
            // ── Dodici quadrati grigi identici ───────────────────────────
            //
            // È così che si presentava la cartella di casa: Documenti,
            // Immagini, Musica, Video, Scaricati e Scrivania tutte con la
            // stessa icona anonima, mentre nella barra laterale a due
            // centimetri di distanza avevano ognuna la sua. Le si cercava
            // leggendo, una per una, in un elenco in cui l'occhio avrebbe
            // dovuto trovarle da solo.
            var speciale = files.iconePerPercorso[entry.path];
            if (speciale)
                return speciale;
            return "folder";
        }
        var kind = files._kindByExt[files.extension(entry.name)];
        if (kind)
            return kind;
        return files.isImage(entry.name) ? "image" : "document";
    }

    // ── Ordinamento ──────────────────────────────────────────────────────
    //
    // Ordina la shell e non il demone: l'elenco è già qui, riordinarlo costa
    // un millisecondo, e chiedere di nuovo la cartella al demone per cambiare
    // il verso di una freccia sarebbe un giro d'aria per niente.
    //
    // Le cartelle restano SEMPRE in cima, qualunque sia l'ordine. Sono il modo
    // in cui ci si sposta, non uno dei contenuti: mescolarle ai file per
    // dimensione (che per una cartella non vuol dire niente) le renderebbe
    // introvabili.

    function sortEntries(entries, by, desc) {
        if (!entries || entries.length === 0)
            return [];
        var out = entries.slice();
        var dir = desc ? -1 : 1;
        out.sort(function (a, b) {
            if (a.isDir !== b.isDir)
                return a.isDir ? -1 : 1;
            var r = 0;
            switch (by) {
            case "size":
                r = (a.size || 0) - (b.size || 0);
                break;
            case "modified":
                r = (a.modified || 0) - (b.modified || 0);
                break;
            case "type":
                r = files.extension(a.name).localeCompare(files.extension(b.name));
                break;
            }
            // A parità — due file della stessa dimensione, o due cartelle
            // ordinate per dimensione che dimensione non hanno — decide il
            // nome. Senza, l'ordine di quei gruppi cambierebbe a ogni
            // ricaricamento e la stessa cartella sembrerebbe rimescolarsi.
            if (r === 0)
                return a.name.toLowerCase().localeCompare(b.name.toLowerCase()) * dir;
            return r * dir;
        });
        return out;
    }

    /// Tiene solo le voci il cui nome contiene quello che si è scritto.
    ///
    /// Senza distinzione fra maiuscole e minuscole, e cercando OVUNQUE nel
    /// nome e non solo in testa: chi cerca «fattura» in mezzo a
    /// «2026-03-fattura-luce.pdf» la sta cercando davvero, e un filtro che
    /// guarda solo l'inizio del nome non la troverebbe mai.
    function filterEntries(entries, text) {
        if (!entries || !text || text === "")
            return entries || [];
        var needle = text.toLowerCase();
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].name.toLowerCase().indexOf(needle) !== -1)
                out.push(entries[i]);
        }
        return out;
    }

    /// Data leggibile per la colonna «modificato». Oggi si dice l'ora, il
    /// resto la data: «14:32» dice più di «28/07/2026» quando è di stamattina.
    /// La lingua con cui si scrivono i mesi. Non quella del sistema: con
    /// `Qt.formatDate` uscivano «26 Jul» dentro un'interfaccia tutta italiana,
    /// perché quella funzione guarda la localizzazione del processo e non
    /// sa niente della lingua scelta nelle Impostazioni di Minerva.
    readonly property var _locale: Qt.locale(Core.Strings.lang === "it"
                                             ? "it_IT" : "en_GB")

    function humanTime(ms) {
        if (!ms)
            return "";
        var d = new Date(ms);
        var now = new Date();
        if (d.getFullYear() === now.getFullYear()
            && d.getMonth() === now.getMonth()
            && d.getDate() === now.getDate())
            return d.toLocaleTimeString(files._locale, "HH:mm");
        if (d.getFullYear() === now.getFullYear())
            return d.toLocaleDateString(files._locale, "d MMM");
        return d.toLocaleDateString(files._locale, "d MMM yyyy");
    }

    // ── Dischi ───────────────────────────────────────────────────────────

    property var volumes: []

    property Connections _fromDaemon: Connections {
        target: Core.Ipc

        function onPlacesReceived(payload) {
            files.userPlaces = payload.places || [];
        }

        function onVolumesReceived(payload) {
            files.volumes = payload.volumes || [];
        }

        // Il demone parte una volta e la shell si ricarica spesso: si chiede
        // tutto a ogni connessione, non una volta sola all'avvio.
        function onConnectedChanged() {
            if (Core.Ipc.connected)
                files.refresh();
        }
    }

    function refresh() {
        Core.Ipc.fsPlaces();
        Core.Ipc.fsVolumes();
    }

    Component.onCompleted: if (Core.Ipc.connected) files.refresh()

    /// Quante finestre del gestore file sono aperte. Serve al controllo
    /// periodico dei dischi qui sotto.
    property int watchers: 0

    /// I dischi si ricontrollano ogni tanto: una chiavetta infilata adesso
    /// deve comparire senza che si debba riaprire la finestra. Ogni otto
    /// secondi è abbastanza spesso da sembrare immediato e abbastanza raro da
    /// non pesare.
    ///
    /// E gira SOLO con una finestra aperta. Un `lsblk` ogni otto secondi per
    /// tutta la sessione, quando nessuno sta guardando una barra laterale, è
    /// un processo lanciato diecimila volte al giorno per niente: il genere di
    /// spreco che non si vede mai perché ognuno costa pochissimo.
    property Timer _watch: Timer {
        interval: 8000
        repeat: true
        running: Core.Ipc.connected && files.watchers > 0
        onTriggered: Core.Ipc.fsVolumes()
    }

    // ── Appunti dei file ─────────────────────────────────────────────────
    //
    // ── Quelli di tutti, non solo i nostri ───────────────────────────────
    //
    // Fino al 6 ottobre 2026 «Copia» scriveva in questa proprietà e basta:
    // un file copiato qui non si incollava in Dolphin, in Telegram o nel
    // caricamento di Chrome, e uno copiato là non si incollava qui. Adesso
    // copiare e tagliare PUBBLICANO negli appunti di sistema, nel formato che
    // leggono tutti (`text/uri-list`, che `wl-copy` offre anche come testo:
    // incollato in un editor dà i percorsi), e incollare LEGGE gli appunti di
    // sistema — col «tagliato» di GNOME (`x-special/gnome-copied-files`) e di
    // KDE (`application/x-kde-cutselection`).
    //
    // `clipboard` resta: dice se la copia è NOSTRA e se l'abbiamo tagliata,
    // che negli appunti di sistema scritti da `wl-copy` non si può dire.

    /// Percorsi in attesa di essere incollati.
    property var clipboard: []
    /// Vero se sono stati TAGLIATI: incollarli li sposta invece di copiarli.
    property bool clipboardIsCut: false

    /// I file negli appunti di sistema, letti l'ultima volta con
    /// `leggiAppunti`, e se chi li ha messi li aveva tagliati.
    property var appuntiDiSistema: []
    property bool appuntiDiSistemaTagliati: false

    /// C'è qualcosa da incollare: nostro o di un altro programma.
    readonly property bool puoiIncollare: files.clipboard.length > 0
                                          || files.appuntiDiSistema.length > 0

    /// Il testo che abbiamo messo noi negli appunti di sistema: se ci si
    /// ritrova lo stesso, la copia è ancora la nostra.
    property string _nostri: ""

    function _uriDi(percorso) {
        return "file://" + String(percorso).split("/").map(encodeURIComponent).join("/");
    }

    function _percorsoDi(uri) {
        var u = String(uri).trim();
        if (u.indexOf("file://") !== 0)
            return "";
        u = u.substring(7);
        // `file://localhost/…` e `file:///…` sono la stessa cosa; un altro
        // host è un file di un'altra macchina, e non si incolla.
        if (u.indexOf("localhost/") === 0)
            u = u.substring(9);
        if (u.charAt(0) !== "/")
            return "";
        try {
            return decodeURIComponent(u);
        } catch (e) {
            return "";
        }
    }

    function _pubblica(paths) {
        var testo = paths.map(files._uriDi).join("\r\n") + "\r\n";
        files._nostri = testo;
        files.appuntiDiSistema = paths.slice();
        files.appuntiDiSistemaTagliati = false;
        scriviAppunti.start(["wl-copy", "--type", "text/uri-list", "--", testo]);
    }

    function copyToClipboard(paths) {
        files.clipboard = paths.slice();
        files.clipboardIsCut = false;
        files._pubblica(paths);
    }

    function cutToClipboard(paths) {
        files.clipboard = paths.slice();
        files.clipboardIsCut = true;
        files._pubblica(paths);
    }

    /// Svuota gli appunti dopo un taglio incollato. `ancheDiSistema`: la
    /// copia negli appunti di sistema era la nostra, e i file non sono più
    /// dove dice — si toglie, così un secondo «incolla» altrove non cerca
    /// file spariti. Quella di un altro programma non si tocca.
    function clearClipboard(ancheDiSistema) {
        files.clipboard = [];
        files.clipboardIsCut = false;
        files.appuntiDiSistema = [];
        files.appuntiDiSistemaTagliati = false;
        if (ancheDiSistema === true) {
            files._nostri = "";
            scriviAppunti.start(["wl-copy", "--clear"]);
        }
    }

    property var scriviAppunti: Core.Exec {}

    /// Rilegge gli appunti di sistema. `poi`, se c'è, si chiama a lettura
    /// finita con `(percorsi, tagliati)`.
    property var _dopoLettura: []
    function leggiAppunti(poi) {
        if (poi)
            files._dopoLettura = files._dopoLettura.concat([poi]);
        if (leggi.busy)
            return;
        // Una riga col tipo, una con «cut» o «copy», poi gli indirizzi.
        leggi.sh("t=$(wl-paste -l 2>/dev/null); "
            + "if printf '%s\\n' \"$t\" | grep -qx 'x-special/gnome-copied-files'; then "
            + "  echo gnome; wl-paste -n -t x-special/gnome-copied-files; "
            + "elif printf '%s\\n' \"$t\" | grep -qx 'text/uri-list'; then "
            + "  echo uri; "
            + "  if printf '%s\\n' \"$t\" | grep -qx 'application/x-kde-cutselection' "
            + "     && [ \"$(wl-paste -n -t application/x-kde-cutselection)\" = 1 ]; then echo cut; else echo copy; fi; "
            + "  wl-paste -n -t text/uri-list; "
            + "fi");
    }

    property var leggi: Core.Exec {
        onDone: function (uscita) {
            var righe = String(uscita).split(/\r?\n/);
            var percorsi = [];
            var tagliati = false;
            if (righe.length >= 2 && (righe[0] === "gnome" || righe[0] === "uri")) {
                tagliati = righe[1].trim() === "cut";
                for (var i = 2; i < righe.length; i++) {
                    var p = files._percorsoDi(righe[i]);
                    if (p !== "")
                        percorsi.push(p);
                }
            }
            files.appuntiDiSistema = percorsi;
            files.appuntiDiSistemaTagliati = tagliati;
            var chi = files._dopoLettura;
            files._dopoLettura = [];
            for (var k = 0; k < chi.length; k++)
                chi[k](percorsi, tagliati);
        }
    }

    /// Cosa incollare adesso: `{percorsi, tagliati}`. Se negli appunti di
    /// sistema c'è ancora la nostra copia vale il nostro «tagliato», che lì
    /// non si può scrivere; se c'è quella di un altro programma, vale la sua.
    function daIncollare() {
        var sistema = files.appuntiDiSistema;
        if (sistema.length === 0)
            return { "percorsi": files.clipboard.slice(), "tagliati": files.clipboardIsCut,
                     "nostra": true };
        var nostra = sistema.length === files.clipboard.length
            && sistema.every(function (p, i) { return p === files.clipboard[i]; });
        return { "percorsi": sistema.slice(),
                 "tagliati": nostra ? files.clipboardIsCut : files.appuntiDiSistemaTagliati,
                 "nostra": nostra };
    }

    // ── Lo sfondo che una cartella si merita da sola ─────────────────────
    //
    // Le cartelle che il sistema conosce hanno un contenuto prevedibile, e
    // quindi un segno che le racconta: note sparse su Musica, fogli su
    // Documenti, fotogrammi su Video. Non è decorazione — è la stessa idea
    // dello sfondo scelto a mano, solo che qui la scelta la sappiamo fare noi.
    //
    // Il confronto è sul NOME della cartella, in italiano e in inglese, perché
    // le cartelle di sistema si chiamano in un modo o nell'altro a seconda di
    // com'era impostata la lingua il giorno che sono nate — e capita di
    // averle miste.
    readonly property var motiviNoti: ({
        "musica": ["music", "#8B7BC7"],
        "music": ["music", "#8B7BC7"],
        "documenti": ["document", "#7C93C3"],
        "documents": ["document", "#7C93C3"],
        "immagini": ["image", "#6FB3A8"],
        "pictures": ["image", "#6FB3A8"],
        "foto": ["image", "#6FB3A8"],
        "video": ["video", "#CE7B7B"],
        "videos": ["video", "#CE7B7B"],
        "filmati": ["video", "#CE7B7B"],
        "scaricati": ["archive", "#D9915B"],
        "downloads": ["archive", "#D9915B"],
        "scrivania": ["window", "#8A9299"],
        "desktop": ["window", "#8A9299"],
        "modelli": ["copy", "#D6C06A"],
        "templates": ["copy", "#D6C06A"],
        "pubblici": ["globe", "#8FBF7F"],
        "public": ["globe", "#8FBF7F"],
        "progetti": ["code", "#B87BB0"],
        "projects": ["code", "#B87BB0"]
    })

    /// Il motivo che spetta a questa cartella, o `null`.
    function motivoPerCartella(percorso) {
        var nome = files.baseName(percorso).toLowerCase();
        var m = files.motiviNoti[nome];
        if (!m)
            return null;
        return { "tipo": "motivo", "icona": m[0], "valore": m[1] };
    }

    /// Da `file:///casa/tizio/foto.png` a `/casa/tizio/foto.png`.
    ///
    /// È il formato con cui i file viaggiano fra programmi diversi
    /// (`text/uri-list`): quello che arriva da Chrome o da Gwenview arriva
    /// così. Gli indirizzi che non sono file locali si buttano: su un `http://`
    /// non si può né copiare né spostare, e fingere il contrario vorrebbe dire
    /// una copia che fallisce dopo aver detto di sì.
    function percorsiDaUrl(urls) {
        var fuori = [];
        for (var i = 0; i < urls.length; i++) {
            var u = String(urls[i]);
            if (u.indexOf("file://") !== 0)
                continue;
            fuori.push(decodeURIComponent(u.substring(7)));
        }
        return fuori;
    }

    /// La cartella che contiene `path`. Senza la barra finale, tranne per la
    /// radice — «/» è l'unico percorso in cui la barra è il nome.
    ///
    /// Serve al trascinamento: lasciare un file nella cartella in cui è già
    /// non è né una copia né uno spostamento, ed è la domanda da non fare.
    function dirName(path) {
        if (!path)
            return "";
        var p = path;
        if (p.length > 1 && p.charAt(p.length - 1) === "/")
            p = p.substring(0, p.length - 1);
        var cut = p.lastIndexOf("/");
        if (cut < 0)
            return "";
        return cut === 0 ? "/" : p.substring(0, cut);
    }

    function baseName(path) {
        if (!path)
            return "";
        var p = path;
        if (p.length > 1 && p.charAt(p.length - 1) === "/")
            p = p.substring(0, p.length - 1);
        var cut = p.lastIndexOf("/");
        return cut < 0 ? p : p.substring(cut + 1);
    }

    function parentPath(path) {
        if (!path || path === "/")
            return "/";
        var p = path;
        if (p.charAt(p.length - 1) === "/")
            p = p.substring(0, p.length - 1);
        var cut = p.lastIndexOf("/");
        return cut <= 0 ? "/" : p.substring(0, cut);
    }
}
