import QtQuick
import Quickshell
import "core" as Core
import "greeter" as Accesso

// ProveGreeter — Le prove della schermata di accesso, senza greetd e senza
// toccare il modo in cui si entra in questo computer.
//
//     qs -p minerva-shell/prove-greeter.qml
//
// ── Perché esistono ────────────────────────────────────────────────────────
//
// Il protocollo di greetd è provato nel demone (`greetd_service_test.dart`):
// lì si dimostra che una password sbagliata torna `auth_error` e che dopo
// bisogna RICOMINCIARE la sessione. Ma il pezzo che decide cosa fare di quei
// messaggi è QML, ed è dove sta il difetto che si vede: un errore che lascia
// il campo spento per sempre, o un `success` scambiato per l'altro.
//
// Qui i messaggi si emettono a mano, uno per uno, e si guarda in che stato
// resta la schermata. Nessun socket, nessuna password, nessun rischio.
//
// È anche la prima prova unitaria QML del progetto: 29.000 righe di interfaccia
// non ne avevano nessuna, ed è lì che sono nati tutti i difetti segnalati.
ShellRoot {
    id: banco

    property int passate: 0
    property int fallite: 0

    function verifica(nome, condizione, dettaglio) {
        if (condizione) {
            banco.passate++;
            console.log("  ok   " + nome);
        } else {
            banco.fallite++;
            console.log("  NO   " + nome + (dettaglio ? "  → " + dettaglio : ""));
        }
    }

    // La schermata da provare. `finto: false` perché si vuole il
    // comportamento vero: con `finto` si prenderebbe la scorciatoia.
    Accesso.Greeter {
        id: schermata
        width: 800
        height: 600
        finto: false
        visible: false

        property int quanteVolteFinito: 0
        onFinito: schermata.quanteVolteFinito++
    }

    // I messaggi si fanno arrivare emettendo i segnali di `Ipc`: è lo stesso
    // punto da cui arrivano quelli veri, quindi si prova il codice vero e non
    // una sua imitazione.
    function info(utenti, sessioni) {
        Core.Ipc.greeterInfoReceived({
            "utenti": utenti, "sessioni": sessioni, "greetd": true
        });
    }

    function messaggio(m) { Core.Ipc.greeterMessage(m); }

    readonly property var utentiFinti: [
        { "nome": "giacomo", "nomeCompleto": "Giacomo", "uid": 1000,
          "casa": "", "ritratto": "" },
        { "nome": "ospite", "nomeCompleto": "", "uid": 1001,
          "casa": "", "ritratto": "" }
    ]

    readonly property var sessioniFinte: [
        { "id": "hyprland", "nome": "Hyprland", "descrizione": "",
          "comando": "/usr/bin/start-hyprland", "tipo": "wayland" },
        { "id": "minerva", "nome": "Minerva", "descrizione": "",
          "comando": "/usr/local/bin/minerva-session", "tipo": "wayland" },
        // Plasma è quella su cui il difetto si vedeva, ed è diversa dalle
        // altre in due modi che contano: dichiara `DesktopNames=KDE` — un
        // nome che NON è il suo id — e il suo `Exec` è di due parole.
        { "id": "plasma", "nome": "Plasma (Wayland)", "descrizione": "",
          "comando": "/usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland",
          "tipo": "wayland", "nomiScrivania": "KDE" },
        // La nostra, come la dichiara il suo `.desktop`: punto e virgola fra
        // i nomi e uno anche in fondo, che è il formato di `DesktopNames`.
        // Nella variabile ci vanno i DUE PUNTI.
        { "id": "minerva-vero", "nome": "Minerva", "descrizione": "",
          "comando": "/usr/local/bin/minerva-session", "tipo": "wayland",
          "nomiScrivania": "Minerva;Hyprland;" }
    ]

    Component.onCompleted: {
        console.log("── Prove della schermata di accesso ──");

        // ── Cosa si sa all'inizio ────────────────────────────────────────

        // PRIMA di sapere chi c'è. Il nome sotto il ritratto diceva «Nessun
        // utente» in questo momento — cioè nei secondi in cui il demone del
        // greeter sta ancora partendo — e chi guardava leggeva su una
        // schermata di accesso che il computer non lo conosce più.
        banco.verifica("prima della risposta non sa ancora chi c'è",
                       !schermata.informato);

        banco.info(banco.utentiFinti, banco.sessioniFinte);

        banco.verifica("dopo la risposta lo sa", schermata.informato);

        banco.verifica("legge gli utenti", schermata.utenti.length === 2);
        banco.verifica("sceglie Minerva e non la prima in ordine alfabetico",
                       schermata.sessione && schermata.sessione.id === "minerva",
                       schermata.sessione ? schermata.sessione.id : "nessuna");

        // ── La domanda ───────────────────────────────────────────────────

        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "secret",
                          "auth_message": "Password: " });

        banco.verifica("mostra la domanda di PAM, non una scritta nostra",
                       schermata.domanda === "Password:",
                       "«" + schermata.domanda + "»");
        banco.verifica("nasconde quello che si scrive", schermata.rispostaSegreta);
        banco.verifica("non è più in attesa", !schermata.inCorso);

        // Una domanda VISIBILE non va nascosta: capita con le chiavi a
        // scadenza e con certi lettori.
        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "visible",
                          "auth_message": "Codice:" });
        banco.verifica("una domanda visibile resta visibile",
                       !schermata.rispostaSegreta);

        // ── Un messaggio che non chiede niente ───────────────────────────

        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "info",
                          "auth_message": "La password scade fra 3 giorni" });
        banco.verifica("un avviso informativo si mostra",
                       schermata.avviso === "La password scade fra 3 giorni");
        banco.verifica("un avviso informativo non è grave",
                       !schermata.avvisoGrave);

        // ── La password sbagliata ────────────────────────────────────────

        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "secret",
                          "auth_message": "Password: " });
        banco.messaggio({ "type": "error", "error_type": "auth_error",
                          "description": "Authentication failure" });

        banco.verifica("dice che la password è sbagliata",
                       schermata.avviso.indexOf("sbagliat") !== -1
                       || schermata.avviso.indexOf("Wrong") !== -1,
                       "«" + schermata.avviso + "»");
        banco.verifica("lo segna come grave", schermata.avvisoGrave);
        banco.verifica("CHIUDE la domanda: dopo un errore greetd ha già "
                       + "chiuso la sessione, rispondere ancora parlerebbe "
                       + "nel vuoto",
                       schermata.domanda === "");
        banco.verifica("non resta a credere di aver già superato l'accesso",
                       !schermata.avviato);

        // Il difetto peggiore possibile qui: restare bloccati. Dopo l'errore
        // parte un timer che ricomincia da solo — se non ripartisse, la
        // schermata resterebbe con il campo spento e nessun modo di riprovare
        // se non riavviare il computer.
        banco.verifica("il campo è spento SOLO per il momento dell'errore",
                       schermata.domanda === "" && !schermata.inCorso);

        // ── La password giusta ───────────────────────────────────────────

        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "secret",
                          "auth_message": "Password: " });
        banco.messaggio({ "type": "success" });

        banco.verifica("il primo «sì» NON chiude la schermata: è quello "
                       + "dell'autenticazione, non quello dell'avvio",
                       schermata.quanteVolteFinito === 0);
        banco.verifica("segna che si è passati all'avvio", schermata.avviato);

        banco.messaggio({ "type": "success" });

        banco.verifica("il secondo «sì» chiude: la sessione parte quando il "
                       + "greeter finisce",
                       schermata.quanteVolteFinito === 1);

        // ── Un guasto che non è una password sbagliata ───────────────────

        schermata.avviato = false;
        banco.messaggio({ "type": "error", "error_type": "error",
                          "description": "greetd è morto" });
        banco.verifica("un guasto mostra il messaggio vero e non «password "
                       + "sbagliata»",
                       schermata.avviso === "greetd è morto",
                       "«" + schermata.avviso + "»");

        // ── Il «sì» dell'annullamento NON è un accesso riuscito ──────────
        //
        // Il difetto peggiore di tutta la schermata, trovato il 10 agosto 2026
        // provandola in carne e ossa. Dopo una password sbagliata greetd tiene
        // la sessione aperta e bisogna annullarla prima di ricominciare. Ma la
        // sua risposta è `success` — la STESSA parola con cui dice «password
        // accettata». Presa per quella, la schermata chiede di aprire la
        // sessione, greetd risponde «session is not ready», e la schermata si
        // chiude portandosi dietro il compositore: Giacomo si è ritrovato
        // davanti a un terminale nero dopo aver sbagliato la password.
        //
        // Il `success` di qui sotto deve finire nel nulla.

        schermata.erroriDiFila = 0;
        schermata.avviato = false;
        var chiusurePrima = schermata.quanteVolteFinito;

        schermata.annullaERicomincia();
        banco.verifica("chiedendo di annullare, la schermata sa di star "
                       + "annullando", schermata.annullando);

        banco.messaggio({ "type": "success" });

        banco.verifica("il «sì» all'annullamento non viene preso per un "
                       + "accesso riuscito", !schermata.avviato);
        banco.verifica("e non chiude la schermata: è così che si finisce su "
                       + "un terminale nero",
                       schermata.quanteVolteFinito === chiusurePrima);
        banco.verifica("finito l'annullamento, si ricomincia da capo",
                       !schermata.annullando);

        // Anche un ERRORE in risposta all'annullamento va consumato: greetd
        // risponde «no session under configuration» quando non c'era niente
        // da annullare, ed è una risposta normale, non un guasto da mostrare.
        schermata.avviso = "";
        schermata.annullaERicomincia();
        banco.messaggio({ "type": "error", "error_type": "error",
                          "description": "no session under configuration" });
        banco.verifica("un annullamento a vuoto non diventa un errore a "
                       + "schermo", schermata.avviso === "",
                       "«" + schermata.avviso + "»");
        banco.verifica("e non conta come tentativo fallito",
                       schermata.erroriDiFila === 0);

        // ── Una tempesta di errori non deve diventare un tremito ─────────
        //
        // Il 10 agosto 2026, provando la schermata vera su una console libera:
        // «la parte dove c'è nome utente e password comincia a tremare
        // all'infinito verso destra e sinistra se inserisco una password
        // sbagliata».
        //
        // Dopo un errore la schermata ricomincia la sessione da sola: giusto,
        // è ciò che permette di riprovare. Ma se anche il tentativo nuovo
        // fallisce, si ottiene errore → scossa → riprova → errore, ogni 900
        // ms, senza fine. La scossa vuol dire «hai sbagliato a scrivere»:
        // ripetuta per sempre non vuol dire più niente.

        schermata.erroriDiFila = 0;
        schermata.avviato = false;
        var scossePrima = schermata.scosse;

        for (var i = 0; i < 7; i++) {
            banco.messaggio({ "type": "error", "error_type": "auth_error",
                              "description": "Authentication failure" });
        }

        banco.verifica("sette errori di fila scuotono la schermata UNA volta",
                       schermata.scosse === scossePrima + 1,
                       "scosse " + (schermata.scosse - scossePrima) + " volte");
        banco.verifica("dopo qualche tentativo smette di ritentare da sola",
                       schermata.arreso);
        banco.verifica("e smette anche di dare la colpa alla password",
                       schermata.avviso.indexOf("non risponde") !== -1
                       || schermata.avviso.indexOf("not responding") !== -1,
                       "«" + schermata.avviso + "»");
        banco.verifica("ma resta un modo di riprovare: il campo non si spegne",
                       schermata.arreso && !schermata.inCorso);

        // E riprovando a mano si riparte davvero da capo.
        schermata.riparti();
        banco.verifica("riprovando a mano il conto degli errori riparte",
                       schermata.erroriDiFila === 0 && !schermata.arreso);
        banco.verifica("e l'avviso di guasto sparisce", schermata.avviso === "");

        // Una domanda di PAM azzera il conto: vuol dire che si è tornati a
        // parlare, e il tentativo dopo deve poter riscuotere come il primo.
        //
        // Il `riparti()` qui sopra ha lasciato un annullamento in volo: la
        // prima risposta è sua, e va consumata prima di poter provare
        // qualunque altra cosa. Vale anche fuori dalle prove — è il motivo per
        // cui `annullando` esiste.
        banco.messaggio({ "type": "success" });
        banco.verifica("l'annullamento in volo si consuma prima del resto",
                       !schermata.annullando);

        schermata.erroriDiFila = 3;
        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "secret",
                          "auth_message": "Password: " });
        banco.verifica("una domanda di PAM azzera il conto degli errori",
                       schermata.erroriDiFila === 0);

        // ── L'annullamento che risponde ERRORE ───────────────────────────
        //
        // Il caso vero, visto nel registro del greeter il 16 agosto 2026 su
        // greetd 0.10.3:
        //
        //     greetd risponde errore (auth_error): pam_authenticate: AUTH_ERR
        //     greetd risponde errore (error): unable to send message:
        //                                     Connection refused (os error 111)
        //
        // greetd fa la conversazione con PAM dentro un processo figlio, e
        // quando `pam_authenticate` fallisce quel figlio esce. Il
        // `cancel_session` che mandiamo subito dopo arriva quindi a un morto, e
        // greetd risponde ERRORE invece di «sì».
        //
        // Chi aspettasse un `success` per andare avanti resterebbe fermo per
        // sempre: schermata di accesso viva, bella, che dopo una password
        // sbagliata non chiede più niente. È lo stesso modo di fallire del
        // «terminale nero» del 10 agosto, dall'altra parte.
        schermata.erroriDiFila = 0;
        schermata.avviso = "";
        schermata.domanda = "";
        schermata.annullaERicomincia();
        banco.verifica("dopo un errore si annulla, e si aspetta la risposta",
                       schermata.annullando);

        banco.messaggio({ "type": "error", "error_type": "error",
                          "description": "unable to send message: "
                                       + "Connection refused (os error 111)" });
        banco.verifica("un ERRORE all'annullamento vale come un sì",
                       !schermata.annullando,
                       "la schermata resta in attesa di una risposta che non "
                       + "arriverà mai");
        banco.verifica("e non lo mostra come guasto a chi guarda",
                       schermata.avviso === "",
                       "«" + schermata.avviso + "»");

        banco.messaggio({ "type": "auth_message",
                          "auth_message_type": "secret",
                          "auth_message": "Password: " });
        banco.verifica("e la password si può riscrivere",
                       schermata.domanda !== "" && !schermata.inCorso,
                       "domanda «" + schermata.domanda + "», inCorso "
                       + schermata.inCorso);

        // ── L'ambiente con cui parte la sessione ─────────────────────────
        //
        // Il difetto peggiore che questa schermata abbia avuto, e il più
        // difficile da vedere: la password veniva accettata, la sessione
        // partiva, e moriva in meno di un secondo. Da fuori è identico a una
        // password sbagliata — si torna alla schermata di accesso e basta.
        //
        // Giacomo, 17 agosto 2026: «mi fa entrare solo con cosmic e minerva,
        // hyprland e kde mi portano sempre su minerva». E il 23 agosto,
        // ancora: «kde appena clicco per entrare mi riporta al login».
        //
        // Passava UNA variabile, `XDG_SESSION_DESKTOP`. Le altre tre le passa
        // ogni gestore di accessi, e senza `XDG_CURRENT_DESKTOP` una scrivania
        // non riconosce sé stessa — né la riconoscono i portali xdg, che da
        // quella scelgono a chi chiedere per file, schermo e password.

        var envKde = schermata.ambienteSessione(banco.sessioniFinte[2]);
        function ha(elenco, chiave) {
            for (var i = 0; i < elenco.length; i++)
                if (String(elenco[i]).indexOf(chiave + "=") === 0)
                    return String(elenco[i]).substring(chiave.length + 1);
            return null;
        }

        banco.verifica("la sessione parte sapendo QUALE scrivania è",
                       ha(envKde, "XDG_CURRENT_DESKTOP") === "KDE",
                       "XDG_CURRENT_DESKTOP = " + ha(envKde, "XDG_CURRENT_DESKTOP"));
        banco.verifica("e sapendo che è Wayland",
                       ha(envKde, "XDG_SESSION_TYPE") === "wayland",
                       "XDG_SESSION_TYPE = " + ha(envKde, "XDG_SESSION_TYPE"));
        banco.verifica("e che è la sessione di una persona",
                       ha(envKde, "XDG_SESSION_CLASS") === "user");
        banco.verifica("e come si chiama il suo file",
                       ha(envKde, "XDG_SESSION_DESKTOP") === "plasma");

        // `DesktopNames` non è l'id: per Plasma vale «KDE». Prendere l'id
        // sarebbe stato peggio del niente — una scrivania che si sente
        // chiamare con un nome che non è il suo.
        var envMin = schermata.ambienteSessione(banco.sessioniFinte[1]);
        banco.verifica("e chi non dichiara DesktopNames ripiega sul nome",
                       ha(envMin, "XDG_CURRENT_DESKTOP") === "Minerva",
                       "XDG_CURRENT_DESKTOP = " + ha(envMin, "XDG_CURRENT_DESKTOP"));

        // ── Da `DesktopNames` a `XDG_CURRENT_DESKTOP` ────────────────────
        //
        // Due specifiche, due separatori per la stessa lista: punto e virgola
        // nel file, due punti nella variabile. Passandola com'è scritta,
        // `Minerva;Hyprland;` è un nome solo — un nome che non esiste — e ogni
        // confronto fallisce in silenzio.

        var envNostra = schermata.ambienteSessione(banco.sessioniFinte[3]);
        banco.verifica("i nomi della scrivania passano ai due punti",
                       ha(envNostra, "XDG_CURRENT_DESKTOP") === "Minerva:Hyprland",
                       "XDG_CURRENT_DESKTOP = " + ha(envNostra, "XDG_CURRENT_DESKTOP"));
        banco.verifica("e il punto e virgola finale non lascia un nome vuoto",
                       ha(envNostra, "XDG_CURRENT_DESKTOP").indexOf("::") < 0
                       && ha(envNostra, "XDG_CURRENT_DESKTOP").slice(-1) !== ":");
        banco.verifica("un nome solo resta un nome solo",
                       ha(envKde, "XDG_CURRENT_DESKTOP") === "KDE");

        // ── Il comando che si manda a greetd ─────────────────────────────
        //
        // greetd NON esegue questo array come un `argv`: lo unisce con degli
        // spazi e lo dà a `/bin/sh -c`. Un `sh -lc` nostro davanti diventava
        // quindi un secondo interprete, e la riga `Exec=` di Plasma — l'unica
        // di due parole — arrivava spezzata: partiva solo il primo pezzo, che
        // esce subito e senza dire niente. È il motivo per cui KDE non
        // entrava.

        schermata.avviatoreCE = false;
        var cmdSenza = schermata.comandoDiAvvio(banco.sessioniFinte[2]);
        banco.verifica("senza avviatore si manda UN elemento solo",
                       cmdSenza.length === 1,
                       cmdSenza.length + " elementi: " + JSON.stringify(cmdSenza));
        banco.verifica("e nessuno di quelli è una shell nostra",
                       cmdSenza.join(" ").indexOf("sh -lc") < 0
                       && cmdSenza[0] !== "sh");
        banco.verifica("l'elemento è la riga del .desktop, tutta",
                       cmdSenza[0] === banco.sessioniFinte[2].comando,
                       "«" + cmdSenza[0] + "»");

        schermata.avviatoreCE = true;
        var cmdCon = schermata.comandoDiAvvio(banco.sessioniFinte[2]);
        banco.verifica("con l'avviatore gli elementi sono due",
                       cmdCon.length === 2,
                       cmdCon.length + " elementi");
        banco.verifica("il primo è l'avviatore",
                       cmdCon[0] === schermata.avviatore);
        banco.verifica("il secondo è la riga intera, non la prima parola",
                       cmdCon[1] === banco.sessioniFinte[2].comando,
                       "«" + cmdCon[1] + "»");
        schermata.avviatoreCE = false;

        // ── Quale sessione risulta già scelta ────────────────────────────
        //
        // Giacomo, 23 agosto 2026: «ci vorrebbe che il login ricordi l'ultimo
        // desktop environment usato e sia già posizionato su di essi e si
        // aggiorni ad ogni rimozione o aggiunta di altri DE».
        //
        // La parte difficile non è ricordare: è cosa fare quando quello che si
        // ricordava non c'è più. L'elenco si rilegge da `/usr/share` a ogni
        // accesso, quindi disinstallare una scrivania la fa sparire, e senza
        // un ripiego si ricadrebbe sulla prima in ordine alfabetico.

        var conScorta = banco.sessioniFinte.concat([
            { "id": "console", "nome": "Riga di comando", "descrizione": "",
              "comando": "exec ${SHELL:-/bin/sh} -l", "tipo": "tty" }
        ]);

        banco.verifica("si riapre sull'ultima scrivania usata",
                       schermata.qualeSessione(conScorta, "plasma") === 2,
                       "indice " + schermata.qualeSessione(conScorta, "plasma"));
        banco.verifica("se quella di prima è stata disinstallata, ripiega su Minerva",
                       schermata.qualeSessione(conScorta, "gnome") === 1,
                       "indice " + schermata.qualeSessione(conScorta, "gnome"));
        banco.verifica("senza nemmeno Minerva prende la prima scrivania vera",
                       schermata.qualeSessione(
                           [conScorta[4], conScorta[0]], "gnome") === 1);
        banco.verifica("non si riapre MAI sulla riga di comando",
                       schermata.qualeSessione(conScorta, "console") === 1,
                       "indice " + schermata.qualeSessione(conScorta, "console"));
        banco.verifica("…tranne quando è rimasta l'unica",
                       schermata.qualeSessione([conScorta[4]], "console") === 0);
        banco.verifica("un elenco vuoto non fa saltare niente",
                       schermata.qualeSessione([], "minerva") === 0);

        // ── E il giorno che «minerva» sparisce dall'elenco ───────────────
        //
        // Successo il 2 settembre 2026: la sessione su Hyprland è stata tolta
        // e il ripiego scritto a mano puntava proprio a lei. Chi aveva
        // `greeter.session = "minerva"` — cioè Giacomo — si sarebbe ritrovato
        // preselezionata la prima non-tty in elenco: COSMIC, o peggio il
        // recupero, che è il nostro compositore con dentro un terminale e
        // nient'altro.
        //
        // Entrare in una scrivania vuota senza averlo chiesto vuol dire
        // credere che Minerva sia rotta.
        var dopoIlDistacco = [
            { "id": "cosmic", "nome": "COSMIC", "descrizione": "",
              "comando": "/usr/bin/start-cosmic", "tipo": "wayland" },
            { "id": "minerva-recupero", "nome": "Minerva (recupero)",
              "descrizione": "", "comando": "/usr/local/bin/minerva-session-recupero",
              "tipo": "wayland" },
            { "id": "minerva-wayland", "nome": "Minerva", "descrizione": "",
              "comando": "/usr/local/bin/minerva-session-wayland",
              "tipo": "wayland" }
        ];
        banco.verifica("tolta la sessione vecchia, si ripiega su quella nostra",
                       schermata.qualeSessione(dopoIlDistacco, "minerva") === 2,
                       "indice " + schermata.qualeSessione(dopoIlDistacco, "minerva"));
        banco.verifica("e non sul RECUPERO, che è una via di scorta",
                       schermata.qualeSessione(dopoIlDistacco, "minerva") !== 1);
        banco.verifica("nemmeno quando Minerva non c'è affatto",
                       schermata.qualeSessione(
                           [dopoIlDistacco[0], dopoIlDistacco[1]], "minerva") === 0,
                       "indice " + schermata.qualeSessione(
                           [dopoIlDistacco[0], dopoIlDistacco[1]], "minerva"));
        banco.verifica("ma se è rimasto solo lui, si prende lui",
                       schermata.qualeSessione([dopoIlDistacco[1]], "minerva") === 0);

        // ── Cosa si ricorda ──────────────────────────────────────────────
        //
        // Finire sulla riga di comando vuol dire che qualcosa era rotto.
        // Ritrovarsela preselezionata la volta dopo — magari dopo aver
        // riparato il guaio — vorrebbe dire entrare in un terminale senza
        // averlo chiesto.

        banco.verifica("dopo un accesso si ricorda la scrivania",
                       schermata.idDaRicordare(banco.sessioniFinte[2]) === "plasma");
        banco.verifica("ma non si ricorda la riga di comando",
                       schermata.idDaRicordare(conScorta[4]) === "");
        banco.verifica("e non si ricorda il nulla",
                       schermata.idDaRicordare(null) === "");

        // ── E adesso le sessioni VERE di questo computer ─────────────────
        //
        // Tutto quello che sta sopra usa dati finti, ed è giusto: prova la
        // regola e non la macchina. Ma la domanda di Giacomo era «entra in
        // tutti i desktop environment disponibili», e a quella i dati finti
        // non rispondono — KDE non entrava proprio perché la SUA riga `Exec=`
        // era diversa da tutte le altre, e nessuna prova la guardava.
        //
        // Qui si chiede al demone l'elenco vero, e per ogni sessione
        // installata si calcola esattamente quello che la schermata
        // manderebbe a greetd. Non fa entrare nessuno — costruisce il
        // messaggio e lo controlla — ma è tutto quello che si può verificare
        // senza riavviare, ed è il pezzo che si era rotto.
        // L'interruttore si arma QUI e non prima: `banco.info()`, in cima a
        // queste prove, emette lo stesso segnale con l'elenco finto, e un
        // gestore già acceso lo scambiava per quello vero. Ci sono cascato
        // scrivendo questa prova, e il sintomo era una prova che falliva
        // dicendo il falso sul computer — «nessuna via di scorta» — mentre il
        // demone la mandava eccome.
        banco.aspettoQuelleVere = true;
        Core.Ipc.greeterInfo();
        vere.start();
    }

    Timer {
        id: vere
        // Otto secondi: il demone si collega dopo che queste prove sono
        // partite, e con tre secondi la risposta arrivava a volte sì e a
        // volte no. Una prova che passa a caso è peggio di una che manca.
        interval: 8000
        onTriggered: {
            // Il demone non ha risposto: non è un fallimento delle prove, è
            // un demone che non c'è. Si dice e si va avanti.
            banco.verifica("(saltata) il demone non ha mandato le sessioni vere",
                           true);
            banco.fine();
        }
    }

    Connections {
        target: Core.Ipc
        enabled: banco.aspettoQuelleVere

        function onGreeterInfoReceived(info) {
            if (!banco.aspettoQuelleVere)
                return;
            banco.aspettoQuelleVere = false;
            vere.stop();
            banco.controllaQuelleVere(info.sessioni || []);
            banco.fine();
        }
    }

    property bool aspettoQuelleVere: false

    function controllaQuelleVere(sessioni) {
        banco.verifica("il demone conosce almeno una sessione",
                       sessioni.length > 0, sessioni.length + " sessioni");

        var scorte = 0;
        for (var i = 0; i < sessioni.length; i++) {
            var s = sessioni[i];
            var nome = String(s.nome || s.id);

            // 1. Il comando è UN elemento solo, ed è la riga del `.desktop`
            //    tutta intera. È il difetto di KDE: la sua riga ha due parole
            //    e arrivava spezzata.
            schermata.avviatoreCE = false;
            var cmd = schermata.comandoDiAvvio(s);
            banco.verifica(nome + ": un elemento, la riga intera",
                           cmd.length === 1 && cmd[0] === s.comando,
                           JSON.stringify(cmd));

            // 2. Con l'avviatore: due elementi, e il secondo è ancora la riga
            //    intera. Se qui ne comparisse uno terzo vorrebbe dire che
            //    qualcuno l'ha rispezzata.
            schermata.avviatoreCE = true;
            var conAvv = schermata.comandoDiAvvio(s);
            banco.verifica(nome + ": con l'avviatore restano due elementi",
                           conAvv.length === 2 && conAvv[1] === s.comando,
                           JSON.stringify(conAvv));
            schermata.avviatoreCE = false;

            // 3. L'ambiente. Le quattro variabili ci sono, e
            //    XDG_CURRENT_DESKTOP non contiene punto e virgola.
            var env = schermata.ambienteSessione(s);
            function ha(chiave) {
                for (var k = 0; k < env.length; k++)
                    if (String(env[k]).indexOf(chiave + "=") === 0)
                        return String(env[k]).substring(chiave.length + 1);
                return null;
            }
            banco.verifica(nome + ": sa che sessione è",
                           ha("XDG_SESSION_DESKTOP") === s.id);
            banco.verifica(nome + ": sa se è wayland o x11",
                           ha("XDG_SESSION_TYPE") === s.tipo);
            banco.verifica(nome + ": è la sessione di una persona",
                           ha("XDG_SESSION_CLASS") === "user");

            if (s.tipo === "tty") {
                scorte++;
                // La via di scorta non dichiara nessuna scrivania: un nome lì
                // dentro farebbe cercare ai portali una scrivania che non c'è.
                banco.verifica(nome + ": non dichiara nessuna scrivania",
                               ha("XDG_CURRENT_DESKTOP") === null);
                banco.verifica(nome + ": avvia la shell di chi entra",
                               String(s.comando).indexOf("SHELL") >= 0,
                               String(s.comando));
            } else {
                var d = ha("XDG_CURRENT_DESKTOP");
                banco.verifica(nome + ": sa quale scrivania è",
                               d !== null && d !== "", String(d));
                banco.verifica(nome + ": i nomi sono separati dai due punti",
                               String(d).indexOf(";") < 0
                               && String(d).slice(-1) !== ":",
                               String(d));
            }
        }

        // La via di scorta c'è, ed è una sola. Zero vorrebbe dire che un
        // giorno una scrivania rotta chiude fuori dal computer; due vorrebbe
        // dire che il demone la aggiunge due volte.
        banco.verifica("c'è esattamente una via di scorta col terminale",
                       scorte === 1, scorte + " trovate");
        banco.verifica("e sta in fondo all'elenco, non davanti",
                       sessioni.length > 0
                       && sessioni[sessioni.length - 1].tipo === "tty");
    }

    // ── Esito ────────────────────────────────────────────────────────────

    function fine() {
        console.log("──");
        console.log(banco.fallite === 0
                    ? "TUTTE PASSATE (" + banco.passate + ")"
                    : "FALLITE " + banco.fallite + " su "
                      + (banco.passate + banco.fallite));
        Qt.exit(banco.fallite === 0 ? 0 : 1);
    }
}
