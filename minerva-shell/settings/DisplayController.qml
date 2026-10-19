import QtQuick
import "../core" as Core
import "." as S

// Un solo gestore per i due aspetti: prova, ripristino e salvataggio degli
// schermi devono seguire lo stesso protocollo qualunque sia il preset.
Item {
    id: page
    width: 0
    height: 0
    property alias changeGuard: guard
    property alias multiChangeGuard: multiGuard
    property var monitors: []
    property bool multiPending: false
    property string displayError: ""
    readonly property string provaId: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    property bool salvaDopoRisposta: false

    /// Vero quando il compositore ha detto che su questo schermo la tabella
    /// dei colori non si può mettere. Finché non risponde è falso, ed è il
    /// caso giusto: non si annuncia un guasto che non si sa se c'è.
    readonly property bool _tintaSenzaStrada:
        String((Core.Compositore.statoCompositore || {}).tintaStrada || "")
        === "nessuna"

    // ── E se il canale non era ancora aperto ─────────────────────────────
    //
    // `_nostro` butta via la richiesta quando il socket del compositore non è
    // ancora connesso, e la pagina restava vuota — un riquadro «Schermi»
    // senza schermi su un computer che lo schermo ce l'ha davanti, che si
    // riempiva solo cambiando sezione e tornando. Visto in fotografia il 22
    // settembre 2026. Quando il canale si apre, si richiede.
    Connections {
        target: Core.Compositore
        function onCanaleApertoChanged() {
            if (Core.Compositore.canaleAperto) page.reload();
        }
    }

    Component.onCompleted: {
        reload();
        // La strada della tinta si sa solo chiedendola: è una proprietà dello
        // SCHERMO, non un'impostazione.
        Core.Compositore.chiediStato();
    }

    Connections {
        target: Core.Compositore
        function onRisposta(cosa, testo) {
            if (cosa.indexOf("monitori-") === 0) {
                if (testo !== "ok") {
                    page.displayError = testo;
                    page.multiPending = false;
                    multiGuard.armed = false;
                    page.reload();
                    return;
                }
                if (cosa === "monitori-prova") {
                    multiGuard.arm(page.it ? "Questa disposizione va bene?" : "Keep this display setup?");
                } else {
                    page.multiPending = false;
                    if (cosa === "monitori-conferma") page.salvaDopoRisposta = true;
                    page.reload();
                }
                return;
            }
            // ── La prova rifiutata ──────────────────────────────────────
            //
            // La risposta a `schermo-prova` non la guardava nessuno. Un modo
            // che il compositore rifiuta («no …») faceva partire lo stesso il
            // conto alla rovescia «Lo schermo si vede bene?» su un cambio mai
            // avvenuto, e «Mantieni» finiva in un avviso sul registro: sullo
            // schermo nessun errore (30 settembre 2026). Adesso la domanda si
            // ritira e il perché si legge nel riquadro.
            if (cosa === "schermo-prova") {
                if (testo.indexOf("ok") !== 0) {
                    guard.armed = false;
                    page.previous = null;
                    page.displayError = testo.indexOf("no ") === 0 ? testo.substring(3) : testo;
                    page.reload();
                }
                return;
            }
            if (cosa === "schermo-conferma") {
                if (testo === "ok") {
                    page.salvaDopoRisposta = true;
                    page.reload();
                } else console.warn("[MINERVA] Conferma schermo rifiutata: " + testo);
                return;
            }
            if (cosa !== "schermi")
                return;
            if (testo === "") {
                page.monitors = [];
                return;
            }
            page.monitors = Core.Compositore.schermiDaTesto(testo);
            if (page.salvaDopoRisposta) {
                page.salvaDopoRisposta = false;
                page.persist();
            }
        }
    }

    function reload() {
        Core.Compositore.chiedi("schermi");
    }

    // ── Applicare, e poterlo disfare ─────────────────────────────────────
    //
    // Nessuna modifica di questa pagina viene salvata nel momento in cui la si
    // fa. Si applica e basta, poi si chiede se va bene: è l'unica difesa che
    // funziona contro una rotazione sbagliata o una risoluzione che il monitor
    // non regge, perché in quei casi il pannello che ha fatto il danno è la
    // prima cosa che diventa irraggiungibile. Chi non risponde ritrova lo
    // schermo com'era e non deve rimettere a posto niente.
    //
    // Vedi ChangeGuard: la conferma sta in una finestra propria, sopra tutto.

    /// Stato a cui tornare se la conferma non arriva.
    property var previous: null

    /// Fotografia di uno schermo, negli stessi termini che `apply` accetta.
    function snapshot(nome) {
        for (var i = 0; i < page.monitors.length; i++) {
            var m = page.monitors[i];
            if (m.nome !== nome)
                continue;
            return {
                "nome": nome,
                "modo": m.modoLarghezza + "x" + m.modoAltezza + "@" + Number(m.hz).toFixed(3),
                "scala": String(m.scala),
                "gradi": String(m.gradi || 0),
                "x": m.x,
                "y": m.y,
                "acceso": m.acceso !== false
            };
        }
        return null;
    }

    /// Manda la modifica al compositore e non salva niente: il salvataggio è
    /// la conferma, e la conferma arriva dopo.
    function push(nome, modo, scala, gradi) {
        Core.Compositore.schermo(nome, modo, scala, gradi, undefined, undefined, page.provaId);
    }

    function apply(nome, modo, scala, gradi, cosa) {
        page.displayError = "";
        // Una seconda modifica mentre la domanda è ancora a schermo è la
        // prova migliore che si possa chiedere: chi la fa sta vedendo e sta
        // cliccando. La domanda precedente si chiude come confermata, e questa
        // parte da uno stato pulito.
        if (guard.armed && page.previous && page.previous.nome !== nome)
            guard.keep();
        if (!guard.armed)
            page.previous = page.snapshot(nome);

        page.push(nome, modo, scala, gradi);
        guard.arm(page.it ? "Lo schermo si vede bene?"
                          : "Does the display look right?",
                  cosa || "");
    }

    function disable(nome) {
        page.displayError = "";
        if (guard.armed && page.previous && page.previous.nome !== nome)
            guard.keep();
        if (!guard.armed)
            page.previous = page.snapshot(nome);

        Core.Compositore.schermoSpento(nome, page.provaId);
        guard.arm(page.it ? "Gli altri schermi si vedono?"
                          : "Can you see the other displays?",
                  page.it ? "Schermo spento: " + nome
                          : "Display turned off: " + nome);
    }

    readonly property bool it: Core.Strings.lang === "it"
    /// L'ora di adesso, per dire se la luce notturna è accesa dall'orario.
    property int oraAdesso: new Date().getHours()
    Timer {
        interval: 60000
        // Solo con le Impostazioni davanti: ridotte o dietro un'altra
        // finestra non c'è nessuno a guardare. Tornandoci si aggiorna
        // subito (`triggeredOnStart`).
        running: Qt.application.state === Qt.ApplicationActive
        triggeredOnStart: true
        repeat: true
        onTriggered: page.oraAdesso = new Date().getHours()
    }

    S.ChangeGuard {
        id: guard

        onKept: {
            if (page.previous) Core.Compositore.confermaSchermo(page.provaId, page.previous.nome, true);
            page.previous = null;
        }

        onReverted: {
            var p = page.previous;
            page.previous = null;
            if (!p)
                return;
            Core.Compositore.confermaSchermo(page.provaId, p.nome, false);
            // Si rilegge ma non si riscrive: il file non è mai stato toccato,
            // e conteneva già lo stato a cui siamo appena tornati.
            reloadSoon.restart();
        }
    }

    Timer {
        id: reloadSoon
        interval: 700
        onTriggered: page.reload()
    }

    /// Aspetta che il compositore abbia finito di applicare, poi fotografa lo stato
    /// e lo scrive. Scrivere prima significherebbe salvare ciò che abbiamo
    /// chiesto invece di ciò che è successo davvero.
    Timer {
        id: persistSoon
        interval: 700
        onTriggered: {
            page.reload();
            writeTimer.restart();
        }
    }

    Timer {
        id: writeTimer
        interval: 300
        onTriggered: page.persist()
    }

    // ── Il file degli schermi ────────────────────────────────────────────
    //
    // `schermi.conf` nella cartella di Liquid DE (`Core.Ipc.cartellaConfig`),
    // che legge il compositore all'avvio (`compositore/src/schermi.c`).
    //
    // Qui c'erano due difetti insieme, trovati il 27 settembre 2026 togliendo
    // Hyprland dal codice. Si scriveva ANCHE `~/.config/hypr/minerva-display.conf`,
    // nella lingua di Hyprland, che non leggeva più nessuno. E il nostro file
    // finiva in `~/.config/minerva`, la cartella di MINERVA: le scelte sugli
    // schermi fatte in Liquid DE non tornavano al prossimo accesso (il
    // compositore le cerca in `liquid-de`) e intanto cambiavano quelle
    // dell'altro desktop.
    function persist() {
        page.persistiPerMinervaWayland();
    }

    function persistiPerMinervaWayland() {
        var righe = [
            "# Schermi — scritto dal pannello Impostazioni di Minerva.",
            "# Lo legge minerva-wayland all'avvio.",
            "# Rigenerato a ogni modifica: le modifiche a mano vengono perse."
        ];
        for (var i = 0; i < page.monitors.length; i++) {
            var m = page.monitors[i];
            if (!m.acceso) {
                righe.push(m.nome + " = spento");
                continue;
            }
            // La rotazione è già in gradi.
            // Un'uscita virtuale può non annunciare una frequenza: @0 non è
            // un modo valido e renderebbe il file inutilizzabile al riavvio.
            var modo = Number(m.hz) > 0
                ? m.modoLarghezza + "x" + m.modoAltezza + "@" + Number(m.hz).toFixed(3) : "preferito";
            righe.push(m.nome + " = " + modo
                       + " " + m.x + "," + m.y
                       + " " + m.scala
                       + " " + (m.gradi || 0));
        }
        // La cartella e il testo passano come ARGOMENTI, non dentro la riga:
        // un nome di schermo non deve poter diventare un comando.
        scrittoreNostro.fireShArgs(
            'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/.schermi.tmp" && '
            + 'mv "$1/.schermi.tmp" "$1/schermi.conf"',
            [Core.Ipc.cartellaConfig, righe.join("\n")]);
    }

    Core.Exec { id: scrittoreNostro }

    function multi(mode, name) {
        if (page.multiPending || guard.armed) return;
        page.displayError = "";
        page.multiPending = true;
        var args = [page.provaId, mode];
        if (name) args.push(name);
        Core.Compositore._nostro("monitori-prova", args);
    }
    S.ChangeGuard {
        id: multiGuard
        onKept: Core.Compositore._nostro("monitori-conferma", [page.provaId])
        onReverted: Core.Compositore._nostro("monitori-annulla", [page.provaId])
    }

    // ── Gli schermi, come si vedono ──────────────────────────────────────
    //
    // Il manutentore, 22 settembre 2026: «se ho collegati uno o più monitor esterni
    // la pagina diventa molto lunga, quindi vorrei come KDE dei monitor in
    // alto e cliccando su quel monitor vedere tutte le sue opzioni». Prima
    // c'era un riquadro per schermo, uno sotto l'altro, con tutte le
    // risoluzioni come pulsanti: con due schermi si scorreva per una stanza.
    //
    // Adesso: le miniature in alto, proporzionate alla loro risoluzione e
    // disposte come stanno sul tavolo (le duplicate si sovrappongono un po'
    // apposta, così si vede che sono nello stesso punto); sotto, i quattro
    // modi; e UNA scheda con le regolazioni dello schermo scelto.

    /// Lo schermo di cui si mostrano le regolazioni. Se sparisce (scollegato)
    /// si torna al primo.
    property string scelto: ""
    readonly property var monitorScelto: {
        for (var i = 0; i < page.monitors.length; i++)
            if (page.monitors[i].nome === page.scelto) return page.monitors[i];
        return page.monitors.length > 0 ? page.monitors[0] : null;
    }
    onMonitorsChanged: {
        if (page.monitors.length === 0) return;
        var c = false;
        for (var i = 0; i < page.monitors.length; i++)
            if (page.monitors[i].nome === page.scelto) c = true;
        if (!c) page.scelto = page.monitors[0].nome;
    }

    /// Il notebook si riconosce dal connettore: eDP e LVDS sono i pannelli
    /// interni, tutto il resto (HDMI, DP, DVI) è esterno.
    function eNotebook(nome) {
        var n = String(nome || "").toUpperCase();
        return n.indexOf("EDP") === 0 || n.indexOf("LVDS") === 0 || n.indexOf("DSI") === 0;
    }
    function nomeParlante(m) {
        if (page.eNotebook(m.nome)) return page.it ? "Schermo del PC" : "Built-in display";
        return m.descrizione ? m.descrizione : m.nome;
    }
    readonly property bool duplicati: {
        if (page.monitors.length < 2) return false;
        var accesi = page.monitors.filter(function (m) { return m.acceso !== false; });
        if (accesi.length < 2) return false;
        for (var i = 1; i < accesi.length; i++)
            if (accesi[i].x !== accesi[0].x || accesi[i].y !== accesi[0].y) return false;
        return true;
    }

}
