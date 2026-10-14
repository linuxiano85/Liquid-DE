import QtQuick
import Quickshell
import Quickshell.Io

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Posta — il client di posta di Liquid DE.
//
// La finestra non parla con i server di posta: lo fa il demone liquid-maild
// (posta/daemon), che sincronizza, legge, sanifica, filtra e spedisce. Qui
// c'è solo quello che si vede, e le richieste al demone (vedi Canale.qml e
// posta/proto/api.md).
FloatingWindow {
    id: finestra

    visible: Core.Ipc.prontoADipingere && !finestra.dormiente
    property bool dormiente: false
    signal requestClose()
    onClosed: finestra.requestClose()

    // Il titolo è anche il modo in cui dock e Alt+Tab riconoscono la finestra
    // (vedi core/Apps.qml, ownApps): non va cambiato senza cambiare anche là.
    title: "Minerva · Posta"
    color: Theme.Colors.window
    implicitWidth: 1180
    implicitHeight: 760
    minimumSize: Qt.size(760, 480)

    // ── Stato ────────────────────────────────────────────────────────
    property var accounts: []
    property var stati: ({})
    property var cartelle: []
    property int cartella: -1
    property string ricerca: ""
    property var messaggi: []
    property var prossima: null
    property bool caricando: false
    property int aperto: -1
    property var dettaglio: null
    property bool aprendo: false
    property bool immaginiRemote: false
    property var filtro: ({})
    property bool nuovoAccount: false
    /// Indirizzo da proporre in NuovoAccount (rientro con Google).
    property string nuovoIndirizzo: ""
    property bool _nuovoPerchéVuoto: false
    property var bozza: null
    property string avviso: ""
    property bool avvisoBuono: true

    readonly property bool sincronizzando: {
        for (var k in finestra.stati) {
            var p = finestra.stati[k].phase;
            if (p === "connecting" || p === "syncing") return true;
        }
        return false;
    }

    function dice(testo, buono) {
        finestra.avviso = testo || "";
        finestra.avvisoBuono = buono !== false;
        scadenza.restart();
    }
    Timer { id: scadenza; interval: 7000; onTriggered: finestra.avviso = "" }

    function _errore(err) {
        var r = err && err.data ? err.data.reason : "";
        if (r === "offline") return "Server non raggiungibile: riprova tra poco.";
        return err && err.message ? err.message : "Operazione non riuscita.";
    }

    Canale {
        id: linea
        onCollegato: finestra.ricaricaTutto()
        onEvento: function (metodo, p) { finestra._evento(metodo, p); }
    }
    readonly property alias canale: linea

    // ── Caricamenti ──────────────────────────────────────────────────
    function ricaricaTutto() {
        linea.chiama("account.list", {}, function (l) {
            finestra.accounts = l;
            // Aperta perché non giaPresenteno account, e ora uno c'è (aggiunto
            // altrove, o il servizio è ripartito): la procedura si chiude.
            // Se l'ha aperta l'utente con "Aggiungi un account", resta.
            if (l.length === 0) {
                finestra.nuovoAccount = true;
                finestra._nuovoPerchéVuoto = true;
            } else if (finestra._nuovoPerchéVuoto) {
                finestra.nuovoAccount = false;
                finestra._nuovoPerchéVuoto = false;
            }
            if (l.length > 0 && finestra._bozzaInAttesa !== null) {
                finestra.bozza = finestra._bozzaInAttesa;
                finestra._bozzaInAttesa = null;
            }
        });
        linea.chiama("sync.status", {}, function (l) {
            var s = {};
            for (var i = 0; i < l.length; i++) s[l[i].accountId] = l[i];
            finestra.stati = s;
        });
        finestra.ricaricaFiltro();
        finestra.ricaricaCartelle();
    }

    function ricaricaFiltro() {
        linea.chiama("filter.status", {}, function (f) { finestra.filtro = f; });
    }

    function ricaricaCartelle() {
        linea.chiama("folder.list", {}, function (l) {
            finestra.cartelle = l;
            var esiste = l.some(function (f) { return f.id === finestra.cartella; });
            if (!esiste) {
                var inbox = l.filter(function (f) { return f.role === "inbox"; });
                if (inbox.length > 0) finestra.scegliCartella(inbox[0].id);
            }
        });
    }

    function scegliCartella(id) {
        finestra.ricerca = "";
        finestra.cartella = id;
        finestra.ricaricaLista();
    }

    function ricaricaLista() {
        if (finestra.ricerca !== "") { finestra.cerca(finestra.ricerca); return; }
        if (finestra.cartella < 0) return;
        finestra.caricando = true;
        var c = finestra.cartella;
        linea.chiama("message.list", { "folderId": c, "limit": 100 }, function (r) {
            if (c !== finestra.cartella || finestra.ricerca !== "") return;
            finestra.caricando = false;
            finestra.messaggi = r.messages;
            finestra.prossima = r.next;
        }, function (err) { finestra.caricando = false; });
    }

    function altri() {
        if (!finestra.prossima || finestra.caricando || finestra.ricerca !== "") return;
        finestra.caricando = true;
        var c = finestra.cartella;
        linea.chiama("message.list", { "folderId": c, "limit": 100, "cursor": finestra.prossima }, function (r) {
            finestra.caricando = false;
            if (c !== finestra.cartella) return;
            finestra.messaggi = finestra.messaggi.concat(r.messages);
            finestra.prossima = r.next;
        }, function (err) { finestra.caricando = false; });
    }

    function cerca(q) {
        finestra.ricerca = String(q).trim();
        if (finestra.ricerca === "") { finestra.ricaricaLista(); return; }
        var cercato = finestra.ricerca;
        linea.chiama("message.search", { "query": cercato, "limit": 200 }, function (l) {
            if (cercato !== finestra.ricerca) return;
            finestra.messaggi = l;
            finestra.prossima = null;
        });
    }

    function apri(id) {
        finestra.bozza = null;
        finestra.aperto = id;
        finestra.immaginiRemote = false;
        finestra.aprendo = true;
        finestra.dettaglio = null;
        linea.chiama("message.get", { "id": id }, function (m) {
            if (finestra.aperto !== id) return;
            finestra.aprendo = false;
            finestra.dettaglio = m;
            if (!m.seen) {
                finestra._cambiaInLista(id, { "seen": true });
                linea.chiama("message.setFlags", { "ids": [id], "seen": true }, function () {
                    finestra.ricaricaCartelleSoft();
                });
            }
        }, function (err) {
            finestra.aprendo = false;
            finestra.dice(finestra._errore(err), false);
        });
    }

    /// Solo i conteggi delle cartelle, senza toccare la scelta.
    function ricaricaCartelleSoft() {
        linea.chiama("folder.list", {}, function (l) { finestra.cartelle = l; });
    }

    function _cambiaInLista(id, campi) {
        var l = finestra.messaggi.slice();
        for (var i = 0; i < l.length; i++) {
            if (l[i].id === id) {
                var copia = Object.assign({}, l[i], campi);
                l[i] = copia;
                finestra.messaggi = l;
                return;
            }
        }
    }

    function _togliDaLista(id) {
        var l = finestra.messaggi;
        var i = l.findIndex(function (m) { return m.id === id; });
        finestra.messaggi = l.filter(function (m) { return m.id !== id; });
        // Si apre il successivo, come in tutti i client: si legge di fila.
        var prossimo = finestra.messaggi[Math.min(i, finestra.messaggi.length - 1)];
        finestra.dettaglio = null;
        finestra.aperto = -1;
        if (prossimo) finestra.apri(prossimo.id);
    }

    function _evento(metodo, p) {
        if (metodo === "event.sync.state") {
            var s = Object.assign({}, finestra.stati);
            s[p.accountId] = p;
            finestra.stati = s;
        } else if (metodo === "event.folders.changed" || metodo === "event.mail.changed") {
            var cartelle = p.folderIds || [p.folderId];
            finestra.ricaricaCartelleSoft();
            if (finestra.ricerca === "" && cartelle.indexOf(finestra.cartella) >= 0)
                finestra.ricaricaLista();
            if (p.reset) finestra.ricaricaCartelle();
            finestra.ricaricaFiltro();
        }
    }

    // ── Azioni sul messaggio aperto ──────────────────────────────────
    function haCartella(ruolo) {
        var m = finestra.dettaglio;
        if (!m) return false;
        return finestra.cartelle.some(function (f) { return f.accountId === m.accountId && f.role === ruolo; });
    }

    function segna(campi) {
        var m = finestra.dettaglio;
        if (!m) return;
        var p = Object.assign({ "ids": [m.id] }, campi);
        finestra._cambiaInLista(m.id, campi);
        finestra.dettaglio = Object.assign({}, m, campi);
        linea.chiama("message.setFlags", p, function () { finestra.ricaricaCartelleSoft(); },
                      function (err) { finestra.dice(finestra._errore(err), false); finestra.ricaricaLista(); });
    }

    function archivia() {
        var m = finestra.dettaglio;
        if (!m) return;
        linea.chiama("message.archive", { "ids": [m.id] }, function () {
            finestra._togliDaLista(m.id);
            finestra.dice("Archiviato.", true);
        }, function (err) { finestra.dice(finestra._errore(err), false); });
    }

    function elimina() {
        var m = finestra.dettaglio;
        if (!m) return;
        var perSempre = m.folderRole === "trash";
        linea.chiama("message.delete", { "ids": [m.id] }, function () {
            finestra._togliDaLista(m.id);
            finestra.dice(perSempre ? "Eliminato per sempre." : "Spostato nel Cestino.", true);
        }, function (err) { finestra.dice(finestra._errore(err), false); });
    }

    function pubblicita(si) {
        var m = finestra.dettaglio;
        if (!m) return;
        linea.chiama("filter.train", { "messageId": m.id, "isAd": si }, function () {
            finestra.ricaricaFiltro();
            if (si) {
                finestra.elimina();
                finestra.dice("Nel Cestino: il filtro ha imparato che è pubblicità.", true);
            } else {
                finestra._cambiaInLista(m.id, { "adMarked": false });
                finestra.dettaglio = Object.assign({}, m, { "adMarked": false });
                finestra.dice("Va bene: il filtro ha imparato che non è pubblicità.", true);
            }
        }, function (err) { finestra.dice(finestra._errore(err), false); });
    }

    function mostraImmagini() {
        var m = finestra.dettaglio;
        if (!m) return;
        linea.chiama("message.get", { "id": m.id, "allowRemoteImages": true }, function (x) {
            if (finestra.aperto !== m.id) return;
            finestra.immaginiRemote = true;
            finestra.dettaglio = x;
        });
    }

    function modoFiltro(modo) {
        linea.chiama("filter.setMode", { "mode": modo }, function () { finestra.ricaricaFiltro(); });
    }

    // ── Allegati ─────────────────────────────────────────────────────
    property FileView _cartelleUtente: FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/user-dirs.dirs"
        printErrors: false
    }
    function cartellaScaricati() {
        var casa = String(Quickshell.env("HOME") || "");
        var testo = "";
        try { testo = String(finestra._cartelleUtente.text()); } catch (e) {}
        var m = /XDG_DOWNLOAD_DIR="([^"]+)"/.exec(testo);
        return m ? m[1].replace("$HOME", casa) : casa + "/Scaricati";
    }

    function salvaAllegato(a, eApri) {
        var dove = eApri
            ? String(Quickshell.env("XDG_RUNTIME_DIR")) + "/liquid-mail/aperti/" + a.id + "-" + a.filename
            : finestra.cartellaScaricati() + "/" + a.filename;
        finestra._salva(a, dove, eApri, 1);
    }

    function _salva(a, dove, eApri, n) {
        var punto = dove.lastIndexOf(".");
        var barra = dove.lastIndexOf("/");
        var nome = n === 1 ? dove
                 : (punto > barra ? dove.substring(0, punto) + " (" + n + ")" + dove.substring(punto)
                                  : dove + " (" + n + ")");
        linea.chiama("attachment.save", { "id": a.id, "path": nome }, function (r) {
            if (eApri) Qt.openUrlExternally("file://" + r.path);
            else finestra.dice("Salvato in " + r.path, true);
        }, function (err) {
            var motivo = err && err.data ? err.data.reason : "";
            if (motivo === "exists" && eApri) { Qt.openUrlExternally("file://" + nome); return; }
            if (motivo === "exists" && n < 50) { finestra._salva(a, dove, eApri, n + 1); return; }
            finestra.dice(finestra._errore(err), false);
        });
    }

    // ── Scrivere ─────────────────────────────────────────────────────
    function accountPerScrivere() {
        if (finestra.dettaglio) return finestra.dettaglio.accountId;
        var c = finestra.cartelle.filter(function (f) { return f.id === finestra.cartella; });
        if (c.length > 0) return c[0].accountId;
        return finestra.accounts.length > 0 ? finestra.accounts[0].id : -1;
    }
    function indirizzoPerScrivere() {
        var id = finestra.accountPerScrivere();
        var a = finestra.accounts.filter(function (x) { return x.id === id; });
        return a.length > 0 ? a[0].email : "";
    }

    /// Un `mailto:` arrivato prima che ci fosse un account: si scrive appena
    /// l'account è aggiunto, invece di perderlo.
    property var _bozzaInAttesa: null

    function scrivi(bozza) {
        if (finestra.accounts.length === 0) {
            finestra._bozzaInAttesa = bozza || {};
            finestra.nuovoAccount = true;
            return;
        }
        finestra.bozza = bozza || {};
    }

    function _data(ms) {
        return new Date(ms).toLocaleString(Qt.locale(Core.Strings.lang === "it" ? "it_IT" : "en_GB"),
                                           "d MMMM yyyy, HH:mm");
    }

    function _citazione(m) {
        var testo = String(m.text || "").replace(/\r\n/g, "\n");
        var righe = testo.split("\n").map(function (r) { return "> " + r; }).join("\n");
        var chi = m.fromName ? m.fromName + " <" + m.fromAddress + ">" : m.fromAddress;
        return "\n\n" + finestra._data(m.date) + ", " + chi + " ha scritto:\n" + righe;
    }

    function rispondi(tutti) {
        var m = finestra.dettaglio;
        if (!m) return;
        var mio = finestra.indirizzoPerScrivere().toLowerCase();
        var a = [m.fromAddress];
        var cc = [];
        if (tutti) {
            (m.to || []).concat(m.cc || []).forEach(function (x) {
                if (x && x.toLowerCase() !== mio && a.indexOf(x) < 0 && cc.indexOf(x) < 0) cc.push(x);
            });
        }
        var oggetto = String(m.subject || "");
        if (!/^re:/i.test(oggetto)) oggetto = "Re: " + oggetto;
        finestra.scrivi({ "to": a, "cc": cc, "subject": oggetto, "text": finestra._citazione(m), "replyToId": m.id });
    }

    function inoltra() {
        var m = finestra.dettaglio;
        if (!m) return;
        var oggetto = String(m.subject || "");
        if (!/^(fwd?|i):/i.test(oggetto)) oggetto = "I: " + oggetto;
        var testa = "\n\n---------- Messaggio inoltrato ----------\nDa: "
                  + (m.fromName ? m.fromName + " <" + m.fromAddress + ">" : m.fromAddress)
                  + "\nData: " + finestra._data(m.date)
                  + "\nOggetto: " + (m.subject || "") + "\nA: " + (m.to || []).join(", ") + "\n\n";
        finestra.scrivi({ "subject": oggetto, "text": testa + String(m.text || "") });
    }

    /// `mailto:indirizzo?subject=…&body=…&cc=…` dal resto del sistema.
    function apriMailto(url) {
        var s = String(url).replace(/^mailto:/i, "");
        var q = s.indexOf("?");
        var a = decodeURIComponent(q < 0 ? s : s.substring(0, q));
        var b = { "to": a === "" ? [] : a.split(",") };
        if (q >= 0) {
            s.substring(q + 1).split("&").forEach(function (coppia) {
                var i = coppia.indexOf("=");
                if (i < 0) return;
                var k = coppia.substring(0, i).toLowerCase();
                var v = decodeURIComponent(coppia.substring(i + 1).replace(/\+/g, " "));
                // Solo questi: `attach` e simili non si accettano MAI da un link.
                if (k === "subject") b.subject = v;
                else if (k === "body") b.text = v;
                else if (k === "cc") b.cc = v.split(",");
            });
        }
        finestra.scrivi(b);
    }

    // ── Disegno ──────────────────────────────────────────────────────
    Ui.WindowTitleBar {
        id: barra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: "Posta"
        onCloseRequested: finestra.requestClose()
    }

    Rectangle {
        id: nastro
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: finestra.avviso !== "" || linea.problema !== "" ? 34 : 0
        clip: true
        color: Qt.alpha(finestra.avviso !== "" && finestra.avvisoBuono ? Theme.Colors.positive : Theme.Colors.danger, 0.13)
        Behavior on height { NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic } }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.Effects.space4
            width: parent.width - x * 2
            elide: Text.ElideRight
            text: finestra.avviso !== "" ? finestra.avviso : linea.problema
            color: finestra.avviso !== "" && finestra.avvisoBuono ? Theme.Colors.positive : Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    Item {
        id: corpo
        anchors.top: nastro.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Colonna {
            id: colonna
            posta: finestra
            visible: !finestra.nuovoAccount || finestra.accounts.length > 0
            width: visible ? 240 : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }
        Lista {
            id: lista
            posta: finestra
            visible: colonna.visible
            anchors.left: colonna.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: visible ? Math.max(300, Math.min(420, corpo.width * 0.32)) : 0
        }
        Lettore {
            posta: finestra
            visible: colonna.visible && finestra.bozza === null
            anchors.left: lista.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }
        Loader {
            id: componi
            active: finestra.bozza !== null
            anchors.left: lista.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            sourceComponent: Componi {
                posta: finestra
                bozza: finestra.bozza || {}
                onChiuso: finestra.bozza = null
                onScegliAllegato: selettore.apri("")
            }
        }

        // Prima volta (o "Aggiungi un account"): tutta la finestra.
        Rectangle {
            anchors.fill: parent
            visible: finestra.nuovoAccount
            color: Theme.Colors.window
            NuovoAccount {
                anchors.fill: parent
                canale: linea
                annullabile: finestra.accounts.length > 0
                indirizzo: finestra.nuovoIndirizzo
                onAnnullato: { finestra.nuovoAccount = false; finestra.nuovoIndirizzo = ""; }
                onAggiunto: function (acc) {
                    finestra.nuovoAccount = false;
                    finestra.nuovoIndirizzo = "";
                    // Un account che giaPresente già (passato a «Accedi con Google»)
                    // torna con lo stesso id: si sostituisce, non si duplica.
                    var giaPresente = finestra.accounts.some(function (a) { return a.id === acc.id; });
                    finestra.dice(giaPresente ? "Fatto: ora " + acc.email + " entra con Google."
                                        : "Account aggiunto: scarico la posta degli ultimi 30 giorni…", true);
                    finestra.accounts = finestra.accounts.filter(function (a) { return a.id !== acc.id; })
                                                         .concat([acc]);
                    finestra.ricaricaTutto();
                    if (finestra._bozzaInAttesa !== null) {
                        finestra.bozza = finestra._bozzaInAttesa;
                        finestra._bozzaInAttesa = null;
                    }
                }
            }
        }

        Ui.Scegli {
            id: selettore
            anchors.fill: parent
            soloCartelle: false
            titolo: "Scegli il file da allegare"
            onScelto: function (percorso) {
                if (componi.item) componi.item.aggiungiAllegato(percorso);
            }
        }
    }
}
