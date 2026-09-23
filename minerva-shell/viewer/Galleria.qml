import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Galleria — Le fotografie e i video, dal più recente al più vecchio.
//
//     minerva-viewer            → questa
//     minerva-viewer foto.jpg   → il visualizzatore di sempre
//
// ── Che cosa NON fa, e perché ────────────────────────────────────────────
//
// Non guarda tutta la cartella personale. Misurato sulla macchina di Giacomo
// il 26 agosto 2026: **88.982 file** fra immagini e video, di cui 64.115 in
// `Documenti/Progetti` e 17.303 in `.local/share` — icone e risorse, non
// ricordi. Le fotografie vere, fuori dai progetti, sono **826**.
//
// Quindi non si cammina la casa: si sceglie. Alla prima apertura il programma
// PROPONE le cartelle dove sembrano esserci foto, col conteggio, e si spuntano.
//
// ── E non ordina per data del file ───────────────────────────────────────
//
// Le 826 fotografie hanno tutte lo stesso `mtime`: 8 luglio 2026, 21:29 —
// l'istante in cui sono state copiate dal telefono. Ordinandole per data di
// modifica finirebbero **tutte in un giorno solo**. La data vera la ricava il
// demone (EXIF, contenitore video, nome del file), ed è la ragione per cui
// quella parte è stata scritta prima di qualunque pixel.
Item {
    id: galleria

    readonly property bool it: Core.Strings.lang === "it"

    signal apri(string percorso)
    signal menu(string percorso, real x, real y)

    /// I giorni: `[{giorno, quante}, …]`, dal più recente.
    property var giorni: []
    property int totale: 0
    property int senzaData: 0
    property bool arrivata: false
    property bool mostraSchermate: true

    /// Lato di una miniatura. Si cambia con Ctrl+rotellina, come su Google
    /// Foto: più piccole per vederne tante, più grandi per guardarle.
    property int lato: 160

    /// I percorsi scelti. Una mappa e non un elenco: «è scelto?» si chiede
    /// una volta per cella a ogni ridisegno, e su un elenco sarebbe una
    /// scansione ogni volta.
    property var scelti: ({})
    property string ultimoScelto: ""

    function svuotaScelta() {
        galleria.scelti = ({});
        galleria.ultimoScelto = "";
    }

    function _scegli(percorso, conCtrl, conShift) {
        var s = galleria.scelti;
        if (conCtrl) {
            var copia = {};
            for (var k in s)
                copia[k] = s[k];
            if (copia[percorso])
                delete copia[percorso];
            else
                copia[percorso] = true;
            galleria.scelti = copia;
        } else {
            var solo = {};
            solo[percorso] = true;
            galleria.scelti = solo;
        }
        galleria.ultimoScelto = percorso;
    }

    // ── Il catalogo ──────────────────────────────────────────────────────

    function ricarica() {
        Core.Ipc.fotoChiediPanoramica();
    }

    Connections {
        target: Core.Ipc
        function onFotoPanoramica(p) {
            if (!p || p.ok !== true)
                return;
            galleria.giorni = p.giorni || [];
            galleria.totale = p.totale || 0;
            galleria.senzaData = p.senzaData || 0;
            galleria.mostraSchermate = p.mostraSchermate !== false;
            galleria.arrivata = true;
        }
        // Finita una scansione, il catalogo è un altro: si richiede.
        function onFotoScansione(p) {
            if (p && p.finita === true)
                galleria.ricarica();
        }
        function onFotoPreferito(p) {
            if (p && p.ok === true)
                galleria.ricarica();
        }
    }

    Component.onCompleted: galleria.ricarica()

    // ── L'elenco dei giorni ──────────────────────────────────────────────

    // Accanto al righello degli anni, non al posto suo: quello salta a
    // un anno, questa dice dove si è e quanto manca.
    Ui.Scorrimento {
        bersaglio: lista
        anchors {
            right: lista.right
            top: lista.top
            bottom: lista.bottom
        }
    }

    ListView {
        id: lista
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: righello.larghezza + 8
        clip: true
        visible: galleria.giorni.length > 0
        // Le altezze sono diverse e si sanno in anticipo: senza questa riga
        // Qt le indovina e la barra di scorrimento salta mentre si scorre.
        cacheBuffer: galleria.lato * 4

        model: galleria.giorni

        delegate: RigaGiorno {
            width: lista.width
            giorno: String(modelData.giorno)
            quante: modelData.quante || 0
            lato: galleria.lato
            larghezzaUtile: lista.width
            scelti: galleria.scelti
            onApri: (p) => galleria.apri(p)
            onMenu: (p, x, y) => galleria.menu(p, x, y)
            onScegli: (p, c, s) => galleria._scegli(p, c, s)
        }

        // ── Ctrl + rotellina cambia la misura ────────────────────────────
        //
        // Come su Google Foto. Senza Ctrl scorre, che è quello che la
        // rotellina fa dappertutto.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: function (w) {
                if ((w.modifiers & Qt.ControlModifier) === 0) {
                    w.accepted = false;
                    return;
                }
                var passo = w.angleDelta.y > 0 ? 32 : -32;
                galleria.lato = Math.max(96, Math.min(320, galleria.lato + passo));
                w.accepted = true;
            }
        }
    }

    // ── Il righello del tempo ────────────────────────────────────────────
    //
    // Gli anni sul bordo destro, per saltare al 2019 senza scorrere. Con
    // ottocento fotografie non è un lusso: è l'unico modo di muoversi.
    Item {
        id: righello
        readonly property int larghezza: 46
        width: larghezza
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: galleria.anni.length > 1

        Column {
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: galleria.anni
                Rectangle {
                    width: righello.larghezza - 10
                    height: 22
                    radius: 4
                    color: tocco.containsMouse
                           ? Qt.alpha(Theme.Colors.accent, 0.18) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: tocco.containsMouse
                               ? Theme.Colors.accent
                               : Qt.alpha(Theme.Colors.text, 0.55)
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: tocco
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: galleria.vaiAllAnno(String(modelData))
                    }
                }
            }
        }
    }

    /// Gli anni presenti, dal più recente. Si ricavano dai giorni: non c'è
    /// nulla da chiedere al demone.
    readonly property var anni: {
        var visti = {};
        var fuori = [];
        for (var i = 0; i < galleria.giorni.length; i++) {
            var g = String(galleria.giorni[i].giorno);
            if (g === "")
                continue;
            var a = g.substring(0, 4);
            if (!visti[a]) {
                visti[a] = true;
                fuori.push(a);
            }
        }
        return fuori;
    }

    function vaiAllAnno(anno) {
        for (var i = 0; i < galleria.giorni.length; i++) {
            if (String(galleria.giorni[i].giorno).substring(0, 4) === anno) {
                lista.positionViewAtIndex(i, ListView.Beginning);
                return;
            }
        }
    }

    // ── Quando non c'è ancora niente ─────────────────────────────────────
    //
    // Non un riquadro vuoto: si dice cosa manca e si dà il pulsante che lo
    // risolve. Un programma che si apre vuoto e tace sembra rotto.
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 420)
        spacing: 14
        visible: galleria.arrivata && galleria.giorni.length === 0

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: 17
            text: galleria.it ? "Nessuna fotografia, per ora"
                              : "No photos yet"
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: Qt.alpha(Theme.Colors.text, 0.6)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: 13
            text: galleria.it
                  ? "Scegli in quali cartelle cercare: Minerva non guarda tutta "
                    + "la cartella personale, o finirebbe per mostrarti le icone "
                    + "dei programmi."
                  : "Pick which folders to look in: Minerva doesn't scan your "
                    + "whole home, or it would show you program icons."
        }

        // `SpineButton` e non un pulsante nuovo: è lo stesso oggetto della
        // barra della scrivania, e un secondo pulsante disegnato a parte
        // diverge dal primo entro un mese. Vedi `viewer/Strumento.qml`, che
        // fa la stessa scelta per la barra degli strumenti.
        Ui.SpineButton {
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: galleria.cercaCartelle()
            content: Text {
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: 13
                font.weight: Theme.Typography.weightMedium
                text: galleria.it ? "Cerca le mie foto" : "Find my photos"
            }
        }
    }

    /// Chiede al demone dove sembrano esserci foto. Costa — cammina la casa,
    /// 0,4 secondi misurati — ed è per questo che è un gesto e non una cosa
    /// che succede da sola a ogni apertura.
    signal cercaCartelle()
}
