import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

// PannelloLaterale — il riquadro dei dettagli e dell'anteprima, a destra.
//
// Il manutentore, 11 ottobre 2026: il gestore file in modalità Windows deve avere
// il pannello che ha Esplora file di Windows 11 (Visualizza → Mostra →
// Riquadro dettagli, Alt+Maiusc+P; Riquadro di anteprima, Alt+P).
//
//   dettagli   icona o immagine, nome, tipo, dimensione, ultima modifica,
//              misure di un'immagine, percorso; con più file selezionati
//              quanti sono e quanto pesano in tutto
//   anteprima  l'immagine grande, o le prime righe di un testo
//
// ── Cosa legge, e quando ─────────────────────────────────────────────────
//
// Niente quando è chiuso: il Loader in `FileManager.qml` non lo crea
// nemmeno. Aperto, chiede al demone `fs_anteprima` per il file selezionato,
// che legge al massimo 16 KB (`FileService.anteprima`), e solo dopo una
// breve pausa: scorrendo con le frecce non parte una lettura per ogni file
// attraversato. Ogni domanda ha un numero, e una risposta col numero vecchio
// (una selezione già cambiata) si butta via.
Rectangle {
    id: pannello
    objectName: "filesPannelloLaterale"

    /// «dettagli» o «anteprima».
    property string modo: "dettagli"
    /// Il riquadro attivo, da cui si legge la selezione.
    property var pane: null

    readonly property bool it: Core.Strings.lang === "it"

    /// Le voci selezionate nel riquadro attivo, nell'ordine dell'elenco.
    readonly property var scelte: {
        if (!pannello.pane)
            return [];
        var dentro = Object.create(null);
        var selezione = pannello.pane.selection || [];
        for (var i = 0; i < selezione.length; i++)
            dentro[selezione[i]] = true;
        return (pannello.pane.shown || []).filter(function(voce) {
            return dentro[voce.path] === true;
        });
    }
    readonly property var voce: scelte.length === 1 ? scelte[0] : null

    /// La risposta del demone per `voce`, o null finché non arriva.
    property var dati: null
    property int _richiesta: 0
    // Il contatore da solo ripartiva da zero riaprendo il Loader e coincideva
    // fra finestre: una risposta vecchia poteva essere accettata da un altro
    // pannello sullo stesso file. Il token appartiene a questa istanza.
    property string _owner: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    readonly property string requestId: _owner + ":" + _richiesta

    readonly property bool eImmagine: voce !== null && !voce.isDir && Files.isImage(voce.name)
    readonly property bool conMiniatura: voce !== null && !voce.isDir && Files.conMiniatura(voce.name)

    color: FileStyle.lettura

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: FileStyle.edge
    }

    onVoceChanged: {
        pannello.dati = null;
        pannello._richiesta++;
        if (pannello.voce)
            chiedi.restart();
        else
            chiedi.stop();
    }

    Timer {
        id: chiedi
        interval: 120
        onTriggered: {
            if (!pannello.voce)
                return;
            Core.Ipc.send({ "action": "fs_anteprima", "path": pannello.voce.path,
                            "richiesta": pannello.requestId });
        }
    }

    Connections {
        target: Core.Ipc
        function onAnteprimaReceived(r) {
            if (!r || r.richiesta !== pannello.requestId || !pannello.voce
                || r.path !== pannello.voce.path)
                return;
            pannello.dati = r;
        }
    }

    function tipo(v) {
        if (v.isDir)
            return pannello.it ? "Cartella di file" : "File folder";
        var e = Files.extension(v.name);
        return e === "" ? (pannello.it ? "File" : "File")
                        : (pannello.it ? "File " + e.toUpperCase() : e.toUpperCase() + " File");
    }

    function quando(ms) {
        if (!ms)
            return "";
        var d = new Date(ms);
        return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " "
            + d.toLocaleTimeString(Qt.locale(), "HH:mm");
    }

    /// Le righe dei dettagli, «etichetta: valore».
    readonly property var righe: {
        var v = pannello.voce;
        if (!v)
            return [];
        var r = [{ "chiave": pannello.it ? "Tipo" : "Type", "valore": pannello.tipo(v) }];
        if (!v.isDir)
            r.push({ "chiave": pannello.it ? "Dimensione" : "Size", "valore": Core.Formato.peso(v.size) });
        r.push({ "chiave": pannello.it ? "Ultima modifica" : "Date modified", "valore": pannello.quando(v.modified) });
        if (pannello.dati && pannello.dati.imageWidth > 0)
            r.push({ "chiave": pannello.it ? "Dimensioni" : "Dimensions",
                     "valore": pannello.dati.imageWidth + " × " + pannello.dati.imageHeight });
        r.push({ "chiave": pannello.it ? "Percorso" : "Path", "valore": Files.parentPath(v.path) });
        return r;
    }

    /// Con più file: quanti, e la somma di quelli che hanno una dimensione.
    readonly property string riassunto: {
        var n = pannello.scelte.length;
        if (n < 2)
            return "";
        var peso = 0;
        var cartelle = 0;
        for (var i = 0; i < n; i++) {
            if (pannello.scelte[i].isDir)
                cartelle++;
            else
                peso += pannello.scelte[i].size || 0;
        }
        var testo = n + (pannello.it ? " elementi selezionati" : " items selected");
        if (cartelle < n)
            testo += "\n" + Core.Formato.peso(peso)
                + (cartelle > 0 ? (pannello.it ? " (cartelle escluse)" : " (folders not counted)") : "");
        return testo;
    }

    Flickable {
        id: scorre
        anchors.fill: parent
        anchors.margins: 16
        anchors.leftMargin: 17
        clip: true
        contentWidth: width
        contentHeight: colonna.height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: colonna
            width: scorre.width
            spacing: 12

            // Niente selezionato: come Windows, una frase sola.
            Text {
                objectName: "filesPannelloVuoto"
                visible: pannello.scelte.length === 0
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                topPadding: 40
                text: pannello.modo === "anteprima"
                      ? (pannello.it ? "Seleziona un file per visualizzarne l'anteprima."
                                     : "Select a file to preview.")
                      : (pannello.it ? "Seleziona un elemento per visualizzarne i dettagli."
                                     : "Select a single item to see its details.")
                color: FileStyle.textMuted
                font.family: FileStyle.font
                font.pixelSize: 13
            }

            Text {
                objectName: "filesPannelloRiassunto"
                visible: pannello.scelte.length > 1
                width: parent.width
                wrapMode: Text.Wrap
                text: pannello.riassunto
                color: FileStyle.text
                font.family: FileStyle.font
                font.pixelSize: 14
                lineHeight: 1.3
            }

            // ── L'immagine o l'icona ─────────────────────────────────────
            Item {
                visible: pannello.voce !== null && !(pannello.modo === "anteprima" && pannello.testoVisibile)
                width: parent.width
                height: pannello.modo === "anteprima" ? Math.min(parent.width * 1.2, 420)
                                                      : Math.min(parent.width * 0.75, 200)

                Image {
                    id: figura
                    objectName: "filesPannelloImmagine"
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    // Si decodifica alla misura del pannello, non a quella del
                    // file: una foto da 24 megapixel in un riquadro da 260
                    // pixel non deve stare in memoria intera.
                    sourceSize.width: Math.ceil(width / 64) * 64
                    sourceSize.height: Math.ceil(height / 64) * 64
                    source: {
                        if (!pannello.voce || pannello.voce.isDir)
                            return "";
                        if (pannello.eImmagine)
                            return Files.fileUrl(pannello.voce.path);
                        if (pannello.conMiniatura) {
                            var versione = Files.miniatureVersione;
                            var f = Files.miniaturaDi(pannello.voce.path);
                            return f !== "" ? Files.fileUrl(f) : "";
                        }
                        return "";
                    }
                    visible: status === Image.Ready
                }

                FileIcon {
                    objectName: "filesPannelloIcona"
                    anchors.centerIn: parent
                    width: 96
                    height: 96
                    visible: !figura.visible && pannello.voce !== null
                    name: pannello.voce ? Files.iconFor(pannello.voce) : "document"
                    // Gli stessi colori dell'elenco (`Pane.qml`).
                    color: pannello.voce && pannello.voce.isDir ? FileStyle.accent
                                                                : FileStyle.textFaint
                    thickness: 1.2
                }
            }

            // ── Il testo, nel riquadro di anteprima ──────────────────────
            Rectangle {
                visible: pannello.modo === "anteprima" && pannello.testoVisibile
                width: parent.width
                height: Math.min(testo.implicitHeight + 20, scorre.height - 4)
                color: FileStyle.raised
                radius: 4
                clip: true

                Text {
                    id: testo
                    objectName: "filesPannelloTesto"
                    x: 10
                    y: 10
                    width: parent.width - 20
                    text: pannello.dati ? pannello.dati.testo
                          + (pannello.dati.troncato ? "\n…" : "") : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                    color: FileStyle.text
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }

            // ── Nome e dettagli ──────────────────────────────────────────
            Text {
                objectName: "filesPannelloNome"
                visible: pannello.voce !== null
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: pannello.voce ? pannello.voce.name : ""
                color: FileStyle.text
                font.family: FileStyle.font
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Repeater {
                model: pannello.modo === "dettagli" ? pannello.righe : []

                delegate: Column {
                    required property var modelData
                    width: colonna.width
                    spacing: 2

                    Text {
                        text: modelData.chiave
                        color: FileStyle.textMuted
                        font.family: FileStyle.font
                        font.pixelSize: 12
                    }
                    Text {
                        objectName: "filesPannelloValore-" + modelData.chiave
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: modelData.valore
                        color: FileStyle.text
                        font.family: FileStyle.font
                        font.pixelSize: 13
                    }
                }
            }

            // Un binario nel riquadro di anteprima: come Windows, lo dice.
            Text {
                objectName: "filesPannelloNessunaAnteprima"
                visible: pannello.modo === "anteprima" && pannello.voce !== null
                         && !pannello.voce.isDir && pannello.dati !== null
                         && pannello.dati.binario && !figura.visible
                width: parent.width
                wrapMode: Text.Wrap
                text: pannello.it ? "Nessuna anteprima disponibile." : "No preview available."
                color: FileStyle.textMuted
                font.family: FileStyle.font
                font.pixelSize: 13
            }
        }
    }

    // Un PDF o un video si mostrano con la loro miniatura, anche quando i
    // loro primi byte sembrano testo (un PDF comincia con «%PDF-1.4»).
    readonly property bool testoVisibile: pannello.dati !== null && pannello.dati.ok
                                          && !pannello.dati.binario && pannello.dati.testo !== ""
                                          && !pannello.eImmagine && !pannello.conMiniatura

    Ui.Scorrimento {
        bersaglio: scorre
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
    }
}
