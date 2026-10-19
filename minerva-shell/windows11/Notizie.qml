import QtQuick
import "../core" as Core

// Notizie — Le notizie della bacheca Widget, sotto meteo e calendario.
//
// Come in Windows 11, sotto i widget c'è un flusso di notizie a schede:
// immagine, testata, titolo. Le notizie vengono dai feed RSS delle testate e
// le scarica il demone (`minervad/lib/services/notizie_service.dart`, dove
// c'è anche che cosa esce dal computer): nessun account, gli interessi
// restano qui, e la shell non contatta nessuno — le immagini sono file
// locali.
//
// Il manutentore, 11 ottobre 2026: «in meteo si vede solo il meteo e ci vorrebbero
// anche notizie, ma che rispettino la privacy».
Column {
    id: notizie
    objectName: "windowsNews"

    /// Aprire le impostazioni delle notizie (pagina Preset, scheda Windows).
    signal personalizza()

    readonly property bool attive: Core.Ipc.get("notizie.attive", true) === true
    property var articoli: []
    property string errore: ""
    property bool chiedendo: false

    spacing: 12
    visible: attive

    function chiedi() {
        if (!notizie.attive || notizie.chiedendo)
            return;
        notizie.chiedendo = true;
        Core.Ipc.notizie(Core.Strings.lang === "en" ? "en" : "it",
                         Core.Ipc.get("notizie.interessi", []),
                         Core.Ipc.get("notizie.fontiSpente", []));
    }

    Component.onCompleted: chiedi()
    onAttiveChanged: chiedi()

    Connections {
        target: Core.Ipc
        function onNotizieRicevute(r) {
            notizie.chiedendo = false;
            notizie.articoli = r.articoli || [];
            notizie.errore = r.error || "";
        }
    }

    // ── La testata del flusso ──
    Item {
        width: parent.width
        height: 36

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Style.label("Notizie", "News")
            color: Style.text
            font.family: Style.font
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Button {
                objectName: "windowsNewsRefresh"
                icon: "restart"
                tooltip: Style.label("Aggiorna", "Refresh")
                onClicked: notizie.chiedi()
            }
            Button {
                objectName: "windowsNewsCustomise"
                text: Style.label("Personalizza interessi", "Personalise interests")
                onClicked: notizie.personalizza()
            }
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: notizie.chiedendo && notizie.articoli.length === 0
              ? Style.label("Carico le notizie…", "Loading news…")
              : notizie.errore !== "" ? notizie.errore
              : notizie.articoli.length === 0 && !notizie.chiedendo
                ? Style.label("Nessuna notizia per gli interessi scelti.", "No news for the chosen interests.")
                : ""
        color: Style.muted
        font.family: Style.font
        font.pixelSize: 13
    }

    // ── Le schede ──
    Grid {
        id: griglia
        width: parent.width
        columns: width >= 780 ? 3 : (width >= 500 ? 2 : 1)
        spacing: 16

        Repeater {
            model: notizie.articoli

            delegate: Rectangle {
                id: scheda
                required property var modelData
                required property int index
                objectName: "windowsNewsCard-" + index
                width: (griglia.width - (griglia.columns - 1) * griglia.spacing) / griglia.columns
                height: 236
                radius: 8
                clip: true
                // La scheda di Windows: trasparente sopra il vetro, e al passaggio il
                // velo leggero dei controlli (SubtleFillColorSecondary).
                color: presa.containsMouse ? Qt.tint(Style.card, Style.hover) : Style.card
                border.color: scheda.activeFocus ? Style.accentIndicator : Style.cardStroke
                border.width: scheda.activeFocus ? 2 : 1
                activeFocusOnTab: true
                Accessible.role: Accessible.Link
                Accessible.name: scheda.modelData.titolo
                Keys.onReturnPressed: Qt.openUrlExternally(scheda.modelData.link)
                Keys.onSpacePressed: Qt.openUrlExternally(scheda.modelData.link)

                // L'immagine, o al suo posto una fascia col colore della
                // testata (sempre lo stesso per la stessa testata).
                Rectangle {
                    id: fascia
                    width: parent.width
                    height: 126
                    color: {
                        var h = 0;
                        var s = String(scheda.modelData.fonte);
                        for (var i = 0; i < s.length; i++)
                            h = (h * 31 + s.charCodeAt(i)) % 360;
                        return Qt.hsla(h / 360, 0.35, Style.dark ? 0.32 : 0.78, 1);
                    }
                    Image {
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: scheda.modelData.immagine ? "file://" + scheda.modelData.immagine : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 520
                        asynchronous: true
                    }
                }

                Column {
                    anchors.top: fascia.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 6

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: scheda.modelData.fonte
                        color: Style.muted
                        font.family: Style.font
                        font.pixelSize: 11
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        // Lo scrive la testata: testo semplice, mai HTML.
                        textFormat: Text.PlainText
                        text: scheda.modelData.titolo
                        color: Style.text
                        font.family: Style.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: presa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Si apre nel browser predefinito: la notizia la legge il
                    // browser, non noi.
                    onClicked: Qt.openUrlExternally(scheda.modelData.link)
                }
            }
        }
    }
}
