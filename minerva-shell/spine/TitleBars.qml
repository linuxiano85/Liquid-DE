import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// TitleBars — Le barre del titolo che Hyprland non disegna.
//
// Hyprland non ha cornici: nessun titolo, nessun tasto per chiudere, niente da
// afferrare per spostare una finestra senza tenere premuto un modificatore.
// Per chi arriva da Windows, da KDE o da GNOME è la cosa che manca di più, e
// non è nostalgia: è che senza una maniglia visibile una finestra non si sa
// prendere.
//
// Qui le disegniamo noi, e la cosa importante è DOVE.
//
// Nello spazio VUOTO sopra ogni finestra, non sopra il programma. Quello
// spazio esiste perché glielo facciamo lasciare a Hyprland: `gaps_in` con
// quattro valori riserva in cima a ogni riquadro un margine alto esattamente
// quanto la barra. È la differenza fra una cornice vera e un adesivo
// appiccicato sopra il programma.
//
// La barra scende poi di dieci pixel DENTRO la finestra (vedi `merge`), e
// quei dieci pixel sono l'unica cosa che copre: sono gli angoli che Hyprland
// arrotonda, cioè pixel già trasparenti. Servono a far leggere barra e
// finestra come un oggetto solo.
//
// E siccome il trascinamento lo gestiamo NOI — pressione, movimento e rilascio
// passano tutti da qui — possiamo fare quello che il compositore da solo non
// farebbe mai: mostrare le zone di aggancio mentre si trascina e sistemare la
// finestra dove la si lascia. Mezzo schermo ai lati, tutto in alto, un quarto
// negli angoli.
PanelWindow {
    id: bars

    /// Le disegna solo se le si vuole.
    property bool enabled: true
    /// Altezza della barra. È anche lo spazio che si chiede a Hyprland.
    ///
    /// Trentaquattro e non ventotto: una barra del titolo deve poter
    /// contenere una icona da sedici, tre pulsanti con la loro area
    /// cliccabile e il testo, tutto centrato sulla stessa linea. A ventotto
    /// non ci stavano, i pulsanti finivano più piccoli del dito che li cerca e
    /// il risultato sembrava un ripiego. Trentaquattro è anche il rapporto
    /// giusto con la barra di sistema, che è alta quarantaquattro: si vede che
    /// appartengono allo stesso ambiente senza essere uguali.
    property int titleHeight: 34
    /// Larghezza della fascia sensibile lungo i bordi, per l'aggancio.
    property int snapEdge: 24

    /// Quanto la barra scende DENTRO la finestra.
    ///
    /// Qui prima c'era `lift`, il contrario: la barra stava staccata di
    /// quattro pixel sopra la finestra. Sembrava una scelta di stile — «una
    /// maniglia, non un pezzo del programma» — ed era il difetto che Giacomo
    /// ha descritto meglio di così: «la barra del titolo non è un tutt'uno
    /// con la finestra ma è una seconda barra sottile superiore, la vorrei
    /// completamente fusa».
    ///
    /// Fonderle richiede tre cose insieme, e nessuna delle tre da sola basta:
    ///
    ///  1. nessuno stacco (`lift` non esiste più);
    ///  2. angoli tondi SOLO in cima, con lo stesso raggio con cui Hyprland
    ///     arrotonda le finestre — altrimenti si vede il salto;
    ///  3. e questa sovrapposizione. Hyprland arrotonda gli angoli in alto
    ///     della finestra, cioè li rende TRASPARENTI: appoggiando la barra al
    ///     bordo senza scendere, sotto i suoi angoli in basso ricompaiono due
    ///     tacche di scrivania. Scendendo di `merge` pixel — esattamente il
    ///     raggio — quelle tacche stanno sotto la barra e non si vedono più.
    ///
    /// Il primo tentativo (documentato nella versione precedente di questo
    /// file) aveva fatto 1 e 2 senza 3, aveva visto le tacche, e ne aveva
    /// concluso che fondere non si potesse fare.
    property int merge: Theme.Effects.radiusSM

    /// Lo spessore della cornice che Hyprland disegna attorno alle finestre
    /// (`general:border_size`). La barra deve disegnare la stessa, o dove le
    /// due si toccano resta un gradino.
    property int borderSize: 2

    readonly property bool it: Core.Strings.lang === "it"

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // ── Senza barre da disegnare, la superficie non deve esistere ────────
    //
    // Qui c'era `visible: bars.enabled`, cioè la superficie restava in piedi
    // anche quando non c'era più niente da disegnarci dentro. Sembra
    // innocuo — è trasparente, e la maschera dei clic si svuota da sé — e non
    // lo è.
    //
    // Una superficie Wayland **tiene sullo schermo l'ultimo fotogramma che ha
    // consegnato**, finché non ne consegna un altro. Quando l'ultima barra se
    // ne va non c'è più niente che cambi qui dentro, quindi Qt non ha ragione
    // di disegnare, quindi non si consegna niente: e sullo schermo resta la
    // fotografia delle barre di prima. Non per un attimo — **per sempre**,
    // finché qualcos'altro non costringe il compositore a ridisegnare.
    //
    // Sono le parole di Giacomo, il 25 agosto 2026: «se premo il tasto per
    // fare gli screenshot scompare, se non premo nulla rimane all'infinito
    // finquando non faccio qualcosa». Si vede cambiando scrivania, che è il
    // modo più facile di restare senza nessuna barra da disegnare.
    //
    // Misurato mentre lo si cercava, e vale la pena scriverlo perché è la
    // strada sbagliata su cui si perde tempo: **la shell aveva ragione da
    // subito.** Il numero della scrivania arriva in 9 millisecondi e l'elenco
    // delle barre si svuota nello stesso istante. Il difetto non era nei dati:
    // era che nessuno li portava sullo schermo.
    //
    // Da spenta la superficie si smonta e il compositore la toglie: è un
    // fatto, non un fotogramma da aspettare. E costa meno, che è un guadagno
    // e non un caso.
    visible: bars.enabled && bars.shown.length > 0

    readonly property int originX: screen ? screen.x : 0
    readonly property int originY: screen ? screen.y : 0

    // ── Quali finestre ───────────────────────────────────────────────────
    //
    // Solo quelle visibili adesso su questo schermo: le ridotte a icona
    // stanno in una scrivania speciale, quelle di un'altra scrivania non si
    // vedono, e una barra del titolo senza la sua finestra sotto è un pezzo
    // di interfaccia che galleggia nel vuoto.

    readonly property int currentWorkspace: Core.Compositore.scrivaniaAttiva

    readonly property var shown: {
        var out = [];
        var all = Core.Windows.all || [];
        for (var i = 0; i < all.length; i++) {
            var w = all[i];
            if (w.minimized || w.fullscreen || w.w <= 0 || w.h <= 0)
                continue;
            if (bars.currentWorkspace >= 0 && w.workspace !== bars.currentWorkspace)
                continue;
            // Le finestre di Minerva la barra ce l'hanno DENTRO
            // (`ui/WindowTitleBar.qml`): disegnargliene una seconda qui sopra
            // vorrebbe dire due barre sulla stessa finestra, e quella
            // disegnata qui è la peggiore delle due — insegue la finestra
            // invece di esserne parte.
            if (w.own)
                continue;
            if (Core.Windows.disegnaLaSua(w.appClass))
                continue;
            out.push(w);
        }
        return out;
    }

    // ── I programmi che la barra se la disegnano da soli ─────────────────
    //
    // Hyprland non ha decorazioni lato server. Non è una mancanza: il
    // protocollo Wayland prevede che sia il compositore a dire al programma se
    // la cornice la disegna lui o se la deve disegnare il programma, e
    // Hyprland — che cornici non ne disegna — dice sempre «fattela tu».
    //
    // Quasi nessun programma la fa davvero, ed è la ragione per cui Minerva
    // gliene disegna una. Ma i browser sì, e parecchie applicazioni GNOME
    // anche: Firefox ha la sua barra dei titoli con le sue schede, Chrome
    // pure. Su quelle la nostra sarebbe la SECONDA barra — due titoli, due
    // file di pulsanti, trenta pixel buttati — ed è esattamente quello che si
    // vede in una delle schermate di Giacomo.
    //
    // L'elenco sta nelle impostazioni e si può cambiare: chi preferisce la
    // barra di Minerva anche su Firefox dice a Firefox di usare quella di
    // sistema (Personalizza → «Barra del titolo») e toglie la voce.
    //
    // La risposta la dà `Core.Windows.disegnaLaSua()` e non una copia locale.
    // Non è un riordino: la stessa domanda serve anche per sapere quanto
    // spazio lasciare a una finestra che si ingrandisce, e due copie che
    // rispondono diversamente vorrebbero dire una barra disegnata dove la
    // finestra non ha lasciato posto — o un buco dove la barra non c'è.

    // ── Chi sta davanti a chi ────────────────────────────────────────────
    //
    // Le barre le disegniamo in un livello che sta SOPRA tutte le finestre.
    // È necessario — devono restare visibili e cliccabili — ma ha un difetto
    // che si vede subito: nessuna finestra le può coprire. Con tre finestre
    // sovrapposte si vedevano tre barre tutte insieme, quella di sotto
    // attraversava quella di sopra, e il pulsante «chiudi» di una finestra
    // nascosta spuntava dal fianco di quella in primo piano. Segnalato da
    // Giacomo guardando lo schermo: «file sta sopra al terminale».
    //
    // Non potendo farle coprire, si TAGLIA quella coperta: si disegna solo la
    // parte che nessuna finestra davanti occupa. Che è, guardando lo schermo,
    // esattamente ciò che si vedrebbe se la cornice fosse della finestra.
    //
    // ── Prima si spegneva, e costava la maniglia ─────────────────────────
    //
    // Qui c'era una riga sola: sovrapposizione, anche di UN pixel, e la barra
    // si spegneva tutta. Con un commento che lo dichiarava come scelta —
    // «il prezzo è che una finestra sfiorata da un angolo perde la maniglia».
    //
    // Quel prezzo era il difetto numero uno di Giacomo, e non si riconosceva
    // come tale: «non ho capito quale sia la condizione nella quale succede ma
    // spesso le finestre non hanno la barra del titolo e devo chiuderle con
    // super+C». La condizione era questa, e non è affatto rara.
    //
    // Misurato, per essere sicuri della causa e non della somiglianza: KCalc a
    // x838..1478, la sua barra a y187..229. Konsole davanti, che finisce a
    // x853. Sovrapposizione: QUINDICI pixel su seicentoquaranta. La barra di
    // KCalc spariva interamente — sopra il menu restava lo sfondo.
    //
    // E c'è la terza faccia dello stesso difetto, che Giacomo ha descritto da
    // sé: «perché quando vado su KCalc e poi mi sposto scompare la barra?».
    // Perché «chi sta davanti» si decide sull'ordine del fuoco: finché KCalc è
    // a fuoco nessuno le sta davanti e la barra c'è; al primo clic altrove
    // quella finestra passa davanti, sfiora la striscia, e la barra si spegne.
    // Cioè: due finestre che si sovrappongono anche appena, e alternandosi si
    // toglievano la maniglia a vicenda.
    //
    // Adesso si taglia. Una barra tagliata è quello che fa una cornice vera, e
    // la parte che resta è ancora una maniglia.
    //
    // ── Il limite che resta, e dove finisce ──────────────────────────────
    //
    // Si taglia in ORIZZONTALE, e si tiene il pezzo libero più largo. Con una
    // finestra davanti a sinistra o a destra — cioè quasi sempre — è esatto.
    // Con una finestra davanti che copre solo il MEZZO della striscia, una
    // cornice vera mostrerebbe entrambi i lati e noi ne mostriamo uno: per
    // mostrarli tutti e due servirebbero due ritagli per barra, e una
    // superficie con un ritaglio per pezzo è la strada per cui non conviene
    // andare — la fa gratis il compositore, se la barra è una sua decorazione
    // (vedi `plugins/minerva-bars`).

    /// Sotto questa larghezza non si disegna niente.
    ///
    /// Non è una soglia di gusto: sotto gli otto pixel quello che resta non è
    /// né una maniglia né una cornice riconoscibile — è una scheggia, e una
    /// scheggia si legge come un errore di disegno. Otto è anche l'ordine di
    /// grandezza del bordo e dell'arrotondamento, cioè del rumore.
    readonly property int minimoVisibile: 8

    /// La parte della barra di `w` che nessuna finestra davanti copre.
    ///
    /// Torna `{x, w}` in coordinate del pannello, oppure `null` se non ne
    /// resta abbastanza da disegnare.
    function libero(w) {
        if (!w)
            return null;

        var bx = w.x - bars.originX;
        var bw = w.w;
        var by = bars.originY + bars.cima(w);
        var bb = by + bars.titleHeight;

        var coperti = [];
        var all = Core.Windows.all || [];
        for (var i = 0; i < all.length; i++) {
            var o = all[i];
            if (o.address === w.address || o.address === "")
                continue;
            if (o.minimized || o.w <= 0 || o.h <= 0)
                continue;
            if (o.workspace !== w.workspace)
                continue;

            // Le finestre libere stanno sempre sopra quelle affiancate; fra
            // pari conta chi è stato toccato più di recente, che in Hyprland
            // è anche chi è stato alzato per ultimo.
            var above = (o.floating && !w.floating)
                     || (o.floating === w.floating && o.stack < w.stack);
            if (!above)
                continue;

            if (o.y >= bb || o.y + o.h <= by)
                continue;

            var a = o.x - bars.originX;
            var b = a + o.w;
            if (b <= bx || a >= bx + bw)
                continue;

            coperti.push([Math.max(a, bx), Math.min(b, bx + bw)]);
        }

        if (coperti.length === 0)
            return { "x": bx, "w": bw };

        coperti.sort(function (p, q) { return p[0] - q[0]; });

        // Il buco più largo fra le zone coperte, scorrendole in ordine.
        var miglioreX = bx;
        var migliore = 0;
        var cursore = bx;
        for (var j = 0; j < coperti.length; j++) {
            if (coperti[j][0] > cursore && coperti[j][0] - cursore > migliore) {
                migliore = coperti[j][0] - cursore;
                miglioreX = cursore;
            }
            if (coperti[j][1] > cursore)
                cursore = coperti[j][1];
        }
        if (bx + bw - cursore > migliore) {
            migliore = bx + bw - cursore;
            miglioreX = cursore;
        }

        if (migliore < bars.minimoVisibile)
            return null;
        return { "x": miglioreX, "w": migliore };
    }

    /// Quanto spazio è riservato in cima allo schermo dalla barra della
    /// scrivania. Sopra quella linea non si può disegnare niente: la barra di
    /// sistema sta su un livello più alto e coprirebbe tutto.
    ///
    /// Lo dice il COMPOSITORE, non `Theme.Effects.barHeight`. Erano lo stesso
    /// numero finché la barra era una sola e alta quarantaquattro, e lo sono
    /// ancora — ma sono due cose diverse: la seconda è quanto è alta la barra,
    /// il primo è quanto spazio si è fatta lasciare. Con una seconda superficie
    /// esclusiva (un pannello, un'altra barra) i due numeri si separano, e a
    /// separarsi in silenzio è la posizione di ogni barra del titolo dello
    /// schermo. L'altezza resta come ripiego per l'istante prima che il
    /// compositore risponda.
    readonly property int reservedTop: {
        var u = Core.Windows.usable;
        return u ? Math.max(0, u.y - bars.originY) : Theme.Effects.barHeight;
    }

    /// Vero quando sopra la finestra NON c'è posto per la sua barra.
    ///
    /// Succedeva in silenzio: la barra finiva sotto quella della scrivania e
    /// sembrava sparita. In una schermata di Giacomo il terminale a tutto
    /// schermo non ha barra del titolo, e in un'altra se ne vede metà.
    ///
    /// È un ripiego, e da quando esiste `abbassa()` qui sotto capita solo per
    /// un istante — il tempo che il compositore risponda — oppure per una
    /// finestra che non si può spostare.
    function dentro(w) {
        return (w.y - bars.originY - bars.titleHeight) < bars.reservedTop;
    }

    // ── Fare posto alla barra ────────────────────────────────────────────
    //
    // Una finestra portata troppo in alto finisce sotto la barra della
    // scrivania insieme alla propria barra del titolo, e l'unica cosa che si
    // potrebbe fare è disegnargliela DENTRO, cioè sopra i primi quaranta pixel
    // del programma. Su un terminale è una riga di testo, su un browser è la
    // fila delle schede.
    //
    // Si preferisce spostare la finestra di quel tanto che serve. È anche ciò
    // che fa qualunque altro ambiente: la barra del titolo di una finestra non
    // si può spingere fuori dallo schermo, perché è la maniglia con cui la si
    // riprende.
    //
    // Il calcolo sta in `Core.Windows.assicuraSpazio()` e non più qui, e non
    // è un riordino: qui girava su `bars.shown`, cioè soltanto sulle finestre
    // che ricevono una barra DA NOI, e lasciava fuori proprio le due categorie
    // che il difetto colpiva — le finestre di Minerva e i programmi che la
    // barra se la disegnano da soli.
    //
    // Qui resta l'unica cosa che è davvero di questo file: NON farlo mentre si
    // trascina. Lì la posizione la decidiamo noi, e una correzione di mezzo
    // rimetterebbe la finestra dove era prima.
    function abbassa() {
        if (drag.active)
            return;
        Core.Windows.assicuraSpazio();
    }

    /// La cima della barra, in coordinate del pannello.
    function cima(w) {
        return bars.dentro(w) ? (w.y - bars.originY)
                              : (w.y - bars.originY - bars.titleHeight);
    }

    // ── Perché durante il trascinamento NON si interroga Hyprland ────────
    //
    // Qui c'era un controllo ogni 60 millisecondi mentre si trascinava, per
    // seguire la finestra che si muove. Era la ragione per cui il
    // trascinamento non ha mai funzionato, e il motivo è tutto in una riga
    // più sotto: `model: bars.shown.slice(0, 6)`.
    //
    // Ogni controllo produce un elenco NUOVO. Un Repeater con un elenco nuovo
    // butta via i suoi delegati e li ricostruisce — compresa l'area del mouse
    // che sta tenendo il pulsante premuto. A quel punto Qt non ha più nessuno
    // a cui consegnare i movimenti, e il trascinamento moriva dopo tre
    // fotogrammi: la finestra si staccava, faceva due passi e si fermava,
    // senza mai arrivare a un bordo. Sembrava un problema di Wayland; era un
    // elenco ricostruito sotto le proprie mani.
    //
    // Mentre si trascina non serve chiedere niente a nessuno: dove sta la
    // finestra lo sappiamo noi, perché siamo noi a spostarla. La barra segue
    // il puntatore da sola (vedi `x` e `y` del delegato), e appena si lascia
    // si rilegge tutto una volta.
    // ── Qui non si guarda più: si riceve ─────────────────────────────────
    //
    // C'era un timer che rileggeva l'elenco delle finestre — sessanta
    // millisecondi mentre qualcosa si muoveva, novecento a riposo — e ogni
    // lettura era un processo `hyprctl` che nasceva e moriva. Con la barra, il
    // gestore file e le Impostazioni aperti erano tre processi diversi che
    // chiedevano la stessa cosa allo stesso compositore, senza sapere l'uno
    // dell'altro: fino a diciannove `hyprctl` al secondo, e tre risposte
    // scattate in tre istanti diversi.
    //
    // Adesso la domanda la fa il demone, una volta, e la risposta arriva a
    // tutti: `services/finestre_service.dart`. Reagisce agli eventi del
    // compositore, quindi il ritardo passa da «fino a novecento
    // millisecondi» a «trenta», e accelera da sé mentre qualcosa si muove.
    //
    // Attenzione: da qui NON va rimessa una lettura periodica. `refresh()`
    // adesso è un messaggio al demone, non una lettura: chiamarlo in un timer
    // sarebbe traffico a vuoto che non anticipa niente, perché lo stato
    // arriverebbe comunque.

    /// Tutto ciò che di una finestra può cambiare una barra, in una stringa.
    ///
    /// Serve solo a capire se è cambiato QUALCOSA: `Core.Windows.all` è un
    /// elenco nuovo a ogni lettura, quindi confrontarlo per identità direbbe
    /// sempre «sì», e si rifarebbe il modello sessanta volte al secondo.
    ///
    /// ── Perché non c'è solo la geometria ─────────────────────────────────
    ///
    /// Qui c'erano soltanto indirizzo e rettangolo, e quel «soltanto» era un
    /// difetto vero: spostando una finestra su un'altra scrivania la sua
    /// geometria non cambia di un pixel, quindi la firma restava identica,
    /// quindi `syncModel()` non veniva mai chiamata — e la barra restava
    /// disegnata sulla scrivania di prima, sopra il vuoto, con sotto nessuna
    /// finestra. Un rettangolo con scritto un nome e quattro pulsanti, e il
    /// pulsante «chiudi» chiudeva una finestra che non si vedeva.
    ///
    /// Lo stesso valeva per ridurre a icona e per lo schermo intero: due modi
    /// diversi di lasciare una barra orfana sullo schermo.
    ///
    /// La regola è che qui dentro deve esserci TUTTO ciò che `shown` guarda.
    function _firma() {
        var all = Core.Windows.all || [];
        var s = "";
        for (var i = 0; i < all.length; i++) {
            var w = all[i];
            s += w.address + ":" + w.x + "," + w.y + "," + w.w + "," + w.h
               + "," + w.workspace + "," + (w.minimized ? 1 : 0)
               + "," + (w.fullscreen ? 1 : 0) + "," + w.title + ";";
        }
        return s + "@" + bars.currentWorkspace;
    }

    property string _geometrie: ""

    // ── Il modello segue `shown`, e nient'altro ──────────────────────────
    //
    // Qui il modello si rifaceva soltanto quando cambiava la firma qui sopra,
    // e ci si è bruciati un'ora a capire perché una barra restava sbagliata.
    //
    // Era il legame ad essere sbagliato, non la firma. Il modello deve
    // rispecchiare `shown`: legarlo a un riassunto di `Core.Windows.all`
    // vuol dire che ogni volta che ci si dimentica un campo — la scrivania,
    // «ridotta a icona», lo schermo intero — il modello e ciò che si deve
    // vedere restano indietro l'uno rispetto all'altro, in silenzio.
    //
    // Quello che si vedeva, spostando una finestra su un'altra scrivania e
    // tornando indietro: la barra di una finestra che sta ALTROVE, disegnata
    // sopra il vuoto, con sotto un'altra finestra senza la sua. Il pulsante
    // «chiudi» chiudeva una finestra che non si vedeva.
    //
    // `onShownChanged` è il legame giusto, ed è anche il più semplice:
    // `syncModel()` è già un confronto e aggiorna sul posto, quindi chiamarla
    // quando non serve non costa e non distrugge niente — nemmeno un
    // trascinamento in corso.
    onShownChanged: {
        bars.syncModel();
        bars.rifaiRegioni();
    }

    /// Le conseguenze di un movimento: fare posto alle barre. Va fatta solo se
    /// è cambiato qualcosa davvero — `abbassa()` manda comandi al compositore,
    /// e mandarli sessanta volte al secondo per niente è il modo più veloce di
    /// far scattare tutto.
    ///
    /// Il «guardare più spesso finché le finestre si fermano» che stava qui è
    /// passato al demone, che è l'unico posto da cui vale la pena guardare.
    function riallinea() {
        var s = bars._firma();
        if (s === bars._geometrie)
            return;
        bars._geometrie = s;
        bars.abbassa();
    }

    Connections {
        target: Core.Windows
        function onAllChanged() { bars.riallinea(); }
    }

    // Cambiare scrivania non cambia nessuna finestra: cambia QUALI si vedono.
    // Il modello lo segue da sé (`onShownChanged`); qui si chiede lo stato
    // perché il demone non ha nessun motivo di mandarlo — per lui non è
    // cambiato niente, e ha ragione: è cambiato solo che cosa guardiamo noi.
    onCurrentWorkspaceChanged: Core.Windows.refresh()

    // Portare avanti una finestra cambia CHI COPRE CHI, e quindi quali barre
    // si vedono. Aspettare il prossimo giro del controllo qui sopra vorrebbe
    // dire fino a due secondi con la barra sbagliata sullo schermo: si clicca
    // una finestra, viene avanti, e la barra di quella dietro le resta
    // addosso. Si rilegge subito.
    //
    // Il breve ritardo serve perché nell'istante in cui Hyprland annuncia il
    // nuovo fuoco non ha ancora finito di riordinare le finestre: chiedendo
    // l'elenco all'istante si ottiene quello di prima.
    Timer {
        id: restack
        interval: 90
        onTriggered: Core.Windows.refresh()
    }

    Connections {
        target: Core.Windows
        function onActiveAddressChanged() {
            // Non durante un trascinamento: lì la posizione la sappiamo noi,
            // e una rilettura di mezzo rimetterebbe la barra dove la finestra
            // era prima.
            if (bars.enabled && !drag.active)
                restack.restart();
        }
    }

    // ── Trascinamento e aggancio ─────────────────────────────────────────

    QtObject {
        id: drag

        property bool active: false
        property string address: ""
        property real grabX: 0        // dove si è preso, dentro la finestra
        property real grabY: 0
        property real pointerX: 0
        property real pointerY: 0
        property bool wasTiled: false

        /// Il monitor sotto il puntatore mentre si trascina: è LÌ che
        /// l'aggancio deve scattare, non sul monitor attivo. Con due schermi
        /// il puntatore può benissimo stare su quello senza fuoco.
        readonly property var spazioSotto: {
            if (!drag.active)
                return null;
            return Core.Windows.spazioPerPunto(drag.pointerX + bars.originX,
                                               drag.pointerY + bars.originY);
        }

        /// Zona di aggancio sotto il puntatore: "", "left", "right", "top",
        /// "tl", "tr", "bl", "br".
        readonly property string zone: {
            if (!drag.active || !drag.spazioSotto)
                return "";
            var e = bars.snapEdge;
            var u = drag.spazioSotto;
            var gx = drag.pointerX + bars.originX;
            var gy = drag.pointerY + bars.originY;
            // ── La fascia si misura sul bordo VERO dello schermo ─────────
            //
            // Qui si usava `bars.width`/`bars.height`, cioè la superficie
            // INTERA: con due monitor il bordo destro esisteva solo sul
            // monitor più a destra, e trascinare verso il bordo del primo
            // non agganciava niente. Sopra c'è la barra della scrivania,
            // che il puntatore può toccare: la fascia parte dal bordo
            // fisico (`s*`), mentre il bersaglio sta nello spazio utile —
            // vedi `zoneRect`.
            var sx = u.sx !== undefined ? u.sx : u.x;
            var sy = u.sy !== undefined ? u.sy : u.y;
            var sw = u.sw !== undefined ? u.sw : u.w;
            var sh = u.sh !== undefined ? u.sh : u.h;
            var nearL = gx <= sx + e;
            var nearR = gx >= sx + sw - e;
            var nearT = gy <= sy + e;
            var nearB = gy >= sy + sh - e;
            // Gli angoli hanno la precedenza: chi punta un angolo vuole un
            // quarto di schermo, non metà.
            if (nearT && nearL) return "tl";
            if (nearT && nearR) return "tr";
            if (nearB && nearL) return "bl";
            if (nearB && nearR) return "br";
            if (nearT) return "top";
            if (nearL) return "left";
            if (nearR) return "right";
            return "";
        }
    }

    /// Rettangolo in cui finirebbe la finestra, in coordinate del pannello.
    ///
    /// ── Dentro lo spazio UTILE, non dentro lo schermo ────────────────────
    ///
    /// Qui si partiva da `bars.width`/`bars.height`, cioè dallo schermo intero:
    /// il pannello delle barre ignora le zone riservate (`ExclusionMode.Ignore`)
    /// perché deve poter disegnare ovunque. Agganciando una finestra a sinistra
    /// o in alto la si mandava quindi a otto pixel dal bordo dello schermo — e
    /// otto pixel dal bordo dello schermo, con una barra della scrivania alta
    /// quarantaquattro, vuol dire sotto la barra della scrivania.
    ///
    /// Il risultato era la finestra «incollata alla barra e senza barra del
    /// titolo»: agganciata, con la propria maniglia nascosta sotto la barra di
    /// sistema. La correzione automatica la rimetteva poi al suo posto, ma
    /// senza ridimensionarla — quindi la finestra usciva dal bordo basso di
    /// tanti pixel quanti ne era stata spinta giù.
    ///
    /// Lo spazio utile lo dice il compositore (`Core.Windows.usable`), che è
    /// anche ciò da cui dipende «ingrandisci»: una finestra agganciata in alto
    /// e una ingrandita devono coincidere, o si vede il salto.
    ///
    /// ── Metà schermo è METÀ schermo ──────────────────────────────────────
    ///
    /// Qui c'era un margine di otto pixel su ogni lato, e sembrava una scelta
    /// di stile. Non lo era: rompeva tre cose insieme.
    ///
    /// La prima è la promessa. «Mezzo schermo» con ventiquattro pixel di
    /// grondaia in mezzo non è mezzo schermo, e due finestre affiancate non
    /// coprono quello che si vede.
    ///
    /// La seconda è la frase qui sopra, scritta e non mantenuta: trascinare in
    /// alto e premere «ingrandisci» devono dare la stessa finestra, e
    /// `Windows.maximize` riempie lo spazio utile senza nessun margine.
    ///
    /// La terza è la peggiore, e si vede solo con due finestre accanto: le
    /// finestre ALTRUI si agganciano da un'altra strada — `aggancio.cpp` dentro
    /// il compositore, perché la loro barra non è la nostra — e quella non ha
    /// mai avuto margini. Konsole a sinistra toccava il bordo, il gestore file
    /// a sinistra si fermava otto pixel prima. Stesso gesto, due risultati:
    /// esattamente il «se un utente installa una app non Minerva avrà sempre
    /// problemi» che Giacomo teme.
    ///
    /// Se un giorno si rivuole l'aria intorno alle finestre agganciate, va
    /// messa in tutti e tre i posti — qui, in `aggancio.cpp` e in `maximize` —
    /// o torna la stessa incoerenza.
    ///
    /// ── Il rettangolo è quello del monitor SOTTO IL PUNTATORE ────────────
    ///
    /// Qui si leggeva `Core.Windows.usable`, cioè lo spazio del monitor
    /// ATTIVO. Con due schermi, trascinando sul monitor senza fuoco la zona
    /// veniva calcolata sulle misure dell'altro e la finestra agganciata
    /// saltava di schermo. Il conto vero sta in `Core.Windows.rectZona`, che
    /// è lo stesso per la shell e per le prove.
    function zoneRect(zone) {
        var u = drag.active
            ? drag.spazioSotto
            : Core.Windows.usable;
        var r = Core.Windows.rectZona(zone, u);
        if (!r)
            return null;
        return { "x": r.x - bars.originX, "y": r.y - bars.originY,
                 "w": r.w, "h": r.h };
    }

    function beginDrag(address, tiled, insideX, insideY, px, py) {
        // Il demone deve guardare da vicino finché si trascina: è l'unica cosa
        // che il compositore non gli annuncia. Vedi `Ipc.seguiFinestre`.
        Core.Ipc.seguiFinestre(true);
        // La garanzia sullo spazio sta zitta finché la mano è giù: la
        // posizione la decidiamo noi, e una correzione di mezzo rimetterebbe
        // la finestra dove era prima.
        Core.Windows.avvisaTrascinamento(true);
        drag.address = address;
        drag.wasTiled = tiled;
        drag.grabX = insideX;
        drag.grabY = insideY;
        drag.pointerX = px;
        drag.pointerY = py;
        drag.active = true;
        // Dov'era alla presa: serve a `spingi()` per riconoscere il primo
        // movimento vero — e solo lì scordare la memoria di «ingrandisci».
        spinta.x0 = Math.round(bars.originX + px - drag.grabX);
        spinta.y0 = Math.round(bars.originY + py - drag.grabY + bars.titleHeight);
        spinta.spostata = false;
        // Trascinare una finestra affiancata la stacca, come su ogni altro
        // ambiente: si prende la barra per spostarla, e una finestra
        // affiancata non si può spostare restando dov'è.
        if (tiled)
            Core.Compositore.libera(address);
    }

    // ── Perché il movimento passa da un timer ────────────────────────────
    //
    // Un mouse manda anche duecento movimenti al secondo. Mandare a Hyprland
    // un `movewindowpixel` per ognuno vuol dire duecento andate e ritorni sul
    // socket al secondo, e ognuna blocca il filo dell'interfaccia finché il
    // compositore non risponde: la barra smette di seguire il puntatore, e
    // quando riprende salta. È il difetto che Giacomo ha descritto come «non
    // ho uno scorrimento fluido spostando con il mouse le finestre… se le
    // sposto velocemente non hanno fluidità».
    //
    // Adesso ogni movimento aggiorna solo dei numeri — la barra li segue
    // all'istante, perché è disegnata da noi — e alla finestra vera si parla
    // una volta per fotogramma. Sedici millisecondi sono la durata di un
    // fotogramma a sessanta hertz: più spesso di così nessuno lo vedrebbe.
    function moveDrag(px, py) {
        if (!drag.active)
            return;
        drag.pointerX = px;
        drag.pointerY = py;
        if (!spinta.running)
            spinta.start();
    }

    Timer {
        id: spinta
        interval: 16
        repeat: true
        running: false
        onTriggered: {
            if (!drag.active) {
                spinta.stop();
                return;
            }
            spinta.spingi();
        }

        /// Manda alla finestra la posizione voluta adesso.
        ///
        /// Va chiamata anche al RILASCIO: senza, la finestra si ferma dove
        /// era arrivata l'ultima volta che il timer ha suonato e non dove si
        /// è lasciato il mouse — fino a un fotogramma di scarto, che su un
        /// movimento veloce sono decine di pixel, e si vede come una finestra
        /// che rimbalza indietro.
        function spingi() {
            var x = Math.round(bars.originX + drag.pointerX - drag.grabX);
            var y = Math.round(bars.originY + drag.pointerY - drag.grabY
                               + bars.titleHeight);
            // Se la finestra è già lì non si dice niente: fermando la mano su
            // un trascinamento, il timer continuerebbe a ripetere lo stesso
            // comando sessanta volte al secondo per niente.
            if (x === spinta.ultimoX && y === spinta.ultimoY)
                return;
            // ── La memoria di «ingrandisci» si scorda qui, non alla presa ─
            //
            // Va scordata solo quando la finestra si MUOVE davvero. Alla
            // presa no: un doppio clic preme due volte, e scordare a ogni
            // pressione buttava via la posizione da ripristinare proprio
            // mentre il secondo clic la chiedeva — il doppio clic che
            // ingrandiva e non tornava mai indietro.
            if (!spinta.spostata && (x !== spinta.x0 || y !== spinta.y0)) {
                spinta.spostata = true;
                Core.Windows.scordaSalvata("address:" + drag.address);
            }
            spinta.ultimoX = x;
            spinta.ultimoY = y;
            Core.Compositore.sposta(drag.address, x, y);
        }
        property int ultimoX: -99999
        property int ultimoY: -99999
        /// Dov'era la finestra alla presa: è il confronto che distingue un
        /// trascinamento da un clic fermo.
        property int x0: -1
        property int y0: -1
        /// Vero da quando la finestra si è spostata davvero.
        property bool spostata: false
    }

    function endDrag() {
        Core.Ipc.seguiFinestre(false);
        Core.Windows.avvisaTrascinamento(false);
        if (!drag.active)
            return;
        spinta.spingi();
        spinta.stop();
        var zone = drag.zone;
        var addr = drag.address;
        // Il rettangolo si legge PRIMA di abbassare `active`: la zona è del
        // monitor sotto il puntatore, e da spenta `spazioSotto` non risponde.
        var bersaglio = zone !== "" ? bars.zoneRect(zone) : null;
        drag.active = false;
        // Il fuoco si dà ADESSO e non alla pressione.
        //
        // Dandolo alla pressione, `focuswindow` faceva cambiare a Hyprland la
        // finestra sotto il puntatore, e il puntatore se ne andava dalla
        // nostra barra portandosi via il trascinamento appena cominciato: si
        // premeva, la finestra si staccava, e da lì in poi non succedeva più
        // niente.
        Core.Windows.focus(addr);
        if (bersaglio) {
            // Prima la dimensione e poi la posizione: al contrario, una
            // finestra che cresce dal proprio angolo in alto a sinistra si
            // sposta da sola e il risultato è fuori posto di qualche
            // decina di pixel.
            // La cornice di Hyprland sta FUORI dal rettangolo della
            // finestra: senza toglierla, una finestra agganciata a
            // sinistra ha la sua linea accesa per metà fuori dallo
            // schermo. Stesso conto di `Windows.maximize`, e per lo
            // stesso motivo — vedi `Windows.bordo`.
            var b = Core.Windows.bordo;
            Core.Compositore.ridimensiona(addr, bersaglio.w - 2 * b,
                                          bersaglio.h - bars.titleHeight - 2 * b);
            Core.Compositore.sposta(addr, bars.originX + bersaglio.x + b,
                                    bars.originY + bersaglio.y + bars.titleHeight + b);
        }
        drag.address = "";
        Core.Windows.refresh();
    }

    // ── Zone cliccabili ──────────────────────────────────────────────────
    //
    // Solo le barre. Il resto della finestra, che copre tutto lo schermo,
    // deve lasciar passare ogni clic: è alta 1080 pixel ed è quasi tutta
    // vuota. Mentre si trascina invece prende tutto, perché deve sentire il
    // puntatore ovunque vada — anche fuori dalla barra da cui è partito.

    // ── Perché i rettangoli si creano invece di dichiararli ──────────────
    //
    // Erano SEI, scritti a mano uno sotto l'altro, e sei era anche il taglio
    // del modello (`shown.slice(0, 6)`): dalla settima finestra in poi la barra
    // non era «non cliccabile», era proprio assente. Con l'affiancamento sei
    // riquadri sullo stesso schermo erano già illeggibili e il limite non si
    // incontrava mai; da quando in Minerva ogni finestra è libera e si
    // sovrappone alle altre, sette finestre aperte sono una giornata normale.
    // È uno dei modi in cui una finestra si ritrova senza barra del titolo.
    //
    // `Region` non è un Item, quindi un `Repeater` non lo sa creare. Ma
    // `regions` è una lista, e a una lista si può assegnare un array: i
    // rettangoli si costruiscono uno per barra e si aggiornano sul posto,
    // esattamente come il modello — e i due non possono più contare fino a
    // numeri diversi.
    //
    // Il primo dell'elenco non è una barra: è lo schermo intero mentre si
    // trascina, perché lì il puntatore va seguito ovunque vada, anche fuori
    // dalla barra da cui è partito.

    Component {
        id: pezzoRegione
        Region {}
    }

    property var regioni: []

    function rifaiRegioni() {
        var n = bars.shown.length;
        var out = bars.regioni.slice();

        while (out.length < n + 1)
            out.push(pezzoRegione.createObject(bars));
        while (out.length > n + 1)
            out.pop().destroy();

        var t = out[0];
        t.x = drag.active ? 0 : -1;
        t.y = drag.active ? 0 : -1;
        t.width = drag.active ? bars.width : 0;
        t.height = drag.active ? bars.height : 0;

        for (var i = 0; i < n; i++) {
            var r = bars.rettangolo(i);
            var reg = out[i + 1];
            reg.x = r.x; reg.y = r.y;
            reg.width = r.w; reg.height = r.h;
        }

        bars.regioni = out;
    }

    /// Il rettangolo cliccabile della barra numero `i`, o niente.
    ///
    /// Deve coincidere con ciò che si VEDE, non con ciò che la barra sarebbe
    /// se nessuno la coprisse: la parte nascosta sotto una finestra davanti,
    /// se restasse fra i rettangoli, continuerebbe a mangiarsi i clic
    /// destinati a quella finestra. Il buco resta dov'è la barra, e chi clicca
    /// non ha modo di indovinarlo.
    function rettangolo(i) {
        var w = bars.shown[i];
        if (!w)
            return { "x": -1, "y": -1, "w": 0, "h": 0 };

        // Quella che si trascina è per definizione davanti, e la sua posizione
        // la decidiamo noi: non si va a cercare che cosa la copre.
        if (drag.active && drag.address === w.address)
            return {
                "x": drag.pointerX - drag.grabX,
                "y": Math.max(0, drag.pointerY - drag.grabY),
                "w": w.w,
                "h": bars.titleHeight
            };

        var p = bars.libero(w);
        if (!p)
            return { "x": -1, "y": -1, "w": 0, "h": 0 };
        return {
            "x": p.x,
            "y": bars.cima(w),
            "w": p.w,
            "h": bars.titleHeight
        };
    }

    // Le due cose che spostano un rettangolo: dove sono le finestre (`shown`,
    // che si rifà a ogni lettura) e se si sta trascinando.
    Connections {
        target: drag
        function onActiveChanged() { bars.rifaiRegioni(); }
    }
    Component.onCompleted: bars.rifaiRegioni()

    mask: Region {
        regions: bars.regioni
    }

    // ── Anteprima della zona di aggancio ─────────────────────────────────

    Rectangle {
        id: preview
        visible: drag.active && drag.zone !== ""
        readonly property var r: bars.zoneRect(drag.zone) || { "x": 0, "y": 0, "w": 0, "h": 0 }

        x: preview.r.x
        y: preview.r.y
        width: preview.r.w
        height: preview.r.h

        radius: Theme.Effects.radiusMD
        color: Qt.alpha(Theme.Colors.accent, 0.16)
        border.width: 2
        border.color: Qt.alpha(Theme.Colors.accent, 0.75)

        Behavior on x { NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic } }
    }

    // ── La rete: un trascinamento non può restare aperto ─────────────────
    //
    // Mentre si trascina, la maschera di questo strato è LO SCHERMO INTERO
    // (vedi `rifaiRegioni`): serve a seguire il puntatore anche fuori dalla
    // barra da cui è partito. Ma questo strato sta sopra tutte le finestre e
    // sopra la dock, quindi finché la maschera è aperta **ogni clic dello
    // schermo arriva qui e non arriva a nessun altro**.
    //
    // Se `active` resta acceso senza che nessuno lo spenga, la scrivania
    // smette di rispondere ai clic pur continuando a disegnarsi: si clicca una
    // finestra dietro e non viene avanti, si clicca la dock e non succede
    // niente. Non sembra un blocco — sembra che le finestre non si portino più
    // davanti.
    //
    // ── Il segnale giusto, e quello sbagliato ──────────────────────────
    //
    // Sbagliato: «fermo da tre secondi». Restare fermi a decidere dove
    // agganciare è un gesto normale, e una rete così farebbe cadere la presa
    // proprio a chi ci sta pensando.
    //
    // Giusto: **il pulsante non è più premuto.** Se il tasto è su e noi
    // crediamo ancora di trascinare, il rilascio si è perso — non c'è nessun
    // altro modo di leggerlo. E la seconda condizione è che la finestra che si
    // stava trascinando non ci sia più: chiusa o andata su un'altra
    // scrivania, il suo rilascio non arriverà mai.
    Timer {
        id: reteDiSicurezza
        interval: 500
        repeat: true
        running: drag.active
        onTriggered: {
            if (!drag.active)
                return;
            if (!raccoglitore.pressed
                || !Core.Windows.find("address:" + drag.address))
                bars.endDrag();
        }
    }

    // Raccoglie il puntatore mentre si trascina, ovunque vada.
    MouseArea {
        id: raccoglitore
        anchors.fill: parent
        visible: drag.active
        enabled: drag.active
        acceptedButtons: Qt.LeftButton
        onPositionChanged: function(m) { bars.moveDrag(m.x, m.y); }
        onReleased: bars.endDrag()
        onCanceled: bars.endDrag()
    }

    // ── Le barre ─────────────────────────────────────────────────────────

    // ── Il modello, e perché è un ListModel ──────────────────────────────
    //
    // Qui c'era `model: bars.shown.slice(0, 6)`, cioè un array JavaScript
    // ricalcolato a ogni lettura di `hyprctl clients`. Un Repeater con un
    // array nuovo non aggiorna i delegati: li DISTRUGGE e li ricostruisce.
    //
    // Costava due cose. La prima è che il trascinamento moriva dopo tre
    // fotogrammi, perché a essere distrutta era anche l'area del mouse che
    // stava ricevendo il trascinamento — ed è per questo che il controllo era
    // stato portato a due secondi e fermato durante il trascinamento. La
    // seconda è che a ogni lettura tutto ripartiva da zero: animazioni,
    // passaggio del mouse, immagini da ricaricare.
    //
    // Un ListModel aggiornato SUL POSTO non ha nessuno dei due problemi. Le
    // righe restano le stesse finché la finestra esiste; cambiano solo i
    // valori, e i delegati se ne accorgono senza morire. È ciò che permette
    // di leggere ogni sessanta millisecondi mentre una finestra si muove.
    //
    // `dynamicRoles` perché ogni riga porta l'intero oggetto della finestra in
    // un campo solo: con i ruoli fissi bisognerebbe elencare a mano tutti i
    // suoi campi qui e in tre punti del delegato.
    ListModel {
        id: barModel
        dynamicRoles: true
    }

    /// Allinea il modello a `shown` senza ricostruirlo.
    function syncModel() {
        // Tutte, e non le prime sei. Il taglio a sei c'era perché la maschera
        // dei clic aveva sei rettangoli scritti a mano: adesso i rettangoli si
        // creano, e non c'è più nessun numero da far coincidere.
        var wanted = bars.shown;

        // Via le finestre che non ci sono più.
        for (var i = barModel.count - 1; i >= 0; i--) {
            var vivo = false;
            for (var j = 0; j < wanted.length; j++) {
                if (wanted[j].address === barModel.get(i).address) {
                    vivo = true;
                    break;
                }
            }
            if (!vivo)
                barModel.remove(i);
        }

        // Le altre: al posto giusto, con i valori aggiornati.
        for (var k = 0; k < wanted.length; k++) {
            var w = wanted[k];
            var dove = -1;
            for (var m = 0; m < barModel.count; m++) {
                if (barModel.get(m).address === w.address) {
                    dove = m;
                    break;
                }
            }
            if (dove === -1) {
                barModel.insert(Math.min(k, barModel.count),
                                { "address": w.address, "win": w });
            } else {
                if (dove !== k)
                    barModel.move(dove, k, 1);
                // `setProperty` e non `set`: `set` riscrive la riga intera e
                // il delegato la vede come un'altra finestra.
                barModel.setProperty(k, "win", w);
            }
        }
    }

    Repeater {
        model: barModel

        // ── La gabbia che taglia ─────────────────────────────────────────
        //
        // Il delegato non è più la barra: è il pezzo di barra che si VEDE. La
        // barra vera sta dentro, intera e sempre della larghezza della
        // finestra, e sborda dai lati coperti.
        //
        // Serve un contenitore a parte perché `clip` ritaglia i FIGLI, non sé
        // stesso: se la barra fosse ancora il delegato, restringerla per
        // tagliarla stringerebbe anche il titolo e i pulsanti — che si
        // riposizionerebbero, invece di essere coperti. Un titolo che si
        // ricentra man mano che un'altra finestra gli passa davanti è più
        // fastidioso della barra che spariva.
        delegate: Item {
            id: gabbia
            required property var win
            required property int index

            readonly property var modelData: gabbia.win

            /// Vero per LA barra che si sta trascinando.
            readonly property bool dragged: drag.active
                                            && drag.address === modelData.address

            /// Dove comincia la barra intera, in coordinate del pannello.
            ///
            /// Mentre si trascina la posizione la decidiamo noi, e non la si
            /// chiede a Hyprland: è la stessa che stiamo dando alla finestra,
            /// quindi barra e finestra si muovono insieme senza un giro di
            /// domande in mezzo.
            readonly property real origine: gabbia.dragged
                ? drag.pointerX - drag.grabX
                : modelData.x - bars.originX

            /// La parte che si vede: `{x, w}`, o `null` se non ne resta.
            ///
            /// Mentre si trascina la finestra è per definizione quella davanti:
            /// si vede tutta, e non si va a cercare che cosa la copre.
            readonly property var parte: gabbia.dragged
                ? { "x": gabbia.origine, "w": modelData.w }
                : bars.libero(modelData)

            /// Da che lati la barra è tagliata. Conta per la cornice: dove il
            /// taglio passa non c'è nessun bordo da mostrare, e mostrarlo
            /// lascerebbe una lineetta d'accento in mezzo al nulla, sopra la
            /// finestra che sta davanti.
            readonly property real bordoSx:
                (gabbia.parte && gabbia.parte.x <= gabbia.origine + 0.5)
                    ? bars.borderSize : 0
            readonly property real bordoDx:
                (gabbia.parte && gabbia.parte.x + gabbia.parte.w
                                 >= gabbia.origine + modelData.w - 0.5)
                    ? bars.borderSize : 0

            // Il controllo sta QUI e non dentro `shown`, e la differenza non è
            // di stile: `shown` è il modello del Repeater, e cambiarlo mentre
            // si tiene premuto il pulsante distrugge il delegato che sta
            // ricevendo il trascinamento. È il difetto che ha tenuto fermo
            // l'aggancio ai bordi per giorni. Nascondere un delegato non lo
            // distrugge.
            visible: gabbia.parte !== null
            clip: true

            x: gabbia.parte ? gabbia.parte.x - gabbia.bordoSx : 0
            y: (gabbia.dragged ? Math.max(0, drag.pointerY - drag.grabY)
                               : bars.cima(gabbia.modelData)) - bars.borderSize
            width: gabbia.parte
                ? gabbia.parte.w + gabbia.bordoSx + gabbia.bordoDx : 0
            height: bar.height + bars.borderSize

        Rectangle {
            id: bar

            readonly property var modelData: gabbia.modelData

            readonly property bool isActive:
                modelData.address === Core.Windows.activeAddress

            /// Vero per LA barra che si sta trascinando.
            readonly property bool dragged: gabbia.dragged

            // Dentro la gabbia: la barra sta dove starebbe se nessuno la
            // coprisse, e i lati fuori dalla gabbia vengono ritagliati.
            x: gabbia.origine - gabbia.x
            y: bars.borderSize
            width: modelData.w
            // Più alta di quanto si veda: gli ultimi `merge` pixel stanno
            // sotto il bordo alto della finestra e servono solo a coprire le
            // due tacche lasciate dai suoi angoli arrotondati.
            //
            // Quando la barra è DENTRO la finestra quei pixel non servono:
            // il suo bordo alto è già il bordo alto della finestra, e gli
            // angoli tondi coincidono.
            height: bars.titleHeight + (bars.dentro(bar.modelData) ? 0 : bars.merge)

            // Tonda SOLO in cima, con lo stesso raggio di Hyprland. È ciò che
            // fa leggere barra e finestra come un oggetto solo invece che come
            // due cose appoggiate una sull'altra.
            topLeftRadius: Theme.Effects.radiusSM
            topRightRadius: Theme.Effects.radiusSM
            bottomLeftRadius: 0
            bottomRightRadius: 0

            // Lo STESSO vetro della barra di sistema. Un secondo grigio, anche
            // di poco diverso, si legge come «pezzo di un'altra interfaccia»:
            // era questo a farle sembrare più scure e fuori posto.
            color: bar.isActive ? Theme.Colors.membrane
                                : Qt.alpha(Theme.Colors.membrane, 0.74)

            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            // La cornice, che è LA STESSA che Hyprland disegna attorno alla
            // finestra: stesso spessore, stesso colore, stesso raggio.
            //
            // È il pezzo che mancava perché la fusione si vedesse davvero.
            // Con la barra attaccata ma senza cornice, la linea d'accento
            // correva lungo i tre lati della finestra e si interrompeva di
            // netto dove cominciava la barra: il taglio si vedeva più di
            // prima, perché adesso i due pezzi si toccano.
            //
            // Su tre lati e non quattro: chiuderla sotto rimetterebbe la
            // riga di separazione che si sta cercando di togliere.
            // ── Perché la cornice sta FUORI dalla barra ──────────────────
            //
            // Hyprland disegna il bordo delle finestre all'ESTERNO: su una
            // finestra che comincia a 320, i due pixel di bordo occupano 318 e
            // 319. Questo riquadro invece disegnava il proprio tratto
            // all'interno, cioè su 320 e 321.
            //
            // Due pixel. Ma sono due pixel su una linea che deve essere UNA:
            // la linea d'accento saliva lungo il fianco della finestra e, dove
            // cominciava la barra, faceva un gradino di lato. Misurato: il
            // bordo della finestra sulla colonna 318,8 e quello della barra
            // sulla 320,4.
            //
            // Perciò la tela sborda di `borderSize` a sinistra, a destra e in
            // cima, e il tratto ci sta dentro: finisce esattamente dove
            // Hyprland disegnerebbe il suo. Il raggio degli angoli cresce
            // dello stesso tanto, perché un bordo esterno gira più largo di
            // quello che circonda.
            Canvas {
                id: cornice
                x: -bars.borderSize
                y: -bars.borderSize
                width: bar.width + bars.borderSize * 2
                height: bar.height + bars.borderSize
                antialiasing: true

                /// Il colore è LO STESSO che Hyprland usa per la finestra, e
                /// arriva dallo stesso posto: `Core.WindowRules`. Qui la
                /// velatura della finestra non a fuoco era `rgba(1,1,1,0.13)`
                /// scritta a mano — su un tema chiaro, bianco su bianco.
                readonly property color tinta: bar.isActive
                    ? Qt.alpha(Theme.Colors.accent, 0.95)
                    : Qt.alpha(Theme.Colors.scura ? Qt.rgba(1, 1, 1, 1)
                                                  : Qt.rgba(0, 0, 0, 1),
                               Theme.Colors.scura ? 0.13 : 0.16)
                onTintaChanged: cornice.requestPaint()

                onPaint: {
                    var g = getContext("2d");
                    // Il tratto di un canvas è centrato sulla linea: si parte
                    // da metà spessore per non finire mezzo fuori dalla tela.
                    var s = bars.borderSize;
                    var m = s / 2;
                    var r = Theme.Effects.radiusSM + s;

                    g.reset();
                    g.strokeStyle = cornice.tinta;
                    g.lineWidth = s;
                    g.beginPath();
                    g.moveTo(m, height);
                    g.lineTo(m, m + r);
                    g.arcTo(m, m, m + r, m, r);
                    g.lineTo(width - m - r, m);
                    g.arcTo(width - m, m, width - m, m + r, r);
                    g.lineTo(width - m, height);
                    g.stroke();
                }
            }

            /// La parte che si VEDE come barra. I contenuti si centrano qui
            /// dentro e non nell'altezza totale, altrimenti scenderebbero di
            /// mezzo `merge` verso la finestra.
            Item {
                id: head
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: bars.titleHeight
            }

            // Presa per spostare. Anche il doppio clic sta qui: ingrandisce e
            // rimpicciolisce, come su qualunque barra del titolo del mondo.
            MouseArea {
                anchors.fill: head
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.SizeAllCursor

                onPressed: function(m) {
                    if (m.button === Qt.RightButton) {
                        bars.menuRequested(bar.modelData.address,
                                           mapToGlobal(m.x, m.y));
                        return;
                    }
                    // ── Il punto di presa, e i 42 pixel che salivano ─────
                    //
                    // Qui c'era `m.y + bars.titleHeight`, sempre. E
                    // `spingi()` mette la finestra a «cima della barra +
                    // titleHeight», cioè sotto la barra. I due conti insieme
                    // danno la finestra un'altezza-di-barra TROPPO IN ALTO:
                    // ogni trascinamento la faceva salire di quarantadue
                    // pixel.
                    //
                    // Misurato col puntatore finto: KCalc da [700,300],
                    // trascinata di (-300,+150), finiva a [400,408] invece di
                    // [400,450]. Scarto 0 in orizzontale, -42 in verticale —
                    // esattamente l'altezza della barra.
                    //
                    // E questo è il difetto che si vedeva come «spesso le
                    // finestre sono incollate alla barra»: non serve una
                    // condizione strana, basta spostare la stessa finestra due
                    // o tre volte. Sale di quarantadue pixel per volta, arriva
                    // sotto la barra della scrivania, e lì `assicuraSpazio()`
                    // la ferma — incollata.
                    //
                    // Perché nessuno l'aveva visto: la somma è GIUSTA per le
                    // finestre che hanno la barra dentro (`dentro()`), cioè
                    // per quelle già schiacciate in cima — che sono proprio
                    // quelle su cui si stava lavorando quando il trascinamento
                    // è stato scritto. Adesso la correzione c'è solo per loro.
                    bars.beginDrag(bar.modelData.address,
                                   !bar.modelData.floating,
                                   m.x,
                                   m.y + (bars.dentro(bar.modelData)
                                          ? bars.titleHeight : 0),
                                   gabbia.x + bar.x + m.x,
                                   gabbia.y + bar.y + m.y);
                }

                // Il trascinamento si segue DA QUI e non dalla superficie che
                // copre lo schermo.
                //
                // Era là, e non funzionava: chi riceve la pressione si tiene
                // il puntatore fino al rilascio: è la regola di Qt, e vale
                // anche se nel frattempo compare qualcosa sopra. La superficie
                // grande non riceveva quindi né i movimenti né il rilascio, e
                // il risultato era una finestra che si staccava, si spostava a
                // metà e non si agganciava a niente — cioè l'aggancio ai bordi
                // esisteva nel codice e non è mai esistito sullo schermo.
                //
                // La posizione vera del puntatore nel pannello, anche mentre la
                // barra si sposta insieme alla finestra: quello che la barra
                // guadagna, `m.x` lo perde.
                //
                // Va sommata anche la gabbia: da quando la barra sta DENTRO un
                // contenitore che la ritaglia, `bar.x` è relativo a quello e
                // non al pannello. Senza `gabbia.x` il trascinamento parte con
                // uno scarto pari a quanto la barra è tagliata a sinistra — e a
                // barra intera lo scarto è `borderSize`, cioè due pixel: un
                // errore piccolo, costante, e quindi facile da guardare senza
                // vederlo.
                onPositionChanged: function(m) {
                    bars.moveDrag(gabbia.x + bar.x + m.x,
                                  gabbia.y + bar.y + m.y);
                }
                onReleased: bars.endDrag()
                onCanceled: bars.endDrag()

                onDoubleClicked: function(m) {
                    if (m.button !== Qt.LeftButton)
                        return;
                    Core.Windows.focus(bar.modelData.address);
                    Core.Windows.maximize("address:" + bar.modelData.address);
                }
            }

            // Icona, titolo al centro e i quattro pulsanti: lo STESSO
            // contenuto delle barre dentro le nostre finestre. Se fosse
            // ridisegnato qui, la differenza si vedrebbe esattamente dove non
            // deve — fra due finestre affiancate, una nostra e una no.
            Ui.TitleBarContent {
                anchors.fill: head
                label: bar.modelData.title || bar.modelData.appClass
                iconPath: {
                    var a = Core.Apps.forWindow(bar.modelData);
                    return (a && a.icon) ? a.icon : "";
                }
                active: bar.isActive
                side: Core.Ipc.get("windows.buttonsSide", "destra")
                // Qui c'era `bar.modelData.maximized === true`, e quel campo
                // non è mai esistito: le finestre che arrivano da
                // `hyprctl clients` non ce l'hanno. Valeva quindi sempre
                // «non ingrandita», e il pulsante non cambiava mai segno —
                // su una finestra già ingrandita continuava a dire
                // «Ingrandisci» e a mostrarne il quadrato.
                maximized: Core.Windows.isMaximized(bar.modelData)

                onMinimizeRequested: Core.Windows.minimize(bar.modelData.address)
                onMaximizeRequested: Core.Windows.maximize(
                    "address:" + bar.modelData.address)
                onFullscreenRequested: Core.Compositore.commutaSchermoIntero(
                    bar.modelData.address)
                onCloseRequested: Core.Windows.close(bar.modelData.address)
            }
        }
        }
    }

    signal menuRequested(string address, point where)
}
