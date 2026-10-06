import QtQuick
import QtQuick.Shapes
import "../theme" as Theme
import "../core" as Core

// Icon — Il set di icone di Minerva, disegnato non scritto.
//
// Le icone sono tracciati vettoriali, non caratteri di un font. Tre motivi:
//
//  · un font di icone è una dipendenza in più che può mancare, e quando manca
//    l'interfaccia si riempie di quadratini;
//  · i glifi Unicode «di ripiego» (⚙ 🔔 ⏻) vengono resi da font diversi su
//    sistemi diversi, con pesi e allineamenti incoerenti;
//  · un tracciato prende il colore e lo spessore che gli diamo, e resta nitido
//    a qualunque dimensione.
//
// Tutte le icone sono disegnate su una griglia 24×24 con tratto continuo, così
// hanno lo stesso peso ottico anche se la forma è diversa.
//
// ── Le icone classiche ─────────────────────────────────────────────────────
//
// Il tratto sottile e luminoso non piace a tutti, e non c'è ragione di
// imporlo: chi preferisce le icone di sempre — quelle di Papirus, di Breeze,
// del tema che ha già scelto per il resto del computer — le sceglie da
// Impostazioni → Aspetto → Icone, e queste stesse `Ui.Icon` disegnano
// un'immagine invece del proprio tracciato.
//
// La traduzione fra i nostri nomi («settings») e quelli della specifica
// freedesktop («preferences-system») la fa il demone, che sa leggere gli
// `index.theme`: vedi `minervad/lib/services/icon_names.dart`. Qui arriva già
// fatta, in `Core.Ipc.iconMap`.
//
// Il ripiego è la cosa importante: un nome che il tema scelto non ha resta
// disegnato da noi. Nessun tema copre tutto, e l'alternativa a un tracciato
// leggermente fuori stile è un buco nella barra.
Item {
    id: icon

    /// Nome dell'icona. Vedi `_paths` per l'elenco.
    property string name: ""
    property color color: Theme.Colors.text
    property real thickness: 1.7
    /// Alcune icone (stella, batteria) stanno meglio piene
    property bool filled: false

    /// Alcune icone non hanno senso in versione classica e restano sempre
    /// disegnate: quelle che fanno parte del disegno di un componente più che
    /// dell'iconografia — le frecce di un menu, i comandi di una barra del
    /// titolo — dove un'icona di un altro tema stona invece di aiutare.
    ///
    /// ── LA REGOLA, per non doverla ridecidere ogni volta ─────────────────
    ///
    /// **Icona di sistema per i PROGRAMMI, tracciato nostro per i SEGNI.**
    ///
    /// Un programma si riconosce dalla sua icona, e chi ha scelto un tema
    /// classico vuole vedere quella. Un segno dentro la nostra interfaccia —
    /// la lente della ricerca, la × che svuota un filtro, il chevron che apre
    /// un gruppo, il disegno smorzato al centro di un pannello vuoto — non è
    /// iconografia: è parte del disegno del componente.
    ///
    /// **Come si riconosce un segno**: gli si assegna un COLORE del tema
    /// (`textFaint`, `textMuted`, `danger`). Se il codice chiede un colore
    /// preciso, vuole il proprio tracciato — un'icona classica è già colorata
    /// dal suo tema e quel colore lo ignora. Era esattamente il difetto: il
    /// segnaposto «nessuna immagine» dell'Anteprima chiedeva un grigio
    /// smorzato e usciva ciano a colori pieni, e la × che chiude una scheda
    /// chiedeva il rosso del pericolo e non l'aveva.
    property bool alwaysDrawn: false

    /// «Questa cosa è spenta»: il volume in silenzio, la rete scollegata, un
    /// pulsante che adesso non si può premere.
    ///
    /// Serve una proprietà a sé perché il COLORE non basta a dirlo. Il colore
    /// vale per il tracciato: `textFaint` sta al 34% perché un tratto sottile
    /// a piena luce urla, non perché quel file sia disattivato. Un'icona
    /// classica, invece, è già colorata dal suo tema e la trasparenza la
    /// spegne e basta.
    ///
    /// Prima l'immagine prendeva `opacity: color.a` sempre, e siccome nel
    /// gestore file le icone dei file sono disegnate con `textFaint`, con le
    /// icone classiche accese OGNI file compariva al 34%. È il difetto che
    /// Giacomo ha descritto come «alcune icone di documenti o altri file sono
    /// trasparenti»: non mancavano, erano quasi invisibili.
    property bool spenta: false

    implicitWidth: 24
    implicitHeight: 24

    // ── Icone classiche ──────────────────────────────────────────────────

    /// Il file da disegnare, o stringa vuota se si usa il tracciato.
    ///
    /// La misura non è un dettaglio: un tema curato ridisegna la stessa icona
    /// per le dimensioni piccole, con meno dettagli. Il demone ne risolve due,
    /// una da 22 e una da 48, e qui si prende quella giusta — la barra chiede
    /// la piccola, il gestore file in modalità griglia la grande.

    /// I nomi che restano il NOSTRO tracciato anche col set classico acceso.
    ///
    /// La regola sta scritta qui sopra — «icona di sistema per i programmi,
    /// tracciato nostro per i segni» — ma finora esisteva solo come frase: si
    /// applicava mettendo `alwaysDrawn: true` sul posto, uno per uno, e
    /// dimenticarsene non dava nessun errore.
    ///
    /// Misurato il 18 agosto 2026: quindici dei nostri ottantadue tracciati
    /// non avevano nessuna controparte classica, e restavano disegnati in
    /// mezzo agli altri. Cinque erano segni ed è giusto così; dieci erano
    /// dimenticanze, e sono state tradotte. La differenza fra le due cose
    /// adesso è scritta, e una prova la fa rispettare
    /// (`minervad/test/icon_names_test.dart`).
    ///
    /// Questi cinque sono i comandi del lettore: `play` e `pause` sono i due
    /// stati dello STESSO pulsante e devono avere lo stesso peso ottico, cosa
    /// che nessun tema garantisce; `more` sono i tre puntini di un menu, che
    /// è parte del disegno del componente e non iconografia.
    readonly property var _segni: ["play", "pause", "next", "prev", "more"]

    readonly property string classicFile: {
        if (icon.alwaysDrawn || icon._segni.indexOf(icon.name) >= 0) return "";
        if (Core.Ipc.get("icons.style", "minerva") === "minerva") return "";
        var entry = Core.Ipc.iconMap[icon.name];
        if (entry === undefined || entry === null) return "";
        return (icon.width <= 28 ? entry.s : entry.l) || "";
    }

    readonly property bool classic: icon.classicFile !== ""

    Image {
        anchors.fill: parent
        visible: icon.classic
        source: icon.classic ? "file://" + icon.classicFile : ""
        fillMode: Image.PreserveAspectFit
        // Un'icona di un tema ha i suoi colori e non prende il nostro. Lo
        // stato «spenta» sì, ma va DICHIARATO: leggerlo dalla trasparenza del
        // colore sembrava furbo e spegneva anche tutto ciò che è tenue per
        // ragioni di disegno. Vedi `spenta` qui sopra.
        opacity: icon.spenta ? 0.4 : 1
        // Senza `sourceSize` un SVG viene rasterizzato alla sua dimensione
        // naturale e poi scalato: a 18 pixel si vede la differenza fra
        // un'icona nitida e una molle.
        sourceSize.width: Math.max(1, Math.round(icon.width))
        sourceSize.height: Math.max(1, Math.round(icon.height))
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true
    }

    readonly property var _paths: ({
        // ── Navigazione e azioni ─────────────────────────────────────────
        "apps":      "M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z",
        "search":    "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z M20.5 20.5l-4.4-4.4",
        "close":     "M6.5 6.5l11 11 M17.5 6.5l-11 11",
        "chevron":   "M6.5 9.5l5.5 5.5 5.5-5.5",
        "chevronUp": "M6.5 14.5l5.5-5.5 5.5 5.5",
        "plus":      "M12 5v14 M5 12h14",
        "check":     "M5 12.5l4.5 4.5L19 7.5",
        "back":      "M19 12H5 M11 6l-6 6 6 6",

        // ── Sistema ──────────────────────────────────────────────────────
        "wifi":      "M2.6 8.6a15 15 0 0 1 18.8 0 M5.7 12.2a10.3 10.3 0 0 1 12.6 0 M8.8 15.8a5.6 5.6 0 0 1 6.4 0 M12 19.2h.01",
        "bluetooth": "M7 7.5l10 9-5 3.5V4l5 3.5-10 9",
        "volume":    "M4 9.5v5h3.5l4.5 3.5v-12L7.5 9.5H4z M16 9.6a3.6 3.6 0 0 1 0 4.8 M18.6 7a7.4 7.4 0 0 1 0 10",
        "muted":     "M4 9.5v5h3.5l4.5 3.5v-12L7.5 9.5H4z M16 10l4.5 4 M20.5 10l-4.5 4",

        // Il microfono: una capsula su un archetto. Chiuso è lo stesso
        // disegno con una sbarra — la stessa grammatica di `volume`/`muted`,
        // così due stati della stessa cosa si riconoscono come tali.
        "mic":       "M12 4a2.5 2.5 0 0 1 2.5 2.5v5a2.5 2.5 0 0 1-5 0v-5A2.5 2.5 0 0 1 12 4z "
                     + "M6.5 11a5.5 5.5 0 0 0 11 0 M12 16.5V20 M9 20h6",
        "micOff":    "M12 4a2.5 2.5 0 0 1 2.5 2.5v5a2.5 2.5 0 0 1-5 0v-5A2.5 2.5 0 0 1 12 4z "
                     + "M6.5 11a5.5 5.5 0 0 0 11 0 M12 16.5V20 M9 20h6 M4.5 3.5l15 17",

        // Il touchpad: un rettangolo con il taglio del tasto in basso. Non è
        // una freccia di puntatore di proposito — il tasto Fn spegne la
        // superficie, non il mouse, e sulla scrivania ce n'è anche un altro.
        "cursor":    "M3.5 5.5h17v13h-17z M12 14.5v4",
        "battery":   "M3 8.5h14.5v7H3z M20 11v2",
        "bell":      "M6.5 9.5a5.5 5.5 0 0 1 11 0c0 4.5 1.8 5.5 1.8 5.5H4.7s1.8-1 1.8-5.5z M10 19a2 2 0 0 0 4 0",
        "power":     "M12 4v8 M7.4 6.6a8 8 0 1 0 9.2 0",
        "lock":      "M6 11.5h12v8.5H6z M9 11.5V8.5a3 3 0 0 1 6 0v3",
        "moon":      "M20 14.2A8.4 8.4 0 1 1 9.8 4a6.6 6.6 0 0 0 10.2 10.2z",
        "restart":   "M20 12a8 8 0 1 1-2.4-5.7 M20.5 3.5v5h-5",
        "logout":    "M14 5H6v14h8 M18 12H10 M15 9l3 3-3 3",
        "sun":       "M12 8.4a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2z M12 3v2 M12 19v2 M3 12h2 M19 12h2 M5.6 5.6l1.4 1.4 M17 17l1.4 1.4 M18.4 5.6L17 7 M7 17l-1.4 1.4",
        "sliders":   "M4 8h9 M17 8h3 M4 16h3 M11 16h9 M15 5.5v5 M9 13.5v5",
        // Accessibilità: la figura a braccia aperte della specifica. Prima
        // quella sezione chiedeva «expand», cioè le due frecce dello schermo
        // intero: un segno che vuol dire un'altra cosa, e che nessun tema di
        // icone traduce in accessibilità.
        "accessibilita": "M12 3.3a1.7 1.7 0 1 0 0 3.4 1.7 1.7 0 0 0 0-3.4z "
                     + "M4.6 9.2h14.8 M12 8.6v6.2 M12 14.8l-3.6 5.9 M12 14.8l3.6 5.9",
        // Ingranaggio: anello, foro centrale e otto denti. Non è il «sole» con
        // un buco — i denti partono DAL bordo dell'anello, ed è questo che lo
        // rende leggibile come impostazioni e non come luminosità.
        "settings":  "M12 5.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13z M12 9.4a2.6 2.6 0 1 0 0 5.2 2.6 2.6 0 0 0 0-5.2z M12 2.6v3 M12 18.4v3 M2.6 12h3 M18.4 12h3 M5.2 5.2l2.1 2.1 M16.7 16.7l2.1 2.1 M18.8 5.2l-2.1 2.1 M7.3 16.7l-2.1 2.1",
        "minimize":  "M6 12.5h12",
        // Schermo intero: due frecce che si allontanano in diagonale. È il
        // segno che usa macOS ed è l'unico che si distingue da «ingrandisci»
        // — che è un'altra cosa e si ferma sotto la barra della scrivania.
        "expand":    "M10 4H4v6 M4 4l6.8 6.8 M14 20h6v-6 M20 20l-6.8-6.8",
        "collapse":  "M4.5 10.5h6v-6 M4 4l6.5 6.5 M19.5 13.5h-6v6 M20 20l-6.5-6.5",
        "maximize":  "M5.5 5.5h13v13h-13z",
        "restore":   "M4.5 9.5h10v9h-10z M8 9.5v-4h11.5v9h-5",

        // ── Contenuti ────────────────────────────────────────────────────
        // Copia e taglia. Mancavano, e i due tracciati assenti non davano
        // nessun errore: `Ui.Icon` con un nome che non conosce disegna una
        // cartella o niente. Le voci «Copia» e «Taglia» del menù del gestore
        // file erano lì da sempre, senza segno accanto.
        "copy":      "M20 9h-9a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2z M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1",
        "cut":       "M6 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M20 4L8.1 15.9 M14.5 14.5L20 20 M8.1 8.1L12 12",
        "clipboard": "M9.5 4.5h5v2.5h-5z M9.5 5.8H6.5V20h11V5.8h-3",
        "keyboard":  "M2.5 7h19v10h-19z M6 11h.01 M9.5 11h.01 M13 11h.01 M16.5 11h.01 M7.5 14.2h9",
        // La casa e il disco: servono alle briciole del percorso, dove il
        // primo pezzo non è una cartella qualunque ma «dove abito» oppure
        // «la radice del disco», e vanno riconosciuti prima di leggerli.
        "home":      "M3.5 11.3L12 4.2l8.5 7.1 M5.6 10.1v9.4h12.8v-9.4 M9.9 19.5v-5.1h4.2v5.1",
        "disco":     "M4.6 7.3c0-1.4 3.3-2.6 7.4-2.6s7.4 1.2 7.4 2.6-3.3 2.6-7.4 2.6-7.4-1.2-7.4-2.6z M4.6 7.3v9.4c0 1.4 3.3 2.6 7.4 2.6s7.4-1.2 7.4-2.6V7.3",
        // La chiavetta: il connettore stretto in cima e il corpo sotto. Non è
        // un disco più piccolo — nella colonna del gestore file la differenza
        // fra «il disco di questo computer» e «una cosa che ho infilato
        // adesso» è la sola che conti, ed era resa da una LAVAGNETTA.
        "chiavetta": "M10 3.5h4v4h-4z M8 7.5h8v13h-8z M10.5 11h3",
        "folder":    "M3 6.5h6l2 2.2h10V19H3z",
        "globe":     "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M3.4 12h17.2 M12 3.2a13.5 13.5 0 0 1 0 17.6 M12 3.2a13.5 13.5 0 0 0 0 17.6",
        "terminal":  "M5.5 7.5l4 4.5-4 4.5 M12.5 16.5h6",
        // Una nuvola disegnata con tre archi e una base, come tutte le altre
        // qui dentro: tratto solo, nessun riempimento, dentro la stessa
        // griglia da 24. Serve agli account online — e non si prende da un
        // tema di sistema, perché un'icona che cambia col tema non è più la
        // nostra (vedi `assets/icons/`).
        "cloud":     "M7.2 18.4h9.9a3.9 3.9 0 0 0 .5-7.77 5.7 5.7 0 0 0-10.86-1.5 4.65 4.65 0 0 0 .46 9.27z",
        "star":      "M12 3.6l2.6 5.5 6 .9-4.3 4.2 1 6-5.3-2.8-5.3 2.8 1-6-4.3-4.2 6-.9z",
        "gamepad":   "M8 10v4 M6 12h4 M15.5 11h.01 M17.5 13.5h.01 M7 7.5h10a4 4 0 0 1 4 4v1a4 4 0 0 1-7 2.7h-4A4 4 0 0 1 3 12.5v-1a4 4 0 0 1 4-4z",
        "image":     "M3.5 5h17v14h-17z M8 11a1.6 1.6 0 1 0 0-3.2A1.6 1.6 0 0 0 8 11z M4 17l5-5 4 3.5 3-2.5 4 4",
        "music":     "M9 18V6l10-2v12 M9 18a2.6 2.6 0 1 1-5.2 0 2.6 2.6 0 0 1 5.2 0z M19 16a2.6 2.6 0 1 1-5.2 0 2.6 2.6 0 0 1 5.2 0z",
        // Il download e la condivisione: servono a Minerva Media. La freccia
        // del download scende dentro il vassoio, quella della condivisione
        // esce dalla scatola — la stessa forma, dall'altra parte.
        "download":  "M12 4v9.5 M7.5 10l4.5 4.5 4.5-4.5 M4.5 18.5h15",
        "share":     "M12 15V4 M7.5 8.5L12 4l4.5 4.5 M4.5 14.5v5.5h15v-5.5",
        // I comandi del lettore. Sono gli unici tracciati pensati per
        // `filled: true` invece che per il tratto: a 16 pixel un triangolo
        // vuoto con un contorno da 1,7 diventa una macchia, e la pausa
        // disegnata a due linee sottili non si distingue dal segno «uguale».
        // Pieni restano leggibili anche piccoli, che è dove vivono.
        "play":      "M8.5 5.4l10 6.6-10 6.6z",
        "pause":     "M8.6 5.6h2.9v12.8h-2.9z M12.5 5.6h2.9v12.8h-2.9z",
        "next":      "M6 5.6l9.4 6.4-9.4 6.4z M16.6 5.6h2.4v12.8h-2.4z",
        "prev":      "M18 5.6l-9.4 6.4 9.4 6.4z M5 5.6h2.4v12.8h-2.4z",
        "wrench":    "M15.5 4.5a5 5 0 0 0-6.2 6.4L4 16.2 7.8 20l5.3-5.3a5 5 0 0 0 6.4-6.2l-3 3-2.3-2.3 3-3z",
        "document":  "M6.5 3.5h7l4.5 4.5v12h-11.5z M13 3.5V8h4.5",
        // ── I tipi di file, e perché non basta «document» ─────────────────
        //
        // Con le icone classiche accese, un tema installato ha un disegno per
        // il PDF, uno per il foglio di calcolo, uno per il codice sorgente.
        // Chiedendo «document» per tutti si buttava via quella ricchezza e si
        // vedevano dieci icone dove il gestore file di KDE ne mostra cento —
        // che è quello che Giacomo ha descritto come «alcune icone non
        // vengono riconosciute». Ogni nome qui sotto ha una controparte nella
        // tabella del demone (`icon_names.dart`), ed è quella a portarci al
        // disegno del tema.
        //
        // Restano tutti la stessa forma di base — il foglio con l'angolo
        // piegato — perché nel NOSTRO set devono leggersi come parenti. A
        // distinguerli è il segno dentro.
        //
        // Foglio con la piega e le lettere PDF ridotte a tre tratti.
        "pdf":       "M6.5 3.5h7l4.5 4.5v12h-11.5z M13 3.5V8h4.5 M9 12.5h1.6a1.2 1.2 0 0 1 0 2.4H9v-2.4z M9 14.9v2.1 M12.6 12.5v4.5h1.2a1.4 1.4 0 0 0 1.4-1.4v-1.7a1.4 1.4 0 0 0-1.4-1.4z",
        // Foglio a griglia: due colonne, due righe. È il segno del foglio di
        // calcolo ovunque.
        "table":     "M6.5 3.5h7l4.5 4.5v12h-11.5z M13 3.5V8h4.5 M8 12.5h8 M8 15.5h8 M12 11v8",
        // Foglio con dentro un rettangolo pieno: la diapositiva.
        "slides":    "M6.5 3.5h7l4.5 4.5v12h-11.5z M13 3.5V8h4.5 M8.5 12h7v5h-7z",
        // Le due parentesi angolari del codice.
        "code":      "M6.5 3.5h7l4.5 4.5v12h-11.5z M13 3.5V8h4.5 M10 12.5L7.5 15l2.5 2.5 M14 12.5L16.5 15 14 17.5",
        // La A del carattere tipografico.
        "font":      "M6.5 3.5h7l4.5 4.5v12h-11.5z M13 3.5V8h4.5 M9.5 17.5l2.5-6 2.5 6 M10.4 15.5h3.2",
        // Busta: la V della patta parte dagli angoli alti, non dai lati —
        // altrimenti a 15 pixel si legge come un rettangolo con una riga
        // storta dentro.
        "mail":      "M3.5 6h17v12h-17z M3.5 6l8.5 6.5L20.5 6",
        // Schermo con il triangolo del «via»: da solo il triangolo è il tasto
        // riproduci, e questo è un tipo di file, non un comando.
        "video":     "M3.5 5.5h17v13h-17z M10 9.8l4.6 2.7-4.6 2.7z",
        // Scatola col coperchio e la fessura: la sola scatola è un cubo.
        "archive":   "M3.5 4.5h17v4h-17z M5 8.5h14V19H5z M10 12h4",
        "cpu":       "M8 8h8v8H8z M4.5 10h3 M4.5 14h3 M16.5 10h3 M16.5 14h3 M10 4.5v3 M14 4.5v3 M10 16.5v3 M14 16.5v3",
        // ── I quattro dei widget della barra ─────────────────────────────
        //
        // Giacomo, 14 settembre 2026: «quelli sulla barra sono confusionari
        // perché non hanno un simbolo per capire che valori monitorano».
        // Tre numeri in fila — «6 % · 21 % · 49°» — non dicono di cosa.
        //
        // La memoria è un modulo con i piedini in basso: si distingue dal
        // processore, che è un quadrato coi piedini su quattro lati.
        "memoria":   "M4 6.5h16v9H4z M7 9.5v3 M10.5 9.5v3 M14 9.5v3 M17 9.5v3 M6 15.5v2.5 M9 15.5v2.5 M12 15.5v2.5 M15 15.5v2.5 M18 15.5v2.5",
        // Il termometro: il bulbo in basso e la colonna.
        "termometro": "M10 13.5V5a2 2 0 0 1 4 0v8.5 M12 20a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4z M12 13.6v2.4",
        // La GPU: una scheda con la ventola tonda. Non è il processore con
        // un cerchio dentro: la scheda è più larga che alta, e sta di lato.
        "gpu":       "M3 7.5h18v9H3z M3 16.5v2 M8.5 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0z M11.5 12h0.01 M16.5 10h2.5 M16.5 14h2.5",
        // Il carico: una lancetta su un quadrante mezzo, come un tachimetro.
        "carico":    "M4 16a8 8 0 0 1 16 0 M12 16l4-5.5 M12 16h0.01",
        // La rete: il globo è del browser, il wifi della connessione; per
        // «quanto sta passando» due frecce, una su e una giù.
        "rete":      "M8 4v14 M4.5 14.5L8 18l3.5-3.5 M16 20V6 M12.5 9.5L16 6l3.5 3.5",
        // ── Gli apparecchi Bluetooth (14 settembre 2026) ─────────────────
        //
        // Le classi di BlueZ — `input-mouse`, `audio-headset`, `phone` — si
        // traducono in questi tre, più `keyboard`, `gamepad` e `volume` che
        // c'erano già. Il mouse è una goccia con la rotellina; le cuffie
        // l'archetto con i due padiglioni; il telefono un rettangolo alto.
        "mouse":     "M12 3.5a5.5 5.5 0 0 0-5.5 5.5v6a5.5 5.5 0 0 0 11 0V9A5.5 5.5 0 0 0 12 3.5z M12 3.5V11 M12 7v2",
        "cuffie":    "M4 15v-3a8 8 0 0 1 16 0v3 M4 15h3v5H5a1 1 0 0 1-1-1v-4z M20 15h-3v5h2a1 1 0 0 0 1-1v-4z",
        "telefono":  "M7.5 3.5h9a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1z M11 18h2",
        "link":      "M10 13.5a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1.2 1.2 M14 10.5a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.2-1.2",
        "pin":       "M12 20v-6 M8 4h8l-1 6 3 2v2H6v-2l3-2z",
        // Una scheda in più: due riquadri affiancati e un piccolo più.
        "split":     "M4 5.5h6.5v13H4z M13.5 5.5H20v13h-6.5z M16.75 9.5v5 M14.25 12h5",
        // Il cestino è un cestino. Con una × sembrava «annulla», ed è
        // esattamente il fraintendimento che non ci si può permettere lì.
        "trash":     "M4.5 7h15 M9.5 7V4.5h5V7 M6.5 7l1 12.5h9l1-12.5 M10 10.5v6 M14 10.5v6",
        "dock":      "M3 15.5h18v4H3z M6 18h.01 M10 18h.01 M14 18h.01 M18 18h.01 M6.5 4.5h11v7h-11z",
        "shuffle":   "M4 6.5h3.5l9 11H20 M4 17.5h3.5l9-11H20 M17.5 4l2.5 2.5-2.5 2.5 M17.5 15l2.5 2.5-2.5 2.5",
        // Ripeti: un anello con due frecce. «Ripeti uno» è lo stesso
        // anello con un 1 dentro — due stati della stessa cosa si
        // riconoscono come tali, come `volume`/`muted`.
        "repeat":    "M7 7h9a3.5 3.5 0 0 1 3.5 3.5v1 M17 17H8a3.5 3.5 0 0 1-3.5-3.5v-1 M9.5 4.5L7 7l2.5 2.5 M14.5 19.5L17 17l-2.5-2.5",
        "repeat1":   "M7 7h9a3.5 3.5 0 0 1 3.5 3.5v1 M17 17H8a3.5 3.5 0 0 1-3.5-3.5v-1 M9.5 4.5L7 7l2.5 2.5 M14.5 19.5L17 17l-2.5-2.5 M11.4 10.6l1.3-.9v4.6",
        "timer":     "M12 7.5V12l3 2 M12 4.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M9.5 2.5h5",
        // L'orologio e il cronometro sono due cose diverse: il secondo ha il
        // pulsante in cima, e messo su «Data e ora» direbbe «conto alla
        // rovescia» a chi lo guarda di sfuggita. Stesso quadrante, stesse
        // lancette, senza il nottolino.
        "clock":     "M12 7.2V12l3.5 2 M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z",
        // La «i» dentro un cerchio: il segno universale di «qui ci sono i
        // dettagli». Il punto e l'asta sono due tratti separati — un glifo
        // disegnato come testo si assottiglierebbe alle dimensioni piccole.
        "info":      "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M12 11v5.5 M12 7.6v0.2",
        // ── Il tempo che fa ──────────────────────────────────────────────
        //
        // Una nuvola sola, disegnata una volta, e le altre gliela mettono
        // sotto: pioggia, neve e temporale sono la STESSA nuvola con qualcosa
        // che cade. Cinque nuvole disegnate a mano divergerebbero entro un
        // mese, e si vedrebbe — sono icone che stanno una accanto all'altra
        // nella riga dei sette giorni.
        "nuvole":    "M7.3 18.5a4.3 4.3 0 0 1-.3-8.6 5.6 5.6 0 0 1 10.7-1.3 3.9 3.9 0 0 1 .6 7.7 4 4 0 0 1-.6 0.2z",
        "nuvole-sole": "M15.6 8.2a5.6 5.6 0 0 0-8.6 1.7 4.3 4.3 0 0 0 .3 8.6h10.4a3.9 3.9 0 0 0 .6-7.7 M5.4 6.6l-1-1 M8.6 3.6V2.4 M12.6 5.4l1-1",
        "pioggia":   "M7.3 15.4a4.3 4.3 0 0 1-.3-8.6 5.6 5.6 0 0 1 10.7-1.3 3.9 3.9 0 0 1 .6 7.7 M8.4 17.6l-1 3 M12 17.6l-1 3 M15.6 17.6l-1 3",
        "neve":      "M7.3 15.4a4.3 4.3 0 0 1-.3-8.6 5.6 5.6 0 0 1 10.7-1.3 3.9 3.9 0 0 1 .6 7.7 M8.4 19v0.2 M12 20.4v0.2 M15.6 19v0.2 M8.4 21.6v0.2 M15.6 21.6v0.2",
        "temporale": "M7.3 15.4a4.3 4.3 0 0 1-.3-8.6 5.6 5.6 0 0 1 10.7-1.3 3.9 3.9 0 0 1 .6 7.7 M13 16.6l-3 3.4h3.4l-2.6 3.2",
        "nebbia":    "M4 9.5h16 M6 13h12 M4 16.5h16",
        // Il segno del ritaglio: due squadre incrociate. È quello che c'è su
        // ogni programma di fotografia dagli anni Ottanta, e si riconosce
        // anche a quattordici pixel — che è la dimensione a cui va letto.
        "crop":      "M7 2.5v14.5h14.5 M2.5 7H17v14.5",
        // Lo schermo e la finestra. Servono davvero e non sono doppioni di
        // «maximize» e «restore»: quelli sono i COMANDI della barra del
        // titolo, e nei temi di icone lo sono anche di nome — `window-maximize`
        // in Breeze è una freccia in su, `window-restore` un rombo. Messi a
        // dire «tutto lo schermo» e «solo una finestra» non si capiscono.
        "screen":    "M3 5h18v11.5H3z M9 20h6 M12 16.5v3.5",
        "window":    "M3.5 5h17v14h-17z M3.5 9.2h17 M6.3 7.1h.01 M8.6 7.1h.01",
        // La macchina fotografica delle schermate. Un rettangolo con
        // l'obiettivo e il rialzo del mirino: senza il rialzo è una finestra,
        // ed è esattamente la cosa con cui non deve essere confusa.
        "camera":    "M3 7.5h4l1.5-2.5h7L17 7.5h4V19H3z M12 9.6a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2z",
        // Ruotare: un arco quasi chiuso con la punta. Il cerchio è APERTO in
        // alto a destra di proposito — chiuso sarebbe «ricarica», e la punta
        // da sola non basta a distinguerli a quattordici pixel.
        "rotate":    "M20 12a8 8 0 1 1-2.35-5.65 M20.5 3.5v4h-4",
        // «Altro»: tre punti. Nessun disegno migliore è mai stato trovato, e
        // qualunque altro segno costringerebbe a impararlo.
        "more":      "M6 12h.01 M12 12h.01 M18 12h.01",

        // ── Come si guarda un elenco ─────────────────────────────────────
        //
        // Le due visuali del gestore file. Si distinguono a colpo d'occhio
        // anche a 14 pixel: righe lunghe contro quadretti. Se somigliassero
        // servirebbe leggere l'etichetta, e a quel punto tanto varrebbe
        // metterci solo l'etichetta.
        "list":      "M4 6.5h2.5 M8.5 6.5H20 M4 12h2.5 M8.5 12H20 M4 17.5h2.5 M8.5 17.5H20",
        "grid":      "M4.5 4.5h6v6h-6z M13.5 4.5h6v6h-6z M4.5 13.5h6v6h-6z M13.5 13.5h6v6h-6z",
        "minus":     "M5 12h14",
        // Ordinamento: due frecce opposte, come su qualunque colonna
        // ordinabile mai disegnata.
        "sort":      "M7 19.5v-15 M4 7.5l3-3 3 3 M17 4.5v15 M14 16.5l3 3 3-3"
    })

    readonly property string _path: {
        if (icon._paths[icon.name] !== undefined)
            return icon._paths[icon.name];
        // ── I nomi che esistono solo per i temi classici ──────────────────
        //
        // «cartella-immagini», «cartella-musica» e gli altri servono a chiedere
        // al tema di icone il disegno che ha per QUELLA cartella. Il nostro
        // tratto invece non ha una cartella diversa per ogni contenuto — e non
        // deve averla: il segno di Minerva è uno solo, ed è la cartella.
        //
        // Senza questo ripiego, con le icone di Minerva accese, le cartelle di
        // casa restavano semplicemente VUOTE: un elenco con dei buchi al posto
        // di sei righe su dodici.
        if (icon.name.indexOf("cartella-") === 0)
            return icon._paths["folder"];
        return "";
    }

    Shape {
        anchors.fill: parent
        // ── Non si NASCONDE: si svuota ───────────────────────────────────
        //
        // Qui c'era `visible: !icon.classic`. Col renderer software nascondere
        // una `Shape` **non fa ridipingere la sua area**: i suoi pixel restano
        // sullo schermo. Da soli non si notano; passando alle icone del tema
        // se ne nascondono centinaia in un colpo, e quello che resta è una
        // scaletta di trattini a mezz'aria che sparisce solo chiudendo la
        // finestra.
        //
        // Isolato per bisezione il 5 settembre 2026: fra sette azioni
        // (cambio icone nei due versi, cambio tema, cambio sezione, cambio
        // accento) l'artefatto compariva **solo** passando a «classiche»,
        // cioè nell'unico momento in cui tante Shape spariscono insieme.
        //
        // Un tracciato VUOTO invece è un cambio di contenuto, e quello Qt lo
        // ridipinge: la Shape resta al suo posto e non disegna niente.
        // ── Non il CurveRenderer: qui NON c'è una scheda video ───────────
        //
        // `Shape.CurveRenderer` è il renderer analitico di Qt 6 e vuole la
        // GPU. Le nostre finestre girano con `QT_QUICK_BACKEND=software` — è
        // una scelta misurata che vale una quarantina di MB per finestra — e
        // lì non c'è nessuna GPU a cui chiederlo.
        //
        // Il sintomo, riprodotto il 5 settembre 2026 cambiando tema di icone e
        // poi sezione: **un «+» bianco sospeso in mezzo alla pagina**, dove
        // prima c'era il pallino «un colore tuo» di «Aspetto». Un oggetto
        // distrutto che lascia i suoi pixel sullo schermo, immuni a qualunque
        // ridisegno; e cambiando set di icone se ne accendono e spengono
        // centinaia in un colpo, quindi ne restano tanti. Chiudendo e
        // riaprendo la finestra spariscono, che è il modo lungo per dire che
        // sono pixel e non oggetti.
        //
        // Giacomo, quel giorno: «oltre al fatto che compaiono tutti quei segni
        // + sovrapposti per un certo tot di secondi non ben definiti non mi fa
        // cambiare sezione, opzione specifica o chiudere impostazioni».
        //
        // ⚠ Nota per il me di domani: questa correzione l'avevo già fatta il 4
        // settembre e l'ho TOLTA, perché la prova diceva che non serviva. La
        // prova era falsa: il processo del lettore non si era mai riavviato e
        // stavo guardando il codice di prima. Prima di dire «non era questo»,
        // si controlla che il processo sia quello nuovo.
        preferredRendererType: Shape.GeometryRenderer
        asynchronous: false

        ShapePath {
            strokeColor: icon.filled ? "transparent" : icon.color
            fillColor: icon.filled ? icon.color : "transparent"
            strokeWidth: icon.thickness
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            // I tracciati sono disegnati su 24×24 e scalati alla dimensione reale
            scale: Qt.size(icon.width / 24, icon.height / 24)

            PathSvg { path: icon.classic ? "" : icon._path }
        }
    }
}
