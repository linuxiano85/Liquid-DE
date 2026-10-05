import QtQuick
import "../theme" as Theme
import "../core" as Core
import "." as Ui

// Condividi — «mandalo fuori di qui»: Bluetooth, posta, e quel che verrà.
//
// Giacomo, 18 agosto 2026: «prima di continuare implementa la condivisione
// via mail bluetooth e altri nel file manager».
//
// La regola sta nel demone (`minervad/lib/services/condivisione_service.dart`)
// e qui non si ripete: «non si offre una destinazione che non può funzionare,
// e quando non può si dice perché». Ogni destinazione torna SEMPRE, anche
// spenta — sparire è la cosa peggiore che possa fare una voce di menu, perché
// chi la cercava resta a chiedersi se l'ha sognata. Questa finestrella si
// limita a mostrare quel motivo invece di nasconderlo.
Rectangle {
    id: chiedi

    anchors.fill: parent
    color: Theme.Colors.scrim
    visible: false
    z: 40

    readonly property bool it: Core.Strings.lang === "it"

    property var file: []
    property var destinazioni: []
    property bool caricando: false

    /// "destinazioni" — la scelta fra Bluetooth e posta.
    /// "dispositivi"   — a chi, sul Bluetooth.
    /// "mandando"       — richiesta partita, in attesa di risposta.
    /// "esito"          — fatto, bene o male.
    property string vista: "destinazioni"

    /// La destinazione su cui si è premuto, quando ne ha una seconda schermata
    /// («a quale dispositivo?», «a quale televisore?»).
    ///
    /// Si chiamava `destinazioneBluetooth` finché il Bluetooth era l'unica ad
    /// avere un elenco. Da quando i televisori si possono davvero raggiungere
    /// ne ha uno anche «Trasmetti a schermo», e un nome che dice «Bluetooth»
    /// per una cosa che ospita anche i televisori è il modo in cui fra un mese
    /// qualcuno aggiunge una terza copia della stessa schermata.
    property var destinazioneScelta: null
    property bool mandandoOk: true
    property string mandandoTesto: ""

    readonly property string titolo: {
        var n = chiedi.file.length;
        if (n === 0) return "";
        if (n === 1) {
            var p = String(chiedi.file[0]);
            var taglio = p.lastIndexOf("/");
            return taglio < 0 ? p : p.substring(taglio + 1);
        }
        return chiedi.it ? n + " elementi" : n + " items";
    }

    function apri(paths) {
        chiedi.file = paths || [];
        chiedi.destinazioni = [];
        chiedi.destinazioneScelta = null;
        chiedi.vista = "destinazioni";
        chiedi.caricando = true;
        chiedi.visible = true;
        Core.Ipc.condivisioneDove();
    }

    focus: chiedi.visible
    Keys.onEscapePressed: chiedi.chiudi()

    /// Chi ospita questa finestrella deve sapere quando se ne va: sulla
    /// scrivania vive dentro una finestra di sovrapposizione tutta sua, che va
    /// spenta insieme a lei o resta a mangiarsi i clic di tutto lo schermo.
    signal chiuso()

    function chiudi() {
        chiedi.visible = false;
        chiedi.file = [];
        chiedi.chiuso();
    }

    Connections {
        target: Core.Ipc

        function onCondivisioneDoveRicevute(dati) {
            if (!chiedi.visible) return;
            chiedi.caricando = false;
            chiedi.destinazioni = (dati && dati.destinazioni) || [];
        }

        function onCondivisioneEsito(esito) {
            if (!chiedi.visible) return;
            chiedi.mandandoOk = esito && esito.ok === true;
            chiedi.mandandoTesto = chiedi.mandandoOk
                ? (esito.messaggio || (chiedi.it ? "Fatto." : "Done."))
                : ((esito && esito.error) || (chiedi.it ? "Non sono riuscito."
                                                         : "I couldn't."));
            chiedi.vista = "esito";
        }
    }

    function scegli(d) {
        if (!d.disponibile) return;
        // Le destinazioni con un elenco chiedono «a chi?» prima di mandare.
        if (d.id === "bluetooth" || d.id === "schermo") {
            chiedi.destinazioneScelta = d;
            chiedi.vista = "dispositivi";
            return;
        }
        chiedi._manda("email", "");
    }

    function _manda(dove, bersaglio) {
        chiedi.vista = "mandando";
        Core.Ipc.condivisioneInvia(dove, chiedi.file, bersaglio);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: chiedi.chiudi()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Effects.space6, 420)
        height: Math.min(parent.height - Theme.Effects.space6,
                         corpo.implicitHeight + Theme.Effects.space5 * 2)
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent }

        Column {
            id: corpo
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space5
            spacing: Theme.Effects.space3

            // ── La testata: torna indietro dai dispositivi, o niente ────
            Row {
                width: parent.width
                spacing: Theme.Effects.space2

                Ui.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    visible: chiedi.vista === "dispositivi"
                    name: "back"
                    color: Theme.Colors.textMuted
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: chiedi.vista = "destinazioni"
                    }
                }

                Text {
                    width: parent.width - (chiedi.vista === "dispositivi" ? 24 : 0)
                    elide: Text.ElideMiddle
                    text: chiedi.vista === "dispositivi"
                          ? (chiedi.it ? "Bluetooth" : "Bluetooth")
                          : (chiedi.it ? "Condividi " : "Share ") + chiedi.titolo
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightMedium
                }
            }

            // ── L'elenco delle destinazioni ──────────────────────────────
            Text {
                width: parent.width
                visible: chiedi.vista === "destinazioni" && chiedi.caricando
                text: chiedi.it ? "Verifico…" : "Checking…"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Column {
                width: parent.width
                spacing: 1
                visible: chiedi.vista === "destinazioni" && !chiedi.caricando

                Repeater {
                    model: chiedi.vista === "destinazioni" ? chiedi.destinazioni : []

                    delegate: Ui.RigaScelta {
                        required property var modelData
                        width: parent.width
                        piccola: true
                        icona: modelData.icona || "share"
                        testo: modelData.nome
                        nota: modelData.disponibile ? "" : modelData.motivo
                        opacity: modelData.disponibile ? 1 : 0.55
                        onScelto: chiedi.scegli(modelData)
                    }
                }
            }

            // ── L'elenco dei dispositivi accoppiati ──────────────────────
            Column {
                width: parent.width
                spacing: 1
                visible: chiedi.vista === "dispositivi"

                Repeater {
                    model: chiedi.vista === "dispositivi" && chiedi.destinazioneScelta
                           ? chiedi.destinazioneScelta.dispositivi : []

                    delegate: Ui.RigaScelta {
                        required property var modelData
                        readonly property bool tv:
                            chiedi.destinazioneScelta
                            && chiedi.destinazioneScelta.id === "schermo"
                        width: parent.width
                        piccola: true
                        icona: tv ? "screen" : "bluetooth"
                        testo: modelData.nome
                        // Per un televisore la nota dice COME gli si parla —
                        // Chromecast o DLNA — che è l'unica cosa che spiega
                        // perché uno funziona e un altro no.
                        nota: tv
                              ? (modelData.modello || modelData.modo || "")
                              : (modelData.connesso
                                 ? (chiedi.it ? "Connesso" : "Connected") : "")
                        onScelto: {
                            if (tv) {
                                // L'ID STABILE, non l'indirizzo: un IP cambia
                                // a ogni riaccensione del router, e domani
                                // manderebbe altrove.
                                chiedi._manda("schermo", String(modelData.id));
                                return;
                            }
                            chiedi._manda("bluetooth", modelData.indirizzo);
                        }
                    }
                }
            }

            // ── In corso, e il risultato ─────────────────────────────────
            Text {
                width: parent.width
                visible: chiedi.vista === "mandando"
                text: chiedi.it ? "Mando…" : "Sending…"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Row {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: chiedi.vista === "esito"

                Ui.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: chiedi.mandandoOk ? "check" : "close"
                    color: chiedi.mandandoOk ? Theme.Colors.accent
                                             : Theme.Colors.danger
                    alwaysDrawn: true
                }

                Text {
                    width: parent.width - 22
                    wrapMode: Text.WordWrap
                    text: chiedi.mandandoTesto
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            // ── Il piede ─────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 34

                Rectangle {
                    anchors.right: parent.right
                    width: 130
                    height: 34
                    radius: Theme.Effects.radiusSM
                    color: viaMouse.containsMouse ? Theme.Colors.raisedHigh
                                                  : Theme.Colors.raised
                    border.width: Theme.Effects.hairline
                    border.color: Theme.Colors.edge

                    Text {
                        anchors.centerIn: parent
                        text: chiedi.vista === "esito"
                              ? (chiedi.it ? "Chiudi" : "Close")
                              : (chiedi.it ? "Lascia perdere" : "Never mind")
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: viaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: chiedi.chiudi()
                    }
                }
            }
        }
    }
}
