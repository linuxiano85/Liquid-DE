import QtQuick
import "../theme" as Theme
import "../core" as Core

// Miniatura — Una fotografia nella griglia della galleria.
//
// ── Perché la miniatura arriva come PERCORSO ─────────────────────────────
//
// Il demone non manda i byte: manda il percorso di un file già pronto nella
// cache. Un'immagine in base64 sul canale sarebbe circa un megabyte per
// schermata di griglia, e il canale è lo stesso su cui passano le finestre e
// le scorciatoie.
//
// La risposta riporta anche `percorsoFoto` — il file di partenza — perché le
// richieste tornano **fuori ordine**: dieci miniature chieste insieme non
// tornano nell'ordine in cui sono state chieste, e senza quel campo ognuna
// finirebbe nella cella sbagliata. È scritto in `EVENTS.md`, e questa è la
// metà che lo usa.
//
// ── E perché si chiede a scatti ──────────────────────────────────────────
//
// `lato` non è la misura esatta della cella: è arrotondata a scatti di 64.
// Legare la richiesta al numero preciso vorrebbe dire rifare tutte le
// miniature a ogni scatto di rotellina che cambia la larghezza della finestra.
// È la stessa lezione già pagata in `viewer/Griglia.qml`.
Item {
    id: cella

    /// La voce dell'indice: `{percorso, tipo, data, durataMs, preferito, …}`.
    property var voce: null
    /// Lato della cella in pixel.
    property int lato: 160
    /// Vero quando fa parte della selezione.
    property bool scelta: false

    signal apri()
    signal menu(real x, real y)
    signal sceltaCambiata(bool conCtrl, bool conShift)

    readonly property string percorso: cella.voce ? String(cella.voce.percorso) : ""
    readonly property bool video: cella.voce && cella.voce.tipo === "video"
    readonly property bool preferito: cella.voce && cella.voce.preferito === true

    /// Il lato da chiedere, arrotondato in su a scatti di 64.
    readonly property int latoChiesto: Math.max(64, Math.ceil(cella.lato / 64) * 64)

    /// Da percorso a indirizzo: gli spazi e gli accenti vanno codificati, e
    /// `#` e `?` a mano perché `encodeURI` li lascia passare come parti
    /// dell'indirizzo invece che del nome. Una foto che si chiama «mare #3.jpg»
    /// senza questo non si apre.
    function indirizzo(percorso) {
        return "file://" + encodeURI(String(percorso))
                            .replace(/#/g, "%23").replace(/\?/g, "%3F");
    }

    property string _miniatura: ""
    property bool _chiesta: false

    function _chiedi() {
        if (cella.percorso === "" || cella._chiesta)
            return;
        cella._chiesta = true;
        Core.Ipc.fotoChiediMiniatura(cella.percorso, cella.latoChiesto);
    }

    // Si chiede quando la cella entra davvero in scena, non quando viene
    // costruita: la ListView costruisce anche un po' fuori dallo schermo, e
    // chiedere lì vorrebbe dire pagare miniature che nessuno guarderà.
    onVisibleChanged: if (visible) cella._chiedi()
    Component.onCompleted: if (visible) cella._chiedi()
    onPercorsoChanged: {
        cella._miniatura = "";
        cella._chiesta = false;
        if (visible) cella._chiedi();
    }
    onLatoChiestoChanged: {
        // Cambiata la misura a scatti: si richiede, ma NON si butta quella che
        // c'è. Vederla sgranata per un istante è meglio di un buco grigio.
        cella._chiesta = false;
        if (visible) cella._chiedi();
    }

    Connections {
        target: Core.Ipc
        function onFotoMiniatura(p) {
            if (!p || String(p.percorsoFoto) !== cella.percorso)
                return;
            if (p.ok === true && p.percorso)
                cella._miniatura = String(p.percorso);
        }
    }

    // ── Il fondo ─────────────────────────────────────────────────────────
    //
    // Sotto la fotografia, e non dietro il vetro della finestra: una foto
    // scura su un fondo trasparente lascia vedere lo sfondo attraverso i suoi
    // stessi neri, e sembra sporca. È la stessa scelta del tavolo di visione.
    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusSM
        color: Qt.alpha(Theme.Colors.text, 0.06)
        border.width: cella.scelta ? 2 : 0
        border.color: Theme.Colors.accent
    }

    Image {
        id: foto
        anchors.fill: parent
        anchors.margins: cella.scelta ? 2 : 0
        // `encodeURI` e non una concatenazione nuda: un percorso con uno
        // spazio o un accento — e le cartelle di foto ne sono piene — darebbe
        // un indirizzo che Qt non apre, e la cella resterebbe vuota senza
        // dire niente. È lo stesso conto di `files/Files.fileUrl()`, e sta
        // qui perché quel file è del gestore file, non del visualizzatore.
        source: cella._miniatura !== "" ? cella.indirizzo(cella._miniatura) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        // La miniatura arriva già alla misura giusta: chiedere a Qt di
        // ridecodificarla a una misura diversa vorrebbe dire farlo due volte.
        sourceSize.width: cella.latoChiesto
        sourceSize.height: cella.latoChiesto
        visible: status === Image.Ready

        // Niente `layer.effect` per arrotondare gli angoli, e non è una
        // dimenticanza: le nostre app disegnano col processore
        // (`QT_QUICK_BACKEND=software`), e lì un effetto di livello fa
        // **sparire** l'oggetto senza dare errore. È già costato il ritratto
        // tondo delle Impostazioni. Gli angoli li dà il fondo sotto.
    }

    // Finché non c'è, un rettangolo con dentro niente. Non una rotellina che
    // gira: cento rotelline in una griglia sono cento animazioni.
    Rectangle {
        anchors.centerIn: parent
        width: Math.round(cella.lato * 0.22)
        height: width
        radius: width / 2
        visible: !foto.visible
        color: Qt.alpha(Theme.Colors.text, 0.10)
    }

    // ── I due segni che una miniatura deve portare ───────────────────────

    /// La durata, sui video. Senza, un video in griglia è indistinguibile da
    /// una fotografia finché non lo si apre.
    Rectangle {
        visible: cella.video
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        width: durata.implicitWidth + 10
        height: durata.implicitHeight + 4
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.55)

        Text {
            id: durata
            anchors.centerIn: parent
            color: "white"
            font.family: Theme.Typography.fontMono
            font.pixelSize: Math.max(9, Math.round(cella.lato * 0.075))
            text: {
                var ms = cella.voce && cella.voce.durataMs ? cella.voce.durataMs : 0;
                if (ms <= 0)
                    return "video";
                var s = Math.round(ms / 1000);
                var m = Math.floor(s / 60);
                var r = s % 60;
                return m + ":" + (r < 10 ? "0" : "") + r;
            }
        }
    }

    /// La stella. In alto a destra, dove non copre un viso al centro.
    Text {
        visible: cella.preferito
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
        text: "★"
        color: Theme.Colors.accent
        font.pixelSize: Math.max(11, Math.round(cella.lato * 0.11))
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.5)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (m) {
            if (m.button === Qt.RightButton) {
                var g = cella.mapToGlobal(m.x, m.y);
                cella.menu(g.x, g.y);
                return;
            }
            cella.sceltaCambiata((m.modifiers & Qt.ControlModifier) !== 0,
                                 (m.modifiers & Qt.ShiftModifier) !== 0);
        }
        onDoubleClicked: cella.apri()
    }
}
