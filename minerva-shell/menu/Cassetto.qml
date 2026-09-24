import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ── Il Cassetto degli appunti ────────────────────────────────────────────
//
// Giacomo, 24 settembre 2026: «Gli appunti dove li vogliamo mettere?». Nel
// Cassetto: esce dal bordo destro dello schermo quando ci si SPINGE contro
// il puntatore (`Core.Compositore.bordo`; una sosta non basta, perché lì si
// va a prendere la barra di scorrimento), o con Super+V.
//
// Dentro c'è la storia di `cliphist`, la stessa del pannello di prima
// (`spine/panels/ClipboardPanel.qml`): un tocco rimette una voce negli
// appunti, la crocetta la toglie, «Svuota» si tocca due volte. Le immagini
// si vedono: `cliphist` le tiene come dati e basta, e il Cassetto le
// decodifica una volta sola in `$XDG_RUNTIME_DIR/liquid-de/appunti`.
//
// Una finestra sola a tutto schermo che esiste solo mentre il Cassetto è
// aperto, come il Centro: il fondo raccoglie i clic fuori.
PanelWindow {
    id: cassetto

    property bool aperto: false
    property bool mostrato: false
    /// Spazio da lasciare in alto (la barra) e in basso (la dock).
    property real margineAlto: 0
    property real margineBasso: 0

    /// Le voci, dalla più recente: `{ id, testo, immagine }`. `immagine` è
    /// il percorso della copia decodificata, o "".
    property var voci: []
    property bool disponibile: true
    property bool caricato: false
    property string cerca: ""
    /// La voce scelta con le frecce.
    property int scelta: 0
    /// La voce appena rimessa negli appunti: si accende un attimo prima che
    /// il Cassetto si chiuda, perché si veda che cosa è successo.
    property string copiata: ""
    /// «Svuota» armato dal primo tocco.
    property bool armato: false
    onArmatoChanged: if (cassetto.armato) disarma.restart(); else disarma.stop()
    Timer { id: disarma; interval: 3000; onTriggered: cassetto.armato = false }

    /// Dove stanno le immagini decodificate. In prova una cartella a parte:
    /// la cartella di `XDG_RUNTIME_DIR` è la stessa della sessione vera, e
    /// la pulizia qui sotto toglierebbe le sue.
    readonly property string _cartella: Core.Ipc.cartellaRuntime + "/appunti"
                                        + (Quickshell.env("MINERVA_PROVA") ? "-prova" : "")

    readonly property var filtrate: {
        var q = cassetto._piano(cassetto.cerca.trim());
        if (q === "")
            return cassetto.voci;
        return cassetto.voci.filter(function(v) {
            return cassetto._piano(v.testo).indexOf(q) >= 0;
        });
    }
    onFiltrateChanged: cassetto.scelta = 0

    function _piano(s) {
        s = String(s).toLowerCase();
        try { s = s.normalize("NFD").replace(/[̀-ͯ]/g, ""); } catch (e) {}
        return s;
    }

    function apri() {
        if (cassetto.aperto) return;
        cassetto.aperto = true;
        cassetto.mostrato = true;
        cassetto.cerca = "";
        campo.text = "";
        cassetto.copiata = "";
        spegni.stop();
        cassetto.carica();
    }
    function chiudi() {
        if (!cassetto.aperto) return;
        cassetto.aperto = false;
        cassetto.armato = false;
        spegni.restart();
    }
    function commuta() { cassetto.aperto ? cassetto.chiudi() : cassetto.apri(); }

    function carica() {
        elenco.running = false;
        elenco.running = true;
    }

    /// Rimette la voce negli appunti, e chiude.
    function copia(voce) {
        if (!voce) return;
        // L'id arriva da fuori (l'uscita di `cliphist`): passa come
        // argomento, non incollato nella riga.
        rimetti.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", String(voce.id)];
        rimetti.running = true;
        cassetto.copiata = voce.id;
        chiudiDopo.restart();
    }
    Timer { id: chiudiDopo; interval: Theme.Motion.liquido ? 260 : 0; onTriggered: cassetto.chiudi() }

    function togli(voce) {
        if (!voce) return;
        via.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", String(voce.id)];
        via.running = true;
        cassetto.voci = cassetto.voci.filter(function(v) { return v.id !== voce.id; });
    }

    function svuota() {
        // Anche le immagini: dopo uno svuotamento `cliphist` può ridare gli
        // stessi numeri, e una copia vecchia comparirebbe al posto della nuova.
        via.command = ["sh", "-c", "cliphist wipe; rm -f \"$1\"/[0-9]*", "sh", cassetto._cartella];
        via.running = true;
        cassetto.voci = [];
        cassetto.armato = false;
    }

    /// Per le prove: che cosa si vede.
    function riassunto() {
        var r = [];
        r.push("aperto: " + cassetto.aperto);
        r.push("voci: " + cassetto.filtrate.length + "/" + cassetto.voci.length);
        for (var i = 0; i < Math.min(8, cassetto.filtrate.length); i++) {
            var v = cassetto.filtrate[i];
            r.push((i === cassetto.scelta ? "> " : "  ") + v.id + " "
                   + (v.immagine !== "" ? "[immagine]" : v.testo.substring(0, 50)));
        }
        return r.join("\n");
    }

    // ── cliphist ────────────────────────────────────────────────────────
    //
    // Un solo processo per aprire: l'elenco, e le immagini nuove decodificate
    // accanto (quelle vecchie restano, quelle che non ci sono più si
    // tolgono). La cartella sta in `XDG_RUNTIME_DIR`: si svuota da sola
    // all'uscita dalla sessione.
    Process {
        id: elenco
        command: ["sh", "-c",
            "command -v cliphist >/dev/null || { echo '__MANCA__'; exit 0; }\n" +
            "d=\"$1\"; mkdir -p \"$d\" && chmod 700 \"$d\" || exit 0\n" +
            "cliphist list 2>/dev/null | head -100 > \"$d/elenco\"\n" +
            "t=$(printf '\\t')\n" +
            "while IFS=\"$t\" read -r id resto; do\n" +
            "  case \"$id\" in ''|*[!0-9]*) continue;; esac\n" +
            "  case \"$resto\" in '[[ binary data '*' png '*|'[[ binary data '*' jpeg '*|" +
            "'[[ binary data '*' jpg '*|'[[ binary data '*' webp '*|'[[ binary data '*' gif '*|" +
            "'[[ binary data '*' bmp '*)\n" +
            "    [ -s \"$d/$id\" ] || cliphist decode \"$id\" > \"$d/$id\" 2>/dev/null;;\n" +
            "  esac\n" +
            "done < \"$d/elenco\"\n" +
            "for f in \"$d\"/[0-9]*; do [ -e \"$f\" ] || continue\n" +
            "  grep -q \"^${f##*/}$t\" \"$d/elenco\" || rm -f \"$f\"; done\n" +
            "cat \"$d/elenco\"",
            "sh", cassetto._cartella]
        stdout: StdioCollector {
            onStreamFinished: {
                cassetto.caricato = true;
                if (text.indexOf("__MANCA__") === 0) {
                    cassetto.disponibile = false;
                    cassetto.voci = [];
                    return;
                }
                cassetto.disponibile = true;
                var out = [];
                var righe = text.split("\n");
                for (var i = 0; i < righe.length; i++) {
                    var tab = righe[i].indexOf("\t");
                    if (tab <= 0)
                        continue;
                    var id = righe[i].substring(0, tab);
                    var resto = righe[i].substring(tab + 1);
                    var img = /^\[\[ binary data .* (png|jpeg|jpg|webp|gif|bmp) /.test(resto);
                    out.push({ "id": id, "testo": img ? "Immagine" : resto,
                               "immagine": img ? "file://" + cassetto._cartella + "/" + id : "" });
                }
                cassetto.voci = out;
            }
        }
    }
    Process { id: rimetti }
    Process { id: via }

    visible: cassetto.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-cassetto"
    WlrLayershell.layer: WlrLayer.Overlay
    // La tastiera SUBITO, come il Centro: con «al primo clic» la finestra si
    // attivava sulla pressione e Qt annullava il clic (qml-fuoco-annulla-clic).
    WlrLayershell.keyboardFocus: cassetto.aperto ? WlrKeyboardFocus.Exclusive
                                                 : WlrKeyboardFocus.None

    Timer { id: spegni; interval: Theme.Motion.liquido ? 650 : 0; onTriggered: if (!cassetto.aperto) cassetto.mostrato = false }

    // Il fondo: premere fuori chiude, già alla pressione.
    MouseArea {
        anchors.fill: parent
        enabled: cassetto.aperto
        onPressed: cassetto.chiudi()
    }

    // ── Il pannello ─────────────────────────────────────────────────────
    Rectangle {
        id: pannello
        readonly property int margine: Theme.Effects.space4
        width: 380
        height: Math.max(240, cassetto.height - cassetto.margineAlto - cassetto.margineBasso - 2 * margine)
        y: cassetto.margineAlto + margine
        x: cassetto.aperto ? cassetto.width - margine - width : cassetto.width + 30
        Behavior on x {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla * 0.6; damping: 0.42 }
        }
        radius: Theme.Effects.radiusLG
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
            id: dentro
            anchors.fill: parent
            anchors.margins: Theme.Effects.space4
            opacity: cassetto.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

            // L'intestazione: il nome, quante, e Svuota.
            Item {
                id: testa
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Appunti"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightMedium
                }

                Rectangle {
                    id: svuota
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cassetto.voci.length > 0
                    height: 28
                    width: svuotaTesto.implicitWidth + 2 * Theme.Effects.space3
                    radius: height / 2
                    color: cassetto.armato ? Qt.alpha(Theme.Colors.danger, 0.85)
                         : svuotaMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
                    Text {
                        id: svuotaTesto
                        anchors.centerIn: parent
                        text: cassetto.armato ? "Ancora, per svuotare" : "Svuota"
                        color: cassetto.armato ? Theme.Colors.textOnAccent : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                        font.weight: Theme.Typography.weightMedium
                    }
                    MouseArea {
                        id: svuotaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cassetto.armato ? cassetto.svuota() : cassetto.armato = true
                    }
                }
            }

            // La ricerca.
            Rectangle {
                id: capsula
                anchors.top: testa.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                height: 40
                radius: height / 2
                color: Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: campo.activeFocus ? Qt.alpha(Theme.Colors.accent, 0.6) : Theme.Colors.edge

                Ui.Icon {
                    id: lente
                    x: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: "search"
                    color: Theme.Colors.textFaint
                }
                TextInput {
                    id: campo
                    anchors.left: lente.right
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    focus: cassetto.aperto
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    clip: true
                    onTextChanged: cassetto.cerca = text
                    Keys.onEscapePressed: cassetto.chiudi()
                    Keys.onReturnPressed: cassetto.copia(cassetto.filtrate[cassetto.scelta])
                    Keys.onEnterPressed: cassetto.copia(cassetto.filtrate[cassetto.scelta])
                    Keys.onDownPressed: cassetto.scelta = Math.min(cassetto.filtrate.length - 1, cassetto.scelta + 1)
                    Keys.onUpPressed: cassetto.scelta = Math.max(0, cassetto.scelta - 1)
                    Keys.onDeletePressed: function(evento) {
                        // Canc a campo vuoto (o a fine testo) toglie la voce
                        // scelta; dentro il testo resta un Canc normale.
                        if (campo.cursorPosition < campo.text.length) {
                            evento.accepted = false;
                            return;
                        }
                        cassetto.togli(cassetto.filtrate[cassetto.scelta]);
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: campo.text === ""
                        text: "Cerca negli appunti"
                        color: Theme.Colors.textFaint
                        font: campo.font
                    }
                }
            }

            Ui.Scorrimento {
                bersaglio: rotolo
                anchors {
                    right: rotolo.right
                    top: rotolo.top
                    bottom: rotolo.bottom
                }
            }

            Flickable {
                id: rotolo
                anchors.top: capsula.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: piede.top
                anchors.bottomMargin: Theme.Effects.space2
                clip: true
                contentHeight: colonna.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Ui.Goccia {
                    id: goccia
                    radius: Theme.Effects.radiusMD
                    attiva: ripetitore.count > cassetto.scelta ? ripetitore.itemAt(cassetto.scelta) : null
                }

                Column {
                    id: colonna
                    width: rotolo.width
                    spacing: Theme.Effects.space1

                    Text {
                        visible: cassetto.caricato && cassetto.filtrate.length === 0
                        width: parent.width
                        topPadding: Theme.Effects.space5
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: !cassetto.disponibile
                              ? "Manca cliphist: senza, gli appunti non hanno memoria."
                              : cassetto.voci.length === 0
                                ? "Niente negli appunti. Quello che copi finisce qui."
                                : "Niente negli appunti per «" + cassetto.cerca.trim() + "»."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Repeater {
                        id: ripetitore
                        model: cassetto.filtrate
                        delegate: Voce {
                            width: colonna.width
                            goccia: goccia
                            padrone: cassetto
                        }
                    }
                }
            }

            Text {
                id: piede
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Tocca per rimettere negli appunti · Canc toglie · Super+V apre e chiude"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }

    // ── Una voce ────────────────────────────────────────────────────────
    component Voce: Item {
        id: voce
        required property var modelData
        required property int index
        property Ui.Goccia goccia: null
        /// Il Cassetto: un componente in linea non vede gli id del file.
        property var padrone: null
        readonly property bool eImmagine: voce.modelData.immagine !== ""
        height: voce.eImmagine ? 96 : Math.max(44, testo.implicitHeight + 2 * Theme.Effects.space2)

        Rectangle {
            anchors.fill: parent
            radius: Theme.Effects.radiusMD
            color: Qt.alpha(Theme.Colors.accent, 0.35)
            opacity: voce.padrone.copiata === voce.modelData.id ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
        }

        MouseArea {
            id: voceMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (voce.goccia) voce.goccia.punta(voce, containsMouse);
                if (containsMouse) voce.padrone.scelta = voce.index;
            }
            onClicked: voce.padrone.copia(voce.modelData)
        }

        Text {
            id: testo
            visible: !voce.eImmagine
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.right: togli.left
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            text: voce.modelData.testo
            textFormat: Text.PlainText
            maximumLineCount: 3
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Image {
            id: figura
            visible: voce.eImmagine
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space2
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Theme.Effects.space2
            width: Math.min(parent.width - 60, height * 16 / 9)
            source: voce.eImmagine ? voce.modelData.immagine : ""
            sourceSize.height: 160
            // Il nome del file è il numero della voce, e un numero si può
            // ripresentare con un'immagine diversa: niente copia in memoria.
            cache: false
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            asynchronous: true
        }
        Row {
            visible: voce.eImmagine && figura.status !== Image.Ready
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space2
            Ui.Icon { width: 16; height: 16; name: "image"; color: Theme.Colors.textMuted }
            Text {
                text: "Immagine"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        Rectangle {
            id: togli
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 14
            opacity: voceMouse.containsMouse || togliMouse.containsMouse ? 1 : 0
            color: togliMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.8) : "transparent"
            Ui.Icon {
                anchors.centerIn: parent
                width: 12; height: 12
                name: "close"
                color: togliMouse.containsMouse ? Theme.Colors.textOnAccent : Theme.Colors.textMuted
            }
            MouseArea {
                id: togliMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                onClicked: voce.padrone.togli(voce.modelData)
            }
        }
    }
}
