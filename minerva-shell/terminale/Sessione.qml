import QtQuick
import Quickshell
import Quickshell.Io
import "../theme" as Theme
import "../core" as Core

// Sessione — Una shell, il suo motore, la sua griglia. Una per scheda.
//
// ── Cosa sta qui e cosa no ─────────────────────────────────────────────────
//
// Qui: il processo del motore (`minerva-terminale-motore`, uno per
// sessione), i messaggi nei due versi, la tastiera e il mouse tradotti in
// messaggi, la selezione e la copia. NON qui: l'emulazione (nel motore) e il
// disegno (in `Griglia`). Questa è la parte che sa di Quickshell.
//
// ── La tastiera ────────────────────────────────────────────────────────────
//
// Qt dà il tasto (`event.key`) e il testo (`event.text`); la traduzione in
// byte la fa il motore, perché dipende dai modi del terminale (le frecce
// cambiano forma se `vim` ha acceso DECCKM). Qui si manda il NOME del tasto
// e i modificatori, e basta. Le combinazioni che sono nostre — copia,
// incolla, ingrandisci — si fermano prima.
Item {
    id: sessione

    /// Da dove far partire la shell, e cosa eseguire invece di lei.
    property string cartella: ""
    property string esegui: ""
    property string shell: ""

    /// Dove stanno il motore e lo pseudo-terminale. Il motore compilato sta
    /// con il demone; se manca si va da sorgente con `dart run`, che parte
    /// più lento ma parte.
    property string radice: ""
    readonly property string pty: Core.Ipc.cartellaBin + "/minerva-pty"

    property var tavolozza: null
    property int corpo: Core.Ipc.get("terminale.corpo", 14)
    /// Quante righe tenere dietro lo schermo: si dà al motore alla nascita
    /// (cambiarla vale per le schede aperte dopo).
    readonly property int scrollbackMassimo: Core.Ipc.get("terminale.scrollback", 10000)
    /// Il campanello si sente solo se lo si vuole: a chi lo spegne non
    /// arriva nemmeno il segnale.
    readonly property bool campanelloAcceso: Core.Ipc.get("terminale.campanello", true)
    // ── Il carattere, e i glifi dei prompt ──────────────────────────────
    //
    // Il prompt di Giacomo (starship) è pieno di simboli nell'area d'uso
    // privato di Unicode — il ramo di git, la cartella, l'orologio — che
    // stanno solo nei «Nerd Font». Alacritty li trova da solo perché chiede
    // a fontconfig «chi ha questo glifo»; Qt non lo fa per quell'area, e
    // disegna dei quadratini. Visto in fotografia il 15 settembre 2026.
    //
    // Quindi, se non si è scelto un carattere: un Nerd Font monospazio se
    // ce n'è uno installato (ne ha 84), altrimenti quello del tema. Chi
    // vuole il carattere del tema lo scrive nelle impostazioni.
    property string carattere: {
        var c = String(Core.Ipc.get("terminale.carattere", "") || "");
        if (c !== "") return c;
        var famiglie = Qt.fontFamilies();
        var preferiti = ["JetBrainsMono Nerd Font Mono", "MesloLGS Nerd Font Mono",
                         "FiraCode Nerd Font Mono", "Hack Nerd Font Mono"];
        for (var i = 0; i < preferiti.length; i++)
            if (famiglie.indexOf(preferiti[i]) !== -1) return preferiti[i];
        for (var k = 0; k < famiglie.length; k++)
            if (famiglie[k].indexOf("Nerd Font Mono") !== -1) return famiglie[k];
        return Theme.Typography.fontMono;
    }

    // ── Lo stato che il motore racconta ──────────────────────────────────
    property string titolo: ""
    property string cartellaAdesso: ""
    property bool schermoAlternativo: false
    property int modoMouse: 0
    property int scrollback: 0
    property int scarto: 0
    property bool pronta: false
    property bool finita: false
    property int codiceUscita: 0
    /// I marcatori dei blocchi arrivano qui (tappa 2 li usa).
    signal blocco(var m)
    signal campanello()
    signal chiusa(int codice)
    /// Dopo la fine, un tasto: chi ha la scheda la può togliere.
    signal congedo()
    signal titoloCambiato(string t)

    readonly property bool haFuoco: tasti.activeFocus

    function prendiFuoco() { tasti.forceActiveFocus(); }

    // ── Il motore ────────────────────────────────────────────────────────
    Process {
        id: motore
        stdinEnabled: true
        command: {
            var compilato = sessione.radice + "/minervad/build/minerva-terminale-motore";
            var base = [compilato];
            var argomenti = ["--pty", sessione.pty,
                             "--colonne", "" + griglia.colonne,
                             "--righe", "" + griglia.righeVisibili];
            if (sessione.cartella !== "") argomenti.push("--cartella", sessione.cartella);
            if (sessione.esegui !== "") argomenti.push("--esegui", sessione.esegui);
            if (sessione.shell !== "") argomenti.push("--shell", sessione.shell);
            argomenti.push("--scrollback", "" + sessione.scrollbackMassimo);
            argomenti.push("--dizionario", sessione.radice + "/config/dizionario-comandi.json");
            argomenti.push("--integrazione", sessione.radice + "/config/terminale");
            // Con `sh -c` si sceglie al volo: il compilato se c'è, altrimenti
            // `dart run` dai sorgenti. Gli argomenti passano come `$@`, mai
            // dentro la riga.
            return ["sh", "-c",
                    'c="$1"; r="$2"; shift 2; if [ -x "$c" ]; then exec "$c" "$@"; else cd "$r/minervad" && exec dart run bin/terminale.dart "$@"; fi',
                    "sh", compilato, sessione.radice].concat(argomenti);
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (riga) { sessione._dalMotore(riga); }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (riga) {
                if (riga.trim() !== "")
                    console.log("[MINERVA][Terminale] " + riga);
            }
        }
        onExited: function (codice) {
            // Una sessione SMONTATA (la scheda è stata tolta) non deve dire
            // «sono finita»: il segnale arriverebbe a un delegato con un
            // indice ormai di un'altra scheda, e chiuderebbe quella. Visto
            // il 15 settembre 2026: `--esegui htop` chiudeva la finestra
            // intera, perché la scheda automatica sostituita, morendo,
            // chiudeva quella di htop.
            if (sessione.smontata) return;
            if (!sessione.finita) {
                sessione.finita = true;
                sessione.chiusa(codice);
            }
        }
    }

    Component.onCompleted: {
        // La griglia deve avere una misura prima che il motore parta, o la
        // shell nasce a 80×24 e un istante dopo si ridimensiona.
        Qt.callLater(function () { motore.running = true; });
    }

    function manda(m) {
        if (!motore.running) return;
        motore.write(JSON.stringify(m) + "\n");
    }

    function _dalMotore(riga) {
        var m;
        try { m = JSON.parse(riga); } catch (e) { return; }
        switch (m.t) {
        case "bloccoAutomatico":
            registro.aggiorna(m);
            break;
        case "predizione":
            compositore.risposta(m);
            break;
        case "confermaIncolla":
        case "erroreIncolla":
            compositore.chiedi(m);
            break;
        case "incollato":
            compositore.chiudi();
            break;
        case "pronto":
            sessione.pronta = true;
            sessione._mandaMisura();
            break;
        case "righe":
            sessione.scarto = m.scarto;
            griglia.aggiorna(m.righe, m.tutte);
            break;
        case "cursore":
            griglia.cursore = { "c": m.c, "r": m.r, "v": m.v, "f": m.f };
            break;
        case "stato":
            sessione.schermoAlternativo = m.alt === true;
            sessione.modoMouse = m.mouse || 0;
            sessione.scrollback = m.scrollback || 0;
            sessione.scarto = m.scarto || 0;
            sessione.cartellaAdesso = m.cartella || "";
            if (m.titolo !== sessione.titolo) {
                sessione.titolo = m.titolo || "";
                sessione.titoloCambiato(sessione.titolo);
            }
            break;
        case "blocco":
            sessione.blocco(m);
            break;
        case "campanello":
            if (sessione.campanelloAcceso) sessione.campanello();
            break;
        case "fine":
            if (sessione.smontata) break;
            sessione.finita = true;
            sessione.codiceUscita = m.codice;
            sessione.chiusa(m.codice);
            break;
        }
    }

    // ── La misura ────────────────────────────────────────────────────────
    //
    // Non a ogni pixel: mentre si trascina il bordo la finestra cambia
    // venti volte al secondo, e ogni misura è un SIGWINCH alla shell che
    // ridisegna tutto. Un battito di attesa, e si manda l'ultima.
    Timer {
        id: misuraDopo
        interval: 40
        onTriggered: sessione._mandaMisura()
    }
    function _mandaMisura() {
        if (!sessione.pronta) return;
        sessione.manda({ "t": "misura", "c": griglia.colonne, "r": griglia.righeVisibili });
    }
    Connections {
        target: griglia
        function onColonneChanged() { misuraDopo.restart(); }
        function onRigheVisibiliChanged() { misuraDopo.restart(); }
    }

    // ── La griglia ───────────────────────────────────────────────────────
    Griglia {
        id: griglia
        anchors.fill: parent
        anchors.margins: Theme.Effects.space2
        anchors.bottomMargin: compositore.height + 12
        anchors.rightMargin: registro.visible ? registro.width + 12 : Theme.Effects.space2
        tavolozza: sessione.tavolozza
        corpo: sessione.corpo
        carattere: sessione.carattere
        haFuoco: sessione.haFuoco
    }

    // ── Il campanello, che si vede ───────────────────────────────────────
    //
    // Un lampo dell'accento sulla griglia, 120 ms: il campanello «visivo» di
    // ogni terminale. Suonare davvero vorrebbe dire un processo audio per
    // ogni BEL, e un `cat` di un file binario ne manda cento al secondo.
    Rectangle {
        id: lampo
        anchors.fill: griglia
        color: Theme.Colors.accent
        opacity: 0
        visible: opacity > 0
        NumberAnimation on opacity {
            id: lampoAnim
            running: false
            from: 0.25; to: 0
            duration: Theme.Motion.instant
        }
    }
    onCampanello: { lampoAnim.restart(); }

    /// Lo scrollback si scorre da qui.
    function scorri(di) { sessione.manda({ "t": "scorri", "di": di }); }
    function incolla(testo) {
        if (testo === undefined || testo === null || testo === "") return;
        sessione.manda({ "t": "incolla", "testo": String(testo) });
    }
    function comando(riga) { sessione.manda({ "t": "comando", "riga": riga }); }
    function copia() {
        var t = griglia.testoSelezionato();
        if (t !== "") Quickshell.clipboardText = t;
    }

    // ── La tastiera ──────────────────────────────────────────────────────
    Item {
        id: tasti
        anchors.fill: parent
        focus: true

        readonly property var nomi: ({
            [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right",
            [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_Insert]: "Insert", [Qt.Key_Delete]: "Delete",
            [Qt.Key_PageUp]: "PageUp", [Qt.Key_PageDown]: "PageDown",
            [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Enter", [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Backtab",
            [Qt.Key_Backspace]: "Backspace", [Qt.Key_Escape]: "Escape", [Qt.Key_Space]: "Space",
            [Qt.Key_F1]: "F1", [Qt.Key_F2]: "F2", [Qt.Key_F3]: "F3", [Qt.Key_F4]: "F4",
            [Qt.Key_F5]: "F5", [Qt.Key_F6]: "F6", [Qt.Key_F7]: "F7", [Qt.Key_F8]: "F8",
            [Qt.Key_F9]: "F9", [Qt.Key_F10]: "F10", [Qt.Key_F11]: "F11", [Qt.Key_F12]: "F12"
        })

        Keys.onPressed: function (event) {
            // ── A shell finita, un tasto qualunque congeda la scheda ─────
            //
            // Un comando lanciato con `--esegui` che finisce male (un
            // programma che non c'è, un errore) lascerebbe la scheda
            // chiudersi con dentro l'unica riga che spiegava perché.
            // Alacritty fa così, e si resta a chiedersi cos'era successo.
            // Qui la scheda resta, con la riga e il codice, finché non si
            // preme un tasto.
            if (sessione.finita) {
                sessione.congedo();
                event.accepted = true;
                return;
            }
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            var alt = (event.modifiers & Qt.AltModifier) !== 0;
            var shift = (event.modifiers & Qt.ShiftModifier) !== 0;

            // ── Le nostre: copia, incolla, scorri ────────────────────
            if (ctrl && shift) {
                if (event.key === Qt.Key_Space) { compositore.apri(); event.accepted = true; return; }
                if (event.key === Qt.Key_C) { sessione.copia(); event.accepted = true; return; }
                if (event.key === Qt.Key_V) { sessione.incolla(Quickshell.clipboardText); event.accepted = true; return; }
            }
            if (shift && !ctrl && !alt) {
                if (event.key === Qt.Key_PageUp) { sessione.scorri(griglia.righeVisibili - 1); event.accepted = true; return; }
                if (event.key === Qt.Key_PageDown) { sessione.scorri(-(griglia.righeVisibili - 1)); event.accepted = true; return; }
                if (event.key === Qt.Key_Home && sessione.scrollback > 0) { sessione.scorri(sessione.scrollback); event.accepted = true; return; }
                if (event.key === Qt.Key_End) { sessione.scorri(0); event.accepted = true; return; }
            }
            // Ingrandire il testo: Ctrl e più/meno/zero, come dappertutto.
            if (ctrl && !alt && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) {
                sessione.cambiaCorpo(1); event.accepted = true; return;
            }
            if (ctrl && !alt && (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore)) {
                sessione.cambiaCorpo(-1); event.accepted = true; return;
            }
            if (ctrl && !alt && event.key === Qt.Key_0) {
                sessione.cambiaCorpo(0); event.accepted = true; return;
            }
            // I tasti solo-modificatore non sono un tasto.
            if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift
                    || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta
                    || event.key === Qt.Key_AltGr || event.key === Qt.Key_CapsLock)
                return;
            var nome = tasti.nomi[event.key];
            var testo = event.text || "";
            if (nome === undefined) {
                if (testo === "") return;
                nome = "";
            }
            // Selezionando si è visto: al primo tasto la selezione se ne va.
            griglia.selezioneAttiva = false;
            sessione.manda({ "t": "tasto", "k": nome, "testo": testo,
                             "ctrl": ctrl, "alt": alt, "shift": shift });
            event.accepted = true;
        }
    }

    function cambiaCorpo(delta) {
        var nuovo = delta === 0 ? 14 : Math.max(8, Math.min(32, sessione.corpo + delta));
        Core.Ipc.setSetting("terminale.corpo", nuovo);
    }

    onActiveFocusChanged: sessione.manda({ "t": "fuoco", "dentro": sessione.haFuoco })
    onHaFuocoChanged: sessione.manda({ "t": "fuoco", "dentro": sessione.haFuoco })

    // ── Il cartello di fine, per i comandi finiti male ───────────────────
    Rectangle {
        visible: sessione.finita && sessione.esegui !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 30
        color: sessione.codiceUscita === 0 ? Theme.Colors.membrane
                                           : Qt.alpha(Theme.Colors.danger, 0.22)

        Text {
            anchors.centerIn: parent
            text: (sessione.codiceUscita === 0
                   ? (Core.Strings.lang === "it" ? "Il comando è finito" : "The command has finished")
                   : (Core.Strings.lang === "it" ? "Il comando è finito con codice " : "The command exited with code ")
                     + sessione.codiceUscita)
                  + (Core.Strings.lang === "it" ? " · premi un tasto per chiudere" : " · press a key to close")
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    Blocchi {
        id: registro
        z: 9
        visible: !sessione.schermoAlternativo && sessione.esegui === "" && sessione.width >= 640
        width: aperto ? Math.min(330, sessione.width * 0.36) : 105
        anchors.top: parent.top; anchors.right: parent.right
        anchors.bottom: compositore.top; anchors.margins: 6
        onRiproponi: function(comando) {
            compositore.apri(); compositore.accetta(comando);
        }
    }

    RigaComando {
        id: compositore
        z: 10
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom; anchors.margins: 6
        onPredici: function(testo) { sessione.manda({t: "predici", testo: testo}); }
        onPrepara: function(testo) { sessione.manda({t: "prepara", testo: testo}); }
        onConfermaIncolla: sessione.manda({t: "confermaIncolla"})
        onAnnullaIncolla: sessione.manda({t: "annullaIncolla"})
        onRestituisciFuoco: sessione.prendiFuoco()
    }

    // ── Il mouse ─────────────────────────────────────────────────────────
    //
    // Se il programma vuole il mouse (`vim` con `set mouse=a`, `htop`) il
    // clic va a lui; altrimenti seleziona. La rotella scorre lo scrollback
    // — o, sullo schermo alternativo, diventa le frecce.
    MouseArea {
        id: mouse
        anchors.fill: griglia
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: sessione.modoMouse === 1003
        cursorShape: Qt.IBeamCursor

        function cella(mx, my) {
            return { "c": Math.max(0, Math.min(griglia.colonne - 1, Math.floor(mx / griglia.cellaL))),
                     "r": Math.max(0, Math.min(griglia.righeVisibili - 1, Math.floor(my / griglia.cellaA))) };
        }
        function bottone(b) { return b === Qt.LeftButton ? 0 : (b === Qt.MiddleButton ? 1 : 2); }
        function mods(m) {
            return { "shift": (m & Qt.ShiftModifier) !== 0, "alt": (m & Qt.AltModifier) !== 0,
                     "ctrl": (m & Qt.ControlModifier) !== 0 };
        }

        property bool selezionando: false

        onPressed: function (e) {
            tasti.forceActiveFocus();
            var c = mouse.cella(e.x, e.y);
            // Con Shift si seleziona anche quando il programma vuole il
            // mouse: è la scappatoia di ogni terminale.
            if (sessione.modoMouse !== 0 && !(e.modifiers & Qt.ShiftModifier)) {
                var md = mouse.mods(e.modifiers);
                sessione.manda({ "t": "mouse", "tipo": "premi", "x": c.c, "y": c.r,
                                 "b": mouse.bottone(e.button), "shift": md.shift, "alt": md.alt, "ctrl": md.ctrl });
                return;
            }
            if (e.button === Qt.MiddleButton) {
                sessione.incolla(Quickshell.clipboardText);
                return;
            }
            if (e.button === Qt.LeftButton) {
                griglia.selezioneAttiva = false;
                griglia.selC1 = c.c; griglia.selR1 = c.r;
                griglia.selC2 = c.c; griglia.selR2 = c.r;
                mouse.selezionando = true;
            }
        }
        onPositionChanged: function (e) {
            var c = mouse.cella(e.x, e.y);
            if (mouse.selezionando) {
                griglia.selC2 = c.c; griglia.selR2 = c.r;
                griglia.selezioneAttiva = !(griglia.selC1 === griglia.selC2 && griglia.selR1 === griglia.selR2);
                if (griglia.selezioneAttiva) { griglia._tutto = true; griglia.requestPaint(); }
                return;
            }
            if (sessione.modoMouse >= 1002) {
                var md = mouse.mods(e.modifiers);
                var b = (e.buttons & Qt.LeftButton) ? 0 : ((e.buttons & Qt.MiddleButton) ? 1 : ((e.buttons & Qt.RightButton) ? 2 : null));
                sessione.manda({ "t": "mouse", "tipo": "muovi", "x": c.c, "y": c.r, "b": b,
                                 "shift": md.shift, "alt": md.alt, "ctrl": md.ctrl });
            }
        }
        onReleased: function (e) {
            var c = mouse.cella(e.x, e.y);
            if (mouse.selezionando) {
                mouse.selezionando = false;
                // Selezionare copia subito, come in ogni terminale: è la
                // «selezione primaria» che poi si incolla col tasto centrale.
                if (griglia.selezioneAttiva) Quickshell.clipboardText = griglia.testoSelezionato();
                return;
            }
            if (sessione.modoMouse !== 0) {
                var md = mouse.mods(e.modifiers);
                sessione.manda({ "t": "mouse", "tipo": "lascia", "x": c.c, "y": c.r,
                                 "b": mouse.bottone(e.button), "shift": md.shift, "alt": md.alt, "ctrl": md.ctrl });
            }
        }
        onWheel: function (e) {
            var c = mouse.cella(e.x, e.y);
            var dy = e.angleDelta.y > 0 ? -1 : 1;
            var md = mouse.mods(e.modifiers);
            sessione.manda({ "t": "mouse", "tipo": "rotella", "x": c.c, "y": c.r, "dy": dy,
                             "shift": md.shift, "alt": md.alt, "ctrl": md.ctrl });
            e.accepted = true;
        }
    }

    property bool smontata: false
    Component.onDestruction: {
        sessione.smontata = true;
        if (motore.running) sessione.manda({ "t": "chiudi" });
    }
}
