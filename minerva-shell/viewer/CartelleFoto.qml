import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// CartelleFoto — Dove guarda la galleria.
//
// La galleria non cammina tutta la casa (vedi `Galleria.qml`): guarda le
// cartelle scelte. Il demone sapeva già tutto — proporre dove sembrano
// esserci foto, aggiungere e togliere cartelle, nascondere le schermate,
// rifare il catalogo — e non c'era un solo pulsante per chiederglielo. Il
// risultato era una galleria che restava vuota per sempre: «Cerca le mie
// foto» chiedeva le proposte, e la risposta non la ascoltava nessuno
// (5 ottobre 2026).
//
// Si apre sopra la galleria; chiudendolo, se qualcosa è cambiato, si rifà il
// catalogo da sé — chi ha appena scelto le cartelle vuole vedere le foto,
// non cercare un secondo pulsante.
Rectangle {
    id: pannello

    readonly property bool it: Core.Strings.lang === "it"
    signal chiuso()
    /// «Foto doppie»: le apre la galleria, sopra questo pannello.
    signal doppioniChiesti()

    color: Theme.Colors.scrim

    property var cartelle: []
    property var escluse: []
    property var proposte: []
    /// Per cosa si è aperto il selettore: "aggiungi" o "escludi".
    property string scopo: "aggiungi"
    property bool mostraSchermate: true
    property bool cercandoProposte: false
    property string errore: ""
    /// Qualcosa è cambiato: alla chiusura si rifà il catalogo.
    property bool cambiato: false

    // La scansione: quante voci trovate camminando, quante già lette.
    property bool scansionando: false
    property int trovate: 0
    property int lette: 0
    property string esito: ""

    readonly property string casa: Quickshell.env("HOME") || ""
    function breve(p) {
        var s = String(p);
        return pannello.casa !== "" && s.indexOf(pannello.casa + "/") === 0
            ? "~/" + s.substring(pannello.casa.length + 1) : s;
    }
    function scelta(p) {
        return pannello.cartelle.indexOf(String(p)) !== -1;
    }

    function apri() {
        pannello.visible = true;
        pannello.errore = "";
        pannello.cambiato = false;
        Core.Ipc.fotoLeggiCartelle();
        pannello.cercandoProposte = true;
        Core.Ipc.fotoCerca();
    }

    function chiudi() {
        pannello.visible = false;
        if (pannello.cambiato && pannello.cartelle.length > 0)
            pannello.scansiona();
        pannello.chiuso();
    }

    function scansiona() {
        pannello.scansionando = true;
        pannello.trovate = 0;
        pannello.lette = 0;
        pannello.esito = "";
        Core.Ipc.fotoScansiona();
    }

    Connections {
        target: Core.Ipc
        function onFotoCartelle(p) {
            if (!p)
                return;
            if (p.ok === false) {
                pannello.errore = p.error || "";
                return;
            }
            pannello.errore = "";
            if (p.cartelle !== undefined)
                pannello.cartelle = p.cartelle;
            if (p.escludi !== undefined)
                pannello.escluse = p.escludi;
            if (p.mostraSchermate !== undefined)
                pannello.mostraSchermate = p.mostraSchermate !== false;
        }
        function onFotoProposte(p) {
            pannello.cercandoProposte = false;
            if (p && p.ok === true)
                pannello.proposte = p.proposte || [];
        }
        function onFotoScansione(p) {
            if (!p)
                return;
            if (p.fase === "cammino") {
                pannello.trovate = p.trovati || 0;
                return;
            }
            if (p.fine !== true) {
                pannello.lette += (p.voci || []).length;
                return;
            }
            pannello.scansionando = false;
            pannello.esito = p.nessunaCartella
                ? (pannello.it ? "Nessuna cartella scelta." : "No folder chosen.")
                : p.fermata
                  ? (pannello.it ? "Fermata." : "Stopped.")
                  : (pannello.it ? p.totale + " fra foto e video."
                                 : p.totale + " photos and videos.");
        }
    }

    // Prende i clic: sotto c'è la galleria.
    MouseArea { anchors.fill: parent; onClicked: pannello.chiudi() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Effects.space6, 560)
        height: Math.min(parent.height - Theme.Effects.space6,
                         colonna.implicitHeight + Theme.Effects.space5 * 2)
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge
        clip: true

        MouseArea { anchors.fill: parent }

        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.Effects.space5
            contentHeight: colonna.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: colonna
                width: parent.width
                spacing: Theme.Effects.space3

                Text {
                    width: parent.width
                    text: pannello.it ? "Dove cerco le foto" : "Where I look for photos"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                }

                Text {
                    width: parent.width
                    visible: pannello.errore !== ""
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: pannello.errore
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // ── Le cartelle scelte ───────────────────────────────────
                Text {
                    width: parent.width
                    visible: pannello.cartelle.length === 0
                    wrapMode: Text.WordWrap
                    text: pannello.it
                          ? "Nessuna cartella ancora. Scegline una qui sotto: Minerva non guarda tutta la cartella personale, o ti mostrerebbe le icone dei programmi."
                          : "No folder yet. Pick one below: Minerva doesn't scan your whole home, or it would show you program icons."
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Repeater {
                    model: pannello.cartelle
                    delegate: RigaCartella {
                        required property var modelData
                        width: colonna.width
                        testo: pannello.breve(modelData)
                        azione: pannello.it ? "Togli" : "Remove"
                        pericolo: true
                        onPremuta: {
                            pannello.cambiato = true;
                            Core.Ipc.fotoTogliCartella(String(modelData));
                        }
                    }
                }

                // ── Le proposte ──────────────────────────────────────────
                Text {
                    width: parent.width
                    topPadding: Theme.Effects.space2
                    text: pannello.it ? "Dove sembrano esserci foto" : "Where photos seem to be"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightMedium
                }

                Text {
                    width: parent.width
                    visible: pannello.cercandoProposte
                    text: pannello.it ? "Guardo in giro…" : "Looking around…"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Repeater {
                    model: pannello.proposte.filter(function (p) {
                        return !pannello.scelta(p.percorso);
                    })
                    delegate: RigaCartella {
                        required property var modelData
                        width: colonna.width
                        testo: pannello.breve(modelData.percorso)
                        dettaglio: pannello.it ? modelData.quante + " fra foto e video"
                                               : modelData.quante + " photos and videos"
                        azione: pannello.it ? "Aggiungi" : "Add"
                        onPremuta: {
                            pannello.cambiato = true;
                            Core.Ipc.fotoAggiungiCartella(String(modelData.percorso));
                        }
                    }
                }

                RigaCartella {
                    width: colonna.width
                    testo: pannello.it ? "Un'altra cartella…" : "Another folder…"
                    azione: pannello.it ? "Scegli" : "Choose"
                    onPremuta: {
                        pannello.scopo = "aggiungi";
                        selettore.apri(pannello.casa);
                    }
                }

                // ── Le escluse ───────────────────────────────────────────
                //
                // Una sottocartella da saltare dentro una scelta: le
                // miniature di un programma, un archivio di lavoro.
                Text {
                    width: parent.width
                    topPadding: Theme.Effects.space2
                    visible: pannello.cartelle.length > 0
                    text: pannello.it ? "Da saltare" : "Skip these"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightMedium
                }

                Repeater {
                    model: pannello.cartelle.length > 0 ? pannello.escluse : []
                    delegate: RigaCartella {
                        required property var modelData
                        width: colonna.width
                        testo: pannello.breve(modelData)
                        azione: pannello.it ? "Includi" : "Include"
                        onPremuta: {
                            pannello.cambiato = true;
                            Core.Ipc.fotoEscludi(String(modelData), false);
                        }
                    }
                }

                RigaCartella {
                    width: colonna.width
                    visible: pannello.cartelle.length > 0
                    testo: pannello.it ? "Salta una cartella…" : "Skip a folder…"
                    azione: pannello.it ? "Scegli" : "Choose"
                    onPremuta: {
                        pannello.scopo = "escludi";
                        selettore.apri(pannello.cartelle[0]);
                    }
                }

                // ── Le schermate ─────────────────────────────────────────
                RigaCartella {
                    width: colonna.width
                    testo: pannello.it ? "Mostra le schermate" : "Show screenshots"
                    dettaglio: pannello.it ? "Le catture dello schermo, fra le foto"
                                           : "Screen captures, among the photos"
                    azione: pannello.mostraSchermate ? (pannello.it ? "Sì" : "Yes")
                                                     : (pannello.it ? "No" : "No")
                    onPremuta: {
                        pannello.cambiato = true;
                        Core.Ipc.fotoMostraSchermate(!pannello.mostraSchermate);
                    }
                }

                // ── Le doppie ────────────────────────────────────────────
                RigaCartella {
                    width: colonna.width
                    visible: pannello.cartelle.length > 0
                    testo: pannello.it ? "Foto doppie" : "Duplicate photos"
                    dettaglio: pannello.it ? "Le copie esatte, da mandare nel cestino"
                                           : "Exact copies, to send to the trash"
                    azione: pannello.it ? "Cerca" : "Find"
                    onPremuta: pannello.doppioniChiesti()
                }

                // ── Il catalogo ──────────────────────────────────────────
                Row {
                    width: parent.width
                    spacing: Theme.Effects.space3
                    topPadding: Theme.Effects.space2

                    Ui.SpineButton {
                        height: 36
                        horizontalPadding: Theme.Effects.space4
                        enabled: pannello.cartelle.length > 0
                        onClicked: pannello.scansionando ? Core.Ipc.fotoFermaScansione()
                                                         : pannello.scansiona()
                        content: Text {
                            text: pannello.scansionando
                                  ? (pannello.it ? "Ferma" : "Stop")
                                  : (pannello.it ? "Cerca di nuovo" : "Look again")
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pannello.scansionando
                              ? (pannello.trovate > 0
                                 ? (pannello.it ? "Leggo " + pannello.lette + " di " + pannello.trovate + "…"
                                                : "Reading " + pannello.lette + " of " + pannello.trovate + "…")
                                 : (pannello.it ? "Cammino nelle cartelle…" : "Walking the folders…"))
                              : pannello.esito
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Item { width: 1; height: 1 }
                }

                Ui.SpineButton {
                    anchors.right: parent.right
                    height: 36
                    horizontalPadding: Theme.Effects.space4
                    onClicked: pannello.chiudi()
                    content: Text {
                        text: pannello.it ? "Fatto" : "Done"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                    }
                }
            }
        }
    }

    Ui.Scegli {
        id: selettore
        anchors.fill: parent
        soloCartelle: true
        it: pannello.it
        titolo: pannello.scopo === "escludi"
                ? (pannello.it ? "Una cartella da saltare" : "A folder to skip")
                : (pannello.it ? "Una cartella con le tue foto" : "A folder with your photos")
        onScelto: function (percorso) {
            pannello.cambiato = true;
            if (pannello.scopo === "escludi")
                Core.Ipc.fotoEscludi(percorso, true);
            else
                Core.Ipc.fotoAggiungiCartella(percorso);
        }
    }

    /// Una riga: un testo, un dettaglio facoltativo, un pulsante a destra.
    component RigaCartella: Item {
        id: riga
        property string testo: ""
        property string dettaglio: ""
        property string azione: ""
        property bool pericolo: false
        signal premuta()

        height: Math.max(40, testi.implicitHeight + 8)

        Column {
            id: testi
            anchors.left: parent.left
            anchors.right: bottone.left
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                text: riga.testo
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
            Text {
                width: parent.width
                visible: riga.dettaglio !== ""
                textFormat: Text.PlainText
                text: riga.dettaglio
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        Rectangle {
            id: bottone
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: bottoneTesto.implicitWidth + 22
            height: 28
            radius: Theme.Effects.radiusSM
            readonly property color tono: riga.pericolo ? Theme.Colors.danger : Theme.Colors.accent
            color: bottoneArea.containsMouse ? Qt.alpha(tono, 0.16) : Theme.Colors.raised
            border.width: 1
            border.color: Theme.Colors.edge

            Text {
                id: bottoneTesto
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: riga.azione
                color: bottoneArea.containsMouse ? bottone.tono : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: bottoneArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: riga.premuta()
            }
        }
    }
}
