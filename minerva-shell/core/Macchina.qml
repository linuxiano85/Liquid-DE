pragma Singleton
import QtQuick
import "." as Core

// Macchina — Come sta il computer, per chi lo mostra sulla scrivania.
//
// ── Una sorgente sola, una cadenza sola ────────────────────────────────────
//
// È il punto in cui i sistemi di widget diventano lenti: dieci widget, dieci
// timer, dieci letture di `/proc`. Qui c'è UN'iscrizione al demone e una sola
// spinta ogni cinque secondi; i widget si legano a queste proprietà e non
// chiedono niente a nessuno.
//
// ── E si accende solo se qualcuno guarda ───────────────────────────────────
//
// `guardano` è un conteggio, non un interruttore: ogni widget dice «io
// guardo» quando compare e «io no» quando sparisce o quando finisce coperto
// da una finestra. Al primo si apre l'iscrizione, all'ultimo si chiude.
//
// Senza questo, un widget aperto una volta lascerebbe il demone a leggere
// `/proc` per il resto della sessione — cioè il widget diventerebbe uno dei
// consumi che serve a mostrare. È la stessa regola del Monitor, e lì sta
// scritta accanto a `subscribeProcesses`.
QtObject {
    id: macchina

    // ── I numeri ─────────────────────────────────────────────────────────
    //
    // I nomi sono quelli che manda il demone (`soloMacchina` in
    // `process_service.dart`), tradotti una volta sola: qui e in nessun altro
    // posto. Un widget che legge `dati.memoriaTotale` da sé sarebbe un
    // secondo posto in cui quel nome deve restare giusto.

    /// Da 0 a 100. `-1` finché non è arrivata la prima misura, ed è un caso
    /// normale: l'uso della CPU non si legge, si calcola fra due letture.
    property real cpu: -1
    property int core: 0

    /// In byte.
    property real memoriaTotale: 0
    property real memoriaUsata: 0
    property real memoriaCache: 0
    property real scambioTotale: 0
    property real scambioUsato: 0

    /// Byte al secondo.
    property real reteGiu: 0
    property real reteSu: 0

    /// Gradi. `-1` quando la macchina non ha sonde leggibili.
    property real temperatura: -1

    /// ── La GPU, e il nome è la prima riga di documentazione ─────────────
    ///
    /// Quanto la GPU è stata SVEGLIA, da 0 a 100. Non è l'uso: è cento meno
    /// il tempo passato nel sonno più profondo (`rc6`), che è un tetto
    /// all'uso — una GPU sveglia può non star facendo niente.
    ///
    /// Si chiama così perché chiamarlo «uso» vorrebbe dire mentire in ogni
    /// punto in cui viene mostrato. L'uso vero, motore per motore, vuole un
    /// permesso che questa macchina non dà a un programma qualunque
    /// (`CAP_PERFMON`), e quando arriverà avrà un nome suo.
    ///
    /// `-1` finché non c'è, ed è un caso normale: la prima misura è una
    /// differenza, e alla prima lettura non c'è niente da cui differire.
    property real gpuSveglia: -1

    /// Il carico medio di un minuto, e i secondi da quando è acceso.
    property real carico: 0
    property int acceso: 0

    /// ── Il disco ────────────────────────────────────────────────────────
    ///
    /// Byte, della radice. Arriva con lo stesso annuncio degli altri, ma il
    /// demone lo rilegge **una volta al minuto**: è l'unico valore che costa
    /// un processo (`df`), e lo spazio libero di un disco da 950 GB non
    /// cambia in cinque secondi. Fra una lettura e l'altra si ripete
    /// l'ultimo, che non è una stima: è la misura di un minuto fa.
    property real discoTotale: 0
    property real discoLibero: 0

    readonly property real discoPerCento:
        macchina.discoTotale > 0
        ? (macchina.discoTotale - macchina.discoLibero)
          / macchina.discoTotale * 100 : 0

    readonly property real memoriaPerCento:
        macchina.memoriaTotale > 0
        ? macchina.memoriaUsata / macchina.memoriaTotale * 100 : 0

    /// Vero quando è arrivata almeno una misura. Chi disegna deve saper stare
    /// senza: fra l'accensione del widget e il primo numero passa un istante,
    /// e mostrare uno zero in quell'istante vuol dire dire una cosa falsa.
    readonly property bool pronta: macchina.cpu >= 0

    // ── La storia ────────────────────────────────────────────────────────
    //
    // Quarantotto campioni: a cinque secondi l'uno sono **quattro minuti**.
    // È la finestra giusta per la domanda che si fa guardando la scrivania —
    // «è appena successo qualcosa?» — e non quella del Monitor, che è «cosa
    // sta succedendo adesso».
    //
    // Un numero da solo non dice se sta salendo. È tutta la differenza fra un
    // widget e un'etichetta: «42 %» non si sa se è tanto, «42 % e sale da un
    // minuto» sì.
    //
    // Costa quarantotto numeri per grandezza — meno di due kilobyte in tutto —
    // e si tiene anche quando nessuno la guarda: chi apre un widget adesso
    // vede subito da dove viene, invece di aspettare quattro minuti per avere
    // una riga.
    readonly property int quantiRicordi: 48

    property var storiaCpu: []
    property var storiaMemoria: []
    property var storiaGpu: []
    property var storiaRete: []

    /// La storia di una grandezza, per nome. Chi disegna non deve sapere in
    /// quale delle quattro liste stia.
    function storia(quale) {
        switch (quale) {
        case "processore":  return macchina.storiaCpu;
        case "memoria":     return macchina.storiaMemoria;
        case "gpu":         return macchina.storiaGpu;
        case "rete":        return macchina.storiaRete;
        }
        return [];
    }

    /// Vero quando questa grandezza una storia ce l'ha. Sta QUI e non in chi
    /// disegna, perché è la stessa domanda a cui risponde `storia()`: due
    /// elenchi in due file sono il modo di aggiungere una grandezza in uno e
    /// dimenticarla nell'altro.
    function haStoria(quale) {
        return quale === "processore" || quale === "memoria"
            || quale === "gpu" || quale === "rete";
    }

    /// Il fondo scala di un grafico. Le percentuali ce l'hanno per natura; la
    /// rete no, e allora è il massimo di quello che si è visto — o un grafico
    /// della rete resterebbe una riga piatta in fondo per sempre.
    function fondoScala(quale) {
        if (quale !== "rete")
            return 100;
        var l = macchina.storiaRete;
        var max = 1;
        for (var i = 0; i < l.length; i++)
            if (l[i] > max)
                max = l[i];
        return max;
    }

    function _ricorda(lista, valore) {
        var l = lista.slice();
        l.push(valore);
        while (l.length > macchina.quantiRicordi)
            l.shift();
        return l;
    }

    // ── Chi guarda ───────────────────────────────────────────────────────

    property int guardano: 0

    function guarda() {
        macchina.guardano++;
        if (macchina.guardano === 1 && Core.Ipc.connected)
            Core.Ipc.iscriviMacchina();
    }

    function nonGuardo() {
        if (macchina.guardano > 0)
            macchina.guardano--;
        if (macchina.guardano === 0 && Core.Ipc.connected)
            Core.Ipc.disiscriviMacchina();
    }

    property Connections _canale: Connections {
        target: Core.Ipc

        // La connessione può cadere e tornare (il demone si riavvia): al
        // ritorno l'iscrizione va rifatta, o i widget restano fermi
        // sull'ultimo numero per sempre senza dire niente. È il difetto
        // scritto in `minerva-riconnessione-demone`.
        function onConnectedChanged() {
            if (Core.Ipc.connected && macchina.guardano > 0)
                Core.Ipc.iscriviMacchina();
        }

        function onMachineStateReceived(m) {
            if (!m)
                return;
            if (m.cpu !== undefined)            macchina.cpu = m.cpu;
            if (m.core !== undefined)           macchina.core = m.core;
            if (m.memoriaTotale !== undefined)  macchina.memoriaTotale = m.memoriaTotale;
            if (m.memoriaUsata !== undefined)   macchina.memoriaUsata = m.memoriaUsata;
            if (m.memoriaCache !== undefined)   macchina.memoriaCache = m.memoriaCache;
            if (m.scambioTotale !== undefined)  macchina.scambioTotale = m.scambioTotale;
            if (m.scambioUsato !== undefined)   macchina.scambioUsato = m.scambioUsato;
            if (m.reteGiu !== undefined)        macchina.reteGiu = m.reteGiu;
            if (m.reteSu !== undefined)         macchina.reteSu = m.reteSu;
            if (m.temperatura !== undefined)    macchina.temperatura = m.temperatura;
            if (m.gpuSveglia !== undefined)     macchina.gpuSveglia = m.gpuSveglia;
            if (m.carico !== undefined)         macchina.carico = m.carico;
            if (m.acceso !== undefined)         macchina.acceso = m.acceso;
            if (m.discoTotale !== undefined)    macchina.discoTotale = m.discoTotale;
            if (m.discoLibero !== undefined)    macchina.discoLibero = m.discoLibero;

            // La storia si scrive DOPO i valori, e con una lista nuova: in
            // QML una `property var` riassegnata allo stesso oggetto non è un
            // cambiamento, e chi disegna non si sveglierebbe. È la trappola
            // presa l'8 settembre 2026 con le spunte di Manutenzione.
            if (m.cpu !== undefined)
                macchina.storiaCpu = macchina._ricorda(macchina.storiaCpu, m.cpu);
            if (m.memoriaTotale !== undefined)
                macchina.storiaMemoria =
                    macchina._ricorda(macchina.storiaMemoria,
                                      macchina.memoriaPerCento);
            if (m.gpuSveglia !== undefined)
                macchina.storiaGpu =
                    macchina._ricorda(macchina.storiaGpu, m.gpuSveglia);
            if (m.reteGiu !== undefined)
                macchina.storiaRete =
                    macchina._ricorda(macchina.storiaRete, m.reteGiu);
        }
    }
}
