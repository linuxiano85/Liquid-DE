import QtQuick
import QtQuick.Shapes
import "../theme" as Theme
import "../core" as Core
import "tracciati.js" as Tracciati

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
    /// il manutentore ha descritto come «alcune icone di documenti o altri file sono
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
    // «radio» (11 ottobre 2026): un segno nostro, mai del tema. Chiesta al
    // tema come «globe», nel tema Win11 diventava il logo di un browser.
    readonly property var _segni: Tracciati.segni

    /// Sempre il disegno grande del tema, anche in piccolo.
    ///
    /// Molti temi (Win11, Papirus…) a 22 pixel non hanno la cartella gialla
    /// ma un segno monocromatico per i pannelli: giusto nella barra, sbagliato
    /// per i FILE. il manutentore, 11 ottobre 2026: «il gestore file ha solo icone
    /// monocromatiche e se cambio icone rimangono le stesse». Era il 22 del
    /// tema Win11, `places/22/folder.svg`, grigio `#dedede`. Le icone dei file
    /// (`files/FileIcon.qml`) chiedono quindi il disegno grande, rimpicciolito
    /// (è un SVG), come fa Esplora file.
    property bool sempreGrande: false

    readonly property string classicFile: {
        if (icon.alwaysDrawn || icon._segni.indexOf(icon.name) >= 0) return "";
        if (Core.Ipc.get("icons.style", "minerva") === "minerva") return "";
        var entry = Core.Ipc.iconMap[icon.name];
        if (entry === undefined || entry === null) return "";
        if (icon.sempreGrande)
            return entry.l || entry.s || "";
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

    // La tabella sta in `tracciati.js`, condivisa da tutte le icone del
    // processo (prima: una copia per icona; vedi il commento là).
    readonly property var _paths: Tracciati.tracciati

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
        // il manutentore, quel giorno: «oltre al fatto che compaiono tutti quei segni
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
