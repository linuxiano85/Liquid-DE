import QtQuick
import Quickshell
import "../core" as Core

// WindowTitleBar — La barra del titolo DENTRO le finestre di Minerva.
//
// ── Perché questo file esiste ────────────────────────────────────────────
//
// Ad agosto 2026 anche le nostre finestre prendevano la barra da una
// superficie a parte, disegnata dalla shell sopra tutto, che inseguiva la
// finestra chiedendo al compositore dove si trovasse. Costava tutto questo:
//
//  · la barra arrivava in ritardo. Spostando la finestra in fretta restava
//    indietro e poi la raggiungeva a scatti; in una schermata di Giacomo si
//    vede staccata di cento pixel dalla finestra a cui appartiene. Nessun
//    inseguimento può essere perfetto: fra il momento in cui la finestra si
//    muove e quello in cui lo veniamo a sapere passa del tempo, e quel tempo
//    si vede.
//  · il vetro era un altro vetro. Due superfici diverse, due trasparenze e
//    due sfocature: si vedeva che la barra era un pezzo riportato.
//  · chi copre chi diventava un problema da risolvere a mano, invece che una
//    cosa che il compositore fa da sé.
//  · a finestra ingrandita la barra finiva SOTTO quella della scrivania,
//    perché sopra la finestra non restava spazio dove disegnarla.
//
// Qui dentro nessuno di questi problemi esiste, e non perché siano stati
// risolti: non si pongono. La barra è la finestra. Si sposta quando si sposta
// la finestra perché è lei che si sposta, ha lo stesso vetro perché è lo
// stesso pixel, e sta davanti a ciò a cui sta davanti la finestra.
//
// ── Lo sfondo ────────────────────────────────────────────────────────────
//
// NESSUNO, ed è il punto di tutto. Questo `Item` non dipinge niente: si vede
// il fondo della finestra, che è già `Theme.Colors.window`. Dipingere qui un colore anche minimamente diverso rimetterebbe la
// riga di separazione che questo file esiste per togliere.
Item {
    id: bar

    /// Il titolo mostrato al centro.
    property string label: ""

    /// L'icona del programma.
    ///
    /// Se la trova da sé invece di farsela passare, e non è pigrizia: le barre
    /// delle finestre ALTRUI l'icona la mostrano sempre (`spine/TitleBars.qml`
    /// la chiede a `Core.Apps`), le nostre non la mostravano mai — nessuno dei
    /// due punti che usano questo componente la passava. Il risultato si vede
    /// mettendo due finestre affiancate, una nostra e una no: due barre
    /// identiche, e in una manca l'icona.
    ///
    /// La domanda è la stessa e la risposta arriva dallo stesso posto: da
    /// `Core.Apps.forWindow()`, che sa già riconoscere le finestre di Minerva
    /// dal titolo — tutte dichiarano la classe `org.quickshell`, e per classe
    /// sarebbero lo stesso programma.
    property string iconPath: {
        var a = Core.Apps.forWindow(bar.mia);
        return (a && a.icon) ? a.icon : "";
    }

    /// Chiudere lo decide la finestra, non noi: il gestore file ha delle
    /// copie in corso da annullare, le Impostazioni no.
    signal closeRequested()

    /// Vero mentre questa è la finestra con cui si sta lavorando.
    ///
    /// Lo chiede alla finestra che la contiene, non a chi la usa:
    /// `FloatingWindow` non espone `active`, ma la proprietà agganciata
    /// `Window` sì, e vale in qualunque punto dell'albero.
    property bool active: Window.active

    /// Da che parte stanno i pulsanti. Si sceglie nelle Impostazioni.
    readonly property string side: Core.Ipc.get("windows.buttonsSide", "destra")

    // ── A schermo intero la barra non c'è ────────────────────────────────
    //
    // E non è una scelta di stile: a schermo intero la finestra parte da zero,
    // quindi la barra finirebbe sotto quella della scrivania — che sta su un
    // livello più alto e la coprirebbe. Provato: i pulsanti diventano
    // incliccabili, e per uscire dallo schermo intero bisogna sapere una
    // scorciatoia.
    //
    // Che una finestra a schermo intero non abbia cornice è anche ciò che fa
    // qualunque altro ambiente. Per uscirne restano Super+F e la linguetta
    // che compare avvicinando il puntatore al bordo alto
    // (`spine/FullscreenBar.qml`).
    //
    // Lo si capisce dalla geometria e non da un interruttore nostro: così
    // resta giusto anche se a mandarla a schermo intero è stato il programma,
    // una scorciatoia, o il compositore.
    /// Questa finestra, come la vede il compositore.
    readonly property var mia: Core.Windows.find(bar.me)

    readonly property bool aTuttoSchermo: bar.mia !== null && bar.mia.fullscreen

    /// Vero quando la finestra riempie già tutto lo spazio utile. Si guarda la
    /// GEOMETRIA e non un interruttore nostro: così resta giusto anche se a
    /// ingrandirla è stata una scorciatoia, un aggancio al bordo o il
    /// programma stesso, e il pulsante mostra sempre il segno che serve.
    readonly property bool maximized: Core.Windows.isMaximized(bar.mia)

    // ── E su una scrivania che non è Minerva, la barra è LORO ────────────
    //
    // Fotografato il 30 agosto 2026, la Calcolatrice aperta dentro COSMIC:
    // **due barre del titolo**, una sopra l'altra. Quella di COSMIC in cima,
    // con i suoi pulsanti, e la nostra subito sotto con i suoi. È la
    // segnalazione «barre del titolo doppiate», vista dal lato delle nostre
    // app invece che da quello del compositore.
    //
    // Non si può togliere quella dell'ospite: un compositore decora le
    // finestre che non gli dicono di no, e dirglielo dal lato di Qt non
    // funziona — provato, `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` impedisce a
    // Qt di disegnarne una sua ma non toglie quella di COSMIC.
    //
    // E soprattutto: **non è quella da togliere.** Una nostra app aperta su
    // GNOME deve avere la barra di GNOME, con i pulsanti dove li ha messi
    // GNOME. La nostra è un pezzo di Minerva, e vive dove vive Minerva.
    //
    // La riga qui sotto è quindi tutta la faccenda: dove Minerva comanda, la
    // barra è nostra e l'ospite non c'è; dove non comanda, la nostra si toglie
    // di mezzo e resta la sua. Una sola, sempre.
    readonly property bool nostraCasa: Core.Compositore.comandabile

    visible: !bar.aTuttoSchermo && bar.nostraCasa
    height: (bar.aTuttoSchermo || !bar.nostraCasa)
            ? 0 : Core.Ipc.get("windows.titleHeight", 34)

    // ── Lo stato della finestra arriva, non si va a prendere ─────────────
    //
    // Lo dice il demone, che ascolta il compositore per tutti: nessuna
    // finestra di Minerva chiede da sé «dove sono e come sto». La rete
    // di sicurezza non è sparita, si è spostata dove ha senso: chi si collega
    // riceve lo stato all'istante (`spingiTutto()`), e se il demone muore il
    // guardiano lo rifà partire e la riconnessione ricomincia da una spinta.
    //
    // Resta questa sola riga, per il caso in cui questa finestra nasca dopo che
    // il demone ha già mandato tutto: chiedere una volta all'avvio costa un
    // messaggio.
    Component.onCompleted: Core.Windows.refresh()

    // ── Che cosa siamo, per il compositore ───────────────────────────────
    //
    // Qui c'era `"pid:" + Quickshell.processId`, e basta. Il ragionamento era
    // che il numero di processo lo sappiamo senza chiedere niente a nessuno,
    // mentre l'indirizzo va cercato nell'elenco delle finestre.
    //
    // Era vero finché ogni applicazione era un processo suo. **Non lo è più.**
    // Calcolatrice, Editor, Anteprima, Attività e Custodia vivono tutte dentro
    // `minerva-shell/app.qml`, per non pagare cinque volte il pavimento di Qt
    // (vedi `minerva-app-pronte`): con due di loro aperte insieme, `pid:` non
    // nomina una finestra — ne nomina due, e il compositore prende la prima
    // che trova.
    //
    // Il difetto che ne veniva, misurato il 25 agosto 2026 con la Custodia e
    // la Calcolatrice aperte nello stesso processo: premere «riduci» sulla
    // Calcolatrice non riduceva la Calcolatrice. E non era solo il riduci —
    // `mia` è la finestra da cui si leggono la geometria e lo stato di
    // «ingrandita», quindi ogni pulsante della barra guardava la finestra
    // sbagliata.
    //
    // Il titolo, invece, le distingue: è quello che ogni nostra finestra si dà
    // per essere riconosciuta nella dock e nell'Alt+Tab, ed è unico dentro un
    // processo. Quando siamo l'unica finestra del processo si resta sul PID,
    // che non ha bisogno di nessun elenco e c'è anche prima che l'elenco
    // arrivi.
    readonly property string me: {
        var pid = Quickshell.processId;
        var tutte = Core.Windows.all || [];
        var miei = [];
        for (var i = 0; i < tutte.length; i++)
            if (tutte[i].pid === pid)
                miei.push(tutte[i]);
        if (miei.length <= 1)
            return "pid:" + pid;
        for (var j = 0; j < miei.length; j++)
            if (miei[j].title === bar.label)
                return "address:" + miei[j].address;
        // L'elenco può essere di un istante fa, e il titolo può essere appena
        // cambiato: meglio il vecchio ripiego che nessun bersaglio.
        return "pid:" + pid;
    }

    // ── I comandi ────────────────────────────────────────────────────────

    // ── Quando sotto non c'è Minerva ─────────────────────────────────────
    //
    // Su COSMIC, GNOME, KDE o sway non c'è nessuno che ascolti i comandi di
    // Minerva. Lì la finestra comanda **sé stessa**, con le richieste che
    // `xdg_toplevel` dà a ogni finestra Wayland e che tutti i compositori
    // capiscono. È la stessa scelta del trascinamento, che usa
    // `startSystemMove()` e infatti funziona ovunque.
    //
    // `QsWindow.window` si risolve dopo la costruzione della finestra —
    // misurato: dentro `Component.onCompleted` è ancora nullo, un secondo
    // dopo c'è. Non è un problema, perché qui ci si arriva solo con un clic.
    function _daSola(cosa, valore) {
        var w = QsWindow.window;
        if (!w) {
            console.warn("[MINERVA][Barra] non trovo la mia finestra: «" + cosa
                         + "» non può fare niente.");
            return false;
        }
        w[cosa] = valore;
        return true;
    }

    function minimizza() {
        // In Minerva la ripesca il pannello «Finestre ridotte» (Super+W).
        // Fuori da Minerva si chiede al compositore ospite di ridurla, che è
        // quello che il suo pannello sa ripescare.
        if (!Core.Compositore.comandabile) {
            bar._daSola("minimized", true);
            return;
        }
        Core.Windows.minimize(bar.me);
    }

    function ingrandisci() {
        // «Ingrandisci» in Minerva vuol dire arrivare ai bordi dello spazio
        // UTILE e fermarsi lì. Lo fa il compositore (`ingrandisci`), che le
        // zone riservate le conosce.
        //
        // Fuori da Minerva lo spazio utile lo conosce il compositore ospite,
        // ed è lui a fermarsi al bordo giusto: `set_maximized` è precisamente
        // la domanda «ingrandiscimi come fai con le altre».
        if (!Core.Compositore.comandabile) {
            var w = QsWindow.window;
            if (w)
                bar._daSola("maximized", !w.maximized);
            return;
        }
        Core.Windows.maximize(bar.me);
    }

    function schermoIntero() {
        if (!Core.Compositore.comandabile) {
            var w = QsWindow.window;
            if (w)
                bar._daSola("fullscreen", !w.fullscreen);
            return;
        }
        Core.Compositore.commutaSchermoIntero(bar.me);
    }

    // ── Trascinamento: lo fa il COMPOSITORE ──────────────────────────────
    //
    // `startSystemMove()` è la richiesta prevista dal protocollo Wayland:
    // «prendi tu questa finestra e portala dove va il puntatore». Da quel
    // momento non passa più niente da qui — nessun comando, nessun calcolo,
    // nessun fotogramma perso — e la finestra si muove con la fluidità con cui
    // il compositore muove le proprie cose, perché è lui a muoverla.
    //
    // ── I due tentativi precedenti, e perché erano sbagliati ─────────────
    //
    // Su Wayland una finestra NON SA DOVE SI TROVA: la posizione la decide il
    // compositore e ai programmi non la dice. È una scelta del protocollo, non
    // una mancanza di Qt.
    //
    //  1. Il primo tentativo calcolava la posizione di arrivo con
    //     `mapToGlobal`, che su Wayland conta a partire dall'angolo della
    //     finestra come se fosse l'angolo dello schermo. Risultato: al primo
    //     movimento la finestra saltava vicino all'angolo in alto a sinistra.
    //     Trascinandola di cento pixel in giù finiva duecento a sinistra e
    //     centodieci in su.
    //
    //  2. Il secondo chiedeva spostamenti RELATIVI, calcolati sulla distanza
    //     dentro la barra. Sembra a prova di tutto, e non lo è: quando il
    //     compositore sposta la finestra sotto un puntatore fermo, Wayland non
    //     manda nessun evento di movimento — non si è mosso il puntatore. La
    //     coordinata dentro la finestra resta quella di prima, la differenza
    //     viene calcolata di nuovo sulla stessa distanza, e la finestra scappa
    //     o rimbalza a seconda di quale evento arriva per primo.
    //
    // Il terzo tentativo è non calcolare niente.

    QtObject {
        id: presa
        property bool armata: false     // premuto, ma non ancora trascinato
        property real partenzaX: 0
        property real partenzaY: 0
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeAllCursor

        onPressed: function(m) {
            presa.partenzaX = m.x;
            presa.partenzaY = m.y;
            presa.armata = true;
        }

        onPositionChanged: function(m) {
            if (!presa.armata)
                return;

            // Sotto i tre pixel non è un trascinamento: è una mano ferma che
            // trema, o un clic. Senza questa soglia, premere sulla barra per
            // portare avanti la finestra la faceva partire di lato — è il
            // difetto che Giacomo ha descritto come «se tengo premuto sulla
            // barra del titolo senza spostare il mouse la barra si sposta e si
            // stacca dalla finestra».
            //
            // La soglia serve anche a lasciar vivere il doppio clic: passando
            // il trascinamento al compositore alla pressione, il secondo clic
            // non arriverebbe mai qui.
            if (Math.abs(m.x - presa.partenzaX) < 3
                && Math.abs(m.y - presa.partenzaY) < 3)
                return;

            presa.armata = false;
            // Una finestra ingrandita trascinata torna alla sua misura: lo
            // fa il compositore (`presa_avanti`), che tiene la misura di prima.
            if (Window.window && Window.window.startSystemMove)
                Window.window.startSystemMove();
        }

        onReleased: presa.armata = false
        onCanceled: presa.armata = false

        // Doppio clic: ingrandisce e ripristina, come su qualunque barra del
        // titolo mai disegnata.
        onDoubleClicked: bar.ingrandisci()
    }

    // Dichiarato DOPO l'area del mouse, così i pulsanti stanno sopra di essa
    // e si prendono i propri clic invece di far partire un trascinamento.
    TitleBarContent {
        anchors.fill: parent
        label: bar.label
        iconPath: bar.iconPath
        active: bar.active
        side: bar.side
        maximized: bar.maximized
        fullscreen: bar.aTuttoSchermo

        onMinimizeRequested: bar.minimizza()
        onMaximizeRequested: bar.ingrandisci()
        onFullscreenRequested: bar.schermoIntero()
        onCloseRequested: bar.closeRequested()
    }
}
