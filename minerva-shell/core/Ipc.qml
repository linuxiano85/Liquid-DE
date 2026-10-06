pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ipc — Canale unico verso il demone minervad (un socket Unix)
//
// Prima ogni componente apriva il proprio canale: N connessioni, N copie
// delle impostazioni, nessuna riconnessione. Qui la connessione è una sola,
// si riapre da sola se il demone riparte, e lo stato è condiviso da tutti.
//
// Uso tipico:
//     Ipc.setSetting("cheatsheet.enabled", true)
//     Connections { target: Ipc; function onAllAppsReceived(apps) { ... } }
QtObject {
    id: ipc

    // ── Stato osservabile ────────────────────────────────────────────────
    /// Connessi vuol dire **salutati**, non solo «il socket è aperto».
    ///
    /// Fra le due cose c'è la parola d'ordine (vedi `_segreto` più sotto), e
    /// finché non è stata accettata il demone non risponde a niente. Se
    /// `connected` diventasse vera prima, ogni finestra manderebbe le sue
    /// richieste dentro un canale che le butta via — e non si vedrebbe un
    /// errore, si vedrebbe una finestra vuota.
    readonly property bool connected: ipc._aperto
                                      && ipc._salutato

    property bool _salutato: false

    /// Vero quando il socket vivo è aperto.
    ///
    /// Sta qui e non si legge da `socket.connected` perché **il socket non è
    /// più sempre lo stesso oggetto**: si ricrea a ogni tentativo, e per un
    /// istante non ce n'è nessuno. Vedi `_rinnova()`.
    property bool _aperto: false

    /// Il socket vivo, o `null` fra un tentativo e il prossimo.
    property var _vivo: null


    /// Impostazioni correnti (rispecchia config/settings.json)
    property var settings: ({})

    /// Vero quando si può DISEGNARE senza rischiare i colori sbagliati.
    ///
    /// Il tema arriva dal demone: finché non è arrivato, `get("shell.scheme")`
    /// restituisce il ripiego, che è `notte`. Chi ha scelto un altro tema —
    /// per esempio `ametista`, viola — vedrebbe la finestra aprirsi ciano e
    /// poi scattare al colore giusto.
    ///
    /// Non era un rischio teorico: misurato, le impostazioni arrivavano
    /// SEDICI MILLISECONDI prima che la finestra andasse a schermo. Un
    /// fotogramma. Al momento dell'accesso, con più finestre che partono
    /// insieme e il demone che sta ancora leggendo i suoi file, quel margine
    /// non c'è — e il lampo si vede.
    ///
    /// Adesso chi disegna aspetta questo. Non costa niente nel caso normale
    /// (le impostazioni arrivavano comunque prima) e toglie il lampo in
    /// quello cattivo.
    ///
    /// ── PERCHÉ NON UN TIMER, MA LO STATO DELLA CONNESSIONE ───────────────
    ///
    /// La prima versione aspettava un quarto di secondo e poi rinunciava. Era
    /// un numero inventato, e sbagliato in tutti e due i versi: le
    /// impostazioni arrivano 170 ms dopo che questo oggetto esiste, quindi il
    /// margine era di ottanta millisecondi — al momento dell'accesso, con la
    /// macchina carica, non basta e il lampo torna. E dall'altra parte, se il
    /// demone non c'è affatto, aspettare un quarto di secondo è tempo buttato
    /// quando la risposta si sa già.
    ///
    /// Non serve indovinare: **il socket lo dice**. Se fallisce o si chiude,
    /// si SA che le impostazioni non stanno arrivando → si dipinge subito coi
    /// valori di fabbrica. Se è aperto o si sta aprendo, si aspetta: su un
    /// socket locale mancano microsecondi, non decimi di secondo.
    ///
    /// Resta una sola scadenza, e fa da rete per il caso patologico — socket
    /// aperto, demone che non risponde più. Larga di proposito: adesso non è
    /// più lei a gestire il caso normale del demone assente, quindi può
    /// permettersi di essere paziente.
    readonly property bool prontoADipingere:
        ipc._settingsNote || ipc._nessunDemone || ipc._troppoTempo

    /// Vero da quando le impostazioni VERE sono arrivate dal demone.
    ///
    /// Serve a chi non deve limitarsi a disegnare in ritardo, ma non deve
    /// proprio AGIRE prima: finché è falso, `get()` risponde con i valori di
    /// ripiego, che sono plausibili e sbagliati. Chi con quei valori scrive
    /// qualcosa fuori da sé — la configurazione del compositore, un file —
    /// scrive una cosa falsa e nessuno gli dice che era falsa.
    ///
    /// È successo il 10 agosto: `BarreCompositore` scriveva al plugin
    /// `height 34` (il ripiego) mentre l'altezza vera era 38. Hyprland
    /// riservava 38, la barra ne disegnava 34, e restavano quattro pixel di
    /// scarto — «la barra è staccata dalla finestra e la linea rosa è un
    /// pochino storta», parole di Giacomo mentre guardava.
    readonly property bool impostazioniArrivate: ipc._settingsNote

    property bool _settingsNote: false

    /// Vero dopo la PRIMA connessione riuscita. Distingue «non è ancora
    /// partito» da «se n'è andato»: vedi `onStatusChanged`.
    property bool _eraConnesso: false

    /// Il distacco in corso è già stato annunciato. Si riarma al
    /// prossimo saluto accettato.
    property bool _perditaDetta: false

    /// Il socket ha detto di no. Non è un'ipotesi: è una risposta.
    ///
    /// **`_haProvato` non è una cautela in più: senza, è tutto rotto.** Una
    /// Un `Socket` nasce staccato e lo resta un istante
    /// dopo, quindi leggere `Closed` da solo vuol dire scambiare «non ho
    /// ancora provato» per «ho provato e non c'è». Misurato con questo
    /// controllo tolto: la finestra si dipingeva a 236 ms col tema di
    /// ripiego e correggeva a 297 — cioè il lampo che tutto questo serve a
    /// togliere, reso SICURO invece che possibile.
    readonly property bool _nessunDemone: ipc._haProvato
        && !ipc._aperto

    /// Vero da quando il socket ha davvero tentato almeno una volta.
    property bool _haProvato: false

    /// La rete per il demone muto: connesso e zitto. Tre secondi, perché il
    /// caso frequente (demone assente) lo risolve già `_nessunDemone`.
    property bool _troppoTempo: false
    property Timer _scadenza: Timer {
        interval: 3000
        running: !ipc._settingsNote
        onTriggered: ipc._troppoTempo = true
    }

    /// Le scorciatoie, come le legge il demone da `config/scorciatoie.minerva`.
    property var keybindings: []

    /// Elenco completo delle applicazioni installate
    property var allApps: []

    /// Le icone di Minerva tradotte nel tema installato sul computer, per chi
    /// preferisce le icone classiche a quelle disegnate da noi:
    /// `{ "settings": { "s": "/percorso/22.svg", "l": "/percorso/48.svg" } }`.
    ///
    /// La costruisce il demone, che sa leggere gli `index.theme`, e arriva già
    /// con `init_state`: le icone non hanno un attimo in cui sono quelle
    /// sbagliate. I nomi che il tema non ha semplicemente non ci sono, e la
    /// shell disegna il proprio tracciato.
    property var iconMap: ({})
    /// Quante icone Minerva chiede in tutto, e quali il tema scelto non ha.
    /// Servono a dire in Impostazioni quanto copre un tema, invece di
    /// lasciare che si scopra guardando la barra.
    property int iconChieste: 0
    property var iconMancanti: []

    /// Il tema di icone effettivamente in uso — quello scelto in Impostazioni,
    /// o quello del sistema se non si è scelto niente. È il nome della
    /// VARIANTE: «Colloid-Dark», non «Colloid».
    property string iconTheme: ""

    /// La FAMIGLIA scelta in Impostazioni, vuota se si segue il sistema. È
    /// questa che l'elenco deve evidenziare: chi ha scelto «Colloid» non deve
    /// vedersi acceso «Colloid-Dark», che nell'elenco non compare — la
    /// variante la sceglie il demone in base allo sfondo dell'interfaccia.
    property string iconChosen: ""

    /// I temi di icone installati. Vuoto finché non li si chiede.
    property var iconThemes: []
    /// Quelli nella cartella dell'utente, che si possono togliere:
    /// `[{nome, cartella}]`. Arrivano insieme a `iconThemes`.
    property var iconeInstallate: []

    /// Lo stato dell'apparecchio — batteria, luminosità, rete, Bluetooth —
    /// letto dal demone UNA volta per tutte le finestre.
    ///
    /// Prima ogni processo se lo leggeva da sé con un giro da dodici secondi,
    /// e i tre non si parlavano: spegnendo il Bluetooth dalle Impostazioni,
    /// la barra continuava a mostrarlo acceso fino al proprio giro. Chi lo
    /// usa è `Core.SystemState`, che resta l'unico nome da conoscere.
    property var system: ({})
    signal systemReceived()
    signal systemAudioState(var data)
    signal systemAudioSelected(var data)
    /// I pad di gioco: quali ci sono, se InputPlumber li gestisce, con che
    /// tipo. Arriva a chi si è iscritto (`iscriviController`).
    signal controllerState(var data)

    // ── Segnali ──────────────────────────────────────────────────────────
    /// Un'estensione del demone si è fermata da sola.
    signal pluginTerminato(string nome, int codice)

    /// Il demone non è riuscito a fare quello che gli avevamo chiesto.
    ///
    /// Non lo ascolta nessuno oggi, ed è voluto: senza un identificativo di
    /// richiesta la shell non sa QUALE chiamata è caduta, quindi non può
    /// rimediare da sé. Serve perché il fatto sia scritto da qualche parte —
    /// prima non lo era, e una richiesta caduta era indistinguibile da una
    /// lenta. Chi vorrà mostrarlo all'utente lo trova già qui.
    signal azioneFallita(string azione, string perche)

    signal settingsReceived(var settings)
    signal keybindingsReceived(var keybindings)

    /// Le scorciatoie già tradotte per minerva-wayland, pronte da mandargli.
    /// Sono una cosa diversa dal promemoria di Super+K, ed è per questo che
    /// non viaggiano insieme: quello è per gli occhi di chi usa il computer e
    /// porta categorie e descrizioni; queste sono righe per un compositore.
    signal scorciatoieCompositoreArrivate(var righe)
    signal allAppsReceived(var apps)
    /// L'elenco delle finestre, già oggetto: prima lo si trasformava in
    /// testo qui e lo si rileggeva in `Windows`, fino a sedici volte al
    /// secondo mentre una finestra si muove.
    signal windowsStateReceived(var clients)
    signal monitorsStateReceived(string monitorsJson)

    /// Il monitor di sistema: processi e stato della macchina.
    signal processesReceived(var dati)

    /// Solo CPU, memoria e temperatura, senza l'elenco dei processi: per chi
    /// mostra tre numeri e non deve pagare la lettura di tutto `/proc`.
    signal machineStateReceived(var macchina)

    function machineState() { return send({ "action": "machine_state" }); }
    signal processKilled(int pid, bool ok, bool force)

    // ── API ──────────────────────────────────────────────────────────────

    /// I messaggi mandati prima che la connessione sia aperta. Vengono
    /// spediti tutti insieme appena il demone risponde.
    ///
    /// ── Perché non si buttano ────────────────────────────────────────────
    ///
    /// Si buttavano, con un avviso. E il momento in cui succede non è raro: è
    /// l'AVVIO. La shell parte, chiede lo stato delle finestre e dei monitor,
    /// e il demone non ha ancora accettato la connessione — tre messaggi persi
    /// ogni volta, misurati nel registro il 2 agosto.
    ///
    /// Chi li aveva chiesti non riprova: si è disegnato con i valori di
    /// ripiego, e ci resta finché qualcos'altro non lo sveglia. È la stessa
    /// famiglia di difetti del demone morto che mostrava i valori di fabbrica
    /// fingendo fossero i tuoi.
    ///
    /// Il tetto c'è perché una coda senza fondo, con il demone che non torna
    /// più, diventa una perdita di memoria silenziosa.
    property var _coda: []
    readonly property int _codaMax: 32

    // Le conversazioni della login valgono solo sul canale corrente.
    // greeter_info è una lettura iniziale, non una richiesta di autenticazione.
    function _loginAction(payload) {
        if (!payload || typeof payload.action !== "string")
            return false;
        // Anche le azioni che portano un SEGRETO: la password di un account,
        // la chiave di Google. In coda resterebbero in memoria finché il
        // demone non torna, e partirebbero magari minuti dopo, quando chi le
        // ha scritte ha già chiuso la pagina (revisione di sicurezza, 5
        // ottobre 2026). A demone assente non partono, e chi le manda lo sa.
        if (payload.action === "account_collega"
            || payload.action === "account_google_chiave")
            return true;
        return payload.action.indexOf("greeter_") === 0
            && payload.action !== "greeter_info";
    }

    function send(payload) {
        if (ipc._loginAction(payload) && (!ipc._aperto || !ipc._salutato || !ipc._vivo))
            return false;
        // Non basta che il socket sia aperto: finché non ci si è salutati il
        // demone butta via tutto. Si accoda, e la coda parte col saluto.
        if (!ipc._aperto || !ipc._salutato) {
            // ── UN DOPPIONE NON SI ACCODA ────────────────────────────────
            //
            // Mentre il demone non c'è, le richieste che si ripetono da sole
            // continuano ad arrivare: `get_windows` parte a ogni cambio di
            // finestra, `get_state` a ogni ronda. In trenta secondi di demone
            // assente riempiono da sole le trentadue caselle, e da lì in poi
            // la coda BUTTA VIA le richieste nuove per tenersi le vecchie —
            // cioè esattamente al contrario di quel che serve.
            //
            // Un messaggio identico a uno già in coda non aggiunge niente:
            // chiedere due volte lo stato attuale non dà due stati, dà lo
            // stesso stato due volte. Si tiene quello che c'è e si tace.
            //
            // Osservato il 10 agosto 2026 tenendo la shell viva con il demone
            // spento: dieci righe «Coda piena, messaggio scartato:
            // get_windows» e nient'altro in coda.
            //
            // ── …MA SOLO SE È UNA DOMANDA (30 settembre 2026) ───────────────
            //
            // Per un ORDINE l'ordine conta. Un interruttore acceso, spento e
            // riacceso a demone fermo mandava `true`, `false`, `true`: il
            // secondo `true` era «un doppione» e spariva, il demone ripartiva
            // e applicava `false`, e l'interruttore diceva acceso finché non
            // arrivavano le impostazioni vere. Lo stesso con iscriviti /
            // disiscriviti / iscriviti. Adesso si scartano solo le domande
            // (`_eDomanda`); per `set_setting` sullo stesso percorso vale
            // l'ultimo valore, che prende il posto del vecchio in fondo alla
            // coda — dopo tutto ciò che c'era prima.
            var testo = JSON.stringify(payload);
            var c = ipc._coda.slice();
            for (var i = 0; i < c.length; i++) {
                if (ipc._eDomanda(payload.action)
                        && JSON.stringify(c[i]) === testo)
                    return false;
                if (payload.action === "set_setting"
                        && c[i].action === "set_setting"
                        && c[i].path === payload.path) {
                    c.splice(i, 1);
                    break;
                }
            }

            if (c.length < ipc._codaMax) {
                c.push(payload);
                ipc._coda = c;
            } else {
                console.warn("[MINERVA][IPC] Coda piena, messaggio scartato:", payload.action);
            }
            return false;
        }
        ipc._scrivi(JSON.stringify(payload) + "\n");
        return true;
    }

    /// Le richieste che CHIEDONO e basta: chiederle due volte dà la stessa
    /// risposta due volte, e in coda se ne tiene una. Tutto il resto cambia
    /// qualcosa, e lì l'ordine e il numero contano. Nel dubbio un'azione è
    /// un ordine: un ordine ripetuto costa un giro, uno perso mente.
    function _eDomanda(azione) {
        var a = String(azione || "");
        return /^get_/.test(a) || /_(state|stato|list|zones|info|elenco|panoramica|inventario)$/.test(a)
            || a === "scorciatoie_compositore" || a === "fs_places" || a === "fs_volumes"
            || a === "fs_jobs" || a === "fs_formats" || a === "mime_categories";
    }

    /// Svuota la coda. Da chiamare quando la connessione si apre.
    function _svuotaCoda() {
        if (ipc._coda.length === 0)
            return;
        var c = ipc._coda;
        ipc._coda = [];
        // Le scritture rimaste in coda partono ADESSO: la loro attesa della
        // conferma comincia da qui, non da quando le si era chieste.
        var adesso = Date.now();
        for (var k in ipc._inVolo)
            ipc._inVolo[k].quando = adesso;
        for (var i = 0; i < c.length; i++) {
            if (ipc._loginAction(c[i])) continue;
            ipc._scrivi(JSON.stringify(c[i]) + "\n");
        }
        console.log("[MINERVA][IPC] Spediti", c.length, "messaggi rimasti in coda.");
    }

    /// Legge un'impostazione con percorso a punti, con valore di ripiego.
    function get(path, fallback) {
        var node = ipc.settings;
        var parts = path.split(".");
        for (var i = 0; i < parts.length; i++) {
            if (node === undefined || node === null || typeof node !== "object")
                return fallback;
            node = node[parts[i]];
        }
        return (node === undefined || node === null) ? fallback : node;
    }

    function setSetting(path, value) {
        // Uguale a quello che c'è già: la copia locale non si tocca. Ogni
        // `Core.Ipc.get(...)` di ogni finestra dipende da TUTTO `settings`, e
        // riassegnarlo rifà circa quattrocento associazioni — per niente,
        // quando il valore non cambia (un'icona trascinata che torna dov'era,
        // un interruttore premuto sul suo stesso stato). Al demone si manda
        // lo stesso: è lui che decide.
        if (JSON.stringify(ipc.get(path, undefined)) === JSON.stringify(value))
            return send({ "action": "set_setting", "path": path, "value": value });

        // Aggiorna subito la copia locale: l'interfaccia risponde all'istante
        // invece di aspettare il giro di ritorno dal demone.
        var copy = JSON.parse(JSON.stringify(ipc.settings || {}));
        var parts = path.split(".");
        var node = copy;
        for (var i = 0; i < parts.length - 1; i++) {
            if (typeof node[parts[i]] !== "object" || node[parts[i]] === null)
                node[parts[i]] = {};
            node = node[parts[i]];
        }
        node[parts[parts.length - 1]] = value;
        ipc.settings = copy;
        ipc._segnaInVolo(path, value);

        return send({ "action": "set_setting", "path": path, "value": value });
    }

    // ── Le scritture ancora in volo ──────────────────────────────────────
    //
    // `setSetting` aggiorna subito la copia locale, e poi il demone rimanda
    // TUTTE le impostazioni con `settings_changed`, una volta per scrittura.
    // Si sostituiva la copia in blocco, e fra due scritture ravvicinate
    // succedeva questo: si accende A, si accende B; arriva l'eco di A, che B
    // non lo sa ancora, e l'interruttore B torna indietro sotto il dito per
    // un giro di disco del demone — poi arriva l'eco di B e si rimette.
    // Trovato in revisione il 30 settembre 2026.
    //
    // Adesso ogni scrittura resta segnata qui finché un annuncio non porta
    // proprio quel valore. Fino ad allora vince lei; ma non per sempre: una
    // scrittura rifiutata dal demone non torna mai, e dopo tre secondi si
    // crede al demone — così un valore rifiutato si rivede com'è davvero.
    property var _inVolo: ({})
    readonly property int _attesaConferma: 3000

    function _segnaInVolo(path, value) {
        var v = ipc._inVolo;
        v[path] = { "valore": JSON.stringify(value === undefined ? null : value),
                    "quando": Date.now() };
        ipc._inVolo = v;
    }

    /// Le impostazioni arrivate dal demone, con sopra le scritture nostre
    /// che il demone non ha ancora fatto proprie.
    function _conScrittureInVolo(arrivate) {
        var adesso = Date.now();
        var sopra = {};
        var quante = 0;
        var restano = {};
        for (var path in ipc._inVolo) {
            var w = ipc._inVolo[path];
            var node = arrivate;
            var parts = path.split(".");
            for (var i = 0; i < parts.length && node !== undefined && node !== null; i++)
                node = (typeof node === "object") ? node[parts[i]] : undefined;
            if (JSON.stringify(node === undefined ? null : node) === w.valore)
                continue;                       // confermata: da qui vale il demone
            if (adesso - w.quando > ipc._attesaConferma)
                continue;                       // mai confermata: si crede al demone
            restano[path] = w;
            sopra[path] = JSON.parse(w.valore);
            quante++;
        }
        ipc._inVolo = restano;
        if (quante === 0)
            return arrivate;
        var copy = JSON.parse(JSON.stringify(arrivate || {}));
        for (var p in sopra) {
            var pezzi = p.split(".");
            var n = copy;
            for (var j = 0; j < pezzi.length - 1; j++) {
                if (typeof n[pezzi[j]] !== "object" || n[pezzi[j]] === null)
                    n[pezzi[j]] = {};
                n = n[pezzi[j]];
            }
            n[pezzi[pezzi.length - 1]] = sopra[p];
        }
        return copy;
    }

    /// Scrive PIÙ impostazioni in un colpo solo.
    ///
    /// ── Perché non basta chiamare `setSetting` venti volte ────────────────
    ///
    /// Perché ogni chiamata è un messaggio, una scrittura del file su disco e
    /// un `settings_changed` che rimbalza a tutte le finestre — che da lì
    /// rifanno i colori, rimisurano la barra, ricostruiscono la dock. Uno
    /// stile come «Windows» tocca una ventina di chiavi: venti giri, venti
    /// scritture, venti ricostruzioni del tema, e per un istante la scrivania
    /// è mezza in un modo e mezza nell'altro.
    ///
    /// Il demone sa già farlo in blocco e non gliel'ha mai chiesto nessuno:
    /// `set_settings` (`websocket_server.dart`) chiama `setValues`
    /// (`settings_api.dart`), che applica tutto e fa **una** scrittura e
    /// **un** annuncio.
    ///
    /// La mappa ha le chiavi col punto, come `get` e `setSetting`:
    ///
    ///     Core.Ipc.setSettings({ "bar.position": "basso",
    ///                            "dock.enabled": false });
    function setSettings(mappa) {
        if (!mappa || typeof mappa !== "object")
            return false;

        // Stessa copia ottimista di `setSetting`, fatta una volta per tutte le
        // chiavi: se si aggiornasse la copia una chiave per volta, ogni
        // aggiornamento rifarebbe partire i legami di QML — cioè la cosa che
        // questa funzione esiste per non fare.
        var copy = JSON.parse(JSON.stringify(ipc.settings || {}));
        for (var path in mappa) {
            var parts = path.split(".");
            var node = copy;
            for (var i = 0; i < parts.length - 1; i++) {
                if (typeof node[parts[i]] !== "object" || node[parts[i]] === null)
                    node[parts[i]] = {};
                node = node[parts[i]];
            }
            node[parts[parts.length - 1]] = mappa[path];
            ipc._segnaInVolo(path, mappa[path]);
        }
        ipc.settings = copy;

        return send({ "action": "set_settings", "values": mappa });
    }

    function resetSettings() {
        // Il ripristino vince su tutto quel che era in volo prima di lui.
        ipc._inVolo = ({});
        return send({ "action": "reset_settings" });
    }

    function requestKeybindings() {
        return send({ "action": "get_keybindings" });
    }
    function scorciatoieCompositore() {
        return send({ "action": "scorciatoie_compositore" });
    }

    function requestAllApps() {
        return send({ "action": "get_all_apps" });
    }

    /// Come sopra, ma rileggendo prima i file `.desktop` dal disco. Costa una
    /// scansione di quattro cartelle e si fa a ogni avvio della shell: senza,
    /// un programma installato dopo l'avvio del demone non compare nel menu
    /// finché non si esce dalla sessione.
    function rescanApps() {
        return send({ "action": "rescan_apps" });
    }

    // ── Il monitor di sistema ────────────────────────────────────────────
    //
    // Iscriversi e disiscriversi non è cerimonia: il demone legge `/proc` solo
    // mentre qualcuno guarda. Senza la disiscrizione resterebbe a misurare per
    // il resto della sessione dopo la prima apertura — cioè il monitor
    // diventerebbe uno dei consumi che serve a trovare.
    function subscribeProcesses() {
        return send({ "action": "subscribe_processes" });
    }

    function unsubscribeProcesses() {
        return send({ "action": "unsubscribe_processes" });
    }

    // ── L'iscrizione LEGGERA, per i widget della scrivania ───────────────
    //
    // Stessa forma di quella dei processi e un ventesimo del costo: il demone
    // legge quattro file invece di `/proc` per ogni processo, e ogni cinque
    // secondi invece di due. I widget stanno accesi tutto il giorno, e da
    // quella pesante costerebbero il fermo di 22 ms misurato il 7 settembre
    // 2026 — che è tutta la scrivania che si ferma, perché Dart ha un filo
    // solo.
    function iscriviMacchina() {
        return send({ "action": "subscribe_machine" });
    }

    function disiscriviMacchina() {
        return send({ "action": "unsubscribe_machine" });
    }

    // ── L'audio di sistema, solo mentre la pagina Audio è aperta ────────
    //
    // Stesso patto: `pactl subscribe` gira nel demone dalla prima iscrizione,
    // e i cambiamenti (cuffie, HDMI, profili) arrivano come `system_audio_state`
    // solo a chi si è iscritto. Prima la pagina chiedeva lo stato ogni 4 s con
    // un timer; Codex ha tolto il timer ma non ha messo l'iscrizione, e da
    // quel giorno inserire le cuffie non aggiornava più la pagina finché non
    // la si riapriva (22 settembre 2026).
    function iscriviAudio() {
        return send({ "action": "subscribe_audio" });
    }

    function disiscriviAudio() {
        return send({ "action": "unsubscribe_audio" });
    }

    // ── I pad di gioco ───────────────────────────────────────────────────
    //
    // Il servizio gira sempre nel demone — accorgersi da solo di un pad che
    // si accende è il suo lavoro. Iscriversi vuol dire solo sentirne i
    // cambi: lo fa la pagina Controller, e la shell per l'avviso.
    function iscriviController() {
        return send({ "action": "subscribe_controller" });
    }

    function disiscriviController() {
        return send({ "action": "unsubscribe_controller" });
    }


    /// `forza` distingue il chiedere (SIGTERM) dall'imporre (SIGKILL).
    function killProcess(pid, forza) {
        return send({ "action": "kill_process", "pid": pid, "force": forza === true });
    }

    function launchApp(execCmd, appId) {
        return send({ "action": "launch_app", "exec": execCmd, "id": appId || "" });
    }

    /// Lancia un file .desktop da un percorso qualsiasi: i launcher messi a
    /// mano sulla scrivania. Il demone lo legge e ne esegue il comando.
    function launchDesktop(path) {
        ipc._cancelLauncher();
        ipc._launcherSerial++;
        ipc._launcherCurrent = String(ipc._launcherSerial);
        if (!ipc._showLauncher({ "path": path, "request": ipc._launcherCurrent })) {
            ipc._launcherCurrent = "";
            return false;
        }
        if (!ipc._launcherSendNow({ "action": "prepare_desktop", "path": path,
                                   "request": ipc._launcherCurrent })) {
            ipc._showLauncher({ "path": path, "error": "Il demone non è connesso: riprova dopo la riconnessione." });
            ipc._launcherCurrent = "";
            return false;
        }
        ipc._launcherWait.restart();
        return true;
    }

    property int _launcherSerial: 0
    property string _launcherCurrent: ""
    property var _launcherWindow: null
    property var _launcherWait: Timer {
        interval: 10000
        onTriggered: {
            ipc._launcherCurrent = "";
            ipc._showLauncher({ "error": "Il demone non ha risposto: riapri il launcher." });
        }
    }

    // Consent must never go through the offline queue, including cancel/approve.
    function _launcherSendNow(payload) {
        if (!ipc.connected || !ipc._vivo) return false;
        try {
            ipc._scrivi(JSON.stringify(payload) + "\n");
            return true;
        } catch (error) {
            return false;
        }
    }

    function _showLauncher(data) {
        if (!ipc._launcherWindow) {
            var component = Qt.createComponent(Qt.resolvedUrl("../ui/LauncherConsent.qml"));
            if (component.status !== Component.Ready) {
                console.warn("[MINERVA][IPC] Dialogo launcher non disponibile:", component.errorString());
                return false;
            }
            ipc._launcherWindow = component.createObject(ipc);
            if (!ipc._launcherWindow) return false;
            ipc._launcherWindow.accepted.connect(function(token, path, request) {
                if (request !== ipc._launcherCurrent) return;
                if (!ipc._launcherSendNow({ "action": "launch_desktop", "path": path,
                                          "token": token, "request": request })) {
                    ipc._launcherCurrent = "";
                    ipc._showLauncher({ "path": path, "error": "Connessione persa: nessun avvio accodato." });
                } else {
                    ipc._launcherWait.stop();
                }
            });
            ipc._launcherWindow.dismissed.connect(function(token, path, request) {
                if (token !== "")
                    ipc._launcherSendNow({ "action": "cancel_desktop", "path": path,
                                          "token": token, "request": request });
                if (request === ipc._launcherCurrent) {
                    ipc._launcherCurrent = "";
                    ipc._launcherWait.stop();
                }
            });
        }
        ipc._launcherWindow.italiano = Strings.lang === "it";
        ipc._launcherWindow.apri(data);
        return true;
    }

    function _cancelLauncher() {
        if (ipc._launcherWindow && ipc._launcherWindow.visible)
            ipc._launcherWindow.chiudi();
        ipc._launcherCurrent = "";
        ipc._launcherWait.stop();
    }

    function _launcherPrepared(data) {
        if (!data) return;
        if (ipc._launcherCurrent === "" || !ipc.connected || data.request !== ipc._launcherCurrent) {
            if (data.token)
                ipc._launcherSendNow({ "action": "cancel_desktop", "path": data.path,
                                      "token": data.token, "request": data.request });
            return;
        }
        ipc._launcherWait.stop();
        if (!ipc._showLauncher(data)) {
            if (data.token)
                ipc._launcherSendNow({ "action": "cancel_desktop", "path": data.path,
                                      "token": data.token, "request": data.request });
            ipc._launcherCurrent = "";
        }
    }

    function _launcherResult(data) {
        if (!data || ipc._launcherCurrent === "" || data.request !== ipc._launcherCurrent) return;
        ipc._launcherWait.stop();
        ipc._launcherCurrent = "";
        if (data.error) ipc._showLauncher(data);
    }

    onConnectedChanged: if (!connected) ipc._cancelLauncher()


    function requestWindows() {
        return send({ "action": "get_windows" });
    }

    function requestMonitors() {
        return send({ "action": "get_monitors" });
    }


    /// I temi di icone installati, per il menu delle Impostazioni.
    function requestIconThemes() {
        return send({ "action": "get_icon_themes" });
    }



    // ── Gestore file ─────────────────────────────────────────────────────
    //
    // Le operazioni sui file stanno nel demone e non qui. Non è pignoleria:
    // una copia deve poter essere messa in pausa e ripresa, e un processo
    // esterno (`cp`) non si mette in pausa — si può solo uccidere, lasciando
    // un file troncato con il nome giusto. Il demone copia blocco per blocco
    // e fra un blocco e l'altro può fermarsi.
    //
    // `pane` viaggia con la richiesta e torna con la risposta: due riquadri
    // che chiedono due cartelle diverse devono poter distinguere la propria
    // risposta da quella dell'altro.

    signal fileListingReceived(var listing)
    signal fileJobChanged(var job)
    signal fileJobsReceived(var jobs)
    signal fileResultReceived(var result)
    /// Il testo di un documento, risposta a `fsRead`.
    signal fileTextReceived(var payload)
    /// I caratteri installati, risposta a `fontsList`.
    signal fontsReceived(var payload)

    /// Un pezzo di ricerca: o un mazzetto di risultati, o la fine.
    signal ricercaAvanza(var pezzo)

    // ── La galleria di Anteprima ─────────────────────────────────────────
    //
    // Il catalogo delle foto e dei video sta nella cache
    // (`~/.cache/liquid-de/foto/indice.json`); le cartelle scelte e le
    // esclusioni stanno nella configurazione, così si possono buttare le
    // miniature senza perdere le scelte.

    /// Le cartelle scelte, e le esclusioni. Costa zero: si legge un file.
    signal fotoCartelle(var payload)
    /// Dove SEMBRA che ci siano foto, col conteggio. Costa: cammina la casa.
    signal fotoProposte(var payload)
    /// I giorni con quante foto ciascuno, dalla più recente. È l'ossatura
    /// della galleria: da qui si sa quante righe disegnare senza leggere
    /// nemmeno un file.
    signal fotoPanoramica(var payload)
    /// Le voci di UN giorno. Si chiede quando quella riga sta per vedersi.
    signal fotoGiorno(var payload)
    /// Il percorso di una miniatura pronta, più `percorsoFoto` di partenza.
    signal fotoMiniatura(var payload)
    /// La stella messa o tolta.
    signal fotoPreferito(var payload)
    /// Un pezzo di scansione: a mazzetti mentre cammina, e l'ultimo lo dice.
    signal fotoScansione(var payload)
    /// I gruppi di copie esatte: `{ gruppi: [{ percorsi, byteInPiu }], byteInPiu }`.
    signal fotoDoppioni(var payload)
    /// L'esito di uno scarto: `{ ok, error, tenuta }`.
    signal fotoDoppioniScartati(var payload)

    function fotoLeggiCartelle() { return send({ "action": "foto_cartelle" }); }
    function fotoCerca() { return send({ "action": "foto_proposte" }); }
    function fotoAggiungiCartella(percorso) {
        return send({ "action": "foto_cartella_aggiungi", "percorso": percorso });
    }
    function fotoTogliCartella(percorso) {
        return send({ "action": "foto_cartella_togli", "percorso": percorso });
    }
    function fotoEscludi(percorso, escludi) {
        // `si`, come lo legge il demone: era `escludi`, e non si escludeva
        // mai niente.
        return send({ "action": "foto_escludi", "percorso": percorso,
                      "si": escludi === true });
    }
    function fotoMostraSchermate(si) {
        // `si`, come lo legge il demone: era `mostra`, e il demone leggeva
        // sempre «no».
        return send({ "action": "foto_schermate", "si": si === true });
    }
    function fotoScansiona() { return send({ "action": "foto_scansiona" }); }
    function fotoCercaDoppioni() { return send({ "action": "foto_doppioni" }); }
    /// Manda nel cestino le copie `butta` di un gruppo, tenendo `tieni`. Il
    /// demone rifiuta tutto se `tieni` manca o sta fra quelle da buttare.
    function fotoScartaDoppioni(tieni, butta) {
        return send({ "action": "foto_doppioni_scarta", "tieni": tieni, "butta": butta });
    }
    function fotoFermaScansione() { return send({ "action": "foto_scansiona_ferma" }); }
    function fotoChiediPanoramica() { return send({ "action": "foto_panoramica" }); }
    function fotoChiediGiorno(giorno) {
        return send({ "action": "foto_giorno", "giorno": giorno });
    }
    /// `lato` è il lato in pixel della miniatura voluta.
    ///
    /// Si chiede a scatti — 128, 192, 256 — e non alla misura esatta: legare
    /// la richiesta al numero preciso vorrebbe dire rifarle tutte a ogni
    /// scatto di rotellina. È la stessa lezione di `viewer/Griglia.qml`.
    function fotoChiediMiniatura(percorso, lato) {
        return send({ "action": "foto_miniatura", "percorso": percorso,
                      "lato": lato });
    }

    /// La copia già sfocata di uno sfondo, per il vetro dietro la barra e la
    /// dock. Vedi `core/Vetro.qml`: il conto lo fa il demone una volta sola.
    function chiediSfondoSfocato(percorso) {
        return send({ "action": "sfondo_sfocato", "percorso": percorso });
    }

    /// La porta del «trasmetti a schermo»: aperta o chiusa.
    ///
    /// Chiede la password una volta sola, e apre **una** porta verso la sola
    /// rete di casa. Serve perché un televisore non riceve la fotografia: se
    /// la va a prendere, e un firewall acceso lo respinge — e il sintomo è
    /// uno schermo nero senza nessun errore.
    signal trasmettiPermesso(var esito)

    function trasmettiApri() {
        return send({ "action": "trasmetti_permesso", "apri": true });
    }
    function trasmettiChiudi() {
        return send({ "action": "trasmetti_permesso", "apri": false });
    }

    // ── Mandare un file a un televisore ──────────────────────────────────
    //
    // Il permesso qui sopra apre la porta; queste tre mandano davvero.
    //
    // Si **comincia da un file**, mai dalla levetta: un televisore non
    // riceve «lo schermo», riceve un indirizzo da cui andarsi a prendere una
    // cosa. Quindi la trasmissione nasce dal menù del tasto destro su una
    // fotografia, e la levetta del pannello serve a vedere che sta andando e
    // a fermarla.

    /// I televisori accesi adesso, col loro nome vero.
    signal trasmettiSchermi(var elenco)
    /// Com'è andata: `{ok, verso}` oppure `{ok: false, error}`.
    signal trasmettiEsito(var esito)
    /// Che cosa sta trasmettendo adesso, se sta trasmettendo.
    signal trasmettiStato(var stato)

    function trasmettiCerca() {
        return send({ "action": "trasmetti_schermi" });
    }

    /// `schermo` è l'ID stabile del televisore, non il suo indirizzo: un IP
    /// cambia a ogni riaccensione del router, e domani manderebbe altrove.
    ///
    /// `tipo` **si lascia vuoto**: lo trova il demone, che ha il file e per
    /// immagini, suoni e video ci guarda dentro invece di fidarsi del nome.
    /// Fino al 4 settembre 2026 il ripiego qui era `"image/jpeg"`, e un film
    /// partiva annunciato come una fotografia — il televisore mostrava nero e
    /// non lo diceva. Resta il parametro perché serve alle prove.
    function trasmettiManda(file, schermo, tipo) {
        var m = { "action": "trasmetti_manda", "file": file,
                  "schermo": schermo };
        if (tipo)
            m.tipo = tipo;
        return send(m);
    }

    /// Manda al televisore **lo schermo**, dal vivo.
    ///
    /// Ci sono circa tre secondi di ritardo, ed è come è fatto HLS — il
    /// protocollo con cui il televisore si viene a prendere i pezzetti. Per
    /// guardare va benissimo; per *usare* il computer sullo schermo grande no,
    /// e va detto invece che lasciato scoprire.
    function trasmettiSchermo(schermo, quale) {
        return send({ "action": "trasmetti_schermo", "schermo": schermo,
                      "quale": quale || "" });
    }

    function trasmettiFerma() {
        return send({ "action": "trasmetti_ferma" });
    }

    function trasmettiChiediStato() {
        return send({ "action": "trasmetti_stato" });
    }

    function fotoSegnaPreferito(percorso, si) {
        return send({ "action": "foto_preferito", "percorso": percorso,
                      "si": si === true });
    }

    // ── Cercare dentro le cartelle ───────────────────────────────────────
    //
    // Il filtro del gestore file guarda la cartella aperta e risponde subito;
    // questa scende nelle sottocartelle e risponde a pezzi, perché su una
    // cartella di casa con centomila file rispondere solo alla fine vuol dire
    // una finestra ferma per venti secondi.
    //
    // `id` distingue chi cerca: due riquadri possono cercare cose diverse
    // nello stesso momento, e i risultati non si devono mescolare.
    function fsSearch(id, path, query, hidden) {
        return send({
            "action": "fs_search",
            "id": id,
            "path": path,
            "query": query,
            "hidden": hidden === true
        });
    }

    function fsSearchCancel(id) {
        return send({ "action": "fs_search_cancel", "id": id });
    }

    function fsList(path, showHidden, pane) {
        return send({
            "action": "fs_list",
            "path": path,
            "showHidden": showHidden === true,
            "pane": pane || ""
        });
    }

    /// I nomi che in `destination` esistono già. La risposta arriva su
    /// `conflittiRicevuti`.
    function fsConflitti(sources, destination) {
        return send({
            "action": "fs_conflitti",
            "sources": sources,
            "destination": destination
        });
    }

    /// `conflitto`: "entrambi" (si tengono tutti e due), "sostituisci",
    /// "salta". Assente vale "entrambi", che è l'unico che non perde niente.
    function fsTransfer(sources, destination, move, conflitto) {
        return send({
            "action": "fs_transfer",
            "sources": sources,
            "destination": destination,
            "move": move === true,
            "conflitto": conflitto || "entrambi"
        });
    }

    function fsPause(id)  { return send({ "action": "fs_pause",  "id": id }); }
    function fsResume(id) { return send({ "action": "fs_resume", "id": id }); }
    function fsCancel(id) { return send({ "action": "fs_cancel", "id": id }); }
    function fsJobs()     { return send({ "action": "fs_jobs" }); }

    function fsMakeDirectory(path) {
        return send({ "action": "fs_mkdir", "path": path });
    }

    function fsRename(from, to) {
        return send({ "action": "fs_rename", "from": from, "to": to });
    }

    function fsTrash(paths) {
        return send({ "action": "fs_trash", "paths": paths });
    }

    /// Lo sfondo di una cartella. `aspetto` è `{tipo, valore}` oppure `null`
    /// per toglierlo.
    function fsAspetto(path, aspetto) {
        return send({ "action": "fs_aspetto", "path": path,
                      "aspetto": aspetto || null });
    }

    /// Un file vuoto col nome dato.
    function fsTouch(path) {
        return send({ "action": "fs_touch", "path": path });
    }

    /// Cancella per davvero. Non c'è ritorno: la conferma la chiede chi
    /// chiama, e non è saltabile.
    function fsDelete(paths) {
        return send({ "action": "fs_delete", "paths": paths });
    }

    // ── Formattare un disco ──────────────────────────────────────────────

    signal formatsReceived(var formati)
    signal conflittiRicevuti(var nomi)

    function fsFormats() { return send({ "action": "fs_formats" }); }

    function fsFormat(device, fs, label) {
        return send({ "action": "fs_format", "device": device,
                      "fs": fs, "label": label || "" });
    }

    // ── Programmi all'avvio ──────────────────────────────────────────────
    //
    // Ogni comando che cambia qualcosa fa arrivare, subito dopo, l'elenco
    // aggiornato: la pagina non tiene una propria copia da correggere a mano.

    signal autostartReceived(var voci)

    function autostartList() { return send({ "action": "autostart_list" }); }

    function autostartSet(file, enabled) {
        return send({ "action": "autostart_set", "file": file,
                      "enabled": enabled });
    }

    function autostartAdd(name, command) {
        return send({ "action": "autostart_add", "name": name,
                      "command": command });
    }

    function autostartRemove(file) {
        return send({ "action": "autostart_remove", "file": file });
    }

    // ── Data e ora ───────────────────────────────────────────────────────
    //
    // `datetimeSet` non torna mai «fatto» da solo: ogni cambiamento passa da
    // polkit, e fra il clic e l'effetto c'è una finestrella con la password
    // che l'utente può annullare. Chi ascolta deve guardare il RISULTATO
    // (`datetimeResult`) e poi lo STATO che arriva subito dopo, non il fatto
    // di aver mandato il comando.

    signal datetimeStateReceived(var stato)
    signal datetimeZonesReceived(var fusi)
    signal datetimeResult(var esito)

    /// La copia sfocata dello sfondo è pronta: `{ok, percorso, sfondo}`.
    signal sfondoSfocato(var esito)

    function datetimeState() { return send({ "action": "datetime_state" }); }
    function datetimeZones() { return send({ "action": "datetime_zones" }); }

    function datetimeSet(field, value) {
        return send({ "action": "datetime_set", "field": field, "value": value });
    }

    // ── Lingua del sistema ───────────────────────────────────────────────
    //
    // Quella di Minerva è un'impostazione come le altre e si cambia con
    // `setSetting("general.language", …)`: ha effetto nell'istante in cui si
    // scrive. Questa invece è di systemd e si vede al prossimo accesso.

    // ── Il tempo che fa ──────────────────────────────────────────────────
    //
    // `weatherState` senza coordinate non chiede niente a nessuno: è il
    // demone a garantirlo, e questa firma lo rende difficile da sbagliare.

    signal weatherPlaces(var luoghi)
    signal weatherReceived(var meteo)

    function weatherSearch(query) {
        return send({ "action": "weather_search", "query": query });
    }

    function weatherState(lat, lon, force) {
        return send({ "action": "weather_state", "lat": lat, "lon": lon,
                      "force": force === true });
    }

    signal localeStateReceived(var stato)
    signal localeResult(var esito)

    function localeState() { return send({ "action": "locale_state" }); }

    function localeSet(value) {
        return send({ "action": "locale_set", "value": value });
    }

    function fsTrashRestore(paths) {
        return send({ "action": "fs_trash_restore", "paths": paths });
    }

    function fsTrashEmpty() {
        return send({ "action": "fs_trash_empty" });
    }

    /// Comprime. Rispondono tutti e due con `fileResultReceived`, con dentro
    /// `percorso` (l'archivio creato) o `cartella` e `nuovo` (dove è finita
    /// la roba estratta).
    function fsCompress(paths, format, name) {
        return send({ "action": "fs_compress", "paths": paths,
                      "format": format || "zip", "name": name || "" });
    }

    function fsExtract(path) {
        return send({ "action": "fs_extract", "path": path });
    }

    // ── Installare un set di icone ───────────────────────────────────────
    //
    // Il demone sapeva farlo dal 19 agosto (`services/tema_icone_service.dart`,
    // con il controllo che rifiuta gli archivi contenenti eseguibili) e per
    // quattro giorni **non l'ha mai chiesto nessuno**: due azioni complete,
    // provate, e senza un pulsante da nessuna parte.
    //
    // Si chiede dal gestore file, col tasto destro su un archivio, e non da
    // un selettore dentro le Impostazioni: un set di icone lo si scarica, e
    // il posto in cui ci si trova subito dopo è la cartella dei download.
    // Chiedere di riaprirlo da un'altra finestra è un passaggio in più per
    // arrivare dove si era già.
    //
    // Risponde con `iconeEsito`: `{ok, nome, error}`.
    function iconeInstalla(path) {
        return send({ "action": "icone_installa", "path": path });
    }

    /// Toglie un tema dalla cartella dell'utente. `path` è il percorso
    /// completo che arriva in `iconeInstallate`: il demone controlla che stia
    /// dentro `~/.local/share/icons`, e fuori da lì non cancella niente.
    function iconeDisinstalla(path) {
        return send({ "action": "icone_disinstalla", "path": path });
    }

    signal iconeEsito(var esito)

    // ── Condividere ──────────────────────────────────────────────────────

    /// Chiede l'elenco delle destinazioni. Arrivano TUTTE, anche quelle che
    /// adesso non funzionano, ognuna con `disponibile` e `motivo`: il pannello
    /// le mostra spente e scrive perché, invece di far sparire la voce.
    function condivisioneDove() {
        return send({ "action": "condivisione_dove" });
    }

    /// Manda. `bersaglio` è l'indirizzo del dispositivo per il Bluetooth, e
    /// non serve per la posta. Risponde con `condivisioneEsito`, che può
    /// arrivare anche dopo mezzo minuto: il Bluetooth aspetta che l'altro
    /// apparecchio risponda.
    function condivisioneInvia(dove, paths, bersaglio) {
        return send({ "action": "condivisione_invia", "dove": dove,
                      "paths": paths, "bersaglio": bersaglio || "" });
    }

    signal condivisioneDoveRicevute(var dati)
    signal condivisioneEsito(var esito)

    // ── Accoppiare un dispositivo Bluetooth ──────────────────────────────

    /// Comincia. Non risponde «è andata bene»: risponde «ho cominciato». Come
    /// va a finire arriva da `btAccoppiamento`, perché in mezzo c'è una
    /// persona che deve guardare un telefono e confrontare sei cifre.
    function btPair(mac) {
        return send({ "action": "bt_pair", "mac": mac });
    }

    /// «Sì, il codice è quello» — o no.
    function btPairAnswer(si) {
        return send({ "action": "bt_pair_answer", "si": si === true });
    }

    function btPairCancel() {
        return send({ "action": "bt_pair_cancel" });
    }

    /// `stato`: "avviato", "chiede", "fatto", "fallito".
    /// Con "chiede" arriva anche `codice`.
    signal btAccoppiamento(var dati)

    // ── Proprietà, dischi, e chi apre che cosa ───────────────────────────

    signal fileInfoReceived(var info)
    signal fileMeasureReceived(var measure)
    signal volumesReceived(var volumes)
    signal placesReceived(var places)
    signal mimeDescribed(var described)
    /// I gruppi, e le FAMIGLIE in cui la pagina li raccoglie. La divisione
    /// la decide il demone insieme ai gruppi (vedi `MimeService.famiglie`):
    /// chi aggiunge un gruppo dice anche dove va, e non c'è modo di
    /// aggiungerne uno che finisce fuori da tutte le tendine.
    signal mimeCategoriesReceived(var categories, var famiglie)

    /// Dettagli di un percorso: tipo, dimensione, permessi, proprietario, e
    /// chi lo aprirebbe. Arriva su `fileInfoReceived`.
    function fsInfo(path) {
        return send({ "action": "fs_info", "path": path });
    }

    /// Il testo di un documento. Arriva su `fileTextReceived`. Serve
    /// all'editor: come ogni altra cosa che tocca il disco, la lettura
    /// passa dal demone.
    function fsRead(path) {
        return send({ "action": "fs_read", "path": path });
    }

    /// I caratteri installati, per il menù dell'editor. Arrivano su
    /// `fontsReceived`.
    function fontsList() {
        return send({ "action": "font_list" });
    }

    /// Salva il testo di un documento. Il demone scrive prima su un file
    /// temporaneo e poi lo sposta sopra il vero: una scrittura interrotta
    /// non lascia il documento a metà. La risposta arriva su
    /// `fileResultReceived`.
    function fsWrite(path, text) {
        return send({ "action": "fs_write", "path": path, "text": text });
    }

    /// Quanto occupa davvero una cartella. Domanda lenta, risposta a parte.
    function fsMeasure(path) {
        return send({ "action": "fs_measure", "path": path });
    }

    function fsChmod(path, mode, recursive) {
        return send({ "action": "fs_chmod", "path": path, "mode": mode,
                      "recursive": recursive === true });
    }

    function fsPlaces()         { return send({ "action": "fs_places" }); }
    function fsVolumes()        { return send({ "action": "fs_volumes" }); }
    function fsMount(device)    { return send({ "action": "fs_mount",   "device": device }); }
    function fsUnmount(device)  { return send({ "action": "fs_unmount", "device": device }); }

    // ── La schermata di accesso ──────────────────────────────────────────
    //
    // Il dialogo vero con `greetd` sta nel demone, e non per gusto: il suo
    // protocollo inquadra ogni messaggio con quattro byte di lunghezza in
    // ordine nativo, e l'unico analizzatore di socket che Quickshell offre
    // taglia su un delimitatore. Di qui passano solo le domande e le risposte.

    /// Chi può entrare e in cosa: `{ sessioni, utenti, greetd }`.
    /// `greetd` è falso quando non siamo dentro un greeter — e allora la
    /// schermata si disegna lo stesso, che è come la si prova senza rischiare
    /// di restare chiusi fuori.
    signal greeterInfoReceived(var info)

    /// Un messaggio di greetd, così com'è: `success`, `error`, o
    /// `auth_message`. Non è tradotto né semplificato qui, perché quanti giri
    /// di domande servano lo decide PAM e non noi.
    signal greeterMessage(var message)

    function greeterInfo() { return send({ "action": "greeter_info" }); }

    /// L'elenco dei gestori di accessi installati, e quale è acceso.
    ///
    /// Solo guardare: accenderne uno richiede root e lo fa
    /// `minerva-greetd gestore` dietro `pkexec`. Il demone gira come te e non
    /// deve poter cambiare chi ti apre la porta all'accensione — se potesse,
    /// basterebbe parlare col demone per prendersi la schermata di accesso.
    signal gestoriAccessoReceived(var info)
    function gestoriAccesso() { return send({ "action": "gestori_accesso" }); }

    // ── La modalità amministratore ───────────────────────────────────────
    //
    // Ogni chiamata qui sotto fa comparire (o no, se polkit se la ricorda
    // ancora) la finestra della password di amministratore. Non c'è nessuna
    // scorciatoia e non deve essercene: il demone gira come te e non ha
    // nessun privilegio da prestare. Vedi `scripts/minerva-radice`.

    signal radiceStato(var info)
    /// L'esito della sola richiesta di permesso — quella che non fa niente e
    /// serve a far comparire la finestrella della password all'INGRESSO della
    /// modalità amministratore, invece che alla prima operazione.
    signal radicePermesso(var info)
    signal radiceElenco(var info)
    signal radiceTesto(var info)
    signal radiceEsito(var info)

    function radiceDisponibile() { return send({ "action": "radice_stato" }); }
    function radiceChiediPermesso() {
        return send({ "action": "radice_permesso" });
    }
    function radiceElenca(path) {
        return send({ "action": "radice_elenca", "path": path });
    }
    function radiceLeggi(path) {
        return send({ "action": "radice_leggi", "path": path });
    }
    function radiceScrivi(path, text) {
        return send({ "action": "radice_scrivi", "path": path, "text": text });
    }
    /// `op` è una di quelle in `RadiceService.operazioni`; il demone rifiuta
    /// tutto il resto, e l'aiutante lo rifiuta una seconda volta.
    // ── La Custodia ──────────────────────────────────────────────────────
    //
    // La storia e la sicurezza delle cartelle. Tutta la logica sta nel demone —
    // qui non c'è nessuna decisione, solo il postino.
    //
    // Il demone garantisce alla shell una cosa sola, ed è quella che permette a
    // questi pulsanti di esistere: **niente che possa perdere lavoro parte
    // senza un punto di ritorno preso prima.** La shell non deve controllarlo
    // né ricordarsene: può offrire «torna a ieri» come un pulsante qualsiasi.
    //
    // Ogni risposta ha la stessa forma, `{ok, errore}`. Quando `ok` è falso c'è
    // sempre una frase italiana già scritta: si mostra così com'è, non si
    // reinterpreta.

    // ── Manutenzione ────────────────────────────────────────────────────
    //
    // L'inventario è **tutta lettura**: dice cosa c'è e quanto pesa, e non
    // tocca niente. Chi lo chiede aspetta fino a un secondo — il conto vero
    // di `~/.cache` e di `/var/cache/pacman/pkg` sono migliaia di file — e
    // per questo la finestra non lo richiede da sola a ripetizione.
    signal manutenzioneInventario(var info)

    /// Le tappe della scansione, mentre succedono: `{fase, testo, fatte,
    /// quante}`. Fanno la barra e le righe del registro. Arrivano solo a chi
    /// ha chiesto l'inventario, non a tutti i collegati.
    signal manutenzionePasso(var info)

    /// Com'è andata una pulizia: `{ok, liberati, quante, nonRiuscite, fatte}`,
    /// e `fatte` dice voce per voce. Un «fatto» solo in fondo non basterebbe:
    /// se tre cartelle su ventidue non si sono potute togliere, chi guarda
    /// deve sapere quali, o il numero che resta sembra un errore del conto.
    signal manutenzionePulito(var info)

    /// Com'è andata coi pacchetti rimasti soli: `{ok, quanti, nomi, errore}`.
    signal manutenzioneOrfaniTolti(var info)

    /// I file che ci sono due volte: `{gruppi, sprecato, guardati}`. Ogni
    /// gruppo ha i `percorsi` — il primo è quello proposto da tenere — più
    /// `tieni`, `perche` e `byteInPiu`.
    signal manutenzioneDoppioni(var info)

    /// Com'è andata a metterli nel cestino: `{cestinati, rifiutati, liberati}`.
    signal manutenzioneDoppioniTolti(var info)

    /// Le cartelle che la Manutenzione non guarda: `{percorsi: [...]}`.
    signal manutenzioneEscluse(var info)

    // ── Fucina ──────────────────────────────────────────────────────────
    //
    // Kernel su misura. Il rilievo guarda e basta; la ricetta è un calcolo
    // senza effetti (si chiede a ogni spunta, per mostrare il piano mentre si
    // sceglie); la compilazione racconta a chi ascolta, e chi riapre la
    // finestra a metà chiede lo stato e riprende il racconto da lì.

    /// Le tappe del rilievo: `{fase, testo, fatte, quante}`, come Manutenzione.
    signal fucinaGuardo(var info)
    /// Che cosa c'è nel computer: dispositivi, moduli con le loro fonti,
    /// famiglie, scorte, preset, macchina, avvisi. Vedi `fucina/rilievo.dart`.
    signal fucinaRilievo(var info)
    /// Le versioni del kernel da kernel.org, e se CachyOS ha le patch.
    signal fucinaVersioni(var info)
    /// Il piano per le scelte fatte: moduli, valori, passi, avvisi.
    signal fucinaRicetta(var info)
    /// La risposta a «compila»: `{ok, errore, rilascio}`. Il seguito arriva
    /// coi quattro segnali sotto.
    signal fucinaAvviata(var info)
    signal fucinaPasso(var info)
    signal fucinaRighe(var info)
    signal fucinaAvanzamento(var info)
    signal fucinaFatto(var info)
    signal fucinaFermata(var info)
    /// Lo stato dell'officina per chi arriva a metà: `{inCorso, rilascio,
    /// passo, secondi, righe, esito}`.
    signal fucinaStato(var info)
    signal fucinaKernel(var info)
    signal fucinaInstallato(var info)
    signal fucinaTolto(var info)
    signal fucinaVerifica(var info)
    /// La fine della registrazione del profilo AutoFDO: `{ok, errore,
    /// rilascio, minuti, sommato, byte}`. Arriva dopo minuti.
    signal fucinaProfilato(var info)

    signal custodiaPanoramica(var info)
    signal custodiaDettaglio(var info)
    signal custodiaEsito(var info)
    signal custodiaGithub(var info)

    // ── Account online ──────────────────────────────────────────────────
    signal accountElenco(var info)
    signal accountEsito(var info)
    signal accountDettaglio(var info)
    signal accountApriGoogle(var info)

    function manutenzioneVedi() {
        return send({ "action": "manutenzione_inventario" });
    }

    // Le funzioni della Fucina hanno nomi diversi dai segnali, per la stessa
    // ragione scritta sopra `manutenzioneVediEscluse`: un segnale e una
    // funzione con lo stesso nome portano giù tutta la shell.
    function fucinaRileva() {
        return send({ "action": "fucina_rileva" });
    }
    function fucinaChiediVersioni() {
        return send({ "action": "fucina_versioni" });
    }
    /// Si mandano SCELTE, mai comandi: la ricetta la calcola il demone.
    function fucinaCalcola(scelte) {
        return send({ "action": "fucina_ricetta", "scelte": scelte });
    }
    function fucinaAvvia(scelte) {
        return send({ "action": "fucina_avvia", "scelte": scelte });
    }
    function fucinaFerma() {
        return send({ "action": "fucina_ferma" });
    }
    function fucinaChiediStato() {
        return send({ "action": "fucina_stato" });
    }
    function fucinaChiediKernel() {
        return send({ "action": "fucina_kernel" });
    }
    /// Un NOME di kernel, mai un percorso: la cartella la ricava il demone e
    /// l'aiutante di root la ricontrolla.
    function fucinaInstalla(rilascio) {
        return send({ "action": "fucina_installa", "rilascio": rilascio });
    }
    function fucinaTogli(rilascio) {
        return send({ "action": "fucina_togli", "rilascio": rilascio });
    }
    function fucinaVerificaOra() {
        return send({ "action": "fucina_verifica" });
    }
    /// Il profilo si registra sul kernel in uso: si manda il suo NOME, che il
    /// demone e l'aiutante ricontrollano, e quanti minuti.
    function fucinaRegistraProfilo(rilascio, minuti) {
        return send({ "action": "fucina_profila", "rilascio": rilascio, "minuti": minuti });
    }

    /// Toglie le voci spuntate. Si mandano **identificativi**, mai percorsi: i
    /// percorsi li ricava il demone rifacendo l'inventario un istante prima di
    /// cancellare, ed è la ragione per cui da qui non si può chiedere di
    /// cancellare una cosa qualunque.
    function manutenzionePulisci(ids) {
        return send({ "action": "manutenzione_pulisci", "ids": ids });
    }

    /// Toglie i pacchetti rimasti soli. **Non si manda nessun elenco**: lo
    /// rifà il demone un istante prima e l'aiutante di root lo ricontrolla
    /// ancora. Un nome che nel frattempo ha smesso di essere orfano è un
    /// pacchetto che serve a qualcosa.
    function manutenzioneOrfani() {
        return send({ "action": "manutenzione_orfani" });
    }

    /// Il nome NON è `manutenzioneDoppioni`: quello è già il segnale della
    /// risposta, e in QML un segnale e una funzione con lo stesso nome sono un
    /// «Duplicate method name» che porta giù l'intera shell — non solo questo
    /// file. La stessa coppia esiste già per l'inventario: segnale
    /// `manutenzioneInventario`, funzione `manutenzioneVedi`.
    function manutenzioneVediEscluse() {
        return send({ "action": "manutenzione_escluse" });
    }

    function manutenzioneEscludi(percorso) {
        return send({ "action": "manutenzione_escludi", "percorso": percorso });
    }

    function manutenzioneIncludi(percorso) {
        return send({ "action": "manutenzione_includi", "percorso": percorso });
    }

    function manutenzioneCercaDoppioni() {
        return send({ "action": "manutenzione_doppioni" });
    }

    /// Li mette nel CESTINO, non li cancella: sono file tuoi, non cache. E il
    /// demone rifà il giro prima di toccarli, rifiutando qualunque percorso
    /// che lascerebbe un gruppo senza copie.
    function manutenzioneDoppioniCestina(percorsi) {
        return send({ "action": "manutenzione_doppioni_cestina",
                      "percorsi": percorsi });
    }

    function custodiaVedi() { return send({ "action": "custodia_panoramica" }); }
    function custodiaApri(percorso) {
        return send({ "action": "custodia_dettaglio", "percorso": percorso });
    }
    function custodiaAggiungi(percorso, nome, motore) {
        return send({ "action": "custodia_aggiungi", "percorso": percorso,
                      "nome": nome || undefined, "motore": motore || undefined });
    }
    function custodiaTogli(percorso) {
        return send({ "action": "custodia_togli", "percorso": percorso });
    }
    function custodiaPunto(percorso, nota) {
        return send({ "action": "custodia_punto", "percorso": percorso,
                      "nota": nota || "" });
    }
    function custodiaSalva(percorso, messaggio, forza) {
        return send({ "action": "custodia_salva", "percorso": percorso,
                      "messaggio": messaggio, "forza": forza === true });
    }
    /// Nome ed email con cui firmare i salvataggi di un progetto.
    function custodiaFirma(percorso, nome, email) {
        return send({ "action": "custodia_firma", "percorso": percorso,
                      "nome": nome, "email": email });
    }
    function custodiaInizia(percorso) {
        return send({ "action": "custodia_inizia", "percorso": percorso });
    }
    function custodiaDestinazioneAggiungi(percorso, tipo, nome, dove) {
        return send({ "action": "custodia_destinazione_aggiungi",
                      "percorso": percorso, "tipo": tipo,
                      "nome": nome || "", "dove": dove });
    }
    function custodiaDestinazioneTogli(percorso, dove) {
        return send({ "action": "custodia_destinazione_togli",
                      "percorso": percorso, "dove": dove });
    }
    function custodiaManda(percorso, dove) {
        return send({ "action": "custodia_manda",
                      "percorso": percorso, "dove": dove });
    }

    function custodiaTornaASalvataggio(percorso, id) {
        return send({ "action": "custodia_torna_salvataggio",
                      "percorso": percorso, "id": id });
    }
    function custodiaTornaAPunto(percorso, id) {
        return send({ "action": "custodia_torna_punto",
                      "percorso": percorso, "id": id });
    }

    // ── GitHub ──────────────────────────────────────────────────────────
    //
    // Il gettone attraversa questa riga una volta sola, in un verso solo. Il
    // demone lo mette nel portachiavi di sistema e da lì non torna più
    // indietro: `custodiaGithubChi()` risponde col nome dell'account, mai con
    // la chiave. Quindi la finestra non ha niente da tenere in memoria, e non
    // c'è nessun posto dove possa dimenticarselo.
    function custodiaGithubGettone(gettone) {
        return send({ "action": "custodia_github_gettone",
                      "gettone": gettone });
    }
    // ── Entrare senza incollare niente ──────────────────────────────────
    //
    // Due funzioni per i due passi del device flow: la prima torna subito col
    // codice da mostrare, la seconda resta in attesa finché non hai confermato
    // sul sito — anche minuti, ed è normale.
    function custodiaGithubAccedi() {
        return send({ "action": "custodia_github_accedi" });
    }
    function custodiaGithubAttendi(nostro, ogni, scadeFra) {
        return send({ "action": "custodia_github_attendi", "nostro": nostro,
                      "ogni": ogni || 5, "scadeFra": scadeFra || 900 });
    }
    function custodiaGithubChi() {
        return send({ "action": "custodia_github_chi" });
    }
    function custodiaGithubDimentica() {
        return send({ "action": "custodia_github_dimentica" });
    }
    function custodiaGithubCrea(percorso, nome, privato) {
        return send({ "action": "custodia_github_crea", "percorso": percorso,
                      "nome": nome, "privato": privato !== false });
    }

    // ── Account online ──────────────────────────────────────────────────
    //
    // La password attraversa questa riga una volta sola, in un verso solo. Il
    // demone la mette nel portachiavi di sistema e da lì non torna più
    // indietro: nessuna risposta la contiene, nemmeno accorciata. Quindi la
    // finestra non ha niente da tenere in memoria, e non c'è nessun posto dove
    // possa dimenticarsela.
    function accountVedi() {
        return send({ "action": "account_elenco" });
    }
    function accountCollega(servizio, utente, password, extra) {
        var m = { "action": "account_collega", "servizio": servizio,
                  "utente": utente, "password": password };
        if (extra) {
            if (extra.url !== undefined) m.url = extra.url;
            if (extra.numero !== undefined) m.numero = extra.numero;
            if (extra.nome !== undefined) m.nome = extra.nome;
        }
        return send(m);
    }
    function accountScollega(id) {
        return send({ "action": "account_scollega", "id": id });
    }
    function accountGuarda(id) {
        return send({ "action": "account_guarda", "id": id });
    }

    // Google: da qui non parte nessuna password. Parte una richiesta, e torna
    // indietro **un indirizzo da aprire nel browser** — la pagina di Google,
    // quella vera, con l'email, la password e il secondo passaggio. Minerva
    // non la vede e non la tocca.
    function accountGoogleChiave(identificativo, segreto) {
        return send({ "action": "account_google_chiave",
                      "identificativo": identificativo, "segreto": segreto });
    }
    function accountGoogleDimentica() {
        return send({ "action": "account_google_dimentica" });
    }
    function accountGoogleCollega() {
        return send({ "action": "account_google_collega" });
    }

    function radiceAzione(op, args) {
        return send({ "action": "radice_azione", "op": op, "args": args });
    }

    function greeterCreateSession(username) {
        return send({ "action": "greeter_create_session", "username": username });
    }

    /// `undefined` per i messaggi che non chiedono niente (`info`, `error`):
    /// vanno confermati, ma senza risposta. Una stringa vuota è un'altra cosa,
    /// e PAM può prenderla per una password sbagliata.
    function greeterRespond(response) {
        var m = { "action": "greeter_respond" };
        if (response !== undefined && response !== null)
            m.response = response;
        return send(m);
    }

    /// Dopo il «sì» a questa, la sessione parte QUANDO IL GREETER FINISCE.
    /// Chi la chiama deve chiudersi, o resta a guardare una schermata di
    /// accesso che ha già accettato la password.
    function greeterStart(cmd, env) {
        return send({ "action": "greeter_start", "cmd": cmd, "env": env || [] });
    }

    function greeterCancel() { return send({ "action": "greeter_cancel" }); }



    /// I gruppi delle impostazioni — immagini, video, pagine web… — con chi li
    /// apre adesso e chi potrebbe. Arriva su `mimeCategoriesReceived`.
    function mimeCategories() {
        return send({ "action": "mime_categories" });
    }

    /// Assegna un programma a TUTTI i tipi di un gruppo. Il demone risponde
    /// anche con l'elenco aggiornato, quindi non serve richiederlo.
    function mimeSetCategory(category, appId) {
        return send({ "action": "mime_set_category",
                      "category": category, "appId": appId });
    }

    function mimeSetDefault(mime, appId) {
        return send({ "action": "mime_set_default", "mime": mime, "appId": appId });
    }

    /// Toglie il programma predefinito di un tipo: da lì in poi decide di
    /// nuovo il sistema. Non mette nessuno in lista nera — quella è un'altra
    /// cosa, e la dice `[Removed Associations]`.
    function mimeForgetDefault(mime) {
        return send({ "action": "mime_forget_default", "mime": mime });
    }

    /// Che cos'è un file e chi lo può aprire: `{path, mime, defaultApp,
    /// candidates}`. Risponde su `mimeDescribed`.
    function mimeDescribe(path) {
        return send({ "action": "mime_describe", "path": path });
    }

    /// Apre dei percorsi con un programma preciso.
    function openWith(appId, paths) {
        return send({ "action": "open_with", "appId": appId, "paths": paths });
    }

    /// Apre col programma predefinito. Se non ce n'è uno, la risposta arriva
    /// con `needsChoice: true` invece che con un silenzio.
    function openDefault(paths) {
        return send({ "action": "open_default", "paths": paths });
    }

    /// Il file per cui la shell deve chiedere «con che cosa?» se il demone
    /// risponde `needsChoice`. Vedi `apriOChiedi`.
    property string chiediPer: ""

    /// «Apri questo», e se non c'è un programma per il suo tipo si chiede.
    ///
    /// `openDefault` da solo lascia la risposta `needsChoice` a chi la vuole
    /// ascoltare, e per una notifica o per `xdg-open` non ascoltava nessuno:
    /// clic su un file di tipo sconosciuto, e niente (6 ottobre 2026). La
    /// finestrella la apre `shell.qml`, che guarda `chiediPer`.
    function apriOChiedi(path) {
        ipc.chiediPer = path;
        return ipc.openDefault([path]);
    }

    /// Le icone arrivano da due strade — dentro `init_state` alla connessione,
    /// e da sole quando il tema cambia — e in tutti e due i casi vanno prese
    /// allo stesso modo.
    /// Lo stato dell'apparecchio arriva da due strade — dentro `init_state`
    /// alla connessione, e da solo quando cambia — e in tutti e due i casi va
    /// preso allo stesso modo.
    ///
    /// Se arriva vuoto NON si azzera quello che si ha: perdere il demone per
    /// un istante non deve far sparire la batteria dalla barra. Il guardiano
    /// lo sta già rimettendo in piedi (`scripts/minerva-demone`), e l'ultimo
    /// valore noto è più vero di nessun valore.
    function _takeSystem(payload) {
        if (!payload || typeof payload !== "object")
            return;
        ipc.system = payload;
        ipc.systemReceived();
    }

    function _takeIcons(payload) {
        ipc.iconMap = payload.map || ({});
        ipc.iconTheme = payload.theme || "";
        ipc.iconChosen = payload.chosen || "";
        ipc.iconChieste = payload.chieste || 0;
        ipc.iconMancanti = payload.mancanti || [];
    }

    // ── Connessione ──────────────────────────────────────────────────────

    // ── L'indirizzo ──────────────────────────────────────────────────────
    //
    // Un socket Unix in `$XDG_RUNTIME_DIR/liquid-de/`, col nome della sessione
    // dentro. Diverso dentro la schermata di accesso, e non per gusto: là c'è
    // un secondo Minerva completo — demone e shell — che gira come utente
    // `greeter` mentre la sessione di chi sta già lavorando è ancora aperta.
    // Con un indirizzo solo il demone del greeter non riesce ad ascoltare e la
    // schermata finisce a parlare col demone dell'ALTRO utente: quello non è
    // dentro un greeter, risponde che greetd non c'è, e la schermata si mette
    // in anteprima. Nessun errore a schermo, solo una password che non fa
    // entrare. È successo il 5 agosto 2026.
    //
    // Fino al 27 agosto 2026 era una porta TCP, la 11432. Il cambio ha tolto
    // `qt6-websockets` dalle dipendenze e ha chiuso il canale a chiunque non
    // sia questo utente — vedi `minervad/lib/ipc/canale_segreto.dart`.
    //
    // `Quickshell.env` restituisce `null` quando la variabile non c'è.

    /// L'indirizzo che si userebbe se non ci fosse un file del canale da
    /// leggere. **La stessa regola sta in `WebSocketServer.socketPredefinito`**:
    /// se si cambia una va cambiata l'altra, o la shell cerca dove il demone
    /// non è.
    readonly property string socketDiRipiego:
        ipc.cartellaRuntime + "/canale-" + ipc._sessione + ".sock"

    // ── Dove stanno le cose ──────────────────────────────────────────────
    //
    // Le stesse regole di `minervad/lib/core/minerva_paths.dart`, e lo stesso
    // nome: le cartelle di Liquid DE si chiamano `liquid-de` in ogni base
    // XDG, così Liquid DE e Minerva convivono senza scriversi addosso. Il
    // nome sta scritto qui e da nessun'altra parte della shell.

    readonly property string nome: "liquid-de"

    function _baseXdg(variabile, diSerie) {
        var v = Quickshell.env(variabile);
        if (v !== null && v !== undefined && String(v).charAt(0) === "/")
            return ipc._senzaBarra(String(v));
        return String(Quickshell.env("HOME") || "/tmp") + "/" + diSerie;
    }

    /// Le impostazioni: `MINERVA_CONFIG_DIR` vince, come nel demone.
    readonly property string cartellaConfig: {
        var detto = Quickshell.env("MINERVA_CONFIG_DIR");
        if (detto)
            return ipc._senzaBarra(String(detto));
        return ipc._baseXdg("XDG_CONFIG_HOME", ".config") + "/" + ipc.nome;
    }
    readonly property string cartellaDati: ipc._baseXdg("XDG_DATA_HOME", ".local/share") + "/" + ipc.nome
    readonly property string cartellaCache: ipc._baseXdg("XDG_CACHE_HOME", ".cache") + "/" + ipc.nome

    /// I programmi installati di Liquid DE (`~/.local/bin` è di Minerva):
    /// `MINERVA_BIN` li sostituisce nelle prove.
    readonly property string cartellaBin: {
        var detto = Quickshell.env("MINERVA_BIN");
        if (detto)
            return ipc._senzaBarra(String(detto));
        var p = Quickshell.env("LIQUID_PREFISSO");
        return (p ? ipc._senzaBarra(String(p))
                  : String(Quickshell.env("HOME") || "/tmp") + "/.local/opt/" + ipc.nome) + "/bin";
    }

    /// Socket e file della sessione; senza una cartella di runtime valida,
    /// /tmp con l'utente nel nome.
    readonly property string cartellaRuntime: {
        var r = Quickshell.env("XDG_RUNTIME_DIR");
        if (r !== null && r !== undefined && String(r).charAt(0) === "/")
            return ipc._senzaBarra(String(r)) + "/" + ipc.nome;
        return "/tmp/" + ipc.nome + "-" + String(Quickshell.env("USER") || "utente");
    }

    /// Qualcuno ha DETTO dove parlare?
    ///
    /// Se sì vince su tutto, file compreso: è un ordine, non un suggerimento —
    /// ed è così che la schermata di accesso resta sul suo socket anche
    /// trovandosi accanto il canale di una sessione già aperta. Un valore
    /// scritto male non è un ordine: si torna al predefinito.
    readonly property bool socketImposto: {
        var v = Quickshell.env("MINERVA_IPC_SOCKET");
        return v !== null && v !== undefined
            && String(v).charAt(0) === "/" && String(v).length <= 100;
    }

    /// L'indirizzo VERO: quello che il demone ha scritto nel file del canale.
    ///
    /// Non si indovina. Due sessioni accese insieme hanno due socket, e dare
    /// per scontato il proprio vorrebbe dire, nella seconda sessione,
    /// comandare la scrivania della prima. Che è peggio di non connettersi.
    readonly property string percorsoSocket:
        ipc.socketImposto ? String(Quickshell.env("MINERVA_IPC_SOCKET"))
                          : ((ipc._canale && ipc._canale.socket)
                                ? ipc._canale.socket
                                : ipc.socketDiRipiego)

    // Detto ad alta voce una volta, perché è la prima cosa da guardare quando
    // «la shell non vede il demone»: due percorsi diversi qui e nel registro
    // del demone spiegano tutto in un secondo.

    // ── La parola d'ordine del canale ────────────────────────────────────
    //
    // Il demone ascolta su una porta TCP di `localhost`, e fino al 16 agosto
    // 2026 rispondeva a chiunque riuscisse a collegarsi — cioè a ogni processo
    // di ogni utente del computer. Dentro la schermata di accesso questo
    // voleva dire che un estraneo poteva aspettare che tu scrivessi la
    // password e poi chiedere lui `greeter_start` con un comando suo, che
    // greetd avrebbe eseguito **come te**.
    //
    // Adesso il demone scrive una parola d'ordine in un file leggibile solo
    // dal proprietario, e la vuole sentire prima di rispondere a qualunque
    // cosa. Che cosa garantisce e che cosa no sta scritto per esteso in
    // `minervad/lib/ipc/canale_segreto.dart`.

    /// I posti dove il segreto può stare, nell'ordine.
    ///
    /// **La stessa lista sta in `canale_segreto.dart`**: se si cambia una va
    /// cambiata l'altra, e c'è una prova che le confronta.
    ///
    /// Sono più d'uno e non uno solo perché il demone ripiega: dentro la
    /// schermata di accesso `XDG_RUNTIME_DIR` può essere impostata su una
    /// cartella che l'utente `greeter` non ha il diritto di creare, e in quel
    /// caso il segreto finisce nella cartella di configurazione. Cercando in
    /// un posto solo, il demone lo scriverebbe di là e la schermata lo
    /// cercherebbe di qua: due programmi giusti, un accesso che non funziona.
    /// Il nome di QUESTA sessione.
    ///
    /// **La stessa regola sta in `scripts/minerva-posti.sh` e in
    /// `minervad/lib/ipc/canale_segreto.dart`**, e c'è una prova che confronta
    /// i tre: se divergono, il demone scrive in un posto e la finestra cerca
    /// in un altro — due programmi giusti e una scrivania che non si connette.
    ///
    /// Serve da quando due Minerva possono essere accese insieme: senza, la
    /// seconda leggerebbe l'indirizzo della prima e finirebbe a comandare la
    /// scrivania dell'altra.
    readonly property string _sessione: {
        var s = String(Quickshell.env("MINERVA_SESSIONE") || "");
        if (s === "")
            s = String(Quickshell.env("XDG_SESSION_ID") || "");
        if (s === "") {
            var vt = Quickshell.env("XDG_VTNR");
            if (vt)
                s = "vt" + String(vt);
        }
        if (s === "")
            s = "unica";
        s = s.replace(/[^A-Za-z0-9._-]/g, "_");
        return s === "" ? "unica" : s;
    }

    readonly property var _percorsiSegreto: {
        var detto = Quickshell.env("MINERVA_TOKEN_FILE");
        if (detto)
            return [String(detto)];
        var out = [];
        var dove = "/sessioni/" + ipc._sessione + "/canale";
        if (Quickshell.env("XDG_RUNTIME_DIR"))
            out.push(ipc.cartellaRuntime + dove);
        out.push(ipc.cartellaConfig + dove);
        return out;
    }

    /// La cartella di QUESTA sessione in `$XDG_RUNTIME_DIR/liquid-de/sessioni/`,
    /// o "" se non c'è una cartella di esecuzione. È 0700 e sparisce allo
    /// spegnimento: il posto per le cose che due processi della stessa
    /// sessione si passano e che nessun altro deve leggere — per esempio le
    /// notifiche da mostrare sulla schermata di blocco.
    readonly property string cartellaSessione:
        Quickshell.env("XDG_RUNTIME_DIR") ? ipc.cartellaRuntime + "/sessioni/" + ipc._sessione : ""

    function _senzaBarra(p) {
        return (p.length > 1 && p.charAt(p.length - 1) === "/")
               ? p.substring(0, p.length - 1) : p;
    }

    /// Il lettore del file.
    ///
    /// `blockLoading` perché la parola d'ordine serve NELL'ISTANTE in cui il
    /// socket si apre: leggerla in modo asincrono vorrebbe dire salutare un
    /// attimo dopo, e nel frattempo scade il limite di cinque secondi del
    /// demone se la macchina è carica. È un file da quaranta byte.
    property FileView _fileSegreto: FileView {
        id: fileSegreto
        blockLoading: true
        // Il file può non esserci ancora: la shell parte insieme al demone e
        // spesso arriva prima. Non è un errore da stampare a ogni avvio, è un
        // «riprova fra poco» — e il riprovare è già la riconnessione.
        printErrors: false
    }

    /// Rilegge il segreto dal disco, adesso.
    ///
    /// Ogni volta e non una sola: il demone ne scrive uno NUOVO a ogni avvio,
    /// e se riparte (lo rimette in piedi il guardiano) quello che avevamo in
    /// mano non vale più. Si azzera il percorso e lo si rimette per costringere
    /// `FileView` a rileggere invece di restituire quello che aveva in cache.
    /// Legge il file del canale: `{socket, segreto}`, o `null` se non c'è.
    ///
    /// Dentro ci sono due cose e non una, e la seconda è l'indirizzo: due
    /// sessioni accese insieme hanno due socket, e il proprio non si può
    /// indovinare. Chi legge questo file scopre insieme DOVE e COME parlare.
    ///
    /// Un file scritto da un demone di prima del 27 agosto 2026 ha `porta=` e
    /// non `socket=`. Non lo si traduce: `socket` resta vuoto e si ricade sul
    /// predefinito, che è l'unica cosa onesta — quel demone lì non ascolta su
    /// nessun socket, e fingere di sapere dove sia vorrebbe dire aspettare per
    /// sempre una risposta che non arriva.
    function _leggiCanale() {
        var posti = ipc._percorsiSegreto;
        for (var i = 0; i < posti.length; i++) {
            // Si azzera e si rimette per costringere `FileView` a rileggere
            // invece di restituire quello che aveva in cache.
            fileSegreto.path = "";
            fileSegreto.path = posti[i];
            var t = fileSegreto.text();
            if (!t || String(t).trim() === "")
                continue;
            var fuori = { "socket": "", "segreto": "" };
            var righe = String(t).split("\n");
            for (var r = 0; r < righe.length; r++) {
                var riga = righe[r].trim();
                var taglio = riga.indexOf("=");
                if (taglio <= 0)
                    continue;
                var chiave = riga.substring(0, taglio).trim();
                var valore = riga.substring(taglio + 1).trim();
                if (chiave === "socket")
                    fuori.socket = valore;
                else if (chiave === "segreto")
                    fuori.segreto = valore;
            }
            // ── Servono TUTTE E DUE, o non è un canale ──────────────────
            //
            // Il demone scrive il file DOPO aver preso il socket (vedi
            // `_ascolta`), quindi se il file c'è con dentro un indirizzo, lì
            // dall'altra parte c'è qualcuno. È la ragione per cui questa shell
            // non bussa mai a vuoto.
            //
            // Un file con la sola parola d'ordine è un avanzo: capita con
            // quelli scritti prima del 27 agosto 2026, che hanno `porta=`.
            // Accettarlo voleva dire ricadere sul percorso di ripiego e
            // bussare a un socket che non esiste — un
            // «QLocalSocket::ServerNotFoundError» a ogni tentativo, cioè un
            // avviso che compare sempre e quindi non vuol più dire niente.
            if (fuori.segreto !== "" && fuori.socket !== "")
                return fuori;
        }
        return null;
    }

    /// L'indirizzo del canale letto dal file: `{socket, segreto}`, o `null`
    /// finché il demone non l'ha scritto.
    property var _canale: null

    /// Rilegge il file. Va fatto a ogni tentativo di connessione: il demone ne
    /// scrive uno nuovo a ogni avvio, e se riparte (lo rimette in piedi il
    /// guardiano) quello che avevamo in mano non vale più — né la porta né la
    /// parola d'ordine.
    function _scopri() {
        ipc._canale = ipc._leggiCanale();
        return ipc._canale !== null;
    }

    // Uno solo, e qui: `Component.onCompleted` si può scrivere una volta per
    // oggetto, e scriverlo due volte non è un avviso — è un file QML che non
    // si carica più, con dietro tutto quello che lo importa. («Property value
    // set multiple times», e a schermo la shell che non parte.)
    Component.onCompleted: {
        // Detto ad alta voce una volta, perché è la prima cosa da guardare
        // quando «la shell non vede il demone»: due percorsi diversi qui e nel
        // registro del demone spiegano tutto in un secondo.
        console.log("[MINERVA][IPC] Canale su " + ipc.percorsoSocket
                    + " (sessione «" + ipc._sessione + "»)");

        // Se il file non c'è ancora — la shell parte insieme al demone e
        // arriva quasi sempre prima — il socket resta chiuso e ci pensa il
        // timer a riprovare. Senza questa riga non partirebbe nessuno: il
        // timer si accende dal socket, e il socket non si apre finché non si
        // sa dove. Un'attesa che non finisce mai, e nessun errore da leggere.
        // Si prova subito, e il timer resta acceso finché il demone non ha
        // risposto al saluto: il primo tentativo può benissimo fallire — la
        // shell parte quasi sempre PRIMA del demone — e da lì in poi tocca a
        // lui. Si ferma nel caso `"ciao"`, che è l'unico posto in cui si sa
        // di essere davvero dentro.
        ipc._rinnova();
        reconnectTimer.start();
    }

    /// Scrive sul socket vivo, se ce n'è uno.
    ///
    /// Fra un tentativo e il prossimo non c'è nessun socket: chi scrive non
    /// deve saperlo, e soprattutto non deve schiantarsi.
    function _scrivi(testo) {
        if (ipc._vivo)
            ipc._vivo.write(testo);
    }

    /// ── UN SOCKET FALLITO NON SI RIUSA: SE NE FA UN ALTRO ────────────────
    ///
    /// È la causa vera del guasto del 31 agosto 2026, ed è stata misurata con
    /// un esperimento apposta invece che dedotta:
    ///
    ///   * si bussa a un socket che non c'è → errore, come previsto;
    ///   * il server compare;
    ///   * `connected = false` e poi `connected = true` sullo **stesso**
    ///     oggetto → **non succede più niente**. Nessun errore, nessuna
    ///     connessione, nessun segnale: silenzio.
    ///   * un `Socket` **appena creato**, stesso percorso, stesso istante →
    ///     connesso subito.
    ///
    /// Un `Socket` di Quickshell 0.3.1 che ha fallito una volta è bruciato.
    /// E la vecchia riconnessione era costruita tutta sul riusarne uno solo:
    /// bastava che il primo tentativo cadesse nel secondo in cui il demone si
    /// stava rialzando — che è ESATTAMENTE quando cade — perché la shell non
    /// tornasse più. Restava viva, disegnava, rispondeva ai tasti, e non
    /// parlava più col demone: senza il suo elenco di applicazioni la dock ha
    /// scritto `visible: items.length > 0` e sparisce, e il menù resta vuoto.
    ///
    /// Da qui in poi ogni tentativo è un oggetto nuovo, e quello di prima si
    /// butta. Costa la creazione di un oggetto ogni due secondi mentre il
    /// demone è giù, e non costa niente quando è su.
    function _rinnova() {
        if (ipc._vivo) {
            ipc._vivo.connected = false;
            ipc._vivo.destroy();
            ipc._vivo = null;
        }
        ipc._aperto = false;
        ipc._salutato = false;
        // Prima si rilegge DOVE, poi si bussa: un demone che è ripartito ha
        // di sicuro una parola d'ordine nuova, e il socket vecchio può essere
        // rimasto per terra.
        if (!ipc._scopri())
            return false;
        ipc._vivo = ipc._stampo.createObject(ipc);
        if (!ipc._vivo)
            return false;
        ipc._vivo.connected = true;
        return true;
    }

    property Component _stampo: Component { Socket {
        id: socket
        path: ipc.percorsoSocket

        // ── I confini fra un messaggio e il prossimo ─────────────────────
        //
        // La `WebSocket` questo lo dava gratis: ogni messaggio arrivava
        // intero. Un socket è un tubo di byte, e quello che il demone scrive
        // in una volta può arrivare in tre pezzi — o tre risposte possono
        // arrivare attaccate. Il confine è l'a-capo, e si può usare perché
        // `JSON.stringify` non ne produce mai uno dentro un messaggio: un
        // a-capo dentro una stringa diventa `\n`, due caratteri. Quindi una
        // riga è sempre esattamente un messaggio.
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { socket.leggi(data); }
        }

        // ── Quando si è «provato» ────────────────────────────────────────
        //
        // `_haProvato` regge `_nessunDemone`, ed è la differenza fra «il
        // demone non c'è» e «non gli abbiamo ancora parlato»: vedi il commento
        // in cima. Con la `WebSocket` bastava lo stato `Connecting`. Un
        // `Socket` non ce l'ha — o è connesso o no — quindi il momento in cui
        // si è provato davvero sono due: quando riesce, e quando fallisce.
        onError: function(quale) {
            if (ipc._vivo !== socket) return;
            ipc._haProvato = true;
            ipc._aperto = false;
            // Un tentativo fallito è un motivo per riprovare. Senza questa
            // riga, un errore che non cambia lo stato della connessione — il
            // socket non era mai arrivato ad aprirsi, quindi
            // `onConnectionStateChanged` non scatta — non riaccendeva
            // niente: la shell restava viva, disegnava, rispondeva ai tasti,
            // e non parlava più col demone.
            if (!reconnectTimer.running)
                reconnectTimer.start();
        }

        onConnectionStateChanged: {
            if (ipc._vivo !== socket) return;
            if (socket.connected) {
                ipc._haProvato = true;
                ipc._aperto = true;
                ipc._apertoDa = Date.now();
                // Aperto, non ancora salutato: la prima cosa che esce da qui
                // è la parola d'ordine, e nient'altro finché il demone non
                // risponde di sì.
                ipc._salutato = false;
                socket.write(JSON.stringify({
                    "action": "ciao",
                    "segreto": ipc._canale ? ipc._canale.segreto : ""
                }) + "\n");
            } else {
                ipc._salutato = false;
                // Solo se è ANCORA lui il socket vivo: quando `_rinnova()`
                // butta il vecchio, anche quello annuncia di essersi chiuso, e
                // senza questa guardia spegnerebbe lo stato di quello nuovo
                // appena acceso.
                if (ipc._vivo === socket) {
                    ipc._aperto = false;

                    // ── Una perdita si annuncia SEMPRE, e una volta sola ──
                    //
                    // Qui l'annuncio stava dentro `if (!reconnectTimer.running)`,
                    // e quella è la condizione sbagliata: quando il demone
                    // riparte il timer **sta già girando** quasi sempre — lo
                    // avvia `_rinnova()`, o la sveglia della scadenza — quindi
                    // il ramo non veniva mai preso e **il distacco non finiva
                    // nel registro**.
                    //
                    // Misurato il 5 settembre 2026 sul registro della sessione
                    // viva: «Connesso al demone» **nove volte**, «Connessione
                    // persa» **zero**. La shell si era riagganciata nove volte
                    // senza mai dire di essersi staccata.
                    //
                    // Non è rumore che manca: è l'unica riga che dice QUANDO è
                    // successo. È esattamente l'evento che il 2 settembre 2026
                    // ha lasciato dock e menù vuoti in tutte e due le sessioni,
                    // e senza quella riga il registro di quel giorno non
                    // avrebbe potuto dirlo.
                    //
                    // E si dice una volta per distacco, non una per tentativo:
                    // la ripetizione si toglie, l'informazione mai.
                    if (!ipc._perditaDetta) {
                        ipc._perditaDetta = true;
                        // «Persa» solo se prima c'era. All'avvio della sessione
                        // la shell parte insieme al demone e arriva quasi
                        // sempre prima: quella non è una connessione persa, è
                        // una che non è ancora cominciata. Chiamarla persa
                        // metteva un avviso nel registro di OGNI accesso — e un
                        // avviso che compare sempre smette di voler dire
                        // qualcosa, che è il modo in cui un registro diventa
                        // inutile.
                        if (ipc._eraConnesso)
                            console.warn("[MINERVA][IPC] Connessione persa, riprovo.");
                        else
                            console.log("[MINERVA][IPC] Il demone non risponde ancora, riprovo.");
                    }
                }
                if (!reconnectTimer.running)
                    reconnectTimer.start();
            }
        }

        /// Un messaggio intero, già senza a-capo: lo passa il `SplitParser`.
        function leggi(message) {
            if (ipc._vivo !== socket) return;
            var msg;
            try {
                msg = JSON.parse(message);
            } catch (e) {
                console.warn("[MINERVA][IPC] Messaggio non leggibile:", message);
                return;
            }

            switch (msg.event) {
            // ── La risposta al saluto ────────────────────────────────────
            //
            // Arriva prima di ogni altra cosa. Da qui in poi il canale è
            // aperto davvero: si svuota la coda e si chiede quello che serve.
            case "ciao":
                if (msg.payload && msg.payload.ok === true) {
                    ipc._salutato = true;
                    // Il prossimo distacco è un altro distacco, e va detto di
                    // nuovo: qui si riarma l'annuncio.
                    ipc._perditaDetta = false;
                    console.log("[MINERVA][IPC] Connesso al demone.");
                    reconnectTimer.stop();
                    // Riagganciato: il prossimo distacco riparte fitto come il
                    // primo, invece di ereditare l'attesa lunga di prima.
                    reconnectTimer.interval = ipc._attesaMinima;
                    ipc._svuotaCoda();
                    ipc.requestKeybindings();
                    // Si rilegge il disco invece di fidarsi dell'elenco che il
                    // demone ha in memoria: il demone parte una volta per
                    // sessione, la shell si riavvia molte volte, e un programma
                    // installato nel frattempo non comparirebbe mai. Costa una
                    // scansione di quattro cartelle, una volta.
                    ipc.rescanApps();
                    ipc._eraConnesso = true;
                } else {
                    // Il segreto che avevamo in mano non vale più: quasi
                    // sempre perché il demone è ripartito e ne ha scritto uno
                    // nuovo mentre eravamo connessi. Si riparte da capo, e la
                    // riconnessione lo rilegge dal disco.
                    console.warn("[MINERVA][IPC] Il demone non ha accettato la "
                                 + "parola d'ordine, la rileggo e riprovo.");
                    ipc._salutato = false;
                    // `_apertoDa = 0` perché il giro dopo il timer non deve
                    // concedere a questa connessione il tempo del saluto: il
                    // saluto c'è già stato, ed è stato rifiutato.
                    ipc._apertoDa = 0;
                    reconnectTimer.start();
                }
                break;
            case "init_state":
                if (msg.payload.settings) {
                    ipc.settings = ipc._conScrittureInVolo(msg.payload.settings);
                    // Da qui in poi i colori sono quelli veri: chi aspettava
                    // per non dipingere sbagliato può partire.
                    ipc._settingsNote = true;
                    ipc.settingsReceived(ipc.settings);
                }
                if (msg.payload.keybindings) {
                    ipc.keybindings = msg.payload.keybindings;
                    ipc.keybindingsReceived(ipc.keybindings);
                }
                if (msg.payload.icons)
                    ipc._takeIcons(msg.payload.icons);
                if (msg.payload.system)
                    ipc._takeSystem(msg.payload.system);
                break;
            case "processes":
                ipc.processesReceived(msg.payload || ({}));
                break;
            case "machine_state":
                ipc.machineStateReceived(msg.payload || ({}));
                break;
            case "process_killed":
                ipc.processKilled(msg.payload.pid || 0,
                                  msg.payload.ok === true,
                                  msg.payload.force === true);
                break;
            case "icons":
                ipc._takeIcons(msg.payload);
                break;
            case "system_state":
                ipc._takeSystem(msg.payload);
                break;
            case "icon_themes":
                ipc.iconThemes = msg.payload.themes || [];
                ipc.iconeInstallate = msg.payload.installati || [];
                break;
            // ── Qui c'era un caso vuoto, e cadeva di sotto ───────────────
            //
            // Un `case` senza corpo e senza `break`, in JavaScript, non è un
            // caso ignorato: è un caso che PROSEGUE nel successivo. Quello
            // che stava qui sarebbe finito dentro il ramo dell'estensione
            // terminata, e Minerva avrebbe annunciato la morte di un plugin
            // che non esiste («?», codice 0) ogni volta che arrivavano le
            // impostazioni.
            //
            // Non è mai successo per un pelo: a mandare quell'evento era una
            // sola azione del demone, e non la chiedeva nessuno. Le
            // impostazioni arrivano dal ramo qui sotto, che è l'evento vero e
            // ha il suo corpo.
            //
            // Tolto il 23 agosto 2026. L'ha trovato `bus_coerenza_test.dart`,
            // che confronta gli eventi smistati dalla shell con quelli
            // pubblicati dal demone: un orfano da una parte era una trappola
            // dall'altra.

            // ── Un'estensione che muore lo deve dire ─────────────────────
            //
            // Il demone pubblicava `plugin_terminated` e non lo smistava
            // nessuno: un plugin si fermava e l'utente non lo sapeva mai.
            // Trovato il 12 agosto 2026 confrontando gli eventi pubblicati
            // con quelli attesi — vedi `minervad/test/bus_coerenza_test.dart`.
            //
            // La regola del progetto è che un plugin rotto non deve impedire
            // l'accesso al computer, e resta vera: si tira dritto E si dice.
            case "plugin_terminated":
                ipc.pluginTerminato(String((msg.payload || {}).name || "?"),
                                    Number((msg.payload || {}).exitCode || 0));
                break;
            case "desktop_launch_prepared":
                ipc._launcherPrepared(msg.payload);
                break;
            case "desktop_launch_result":
                ipc._launcherResult(msg.payload);
                break;
            // ── Una richiesta che non è andata ───────────────────────────
            //
            // Fino al 7 settembre 2026 il demone non lo diceva: un'azione
            // sconosciuta, o una che scoppiava a metà, finiva in una riga del
            // suo registro, e chi l'aveva mandata restava ad aspettare per
            // sempre. Il canale intanto continuava a funzionare per tutto il
            // resto, quindi il difetto non si vedeva.
            //
            // Qui si SCRIVE e basta, di proposito: non c'è un identificativo
            // di richiesta, quindi la shell non può sapere QUALE chiamata
            // riaprire, e inventarsi un rimedio a indovinare sarebbe peggio
            // del silenzio. Ma adesso, quando una cosa non funziona, in
            // `qs log` c'è scritto il nome dell'azione invece di niente.
            case "azione_fallita":
                console.warn("[MINERVA][IPC] il demone non è riuscito a fare «"
                             + ((msg.payload || {}).azione || "?") + "»: "
                             + ((msg.payload || {}).perche || "senza motivo"));
                ipc.azioneFallita(String((msg.payload || {}).azione || "?"),
                                  String((msg.payload || {}).perche || ""));
                break;
            case "settings_changed":
                // L'eco di una scrittura nostra arriva identica a quello che
                // abbiamo già: riassegnarla rifaceva tutte le associazioni
                // una seconda volta. Si riassegna solo se è diverso.
                var nuove = ipc._conScrittureInVolo(msg.payload);
                if (JSON.stringify(nuove) !== JSON.stringify(ipc.settings))
                    ipc.settings = nuove;
                ipc.settingsReceived(ipc.settings);
                break;
            case "scorciatoie_compositore":
                ipc.scorciatoieCompositoreArrivate(
                    msg.payload && msg.payload.righe ? msg.payload.righe : []);
                break;
            case "keybindings":
            case "keybindings_changed":
                ipc.keybindings = msg.payload;
                ipc.keybindingsReceived(ipc.keybindings);
                break;
            case "all_apps":
                ipc.allApps = msg.payload;
                ipc.allAppsReceived(ipc.allApps);
                break;
            // Il ramo della finestra attiva è uscito insieme al comando che
            // la chiedeva: il demone non la manda più, e il segnale non lo
            // ascoltava nessuno.
            // Qual è la finestra attiva la shell lo sa dal compositore
            // direttamente (`core/Windows.qml`), che è la strada buona:
            // passare dal demone voleva dire due salti per una cosa che
            // cambia a ogni clic.
            case "windows_state":
                ipc.windowsStateReceived(msg.payload);
                break;
            case "monitors_state":
                var pMon = msg.payload;
                ipc.monitorsStateReceived(typeof pMon === "string" ? pMon : JSON.stringify(pMon));
                break;
            case "fs_listing":
                ipc.fileListingReceived(msg.payload);
                break;
            case "fs_search":
                ipc.ricercaAvanza(msg.payload);
                break;
            case "fs_job":
                ipc.fileJobChanged(msg.payload);
                break;
            case "fs_jobs":
                ipc.fileJobsReceived(msg.payload);
                break;
            case "fs_result":
                ipc.fileResultReceived(msg.payload);
                break;
            case "icone_esito":
                ipc.iconeEsito(msg.payload);
                break;
            case "condivisione_dove":
                ipc.condivisioneDoveRicevute(msg.payload);
                break;
            case "condivisione_esito":
                ipc.condivisioneEsito(msg.payload);
                break;
            case "bt_pairing":
                ipc.btAccoppiamento(msg.payload);
                break;
            case "bt_pair_result":
                // La ricevuta della richiesta. Interessa solo quando dice di
                // no — «c'è già un accoppiamento in corso» — e in quel caso è
                // un guasto da mostrare come gli altri.
                if (msg.payload && msg.payload.ok === false)
                    ipc.btAccoppiamento({ "stato": "fallito",
                                          "error": msg.payload.error });
                break;
            case "fs_text":
                ipc.fileTextReceived(msg.payload);
                break;
            case "fonts_list":
                ipc.fontsReceived(msg.payload);
                break;

            // ── La galleria ──────────────────────────────────────────────
            //
            // Sette eventi e non uno, e la divisione la spiega `EVENTS.md`:
            // `foto_proposte` costa (cerca dove sono le foto camminando la
            // cartella personale, 0,4 secondi misurati) e `foto_cartelle` no,
            // quindi tenerle insieme avrebbe fatto pagare la ricerca a ogni
            // apertura di finestra.
            case "foto_cartelle":
                ipc.fotoCartelle(msg.payload);
                break;
            case "foto_proposte":
                ipc.fotoProposte(msg.payload);
                break;
            case "foto_panoramica":
                ipc.fotoPanoramica(msg.payload);
                break;
            case "foto_giorno":
                ipc.fotoGiorno(msg.payload);
                break;
            // La miniatura risponde con un PERCORSO, non con dei byte: in
            // base64 sarebbe circa un megabyte per schermata di griglia. E
            // porta con sé `percorsoFoto`, il file di partenza, perché le
            // richieste tornano fuori ordine e chi ha chiesto deve poter
            // riconoscere la propria.
            case "foto_miniatura":
                ipc.fotoMiniatura(msg.payload);
                break;
            case "sfondo_sfocato":
                ipc.sfondoSfocato(msg.payload);
                break;
            case "foto_preferito":
                ipc.fotoPreferito(msg.payload);
                break;
            // A flusso: arriva a mazzetti mentre il demone cammina, e l'ultimo
            // dice che ha finito. Una scansione annullata non lascia un indice
            // a metà.
            case "foto_scansione":
                ipc.fotoScansione(msg.payload);
                break;
            case "foto_doppioni":
                ipc.fotoDoppioni(msg.payload);
                break;
            case "foto_doppioni_scarta":
                ipc.fotoDoppioniScartati(msg.payload);
                break;
            case "trasmetti_schermi":
                ipc.trasmettiSchermi(msg.payload && msg.payload.schermi
                                     ? msg.payload.schermi : []);
                break;
            case "trasmetti_esito":
                ipc.trasmettiEsito(msg.payload);
                break;
            case "trasmetti_stato":
                ipc.trasmettiStato(msg.payload);
                break;
            case "trasmetti_permesso":
                ipc.trasmettiPermesso(msg.payload);
                break;
            case "system_audio_state":
                ipc.systemAudioState(msg.payload);
                break;
            case "system_audio_select":
                ipc.systemAudioSelected(msg.payload);
                break;
            case "controller_state":
                ipc.controllerState(msg.payload);
                break;
            case "fs_info":
                ipc.fileInfoReceived(msg.payload);
                break;
            case "fs_measure":
                ipc.fileMeasureReceived(msg.payload);
                break;
            case "fs_volumes":
                ipc.volumesReceived(msg.payload);
                break;
            case "greeter_info":
                ipc.greeterInfoReceived(msg.payload);
                break;
            case "gestori_accesso":
                ipc.gestoriAccessoReceived(msg.payload);
                break;
            case "radice_stato":
                ipc.radiceStato(msg.payload);
                break;
            case "radice_permesso":
                ipc.radicePermesso(msg.payload);
                break;
            case "radice_elenco":
                ipc.radiceElenco(msg.payload);
                break;
            case "radice_testo":
                ipc.radiceTesto(msg.payload);
                break;
            case "radice_esito":
                ipc.radiceEsito(msg.payload);
                break;
            case "manutenzione_escluse":
                ipc.manutenzioneEscluse(msg.payload);
                break;
            case "manutenzione_doppioni":
                ipc.manutenzioneDoppioni(msg.payload);
                break;
            case "manutenzione_doppioni_tolti":
                ipc.manutenzioneDoppioniTolti(msg.payload);
                break;
            case "manutenzione_orfani":
                ipc.manutenzioneOrfaniTolti(msg.payload);
                break;
            case "manutenzione_pulito":
                ipc.manutenzionePulito(msg.payload);
                break;
            case "manutenzione_passo":
                ipc.manutenzionePasso(msg.payload);
                break;
            case "manutenzione_inventario":
                ipc.manutenzioneInventario(msg.payload);
                break;
            case "fucina_guardo":
                ipc.fucinaGuardo(msg.payload);
                break;
            case "fucina_rilievo":
                ipc.fucinaRilievo(msg.payload);
                break;
            case "fucina_versioni":
                ipc.fucinaVersioni(msg.payload);
                break;
            case "fucina_ricetta":
                ipc.fucinaRicetta(msg.payload);
                break;
            case "fucina_avviata":
                ipc.fucinaAvviata(msg.payload);
                break;
            case "fucina_passo":
                ipc.fucinaPasso(msg.payload);
                break;
            case "fucina_righe":
                ipc.fucinaRighe(msg.payload);
                break;
            case "fucina_avanzamento":
                ipc.fucinaAvanzamento(msg.payload);
                break;
            case "fucina_fatto":
                ipc.fucinaFatto(msg.payload);
                break;
            case "fucina_fermata":
                ipc.fucinaFermata(msg.payload);
                break;
            case "fucina_stato":
                ipc.fucinaStato(msg.payload);
                break;
            case "fucina_kernel":
                ipc.fucinaKernel(msg.payload);
                break;
            case "fucina_installato":
                ipc.fucinaInstallato(msg.payload);
                break;
            case "fucina_tolto":
                ipc.fucinaTolto(msg.payload);
                break;
            case "fucina_verifica":
                ipc.fucinaVerifica(msg.payload);
                break;
            case "fucina_profilato":
                ipc.fucinaProfilato(msg.payload);
                break;
            case "custodia_panoramica":
                ipc.custodiaPanoramica(msg.payload);
                break;
            case "custodia_dettaglio":
                ipc.custodiaDettaglio(msg.payload);
                break;
            case "custodia_esito":
                ipc.custodiaEsito(msg.payload);
                break;
            case "custodia_github":
                ipc.custodiaGithub(msg.payload);
                break;
            case "account":
                ipc.accountElenco(msg.payload);
                break;
            case "account_esito":
                ipc.accountEsito(msg.payload);
                break;
            case "account_dettaglio":
                ipc.accountDettaglio(msg.payload);
                break;
            case "account_google_apri":
                ipc.accountApriGoogle(msg.payload);
                break;
            case "greeter_message":
                ipc.greeterMessage(msg.payload);
                break;
            case "fs_places":
                ipc.placesReceived(msg.payload);
                break;
            case "autostart_list":
                ipc.autostartReceived(msg.payload.voci || []);
                break;
            case "datetime_state":
                ipc.datetimeStateReceived(msg.payload);
                break;
            case "datetime_zones":
                ipc.datetimeZonesReceived(msg.payload.fusi || []);
                break;
            case "datetime_result":
                ipc.datetimeResult(msg.payload);
                break;
            case "locale_state":
                ipc.localeStateReceived(msg.payload);
                break;
            case "weather_places":
                ipc.weatherPlaces(msg.payload.luoghi || []);
                break;
            case "weather":
                ipc.weatherReceived(msg.payload || ({}));
                break;
            case "locale_result":
                ipc.localeResult(msg.payload);
                break;
            case "fs_conflitti":
                ipc.conflittiRicevuti((msg.payload && msg.payload.nomi) || []);
                break;
            case "fs_formats":
                ipc.formatsReceived(msg.payload.formati || []);
                break;
            case "mime_described":
                ipc.mimeDescribed(msg.payload);
                break;
            case "mime_categories":
                ipc.mimeCategoriesReceived(msg.payload.categories || [],
                                           msg.payload.famiglie || []);
                break;
            }
        }
    } }

    // Il demone può partire dopo la shell, o essere riavviato a mano:
    // ritentiamo finché non risponde.
    //
    // ── I PRIMI TENTATIVI SONO FITTI ─────────────────────────────────────
    //
    // L'intervallo era fisso a 2 secondi, e all'avvio quei 2 secondi si
    // vedevano tutti. La shell parte quasi sempre PRIMA del demone: il primo
    // tentativo cade nel vuoto, e da lì in poi non si riprova per due secondi
    // interi — anche se il demone è pronto dopo centocinquanta millisecondi
    // (misurato il 10 agosto 2026: la porta si apre in 156 ms).
    //
    // Dove si vedeva peggio: nella schermata di accesso. Il nome dell'utente
    // arrivava dopo circa tre secondi, su una schermata che era già tutta
    // disegnata — Giacomo: «prima di uscire il nome utente passano intorno ai
    // 3 secondi».
    //
    // Adesso si comincia a 120 ms e si raddoppia fino a 2 secondi: chi parte
    // insieme al demone lo aggancia quasi subito, e chi aspetta un demone che
    // non c'è non consuma la macchina a bussare.
    readonly property int _attesaMinima: 120
    readonly property int _attesaMassima: 2000

    /// ── E il raddoppio NON vale al primo aggancio ────────────────────────
    ///
    /// All'accesso la shell e il demone partono insieme, e la shell è più
    /// svelta: Qt più il nostro QML sono mezzo secondo, il demone ce ne mette
    /// due o tre — di più se i sorgenti sono più recenti del compilato e il
    /// guardiano ripiega su `dart run`.
    ///
    /// Col raddoppio, in quei secondi la shell smette di bussare: 120, 240,
    /// 480, 960, 1920 — a tre secondi e sette decimi ha appena provato, e la
    /// prossima volta che ci prova è a cinque e sette. Misurato sul registro
    /// della sessione del 31 agosto 2026: la dock compariva a **4,666
    /// secondi**, e quasi due erano soltanto attesa fra un tentativo e
    /// l'altro. È la metà buona dei «dieci secondi per avviarsi» di Giacomo;
    /// l'altra metà era `dart run` (1965 ms contro 162, misurati).
    ///
    /// Quindi: finché non ci si è **mai** agganciati, e solo per i primi
    /// secondi di vita del processo, si bussa sempre al ritmo minimo. Bussare
    /// a un socket che non c'è costa una `connect()` fallita — niente.
    ///
    /// La ragione del raddoppio resta intatta per il caso che l'ha fatto
    /// scrivere: una nostra finestra aperta dove il demone NON c'è, che
    /// altrimenti busserebbe otto volte al secondo per sempre. Dopo questa
    /// finestra il raddoppio riprende esattamente come prima.
    ///
    /// ── Perché sei secondi, e non dodici ─────────────────────────────────
    ///
    /// Perché ogni tentativo fallito lascia una riga nel registro
    /// (`quickshell.io.socket: ServerNotFoundError`), e quella riga la scrive
    /// Quickshell: da qui non si può zittire. A otto tentativi al secondo,
    /// dodici secondi sono cento righe — e una nostra finestra aperta dove il
    /// demone non c'è le farebbe tutte e cento, ogni volta.
    ///
    /// Sarebbe esattamente il difetto che si è appena tolto dal demone: un
    /// registro fatto di rumore non lo legge più nessuno.
    ///
    /// Sei secondi bastano con margine. Il demone compilato è pronto in 162 ms
    /// dal lancio, interpretato in 1965: anche nel caso peggiore ci si sta
    /// dentro tre volte. E se un giorno ci mettesse di più non si torna al
    /// punto di partenza — il raddoppio riparte da 120 ms, non da dove era
    /// arrivato.
    readonly property int _senzaFrettaDopo: 6000

    /// Quando è nato questo processo. Non l'ora del giorno: serve solo a
    /// misurare una distanza, e `Date.now()` va bene per quello.
    readonly property double _nato: Date.now()

    /// Quanto si concede al demone per rispondere al saluto prima di
    /// considerare morta una connessione che si dice aperta. Tre secondi: il
    /// giro di andata e ritorno vero è di millisecondi, e il demone si dà
    /// cinque secondi per buttare fuori chi non saluta — restare sotto quel
    /// limite vuol dire che a rinunciare siamo noi, non lui.
    readonly property int _attesaSaluto: 3000

    /// Quando il socket si è aperto, in millisecondi. Serve solo a dare a una
    /// connessione appena nata il tempo di finire il saluto.
    property double _apertoDa: 0

    property Timer _reconnectTimer: Timer {
        id: reconnectTimer
        interval: ipc._attesaMinima
        repeat: true
        onTriggered: {
            // ── CI SI FERMA QUANDO IL DEMONE HA RISPOSTO ─────────────────
            //
            // Qui c'era `if (!socket.connected) … else stop()`, e quel `stop()`
            // è costato a Giacomo una scrivania senza dock e senza menù per
            // tutta la mattina del 31 agosto 2026.
            //
            // `socket.connected` dice che una connessione è stata CHIESTA, non
            // che è riuscita. Il demone moriva, il guardiano lo rimetteva in
            // piedi dopo un secondo, e in quel secondo il timer bussava a un
            // socket che non c'era ancora: la richiesta bastava a far leggere
            // vero a `connected`, il giro dopo si prendeva il ramo `else`, e il
            // timer si spegneva **per sempre**. Nel registro restava una sola
            // riga — `ServerNotFoundError` — e poi il silenzio, con il demone
            // vivo e in ascolto dall'altra parte.
            //
            // L'unico segno che si è davvero dentro è la risposta al saluto, e
            // il posto dove fermarsi è quello: il caso `"ciao"` più sopra.
            if (ipc._salutato && ipc._aperto) {
                reconnectTimer.stop();
                return;
            }

            // ── Una connessione appena aperta ha diritto di finire ────────
            //
            // Fra l'apertura del socket e il «ciao» del demone c'è un giro di
            // andata e ritorno. Il timer scatta dopo 120 ms: senza questa
            // attesa butterebbe giù proprio la connessione che sta per
            // riuscire, e su una macchina carica non se ne chiuderebbe mai
            // nessuna — un guasto che si vede solo quando c'è fretta.
            if (ipc._aperto
                && (Date.now() - ipc._apertoDa) < ipc._attesaSaluto)
                return;

            // Vedi `_senzaFrettaDopo`: nei primi secondi, e solo se non ci
            // si è mai agganciati, si bussa al ritmo minimo. È il caso
            // dell'accesso, dove il demone sta nascendo e l'attesa lunga si
            // vede come una scrivania che ci mette secondi a completarsi.
            var appenaNati = !ipc._eraConnesso
                && (Date.now() - ipc._nato) < ipc._senzaFrettaDopo;
            if (!appenaNati && reconnectTimer.interval < ipc._attesaMassima) {
                reconnectTimer.interval = Math.min(
                    ipc._attesaMassima, reconnectTimer.interval * 2);
            }
            ipc._rinnova();
        }
    }
}
