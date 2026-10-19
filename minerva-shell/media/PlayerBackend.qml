import QtQuick
import QtMultimedia

// PlayerBackend — Il riproduttore di Minerva Media, uno solo.
//
// Prima c'erano due `MediaPlayer` di Qt Multimedia (la finestra e il
// `Lettore`), e niente mpv. Qui il motore è mpv (modulo nativo
// `Liquid.Media`, `native/mpv/`): decodifica in hardware con VA-API, HLS e
// IPTV, pagine YouTube attraverso yt-dlp. Se il modulo manca, o se la
// finestra non disegna con OpenGL (`QT_QUICK_BACKEND=software`), si torna a
// Qt Multimedia e `motore` lo dice.
//
// Il video è un elemento che il riproduttore possiede e sposta: `mostraIn`
// lo appoggia nella finestra grande o nel PiP. Con mpv il passaggio da una
// finestra all'altra ricrea il contesto OpenGL nella nuova (vedi
// `releaseRenderer` in liquidmedia.cpp); la riproduzione non si ferma.
//
// Tempi in millisecondi, volume da 0 a 1.
Item {
    id: lettore
    visible: false

    property url source
    property real volume: 1
    property bool muted: false
    /// Vera per musica e radio: mpv apre il file senza aspettare una
    /// superficie video, che a pagina nascosta non disegna mai.
    property bool audioOnly: false

    readonly property string motore: _mpv ? "mpv" : "qt"
    readonly property bool playing: _mpv ? _mpv.playing
                                         : qt.playbackState === MediaPlayer.PlayingState
    readonly property real position: _mpv ? _mpv.position : qt.position
    readonly property real duration: _mpv ? _mpv.duration : qt.duration
    readonly property string errorString: _mpv
        ? (_mpv.errorString !== "" ? _mpv.errorString : _superficie.renderError)
        : (qt.error !== MediaPlayer.NoError ? qt.errorString : "")
    /// Il decodificatore hardware in uso («vaapi»), vuoto se nessuno.
    readonly property string decodificatore: _mpv ? _mpv.hardwareDecoder : ""

    /// Il brano è arrivato in fondo da sé.
    signal finito()

    function play() { _vuoleSuonare = true; if (_mpv) _mpv.play(); else qt.play(); }
    function pause() { _vuoleSuonare = false; if (_mpv) _mpv.pause(); else qt.pause(); }
    function stop() { _vuoleSuonare = false; if (_mpv) _mpv.stop(); else qt.stop(); }
    function seek(ms) {
        ms = Math.max(0, Math.round(ms));
        if (_mpv) _mpv.seek(ms); else qt.position = ms;
    }

    /// Appoggia il video dentro [contenitore] (null: da nessuna parte).
    function mostraIn(contenitore) {
        _contenitore = contenitore;
        _video().parent = contenitore;
    }

    // ── Dentro ───────────────────────────────────────────────────────────

    property var _mpv: null
    /// L'ultimo comando fra play e pausa/stop. Un file aperto all'avvio
    /// (MINERVA_MEDIA_APRI) chiede play prima che mpv esista: lo prendeva
    /// Qt Multimedia, poi mpv riceveva il file ma non il play e restava in
    /// pausa, mentre Qt perdeva l'uscita audio. Silenzio (19 ottobre).
    property bool _vuoleSuonare: false
    property var _superficie: null
    property Item _contenitore: null

    function _video() { return _mpv ? _superficie : uscitaQt; }

    Component.onCompleted: {
        // `import Liquid.Media` in testa al file renderebbe Media
        // inutilizzabile dove il modulo non c'è: lo si chiede qui, e un
        // errore vuol dire Qt Multimedia.
        try {
            _mpv = Qt.createQmlObject(
                "import Liquid.Media 1.0; MpvPlayer {}", lettore, "PlayerBackend.mpv");
            _superficie = Qt.createQmlObject(
                "import QtQuick; import Liquid.Media 1.0; MpvSurface { anchors.fill: parent }",
                lettore, "PlayerBackend.superficie");
        } catch (e) {
            console.log("[Media] mpv non disponibile, uso Qt Multimedia:", e);
            _lasciaMpv();
            return;
        }
        if (!_mpv.ready) {
            console.log("[Media] mpv non partito, uso Qt Multimedia:", _mpv.errorString);
            _lasciaMpv();
            return;
        }
        _superficie.player = _mpv;
        // `mostraIn` può essere arrivato prima di qui (l'ordine dei
        // Component.onCompleted non è garantito): allora aveva appoggiato il
        // video di Qt, e la superficie di mpv restava nascosta per sempre.
        if (_contenitore) {
            uscitaQt.parent = lettore;
            _superficie.parent = _contenitore;
        }
        _mpv.audioOnly = Qt.binding(function () { return lettore.audioOnly; });
        _mpv.muted = Qt.binding(function () { return lettore.muted; });
        _mpv.volume = Qt.binding(function () { return lettore.volume * 100; });
        _mpv.ended.connect(lettore.finito);
        _superficie.renderErrorChanged.connect(function () {
            if (lettore._superficie && lettore._superficie.renderError === "mpv-opengl-required") {
                console.log("[Media] la finestra non disegna con OpenGL: uso Qt Multimedia");
                var eraInCorso = lettore.playing, dove = lettore.position;
                lettore._lasciaMpv();
                if (String(lettore.source) !== "") {
                    qt.source = lettore.source;
                    qt.position = dove;
                    if (eraInCorso) qt.play();
                }
            }
        });
        if (String(source) !== "") {
            qt.stop();
            _mpv.source = source;
            if (_vuoleSuonare)
                _mpv.play();
        }
    }

    function _lasciaMpv() {
        var m = _mpv, s = _superficie;
        _mpv = null;
        _superficie = null;
        if (s) s.destroy();
        if (m) m.destroy();
        uscitaQt.parent = _contenitore;
    }

    onSourceChanged: {
        if (_mpv) _mpv.source = source;
        else qt.source = source;
    }

    AudioOutput {
        id: uscitaAudio
        volume: lettore.muted ? 0 : lettore.volume
    }

    MediaPlayer {
        id: qt
        audioOutput: lettore._mpv ? null : uscitaAudio
        videoOutput: lettore._mpv ? null : uscitaQt
        onMediaStatusChanged: function (stato) {
            if (!lettore._mpv && stato === MediaPlayer.EndOfMedia)
                lettore.finito();
        }
    }

    VideoOutput {
        id: uscitaQt
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }
}
