import QtQuick
import QtQuick.Effects
import Quickshell

import "../theme" as Theme
import "../core/sessioni.js" as Sessioni
import "../core" as Core
import "../ui" as Ui
import "aurora"

// Greeter — La schermata di accesso di Minerva.
//
// ── Cosa succede davvero quando si scrive una password ─────────────────────
//
// Questa schermata NON verifica niente. Parla con `greetd`, che parla con PAM.
// Il giro è:
//
//     create_session(utente)  →  greetd chiede qualcosa  →  si risponde
//                             →  chiede ancora, forse    →  si risponde ancora
//                             →  success                 →  start_session
//
// E qui la cosa meno ovvia di tutto il protocollo: **la sessione parte quando
// il greeter finisce**. Dopo il «sì» a `start_session` questo processo deve
// chiudersi. Se resta aperto, si guarda una schermata di accesso che ha già
// accettato la password e non succede più niente.
//
// ── Perché non si conta quante domande arriveranno ─────────────────────────
//
// La pagina di manuale di greetd è esplicita: «there are no limits on the
// number and type of messages that may be required for authentication to
// succeed, and a greeter should not make any assumptions about the messages».
// Con un lettore di impronte, o con l'autenticazione a due fattori, i giri
// sono più d'uno. Quindi non c'è nessuno stato «adesso tocca alla password»:
// c'è UNA domanda in corso, che è quella che PAM ha appena fatto, e la sua
// etichetta è quella che PAM ha mandato.
//
// ── La forma ───────────────────────────────────────────────────────────────
//
// Niente riquadro. Il contenuto galleggia sullo sfondo sfocato: ritratto,
// nome, una pillola per la risposta. Un pannello squadrato attorno al campo è
// il modo in cui si disegnavano queste schermate quindici anni fa, e la prima
// cosa che si vede di un sistema operativo non può somigliare a un modulo da
// compilare.
//
// La sfocatura non è decorazione: è ciò che rende leggibile un testo chiaro
// sopra una fotografia qualunque. Vedi [[minerva-vetro-leggibile]] — la
// leggibilità sul vetro si calcola, non si azzecca a occhio.
//
// ── Perché si può guardare senza greetd ────────────────────────────────────
//
// `finto` è vero quando `GREETD_SOCK` non c'è. Serve a poterla disegnare,
// guardare e correggere dentro una sessione normale, senza toccare il modo in
// cui si entra in questo computer. Una schermata di accesso è l'unica finestra
// che, sbagliata, chiude fuori dal proprio computer: va provata da spenta
// prima che da accesa.
Item {
    id: greeter

    /// Vero quando non c'è nessun greetd con cui parlare: si disegna tutto,
    /// ma «Entra» non entra da nessuna parte.
    property bool finto: true

    readonly property bool it: Core.Strings.lang === "it"

    // ── Quello che sappiamo ──────────────────────────────────────────────

    property var utenti: []
    property var sessioni: []

    /// Vero da quando il demone ha risposto chi c'è.
    ///
    /// Serve a non dire una bugia nei primi secondi. Il nome sotto il ritratto
    /// mostrava «Nessun utente» finché la risposta non arrivava — e la
    /// risposta arriva quando il demone ha finito di partire, cioè dopo
    /// qualche secondo. Chi guarda legge «Nessun utente» su una schermata di
    /// accesso e pensa che il computer non lo conosca più: è il momento
    /// peggiore in cui dare quella notizia, ed era anche falsa.
    property bool informato: false
    property int utenteScelto: 0
    property int sessioneScelta: 0

    readonly property var utente: greeter.utenti[greeter.utenteScelto] || null
    readonly property var sessione: greeter.sessioni[greeter.sessioneScelta] || null

    // ── Quello che si può personalizzare ─────────────────────────────────
    //
    // Tutto passa dal demone, come ogni altra preferenza di Minerva. Il
    // greeter gira come utente `greeter` e legge le SUE impostazioni: è il
    // motivo per cui il pannello scrive in un file di sistema e non in casa
    // di qualcuno. Vedi `settings/sections/Accesso.qml`.

    readonly property real sfocatura: Core.Ipc.get("greeter.blur", 48)
    readonly property real velo:      Core.Ipc.get("greeter.scrim", 0.42)
    readonly property bool conOra:    Core.Ipc.get("greeter.showClock", true)
    readonly property bool ore24:     Core.Ipc.get("greeter.clock24", true)

    // ── Le cose in più, dal 23 settembre 2026 ────────────────────────────
    //
    // Giacomo: «predisponiamolo anche per meteo e altre cose interessanti e
    // attraenti». La regola che le tiene insieme: ognuna risponde a una
    // domanda che si fa DAVANTI a questo schermo, prima di entrare — che
    // tempo fa, quanto resta di batteria, perché la password non va — e
    // nessuna dice niente di chi usa il computer che non si veda già
    // guardandolo. Il meteo mostra la città scelta: si spegne da qui.

    /// Il meteo sotto la data. Solo se la sessione l'ha acceso e ha scelto
    /// un posto: le impostazioni del meteo le porta qui `minerva-greetd`.
    readonly property bool conMeteo: Core.Ipc.get("greeter.meteo", true)
                                     && Core.Meteo.attivo
    /// «Buonasera, Giacomo» al posto del nome secco.
    readonly property bool conSaluto: Core.Ipc.get("greeter.saluto", true)
    /// Batteria e tastiera nell'angolo in alto.
    readonly property bool conStato: Core.Ipc.get("greeter.stato", true)
    /// ── Da che parte ─────────────────────────────────────────────────────
    ///
    /// Giacomo, 23 settembre 2026: «la riorganizzerei spostando dall'ora
    /// fino all'inserimento della password sulla sinistra o destra, e sulla
    /// parte libera metterei tutte le notifiche». L'ora e l'accesso stanno
    /// in una colonna sola, su un asse a un quarto dello schermo; l'altra
    /// metà resta libera — nella schermata di BLOCCO lì vanno le notifiche
    /// (qui, prima dell'accesso, non ne arriva nessuna: di chi entra non
    /// gira ancora niente). «centro» è la disposizione di prima.
    readonly property string lato: Core.Ipc.get("greeter.lato", "sinistra")
    readonly property real asse: greeter.lato === "destra" ? greeter.width * 0.72
                               : greeter.lato === "centro" ? greeter.width / 2
                               : greeter.width * 0.28

    /// La disposizione dei tasti, come la scrive la sessione: «IT», «US».
    readonly property string disposizione:
        String(Core.Ipc.get("input.layout", "")).toUpperCase()

    /// Le maiuscole bloccate, INDOVINATE dai tasti: Qt non dice lo stato del
    /// Bloc Maiusc. Una lettera maiuscola senza Shift, o minuscola con
    /// Shift, vuol dire che è acceso; e da lì in poi il tasto stesso lo
    /// inverte. Finché non si è vista una lettera non si sa, e non si dice
    /// niente: un avviso sbagliato su una password è peggio di nessuno.
    property bool maiuscole: false
    property bool maiuscoleNote: false

    function saluto(ora) {
        var h = ora.getHours();
        if (h >= 5 && h < 12)  return greeter.it ? "Buongiorno" : "Good morning";
        if (h >= 12 && h < 18) return greeter.it ? "Buon pomeriggio" : "Good afternoon";
        if (h >= 18 && h < 23) return greeter.it ? "Buonasera" : "Good evening";
        return greeter.it ? "Buonanotte" : "Good night";
    }

    // ── Lo stato della conversazione ─────────────────────────────────────

    /// La domanda che PAM ha fatto adesso. Vuota = non sta chiedendo niente.
    property string domanda: ""
    /// Se la risposta va nascosta mentre si scrive.
    property bool rispostaSegreta: true
    /// Un messaggio da mostrare: un errore, o un'informazione di PAM.
    property string avviso: ""
    property bool avvisoGrave: false
    /// Vero mentre si aspetta greetd: il pulsante non si può ripremere.
    property bool inCorso: false

    /// Vero fra il «sì» all'autenticazione e il «sì» all'avvio: serve a
    /// distinguere i due `success`, che sul filo sono identici.
    property bool avviato: false

    // ── Quanti «errore» di fila ───────────────────────────────────────────
    //
    // Dopo un errore la sessione va RICOMINCIATA, e la schermata lo faceva da
    // sola dopo 900 ms. Giusto quando l'errore è una password sbagliata: si
    // riscuote, e un istante dopo il campo torna pronto.
    //
    // Sbagliato quando l'errore si ripete. Se ciò che si ricomincia fallisce
    // a sua volta — greetd che ha chiuso il socket, il servizio caduto — si
    // ottiene: errore → scossa → riprova → errore → scossa → riprova, ogni
    // 900 ms, per sempre. È quello che Giacomo ha visto il 10 agosto 2026:
    // «comincia a tremare all'infinito verso destra e sinistra».
    //
    // Il rimedio non è togliere la riprova, che è ciò che rende la schermata
    // usabile: è contarla. Una domanda di PAM azzera il conto, perché vuol
    // dire che si è tornati a parlare. Senza quella, ogni tentativo aspetta
    // più del precedente e la scossa la fa **solo il primo**: dopo, non è più
    // una password sbagliata, è un guasto, e va detto con parole diverse.
    property int erroriDiFila: 0

    /// Il massimo oltre il quale non si riprova più da soli.
    readonly property int erroriMax: 4

    /// Quante volte la colonna si è scossa. Esiste per le prove: la scossa è
    /// un'animazione interna, e senza un numero da guardare l'unico modo di
    /// sapere se si è ripetuta sarebbe fissare lo schermo — che è esattamente
    /// come questo difetto è arrivato fin qui.
    property int scosse: 0

    // ── L'annullamento, e perché è uno STATO e non un dettaglio ───────────
    //
    // Dopo una password sbagliata greetd **tiene** la sessione in
    // configurazione: ricominciarne una senza chiudere la prima riceve «a
    // session is already being configured», e da lì non si entra più.
    //
    // Serve quindi un `cancel_session` prima di ogni nuovo tentativo. Il
    // problema è la sua risposta: greetd risponde `success`, che è la STESSA
    // parola con cui dice «password accettata». Letta nel posto sbagliato,
    // quella parola fa chiedere alla schermata di aprire la sessione — greetd
    // risponde «session is not ready» — e la schermata si chiude portandosi
    // dietro il compositore. Il 10 agosto 2026 è finita così: Giacomo, dopo
    // una password sbagliata, si è ritrovato su un terminale nero.
    //
    // Il rimedio è la stessa cosa che questo file già fa per i due `success`
    // dell'accesso, che pure sono identici sul filo: TENERE LO STATO. Mentre
    // `annullando` è vero, la prossima risposta È quella dell'annullamento,
    // qualunque parola porti, e non vuol dire niente altro.
    property bool annullando: false
    property bool canalePerso: false

    function perdiCanale() {
        riprova.stop();
        campo.text = "";
        greeter.domanda = "";
        greeter.inCorso = false;
        greeter.avviato = false;
        greeter.annullando = false;
        greeter.canalePerso = true;
        greeter.erroriDiFila = greeter.erroriMax + 1;
        greeter.avvisoGrave = true;
        greeter.avviso = greeter.it
            ? "Collegamento alla login interrotto. Premi Invio per riprovare."
            : "Login connection interrupted. Press Enter to try again.";
    }

    /// Vero quando la schermata ha smesso di ritentare per conto suo.
    readonly property bool arreso: greeter.erroriDiFila > greeter.erroriMax

    /// Ricominciare per scelta di chi guarda, non per conto di un timer.
    function riparti() {
        greeter.erroriDiFila = 0;
        greeter.avviso = "";
        greeter.avvisoGrave = false;
        // Dalla stessa porta della riprova automatica: anche qui la sessione
        // di prima può essere rimasta aperta.
        greeter.annullaERicomincia();
    }

    signal finito()

    // ── Il giro ──────────────────────────────────────────────────────────

    function comincia() {
        if (greeter.canalePerso) {
            greeter.perdiCanale();
            return;
        }
        if (!greeter.utente)
            return;
        greeter.domanda = "";
        greeter.avviso = "";
        greeter.avvisoGrave = false;
        greeter.avviato = false;
        greeter.inCorso = true;
        if (greeter.finto) {
            // Senza greetd si finge la domanda, così la schermata si vede
            // esattamente com'è: è l'unico pezzo di finzione di tutto il file.
            greeter.inCorso = false;
            greeter.domanda = "Password:";
            greeter.rispostaSegreta = true;
            campo.forceActiveFocus();
            return;
        }
        if (!Core.Ipc.greeterCreateSession(greeter.utente.nome))
            greeter.perdiCanale();
    }

    function rispondi(testo) {
        if (greeter.inCorso || greeter.domanda === "")
            return;
        campo.text = "";
        greeter.inCorso = true;
        greeter.avviso = "";
        if (greeter.finto) {
            greeter.inCorso = false;
            greeter.avviso = greeter.it
                ? "Anteprima: da qui non si entra."
                : "Preview: this cannot log you in.";
            greeter.avvisoGrave = false;
            return;
        }
        if (!Core.Ipc.greeterRespond(testo))
            greeter.perdiCanale();
    }

    /// Torna indietro pulito. Va fatto anche solo cambiando utente: greetd
    /// tiene UNA sessione in configurazione, e cominciarne un'altra senza
    /// chiudere la prima è un errore.
    function annulla() {
        campo.text = "";
        greeter.domanda = "";
        greeter.inCorso = false;
        greeter.avviato = false;
        if (!greeter.finto)
            Core.Ipc.greeterCancel();
    }

    // ── L'ambiente con cui parte la sessione ─────────────────────────────
    //
    // Qui c'era UNA riga, `XDG_SESSION_DESKTOP`, e le altre scrivanie
    // partivano senza sapere di esserlo. Il 17 agosto 2026 Giacomo l'ha
    // descritto così: «mi fa entrare solo con cosmic e minerva, hyprland e kde
    // mi portano sempre su minerva».
    //
    // Le quattro variabili non sono cerimoniale: le passa ogni gestore di
    // accessi, e ognuna serve a qualcuno di preciso.
    //
    //  · XDG_CURRENT_DESKTOP — la più importante. È con questa che Plasma e
    //    Hyprland riconoscono sé stessi, e con cui i portali xdg scelgono il
    //    backend: senza, `xdg-desktop-portal` non sa a chi chiedere per lo
    //    schermo condiviso, i file e le password. Viene da `DesktopNames` del
    //    `.desktop` — che fino a quel giorno non leggeva nessuno.
    //  · XDG_SESSION_TYPE — `wayland` o `x11`. Molti programmi Qt e GTK
    //    scelgono da qui quale backend grafico usare.
    //  · XDG_SESSION_CLASS — `user`, e serve a systemd/logind per distinguere
    //    una sessione di persona da una di servizio.
    //  · XDG_SESSION_DESKTOP — il nome del file, che c'era già.
    function ambienteSessione(s) {
        var env = ["XDG_SESSION_DESKTOP=" + s.id,
                   "XDG_SESSION_CLASS=user"];
        if (s.tipo)
            env.push("XDG_SESSION_TYPE=" + s.tipo);
        // Il demone ripiega già sul nome quando il file non dichiara
        // `DesktopNames`; questo controllo è per le versioni vecchie del
        // demone, che il campo non lo mandano affatto.
        //
        // Tranne la riga di comando: non È una scrivania, e scriverle
        // `XDG_CURRENT_DESKTOP=Riga di comando` vorrebbe dire annunciare al
        // sistema una scrivania che non esiste. I portali xdg la cercherebbero.
        var nomi = s.tipo === "tty" ? "" : (s.nomiScrivania || s.nome || s.id);
        if (nomi)
            env.push("XDG_CURRENT_DESKTOP=" + greeter.aDueSepararatori(nomi));
        return env;
    }

    /// Da `DesktopNames` a `XDG_CURRENT_DESKTOP`: due punti, non punto e
    /// virgola.
    ///
    /// Sembra un dettaglio da pignoli e non lo è. Le due specifiche usano
    /// separatori DIVERSI per la stessa lista di nomi:
    ///
    ///   · nel file `.desktop`, `DesktopNames=KDE;Plasma;` — punto e
    ///     virgola, con quello finale, perché lì è il tipo «lista di stringhe»
    ///     e la specifica vuole il separatore anche in fondo;
    ///   · nella variabile, `XDG_CURRENT_DESKTOP=KDE:Plasma` — due
    ///     punti, come `PATH`.
    ///
    /// Chi legge la variabile la spezza sui due punti. Passandogliela com'è
    /// scritta nel file, `KDE;Plasma;` è UN nome solo — un nome che non
    /// esiste — e il confronto con «KDE» fallisce
    /// silenziosamente. È il modo in cui si era rotto il portachiavi di
    /// Chrome: nessun errore, solo una funzione che smette di esserci.
    ///
    /// La sessione di Minerva se la riscrive comunque da capo dopo l'accesso
    /// (`scripts/minerva-greeter-sessione`); le altre scrivanie no.
    function aDueSepararatori(nomi) {
        return String(nomi).split(";")
                           .filter(function (n) { return n !== ""; })
                           .join(":");
    }

    /// Chi avvia davvero la sessione, quando c'è.
    ///
    /// `scripts/minerva-avvia-sessione`, installato qui dall'installatore del
    /// greeter. Fa due cose che `sh -lc` da solo non fa: scrive nel registro
    /// dell'utente **che cosa** sta avviando e con quale ambiente, e alla fine
    /// scrive quanto è durata.
    ///
    /// Serve perché una sessione che muore in un secondo oggi non lascia
    /// niente: si torna alla schermata di accesso e da fuori sembra che la
    /// password fosse sbagliata. Nel journal del 20 agosto 2026 si vede il
    /// contrario — «session opened», e un secondo dopo «session closed» —
    /// cioè PAM aveva detto di sì. Vedi il file, che racconta tutto.
    readonly property string avviatore: "/usr/local/lib/minerva/minerva-avvia-sessione"

    /// Vero quando l'avviatore c'è. Lo dice il demone dentro `greeter_info`,
    /// che il file lo può guardare in una riga.
    ///
    /// Falso in anteprima, o su un'installazione vecchia — e allora si avvia
    /// come prima, invece di non entrare affatto.
    property bool avviatoreCE: false

    function avvia() {
        if (!greeter.sessione)
            return;
        // ── Perché non c'è nessun `sh -lc` qui dentro ───────────────────
        //
        // Perché greetd ce ne mette già uno, e ce ne vuole uno solo.
        //
        // La sua pagina di manuale dice che `cmd` è una «command line», un
        // array di stringhe, e verrebbe da leggerlo come un `argv`. Non lo è:
        // greetd unisce l'array con degli spazi e appiccica il risultato in
        // fondo a una riga che poi esegue con `/bin/sh -c`. Nel binario si
        // legge per esteso, e finisce con «exec » e uno spazio.
        //
        // Quindi il vecchio `["sh", "-lc", comando]` diventava, per Plasma:
        //
        //     exec sh -lc /usr/lib/plasma-dbus-run-session-if-needed \
        //                 /usr/bin/startplasma-wayland
        //
        // cioè `sh` eseguiva come script il PRIMO pezzo e passava il secondo
        // come `$0`. Partiva `plasma-dbus-run-session-if-needed` senza il
        // programma da avviare: fa `exec dbus-run-session` a mani vuote, che
        // senza terminale esce subito. Uscita 0, zero secondi, nessun
        // messaggio — e da fuori sembra una password sbagliata. Giacomo, 23
        // agosto 2026: «niente kde non entra e torna alla login».
        //
        // Un elemento solo, invece, è la riga com'è scritta nel `.desktop`, e
        // la shell di greetd la esegue come si deve.
        //
        // ── E se l'avviatore non c'è, si entra lo stesso ─────────────────
        //
        // È la regola che conta in una schermata di accesso: **niente di
        // quello che aggiungiamo può diventare un motivo per non entrare.**
        // Un registro in più vale molto meno di un computer che si apre.
        greeter.ricorda(greeter.sessione, greeter.utente);
        if (!Core.Ipc.greeterStart(greeter.comandoDiAvvio(greeter.sessione),
                                  greeter.ambienteSessione(greeter.sessione)))
            greeter.perdiCanale();
    }

    /// Quale voce risulta già scelta quando la schermata si apre.
    ///
    /// Tre gradini, e servono tutti e tre:
    ///
    ///  1. **l'ultima usata**, che la schermata si scrive da sola dopo ogni
    ///     accesso riuscito (`ricorda()`). È quello che Giacomo ha chiesto il
    ///     23 agosto 2026: «ci vorrebbe che il login ricordi l'ultimo desktop
    ///     environment usato e sia già posizionato su di essi».
    ///  2. **Minerva**, se quella di prima non c'è più. Succede davvero:
    ///     disinstalli una scrivania e la voce ricordata sparisce dall'elenco.
    ///     Senza questo gradino si ricadrebbe sulla prima in ordine
    ///     alfabetico, che qui sarebbe Cosmic.
    ///
    ///     ⚠ E il 2 settembre 2026 è successo a NOI. Il gradino diceva
    ///     «minerva», che era la sessione su Hyprland; togliendola — la Tappa
    ///     4 del distacco — il ripiego puntava a una voce che non esiste più,
    ///     e si finiva sulla prima non-tty: Cosmic, o peggio il RECUPERO.
    ///     Adesso i nomi sono due, nell'ordine in cui vanno provati:
    ///     `minerva-wayland` (la sessione di oggi) e poi `minerva` (quella
    ///     vecchia, che su una macchina non ancora aggiornata c'è ancora).
    ///  3. **la prima scrivania vera**, se non c'è nemmeno Minerva.
    ///
    /// In nessun caso si finisce sulla riga di comando: è una via di scorta,
    /// e una via di scorta preselezionata è una trappola. L'unica eccezione è
    /// quando è rimasta l'unica voce — cioè esattamente il guaio per cui esiste.
    ///
    /// E per la stessa ragione **non si finisce sul RECUPERO**: è il nostro
    /// compositore con dentro un terminale e nient'altro, cioè una via di
    /// scorta anche lei. Preselezionarla vorrebbe dire entrare in una
    /// scrivania vuota senza averlo chiesto, e credere che Minerva sia rotta.
    ///
    /// `voluta` si passa nelle prove; lasciandola fuori si legge
    /// l'impostazione vera. È l'unico modo di provare questa scelta senza
    /// dipendere da come è configurato IL COMPUTER su cui girano le prove —
    /// che è un modo classico di scrivere una prova che non prova niente.
    function qualeSessione(elenco, voluta) {
        // La regola sta in `core/sessioni.js`: la usa anche la pagina
        // Accesso delle Impostazioni, che deve mostrare accesa la STESSA
        // sessione in cui si entrerà premendo Invio.
        return Sessioni.scegli(elenco, voluta !== undefined
                                       ? voluta : Core.Ipc.get("greeter.session", ""));
    }

    /// Si segna dove si è appena entrati, così la volta dopo è già scelto.
    ///
    /// Non si ricorda la riga di comando: se ci sei finito una volta è perché
    /// qualcosa era rotto, e ritrovarsela preselezionata la volta dopo — magari
    /// dopo aver riparato il guaio — vuol dire entrare in un terminale senza
    /// averlo chiesto.
    function ricorda(s, chi) {
        var id = greeter.idDaRicordare(s);
        if (id !== "")
            Core.Ipc.setSetting("greeter.session", id);
        if (chi && chi.nome)
            Core.Ipc.setSetting("greeter.user", chi.nome);
    }

    /// Che cosa si scrive nelle impostazioni, e vuoto quando non si scrive
    /// niente. A parte da `ricorda()` perché così si può provare la DECISIONE
    /// senza scrivere per davvero nelle impostazioni di chi lancia le prove.
    function idDaRicordare(s) {
        if (!s || !s.id || s.tipo === "tty")
            return "";
        return String(s.id);
    }

    /// L'array `cmd` da mandare a greetd per una sessione. Sta a parte da
    /// `avvia()` per una ragione sola: così si può provare senza far entrare
    /// nessuno. Vedi `prove-greeter.qml`.
    function comandoDiAvvio(s) {
        if (!s)
            return [];
        return greeter.avviatoreCE ? [greeter.avviatore, s.comando]
                                   : [s.comando];
    }


    Connections {
        target: Core.Ipc

        function onConnectedChanged() {
            if (!Core.Ipc.connected && greeter.informato && !greeter.finto)
                greeter.perdiCanale();
        }

        function onGreeterInfoReceived(info) {
            greeter.informato = true;
            greeter.utenti = info.utenti || [];
            greeter.sessioni = info.sessioni || [];
            greeter.finto = info.greetd !== true;
            greeter.avviatoreCE = info.avviatore === true;

            greeter.sessioneScelta = greeter.qualeSessione(greeter.sessioni);

            var chi = Core.Ipc.get("greeter.user", "");
            if (chi !== "") {
                for (var j = 0; j < greeter.utenti.length; j++) {
                    if (greeter.utenti[j].nome === chi) {
                        greeter.utenteScelto = j;
                        break;
                    }
                }
            }

            if (!greeter.canalePerso) greeter.comincia();
        }

        function onGreeterMessage(m) {
            if (greeter.canalePerso) return;
            if (m.transport_error === true || m.request_rejected === true) {
                greeter.perdiCanale();
                return;
            }
            // Prima di tutto il resto: se stavamo annullando, questa è la
            // risposta all'annullamento. Non è un accesso riuscito, non è un
            // errore da mostrare, non è niente — è solo il permesso di
            // ricominciare.
            if (greeter.annullando) {
                if (m.request_action !== "greeter_cancel") return;
                greeter.annullando = false;
                greeter.comincia();
                return;
            }

            greeter.inCorso = false;

            switch (m.type) {
            case "auth_message":
                var tipo = m.auth_message_type;
                if (tipo === "secret" || tipo === "visible") {
                    // Si è tornati a parlare: il conto degli errori riparte.
                    greeter.erroriDiFila = 0;
                    greeter.domanda = (m.auth_message || "").trim();
                    greeter.rispostaSegreta = tipo === "secret";
                    campo.text = "";
                    campo.forceActiveFocus();
                } else {
                    // `info` ed `error` non chiedono niente: si mostrano e si
                    // confermano SENZA risposta. Mandare una stringa vuota
                    // sarebbe una risposta, e PAM può prenderla per sbagliata.
                    greeter.avviso = (m.auth_message || "").trim();
                    greeter.avvisoGrave = tipo === "error";
                    greeter.inCorso = true;
                    if (!Core.Ipc.greeterRespond(undefined))
                        greeter.perdiCanale();
                }
                break;

            case "success":
                if (greeter.avviato) {
                    // Il «sì» a start_session. Da qui in poi la sessione parte
                    // quando questo processo finisce: finire è il gesto
                    // finale, non un effetto collaterale.
                    greeter.finito();
                    return;
                }
                // Il «sì» all'autenticazione: adesso si chiede la sessione.
                greeter.domanda = "";
                greeter.avviato = true;
                greeter.avvia();
                break;

            case "error":
                greeter.avviato = false;
                greeter.avvisoGrave = true;
                greeter.erroriDiFila++;

                greeter.avviso = greeter.erroriDiFila > 1
                    // Dal secondo di fila non è più una questione di password:
                    // è il servizio di accesso che non risponde come dovrebbe,
                    // e continuare a dire «password sbagliata» manderebbe la
                    // persona a riprovare la stessa password all'infinito.
                    ? (greeter.it
                       ? "Il servizio di accesso non risponde."
                       : "The login service is not responding.")
                    : m.error_type === "auth_error"
                    ? (greeter.it ? "Password sbagliata." : "Wrong password.")
                    : (m.description || (greeter.it ? "Non è riuscito."
                                                    : "It did not work."));
                campo.text = "";

                // La scossa solo la PRIMA volta. È il messaggio «hai sbagliato
                // a scrivere», e ripetuto a ogni tentativo automatico diventa
                // un tremito che non finisce più.
                if (greeter.erroriDiFila === 1) {
                    greeter.scosse++;
                    scossa.start();
                }

                // Dopo un errore greetd ha già chiuso la sessione in
                // configurazione: per riprovare bisogna ricominciarla, non
                // rispondere di nuovo.
                greeter.domanda = "";

                if (greeter.erroriDiFila <= greeter.erroriMax) {
                    // Ogni volta si aspetta di più: 0,9 s, 1,8 s, 3,6 s… Se il
                    // guasto passa da solo si riparte comunque; se non passa,
                    // non si consuma la macchina a ritentare.
                    riprova.interval = 900 * Math.pow(2, greeter.erroriDiFila - 1);
                    riprova.start();
                } else {
                    // Arrivati qui si smette di ritentare da soli e lo si
                    // dice: il pulsante sotto il campo resta l'unico modo di
                    // riprovare, ed è una scelta di chi guarda.
                    greeter.avviso = greeter.it
                        ? "Il servizio di accesso non risponde. Premi Invio per riprovare."
                        : "The login service is not responding. Press Enter to try again.";
                }
                break;
            }
        }
    }

    Timer {
        id: riprova
        interval: 900
        onTriggered: greeter.annullaERicomincia()
    }

    /// Chiude la sessione rimasta aperta e poi ne comincia una nuova.
    function annullaERicomincia() {
        if (greeter.avviato) return;
        riprova.stop();
        campo.text = "";
        greeter.domanda = "";
        if (!greeter.utente)
            return;
        if (greeter.finto) {
            greeter.comincia();
            return;
        }
        // `inCorso` resta vero: fra l'annullamento e la domanda nuova non c'è
        // niente da scrivere, e un campo acceso in cui la risposta finirebbe
        // nel vuoto è peggio di un campo spento.
        if (!Core.Ipc.connected) {
            greeter.perdiCanale();
            return;
        }
        greeter.canalePerso = false;
        greeter.inCorso = true;
        greeter.annullando = true;
        if (!Core.Ipc.greeterCancel())
            greeter.perdiCanale();
    }

    Component.onCompleted: Core.Ipc.greeterInfo()

    // ── Lo sfondo ────────────────────────────────────────────────────────
    //
    // Due modi, e si sceglie dalle Impostazioni:
    //
    //   «aurora»    calcolato dalla scheda grafica, si muove, non si ripete
    //   «immagine»  una fotografia, sfocata
    //
    // Il predefinito è l'aurora perché è l'unico che sta bene su qualunque
    // computer: non c'è una fotografia che sia bella su ogni schermo, e la
    // prima cosa che si vede di un sistema non può dipendere dall'aver
    // scelto lo sfondo giusto.

    readonly property string tipoSfondo: Core.Ipc.get("greeter.background", "aurora")

    Loader {
        anchors.fill: parent
        active: greeter.tipoSfondo === "aurora"
        sourceComponent: Aurora {
            forza: Core.Ipc.get("greeter.auroraStrength", 0.55)
            // Ferma quando la finestra non si vede: un'animazione che nessuno
            // guarda è batteria buttata.
            vivo: Qt.application.state === Qt.ApplicationActive || !greeter.finto
        }
    }

    Image {
        // Alla larghezza dello schermo: si sfoca, la piena risoluzione è memoria buttata.
        sourceSize.width: Math.max(1, Math.round(width))
        id: sfondo
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
        // Il greeter gira come utente `greeter`, che non ha la casa di
        // nessuno: lo sfondo di chi accede non è leggibile, e quello di
        // Minerva sì perché sta accanto al codice.
        source: {
            if (greeter.tipoSfondo === "aurora")
                return "";
            var scelto = Core.Ipc.get("greeter.wallpaper", "");
            if (scelto !== "")
                return scelto.indexOf("file://") === 0 ? scelto : "file://" + scelto;
            return Quickshell.shellDir + "/assets/wallpapers/continuum.png";
        }
    }

    // La sfocatura è quella che permette al testo di stare direttamente sulla
    // fotografia senza un pannello sotto. Senza, servirebbe un riquadro — cioè
    // esattamente la forma che questa schermata non vuole avere.
    MultiEffect {
        anchors.fill: parent
        visible: greeter.tipoSfondo !== "aurora"
        source: sfondo
        blurEnabled: greeter.sfocatura > 0
        blur: 1.0
        blurMax: Math.round(greeter.sfocatura)
        blurMultiplier: 1.0
        autoPaddingEnabled: false
    }

    // Il velo. Una fotografia chiara mangia il testo bianco, e chi sceglie lo
    // sfondo non sta pensando alla leggibilità dell'ora. Sull'aurora serve
    // meno: i colori li abbiamo scelti noi, e sono già scuri.
    Rectangle {
        anchors.fill: parent
        opacity: greeter.tipoSfondo === "aurora" ? 0.45 : 1.0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, greeter.velo * 0.75) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, greeter.velo) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, greeter.velo * 1.45) }
        }
    }

    // ── L'ora ────────────────────────────────────────────────────────────
    //
    // In cima e grande: è la cosa che si guarda mentre si arriva al computer,
    // prima ancora di decidere di entrarci.

    Column {
        id: orologio
        x: Math.round(greeter.asse - width / 2)
        anchors.bottom: colonna.top
        anchors.bottomMargin: Theme.Effects.space7
        spacing: 2
        visible: greeter.conOra

        property date adesso: new Date()

        Timer {
            interval: 1000
            running: greeter.conOra
            repeat: true
            // Si rilegge l'ora vera invece di sommare un secondo: un timer che
            // somma scivola, e questa schermata può restare aperta tutta la
            // notte.
            onTriggered: orologio.adesso = new Date()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(orologio.adesso, greeter.ore24 ? "HH:mm" : "h:mm AP")
            color: Theme.Colors._bianco
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Math.round(greeter.height * 0.135)
            font.weight: Theme.Typography.weightLight
            font.letterSpacing: 1
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // `Qt.formatDate` usa la lingua DI SISTEMA, non quella scelta in
            // Minerva: con le impostazioni in italiano la data usciva
            // «Tuesday 4 August». La lingua si passa a mano.
            text: {
                var loc = Qt.locale(greeter.it ? "it_IT" : "en_GB");
                var d = orologio.adesso.toLocaleDateString(
                            loc, greeter.it ? "dddd d MMMM" : "dddd, d MMMM");
                return d.charAt(0).toUpperCase() + d.slice(1);
            }
            color: Qt.alpha(Theme.Colors._bianco, 0.66)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeLG
            font.weight: Theme.Typography.weightMedium
            font.letterSpacing: Theme.Typography.trackingTitle
        }

    }

    // ── La riga in alto: meteo, tastiera, batteria ───────────────────────
    //
    // La stessa della schermata di blocco (`ui/StatoSchermata.qml`): due
    // schermate che si vedono una dopo l'altra devono dire le stesse cose
    // negli stessi posti.
    Ui.StatoSchermata {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space6
        it: greeter.it
        conMeteo: greeter.conMeteo
        conStato: greeter.conStato
        disposizione: greeter.disposizione
    }

    // ── L'accesso ────────────────────────────────────────────────────────
    //
    // Nessun riquadro: ritratto, nome, pillola. Galleggia.

    Column {
        id: colonna
        x: Math.round(greeter.asse - width / 2)
        anchors.verticalCenter: parent.verticalCenter
        // La pila intera — ora sopra, accesso sotto — sta a metà altezza:
        // si sposta in giù della metà dell'ora.
        anchors.verticalCenterOffset: orologio.visible
            ? Math.round((orologio.height + Theme.Effects.space7) / 2) : 0
        spacing: Theme.Effects.space4

        // Lo scatto orizzontale quando la password è sbagliata. È l'unico
        // messaggio che si capisce senza leggere.
        property real scarto: 0
        transform: Translate { x: colonna.scarto }

        SequentialAnimation {
            id: scossa
            loops: 3
            NumberAnimation { target: colonna; property: "scarto"; to: 10
                              duration: 45; easing.type: Easing.OutSine }
            NumberAnimation { target: colonna; property: "scarto"; to: -10
                              duration: 90; easing.type: Easing.InOutSine }
            NumberAnimation { target: colonna; property: "scarto"; to: 0
                              duration: 45; easing.type: Easing.InSine }
        }

        // ── Il ritratto, con l'anello che gira mentre si verifica ────────

        Item {
            width: 112
            height: 112
            anchors.horizontalCenter: parent.horizontalCenter

            // L'alone. È ciò che stacca il ritratto dallo sfondo senza
            // disegnargli attorno un bordo netto.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 26
                height: width
                radius: width / 2
                color: Qt.alpha(Theme.Colors.accent, 0.13)
                opacity: greeter.inCorso ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
            }

            Rectangle {
                id: cerchio
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors._bianco, 0.22)

                Text {
                    anchors.centerIn: parent
                    visible: !ritratto.visible
                    text: {
                        var n = greeter.utente
                            ? (greeter.utente.nomeCompleto || greeter.utente.nome)
                            : "?";
                        return n.charAt(0).toUpperCase();
                    }
                    color: Theme.Colors._bianco
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: 46
                    font.weight: Theme.Typography.weightLight
                }
            }

            Image {
                // Il doppio della misura a cui si vede: nitido, senza decodificare
                // una fotografia da dodici megapixel per un cerchio.
                sourceSize.width: Math.max(64, Math.round(width * 2))
                id: ritratto
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
                source: (greeter.utente && greeter.utente.ritratto)
                        ? "file://" + greeter.utente.ritratto : ""
                layer.enabled: visible
                layer.effect: MultiEffect { maskEnabled: true; maskSource: maschera }
            }

            Item {
                id: maschera
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "black"
                }
            }

            // L'anello che gira. Compare solo mentre si aspetta greetd: è la
            // differenza fra «sto verificando» e «non ho ricevuto il tasto»,
            // che senza un segno sono indistinguibili.
            Canvas {
                id: anello
                anchors.centerIn: parent
                width: parent.width + 12
                height: width
                visible: greeter.inCorso
                property real giro: 0

                onGiroChanged: anello.requestPaint()
                onPaint: {
                    var c = getContext("2d");
                    c.reset();
                    c.lineWidth = 2.5;
                    c.lineCap = "round";
                    c.strokeStyle = Theme.Colors.accent;
                    c.beginPath();
                    c.arc(width / 2, height / 2, width / 2 - 2,
                          anello.giro, anello.giro + Math.PI * 0.55);
                    c.stroke();
                }

                NumberAnimation on giro {
                    running: anello.visible
                    from: 0; to: Math.PI * 2
                    duration: 900
                    loops: Animation.Infinite
                }
            }
        }

        // ── Il nome ──────────────────────────────────────────────────────

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // Finché non si sa, non si dice niente: il puntino di attesa gira
            // già sopra, ed è quello il messaggio giusto in quel momento.
            text: {
                if (!greeter.utente)
                    return !greeter.informato ? ""
                           : (greeter.it ? "Nessun utente" : "No user");
                var intero = greeter.utente.nomeCompleto || greeter.utente.nome;
                if (!greeter.conSaluto)
                    return intero;
                // Il nome di battesimo, non quello intero: «Buonasera,
                // Giacomo Rossi» è un modulo, «Buonasera, Giacomo» è un
                // saluto.
                var primo = String(intero).split(" ")[0];
                // Senza nome completo resta quello d'accesso, che è minuscolo:
                // «Buonasera, giacomo» sembra un errore di battitura.
                primo = primo.charAt(0).toUpperCase() + primo.slice(1);
                return greeter.saluto(orologio.adesso) + ", " + primo;
            }
            color: Theme.Colors._bianco
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXL
            font.weight: Theme.Typography.weightMedium
            font.letterSpacing: Theme.Typography.trackingTitle
        }

        // ── La pillola ───────────────────────────────────────────────────
        //
        // Una pillola e non un rettangolo: è la differenza fra una schermata
        // di adesso e un modulo da compilare. Si allarga quando prende il
        // fuoco, e l'anello di luce le cresce attorno invece di ispessirsi —
        // un bordo che ingrassa sposta il testo dentro di un pixel.

        Item {
            id: pillola
            anchors.horizontalCenter: parent.horizontalCenter
            // Piccola. Una casella larga quanto mezzo schermo per accogliere
            // otto caratteri dice a chi guarda che ci si aspetta un tema, non
            // una password — e riempie di vuoto la parte centrale della
            // schermata, che è dove sta l'unica cosa da fare.
            width: campo.activeFocus ? 268 : 248
            height: 44

            Behavior on width {
                NumberAnimation { duration: Theme.Motion.quick
                                  easing.type: Easing.OutCubic }
            }

            // L'alone del fuoco, fuori dalla pillola.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 9
                height: parent.height + 9
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(Theme.Colors.accent,
                                       campo.activeFocus ? 0.45 : 0)
                Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, campo.activeFocus ? 0.16 : 0.11)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors._bianco,
                                       campo.activeFocus ? 0.34 : 0.18)
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
            }

            TextInput {
                id: campo
                anchors.fill: parent
                anchors.leftMargin: Theme.Effects.space4
                anchors.rightMargin: 44
                verticalAlignment: TextInput.AlignVCenter
                clip: true

                // Resta acceso anche dopo la resa, o non ci sarebbe più
                // nessun modo di riprovare: il campo sarebbe spento, la
                // domanda vuota, e la schermata un vicolo cieco.
                enabled: (greeter.domanda !== "" || greeter.arreso)
                         && !greeter.inCorso
                echoMode: greeter.rispostaSegreta ? TextInput.Password
                                                  : TextInput.Normal
                passwordCharacter: "●"
                passwordMaskDelay: 0
                color: Theme.Colors._bianco
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
                font.letterSpacing: greeter.rispostaSegreta ? 2.5 : 0
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.45)
                selectByMouse: true

                onAccepted: greeter.arreso ? greeter.riparti()
                                           : greeter.rispondi(campo.text)

                // Le maiuscole, indovinate: vedi `maiuscole` in cima. Non si
                // accetta l'evento — il tasto deve arrivare al campo.
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_CapsLock) {
                        if (greeter.maiuscoleNote)
                            greeter.maiuscole = !greeter.maiuscole;
                        return;
                    }
                    var t = e.text;
                    if (t.length === 1 && t.toLowerCase() !== t.toUpperCase()) {
                        var su = t === t.toUpperCase();
                        var shift = (e.modifiers & Qt.ShiftModifier) !== 0;
                        greeter.maiuscole = su !== shift;
                        greeter.maiuscoleNote = true;
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.verticalCenter: parent.verticalCenter
                    text: greeter.domanda !== ""
                          ? greeter.domanda.replace(/:\s*$/, "")
                          : greeter.arreso
                          ? (greeter.it ? "Premi Invio per riprovare"
                                        : "Press Enter to try again")
                          : (greeter.it ? "Un momento…" : "One moment…")
                    color: Qt.alpha(Theme.Colors._bianco, 0.45)
                    font.family: campo.font.family
                    font.pixelSize: campo.font.pixelSize
                    visible: campo.text === ""
                }
            }

            // La freccia. Sta dentro la pillola perché è la stessa azione
            // dell'Invio: due bersagli separati per un gesto solo fanno
            // esitare.
            Rectangle {
                id: freccia
                width: 32
                height: 32
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: campo.text !== ""
                       ? Qt.alpha(Theme.Colors.accent, entra.containsMouse ? 1.0 : 0.85)
                       : Qt.rgba(1, 1, 1, 0.10)
                opacity: campo.enabled ? 1 : 0.3

                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    anchors.centerIn: parent
                    name: "chevron"
                    width: 15; height: 15
                    // La freccia guarda a destra: `chevron` punta in giù, e
                    // ruotarla è più onesto che aggiungere un tracciato quasi
                    // identico al catalogo.
                    rotation: -90
                    color: campo.text !== "" ? Theme.Colors.textOnAccent
                                             : Qt.alpha(Theme.Colors._bianco, 0.5)
                }

                MouseArea {
                    id: entra
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: campo.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: greeter.rispondi(campo.text)
                }
            }
        }

        // ── L'avviso ─────────────────────────────────────────────────────
        //
        // Occupa il suo posto anche da vuoto: se comparisse spostando in giù
        // il resto, la pillola si muoverebbe sotto il dito nel momento
        // peggiore — subito dopo un errore.

        Item {
            width: pillola.width
            height: 20
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                // L'avviso vero vince; da vuoto, parlano le maiuscole — che
                // sono la ragione più comune di una password «sbagliata».
                readonly property bool soloMaiuscole: greeter.avviso === ""
                    && greeter.maiuscole && greeter.rispostaSegreta
                text: soloMaiuscole
                      ? (greeter.it ? "Maiuscole bloccate" : "Caps Lock is on")
                      : greeter.avviso
                color: soloMaiuscole ? Theme.Colors.warning
                     : greeter.avvisoGrave ? Theme.Colors.danger
                     : Qt.alpha(Theme.Colors._bianco, 0.62)
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
                elide: Text.ElideRight
                opacity: text === "" ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }
            }
        }

        // ── Gli altri utenti ─────────────────────────────────────────────
        //
        // Con uno solo la riga non c'è: un elenco a scelta singola non è una
        // scelta, è un ingombro.

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.Effects.space2
            visible: greeter.utenti.length > 1

            Repeater {
                model: greeter.utenti
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    height: 30
                    width: nomeUtente.implicitWidth + Theme.Effects.space4 * 2
                    radius: height / 2
                    color: index === greeter.utenteScelto
                           ? Qt.alpha(Theme.Colors.accent, 0.38)
                           : Qt.rgba(1, 1, 1, 0.10)
                    border.width: 1
                    border.color: Qt.alpha(Theme.Colors._bianco,
                                           index === greeter.utenteScelto ? 0.3 : 0.13)

                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        id: nomeUtente
                        anchors.centerIn: parent
                        text: modelData.nome
                        color: Theme.Colors._bianco
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (index === greeter.utenteScelto)
                                return;
                            if (greeter.avviato) return;
                            greeter.utenteScelto = index;
                            greeter.annullaERicomincia();
                        }
                    }
                }
            }
        }
    }

    // ── La sessione ──────────────────────────────────────────────────────

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space6
        spacing: Theme.Effects.space2
        visible: greeter.sessioni.length > 1

        Repeater {
            model: greeter.sessioni
            delegate: Rectangle {
                id: pillolaSessione
                required property var modelData
                required property int index

                // La via di scorta si vede, ma non si mette in mostra: più
                // scura delle altre finché non la si sceglie. Non è una
                // scrivania fra le scrivanie, è quello che si prende quando
                // niente funziona.
                readonly property bool diScorta: modelData.tipo === "tty"
                readonly property bool scelta: index === greeter.sessioneScelta

                height: 36
                width: nomeSessione.implicitWidth + Theme.Effects.space4 * 2
                radius: height / 2
                color: scelta ? Qt.alpha(Theme.Colors.accent, 0.38)
                              : Qt.rgba(1, 1, 1, diScorta ? 0.05 : 0.10)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors._bianco,
                                       scelta ? 0.3 : (diScorta ? 0.08 : 0.13))

                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    id: nomeSessione
                    anchors.centerIn: parent
                    text: modelData.nome
                    color: Qt.alpha(Theme.Colors._bianco,
                                    pillolaSessione.scelta
                                    || !pillolaSessione.diScorta ? 1 : 0.6)
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: pillolaSessione.scelta
                                 ? Theme.Typography.weightSemiBold
                                 : Theme.Typography.weightRegular
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: greeter.sessioneScelta = index
                }
            }
        }
    }

    // ── Spegnere e riavviare ─────────────────────────────────────────────

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space6
        spacing: Theme.Effects.space2

        Repeater {
            model: [
                { "icona": "restart", "comando": "systemctl reboot",
                  "it": "Riavvia", "en": "Restart" },
                { "icona": "power", "comando": "systemctl poweroff",
                  "it": "Spegni", "en": "Shut down" }
            ]

            delegate: Rectangle {
                required property var modelData

                width: 44
                height: 44
                radius: height / 2
                color: sopra.containsMouse ? Qt.rgba(1, 1, 1, 0.18)
                                           : Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors._bianco, 0.13)

                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    anchors.centerIn: parent
                    name: modelData.icona
                    width: 19; height: 19
                    color: Theme.Colors._bianco
                }

                Ui.ToolTipHint {
                    text: greeter.it ? modelData.it : modelData.en
                    shown: sopra.containsMouse
                }

                MouseArea {
                    id: sopra
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (greeter.finto) {
                            greeter.avviso = greeter.it
                                ? "Anteprima: non spengo davvero."
                                : "Preview: not actually shutting down.";
                            greeter.avvisoGrave = false;
                            return;
                        }
                        Quickshell.execDetached(["sh", "-c", modelData.comando]);
                    }
                }
            }
        }
    }

    // ── Il segno dell'anteprima ──────────────────────────────────────────
    //
    // Guardando uno scatto non si distingue una schermata vera da una provata
    // in sessione. Questa riga lo dice, e c'è solo quando è vero.

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.Effects.space4
        visible: greeter.finto
        // Dice anche come si esce: senza barra del titolo, se non sta
        // scritto qui non sta scritto da nessuna parte.
        text: greeter.it ? "ANTEPRIMA — GREETD NON È IN ASCOLTO · Esc per chiudere"
                         : "PREVIEW — GREETD IS NOT LISTENING · Esc to close"
        color: Qt.alpha(Theme.Colors._bianco, 0.30)
        font.family: Theme.Typography.fontMono
        font.pixelSize: Theme.Typography.sizeXS
        font.letterSpacing: Theme.Typography.trackingLabel
    }
}
