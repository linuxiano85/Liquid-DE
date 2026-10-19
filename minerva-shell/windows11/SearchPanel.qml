import QtQuick
import Quickshell
import "../core" as Core
import "../ui" as Ui

// Cerca, come l'ultima Windows 11 (aggiornamento di settembre 2026,
// KB5120998 → Patch Tuesday dell'8 settembre: «Refined Windows Search»).
//
// Il manutentore, 11 ottobre 2026: «quando la premo si vede una lampadina e un
// ingranaggio in basso e sono per metà fuori dalla scheda cerca e non sono
// cliccabili, e si deve vedere se è coerente con Windows». Non lo era più:
// Windows ha tolto dalla pagina iniziale le app principali e le ricerche
// rapide (Windows Latest, 14 luglio e 31 agosto 2026). Adesso:
//
//   - a campo vuoto, SOLO le ricerche recenti;
//   - un ingranaggio in alto a destra per le impostazioni della ricerca;
//   - i risultati con l'etichetta della fonte (App, File, Cartella) e la
//     «Migliore corrispondenza» in cima;
//   - a destra l'anteprima del risultato scelto: percorso, «Apri» e
//     «Copia percorso» per un file; per un'app «Apri», «Aggiungi a Start» e
//     «Aggiungi alla barra delle applicazioni».
//
// Le ricerche recenti restano su questo computer (`windows11.ricercheRecenti`)
// e si spengono o si cancellano da Preset › Windows 11 › Ricerca, come
// «Cronologia delle ricerche su questo dispositivo» di Windows.
FocusScope {
    id: cerca

    objectName: "windowsSearchPanel"

    signal closeRequested()
    signal actionRequested(string action)

    // ── Gli stessi nomi del vecchio pannello, che le prove leggono ───────
    property string searchCategory: "all"
    property int selectedIndex: 0
    property var files: []
    property var recent: []
    property string searchId: ""

    readonly property string query: field.text.trim()
    readonly property string queryBassa: cerca.query.toLowerCase()
    readonly property bool searchLanding: cerca.query === ""

    readonly property bool conCronologia: Core.Ipc.get("windows11.cronologiaRicerche", true) !== false
    readonly property var ricerche: cerca.conCronologia ? Core.Ipc.get("windows11.ricercheRecenti", []) : []

    readonly property var catalog: Core.Apps.all.slice().sort(function(a, b) {
        return a.name.localeCompare(b.name);
    })
    readonly property var apps: {
        if (cerca.query === "" || cerca.searchCategory === "documents")
            return [];
        var q = cerca.queryBassa;
        return cerca.catalog.filter(function(a) {
            return (a.name + " " + (a.genericName || "") + " " + a.appId).toLowerCase().indexOf(q) >= 0;
        }).slice(0, 8);
    }

    /// Tutti i risultati in fila, per la tastiera e per la «migliore
    /// corrispondenza»: prima le app, poi i file.
    readonly property var risultati: {
        var r = cerca.apps.map(function(a) { return { "tipo": "app", "app": a }; });
        if (cerca.searchCategory !== "apps") {
            cerca.files.slice(0, 8).forEach(function(f) {
                r.push({ "tipo": f.isDir ? "cartella" : "file", "file": f });
            });
        }
        return r;
    }
    readonly property var scelto: cerca.risultati[cerca.selectedIndex] || null

    function etichetta(r) {
        if (r.tipo === "app")
            return Style.label("App", "App");
        var dove = r.file.dove || "";
        return (r.tipo === "cartella" ? Style.label("Cartella", "Folder") : Style.label("File", "File"))
            + (dove !== "" ? " · " + dove : "");
    }

    function ricorda() {
        if (!cerca.conCronologia || cerca.query === "")
            return;
        var lista = Core.Ipc.get("windows11.ricercheRecenti", []).filter(function(q) {
            return q.toLowerCase() !== cerca.queryBassa;
        });
        lista.unshift(cerca.query.slice(0, 120));
        Core.Ipc.setSetting("windows11.ricercheRecenti", lista.slice(0, 8));
    }

    function dimentica(q) {
        Core.Ipc.setSetting("windows11.ricercheRecenti",
            Core.Ipc.get("windows11.ricercheRecenti", []).filter(function(x) { return x !== q; }));
    }

    function apri(r) {
        if (!r)
            return;
        cerca.ricorda();
        if (r.tipo === "app")
            Core.Ipc.launchApp(r.app.exec, r.app.appId, "new-window");
        else
            Core.Ipc.apriOChiedi(r.file.path);
        cerca.closeRequested();
    }

    function activateSelection() {
        if (!cerca.searchLanding)
            cerca.apri(cerca.scelto);
    }

    function move(delta) {
        cerca.selectedIndex = Math.max(0, Math.min(cerca.risultati.length - 1, cerca.selectedIndex + delta));
        elenco.positionViewAtIndex(cerca.selectedIndex, ListView.Contain);
    }

    function begin(text) {
        field.text = text || "";
        field.forceActiveFocus();
    }

    /// Fissa o toglie un'app da Start (`launcher.fixedApps`) o dalla barra
    /// (`dock.pinned`), come il menu dello Start.
    function fissa(app, chiave) {
        var lista = Core.Ipc.get(chiave, []).slice();
        var i = lista.indexOf(app.appId);
        if (i < 0)
            lista.push(app.appId);
        else
            lista.splice(i, 1);
        Core.Ipc.setSetting(chiave, lista);
    }

    Component.onCompleted: {
        Core.Apps.aggiorna();
        field.forceActiveFocus();
    }
    Component.onDestruction: {
        if (cerca.searchId !== "")
            Core.Ipc.fsSearchCancel(cerca.searchId);
    }
    onQueryChanged: cerca._riparti()
    onSearchCategoryChanged: cerca._riparti()
    function _riparti() {
        cerca.selectedIndex = 0;
        cerca.files = [];
        if (cerca.searchId !== "")
            Core.Ipc.fsSearchCancel(cerca.searchId);
        cerca.searchId = "";
        ritardo.restart();
    }
    Keys.onEscapePressed: function(event) {
        cerca.closeRequested();
        event.accepted = true;
    }

    Timer {
        id: ritardo
        interval: 250
        onTriggered: {
            if (cerca.query.length >= 2 && cerca.searchCategory !== "apps") {
                cerca.searchId = "windows-search-" + Date.now() + "-" + Math.random();
                Core.Ipc.fsSearch(cerca.searchId, Quickshell.env("HOME"), cerca.query, false);
            }
        }
    }

    Connections {
        target: Core.Ipc
        function onRicercaAvanza(data) {
            if (data && cerca.searchId !== "" && data.id === cerca.searchId)
                cerca.files = cerca.files.concat(data.voci || []).slice(0, 20);
        }
    }

    // ── Il fondo ─────────────────────────────────────────────────────────
    Rectangle {
        z: -1
        anchors.fill: parent
        radius: 8
        color: Style.pannello
        border.color: Style.edge
    }

    // ── Il campo ─────────────────────────────────────────────────────────
    Rectangle {
        objectName: "windowsSearchField"
        x: 32
        y: 32
        width: parent.width - 64
        height: 34
        radius: 4
        color: Style.field
        border.color: Style.edge

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 2
            radius: 1
            color: Style.accentInk
        }

        Glyph {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            name: "search"
            color: Style.muted
            alwaysDrawn: true
        }

        TextInput {
            id: field
            objectName: "windowsSearchInput"
            x: 40
            y: 7
            width: parent.width - 52
            height: 24
            font.family: Style.font
            font.pixelSize: 14 * Style.textScale
            color: Style.text
            selectByMouse: true
            clip: true
            Accessible.name: Style.label("Digita qui per eseguire la ricerca", "Type here to search")
            Keys.onDownPressed: cerca.move(1)
            Keys.onUpPressed: cerca.move(-1)
            Keys.onReturnPressed: cerca.activateSelection()
            Keys.onEnterPressed: cerca.activateSelection()

            Text {
                anchors.fill: parent
                visible: field.text === ""
                text: Style.label("Digita qui per eseguire la ricerca", "Type here to search")
                font: field.font
                color: Style.muted
            }
        }
    }

    // ── I filtri e l'ingranaggio ─────────────────────────────────────────
    Row {
        x: 32
        y: 82
        spacing: 8

        Repeater {
            model: [
                { "id": "all", "label": Style.label("Tutti", "All") },
                { "id": "apps", "label": Style.label("App", "Apps") },
                { "id": "documents", "label": Style.label("Documenti", "Documents") }
            ]

            delegate: Button {
                required property var modelData
                objectName: "windowsSearchFilter-" + modelData.id
                text: modelData.label
                selected: cerca.searchCategory === modelData.id
                onClicked: {
                    cerca.searchCategory = modelData.id;
                    field.forceActiveFocus();
                }
            }
        }
    }

    Button {
        objectName: "windowsSearchSettings"
        x: parent.width - 32 - width
        y: 82
        width: 32
        height: 32
        icon: "settings"
        tooltip: Style.label("Impostazioni di ricerca", "Search settings")
        onClicked: cerca.actionRequested("preset")
    }

    // ── Campo vuoto: le ricerche recenti ─────────────────────────────────
    Item {
        id: casa
        x: 32
        y: 136
        width: parent.width - 64
        height: parent.height - y - 24
        visible: cerca.searchLanding

        Text {
            text: Style.label("Ricerche recenti", "Recent searches")
            color: Style.text
            font.family: Style.font
            font.pixelSize: 14 * Style.textScale
            font.weight: Font.DemiBold
        }

        Text {
            objectName: "windowsSearchHistoryEmpty"
            y: 40
            width: parent.width
            visible: cerca.ricerche.length === 0
            wrapMode: Text.Wrap
            text: cerca.conCronologia
                  ? Style.label("Le ricerche che fai compariranno qui.", "Your searches will appear here.")
                  : Style.label("La cronologia delle ricerche su questo dispositivo è disattivata.",
                                "Search history on this device is turned off.")
            color: Style.muted
            font.family: Style.font
            font.pixelSize: 13 * Style.textScale
        }

        ListView {
            id: storia
            y: 36
            width: parent.width
            height: parent.height - 36
            clip: true
            model: cerca.ricerche
            boundsBehavior: Flickable.StopAtBounds

            delegate: Button {
                id: riga
                required property string modelData
                required property int index
                objectName: "windowsSearchHistory-" + index
                width: storia.width
                height: 40
                onClicked: cerca.begin(riga.modelData)

                Glyph {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    name: "search"
                    color: Style.muted
                    alwaysDrawn: true
                }
                Text {
                    x: 40
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 88
                    text: riga.modelData
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 14 * Style.textScale
                }
                Button {
                    objectName: "windowsSearchHistoryRemove-" + riga.index
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    icon: "close"
                    visible: riga.hovered
                    tooltip: Style.label("Rimuovi dalla cronologia", "Remove from history")
                    onClicked: cerca.dimentica(riga.modelData)
                }
            }
        }

        Ui.Scorrimento {
            tinta: Style.muted
            bersaglio: storia
            anchors.right: storia.right
            anchors.top: storia.top
            anchors.bottom: storia.bottom
        }
    }

    // ── I risultati ──────────────────────────────────────────────────────
    Item {
        id: esiti
        x: 32
        y: 136
        width: parent.width - 64
        height: parent.height - y - 24
        visible: !cerca.searchLanding

        ListView {
            id: elenco
            objectName: "windowsSearchResults"
            width: Math.round(parent.width * 0.52)
            height: parent.height
            clip: true
            spacing: 2
            model: cerca.risultati
            currentIndex: cerca.selectedIndex
            boundsBehavior: Flickable.StopAtBounds

            // L'intestazione di ogni gruppo: «Migliore corrispondenza» sopra
            // il primo, poi «App» e «Documenti» dove cambia il tipo.
            delegate: Column {
                id: voce
                required property var modelData
                required property int index
                width: elenco.width
                readonly property bool primo: index === 0
                readonly property bool cambia: index > 0
                    && (cerca.risultati[index - 1].tipo === "app") !== (modelData.tipo === "app")
                readonly property bool inizioGruppo: index === 1 || voce.cambia

                Text {
                    visible: voce.primo || voce.inizioGruppo
                    height: visible ? 30 : 0
                    verticalAlignment: Text.AlignBottom
                    bottomPadding: 6
                    text: voce.primo ? Style.label("Migliore corrispondenza", "Best match")
                          : (voce.modelData.tipo === "app" ? Style.label("App", "Apps")
                                                          : Style.label("Documenti", "Documents"))
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 13 * Style.textScale
                    font.weight: Font.DemiBold
                }

                Button {
                    objectName: voce.modelData.tipo === "app" ? "windowsApp-" + voce.modelData.app.appId
                                                              : "windowsSearchFile-" + voce.modelData.file.name
                    width: elenco.width
                    height: voce.primo ? 64 : 44
                    selected: cerca.selectedIndex === voce.index
                    // Come Windows: il puntatore sopra un risultato ne mostra
                    // l'anteprima, il clic lo apre.
                    onHoveredChanged: if (hovered) cerca.selectedIndex = voce.index
                    onClicked: cerca.apri(voce.modelData)

                    AppIcon {
                        visible: voce.modelData.tipo === "app"
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: voce.primo ? 32 : 24
                        height: width
                        path: voce.modelData.tipo === "app" ? (voce.modelData.app.icon || "") : ""
                    }
                    Glyph {
                        visible: voce.modelData.tipo !== "app"
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: voce.primo ? 28 : 20
                        height: width
                        name: voce.modelData.tipo === "cartella" ? "folder" : "document"
                        color: Style.accentInk
                        alwaysDrawn: true
                    }
                    Column {
                        x: voce.primo ? 56 : 48
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 12
                        Text {
                            width: parent.width
                            text: voce.modelData.tipo === "app" ? voce.modelData.app.name : voce.modelData.file.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 14 * Style.textScale
                        }
                        Text {
                            objectName: "windowsSearchLabel-" + voce.index
                            width: parent.width
                            text: cerca.etichetta(voce.modelData)
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: Style.muted
                            font.family: Style.font
                            font.pixelSize: 12 * Style.textScale
                        }
                    }
                }
            }
        }

        Text {
            y: 40
            width: elenco.width
            visible: cerca.risultati.length === 0
            text: Style.label("Nessun risultato", "No results")
            horizontalAlignment: Text.AlignHCenter
            color: Style.muted
            font.family: Style.font
            font.pixelSize: 14
        }

        // ── L'anteprima del risultato scelto ─────────────────────────────
        Rectangle {
            id: anteprima
            objectName: "windowsSearchPreview"
            x: elenco.width + 16
            width: parent.width - x
            height: parent.height
            radius: 8
            color: Style.card
            border.color: Style.cardStroke
            visible: cerca.scelto !== null

            readonly property var r: cerca.scelto
            // Le espressioni qui sotto guardano `r.tipo` da sé: una proprietà
            // intermedia può aggiornarsi dopo `r` e leggere `.app` di un file.
            readonly property bool eApp: anteprima.r !== null && anteprima.r.tipo === "app"

            Column {
                x: 20
                y: 28
                width: parent.width - 40
                spacing: 10

                Item {
                    width: parent.width
                    height: 64
                    AppIcon {
                        visible: anteprima.eApp
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64
                        height: 64
                        path: anteprima.r !== null && anteprima.r.tipo === "app" ? (anteprima.r.app.icon || "") : ""
                    }
                    Glyph {
                        visible: anteprima.r !== null && !anteprima.eApp
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 56
                        height: 56
                        name: anteprima.r !== null && anteprima.r.tipo === "cartella" ? "folder" : "document"
                        color: Style.accentInk
                        alwaysDrawn: true
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    text: anteprima.r === null ? "" : (anteprima.r.tipo === "app" ? anteprima.r.app.name : anteprima.r.file.name)
                    textFormat: Text.PlainText
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 18 * Style.textScale
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    text: anteprima.r === null ? "" : cerca.etichetta(anteprima.r)
                    textFormat: Text.PlainText
                    color: Style.muted
                    font.family: Style.font
                    font.pixelSize: 12 * Style.textScale
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Style.divider
                }

                // Le azioni: un elenco come in Windows, icona e testo.
                Repeater {
                    model: anteprima.r === null ? [] : (anteprima.r.tipo === "app" ? [
                        { "id": "apri", "icon": "apps", "label": Style.label("Apri", "Open") },
                        { "id": "start", "icon": "plus",
                          "label": Core.Ipc.get("launcher.fixedApps", []).indexOf(anteprima.r.app.appId) >= 0
                                   ? Style.label("Rimuovi da Start", "Unpin from Start")
                                   : Style.label("Aggiungi a Start", "Pin to Start") },
                        { "id": "barra", "icon": "plus",
                          "label": Core.Ipc.get("dock.pinned", []).indexOf(anteprima.r.app.appId) >= 0
                                   ? Style.label("Rimuovi dalla barra delle applicazioni", "Unpin from taskbar")
                                   : Style.label("Aggiungi alla barra delle applicazioni", "Pin to taskbar") }
                    ] : [
                        { "id": "apri", "icon": "document", "label": Style.label("Apri", "Open") },
                        { "id": "copia", "icon": "edit", "label": Style.label("Copia percorso", "Copy path") }
                    ])

                    delegate: Button {
                        required property var modelData
                        objectName: "windowsSearchAction-" + modelData.id
                        width: anteprima.width - 40
                        height: 36
                        aSinistra: true
                        icon: modelData.icon
                        text: modelData.label
                        onClicked: {
                            var r = anteprima.r;
                            if (modelData.id === "apri")
                                cerca.apri(r);
                            else if (modelData.id === "copia")
                                Quickshell.clipboardText = r.file.path;
                            else if (modelData.id === "start")
                                cerca.fissa(r.app, "launcher.fixedApps");
                            else if (modelData.id === "barra")
                                cerca.fissa(r.app, "dock.pinned");
                        }
                    }
                }
            }
        }
    }
}
