import QtQuick
import Quickshell
import "." as Core

// TenutaPronta — Un'app che, chiusa, non se ne va: si toglie di mezzo.
//
// ── Il problema, in millisecondi ────────────────────────────────────────────
//
// Misurato il 18 agosto 2026 sulla macchina vera, dal lancio del processo alla
// finestra mappata dal compositore:
//
//     finestra `qs` VUOTA (il pavimento)   70 ms
//     Calcolatrice                        317 ms
//     Attività                            353 ms
//     Anteprima                           359 ms
//     Editor                              385 ms
//     Impostazioni                        480 ms
//     Gestore file                        645 ms
//
// (Rimisurati il 18 agosto dopo il passaggio al disegno col processore — vedi
// `scripts/minerva-ambiente-app`. Con la scheda video erano fra 373 e 717 ms.)
//
// Il pavimento è un quinto del totale: quasi tutto il tempo è la COSTRUZIONE
// dell'albero degli oggetti QML. Due strade per accorciarlo sono già state
// percorse e sono chiuse — la cache di compilazione di Qt non si può accendere
// (Quickshell carica da una radice virtuale `qs:@/qs/…` e Qt non mette in
// cache ciò che non è `file:`), e ridurre il sorgente non sposta niente
// (776 righe tolte: 18 ms, dentro il rumore).
//
// Resta una strada sola: **non ricostruire**. Un'app già costruita si rimostra
// in 17–50 ms invece che in 317–645. Anche questo è misurato, sugli stessi
// processi e nella stessa sessione: da dieci a venti volte più veloce.
//
// ── E il prezzo, in megabyte ────────────────────────────────────────────────
//
// Non c'è nessun preload gratis, e conviene dirlo prima di offrirlo.
//
//     Calcolatrice   49 MB      Attività       74 MB
//     Anteprima      52 MB      Gestore file   84 MB
//     Editor         61 MB      Impostazioni   98 MB
//
// Sono i megabyte privati di un'app accesa e senza finestra. Dormire risparmia
// poco rispetto all'essere aperta — il gestore file passa da 87 a 84 — e il
// motivo è noto: `visible: false` NASCONDE, non sospende, quindi da dormiente
// l'albero resta costruito. Che è esattamente il motivo per cui il risveglio
// costa 34 ms e non 645: la memoria che si paga È la velocità che si compra.
// Sono la stessa cosa.
//
// E anche da ferma consuma: 0,20% di CPU costante. Su cinque app tenute
// pronte è un punto percentuale sempre acceso, su un portatile.
//
// Tenerle pronte tutte e sei costa 418 MB. È una cifra che si guarda tutta
// insieme, ed è per questo che le levette stanno in una scheda sola nelle
// Impostazioni, con il totale scritto sotto.
//
// Per questo qui dentro ci sono tre freni, e non uno:
//
//  1. **L'utente deve averlo chiesto** (`preload.<nome>`), app per app.
//  2. **Se cambia idea, si spegne subito** — anche a finestra già chiusa: una
//     casella tolta che libera la memoria «al prossimo accesso» non è una
//     casella, è una promessa.
//  3. **Se non la si usa, esce da sola.** Un'app tenuta calda per tre giorni
//     non è una cache: è una perdita con un'altra faccia.
//
// ── Come si usa ─────────────────────────────────────────────────────────────
//
// Nel punto d'ingresso dell'app, accanto alla finestra:
//
//     Core.TenutaPronta {
//         id: pronta
//         nome: "calcolatrice"
//     }
//
//     Calcolatrice {
//         visible: Core.Ipc.prontoADipingere && !pronta.dormiente
//         onRequestClose: pronta.chiudi()
//     }
//
// e chi la lancia da fuori chiama `pronta.risveglia()` dal suo `IpcHandler`.
Item {
    id: pronta

    /// Il nome dell'app. Da qui escono la chiave delle impostazioni e il nome
    /// della variabile d'ambiente: non si scrivono a mano due volte, o prima o
    /// poi divergono e il difetto è un'app che non si spegne mai.
    property string nome: ""

    /// Si possono scavalcare tutte e due, e il gestore file lo fa: è arrivato
    /// per primo, il 16 agosto, con `files.tieniAcceso` e
    /// `MINERVA_FILES_DORMIENTE` già scritti nelle Impostazioni e nell'avvio
    /// automatico. Rinominarli per simmetria avrebbe spento in silenzio la
    /// scelta che Giacomo aveva già fatto.
    property string chiave: "preload." + pronta.nome
    property string variabile:
        "MINERVA_" + pronta.nome.toUpperCase() + "_DORMIENTE"

    /// Vera quando l'app c'è ma non si deve vedere.
    ///
    /// Parte già vera se chi ci ha lanciati l'ha chiesto — è così che l'avvio
    /// automatico all'accesso apre i programmi senza mostrarli. Chi lancia
    /// l'app a mano non passa niente, e la finestra compare.
    property bool dormiente: {
        // Se la variabile manca del tutto `Quickshell.env` può non restituire
        // una stringa vuota ma fallire, e un errore dentro un binding è
        // veleno: la finestra resta al primo fotogramma e i dialoghi non
        // compaiono mai. Vale la pena blindarlo.
        try {
            return String(Quickshell.env(pronta.variabile) || "") === "1";
        } catch (e) {
            return false;
        }
    }

    /// Quello che l'utente ha scelto.
    ///
    /// Legato e non letto una volta: spegnendo l'interruttore mentre la
    /// finestra è aperta, alla chiusura il programma deve uscire davvero — e
    /// se è già dormiente deve uscire subito, senza aspettare niente.
    readonly property bool tenerlaPronta: Core.Ipc.get(pronta.chiave, pronta.ripiego)

    /// Che cosa vale se dell'impostazione non si sa ancora niente.
    ///
    /// Falso per tutte tranne il gestore file, che era già acceso per scelta
    /// di Giacomo. Sei app tenute pronte sono circa 700 MB: è una cosa che si
    /// sceglie una alla volta guardando il prezzo, non un valore di fabbrica.
    property bool ripiego: false

    /// Dopo quanti minuti da ferma esce da sola. 0 la lascia lì per sempre.
    readonly property int minutiDiPazienza: Core.Ipc.get("preload.minuti", 30)

    /// Emesso quando torna a farsi vedere, per chi deve ripartire pulito.
    signal risvegliata()

    /// Emesso quando si toglie di mezzo, per chi deve mettere via le sue cose.
    signal addormentata()

    /// Emesso quando l'app va spenta del tutto.
    ///
    /// Chi ha un processo suo non lo ascolta: esce e basta. Chi è ospitato in
    /// `app.qml` insieme ad altri tre programmi lo ascolta eccome — lì uscire
    /// vorrebbe dire chiudere anche le altre tre, e quello che va spento è
    /// solo il proprio `Loader`.
    signal spenta()

    /// Se falsa, invece di uscire dal processo emette `spenta()`.
    ///
    /// Vera per chi ha un processo suo (gestore file, Impostazioni), falsa per
    /// le quattro ospitate in `app.qml`. È l'unica differenza fra i due casi,
    /// e sta in una proprietà sola apposta: due meccanismi separati sarebbero
    /// divergiti al primo cambiamento.
    property bool esceDaSola: true

    // ── Chiudere ────────────────────────────────────────────────────────────

    /// Da chiamare al posto di `Qt.quit()` quando l'utente chiude la finestra.
    ///
    /// Qui c'era `Qt.quit()` in tutte e sei le app, con accanto una ragione
    /// giusta: «un processo senza finestre che resta in memoria è un programma
    /// che l'utente crede di aver chiuso e invece no». Resta giusta, ed è il
    /// motivo per cui questo non si fa di nascosto: si spegne davvero, a meno
    /// che l'utente abbia chiesto di tenerlo pronto. In quel caso resta — e si
    /// vede in `Minerva Attività`, che è il posto dove si va a cercare chi
    /// occupa la memoria. Un programma acceso che non si vede da nessuna parte
    /// è il difetto, non la soluzione.
    function chiudi() {
        if (pronta.tenerlaPronta)
            pronta.addormenta();
        else
            pronta.smetti();
    }

    /// Sparire per davvero: uscire dal processo, o farsi smontare da chi
    /// ospita.
    ///
    /// Tutti i punti che prima uscivano passano di qui, e sono tre: la
    /// finestra chiusa, l'interruttore spento, il tempo scaduto. Sparsi in tre
    /// punti, ospitare un'app avrebbe voluto dire ricordarsi di cambiarli
    /// tutti e tre — e quello dimenticato avrebbe chiuso le altre tre app
    /// senza che nessuno capisse perché.
    function smetti() {
        if (pronta.esceDaSola)
            Qt.quit();
        else
            pronta.spenta();
    }

    /// Si toglie di mezzo restando viva.
    function addormenta() {
        if (pronta.dormiente)
            return;
        pronta.dormiente = true;
        pronta.addormentata();
    }

    /// Torna a farsi vedere, e davanti a tutto.
    function risveglia() {
        var dormiva = pronta.dormiente;
        pronta.dormiente = false;
        if (dormiva)
            pronta.risvegliata();
        pronta.portaDavanti();
    }

    /// Porta la finestra davanti e sulla scrivania di chi guarda.
    ///
    /// Serve anche quando l'app era già sveglia: senza, chiedere di aprire una
    /// cosa a un programma già aperto sembra non fare niente — la finestra c'è
    /// davvero, ma dietro a tutto il resto, magari su un'altra scrivania.
    ///
    /// Si chiede al compositore per numero di processo, che è l'unica cosa che
    /// distingue con certezza questa finestra: la classe (`org.quickshell`) e
    /// il titolo li ha uguali anche il resto di Minerva.
    ///
    /// ── E si insiste, perché una volta sola non basta ────────────────────
    ///
    /// Qui c'era un `Qt.callLater` solo, con scritto accanto che «un giro
    /// dopo» bastava. Non basta: misurato il 18 agosto 2026 svegliando una
    /// calcolatrice tenuta pronta, il compositore risponde
    ///
    ///     Dispatch request "focuswindow pid:9959" failed with error
    ///     "No such window found"
    ///
    /// perché fra il momento in cui QML dice `visible = true` e il momento in
    /// cui Wayland ha mappato la finestra passa un giro di compositore, non un
    /// giro di ciclo degli eventi. Il risultato era un'app che ricompariva
    /// dietro a quella su cui si stava lavorando — cioè il difetto che questa
    /// funzione esiste per evitare, e per di più senza un errore in faccia a
    /// nessuno.
    ///
    /// Quindi si riprova finché non ha davvero il fuoco. La condizione di
    /// arresto è la finestra stessa (`active`), non un numero di tentativi:
    /// contare i tentativi vuol dire indovinare quanto è lenta la macchina.
    function portaDavanti() {
        insistenza.rimasti = 12;
        insistenza.restart();
    }

    /// La finestra dell'app, per sapere quando ha davvero preso il fuoco.
    ///
    /// Senza, `portaDavanti()` non ha nessun modo di sapere se ha funzionato e
    /// deve tirare a indovinare. Chi non la lega ottiene comunque un tentativo
    /// per ogni scatto: funziona quasi sempre, e «quasi sempre» è esattamente
    /// il tipo di difetto che non si trova.
    ///
    /// Si chiama `laFinestra` e non `finestra` per una ragione noiosa e reale:
    /// in Attività e in Anteprima la finestra ha `id: finestra`, e in QML la
    /// proprietà dell'oggetto che si sta costruendo copre l'id dichiarato
    /// fuori — `finestra: finestra` si legherebbe a sé stessa.
    property var laFinestra: null

    /// Il fuoco alla NOSTRA finestra, non a una qualsiasi del processo.
    ///
    /// Qui c'era `Compositore.fuocoAlNostroProcesso()`, cioè `focuswindow
    /// pid:…`. Era giusto finché ogni applicazione era un processo suo; da
    /// quando Calcolatrice, Editor, Anteprima, Attività e Custodia vivono
    /// tutte dentro `app.qml`, quel `pid:` nomina fino a cinque finestre e il
    /// compositore prende la prima che trova.
    ///
    /// Il risultato: rilanciare la Calcolatrice mentre la Custodia è aperta
    /// portava avanti la Custodia. È lo stesso difetto di
    /// `ui/WindowTitleBar.qml::me`, e si chiude allo stesso modo — il titolo
    /// distingue le nostre finestre, il numero di processo no.
    function _fuocoAllaMia() {
        var f = pronta.laFinestra;
        var titolo = f ? String(f.title || "") : "";
        var tutte = Core.Windows.all || [];
        for (var i = 0; i < tutte.length; i++) {
            if (tutte[i].pid === Quickshell.processId
                    && tutte[i].title === titolo && titolo !== "") {
                Core.Windows.focus(tutte[i].address);
                return;
            }
        }
        // Prima che l'elenco arrivi, o se il titolo è appena cambiato: meglio
        // il vecchio ripiego che nessun fuoco.
        Core.Compositore.fuocoAlNostroProcesso();
    }

    Timer {
        id: insistenza
        // Cento millisecondi e non venti: il primo tentativo deve cadere DOPO
        // che il compositore ha mappato la finestra, o si spende un avviso in
        // giornale per niente. Misurato, il ritardo fra `visible = true` e la
        // finestra mappata va dai 36 ms della calcolatrice ai 106 dell'editor.
        interval: 100
        repeat: true
        property int rimasti: 0
        onTriggered: {
            if (insistenza.rimasti <= 0
                    || (pronta.laFinestra && pronta.laFinestra.active)) {
                insistenza.stop();
                return;
            }
            insistenza.rimasti -= 1;
            pronta._fuocoAllaMia();
        }
    }

    // ── Se non la si vuole pronta, non resta ────────────────────────────────
    //
    // L'app dormiente la avvia l'accesso, che non può sapere cosa ha scelto
    // l'utente: quando l'accesso parte, il demone sta ancora nascendo. Quindi
    // si avvia sempre e si decide qui, appena le impostazioni vere arrivano.
    //
    // `impostazioniArrivate` e non `prontoADipingere`: il secondo è vero anche
    // per scadenza, e con i valori di ripiego si deciderebbe sul falso. È la
    // regola scritta in `core/Ipc.qml`, e vale qui più che altrove, perché la
    // decisione è «resto o me ne vado».

    function _valutaSeRestare() {
        if (Core.Ipc.impostazioniArrivate && pronta.dormiente
                && !pronta.tenerlaPronta)
            pronta.smetti();
    }

    onTenerlaProntaChanged: pronta._valutaSeRestare()
    onDormienteChanged: pronta._valutaSeRestare()

    Connections {
        target: Core.Ipc
        function onImpostazioniArrivateChanged() { pronta._valutaSeRestare(); }
    }

    // ── E se non la si usa, se ne va ────────────────────────────────────────
    //
    // Il tetto vero — «oltre tanti megabyte di app calde, la più vecchia esce»
    // — vuole qualcuno che veda tutti i processi insieme, e quel qualcuno è il
    // demone. Questa è la metà che ogni app può fare da sola, e che da sola
    // già limita il danno: chi ha aperto la calcolatrice una volta stamattina
    // non se la ritrova in memoria stasera.
    Timer {
        // In minuti, ma non si aspetta mezz'ora per accorgersi di un cambio di
        // impostazione: si controlla spesso e si conta.
        interval: 60000
        running: pronta.dormiente && pronta.minutiDiPazienza > 0
        repeat: true
        property int fermaDa: 0
        onRunningChanged: fermaDa = 0
        onTriggered: {
            fermaDa += 1;
            if (fermaDa >= pronta.minutiDiPazienza)
                pronta.smetti();
        }
    }
}
