// shell.qml — Punto d'ingresso di Minerva Shell.
//
// Questo file non disegna niente. Mette in piedi i pochi oggetti di primo
// livello e li collega fra loro; tutto il resto sta nei componenti.
//
//   Spine         la barra e i pannelli che ne discendono (una superficie sola)
//   Toasts        gli avvisi delle notifiche
//   DesktopLayer  il tasto destro sullo sfondo
//   Palette / Cheatsheet   sovrapposizioni a schermo intero, caricate solo
//                 quando servono
//
// Regola d'oro del progetto: OGNI funzione raggiungibile da tastiera deve
// essere raggiungibile anche col mouse, e viceversa. Chi non conosce le
// scorciatoie deve poter fare tutto cliccando; chi le conosce non deve
// staccare le mani dalla tastiera.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

import "theme" as Theme
import "core" as Core
import "switcher"
import "ui" as Ui
import "widget" as Widget
import "spine"
import "menu"
import "dock"

ShellRoot {
    id: root

    // ── Ricaricamento a caldo: spento ────────────────────────────────────
    //
    // Quickshell sorveglia i file QML e si ricarica da solo appena ne cambia
    // uno. È comodissimo mentre si scrive la shell ed è INACCETTABILE mentre
    // qualcuno la sta usando: un ricaricamento ricrea barra, dock e scrivania
    // e chiude tutte le finestre di Minerva aperte. Chi sta lavorando vede
    // sparire tutto senza aver toccato niente, e pensa giustamente che sia
    // crollato qualcosa.
    //
    // Da qui in poi si ricarica solo quando lo si chiede:
    //
    //     qs ipc --pid <pid> call minerva reload
    //
    // Chi sviluppa lo riaccende dalle Impostazioni, ed è l'unico che lo vuole.
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        // ── Chi comanda le impostazioni di SISTEMA è uno solo ────────────
        //
        // Stessa ragione dello sfondo qui sotto, e lo stesso schema: Minerva è
        // più di un processo, e ogni processo ha la sua copia di
        // `Core.Compositore`. La disposizione della tastiera, il tocco del
        // trackpad, l'aspetto delle barre del titolo e le regole delle
        // finestre riguardano tutta la sessione — non una finestra.
        //
        // Fino al 31 agosto 2026 le mandava OGNUNO: aprire il gestore file
        // riconfigurava l'ingresso e lanciava una shell per riscrivere
        // `minerva-windows.conf`. Si è visto solo il giorno in cui è comparso
        // un verbo nuovo e ogni app ha cominciato a stampare
        // «verbo sconosciuto».
        Core.Compositore.scrivania = true;
        // Il mazzo degli sfondi lo fa girare la shell e nessun altro. Minerva
        // è più di un processo, e ogni processo ha la sua copia di
        // `Core.Wallpaper`: senza questo turno esplicito, con le Impostazioni
        // aperte lo sfondo cambierebbe al doppio della velocità chiesta.
        Core.Wallpaper.rotates = true;
        // Trova il touchpad e rimettilo com'era stato lasciato: vedi più
        // sotto, alla voce del tasto Fn.
        Core.Compositore.chiedi("dispositivi");
        // ── E le soglie dell'inattività ─────────────────────────────────
        //
        // Qui, e non solo nei due segnali che le seguono. Un segnale è
        // un'occasione sola: se il canale era già aperto quando questa shell è
        // nata, `onCanaleApertoChanged` è già passato; e se le impostazioni
        // del demone dicono gli stessi numeri dei valori di ripiego — cinque,
        // dieci, trenta — il valore non CAMBIA e `onSogliaDimChanged` non
        // scatta affatto. Quella seconda coincidenza è comunissima, ed è
        // esattamente il caso in cui la prima prova annidata ha trovato zero
        // soglie chieste.
        //
        // Vedi `core/Compositore.qml`: è lo stesso difetto che il 1º settembre
        // 2026 ha lasciato il touchpad senza tap-to-click per otto ore.
        root.applicaInattivita();
    }

    Binding {
        target: Quickshell
        property: "watchFiles"
        value: Core.Ipc.get("shell.hotReload", false)
    }

    // ── Preferenze che vivono nel demone ─────────────────────────────────

    // La lingua dei testi segue le impostazioni; "auto" usa quella di sistema.
    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }

    Binding {
        target: Core.Notifications
        property: "doNotDisturb"
        value: Core.Ipc.get("notifications.doNotDisturb", false)
    }

    // ── Il colore di Minerva ─────────────────────────────────────────────
    //
    // Tema, accento e trasparenze si legano QUI e non dentro la palette,
    // perché la palette non deve conoscere il demone: un tema che sa dove
    // stanno le impostazioni è un tema che non si può riusare. E si ripete in
    // tutti e tre i punti d'ingresso perché sono processi diversi, che non
    // possono leggersi le proprietà a vicenda — la sorgente però è la stessa,
    // quindi cambiare tema li ridipinge tutti nello stesso istante.
    // Il tema di colore: una tinta e un verso, e da lì escono tutte le
    // superfici. Sta prima dell'accento di proposito — l'accento predefinito
    // è quello suggerito dal tema, e chi non ne ha scelto uno suo deve
    // vedersi arrivare quello giusto insieme al resto.

    // ── Il tema ──────────────────────────────────────────────────────────
    //
    // Un oggetto solo al posto dei blocchi di `Binding` che stavano qui: la
    // tavolozza non legge le impostazioni, e chi fa il legame lo fa in un
    // posto solo per tutti e sei i punti d'ingresso. Vedi `theme/LegaTema.qml`.
    Theme.LegaTema { animazioni: true }


    // ── Le animazioni della SHELL, che l'interruttore non toccava ────────
    //
    // Giacomo, 19 agosto 2026: spegnere le animazioni «non porta a nessun
    // cambiamento». Era vero: `Compositore.animazioni()` spegne quelle del
    // COMPOSITORE — finestre che si aprono, cambio scrivania — mentre i
    // pannelli, la dock e i menu li anima la shell con le durate di
    // `Theme.Motion`, che erano numeri fissi.
    //
    // Zero vuol dire nessuna animazione: in QML una durata di zero fa arrivare
    // il valore a destinazione nello stesso fotogramma.
    //
    // La velocità è separata dall'interruttore apposta: chi le spegne e poi le
    // riaccende ritrova la SUA velocità, non quella di fabbrica.




    // Quanto vetro hanno le finestre di Minerva. Separata dalla membrana
    // perché è un problema diverso: la barra deve restare leggibile sopra
    // qualunque cosa, una finestra ha dietro solo la scrivania.

    // Il tetto del volume. Cento è il massimo onesto di un altoparlante; oltre
    // è amplificazione software che aggiunge distorsione e non volume.
    Binding {
        target: Core.SystemState
        property: "volumeCeiling"
        value: Core.Ipc.get("audio.allowOverdrive", false) ? 150 : 100
    }

    // La voce di Minerva. Si può spegnere, e chi la vuole più discreta la
    // abbassa senza spegnerla: un ambiente che fa rumore quando non lo si
    // vuole è peggio di uno muto.
    Binding {
        target: Core.Sounds
        property: "enabled"
        value: Core.Ipc.get("audio.feedbackSounds", true)
    }

    Binding {
        target: Core.Sounds
        property: "level"
        value: Core.Ipc.get("audio.feedbackVolume", 0.4)
    }

    // ── Comandi dall'esterno ─────────────────────────────────────────────
    //
    // Quickshell rilegge i file QML da solo appena cambiano, quindi durante lo
    // sviluppo non serve fare niente. Ma quando un file viene salvato mentre
    // la shell è in errore, o quando si modifica qualcosa che il controllo
    // automatico non guarda, serve un modo per dire «ricarica adesso» senza
    // uccidere il processo — uccidere `qs` fa sparire barra e pannelli per un
    // secondo, e con loro la maniglia per rimetterli a posto.
    //
    //     qs ipc -p <percorso> call minerva reload
    //     qs ipc -p <percorso> call minerva panel apps
    IpcHandler {
        target: "minerva"

        function reload(): string {
            Quickshell.reload(false);
            return "ok";
        }

        /// Ricarica buttando via anche ciò che è in cache. Serve quando un
        /// componente nuovo non viene visto dal ricaricamento normale.
        function reloadHard(): string {
            Quickshell.reload(true);
            return "ok";
        }

        /// Apre o chiude un pannello per nome, per poterli provare da script.
        function panel(name: string): string {
            var barraAttiva = root.spine;
            if (!barraAttiva || barraAttiva.registry[name] === undefined)
                return "pannello sconosciuto: " + name;
            root.pannello(name);
            return "ok";
        }

        /// Apre una parte della shell per nome, gli stessi nomi che usa la
        /// ricerca universale: settings, display, power, audio, network,
        /// bluetooth, files, clipboard, cheatsheet.
        ///
        ///     qs ipc --pid <pid> call minerva open display
        function open(what: string): string {
            root.runCommand(what);
            return "ok";
        }

        /// Apre il gestore file su una cartella precisa.
        ///
        ///     qs ipc --pid <pid> call minerva files ~/Immagini
        ///
        /// È quello che rende il nostro gestore file un candidato vero per
        /// `inode/directory`: senza un modo di dirgli DOVE andare, sceglierlo
        /// per aprire le cartelle vorrebbe dire vederselo aprire sempre sulla
        /// cartella di casa, e a quel punto Dolphin è meglio.
        function files(path: string): string {
            root.openFiles(path);
            return "ok";
        }

        /// Com'è messa la dock adesso: il modo e se si vede.
        ///
        ///     qs ipc --pid <pid> call minerva dock
        ///     → "elude ritirata"   |   "elude presente"   |   "sempre presente"
        ///
        /// ── Perché esiste ────────────────────────────────────────────────
        ///
        /// Perché «la dock si è tolta di mezzo» è una cosa che si vede e non
        /// si misura: è una superficie layer-shell che scivola fuori dallo
        /// schermo, e da fuori non c'è niente da interrogare. Senza questa
        /// riga l'unico modo di provare il modo «elude» sarebbe confrontare i
        /// pixel di una fotografia — cioè una prova che diventa rossa il
        /// giorno che cambia lo sfondo.
        ///
        /// È la stessa ragione per cui il compositore risponde con
        /// `"inattivita": N` a `stato`: una cosa che non si può guardare da
        /// fuori è una cosa che nessuno saprà se ha smesso di funzionare.
        /// Apre il menù delle app con un testo già scritto (vuoto: com'è),
        /// o lo chiude se il testo è «chiudi». Risponde con quello che il
        /// menù mostra: le prove leggono qui cosa ha trovato la ricerca.
        function menu(testo: string): string {
            var s = root.scrivaniaAttiva();
            if (!s || !s.sottomarino)
                return "nessun menù";
            if (testo === "chiudi") {
                s.sottomarino.chiudi();
                return "chiuso";
            }
            s.sottomarino.apri(testo);
            s.sottomarino.cerca = testo;
            return s.sottomarino.riassunto();
        }

        function dock(): string {
            // Il terzo pezzo dice PERCHÉ, e serve: «la dock non si nasconde»
            // ha due cause che da fuori si vedono identiche — il modo
            // sbagliato, e il puntatore che le sta sopra. La seconda è il
            // comportamento giusto, ma senza dirlo sembra un guasto.
            return root.dockModo + " "
                   + (root.dockVisibile ? "presente" : "ritirata")
                   + (root.dockVisibile && root.dockSottoIlDito
                      ? " col-puntatore" : "");
        }

        /// Rilegge i file `.desktop`. Serve dopo aver installato o corretto
        /// un programma, senza uscire dalla sessione.
        function rescan(): string {
            Core.Ipc.rescanApps();
            return "ok";
        }

        /// Salta allo sfondo successivo o precedente del mazzo che gira, e
        /// dice a che punto siamo. Vale in tutti i modi in cui c'è un mazzo:
        /// gli sfondi di Minerva e la cartella.
        ///
        ///     qs ipc --pid <pid> call minerva sfondo next
        ///
        /// Serve anche a legarlo a un tasto, senza aprire le Impostazioni.
        function sfondo(dove: string): string {
            if (dove === "next" || dove === "prossimo")
                Core.Wallpaper.next(1);
            else if (dove === "prev" || dove === "precedente")
                Core.Wallpaper.next(-1);
            var name = String(Core.Wallpaper.current);
            var cut = name.lastIndexOf("/");
            return (cut >= 0 ? name.substring(cut + 1) : name)
                 + "  " + (Core.Wallpaper.poolAt + 1)
                 + "/" + Core.Wallpaper.pool.length
                 + "  modo=" + Core.Wallpaper.mode
                 + " ogni=" + Core.Wallpaper.rotateMinutes + "min"
                 + (Core.Wallpaper.rotateRandom ? " a-caso" : " in-ordine");
        }

        function status(): string {
            return "pannello=" + (!root.spine || root.spine.activePanel === ""
                                  ? "-" : root.spine.activePanel)
                 + " demone=" + (Core.Ipc.connected ? "connesso" : "assente")
                 + " lingua=" + Core.Strings.lang
                 + " sorveglia-file=" + (Quickshell.watchFiles ? "SI" : "no")
                 + " dock=" + (root.dock ? root.dock.items.length : 0)
                 + " schermi=" + Object.keys(root.scrivanie).length
                 + " finestre=" + Core.Windows.all.length
                 // Qual è la finestra attiva SECONDO LA SHELL. Non è la stessa
                 // domanda che si fa al compositore: da questa dipende quale
                 // barra del titolo si accende, e le due possono divergere in
                 // silenzio — una barra spenta sopra una finestra accesa.
                 + " attiva=" + (Core.Windows.activeAddress === ""
                                 ? "-" : Core.Windows.activeAddress);
        }

        /// Lo SPAZIO UTILE come lo crede la shell in questo momento.
        ///
        /// Esiste per una ragione precisa: è il numero da cui dipendono
        /// «ingrandisci», l'aggancio ai bordi e la posizione minima di ogni
        /// finestra, ed è anche un numero che si può sbagliare in silenzio —
        /// se lo si legge prima che la barra abbia riservato il proprio posto,
        /// resta sbagliato per sempre e nessuna schermata lo dice.
        ///
        /// Guardando lo schermo si vede l'effetto (una finestra troppo in
        /// alto) e non la causa. Da qui si vede la causa.
        ///
        ///     qs ipc -p <percorso> call minerva spazio
        function spazio(): string {
            var u = Core.Windows.usable;
            if (!u)
                return "sconosciuto";
            return "x=" + u.x + " y=" + u.y + " w=" + u.w + " h=" + u.h;
        }
    }

    // ── Esecuzione di comandi esterni ────────────────────────────────────
    //
    // `execDetached` e non un `Process`, e non è un dettaglio: un `Process` di
    // Quickshell POSSIEDE il programma che ha lanciato. Quando l'oggetto QML
    // viene distrutto — cioè a ogni ricaricamento della shell — il programma
    // muore con lui. E siccome un solo `Process` veniva riusato per ogni
    // avvio, lanciare Firefox chiudeva il terminale aperto un minuto prima.
    //
    // Era questo il guasto per cui «quando si aggiorna la shell si chiudono
    // tutte le app». Un programma lanciato dall'ambiente non appartiene
    // all'ambiente: gli sopravvive, come su qualunque altro sistema.
    function run(command) {
        if (!command || command.length === 0)
            return;
        Quickshell.execDetached(command);
    }

    // ── ORDINE DI SOVRAPPOSIZIONE ────────────────────────────────────────
    //
    // Barre del titolo, dock e barra di sistema stanno tutte sul livello
    // `Top` di layer-shell, e dentro uno stesso livello il compositore
    // impila le superfici NELL'ORDINE IN CUI SONO STATE CREATE: l'ultima
    // arrivata sta sopra. Non c'è nessun `z` che possa cambiarlo, quindi
    // l'ordine di dichiarazione in questo file È l'ordine visivo.
    //
    // Da qui in giù, dal fondo verso l'alto:
    //
    //   1. TitleBars  — appartengono alle finestre, stanno appena sopra di
    //                   loro. Erano dichiarate per ultime e finivano SOPRA il
    //                   menu delle applicazioni, tagliandolo a metà.
    //   2. Dock       — sopra le finestre, sotto i pannelli.
    //   3. Spine      — la barra e la sua lingua stanno sopra tutto: sono il
    //                   comando dell'ambiente, e niente le deve coprire.

    // ── Barre del titolo ─────────────────────────────────────────────────
    //
    // Danno a ogni finestra la sua maniglia e i suoi tre pulsanti, senza
    // dover salire fino alla barra di sistema. Occupano lo spazio che
    // Hyprland lascia libero sopra ogni riquadro — vedi `windows.titleBars`
    // nelle Impostazioni, che regola anche i margini del compositore.

    // ── Dove stanno barra e dock ─────────────────────────────────────────
    //
    // La risposta sta in `Core.Posizioni`, non qui: se la fanno anche gli
    // avvisi, la griglia della scrivania e il promemoria dei tasti, e la
    // conversione dai nomi vecchi (`top`, `bottom`) deve stare in un posto
    // solo. Qui si legge e si passa a chi non è un singleton, come per tutte
    // le altre preferenze: la Spine e la Dock non leggono le impostazioni da
    // sé, così una prova può metterle dove vuole senza toccare il file della
    // sessione vera.
    readonly property bool barraInBasso: Core.Posizioni.barraInBasso
    readonly property bool dockInAlto: Core.Posizioni.dockInAlto

    readonly property bool titleBarsOn: Core.Ipc.get("windows.titleBars", true)
    readonly property int titleBarHeight: Core.Ipc.get("windows.titleHeight", 34)

    // ── Chi disegna le barre del titolo, davvero ─────────────────────────
    //
    // Qui c'era `!barreCompositore.attiva`, e `attiva` vuol dire una cosa
    // sola: **il plugin di Hyprland è caricato**. Sotto minerva-wayland quel
    // plugin non esiste e non esisterà mai — quindi risultava falso, e la
    // shell si rimetteva a disegnare le barre.
    //
    // Ma il nostro compositore le disegna già, native, in `src/barra.c`. Il
    // risultato, fotografato il 30 agosto 2026 aprendo un terminale dentro la
    // sessione: **due barre del titolo, una sopra l'altra**, con lo stesso
    // titolo e due file di pulsanti. Sono le «barre sovrapposte» della lista
    // di Giacomo, ed è il caso che si vede tutti i giorni.
    //
    // E non costava solo brutto: `TitleBars.qml` insegue la geometria delle
    // finestre per stare loro addosso, quindi teneva la shell a ridipingere
    // di continuo. Misurato nella sessione annidata, a scrivania ferma:
    // **329 risvegli al secondo** e un ridisegno a ogni fotogramma.
    //
    // Le barre le disegna il compositore in DUE casi, non uno: il plugin sotto
    // Hyprland, e nativamente sotto il nostro. La shell disegna solo quando non
    // lo fa nessuno dei due.
    //
    // ── E dal 1º settembre 2026 il caso è uno solo ───────────────────────
    //
    // Il secondo era il plugin di Hyprland, sorvegliato da
    // `core/BarreCompositore.qml`: una ronda ogni trenta secondi con dentro
    // due `hyprctl`, perché il plugin poteva sparire senza dirlo. Con
    // Hyprland se ne va anche quella — le barre native del nostro compositore
    // non si scaricano da sole, e non c'è niente da sorvegliare.
    readonly property bool barreDalCompositore: Core.Compositore.nostro

    TitleBars {
        id: titleBars
        enabled: root.titleBarsOn && !root.barreDalCompositore
        titleHeight: root.titleBarHeight

        onMenuRequested: function(address, where) {
            Core.Windows.focus(address);
            windowMenu.openAt(where.x, where.y, root.windowMenuItems());
        }
    }

    // La via d'uscita dallo schermo intero. Sta su `overlay` perché è l'unico
    // livello che una finestra a schermo intero non copre — vedi il file, dove
    // c'è scritto come è stato misurato.
    FullscreenBar {
        mode: Core.Ipc.get("windows.fullscreenBar", "hover")
        barHeight: root.titleBarHeight
    }

    // Le barre del titolo hanno bisogno che il compositore lasci il posto in
    // cui disegnarle: senza, coprirebbero il contenuto del programma. Qui si
    // scrive la regola, e da qui passa anche la scelta fra finestre affiancate
    // e finestre libere.
    Core.WindowRules {
        id: windowRules

        // Con il plugin il posto per la barra se lo riserva il compositore
        // (`reserved = true` nella decorazione): chiedere ANCHE il margine in
        // cima a `gaps_in` lo conterebbe due volte, e ogni finestra
        // nascerebbe con una fascia vuota alta quanto una barra sopra la
        // barra.
        titleBars:      root.titleBarsOn && !root.barreDalCompositore
        titleHeight:    root.titleBarHeight
        effetto:        Core.Ipc.get("windows.effetto", "nessuno")
        effettoOpacita: Core.Ipc.get("windows.effettoOpacita", 0.88)
        blurIntensita: Core.Ipc.get("windows.blurIntensita", 50)
        rigidita: Core.Ipc.get("windows.rigidita", 1)
        smorzamento: Core.Ipc.get("windows.smorzamento", 0.42)
        cornice:        Core.Ipc.get("windows.cornice", "spento")
        cornicePeriodo: Core.Ipc.get("windows.cornicePeriodo", 8000)
        corniceSpessore: Core.Ipc.get("windows.corniceSpessore", 6)
        corniceTinte:   Core.Ipc.get("windows.corniceTinte", [])
        corniceSpente:  Core.Ipc.get("windows.corniceSpente", 0)
        elastico:       Core.Ipc.get("desktop.animations", true)
                       ? Core.Ipc.get("windows.elastico", 0) : 0
    }

    // ── La dock ──────────────────────────────────────────────────────────
    //
    // Sta in basso e mostra cosa gira. Ogni sua impostazione arriva da qui:
    // la dock non sa che esiste un demone, sa solo disegnarsi.

    // ── Quale schermo è «adesso» ─────────────────────────────────────────
    //
    // Con un monitor solo la domanda non esisteva: `spine.toggle("apps")` e
    // via. Con due, ogni scorciatoia deve scegliere — e la risposta giusta è
    // sempre la stessa: **lo schermo dove sta il puntatore**, cioè quello che
    // Hyprland chiama attivo. Chi preme Super+A guarda lì.
    //
    // `scrivanie` è la mappa nome-monitor → { barra, dock }. La riempiono le
    // copie stesse nascendo, e la svuotano morendo: staccare un monitor
    // distrugge la sua copia, e se restasse iscritta le scorciatoie
    // parlerebbero a una barra che non esiste più.

    property var scrivanie: ({})

    function iscriviScrivania(nome, barra, dock, sottomarino) {
        if (!nome)
            return;
        var m = root.scrivanie;
        m[nome] = { "barra": barra, "dock": dock, "sottomarino": sottomarino };
        root.scrivanie = m;
        root.scrivanieCambiate();
    }

    function cancellaScrivania(nome) {
        if (!nome || root.scrivanie[nome] === undefined)
            return;
        var m = root.scrivanie;
        delete m[nome];
        root.scrivanie = m;
        root.scrivanieCambiate();
    }

    /// Cambia quando una scrivania si iscrive o si cancella. `scrivanie` è un
    /// `var`: cambiarne il contenuto non fa scattare nessuna associazione, e
    /// senza questo segnale `spine` resterebbe ferma sulla prima risposta.
    signal scrivanieCambiate()

    /// La barra dello schermo attivo. Se quel nome non si trova — succede nel
    /// mezzo di un attacca-e-stacca — si prende la prima che c'è, perché una
    /// scorciatoia che non fa niente è peggio di una che agisce sullo schermo
    /// sbagliato.
    function scrivaniaAttiva() {
        var nome = Core.Compositore.monitorAttivo;
        if (nome && root.scrivanie[nome])
            return root.scrivanie[nome];
        for (var k in root.scrivanie)
            return root.scrivanie[k];
        return null;
    }

    /// Apre o chiude un pannello sulla barra dello schermo attivo.
    ///
    /// Passano da qui TUTTE le scorciatoie: se un giorno non c'è nessuno
    /// schermo — succede fra lo stacco di un monitor e l'attacco del
    /// successivo — non deve saltare fuori un errore, deve semplicemente non
    /// succedere niente.
    /// Il menù delle app dello schermo attivo. Se per qualche ragione quello
    /// schermo non ce l'ha, resta il pannello di prima.
    function apriSottomarino() {
        var s = root.scrivaniaAttiva();
        if (s && s.sottomarino)
            s.sottomarino.commuta();
        else
            root.pannello("apps");
    }

    /// Le azioni che il Sottomarino trova con la ricerca. Quelle che
    /// chiudono la sessione passano dal pannello dell'energia, che chiede
    /// conferma: la ricerca non deve poter spegnere il computer con un Invio.
    function azioneDalMenu(id) {
        switch (id) {
        case "blocca":       root.run(["minerva-blocca"]); break;
        case "notte":        Core.Ipc.setSetting("display.nightLight",
                                                 !Core.Ipc.get("display.nightLight", false)); break;
        case "dnd":          Core.Ipc.setSetting("notifications.doNotDisturb",
                                                 !Core.Notifications.doNotDisturb); break;
        case "impostazioni": root.openSettings(); break;
        case "sospendi":
        case "riavvia":
        case "spegni":
        case "esci":         root.apriPannello("power"); break;
        }
    }

    function pannello(nome) {
        var s = root.scrivaniaAttiva();
        if (s && s.barra)
            s.barra.toggle(nome);
    }

    function apriPannello(nome) {
        var s = root.scrivaniaAttiva();
        if (s && s.barra)
            s.barra.open(nome);
    }

    function chiudiPannelli() {
        for (var k in root.scrivanie)
            if (root.scrivanie[k].barra)
                root.scrivanie[k].barra.close();
    }

    /// Comodità: `root.spine.toggle(...)` continua a leggersi come prima.
    readonly property var spine: {
        root.scrivanieCambiate;
        var s = root.scrivaniaAttiva();
        return s ? s.barra : null;
    }

    readonly property var dock: {
        root.scrivanieCambiate;
        var s = root.scrivaniaAttiva();
        return s ? s.dock : null;
    }

    // ── Dock e barra: una coppia per schermo ─────────────────────────────
    //
    // Stanno insieme in un `Scope` perché si conoscono: la barra deve sapere
    // dove NON stendersi (la dock del SUO schermo), e la dock deve sapere
    // quando il puntatore è in basso (glielo dice la barra del suo schermo).
    // Con due `Variants` separati la barra del monitor esterno avrebbe
    // guardato la dock del portatile, e il buco per la dock sarebbe finito
    // nel posto sbagliato.
    //
    // Ogni coppia si iscrive a `root.scrivanie` quando nasce e si cancella
    // quando lo schermo se ne va: è così che le scorciatoie sanno su quale
    // barra agire.
    Variants {
        model: Quickshell.screens

        Scope {
            id: scrivania
            required property var modelData

            Dock {
                id: dock
                screen: scrivania.modelData
                inAlto: root.dockInAlto

                enabled:              Core.Ipc.get("dock.enabled", true)
                iconSize:             Core.Ipc.get("dock.iconSize", 48)
                magnification:        Core.Ipc.get("dock.magnification", 1.6)
                magnificationReach:   Core.Ipc.get("dock.reach", 2.2)
                // ── Tre modi, e il vecchio valore che vale ancora ────
                //
                // Chi aveva già Minerva installata ha `dock.autoHide` nel
                // proprio file e non ha mai sentito parlare di `dock.modo`:
                // se si leggesse solo la chiave nuova, la sua dock
                // cambierebbe comportamento da sola al primo avvio dopo
                // l'aggiornamento. Si legge la nuova, e se non c'è si guarda
                // la vecchia.
                modo: {
                    var m = String(Core.Ipc.get("dock.modo", ""));
                    if (m === "sempre" || m === "nascondi" || m === "elude")
                        return m;
                    return Core.Ipc.get("dock.autoHide", false)
                           ? "nascondi" : "sempre";
                }
                // Due chiavi come per la membrana, e per la stessa ragione:
                // dietro la dock col blur c'è una macchia morbida e senza una
                // fotografia nitida, cioè due situazioni diverse. Vedi
                // `theme/LegaTema.qml`.
                opacity_:             Core.Vetro.blurVero
                                      ? Core.Ipc.get("dock.opacityBlur", 0.68)
                                      : Core.Ipc.get("dock.opacity", 0.90)
                showLabels:           Core.Ipc.get("dock.showLabels", true)
                pinned:               Core.Ipc.get("dock.pinned", [
                                          "firefox.desktop", "minerva-terminale.desktop"
                                      ])

                onMenuRequested: function(index, where) {
                    dockMenu.index = index;
                    dockMenu.dock = dock;
                    // Centrato sull'icona, e dalla parte dove c'è spazio: sopra
                    // se la dock sta in fondo allo schermo, sotto se sta in
                    // cima. Da che parte lo dice la dock — è lei a sapere dov'è.
                    if (dock.menuVersoIlBasso)
                        dockMenu.openBelow(where.x, where.y, dock.menuItems(index));
                    else
                        dockMenu.openAbove(where.x, where.y, dock.menuItems(index));
                }

                onPinnedChangeRequested: function(list) {
                    Core.Ipc.setSetting("dock.pinned", list);
                }

                // ── La dock riferisce com'è messa ────────────────────────
                //
                // Serve all'IPC `minerva dock`, che è l'unico modo di sapere
                // da fuori se si è ritirata: è una superficie layer-shell che
                // scivola via, e da fuori non c'è niente da interrogare.
                //
                // Con due schermi vince l'ultima che parla, e va bene: quello
                // che si sta provando è il MODO, che è lo stesso per tutte.
                onRevealedChanged: root.dockVisibile = dock.revealed
                onModoChanged: root.dockModo = dock.modo
                onSottoIlDitoChanged: root.dockSottoIlDito = dock.sottoIlDito
                Component.onCompleted: {
                    root.dockVisibile = dock.revealed;
                    root.dockModo = dock.modo;
                    root.dockSottoIlDito = dock.sottoIlDito;
                }
            }

            Spine {
                id: spine
                screen: scrivania.modelData
                inBasso: root.barraInBasso

                // Il raccoglitore di clic della Spine sta sopra tutto: gli si
                // dice dove NON stendersi, altrimenti con un pannello aperto
                // la dock diventerebbe inservibile.
                keepClickable: dock.screenRect
                dockBand: dock.hoverRect

                // Vedi `puntatoreSullaDock` in Spine.qml: con un pannello aperto
                // il puntatore lo riceve solo lei, e la dock lo saprebbe da
                // nessuno.
                onPuntatoreSullaDockChanged: dock.forceReveal = spine.puntatoreSullaDock

                onCheatsheetRequested: root.toggleCheatsheet()
                onSettingsRequested: root.openSettings()
                onMenuAppChiesto: sottomarino.commuta()
                onMonitorRequested: root.openMonitor()
                onScreenshotRequested: function(modo, ritardo) {
                    root.scattaSchermata(modo, ritardo);
                }
                onWindowMenuRequested: function(where) {
                    windowMenu.openAt(where.x, where.y, root.windowMenuItems());
                }

                // Il tasto destro sul vuoto della barra. Lo stesso menù
                // `desktopMenu` con voci diverse: due ContextMenu identici
                // sarebbero due superfici a schermo intero, e la seconda
                // servirebbe solo a duplicare il gestore delle azioni.
                onMenuBarraChiesto: function(dove) {
                    desktopMenu.openAt(dove.x, dove.y, root.barraMenuItems());
                }
            }

            // ── Il menù delle app: emerge dall'angolo in basso a sinistra ──
            Sottomarino {
                id: sottomarino
                screen: scrivania.modelData
                // Sopra la dock quando è in basso e si vede: coprirla vorrebbe
                // dire nasconderle le app sotto il menù che le cerca.
                margineBasso: dock.screenRect.height > 0 && !root.dockInAlto && scrivania.modelData
                              ? Math.max(0, scrivania.modelData.height - dock.screenRect.y) + Theme.Effects.space2
                              : 0
                onAzione: function(id) { root.azioneDalMenu(id); }
            }
            Connections {
                target: Core.Compositore
                function onAngolo(quale, schermo) {
                    if (quale === "basso-sx" && scrivania.modelData
                        && schermo === scrivania.modelData.name)
                        sottomarino.apri("");
                }
            }

            Component.onCompleted: root.iscriviScrivania(
                scrivania.modelData ? scrivania.modelData.name : "", spine, dock, sottomarino)
            Component.onDestruction: root.cancellaScrivania(
                scrivania.modelData ? scrivania.modelData.name : "")
        }
    }

    ContextMenu {
        id: dockMenu
        property int index: -1
        /// La dock che ha aperto questo menu: con più schermi non è più
        /// «la dock», è una delle due.
        property var dock: null
        onTriggered: function(action) {
            if (dockMenu.dock)
                dockMenu.dock.runMenuAction(dockMenu.index, action);
        }
    }

    // ── Alt+Tab ──────────────────────────────────────────────────────────
    //
    // Uno solo per tutta la sessione e non uno per schermo: si tiene premuto
    // Alt e si guarda un posto solo. Due riquadri identici su due monitor
    // sarebbero due cose da guardare per una scelta sola.
    Switcher {
        id: selettore
    }

    // ── I due singleton che devono esistere anche se nessuno li guarda ───
    //
    // Un singleton QML nasce alla PRIMA volta che qualcuno lo nomina. La
    // modalità gioco e la luce notturna non hanno nessuno che le guardi —
    // lavorano da sole — quindi senza queste due righe non nascerebbero mai,
    // e non se ne accorgerebbe nessuno: non è un errore, è semplicemente una
    // funzione che non c'è.
    // ── I due singleton che devono esistere anche se nessuno li guarda ───
    //
    // `Gioco` e `LuceNotturna` non hanno interfaccia: lavorano reagendo alle
    // impostazioni. Ma un singleton QML nasce quando qualcuno lo TOCCA, e
    // nominarlo non è toccarlo:
    //
    //     readonly property var _tieniVivaLaLuce: Core.LuceNotturna   ← inutile
    //
    // Quella riga c'era, sembrava fare il suo mestiere, e non ne faceva
    // nessuno: nomina il tipo senza leggerne una proprietà, quindi il
    // singleton non veniva costruito. Il pannello di controllo scrive
    // `display.nightLight` passando da `Core.Ipc`, non da `Core.LuceNotturna`,
    // e così NESSUNO in tutta la sessione toccava la luce notturna: la levetta
    // scattava, l'impostazione si salvava, e non succedeva niente.
    //
    // Segnalato da Giacomo il 17 agosto 2026 — «se clicco su luce notturna non
    // succede» — e trovato solo perché `prove-luce.qml` faceva la stessa cosa
    // e falliva allo stesso modo.
    //
    // Si legge una PROPRIETÀ, non il tipo. È la differenza fra le due righe.
    readonly property bool _tieniVivoGioco: Core.Gioco.attiva
    readonly property bool _tieniVivaLaLuce: Core.LuceNotturna.daApplicare

    // ── Modalità gioco ───────────────────────────────────────────────────
    //
    // Si accende da sola quando qualcosa va a schermo intero. Vedi
    // `core/Gioco.qml`: qui si dà solo la superficie a cui appendere il freno
    // dell'inattività, perché `IdleInhibitor` ne vuole una e un singleton non
    // ne ha.
    Binding {
        target: Core.Gioco
        property: "finestraFreno"
        value: cartelloGioco
    }

    // Il cartello. Compare due secondi e se ne va: serve a dire «lo so, ci
    // penso io», non a restare lì mentre si gioca.
    PanelWindow {
        id: cartelloGioco

        // In BASSO, non in alto. In alto c'è già la barra che compare sulle
        // finestre a schermo intero (`spine/FullscreenBar.qml`), e due cartelli
        // nello stesso punto sono uno sopra l'altro: provato il 10 agosto, il
        // secondo non si vedeva affatto.
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 110
        color: "transparent"
        // Montato solo finché serve: mentre si vede la pillola, o mentre
        // regge il freno dell'inattività (`Core.Gioco.frenoServe`). Era
        // sempre montato, trasparente, sopra ogni film: e una superficie
        // sopra la finestra a schermo intero impedisce lo scanout diretto —
        // misurato il 23 settembre 2026, lista di disegno da tre elementi
        // invece che da uno.
        visible: pillolaGioco.opacity > 0 || viaIlCartello.running
                 || Core.Gioco.frenoServe

        WlrLayershell.namespace: "minerva-gioco"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        // Nessun clic: è un cartello, non un comando. Senza questa riga si
        // mangerebbe il mouse nella fascia alta dello schermo — cioè proprio
        // sopra un gioco.
        mask: Region {}

        Rectangle {
            id: pillolaGioco
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.Effects.space6
            width: testoGioco.implicitWidth + Theme.Effects.space6
            height: 40
            radius: height / 2
            color: Qt.alpha(Theme.Colors.membrane, 0.92)
            border.width: Theme.Effects.hairline
            border.color: Qt.alpha(Theme.Colors.accent, 0.5)

            // Sale entrando e scende uscendo: un cartello che appare e
            // sparisce sul posto si nota meno di uno che si muove, e qui va
            // notato una volta sola e poi dimenticato.
            // Sale entrando e scende uscendo. Il `Translate` va dichiarato con
            // un id e la sua animazione a parte: scritto tutto dentro
            // `transform:` su una riga sola, QML legge male dove finisce la
            // proprietà e finisce per assegnare `undefined` — un avviso che
            // indica una riga in cui non c'è niente di sbagliato.
            opacity: 0
            transform: Translate { id: salita; y: 14 }

            states: State {
                when: pillolaGioco.opacity > 0
                PropertyChanges { salita.y: 0 }
            }
            transitions: Transition {
                NumberAnimation { target: salita; property: "y"
                                  duration: Theme.Motion.quick
                                  easing.type: Easing.OutCubic }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

            Row {
                anchors.centerIn: parent
                spacing: Theme.Effects.space2

                Ui.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: "play"
                    color: Theme.Colors.accent
                }

                Text {
                    id: testoGioco
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var it = Core.Strings.lang === "it";
                        var n = Core.Gioco.nome;
                        if (Core.Gioco.prestazioni)
                            return it ? "Modalità gioco" + (n ? " · " + n : "")
                                      : "Game mode" + (n ? " · " + n : "");
                        return it ? "Schermo intero: notifiche zitte"
                                  : "Full screen: notifications silenced";
                    }
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: Theme.Typography.weightMedium
                }
            }
        }

        Timer {
            id: viaIlCartello
            interval: 2600
            onTriggered: pillolaGioco.opacity = 0
        }

        Connections {
            target: Core.Gioco
            function onAttivaChanged() {
                if (Core.Gioco.attiva) {
                    pillolaGioco.opacity = 1;
                    viaIlCartello.restart();
                } else {
                    viaIlCartello.stop();
                    pillolaGioco.opacity = 0;
                }
            }
        }
    }

    // ── Menu della finestra attiva ───────────────────────────────────────

    function windowMenuItems() {
        var it = Core.Strings.lang === "it";
        return [
            { "label": it ? "Riduci a icona" : "Minimise",  "icon": "minimize", "action": "minimize" },
            { "label": Core.Windows.activeMaximized
                       ? (it ? "Ripristina" : "Restore")
                       : (it ? "Ingrandisci" : "Maximise"), "icon": "maximize", "action": "maximize" },
            // Qui c'era «Affianca (tiling) / Rendi libera», con la scorciatoia
            // Super+T. Il tiling non esiste più (`core/WindowRules.qml`) e la
            // scorciatoia nemmeno: era una voce che affiancava una finestra in
            // un ambiente che non sa più come rimetterla a posto.
            { "label": it ? "Schermo intero" : "Full screen",
              "icon": "expand", "action": "fullscreen", "shortcut": "Super+F" },
            { "separator": true },
            // L'opzione che spegne i pulsanti sta dove i pulsanti sono: chi li
            // trova d'intralcio ci arriva senza cercarli nelle impostazioni.
            { "label": it ? "Nascondi questi pulsanti" : "Hide these buttons",
              "icon": "close", "action": "hideControls" },
            { "separator": true },
            { "label": it ? "Chiudi la finestra" : "Close the window",
              "icon": "close", "action": "close", "shortcut": "Super+C", "danger": true }
        ];
    }

    ContextMenu {
        id: windowMenu

        onTriggered: function(action) {
            switch (action) {
            case "minimize": Core.Windows.minimize(); break;
            case "maximize":   Core.Windows.toggleMaximize(); break;
            case "fullscreen": Core.Compositore.commutaSchermoIntero(""); break;
            case "close":      Core.Windows.close(); break;
            case "hideControls": Core.Ipc.setSetting("windowControls.enabled", false); break;
            }
        }
    }

    // ── Avvisi delle notifiche ───────────────────────────────────────────

    Toasts { inBasso: root.barraInBasso }

    // Avviso a schermo di volume e luminosità: senza, premere i tasti
    // funzione non produce nessun segno e non si sa se hanno funzionato.
    Osd { id: osd }

    // ── Scrivania: lo sfondo e il tasto destro ───────────────────────────
    //
    // Due superfici, non una. Lo sfondo sta sul livello più basso e non
    // riceve nessun clic; la scrivania sta appena sopra e li riceve tutti.
    // Tenerli separati vuol dire che l'immagine può cambiare in dissolvenza
    // senza toccare la superficie che ascolta il mouse.

    // ── Uno per schermo ──────────────────────────────────────────────────
    //
    // `Variants` costruisce una copia di quello che contiene per ogni voce del
    // modello, e la distrugge quando la voce sparisce. Con
    // `Quickshell.screens` come modello vuol dire: una scrivania per monitor,
    // che compare quando lo si attacca e se ne va quando lo si stacca.
    //
    // Senza, in 35.928 righe di QML non c'era **un solo** `Variants`: barra,
    // dock, sfondo e scrivania erano oggetti singoli, e attaccare un monitor
    // dava un secondo schermo nero. Misurato il 10 agosto 2026 creando un
    // monitor finto con `hyprctl output create headless`: nero, vuoto,
    // nemmeno lo sfondo.
    //
    // `modelData` è lo schermo di questa copia. Va dichiarato `required` sulla
    // copia stessa: è il modo in cui QML sa che quella proprietà la riempie il
    // modello e non un valore di partenza.
    Variants {
        model: Quickshell.screens
        WallpaperLayer {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        DesktopLayer {
            required property var modelData
            screen: modelData
            cartella: root.desktopPath
            onRightClicked: function(x, y) {
                // Il punto si ricorda: «Disposizione icone…» apre un secondo
                // menu, e deve nascere dove è nato il primo.
                root.puntoMenu = Qt.point(x, y);
                desktopMenu.openAt(x, y, root.desktopMenuItems());
            }
            onReleased: function(urls, x, y) {
                root.desktopRiceve(urls, x, y);
            }

            // Le icone della scrivania, su UNO schermo solo: duplicarle su
            // tutti vorrebbe dire due copie della stessa cartella, e
            // spostare un'icona da una parte non la muoverebbe dall'altra.
            // Lo schermo principale è quello con l'origine in (0,0).
            DesktopIcons {
                id: iconeScrivania
                anchors.fill: parent
                visible: modelData.x === 0 && modelData.y === 0
                         && Core.Ipc.get("desktop.icons", true)
                cartella: root.desktopPath
                // Il nome del monitor: da lì si sa quanto si sono presi la
                // barra e la dock, e la griglia comincia sotto la barra
                // invece che dietro.
                monitor: modelData ? modelData.name : ""
                onRicevuti: function(urls, x, y) {
                    root.desktopRiceve(urls, x, y);
                }
                onMenuSu: function(nome, dove) {
                    root.menuIconaScrivania(nome, dove);
                }
                onApriConRichiesto: function(percorso, eseguibile) {
                    sovrapposizioneScrivania.apriCon(percorso, eseguibile);
                }
                onApriCartella: function(percorso) {
                    root.openFiles(percorso);
                }
                Component.onCompleted: root.icone = iconeScrivania
            }
        }
    }

    // ── I widget della scrivania ─────────────────────────────────────────
    //
    // Superficie loro, sopra lo sfondo e sotto le finestre, e non insieme
    // alle icone: il perché sta in cima a `widget/WidgetLayer.qml` — in due
    // parole, il vetro del compositore si mette dietro una superficie intera,
    // e dietro i nomi dei file non lo vogliamo.
    //
    // ── DOPO le icone, e non è un dettaglio ─────────────────────────────
    //
    // Dentro lo stesso piano (Bottom) il compositore mette sopra chi arriva
    // dopo, e le superfici nascono nell'ordine in cui stanno scritte qui.
    // Fino al 13 settembre 2026 questo blocco stava PRIMA di `DesktopLayer`:
    // i widget si vedevano — le icone hanno il fondo trasparente — ma stavano
    // SOTTO, e ogni clic, tasto destro e trascinamento se lo prendeva la
    // superficie delle icone. Giacomo: «non posso fare tasto destro per
    // opzioni […] non sono ridimensionabili». Non era il blocco, non erano
    // le maniglie: era l'ordine di due blocchi in questo file.
    //
    // Su UNO schermo solo, come le icone: duplicarli su tutti vorrebbe dire
    // due copie dello stesso processore, e spostarne uno non muoverebbe
    // l'altro.
    Variants {
        model: Quickshell.screens
        Widget.WidgetLayer {
            required property var modelData
            screen: modelData

            Widget.Widgets {
                anchors.fill: parent
                bloccati: Core.Ipc.get("desktop.widgetBloccati", true)
            }
        }
    }

    /// La finestrella delle icone, per i comandi del menu.
    property var icone: null

    /// Dov'è stato premuto il tasto destro sulla scrivania, in coordinate
    /// dello schermo. Serve al secondo menu, quello della disposizione.
    property point puntoMenu: Qt.point(0, 0)

    /// La cartella della scrivania, come la conosce il demone. Vuota finché
    /// non risponde.
    property string desktopPath: ""

    Connections {
        target: Core.Ipc
        // La scrivania esiste come cartella anche se il file `user-dirs.dirs`
        // non c'è: il demone la ripiega sulla Home. Chi la conosce davvero è
        // lui, e la risposta arriva qui insieme ai posti della barra.
        function onPlacesReceived(payload) {
            var luoghi = payload.places || [];
            for (var i = 0; i < luoghi.length; i++) {
                if (luoghi[i].kind === "desktop" && luoghi[i].path)
                    root.desktopPath = luoghi[i].path;
            }
        }
        function onConnectedChanged() {
            if (Core.Ipc.connected)
                Core.Ipc.fsPlaces();
        }
    }

    /// Il trascinamento arrivato sulla scrivania: gli indirizzi e il punto
    /// in cui si è lasciato. La decisione «copiare o spostare» si chiede
    /// come nel gestore file — il gesto è lo stesso, gli esiti no.
    function desktopRiceve(urls, x, y) {
        var sorgenti = [];
        for (var i = 0; i < urls.length; i++) {
            var u = String(urls[i]);
            if (u.indexOf("file://") !== 0)
                continue;
            sorgenti.push(decodeURIComponent(u.substring(7)));
        }
        if (sorgenti.length === 0 || root.desktopPath === "")
            return;
        // Lasciare una cosa dov'era già: nessuna domanda, nessun esito.
        var utili = [];
        for (var k = 0; k < sorgenti.length; k++) {
            var s = sorgenti[k];
            if (s === root.desktopPath)
                continue;
            var taglio = s.lastIndexOf("/");
            var dentro = taglio <= 0 ? "/" : s.substring(0, taglio);
            if (dentro === root.desktopPath)
                continue;
            utili.push(s);
        }
        if (utili.length === 0)
            return;
        desktopDrop.arrivo = utili;
        var it = Core.Strings.lang === "it";
        var dove = desktopDrop.arrivo.length > 1
                    ? (it ? "la Scrivania" : "the Desktop")
                    : (it ? "la Scrivania" : "the Desktop");
        desktopDropMenu.openAt(x, y, [
            { "label": (it ? "Copia in " : "Copy into ") + dove,
              "icon": "copy", "action": "copia" },
            { "label": (it ? "Sposta in " : "Move into ") + dove,
              "icon": "cut", "action": "sposta" },
            { "separator": true },
            { "label": it ? "Annulla" : "Cancel",
              "icon": "close", "action": "niente" }
        ]);
    }

    /// Quello che sta per arrivare sulla scrivania, in attesa della risposta
    /// sui conflitti.
    property var desktopDrop: ({ "arrivo": [] })
    property var _desktopInAttesa: null

    function trasferisciSullaScrivania(sorgenti, sposta) {
        root._desktopInAttesa = { "sorgenti": sorgenti, "sposta": sposta === true };
        Core.Ipc.fsConflitti(sorgenti, root.desktopPath);
    }

    Connections {
        target: Core.Ipc
        function onConflittiRicevuti(nomi) {
            var a = root._desktopInAttesa;
            if (!a)
                return;
            if (!nomi || nomi.length === 0) {
                root._desktopInAttesa = null;
                Core.Ipc.fsTransfer(a.sorgenti, root.desktopPath, a.sposta, "entrambi");
                return;
            }
            var it = Core.Strings.lang === "it";
            var quali = nomi.length === 1 ? nomi[0]
                        : nomi.length + (it ? " nomi" : " names");
            desktopConflictMenu.openAtCursor([
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
        id: desktopDropMenu
        onTriggered: function(azione) {
            var arrivo = root.desktopDrop.arrivo;
            root.desktopDrop.arrivo = [];
            if (azione !== "copia" && azione !== "sposta")
                return;
            root.trasferisciSullaScrivania(arrivo, azione === "sposta");
        }
    }

    ContextMenu {
        id: desktopConflictMenu
        onTriggered: function(scelta) {
            var a = root._desktopInAttesa;
            root._desktopInAttesa = null;
            if (!a || scelta === "niente")
                return;
            Core.Ipc.fsTransfer(a.sorgenti, root.desktopPath, a.sposta, scelta);
        }
    }

    // ── Il menu su un'icona della scrivania ───────────────────────────────

    function menuIconaScrivania(nome, dove) {
        var it = Core.Strings.lang === "it";
        var voci = [
            { "label": it ? "Apri" : "Open", "icon": "chevron", "action": "apri" }
        ];
        // Su una fotografia posata sulla scrivania, la voce più corta che
        // esista per cambiare lo sfondo: è già lì, si vede, e si sceglie con
        // un clic invece che copiando un percorso dentro le Impostazioni.
        if (root.icone && root.icone.eImmagine(nome))
            voci.push({ "label": it ? "Imposta come sfondo" : "Set as wallpaper",
                        "icon": "image", "action": "sfondo" });
        voci.push({ "separator": true });
        voci.push({ "label": it ? "Rinomina" : "Rename", "icon": "document",
                    "action": "rinomina", "shortcut": "F2" });
        voci.push({ "label": it ? "Condividi…" : "Share…", "icon": "split",
                    "action": "condividi" });
        voci.push({ "label": it ? "Copia il percorso" : "Copy the path",
                    "icon": "clipboard", "action": "percorso" });
        voci.push({ "separator": true });
        voci.push({ "label": it ? "Sposta nel cestino" : "Move to the bin",
                    "icon": "trash", "action": "cestino", "danger": true });
        desktopIconMenu.openAt(dove.x, dove.y, voci);
    }

    ContextMenu {
        id: desktopIconMenu
        onTriggered: function(azione) {
            var ic = root.icone;
            if (!ic)
                return;
            switch (azione) {
            case "apri": {
                var v = ic.voceSelezionata();
                if (v)
                    ic.apri(v);
                break;
            }
            case "sfondo": {
                var f = ic.voceSelezionata();
                if (f && f.path)
                    Core.Wallpaper.scegli(f.path);
                break;
            }
            case "rinomina": ic.iniziaRinomina(); break;
            case "percorso": ic.copiaPercorso(); break;
            case "condividi": {
                var v = ic.voceSelezionata();
                if (v)
                    sovrapposizioneScrivania.condividi([v.path]);
                break;
            }
            case "cestino":  ic.cestina(); break;
            }
        }
    }

    // ── Le finestrelle della scrivania ────────────────────────────────────
    //
    // «Condividi…» e «Apri con…» sono due `Rectangle` a schermo intero che
    // dentro un'applicazione stanno nella finestra dell'applicazione. La
    // scrivania una finestra così non ce l'ha: il suo livello — `minerva-desktop`
    // — sta in fondo a tutto (`hyprctl layers`: «Layer level 1 (bottom)»), che
    // è giusto, perché la scrivania DEVE stare dietro alle finestre.
    //
    // Mettercele dentro le disegnava lì: sotto ogni finestra aperta, e senza
    // poter prendere un tasto. Nessun errore, nessun avviso — il pannello si
    // apriva davvero, semplicemente non lo vedeva nessuno. E quando lo schermo
    // era sgombro funzionava, che è il modo peggiore di rompersi.
    //
    // Questa è la superficie che mancava: stessa ricetta di `ContextMenu`,
    // livello di sovrapposizione e tastiera a richiesta. Resta spenta finché
    // non serve, quindi non si mangia i clic della scrivania.
    PanelWindow {
        id: sovrapposizioneScrivania

        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "quickshell"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Come in `ContextMenu`: senza, il livello viene spinto sotto la zona
        // esclusiva della barra e le coordinate del mouse risultano sfalsate
        // di tutta la sua altezza.
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: false

        function condividi(percorsi) {
            sovrapposizioneScrivania.visible = true;
            condividiScrivania.apri(percorsi);
        }

        function apriCon(percorso, eseguibile) {
            sovrapposizioneScrivania.visible = true;
            apriConScrivania.apri(percorso, eseguibile);
        }

        /// Si spegne solo quando NESSUNO dei due è più acceso: spegnerla al
        /// primo `chiuso()` la porterebbe via da sotto l'altro.
        function _forseSpegni() {
            if (!condividiScrivania.visible && !apriConScrivania.visible)
                sovrapposizioneScrivania.visible = false;
        }

        Ui.Condividi {
            id: condividiScrivania
            onChiuso: sovrapposizioneScrivania._forseSpegni()
        }

        Ui.ApriCon {
            id: apriConScrivania
            onChiuso: sovrapposizioneScrivania._forseSpegni()
            onEseguiRichiesto: function (percorso) {
                if (root.icone)
                    root.icone.eseguiNelTerminale(percorso);
            }
            onEseguibileRichiesto: function (percorso) {
                if (root.icone)
                    root.icone.rendiEseguibileOra(percorso);
            }
        }
    }

    /// Voci del menu della scrivania. Ricostruite a ogni apertura perché le
    /// etichette dipendono dalla lingua corrente.
    /// La voce che sblocca e riblocca i widget. Una sola, in due posti: il
    /// menù della scrivania e quello della barra. Scriverla due volte
    /// vorrebbe dire due frasi che un giorno dicono cose diverse.
    function vocePersonalizza() {
        var it = Core.Strings.lang === "it";
        var bloccati = Core.Ipc.get("desktop.widgetBloccati", true);
        return bloccati
            ? { "label": it ? "Personalizza scrivania" : "Customise desktop",
                "icon": "window", "action": "personalizza" }
            : { "label": it ? "Fatto: riblocca i widget" : "Done: lock the widgets",
                "icon": "lock", "action": "personalizza" };
    }

    /// Il menù del tasto destro sulla BARRA. Corto di proposito: la barra non
    /// è la scrivania, e un menù con dentro «Spegni» che si apre cliccando di
    /// fianco all'orologio è un modo di spegnere il computer per sbaglio.
    function barraMenuItems() {
        var S = Core.Strings;
        var it = Core.Strings.lang === "it";
        return [
            root.vocePersonalizza(),
            { "label": it ? "Scrivania pulita" : "Clean desktop",
              "icon": "image", "action": "pulita" },
            { "separator": true },
            { "label": S.t("settings"), "icon": "settings", "action": "settings",
              "shortcut": "Super+I" }
        ];
    }

    function desktopMenuItems() {
        var S = Core.Strings;
        var it = Core.Strings.lang === "it";
        var items = [
            { "label": S.t("apps"),        "icon": "apps",      "action": "apps",     "shortcut": "Super+A" },
            { "label": S.t("newTerminal"), "icon": "terminal",  "action": "terminal", "shortcut": "Super+↵" },
            { "label": S.t("openFiles"),   "icon": "folder",    "action": "files",    "shortcut": "Super+E" },
            { "label": S.t("openBrowser"), "icon": "globe",     "action": "browser",  "shortcut": "Super+B" },
            { "separator": true },
            { "label": S.t("shortcuts"),   "icon": "keyboard",  "action": "cheatsheet", "shortcut": "F1" },
            { "label": S.t("settings"),    "icon": "settings",  "action": "settings",   "shortcut": "Super+I" },
            { "label": it ? "Cambia sfondo…" : "Change wallpaper…",
              "icon": "image", "action": "wallpaper" }
        ];

        // «Il prossimo sfondo» si aggiunge solo se c'è davvero un mazzo che
        // gira: con una sola immagine scelta a mano sarebbe una voce che non
        // fa niente, e una voce che non fa niente è peggio di una che manca.
        if (Core.Wallpaper.pool.length > 1)
            items.push({ "label": it ? "Il prossimo sfondo" : "Next wallpaper",
                         "icon": "shuffle", "action": "wallpaperNext" });

        // «Disposizione icone» sta accanto a «Cambia sfondo»: sono le due
        // cose che riguardano l'aspetto della scrivania, e chi cerca l'una
        // guarda dov'è l'altra. Solo se le icone ci sono, però: con la
        // scrivania spenta sarebbe un menu di regolazioni per una cosa che non
        // si vede.
        if (Core.Ipc.get("desktop.icons", true))
            items.push({ "label": it ? "Disposizione icone…" : "Icon arrangement…",
                         "icon": "grid", "action": "disposizione" });

        // ── «Personalizza scrivania» ──────────────────────────────────
        //
        // Sblocca i widget: da lì in poi si trascinano, si ridimensionano e
        // col tasto destro si tolgono. Sbloccati la voce cambia in «Fatto»,
        // perché il gesto che serve dopo è chiuderla — un interruttore che si
        // apre e non si chiude si dimentica aperto.
        //
        // Sta anche nel tasto destro sulla BARRA, che è dove Giacomo l'ha
        // chiesta: «tranne il caso in cui io decida di sbloccarli via tasto
        // destro sulla barra e cliccare personalizza desktop».
        items.push({ "separator": true });
        items.push(root.vocePersonalizza());
        items.push({ "separator": true });
        items.push({ "label": S.t("lockScreen"), "icon": "lock",  "action": "lock", "shortcut": "Super+L" });
        items.push({ "label": S.t("power"),      "icon": "power", "action": "power", "danger": true });
        return items;
    }

    ContextMenu {
        id: desktopMenu

        onTriggered: function(action) {
            switch (action) {
            case "apps":       root.pannello("apps"); break;
            case "terminal":   root.run([Core.Ipc.get("launcher.defaultTerminal", "minerva-terminale")]); break;
            case "files":      root.openFiles(); break;
            case "browser":    root.run(["firefox"]); break;
            case "cheatsheet": root.toggleCheatsheet(); break;
            case "settings":   root.openSettings(); break;
            case "personalizza":
                Core.Ipc.setSetting("desktop.widgetBloccati",
                    !Core.Ipc.get("desktop.widgetBloccati", true));
                break;
            case "pulita":
                Core.Ipc.setSetting("desktop.puliti",
                    !Core.Ipc.get("desktop.puliti", false));
                break;
            case "disposizione":
                // Un istante dopo: il menu che si sta chiudendo e quello che
                // si apre sono due superfici, e aprire la seconda mentre la
                // prima si sta ancora smontando la fa nascere senza fuoco.
                apriDisposizione.restart();
                break;
            case "wallpaper":     root.openSettings("appearance"); break;
            case "wallpaperNext": Core.Wallpaper.next(1); break;
            case "lock":       root.run(["minerva-blocca"]); break;
            case "power":      root.pannello("power"); break;
            }
        }
    }

    // ── La disposizione delle icone ──────────────────────────────────────
    //
    // Le voci e i comandi li sa `DesktopIcons`, che è l'unico posto in cui si
    // sa che cosa è acceso adesso. La shell mette solo il menu, perché il menu
    // è una superficie a schermo intero e quelle stanno qui.

    Timer {
        id: apriDisposizione
        interval: Theme.Motion.exit
        onTriggered: {
            if (!root.icone)
                return;
            disposizioneMenu.openAt(root.puntoMenu.x, root.puntoMenu.y,
                                    root.icone.vociDisposizione());
        }
    }

    ContextMenu {
        id: disposizioneMenu
        onTriggered: function(azione) {
            if (root.icone)
                root.icone.eseguiDisposizione(azione);
        }
    }

    // ── Pannelli a schermo intero ────────────────────────────────────────
    //
    // Caricati alla prima apertura e scaricati alla chiusura: restano fuori
    // dalla memoria finché non servono, e non c'è modo che un pannello chiuso
    // continui a interrogare il sistema in sottofondo.

    Loader {
        id: cheatsheetLoader
        active: false
        source: "help/Cheatsheet.qml"
        onLoaded: item.requestClose.connect(function() {
            cheatsheetLoader.active = false;
            Core.Overlays.release("cheatsheet");
        })
    }

    function toggleCheatsheet() {
        if (!Core.Ipc.get("cheatsheet.enabled", true))
            return;
        if (cheatsheetLoader.active && cheatsheetLoader.item)
            cheatsheetLoader.item.close();
        else {
            Core.Overlays.claim("cheatsheet");
            cheatsheetLoader.active = true;
        }
    }

    // Le impostazioni sono una finestra vera e non una sovrapposizione: si
    // tengono aperte accanto a ciò che si sta regolando. Un pannello che copre
    // tutto costringe a chiudere e riaprire a ogni tentativo.
    /// Apre le Impostazioni, eventualmente su una sezione precisa.
    ///
    /// Non stanno più qui dentro: sono un programma a sé
    /// (`minerva-shell/settings.qml`, avviato da `minerva-settings`), per gli
    /// stessi motivi del gestore file — e per uno in più, che è che le
    /// Impostazioni sono la finestra in cui si toccano i valori, cioè quella
    /// in cui è più facile romperne uno.
    function openSettings(section) {
        var cmd = [root.minervaRoot + "/scripts/minerva-settings"];
        if (section && section !== "")
            cmd.push(section);
        root.run(cmd);
    }

    // Ricerca universale. È la finestra che si apre più spesso di ogni altra,
    // quindi resta l'unica cosa che la shell tiene già caricata: mezzo secondo
    // di attesa su Super+Spazio si nota, su qualunque altro pannello no.
    Loader {
        id: paletteLoader
        active: false
        source: "search/Palette.qml"
        onLoaded: {
            item.requestClose.connect(function() {
                paletteLoader.active = false;
                Core.Overlays.release("palette");
            });
            item.commandRequested.connect(root.runCommand);
        }
    }

    function openPalette() {
        Core.Overlays.claim("palette");
        paletteLoader.active = true;
    }

    // ── Gestore file ─────────────────────────────────────────────────────
    //
    // Non sta più qui dentro. È un programma a sé —
    // `minerva-shell/filemanager.qml`, avviato da `minerva-files` — e la shell
    // lo lancia come lancerebbe Firefox.
    //
    // Era una finestra della shell, ed è stato il primo pezzo a uscire. Il
    // motivo non è l'eleganza: finché stava qui, una riga sbagliata
    // nell'elenco dei file spegneva barra, dock e scrivania insieme a lui, e
    // spegneva anche la maniglia con cui rimediare. Adesso un errore nel
    // gestore file chiude il gestore file.
    //
    // Il prezzo è mezzo secondo di avvio la prima volta, e due processi invece
    // di uno. Il guadagno è che l'ambiente non dipende più dall'assenza di
    // errori nella parte che si tocca di più.

    /// Dove sta Minerva sul disco. Da qui si ricavano gli script: lo dice
    /// Quickshell, non è scritto da nessuna parte.
    readonly property string minervaRoot: {
        var dir = String(Quickshell.shellDir);
        if (dir.indexOf("file://") === 0)
            dir = dir.substring(7);
        // `shellDir` è la cartella di shell.qml, cioè `minerva-shell`: la
        // radice del progetto è quella sopra.
        var cut = dir.lastIndexOf("/");
        return cut > 0 ? dir.substring(0, cut) : dir;
    }

    // ── Le app che l'utente vuole trovare pronte ─────────────────────────
    //
    // Le accende una alla volta, e solo quelle chieste. Il perché lo faccia la
    // shell — e non l'avvio del compositore, che pure lancia il gestore file —
    // sta scritto in `core/AppPronte.qml`.
    Core.AppPronte {
        radice: root.minervaRoot
    }

    // ── Schermate ────────────────────────────────────────────────────────
    //
    // `grim` fotografa anche i pannelli di Minerva: se si scattasse nello
    // stesso istante in cui si sceglie «tutto lo schermo», nella fotografia
    // ci sarebbe il pannello che l'ha chiesta. Perciò si chiude prima e si
    // aspetta che l'animazione di chiusura sia finita davvero — scattare a
    // metà lascia un fantasma semitrasparente in un angolo.
    //
    // L'attesa sta QUI e non nel pannello perché il pannello, chiudendosi,
    // viene scaricato: un timer dentro di lui muore prima di suonare.

    Timer {
        id: schermata
        property string modo: "schermo"
        property int ritardo: 0
        // La durata dell'animazione dei pannelli, più un fotogramma.
        interval: Theme.Motion.panel + 120
        onTriggered: root.run([root.minervaRoot + "/scripts/minerva-schermata",
                               schermata.modo, String(schermata.ritardo)])
    }

    function scattaSchermata(modo, ritardo) {
        root.chiudiPannelli();
        schermata.modo = modo || "schermo";
        schermata.ritardo = ritardo || 0;
        schermata.restart();
    }

    function openFiles(path) {
        var where = path || "";
        var cmd = [root.minervaRoot + "/scripts/minerva-files"];
        if (where !== "")
            cmd.push(where);
        root.run(cmd);
    }

    /// Il gestore attività. Come il gestore file: uno script che, se il
    /// programma è già aperto, lo porta davanti invece di aprirne un secondo.
    function openMonitor() {
        root.run([root.minervaRoot + "/scripts/minerva-monitor"]);
    }

    /// Azioni chieste dalla ricerca universale per nome.
    function runCommand(id) {
        switch (id) {
        case "settings":   root.openSettings(); break;
        case "wallpaper":  root.openSettings("appearance"); break;
        case "display":    root.openSettings("display"); break;
        case "power":      root.openSettings("power"); break;
        case "audio":      root.openSettings("audio"); break;
        case "network":    root.openSettings("network"); break;
        case "bluetooth":  root.openSettings("bluetooth"); break;
        case "defaults":   root.openSettings("defaults"); break;
        case "cheatsheet": root.toggleCheatsheet(); break;
        case "clipboard":  root.apriPannello("clipboard"); break;
        case "files":      root.openFiles(); break;
        case "lock":       root.run(["minerva-blocca"]); break;
        case "suspend":    if (!Quickshell.env("MINERVA_PROVA")) Core.Compositore._nostro("sospendi", []); break;
        case "reboot":     root.run(["systemctl", "reboot"]); break;
        case "poweroff":   root.run(["systemctl", "poweroff"]); break;
        }
    }

    // ── Primo avvio ──────────────────────────────────────────────────────
    //
    // Al primo accesso della sessione le scorciatoie si mostrano da sole: è il
    // modo più diretto per far scoprire l'ambiente a chi non l'ha mai visto.
    // Si disattiva dalle Impostazioni.

    // «Primo accesso» vuol dire una volta per SESSIONE, non una volta per
    // avvio della shell. Tenere il conto in una proprietà era un difetto: la
    // proprietà nasce con il processo, e ogni volta che la shell si riavvia —
    // per un aggiornamento, per una modifica, per un errore — il pannello
    // ricompariva come se fosse la prima volta. Dà molto fastidio, giustamente.
    //
    // Il segno sta in $XDG_RUNTIME_DIR, che il sistema svuota all'uscita dalla
    // sessione: è esattamente la durata che serve, e non lascia niente in giro.
    property bool firstRunShown: false

    Process {
        id: firstRunMark
        command: ["sh", "-c",
                  "f=\"${XDG_RUNTIME_DIR:-/tmp}/minerva-cheatsheet-shown\"; " +
                  "[ -e \"$f\" ] && echo gia || { : > \"$f\"; echo prima; }"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.firstRunShown = true;
                if (text.trim() !== "prima")
                    return;
                if (Core.Ipc.get("cheatsheet.enabled", true)
                        && Core.Ipc.get("cheatsheet.showOnFirstRun", true))
                    root.toggleCheatsheet();
            }
        }
    }

    Timer {
        id: firstRunTimer
        interval: 1500
        running: false
        onTriggered: {
            if (root.firstRunShown)
                return;
            firstRunMark.running = true;
        }
    }

    Connections {
        target: Core.Ipc
        // Si aspettano le impostazioni vere prima di decidere: partire dai
        // valori di ripiego mostrerebbe il pannello anche a chi l'ha spento.
        function onSettingsReceived() {
            if (!root.firstRunShown && !firstRunTimer.running)
                firstRunTimer.start();
        }
    }

    // ── Il touchpad: qui si APPLICA, la preferenza sta nel demone ────────
    //
    // Vedi `core/SystemState.qml` per il perché la scelta la scrive chiunque
    // e la esegue solo la shell. Qui c'è la parte che tocca il compositore:
    // trovare il dispositivo, e riscriverne lo stato quando la preferenza
    // cambia — da qualunque parte sia cambiata.
    //
    // Il nome NON si scrive a mano: `elan0504:01-04f3:312a-touchpad` è vero
    // su questa macchina e su nessun'altra. Si chiede a Hyprland e si tiene
    // il primo dispositivo di puntamento il cui nome finisce per «touchpad».
    property string touchpadName: ""

    Connections {
        target: Core.Compositore

        // ── Il menu del tasto destro, chiesto dal PLUGIN ──────────────────
        //
        // Quando le barre le disegna il compositore, `spine/TitleBars.qml` è
        // spenta — ed è lei che porta `onMenuRequested`. Il risultato era che
        // sulla configurazione normale di Minerva il tasto destro sulla barra
        // del titolo non faceva niente, e questo menu, che esiste da sempre,
        // era irraggiungibile dal posto dove tutti lo cercano.
        //
        // Il plugin manda `minervamenu>>x,y` (`plugins/minerva-bars/src/barra.cpp`)
        // e il menu lo apre chi lo sa fare: la shell. Stesso canale del
        // trascinamento (`minervadrag`), che passa di qui da agosto.
        //
        // Le voci agiscono sulla finestra ATTIVA, e il fuoco glielo ha già
        // dato il plugin prima di mandare l'evento: qui non si tocca, o si
        // rischia di spostarlo mentre il menu si apre.
        function onEvento(nome, dati) {
            if (nome !== "minervamenu")
                return;
            var p = String(dati || "").split(",");
            if (p.length !== 2)
                return;
            var x = parseInt(p[0]);
            var y = parseInt(p[1]);
            if (isNaN(x) || isNaN(y))
                return;
            windowMenu.openAt(x, y, root.windowMenuItems());
        }

        function onRisposta(cosa, text) {
            if (cosa !== "dispositivi")
                return;
            // Chi sia il touchpad lo dicono i due compositori in due modi
            // diversi, e la traduzione sta dove stanno tutte le altre — in
            // `core/Compositore.qml`. Qui basta il nome.
            var nome = Core.Compositore.touchpadDaTesto(text);
            if (nome === "")
                return;
            root.touchpadName = nome;
            // Il compositore riparte sempre col touchpad acceso: se l'avevi
            // spento, qui si rimette come l'avevi lasciato.
            root.applicaTouchpad();
        }

        // ── Il coperchio del portatile ──────────────────────────────────
        //
        // Il compositore riferisce il FATTO — il coperchio è chiuso — e la
        // politica sta qui, dove sta già quella dei tasti di accensione.
        //
        // Sotto Hyprland lo stesso fatto arriva per un'altra strada
        // (`bindl = , switch:on:Lid Switch`, scritta da `Power.qml`), e la
        // scelta è la stessa impostazione: `power.lidAction`. Due strade, una
        // politica — o il coperchio farebbe due cose diverse a seconda della
        // sessione, e nessuno capirebbe quale delle due è quella giusta.
        function onCoperchio(chiuso) {
            if (!chiuso)
                return;
            var azione = Core.Ipc.get("power.lidAction", "suspend");

            // ── E la guardia che non si discute ─────────────────────────
            //
            // Dentro una prova non si sospende, mai. È la regola scritta il
            // 24 luglio: «altrimenti ti perdo». Una macchina che si addormenta
            // in mezzo a una prova non è un difetto da guardare dopo — è una
            // macchina che non risponde più, e da lì non si torna scrivendo
            // codice.
            //
            // Qui il fatto arriva da un interruttore fisico, quindi in una
            // prova annidata non scatta comunque. La riga c'è lo stesso:
            // costa nulla, e le regole che valgono «tanto non può capitare»
            // sono quelle che un giorno capitano.
            if (Quickshell.env("MINERVA_PROVA")) {
                console.log("[MINERVA] Coperchio chiuso, ma siamo in prova: "
                            + "non faccio «" + azione + "».");
                return;
            }

            if (azione === "suspend")
                Core.Compositore._nostro("sospendi", []);
            else if (azione === "lock")
                root.run(["minerva-blocca"]);
            // Terzo caso: niente. Ed è un caso vero, non un buco — c'è chi
            // chiude il coperchio e vuole che il computer continui a
            // scaricare.
        }

        // ── Quando ti allontani ─────────────────────────────────────────
        //
        // Il compositore conta e annuncia; la politica è qui, accanto a
        // quella del coperchio e per la stessa ragione. Fino al 1º settembre
        // 2026 questo mestiere era di `hypridle`: un programma di un altro
        // ambiente, con un file di configurazione suo che il pannello Energia
        // riscriveva e poi riavviava a ogni cursore trascinato.
        //
        // Il numero che arriva è la SOGLIA che è scattata, non il tempo vero:
        // così si sa quale delle tre è, senza riconoscerla a occhio. E si
        // confrontano tutte e tre, non una: chi mette «blocca» e «sospendi»
        // allo stesso minuto deve vedere succedere tutte e due le cose.
        function onInattivo(secondi) {
            if (Quickshell.env("MINERVA_PROVA")) return;
            if (secondi === root.sogliaDim && root.sogliaDim > 0
                    && !root.luceAbbassata) {
                root.luceAbbassata = true;
                root.run(["brightnessctl", "-s", "set", "20%"]);
            }
            if (secondi === root.sogliaBlocco && root.sogliaBlocco > 0)
                root.run(["minerva-blocca"]);
            if (secondi === root.sogliaSospensione
                    && root.sogliaSospensione > 0) {
                // ── La riga che non si discute ──────────────────────────
                //
                // Dentro una prova non si sospende, mai. «Altrimenti ti
                // perdo», scritto il 24 luglio 2026. E qui, a differenza del
                // coperchio, il caso NON è impossibile: una prova annidata
                // che resta ferma qualche minuto arriva a questa riga da
                // sola.
                if (Quickshell.env("MINERVA_PROVA")) {
                    console.log("[MINERVA] Inattivo da " + secondi
                                + "s, ma siamo in prova: non sospendo.");
                    return;
                }
                Core.Compositore._nostro("sospendi", []);
            }
        }

        function onAttivo() {
            if (!root.luceAbbassata)
                return;
            root.luceAbbassata = false;
            // `-r` rimette quella salvata da `-s`. Se non c'era niente da
            // rimettere non fa niente, e va bene: è il caso di chi ha
            // «abbassa la luce» spento.
            root.run(["brightnessctl", "-r"]);
        }
    }

    /// Com'è messa la dock, per l'IPC `minerva dock`. Le scrive la dock
    /// stessa: vedi il blocco `Dock { }` più sotto.
    property string dockModo: "sempre"
    property bool dockVisibile: true
    /// Il puntatore è sopra la dock: è la ragione per cui una dock che
    /// dovrebbe nascondersi resta dov'è, ed è giusto che resti.
    property bool dockSottoIlDito: false

    // ── Le tre soglie, in secondi ────────────────────────────────────────
    //
    // Stanno nelle impostazioni in MINUTI, perché è come si mostrano nel
    // pannello; il compositore ragiona in secondi. Zero vuol dire «mai», e
    // «mai» si dice non mandando quel numero — non mandandone uno enorme, che
    // prima o poi scatta.
    readonly property int sogliaDim: Core.Ipc.get("power.dimAfter", 5) * 60
    readonly property int sogliaBlocco: Core.Ipc.get("power.lockAfter", 10) * 60
    readonly property int sogliaSospensione:
        Core.Ipc.get("power.suspendAfter", 30) * 60

    /// Se la luce è stata abbassata da noi. Senza, `brightnessctl -r`
    /// partirebbe a ogni ritorno all'attività e rimetterebbe una luminosità
    /// salvata chissà quando — anche a chi nel frattempo l'ha cambiata a mano.
    property bool luceAbbassata: false

    function applicaInattivita() {
        // Si dice, e non è chiacchiera: una sorveglianza che non è stata
        // chiesta è indistinguibile da una che non funziona — lo schermo non
        // si blocca, e non c'è niente da guardare. L'altra metà del controllo
        // è il campo `inattivita` nella risposta a `stato` del compositore.
        console.debug("[MINERVA] Inattività: chiedo le soglie "
                      + root.sogliaDim + " " + root.sogliaBlocco + " "
                      + root.sogliaSospensione + " (canale aperto: "
                      + Core.Compositore.canaleAperto + ")");
        Core.Compositore.sorvegliaInattivita([root.sogliaDim,
                                              root.sogliaBlocco,
                                              root.sogliaSospensione]);
    }

    // Le soglie si mandano quando cambiano E quando il canale si apre. Due
    // occasioni e non una, perché sono due eventi indipendenti: le
    // impostazioni possono arrivare prima del canale o dopo, e una sola delle
    // due mani lascerebbe la sorveglianza spenta per tutta la sessione. È lo
    // stesso difetto che il 1º settembre 2026 ha lasciato il touchpad senza
    // tap-to-click per otto ore — vedi `core/Compositore.qml`.
    onSogliaDimChanged: root.applicaInattivita()
    onSogliaBloccoChanged: root.applicaInattivita()
    onSogliaSospensioneChanged: root.applicaInattivita()

    Connections {
        target: Core.Compositore
        function onCanaleApertoChanged() {
            if (Core.Compositore.canaleAperto) {
                root.applicaInattivita();
                root.applicaRisparmio();
            }
        }
    }

    // ── Il modo risparmio ────────────────────────────────────────────────
    //
    // La regola la manda la shell, la decisione la prende il compositore
    // (`compositore/src/energia.h`): a batteria bassa abbassa gli effetti da
    // sé anche se questa shell è ferma. Stesse due occasioni delle soglie
    // qui sopra: quando cambia e quando il canale si apre.
    readonly property string risparmioModo: Core.Ipc.get("power.risparmioEffetti", "auto")
    readonly property int risparmioSoglia: Core.Ipc.get("power.risparmioSoglia", 20)
    onRisparmioModoChanged: root.applicaRisparmio()
    onRisparmioSogliaChanged: root.applicaRisparmio()

    function applicaRisparmio() {
        Core.Compositore.regolaRisparmio(root.risparmioModo, root.risparmioSoglia);
    }

    // E si DICE. Un blur che si spegne da solo, senza una parola, sembra
    // un guasto — ed è la prima cosa che uno va a «riparare» nelle
    // Impostazioni. Non si dice quando l'ha chiesto chi guarda («sempre»):
    // lo sa già.
    property bool _risparmioDetto: false
    Connections {
        target: Core.Compositore
        function onRisparmioCambiato() {
            var r = Core.Compositore.risparmio || {};
            var it = Core.Strings.lang === "it";
            if (r.attivo && (r.motivo === "batteria" || r.motivo === "profilo")) {
                root._risparmioDetto = true;
                Core.Notifications.daMinerva(
                    it ? "Effetti ridotti per risparmiare" : "Effects reduced to save power",
                    (r.motivo === "batteria"
                        ? (it ? "Batteria al " + r.percento + " %. "
                              : "Battery at " + r.percento + "%. ")
                        : (it ? "Profilo «risparmio energetico». "
                              : "Power saver profile. "))
                    + (it ? "Niente sfocatura né trasparenza, cornice ferma, finestre "
                            + "senza elastico: tornano da soli."
                          : "No blur or transparency, still border, no wobble: "
                            + "they come back on their own."));
            } else if (!r.attivo && root._risparmioDetto) {
                root._risparmioDetto = false;
                Core.Notifications.daMinerva(
                    it ? "Effetti di nuovo pieni" : "Effects back to full",
                    it ? "Il risparmio è finito." : "Power saving is over.");
            }
        }
    }

    function applicaTouchpad() {
        if (root.touchpadName === "")
            return;
        Core.Compositore.dispositivoAcceso(root.touchpadName,
                                           Core.SystemState.touchpadOn);
    }

    Connections {
        target: Core.SystemState
        function onTouchpadOnChanged() { root.applicaTouchpad(); }
    }

    // ── Scorciatoie globali, dichiarate in keybinds.conf ─────────────────

    Core.Scorciatoia {
        name: "launcher"
        onPressed: {
            if (paletteLoader.active && paletteLoader.item)
                paletteLoader.item.close();
            else
                root.openPalette();
        }
    }

    // ── Alt+Tab ──────────────────────────────────────────────────────────
    //
    // Tre scorciatoie per un gesto solo, e servono tutte e tre: Hyprland manda
    // un evento alla PRESSIONE di una combinazione, non al rilascio di un
    // modificatore. Il rilascio di Alt arriva come `bindr` su `Alt_L`, ed è
    // quello che chiude la scelta — senza, il riquadro resterebbe aperto
    // finché non si preme altro.
    Core.Scorciatoia {
        // Centra il BLOCCO VISIBILE, barra del titolo compresa. Il
        // `centerwindow` del compositore centrava la finestra e basta, e il
        // risultato stava ventun pixel più in basso — vedi `Windows.centra`.
        name: "centrawindow"
        onPressed: Core.Windows.centra("")
    }

    Core.Scorciatoia {
        name: "maximize"
        onPressed: Core.Windows.toggleMaximize()
    }

    Core.Scorciatoia {
        name: "showdesktop"
        onPressed: Core.Windows.mostraScrivania()
    }

    Core.Scorciatoia {
        name: "switcher"
        onPressed: selettore.avanti()
    }

    Core.Scorciatoia {
        name: "switcherprev"
        onPressed: selettore.indietro()
    }

    // ── Il rilascio arriva come RILASCIO, non come pressione ─────────────
    //
    // Una scorciatoia dichiarata con `bindr` non manda un «premuto»: manda un
    // «lasciato». Sono due segnali diversi del protocollo delle scorciatoie
    // globali, e scritto solo `onPressed` non scattava niente — il selettore
    // restava aperto sullo schermo dopo aver mollato Alt, e la finestra scelta
    // non prendeva il fuoco.
    //
    // Si ascoltano tutti e due: costa una riga, e se un domani il bind
    // diventasse una pressione continuerebbe a funzionare.
    Core.Scorciatoia {
        name: "switchercommit"
        onPressed: selettore.conferma()
        onReleased: selettore.conferma()
    }

    Core.Scorciatoia {
        name: "switchercancel"
        onPressed: selettore.annulla()
    }

    Core.Scorciatoia {
        name: "appmenu"
        onPressed: root.apriSottomarino()
    }

    Core.Scorciatoia {
        name: "cheatsheet"
        onPressed: root.toggleCheatsheet()
    }

    Core.Scorciatoia {
        name: "settings"
        onPressed: root.openSettings()
    }

    Core.Scorciatoia {
        name: "clipboard"
        onPressed: root.pannello("clipboard")
    }

    Core.Scorciatoia {
        name: "notifications"
        onPressed: root.pannello("notifications")
    }

    Core.Scorciatoia {
        name: "control"
        onPressed: root.pannello("control")
    }

    // Stamp non scatta: CHIEDE. Prima faceva una cosa sola e la faceva subito
    // — tutto lo schermo, adesso — e il resto delle volte si fotografavano
    // tre finestre per mostrarne una. Le scorciatoie dirette restano per chi
    // sa già cosa vuole (Maiusc+Stamp una porzione, Super+Stamp la finestra).
    Core.Scorciatoia {
        name: "schermata"
        onPressed: root.pannello("schermata")
    }

    Core.Scorciatoia {
        name: "minimized"
        onPressed: root.pannello("minimized")
    }

    Core.Scorciatoia {
        name: "power"
        onPressed: root.pannello("power")
    }

    // ── Comandi sulla finestra attiva, anche da tastiera ─────────────────
    //
    // I tre pulsanti nella barra hanno il loro equivalente qui: chi li spegne
    // dalle Impostazioni non perde le funzioni, solo i pulsanti.

    Core.Scorciatoia {
        name: "minimizewindow"
        onPressed: Core.Windows.minimize()
    }

    // I tasti della luminosità passano di qui invece di chiamare
    // `brightnessctl` da soli. Non è pignoleria: se li lancia Hyprland, la
    // shell scopre che la luminosità è cambiata solo al giro di lettura
    // successivo, e l'avviso a schermo compare in ritardo con il valore
    // sbagliato. Il volume no: quello lo racconta PipeWire nell'istante in
    // cui cambia, da qualunque parte arrivi.

    // Anche il volume passa di qui, e per un motivo preciso: `pactl +5%` non
    // conosce nessun tetto, e premendo il tasto abbastanza volte si arrivava
    // al 500% — amplificazione vera, suono gracchiante, e nessuno che si
    // opponesse. Passando dalla shell il limite c'è.

    Core.Scorciatoia {
        name: "volumeup"
        onPressed: Core.SystemState.stepVolume(5)
    }

    Core.Scorciatoia {
        name: "volumedown"
        onPressed: Core.SystemState.stepVolume(-5)
    }

    Core.Scorciatoia {
        name: "volumemute"
        onPressed: Core.SystemState.toggleMute()
    }

    Core.Scorciatoia {
        name: "brightnessup"
        onPressed: Core.SystemState.stepBrightness(5)
    }

    Core.Scorciatoia {
        name: "brightnessdown"
        onPressed: Core.SystemState.stepBrightness(-5)
    }

    // ── Il lettore ───────────────────────────────────────────────────────
    //
    // Passano di qui e non da `playerctl` — che oltretutto non era nemmeno
    // installato, quindi questi tre tasti erano morti — perché la scelta di
    // QUALE lettore comandare è una decisione, non un dettaglio: la fa
    // `Core.Media` e la ricorda. Vedi il commento in `keybinds.conf`.
    //
    // Quando non c'è nessun lettore il tasto lo DICE. È la stessa regola dei
    // tasti Fn qui sotto: un tasto che non fa niente in silenzio sembra
    // rotto, e chi lo preme prova a premerlo più forte.

    Core.Scorciatoia {
        name: "mediaplay"
        onPressed: {
            if (!root.avvisaSeNienteSuona())
                Core.Media.riproduci();
        }
    }

    Core.Scorciatoia {
        name: "medianext"
        onPressed: {
            if (root.avvisaSeNienteSuona())
                return;
            if (Core.Media.attivo.canGoNext)
                Core.Media.successivo();
            else
                osd.say(Core.Strings.lang === "it" ? "Non ha un brano successivo"
                                                   : "No next track", "music");
        }
    }

    Core.Scorciatoia {
        name: "mediaprev"
        onPressed: {
            if (root.avvisaSeNienteSuona())
                return;
            if (Core.Media.attivo.canGoPrevious)
                Core.Media.precedente();
            else
                osd.say(Core.Strings.lang === "it" ? "Non ha un brano precedente"
                                                   : "No previous track", "music");
        }
    }

    Core.Scorciatoia {
        name: "mediastop"
        onPressed: {
            if (!root.avvisaSeNienteSuona())
                Core.Media.ferma();
        }
    }

    /// Vero se non c'è niente da comandare — e in quel caso lo ha già detto.
    function avvisaSeNienteSuona() {
        if (Core.Media.attivo !== null)
            return false;
        osd.say(Core.Strings.lang === "it" ? "Nessun lettore aperto"
                                           : "No player open", "music");
        return true;
    }

    // ── I tasti Fn che non dicevano niente ───────────────────────────────
    //
    // Volume e luminosità avevano il loro segno a schermo; il touchpad e il
    // muto del microfono no. Il microfono era pure già legato — a `pactl`,
    // direttamente — quindi funzionava e sembrava rotto: premi, non succede
    // niente di visibile, e non hai modo di sapere se il microfono è aperto o
    // chiuso. È il difetto peggiore dei due, perché riguarda la privacy.
    //
    // Adesso passano tutti e due dalla shell, che è l'unica che sa disegnare.

    // ── Accendi, spegni, inverti: sono TRE cose, non una ─────────────────
    //
    // I tre tasti (`XF86TouchpadOn`, `Off`, `Toggle`) erano legati tutti e
    // tre a «inverti». Sembra una comodità e invece è un difetto: una
    // tastiera che manda **due** di questi tasti per una sola pressione —
    // e su questo Acer i tasti WMI e la tastiera AT sono due dispositivi
    // distinti — invertiva due volte, cioè tornava esattamente al punto di
    // partenza. Il tasto sembrava rotto perché faceva il suo lavoro due
    // volte.
    //
    // Con i comandi separati il doppio invio è innocuo: «accendi» due volte
    // accende, e basta. È anche il comportamento che KDE ha da sempre, ed è
    // il motivo per cui lì il tasto rispondeva.
    function cambiaTouchpad(voluto) {
        if (root.touchpadName === "") {
            osd.say(Core.Strings.lang === "it" ? "Nessun touchpad"
                                               : "No touchpad", "cursor");
            return;
        }
        var acceso = (voluto === null) ? !Core.SystemState.touchpadOn : voluto;
        Core.SystemState.setTouchpad(acceso);
        // Si riapplica sempre, anche se la preferenza non è cambiata: il
        // segnale `onTouchpadOnChanged` non scatta quando il valore è già
        // quello, e chi preme «accendi» su un touchpad che il compositore ha
        // spento per conto suo resterebbe senza niente.
        root.applicaTouchpad();
        osd.say(acceso
                ? (Core.Strings.lang === "it" ? "Touchpad acceso"
                                              : "Touchpad on")
                : (Core.Strings.lang === "it" ? "Touchpad spento"
                                              : "Touchpad off"),
                "cursor");
    }

    Core.Scorciatoia {
        name: "touchpad"
        onPressed: root.cambiaTouchpad(null)
    }

    Core.Scorciatoia {
        name: "touchpadon"
        onPressed: root.cambiaTouchpad(true)
    }

    Core.Scorciatoia {
        name: "touchpadoff"
        onPressed: root.cambiaTouchpad(false)
    }

    // ── La lente d'ingrandimento ─────────────────────────────────────────
    //
    // `cursor:zoom_factor` di Hyprland ingrandisce tutto lo schermo attorno al
    // puntatore. È la sola cosa in Minerva che permetta a chi ci vede poco di
    // leggere una finestra che non ha modo di ingrandire — un PDF, una foto,
    // un programma che non è nostro.
    //
    // Il fattore vive nelle IMPOSTAZIONI e non dentro Hyprland, e la
    // differenza conta: il compositore lo dimentica a ogni riavvio della
    // sessione, e chi ne ha bisogno se lo ritroverebbe spento ogni mattina.
    // Qui è la nostra impostazione a comandare, e Hyprland ne è la
    // conseguenza.
    //
    // Il passo è MOLTIPLICATIVO. A somma fissa, da 1 a 1.25 il salto è
    // enorme e da 4 a 4.25 non si vede: ingrandire è un rapporto, non una
    // distanza.
    readonly property real lenteMax: 5.0

    function applicaLente() {
        var f = Core.Ipc.get("accessibility.zoom", 1.0);
        Core.Compositore.ingrandimentoPuntatore(f);
    }

    function cambiaLente(verso) {
        var ora = Core.Ipc.get("accessibility.zoom", 1.0);
        var nuovo = verso === 0 ? 1.0
                  : verso > 0   ? ora * 1.25
                                : ora / 1.25;
        // Sotto l'uno non si «rimpicciolisce»: Hyprland disegnerebbe lo
        // schermo più piccolo dello schermo, con una cornice nera attorno.
        nuovo = Math.max(1.0, Math.min(root.lenteMax, nuovo));
        nuovo = Math.round(nuovo * 100) / 100;
        Core.Ipc.setSetting("accessibility.zoom", nuovo);
        root.applicaLente();
        osd.say(nuovo <= 1.0
                ? (Core.Strings.lang === "it" ? "Lente spenta" : "Magnifier off")
                : Math.round(nuovo * 100) + "%",
                "search");
    }

    Core.Scorciatoia { name: "zoomin";    onPressed: root.cambiaLente(1) }
    Core.Scorciatoia { name: "zoomout";   onPressed: root.cambiaLente(-1) }
    Core.Scorciatoia { name: "zoomreset"; onPressed: root.cambiaLente(0) }


    // ── Il cursore più grande ────────────────────────────────────────────
    //
    // `hyprctl setcursor` vuole DUE cose: il tema e la dimensione. Il tema non
    // lo sceglie Minerva — è quello che l'utente ha già per tutto il resto del
    // computer, scritto dove lo scrivono GTK e KDE — e passargliene uno che
    // non esiste **fa sparire il puntatore**, senza messaggi. Per questo il
    // nome viene sempre verificato su disco prima di essere usato, e in
    // mancanza si ripiega su Adwaita, che c'è ovunque.
    Core.Exec {
        id: scriviCursore
        onDone: function(tema) {
            var t = String(tema).trim();
            if (t !== "")
                Core.Compositore.cursore(t, Core.Ipc.get("accessibility.cursorSize", 24));
        }
    }

    function applicaCursore() {
        var d = Core.Ipc.get("accessibility.cursorSize", 24);
        // Il TEMA si cerca con `sh` (bisogna leggere un file e provare
        // due cartelle), ma applicarlo passa dalla porta: un tema di
        // puntatori che non esiste fa SPARIRE il puntatore, e il nome
        // va verificato su disco prima di usarlo.
        // ── `sh`, non `fireSh` ───────────────────────────────────────
            //
            // `fireSh` vuol dire «lancia e basta»: usa un `Process` senza
            // raccoglitore di stdout e senza segnale, e `onDone` **non arriva
            // mai**. Qui il risultato del comando È la risposta — il nome del
            // tema — quindi serve `sh`, che aspetta.
            //
            // Giacomo, 7 settembre 2026: «nemmeno ingrandire il puntatore».
            // Non era una questione di quando si applicava: non si applicava
            // proprio, né all'accesso né premendo il pulsante. Il comando
            // partiva, trovava il tema, e la risposta la buttava via un
            // `Process` che non ascoltava nessuno.
            scriviCursore.sh(
            "t=$(sed -n 's/^gtk-cursor-theme-name=//p' " +
            "\"$HOME/.config/gtk-3.0/settings.ini\" 2>/dev/null " +
            "| tr -d '\"' | head -1); " +
            "[ -d \"/usr/share/icons/$t/cursors\" ] || " +
            "[ -d \"$HOME/.icons/$t/cursors\" ] || t=Adwaita; " +
            "printf '%s' \"$t\"");
    }

    // Riapplicate appena il demone risponde, e non solo quando si preme un
    // tasto: il compositore dimentica lente e cursore a ogni avvio della
    // sessione, e chi ha bisogno dell'una o dell'altro se li ritroverebbe
    // spenti ogni mattina — cioè proprio chi non può rimetterli a posto da
    // solo.
    //
    // ── Quando le impostazioni ci SONO, non quando il canale si apre ─────
    //
    // Qui c'era solo `onConnectedChanged`, e sembrava la stessa cosa. Non lo
    // è: collegarsi e ricevere le impostazioni sono due momenti diversi, e in
    // mezzo `Core.Ipc.get("accessibility.cursorSize", 24)` non restituisce il
    // valore scelto — restituisce **il ripiego scritto nella riga**.
    //
    // Quindi a ogni accesso il puntatore tornava a 24 e la lente a 1.0,
    // qualunque cosa ci fosse nelle impostazioni. Cambiarli dal pannello
    // funzionava, ed è per questo che sembrava a intermittenza: funziona
    // finché non esci.
    //
    // Giacomo, 7 settembre 2026: «ho disconnesso la sessione e al nuovo
    // accesso non lo fa ancora, nemmeno ingrandire il puntatore». Misurato:
    // `cursorSize` 32 nelle impostazioni, 22 pixel chiari di puntatore sullo
    // schermo — cioè il 24 di ripiego.
    //
    // Si riapplica a tutti e due i momenti: riapplicare due volte lo stesso
    // valore non costa e non si vede, mentre applicarlo una volta sola nel
    // momento sbagliato non si vede affatto.
    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (!Core.Ipc.connected)
                return;
            root.applicaLente();
            root.applicaCursore();
        }
        function onImpostazioniArrivateChanged() {
            if (!Core.Ipc.impostazioniArrivate)
                return;
            root.applicaLente();
            root.applicaCursore();
        }
        // E se le impostazioni CI SONO GIÀ quando questo pezzo nasce, nessuno
        // dei due segnali scatterà mai: un `Changed` si accorge dei
        // cambiamenti, non di com'erano le cose all'inizio. Succede a ogni
        // ricarica a caldo della shell, ed è il modo in cui questa stessa
        // correzione sarebbe potuta sembrare inutile.
        Component.onCompleted: {
            if (Core.Ipc.impostazioniArrivate) {
                root.applicaLente();
                root.applicaCursore();
            }
        }
    }

    Core.Scorciatoia {
        name: "micmute"
        onPressed: micMute.running = true
    }

    Process {
        id: micMute
        command: ["sh", "-c",
                  "pactl set-source-mute @DEFAULT_SOURCE@ toggle >/dev/null 2>&1; "
                  + "pactl get-source-mute @DEFAULT_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                // «Mute: yes» o «Mute: no». Si legge la risposta invece di
                // tenere un conto nostro: il microfono lo può chiudere anche
                // qualcun altro, e un interruttore che mente sulla privacy è
                // peggio di nessun interruttore.
                var chiuso = text.indexOf("yes") !== -1;
                var it = Core.Strings.lang === "it";
                osd.say(chiuso ? (it ? "Microfono chiuso" : "Microphone muted")
                               : (it ? "Microfono aperto" : "Microphone on"),
                        chiuso ? "micOff" : "mic");
            }
        }
    }

    Core.Scorciatoia {
        name: "files"
        onPressed: root.openFiles()
    }

    Core.Scorciatoia {
        name: "monitor"
        onPressed: root.openMonitor()
    }
}
