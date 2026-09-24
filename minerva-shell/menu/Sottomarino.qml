import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ── Il Sottomarino: il menù delle app di Liquid DE ───────────────────────
//
// Giacomo, 23 settembre 2026: «lo farei comparire come un sottomarino
// sfruttando gli angoli attivi, e metterei una ricerca intelligente delle
// app nella quale io possa sia cercare il nome che la sua funzione, come ad
// esempio browser o chrome o navigare il web, e possa vedere sia in vista
// classica a categorie oppure altri tipi, e possa essere visto sia in
// orizzontale che verticale». Il disegno è la pagina «La Riva, studiata
// meglio» (`disegno/`).
//
// Emerge dall'angolo in basso a sinistra: prima il periscopio, una bolla
// nell'angolo, poi lo scafo che sale con una molla. Si apre con la sosta del
// puntatore nell'angolo (`Core.Compositore.angolo`), col tocco di Super, e si
// chiude con Esc, con un clic fuori, o lanciando qualcosa.
//
// La ricerca guarda il nome, e poi quello che il programma dice di sé nel suo
// `.desktop` — nome generico, parole chiave, descrizione, nella lingua
// dell'utente (le legge il demone, `app_scanner.dart`) — più un dizionario di
// sinonimi italiani e quello che si FA con ogni app. Trova anche le azioni:
// «blocca», «notte», «spegni».
//
// Una finestra sola, a tutto schermo e trasparente, che esiste solo mentre il
// menù è aperto: il fondo raccoglie i clic fuori dallo scafo.
PanelWindow {
    id: sub

    /// Vero da quando si apre a quando si chiude.
    property bool aperto: false
    /// Vero mentre la finestra c'è: resta vero durante l'immersione.
    property bool mostrato: false
    /// Lo scafo è salito (dopo il periscopio).
    property bool emerso: false

    property string vista: String(Core.Ipc.get("launcher.vista", "categorie"))
    property bool verticale: Core.Ipc.get("launcher.verticale", false) === true
    property string categoria: "tutte"
    property string cerca: ""
    /// Quanto spazio lasciare in basso: la dock, finché c'è, non si copre.
    property real margineBasso: 0
    /// E in alto: la barra, quando sta in alto, non si copre.
    property real margineAlto: 0

    /// Le misure scelte trascinando i bordi, una per verso.
    property real largO: Number(Core.Ipc.get("launcher.orizzontaleLarghezza", 960))
    property real altO: Number(Core.Ipc.get("launcher.orizzontaleAltezza", 430))
    property real largV: Number(Core.Ipc.get("launcher.verticaleLarghezza", 420))
    /// Vero mentre si trascina un bordo: lo scafo segue il puntatore esatto,
    /// senza molla.
    property bool ridimensionando: false

    /// Un'azione trovata con la ricerca: la esegue la shell.
    signal azione(string id)

    function apri(testo) {
        if (sub.aperto) {
            if (testo) campo.text = testo;
            return;
        }
        sub.cerca = testo || "";
        campo.text = sub.cerca;
        sub.aperto = true;
        sub.mostrato = true;
        sub.emerso = false;
        // Lo scafo emerge 170 ms dopo il PRIMO FOTOGRAMMA, non dopo il
        // comando: se la finestra c'è già (riaperto prima di sparire) subito.
        if (pronto.visto)
            emergi.restart();
        spegni.stop();
    }
    function chiudi() {
        if (!sub.aperto)
            return;
        sub.aperto = false;
        sub.emerso = false;
        spegni.restart();
    }
    function commuta() { sub.aperto ? sub.chiudi() : sub.apri(""); }

    // Le molle solo dopo il primo fotogramma vero (`Ui.Pronto`), e lo
    // scafo emerge solo DOPO che le molle ci sono: prima la finestra misura
    // zero, e una posizione calcolata dalla sua misura volava attraverso lo
    // schermo (il menù «a metà fuori schermo» della prima apertura).
    Ui.Pronto { id: pronto }
    Connections {
        target: pronto
        function onVistoChanged() { if (pronto.visto && sub.aperto && !sub.emerso) emergi.restart(); }
    }

    visible: sub.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-sottomarino"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: sub.aperto ? WlrKeyboardFocus.Exclusive
                                            : WlrKeyboardFocus.None

    // Prima il periscopio, poi lo scafo; il campo prende i tasti quando c'è.
    Timer { id: emergi; interval: Theme.Motion.liquido ? 170 : 0; onTriggered: { sub.emerso = true; campo.forceActiveFocus(); } }
    // Dopo l'immersione la finestra se ne va: niente superficie montata per niente.
    Timer { id: spegni; interval: Theme.Motion.liquido ? 650 : 0; onTriggered: if (!sub.aperto) sub.mostrato = false }

    // ── Il catalogo ─────────────────────────────────────────────────────

    readonly property var categorie: [
        { "id": "internet",   "it": "Internet",   "c": ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
        { "id": "ufficio",    "it": "Ufficio",    "c": ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Calendar"] },
        { "id": "grafica",    "it": "Grafica",    "c": ["Graphics", "Photography", "2DGraphics", "3DGraphics", "VectorGraphics", "RasterGraphics"] },
        { "id": "multimedia", "it": "Multimedia", "c": ["AudioVideo", "Audio", "Video", "Player", "Music"] },
        { "id": "sviluppo",   "it": "Sviluppo",   "c": ["Development", "IDE"] },
        { "id": "giochi",     "it": "Giochi",     "c": ["Game"] },
        { "id": "sistema",    "it": "Sistema",    "c": ["System", "Settings", "Monitor", "PackageManager", "TerminalEmulator"] },
        { "id": "accessori",  "it": "Accessori",  "c": ["Utility", "Accessories", "FileTools", "FileManager", "TextEditor", "Calculator"] }
    ]

    /// Le app appena installate e mai aperte: lo decide il demone
    /// (`isNew`, da `app_novita.dart`), e smettono di esserlo al primo lancio.
    readonly property int nuove: {
        var tutte = Core.Ipc.allApps || [], n = 0;
        for (var i = 0; i < tutte.length; i++) if (tutte[i].isNew) n++;
        return n;
    }
    /// Vero se nella categoria c'è almeno un'app nuova.
    function categoriaNuova(id) {
        if (sub.nuove === 0) return false;
        var cat = null;
        for (var n = 0; n < sub.categorie.length; n++)
            if (sub.categorie[n].id === id) cat = sub.categorie[n];
        var tutte = Core.Ipc.allApps || [];
        for (var i = 0; i < tutte.length; i++) {
            if (!tutte[i].isNew) continue;
            if (!cat) return true;
            var cs = tutte[i].categories || [];
            for (var z = 0; z < cat.c.length; z++)
                if (cs.indexOf(cat.c[z]) !== -1) return true;
        }
        return false;
    }

    /// Quello che si FA con un'app, dalle sue categorie: la vista «Cosa vuoi
    /// fare» e metà della ricerca per funzione. Vale la prima che combacia.
    readonly property var attivita: [
        { "id": "navigare",    "it": "Navigare",    "c": ["WebBrowser"] },
        { "id": "comunicare",  "it": "Comunicare",  "c": ["Email", "InstantMessaging", "Chat", "Telephony", "IRCClient"] },
        { "id": "scrivere",    "it": "Scrivere",    "c": ["WordProcessor", "TextEditor"] },
        { "id": "calcolare",   "it": "Calcolare",   "c": ["Calculator", "Spreadsheet"] },
        { "id": "creare",      "it": "Creare",      "c": ["Graphics", "2DGraphics", "3DGraphics", "VectorGraphics", "RasterGraphics", "AudioVideoEditing", "Photography"] },
        { "id": "ascoltare",   "it": "Ascoltare",   "c": ["Audio", "Music"] },
        { "id": "guardare",    "it": "Guardare",    "c": ["Video", "Viewer", "TV"] },
        { "id": "programmare", "it": "Programmare", "c": ["Development", "IDE", "TerminalEmulator"] },
        { "id": "organizzare", "it": "Organizzare", "c": ["FileManager", "Calendar", "Archiving", "Office"] },
        { "id": "giocare",     "it": "Giocare",     "c": ["Game"] },
        { "id": "sistemare",   "it": "Sistemare",   "c": ["Settings", "System", "Monitor", "PackageManager"] }
    ]

    /// Le parole che vogliono dire la stessa cosa. È quello che fa trovare
    /// Chrome scrivendo «navigare il web».
    readonly property var sinonimi: ({
        "navigare": ["web", "internet", "browser"], "internet": ["web", "browser"],
        "browser": ["web"], "web": ["browser", "internet"],
        "scrivere": ["testo", "text", "editor", "documenti"], "testo": ["text", "editor"],
        "foto": ["immagini", "image", "photo"], "immagini": ["foto", "image"],
        "musica": ["audio", "music", "player"], "video": ["film", "movie", "player"],
        "film": ["video", "movie"], "giocare": ["giochi", "game"], "giochi": ["game"],
        "posta": ["email", "mail"], "email": ["posta", "mail"], "mail": ["posta", "email"],
        "chat": ["messaggi", "messenger"], "messaggi": ["chat", "messenger"],
        "disegnare": ["disegno", "draw", "vector", "grafica"], "cartelle": ["file", "files"],
        "comandi": ["terminale", "terminal", "console", "shell"], "terminale": ["terminal", "console"],
        "programmare": ["codice", "code", "development", "ide"], "codice": ["code"],
        "conti": ["calcolatrice", "calculator"], "calcolatrice": ["calculator"],
        "impostazioni": ["settings", "preferenze"], "ascoltare": ["musica", "audio"],
        "guardare": ["video", "film", "foto"]
    })
    /// Le parole che dicono cosa si vuole FARE. Scrivendo «browser» si vuole
    /// navigare, non un'app che ha «Browser» nel nome: un concetto trovato
    /// vale più del nome (vedi `valuta`).
    readonly property var concetti: ({
        "browser": "navigare", "web": "navigare", "internet": "navigare",
        "navigare": "navigare", "navigatore": "navigare",
        "posta": "comunicare", "email": "comunicare", "mail": "comunicare",
        "chat": "comunicare", "messaggi": "comunicare",
        "scrivere": "scrivere", "editor": "scrivere", "testo": "scrivere",
        "conti": "calcolare", "calcolatrice": "calcolare", "calcolare": "calcolare",
        "disegnare": "creare", "disegno": "creare", "grafica": "creare",
        "musica": "ascoltare", "audio": "ascoltare", "ascoltare": "ascoltare",
        "video": "guardare", "film": "guardare", "guardare": "guardare",
        "programmare": "programmare", "codice": "programmare",
        "cartelle": "organizzare", "giochi": "giocare", "giocare": "giocare"
    })
    readonly property var vuote: ["il", "lo", "la", "i", "gli", "le", "di", "a", "da", "in",
        "con", "su", "per", "un", "una", "e", "del", "della", "voglio", "vorrei", "apri"]

    readonly property var azioni: [
        { "id": "blocca",       "it": "Blocca lo schermo",   "p": "blocca bloccare lock schermo" },
        { "id": "notte",        "it": "Luce notturna",       "p": "luce notturna notte occhi sera" },
        { "id": "dnd",          "it": "Non disturbare",      "p": "non disturbare silenzio notifiche" },
        { "id": "impostazioni", "it": "Impostazioni",        "p": "impostazioni settings preferenze" },
        { "id": "appunti",      "it": "Appunti",             "p": "appunti clipboard copiato copia incolla" },
        { "id": "sospendi",     "it": "Sospendi",            "p": "sospendi dormire sleep" },
        { "id": "riavvia",      "it": "Riavvia",             "p": "riavvia riavviare reboot" },
        { "id": "spegni",       "it": "Spegni",              "p": "spegni spegnere arresta shutdown" },
        { "id": "esci",         "it": "Esci dalla sessione", "p": "esci uscire logout sessione" }
    ]

    function norma(t) {
        var s = String(t || "").toLowerCase();
        try { s = s.normalize("NFD").replace(/[̀-ͯ]/g, ""); } catch (e) {}
        return s;
    }
    function _cheFa(cats) {
        for (var i = 0; i < sub.attivita.length; i++)
            for (var k = 0; k < sub.attivita[i].c.length; k++)
                if (cats.indexOf(sub.attivita[i].c[k]) !== -1)
                    return sub.attivita[i];
        return null;
    }

    /// L'elenco, preparato UNA volta quando il demone lo manda: i testi già
    /// in minuscolo e senza accenti, l'attività già calcolata. Per ogni tasto
    /// si confrontano stringhe pronte.
    readonly property var indice: {
        var tutte = Core.Ipc.allApps || [];
        var out = [];
        for (var i = 0; i < tutte.length; i++) {
            var a = tutte[i];
            var cats = a.categories || [];
            var fa = sub._cheFa(cats);
            out.push({
                "app": a,
                "nome": sub.norma(a.name),
                "generico": sub.norma(a.generico || ""),
                "parole": sub.norma((a.parole || []).join(" ")),
                "descrizione": sub.norma(a.descrizione || ""),
                "fa": fa ? fa.id : "",
                "faNome": fa ? fa.it : "",
                "lanci": a.lanci || 0,
                // Quante volte intorno a quest'ora (il demone conta anche
                // l'ora di ogni lancio): «adesso, di solito».
                "adesso": a.adesso || 0
            });
        }
        out.sort(function(x, y) { return x.nome.localeCompare(y.nome); });
        return out;
    }

    function _inizia(testo, t) {
        if (testo.indexOf(t) === 0) return true;
        var parole = testo.split(/[\s\-;,.]+/);
        for (var i = 0; i < parole.length; i++)
            if (parole[i].indexOf(t) === 0) return true;
        return false;
    }

    /// Quanto una voce risponde alle parole cercate, e perché.
    ///
    /// I pesi dicono cosa conta di più: il nome, poi quello che l'app FA
    /// («navigare» è quello che fanno Chrome e Firefox), poi come si chiama
    /// il suo genere, le sue parole chiave, la descrizione. Una parola trovata
    /// attraverso un sinonimo vale poco più di metà: senza, «navigare il
    /// web» metteva in testa tre strumenti di rete con «Browser» nel nome.
    function valuta(v, parole) {
        var punti = 0, prese = 0, perche = "";
        for (var i = 0; i < parole.length; i++) {
            var t = parole[i];
            var termini = [t].concat(sub.sinonimi[t] || []);
            var meglio = 0, qui = "";
            for (var k = 0; k < termini.length; k++) {
                var x = termini[k];
                var peso = k === 0 ? 1 : 0.55;
                var campi = t.length === 1
                    ? [[100, v.nome, "per nome"]]
                    : [[100, v.nome, "per nome"],
                       [90, v.fa, "perché serve a " + v.faNome.toLowerCase()],
                       [70, v.generico, "perché è un «" + (v.app.generico || "").toLowerCase() + "»"],
                       [50, v.parole, "per «" + x + "»"],
                       [25, v.descrizione, "per quello che dice di sé"]];
                for (var c = 0; c < campi.length; c++) {
                    var testo = campi[c][1];
                    if (!testo) continue;
                    var p = sub._inizia(testo, x) ? campi[c][0]
                          : (t.length > 2 && testo.indexOf(x) !== -1) ? campi[c][0] * 0.6 : 0;
                    p *= peso;
                    if (p > meglio) { meglio = p; qui = campi[c][2]; }
                }
            }
            if (sub.concetti[t] && sub.concetti[t] === v.fa && 110 > meglio) {
                meglio = 110;
                qui = "perché serve a " + v.faNome.toLowerCase();
            }
            if (meglio > 0) { prese++; punti += meglio; if (!perche) perche = qui; }
        }
        return { "punti": punti + Math.min(20, v.lanci) , "prese": prese, "perche": perche };
    }

    function _parole(q) {
        var tutte = sub.norma(q).split(/\s+/);
        var out = [];
        for (var i = 0; i < tutte.length; i++)
            if (tutte[i] !== "" && sub.vuote.indexOf(tutte[i]) === -1)
                out.push(tutte[i]);
        return out;
    }

    /// Quello che il corpo del menù mostra: gruppi con un titolo e le loro
    /// voci. Tutte le viste, e la ricerca, diventano questa forma.
    readonly property var gruppi: {
        var q = sub.cerca.trim();
        var tutte = sub.indice;
        var g = [];
        if (q !== "") {
            var parole = sub._parole(q);
            if (parole.length === 0) return [];
            var az = [];
            for (var a = 0; a < sub.azioni.length; a++) {
                var testoAz = sub.norma(sub.azioni[a].it + " " + sub.azioni[a].p);
                var tutteLe = true;
                for (var p = 0; p < parole.length; p++)
                    if (!sub._inizia(testoAz, parole[p])) { tutteLe = false; break; }
                if (tutteLe) az.push(sub.azioni[a]);
            }
            var ris = [];
            for (var i = 0; i < tutte.length; i++) {
                var r = sub.valuta(tutte[i], parole);
                if (r.prese > 0) ris.push({ "v": tutte[i], "r": r });
            }
            // Se qualcosa risponde a tutte le parole, il resto è rumore.
            var piene = ris.filter(function(e) { return e.r.prese === parole.length; });
            if (piene.length > 0) ris = piene;
            ris.sort(function(x, y) {
                return y.r.prese - x.r.prese || y.r.punti - x.r.punti;
            });
            // Quello che sta molto sotto il migliore è rumore: si tiene chi
            // arriva almeno a metà.
            if (ris.length > 0) {
                var soglia = ris[0].r.punti * 0.5;
                ris = ris.filter(function(e) { return e.r.punti >= soglia; });
            }
            if (az.length > 0)
                g.push({ "titolo": "Azioni", "tipo": "azioni", "voci": az.slice(0, 4) });
            if (ris.length > 0)
                g.push({ "titolo": "App", "tipo": "risultati",
                         "voci": ris.slice(0, 12).map(function(e) {
                             return { "v": e.v, "perche": e.r.perche }; }) });
            return g;
        }
        if (sub.vista === "attivita") {
            var perFa = {};
            for (var j = 0; j < tutte.length; j++) {
                var chiave = tutte[j].fa || "altro";
                (perFa[chiave] = perFa[chiave] || []).push(tutte[j]);
            }
            for (var f = 0; f < sub.attivita.length; f++) {
                var voci = perFa[sub.attivita[f].id];
                if (voci) g.push({ "titolo": sub.attivita[f].it, "tipo": "tessere",
                                   "voci": voci.slice().sort(function(x, y) { return y.lanci - x.lanci; }) });
            }
            if (perFa["altro"]) g.push({ "titolo": "Altro", "tipo": "tessere", "voci": perFa["altro"] });
            return g;
        }
        if (sub.vista === "frequenti") {
            // Prima quelle che a quest'ora si aprono di solito (almeno due
            // volte intorno a quest'ora: una volta sola è un caso), poi le
            // più usate in assoluto.
            var ora = tutte.filter(function(v) { return v.adesso >= 2; })
                           .sort(function(x, y) { return y.adesso - x.adesso; })
                           .slice(0, 6);
            var resto = tutte.filter(function(v) { return ora.indexOf(v) < 0; })
                             .sort(function(x, y) { return y.lanci - x.lanci; });
            if (ora.length > 0)
                g.push({ "titolo": "Adesso, di solito", "tipo": "grandi", "voci": ora });
            g.push({ "titolo": "Le più usate", "tipo": ora.length > 0 ? "tessere" : "grandi",
                     "voci": resto.slice(0, 6) });
            g.push({ "titolo": "Poi", "tipo": "tessere", "voci": resto.slice(6, 30) });
            return g;
        }
        if (sub.vista === "az") {
            var perLettera = {}, lettere = [];
            for (var l = 0; l < tutte.length; l++) {
                var c0 = (tutte[l].app.name || "?").charAt(0).toUpperCase();
                if (!perLettera[c0]) { perLettera[c0] = []; lettere.push(c0); }
                perLettera[c0].push(tutte[l]);
            }
            for (var m = 0; m < lettere.length; m++)
                g.push({ "titolo": lettere[m], "tipo": "righe", "voci": perLettera[lettere[m]] });
            return g;
        }
        // Categorie.
        var cat = null;
        for (var n = 0; n < sub.categorie.length; n++)
            if (sub.categorie[n].id === sub.categoria) cat = sub.categorie[n];
        var scelte = tutte.filter(function(v) {
            if (!cat) return true;
            var cs = v.app.categories || [];
            for (var z = 0; z < cat.c.length; z++)
                if (cs.indexOf(cat.c[z]) !== -1) return true;
            return false;
        });
        g.push({ "titolo": "", "tipo": "tessere", "voci": scelte });
        return g;
    }

    /// Quello che il menù mostra, in una riga per gruppo: «App: Firefox,
    /// Google Chrome». Serve alle prove, che lo chiedono dal canale della
    /// shell (`qs ipc call minerva menu …`).
    function riassunto() {
        var g = sub.gruppi, righe = [];
        for (var i = 0; i < g.length; i++) {
            var nomi = g[i].voci.slice(0, 8).map(function(v) {
                return g[i].tipo === "azioni" ? v.it
                     : g[i].tipo === "risultati" ? v.v.app.name : v.app.name;
            });
            righe.push((g[i].titolo || "Tutte") + ": " + nomi.join(", "));
        }
        return righe.join("\n");
    }

    function lancia(app) {
        Core.Ipc.launchApp(app.exec, app.appId);
        sub.chiudi();
    }
    function esegui(id) {
        sub.chiudi();
        sub.azione(id);
    }
    function primo() {
        var g = sub.gruppi;
        if (g.length === 0) return;
        var v = g[0].voci[0];
        if (g[0].tipo === "azioni") sub.esegui(v.id);
        else sub.lancia(g[0].tipo === "risultati" ? v.v.app : v.app);
    }

    // ── Il fondo: raccoglie i clic fuori ────────────────────────────────
    MouseArea {
        anchors.fill: parent
        enabled: sub.aperto
        // Alla pressione e non al rilascio: vedi `menu/Centro.qml`.
        onPressed: sub.chiudi()
    }

    // ── Il periscopio ───────────────────────────────────────────────────
    Rectangle {
        id: periscopio
        x: 6
        y: sub.height - 6 - height
        width: 34; height: 34
        radius: 17
        color: Theme.Colors.panel
        border.width: 1
        border.color: Qt.alpha(Theme.Colors.accent, 0.55)
        scale: sub.aperto && !sub.emerso ? 1 : 0
        Behavior on scale {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 12; height: 12; radius: 6
            color: Theme.Colors.accent
        }
    }

    // ── Lo scafo ────────────────────────────────────────────────────────
    Rectangle {
        id: scafo
        readonly property int margine: Theme.Effects.space4
        x: margine
        readonly property real largMax: sub.width - 2 * margine
        readonly property real altMax: sub.height - 2 * margine - sub.margineBasso - sub.margineAlto
        width: Math.min(largMax, sub.verticale ? sub.largV : sub.largO)
        height: sub.verticale ? altMax : Math.min(altMax, sub.altO)
        y: sub.emerso ? (sub.verticale ? margine + sub.margineAlto : sub.height - margine - sub.margineBasso - height)
                      : sub.height + 30
        Behavior on y {
            enabled: Theme.Motion.liquido && !sub.ridimensionando && pronto.visto
            SpringAnimation { spring: Theme.Motion.molla * 0.55; damping: 0.42 }
        }
        Behavior on width {
            enabled: Theme.Motion.liquido && !sub.ridimensionando && pronto.visto && sub.emerso
            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
        }
        Behavior on height {
            enabled: Theme.Motion.liquido && !sub.ridimensionando && pronto.visto && sub.emerso
            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
        }
        // Anche la y: in orizzontale lo scafo è appoggiato in basso, e
        // allungandolo verso l'alto la sua cima deve seguire il dito.
        radius: Theme.Effects.radiusLG
        // Quasi pieno: col vetro trasparente di serie i riquadri della
        // scrivania dietro si leggevano ATTRAVERSO le levette e le app.
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        // I clic dentro lo scafo non chiudono.
        MouseArea { anchors.fill: parent; onClicked: {} }

        // ── Le maniglie: si ridimensiona trascinando i bordi ─────────────
        //
        // Il bordo destro cambia la larghezza; in orizzontale il bordo alto
        // cambia l'altezza (lo scafo è appoggiato in basso), e l'angolo in
        // alto a destra tutte e due. Le misure si ricordano, una per verso.
        Maniglia { menu: sub; corpo: scafo; lato: "destra";  anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 12 }
        Maniglia { menu: sub; corpo: scafo; lato: "alto";    visible: !sub.verticale; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 12 }
        Maniglia { menu: sub; corpo: scafo; lato: "angolo";  visible: !sub.verticale; anchors.top: parent.top; anchors.right: parent.right; width: 22; height: 22 }

        Item {
            id: dentro
            anchors.fill: parent
            anchors.margins: Theme.Effects.space4
            opacity: sub.emerso ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

            // La ricerca.
            Rectangle {
                id: capsulaCerca
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 44
                radius: height / 2
                color: campo.activeFocus ? Theme.Colors.raisedHigh : Theme.Colors.raised
                border.width: 1
                border.color: campo.activeFocus ? Qt.alpha(Theme.Colors.accent, 0.5) : "transparent"

                Ui.Icon {
                    id: lente
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: "search"
                    color: Theme.Colors.textFaint
                }
                // Il verso sta qui, tondo, e non nella riga delle viste: nel
                // menù verticale le quattro viste e il pulsante non ci
                // stavano su una riga, e lui finiva sopra le categorie.
                Rectangle {
                    id: verso
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34
                    radius: height / 2
                    color: versoMouse.containsMouse ? Theme.Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                    Text {
                        anchors.centerIn: parent
                        text: "⇆"
                        rotation: sub.verticale ? 90 : 0
                        Behavior on rotation {
                            enabled: Theme.Motion.liquido
                            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                        }
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                    }
                    MouseArea {
                        id: versoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sub.verticale = !sub.verticale;
                            Core.Ipc.setSetting("launcher.verticale", sub.verticale);
                        }
                    }
                    Ui.ToolTipHint {
                        text: sub.verticale ? "Orizzontale" : "Verticale"
                        shown: versoMouse.containsMouse
                    }
                }

                TextInput {
                    id: campo
                    anchors.left: lente.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: verso.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    clip: true
                    onTextChanged: sub.cerca = text
                    Keys.onEscapePressed: sub.chiudi()
                    Keys.onReturnPressed: sub.primo()
                    Keys.onEnterPressed: sub.primo()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: campo.text === ""
                        text: "Nome dell'app o cosa vuoi fare: «navigare il web», «foto», «spegni»…"
                        color: Theme.Colors.textFaint
                        font: campo.font
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            // Le viste, e il verso.
            Item {
                id: riga
                anchors.top: capsulaCerca.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32

                Ui.Goccia {
                    id: gocciaViste
                    radius: height / 2
                    color: Qt.alpha(Theme.Colors.accent, 0.18)
                }

                Row {
                    id: viste
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [
                            { "id": "categorie", "it": "Categorie" },
                            { "id": "attivita",  "it": "Cosa vuoi fare" },
                            { "id": "frequenti", "it": "Frequenti" },
                            { "id": "az",        "it": "A–Z" }
                        ]
                        delegate: Item {
                            id: tab
                            required property var modelData
                            readonly property bool attiva: sub.vista === tab.modelData.id && sub.cerca === ""
                            onAttivaChanged: if (tab.attiva) gocciaViste.attiva = tab
                            Component.onCompleted: if (tab.attiva) gocciaViste.attiva = tab
                            readonly property bool conNuove: tab.modelData.id === "az" && sub.nuove > 0
                            width: tabTesto.implicitWidth + Theme.Effects.space5
                                   + (tab.conNuove ? tabNuove.width + Theme.Effects.space1 : 0)
                            height: 30
                            function scegli() {
                                if (sub.vista === tab.modelData.id && sub.cerca === "") return;
                                campo.text = "";
                                sub.vista = tab.modelData.id;
                                Core.Ipc.setSetting("launcher.vista", tab.modelData.id);
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.Effects.space1
                                Text {
                                    id: tabTesto
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tab.modelData.it
                                    color: tab.attiva ? Theme.Colors.text : Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeSM
                                }
                                Nuova {
                                    id: tabNuove
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: tab.conNuove
                                    testo: sub.nuove === 1 ? "Nuova" : "Nuove"
                                }
                            }
                            // Col solo puntatore, dopo una sosta breve: passarci
                            // sopra per andare altrove non cambia vista.
                            Timer { id: tabSosta; interval: 140; onTriggered: tab.scegli() }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: containsMouse ? tabSosta.restart() : tabSosta.stop()
                                onClicked: tab.scegli()
                            }
                        }
                    }
                }

            }

            // Le categorie, solo nella loro vista.
            Flow {
                id: chips
                anchors.top: riga.bottom
                anchors.topMargin: visible ? Theme.Effects.space2 : 0
                anchors.left: parent.left
                anchors.right: parent.right
                visible: sub.vista === "categorie" && sub.cerca === ""
                height: visible ? implicitHeight : 0
                spacing: 4
                Repeater {
                    model: [{ "id": "tutte", "it": "Tutte" }].concat(sub.categorie)
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool scelta: sub.categoria === chip.modelData.id
                        readonly property bool conNuove: sub.categoriaNuova(chip.modelData.id)
                        width: chipTesto.implicitWidth + Theme.Effects.space4
                               + (chip.conNuove ? chipNuova.width + Theme.Effects.space1 : 0)
                        height: 28
                        radius: height / 2
                        color: chip.scelta ? Qt.alpha(Theme.Colors.accent, 0.18)
                             : chipMouse.containsMouse ? Theme.Colors.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.Effects.space1
                            Text {
                                id: chipTesto
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.it
                                color: chip.scelta ? Theme.Colors.text : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                            Nuova {
                                id: chipNuova
                                anchors.verticalCenter: parent.verticalCenter
                                visible: chip.conNuove
                                testo: "Nuova"
                            }
                        }
                        Timer { id: chipSosta; interval: 140; onTriggered: sub.categoria = chip.modelData.id }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: containsMouse ? chipSosta.restart() : chipSosta.stop()
                            onClicked: sub.categoria = chip.modelData.id
                        }
                    }
                }
            }

            // Il corpo, con la sua barra: con duecento app scorre.
            Ui.Scorrimento {
                bersaglio: corpo
                anchors {
                    right: corpo.right
                    top: corpo.top
                    bottom: corpo.bottom
                }
            }

            Flickable {
                id: corpo
                anchors.top: chips.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                contentHeight: colonna.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Ui.Goccia {
                    id: gocciaVoci
                    radius: Theme.Effects.radiusMD
                }

                Column {
                    id: colonna
                    width: corpo.width
                    spacing: Theme.Effects.space3

                    Text {
                        visible: sub.cerca.trim() !== "" && sub.gruppi.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Nessuna app per «" + sub.cerca.trim()
                              + "». Prova con quello che vuoi fare: «ascoltare», «disegnare», «conti»."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Repeater {
                        model: sub.gruppi
                        delegate: Column {
                            id: gruppo
                            required property var modelData
                            width: colonna.width
                            spacing: Theme.Effects.space1

                            Text {
                                visible: gruppo.modelData.titolo !== ""
                                text: gruppo.modelData.tipo === "righe"
                                      ? gruppo.modelData.titolo
                                      : gruppo.modelData.titolo.toUpperCase()
                                color: gruppo.modelData.tipo === "righe" ? Theme.Colors.accent
                                                                         : Theme.Colors.textFaint
                                font.family: gruppo.modelData.tipo === "righe" ? Theme.Typography.fontMono
                                                                               : Theme.Typography.fontDisplay
                                font.pixelSize: gruppo.modelData.tipo === "righe" ? Theme.Typography.sizeMD
                                                                                  : Theme.Typography.sizeXS
                                font.letterSpacing: gruppo.modelData.tipo === "righe" ? 0 : 1.4
                                leftPadding: 4
                            }

                            Flow {
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: gruppo.modelData.voci
                                    delegate: Voce {
                                        tipo: gruppo.modelData.tipo
                                        goccia: gocciaVoci
                                        larghezzaCorpo: colonna.width
                                        onLanciata: function(app) { sub.lancia(app); }
                                        onEseguita: function(id) { sub.esegui(id); }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Una maniglia per ridimensionare ─────────────────────────────────
    component Maniglia: MouseArea {
        id: man
        property string lato: "destra"
        // Un componente in linea non vede gli id del file che lo contiene:
        // il menù e lo scafo gli si passano.
        property var menu: null
        property Item corpo: null
        property real _x0: 0
        property real _y0: 0
        property real _l0: 0
        property real _a0: 0
        hoverEnabled: true
        preventStealing: true
        cursorShape: man.lato === "destra" ? Qt.SizeHorCursor
                   : man.lato === "alto" ? Qt.SizeVerCursor : Qt.SizeBDiagCursor

        // Il segno che c'è: una lineetta tonda che compare sfiorando il bordo.
        Rectangle {
            visible: man.lato !== "angolo"
            anchors.centerIn: parent
            width: man.lato === "destra" ? 4 : 44
            height: man.lato === "destra" ? 44 : 4
            radius: 2
            color: Theme.Colors.textMuted
            opacity: man.containsMouse || man.pressed ? 0.6 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
        }

        onPressed: function(ev) {
            var p = man.mapToItem(null, ev.x, ev.y);
            man._x0 = p.x; man._y0 = p.y;
            man._l0 = man.corpo.width; man._a0 = man.corpo.height;
            man.menu.ridimensionando = true;
        }
        onPositionChanged: function(ev) {
            if (!man.pressed)
                return;
            var p = man.mapToItem(null, ev.x, ev.y);
            if (man.lato !== "alto") {
                var l = Math.max(380, Math.min(man.corpo.largMax, man._l0 + (p.x - man._x0)));
                if (man.menu.verticale) man.menu.largV = l; else man.menu.largO = l;
            }
            if (man.lato !== "destra" && !man.menu.verticale)
                man.menu.altO = Math.max(280, Math.min(man.corpo.altMax, man._a0 + (man._y0 - p.y)));
        }
        onReleased: {
            man.menu.ridimensionando = false;
            if (man.menu.verticale) {
                Core.Ipc.setSetting("launcher.verticaleLarghezza", Math.round(man.menu.largV));
            } else {
                Core.Ipc.setSetting("launcher.orizzontaleLarghezza", Math.round(man.menu.largO));
                Core.Ipc.setSetting("launcher.orizzontaleAltezza", Math.round(man.menu.altO));
            }
        }
    }

    // ── Una voce del corpo: tessera, tessera grande, riga, risultato, azione
    component Voce: Item {
        id: voce
        required property var modelData
        property string tipo: "tessere"
        property Item goccia: null
        property real larghezzaCorpo: 400
        signal lanciata(var app)
        signal eseguita(string id)

        readonly property bool azione: voce.tipo === "azioni"
        readonly property var app: voce.azione ? null
                                 : (voce.tipo === "risultati" ? voce.modelData.v.app : voce.modelData.app)
        readonly property bool riga: voce.tipo === "righe" || voce.tipo === "risultati"
        readonly property bool grande: voce.tipo === "grandi"

        width: voce.azione ? azioneTesto.implicitWidth + Theme.Effects.space5
             : voce.tipo === "risultati" ? Math.max(260, (voce.larghezzaCorpo - 8) / Math.max(1, Math.floor(voce.larghezzaCorpo / 300)))
             : voce.riga ? Math.min(voce.larghezzaCorpo, 300)
             : voce.grande ? 132 : 108
        height: voce.azione ? 34 : voce.riga ? (voce.tipo === "risultati" ? 52 : 36)
              : voce.grande ? 132 : 104

        Rectangle {
            anchors.fill: parent
            visible: voce.azione
            radius: height / 2
            color: Qt.alpha(Theme.Colors.accent, 0.16)
            border.width: 1
            border.color: Qt.alpha(Theme.Colors.accent, 0.4)
            Text {
                id: azioneTesto
                anchors.centerIn: parent
                text: voce.azione ? voce.modelData.it : ""
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        Image {
            id: icona
            visible: !voce.azione && status === Image.Ready
            source: voce.app && voce.app.icon ? "file://" + voce.app.icon : ""
            sourceSize.width: 96
            sourceSize.height: 96
            asynchronous: true
            smooth: true
            fillMode: Image.PreserveAspectFit
            width: voce.riga ? (voce.tipo === "risultati" ? 34 : 24) : (voce.grande ? 58 : 44)
            height: width
            x: voce.riga ? Theme.Effects.space2 : (voce.width - width) / 2
            y: voce.riga ? (voce.height - height) / 2 : (voce.grande ? 18 : 12)
            scale: !voce.riga && voceMouse.containsMouse ? 1.08 : 1
            transformOrigin: Item.Bottom
            Behavior on scale {
                enabled: Theme.Motion.liquido
                SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
            }
        }
        // Ripiego: l'iniziale in un cerchio.
        Rectangle {
            visible: !voce.azione && icona.status !== Image.Ready
            anchors.fill: icona
            radius: width / 2
            color: Theme.Colors.raisedHigh
            Text {
                anchors.centerIn: parent
                text: voce.app ? String(voce.app.name || "?").charAt(0).toUpperCase() : ""
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: parent.width * 0.42
            }
        }

        Column {
            visible: !voce.azione
            x: voce.riga ? icona.x + icona.width + Theme.Effects.space3 : 4
            y: voce.riga ? (voce.height - height) / 2 : icona.y + icona.height + 8
            width: voce.riga ? voce.width - x - Theme.Effects.space2 : voce.width - 8
            spacing: 1
            Text {
                width: parent.width
                text: voce.app ? voce.app.name : ""
                horizontalAlignment: voce.riga ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: voce.tipo === "risultati" ? Theme.Typography.weightMedium
                                                        : Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }
            Text {
                width: parent.width
                visible: text !== "" && voce.tipo !== "righe"
                text: !voce.app ? ""
                      : voce.tipo === "risultati"
                        ? ((voce.app.generico || "") + (voce.app.generico ? " · " : "")
                           + "trovata " + voce.modelData.perche)
                        : (voce.app.generico || "")
                horizontalAlignment: voce.riga ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        Nuova {
            visible: !voce.azione && !!voce.app && !!voce.app.isNew
            testo: "Nuova"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: voce.riga ? (voce.height - height) / 2 : 4
            anchors.rightMargin: voce.riga ? Theme.Effects.space2 : 4
        }

        MouseArea {
            id: voceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (voce.goccia && !voce.azione) voce.goccia.punta(voce, voceMouse.containsMouse)
            onClicked: voce.azione ? voce.eseguita(voce.modelData.id) : voce.lanciata(voce.app)
        }
    }

    // ── La targhetta «Nuova» ────────────────────────────────────────────
    component Nuova: Rectangle {
        property string testo: "Nuova"
        width: nuovaTesto.implicitWidth + 10
        height: 16
        radius: height / 2
        color: Theme.Colors.accent
        Text {
            id: nuovaTesto
            anchors.centerIn: parent
            text: parent.testo
            color: Theme.Colors.textOnAccent
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: 10
            font.weight: Theme.Typography.weightMedium
        }
    }
}
