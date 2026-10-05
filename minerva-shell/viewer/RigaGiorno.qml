import QtQuick
import "../theme" as Theme
import "../core" as Core

// RigaGiorno — Un giorno della galleria: l'intestazione e le sue fotografie.
//
// ── Perché una lista di GIORNI e non una griglia di foto ─────────────────
//
// È la scelta che decide se la galleria scorre o singhiozza. Una `GridView` di
// ottocento fotografie tiene in vita ottocento delegati e li rifà tutti quando
// cambia la larghezza. Una `ListView` di **quaranta giorni** ne tiene in vita
// quanti ne stanno sullo schermo — tre o quattro — e dentro ognuno una griglia
// piccola e finita.
//
// È anche il modo in cui Google Foto ottiene le intestazioni che restano
// appiccicate in cima mentre si scorre, e le righe di altezza diversa: un
// giorno con tre foto è alto una riga, uno con centosei ne è alto nove.
//
// ── E perché il giorno si chiede solo quando serve ───────────────────────
//
// La panoramica dice quanti giorni ci sono e quante foto ha ognuno — e basta
// quello per sapere quanto è alta ogni riga, cioè per disegnare la barra di
// scorrimento giusta **senza aver letto un solo file**. Le voci vere di un
// giorno si chiedono quando quella riga sta per entrare in scena.
Item {
    id: riga

    /// `"2026-03-17"`, oppure `""` per «quelle senza data».
    property string giorno: ""
    /// Quante ne ha, dalla panoramica. Serve a sapere l'altezza prima di
    /// avere le voci.
    property int quante: 0
    /// Lato di una miniatura e spazio fra loro.
    property int lato: 160
    property int spazio: 6
    /// Quanto è larga la fila di celle.
    property int larghezzaUtile: 800
    /// I percorsi scelti, per marcare le celle. Lo tiene la galleria.
    property var scelti: ({})

    signal apri(string percorso)
    signal menu(string percorso, real x, real y, bool preferito)
    signal scegli(string percorso, bool conCtrl, bool conShift)

    readonly property bool senzaData: riga.giorno === ""

    /// Quante celle stanno in una riga, almeno una.
    readonly property int perRiga:
        Math.max(1, Math.floor((riga.larghezzaUtile + riga.spazio)
                               / (riga.lato + riga.spazio)))
    readonly property int righe: Math.ceil(Math.max(1, riga.quante) / riga.perRiga)

    /// L'altezza si sa PRIMA delle voci: dalla panoramica e dalla geometria.
    /// È quello che permette alla barra di scorrimento di essere giusta da
    /// subito invece di allungarsi mentre si scorre.
    implicitHeight: intestazione.height + intestazione.anchors.topMargin
                    + riga.righe * riga.lato + (riga.righe - 1) * riga.spazio
                    + 18

    property var voci: []
    property bool _chieste: false

    function _chiedi() {
        if (riga._chieste)
            return;
        riga._chieste = true;
        Core.Ipc.fotoChiediGiorno(riga.giorno);
    }

    onVisibleChanged: if (visible) riga._chiedi()
    Component.onCompleted: if (visible) riga._chiedi()

    Connections {
        target: Core.Ipc
        function onFotoGiorno(p) {
            if (!p || p.ok !== true || String(p.giorno) !== riga.giorno)
                return;
            riga.voci = p.voci || [];
        }
        // La stella messa o tolta: se la foto è di questo giorno, si aggiorna
        // la sua voce sul posto invece di rileggere il giorno intero.
        function onFotoPreferito(p) {
            if (!p || p.ok !== true || !p.percorso)
                return;
            var v = riga.voci;
            for (var i = 0; i < v.length; i++) {
                if (String(v[i].percorso) !== String(p.percorso))
                    continue;
                var copia = v.slice();
                var voce = Object.assign({}, v[i]);
                voce.preferito = p.preferito === true;
                copia[i] = voce;
                riga.voci = copia;
                return;
            }
        }
    }

    // ── L'intestazione ───────────────────────────────────────────────────

    Text {
        id: intestazione
        anchors.top: parent.top
        anchors.topMargin: 14
        anchors.left: parent.left
        color: Theme.Colors.text
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: 15
        font.weight: Theme.Typography.weightMedium
        text: riga.senzaData
              ? (Core.Strings.lang === "it" ? "Senza data" : "No date")
              : riga.nomeGiorno(riga.giorno)
    }

    Text {
        anchors.verticalCenter: intestazione.verticalCenter
        anchors.left: intestazione.right
        anchors.leftMargin: 10
        color: Qt.alpha(Theme.Colors.text, 0.45)
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: 12
        text: riga.quante + (Core.Strings.lang === "it"
                             ? (riga.quante === 1 ? " elemento" : " elementi")
                             : (riga.quante === 1 ? " item" : " items"))
    }

    /// «martedì 17 marzo 2026». I mesi in italiano perché la galleria è di
    /// chi la guarda, non del sistema: `toLocaleDateString` seguirebbe la
    /// lingua della macchina anche quando Minerva è in un'altra.
    function nomeGiorno(g) {
        var p = String(g).split("-");
        if (p.length !== 3)
            return String(g);
        var d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
        var it = Core.Strings.lang === "it";
        var giorni = it
            ? ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]
            : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        var mesi = it
            ? ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
               "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
            : ["January", "February", "March", "April", "May", "June",
               "July", "August", "September", "October", "November", "December"];
        var testa = giorni[d.getDay()] + " " + d.getDate() + " "
                  + mesi[d.getMonth()] + " " + d.getFullYear();
        return it ? testa : (giorni[d.getDay()] + ", " + mesi[d.getMonth()]
                             + " " + d.getDate() + " " + d.getFullYear());
    }

    // ── Le fotografie ────────────────────────────────────────────────────
    //
    // Una `Grid` e non una `GridView`: qui dentro le voci sono poche e finite
    // — un giorno, non una libreria — e una vista virtualizzata dentro un'altra
    // vista virtualizzata è il modo di far ricalcolare tutto a ognuna delle
    // due. La virtualizzazione la fa la lista dei giorni, una volta sola.
    Grid {
        anchors.top: intestazione.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        columns: riga.perRiga
        spacing: riga.spazio

        Repeater {
            model: riga.voci
            Miniatura {
                width: riga.lato
                height: riga.lato
                lato: riga.lato
                voce: modelData
                scelta: riga.scelti[String(modelData.percorso)] === true
                onApri: riga.apri(String(modelData.percorso))
                onMenu: (x, y) => riga.menu(String(modelData.percorso), x, y,
                                            modelData.preferito === true)
                onSceltaCambiata: (c, s) => riga.scegli(String(modelData.percorso), c, s)
            }
        }
    }
}
