import QtQuick
import "../core" as Core

// Processi — I dati del gestore dei processi, senza disegno.
//
// Stavano dentro `Monitor.qml`, la finestra. Il 28 settembre 2026 Giacomo ha
// scelto che Attività viva ANCHE dentro la shell, come pannello liquido: una
// finestra Qt Quick a sé costa ~69 MB prima di disegnare una riga
// (`minerva-peso-app`), un pannello nella shell solo il suo codice. Due
// posti che mostrano gli stessi processi devono avere UNA logica sola —
// raggruppare, ordinare, la memoria equa, la lista corretta sul posto — o
// il giorno che se ne corregge una, l'altra resta sbagliata.
//
// `attivo` iscrive al demone: si legge `/proc` solo mentre qualcuno guarda.
Item {
    id: dati
    visible: false

    readonly property bool it: Core.Strings.lang === "it"

    /// Vero mentre qualcuno guarda: il demone legge `/proc` solo allora.
    property bool attivo: false
    onAttivoChanged: dati.attivo ? Core.Ipc.subscribeProcesses()
                                 : Core.Ipc.unsubscribeProcesses()
    Component.onCompleted: if (dati.attivo) Core.Ipc.subscribeProcesses()
    Component.onDestruction: if (dati.attivo) Core.Ipc.unsubscribeProcesses()

    // ── I dati ───────────────────────────────────────────────────────────

    property var macchina: ({})
    property var processi: []

    /// Storie per i grafici. Sessanta campioni a due secondi l'uno fanno due
    /// minuti di passato, che è la finestra in cui si riconosce «sta salendo».
    readonly property int storiaMax: 60
    property var storiaCpu: []
    property var storiaMem: []
    property var storiaRete: []
    property var storiaTemp: []

    property string filtro: ""
    /// "app" mostra solo i programmi con una finestra, "tutti" ogni processo.
    property string vista: "app"
    /// In vista «tutti»: mostrare anche i processi del sistema.
    property bool conSistema: false

    /// Quanti processi di sistema si stanno tenendo chiusi.
    readonly property int quantiDiSistema: {
        var n = 0;
        for (var i = 0; i < dati.processi.length; i++)
            if (dati.processi[i].sistema
                && dati.pidConFinestra[dati.processi[i].pid] === undefined)
                n++;
        return n;
    }
    /// "cpu", "memoria" o "nome".
    property string ordine: "cpu"

    /// Il PID su cui il primo «chiudi» non ha funzionato: solo a lui si offre
    /// di terminare a forza.
    property int pidOstinato: -1

    Connections {
        target: Core.Ipc
        function onProcessesReceived(dati) {
            dati.macchina = dati.macchina || ({});
            dati.processi = dati.processi || [];
            dati.aggiungiStorie();
        }
        function onProcessKilled(pid, ok, force) {
            // Se il gentile non ha funzionato, la riga si offre di insistere.
            if (!force)
                dati.pidOstinato = ok ? -1 : pid;
        }
    }

    function aggiungiStorie() {
        var m = dati.macchina;
        dati.storiaCpu = dati.appendi(dati.storiaCpu, m.cpu !== undefined ? m.cpu : 0);
        var memPerc = (m.memoriaTotale > 0)
                      ? (m.memoriaUsata / m.memoriaTotale * 100) : 0;
        dati.storiaMem = dati.appendi(dati.storiaMem, memPerc);
        dati.storiaRete = dati.appendi(dati.storiaRete,
                                             (m.reteGiu || 0) + (m.reteSu || 0));
        if (m.temperatura !== undefined)
            dati.storiaTemp = dati.appendi(dati.storiaTemp, m.temperatura);
    }

    function appendi(storia, valore) {
        var s = storia.slice();
        s.push(valore);
        while (s.length > dati.storiaMax)
            s.shift();
        return s;
    }

    // ── Chi ha una finestra ──────────────────────────────────────────────
    //
    // Il compositore sa il numero di processo di ogni finestra aperta. È
    // l'unico modo onesto di distinguere «un programma che ho aperto io» da
    // «un servizio che gira per conto suo»: il nome non basta — `chrome` è
    // undici processi, e uno solo ha la finestra.
    readonly property var pidConFinestra: {
        var s = {};
        var f = Core.Windows.all || [];
        for (var i = 0; i < f.length; i++)
            if (f[i].pid)
                s[f[i].pid] = f[i].appClass || "";
        return s;
    }

    // ── Una lista che si aggiorna SUL POSTO ──────────────────────────────
    //
    // Giacomo, 28 settembre 2026: «se voglio scrollare tutti i processi non
    // si può fermare l'aggiornarsi della lista […] tornando sempre in cima».
    // La lista riceveva `righe`, un elenco JavaScript nuovo ogni due secondi:
    // per Qt è un modello diverso, e un modello diverso vuol dire buttare
    // tutti i delegati, ricostruirli da capo e ripartire da contentY = 0.
    // Duecento righe rifatte ogni due secondi, e la lettura interrotta.
    //
    // Adesso le righe stanno in un `ListModel` che si CORREGGE: una riga che
    // c'era si aggiorna, una che ha cambiato posto si sposta, una nuova si
    // infila, una sparita si toglie. I delegati restano, e resta dove si era.
    //
    // E l'ordine si FERMA mentre lo si guarda: col puntatore sopra l'elenco,
    // o mentre scorre, i numeri cambiano ma le righe no — ordinare per CPU
    // vuol dire righe che si scambiano di posto a ogni giro, e una riga che
    // scappa mentre la si legge è lo stesso difetto. «Pausa» ferma tutto.

    /// Il modello delle righe, per chi le disegna.
    readonly property alias modello: modello

    /// Ferma tutto, numeri compresi, finché non si riprende.
    property bool inPausa: false
    /// Vero mentre l'elenco si guarda: l'ordine resta com'è. Lo dice chi
    /// disegna l'elenco (il puntatore sopra, lo scorrimento in corso).
    property bool ordineFermo: false

    ListModel {
        id: modello
        dynamicRoles: true
    }

    onRigheChanged: dati.sincronizza()
    onInPausaChanged: if (!dati.inPausa) dati.sincronizza()
    onOrdineFermoChanged: if (!dati.ordineFermo) dati.sincronizza()

    function sincronizza() {
        if (dati.inPausa)
            return;
        var nuove = dati.righe;
        if (dati.ordineFermo) {
            // L'ordine di adesso, con le righe che ci sono ancora; le nuove
            // in fondo.
            var perChiave = {};
            for (var a = 0; a < nuove.length; a++)
                perChiave[nuove[a].chiave] = nuove[a];
            var tenute = [];
            var viste = {};
            for (var b = 0; b < modello.count; b++) {
                var k = modello.get(b).chiave;
                if (perChiave[k] !== undefined) {
                    tenute.push(perChiave[k]);
                    viste[k] = true;
                }
            }
            for (var c = 0; c < nuove.length; c++)
                if (!viste[nuove[c].chiave])
                    tenute.push(nuove[c]);
            nuove = tenute;
        }
        for (var i = 0; i < nuove.length; i++) {
            var chiave = nuove[i].chiave;
            var j = -1;
            for (var q = i; q < modello.count; q++) {
                if (modello.get(q).chiave === chiave) {
                    j = q;
                    break;
                }
            }
            if (j === -1) {
                modello.insert(i, { "chiave": chiave, "riga": nuove[i] });
                continue;
            }
            if (j !== i)
                modello.move(j, i, 1);
            modello.setProperty(i, "riga", nuove[i]);
        }
        if (modello.count > nuove.length)
            modello.remove(nuove.length, modello.count - nuove.length);
    }

    /// Le righe da mostrare, filtrate e ordinate.
    ///
    /// I processi di uno stesso programma si SOMMANO in una riga sola: un
    /// browser con dodici schede sono dodici processi che nessuno vuole
    /// contare, e la domanda vera è quanto costa il browser.
    readonly property var righe: {
        var dentro = [];
        var ago = dati.filtro.trim().toLowerCase();
        var gruppi = {};

        for (var i = 0; i < dati.processi.length; i++) {
            var p = dati.processi[i];
            var haFinestra = dati.pidConFinestra[p.pid] !== undefined;

            if (dati.vista === "app" && !haFinestra)
                continue;

            // ── Il sistema sta chiuso finché non lo si chiede ────────────
            //
            // «Tutti i processi» ne mostrava duecentodue, e centottanta erano
            // `kworker/3:1H`, `systemd-udevd`, `irq/142-nvme0q3`. Nessuno di
            // quelli si chiude, nessuno di quelli è la risposta a «perché la
            // ventola gira», e stanno lì solo a far scorrere.
            //
            // Non si tolgono: si chiudono. Chi li vuole ha una levetta, e
            // sotto c'è scritto quanti sono — così non sembra che manchino.
            // Cercando invece si trova tutto: chi scrive «kworker» sa quello
            // che sta cercando.
            if (dati.vista === "tutti" && !dati.conSistema && ago === ""
                && p.sistema && !haFinestra)
                continue;
            if (ago !== "" && (p.nome || "").toLowerCase().indexOf(ago) === -1
                && (p.comando || "").toLowerCase().indexOf(ago) === -1)
                continue;

            // In vista «tutti» non si raggruppa: lì si guarda il dettaglio, ed
            // è proprio il dettaglio che si è venuti a cercare.
            //
            // ── Perché la chiave non è (solo) il nome ────────────────────
            //
            // Il nome del processo identifica il PROGRAMMA solo finché un
            // programma è un binario. Le finestre di Minerva sono cinque
            // applicazioni diverse eseguite tutte da `qs`: raggruppate per
            // nome diventavano una riga sola, «qs ×5», con le memorie sommate
            // — ed è da lì che veniva il «450 MB» di Anteprima, che non era
            // Anteprima. Quando una finestra c'è, è la sua CLASSE a dire di
            // quale applicazione si tratta.
            var classe = dati.pidConFinestra[p.pid] || "";
            var chiave = dati.vista !== "app" ? String(p.pid)
                       : (classe !== "" ? classe : (p.nome || "?"));
            var privata = Math.max(0, (p.memoria || 0) - (p.memoriaCondivisa || 0));
            // ── Il numero equo, quando il demone è riuscito a prenderlo ───
            //
            // `memoriaEqua` è il PSS: le pagine condivise divise fra chi le
            // usa. È additivo — sommare i PSS di più processi dà un numero
            // vero — e quindi non ha bisogno del giro qui sotto sul massimo.
            // Manca per i processi di altri utenti (`smaps_rollup` non è
            // leggibile) e per quelli piccoli, che il demone non interroga: lì
            // si torna alla stima privata + condivisa.
            var equa = p.memoriaEqua || 0;
            var g = gruppi[chiave];
            if (g === undefined) {
                gruppi[chiave] = {
                    "chiave": chiave,
                    "pid": p.pid,
                    "nome": p.nome,
                    "comando": p.comando,
                    // Li calcola il demone, e vanno portati fin qui: senza,
                    // l'aggregazione li lasciava per strada e la riga tornava
                    // a mostrare la riga di comando.
                    "etichetta": p.etichetta,
                    "descrizione": p.descrizione,
                    "sistema": p.sistema,
                    "cpu": p.cpu,
                    // Vedi `memoria` più sotto: si tengono separate la parte
                    // privata (che si somma) e quella condivisa (che no).
                    "privata": privata,
                    "condivisa": p.memoriaCondivisa || 0,
                    "equa": equa,
                    "quanti": 1,
                    "finestra": haFinestra,
                    "classe": classe
                };
            } else {
                g.cpu = (g.cpu === null || g.cpu === undefined)
                        ? p.cpu : (g.cpu + (p.cpu || 0));
                g.privata += privata;
                // ── La memoria condivisa NON si somma ────────────────────
                //
                // Dentro l'RSS ci sono le librerie — Qt e Mesa sono
                // centoventi megabyte — che stanno in memoria una volta sola
                // e vengono contate in ogni processo che le usa. Sommare
                // l'RSS di dodici processi di un browser dà un numero che non
                // esiste in nessuna parte del computer. Del pezzo condiviso
                // si tiene il massimo del gruppo: è una stima per difetto,
                // ma è dalla parte giusta.
                g.condivisa = Math.max(g.condivisa, p.memoriaCondivisa || 0);
                g.equa += equa;
                g.quanti++;
                if (haFinestra && !g.finestra) {
                    g.finestra = true;
                    g.pid = p.pid;
                    g.classe = classe;
                }
            }
        }

        for (var k in gruppi) {
            var r = gruppi[k];
            // Il PSS quando c'è, la stima quando manca. Mai la somma dei due
            // e mai l'RSS crudo: era quello a far sembrare 183 MB una
            // finestra che di suo ne occupa quarantadue.
            r.memoria = r.equa > 0 ? r.equa : (r.privata + r.condivisa);
            dentro.push(r);
        }

        dentro.sort(function(a, b) {
            if (dati.ordine === "nome")
                return (a.nome || "").localeCompare(b.nome || "");
            if (dati.ordine === "memoria")
                return (b.memoria || 0) - (a.memoria || 0);
            return (b.cpu || 0) - (a.cpu || 0);
        });
        return dentro;
    }

    // ── Formattazione ────────────────────────────────────────────────────

    function byte(v) {
        if (!v || v <= 0) return "0";
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }

    function durata(secondi) {
        if (!secondi) return "—";
        var g = Math.floor(secondi / 86400);
        var o = Math.floor((secondi % 86400) / 3600);
        var m = Math.floor((secondi % 3600) / 60);
        if (g > 0) return g + (dati.it ? " g " : "d ") + o + "h";
        if (o > 0) return o + "h " + m + "m";
        return m + "m";
    }

}
