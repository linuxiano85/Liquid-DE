import QtQuick
import QtWebSockets
import Quickshell
import Quickshell.Io

// Canale — la linea fra la finestra Posta e il demone liquid-maild.
//
// Il demone ascolta su 127.0.0.1 con WebSocket e JSON-RPC; porta e
// parola d'ordine stanno in `$XDG_RUNTIME_DIR/liquid-mail/{port,token}`,
// leggibili solo da chi usa il computer (vedi posta/proto/api.md).
//
// Se il demone non risponde, il canale lo avvia (lo script esce subito se
// ce n'è già uno: il demone ha il suo lock) e riprova con attese crescenti.
// Chi usa il canale vede `pronto` e chiama `chiama()`; gli eventi del
// demone arrivano come segnale `evento`.
QtObject {
    id: canale

    /// Autenticato: si può chiamare.
    readonly property bool pronto: canale._autenticato
    property bool _autenticato: false

    /// Ultimo problema di collegamento, in parole da mostrare (vuoto se va).
    property string problema: ""

    signal evento(string metodo, var parametri)
    /// Appena autenticato (anche dopo una riconnessione): ricaricare tutto.
    signal collegato()

    readonly property string _cartella: {
        var r = Quickshell.env("XDG_RUNTIME_DIR");
        return r ? r + "/liquid-mail" : "";
    }
    readonly property string _avvio: Quickshell.shellDir + "/../scripts/minerva-posta-demone"

    property int _prossimoId: 1
    property var _attese: ({})
    property int _tentativi: 0
    property bool _avviatoDaNoi: false

    property FileView _porta: FileView {
        path: canale._cartella !== "" ? canale._cartella + "/port" : ""
        printErrors: false
    }
    property FileView _gettone: FileView {
        path: canale._cartella !== "" ? canale._cartella + "/token" : ""
        printErrors: false
    }

    property WebSocket _ws: WebSocket {
        active: false
        onStatusChanged: function (stato) {
            if (stato === WebSocket.Open) {
                canale._invia({ "jsonrpc": "2.0", "id": 0, "method": "auth",
                                "params": { "token": canale._token } });
            } else if (stato === WebSocket.Error || stato === WebSocket.Closed) {
                canale._caduto();
            }
        }
        onTextMessageReceived: function (testo) { canale._ricevi(testo); }
    }

    property string _token: ""

    property Timer _riprova: Timer {
        repeat: false
        onTriggered: canale.collega()
    }

    /// Rilegge porta e parola d'ordine e si collega.
    function collega() {
        if (canale._cartella === "") {
            canale.problema = "XDG_RUNTIME_DIR non impostata";
            return;
        }
        canale._porta.reload();
        canale._gettone.reload();
        var porta = parseInt(String(canale._porta.text()).trim());
        var token = String(canale._gettone.text()).trim();
        if (!porta || token === "") {
            canale._avviaDemone();
            canale._attendi();
            return;
        }
        // Porta e parola d'ordine possono essere di un servizio appena morto
        // (file non ancora tolti): se il collegamento fallisce, `_caduto`
        // riavvia e riprova.
        canale._token = token;
        canale._ws.active = false;
        canale._ws.url = "ws://127.0.0.1:" + porta;
        canale._ws.active = true;
    }

    function _avviaDemone() {
        // Una volta per caduta: il demone, se c'è già, esce subito da solo.
        if (canale._avviatoDaNoi) return;
        canale._avviatoDaNoi = true;
        Quickshell.execDetached([canale._avvio]);
    }

    function _attendi() {
        canale._tentativi++;
        // Ogni tre tentativi si riprova anche ad AVVIARE il servizio: se il
        // vecchio stava ancora chiudendo (fino a qualche secondo, per salutare
        // i server), il primo riavvio ha trovato il lock preso ed è uscito.
        // Riprovare non fa danni: il lock lascia passare un solo servizio.
        if (canale._tentativi % 3 === 0)
            canale._avviatoDaNoi = false;
        // 0,3 s, 0,6 s, 1,2 s... fino a 10 s: il primo avvio del demone
        // (database, portachiavi) richiede un attimo.
        canale._riprova.interval = Math.min(10000, 300 * Math.pow(2, Math.min(canale._tentativi, 6)));
        canale._riprova.restart();
        if (canale._tentativi > 4)
            canale.problema = "Il servizio della posta non risponde: nuovo tentativo…";
    }

    function _caduto() {
        var eraPronto = canale._autenticato;
        canale._autenticato = false;
        // Le chiamate in volo non avranno risposta: lo si dice subito a chi
        // aspetta, invece di lasciare un indicatore che gira per sempre.
        var attese = canale._attese;
        canale._attese = ({});
        for (var k in attese) {
            if (attese[k].errore)
                attese[k].errore({ "code": -1, "message": "Collegamento al servizio della posta perso",
                                   "data": { "reason": "offline" } });
        }
        if (eraPronto) {
            canale._avviatoDaNoi = false;
            canale._tentativi = 0;
        }
        canale._avviaDemone();
        canale._attendi();
    }

    function _invia(oggetto) {
        canale._ws.sendTextMessage(JSON.stringify(oggetto));
    }

    function _ricevi(testo) {
        var m;
        try { m = JSON.parse(testo); } catch (e) { return; }
        if (m.id === 0) {
            if (m.result && m.result.ok) {
                canale._autenticato = true;
                canale._tentativi = 0;
                canale._avviatoDaNoi = false;
                canale.problema = "";
                canale.collegato();
            } else {
                // Parola d'ordine vecchia: il demone è ripartito, si rilegge.
                canale._ws.active = false;
                canale._attendi();
            }
            return;
        }
        if (m.id === undefined || m.id === null) {
            if (m.method) canale.evento(m.method, m.params);
            return;
        }
        var a = canale._attese[m.id];
        if (!a) return;
        delete canale._attese[m.id];
        if (m.error) {
            if (a.errore) a.errore(m.error);
        } else if (a.risposta) {
            a.risposta(m.result);
        }
    }

    /// Chiama un metodo del demone. `risposta(result)` o `errore(error)`
    /// con `error.data.reason` quando il demone dà un motivo.
    function chiama(metodo, parametri, risposta, errore) {
        if (!canale._autenticato) {
            if (errore) errore({ "code": -1, "message": "Servizio della posta non collegato",
                                 "data": { "reason": "offline" } });
            return;
        }
        var id = canale._prossimoId++;
        canale._attese[id] = { "risposta": risposta, "errore": errore };
        canale._invia({ "jsonrpc": "2.0", "id": id, "method": metodo, "params": parametri || {} });
    }

    Component.onCompleted: canale.collega()
}
