pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.Notifications
import "." as Core

// Notifications — La coda delle notifiche, unica per tutta la sessione.
//
// Il server DBus sta qui e non dentro un pannello, per un motivo pratico:
// i pannelli vengono creati e distrutti a ogni apertura, e con loro sparirebbe
// la cronologia. Le notifiche arrivate mentre il pannello era chiuso — cioè
// quasi tutte — non esisterebbero.
//
// `items` è un array JavaScript e non un ListModel: le voci vengono lette e
// mai modificate sul posto, e un array si sostituisce in blocco senza doversi
// preoccupare di indici che cambiano mentre una vista lo sta scorrendo.
QtObject {
    id: notifications

    /// Notifiche ricevute, dalla più vecchia alla più recente.
    property var items: []

    /// Ricevute e non ancora viste dall'utente.
    property int unread: 0

    /// Oltre questo numero le più vecchie vengono scartate: una cronologia
    /// illimitata non serve a nessuno e cresce per sempre.
    readonly property int capacity: 60

    signal arrived(var item)

    /// Una notifica che non viene da un programma ma da Minerva stessa.
    ///
    /// Nasce per le estensioni che si fermano: prima il demone lo diceva solo
    /// al proprio registro, che nessuno legge.
    function daMinerva(sommario, corpo) {
        var item = {
            "id": "minerva-" + Date.now(),
            "appName": "Minerva",
            "summary": sommario,
            "body": corpo,
            "urgency": 1,
            "timeout": 6000,
            "time": Date.now()
        };
        var copy = notifications.items.slice();
        copy.push(item);
        while (copy.length > notifications.capacity)
            copy.shift();
        notifications.items = copy;
        notifications.unread++;
        if (!notifications.inSilenzio)
            notifications.arrived(item);
    }

    property Connections _estensioni: Connections {
        target: Core.Ipc
        function onPluginTerminato(nome, codice) {
            notifications.daMinerva(
                Core.Strings.t("pluginMorto"),
                Core.Strings.t("pluginMortoCorpo").replace("%1", nome));
        }
    }

    // ── Il file di cui parla una notifica ────────────────────────────────
    //
    // Le notifiche NOSTRE riguardano spesso un file: una schermata appena
    // scattata, una copia finita, uno scaricamento. Cliccarle deve aprirlo.
    //
    // Il protocollo delle notifiche non ha un campo «file», quindi si passa da
    // un SUGGERIMENTO — `x-minerva-file` — che mettono i nostri programmi
    // (`scripts/minerva-schermata`). Chi non lo mette non perde niente: si
    // ricade sulle azioni, e se non ce ne sono il clic chiude e basta, come
    // faceva prima.
    //
    // Non si indovina il file dal CORPO del messaggio: un percorso scritto
    // dentro una frase è una cosa che si somiglia, non una cosa che è, e
    // aprire il file sbagliato perché il testo conteneva una barra sarebbe
    // peggio di non aprire niente.
    function fileDi(notif) {
        try {
            var h = notif.hints;
            if (!h)
                return "";
            var v = h["x-minerva-file"];
            return v === undefined || v === null ? "" : String(v);
        } catch (e) {
            return "";
        }
    }

    /// Cosa succede cliccando una notifica. Torna vero se ha fatto qualcosa.
    ///
    /// L'ordine non è casuale: **prima l'azione predefinita del programma**,
    /// perché è quello che il programma ha chiesto che succeda, e solo dopo il
    /// nostro file. Un lettore musicale che manda «apri l'album» sa meglio di
    /// noi cosa vuol dire cliccare la sua notifica.
    function apri(item) {
        if (!item)
            return false;

        var az = item.azioni || [];
        for (var i = 0; i < az.length; i++) {
            // «default» è il nome che il protocollo riserva all'azione del
            // clic sul corpo. Se c'è, è quella.
            if (String(az[i].identifier) === "default") {
                az[i].invoke();
                return true;
            }
        }

        var f = String(item.file || "");
        if (f !== "") {
            // `openDefault` e non un `xdg-open` nostro: se un predefinito non
            // c'è, la risposta lo DICE (`needsChoice`) invece di lasciare il
            // clic senza effetto — ed è la stessa strada del doppio clic nel
            // gestore file, quindi una sola regola per «apri questo».
            Core.Ipc.openDefault([f]);
            return true;
        }

        // Nessuna «default» ma qualche azione: si prende la prima. È la
        // convenzione di tutti i centri notifiche, e l'alternativa — non fare
        // niente avendo un'azione in mano — è la cosa che Giacomo ha
        // segnalato.
        if (az.length > 0) {
            az[0].invoke();
            return true;
        }
        return false;
    }

    /// Come `apri`, ma partendo dall'identificatore.
    ///
    /// Serve a chi tiene un `ListModel` — il toast — che i tipi di QML sa
    /// portarli solo come testo e numeri: un oggetto ci passa dentro e ne esce
    /// diverso, e con lui se ne andrebbe proprio il metodo `invoke()` che
    /// serve. Si porta l'id, e la notifica vera la si ritrova qui.
    function apriPerId(id) {
        var cercato = String(id);
        for (var i = 0; i < notifications.items.length; i++) {
            if (String(notifications.items[i].id) === cercato)
                return notifications.apri(notifications.items[i]);
        }
        return false;
    }

    /// Vero se cliccando succede qualcosa. Chi disegna lo usa per non
    /// promettere un clic che non fa niente — la mano a dito su una notifica
    /// inerte è una promessa falsa.
    function siPuoAprire(item) {
        if (!item)
            return false;
        return (item.azioni || []).length > 0 || String(item.file || "") !== "";
    }

    function markAllRead() {
        notifications.unread = 0;
    }

    function clear() {
        notifications.items = [];
        notifications.unread = 0;
    }

    function remove(index) {
        if (index < 0 || index >= notifications.items.length)
            return;
        var copy = notifications.items.slice();
        copy.splice(index, 1);
        notifications.items = copy;
    }

    /// Silenzio: le notifiche continuano ad arrivare e a essere registrate,
    /// ma non compare nessun avviso a schermo. Spegnere del tutto il server
    /// farebbe perdere ciò che è arrivato mentre era attivo.
    property bool doNotDisturb: false

    /// Silenzio temporaneo, non un'impostazione.
    ///
    /// Lo accende la modalità gioco (`core/Gioco.qml`) quando qualcosa va a
    /// schermo intero, e lo spegne quando finisce. NON passa dal demone di
    /// proposito: un'impostazione scritta resta scritta, e chi ha giocato
    /// mezz'ora si ritroverebbe le notifiche spente per sempre senza sapere
    /// perché — con la levetta del pannello che dice «acceso», per giunta.
    property bool zittitoDalGioco: false

    /// Vero quando una notifica NON deve comparire a schermo. Arriva lo stesso
    /// e finisce nell'elenco: nessuna si perde, solo non interrompono.
    readonly property bool inSilenzio:
        notifications.doNotDisturb || notifications.zittitoDalGioco

    // ── Le notifiche per la schermata di blocco ──────────────────────────
    //
    // Giacomo, 23 settembre 2026: «poter nascondere per privacy parte della
    // notifica, se mi arrivano mail mi dice solo che ci sono ad esempio 3
    // email, tipo come gli smartphone».
    //
    // La schermata di blocco è un ALTRO processo (`blocco.qml`), e le
    // notifiche le riceve questo. Si passano con un file nella cartella della
    // sessione (0700, sparisce allo spegnimento), e il file si scrive GIÀ
    // FILTRATO: con «numero» dentro ci sono solo i nomi dei programmi e
    // quante — il testo di una mail non esce da questo processo, e quindi non
    // può finire sotto gli occhi di nessuno nemmeno per un difetto di chi
    // disegna la schermata di blocco.
    //
    //   «numero»  per programma: «Posta · 3 email», «Telegram · 2 notifiche»
    //   «tutto»   anche il titolo e il testo, come le vedi sulla scrivania
    //   «niente»  il file resta vuoto
    //
    // Quali: quelle arrivate e non ancora viste (`unread`), come sul telefono
    // — quelle già lette nel pannello non si ripetono sul blocco.
    readonly property string bloccoMostra:
        String(Core.Ipc.get("notifications.bloccoMostra", "numero"))

    /// Un programma di posta, dal nome: per dire «3 email» e non «3
    /// notifiche». Solo il nome del programma, mai il contenuto.
    function _diPosta(app) {
        return /thunderbird|evolution|geary|kmail|mailspring|betterbird|posta|mail|gmail|outlook/i
               .test(String(app || ""));
    }

    function _perIlBlocco() {
        var modo = notifications.bloccoMostra;
        var nuove = notifications.unread > 0
                    ? notifications.items.slice(-notifications.unread) : [];
        if (modo === "niente" || nuove.length === 0)
            return { "modo": modo, "gruppi": [], "voci": [] };
        var gruppi = [];
        var dove = {};
        for (var i = nuove.length - 1; i >= 0; i--) {
            var app = String(nuove[i].appName || "Sistema");
            if (dove[app] === undefined) {
                dove[app] = gruppi.length;
                gruppi.push({ "app": app, "quante": 0, "posta": notifications._diPosta(app),
                              "ultima": nuove[i].time || 0 });
            }
            gruppi[dove[app]].quante++;
        }
        var voci = [];
        if (modo === "tutto") {
            for (var j = nuove.length - 1; j >= 0 && voci.length < 8; j--) {
                voci.push({ "app": String(nuove[j].appName || "Sistema"),
                            "posta": notifications._diPosta(nuove[j].appName),
                            "titolo": String(nuove[j].summary || "").substring(0, 120),
                            "testo": String(nuove[j].body || "").substring(0, 240),
                            "quando": nuove[j].time || 0 });
            }
        }
        return { "modo": modo, "gruppi": gruppi, "voci": voci };
    }

    function _scriviPerIlBlocco() {
        if (_fileBlocco.path === "")
            return;
        _fileBlocco.setText(JSON.stringify(notifications._perIlBlocco()));
    }

    property FileView _fileBlocco: FileView {
        path: Core.Ipc.cartellaSessione !== ""
              ? Core.Ipc.cartellaSessione + "/notifiche-blocco.json" : ""
        atomicWrites: true
        printErrors: false
    }

    // Si riscrive quando cambia qualcosa: una notifica nuova, una letta, la
    // scelta della privacy. Un giro dopo, così dieci notifiche arrivate
    // insieme sono una scrittura e non dieci.
    onItemsChanged: _riscriviBlocco.restart()
    onUnreadChanged: _riscriviBlocco.restart()
    onBloccoMostraChanged: _riscriviBlocco.restart()
    property Timer _riscriviBlocco: Timer {
        interval: 200
        onTriggered: notifications._scriviPerIlBlocco()
    }

    property NotificationServer _server: NotificationServer {
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        keepOnReload: true

        onNotification: function(notif) {
            // ── La notifica si TIENE, non se ne copia solo il testo ──────
            //
            // Fino al 2 settembre 2026 qui si costruiva una mappa con sette
            // campi e si buttava via l'oggetto. Il risultato: dichiaravamo ai
            // programmi `actionsSupported: true` — quindi le azioni ce le
            // mandavano davvero — e poi le perdevamo un istante dopo.
            // Cliccando una notifica non succedeva niente, perché non c'era
            // più niente da invocare.
            //
            // Giacomo: «le notifiche quando compaiono devono essere
            // interagibili, ad esempio se scatto uno screenshot e compare la
            // notifica e ci clicco devo poter vedere l'immagine».
            //
            // `tracked` è la riga che la tiene viva: senza, Quickshell
            // considera la notifica finita appena questo gestore ritorna, e
            // l'oggetto muore con tutte le sue azioni. Vale anche a notifica
            // scaduta — resta nell'elenco del pannello, e da lì la si può
            // ancora aprire.
            notif.tracked = true;

            var item = {
                "id": notif.id,
                "appName": notif.appName || "Sistema",
                "summary": notif.summary || "",
                "body": notif.body || "",
                "urgency": notif.urgency || 0,
                "timeout": notif.expireTimeout > 0 ? notif.expireTimeout : 5000,
                "time": Date.now(),
                // L'oggetto vero, per invocare le azioni. Le `actions` non si
                // copiano in una lista nostra: sono oggetti di Quickshell con
                // un metodo `invoke()`, e una copia perderebbe proprio quello.
                "notif": notif,
                "azioni": notif.actions || [],
                // Un file che questa notifica riguarda, se lo dice. Vedi
                // `fileDi()` qui sotto.
                "file": notifications.fileDi(notif)
            };

            var copy = notifications.items.slice();
            copy.push(item);
            while (copy.length > notifications.capacity)
                copy.shift();
            notifications.items = copy;

            notifications.unread++;

            if (!notifications.inSilenzio)
                notifications.arrived(item);
        }
    }
}
