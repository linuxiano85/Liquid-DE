import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Display — Risoluzione, frequenza, ingrandimento e rotazione degli schermi.
//
// I dati arrivano dal COMPOSITORE, che è l'unica fonte che sa davvero cosa il
// monitor supporta: un elenco di risoluzioni scritto a mano prima o poi
// propone qualcosa che lo schermo non regge, e chi la sceglie resta al buio.
//
// ── Un vocabolario solo, due compositori ─────────────────────────────────
//
// Questa pagina parlava il vocabolario di Hyprland a mano — `width`,
// `refreshRate`, `availableModes`, `transform`, `disabled` — e sotto
// `minerva-wayland` non trovava nessuno di quei nomi: mostrava «nessuno
// schermo rilevato» su un computer che lo schermo ce l'ha davanti.
//
// Adesso i nomi sono quelli di Minerva (`larghezza`, `hz`, `modi`, `gradi`,
// `acceso`) e la traduzione la fa `core/Compositore.qml`, che è il posto
// dichiarato per farla.
//
// Ogni modifica si applica SUBITO, su tutti e due i compositori, e poi viene
// scritta nei due file di configurazione perché resti dopo il riavvio.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Schermo" : "Display"
    subtitle: Core.Strings.lang === "it"
              ? "Risoluzione, frequenza di aggiornamento e ingrandimento"
              : "Resolution, refresh rate and scaling"

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
        running: true
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

    /// Aspetta che Hyprland abbia finito di applicare, poi fotografa lo stato
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
            // La rotazione è già in gradi, e ci arriva pulita: le
            // trasformazioni specchiate di Hyprland (da 4 in su) le ha già
            // ridotte a «dritto» il traduttore, perché moltiplicate per 90
            // darebbero 360 e oltre — un numero senza senso in una casella
            // di rotazione.
            righe.push(m.nome + " = "
                       + m.modoLarghezza + "x" + m.modoAltezza + "@" + Number(m.hz).toFixed(3)
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
    // Giacomo, 22 settembre 2026: «se ho collegati uno o più monitor esterni
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

    Card {
        heading: page.it ? "Schermi" : "Displays"
        // Senza schermi non si mostra un riquadro vuoto: sotto c'è già la
        // riga che dice che il compositore non ha risposto.
        visible: page.monitors.length > 0
        note: page.displayError
              || (page.monitors.length > 1
                  ? (page.it ? "Clicca uno schermo per regolarlo. I modi qui sotto vanno confermati entro 15 secondi, altrimenti si torna a com'era."
                             : "Click a display to adjust it. The modes below must be confirmed within 15 seconds, or things go back as they were.")
                  : (page.it ? "Clicca lo schermo per regolarlo. Collegando un monitor compare qui da solo."
                             : "Click the display to adjust it. A monitor you plug in shows up here by itself."))

        // ── Le miniature ─────────────────────────────────────────────────
        //
        // La scala è una per tutte: il più largo prende 260 px, gli altri
        // in proporzione, e le posizioni sono quelle vere divise per la
        // stessa scala. Uno schermo spento è un contorno tratteggiato.
        Item {
            id: tavolo
            width: parent.width
            readonly property real scala: {
                var maxW = 1, maxX = 1;
                for (var i = 0; i < page.monitors.length; i++) {
                    var m = page.monitors[i];
                    var w = (m.larghezza || m.modoLarghezza || 1280);
                    maxW = Math.max(maxW, w);
                    maxX = Math.max(maxX, (m.x || 0) + w);
                }
                // Tutto deve starci in larghezza: se sono affiancati, la
                // scala segue la somma, non il singolo.
                return Math.min(260 / maxW, Math.max(1, tavolo.width - 16) / maxX);
            }
            readonly property real altezzaTotale: {
                var maxY = 1;
                for (var i = 0; i < page.monitors.length; i++) {
                    var m = page.monitors[i];
                    maxY = Math.max(maxY, (m.y || 0) + (m.altezza || m.modoAltezza || 720));
                }
                return maxY * tavolo.scala;
            }
            height: Math.max(90, tavolo.altezzaTotale + 40)

            Repeater {
                model: page.monitors
                delegate: Item {
                    id: mini
                    required property var modelData
                    required property int index
                    readonly property bool scelta: page.scelto === mini.modelData.nome
                                                   || (page.scelto === "" && mini.index === 0)
                    readonly property bool acceso: mini.modelData.acceso !== false
                    // Le duplicate stanno nello stesso punto: si sfalsano di
                    // qualche pixel per ognuna, così si vede che ce n'è più
                    // d'una — è quello che fa KDE.
                    x: 8 + (mini.modelData.x || 0) * tavolo.scala + (page.duplicati ? mini.index * 10 : 0)
                    y: (mini.modelData.y || 0) * tavolo.scala + (page.duplicati ? mini.index * 10 : 0)
                    width: Math.max(60, (mini.modelData.larghezza || mini.modelData.modoLarghezza || 1280) * tavolo.scala)
                    height: Math.max(40, (mini.modelData.altezza || mini.modelData.modoAltezza || 720) * tavolo.scala)
                    z: mini.scelta ? 2 : 1

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.Effects.radiusSM
                        color: mini.scelta ? Qt.alpha(Theme.Colors.accent, 0.18)
                             : (mini.acceso ? Theme.Colors.raised : "transparent")
                        border.width: mini.scelta ? 2 : 1
                        border.color: mini.scelta ? Theme.Colors.accent
                                    : (mini.acceso ? Theme.Colors.edge : Theme.Colors.textFaint)
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            width: parent.width - 12
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: page.nomeParlante(mini.modelData)
                                color: mini.scelta ? Theme.Colors.accent : Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightMedium
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: mini.acceso
                                      ? mini.modelData.modoLarghezza + " × " + mini.modelData.modoAltezza
                                        + (mini.modelData.attivo ? "  ·  " + (page.it ? "attivo" : "active") : "")
                                      : (page.it ? "spento" : "off")
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.scelto = mini.modelData.nome
                    }
                }
            }
        }

        // ── I quattro modi ───────────────────────────────────────────────
        //
        // «Duplica», «Solo …» per ogni schermo, «Estendi». Sono una
        // TRANSAZIONE del compositore (`monitori-prova`): quindici secondi
        // per dire che va bene, altrimenti si torna indietro da soli — chi
        // sceglie male qui non vede più il pannello con cui rimediare.
        Flow {
            width: parent.width
            spacing: Theme.Effects.space2
            visible: page.monitors.length > 1

            Ui.SpineButton {
                height: 32
                horizontalPadding: Theme.Effects.space3
                enabled: !page.multiPending && !guard.armed && !page.duplicati
                tooltip: page.it ? "Lo stesso contenuto su tutti gli schermi"
                                 : "The same picture on every display"
                content: Text {
                    text: page.it ? "Duplica" : "Mirror"
                    color: page.duplicati ? Theme.Colors.accent : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                onClicked: page.multi("duplica", "")
            }

            Repeater {
                model: page.monitors
                delegate: Ui.SpineButton {
                    id: bottoneSolo
                    required property var modelData
                    readonly property bool giaCosi: page.monitors.filter(function (m) {
                        return m.acceso !== false; }).length === 1 && bottoneSolo.modelData.acceso !== false
                    height: 32
                    horizontalPadding: Theme.Effects.space3
                    enabled: !page.multiPending && !guard.armed && !giaCosi
                    tooltip: page.it ? "Usa solo questo schermo, gli altri si spengono"
                                     : "Use only this display; the others turn off"
                    content: Text {
                        text: (page.it ? "Solo " : "Only ")
                              + (page.eNotebook(bottoneSolo.modelData.nome)
                                 ? "PC" : page.nomeParlante(bottoneSolo.modelData))
                        color: bottoneSolo.giaCosi ? Theme.Colors.accent : Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    onClicked: page.multi("solo", bottoneSolo.modelData.nome)
                }
            }

            Ui.SpineButton {
                id: bottoneEstendi
                readonly property bool giaCosi: !page.duplicati && page.monitors.every(function (m) {
                    return m.acceso !== false; })
                height: 32
                horizontalPadding: Theme.Effects.space3
                enabled: !page.multiPending && !guard.armed && !giaCosi
                tooltip: page.it ? "Una scrivania larga quanto tutti gli schermi insieme"
                                 : "One desktop as wide as all displays together"
                content: Text {
                    text: page.it ? "Estendi" : "Extend"
                    color: bottoneEstendi.giaCosi ? Theme.Colors.accent : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                onClicked: page.multi("estendi", "")
            }
        }

        Text {
            width: parent.width
            visible: page.duplicati
            wrapMode: Text.WordWrap
            text: page.it
                ? "Gli schermi sono duplicati: mostrano lo stesso pezzo di scrivania. Con risoluzioni diverse, il più grande lascia un bordo vuoto."
                : "The displays are mirrored: they show the same piece of the desktop. With different resolutions the larger one leaves an empty edge."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    // ── Lo schermo scelto, con le sue regolazioni ────────────────────────

    Card {
        id: mon
        visible: page.monitorScelto !== null
        readonly property var m: page.monitorScelto || ({})

        heading: page.nomeParlante(mon.m)
                 + (mon.m.nome && page.nomeParlante(mon.m) !== mon.m.nome ? "  ·  " + mon.m.nome : "")
        note: page.it
              ? "Posizione " + mon.m.x + "," + mon.m.y
                + (mon.m.attivo ? "  ·  schermo attivo" : "")
                + (page.eNotebook(mon.m.nome) ? "" : "  ·  " + (page.it ? "monitor esterno" : "external monitor"))
              : "Position " + mon.m.x + "," + mon.m.y
                + (mon.m.attivo ? "  ·  active display" : "")

        /// Le risoluzioni senza doppioni, ognuna con le sue frequenze. Dal
        /// compositore arrivano come «1920x1080@60.000»: qui si spezzano in
        /// due tendine, perché venti voci «1920 × 1080 a 60 / 59,94 / 50»
        /// sono tre risoluzioni e non venti.
        readonly property var risoluzioni: {
            var grezzi = mon.m.modi || [];
            var perRis = {}, ordine = [];
            for (var i = 0; i < grezzi.length; i++) {
                var t = String(grezzi[i]);
                var k = t.indexOf("@");
                if (k < 0) continue;
                var ris = t.substring(0, k);
                var hz = Number(t.substring(k + 1));
                if (!perRis[ris]) { perRis[ris] = []; ordine.push(ris); }
                if (perRis[ris].indexOf(hz) < 0) perRis[ris].push(hz);
            }
            // Dalla più grande alla più piccola, come fanno tutti.
            ordine.sort(function (a, b) {
                var pa = a.split("x"), pb = b.split("x");
                return (Number(pb[0]) * Number(pb[1])) - (Number(pa[0]) * Number(pa[1]));
            });
            var out = [];
            for (var j = 0; j < ordine.length; j++) {
                var hzs = perRis[ordine[j]].slice().sort(function (a, b) { return b - a; });
                out.push({ "value": ordine[j], "label": ordine[j].replace("x", " × "), "hz": hzs });
            }
            return out;
        }
        readonly property string risoluzioneAttuale: mon.m.modoLarghezza + "x" + mon.m.modoAltezza
        readonly property var frequenze: {
            for (var i = 0; i < mon.risoluzioni.length; i++)
                if (mon.risoluzioni[i].value === mon.risoluzioneAttuale) {
                    return mon.risoluzioni[i].hz.map(function (h) {
                        return { "value": Number(h).toFixed(3), "label": page.hzParlante(h) };
                    });
                }
            return [];
        }
        readonly property string currentMode: mon.risoluzioneAttuale + "@" + Number(mon.m.hz).toFixed(3)

        /// Cambiando risoluzione si tiene la frequenza di adesso se quella
        /// risoluzione ce l'ha, altrimenti la più alta.
        function modoPer(ris) {
            for (var i = 0; i < mon.risoluzioni.length; i++) {
                if (mon.risoluzioni[i].value !== ris) continue;
                var hzs = mon.risoluzioni[i].hz;
                var ora = Number(mon.m.hz);
                for (var k = 0; k < hzs.length; k++)
                    if (Math.abs(hzs[k] - ora) < 0.01) return ris + "@" + Number(hzs[k]).toFixed(3);
                return ris + "@" + Number(hzs[0]).toFixed(3);
            }
            return mon.currentMode;
        }

        S.SettingRow {
            width: parent.width
            visible: mon.risoluzioni.length === 0
            label: page.it ? "Risoluzione" : "Resolution"
            description: page.it ? "Questo schermo non ne offre altre" : "This display offers no others"
            controlWidth: 260
            control: Text {
                text: mon.m.modoLarghezza + " × " + mon.m.modoAltezza
                      + (mon.m.hz > 0 ? "   " + page.hzParlante(mon.m.hz) : "")
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightRegular
            }
        }

        S.SettingRow {
            width: parent.width
            visible: mon.risoluzioni.length > 0
            label: page.it ? "Risoluzione" : "Resolution"
            searchTerms: "risoluzione resolution pixel"
            controlWidth: 260
            control: S.Tendina {
                width: 260
                value: mon.risoluzioneAttuale
                options: mon.risoluzioni
                onPicked: function (v) {
                    page.apply(mon.m.nome, mon.modoPer(v), mon.m.scala, mon.m.gradi,
                               (page.it ? "Risoluzione: " : "Resolution: ") + v.replace("x", " × "));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: mon.frequenze.length > 1
            label: page.it ? "Frequenza di aggiornamento" : "Refresh rate"
            description: page.it ? "Quante volte al secondo lo schermo si ridisegna"
                                 : "How many times per second the display redraws"
            searchTerms: "frequenza hertz hz refresh"
            controlWidth: 260
            control: S.Tendina {
                width: 260
                value: Number(mon.m.hz).toFixed(3)
                options: mon.frequenze
                onPicked: function (v) {
                    page.apply(mon.m.nome, mon.risoluzioneAttuale + "@" + v, mon.m.scala, mon.m.gradi,
                               (page.it ? "Frequenza: " : "Refresh rate: ") + page.hzParlante(Number(v)));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Ingrandimento" : "Scaling"
            description: page.it ? "Quanto sono grandi testo e icone su questo schermo"
                                 : "How large text and icons are on this display"
            searchTerms: "scala ingrandimento zoom hidpi"
            controlWidth: 260
            control: S.Tendina {
                width: 260
                // Solo frazioni che Wayland gestisce senza sfocare: le
                // scale arbitrarie fanno vedere il testo impastato.
                value: String(mon.m.scala)
                options: [
                    { "value": "1",    "label": "100%" },
                    { "value": "1.25", "label": "125%" },
                    { "value": "1.5",  "label": "150%" },
                    { "value": "1.75", "label": "175%" },
                    { "value": "2",    "label": "200%" }
                ]
                onPicked: function (v) {
                    page.apply(mon.m.nome, mon.currentMode, v, mon.m.gradi,
                               (page.it ? "Ingrandimento: " : "Scaling: ")
                               + Math.round(parseFloat(v) * 100) + "%");
                }
            }
        }

        // La rotazione è la modifica che si sbaglia più facilmente e che
        // più difficilmente si disfa: col puntatore che si muove di
        // traverso, ritrovare questo stesso menu è un'impresa. Da qui la
        // conferma a tempo — ed è il motivo per cui esiste.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Rotazione" : "Rotation"
            description: page.it ? "Si torna indietro da soli se non confermi"
                                 : "Reverts on its own unless you confirm"
            searchTerms: "rotazione ruota verticale orientamento"
            controlWidth: 260
            control: S.Tendina {
                width: 260
                // In GRADI, che è quello che c'è scritto sull'etichetta.
                value: String(mon.m.gradi || 0)
                options: [
                    { "value": "0",   "label": page.it ? "Normale" : "Normal" },
                    { "value": "90",  "label": "90°" },
                    { "value": "180", "label": "180°" },
                    { "value": "270", "label": "270°" }
                ]
                onPicked: function (v) {
                    var names = { "0": page.it ? "Normale" : "Normal",
                                  "90": "90°", "180": "180°", "270": "270°" };
                    page.apply(mon.m.nome, mon.currentMode, mon.m.scala, v,
                               (page.it ? "Rotazione: " : "Rotation: ") + names[String(v)]);
                }
            }
        }

        // Spegnere uno schermo si può solo se ne resta almeno un altro:
        // spegnere l'unico significa restare al buio senza modo di
        // riaccenderlo, perché il pannello sparisce insieme allo schermo.
        S.SettingRow {
            width: parent.width
            visible: page.monitors.length > 1
            label: page.it ? "Schermo acceso" : "Display on"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: mon.m.acceso !== false
                onToggled: function (v) {
                    if (v)
                        page.apply(mon.m.nome, mon.currentMode, mon.m.scala, mon.m.gradi,
                                   (page.it ? "Schermo acceso: " : "Display on: ") + mon.m.nome);
                    else
                        page.disable(mon.m.nome);
                }
            }
        }
    }

    /// «60 Hz», «59,94 Hz»: i decimali solo quando ci sono.
    function hzParlante(h) {
        var n = Number(h);
        var s = Math.abs(n - Math.round(n)) < 0.005 ? String(Math.round(n))
                                                    : n.toFixed(2).replace(".", ",");
        return s + " Hz";
    }

    // ── Luce notturna ────────────────────────────────────────────────────
    //
    // Cinque impostazioni che funzionavano e non si potevano cambiare da
    // nessuna parte: c'era la sola levetta nella tendina della barra, quindi
    // la temperatura, l'orario e l'accensione automatica erano scritte nei
    // valori di fabbrica e irraggiungibili. Giacomo, 9 settembre 2026: «ho
    // notato che la funzione luce notturna non funziona più».
    //
    // ── E la riga che dice quando NON può funzionare ─────────────────────
    //
    // La tinta la applica lo SCHERMO, con la sua tabella dei colori — è la
    // strada di `gammastep` e del pannello colori di un monitor. Uno schermo
    // che quella tabella non la prende lascia tutto com'era, e da fuori è
    // identico a una manopola spenta: è così che questa funzione è rimasta
    // rotta due settimane. Adesso il compositore lo DICE (`tintaStrada`), e
    // questa pagina lo ripete a chi guarda invece di lasciarlo indovinare.
    Card {
        heading: page.it ? "Luce notturna" : "Night light"
        note: page._tintaSenzaStrada
              ? (page.it
                 ? "Questo schermo non prende la tabella dei colori: la luce "
                   + "notturna non si vedrà. Non è una tua impostazione "
                   + "sbagliata — è l'hardware che non la offre."
                 : "This screen does not take a colour table: the night light "
                   + "will not show. It is not a setting of yours.")
              : (page.it
                 ? "Toglie il blu dallo schermo la sera. La tinta la applica "
                   + "lo schermo stesso, quindi vale su tutto — giochi e "
                   + "filmati a schermo intero compresi."
                 : "Takes the blue out in the evening. Applied by the screen "
                   + "itself, so it covers everything.")

        S.SettingRow {
            width: parent.width
            label: page.it ? "Luce notturna" : "Night light"
            // Diceva sempre «Accesa adesso» — voleva dire «accendila adesso» —
            // anche con l'interruttore spento e la luce accesa dall'orario:
            // si leggeva come un errore (28 settembre 2026). Adesso dice lo
            // stato. Non si chiede a `Core.LuceNotturna`: qui siamo nel
            // processo delle Impostazioni, e una sua seconda copia manderebbe
            // tinte al compositore.
            description: {
                var manuale = Core.Ipc.get("display.nightLight", false);
                var auto = Core.Ipc.get("display.nightLightAuto", false);
                var da = Number(Core.Ipc.get("display.nightLightFrom", 21));
                var a = Number(Core.Ipc.get("display.nightLightTo", 7));
                var h = page.oraAdesso;
                var dentro = da <= a ? (h >= da && h < a) : (h >= da || h < a);
                if (manuale)
                    return page.it ? "Accesa" : "On";
                if (auto && dentro)
                    return page.it ? "Accesa dall'orario, fino alle " + a + ":00"
                                   : "On from the schedule, until " + a + ":00";
                if (auto)
                    return page.it ? "Si accende da sola alle " + da + ":00"
                                   : "Turns on by itself at " + da + ":00";
                return page.it ? "Spenta" : "Off";
            }
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("display.nightLight", false)
                onToggled: function(v) {
                    Core.Ipc.setSetting("display.nightLight", v);
                    // Si richiede lo stato: è il momento in cui si scopre se
                    // questo schermo la tinta la prende davvero.
                    Qt.callLater(Core.Compositore.chiediStato);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Quanto calda" : "How warm"
            // I due estremi si dicono a parole, o «3800 K» non vuol dire
            // niente a chi non fotografa.
            description: page.it
                ? "6500 K è la luce del giorno e non tocca niente; 2000 K è "
                  + "quasi la luce di una candela"
                : "6500 K is daylight and changes nothing; 2000 K is nearly "
                  + "candlelight"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 2000
                to: 6500
                unit: "intero"
                suffix: "K"
                value: Core.Ipc.get("display.nightLightTemp", 3800)
                onReleased: function(v) {
                    Core.Ipc.setSetting("display.nightLightTemp", Math.round(v));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Si accende da sola" : "Turns on by itself"
            description: page.it ? "A un'ora scelta, e si spegne al mattino"
                                 : "At a chosen hour, off in the morning"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("display.nightLightAuto", false)
                onToggled: function(v) {
                    Core.Ipc.setSetting("display.nightLightAuto", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("display.nightLightAuto", false)
            label: page.it ? "Dalle" : "From"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0
                to: 23
                unit: "intero"
                suffix: ":00"
                value: Core.Ipc.get("display.nightLightFrom", 21)
                onReleased: function(v) {
                    Core.Ipc.setSetting("display.nightLightFrom", Math.round(v));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("display.nightLightAuto", false)
            label: page.it ? "Alle" : "To"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0
                to: 23
                unit: "intero"
                suffix: ":00"
                value: Core.Ipc.get("display.nightLightTo", 7)
                onReleased: function(v) {
                    Core.Ipc.setSetting("display.nightLightTo", Math.round(v));
                }
            }
        }
    }

    // ── Luminosità ───────────────────────────────────────────────────────

    Card {
        heading: Core.Strings.lang === "it" ? "Luminosità" : "Brightness"
        visible: Core.SystemState.hasBrightness
        note: Core.Strings.lang === "it"
              ? "Si regola anche con i tasti dedicati della tastiera."
              : "Also adjustable with the dedicated keyboard keys."

        Ui.Slider {
            width: parent.width
            icon: "sun"
            from: 1
            value: Core.SystemState.brightness
            accent: Theme.Colors.warning
            onMoved: function(v) { Core.SystemState.setBrightness(v); }
        }
    }

    // ── Trasmetti a schermo: la prima connessione ────────────────────────
    //
    // Giacomo, 30 agosto 2026: «se serve anche in impostazioni per la prima
    // connessione». Serve, ma per una ragione diversa da quella che
    // pensavamo: non è il televisore a chiedere di essere accoppiato — è il
    // FIREWALL di questo computer a respingerlo.
    //
    // Un Chromecast non riceve la fotografia: se la va a **prendere**, da un
    // servizio che Minerva apre per il tempo della trasmissione. Con `ufw`
    // acceso quel servizio è irraggiungibile, e il modo in cui si rompe è il
    // peggiore: il televisore ACCETTA il comando, la schermata di Chromecast
    // sparisce, e resta schermo nero. Il sì arriva subito, il no dopo e in
    // silenzio. Visto sulla «TV cameretta» il 30 agosto 2026.
    Card {
        id: trasmetti
        heading: Core.Strings.lang === "it" ? "Trasmetti a schermo"
                                            : "Cast to a screen"
        note: Core.Strings.lang === "it"
              ? "Apre la porta 8010 SOLO verso la tua rete di casa, e solo per "
                + "il tempo di una trasmissione. La chiave resta l'indirizzo, "
                + "non la porta: chi non l'ha ricevuto non ottiene niente."
              : "Opens port 8010 only towards your home network."

        property string esito: ""

        Connections {
            target: Core.Ipc
            function onTrasmettiPermesso(r) {
                if (!r) return;
                trasmetti.esito = r.ok === true
                    ? (Core.Strings.lang === "it" ? "Fatto." : "Done.")
                    : String(r.error || (Core.Strings.lang === "it"
                             ? "Non è riuscito." : "It did not work."));
            }
        }

        Row {
            width: parent.width
            spacing: Theme.Effects.space2

            Ui.SpineButton {
                onClicked: {
                    trasmetti.esito = Core.Strings.lang === "it"
                                      ? "Chiedo la password…" : "Asking…";
                    Core.Ipc.trasmettiApri();
                }
                content: Text {
                    color: Theme.Colors.accent
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    text: Core.Strings.lang === "it" ? "Permetti" : "Allow"
                }
            }

            Ui.SpineButton {
                onClicked: {
                    trasmetti.esito = Core.Strings.lang === "it"
                                      ? "Chiedo la password…" : "Asking…";
                    Core.Ipc.trasmettiChiudi();
                }
                content: Text {
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    text: Core.Strings.lang === "it" ? "Togli il permesso"
                                                     : "Remove"
                }
            }
        }

        Text {
            width: parent.width
            visible: trasmetti.esito !== ""
            wrapMode: Text.WordWrap
            text: trasmetti.esito
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    Text {
        width: parent.width
        visible: page.monitors.length === 0
        wrapMode: Text.WordWrap
        text: Core.Strings.lang === "it"
              ? "Nessuno schermo rilevato. Il compositore non ha risposto: "
                + "prova a riaprire le impostazioni."
              : "No display detected. The compositor did not answer — try "
                + "reopening settings."
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeSM
    }
}
