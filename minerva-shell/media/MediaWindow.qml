import QtQuick
import QtMultimedia
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// MediaWindow — La finestra di Minerva Media.
//
// Quattro pagine in una colonna di sinistra: Player (il lettore con la
// playlist della cartella dei download), Taglia (il trimmer a onde), Download
// (indirizzo, ricerca e risultati), Esplora (una cartella qualunque del
// disco).
//
// Il riproduttore è uno solo e vale per tutto: l'audio disegna il suo
// visualizzatore, il video la sua superficie — e quando il video va in PiP
// cambia solo la proprietà `videoOutput`, la musica non se ne accorge.
FloatingWindow {
    id: finestra

    visible: Core.Ipc.prontoADipingere && !finestra.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    property bool dormiente: false
    signal requestClose()
    onClosed: finestra.requestClose()

    /// Il percorso con cui siamo stati lanciati (da `MINERVA_MEDIA_APRI`).
    property string initialPath: ""

    title: Core.Strings.lang === "it" ? "Minerva · Media" : "Minerva · Media"
    // ── Il colore lo mette la FINESTRA, e costa quindici megabyte di meno ─
    //
    // Il 2 settembre 2026 qui c'era `color: "transparent"` più un
    // `Ui.FondoFinestra` — un rettangolo a tutta finestra col raggio — per
    // arrotondare gli angoli, che Giacomo aveva chiesto.
    //
    // Funzionava, e si è visto nelle fotografie. Costava però **quindici
    // megabyte per applicazione**, misurati: 55 MB senza, 69-72 con. Provato
    // in quattro modi per isolarne la causa — raggio zero, finestra opaca,
    // senza `z: -1` — e il conto non cambiava: in Qt Quick col renderer
    // software un rettangolo grande quanto la finestra costa così, comunque
    // lo si scriva.
    //
    // Su una scrivania che pesa 430 MB, quindici per applicazione non è un
    // prezzo che si paga per un angolo tondo. Gli angoli si faranno nel
    // COMPOSITORE, dove costano una volta sola e valgono anche per i
    // programmi degli altri — che è poi dove deve stare anche il «corpo
    // unico» fra barra e finestra.
    color: Theme.Colors.window
    implicitWidth: 1120
    implicitHeight: 720
    minimumSize: Qt.size(960, 600)

    // ── Il motore ────────────────────────────────────────────────────────

    MediaBackend {
        id: backend

        onResultsReady: function (r) {
            risultati.clear();
            for (var i = 0; i < r.length; i++)
                risultati.append(r[i]);
            finestra._statoRicerca = r.length === 0
                ? (Core.Strings.lang === "it" ? "Nessun risultato."
                                              : "No results.")
                : "";
        }

        onDownloadStatus: function (m) {
            finestra._statoDownload = m;
            finestra._downloadErrato = false;
        }

        onDownloadFinished: function (percorso, titolo) {
            finestra._statoDownload = (Core.Strings.lang === "it"
                                       ? "Scaricato: " : "Downloaded: ")
                                      + (titolo || "");
            finestra._downloadErrato = false;
            finestra._aggiungiAllaPlaylist(percorso, titolo);
            finestra.riproduciFile(percorso, titolo);
        }

        onDownloadError: function (m) {
            finestra._statoDownload = m || (Core.Strings.lang === "it"
                                            ? "Errore." : "Error.");
            finestra._downloadErrato = true;
        }

        onWaveformReady: function (percorso, durata) {
            finestra._ondaPercorso = percorso;
            finestra._durataTaglio = durata;
            if (finestra._finePx <= 0)
                finestra._finePx = Math.max(1, zonaOnda.width);
            finestra._aggiornaSelezione();
            finestra._taglioPronto = durata > 0;
            finestra._statoTaglio = "";
        }

        onWaveformError: function (m) {
            finestra._statoTaglio = m || (Core.Strings.lang === "it"
                                          ? "Errore." : "Error.");
            finestra._taglioPronto = false;
        }

        onTrimFinished: function (percorso) {
            finestra._taglioFatto = percorso;
            finestra._statoTaglio = "";
            finestra._aggiungiAllaPlaylist(percorso);
        }

        onTrimError: function (m) {
            finestra._statoTaglio = m || (Core.Strings.lang === "it"
                                          ? "Errore." : "Error.");
        }

        onElencoPronto: function (file, playlist) {
            if (playlist)
                finestra._riempiPlaylist(file);
            else
                finestra._riempiEsplora(file);
        }

        onElencoError: function (m) {
            finestra._statoEsplora = m || "";
        }
    }

    PiPWindow {
        id: pip
        riproduttore: player
        onChiuso: function () {
            player.videoOutput = videoPrincipale;
        }
        onSuccessivoRichiesto: function () {
            finestra.successivo();
        }
        onPrecedenteRichiesto: function () {
            finestra.precedente();
        }
    }

    Ui.Condividi { id: condividi }

    // ── Scegliere si fa col mouse ────────────────────────────────────────
    //
    // Prima l'unico modo di aprire qualcosa che non fosse nella cartella dei
    // download era **scrivere il percorso a mano** nella pagina Esplora, e lo
    // stesso per il file da tagliare. Il nostro selettore esisteva già —
    // `ui/Scegli.qml`, quello della Custodia — e non lo usava nessuno.
    //
    // Giacomo, 4 settembre 2026: «rendi tutti i passaggi a portata di click».
    property string _scopoScelta: ""

    function scegli(scopo, titolo, daDove) {
        finestra._scopoScelta = scopo;
        selettore.titolo = titolo || "";
        selettore.soloCartelle = (scopo === "cartella");
        selettore.apri(daDove || "");
    }

    Ui.Scegli {
        id: selettore
        // Sotto la barra del titolo: mentre si sceglie, la finestra resta
        // chiudibile e trascinabile come sempre.
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        soloCartelle: false

        onScelto: function (percorso) {
            switch (finestra._scopoScelta) {
            case "riproduci":
                finestra.apriPercorso(percorso);
                break;
            case "taglia":
                campoTaglio.text = percorso;
                finestra.caricaOnda(percorso);
                break;
            case "cartella":
                campoCartella.text = percorso;
                finestra._apriCartella();
                break;
            }
        }
    }

    // ── Il volume, che diceva il falso ───────────────────────────────────
    //
    // Qui c'era `AudioOutput { id: uscitaAudio }` e basta: nessun volume
    // impostato, quindi l'unità. Il cursore accanto al play, però, nasceva a
    // 70. All'avvio il numero sullo schermo e il suono nelle casse dicevano
    // due cose diverse, e il primo che si spostava era quello che aveva
    // ragione. Spostandolo non se ne ricordava niente: al riavvio si tornava
    // alla stessa bugia.
    AudioOutput {
        id: uscitaAudio
        volume: finestra.muto ? 0 : finestra.volume / 100
    }

    MediaPlayer {
        id: player
        audioOutput: uscitaAudio
        videoOutput: videoPrincipale
        onPositionChanged: {
            if (!finestra.cercando)
                finestra.progresso = player.position;
        }
        onDurationChanged: finestra.durata = player.duration
        onMediaStatusChanged: function (stato) {
            if (stato === MediaPlayer.EndOfMedia && !spiaAnteprima.running)
                finestra._finito();
        }
    }

    // ── La tastiera ──────────────────────────────────────────────────────
    //
    // In tutto `media/` non c'era **una** scorciatoia: né spazio, né frecce,
    // né Esc. Un lettore video senza barra spaziatrice è una cosa che si usa
    // con il mouse e basta, e a schermo intero il mouse non aveva più niente
    // da premere.
    //
    // `_scrivendo` è la guardia che serve a tutte: `Shortcut` scatta
    // dovunque sia il fuoco, quindi senza di lei premere spazio dentro il
    // campo dell'indirizzo metterebbe in pausa invece di scrivere uno spazio.
    // Si riconosce un campo di testo da `cursorPosition`, che hanno solo
    // loro.
    //
    // L'elemento col fuoco si chiede a un elemento DENTRO la finestra
    // (`Window.activeFocusItem`, agganciata): la finestra di Quickshell una
    // proprietà `activeFocusItem` non ce l'ha, valeva sempre `undefined`, e
    // spazio e K scritti nel campo dell'indirizzo mettevano in pausa invece
    // di scrivere (provato il 5 ottobre 2026).
    readonly property bool _scrivendo: {
        var f = sondaFuoco.Window.activeFocusItem;
        return f !== null && f !== undefined
               && f.cursorPosition !== undefined;
    }
    Item { id: sondaFuoco; visible: false }

    Shortcut {
        sequences: ["Space", "K"]
        enabled: !finestra._scrivendo
        onActivated: { finestra.svegliaComandi(); finestra.alternaRiproduzione(); }
    }
    Shortcut {
        sequence: "Right"
        enabled: !finestra._scrivendo
        onActivated: { finestra.svegliaComandi(); finestra.salta(10); }
    }
    Shortcut {
        sequence: "Left"
        enabled: !finestra._scrivendo
        onActivated: { finestra.svegliaComandi(); finestra.salta(-10); }
    }
    Shortcut {
        sequence: "Up"
        enabled: !finestra._scrivendo
        onActivated: {
            finestra.svegliaComandi();
            finestra.cambiaVolume(finestra.volume + 5, true);
        }
    }
    Shortcut {
        sequence: "Down"
        enabled: !finestra._scrivendo
        onActivated: {
            finestra.svegliaComandi();
            finestra.cambiaVolume(finestra.volume - 5, true);
        }
    }
    Shortcut {
        sequence: "M"
        enabled: !finestra._scrivendo
        onActivated: { finestra.svegliaComandi(); finestra.alternaMuto(); }
    }
    Shortcut {
        sequence: "F"
        enabled: !finestra._scrivendo
        onActivated: finestra.alternaPalcoPieno()
    }
    Shortcut {
        // Esc esce dallo schermo intero e non chiude la finestra: chiudere
        // con Esc un lettore che sta suonando è il modo più veloce di perdere
        // il posto in cui si era.
        sequence: "Escape"
        enabled: finestra.palcoPieno
        onActivated: finestra.alternaPalcoPieno()
    }

    // ── Lo stato ─────────────────────────────────────────────────────────

    property int pagina: 0

    /// Il volume, da 0 a 100, e il muto. Si ricordano tutti e due.
    property real volume: Core.Ipc.get("media.volume", 70)
    property bool muto: Core.Ipc.get("media.muto", false)

    /// Che cosa si fa quando un brano finisce: `no`, `tutto`, `uno`.
    ///
    /// «tutto» era il comportamento di prima, ed era implicito: `successivo()`
    /// ripartiva da capo in fondo alla scaletta e non c'era modo di dirle di
    /// smettere. Adesso è una scelta, e le altre due esistono.
    property string ripeti: Core.Ipc.get("media.ripeti", "tutto")
    property bool casuale: Core.Ipc.get("media.casuale", false)

    function cambiaVolume(v, salva) {
        finestra.volume = Math.max(0, Math.min(100, v));
        if (finestra.volume > 0)
            finestra.muto = false;
        if (salva) {
            Core.Ipc.setSetting("media.volume", Math.round(finestra.volume));
            Core.Ipc.setSetting("media.muto", finestra.muto);
        }
    }

    /// Vero mentre la barra dei comandi a schermo intero è visibile.
    property bool comandiSvegli: true

    /// La sveglia: dopo qualche secondo senza mouse i comandi se ne vanno.
    /// Non si spengono mentre il puntatore è sopra di loro — è il difetto
    /// classico di queste barre, sparire sotto il dito che le sta usando.
    Timer {
        id: sonno
        interval: 2500
        onTriggered: {
            if (!sopraComandi.containsMouse)
                finestra.comandiSvegli = false;
        }
    }

    function svegliaComandi() {
        finestra.comandiSvegli = true;
        sonno.restart();
    }

    function alternaRiproduzione() {
        if (!finestra._percorsoCorrente)
            return;
        if (player.playing)
            player.pause();
        else
            player.play();
    }

    function alternaMuto() {
        finestra.muto = !finestra.muto;
        Core.Ipc.setSetting("media.muto", finestra.muto);
    }

    /// Salta avanti o indietro di `quanti` secondi, restando dentro il brano.
    function salta(quanti) {
        if (finestra.durata <= 0)
            return;
        var t = Math.max(0, Math.min(finestra.durata,
                                     player.position + quanti * 1000));
        player.position = t;
        finestra.progresso = t;
    }

    /// Il file in riproduzione e il suo titolo da mostrare.
    property string _percorsoCorrente: ""
    property string _titoloCorrente: ""
    property real durata: 0
    property real progresso: 0
    property bool cercando: false

    readonly property bool haVideo: finestra._video(finestra._percorsoCorrente)

    /// Il palco — video o disegno dell'audio — occupa tutta la finestra.
    ///
    /// Non è «ingrandisci la finestra»: quello lo fa già la barra del titolo.
    /// È il gesto dei lettori video, e serve tutte e due le volte: guardare un
    /// film senza la colonna di sinistra e la scaletta intorno, e guardare il
    /// disegno dell'audio grande mentre si ascolta. Giacomo, 4 settembre 2026:
    /// «metti un pulsantino per vedere i video e gli effetti per audio a
    /// schermo intero».
    /// ── E si LEGGE dalla finestra, non si tiene da parte ─────────────────
    ///
    /// Qui c'era un interruttore nostro, `property bool palcoPieno: false`,
    /// che il pulsante ribaltava. Sbagliato, e in un modo che `WindowTitleBar`
    /// aveva già scritto per esteso: «lo si capisce dalla geometria e non da
    /// un interruttore nostro, così resta giusto anche se a mandarla a schermo
    /// intero è stato il programma, una scorciatoia, o il compositore».
    ///
    /// Con l'interruttore bastava uscire dallo schermo intero con Super+F o
    /// con la linguetta in cima — cioè senza passare dal nostro pulsante — e
    /// il nostro sì restava sì: colonna sparita, barra del titolo sparita, e
    /// nessun modo di riaverle se non chiudendo la finestra.
    ///
    /// Adesso la domanda è una sola e la risposta viene dal compositore, che è
    /// l'unico che lo sa davvero.
    ///
    /// Fuori da Minerva la domanda va fatta alla finestra: là il compositore
    /// non ci risponde, e `Core.Windows` non sa niente di noi. È lo stesso
    /// ramo che hanno già «riduci», «ingrandisci» e «schermo intero» nella
    /// barra del titolo.
    readonly property bool palcoPieno: Core.Compositore.comandabile
                                       ? barra.aTuttoSchermo
                                       : finestra.fullscreen

    onPalcoPienoChanged: if (finestra.palcoPieno) finestra.svegliaComandi()

    function alternaPalcoPieno() {
        // Non c'è niente da ribaltare qui: si chiede lo schermo intero al
        // compositore, e `palcoPieno` diventa vero perché la finestra È a
        // schermo intero — non perché gliel'abbiamo detto noi.
        barra.schermoIntero();
    }

    // Il trimmer.
    property string _ondaPercorso: ""
    property string _fileTaglio: ""
    property real _durataTaglio: 0
    property real _inizioPx: 0
    property real _finePx: 0
    property bool _taglioPronto: false
    property string _taglioFatto: ""
    property string _statoTaglio: ""

    // Download.
    property string _statoDownload: ""
    property bool _downloadErrato: false
    property string _statoRicerca: ""
    property bool _tipoVideo: false

    // Esplora.
    property string cartellaEsplorata: ""
    property string _statoEsplora: ""

    // ── Strumenti ────────────────────────────────────────────────────────

    function _tempo(ms) {
        if (!(ms > 0))
            return "0:00";
        var s = Math.floor(ms / 1000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    function _est(p) {
        var s = String(p);
        var i = s.lastIndexOf(".");
        return i < 0 ? "" : s.slice(i + 1).toLowerCase();
    }

    function _audio(p) {
        return ["mp3", "m4a", "wav", "ogg", "oga", "flac", "opus", "aac",
                "aiff"].indexOf(finestra._est(p)) >= 0;
    }

    function _video(p) {
        return ["mp4", "m4v", "mkv", "mov", "avi", "ogv", "ts",
                "webm"].indexOf(finestra._est(p)) >= 0;
    }

    function _accettabile(p) {
        return finestra._audio(p) || finestra._video(p);
    }

    function _basename(p) {
        var s = String(p);
        return s.slice(s.lastIndexOf("/") + 1);
    }

    function _percorsoFile(p) {
        var s = String(p);
        return s.indexOf("file://") === 0 ? s.slice(7) : s;
    }

    function _soloNome(p) {
        return finestra._basename(finestra._percorsoFile(p));
    }

    // ── Il lettore ───────────────────────────────────────────────────────

    function riproduciFile(percorso, titolo) {
        var p = finestra._percorsoFile(percorso);
        if (!p)
            return;
        finestra._percorsoCorrente = p;
        finestra._titoloCorrente = titolo || finestra._basename(p);
        player.source = "file://" + p;
        player.play();
    }

    function _indiceInPlaylist(p) {
        for (var i = 0; i < playlist.count; i++)
            if (playlist.get(i).percorso === p)
                return i;
        return -1;
    }

    function successivo() {
        if (playlist.count === 0)
            return;

        // «Ripeti uno» vale solo quando il brano finisce da sé: premere
        // «avanti» deve andare avanti, o il tasto non farebbe niente e
        // sembrerebbe rotto. Chi arriva dalla fine del brano passa da
        // `_finito()`.
        if (finestra.casuale) {
            finestra.riproduciIndice(finestra._aCaso());
            return;
        }

        var i = finestra._indiceInPlaylist(finestra._percorsoCorrente);
        if (i >= 0 && i + 1 < playlist.count) {
            finestra.riproduciIndice(i + 1);
            return;
        }
        if (finestra.ripeti === "tutto")
            finestra.riproduciIndice(0);
    }

    /// Il brano è finito da sé. Qui «ripeti uno» conta.
    function _finito() {
        if (finestra.ripeti === "uno" && finestra._percorsoCorrente !== "") {
            player.position = 0;
            player.play();
            return;
        }
        finestra.successivo();
    }

    function riproduciIndice(i) {
        if (i < 0 || i >= playlist.count)
            return;
        finestra.riproduciFile(playlist.get(i).percorso, playlist.get(i).titolo);
    }

    /// Un indice a caso, ma non quello che sta suonando: sentire due volte di
    /// fila lo stesso brano non sembra il caso, sembra un difetto.
    function _aCaso() {
        if (playlist.count <= 1)
            return 0;
        var ora = finestra._indiceInPlaylist(finestra._percorsoCorrente);
        var i = ora;
        for (var g = 0; g < 12 && i === ora; g++)
            i = Math.floor(Math.random() * playlist.count);
        return i;
    }

    function precedente() {
        var i = finestra._indiceInPlaylist(finestra._percorsoCorrente);
        if (i > 0)
            finestra.riproduciFile(playlist.get(i - 1).percorso,
                                   playlist.get(i - 1).titolo);
    }

    function apriPip() {
        if (!finestra.haVideo || pip.attivo)
            return;
        pip.attivo = true;
        player.videoOutput = pip.uscita;
    }

    function chiudiPip() {
        pip.attivo = false;
        player.videoOutput = videoPrincipale;
    }

    function condividiFile(percorso) {
        var p = finestra._percorsoFile(percorso);
        if (p)
            condividi.apri([p]);
    }

    function _aggiungiAllaPlaylist(percorso, titolo) {
        var p = finestra._percorsoFile(percorso);
        if (!p)
            return;
        if (finestra._indiceInPlaylist(p) >= 0)
            return;
        playlist.append({
            percorso: p,
            titolo: titolo || finestra._basename(p),
            video: finestra._video(p)
        });
    }

    function _riempiPlaylist(file) {
        playlist.clear();
        for (var i = 0; i < file.length; i++)
            finestra._aggiungiAllaPlaylist(file[i]);
    }

    function _riempiEsplora(file) {
        esplora.clear();
        for (var i = 0; i < file.length; i++) {
            var p = file[i];
            if (finestra._accettabile(p))
                esplora.append({
                    percorso: p,
                    titolo: finestra._basename(p),
                    video: finestra._video(p)
                });
        }
        finestra._statoEsplora = esplora.count === 0
            ? (Core.Strings.lang === "it"
               ? "Nessun file audio o video qui."
               : "No audio or video files here.")
            : "";
    }

    // ── Aprire ───────────────────────────────────────────────────────────

    /// Un percorso dall'esterno: un file si ascolta, una cartella si esplora.
    function apriPercorso(percorso) {
        var p = finestra._percorsoFile(percorso || "");
        if (p === "")
            return;
        if (finestra._accettabile(p)) {
            finestra.riproduciFile(p);
            finestra.pagina = 0;
        } else {
            finestra.cartellaEsplorata = p;
            finestra.pagina = 3;
            backend.elencoCartella(p);
        }
    }

    /// Un indirizzo da incollare: si va alla pagina Download.
    function apriDownload(indirizzo) {
        finestra.pagina = 2;
        campoUrl.text = String(indirizzo || "");
        campoUrl.prendiIlFuoco();
    }

    /// Chiusa, mette via le sue cose: la musica si ferma e si riparte puliti.
    function addormenta() {
        player.stop();
        player.source = "";
        finestra._percorsoCorrente = "";
        finestra._titoloCorrente = "";
        finestra._ondaPercorso = "";
        finestra._taglioFatto = "";
        finestra._statoDownload = "";
        finestra.pagina = 0;
        if (pip.attivo)
            finestra.chiudiPip();
    }

    function risveglia(percorso) {
        if (percorso)
            finestra.apriPercorso(percorso);
    }

    Component.onCompleted: {
        backend.elencoPlaylist();
        if (finestra.initialPath)
            finestra.apriPercorso(finestra.initialPath);
    }

    // ── Il trimmer ───────────────────────────────────────────────────────

    function caricaOnda(percorso) {
        finestra._fileTaglio = percorso || "";
        finestra._taglioFatto = "";
        finestra._ondaPercorso = "";
        finestra._durataTaglio = 0;
        finestra._inizioPx = 0;
        finestra._finePx = 0;
        finestra._taglioPronto = false;
        if (!percorso)
            return;
        backend.ondaDi(percorso, 1000, 200, Theme.Colors.accent);
    }

    function apriTaglio(percorso, titolo) {
        finestra.pagina = 1;
        campoTaglio.text = finestra._percorsoFile(percorso || "");
        finestra.caricaOnda(campoTaglio.text);
    }

    function _aggiornaSelezione() {
        handleInizio.x = Math.max(0, Math.min(finestra._inizioPx,
                                              zonaOnda.width - 10));
        handleFine.x = Math.max(0, Math.min(finestra._finePx,
                                            zonaOnda.width - 10));
        selezione.x = handleInizio.x;
        selezione.width = Math.max(0, handleFine.x - handleInizio.x);
    }

    /// I secondi a cui corrisponde un pixel dell'onda.
    function _secondiDaPx(px) {
        if (!finestra._durataTaglio)
            return 0;
        return px / Math.max(1, zonaOnda.width) * finestra._durataTaglio;
    }

    function _impostaInizioDaPosizione() {
        if (!finestra._taglioPronto)
            return;
        var px = player.position / 1000 / finestra._durataTaglio
                 * zonaOnda.width;
        finestra._inizioPx = Math.max(0, Math.min(px, finestra._finePx - 10));
        finestra._aggiornaSelezione();
    }

    function _impostaFineDaPosizione() {
        if (!finestra._taglioPronto)
            return;
        var px = player.position / 1000 / finestra._durataTaglio
                 * zonaOnda.width;
        finestra._finePx = Math.max(finestra._inizioPx + 10,
                                    Math.min(px, zonaOnda.width - 10));
        finestra._aggiornaSelezione();
    }

    function anteprimaTaglio() {
        if (!finestra._taglioPronto)
            return;
        var p = finestra._percorsoFile(campoTaglio.text);
        if (!p || !finestra._accettabile(p))
            return;
        player.source = "file://" + p;
        player.position = Math.round(finestra._secondiDaPx(finestra._inizioPx) * 1000);
        player.play();
        spiaAnteprima.restart();
    }

    function eseguiTaglio() {
        if (!finestra._taglioPronto)
            return;
        var p = finestra._percorsoFile(campoTaglio.text);
        if (!p) {
            finestra._statoTaglio = Core.Strings.lang === "it"
                                    ? "Nessun file da tagliare."
                                    : "No file to cut.";
            return;
        }
        var inizio = Math.max(0, Math.min(finestra._durataTaglio,
                                          finestra._secondiDaPx(finestra._inizioPx)));
        var fine = Math.max(0, Math.min(finestra._durataTaglio,
                                         finestra._secondiDaPx(finestra._finePx)));
        if (fine - inizio < 0.5) {
            finestra._statoTaglio = Core.Strings.lang === "it"
                                    ? "Selezione troppo corta."
                                    : "Selection too short.";
            return;
        }
        backend.taglia(p, inizio, fine,
                       fadeInSlider.value / 1000,
                       fadeOutSlider.value / 1000);
    }

    // ── La barra del titolo ──────────────────────────────────────────────
    //
    // Disegnata QUI dentro come in ogni finestra di Minerva: vedi
    // `ui/WindowTitleBar.qml`. Mancava, e il lettore si chiudeva solo con
    // Super+C — non si trascinava per la cima e non si ingrandiva col doppio
    // clic. Non è un dettaglio grafico: è una finestra che non si comanda.

    Ui.WindowTitleBar {
        id: barra
        // Niente `visible` e niente `height` qui: la regola è UNA, e sta nel
        // componente. Sovrascriverle qui è costato la barra del titolo di
        // Minerva Media — `implicitHeight` di un Item senza figli è zero,
        // quindi la barra c'era, rispondeva ai clic, ed era alta zero pixel.
        // Nessun'altra delle nostre finestre le tocca: si passano il titolo e
        // basta.
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: finestra.title
        onCloseRequested: finestra.requestClose()
    }

    // ── La colonna di sinistra ───────────────────────────────────────────

    Rectangle {
        id: sidebar
        width: 200
        visible: !finestra.palcoPieno
        anchors { left: parent.left; top: barra.bottom; bottom: parent.bottom }
        color: Theme.Colors.raised

        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 1
            color: Theme.Colors.edge
        }

        Column {
            anchors {
                top: parent.top; topMargin: Theme.Effects.space4
                left: parent.left; leftMargin: Theme.Effects.space3
                right: parent.right; rightMargin: Theme.Effects.space3
            }
            spacing: Theme.Effects.space2

            Text {
                text: "Media"
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeLG
                       ; weight: Theme.Typography.weightBold }
                color: Theme.Colors.text
            }
            Text {
                text: Core.Strings.lang === "it"
                      ? "musica, video, tagli" : "music, video, cuts"
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeXS }
                color: Theme.Colors.textFaint
            }

            Item { width: 1; height: Theme.Effects.space2 }

            VoceLaterale { icona: "music"; testo: "Player"; pagina: 0 }
            VoceLaterale { icona: "cut"; testo: "Taglia"; pagina: 1 }
            VoceLaterale { icona: "download"; testo: "Download"; pagina: 2 }
            VoceLaterale { icona: "folder"; testo: "Esplora"; pagina: 3 }
        }
    }

    // ── Il contenuto ─────────────────────────────────────────────────────

    Item {
        id: contenuto
        // A palco pieno il contenuto parte dal bordo: niente colonna, niente
        // barra, niente margini. Gli ancoraggi si scelgono, non si spostano —
        // in QML un ancoraggio è un'espressione come un'altra.
        anchors {
            left: finestra.palcoPieno ? parent.left : sidebar.right
            leftMargin: finestra.palcoPieno ? 0 : Theme.Effects.space5
            right: parent.right
            rightMargin: finestra.palcoPieno ? 0 : Theme.Effects.space5
            top: finestra.palcoPieno ? parent.top : barra.bottom
            topMargin: finestra.palcoPieno ? 0 : Theme.Effects.space4
            bottom: parent.bottom
            bottomMargin: finestra.palcoPieno ? 0 : Theme.Effects.space4
        }
        clip: true

        Item {
            id: paginaPlayer
            anchors.fill: parent
            visible: finestra.pagina === 0

            // La superficie su cui si guarda o si ascolta.
            Rectangle {
                id: zonaVideo
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: finestra.palcoPieno ? parent.height
                                            : Math.max(240, parent.height * 0.44)
                radius: finestra.palcoPieno ? 0 : Theme.Effects.radiusLG
                color: Theme.Colors.sunken
                clip: true

                VideoOutput {
                    id: videoPrincipale
                    anchors.fill: parent
                    visible: finestra.haVideo && !pip.attivo
                }

                // ── A schermo intero i comandi erano SPARITI ─────────────
                //
                // Non erano nascosti: erano fuori. `contenuto` ritaglia
                // (`clip: true`) e a palco pieno `zonaVideo` prende tutta
                // l'altezza, quindi tempo, barra di ricerca, play, volume e
                // scaletta — che sono ancorati in catena SOTTO la zona video —
                // finivano oltre il bordo senza che nessuno li avesse
                // dichiarati invisibili.
                //
                // Quello che restava raggiungibile su un film a tutto schermo
                // era **un pulsante da 34×24 pixel**, e nient'altro: niente
                // pausa, niente tempo, niente volume. Per uscire bisognava
                // sapere una scorciatoia.
                //
                // Questi comandi vivono DENTRO `zonaVideo`, che a schermo
                // intero è l'unica cosa che esiste ancora, e compaiono al
                // movimento del mouse come in qualunque lettore video.
                MouseArea {
                    id: risveglia
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    // Non ruba i clic a chi sta sotto quando non serve.
                    enabled: finestra.palcoPieno
                    visible: finestra.palcoPieno
                    z: 5

                    onPositionChanged: finestra.svegliaComandi()
                    onEntered: finestra.svegliaComandi()
                    // Un clic solo mette in pausa, due tornano indietro dallo
                    // schermo intero: è quello che fanno tutti i lettori.
                    onClicked: {
                        finestra.svegliaComandi();
                        finestra.alternaRiproduzione();
                    }
                    onDoubleClicked: finestra.alternaPalcoPieno()
                }

                Rectangle {
                    id: comandiPieno
                    z: 6
                    visible: finestra.palcoPieno
                             && finestra._percorsoCorrente !== ""
                    opacity: finestra.comandiSvegli ? 1 : 0
                    anchors { left: parent.left; right: parent.right
                              bottom: parent.bottom }
                    height: 92
                    // Una velatura scura sotto i comandi: su un fotogramma
                    // chiaro un testo bianco senza fondo non si legge.
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0
                                       color: Qt.alpha(Theme.Colors.base, 0.86) }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.Motion.quick }
                    }

                    // Mentre il puntatore è sui comandi non si spengono sotto
                    // il dito: è il difetto classico di queste barre.
                    MouseArea {
                        id: sopraComandi
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: finestra.svegliaComandi()
                        onPositionChanged: finestra.svegliaComandi()
                    }

                    Text {
                        id: tempoPieno
                        anchors { left: parent.left
                                  leftMargin: Theme.Effects.space4
                                  bottom: comandiRiga.top
                                  bottomMargin: Theme.Effects.space1 }
                        text: finestra._tempo(finestra.progresso) + "  /  "
                              + finestra._tempo(finestra.durata)
                        font { family: Theme.Typography.fontMono
                               ; pixelSize: Theme.Typography.sizeSM }
                        color: Theme.Colors.text
                    }

                    Text {
                        anchors { right: parent.right
                                  rightMargin: Theme.Effects.space4
                                  verticalCenter: tempoPieno.verticalCenter }
                        width: parent.width / 2
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: finestra._titoloCorrente
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeSM }
                        color: Theme.Colors.textMuted
                    }

                    Row {
                        id: comandiRiga
                        anchors { left: parent.left
                                  leftMargin: Theme.Effects.space4
                                  right: parent.right
                                  rightMargin: Theme.Effects.space4
                                  bottom: parent.bottom
                                  bottomMargin: Theme.Effects.space3 }
                        height: 38
                        spacing: Theme.Effects.space2

                        TastoControllo {
                            icona: "prev"
                            onPremuto: finestra.precedente()
                        }
                        TastoControllo {
                            icona: player.playing ? "pause" : "play"
                            onPremuto: finestra.alternaRiproduzione()
                        }
                        TastoControllo {
                            icona: "next"
                            attivo: playlist.count > 0
                            onPremuto: finestra.successivo()
                        }

                        Ui.Slider {
                            id: cercaPieno
                            width: Math.max(120, comandiRiga.width - 38 * 5
                                            - Theme.Effects.space2 * 6 - 150)
                            height: 38
                            from: 0
                            to: Math.max(1, finestra.durata)
                            value: finestra.progresso
                            showValue: false
                            onMoved: function (v) { finestra.cercando = true; }
                            onReleased: function (v) {
                                finestra.cercando = false;
                                player.position = v;
                                finestra.progresso = v;
                            }
                        }

                        TastoControllo {
                            icona: finestra.muto ? "muted" : "volume"
                            onPremuto: finestra.alternaMuto()
                        }
                        Ui.Slider {
                            width: 150
                            height: 38
                            from: 0
                            to: 100
                            value: finestra.muto ? 0 : finestra.volume
                            icon: ""
                            showValue: false
                            onMoved: function (v) { finestra.cambiaVolume(v, false); }
                            onReleased: function (v) { finestra.cambiaVolume(v, true); }
                        }
                        TastoControllo {
                            icona: "collapse"
                            onPremuto: finestra.alternaPalcoPieno()
                        }
                    }
                }

                VisualizerWidgetQML {
                    id: vis
                    modo: Core.Ipc.get("media.disegno", 0)
                    anchors.fill: parent
                    visible: !finestra.haVideo
                    inRiproduzione: player.playing
                    tinta: Theme.Colors.accent
                    tintaBassa: Theme.Colors.accentAlt
                }

                // Il vuoto: nessun file ancora.
                Item {
                    anchors.centerIn: parent
                    visible: finestra._percorsoCorrente === ""
                    width: 240
                    height: 90
                    Ui.Icon {
                        id: iconaVuoto
                        anchors.centerIn: parent
                        width: 46
                        height: 46
                        name: "music"
                        color: Theme.Colors.textFaint
                    }
                    Text {
                        id: testoVuoto
                        anchors { top: iconaVuoto.bottom; topMargin: Theme.Effects.space2
                                  horizontalCenter: parent.horizontalCenter }
                        text: Core.Strings.lang === "it"
                              ? "Niente in riproduzione" : "Nothing playing"
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeSM }
                        color: Theme.Colors.textFaint
                    }

                    // Da qui si può APRIRE qualcosa. Prima questo riquadro
                    // diceva solo che non c'era niente, e l'unico modo di
                    // mettercelo era scrivere un percorso in un'altra pagina.
                    TastoTesto {
                        anchors { top: testoVuoto.bottom
                                  topMargin: Theme.Effects.space3
                                  horizontalCenter: parent.horizontalCenter }
                        testo: Core.Strings.lang === "it" ? "Apri un file…"
                                                          : "Open a file…"
                        accento: true
                        onPremuto: finestra.scegli(
                            "riproduci",
                            Core.Strings.lang === "it" ? "Che cosa ascoltare"
                                                       : "What to play",
                            "")
                    }
                }

                // ── Schermo intero, per il video E per il disegno ────────
                //
                // In basso a sinistra e non a destra: a destra ci sono già i
                // quattro nomi dei disegni, e un pulsante che cambia
                // significato in mezzo a un gruppo che ne ha uno solo si
                // preme per sbaglio.
                Rectangle {
                    anchors { left: parent.left; leftMargin: Theme.Effects.space3
                              bottom: parent.bottom
                              bottomMargin: Theme.Effects.space3 }
                    width: 34
                    height: 24
                    radius: Theme.Effects.radiusXS
                    color: presaPieno.containsMouse
                           ? Qt.alpha(Theme.Colors.accent, 0.22)
                           : Qt.alpha(Theme.Colors.base, 0.55)
                    border.width: Theme.Effects.hairline
                    border.color: Theme.Colors.edge
                    // A schermo intero non serve: nella barra dei comandi c'è
                    // il suo gemello, più grande e in mezzo agli altri.
                    visible: finestra._percorsoCorrente !== "" && !pip.attivo
                             && !finestra.palcoPieno

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 15
                        height: 15
                        name: finestra.palcoPieno ? "collapse" : "expand"
                        color: presaPieno.containsMouse ? Theme.Colors.accent
                                                        : Theme.Colors.textMuted
                    }

                    MouseArea {
                        id: presaPieno
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: finestra.alternaPalcoPieno()
                    }

                    Ui.ToolTipHint {
                        shown: presaPieno.containsMouse
                        sopra: true
                        text: Core.Strings.lang === "it"
                              ? (finestra.palcoPieno ? "Esci da schermo intero"
                                                     : "Schermo intero")
                              : (finestra.palcoPieno ? "Exit full screen"
                                                     : "Full screen")
                    }
                }

                // La scelta del disegno, per chi ascolta senza video.
                Row {
                    anchors { right: parent.right; rightMargin: Theme.Effects.space3
                               bottom: parent.bottom
                               // A schermo intero sale sopra i comandi: sotto
                               // ci finirebbe in mezzo, e i due gruppi si
                               // premerebbero a vicenda.
                               bottomMargin: finestra.palcoPieno
                                             ? comandiPieno.height + Theme.Effects.space3
                                             : Theme.Effects.space3 }
                    spacing: Theme.Effects.space1
                    visible: !finestra.haVideo
                    opacity: finestra.palcoPieno && !finestra.comandiSvegli ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.Motion.quick }
                    }

                    Repeater {
                        model: ["Barre", "Onda", "Radiale", "Neon"]
                        delegate: Rectangle {
                            width: 52
                            height: 24
                            radius: Theme.Effects.radiusXS
                            color: vis.modo === index
                                   ? Qt.alpha(Theme.Colors.accent, 0.22)
                                   : (presaModo.containsMouse ? Theme.Colors.hover
                                                        : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                font { family: Theme.Typography.fontDisplay
                                       ; pixelSize: Theme.Typography.sizeXS
                                       ; weight: Theme.Typography.weightSemiBold
                                       ; capitalization: Font.AllUppercase }
                                font.letterSpacing: Theme.Typography.trackingLabel
                                color: vis.modo === index
                                       ? Theme.Colors.accent
                                       : Theme.Colors.textMuted
                            }
                            MouseArea {
                                id: presaModo
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    vis.modo = index;
                                    // Si ricorda: ogni avvio ripartiva da
                                    // «Barre», qualunque cosa si fosse scelta.
                                    Core.Ipc.setSetting("media.disegno", index);
                                }
                            }
                        }
                    }
                }
            }

            // Chi suona e da dove.
            Column {
                id: colonnaInfo
                anchors { left: parent.left; right: parent.right
                           top: zonaVideo.bottom; topMargin: Theme.Effects.space3 }
                spacing: Theme.Effects.space1

                Text {
                    width: parent.width
                    text: finestra._titoloCorrente
                          || (Core.Strings.lang === "it"
                              ? "Scegli un file dalla playlist" : "Pick a file from the playlist")
                    elide: Text.ElideRight
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeLG
                           ; weight: Theme.Typography.weightSemiBold }
                    color: Theme.Colors.text
                }
                Text {
                    width: parent.width
                    text: finestra._percorsoCorrente || ""
                    elide: Text.ElideLeft
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeXS }
                    color: Theme.Colors.textFaint
                }
            }

            // La barra del tempo.
            Row {
                id: rigaTempo
                anchors { left: parent.left; right: parent.right
                           top: colonnaInfo.bottom; topMargin: Theme.Effects.space3 }
                spacing: Theme.Effects.space3

                Text {
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: finestra._tempo(finestra.progresso)
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.textMuted
                }
                Ui.Slider {
                    id: progressoSlider
                    width: parent.width - 44 - 44 - Theme.Effects.space3 * 2
                    from: 0
                    to: Math.max(1, finestra.durata)
                    value: finestra.progresso
                    icon: "music"
                    showValue: false
                    onMoved: function (v) {
                        finestra.cercando = true;
                    }
                    onReleased: function (v) {
                        finestra.cercando = false;
                        player.position = v;
                        finestra.progresso = v;
                    }
                }
                Text {
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: finestra._tempo(finestra.durata)
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.textMuted
                }
            }

            // I comandi del lettore.
            Row {
                id: rigaComandi
                anchors { left: parent.left; right: parent.right
                           top: rigaTempo.bottom; topMargin: Theme.Effects.space1 }
                height: 46
                spacing: Theme.Effects.space2

                TastoControllo {
                    icona: "prev"
                    attivo: finestra._indiceInPlaylist(finestra._percorsoCorrente) > 0
                    onPremuto: finestra.precedente()
                }
                TastoPlay {
                    suonando: player.playing
                    onPremuto: {
                        if (!finestra._percorsoCorrente)
                            return;
                        if (player.playing)
                            player.pause();
                        else
                            player.play();
                    }
                }
                TastoControllo {
                    icona: "next"
                    attivo: playlist.count > 0
                    onPremuto: finestra.successivo()
                }

                Item { width: Theme.Effects.space4 }

                Ui.Slider {
                    id: volumeSlider
                    width: 150
                    height: 42
                    from: 0
                    to: 100
                    // Il valore viene dallo stato, non dal cursore: così il
                    // numero che si legge è quello che si sente, anche quando
                    // a cambiarlo è stata la tastiera.
                    value: finestra.muto ? 0 : finestra.volume
                    icon: finestra.muto ? "muted" : "volume"
                    onMoved: function (v) { finestra.cambiaVolume(v, false); }
                    onReleased: function (v) { finestra.cambiaVolume(v, true); }
                }

                Item { width: Theme.Effects.space4 }

                // ── Ripeti e casuale ────────────────────────────────────
                //
                // «Ripeti tutto» era il comportamento di prima ed era
                // IMPLICITO: la scaletta ripartiva da capo in fondo e non
                // c'era modo di dirle di smettere. Adesso è una scelta fra
                // tre, e si vede quale.
                TastoControllo {
                    icona: finestra.ripeti === "uno" ? "repeat1" : "repeat"
                    attivo: finestra.ripeti !== "no"
                    onPremuto: {
                        var giro = { "no": "tutto", "tutto": "uno", "uno": "no" };
                        finestra.ripeti = giro[finestra.ripeti] || "tutto";
                        Core.Ipc.setSetting("media.ripeti", finestra.ripeti);
                    }
                }
                TastoControllo {
                    icona: "shuffle"
                    attivo: finestra.casuale
                    onPremuto: {
                        finestra.casuale = !finestra.casuale;
                        Core.Ipc.setSetting("media.casuale", finestra.casuale);
                    }
                }

                Item { width: Theme.Effects.space4 }

                TastoControllo {
                    icona: "video"
                    attivo: finestra.haVideo
                    onPremuto: finestra.apriPip()
                }
                TastoControllo {
                    icona: "share"
                    attivo: finestra._percorsoCorrente !== ""
                    onPremuto: finestra.condividiFile(finestra._percorsoCorrente)
                }
            }

            // La playlist.
            Row {
                anchors { left: parent.left; right: parent.right
                           top: rigaComandi.bottom; topMargin: Theme.Effects.space4 }
                spacing: Theme.Effects.space2

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Core.Strings.lang === "it" ? "Playlist" : "Playlist"
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeSM
                           ; weight: Theme.Typography.weightSemiBold
                           ; capitalization: Font.AllUppercase }
                    font.letterSpacing: Theme.Typography.trackingLabel
                    color: Theme.Colors.textMuted
                }
                TastoRiga {
                    icona: "restart"
                    onPremuto: backend.elencoPlaylist()
                }
                Item { width: Theme.Effects.space2 }
                Text {
                    width: parent.width - 180
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    horizontalAlignment: Text.AlignRight
                    text: "~/Musica/Minerva_YT"
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeXS }
                    color: Theme.Colors.textFaint
                }
            }

            // La scaletta della cartella.
            Ui.Scorrimento {
                bersaglio: elencoPlaylist
                anchors {
                    right: elencoPlaylist.right
                    top: elencoPlaylist.top
                    bottom: elencoPlaylist.bottom
                }
            }

            ListView {
                id: elencoPlaylist
                cacheBuffer: 400
                anchors { left: parent.left; right: parent.right
                           top: rigaComandi.bottom; topMargin: 44
                           bottom: parent.bottom }
                clip: true
                spacing: Theme.Effects.space1
                model: playlist

                delegate: VoceFile {
                    testo: model.titolo
                    icona: model.video ? "video" : "music"
                    selezionata: model.percorso === finestra._percorsoCorrente
                    onRiproduci: finestra.riproduciFile(model.percorso, model.titolo)
                    onTaglia: finestra.apriTaglio(model.percorso, model.titolo)
                    onCondividi: finestra.condividiFile(model.percorso)
                }

                Text {
                    anchors.centerIn: parent
                    visible: playlist.count === 0
                    text: Core.Strings.lang === "it"
                          ? "Cartella vuota: scarica qualcosa nella pagina Download."
                          : "Empty folder: grab something in the Download page."
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.textFaint
                }
            }
        }

        Item {
            id: paginaTaglia
            anchors.fill: parent
            visible: finestra.pagina === 1

            // La sorgente.
            Row {
                id: rigaSorgente
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.Effects.space2

                Ui.Campo {
                    id: campoTaglio
                    width: parent.width - 230
                    segnaposto: Core.Strings.lang === "it"
                                ? "Percorso del file…"
                                : "File path…"
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it" ? "Scegli file…"
                                                      : "Choose file…"
                    onPremuto: finestra.scegli(
                        "taglia",
                        Core.Strings.lang === "it" ? "Quale file tagliare"
                                                   : "Which file to trim",
                        finestra._percorsoFile(finestra._percorsoCorrente))
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it"
                           ? "Usa in riproduzione" : "Use what's playing"
                    attivo: finestra._percorsoCorrente !== ""
                    onPremuto: {
                        campoTaglio.text = finestra._percorsoCorrente;
                        finestra.caricaOnda(campoTaglio.text);
                    }
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it" ? "Carica" : "Load"
                    onPremuto: finestra.caricaOnda(campoTaglio.text)
                }
            }

            // L'onda e la selezione.
            Rectangle {
                id: zonaOnda
                anchors { left: parent.left; right: parent.right
                           top: rigaSorgente.bottom; topMargin: Theme.Effects.space4 }
                height: 210
                radius: Theme.Effects.radiusLG
                color: Theme.Colors.sunken
                clip: true

                Image {
                    id: onda
                    anchors.fill: parent
                    fillMode: Image.Stretch
                    source: finestra._ondaPercorso
                            ? "file://" + finestra._ondaPercorso : ""
                    opacity: 0.9
                    // Senza queste tre righe il disegno dell'onda si
                    // decodificava alla sua misura naturale e **sul filo
                    // dell'interfaccia**: la finestra restava ferma finché
                    // non aveva finito. È la stessa cura misurata in
                    // `files/Pane.qml`, dove la griglia da 311 miniature la
                    // paga a ogni pixel di ridimensionamento.
                    sourceSize.width: Math.max(1, Math.round(width))
                    asynchronous: true
                    cache: true
                }

                Rectangle {
                    id: selezione
                    anchors { top: parent.top; bottom: parent.bottom }
                    color: Qt.alpha(Theme.Colors.accent, 0.22)
                }

                Rectangle {
                    id: testina
                    anchors { top: parent.top; bottom: parent.bottom }
                    width: 2
                    color: Theme.Colors.text
                    visible: campoTaglio.text === finestra._percorsoCorrente
                             && player.position > 0 && finestra._durataTaglio > 0
                    x: player.position / 1000 / finestra._durataTaglio
                       * zonaOnda.width
                }

                Maniglia {
                    id: handleInizio
                    minimo: 0
                    massimo: zonaOnda.width - 10
                    onMossa: function (x) {
                        finestra._inizioPx = x;
                        selezione.x = x;
                        selezione.width = Math.max(0, handleFine.x - x);
                    }
                }
                Maniglia {
                    id: handleFine
                    minimo: 0
                    massimo: zonaOnda.width - 10
                    onMossa: function (x) {
                        finestra._finePx = x;
                        selezione.width = Math.max(0, x - handleInizio.x);
                    }
                }
            }

            // Le misure.
            Row {
                id: rigaMisure
                anchors { left: parent.left; right: parent.right
                           top: zonaOnda.bottom; topMargin: Theme.Effects.space2 }
                spacing: Theme.Effects.space4

                Text {
                    text: Core.Strings.lang === "it" ? "Inizio" : "Start"
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeXS
                           ; weight: Theme.Typography.weightSemiBold
                           ; capitalization: Font.AllUppercase }
                    font.letterSpacing: Theme.Typography.trackingLabel
                    color: Theme.Colors.textMuted
                }
                Text {
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.accent
                    text: finestra._tempo(finestra._secondiDaPx(finestra._inizioPx) * 1000)
                }
                Text {
                    text: Core.Strings.lang === "it" ? "Fine" : "End"
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeXS
                           ; weight: Theme.Typography.weightSemiBold
                           ; capitalization: Font.AllUppercase }
                    font.letterSpacing: Theme.Typography.trackingLabel
                    color: Theme.Colors.textMuted
                }
                Text {
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.accent
                    text: finestra._tempo(finestra._secondiDaPx(finestra._finePx) * 1000)
                }
                Item { width: Theme.Effects.space3 }
                Text {
                    text: Core.Strings.lang === "it" ? "Durata" : "Length"
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeXS
                           ; weight: Theme.Typography.weightSemiBold
                           ; capitalization: Font.AllUppercase }
                    font.letterSpacing: Theme.Typography.trackingLabel
                    color: Theme.Colors.textMuted
                }
                Text {
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.text
                    text: finestra._tempo(finestra._durataTaglio * 1000)
                }
            }

            // Le dissolvenze.
            Row {
                id: rigaDissolvenze
                anchors { left: parent.left; right: parent.right
                           top: rigaMisure.bottom; topMargin: Theme.Effects.space2 }
                spacing: Theme.Effects.space5

                Column {
                    spacing: Theme.Effects.space1
                    Text {
                        text: Core.Strings.lang === "it"
                              ? "Dissolvenza in" : "Fade in"
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeXS
                               ; weight: Theme.Typography.weightSemiBold
                               ; capitalization: Font.AllUppercase }
                        font.letterSpacing: Theme.Typography.trackingLabel
                        color: Theme.Colors.textMuted
                    }
                    Row {
                        spacing: Theme.Effects.space2
                        Ui.Slider {
                            id: fadeInSlider
                            width: 160
                            height: 34
                            from: 0
                            to: 5000
                            value: 300
                            icon: ""
                            showValue: false
                            // Questo cursore È il suo valore (non c'è
                            // un'impostazione dietro): dal 30 settembre 2026
                            // `Ui.Slider` non scrive più `value` da sé, e
                            // lo si tiene qui, al rilascio.
                            onReleased: function (v) { fadeInSlider.value = v; }
                        }
                        Text {
                            width: 52
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(fadeInSlider.mostrato) + " ms"
                            font { family: Theme.Typography.fontMono
                                   ; pixelSize: Theme.Typography.sizeXS }
                            color: Theme.Colors.textFaint
                        }
                    }
                }

                Column {
                    spacing: Theme.Effects.space1
                    Text {
                        text: Core.Strings.lang === "it"
                              ? "Dissolvenza fuori" : "Fade out"
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeXS
                               ; weight: Theme.Typography.weightSemiBold
                               ; capitalization: Font.AllUppercase }
                        font.letterSpacing: Theme.Typography.trackingLabel
                        color: Theme.Colors.textMuted
                    }
                    Row {
                        spacing: Theme.Effects.space2
                        Ui.Slider {
                            id: fadeOutSlider
                            width: 160
                            height: 34
                            from: 0
                            to: 5000
                            value: 500
                            icon: ""
                            showValue: false
                            onReleased: function (v) { fadeOutSlider.value = v; }
                        }
                        Text {
                            width: 52
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(fadeOutSlider.mostrato) + " ms"
                            font { family: Theme.Typography.fontMono
                                   ; pixelSize: Theme.Typography.sizeXS }
                            color: Theme.Colors.textFaint
                        }
                    }
                }
            }

            // Le azioni.
            Row {
                id: rigaAzione
                anchors { left: parent.left; right: parent.right
                           top: rigaDissolvenze.bottom; topMargin: Theme.Effects.space4 }
                spacing: Theme.Effects.space2

                TastoTesto {
                    testo: Core.Strings.lang === "it"
                           ? "Inizio = posizione" : "Start = position"
                    attivo: finestra._taglioPronto
                    onPremuto: finestra._impostaInizioDaPosizione()
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it"
                           ? "Fine = posizione" : "End = position"
                    attivo: finestra._taglioPronto
                    onPremuto: finestra._impostaFineDaPosizione()
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it" ? "Anteprima" : "Preview"
                    attivo: finestra._taglioPronto
                    onPremuto: finestra.anteprimaTaglio()
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it"
                           ? "Taglia e salva" : "Cut and save"
                    accento: true
                    attivo: finestra._taglioPronto && !backend.lavorando
                    onPremuto: finestra.eseguiTaglio()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: backend.lavorando
                    text: Core.Strings.lang === "it"
                          ? "Lavoro in corso…" : "Working…"
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.textFaint
                }
            }

            Text {
                id: rigaStatoTaglio
                anchors { left: parent.left; right: parent.right
                           top: rigaAzione.bottom; topMargin: Theme.Effects.space2 }
                visible: finestra._statoTaglio !== ""
                text: finestra._statoTaglio
                elide: Text.ElideRight
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeSM }
                color: Theme.Colors.danger
            }

            // Il risultato: tagliato, e adesso?
            Rectangle {
                id: rigaRisultato
                anchors { left: parent.left; right: parent.right
                           top: rigaStatoTaglio.bottom; topMargin: Theme.Effects.space4 }
                visible: finestra._taglioFatto !== ""
                height: 56
                radius: Theme.Effects.radiusSM
                color: Theme.Colors.raised

                Row {
                    anchors { left: parent.left; leftMargin: Theme.Effects.space3
                               right: parent.right; rightMargin: Theme.Effects.space2
                               verticalCenter: parent.verticalCenter }
                    spacing: Theme.Effects.space3

                    Ui.Icon {
                        width: 18; height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        name: "music"
                        color: Theme.Colors.textMuted
                    }
                    Text {
                        width: parent.width - 150
                        anchors.verticalCenter: parent.verticalCenter
                        text: finestra._soloNome(finestra._taglioFatto)
                        elide: Text.ElideMiddle
                        font { family: Theme.Typography.fontMono
                               ; pixelSize: Theme.Typography.sizeSM }
                        color: Theme.Colors.text
                    }
                    Item { width: Theme.Effects.space2 }
                    TastoRiga {
                        icona: "play"
                        onPremuto: finestra.riproduciFile(finestra._taglioFatto)
                    }
                    TastoRiga {
                        icona: "share"
                        onPremuto: finestra.condividiFile(finestra._taglioFatto)
                    }
                    TastoRiga {
                        icona: "folder"
                        onPremuto: {
                            var p = finestra._taglioFatto;
                            Quickshell.execDetached([
                                "xdg-open",
                                p.slice(0, p.lastIndexOf("/"))]);
                        }
                    }
                }
            }
        }

        Item {
            id: paginaDownload
            anchors.fill: parent
            visible: finestra.pagina === 2

            // Scarica da un indirizzo.
            Column {
                id: colonnaIndirizzo
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.Effects.space2

                Row {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Ui.Campo {
                        id: campoUrl
                        width: parent.width - 120
                        segnaposto: Core.Strings.lang === "it"
                                    ? "Indirizzo del video…"
                                    : "Video address…"
                        onAccettato: finestra._scaricaDaCampo()
                    }
                    TastoTesto {
                        testo: Core.Strings.lang === "it" ? "Scarica" : "Download"
                        accento: true
                        attivo: !backend.scaricando
                        onPremuto: finestra._scaricaDaCampo()
                    }
                }

                // La scelta del formato.
                Row {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    TastoTesto {
                        testo: "Audio MP3"
                        accento: !finestra._tipoVideo
                        onPremuto: finestra._tipoVideo = false
                    }
                    TastoTesto {
                        testo: "Video MP4"
                        accento: finestra._tipoVideo
                        onPremuto: finestra._tipoVideo = true
                    }
                }

                Text {
                    width: parent.width
                    visible: finestra._statoDownload !== ""
                    text: finestra._statoDownload
                    elide: Text.ElideRight
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeSM }
                    color: finestra._downloadErrato
                           ? Theme.Colors.danger : Theme.Colors.textMuted
                }
            }

            // La ricerca.
            Row {
                id: rigaRicerca
                anchors { left: parent.left; right: parent.right
                           top: colonnaIndirizzo.bottom; topMargin: Theme.Effects.space5 }
                spacing: Theme.Effects.space2

                Ui.Campo {
                    id: campoRicerca
                    width: parent.width - 120
                    segnaposto: Core.Strings.lang === "it"
                                ? "Cerca su YouTube…"
                                : "Search YouTube…"
                    onAccettato: finestra._cerca()
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it" ? "Cerca" : "Search"
                    attivo: !backend.cercando
                    onPremuto: finestra._cerca()
                }
            }

            Text {
                anchors { left: parent.left; right: parent.right
                           top: rigaRicerca.bottom; topMargin: Theme.Effects.space2 }
                visible: finestra._statoRicerca !== ""
                text: finestra._statoRicerca
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeSM }
                color: Theme.Colors.textFaint
            }

            // I risultati della ricerca.
            Ui.Scorrimento {
                bersaglio: elencoRisultati
                anchors {
                    right: elencoRisultati.right
                    top: elencoRisultati.top
                    bottom: elencoRisultati.bottom
                }
            }

            ListView {
                id: elencoRisultati
                cacheBuffer: 400
                anchors { left: parent.left; right: parent.right
                           top: rigaRicerca.bottom; topMargin: 56
                           bottom: parent.bottom }
                clip: true
                spacing: Theme.Effects.space1
                model: risultati

                delegate: VoceRisultato {
                    titolo: model.titolo
                    canale: model.canale
                    durata: model.durata
                    miniatura: model.miniatura
                    url: model.url
                    onScaricaAudio: backend.scaricaAudio(model.url)
                    onScaricaVideo: backend.scaricaVideo(model.url)
                }
            }
        }

        Item {
            id: paginaEsplora
            anchors.fill: parent
            visible: finestra.pagina === 3

            Row {
                id: rigaCartella
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.Effects.space2

                Ui.Campo {
                    id: campoCartella
                    width: parent.width - 120
                    segnaposto: Core.Strings.lang === "it"
                                ? "Percorso di una cartella…"
                                : "Folder path…"
                    onAccettato: finestra._apriCartella()
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it" ? "Sfoglia…" : "Browse…"
                    onPremuto: finestra.scegli(
                        "cartella",
                        Core.Strings.lang === "it" ? "Quale cartella aprire"
                                                   : "Which folder to open",
                        campoCartella.text)
                }
                TastoTesto {
                    testo: Core.Strings.lang === "it" ? "Apri" : "Open"
                    onPremuto: finestra._apriCartella()
                }
            }

            Text {
                anchors { left: parent.left; right: parent.right
                           top: rigaCartella.bottom; topMargin: Theme.Effects.space2 }
                visible: finestra._statoEsplora !== ""
                text: finestra._statoEsplora
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeSM }
                color: Theme.Colors.textFaint
            }

            // Il contenuto della cartella aperta.
            Ui.Scorrimento {
                bersaglio: elencoEsplora
                anchors {
                    right: elencoEsplora.right
                    top: elencoEsplora.top
                    bottom: elencoEsplora.bottom
                }
            }

            ListView {
                id: elencoEsplora
                cacheBuffer: 400
                anchors { left: parent.left; right: parent.right
                           top: rigaCartella.bottom; topMargin: 40
                           bottom: parent.bottom }
                clip: true
                spacing: Theme.Effects.space1
                model: esplora

                delegate: VoceFile {
                    testo: model.titolo
                    icona: model.video ? "video" : "music"
                    selezionata: model.percorso === finestra._percorsoCorrente
                    onRiproduci: finestra.riproduciFile(model.percorso, model.titolo)
                    onTaglia: finestra.apriTaglio(model.percorso, model.titolo)
                    onCondividi: finestra.condividiFile(model.percorso)
                }
            }
        }
    }

    ListModel { id: playlist }
    ListModel { id: risultati }
    ListModel { id: esplora }

    // ── Le azioni delle pagine ───────────────────────────────────────────

    function _scaricaDaCampo() {
        var u = String(campoUrl.text || "").trim();
        if (u === "")
            return;
        if (finestra._tipoVideo)
            backend.scaricaVideo(u);
        else
            backend.scaricaAudio(u);
    }

    function _cerca() {
        var q = String(campoRicerca.text || "").trim();
        if (q === "")
            return;
        finestra._statoRicerca = Core.Strings.lang === "it"
                                 ? "Cerco…" : "Searching…";
        backend.cerca(q, 6);
    }

    function _apriCartella() {
        var d = String(campoCartella.text || "").trim();
        if (d === "")
            return;
        finestra.cartellaEsplorata = d;
        backend.elencoCartella(d);
    }

    // ── I pezzi ──────────────────────────────────────────────────────────

    Timer {
        id: spiaAnteprima
        interval: 150
        repeat: true
        onTriggered: {
            var fine = finestra._secondiDaPx(finestra._finePx) * 1000;
            if (player.position >= fine) {
                player.pause();
                player.position = Math.round(
                    finestra._secondiDaPx(finestra._inizioPx) * 1000);
                spiaAnteprima.stop();
            }
        }
    }

    /// Una voce della colonna di sinistra.
    component VoceLaterale: Item {
        property string icona: ""
        property string testo: ""
        property int pagina: 0
        width: sidebar.width - Theme.Effects.space3 * 2
        height: 42

        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusSM
            color: presa.containsMouse && !presa.pressed
                   ? (finestra.pagina === parent.pagina
                      ? Qt.alpha(Theme.Colors.accent, 0.22)
                      : Theme.Colors.hover)
                   : presa.pressed
                     ? (finestra.pagina === parent.pagina
                        ? Qt.alpha(Theme.Colors.accent, 0.32)
                        : Theme.Colors.pressed)
                     : (finestra.pagina === parent.pagina
                        ? Qt.alpha(Theme.Colors.accent, 0.14)
                        : "transparent")

            Ui.Icon {
                anchors { left: parent.left; leftMargin: Theme.Effects.space3
                           verticalCenter: parent.verticalCenter }
                width: 18
                height: 18
                name: parent.parent.icona
                color: finestra.pagina === parent.parent.pagina
                       ? Theme.Colors.accent : Theme.Colors.textMuted
            }
            Text {
                anchors { left: parent.left; leftMargin: Theme.Effects.space3 * 3 + 18
                           verticalCenter: parent.verticalCenter }
                text: parent.parent.testo
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeSM
                       ; weight: Theme.Typography.weightSemiBold
                       ; capitalization: Font.AllUppercase }
                font.letterSpacing: Theme.Typography.trackingLabel
                color: finestra.pagina === parent.parent.pagina
                       ? Theme.Colors.text : Theme.Colors.textMuted
            }
        }

        MouseArea {
            id: presa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: finestra.pagina = parent.pagina
        }
    }

    /// Un pulsante con un'etichetta.
    component TastoTesto: Item {
        property string testo: ""
        property bool accento: false
        property bool attivo: true
        signal premuto()
        implicitWidth: etichettaTasto.implicitWidth + Theme.Effects.space4 * 2
        implicitHeight: 38

        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusSM
            color: parent.accento
                   ? Qt.alpha(Theme.Colors.accent,
                              presaTasto.pressed ? 0.55 : 0.35)
                   : presaTasto.pressed ? Theme.Colors.pressed
                     : presaTasto.containsMouse ? Theme.Colors.hover
                       : Theme.Colors.raised
        }
        Text {
            id: etichettaTasto
            anchors.centerIn: parent
            text: parent.testo
            font { family: Theme.Typography.fontDisplay
                   ; pixelSize: Theme.Typography.sizeSM
                   ; weight: Theme.Typography.weightSemiBold
                   ; capitalization: Font.AllUppercase }
            font.letterSpacing: Theme.Typography.trackingLabel
            color: parent.accento
                   ? Theme.Colors.textOnAccent : Theme.Colors.text
        }
        MouseArea {
            id: presaTasto
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.attivo
            onClicked: parent.premuto()
        }
        opacity: presaTasto.enabled ? 1 : 0.4
    }

    /// Un pulsante tondo del lettore.
    component TastoControllo: Item {
        property string icona: ""
        property bool attivo: true
        signal premuto()
        width: 38
        height: 38

        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusFull
            color: presaControllo.containsMouse && !presaControllo.pressed
                   ? Theme.Colors.hover
                   : presaControllo.pressed ? Theme.Colors.pressed
                     : "transparent"
            opacity: parent.attivo ? 1 : 0.35

            Ui.Icon {
                anchors.centerIn: parent
                width: 18
                height: 18
                name: parent.parent.icona
                color: Theme.Colors.text
            }
            MouseArea {
                id: presaControllo
                anchors.fill: parent
                hoverEnabled: true
                enabled: parent.parent.attivo
                onClicked: parent.parent.premuto()
            }
        }
    }

    /// Il tasto grande riproduci/pausa.
    component TastoPlay: Rectangle {
        property bool suonando: false
        signal premuto()
        width: 44
        height: 44
        radius: Theme.Effects.radiusFull
        color: Theme.Colors.accent

        Ui.Icon {
            anchors.centerIn: parent
            width: 20
            height: 20
            name: parent.suonando ? "pause" : "play"
            color: Theme.Colors.textOnAccent
        }
        MouseArea {
            anchors.fill: parent
            onClicked: parent.premuto()
        }
    }

    /// Il tasto tondo piccolo, per le righe.
    component TastoRiga: Rectangle {
        property string icona: ""
        signal premuto()
        width: 30
        height: 30
        radius: Theme.Effects.radiusFull
        color: presaRiga.containsMouse ? Theme.Colors.hover : "transparent"
        Ui.Icon {
            anchors.centerIn: parent
            width: 15
            height: 15
            name: parent.icona
            color: Theme.Colors.textMuted
        }
        MouseArea {
            id: presaRiga
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.premuto()
        }
    }

    /// Una riga della playlist o dell'esplora.
    component VoceFile: Item {
        // ── `parent` è nullo alla nascita ────────────────────────────────
        //
        // Questo componente si usa come `delegate` di un ListView, e un
        // delegato viene COSTRUITO prima di essere agganciato alla lista:
        // per un istante `parent` non c'è. Con `width: parent.width` secco
        // quell'istante stampa «TypeError: Cannot read property 'width' of
        // null» — una volta per riga, a ogni riga, per sempre.
        //
        // Non si vedeva perché finiva nel registro di Quickshell e nessuno lo
        // leggeva. Trovato il 4 settembre 2026 leggendo quel registro.
        property string testo: ""
        property string icona: "music"
        property bool selezionata: false
        signal riproduci()
        signal taglia()
        signal condividi()
        width: parent ? parent.width : 0
        height: 44

        // Il clic sulla riga riproduce; i tasti stanno SOPRA e si prendono
        // i loro clic.
        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusSM
            color: presaVoce.containsMouse
                   ? Theme.Colors.hover
                   : parent.selezionata ? Qt.alpha(Theme.Colors.accent, 0.10)
                     : "transparent"
        }

        MouseArea {
            id: presaVoce
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.riproduci()
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space2
            spacing: Theme.Effects.space3

            Ui.Icon {
                width: 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                name: parent.parent.icona
                color: parent.parent.selezionata
                       ? Theme.Colors.accent : Theme.Colors.textMuted
            }
            Text {
                width: parent.width - 200
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.testo
                elide: Text.ElideMiddle
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeMD
                       ; weight: Theme.Typography.weightMedium }
                color: Theme.Colors.text
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: Theme.Effects.space2
                       verticalCenter: parent.verticalCenter }
            spacing: Theme.Effects.space1
            TastoRiga {
                icona: "play"
                onPremuto: parent.parent.riproduci()
            }
            TastoRiga {
                icona: "cut"
                onPremuto: parent.parent.taglia()
            }
            TastoRiga {
                icona: "share"
                onPremuto: parent.parent.condividi()
            }
        }
    }

    /// Un risultato di ricerca: miniatura, titolo, e i due download.
    component VoceRisultato: Item {
        property string titolo: ""
        property string canale: ""
        property real durata: 0
        property string miniatura: ""
        property string url: ""
        signal scaricaAudio()
        signal scaricaVideo()
        width: parent ? parent.width : 0
        height: 58

        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusSM
            color: presaRisultato.containsMouse ? Theme.Colors.hover : "transparent"
        }

        MouseArea {
            id: presaRisultato
            anchors.fill: parent
            hoverEnabled: true
        }

        Row {
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            spacing: Theme.Effects.space3

            Rectangle {
                width: 80
                height: 45
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                clip: true

                Image {
                    anchors.fill: parent
                    source: parent.parent.parent.miniatura
                    fillMode: Image.PreserveAspectCrop
                    // La miniatura di un risultato di ricerca arriva grande
                    // quanto l'ha fatta YouTube e qui sta in 80×45: senza
                    // `sourceSize` si decodificava intera, e senza
                    // `asynchronous` lo faceva sul filo dell'interfaccia
                    // **mentre si scorreva**. Il doppio della misura, per gli
                    // schermi scalati.
                    sourceSize.width: 160
                    asynchronous: true
                    cache: true
                }
                Ui.Icon {
                    visible: parent.parent.parent.miniatura === ""
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    name: "music"
                    color: Theme.Colors.textFaint
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 80 - 110 - Theme.Effects.space3 * 3
                spacing: Theme.Effects.space1

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: parent.parent.parent.titolo
                    elide: Text.ElideRight
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeMD
                           ; weight: Theme.Typography.weightMedium }
                    color: Theme.Colors.text
                }
                Text {
                    width: parent.width
                    text: (parent.parent.parent.canale
                           ? parent.parent.parent.canale + " · " : "")
                          + finestra._tempo(parent.parent.parent.durata * 1000)
                    elide: Text.ElideRight
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeXS }
                    color: Theme.Colors.textFaint
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: Theme.Effects.space2
                       verticalCenter: parent.verticalCenter }
            spacing: Theme.Effects.space1
            TastoRiga {
                icona: "music"
                onPremuto: parent.parent.scaricaAudio()
            }
            TastoRiga {
                icona: "video"
                onPremuto: parent.parent.scaricaVideo()
            }
        }
    }

    /// Una maniglia di selezione sull'onda.
    component Maniglia: Rectangle {
        property real minimo: 0
        property real massimo: 1
        signal mossa(real x)
        width: 10
        radius: 3
        color: Theme.Colors.accent
        anchors { top: parent.top; bottom: parent.bottom }

        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            width: 2
            color: Qt.alpha(Theme.Colors.accent, 0.5)
        }
        MouseArea {
            id: presaManiglia
            anchors.fill: parent
            property real avvio: 0
            onPressed: function (m) {
                presaManiglia.avvio = m.x;
            }
            onPositionChanged: function (m) {
                if (!presaManiglia.pressed)
                    return;
                var n = parent.x + (m.x - presaManiglia.avvio);
                n = Math.max(parent.minimo,
                             Math.min(parent.massimo, n));
                parent.x = n;
                parent.mossa(n);
            }
        }
    }
}