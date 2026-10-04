import QtQuick
import Quickshell
import Quickshell.Io
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "../menu"

// FileManager — Il gestore file di Minerva.
//
// È una finestra normale, non una sovrapposizione della shell: si affianca,
// si ridimensiona, si sposta fra le scrivanie come qualunque altro programma.
// Un gestore file che vive sopra tutto e non si può mettere accanto a un'altra
// finestra non serve a niente — trascinare roba da una parte all'altra è il
// motivo per cui esiste.
//
// Due riquadri indipendenti. Non è un vezzo da smanettoni: copiare da A a B è
// l'operazione più comune che si fa con i file, e con un riquadro solo
// significa navigare, ricordare, tornare indietro, incollare. Con due
// significa guardare entrambi e premere un tasto.
FloatingWindow {
    id: manager

    /// Il vuoto fra le isole di Liquid DE (la colonna, i riquadri, le
    /// capsule dei comandi) e fra loro e il bordo della finestra.
    readonly property int isola: Theme.Effects.space2

    // Non ci si mostra col tema di fabbrica.
    //
    // I colori arrivano dal demone. Finché non sono arrivati, il tema è quello
    // di ripiego (`notte`, ciano): chi ne ha scelto un altro vedeva la
    // finestra aprirsi del colore sbagliato e poi scattare. Misurato, le
    // impostazioni vincevano la corsa per SEDICI MILLISECONDI — un fotogramma,
    // cioè per caso. All'accesso, con più finestre insieme e il demone che sta
    // ancora partendo, quel margine non c'è.
    //
    // `Core.Ipc.prontoADipingere` aspetta le impostazioni e si arrende dopo tre
    // secondi, così un demone spento non lascia senza finestra: vedi
    // `core/Ipc.qml`.
    visible: Core.Ipc.prontoADipingere && !manager.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    //
    // Aprire il gestore file costava circa 800 ms, e misurandoli si scopriva
    // che non c'era niente da tagliare: 25 ms Qt, 410 la lettura e la
    // costruzione di tutto il QML che serve, 50 il giro di domande al demone,
    // 160 la creazione della finestra sotto Wayland (pavimento: una finestra
    // VUOTA ci metteva tanto), e 110 il primo fotogramma dei nostri contenuti.
    //
    // Dal 18 agosto 2026 sono 645, perché il pavimento si è dimezzato: le app
    // di Minerva disegnano col processore e non con la scheda video (vedi
    // `scripts/minerva-ambiente-app`). I 410 della costruzione però sono
    // rimasti lì, e restano il grosso.
    //
    // Le due strade provate e misurate — rendere pigri i sette dialoghi,
    // spezzare i file — non hanno spostato un millisecondo: il tempo non sta
    // nelle righe ma nell'albero dei tipi, che si carica comunque (vedi il
    // commento sopra `Loader { id: propsCard }`).
    //
    // Quindi non si accorcia l'attesa: si sposta. Il gestore file si avvia
    // all'accesso e resta acceso senza finestra; la prima cartella che si
    // apre trova tutto già costruito e compare subito. Rimisurato il 18
    // agosto 2026: 645 ms a freddo contro 34 ms da già acceso.
    //
    // Il prezzo è dichiarato e non è piccolo — 84 MB di memoria privata
    // sempre occupati — e per questo c'è un interruttore nelle
    // Impostazioni del gestore file, e per questo `Minerva Attività` continua
    // a mostrarlo: un programma acceso che non si vede da nessuna parte è il
    // difetto, non la soluzione.
    //
    // Scelta di Giacomo il 16 agosto 2026, davanti ai due conti. Dal 18 agosto
    // il meccanismo è di tutte le app e vive in `core/TenutaPronta.qml`: qui
    // resta solo l'interruttore della luce.
    property bool dormiente: false

    /// Torna alla cartella chiesta.
    ///
    /// Non tocca `dormiente`: quella la decide `core/TenutaPronta.qml`, che è
    /// l'unico a sapere se l'utente vuole tenere acceso il programma. Qui si
    /// fa solo il mestiere del gestore file — andare dove è stato chiesto.
    function risveglia(percorso) {
        if (percorso && percorso !== "" && manager.current)
            manager.current.navigate(percorso);
    }

    /// Mette via le sue cose prima di sparire.
    ///
    /// Si riparte puliti: schede in più chiuse e ricerca spenta. Ritrovare la
    /// finestra com'era tre giorni fa non è memoria, è disordine — e chi
    /// riapre il gestore file quasi sempre sta cominciando un'altra cosa.
    ///
    /// Anche questa non tocca `dormiente`, per lo stesso motivo: la proprietà
    /// arriva LEGATA da fuori, e scriverci sopra spezzerebbe il legame — la
    /// finestra si nasconderebbe una volta e poi mai più.
    function addormenta() {
        while (manager.tabs.count > 1)
            manager.tabs.remove(manager.tabs.count - 1);
        manager.currentIndex = 0;
        if (manager.current)
            manager.current.navigate(Files.home);
    }

    title: "Minerva · " + (Core.Strings.lang === "it" ? "File" : "Files")
    implicitWidth: 1100
    implicitHeight: 680

    // Vetro come la barra: il fondo è trasparente e la sfocatura la mette
    // Hyprland dietro ai pixel che lo sono. Con un fondo opaco non c'è blur
    // che tenga — non è una questione di configurazione del compositore, è
    // che non c'è niente da sfocare.
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

    Connections {
        target: Core.Ipc

        function onRadiceStato(info) {
            manager.radiceCE = info && info.disponibile === true;
        }

        /// La risposta alla richiesta di permesso: è QUI che la modalità si
        /// accende, non nel clic che l'ha chiesta.
        function onRadicePermesso(info) {
            if (!manager.inAttesaDiPermesso)
                return;
            manager.inAttesaDiPermesso = false;
            if (info && info.ok === true) {
                manager.accendiDavvero();
                return;
            }
            // Annullare la finestra della password è il modo normale di dire
            // «no, ripensandoci»: non è un guasto e non si racconta come tale.
            if (info && info.annullato === true) {
                problem.dillo(Core.Strings.lang === "it"
                              ? "Modalità amministratore non accesa."
                              : "Administrator mode not enabled.");
                return;
            }
            problem.show(String((info && info.error) || (Core.Strings.lang === "it"
                ? "Non sono riuscito a chiedere i permessi di amministratore."
                : "Could not ask for administrator permissions.")));
        }

        /// Com'è andata un'operazione da amministratore.
        ///
        /// Si racconta SEMPRE, anche quando è andata bene: da root non c'è
        /// cestino da cui ripescare, e un'operazione irreversibile che non
        /// lascia una riga a schermo è un'operazione di cui non si è sicuri.
        function onRadiceEsito(info) {
            if (!info)
                return;
            if (info.ok === true) {
                problem.dillo(Core.Strings.lang === "it"
                              ? "Fatto, da amministratore."
                              : "Done, as administrator.");
                if (manager.current)
                    manager.current.reload();
                return;
            }
            if (info.annullato === true) {
                // Annullare la finestra della password non è un guasto, ed è
                // il modo normale di dire «no, ripensandoci».
                problem.dillo(Core.Strings.lang === "it" ? "Annullato."
                                                         : "Cancelled.");
                return;
            }
            problem.show(String(info.error || (Core.Strings.lang === "it"
                                               ? "Non è andata."
                                               : "It did not work.")));
        }
    }

    onClosed: manager.requestClose()

    // ── Schede ───────────────────────────────────────────────────────────
    //
    // Si apre con UNA scheda sola. La doppia visuale è comodissima quando
    // serve spostare roba, ed è inutile ingombro tutte le altre volte: due
    // elenchi identici della stessa cartella non aiutano nessuno, e obbligano
    // a chiedersi ogni volta su quale dei due si sta agendo.
    //
    // Le schede si affiancano invece di sovrapporsi. È la stessa idea della
    // doppia visuale portata al numero che serve: vederle tutte è il motivo
    // per cui esistono, e una scheda nascosta dietro un'altra non serve a
    // trascinarci dentro un file.

    property ListModel tabs: ListModel {}

    /// Quante se ne possono aprire. Oltre le quattro ogni riquadro è più
    /// stretto dei nomi dei file che deve mostrare.
    readonly property int maxTabs: 4

    // ── Di quale finestra è un riquadro ──────────────────────────────────
    //
    // Dal 29 settembre una «nuova finestra» nasce nello stesso processo
    // (`filemanager.qml`), e i riquadri di tutte si chiamavano `t0`, `t1`…:
    // l'elenco di una cartella chiesto da una finestra arrivava anche al
    // riquadro omonimo dell'altra, che mostrava la cartella sbagliata — «entro
    // in una cartella e ci entra anche l'altro» (K2, PC di prova). Lo stesso
    // per le ricerche. Ogni finestra ha il suo prefisso.
    readonly property string finestraId: "w" + Date.now().toString(36)
                                         + Math.floor(Math.random() * 1e9).toString(36)

    /// Indice della scheda che riceve i comandi.
    property int currentIndex: 0

    /// I riquadri vivi, in ordine. Li tiene aggiornati il Repeater.
    property var panes: []

    readonly property var current: manager.panes[manager.currentIndex] || null
    /// La scheda "di destinazione" dei comandi che spostano roba: la
    /// successiva, a giro. Con una scheda sola non esiste, e i comandi che la
    /// vorrebbero spariscono invece di fallire in silenzio.
    readonly property var other: manager.panes.length > 1
                                 ? manager.panes[(manager.currentIndex + 1) % manager.panes.length]
                                 : null

    // ── Confronta due cartelle ───────────────────────────────────────────
    //
    // È la cosa che si fa ogni volta che si copia roba da qualche parte e poi
    // ci si chiede se è arrivata tutta. Oggi si fa guardando due elenchi uno
    // accanto all'altro e leggendo i nomi a uno a uno — e con centosessanta
    // file non si fa: si copia tutto di nuovo e si spera.
    //
    // Con due riquadri affiancati la risposta è già lì, basta dirla. Nessun
    // gestore file la dice bene, e ce l'abbiamo quasi gratis.
    //
    // ── Cosa vuol dire «diverso» ─────────────────────────────────────────
    //
    // Non il contenuto: confrontare byte per byte due cartelle da un gigabyte
    // vuol dire leggerle tutte, e non è quello che si sta chiedendo. Si
    // guardano DIMENSIONE e DATA, che è quello che guarderebbe una persona, ed
    // è abbastanza per accorgersi di una copia interrotta o di un file
    // aggiornato solo di là.
    //
    // Le cartelle si confrontano per nome soltanto: dire «diversa» di una
    // cartella vorrebbe dire scendere dentro, e allora il confronto diventa
    // un'altra cosa (e un'altra attesa).
    property bool confronto: false

    /// L'esito, per percorso: "solo", "diverso", "uguale".
    /// Vuoto quando il confronto è spento o non ci sono due riquadri.
    readonly property var esitoConfronto: {
        if (!manager.confronto || manager.panes.length < 2)
            return ({});
        var a = manager.current;
        var b = manager.other;
        if (!a || !b)
            return ({});

        // L'altro elenco per nome, così il confronto è una lettura sola per
        // voce invece di una scansione dentro l'altra.
        var la = {};
        var eB = b.entries || [];
        for (var i = 0; i < eB.length; i++)
            la[eB[i].name] = eB[i];

        var out = {};
        var eA = a.entries || [];
        for (var k = 0; k < eA.length; k++) {
            var v = eA[k];
            var g = la[v.name];
            if (g === undefined) {
                out[v.path] = "solo";
            } else if (v.isDir || g.isDir) {
                // Due cartelle con lo stesso nome: si dicono uguali. Scendere
                // dentro sarebbe un altro confronto e un'altra attesa.
                out[v.path] = (v.isDir === g.isDir) ? "uguale" : "diverso";
            } else if (v.size !== g.size
                       || Math.abs((v.modified || 0) - (g.modified || 0)) > 2000) {
                // Due secondi di tolleranza: fra due file system diversi la
                // data si arrotonda in modi diversi, e un secondo di scarto
                // non è una differenza — è il modo in cui è stata scritta.
                out[v.path] = "diverso";
            } else {
                out[v.path] = "uguale";
            }
        }
        return out;
    }

    /// Il riassunto, per la barra: quanti solo qui e quanti diversi.
    readonly property var contoConfronto: {
        var soli = 0, diversi = 0, uguali = 0;
        var e = manager.esitoConfronto;
        for (var k in e) {
            if (e[k] === "solo") soli++;
            else if (e[k] === "diverso") diversi++;
            else uguali++;
        }
        return { "soli": soli, "diversi": diversi, "uguali": uguali };
    }

    /// Come si chiama la destinazione, per scriverlo nei menu. Con più di due
    /// schede «a destra» non vuol dire più niente: si dice il numero.
    readonly property string otherSideName: {
        var it = Core.Strings.lang === "it";
        if (!manager.other)
            return "";
        if (manager.panes.length === 2)
            return manager.currentIndex === 0
                   ? (it ? "nella scheda di destra" : "to the right tab")
                   : (it ? "nella scheda di sinistra" : "to the left tab");
        // Con tre o quattro schede non si nomina una destinazione: la si
        // chiede. I tre puntini sono la promessa che seguirà una domanda, ed
        // è una promessa che qui viene mantenuta.
        return it ? "in un'altra scheda…" : "to another tab…";
    }

    function focusPane(p) {
        for (var i = 0; i < manager.panes.length; i++) {
            manager.panes[i].focused = (manager.panes[i] === p);
            if (manager.panes[i] === p)
                manager.currentIndex = i;
        }
    }

    function focusIndex(i) {
        if (i >= 0 && i < manager.panes.length)
            manager.focusPane(manager.panes[i]);
    }

    /// Apre una scheda nuova. Parte dalla cartella che si sta guardando: si
    /// apre una scheda per andare da qualche altra parte PARTENDO da qui,
    /// quasi mai per ricominciare dalla home.
    function addTab(path) {
        if (manager.tabs.count >= manager.maxTabs)
            return;
        var start = path
                    || (manager.current ? manager.current.path : Files.home)
                    || Files.home;
        manager.tabs.append({ "startPath": start });
        // Il fuoco va sulla scheda appena aperta: è quella che si è chiesta.
        focusLater.index = manager.tabs.count - 1;
        focusLater.restart();
    }

    function closeTab(i) {
        if (manager.tabs.count <= 1 || i < 0 || i >= manager.tabs.count)
            return;
        manager.tabs.remove(i);
        if (manager.currentIndex >= manager.tabs.count)
            manager.currentIndex = manager.tabs.count - 1;
        focusLater.index = manager.currentIndex;
        focusLater.restart();
    }

    function closeCurrentTab() {
        manager.closeTab(manager.currentIndex);
    }

    // Il riquadro nuovo non esiste ancora nell'istante in cui lo si chiede:
    // il Repeater lo costruisce al giro dopo. Si aspetta quel giro invece di
    // dare il fuoco a un oggetto che non c'è.
    Timer {
        id: focusLater
        property int index: 0
        interval: 30
        onTriggered: manager.focusIndex(focusLater.index)
    }

    /// La cartella della PRIMA scheda. Vuota vuol dire casa.
    ///
    /// Chi ci lancia per aprire una cartella precisa la mette qui e non chiama
    /// `addTab` dopo: aggiungere una scheda a una finestra appena nata lascia
    /// aperta anche la scheda di casa, che nessuno aveva chiesto — si finiva
    /// con due riquadri per una cartella sola.
    property string initialPath: ""

    Component.onCompleted: {
        manager.tabs.append({
            "startPath": manager.initialPath !== "" ? manager.initialPath
                                                    : Files.home
        });
        // Vedi `watchers` in Files.qml: i dischi si ricontrollano solo
        // mentre c'è una finestra che li guarda.
        Files.watchers += 1;
        Files.refresh();
        // Se l'aiutante di root non c'è, la modalità amministratore non si
        // offre nemmeno: una voce di menu che non può funzionare è una
        // promessa falsa, ed è peggio della voce che manca.
        Core.Ipc.radiceDisponibile();
        // I televisori: una volta all'apertura, e poi li rinfresca il timer.
        Core.Ipc.trasmettiCerca();
    }

    // Ogni due minuti, e solo mentre la finestra c'è: un televisore acceso
    // adesso può essere spento fra un'ora, e una voce di menu che manda a un
    // apparecchio spento è peggio di una voce che manca.
    Timer {
        interval: 120000
        repeat: true
        running: true
        onTriggered: Core.Ipc.trasmettiCerca()
    }


    // ── Aprire un file ───────────────────────────────────────────────────
    //
    // Qui c'era `xdg-open`, e da lì veniva il difetto per cui Minerva apriva
    // le immagini con Google Chrome: `xdg-open` è uno script che guarda
    // `XDG_CURRENT_DESKTOP`, non riconosce Minerva, e finisce nel ramo
    // generico dove vince il primo programma che dichiara di saper leggere
    // quel tipo. Un browser dichiara di saper leggere quasi tutto.
    //
    // Adesso lo decide il demone, che applica la specifica freedesktop per
    // conto suo — e soprattutto SA DIRE DI NON SAPERLO: se per quel tipo non
    // c'è un programma predefinito lo dice, e si apre la finestra che chiede
    // con che cosa aprirlo, invece di lanciare qualcosa a caso o non fare
    // niente. Vedi `mime_service.dart`.
    //
    // Il programma parte staccato dal demone, quindi sopravvive alla shell che
    // si ricarica: è la stessa ragione per cui in shell.qml c'è
    // `execDetached` e non un `Process`.
    /// La voce dell'elenco che sta a quel percorso, o `null`.
    ///
    /// Serve a sapere se il file si può ESEGUIRE, e la risposta è già in
    /// casa: `fs_list` manda `mode` (`rwxr-xr-x`) per ogni voce, e in tutta la
    /// shell non lo leggeva nessuno. Meglio così che una domanda in più al
    /// demone per una cosa che si sa già.
    function voceDi(path) {
        var p = manager.current;
        if (!p)
            return null;
        for (var i = 0; i < p.entries.length; i++) {
            if (p.entries[i].path === path)
                return p.entries[i];
        }
        return null;
    }

    function eseguibileDi(path) {
        var v = manager.voceDi(path);
        if (!v || v.isDir)
            return false;
        // `rwxr-xr-x`: basta che UNA delle tre `x` ci sia. Chi apre il gestore
        // file è quasi sempre il proprietario, ma un file di sistema
        // eseguibile da tutti si esegue lo stesso.
        return String(v.mode || "").indexOf("x") !== -1;
    }

    /// I tipi che ha senso eseguire. È il tipo VERO e non l'estensione: da
    /// quando il demone legge il database di freedesktop sa dire che
    /// `joca.sh` è `text/x-shellscript` e non «testo qualunque».
    ///
    /// La stessa tabella sta in `ui/ApriCon.qml`, e non è una svista: là serve
    /// a decidere che cosa OFFRIRE in una finestra che vive anche fuori dal
    /// gestore file. Se un giorno diventa tre, allora va spostata in `core`.
    function tipoEseguibile(mime) {
        return mime === "text/x-shellscript"
            || mime === "text/x-python"
            || mime === "application/x-perl"
            || mime === "application/x-ruby"
            || mime === "text/x-lua"
            || mime === "application/x-executable"
            || mime === "application/x-pie-executable";
    }

    function eLanciatore(path) {
        return /\.desktop$/.test(String(path || ""));
    }

    function openExternally(path) {
        // ── Un lanciatore si LANCIA ──────────────────────────────────────
        //
        // La scrivania lo faceva già (`menu/DesktopIcons.qml`), il gestore
        // file no: un `.desktop` ci si apriva nell'editor, perché `file` lo
        // riconosceva come testo semplice. Adesso il tipo è giusto
        // (`application/x-desktop`) ma la conclusione resta: quel file non è
        // un documento, è un pulsante.
        if (manager.eLanciatore(path)) {
            Core.Ipc.launchDesktop(path);
            return;
        }
        // ── Un eseguibile fa fermare a chiedere ──────────────────────────
        //
        // `joca.sh` ha un programma predefinito (l'editor) e aprirlo lì è una
        // risposta legittima — ma non è quasi mai quella che si voleva
        // facendo doppio clic su un lanciatore di un proprio progetto. Quindi
        // si chiede, invece di indovinare in una direzione o nell'altra.
        if (manager.eseguibileDi(path)) {
            apriCon.apri(path, true);
            return;
        }
        Core.Ipc.openDefault([path]);
    }

    Connections {
        target: Core.Ipc

        function onFileResultReceived(result) {
            if (result.needsChoice !== true)
                return;
            var paths = result.paths || [];
            // Qui si finiva nelle PROPRIETÀ, che per giunta in questo caso
            // mostravano una colonna «Si apre con» vuota: il file non si
            // poteva né aprire, né assegnare, né eseguire. Vedi
            // `ui/ApriCon.qml`.
            if (paths.length > 0)
                apriCon.apri(paths[0], manager.eseguibileDi(paths[0]));
        }
    }

    // ── Che cos'è il file scelto ─────────────────────────────────────────
    //
    // Serve al MENU: «Apri» ha senso solo se qualcosa lo apre davvero, e per
    // saperlo bisogna aver chiesto al demone PRIMA che il menu si apra — un
    // menu costruito a metà e completato dopo è un menu che balla sotto il
    // dito.
    //
    // Si chiede quando la selezione diventa di un file solo, con due decimi di
    // secondo di attesa: tenendo premuta una freccia si attraversano venti
    // righe, e venti domande al demone per arrivare alla ventunesima sono
    // diciannove sprecate.
    //
    // Se la risposta non è ancora arrivata, il menu resta quello di prima —
    // «Apri» e «Apri con…» tutti e due. Un menu generico è meglio di un menu
    // che si fa aspettare.
    property var tipoScelto: null

    Timer {
        id: chiediTipo
        interval: 200
        onTriggered: {
            var ops = manager.operands();
            if (ops.length !== 1 || manager.selectedDirectory() !== "") {
                manager.tipoScelto = null;
                return;
            }
            Core.Ipc.mimeDescribe(ops[0]);
        }
    }

    Connections {
        target: manager.current
        function onSelectionChanged() {
            manager.tipoScelto = null;
            chiediTipo.restart();
        }
    }

    Connections {
        target: Core.Ipc
        function onMimeDescribed(d) {
            if (d && d.path)
                manager.tipoScelto = d;
        }
    }

    // ── «Con che cosa lo apro?» ──────────────────────────────────────────

    Ui.ApriCon {
        id: apriCon
        onEseguiRichiesto: function (percorso) {
            manager.eseguiNelTerminale(percorso);
        }
        onEseguibileRichiesto: function (percorso) {
            manager.rendiEseguibile(percorso);
        }
    }

    // ── «Mandalo fuori di qui»: Bluetooth, posta ─────────────────────────

    Ui.Condividi {
        id: condividi
    }

    /// Lo avvia in un terminale, e il terminale RESTA APERTO.
    ///
    /// Uno script che fallisce in mezzo secondo, in una finestra che si chiude
    /// da sola, è indistinguibile da uno script che non è mai partito. Si
    /// mostra il codice d'uscita e si aspetta un Invio.
    ///
    /// Si entra prima nella sua cartella: la maggior parte degli script cerca
    /// i propri file lì accanto e da un'altra cartella non li trova.
    ///
    /// Percorso e comando passano come ARGOMENTI e mai dentro la riga: un file
    /// con un apice o un backtick nel nome non deve poter diventare un pezzo
    /// di comando. Vedi `shArgs` in `core/Exec.qml`.
    function eseguiNelTerminale(percorso) {
        var term = Core.Ipc.get("launcher.defaultTerminal", "minerva-terminale");
        var it = Core.Strings.lang === "it";
        Quickshell.execDetached([
            term, "-e", "sh", "-c",
            'cd "$(dirname "$1")" || exit 1; "$1"; s=$?; echo; '
            + 'printf "%s %s — " "' + (it ? "uscita" : "exit") + '" "$s"; '
            + 'printf "%s" "' + (it ? "premi Invio" : "press Enter")
            + '"; read _',
            "sh", percorso]);
    }

    function rendiEseguibile(percorso) {
        var v = manager.voceDi(percorso);
        if (!v)
            return;
        problem.attesa = Core.Strings.lang === "it"
                         ? "Lo rendo eseguibile…" : "Making it runnable…";
        eseguibileExec.shArgs('chmod +x -- "$1" 2>&1', [percorso]);
    }

    Core.Exec {
        id: eseguibileExec
        onDone: function (out) {
            problem.attesa = "";
            if (out.trim() !== "")
                problem.show(out.trim());
            else if (manager.current)
                // Il permesso è cambiato sul disco e non nell'elenco: senza
                // questa riga il file resterebbe «non eseguibile» finché non
                // si cambia cartella. Il `chmod` lo fa un processo nostro e
                // non il demone, quindi il ricarico automatico su `fs_result`
                // (vedi `Pane.qml`) qui non scatta.
                manager.current.reload();
        }
    }

    // ── Terminale qui ────────────────────────────────────────────────────
    //
    // Il gestore file serve a girare fra le cartelle; il terminale serve a
    // fare le cose che nessuna interfaccia grafica farà mai. Passare dall'uno
    // all'altro senza riscrivere il percorso a mano è il ponte fra i due, ed è
    // la voce che si cerca per prima quando si arriva da un altro ambiente.

    /// Dove aprirlo: dentro la cartella su cui si è cliccato, se è una
    /// cartella; altrimenti nella cartella che si sta guardando. Cliccare col
    /// destro su un file e ritrovarsi nella sua cartella è quello che ci si
    /// aspetta — un terminale non si apre «dentro» un documento.
    ///
    /// Conta solo ciò che è SELEZIONATO, non la riga sotto il cursore: il
    /// cursore all'apertura sta sulla prima riga senza che nessuno l'abbia
    /// messo lì, e aprire il terminale nella prima cartella in ordine
    /// alfabetico invece che dove si sta guardando è un tranello.
    function terminalDirectory() {
        var p = manager.current;
        if (!p || p.path === "")
            return Files.home;
        if (p.selection.length === 1) {
            for (var i = 0; i < p.entries.length; i++) {
                var e = p.entries[i];
                if (e.path === p.selection[0])
                    return e.isDir ? e.path : p.path;
            }
        }
        return p.path;
    }

    /// Manda una cartella ad Anteprima, che ne fa un provino a contatto.
    ///
    /// La stessa scelta del terminale: la cartella su cui si è cliccato se è
    /// una cartella, altrimenti quella che si sta guardando. Cliccare col
    /// destro su una fotografia e ritrovarsi a sfogliare la cartella che la
    /// contiene è quello che ci si aspetta — quella fotografia è lì dentro.
    function browseWithViewer() {
        var dir = manager.terminalDirectory();
        if (dir && dir !== "")
            Quickshell.execDetached(["minerva-viewer", dir]);
    }

    /// Una finestra nuova, non una scheda. Sono due processi separati: un
    /// errore nell'una non tocca l'altra, ed è la stessa scelta fatta per le
    /// applicazioni di Minerva (vedi MODULI.md). Il prezzo è la memoria di un
    /// processo in più, e si paga solo a chi la chiede.
    ///
    /// Parte dalla cartella in cui si è: aprire una seconda finestra sulla
    /// stessa cartella si fa in un attimo, tornare dove si era no.
    function apriNuovaFinestra() {
        var dir = manager.current ? manager.current.path : "";
        // `--nuova-finestra`: senza, lo script trovava questo processo e gli
        // chiedeva una scheda — la «Nuova finestra» era una «Nuova scheda».
        Quickshell.execDetached(dir !== "" ? ["minerva-files", "--nuova-finestra", dir]
                                           : ["minerva-files", "--nuova-finestra"]);
    }

    function openTerminalHere() {
        var dir = manager.terminalDirectory();
        // Quale terminale si sceglie in Impostazioni → App predefinite.
        var term = Core.Ipc.get("launcher.defaultTerminal", "minerva-terminale");

        // Si entra nella cartella con `cd` invece di usare l'opzione del
        // terminale: ogni terminale la chiama in modo diverso
        // (--working-directory, --directory, -D, --workdir) e chi cambia
        // terminale nelle impostazioni si ritroverebbe la voce rotta. La
        // cartella di lavoro si eredita e basta.
        //
        // Percorso e comando passano come ARGOMENTI e non dentro la riga:
        // così una cartella che contiene un apice o uno spazio non ha modo di
        // diventare un pezzo di comando.
        //
        // Staccato: il terminale è un programma dell'utente, non un pezzo del
        // gestore file. Vedi `run()` in shell.qml.
        Quickshell.execDetached(["sh", "-c", "cd \"$1\" || exit 1; exec \"$0\"",
                                 term, dir]);
    }

    // ── Operazioni ───────────────────────────────────────────────────────
    //
    // Ogni comando agisce sulla SCHEDA ATTIVA e su nient'altro. Le scorciatoie
    // esistono già mentre i riquadri si stanno ancora costruendo, quindi
    // ognuno controlla di avere davvero una scheda su cui agire: un comando
    // che parte su niente è un comando che agisce sul posto sbagliato.

    /// I file su cui agire, o un elenco vuoto se non c'è una scheda attiva.
    function operands() {
        return manager.current ? manager.current.operands() : [];
    }

    function doCopy() {
        var ops = manager.operands();
        if (ops.length > 0) Files.copyToClipboard(ops);
    }

    function doCut() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        // Tagliare è mezzo spostamento, e la metà che qui non riuscirebbe è
        // proprio quella che toglie: si direbbe di sì adesso e di no fra
        // cinque minuti, in un'altra cartella, dove non si capisce più perché.
        if (!manager.scriviQui())
            return;
        Files.cutToClipboard(ops);
    }

    function doPaste() {
        if (Files.clipboard.length === 0 || !manager.current)
            return;
        if (!manager.scriviQui())
            return;
        manager.trasferisci(Files.clipboard, manager.current.path,
                            Files.clipboardIsCut);
        // Dopo un taglio gli appunti si svuotano: incollarli due volte
        // sposterebbe file che non sono più dove erano.
        if (Files.clipboardIsCut)
            Files.clearClipboard();
    }

    /// Con più di due schede la destinazione non è più ovvia, e allora si
    /// chiede. Con due lo è, e chiederlo sarebbe una domanda con una sola
    /// risposta possibile — cioè un fastidio.
    readonly property bool asksWhere: manager.panes.length > 2

    /// Copia verso un'ALTRA scheda. È la scorciatoia che giustifica la doppia
    /// visuale: niente copia, niente navigazione, niente incolla.
    ///
    /// Difetto che questa funzione aveva e che vale la pena scrivere, perché
    /// è il genere di cosa che sembra funzionare: la destinazione era «la
    /// scheda successiva, a giro». Con due schede è l'unica possibile e va
    /// bene. Con tre o quattro è una fra tre, scelta da noi, senza dirlo: si
    /// premeva «Sposta» e i file finivano in una cartella che chi premeva non
    /// aveva scelto. Non è un difetto di comodità — è roba spostata dove non
    /// si voleva, e per accorgersene bisogna prima cercarla.
    function sendToOther(move) {
        if (!manager.current)
            return;
        var ops = manager.current.operands();
        if (ops.length === 0)
            return;
        if (manager.asksWhere) {
            if (destination.begin(ops, move === true))
                return;
            // Nessuna destinazione buona fra le altre schede: non si ripiega
            // sulla «scheda successiva», che è proprio quella che è stata
            // scartata. Meglio non fare niente che fare la cosa sbagliata in
            // silenzio.
            return;
        }
        if (!manager.other)
            return;
        // Anche con due sole schede la destinazione può essere la stessa
        // cartella di partenza, o una sua sottocartella.
        if (manager.other.path === manager.current.path)
            return;
        for (var i = 0; i < ops.length; i++) {
            if (manager.other.path === ops[i]
                || manager.other.path.indexOf(ops[i] + "/") === 0)
                return;
        }
        manager.trasferisci(ops, manager.other.path, move === true);
    }

    /// Le schede che possono ricevere davvero.
    ///
    /// Non basta togliere quella da cui si parte. Due schede possono mostrare
    /// la STESSA cartella — succede appena si apre una scheda nuova, che nasce
    /// dove si era — e offrire di copiare un file su sé stesso è una domanda
    /// senza una risposta giusta.
    ///
    /// Peggio: copiando una cartella, una scheda aperta DENTRO quella cartella
    /// è una destinazione che si mangia la coda. `cp -r Documenti
    /// Documenti/Documenti` o gira all'infinito o si ferma a metà lasciando
    /// una copia parziale, a seconda di come il sistema decide di
    /// accorgersene. È una scelta che non deve nemmeno comparire.
    function destinationChoices() {
        var out = [];
        var from = manager.current ? manager.current.path : "";
        var ops = manager.operands();

        for (var i = 0; i < manager.panes.length; i++) {
            if (i === manager.currentIndex || !manager.panes[i])
                continue;
            var to = manager.panes[i].path;
            if (to === "" || to === from)
                continue;

            var inside = false;
            for (var k = 0; k < ops.length; k++) {
                // `to` sta dentro `ops[k]` se ne ripete il percorso ed è
                // seguito da una barra. Il confronto con la barra conta:
                // senza, «/casa/Foto2» risulterebbe dentro «/casa/Foto».
                if (to === ops[k] || to.indexOf(ops[k] + "/") === 0) {
                    inside = true;
                    break;
                }
            }
            if (inside)
                continue;

            out.push({ "index": i, "path": to });
        }
        return out;
    }

    /// «Questa cartella si lascia cambiare?»
    ///
    /// Il menu e la barra già non offrono ciò che non si può fare, ma i
    /// comandi hanno anche una scorciatoia — Canc, Maiusc+Canc, F2, Ctrl+N —
    /// e le scorciatoie non passano dal menu. Un solo posto in cui chiederlo,
    /// e una risposta che si legge invece di un tasto che non fa niente.
    // ── La modalità amministratore ───────────────────────────────────────
    //
    // Giacomo, 23 agosto 2026: «nel file manager, se entro nelle cartelle di
    // root, non posso usare una modalità amministratore come fa Linux Mint,
    // per poter eliminare qualsiasi file di root come se fossi un utente
    // root».
    //
    // È accesa per la FINESTRA e non per la scheda: chi l'ha accesa sa di
    // averla accesa, e se cambiasse da sola passando da una scheda all'altra
    // ci si troverebbe amministratori senza essersene accorti — che è
    // esattamente il modo in cui si cancella la cosa sbagliata.
    //
    // ── E si spegne da sola ──────────────────────────────────────────────
    //
    // Dopo dieci minuti senza usarla. Non è teatro: polkit ricorda la
    // password per qualche minuto (`auth_admin_keep`), quindi una finestra
    // lasciata aperta in modalità amministratore è una finestra dove il
    // prossimo clic sbagliato non chiede più niente. Il timer riparte a ogni
    // operazione fatta davvero.
    property bool amministratore: false

    // ── I televisori in rete ─────────────────────────────────────────────
    //
    // Servono alla voce «Trasmetti a…» del menù del tasto destro. Si chiedono
    // quando la finestra si apre e poi ogni tanto: la scoperta costa due
    // secondi di rete, e rifarla a ogni clic destro vorrebbe dire un menù che
    // si apre in ritardo.
    property var schermiTrovati: []

    Connections {
        target: Core.Ipc
        function onTrasmettiSchermi(elenco) {
            manager.schermiTrovati = elenco || [];
        }
        function onTrasmettiEsito(e) {
            if (!e)
                return;
            if (e.ok === true) {
                problem.dillo(Core.Strings.lang === "it"
                              ? "Sto mandando a " + String(e.verso) + "."
                              : "Sending to " + String(e.verso) + ".");
                return;
            }
            problem.show(String(e.error || (Core.Strings.lang === "it"
                                            ? "Non è andata."
                                            : "It didn't work.")));
        }
    }

    /// Manda al televisore il file selezionato. `id` è quello STABILE del
    /// televisore, non il suo indirizzo: un IP cambia a ogni riaccensione del
    /// router, e domani manderebbe altrove.
    function trasmettiIlSelezionato(id) {
        var uno = manager.operands();
        if (uno.length !== 1)
            return;
        problem.dillo(Core.Strings.lang === "it" ? "Trasmetto…" : "Casting…");
        // ── Il tipo NON si dice ──────────────────────────────────────────
        //
        // Qui c'era `manager.tipoDi()`, una tabella di estensioni il cui
        // ripiego era `image/jpeg`: **un `.mp4` partiva annunciato come una
        // fotografia**, e il televisore mostrava nero senza dire niente.
        //
        // Adesso il tipo lo trova il demone, che ha il file e per immagini,
        // suoni e video ci guarda DENTRO invece di fidarsi del nome — un
        // `IMG_1234.mp4` che è davvero un JPEG ce l'ha il telefono di
        // chiunque. Non indovinare è meglio che indovinare bene.
        Core.Ipc.trasmettiManda(uno[0], id);
    }

    /// Vero se il nome dice che è una cosa che un televisore sa mostrare:
    /// una fotografia, un film, un brano.
    ///
    /// **Basta il nome**, e di proposito: questa domanda serve solo a decidere
    /// se far comparire una voce di menu, e chiedere al demone il tipo vero di
    /// ogni file a ogni clic destro sarebbe una domanda per ogni clic. Il tipo
    /// VERO — quello che parte davvero — lo trova il demone quando si
    /// trasmette, ed è un'altra cosa: qui si sbaglia al massimo mostrando una
    /// voce in più, lì si sbaglierebbe mandando un film come una fotografia.
    function eTrasmettibile(percorso) {
        var p = String(percorso).toLowerCase();
        var punto = p.lastIndexOf(".");
        if (punto < 0)
            return false;
        return manager.codeTrasmissibili.indexOf(p.substring(punto)) >= 0;
    }

    /// Le estensioni che un televisore sa mostrare. Gli MKV e gli AVI ci sono:
    /// un Chromecast non li legge e lo dirà con una frase — ma un televisore
    /// DLNA spesso sì, e togliere la voce dal menu vorrebbe dire nascondere
    /// una cosa che funziona.
    readonly property var codeTrasmissibili: [
        ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp",
        ".mp4", ".m4v", ".mov", ".webm", ".mkv", ".avi", ".mpg", ".mpeg",
        ".mp3", ".m4a", ".flac", ".ogg", ".opus", ".wav", ".aac"
    ]

    /// Vero quando l'aiutante c'è. Se manca, la modalità non si offre
    /// nemmeno: una voce di menu che non può funzionare è una promessa falsa.
    property bool radiceCE: false

    Timer {
        id: scadenzaRadice
        interval: 10 * 60 * 1000
        onTriggered: {
            if (!manager.amministratore)
                return;
            manager.amministratore = false;
            problem.dillo(Core.Strings.lang === "it"
                ? "Modalità amministratore spenta da sola dopo dieci minuti."
                : "Administrator mode switched itself off after ten minutes.");
        }
    }

    /// Vero mentre la finestrella della password è aperta. Impedisce che due
    /// clic di fila aprano due richieste, e soprattutto tiene la modalità
    /// SPENTA finché non si sa com'è andata.
    property bool inAttesaDiPermesso: false

    /// ── La password si chiede all'INGRESSO ───────────────────────────────
    ///
    /// Giacomo, 2 settembre 2026: «non chiede una password per entrare in
    /// modalità amministratore».
    ///
    /// Era vero. Qui si metteva `amministratore = true` e basta: la password
    /// la chiedeva la prima operazione, tramite `pkexec`. Funzionava, ma
    /// diceva la cosa sbagliata — la scritta «modalità amministratore» compare
    /// subito, e da quel momento in poi chi guarda lo schermo crede di essere
    /// amministratore. Lo è per davvero solo dal primo `pkexec` in poi, e
    /// nell'intervallo fra le due cose sta un clic che non farà quello che
    /// sembra.
    ///
    /// Adesso si chiede prima, con un'operazione che non fa niente
    /// (`minerva-radice permesso`), e la modalità si accende **solo** se la
    /// password è stata data. Annullare la finestrella lascia tutto com'era.
    function accendiAmministratore() {
        if (!manager.radiceCE || manager.inAttesaDiPermesso)
            return;
        manager.inAttesaDiPermesso = true;
        problem.dillo(Core.Strings.lang === "it"
            ? "Chiedo i permessi di amministratore…"
            : "Asking for administrator permissions…");
        Core.Ipc.radiceChiediPermesso();
    }

    /// Accende per davvero. Ci si arriva solo da `onRadicePermesso`, cioè con
    /// la password già data.
    function accendiDavvero() {
        manager.amministratore = true;
        scadenzaRadice.restart();
        // Se si è in una cartella che non si è potuta leggere — `/root` —
        // adesso si può: si rilegge subito, invece di lasciare a chi guarda
        // il compito di indovinare che deve premere F5.
        if (manager.current && manager.current.error !== "")
            manager.current.reload();
        // ── E il messaggio dice la verità ────────────────────────────────
        //
        // Diceva «ogni operazione chiede la password», e non era vero: la
        // regola polkit è `auth_admin_keep` (`config/polkit/…radice.policy`),
        // quindi la password vale per qualche minuto e le operazioni che
        // seguono non la chiedono. È esattamente il motivo per cui la modalità
        // si spegne da sola: la protezione non è la password ripetuta, è che
        // la finestra non resti amministratrice mentre non guardi.
        problem.dillo(Core.Strings.lang === "it"
            ? "Modalità amministratore accesa. Vale per qualche minuto senza "
              + "richiedere la password, e si spegne da sola dopo dieci."
            : "Administrator mode is on. It stays valid for a few minutes "
              + "without asking again, and switches itself off after ten.");
    }

    function spegniAmministratore() {
        manager.amministratore = false;
        scadenzaRadice.stop();
    }

    /// Fa fare una cosa all'aiutante di root, e riavvia il conto alla
    /// rovescia. Ogni chiamata passa da `pkexec`: la password la chiede il
    /// sistema, non noi, e noi non la vediamo mai.
    /// Restituisce falso quando NON se n'è occupata — e allora tocca alla
    /// strada normale.
    ///
    /// La condizione non è «la modalità è accesa» ma «la modalità è accesa E
    /// qui non si scrive». Senza la seconda metà, con la modalità accesa
    /// anche un «Nuova cartella» dentro Documenti passerebbe da root, e ti
    /// ritroveresti in casa tua una cartella di proprietà di root che poi non
    /// puoi più cancellare. È il genere di regalo che una modalità
    /// amministratore fa se la si scrive di fretta.
    function radice(op, args) {
        if (!manager.operaComeRoot)
            return false;
        scadenzaRadice.restart();
        Core.Ipc.radiceAzione(op, args);
        return true;
    }

    function scriviQui() {
        if (!manager.current || manager.current.scrivibile)
            return true;
        // In modalità amministratore si può: il rifiuto qui sarebbe un divieto
        // nostro sopra un permesso che il sistema ha già dato.
        if (manager.amministratore)
            return true;
        problem.show(Core.Strings.lang === "it"
            ? (manager.radiceCE
               ? "Questa cartella è di sistema. Per cambiarla accendi la "
                 + "modalità amministratore dal menu del tasto destro."
               : "Questa cartella è di sistema: si può guardare, non cambiare. "
                 + "Per modificarla serve un amministratore.")
            : (manager.radiceCE
               ? "This folder belongs to the system. To change it, turn on "
                 + "administrator mode from the right-click menu."
               : "This folder belongs to the system: you can look, not change. "
                 + "Changing it needs an administrator."));
        return false;
    }

    function doTrash() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        if (!manager.scriviQui())
            return;
        trashConfirm.paths = ops;
        // Chi ha tolto la domanda l'ha tolta davvero: il cestino è già una
        // rete, e chiedere due volte per un'azione reversibile è il tipo di
        // attrito che fa smettere di leggere le domande — comprese quelle
        // che contano.
        if (!Core.Ipc.get("files.confermaCestino", true)) {
            Core.Ipc.fsTrash(ops);
            return;
        }
        trashConfirm.open();
    }

    // ── Archivi ──────────────────────────────────────────────────────────
    //
    // Nessuna finestra di mezzo, né per comprimere né per estrarre. È la
    // scelta che rende la cosa usabile: il novanta per cento delle volte si
    // vuole «questo, in uno zip, qui» — e un archivio creato col nome
    // sbagliato si rinomina in due secondi, mentre una finestra da compilare
    // la si paga tutte le volte. Il nome lo sceglie il demone, che sa anche
    // non sovrascrivere niente.

    function doCompress() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        // L'archivio nasce ACCANTO a quello che comprime, quindi dentro questa
        // cartella: comprimere in una cartella di sistema è scriverci.
        if (!manager.scriviQui())
            return;
        problem.attesa = Core.Strings.lang === "it" ? "Comprimo…" : "Compressing…";
        Core.Ipc.fsCompress(ops, "zip", "");
    }

    function doExtract() {
        var archivio = manager.selectedArchive();
        if (archivio === "")
            return;
        // «Estrai qui» vuol dire proprio qui.
        if (!manager.scriviQui())
            return;
        problem.attesa = Core.Strings.lang === "it" ? "Estraggo…" : "Extracting…";
        Core.Ipc.fsExtract(archivio);
    }

    /// Installa l'archivio scelto come set di icone.
    ///
    /// Non chiede conferma e non chiede dove: il posto è uno solo
    /// (`~/.local/share/icons`, che è lo standard freedesktop) e l'azione è
    /// reversibile — il tema si toglie dalle Impostazioni. Chiedere conferma
    /// per una cosa che si disfa con un clic è rumore.
    ///
    /// Chi rifiuta è il demone, e rifiuta parecchio: un archivio senza
    /// `index.theme` non è un tema, e uno che contiene eseguibili o `.desktop`
    /// viene scartato INTERO, dicendo quale file e perché. Un tema è dati.
    function doInstallaIcone() {
        var archivio = manager.selectedArchive();
        if (archivio === "")
            return;
        problem.attesa = Core.Strings.lang === "it"
                         ? "Installo le icone…" : "Installing icons…";
        Core.Ipc.iconeInstalla(archivio);
    }

    // ── Cestino ──────────────────────────────────────────────────────────

    function doRestore() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        Core.Ipc.fsTrashRestore(ops);
    }

    /// Mette come sfondo l'immagine scelta.
    function sfondoDaFile() {
        var ops = manager.operands();
        if (ops.length !== 1 || !manager.current)
            return;
        manager.mettiSfondo({ "tipo": "immagine", "valore": ops[0] });
    }

    /// La fotografia scelta diventa lo sfondo della SCRIVANIA. Passa da
    /// `Core.Wallpaper` e non da `setSetting` diretto, perché scegliere uno
    /// sfondo è due impostazioni e non una: vedi il commento là.
    function sfondoScrivania() {
        var ops = manager.operands();
        if (ops.length !== 1)
            return;
        // Nessun messaggio di conferma: la conferma è la scrivania che
        // cambia, e si vede dietro alla finestra nello stesso istante.
        Core.Wallpaper.scegli(ops[0]);
    }

    /// Scrive l'aspetto e lo mostra subito, senza aspettare il giro di
    /// ritorno: uno sfondo che compare mezzo secondo dopo il clic sembra
    /// un'esitazione del programma.
    function mettiSfondo(aspetto) {
        if (!manager.current)
            return;
        manager.current.aspetto = aspetto;
        Core.Ipc.fsAspetto(manager.current.path, aspetto);
    }

    /// Un documento vuoto. C'è in tutti i gestori file del mondo tranne che
    /// nel nostro, e serve più spesso di quanto sembri: un appunto, un file
    /// di configurazione, una nota da riempire dopo.
    function doNewFile() {
        if (!manager.current || !manager.scriviQui())
            return;
        prompt.begin("newFile",
                     Core.Strings.lang === "it" ? "Nome del nuovo documento"
                                                : "Name of the new document",
                     Core.Strings.lang === "it" ? "Senza nome.txt" : "Untitled.txt");
    }

    /// Il percorso negli appunti. È la cosa che si copia più spesso e che
    /// finora si otteneva solo scrivendola a mano guardando le briciole.
    function doCopyPath() {
        var ops = manager.operands();
        if (ops.length === 0 && manager.current)
            ops = [manager.current.path];
        if (ops.length === 0)
            return;
        Quickshell.clipboardText = ops.join("\n");
    }

    /// Cancellare senza cestino. Maiusc+Canc è la scorciatoia che tutti
    /// conoscono, e finora qui non faceva niente: chi la premeva credeva di
    /// aver cancellato e invece non era successo nulla.
    function doDeleteForever() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        if (!manager.scriviQui())
            return;
        trashConfirm.paths = ops;
        trashConfirm.open(true);
    }

    /// Vero quando quello che si sta per fare passa dall'aiutante di root.
    /// Serve alla finestra di conferma, che deve dire parole diverse: da root
    /// non c'è cestino da cui ripescare.
    readonly property bool operaComeRoot: manager.amministratore
                                          && manager.current
                                          && !manager.current.scrivibile

    function doNewFolder() {
        if (!manager.current || !manager.scriviQui())
            return;
        prompt.begin("newFolder",
                     Core.Strings.lang === "it" ? "Nome della nuova cartella"
                                                : "Name of the new folder",
                     Core.Strings.lang === "it" ? "Senza nome" : "Untitled");
    }

    function doRename() {
        var ops = manager.operands();
        if (ops.length !== 1)
            return;
        if (!manager.scriviQui())
            return;
        prompt.begin("rename",
                     Core.Strings.lang === "it" ? "Nuovo nome" : "New name",
                     Files.baseName(ops[0]));
    }

    /// I pulsanti della barra, decisi da ciò che è selezionato adesso.
    ///
    /// Non è un elenco fisso con dei pulsanti spenti: è l'elenco di ciò che si
    /// può fare, e basta. Il perché per esteso sta nel commento del Repeater
    /// che lo consuma.
    readonly property var toolbarModel: {
        var n = manager.current ? manager.current.operands().length : 0;
        // ── Dove non si può scrivere, non si offre di scrivere ───────────
        //
        // Giacomo, 18 agosto 2026: «se clicco su sistema posso cancellare
        // qualsiasi file di sistema… non c'è nessuna protezione». Cancellare
        // non si poteva davvero, ma «Nuova cartella» e «Nuovo documento»
        // stavano lì a colori pieni sopra `/usr`, e il rifiuto arrivava solo
        // dopo aver scritto il nome. Questa barra si è già data la regola —
        // *«non è un elenco fisso con dei pulsanti spenti: è l'elenco di ciò
        // che si può fare»* — e la applicava a tutto tranne che ai permessi.
        // ── E la modalità amministratore riapre quello che i permessi
        //    avevano chiuso ─────────────────────────────────────────────
        //
        // Giacomo, 2 settembre 2026: «non vedo opzioni come sposta nel cestino
        // o altre cose utili» — parlando della modalità amministratore.
        //
        // La causa non era una voce dimenticata: erano TUTTE le voci di
        // scrittura, spente insieme da questa riga. `scrivibile` è «ci scrive
        // l'utente», e in `/root` è falso anche dopo aver dato la password —
        // quindi si accendeva la modalità amministratore e il menu restava
        // identico a prima, cioè la modalità sembrava non fare niente.
        //
        // È la stessa regola di sempre, applicata a un caso in più: *l'elenco
        // è ciò che si può fare*. Da amministratore si può, e le operazioni
        // passano dall'aiutante di root (vedi `operaComeRoot`), quindi le voci
        // devono esserci. Il rifiuto vero, se mai serve, lo dà l'aiutante — e
        // lo dà per iscritto invece di far sparire il comando.
        var puoi = manager.amministratore
                   || !manager.current || manager.current.scrivibile;

        // Il cestino è una cartella scrivibile, quindi «Nuova cartella» e
        // «Nuovo documento» ci comparivano — e creare un documento dentro il
        // cestino non vuol dire niente: nasce già buttato via. Dentro il
        // cestino si viene a fare due cose, rimettere a posto e svuotare.
        var nelCestino = Files.inTrash(manager.current ? manager.current.path : "");
        if (nelCestino)
            puoi = false;

        var voci = [];

        // ── Dentro il cestino la barra dice un'altra cosa ────────────────
        //
        // Giacomo, 23 agosto 2026: «entrando nel cestino, un tasto nella barra
        // degli strumenti che compaia quando si è nel cestino per svuotarlo».
        //
        // «Svuota il cestino» c'era solo nel tasto destro, ed è l'unico posto
        // di tutto il gestore file in cui il comando che si viene a dare è UNO
        // e non si può indovinare: nel cestino non si crea niente e non si
        // incolla niente, quindi la barra era vuota proprio dove serviva.
        //
        // Compare per primo e in rosso, e chiede conferma come sempre: è
        // l'unica operazione del programma senza una rete sotto.
        // Un cestino già vuoto non si svuota: il pulsante non compare, come
        // ogni altro comando di questa barra che adesso non si può dare.
        if (nelCestino && manager.current
            && manager.current.entries.length > 0) {
            voci.push({ "id": "emptyTrash", "icon": "trash",
                        "danger": true,
                        "it": "Svuota il cestino", "en": "Empty the bin" });
        }

        if (puoi)
            voci.push({ "id": "newFolder", "icon": "plus",
                        "it": "Nuova cartella", "en": "New folder" });

        // «Incolla» compare solo con qualcosa negli appunti. È l'unico comando
        // della barra che dipende da un'azione fatta PRIMA e altrove, quindi è
        // anche l'unico che vale la pena mostrare come promemoria.
        if (puoi && Files.clipboard.length > 0)
            voci.push({ "id": "paste", "icon": "check",
                        "it": "Incolla", "en": "Paste" });

        // ── Quello che il tasto destro NON sa fare ──────────────────────
        //
        // Qui c'erano Copia, Taglia e Rinomina. Sono tre comandi che stanno
        // già nel menu del tasto destro E hanno una scorciatoia da tastiera
        // (Ctrl+C, Ctrl+X, F2): metterli anche qui non aggiunge un modo di
        // farli, aggiunge tre pulsanti da guardare ogni volta che si cerca
        // qualcos'altro.
        //
        // Peggio: comparivano appena il cursore stava su una riga, senza che
        // nessuno avesse selezionato niente — quindi c'erano SEMPRE, e la
        // barra sembrava una fila fissa di doppioni. È la stessa cosa che
        // Giacomo aveva già segnalato per «sposta nel cestino»: «propone cose
        // duplicate, posso farlo col tasto destro».
        //
        // «Copia di là» e «Sposta di là» — gli unici comandi che da nessun'altra
        // parte si possono dare — stanno già in fondo a destra di questa
        // stessa barra, staccati perché sono un'altra categoria: non agiscono
        // sugli appunti, agiscono fra i riquadri. Rimetterli anche a sinistra
        // sarebbe ricominciare da capo con i doppioni.

        // ── Confronta ───────────────────────────────────────────────────
        //
        // Compare solo con due riquadri, perché con uno non c'è niente da
        // confrontare. Ed è l'unico comando qui dentro che ACCENDE un modo
        // invece di fare una cosa e finire: si vede da com'è disegnato.
        if (manager.panes.length > 1) {
            voci.push({ "id": "sep" });
            var c = manager.contoConfronto;
            voci.push({
                "id": "confronta",
                "icon": "split",
                "acceso": manager.confronto,
                "it": manager.confronto
                     ? (c.soli + c.diversi === 0
                        ? "Identiche"
                        : c.soli + " solo qui · " + c.diversi
                          + (c.diversi === 1 ? " diverso" : " diversi"))
                     : "Confronta",
                "en": manager.confronto
                     ? (c.soli + c.diversi === 0
                        ? "Identical"
                        : c.soli + " only here · " + c.diversi + " differ")
                     : "Compare"
            });
        }

        voci.push({ "id": "sep" });
        // Le schede sono comandi sulla FINESTRA e non sui file, ma è qui che
        // si va a cercarli. «Chiudi scheda» solo se ce n'è più di una.
        if (puoi && manager.tabs.count < manager.maxTabs)
            voci.push({ "id": "newFile", "icon": "document",
                        "it": "Nuovo documento", "en": "New document" });
        voci.push({ "id": "newTab", "icon": "split",
                    "it": "Nuova scheda", "en": "New tab" });
        voci.push({ "id": "newWindow", "icon": "window",
                    "it": "Nuova finestra", "en": "New window" });
        if (manager.tabs.count > 1)
            voci.push({ "id": "closeTab", "icon": "close",
                        "it": "Chiudi scheda", "en": "Close tab" });
        // Impostazioni PER ULTIMA, come in ogni barra del mondo: è l'unica
        // voce che non fa niente subito, e in mezzo ai comandi sembrava un
        // comando che non si sa premere.
        voci.push({ "id": "impostazioni", "icon": "sliders",
                    "it": "Impostazioni", "en": "Settings" });
        return voci;
    }



    // ── La barra del titolo ──────────────────────────────────────────────
    //
    // DENTRO la finestra e non sopra, e non è una scelta di stile: vedi il
    // lungo perché in cima a `ui/WindowTitleBar.qml`. In due parole: una
    // barra disegnata fuori insegue la finestra e arriva sempre in ritardo,
    // una barra che è la finestra non ha niente da inseguire.
    Ui.WindowTitleBar {
        id: titolo
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        // Il titolo, e nient'altro.
        //
        // Qui c'era appeso un contatore che saliva di uno al secondo — una
        // sonda di sviluppo rimasta accesa. Giacomo l'ha vista subito: «al
        // centro della barra del titolo credo siano secondi di apertura del
        // file manager, non richiesto».
        //
        // Non era solo brutta. Il titolo di una finestra non è roba nostra: lo
        // legge il compositore, che a ogni cambio emette `windowtitle`; lo
        // legge il demone; e il demone sveglia la shell. Una volta al secondo,
        // per sempre, anche a finestra ferma in secondo piano.
        //
        // La parte da ricordare: in `finestre_service.dart` c'è già una difesa
        // scritta apposta contro questo — «bastava UNA finestra col titolo
        // animato». Era stata scritta per un colpevole mai identificato, e il
        // colpevole eravamo noi.
        label: manager.title
        onCloseRequested: manager.requestClose()
    }

    Item {
        id: toolbar
        anchors.top: titolo.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 50

        // ── Due capsule, non una fascia ─────────────────────────────────
        //
        // In Liquid DE i comandi galleggiano: una capsula larga quanto
        // quello che contiene, che si allarga con una molla quando compare
        // un comando (una selezione) e si stringe quando sparisce. Sotto i
        // pulsanti scivola una goccia sola (`ui/Goccia.qml`).
        Rectangle {
            id: capsulaComandi
            anchors.left: parent.left
            anchors.leftMargin: manager.isola
            anchors.verticalCenter: parent.verticalCenter
            height: 38
            radius: height / 2
            width: comandiRow.implicitWidth + 2 * Theme.Effects.space1
            color: Theme.Colors.raised
            Behavior on width {
                enabled: Theme.Motion.liquido
                SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
            }

            Ui.Goccia {
                id: gocciaComandi
                radius: height / 2
            }
        }

        // Sotto una certa larghezza i comandi perdono l'etichetta e restano
        // solo le icone. La finestra si può affiancare a un'altra e diventare
        // stretta: due file di pulsanti che si accavallano sono peggio di due
        // file di icone senza nome.
        readonly property bool compact: toolbar.width < 880

        Row {
            id: comandiRow
            // Dentro la capsula, ma figlio della barra: la capsula si allarga
            // con la molla, i comandi stanno fermi dove devono stare.
            anchors.left: capsulaComandi.left
            anchors.leftMargin: Theme.Effects.space1
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            Repeater {
                // ── LA BARRA CAMBIA CON QUELLO CHE HAI IN MANO ───────────
                //
                // Prima erano dieci pulsanti sempre uguali, e la metà stava lì
                // spenta finché non si selezionava qualcosa. Giacomo: «quella
                // barra degli strumenti propone cose duplicate, come ad
                // esempio sposta nel cestino che posso farlo con il tasto
                // destro… in generale è da rendere più intelligente».
                //
                // Ha ragione due volte. **Duplicate**: ogni singolo comando di
                // quella barra sta anche nel menu del tasto destro, e ha pure
                // una scorciatoia. **Non intelligente**: una fila di pulsanti
                // spenti insegna a non guardarla più, e quando poi si accende
                // nessuno se ne accorge.
                //
                // La regola adesso è una sola: **si vede solo ciò che si può
                // fare adesso**. Senza selezione la barra ha due voci, non
                // sette; con una selezione compaiono i comandi che la
                // riguardano. Niente pulsanti spenti, niente da imparare a
                // ignorare.
                //
                // «Sposta nel cestino» dalla barra è **tolto**, e non per
                // duplicazione: è l'unico comando distruttivo, sta a un dito
                // da «Rinomina», e non c'è ragione di tenerne uno sempre
                // acceso in cima alla finestra. Restano Canc e il tasto
                // destro, che sono i due modi in cui lo cerca chiunque.
                model: manager.toolbarModel

                delegate: Rectangle {
                    id: tool
                    required property var modelData

                    readonly property bool isSep: modelData.id === "sep"

                    // Un pulsante che si vede si può premere: è il patto di
                    // questa barra. Resta come rete per il caso in cui la
                    // selezione cambi nell'istante fra il disegno e il clic.
                    readonly property bool usable: {
                        switch (modelData.id) {
                        case "paste":  return Files.clipboard.length > 0;
                        case "newFile":  return true;
                        case "impostazioni": return true;
                        case "newTab":   return manager.tabs.count < manager.maxTabs;
                        case "newWindow": return true;
                        case "closeTab": return manager.tabs.count > 1;
                        default: return true;
                        }
                    }

                    // Un comando che distrugge non ha lo stesso colore di
                    // «Nuova cartella». «Svuota il cestino» è l'unica cosa in
                    // tutto il gestore file che non si può annullare, e la
                    // barra non deve farla sembrare una delle altre.
                    readonly property color tone: tool.modelData.danger === true
                                                  ? Theme.Colors.danger
                                                  : Theme.Colors.accent

                    width: tool.isSep ? 13
                                      : toolRow.implicitWidth + Theme.Effects.space4
                    height: 30
                    radius: height / 2
                    // Un comando che ACCENDE un modo si vede che è acceso:
                    // resta colorato anche senza il puntatore sopra. Il
                    // passaggio del mouse lo disegna la goccia della capsula.
                    color: tool.modelData.acceso === true
                           ? Qt.alpha(tone, 0.22) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                    opacity: tool.isSep ? 1 : (usable ? 1 : 0.35)

                    Rectangle {
                        anchors.centerIn: parent
                        visible: tool.isSep
                        width: 1
                        height: 18
                        color: Theme.Colors.edge
                    }

                    Row {
                        id: toolRow
                        anchors.centerIn: parent
                        spacing: Theme.Effects.space2
                        visible: !tool.isSep

                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15; height: 15
                            name: tool.modelData.icon || ""
                            color: (toolMouse.containsMouse && tool.usable)
                                   || tool.modelData.danger === true
                                   ? tool.tone : Theme.Colors.textFaint
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !toolbar.compact
                            text: Core.Strings.lang === "it" ? (tool.modelData.it || "")
                                                             : (tool.modelData.en || "")
                            color: tool.modelData.danger === true
                                   ? Theme.Colors.danger : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }

                    MouseArea {
                        id: toolMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: tool.usable && !tool.isSep
                        onContainsMouseChanged: gocciaComandi.punta(tool, toolMouse.containsMouse)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            switch (tool.modelData.id) {
                            case "newFolder": manager.doNewFolder(); break;
                            case "newFile":   manager.doNewFile(); break;
                            case "impostazioni": impostazioni.apri(); break;
                            case "confronta": manager.confronto = !manager.confronto; break;
                            case "paste":     manager.doPaste(); break;
                            case "newTab":    manager.addTab(); break;
                            case "newWindow": manager.apriNuovaFinestra(); break;
                            case "closeTab":  manager.closeCurrentTab(); break;
                            case "emptyTrash": emptyConfirm.open(); break;
                            }
                        }
                    }
                }
            }
        }

        // I due pulsanti che spostano roba da un riquadro all'altro. Sono a
        // destra e staccati dagli altri: non agiscono sugli appunti, agiscono
        // fra i due riquadri, ed è una categoria di comando diversa.
        Rectangle {
            anchors.fill: incrocioRow
            anchors.margins: -Theme.Effects.space1
            visible: incrocioRow.visible
            radius: height / 2
            color: Theme.Colors.raised
        }

        Row {
            id: incrocioRow
            anchors.right: parent.right
            anchors.rightMargin: manager.isola + Theme.Effects.space1
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            // Con una scheda sola non c'è nessun «altro riquadro» dove
            // mandare le cose. Il pulsante spariva sotto le dita restando
            // spento: adesso non c'è proprio, e la barra si legge meglio.
            visible: manager.tabs.count > 1

            Repeater {
                // Le etichette dicono DOVE finisce la roba, non «di là».
                // «Di là» costringe a ricordare quale riquadro è attivo; una
                // freccia e un lato si leggono senza pensarci.
                model: [
                    { "id": "copyOther", "it": "Copia", "en": "Copy", "key": "F5" },
                    { "id": "moveOther", "it": "Sposta", "en": "Move", "key": "F6" }
                ]

                delegate: Rectangle {
                    id: cross
                    required property var modelData

                    // Non basta che ci sia un'altra scheda e qualcosa di
                    // selezionato: l'altra scheda dev'essere una destinazione
                    // dove la roba può davvero andare. Un pulsante acceso che
                    // non fa niente è peggio di un pulsante spento.
                    readonly property bool usable:
                        manager.current
                        && manager.current.operands().length > 0
                        && (manager.asksWhere
                            ? manager.destinationChoices().length > 0
                            : (manager.other
                               && manager.other.path !== manager.current.path))

                    width: crossText.implicitWidth + Theme.Effects.space5
                    height: 30
                    radius: height / 2
                    color: crossMouse.containsMouse && usable
                           ? Qt.alpha(Theme.Colors.accent, 0.14) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                    opacity: usable ? 1 : 0.35

                    /// Verso in cui si sposta la roba: dalla scheda attiva
                    /// alla successiva, che gira in tondo. Vale solo con due
                    /// schede — con tre la freccia mentirebbe, perché la
                    /// destinazione non è ancora decisa.
                    readonly property bool toRight:
                        manager.currentIndex < manager.tabs.count - 1

                    Text {
                        id: crossText
                        anchors.centerIn: parent
                        // Stretti, restano i due tasti funzione: sono comunque
                        // il modo più veloce di usarli, e occupano nulla.
                        text: toolbar.compact
                              ? cross.modelData.key
                              : (Core.Strings.lang === "it" ? cross.modelData.it
                                                            : cross.modelData.en)
                              + (toolbar.compact ? ""
                                 : (manager.asksWhere ? "…"
                                    : (cross.toRight ? "  →" : "  ←")))
                        color: crossMouse.containsMouse && cross.usable
                               ? Theme.Colors.accent : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: crossMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: cross.usable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: manager.sendToOther(cross.modelData.id === "moveOther")
                    }
                }
            }
        }
    }

    // ── Scorciatoie ──────────────────────────────────────────────────────
    //
    // Sono `Shortcut` e non un gestore di tasti su un Item, e la differenza
    // qui non è di stile: il fuoco della tastiera vive DENTRO i riquadri —
    // l'elenco dei file, il campo del percorso — e un Item fratello non riceve
    // mai un tasto, perché i tasti risalgono la catena dei genitori e non
    // attraversano i rami. Erano scritte così, e F2, F5, Ctrl+C non facevano
    // niente. `Shortcut` guarda la finestra intera e non dipende dal fuoco.
    //
    // Si spengono mentre si sta scrivendo: nel campo del percorso o nella
    // finestrella del nome, Ctrl+C deve copiare il testo e F2 non deve partire
    // in mezzo a una parola.

    readonly property bool typing: {
        if (prompt && prompt.visible)
            return true;
        for (var i = 0; i < manager.panes.length; i++)
            if (manager.panes[i] && manager.panes[i].editingPath)
                return true;
        return false;
    }

    /// Vero anche quando c'è una domanda aperta sullo schermo. Le scorciatoie
    /// guardano la finestra intera e non il fuoco: senza questo, «Canc» con la
    /// richiesta di destinazione aperta apriva la conferma del cestino SOPRA
    /// di essa, e a quel punto non si capisce più a che cosa si sta
    /// rispondendo.
    readonly property bool busy: manager.typing
                                 || (destination !== null && destination.visible)
                                 || (trashConfirm !== null && trashConfirm.visible)
                                 || (fileProps !== null && fileProps.visible)

    Shortcut { sequence: "Ctrl+C"; enabled: !manager.busy; onActivated: manager.doCopy() }
    Shortcut { sequence: "Ctrl+Shift+C"; enabled: !manager.busy; onActivated: manager.doCopyPath() }
    // Maiusc+Canc: la scorciatoia che tutti conoscono, e che qui finora
    // non faceva niente — chi la premeva credeva di aver cancellato.
    Shortcut { sequence: "Shift+Delete"; enabled: !manager.busy; onActivated: manager.doDeleteForever() }
    Shortcut { sequence: "Ctrl+X"; enabled: !manager.busy; onActivated: manager.doCut() }
    Shortcut { sequence: "Ctrl+V"; enabled: !manager.busy; onActivated: manager.doPaste() }
    Shortcut { sequence: "Ctrl+N"; enabled: !manager.busy; onActivated: manager.doNewFolder() }
    Shortcut { sequence: "F2";     enabled: !manager.busy; onActivated: manager.doRename() }
    // Ctrl+F apre la riga di filtro del riquadro attivo. Non si spegne con
    // `busy` come le altre: cercare mentre una copia è in corso è legittimo.
    Shortcut {
        sequence: "Ctrl+F"
        enabled: !manager.typing
        onActivated: if (manager.current) manager.current.startFilter()
    }
    Shortcut { sequence: "F4";     enabled: !manager.busy; onActivated: manager.openTerminalHere() }
    Shortcut { sequence: "F5";     enabled: !manager.busy; onActivated: manager.sendToOther(false) }
    Shortcut { sequence: "F6";     enabled: !manager.busy; onActivated: manager.sendToOther(true) }
    Shortcut { sequence: "Delete"; enabled: !manager.busy; onActivated: manager.doTrash() }
    Shortcut { sequence: "Ctrl+T"; enabled: !manager.busy; onActivated: manager.addTab() }
    // Ctrl+N è già «nuova cartella» qui da prima, e cambiarglielo sotto le
    // mani a chi lo usa sarebbe peggio di una scorciatoia insolita.
    Shortcut { sequence: "Ctrl+Shift+N"; enabled: !manager.busy; onActivated: manager.apriNuovaFinestra() }
    Shortcut { sequence: "Ctrl+W"; enabled: !manager.busy; onActivated: manager.closeCurrentTab() }
    Shortcut { sequence: "Alt+Return"; enabled: !manager.busy; onActivated: manager.doProperties() }
    Shortcut {
        sequence: "Tab"
        enabled: !manager.busy && manager.panes.length > 1
        onActivated: manager.focusIndex((manager.currentIndex + 1) % manager.panes.length)
    }

    // ── La colonna di sinistra ───────────────────────────────────────────
    //
    // Tre gruppi, e sono tre cose diverse: le cartelle di casa, i percorsi che
    // ha scelto l'utente, i dischi. Tenerli separati non è ordine per amore
    // dell'ordine — un disco si può smontare e una cartella no, un percorso
    // fissato si può togliere e Home no. Gruppi diversi, comandi diversi.
    //
    // Scorre: con quattro dischi montati e sei percorsi fissati la colonna è
    // più alta della finestra, e senza scorrimento le ultime voci sarebbero
    // semplicemente irraggiungibili.

    // La colonna dei posti è area di LETTURA come l'elenco, non chrome:
    // ci si cerca «Immagini» leggendo. Prende la stessa superficie piena,
    // così le due metà del corpo della finestra sono un materiale solo e il
    // vetro resta dove serve — la striscia dei comandi in alto, che è quella
    // che deve far vedere che sotto c'è una scrivania.
    //
    // In Liquid DE la colonna è un'isola: staccata dai bordi della finestra,
    // arrotondata, e sotto le voci scivola una goccia sola (`ui/Goccia.qml`)
    // invece di tante voci che si accendono ognuna per conto suo.
    Rectangle {
        id: places
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.bottom: transfers.top
        anchors.leftMargin: manager.isola
        anchors.bottomMargin: manager.isola
        width: 194
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.lettura
        // Il filo non delimita: fa cogliere la curvatura dell'isola sul vetro
        // della finestra, che su un tema scuro ha quasi lo stesso colore.
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        Ui.Scorrimento {
            bersaglio: colonnaPosti
            anchors {
                right: colonnaPosti.right
                top: colonnaPosti.top
                bottom: colonnaPosti.bottom
            }
        }

        Flickable {
            id: colonnaPosti
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            contentHeight: sideColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Ui.Goccia {
                id: gocciaPosti
                radius: Theme.Effects.radiusSM
            }

            Column {
                id: sideColumn
                width: parent.width
                spacing: 1

                // ── Casa ─────────────────────────────────────────────────

                Repeater {
                    model: Files.places
                    delegate: SideEntry {
                        required property var modelData
                        goccia: gocciaPosti
                        attiva: manager.current !== null && path !== ""
                                && manager.current.path === path
                        width: sideColumn.width
                        icon: modelData.icon
                        onRilasciato: function (sorgenti) {
                            manager.chiediCopiaOSposta(sorgenti, modelData.path);
                        }
                        label: Core.Strings.lang === "it" ? modelData.it : modelData.en
                        path: modelData.path
                        // Va nel riquadro che ha il fuoco: cliccare una
                        // scorciatoia non deve mai cambiare la cartella che
                        // si sta guardando dall'altra parte.
                        onChosen: if (manager.current) manager.current.navigate(path)
                    }
                }

                // ── Fissati ──────────────────────────────────────────────

                Item {
                    width: sideColumn.width
                    height: 28

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: Core.Strings.lang === "it" ? "FISSATI" : "PINNED"
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                        font.letterSpacing: 1
                    }

                    // Fissa la cartella che si sta guardando. È il gesto che
                    // serve nel momento in cui serve: si arriva in una
                    // cartella, si capisce che ci si tornerà, si preme.
                    Rectangle {
                        id: pinNow
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 20; height: 20
                        radius: Theme.Effects.radiusXS
                        visible: manager.current
                                 && !Files.isPinned(manager.current.path)
                        color: pinNowMouse.containsMouse
                               ? Qt.alpha(Theme.Colors.accent, 0.18) : "transparent"

                        Ui.Icon {
                            anchors.centerIn: parent
                            width: 12; height: 12
                            name: "pin"
                            color: pinNowMouse.containsMouse ? Theme.Colors.accent
                                                             : Theme.Colors.textFaint
                        }

                        MouseArea {
                            id: pinNowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (manager.current)
                                           Files.togglePinned(manager.current.path)
                        }
                    }
                }

                Text {
                    width: sideColumn.width
                    visible: Files.pinned.length === 0
                    leftPadding: Theme.Effects.space2
                    bottomPadding: Theme.Effects.space2
                    wrapMode: Text.WordWrap
                    text: Core.Strings.lang === "it"
                          ? "Nessuno. Il pulsante qui sopra fissa la cartella che stai guardando."
                          : "None. The button above pins the folder you are in."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Repeater {
                    model: Files.pinned
                    delegate: SideEntry {
                        required property var modelData
                        goccia: gocciaPosti
                        attiva: manager.current !== null && path !== ""
                                && manager.current.path === path
                        width: sideColumn.width
                        // Una cartella, non una puntina: la puntina è il
                        // pulsante che fissa, e vuol dire un'azione. Qui sono
                        // cartelle, e devono somigliare alle altre cartelle
                        // della colonna.
                        icon: "cartella-fissata"
                        onRilasciato: function (sorgenti) {
                            manager.chiediCopiaOSposta(sorgenti, modelData);
                        }
                        label: Files.baseName(modelData) || modelData
                        path: modelData
                        removable: true
                        onChosen: if (manager.current) manager.current.navigate(path)
                        onRemoved: Files.togglePinned(path)
                    }
                }

                // ── Dischi ───────────────────────────────────────────────

                Item {
                    width: sideColumn.width
                    height: 28
                    visible: Files.volumes.length > 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: Core.Strings.lang === "it" ? "DISPOSITIVI" : "DEVICES"
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                        font.letterSpacing: 1
                    }
                }

                Repeater {
                    model: Files.volumes

                    delegate: SideEntry {
                        id: volume
                        required property var modelData
                        goccia: gocciaPosti
                        attiva: manager.current !== null && path !== ""
                                && manager.current.path === path

                        onRilasciato: function (sorgenti) {
                            manager.chiediCopiaOSposta(sorgenti, volume.path);
                        }
                        width: sideColumn.width
                        icon: modelData.removable ? "chiavetta" : "disco"
                        label: modelData.name
                        // Un disco non montato non ha un percorso: si dice
                        // quanto è grande, che è l'unica cosa che se ne sa.
                        detail: modelData.mounted ? modelData.mountPoint
                                                  : modelData.size
                        path: modelData.mountPoint
                        dimmed: !modelData.mounted
                        ejectable: modelData.mounted && modelData.removable

                        onChosen: {
                            if (modelData.mounted) {
                                if (manager.current)
                                    manager.current.navigate(modelData.mountPoint);
                                return;
                            }
                            // Non montato: si monta, e ci si va appena è
                            // pronto. Chiedere due clic per una cosa sola —
                            // «monta» e poi «apri» — è una distinzione che
                            // interessa al sistema, non a chi guarda.
                            manager.mountThenOpen = volume.modelData.device;
                            Core.Ipc.fsMount(volume.modelData.device);
                        }

                        onEjected: Core.Ipc.fsUnmount(volume.modelData.device)

                        // Il tasto destro su un disco: espellere e
                        // formattare. Formattare NON è un pulsante nella
                        // colonna — sta sotto il tasto destro, dove non lo si
                        // preme per sbaglio mentre si cerca di aprire una
                        // chiavetta.
                        onSecondary: {
                            var it = Core.Strings.lang === "it";
                            var voci = [];
                            if (volume.modelData.mounted)
                                voci.push({ "label": it ? "Espelli" : "Eject",
                                            "icon": "back", "action": "eject" });
                            if (volume.modelData.removable)
                                voci.push({ "label": it ? "Formatta…" : "Format…",
                                            "icon": "wrench", "action": "format",
                                            "danger": true });
                            if (voci.length === 0)
                                return;
                            manager.discoScelto = volume.modelData;
                            volumeMenu.openAtCursor(voci);
                        }
                    }
                }
            }
        }
    }

    /// Il disco che si è appena chiesto di montare, per andarci quando il
    /// demone risponde col punto di mount.
    property string mountThenOpen: ""

    Connections {
        target: Core.Ipc

        function onFileResultReceived(result) {
            if (manager.mountThenOpen === "")
                return;
            manager.mountThenOpen = "";
            if (result.ok === true && result.mountPoint
                && result.mountPoint !== "" && manager.current)
                manager.current.navigate(result.mountPoint);
        }
    }

    // Il controllo periodico dei dischi gira solo mentre una finestra è
    // aperta: vedi `watchers` in Files.qml.
    Component.onDestruction: Files.watchers -= 1

    // ── I due riquadri ───────────────────────────────────────────────────

    Row {
        id: panes
        anchors.top: toolbar.bottom
        anchors.left: places.right
        anchors.right: parent.right
        anchors.bottom: transfers.top
        anchors.margins: manager.isola
        anchors.topMargin: 0
        spacing: manager.isola

        readonly property real cell: (width - spacing * (manager.tabs.count - 1))
                                     / Math.max(1, manager.tabs.count)

        Repeater {
            id: paneRepeater
            model: manager.tabs

            delegate: Pane {
                id: tabPane
                required property int index
                required property string startPath

                solo: manager.tabs.count === 1
                // Lo stato è della finestra: tutte le schede lo mostrano, così
                // non si può essere amministratori in una e non accorgersene
                // nell'altra.
                amministratore: manager.amministratore
                // Solo il riquadro attivo si colora: il confronto è «cosa ho
                // qui che non è di là», e dipende da qual è «qui».
                esitoConfronto: tabPane.index === manager.currentIndex
                                ? manager.esitoConfronto : ({})
                paneId: manager.finestraId + "t" + index
                width: panes.cell
                height: panes.height
                canClose: manager.tabs.count > 1

                Component.onCompleted: {
                    manager.registerPane(index, tabPane);
                    navigate(tabPane.startPath);
                }
                Component.onDestruction: manager.forgetPane(tabPane)

                onActivated: manager.focusPane(tabPane)
                onOpenRequested: function(p) { manager.openExternally(p); }
                onCloseRequested: manager.closeTab(tabPane.index)
                onMenuRequested: {
                    manager.focusPane(tabPane);
                    paneMenu.openAtCursor(manager.paneMenuItems());
                }
                onRilasciato: function(sorgenti, destinazione) {
                    manager.chiediCopiaOSposta(sorgenti, destinazione);
                }
                onRilascioSenzaFile: {
                    problem.show(Core.Strings.lang === "it"
                                 ? "Qui si possono lasciare solo file di questo computer."
                                 : "Only files from this computer can be dropped here.");
                }
            }
        }
    }

    /// Il Repeater costruisce e distrugge i riquadri; l'elenco `panes` deve
    /// seguirlo. Si ricostruisce per intero invece di infilare l'elemento al
    /// posto giusto: chiudendo una scheda in mezzo tutti gli indici dopo di
    /// lei scalano, e un elenco aggiornato a pezzi si disallinea al primo
    /// buco.
    function registerPane(index, p) {
        manager.rebuildPanes();
    }

    function forgetPane(p) {
        rebuildLater.restart();
    }

    function rebuildPanes() {
        var list = [];
        for (var i = 0; i < paneRepeater.count; i++) {
            var p = paneRepeater.itemAt(i);
            if (p)
                list.push(p);
        }
        manager.panes = list;
        if (manager.currentIndex >= list.length)
            manager.currentIndex = Math.max(0, list.length - 1);
        for (var j = 0; j < list.length; j++)
            list[j].focused = (j === manager.currentIndex);
    }

    Timer {
        id: rebuildLater
        interval: 20
        onTriggered: manager.rebuildPanes()
    }

    // ── Trasferimenti ────────────────────────────────────────────────────

    Transfers {
        id: transfers
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space2
    }

    // ── Quando qualcosa non riesce ───────────────────────────────────────
    //
    // Il demone rispondeva già `{ok: false, error: "…"}` a chi chiede di
    // creare una cartella, rinominare o cestinare — e nessuno leggeva quella
    // risposta. Un nome già preso, un permesso mancante, un disco pieno: il
    // comando non faceva niente e la finestra non diceva niente. Chi guarda
    // conclude che il pulsante è rotto, che è la conclusione giusta data
    // l'evidenza.
    //
    // Compare qui sopra ai riquadri, non in una finestrella da chiudere: è
    // una notizia, non una domanda. Va via da sola.

    Rectangle {
        id: problem

        property string message: ""

        /// La stessa striscia dice anche «sto lavorando».
        ///
        /// Comprimere una cartella di foto non è istantaneo, e senza niente a
        /// schermo il secondo clic parte da solo: si ottengono due archivi e
        /// si dà la colpa al programma. Non è un guasto, quindi non è rossa —
        /// ma è nello stesso posto, che è dove l'occhio è già abituato a
        /// cercare le notizie in questa finestra.
        property string attesa: ""

        /// E dice anche «è andata bene».
        ///
        /// Terzo stato, e serve: c'erano solo «sto lavorando» e «è un guasto»,
        /// quindi una cosa riuscita non aveva modo di dirlo e restava muta.
        /// Va benissimo per copiare un file — si vede comparire — ma non per
        /// quello che riesce **altrove**: installare un set di icone mette
        /// roba in `~/.local/share/icons`, dove nessuno sta guardando, e senza
        /// una riga il comando sembra non aver fatto niente.
        property string notizia: ""

        readonly property bool guasto: problem.message !== ""
        readonly property string testo:
            problem.guasto ? problem.message
                           : (problem.notizia !== "" ? problem.notizia
                                                     : problem.attesa)

        function show(text) {
            problem.message = text || "";
            problem.notizia = "";
            if (problem.message !== "")
                problemTimer.restart();
        }

        /// Una buona notizia. Resta più a lungo di un guasto di proposito:
        /// spesso contiene un «adesso vai in…», e sette secondi non bastano a
        /// leggerlo e andarci.
        function dillo(text) {
            problem.notizia = text || "";
            problem.message = "";
            if (problem.notizia !== "")
                problemTimer.restart();
        }

        anchors.bottom: transfers.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.Effects.space2
        width: Math.min(manager.width - Theme.Effects.space6,
                        problemRow.implicitWidth + Theme.Effects.space5)
        height: 34
        radius: Theme.Effects.radiusSM
        color: problem.guasto ? Qt.rgba(0.22, 0.06, 0.10, 0.96)
                              : Theme.Colors.panel
        border.width: 1
        border.color: problem.guasto ? Qt.alpha(Theme.Colors.danger, 0.5)
                                     : Theme.Colors.edge
        z: 20

        opacity: problem.testo !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        Timer {
            id: problemTimer
            // Dodici secondi per una buona notizia, sette per un guasto: la
            // buona notizia di solito dice anche dove andare adesso, e
            // leggerla e andarci non sta in sette.
            interval: problem.notizia !== "" ? 12000 : 7000
            onTriggered: { problem.message = ""; problem.notizia = ""; }
        }

        Row {
            id: problemRow
            anchors.centerIn: parent
            spacing: Theme.Effects.space2

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 15; height: 15
                name: problem.guasto ? "close"
                                     : (problem.notizia !== "" ? "check"
                                                               : "archive")
                color: problem.guasto ? Theme.Colors.danger
                                      : (problem.notizia !== ""
                                         ? Theme.Colors.accent
                                         : Theme.Colors.textMuted)
                alwaysDrawn: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: problem.testo
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        // Cliccandoci sopra se ne va subito: chi ha già letto non deve
        // aspettare sette secondi per riavere indietro il suo spazio.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Solo il guasto si scaccia con un clic. L'avviso «sto lavorando»
            // no: sparisce quando il lavoro è finito, e toglierlo prima
            // vorrebbe dire nascondere l'unica cosa che spiega l'attesa.
            onClicked: { problem.message = ""; problem.notizia = ""; }
        }
    }

    Connections {
        target: Core.Ipc

        function onFileResultReceived(result) {
            // «Serve una scelta» non è un guasto: è la finestra «apri con» che
            // sta per aprirsi, e l'ha già gestita chi di dovere più su.
            if (result.needsChoice === true)
                return;
            // Qualunque risposta chiude l'attesa. Anche una che non riguarda
            // l'archivio: meglio togliere la scritta un istante prima che
            // lasciarla accesa per sempre se una risposta si perde.
            problem.attesa = "";
            if (result.ok === false && result.error && result.error !== "")
                problem.show(result.error);
        }

        /// L'esito dell'installazione di un set di icone.
        ///
        /// Quando va bene si dice comunque qualcosa, e non è pignoleria: le
        /// icone nuove **non si vedono da nessuna parte** finché non si va in
        /// Impostazioni → Aspetto a sceglierle. Senza una riga, il comando
        /// sembra non aver fatto niente — che è il modo più veloce di far
        /// credere rotta una cosa che funziona.
        function onIconeEsito(esito) {
            problem.attesa = "";
            var e = esito || {};
            var it = Core.Strings.lang === "it";
            if (e.ok === true) {
                problem.dillo(it
                    ? "«" + (e.nome || "") + "» installato. Per usarlo: "
                      + "Impostazioni → Aspetto → Icone."
                    : "“" + (e.nome || "") + "” installed. To use it: "
                      + "Settings → Appearance → Icons.");
                // L'elenco dei temi si rilegge dal disco: senza, il tema
                // appena installato non comparirebbe fino alla riapertura
                // delle Impostazioni.
                Core.Ipc.requestIconThemes();
            } else if (e.error && e.error !== "") {
                problem.show(e.error);
            }
        }
    }

    // ── Menu contestuale ─────────────────────────────────────────────────

    function paneMenuItems() {
        var it = Core.Strings.lang === "it";
        var n = manager.operands().length;
        // ── Dove non si può scrivere, non si offre di scrivere ───────────
        //
        // Stessa regola della barra, e stesso motivo: sopra `/usr` questo
        // menu offriva Taglia, Rinomina, «Sposta nel cestino» ed «Elimina
        // definitivamente» esattamente come sopra Documenti. Aprire, copiare
        // e guardare invece si può, e restano.
        // ── E la modalità amministratore riapre quello che i permessi
        //    avevano chiuso ─────────────────────────────────────────────
        //
        // Giacomo, 2 settembre 2026: «non vedo opzioni come sposta nel cestino
        // o altre cose utili» — parlando della modalità amministratore.
        //
        // La causa non era una voce dimenticata: erano TUTTE le voci di
        // scrittura, spente insieme da questa riga. `scrivibile` è «ci scrive
        // l'utente», e in `/root` è falso anche dopo aver dato la password —
        // quindi si accendeva la modalità amministratore e il menu restava
        // identico a prima, cioè la modalità sembrava non fare niente.
        //
        // È la stessa regola di sempre, applicata a un caso in più: *l'elenco
        // è ciò che si può fare*. Da amministratore si può, e le operazioni
        // passano dall'aiutante di root (vedi `operaComeRoot`), quindi le voci
        // devono esserci. Il rifiuto vero, se mai serve, lo dà l'aiutante — e
        // lo dà per iscritto invece di far sparire il comando.
        var puoi = manager.amministratore
                   || !manager.current || manager.current.scrivibile;
        var items = [];
        // «Apri» solo con qualcosa di selezionato: sul vuoto una voce che
        // non fa niente è una promessa falsa.
        if (n > 0) {
            var uno = (n === 1 && !manager.selectedDirectory())
                      ? manager.operands()[0] : "";
            // Quel che il demone ha detto di QUESTO file, non di quello di
            // prima: la risposta arriva dopo, e un menu che descrive il file
            // precedente è peggio di un menu che non descrive niente.
            var t = (uno !== "" && manager.tipoScelto
                     && manager.tipoScelto.path === uno)
                    ? manager.tipoScelto : null;

            // «Apri» solo se qualcosa lo apre. Su un tipo che nessun programma
            // dichiara, quella voce non apriva niente e non lo diceva — ed è
            // la stessa regola che questo file applica già al vuoto: una voce
            // che non fa niente è una promessa falsa.
            if (uno === "" || !t || t.defaultApp !== "")
                items.push({ "label": it ? "Apri" : "Open", "icon": "chevron",
                             "action": "open" });
            if (uno !== "")
                items.push({ "label": it ? "Apri con…" : "Open with…",
                             "icon": "apps", "action": "openWith" });

            // ── Eseguire ─────────────────────────────────────────────────
            //
            // Richiesta di Giacomo il 17 agosto 2026: «essendo un file .sh
            // vorrei poter avere la voce esegui nel terminale».
            if (uno !== "" && manager.eseguibileDi(uno)) {
                items.push({ "label": it ? "Esegui nel terminale"
                                         : "Run in the terminal",
                             "icon": "terminal", "action": "esegui" });
            } else if (uno !== "" && t && manager.tipoEseguibile(t.mime)) {
                // Uno script senza il permesso non si esegue di nascosto: si
                // offre di darglielo, che è una cosa sola e si vede.
                items.push({ "label": it ? "Rendi eseguibile" : "Make it runnable",
                             "icon": "check", "action": "eseguibile" });
            }
            items.push({ "separator": true });
        }
        // ── Quello che si fa a qualcosa, e quello che si fa a un posto ──
        //
        // Giacomo, 16 agosto 2026: «anche se clicco dove non c'è nessun file o
        // cartella esce scritto taglia, copia, e dovrebbe essere presente solo
        // se clicco su file».
        //
        // Aveva ragione, e il file lo diceva già di sé stesso venti righe più
        // su, per «Apri»: *sul vuoto una voce che non fa niente è una promessa
        // falsa*. La regola c'era, si applicava a metà. Copia, Taglia,
        // Rinomina, «sposta nel cestino» ed «elimina definitivamente»
        // comparivano sempre — cinque voci inerti, due delle quali rosse.
        //
        // Le funzioni dietro escono già subito su una selezione vuota
        // (`if (ops.length === 0) return;`), quindi non si rompe niente: si
        // smette di offrirle.
        if (n > 0) {
            items.push({ "label": it ? "Copia" : "Copy", "icon": "clipboard",
                         "action": "copy", "shortcut": "Ctrl+C" });
            // Copia sì, Taglia no: tagliare è mezzo spostamento, e la metà
            // che qui non riuscirebbe è proprio quella che toglie.
            if (puoi)
                items.push({ "label": it ? "Taglia" : "Cut", "icon": "back",
                             "action": "cut", "shortcut": "Ctrl+X" });
        }
        // «Incolla» invece non dipende dalla selezione ma dagli APPUNTI, ed è
        // il comando che sul vuoto serve di più: si clicca proprio lì per
        // mettere dentro quello che si è copiato altrove.
        if (puoi && Files.clipboard.length > 0)
            items.push({ "label": it ? "Incolla" : "Paste", "icon": "check",
                         "action": "paste", "shortcut": "Ctrl+V" });

        // Le voci che mandano roba in un'altra scheda compaiono solo se
        // un'altra scheda c'è — e se c'è qualcosa da mandarci.
        if (manager.other && n > 0) {
            items.push({ "separator": true });
            items.push({ "label": (it ? "Copia " : "Copy ") + manager.otherSideName,
                         "icon": "split", "action": "copyOther", "shortcut": "F5" });
            if (puoi)
                items.push({ "label": (it ? "Sposta " : "Move ") + manager.otherSideName,
                             "icon": "split", "action": "moveOther", "shortcut": "F6" });
        }

        items.push({ "separator": true });
        // Rinomina vuole UNA cosa sola, non «almeno una»: `doRename()` esce se
        // gli operandi non sono esattamente uno, quindi su tre file selezionati
        // era una voce che si poteva premere e non faceva niente.
        if (puoi && n === 1)
            items.push({ "label": it ? "Rinomina" : "Rename", "icon": "document",
                         "action": "rename", "shortcut": "F2" });
        if (puoi) {
            items.push({ "label": it ? "Nuova cartella" : "New folder",
                         "icon": "plus", "action": "newFolder",
                         "shortcut": "Ctrl+N" });
            items.push({ "label": it ? "Nuovo documento" : "New document",
                         "icon": "document", "action": "newFile" });
        }
        // Lo sfondo della cartella. Con un'immagine sola scelta la si può
        // usare direttamente: è il gesto più corto possibile, e su GNOME 2
        // era una finestra a parte da cui si trascinava.
        if (n === 1 && Files.isImage(Files.baseName(manager.operands()[0]))) {
            items.push({ "separator": true });
            // ── Le due voci non sono la stessa cosa ─────────────────────
            //
            // Giacomo, 18 agosto 2026: «per impostare lo sfondo devo copiare
            // il percorso dal file manager e incollarlo in impostazioni».
            // Aveva ragione, e la voce che c'era non lo tradiva: è lo sfondo
            // di QUESTA cartella, che è una decorazione del gestore file.
            // Quella della scrivania mancava — e il posto in cui si sceglie
            // una fotografia è dove la fotografia sta.
            // Etichette corte e PARALLELE. «Imposta come sfondo della
            // scrivania» e «Usa come sfondo della cartella» sono più larghe
            // del menu: si vedevano tutte e due tagliate a metà, e tagliate a
            // metà cominciavano con le stesse quattro parole.
            items.push({ "label": it ? "Sfondo della scrivania"
                                     : "Desktop wallpaper",
                         "icon": "image", "action": "sfondoScrivania" });
            items.push({ "label": it ? "Sfondo di questa cartella"
                                     : "Background of this folder",
                         "icon": "folder", "action": "sfondoDaFile" });
        } else if (n === 0) {
            items.push({ "separator": true });
            items.push({ "label": it ? "Sfondo di questa cartella…"
                                     : "Background of this folder…",
                         "icon": "image", "action": "sfondo" });
        }
        // ── Archivi ──────────────────────────────────────────────────────
        //
        // «Estrai qui» solo se ciò che è scelto è UN archivio: su due file
        // insieme non si sa dove metterli senza mescolarli, e su un `.odt`
        // non vuol dire niente. «Comprimi» invece vale su qualunque cosa,
        // purché ci sia una selezione: comprimere il vuoto non è un comando.
        if (puoi && n === 1 && manager.selectedArchive() !== "") {
            items.push({ "separator": true });
            items.push({ "label": it ? "Estrai qui" : "Extract here",
                         "icon": "archive", "action": "extract" });
            // ── Installa come set di icone ───────────────────────────────
            //
            // Sta qui e non nelle Impostazioni per un motivo di percorso: un
            // set di icone lo si scarica, e il posto in cui ci si trova
            // subito dopo è la cartella dei download, con l'archivio davanti.
            // Un selettore dentro le Impostazioni vorrebbe dire tornare a
            // cercare un file che si ha già sotto il puntatore.
            //
            // Non si controlla che dentro ci siano davvero delle icone: lo fa
            // il demone, che l'archivio lo apre — e se non lo sono, o se
            // contiene un eseguibile, lo dice e non installa niente. Vedi
            // `minervad/lib/services/tema_icone_service.dart`.
            items.push({ "label": it ? "Installa come set di icone"
                                     : "Install as icon set",
                         "icon": "apps", "action": "installaIcone" });
        } else if (puoi && n > 0) {
            items.push({ "separator": true });
            items.push({ "label": n > 1
                                  ? (it ? "Comprimi " + n + " elementi in ZIP"
                                        : "Compress " + n + " items to ZIP")
                                  : (it ? "Comprimi in ZIP" : "Compress to ZIP"),
                         "icon": "archive", "action": "compress" });
        }

        items.push({ "separator": true });
        // «Sfoglia con Anteprima»: la cartella selezionata, o quella che si
        // sta guardando. È la voce che risponde a «fammi vedere che immagini
        // ci sono qui» senza aprirle una per una — Anteprima ne fa un provino
        // a contatto, e ci si cammina dentro con le frecce.
        items.push({ "label": it ? "Sfoglia con Anteprima" : "Browse with Preview",
                     "icon": "image", "action": "anteprima" });
        items.push({ "label": it ? "Apri terminale qui" : "Open terminal here",
                     "icon": "terminal", "action": "terminal", "shortcut": "F4" });
        if (manager.tabs.count < manager.maxTabs)
            items.push({ "label": it ? "Apri in una nuova scheda" : "Open in a new tab",
                         "icon": "split", "action": "openTab", "shortcut": "Ctrl+T" });

        // «Fissa nella colonna» solo su una cartella: fissare un file
        // vorrebbe dire mettere in un elenco di POSTI qualcosa che non è un
        // posto, e cliccarlo non saprebbe dove portare.
        var one = manager.selectedDirectory();
        if (one !== "")
            items.push({ "label": Files.isPinned(one)
                                  ? (it ? "Togli dalla colonna" : "Unpin from sidebar")
                                  : (it ? "Fissa nella colonna" : "Pin to sidebar"),
                         "icon": "pin", "action": "pin" });
        // ── Dentro il cestino i comandi sono altri ───────────────────────
        //
        // «Sposta nel cestino» su roba che è già nel cestino non vuol dire
        // niente, e lasciarcelo fa credere che serva a cancellare davvero.
        // Al suo posto le due cose che si vengono a fare qui: rimettere a
        // posto, e buttare via per sempre.
        if (Files.inTrash(manager.current ? manager.current.path : "")) {
            items.push({ "separator": true });
            if (n > 0)
                items.push({ "label": n > 1
                                      ? (it ? "Rimetti a posto " + n + " elementi"
                                            : "Restore " + n + " items")
                                      : (it ? "Rimetti a posto" : "Restore"),
                             "icon": "back", "action": "restore" });
            items.push({ "label": it ? "Svuota il cestino" : "Empty the bin",
                         "icon": "trash", "action": "emptyTrash",
                         "danger": true });
        } else if (puoi && n > 0) {
            items.push({ "separator": true });
            items.push({ "label": n > 1
                                  ? (it ? "Sposta " + n + " elementi nel cestino"
                                        : "Move " + n + " items to the bin")
                                  : (it ? "Sposta nel cestino" : "Move to the bin"),
                         "icon": "trash", "action": "trash", "shortcut": "Canc",
                         "danger": true });
            // Sotto al cestino, e non al suo posto: chi vuole l'una trova
            // l'altra a un millimetro di distanza, e chi non la cerca non ci
            // finisce sopra per sbaglio.
            items.push({ "label": it ? "Elimina definitivamente"
                                     : "Delete permanently",
                         "icon": "close", "action": "deleteForever",
                         "shortcut": "Maiusc+Canc", "danger": true });
        }

        // «Condividi…» sta fuori dalla sezione del cestino apposta: quel
        // che è già cestinato non si manda a nessuno, va prima rimesso a
        // posto. Non dipende da `puoi`: mandare fuori un file non scrive
        // niente in QUESTA cartella.
        if (n > 0 && !Files.inTrash(manager.current ? manager.current.path : "")) {
            items.push({ "label": it ? "Condividi…" : "Share…",
                         "icon": "split", "action": "share" });
        }

        // ── «Trasmetti a…», e solo su UN'IMMAGINE ────────────────────────
        //
        // Una trasmissione comincia da un file, non da una levetta: un
        // televisore non riceve lo schermo, riceve un indirizzo e si va a
        // prendere una cosa. Questa è la voce da cui si comincia; la
        // piastrella del pannello di controllo serve a vedere che sta andando
        // e a fermarla.
        //
        // Una sola, e un'immagine: il lettore di serie di un Chromecast
        // (`CC1AD845`) mostra una fotografia per volta. Offrirlo su una
        // selezione di venti file sarebbe una promessa che il televisore non
        // mantiene.
        //
        // I televisori si chiedono quando il menù si APRE e non a ogni giro di
        // ridisegno: la scoperta costa due secondi di rete, e farla mentre si
        // scorre una cartella sarebbe la stessa spesa silenziosa che il
        // gestore attività si è già dato la regola di non fare.
        //
        // Una voce per televisore e non un sottomenù «Trasmetti a…»: questo
        // menù i sottomenù non li sa fare, e in una casa i televisori sono
        // due o tre. Scriverne il nome per esteso — «Trasmetti a Cucina» — è
        // anche un clic in meno.
        if (n === 1 && manager.schermiTrovati.length > 0
                && manager.eTrasmettibile(manager.operands()[0])
                && !Files.inTrash(manager.current ? manager.current.path : "")) {
            for (var t = 0; t < manager.schermiTrovati.length; t++) {
                var tv = manager.schermiTrovati[t];
                items.push({ "label": (it ? "Trasmetti a " : "Cast to ")
                                      + String(tv.nome),
                             "icon": "screen",
                             "action": "trasmetti:" + String(tv.id) });
            }
        }
        if (n > 0) {
            items.push({ "label": it ? "Copia il percorso" : "Copy the path",
                         "icon": "clipboard", "action": "copyPath",
                         "shortcut": "Ctrl+Maiusc+C" });
        }

        // «Proprietà» in fondo, come su qualunque altro sistema: è il posto
        // dove la mano va da sola, e cambiarlo non farebbe guadagnare niente
        // a nessuno.
        if (n > 0) {
            items.push({ "separator": true });
            items.push({ "label": it ? "Proprietà" : "Properties",
                         "icon": "sliders", "action": "properties",
                         "shortcut": "Alt+Invio" });
        }

        // ── La modalità amministratore ───────────────────────────────────
        //
        // Compare SOLO dove serve: in una cartella dove non si scrive. Nelle
        // tue cartelle non ha senso e sarebbe soltanto un modo di accenderla
        // per sbaglio e ritrovarsi file di root in casa.
        //
        // E compare in fondo, staccata: non è un'operazione fra le altre, è
        // un cambio di stato della finestra.
        if (manager.radiceCE && (!puoi || manager.amministratore)) {
            items.push({ "separator": true });
            items.push(manager.amministratore
                ? { "label": it ? "Esci dalla modalità amministratore"
                                : "Leave administrator mode",
                    "icon": "check", "action": "radiceSpegni" }
                : { "label": it ? "Modalità amministratore"
                                : "Administrator mode",
                    "icon": "lock", "action": "radiceAccendi" });
        }
        return manager.senzaSeparatoriInutili(items);
    }

    /// Toglie i separatori che non separano più niente.
    ///
    /// Serve perché le voci di sopra si accendono e si spengono a seconda di
    /// cosa è selezionato, mentre i separatori sono scritti in mezzo a mano.
    /// Togliendo cinque voci dal menu del vuoto restavano due righe di
    /// separazione appiccicate e una in cima — il genere di cosa che non rompe
    /// niente e si vede subito.
    ///
    /// Tre regole, che sono poi la definizione di «separare»: niente in cima,
    /// niente in fondo, mai due di fila.
    function senzaSeparatoriInutili(items) {
        var fuori = [];
        for (var i = 0; i < items.length; i++) {
            var v = items[i];
            if (v && v.separator === true) {
                if (fuori.length === 0)
                    continue;
                var ultimo = fuori[fuori.length - 1];
                if (ultimo && ultimo.separator === true)
                    continue;
            }
            fuori.push(v);
        }
        while (fuori.length > 0 && fuori[fuori.length - 1].separator === true)
            fuori.pop();
        return fuori;
    }

    /// L'archivio selezionato, se ce n'è esattamente uno. Vuoto altrimenti.
    ///
    /// Se sia un archivio lo ha già deciso il demone (`archive` nella voce di
    /// elenco): l'elenco delle estensioni che si sanno aprire sta in un posto
    /// solo, altrimenti prima o poi il menu offre di estrarre qualcosa che il
    /// demone non sa aprire.
    function selectedArchive() {
        var p = manager.current;
        if (!p || p.selection.length !== 1)
            return "";
        for (var i = 0; i < p.entries.length; i++) {
            var e = p.entries[i];
            if (e.path === p.selection[0])
                return e.archive === true ? e.path : "";
        }
        return "";
    }

    /// La cartella selezionata, se ce n'è esattamente una. Vuoto altrimenti.
    function selectedDirectory() {
        var p = manager.current;
        if (!p || p.selection.length !== 1)
            return "";
        for (var i = 0; i < p.entries.length; i++) {
            var e = p.entries[i];
            if (e.path === p.selection[0])
                return e.isDir ? e.path : "";
        }
        return "";
    }

    /// Apre in una scheda nuova la cartella su cui si è cliccato — o quella
    /// che si sta guardando, se il clic non era su una cartella.
    function openInNewTab() {
        manager.addTab(manager.terminalDirectory());
    }

    /// Il disco su cui si è aperto il menu del tasto destro.
    property var discoScelto: null

    // ── Trascinare e lasciare ────────────────────────────────────────────
    //
    // Giacomo, 12 agosto 2026: «voglio poter trascinare qualsiasi cosa come in
    // KDE, e lasciando mi chiede se copiare o spostare».
    //
    // Si CHIEDE, e non si indovina. Il gesto è lo stesso per due esiti molto
    // diversi: dopo una copia i file sono ancora dove erano, dopo uno
    // spostamento no — e se la scelta la facciamo noi, chi ha sbagliato gesto
    // se ne accorge cercando i file dove non sono più.
    property var _dndSorgenti: []
    property string _dndDestinazione: ""

    /// Per le prove: il menù «Copia in / Sposta in» aperto da un rilascio.
    /// Senza azione dice che cosa offre (e dove porterebbe); con «copia» o
    /// «sposta» sceglie come farebbe il clic.
    function menuRilascio(azione) {
        if (manager._dndSorgenti.length === 0)
            return "nessun rilascio in attesa";
        if (azione === "") {
            var voci = [];
            for (var i = 0; i < dropMenu.items.length; i++)
                if (dropMenu.items[i].label)
                    voci.push(dropMenu.items[i].label);
            return voci.join(" | ") + " → " + manager._dndDestinazione;
        }
        dropMenu.close();
        dropMenu.triggered(azione);
        return "ok";
    }

    function chiediCopiaOSposta(sorgenti, destinazione) {
        if (!sorgenti || sorgenti.length === 0 || destinazione === "")
            return;
        // Lasciare una cosa dov'era già: nessuna delle due risposte avrebbe
        // senso, e la domanda sarebbe solo un ostacolo.
        var utili = [];
        for (var i = 0; i < sorgenti.length; i++) {
            var s = sorgenti[i];
            if (s === destinazione)
                continue;
            if (Files.dirName(s) === destinazione)
                continue;
            utili.push(s);
        }
        if (utili.length === 0)
            return;
        manager._dndSorgenti = utili;
        manager._dndDestinazione = destinazione;

        var it = Core.Strings.lang === "it";
        var dove = Files.baseName(destinazione);
        // La destinazione sta DENTRO le due voci, non su una riga per conto
        // suo: una riga che si può cliccare e non fa niente è una riga che
        // qualcuno cliccherà. Cosa si sta trascinando non serve scriverlo —
        // lo si ha ancora in mano.
        dropMenu.openAtCursor([
            { "label": (it ? "Copia in " : "Copy into ") + dove,
              "icon": "copy", "action": "copia" },
            { "label": (it ? "Sposta in " : "Move into ") + dove,
              "icon": "cut", "action": "sposta" },
            { "separator": true },
            { "label": it ? "Annulla" : "Cancel", "icon": "close", "action": "niente" }
        ]);
    }

    /// Quello che sta per partire, in attesa della risposta sui conflitti.
    property var _inAttesa: null

    /// L'unica porta per copiare e spostare. Prima si chiede al demone se in
    /// destinazione ci sono già dei nomi uguali: la domanda va fatta ADESSO,
    /// perché a metà copia, con la barra che corre, è una domanda a cui si
    /// risponde male.
    function trasferisci(sorgenti, destinazione, sposta) {
        if (!sorgenti || sorgenti.length === 0 || destinazione === "")
            return;
        manager._inAttesa = { "sorgenti": sorgenti, "dove": destinazione,
                              "sposta": sposta === true };
        Core.Ipc.fsConflitti(sorgenti, destinazione);
    }

    Connections {
        target: Core.Ipc
        function onConflittiRicevuti(nomi) {
            var a = manager._inAttesa;
            if (!a)
                return;
            if (!nomi || nomi.length === 0) {
                manager._inAttesa = null;
                Core.Ipc.fsTransfer(a.sorgenti, a.dove, a.sposta, "entrambi");
                return;
            }
            var it = Core.Strings.lang === "it";
            var quali = nomi.length === 1
                        ? nomi[0]
                        : nomi.length + (it ? " nomi" : " names");
            conflittoMenu.openAtCursor([
                { "label": (it ? "Esiste già: " : "Already there: ") + quali,
                  "action": "niente" },
                { "separator": true },
                { "label": it ? "Tieni tutti e due" : "Keep both",
                  "icon": "copy", "action": "entrambi" },
                { "label": it ? "Salta quelli che ci sono" : "Skip existing",
                  "icon": "check", "action": "salta" },
                { "label": it ? "Sostituisci" : "Replace",
                  "icon": "trash", "action": "sostituisci", "danger": true },
                { "separator": true },
                { "label": it ? "Annulla" : "Cancel",
                  "icon": "close", "action": "niente" }
            ]);
        }
    }

    ContextMenu {
        id: conflittoMenu

        onTriggered: function (scelta) {
            var a = manager._inAttesa;
            manager._inAttesa = null;
            if (!a || scelta === "niente")
                return;
            Core.Ipc.fsTransfer(a.sorgenti, a.dove, a.sposta, scelta);
        }
    }

    ContextMenu {
        id: dropMenu

        onTriggered: function(azione) {
            if (azione !== "copia" && azione !== "sposta")
                return;
            manager.trasferisci(manager._dndSorgenti, manager._dndDestinazione,
                                azione === "sposta");
            manager._dndSorgenti = [];
            // Dopo un trascinamento non resta niente di acceso. La roba
            // selezionata era il PUNTO DI PARTENZA del gesto: tenerla accesa
            // a gesto finito la fa sembrare ancora in attesa di qualcosa, e
            // il comando successivo — un Canc, un Ctrl+X — la troverebbe lì.
            for (var i = 0; i < manager.panes.length; i++)
                if (manager.panes[i])
                    manager.panes[i].selection = [];
        }
    }

    ContextMenu {
        id: volumeMenu

        onTriggered: function(action) {
            if (!manager.discoScelto)
                return;
            if (action === "eject") {
                Core.Ipc.fsUnmount(manager.discoScelto.device);
            } else if (action === "format") {
                Core.Ipc.fsFormats();
                formatta.open(manager.discoScelto);
            }
        }
    }

    ContextMenu {
        id: paneMenu

        onTriggered: function(action) {
            // ── Le azioni con un argomento dentro il nome ────────────────
            //
            // «trasmetti:<id del televisore>». Il menù consegna una stringa e
            // basta, e mettere l'id nel nome è più onesto che tenerlo in una
            // proprietà che qualcuno cambia fra il clic e la risposta — è già
            // successo con «Apri con», dove il menù descriveva il file
            // precedente.
            if (action.indexOf("trasmetti:") === 0) {
                manager.trasmettiIlSelezionato(action.substring(10));
                return;
            }
            switch (action) {
            case "open":      if (manager.current) manager.current.openCursor(); break;
            case "openWith":  manager.doOpenWith(); break;
            case "esegui":
                if (manager.operands().length === 1)
                    manager.eseguiNelTerminale(manager.operands()[0]);
                break;
            case "eseguibile":
                if (manager.operands().length === 1)
                    manager.rendiEseguibile(manager.operands()[0]);
                break;
            case "openTab":   manager.openInNewTab(); break;
            case "copy":      manager.doCopy(); break;
            case "cut":       manager.doCut(); break;
            case "paste":     manager.doPaste(); break;
            case "copyOther": manager.sendToOther(false); break;
            case "moveOther": manager.sendToOther(true); break;
            case "rename":    manager.doRename(); break;
            case "newFolder": manager.doNewFolder(); break;
            case "radiceAccendi": manager.accendiAmministratore(); break;
            case "radiceSpegni":  manager.spegniAmministratore(); break;
            case "newFile":   manager.doNewFile(); break;
            case "sfondo":    tavolozza.apri(); break;
            case "impostazioni": impostazioni.apri(); break;
            case "sfondoDaFile": manager.sfondoDaFile(); break;
            case "sfondoScrivania": manager.sfondoScrivania(); break;
            case "copyPath":  manager.doCopyPath(); break;
            case "deleteForever": manager.doDeleteForever(); break;
            case "terminal":  manager.openTerminalHere(); break;
            case "anteprima": manager.browseWithViewer(); break;
            case "trash":     manager.doTrash(); break;
            case "compress":  manager.doCompress(); break;
            case "share":     manager.doShare(); break;
            case "extract":   manager.doExtract(); break;
            case "installaIcone": manager.doInstallaIcone(); break;
            case "restore":   manager.doRestore(); break;
            case "emptyTrash": emptyConfirm.open(); break;
            case "properties": manager.doProperties(); break;
            case "pin": {
                var dir = manager.selectedDirectory();
                if (dir !== "")
                    Files.togglePinned(dir);
                break;
            }
            }
        }
    }

    // ── Richiesta di un nome ─────────────────────────────────────────────

    Rectangle {
        id: prompt
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false


        property string mode: ""
        property string caption: ""

        function begin(m, cap, initial) {
            prompt.mode = m;
            prompt.caption = cap;
            prompt.visible = true;
            promptInput.text = initial;
            // La selezione e il fuoco si danno al giro dopo: la scheda è
            // appena comparsa e una selezione data a un campo ancora
            // invisibile si perde — il testo digitato finirebbe ACCANTO al
            // nome vecchio invece che al suo posto.
            Qt.callLater(function () {
                promptInput.selectAll();
                promptInput.forceActiveFocus();
            });
        }

        function accept() {
            var name = promptInput.text.trim();
            prompt.visible = false;
            if (name === "" || name.indexOf("/") !== -1 || !manager.current)
                return;
            if (prompt.mode === "newFile") {
                Core.Ipc.fsTouch(manager.current.path + "/" + name);
                return;
            }
            if (prompt.mode === "newFolder") {
                // In modalità amministratore la stessa cosa passa
                // dall'aiutante: il demone gira come te e in `/etc` non
                // scrive, e il rifiuto arriverebbe dopo aver scritto il nome.
                if (!manager.radice("crea-cartella",
                                    [manager.current.path + "/" + name]))
                    Core.Ipc.fsMakeDirectory(manager.current.path + "/" + name);
            } else if (prompt.mode === "rename") {
                var ops = manager.operands();
                if (ops.length === 1) {
                    var nuovo = Files.parentPath(ops[0]) + "/" + name;
                    if (!manager.radice("rinomina", [String(ops[0]), nuovo]))
                        Core.Ipc.fsRename(ops[0], nuovo);
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: prompt.visible = false
        }


        // ── Costruita all'avvio, e va bene così ──────────────────────────
        //
        // Qui c'era scritto «costruita alla prima apertura», e non era vero: la
        // scheda si costruiva a ogni avvio come tutto il resto. Il commento
        // descriveva un'intenzione — con tanto di misura del 10 agosto 2026 —
        // che il codice non eseguiva, perché il Loader che la eseguiva era
        // stato tolto (il perché sta dentro `prompt`: le schede non
        // comparivano).
        //
        // **Rimesso e rimisurato il 16 agosto 2026, e la misura dice di no.**
        // Tempo fino a «Configuration Loaded», minimo su cinque giri:
        //
        //     schede costruite all'avvio     413 ms
        //     schede pigre (Loader)          423 ms
        //
        // Cioè niente, dentro il rumore. Il conto delle righe ingannava: questi
        // sette riquadri sono 1414 righe su 3438, ma stanno dentro un genitore
        // `visible: false`, e di un albero invisibile Qt non impagina niente,
        // non misura nessun testo, non costruisce nessun nodo da disegnare.
        // Resta la creazione degli oggetti e dei legami, che costa poco.
        //
        // Dove vanno davvero i millisecondi, misurato allo stesso modo:
        //
        //     Quickshell a vuoto              66 ms
        //     + `core` (Ipc e compagni)      ~90 ms
        //     + UN riquadro (`Pane.qml`)    ~100 ms
        //     + il resto del gestore file   ~145 ms
        //
        // Non c'è un colpevole: è distribuito. E dalla fine del QML alla
        // finestra a schermo passano altri 200 ms buoni, che sono il giro di
        // domande al demone e il primo elenco — lì, non qui, sta la metà più
        // grossa.
        //
        // Chi legge questo commento e pensa «basta un Loader»: è già stato
        // provato due volte. La seconda con i numeri.
        // ── La scheda ────────────────────────────────────────────────
        //
        // DENTRO il riquadro e non dentro un Loader.
        //
        // Il Loader la costruiva al primo uso per risparmiare un po' di
        // avvio, ma le schede caricate a metà non comparivano mai:
        // l'ottimizzazione costava un dialogo cieco. Il difetto era il
        // Loader senza misure proprie — una scheda `centerIn: parent`
        // dentro un padre grande zero si centra nel nulla — e si
        // aggiusterebbe in una riga (`anchors.fill: parent` sul Loader).
        //
        // Non si fa lo stesso, e stavolta con un numero invece che con
        // un'impressione: rimesso per bene il 16 agosto 2026, il tempo di
        // caricamento non si muove (413 ms contro 423, minimo su cinque
        // giri). Vedi il conto per esteso qui sopra.
        Rectangle {
            id: promptCard
            anchors.centerIn: parent
            width: 360
            height: 148
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea {
                anchors.fill: parent

            }

            Text {
                id: promptCaption
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                text: prompt.caption
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Rectangle {
                anchors.top: promptCaption.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                height: 36
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.45)

                TextInput {
                    id: promptInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.Colors.text
                    selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
                    selectedTextColor: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD

                    onAccepted: prompt.accept()
                    Keys.onEscapePressed: prompt.visible = false
                }
            }

            // ── Annulla e Conferma ──────────────────────────────────────
            //
            // Un dialogo senza pulsanti è una domanda a cui si può
            // rispondere solo a tastiera: chi usa il mouse non ha niente
            // da premere. Invio e Esc restano, e fanno la stessa cosa.
            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "annulla", "principale": false },
                        { "id": "conferma", "principale": true }
                    ]

                    delegate: Rectangle {
                        id: promptBtn
                        required property var modelData

                        readonly property color tinta: modelData.principale
                            ? Theme.Colors.accent : Theme.Colors.textMuted

                        width: promptLabel.implicitWidth + Theme.Effects.space5
                        height: 32
                        radius: Theme.Effects.radiusXS
                        color: modelData.principale
                               ? (btnMouse.containsMouse ? Qt.lighter(tinta, 1.1) : tinta)
                               : (btnMouse.containsMouse ? Theme.Colors.hover
                                                         : Theme.Colors.raised)

                        Text {
                            id: promptLabel
                            anchors.centerIn: parent
                            text: {
                                var it = Core.Strings.lang === "it";
                                if (promptBtn.modelData.id === "annulla")
                                    return it ? "Annulla" : "Cancel";
                                if (prompt.mode === "rename")
                                    return it ? "Rinomina" : "Rename";
                                if (prompt.mode === "newFolder")
                                    return it ? "Crea" : "Create";
                                return it ? "Crea documento" : "Create document";
                            }
                            color: modelData.principale ? Theme.Colors.textOnAccent
                                                         : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: btnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (promptBtn.modelData.id === "annulla")
                                    prompt.visible = false;
                                else
                                    prompt.accept();
                            }
                        }
                    }
                }
            }
        }

    }

    // ── Dove finisce la roba ─────────────────────────────────────────────
    //
    // Compare solo con tre o quattro schede aperte. Mostra il PERCORSO intero
    // di ogni destinazione e non solo il nome della cartella: di «Documenti»
    // ce n'è uno per ogni disco montato, e leggere il nome giusto sopra il
    // disco sbagliato è esattamente il modo in cui si perde un file.
    //
    // I numeri 1-4 sono scritti accanto a ogni riga e funzionano da tastiera:
    // chi sposta file a mucchi lo fa venti volte di fila, e venti volte di
    // fila si preme un tasto invece di mirare.

    Rectangle {
        id: destination
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false
        focus: destination.visible

        property var paths: []
        property bool moving: false
        property var choices: []

        /// Restituisce `false` se non c'era niente da chiedere, così chi
        /// chiama sa che deve arrangiarsi.
        function begin(ops, move) {
            var choices = manager.destinationChoices();
            // Nessuna destinazione valida: le altre schede sono tutte sulla
            // stessa cartella o dentro quello che si sta copiando. Aprire una
            // finestra vuota con scritto «dove?» sarebbe una presa in giro.
            if (choices.length === 0)
                return false;
            // Una sola: la domanda ha una risposta sola, e farla è un
            // fastidio. Si fa e basta — è la stessa regola per cui con due
            // schede non si chiede niente.
            if (choices.length === 1) {
                manager.trasferisci(ops, choices[0].path, move === true);
                return true;
            }
            destination.paths = ops.slice();
            destination.moving = move === true;
            destination.choices = choices;
            destination.visible = true;
            destination.forceActiveFocus();
            return true;
        }

        function pick(paneIndex) {
            destination.visible = false;
            var p = manager.panes[paneIndex];
            if (!p || destination.paths.length === 0)
                return;
            manager.trasferisci(destination.paths, p.path, destination.moving);
        }

        // ── Copiare in PIÙ cartelle in un colpo solo ─────────────────────
        //
        // È la cosa che Giacomo aveva chiesto e che il gestore file non
        // sapeva fare: «copiare un file da una scheda a DUE O PIÙ
        // contemporaneamente — due chiavette USB, lo stesso file su
        // entrambe in un colpo». Farlo a mano vuol dire copiare, andare,
        // incollare, tornare, andare di là, incollare: sei gesti per una
        // cosa sola, e con file grossi vuol dire anche aspettare due volte
        // guardando.
        //
        // Solo per la COPIA. «Sposta in due posti» non vuol dire niente:
        // una cosa spostata sta in un posto, e le due caselle non
        // compaiono nemmeno quando si sta spostando.
        //
        // Il clic sulla riga resta quello di prima — copia lì, subito —
        // perché è il caso di nove volte su dieci e non deve costare un
        // gesto in più. Le caselle sono per la decima.
        property var scelte: []

        function segna(indice) {
            var s = destination.scelte.slice();
            var dove = s.indexOf(indice);
            if (dove === -1) s.push(indice);
            else s.splice(dove, 1);
            destination.scelte = s;
        }

        function segnata(indice) {
            return destination.scelte.indexOf(indice) !== -1;
        }

        /// Manda la copia verso tutte le cartelle segnate.
        ///
        /// Una chiamata per destinazione, non una sola con più mete: il
        /// demone copia verso UNA cartella per volta, e le sue prove — i
        /// nomi che si scontrano, lo spazio che finisce — sono scritte per
        /// quella forma. Aggiungere un secondo argomento vorrebbe dire
        /// riscriverle tutte per guadagnare una riga.
        function copiaInTutte() {
            var quali = destination.scelte.slice();
            destination.visible = false;
            for (var i = 0; i < quali.length; i++) {
                var p = manager.panes[quali[i]];
                if (p && destination.paths.length > 0)
                    manager.trasferisci(destination.paths, p.path, false);
            }
        }

        // Le caselle si azzerano a ogni apertura: le scelte della volta
        // scorsa sono un'altra domanda, e ritrovarle segnate è il modo di
        // copiare in una cartella a cui non si stava pensando.
        //
        // E all'apertura si costruisce la scheda, che nasce spenta. In QML un
        // segnale ha UN gestore: scritti due `onVisibleChanged` il file non si
        // carica affatto — «Property value set multiple times» — e il gestore
        // file non si apre più.
        onVisibleChanged: {
            if (!destination.visible)
                destination.scelte = [];
        }

        Keys.onEscapePressed: destination.visible = false
        Keys.onPressed: function(e) {
            // I tasti 1-4 scelgono la scheda per numero, non la riga per
            // posizione: il numero è quello scritto sulla scheda in alto, e
            // deve voler dire la stessa cosa nei due posti.
            if (e.key >= Qt.Key_1 && e.key <= Qt.Key_4) {
                var wanted = e.key - Qt.Key_1;
                for (var i = 0; i < destination.choices.length; i++)
                    if (destination.choices[i].index === wanted) {
                        destination.pick(wanted);
                        e.accepted = true;
                        return;
                    }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: destination.visible = false
        }


        // Costruita all'avvio, e va bene così: renderla pigra è stato provato
        // due volte e misurato una, e non cambia niente. Il conto per esteso
        // sta sul primo di questi riquadri, sopra `prompt`.
        Rectangle {
            anchors.centerIn: parent
            width: 460
            height: destColumn.implicitHeight + Theme.Effects.space4 * 2
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Column {
                id: destColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: {
                        var it = Core.Strings.lang === "it";
                        var n = destination.paths.length;
                        var what = n === 1
                                   ? "«" + Files.baseName(destination.paths[0]) + "»"
                                   : n + (it ? " elementi" : " items");
                        if (destination.moving)
                            return it ? "Spostare " + what + " dove?"
                                      : "Move " + what + " where?";
                        return it ? "Copiare " + what + " dove?"
                                  : "Copy " + what + " where?";
                    }
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD
                }

                Repeater {
                    model: destination.choices

                    delegate: Rectangle {
                        id: destRow
                        required property var modelData

                        width: destColumn.width
                        height: 46
                        radius: Theme.Effects.radiusXS
                        color: destMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.16)
                                                       : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Rectangle {
                            id: destNumber
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22
                            radius: Theme.Effects.radiusXS
                            color: Qt.alpha(Theme.Colors.accent, 0.18)

                            Text {
                                anchors.centerIn: parent
                                text: destRow.modelData.index + 1
                                color: Theme.Colors.accent
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }

                        Text {
                            anchors.left: destNumber.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            elide: Text.ElideRight
                            text: Files.baseName(destRow.modelData.path)
                                  || destRow.modelData.path
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        Text {
                            anchors.left: destNumber.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 5
                            elide: Text.ElideMiddle
                            text: destRow.modelData.path
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        // Il clic sulla riga copia lì e subito: è il caso di
                        // nove volte su dieci e non deve costare un gesto in
                        // più. La casella è per la decima — «anche di là».
                        MouseArea {
                            id: destMouse
                            anchors.fill: parent
                            anchors.rightMargin: casella.visible ? casella.width
                                                 + Theme.Effects.space3 * 2 : 0
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: destination.pick(destRow.modelData.index)
                        }

                        Rectangle {
                            id: casella
                            // Spostare in due posti non vuol dire niente: una
                            // cosa spostata sta in un posto solo.
                            visible: !destination.moving
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22
                            radius: Theme.Effects.radiusXS
                            readonly property bool segnata:
                                destination.segnata(destRow.modelData.index)
                            color: segnata ? Theme.Colors.accent : "transparent"
                            border.width: 1
                            border.color: segnata ? Theme.Colors.accent
                                                  : Theme.Colors.edge
                            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                            Text {
                                anchors.centerIn: parent
                                visible: casella.segnata
                                text: "✓"
                                color: Theme.Colors.textOnAccent
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightSemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: destination.segna(destRow.modelData.index)
                            }
                        }
                    }
                }

                // ── «Copia in tutte e due» ───────────────────────────────
                //
                // Compare solo quando c'è qualcosa di segnato: un pulsante
                // sempre lì, e sempre spento, insegna a non guardarlo.
                Rectangle {
                    visible: !destination.moving && destination.scelte.length > 0
                    width: parent.width
                    height: visible ? 40 : 0
                    radius: Theme.Effects.radiusXS
                    color: tuttiMouse.containsMouse
                           ? Qt.lighter(Theme.Colors.accent, 1.12)
                           : Theme.Colors.accent
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var it = Core.Strings.lang === "it";
                            var n = destination.scelte.length;
                            if (n === 1)
                                return it ? "Copia nella cartella segnata"
                                          : "Copy to the ticked folder";
                            return it ? "Copia in tutte e " + n + " le cartelle"
                                      : "Copy to all " + n + " folders";
                        }
                        color: Theme.Colors.textOnAccent
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightSemiBold
                    }

                    MouseArea {
                        id: tuttiMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: destination.copiaInTutte()
                    }
                }

                Text {
                    width: parent.width
                    text: {
                        var it = Core.Strings.lang === "it";
                        if (destination.moving)
                            return it ? "Esc per lasciar perdere."
                                      : "Esc to leave it.";
                        return it
                            ? "Segna più cartelle per copiarci dentro tutte insieme. Esc per lasciar perdere."
                            : "Tick more than one folder to copy into all of them. Esc to leave it.";
                    }
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }

    }

    // ── Proprietà ────────────────────────────────────────────────────────

    // ── Le proprietà si costruiscono quando si aprono ────────────────────
    //
    // `FileProperties` sono 584 righe di QML per una finestrella che si apre
    // con Alt+Invio o dal tasto destro: quasi mai. Costruita insieme alla
    // finestra, quelle 584 righe si leggono, si compilano e si eseguono PRIMA
    // che compaia qualunque cosa a schermo — e il gestore file ci metteva 600
    // millisecondi a comparire.
    //
    // Un `Loader` spento non costa niente finché non lo si accende. Il prezzo
    // è che la prima apertura è un filo più lenta della seconda; il guadagno
    // è che ogni avvio è più svelto, e gli avvii sono molti più delle
    // aperture di quella finestrella.
    // Il Loader del commento qui sopra non c'era: `FileProperties` si
    // costruiva dritta, e le sue 584 righe si leggevano e si compilavano a
    // ogni avvio. Adesso c'è davvero.
    //
    // E stavolta funziona, perché si carica un FILE a parte (`source:`) e non
    // un `Component` scritto lì dentro. È la differenza che conta: un
    // `Component` nello stesso file rimanda la COSTRUZIONE degli oggetti, che
    // costa poco; un file a parte rimanda anche la LETTURA e la
    // COMPILAZIONE, che è dove se ne va il tempo. Misurato il 16 agosto 2026:
    // un `Pane` costa 120 ms la prima volta e 10 ms la seconda — cioè 110 di
    // quei 120 sono compilazione, pagata a ogni avvio perché Quickshell 0.3
    // non tiene una cache su disco.
    //
    // Il Loader riempie la finestra: `FileProperties` è `anchors.fill:
    // parent`, e un Loader senza misure la lascerebbe grande zero.
    Loader {
        id: propsCard
        anchors.fill: parent
        active: false
        source: "FileProperties.qml"
    }

    /// Il ponte: chi chiama non deve sapere chi disegna la scheda — e adesso
    /// nemmeno che potrebbe non esistere ancora.
    QtObject {
        id: fileProps
        readonly property bool visible: propsCard.item !== null
                                        && propsCard.item.visible
        function open(percorso) {
            propsCard.active = true;
            propsCard.item.open(percorso);
        }
    }

    /// Apre le proprietà di ciò che è selezionato. Con più file selezionati si
    /// apre quello su cui è il cursore: una finestra «Proprietà» che parla di
    /// dieci file insieme non può mostrare né i permessi né la dimensione,
    /// cioè le due cose per cui la si apre.
    function doProperties() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        fileProps.open(ops[0]);
    }

    /// «Apri con…»: la finestra delle proprietà col suo elenco «Si apre
    /// con». Vale per UN file — una cartella non si «apre con» niente — e la
    /// scelta fatta lì vale per quella apertura sola, non per sempre: il
    /// «sempre questo» resta una decisione esplicita, con il suo pulsante.
    function doOpenWith() {
        var ops = manager.operands();
        if (ops.length !== 1 || manager.selectedDirectory() !== "")
            return;
        // Le Proprietà erano il ripiego: adesso c'è una finestra che fa
        // proprio questo, e che sa anche eseguire.
        apriCon.apri(ops[0], manager.eseguibileDi(ops[0]));
    }

    /// «Condividi…»: manda quel che è selezionato fuori da questo computer.
    /// Il demone decide da solo se una cartella ci può stare — su Bluetooth e
    /// posta non ci sta mai — e lo dice nella finestrella, invece che qui.
    function doShare() {
        var ops = manager.operands();
        if (ops.length === 0)
            return;
        condividi.apri(ops);
    }

    // ── La tavolozza degli sfondi ────────────────────────────────────────
    //
    // Tre righe, tre modi di dire la stessa cosa con forza diversa:
    //
    //   parete   una tinta piena. Si riconosce dall'altra parte della stanza.
    //   vetro    la stessa tinta come luce: sfuma e non pesa.
    //   motivo   icone sparse. È quello che le cartelle note prendono da sole.
    //
    // Non c'è un selettore di colore completo, ed è voluto: davanti a una
    // ruota infinita si sceglie male e si perde tempo; davanti a dieci tinte
    // già scelte si sceglie in un secondo. Chi vuole qualcosa di preciso mette
    // un'immagine, che è il quarto modo e sta nel menù del tasto destro.
    Rectangle {
        id: tavolozza
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false

        function apri() { tavolozza.visible = true; }

        readonly property var tinte: [
            "#7C93C3", "#6FB3A8", "#8FBF7F", "#D6C06A", "#D9915B",
            "#CE7B7B", "#B87BB0", "#8B7BC7", "#8A9299", "#6E6E6E"
        ]
        readonly property var motivi: [
            ["music", "#8B7BC7"], ["document", "#7C93C3"],
            ["image", "#6FB3A8"], ["video", "#CE7B7B"],
            ["star", "#D6C06A"], ["globe", "#8FBF7F"],
            ["code", "#B87BB0"], ["archive", "#D9915B"],
            ["cpu", "#8A9299"], ["clock", "#6FB3A8"]
        ]

        function scegli(a) {
            manager.mettiSfondo(a);
            tavolozza.visible = false;
        }

        MouseArea {
            anchors.fill: parent
            onClicked: tavolozza.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 452
            height: colonna.implicitHeight + Theme.Effects.space5 * 2
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Column {
                id: colonna
                anchors.centerIn: parent
                width: parent.width - Theme.Effects.space5 * 2
                spacing: Theme.Effects.space3

                Text {
                    text: Core.Strings.lang === "it" ? "Sfondo della cartella"
                                                     : "Folder background"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                }

                Repeater {
                    model: [
                        { "modo": "tinta", "it": "Parete",  "en": "Wall" },
                        { "modo": "vetro", "it": "Vetro",   "en": "Glass" },
                        { "modo": "motivo","it": "Motivo",  "en": "Pattern" }
                    ]

                    delegate: Column {
                        id: riga
                        required property var modelData
                        spacing: Theme.Effects.space1

                        Text {
                            text: Core.Strings.lang === "it" ? riga.modelData.it
                                                             : riga.modelData.en
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        Grid {
                            columns: 10
                            spacing: Theme.Effects.space1

                            Repeater {
                                model: riga.modelData.modo === "motivo"
                                       ? tavolozza.motivi : tavolozza.tinte

                                delegate: Rectangle {
                                    id: cella
                                    required property var modelData
                                    readonly property bool eMotivo:
                                        riga.modelData.modo === "motivo"
                                    readonly property color tinta:
                                        cella.eMotivo ? cella.modelData[1]
                                                      : cella.modelData

                                    width: 36
                                    height: 30
                                    radius: Theme.Effects.radiusXS
                                    clip: true
                                    border.width: cellaMouse.containsMouse ? 2 : 0
                                    border.color: Theme.Colors.text
                                    // Il campione mostra quello che si otterrà:
                                    // pieno per la parete, sfumato per il vetro,
                                    // con l'icona per il motivo. Un campione che
                                    // non somiglia al risultato è una bugia
                                    // grande quanto è comodo il pulsante.
                                    color: riga.modelData.modo === "vetro"
                                           ? "transparent"
                                           : Qt.tint(Theme.Colors.base,
                                                     Qt.alpha(cella.tinta,
                                                              cella.eMotivo ? 0.34 : 0.55))
                                    gradient: riga.modelData.modo === "vetro"
                                              ? sfumatura : null

                                    Gradient {
                                        id: sfumatura
                                        GradientStop { position: 0.0; color: Qt.alpha(cella.tinta, 0.55) }
                                        GradientStop { position: 1.0; color: Qt.alpha(cella.tinta, 0.05) }
                                    }

                                    Ui.Icon {
                                        visible: cella.eMotivo
                                        anchors.centerIn: parent
                                        width: 17; height: 17
                                        name: cella.eMotivo ? cella.modelData[0] : "folder"
                                        // Il nostro tracciato, sempre: qui il colore lo scegliamo noi, e
                                        // un'icona del tema di sistema arriva già colorata e lo ignora.
                                        alwaysDrawn: true
                                        color: Qt.lighter(cella.tinta, 1.5)
                                        opacity: 0.85
                                    }

                                    MouseArea {
                                        id: cellaMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: tavolozza.scegli(
                                            cella.eMotivo
                                            ? { "tipo": "motivo",
                                                "icona": cella.modelData[0],
                                                "valore": cella.modelData[1] }
                                            : { "tipo": riga.modelData.modo,
                                                "valore": cella.tinta })
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    id: niente
                    anchors.right: parent.right
                    // «Nessuno sfondo» toglie ANCHE il motivo automatico: chi
                    // lo preme sta dicendo «voglio questa cartella nuda», e
                    // ridargliela colorata al prossimo giro sarebbe non averlo
                    // ascoltato.
                    text: Core.Strings.lang === "it" ? "Nessuno sfondo"
                                                     : "No background"
                    color: nienteMouse.containsMouse ? Theme.Colors.text
                                                     : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM

                    MouseArea {
                        id: nienteMouse
                        anchors.fill: parent
                        anchors.margins: -Theme.Effects.space2
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tavolozza.scegli({ "tipo": "niente" })
                    }
                }
            }
        }
    }

    // ── Le impostazioni del gestore file ─────────────────────────────────
    //
    // Quattro, e tutte cose che cambiano COME CI SI COMPORTA, non come si
    // vede: vista, ordine e zoom stanno nella finestra dove si vedono, e
    // cambiarli lì è più veloce che cercarli qui.
    //
    // Stanno nel demone e non nella finestra: due finestre del gestore file
    // sono due processi, e un'impostazione che vale in una e non nell'altra è
    // peggio di un'impostazione che non c'è.
    Rectangle {
        id: impostazioni
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false

        function apri() { impostazioni.visible = true; }

        MouseArea {
            anchors.fill: parent
            onClicked: impostazioni.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 448
            height: elenco.implicitHeight + Theme.Effects.space5 * 2
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Column {
                id: elenco
                anchors.centerIn: parent
                width: parent.width - Theme.Effects.space5 * 2
                spacing: Theme.Effects.space2

                Text {
                    text: Core.Strings.lang === "it" ? "Impostazioni"
                                                     : "Settings"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    bottomPadding: Theme.Effects.space1
                }

                Repeater {
                    model: {
                        var it = Core.Strings.lang === "it";
                        return [
                            { "chiave": "files.sfondiAutomatici", "icona": "image",
                              "titolo": it ? "Sfondi automatici" : "Automatic backgrounds",
                              "detta": it ? "Musica, Documenti e le altre cartelle note si riconoscono da lontano"
                                          : "Music, Documents and the other known folders stand out",
                              "serie": true },
                            { "chiave": "files.clicSingolo", "icona": "cursor",
                              "titolo": it ? "Un clic solo per aprire" : "Single click to open",
                              "detta": it ? "Invece di due" : "Instead of two",
                              "serie": false },
                            { "chiave": "files.anteprime", "icona": "image",
                              "titolo": it ? "Anteprime delle immagini" : "Image previews",
                              "detta": it ? "Da spegnere su cartelle enormi di foto su un disco lento"
                                          : "Turn off for huge photo folders on a slow disk",
                              "serie": true },
                            { "chiave": "files.confermaCestino", "icona": "trash",
                              "titolo": it ? "Chiedi prima di cestinare" : "Ask before binning",
                              "detta": it ? "Il cestino è già una rete: la domanda si può togliere"
                                          : "The bin is already a net: the question can go",
                              "serie": true },
                            // Il numero sta scritto nella riga sotto perché è
                            // il solo modo di scegliere davvero: un
                            // interruttore che dice «più veloce» e non dice
                            // «131 MB» non è una scelta, è una spinta.
                            { "chiave": "files.tieniAcceso", "icona": "window",
                              "titolo": it ? "Tienilo pronto" : "Keep it ready",
                              "detta": it ? "Si apre subito invece che in un secondo. Costa 131 MB di memoria, sempre"
                                          : "Opens at once instead of in a second. Costs 131 MB of memory, always",
                              "serie": true }
                        ];
                    }

                    delegate: Ui.ToggleTile {
                        required property var modelData
                        width: elenco.width
                        icon: modelData.icona
                        label: modelData.titolo
                        detail: modelData.detta
                        checked: Core.Ipc.get(modelData.chiave, modelData.serie)
                        onToggled: function (v) {
                            Core.Ipc.setSetting(modelData.chiave, v);
                        }
                    }
                }
            }
        }
    }

    // ── Conferma del cestinamento ────────────────────────────────────────

    Rectangle {
        id: trashConfirm
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false


        property var paths: []
        /// Quando è vero non si parla più di cestino: si cancella e basta.
        /// Stessa finestra perché la forma della domanda è la stessa — quel
        /// che cambia è la risposta, e va detto nel testo e sul pulsante.
        property bool permanente: false

        function open(perDavvero) {
            trashConfirm.permanente = perDavvero === true;
            trashConfirm.visible = true;
        }

        /// La cartella che contiene la roba scelta, se sta fuori da casa.
        ///
        /// Vuota quando è tutto dentro `$HOME`, che è il caso normale: lì
        /// aggiungere una riga a ogni conferma vorrebbe dire insegnare a non
        /// leggerle.
        function fuoriCasa() {
            var casa = Files.home;
            if (casa === "")
                return "";
            for (var i = 0; i < trashConfirm.paths.length; i++) {
                var p = String(trashConfirm.paths[i]);
                if (p.indexOf(casa + "/") === 0 || p === casa)
                    continue;
                var tagli = p.lastIndexOf("/");
                return tagli > 0 ? p.substring(0, tagli) : "/";
            }
            return "";
        }

        MouseArea {
            anchors.fill: parent
            onClicked: trashConfirm.visible = false
        }


        // Costruita all'avvio, e va bene così: renderla pigra è stato provato
        // due volte e misurato una, e non cambia niente. Il conto per esteso
        // sta sul primo di questi riquadri, sopra `prompt`.
        Rectangle {
            id: trashCard
            anchors.centerIn: parent
            width: 400
            // Cresce col testo. Era fissa a 150, e con la riga che dice dove
            // sta la roba — un percorso lungo va a capo due volte — la nota
            // sarebbe finita sotto i pulsanti. Il minimo resta quello di
            // prima, così la finestra normale non cambia di un pixel.
            height: Math.max(150,
                Theme.Effects.space4 + confirmText.implicitHeight
                + Theme.Effects.space2 + confirmNota.implicitHeight
                + Theme.Effects.space4 + 34 + Theme.Effects.space4)
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea {
                anchors.fill: parent

            }

            Text {
                id: confirmText
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                wrapMode: Text.WordWrap
                text: {
                    var it = Core.Strings.lang === "it";
                    var n = trashConfirm.paths.length;
                    var uno = n === 1
                              ? Files.baseName(trashConfirm.paths[0]) : "";
                    if (trashConfirm.permanente) {
                        if (n === 1)
                            return (it ? "Eliminare «" : "Delete “") + uno
                                   + (it ? "» per sempre?" : "” for good?");
                        return it ? "Eliminare " + n + " elementi per sempre?"
                                  : "Delete " + n + " items for good?";
                    }
                    if (n === 1)
                        return (it ? "Spostare «" : "Move “") + uno
                               + (it ? "» nel cestino?" : "” to the bin?");
                    return it ? "Spostare " + n + " elementi nel cestino?"
                              : "Move " + n + " items to the bin?";
                }
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            // Si dice sempre dove vanno a finire: «cestino» e non «elimina»
            // perché è la verità, e sapere che si può tornare indietro cambia
            // quanto si esita davanti a questo bottone.
            Text {
                id: confirmNota
                anchors.top: confirmText.bottom
                anchors.topMargin: Theme.Effects.space2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                wrapMode: Text.WordWrap
                text: {
                    var it = Core.Strings.lang === "it";
                    // ── Dove sta la roba, se non è roba tua ─────────────
                    //
                    // Fuori dalla cartella di casa la domanda è la stessa e la
                    // posta in gioco no: un file su una chiavetta o su un
                    // secondo disco non è un documento che si rifà. Prima la
                    // finestra era identica in tutti i casi — ed è quello che
                    // Giacomo ha visto come «nessuna protezione».
                    var fuori = trashConfirm.fuoriCasa();
                    var dove = fuori !== ""
                        ? (it ? "Sta fuori dalla tua cartella di casa, in "
                              + fuori + ". " : "It is outside your home folder, in "
                              + fuori + ". ")
                        : "";
                    if (trashConfirm.permanente)
                        return dove + (it ? "Non finiscono nel cestino: non si torna indietro."
                                  : "They do not go to the bin: there is no way back.");
                    return dove + (it ? "Restano nel cestino finché non lo svuoti."
                              : "They stay in the bin until you empty it.");
                }
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "cancel", "danger": false },
                        { "id": "trash",  "danger": true }
                    ]

                    delegate: Rectangle {
                        id: confirmBtn
                        required property var modelData

                        readonly property color tone: modelData.danger
                                                      ? Theme.Colors.danger
                                                      : Theme.Colors.textMuted

                        width: confirmLabel.implicitWidth + Theme.Effects.space5
                        height: 32
                        radius: Theme.Effects.radiusXS
                        color: confirmMouse.containsMouse ? Qt.alpha(tone, 0.18)
                                                          : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: confirmLabel
                            anchors.centerIn: parent
                            text: {
                                var it = Core.Strings.lang === "it";
                                if (confirmBtn.modelData.id === "cancel")
                                    return it ? "Annulla" : "Cancel";
                                if (trashConfirm.permanente)
                                    return it ? "Elimina per sempre"
                                              : "Delete for good";
                                return it ? "Sposta nel cestino" : "Move to the bin";
                            }
                            color: confirmBtn.modelData.danger ? Theme.Colors.danger
                                                               : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: confirmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                trashConfirm.visible = false;
                                if (confirmBtn.modelData.id !== "trash")
                                    return;
                                // ── In modalità amministratore ───────────
                                //
                                // Non c'è cestino: il cestino è in casa tua, e
                                // spostarci dentro un file di `/etc` vorrebbe
                                // dire portarlo via dal sistema lasciandolo
                                // credere cancellato. Da root si cancella e
                                // basta — ed è per questo che la domanda di
                                // conferma sopra dice parole diverse.
                                if (manager.operaComeRoot) {
                                    for (var i = 0; i < trashConfirm.paths.length; i++)
                                        manager.radice("elimina",
                                                       [String(trashConfirm.paths[i])]);
                                    return;
                                }
                                if (trashConfirm.permanente)
                                    Core.Ipc.fsDelete(trashConfirm.paths);
                                else
                                    Core.Ipc.fsTrash(trashConfirm.paths);
                            }
                        }
                    }
                }
            }
        }

    }

    // ── Formattare un disco ──────────────────────────────────────────────
    //
    // È l'unica cosa in Minerva che distrugge dati senza rete: una chiavetta
    // formattata non finisce in nessun cestino. Quindi la finestra è fatta
    // per rallentare, non per essere comoda:
    //
    //  · in cima c'è QUALE disco, col nome, il tipo di adesso e la
    //    dimensione — perché l'errore che si fa è formattare quello sbagliato,
    //    non scegliere il filesystem sbagliato;
    //  · il pulsante non dice «OK» ma «Cancella tutto e formatta»;
    //  · i formati che questa macchina non sa creare si vedono, spenti, col
    //    nome del programma che manca. Nasconderli farebbe chiedere «e NTFS
    //    dov'è?» senza nessuna risposta.
    //
    // I muri veri però NON sono qui: stanno nel demone (`formatVolume`), e
    // valgono anche se questa finestra chiedesse una sciocchezza.

    Rectangle {
        id: formatta
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false


        property var disco: null
        property string scelto: "vfat"
        property var formati: []

        function open(d) {
            formatta.disco = d;
            formatta.scelto = "vfat";
            nomeNuovo.text = d && d.name ? d.name : "";
            formatta.visible = true;
        }

        Connections {
            target: Core.Ipc
            function onFormatsReceived(f) { formatta.formati = f || []; }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: formatta.visible = false
        }


        // Costruita all'avvio, e va bene così: renderla pigra è stato provato
        // due volte e misurato una, e non cambia niente. Il conto per esteso
        // sta sul primo di questi riquadri, sopra `prompt`.
        Rectangle {
            anchors.centerIn: parent
            width: 460
            height: corpo.implicitHeight + Theme.Effects.space5 * 2
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Column {
                id: corpo
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.Effects.space5
                spacing: Theme.Effects.space3

                Text {
                    width: parent.width
                    text: Core.Strings.lang === "it" ? "Formatta il disco"
                                                     : "Format the disk"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD
                }

                // Quale disco. È la riga che evita il disastro.
                Rectangle {
                    width: parent.width
                    height: 46
                    radius: Theme.Effects.radiusSM
                    color: Theme.Colors.sunken

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: {
                            if (!formatta.disco)
                                return "";
                            var d = formatta.disco;
                            return d.name + "  ·  " + d.device
                                   + "  ·  " + d.size
                                   + (d.fsType ? "  ·  " + d.fsType : "");
                        }
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Core.Strings.lang === "it"
                          ? "Tutto quello che c'è su questo disco viene cancellato. Non finisce nel cestino."
                          : "Everything on this disk is erased. It does not go to the bin."
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // Il nome nuovo.
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: Theme.Effects.radiusSM
                    color: Theme.Colors.sunken
                    border.width: 1
                    border.color: nomeNuovo.activeFocus ? Theme.Colors.edgeAccent
                                                        : Theme.Colors.edge

                    TextInput {
                        id: nomeNuovo
                        anchors.fill: parent
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.rightMargin: Theme.Effects.space3
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                        selectByMouse: true
                        selectionColor: Theme.Colors.selected
                    }

                    Text {
                        anchors.fill: nomeNuovo
                        verticalAlignment: Text.AlignVCenter
                        visible: nomeNuovo.text === ""
                        text: Core.Strings.lang === "it" ? "Nome del disco"
                                                         : "Disk name"
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }

                // I formati.
                Column {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: formatta.formati

                        delegate: Rectangle {
                            id: scelta
                            required property var modelData

                            readonly property bool sceglibile: scelta.modelData.possibile
                            readonly property bool attivo:
                                formatta.scelto === scelta.modelData.id

                            width: parent.width
                            height: 44
                            radius: Theme.Effects.radiusSM
                            color: !scelta.sceglibile ? "transparent"
                                 : scelta.attivo ? Qt.alpha(Theme.Colors.accent, 0.18)
                                 : sceltaMouse.containsMouse ? Theme.Colors.hover
                                 : Theme.Colors.raised
                            border.width: 1
                            border.color: scelta.attivo ? Theme.Colors.edgeAccent
                                                        : "transparent"
                            opacity: scelta.sceglibile ? 1 : 0.45

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: scelta.modelData.nome
                                    color: Theme.Colors.text
                                    font.family: Theme.Typography.fontDisplay
                                    font.weight: Theme.Typography.weightRegular
                                    font.pixelSize: Theme.Typography.sizeSM
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    // Se non si può, si dice cosa manca: è
                                    // un'informazione che si può usare
                                    // (installare quel pacchetto), non un
                                    // «non disponibile» che chiude il discorso.
                                    text: scelta.sceglibile
                                          ? scelta.modelData.nota
                                          : (Core.Strings.lang === "it"
                                             ? "Manca «" + scelta.modelData.manca + "»"
                                             : "Missing “" + scelta.modelData.manca + "”")
                                    color: Theme.Colors.textFaint
                                    font.family: Theme.Typography.fontDisplay
                                    font.weight: Theme.Typography.weightRegular
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                            }

                            MouseArea {
                                id: sceltaMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: scelta.sceglibile
                                cursorShape: Qt.PointingHandCursor
                                onClicked: formatta.scelto = scelta.modelData.id
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: [
                            { "id": "cancel", "danger": false },
                            { "id": "go",     "danger": true }
                        ]

                        delegate: Rectangle {
                            id: fBtn
                            required property var modelData

                            readonly property color tone: modelData.danger
                                                          ? Theme.Colors.danger
                                                          : Theme.Colors.textMuted

                            width: fLabel.implicitWidth + Theme.Effects.space5
                            height: 34
                            radius: Theme.Effects.radiusXS
                            color: fMouse.containsMouse ? Qt.alpha(fBtn.tone, 0.18)
                                                        : Theme.Colors.raised
                            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                            Text {
                                id: fLabel
                                anchors.centerIn: parent
                                text: {
                                    var it = Core.Strings.lang === "it";
                                    if (fBtn.modelData.id === "cancel")
                                        return it ? "Annulla" : "Cancel";
                                    return it ? "Cancella tutto e formatta"
                                              : "Erase everything and format";
                                }
                                color: fBtn.tone
                                font.family: Theme.Typography.fontDisplay
                                font.weight: Theme.Typography.weightRegular
                                font.pixelSize: Theme.Typography.sizeSM
                            }

                            MouseArea {
                                id: fMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    formatta.visible = false;
                                    if (fBtn.modelData.id !== "go" || !formatta.disco)
                                        return;
                                    problem.attesa = Core.Strings.lang === "it"
                                                     ? "Formatto…" : "Formatting…";
                                    Core.Ipc.fsFormat(formatta.disco.device,
                                                      formatta.scelto,
                                                      nomeNuovo.text);
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    // ── Svuotare il cestino ──────────────────────────────────────────────
    //
    // È l'unica cosa in tutto il gestore file che cancella per davvero: ogni
    // altra strada passa dal cestino. Per questo ha una conferma tutta sua,
    // e per questo il testo dice «per sempre» invece di «sei sicuro?» — la
    // domanda giusta non è se sei sicuro, è se sai cosa succede.

    Rectangle {
        id: emptyConfirm
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false


        function open() {
            emptyConfirm.visible = true;
            emptyConfirm.forceActiveFocus();
        }

        Keys.onEscapePressed: emptyConfirm.visible = false

        MouseArea {
            anchors.fill: parent
            onClicked: emptyConfirm.visible = false
        }


        // Costruita all'avvio, e va bene così: renderla pigra è stato provato
        // due volte e misurato una, e non cambia niente. Il conto per esteso
        // sta sul primo di questi riquadri, sopra `prompt`.
        Rectangle {
            id: emptyCard
            anchors.centerIn: parent
            width: 400
            height: 150
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea {
                anchors.fill: parent

            }

            Text {
                id: emptyText
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                wrapMode: Text.WordWrap
                text: Core.Strings.lang === "it" ? "Svuotare il cestino?"
                                                 : "Empty the bin?"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.top: emptyText.bottom
                anchors.topMargin: Theme.Effects.space2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                wrapMode: Text.WordWrap
                text: Core.Strings.lang === "it"
                      ? "Quello che c'è dentro viene cancellato per sempre. "
                        + "Non c'è un altro cestino sotto questo."
                      : "Everything inside is deleted for good. "
                        + "There is no second bin under this one."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "cancel", "danger": false },
                        { "id": "empty",  "danger": true }
                    ]

                    delegate: Rectangle {
                        id: emptyBtn
                        required property var modelData

                        readonly property color tone: modelData.danger
                                                      ? Theme.Colors.danger
                                                      : Theme.Colors.textMuted

                        width: emptyLabel.implicitWidth + Theme.Effects.space5
                        height: 32
                        radius: Theme.Effects.radiusXS
                        color: emptyMouse.containsMouse ? Qt.alpha(tone, 0.18)
                                                        : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: emptyLabel
                            anchors.centerIn: parent
                            text: {
                                var it = Core.Strings.lang === "it";
                                if (emptyBtn.modelData.id === "cancel")
                                    return it ? "Annulla" : "Cancel";
                                return it ? "Svuota" : "Empty";
                            }
                            color: emptyBtn.modelData.danger ? Theme.Colors.danger
                                                             : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: emptyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                emptyConfirm.visible = false;
                                if (emptyBtn.modelData.id === "empty")
                                    Core.Ipc.fsTrashEmpty();
                            }
                        }
                    }
                }
            }
        }

    }
}
