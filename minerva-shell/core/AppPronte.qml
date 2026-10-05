import QtQuick
import Quickshell
import "." as Core

// AppPronte — Accende all'avvio le app che l'utente vuole trovare pronte.
//
// L'altra metà sta in `core/TenutaPronta.qml`, dentro ogni app: lì c'è cosa
// vuol dire «pronta» e quanto costa. Qui c'è solo chi accende la luce, e
// quando.
//
// ── Perché lo fa la shell e non l'avvio del compositore ─────────────────────
//
// Il gestore file parte da `scripts/minerva-dentro-wayland`, all'avvio della
// sessione. Funziona perché è l'unico acceso di fabbrica: parte comunque, e
// non c'è niente da sprecare.
//
// Per le altre cinque quella strada costa cara e in silenzio. Quando parte
// l'accesso il demone sta ancora nascendo, quindi da lì NON si può sapere
// quali app l'utente vuole pronte: si lancerebbero tutte e cinque, e quelle
// spente uscirebbero da sole dopo mezzo secondo. Mezzo secondo di CPU l'una,
// cinque volte, proprio nell'istante in cui la sessione sta ancora aprendosi e
// ogni millisecondo si vede.
//
// La shell invece le impostazioni ce le ha. Quindi accende solo quelle chieste.
//
// ── E le accende a una a una ────────────────────────────────────────────────
//
// Non insieme. Costruire l'albero QML di un'app impegna un processore per
// quasi mezzo secondo; farne partire cinque nello stesso istante, appena
// dopo l'accesso, vuol dire una scrivania che non risponde proprio mentre la
// si sta guardando per la prima volta. A scaglioni non si nota niente: chi
// apre la calcolatrice sette secondi dopo aver acceso il computer non esiste.
Item {
    id: appPronte

    /// La cartella di Minerva, per trovare gli script di avvio.
    property string radice: ""

    /// Quali app si possono tenere pronte, e come si avviano.
    ///
    /// La chiave dell'impostazione e il nome della variabile d'ambiente sono
    /// gli stessi che ogni app si calcola da sola in `TenutaPronta`: qui sono
    /// scritti una seconda volta, e la prova `preload_avvio_test.dart` esiste
    /// apposta per accorgersi se un giorno divergono.
    ///
    /// Il gestore file non c'è: lo avvia `scripts/minerva-dentro-wayland`, che
    /// è l'unico posto da cui può partire abbastanza presto da servire.
    readonly property var elenco: [
        { "chiave": "preload.calcolatrice", "variabile": "MINERVA_CALCOLATRICE_DORMIENTE",
          "script": "minerva-calcolatrice" },
        { "chiave": "preload.editor",       "variabile": "MINERVA_EDITOR_DORMIENTE",
          "script": "minerva-editor" },
        { "chiave": "preload.impostazioni", "variabile": "MINERVA_IMPOSTAZIONI_DORMIENTE",
          "script": "minerva-settings" },
        { "chiave": "preload.anteprima",    "variabile": "MINERVA_ANTEPRIMA_DORMIENTE",
          "script": "minerva-viewer" },
        { "chiave": "preload.attivita",     "variabile": "MINERVA_ATTIVITA_DORMIENTE",
          "script": "minerva-monitor" },
        { "chiave": "preload.terminale",    "variabile": "MINERVA_TERMINALE_DORMIENTE",
          "script": "minerva-terminale" }
    ]

    /// Quelle ancora da accendere. Si svuota man mano.
    property var _coda: []

    /// Una volta sola per sessione, e questo lo garantisce.
    ///
    /// Non si riaccende quando l'impostazione cambia, ed è voluto: chi la
    /// accende mentre l'app è aperta se la vedrebbe saltare davanti senza
    /// averla chiesta — lo script, trovando l'app già viva, la porta avanti.
    /// Chi l'accende adesso la trova pronta dalla prossima chiusura in poi,
    /// che è esattamente quando comincia a servire.
    property bool _fatto: false

    function _prepara() {
        if (appPronte._fatto || !Core.Ipc.impostazioniArrivate
                || appPronte.radice === "")
            return;
        appPronte._fatto = true;
        var da = [];
        for (var i = 0; i < appPronte.elenco.length; i++) {
            var v = appPronte.elenco[i];
            if (Core.Ipc.get(v.chiave, false) === true)
                da.push(v);
        }
        if (da.length === 0)
            return;
        appPronte._coda = da;
        scaglioni.start();
    }

    Component.onCompleted: appPronte._prepara()

    Connections {
        target: Core.Ipc
        function onImpostazioniArrivateChanged() { appPronte._prepara(); }
    }

    Timer {
        id: scaglioni
        // Il primo dopo quattro secondi: la barra, la dock e la scrivania si
        // stanno ancora disegnando, e sono loro che si guardano per prime.
        interval: 4000
        repeat: true
        onTriggered: {
            if (appPronte._coda.length === 0) {
                scaglioni.stop();
                return;
            }
            var v = appPronte._coda[0];
            appPronte._coda = appPronte._coda.slice(1);
            // ── `env`, e NON `sh -c` ─────────────────────────────────────
            //
            // Serve una variabile d'ambiente e `execDetached` prende una
            // lista di argomenti, non un ambiente. La strada corta sarebbe
            // `sh -c "VAR=1 exec «percorso»"`, e sarebbe un difetto già visto
            // in questo progetto: dentro le virgolette doppie la shell espande
            // ancora `$`, i backtick e le barre rovesce, quindi un percorso
            // con un backtick ESEGUE quello che c'è dentro. `JSON.stringify`
            // cita per JavaScript, non per la shell — e la cartella di Minerva
            // la sceglie l'utente.
            //
            // `env` non ha nessuna shell dentro: prende `VAR=valore`, poi il
            // comando, e non guarda dentro a niente.
            Quickshell.execDetached(["env", v.variabile + "=1",
                appPronte.radice + "/scripts/" + v.script]);
            // Dopo il primo si rallenta: il grosso dell'avvio è passato, e
            // quello che resta può prendersela comoda.
            scaglioni.interval = 2500;
        }
    }
}
