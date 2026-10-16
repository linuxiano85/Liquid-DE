import QtQuick
import QtQuick.Window
import Quickshell
import Minerva.WindowIdentity 1.0 as Native
import "../../core" as Core
import "../../files" as Files
import "../../ui" as Ui
import "../../windows11" as W

// Riferimento: dialogo Apri osservato nella VM il 13 ottobre 2026, 946×534.
// Finestra separata e modale, elenco virtualizzato e immagini decodificate
// solo a dimensione di miniatura. Il servizio file rimane quello del desktop.
Window {
    id: dialogo
    objectName: "selettoreFileWindows"
    property var proprietario: null
    property bool soloCartelle: false
    // Existing wallpaper callers keep image validation. Other applications
    // can select documents or choose a destination without decoding it.
    property string purpose: "image"
    property string initialName: ""
    property var allowedExtensions: []
    property string cartella: ""
    property var voci: []
    property var posti: []
    property var storia: []
    property int posizione: -1
    property string errore: ""
    property bool caricando: false
    property bool attesaImmagini: false
    property string ultimaCartella: ""
    property string richiesta: ""
    property string nomeDaTrovare: ""
    property bool confermaDopoLettura: false
    property string daValidare: ""
    property int sequenza: 0
    property string ordinamento: "name"
    property bool dettagli: false
    property bool anteprima: false
    readonly property string canale: "scelta-windows-" + Date.now() + "-" + Math.random() + "-"
    readonly property string casa: Quickshell.env("HOME") || "/"
    readonly property color fondo: W.Style.dark ? "#202020" : "#FFFFFF"
    readonly property color fascia: W.Style.dark ? "#2B2B2B" : "#F0F0F0"
    readonly property color contorno: W.Style.dark ? "#686868" : "#A8A8A8"
    readonly property var mostrate: {
        var sceltaFiltro = filtro.valore;
        var testoRicerca = ricerca.text.toLowerCase();
        return voci.filter(function(v) {
        if (dialogo.soloCartelle && !v.isDir)
            return false;
        if (!v.isDir && dialogo.allowedExtensions.length && !dialogo.allowedExtensions.some(function(ext){return v.name.toLowerCase().endsWith(ext.toLowerCase());}))
            return false;
        if (sceltaFiltro === "images" && !v.isDir && !dialogo.immagine(v.name))
            return false;
        return v.name.toLowerCase().indexOf(testoRicerca) >= 0;
    }).sort(function(a, b) {
        if (a.isDir !== b.isDir)
            return a.isDir ? -1 : 1;
        return dialogo.ordinamento === "date" ? b.modified - a.modified : a.name.localeCompare(b.name);
        });
    }
    property string cartellaDaCreare: ""
    signal scelto(string percorso)
    signal annullato()

    title: purpose === "save" ? W.Style.label("Salva con nome", "Save As") : W.Style.label("Apri", "Open")
    width: 946
    height: 534
    minimumWidth: 640
    minimumHeight: 420
    visible: false
    color: fondo
    flags: Qt.Dialog | Qt.FramelessWindowHint
    modality: Qt.WindowModal
    transientParent: proprietario
    onClosing: function(event) {
        event.accepted = false;
        annulla();
    }
    onVisibleChanged: if (!visible) pulisci()
    Component.onDestruction: if (richiesta !== "") Core.Ipc.fsSmettiDiGuardare(richiesta)

    function url(percorso) {
        return "file://" + percorso.split("/").map(encodeURIComponent).join("/");
    }
    function immagine(nome) {
        return /\.(png|jpe?g|webp|bmp|gif|avif|jxl|svg|tiff?)$/i.test(nome);
    }
    function normalizza(percorso) {
        var parti = [];
        for (var pezzo of percorso.split("/")) {
            if (pezzo === "..")
                parti.pop();
            else if (pezzo !== "" && pezzo !== ".")
                parti.push(pezzo);
        }
        return "/" + parti.join("/");
    }
    function apri(inizio) {
        errore = "";
        nome.text = purpose === "save" ? initialName : "";
        ricerca.text = "";
        filtro.valore = "all";
        storia = [];
        posizione = -1;
        visible = true;
        var partenza = inizio || ultimaCartella || casa;
        vai(partenza);
        attesaImmagini = purpose === "image" && !inizio && ultimaCartella === "";
        Core.Ipc.fsPlaces();
        nome.forceActiveFocus(Qt.TabFocusReason);
        requestActivate();
    }
    function pulisci() {
        if (richiesta !== "")
            Core.Ipc.fsSmettiDiGuardare(richiesta);
        richiesta = "";
        daValidare = "";
        nomeDaTrovare = "";
        confermaDopoLettura = false;
        cartellaDaCreare = "";
        nuova.visible = false;
        voci = [];
        caricando = false;
        attesaImmagini = false;
    }
    function annulla() {
        visible = false;
        annullato();
    }
    function termina(percorso) {
        visible = false;
        scelto(percorso);
    }
    function vai(percorso, storico) {
        attesaImmagini = false;
        if (richiesta !== "")
            Core.Ipc.fsSmettiDiGuardare(richiesta);
        nomeDaTrovare = "";
        confermaDopoLettura = false;
        daValidare = "";
        cartella = normalizza(percorso);
        if (storico !== false) {
            storia = storia.slice(0, posizione + 1).concat([cartella]);
            posizione = storia.length - 1;
        }
        if (purpose !== "save") nome.text = "";
        ricerca.text = "";
        errore = "";
        voci = [];
        elenco.currentIndex = -1;
        caricando = true;
        richiesta = canale + (++sequenza);
        Core.Ipc.fsList(cartella, false, richiesta, false);
    }
    function spostaStoria(delta) {
        var p = posizione + delta;
        if (p >= 0 && p < storia.length) {
            posizione = p;
            vai(storia[p], false);
        }
    }
    function su() {
        vai(normalizza(cartella + "/.."));
    }
    function seleziona(v) {
        daValidare = "";
        if (purpose === "save" && v.isDir) return;
        nome.text = v.name;
    }
    function attiva(v) {
        if (v.isDir)
            vai(v.path);
        else {
            seleziona(v);
            conferma();
        }
    }
    function creaCartella() {
        var n = nuovaNome.text.trim();
        if (n === "" || n === "." || n === ".." || n.indexOf("/") >= 0 || n.indexOf("\\") >= 0) {
            errore = W.Style.label("Nome della cartella non valido.", "Invalid folder name.");
            return;
        }
        cartellaDaCreare = normalizza(cartella + "/" + n);
        // Esclusività del nome verificata dal servizio: una voce esistente
        // non va mai sostituita per completare una scelta dello sfondo.
        if (voci.some(function(v) { return v.path === cartellaDaCreare; })) {
            cartellaDaCreare = "";
            errore = W.Style.label("Esiste già un elemento con questo nome.", "An item with this name already exists.");
            return;
        }
        Core.Ipc.fsMakeDirectory(cartellaDaCreare);
    }
    function conferma() {
        errore = "";
        if (caricando || daValidare !== "")
            return;
        if (soloCartelle && nome.text === "") {
            termina(cartella);
            return;
        }
        var testo = nome.text;
        if (testo === "")
            return;
        var percorso = normalizza(testo.startsWith("/") ? testo : cartella + "/" + testo);
        var voce = voci.find(function(v) { return v.path === percorso; });
        if (purpose === "save" && !soloCartelle && !(voce && voce.isDir)) {
            var divisione = percorso.lastIndexOf("/");
            var directory = divisione <= 0 ? "/" : percorso.substring(0, divisione);
            if (directory === cartella) {
                termina(percorso.toLowerCase().endsWith(".pdf") ? percorso : percorso + ".pdf");
                return;
            }
        }
        if (voce) {
            if (voce.isDir) {
                if (soloCartelle)
                    termina(voce.path);
                else
                    vai(voce.path);
            } else if (!soloCartelle) {
                // Anche un nome digitato deve esistere nell'elenco ricevuto;
                // la decodifica conferma che sia davvero un'immagine leggibile.
                if (purpose === "image") daValidare = voce.path;
                else termina(voce.path);
            }
            return;
        }
        var taglio = percorso.lastIndexOf("/");
        var padre = taglio <= 0 ? "/" : percorso.substring(0, taglio);
        if (padre !== cartella) {
            vai(padre);
            nomeDaTrovare = percorso.substring(taglio + 1);
            confermaDopoLettura = true;
        } else {
            errore = W.Style.label("File o cartella non trovato.", "File or folder not found.");
        }
    }
    Connections {
        target: Core.Ipc
        function onFileResultReceived(payload) {
            if (!dialogo.visible || dialogo.cartellaDaCreare === "")
                return;
            if (payload.ok && (payload.creati || []).indexOf(dialogo.cartellaDaCreare) >= 0) {
                var target = dialogo.cartellaDaCreare;
                dialogo.cartellaDaCreare = "";
                nuova.visible = false;
                dialogo.vai(target);
            } else if (payload.ok === false) {
                dialogo.cartellaDaCreare = "";
                dialogo.errore = payload.error || "";
            }
        }
        function onPlacesReceived(payload) {
            if (!dialogo.visible)
                return;
            var luoghi = payload.places || [];
            dialogo.posti = [{kind: "home", path: dialogo.casa, name: "Home"}].concat(luoghi.filter(function(p) {
                return p.nellaBarra && p.kind !== "trash";
            })).concat([{kind: "root", path: "/", name: W.Style.label("Questo PC", "This PC")}]);
            if (dialogo.attesaImmagini) {
                var foto = luoghi.find(function(p) { return p.kind === "pictures"; });
                dialogo.attesaImmagini = false;
                if (foto)
                    dialogo.vai(foto.path);
            }
        }
        function onFileListingReceived(payload) {
            if (!payload || !String(payload.pane).startsWith(dialogo.canale))
                return;
            // fs_list registra un osservatore: lo rilasciamo anche per una
            // risposta vecchia o arrivata dopo Annulla. Il dialogo legge su richiesta.
            Core.Ipc.fsSmettiDiGuardare(payload.pane);
            if (!dialogo.visible || payload.pane !== dialogo.richiesta || payload.path !== dialogo.cartella)
                return;
            dialogo.errore = payload.error || "";
            dialogo.voci = (payload.entries || []).slice().sort(function(a, b) {
                return a.isDir !== b.isDir ? (a.isDir ? -1 : 1) : a.name.localeCompare(b.name);
            });
            if (dialogo.errore === "")
                dialogo.ultimaCartella = dialogo.cartella;
            elenco.currentIndex = -1;
            dialogo.caricando = false;
            if (dialogo.purpose !== "save") nome.text = "";
            if (dialogo.nomeDaTrovare !== "") {
                nome.text = dialogo.nomeDaTrovare;
                dialogo.nomeDaTrovare = "";
                if (dialogo.confermaDopoLettura) {
                    dialogo.confermaDopoLettura = false;
                    dialogo.conferma();
                }
            }
        }
    }
    Image {
        visible: false
        source: dialogo.daValidare !== "" ? dialogo.url(dialogo.daValidare) : ""
        sourceSize: Qt.size(256, 256)
        asynchronous: true
        onStatusChanged: {
            if (dialogo.daValidare === "")
                return;
            if (status === Image.Ready)
                dialogo.termina(dialogo.daValidare);
            else if (status === Image.Error) {
                dialogo.daValidare = "";
                dialogo.errore = W.Style.label("Impossibile aprire questa immagine.", "This image cannot be opened.");
            }
        }
    }

    Shortcut {
        sequence: "Alt+Left"
        enabled: dialogo.visible && !nuova.visible
        context: Qt.WindowShortcut
        onActivated: dialogo.spostaStoria(-1)
    }
    Shortcut {
        sequence: "Alt+Right"
        enabled: dialogo.visible && !nuova.visible
        context: Qt.WindowShortcut
        onActivated: dialogo.spostaStoria(1)
    }
    Shortcut {
        sequence: "Alt+Up"
        enabled: dialogo.visible && !nuova.visible
        context: Qt.WindowShortcut
        onActivated: dialogo.su()
    }
    Shortcut {
        sequence: "F5"
        enabled: dialogo.visible && !nuova.visible
        context: Qt.WindowShortcut
        onActivated: dialogo.vai(cartella, false)
    }
    Shortcut {
        sequence: "Ctrl+L"
        enabled: dialogo.visible && !nuova.visible
        context: Qt.WindowShortcut
        onActivated: { indirizzo.forceActiveFocus(Qt.ShortcutFocusReason); indirizzo.selectAll(); }
    }

    Native.WindowIdentity {
        id: identita
        item: contenuto
    }
    function recuperaDialogo(aggiorna) {
        if (!visible || modality !== Qt.WindowModal || !proprietario || !proprietario.active)
            return;
        if (!Core.Compositore.nostro) {
            requestActivate();
            return;
        }
        var finestra = Core.Compositore.nativeWindowList.find(function(w) {
            return w.pid === Quickshell.processId && w.surfaceId === identita.surfaceId;
        });
        if (finestra && identita.surfaceId !== 0)
            Core.Compositore._nostro("fuoco", ["address:" + finestra.id]);
        else if (aggiorna)
            Core.Compositore.chiedi("finestre");
    }
    Connections {
        target: Core.Compositore
        function onNativeWindows(windows) { dialogo.recuperaDialogo(false); }
    }
    // Il richiamo appartiene alla finestra: distruggendo la pagina si annulla
    // anche il timer, evitando callback su un selettore già eliminato.
    Timer {
        id: richiamoFocus
        interval: 0
        repeat: false
        onTriggered: dialogo.recuperaDialogo(true)
    }
    // Compatibilità con il compositore della sessione già aperta, precedente
    // a xdg-dialog-v1: il solo clic sulla madre richiama questa superficie,
    // identificata da PID e wl_surface, senza sottrarre focus ad altre app.
    Connections {
        target: dialogo.proprietario
        function onActiveChanged() {
            if (dialogo.visible && dialogo.proprietario.active)
                richiamoFocus.restart();
        }
    }

    component Campo: Rectangle {
        property alias text: ingresso.text
        property string nomeAccessibile: ""
        function selectAll() { ingresso.selectAll(); }
        signal invio()
        function forceActiveFocus(motivo) { ingresso.forceActiveFocus(motivo); }
        color: dialogo.fondo
        border.color: ingresso.activeFocus ? W.Style.accent : dialogo.contorno
        height: 24
        TextInput {
            id: ingresso
            anchors.fill: parent
            anchors.margins: 4
            verticalAlignment: TextInput.AlignVCenter
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 12
            selectByMouse: true
            clip: true
            activeFocusOnTab: true
            Accessible.name: parent.nomeAccessibile
            Keys.onReturnPressed: parent.invio()
        }
    }
    component Comando: Rectangle {
        property string testo: ""
        property string icona: ""
        property string suggerimento: ""
        signal premuto()
        width: testo !== "" ? Math.max(86, scritta.implicitWidth + 24) : 32
        height: 24
        radius: 3
        color: presa.containsMouse ? W.Style.hover : dialogo.fondo
        border.color: activeFocus ? W.Style.accent : dialogo.contorno
        border.width: testo !== "" || activeFocus ? 1 : 0
        activeFocusOnTab: enabled
        opacity: enabled ? 1 : 0.4
        Accessible.role: Accessible.Button
        Accessible.name: testo || suggerimento
        Keys.onReturnPressed: if (enabled) premuto()
        Keys.onSpacePressed: if (enabled) premuto()
        Text {
            id: scritta
            anchors.centerIn: parent
            text: parent.testo
            textFormat: Text.PlainText
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 12
        }
        W.Glyph {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: parent.icona
            visible: parent.icona !== ""
            color: W.Style.muted
        }
        MouseArea {
            id: presa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.premuto()
        }
    }
    Item {
        id: contenuto
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { if (nuova.visible) nuova.visible = false; else dialogo.annulla(); }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_L && event.modifiers & Qt.ControlModifier) {
                indirizzo.forceActiveFocus(Qt.ShortcutFocusReason);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up && event.modifiers & Qt.AltModifier) {
                dialogo.su();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left && event.modifiers & Qt.AltModifier) {
                dialogo.spostaStoria(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right && event.modifiers & Qt.AltModifier) {
                dialogo.spostaStoria(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_F5) {
                dialogo.vai(dialogo.cartella, false);
                event.accepted = true;
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: dialogo.contorno
        }
        Rectangle {
            id: titolo
            width: parent.width
            height: 32
            color: W.Style.dark ? dialogo.fascia : "#F3F3F3"
            Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: dialogo.title
                textFormat: Text.PlainText
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 12
            }
            DragHandler {
                target: null
                onActiveChanged: if (active) dialogo.startSystemMove()
            }
            Comando {
                objectName: "fileWindowsChiudi"
                suggerimento: W.Style.label("Chiudi", "Close")
                anchors.right: parent.right
                height: 30
                icona: "close"
                onPremuto: dialogo.annulla()
            }
        }
        Row {
            id: navigazione
            x: 8
            y: 41
            spacing: 3
            Comando { suggerimento: W.Style.label("Indietro", "Back"); icona: "back"; enabled: dialogo.posizione > 0; onPremuto: dialogo.spostaStoria(-1) }
            Comando { suggerimento: W.Style.label("Avanti", "Forward"); icona: "chevronRight"; enabled: dialogo.posizione + 1 < dialogo.storia.length; onPremuto: dialogo.spostaStoria(1) }
            Comando { suggerimento: W.Style.label("Sali di un livello", "Up one level"); icona: "chevronUp"; enabled: dialogo.cartella !== "/"; onPremuto: dialogo.su() }
        }
        Campo {
            id: indirizzo
            objectName: "fileWindowsPercorso"
            nomeAccessibile: W.Style.label("Percorso", "Location")
            x: 137
            y: 41
            width: dialogo.width - 365
            height: 34
            text: dialogo.cartella
            onInvio: dialogo.vai(text)
        }
        Campo {
            id: ricerca
            objectName: "fileWindowsRicerca"
            nomeAccessibile: W.Style.label("Cerca nella cartella", "Search folder")
            x: dialogo.width - 214
            y: 41
            width: 202
            height: 34
            Text {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: ricerca.text === ""
                text: W.Style.label("Cerca nella cartella", "Search folder")
                color: W.Style.muted
                font.family: W.Style.font
                font.pixelSize: 12
            }
        }
        Rectangle {
            x: 1
            y: 86
            width: parent.width - 2
            height: 31
            color: W.Style.dark ? dialogo.fascia : "#F5F6F7"
            TendinaWindows {
                objectName: "fileWindowsOrganizza"
                x: 12
                y: 3
                width: 110
                height: 24
                classica: true
                valore: "organize"
                voci: [
                    {valore: "organize", testo: W.Style.label("Organizza", "Organize"), disponibile: false},
                    {valore: "name", testo: W.Style.label("Ordina per nome", "Sort by name")},
                    {valore: "date", testo: W.Style.label("Ordina per data", "Sort by date")}
                ]
                onScelto: function(v) { dialogo.ordinamento = v; }
            }
            Comando {
                objectName: "fileWindowsNuovaCartella"
                x: 130
                y: 3
                testo: W.Style.label("Nuova cartella", "New folder")
                onPremuto: {
                    nuova.visible = true;
                    nuovaNome.text = W.Style.label("Nuova cartella", "New folder");
                    nuovaNome.forceActiveFocus(Qt.TabFocusReason);
                    nuovaNome.selectAll();
                }
            }
            Comando {
                objectName: "fileWindowsVista"
                suggerimento: W.Style.label("Cambia visualizzazione", "Change view")
                anchors.right: previewToggle.left
                anchors.rightMargin: 12
                y: 3
                icona: "grid"
                onPremuto: dialogo.dettagli = !dialogo.dettagli
            }
            Comando {
                id: previewToggle
                objectName: "fileWindowsAnteprima"
                suggerimento: W.Style.label("Riquadro anteprima", "Preview pane")
                anchors.right: parent.right
                anchors.rightMargin: 10
                y: 3
                icona: "window"
                onPremuto: dialogo.anteprima = !dialogo.anteprima
            }
        }
        ListView {
            id: luoghi
            x: 8
            y: 117
            width: 150
            height: dialogo.height - 199
            model: dialogo.visible ? dialogo.posti : []
            clip: true
            delegate: Rectangle {
                required property var modelData
                width: luoghi.width - 12
                height: 32
                color: dialogo.cartella === modelData.path ? W.Style.hover : "transparent"
                Files.FileIcon {
                    x: 28
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    name: ({home: "cartella-casa", desktop: "cartella-scrivania", downloads: "cartella-scaricati", documents: "cartella-documenti", pictures: "cartella-immagini", music: "cartella-musica", videos: "cartella-video", root: "disco"})[modelData.kind] || "folder"
                }
                Text {
                    x: 52
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56
                    text: ({home: "Home", desktop: "Desktop", downloads: W.Style.label("Download", "Downloads"), documents: W.Style.label("Documenti", "Documents"), pictures: W.Style.label("Immagini", "Pictures"), music: W.Style.label("Musica", "Music"), videos: W.Style.label("Video", "Videos"), root: W.Style.label("Questo PC", "This PC")})[modelData.kind] || modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: W.Style.text
                    font.family: W.Style.font
                    font.pixelSize: 12
                }
                MouseArea { anchors.fill: parent; onClicked: dialogo.vai(parent.modelData.path) }
            }
        }
        Ui.Scorrimento { bersaglio: luoghi; anchors.right: luoghi.right; anchors.top: luoghi.top; anchors.bottom: luoghi.bottom }
        GridView {
            id: elenco
            objectName: "fileWindowsElenco"
            x: 160
            y: 118
            width: dialogo.width - 172 - (dialogo.anteprima ? 200 : 0)
            height: dialogo.height - 200
            cellWidth: dialogo.dettagli ? width : 116
            cellHeight: dialogo.dettagli ? 32 : 110
            clip: true
            model: dialogo.visible ? dialogo.mostrate : []
            activeFocusOnTab: true
            onModelChanged: {
                currentIndex = -1;
                if (dialogo.purpose !== "save" && !dialogo.caricando && dialogo.nomeDaTrovare === "")
                    nome.text = "";
            }
            onCurrentIndexChanged: {
                if (!dialogo.caricando && currentIndex >= 0 && currentIndex < count) {
                    dialogo.seleziona(dialogo.mostrate[currentIndex]);
                    positionViewAtIndex(currentIndex, GridView.Contain);
                }
            }
            Keys.onReturnPressed: if (currentIndex >= 0) dialogo.attiva(dialogo.mostrate[currentIndex])
            delegate: Rectangle {
                id: voce
                required property var modelData
                required property int index
                objectName: "fileWindowsVoce-" + index
                width: elenco.cellWidth - 8
                height: elenco.cellHeight - 6
                radius: 2
                color: elenco.currentIndex === index ? W.Style.hover : "transparent"
                border.width: elenco.activeFocus && elenco.currentIndex === index ? 1 : 0
                border.color: W.Style.accent
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData.name
                Image {
                    id: miniatura
                    x: 12
                    y: 6
                    width: dialogo.dettagli ? 22 : 84
                    height: dialogo.dettagli ? 22 : 66
                    source: !voce.modelData.isDir && dialogo.immagine(voce.modelData.name) ? dialogo.url(voce.modelData.path) : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Files.FileIcon {
                    anchors.fill: miniatura
                    visible: miniatura.status !== Image.Ready
                    name: voce.modelData.isDir ? "folder" : "document"
                }
                Text {
                    x: dialogo.dettagli ? 42 : 3
                    y: dialogo.dettagli ? 8 : 76
                    width: parent.width - x - 3
                    text: voce.modelData.name
                    textFormat: Text.PlainText
                    horizontalAlignment: dialogo.dettagli ? Text.AlignLeft : Text.AlignHCenter
                    elide: Text.ElideRight
                    color: W.Style.text
                    font.family: W.Style.font
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        elenco.currentIndex = voce.index;
                        elenco.forceActiveFocus(Qt.MouseFocusReason);
                    }
                    onDoubleClicked: dialogo.attiva(voce.modelData)
                }
            }
        }
        Ui.Scorrimento { bersaglio: elenco; anchors.right: elenco.right; anchors.top: elenco.top; anchors.bottom: elenco.bottom }
        Image {
            x: elenco.x + elenco.width + 8
            y: elenco.y + 12
            width: 180
            height: elenco.height - 24
            visible: dialogo.anteprima
            source: dialogo.anteprima && elenco.currentIndex >= 0 && elenco.currentIndex < dialogo.mostrate.length && !dialogo.mostrate[elenco.currentIndex].isDir
                && dialogo.immagine(dialogo.mostrate[elenco.currentIndex].name) ? dialogo.url(dialogo.mostrate[elenco.currentIndex].path) : ""
            sourceSize: Qt.size(360, 360)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        Text {
            x: 168
            y: 134
            width: dialogo.width - 180
            visible: dialogo.caricando || dialogo.errore !== "" || elenco.count === 0
            text: dialogo.errore || (dialogo.caricando ? W.Style.label("Caricamento…", "Loading…") : W.Style.label("Nessun elemento corrisponde ai criteri di ricerca.", "No items match your search."))
            color: dialogo.errore !== "" ? "#C42B1C" : W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
        Rectangle {
            id: nuova
            visible: false
            z: 20
            anchors.centerIn: parent
            width: 380
            height: 110
            color: dialogo.fascia
            border.color: dialogo.contorno
            Campo {
                id: nuovaNome
                objectName: "fileWindowsNomeCartella"
                nomeAccessibile: W.Style.label("Nome della cartella", "Folder name")
                x: 16
                y: 20
                width: parent.width - 32
                onInvio: dialogo.creaCartella()
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 16
                y: 64
                spacing: 12
                Comando { testo: W.Style.label("Crea", "Create"); onPremuto: dialogo.creaCartella() }
                Comando { testo: W.Style.label("Annulla", "Cancel"); onPremuto: nuova.visible = false }
            }
        }
        Rectangle {
            id: piede
            anchors.bottom: parent.bottom
            width: parent.width
            height: 82
            color: dialogo.fascia
            Text {
                x: 129
                y: 12
                text: dialogo.soloCartelle ? W.Style.label("Cartella:", "Folder:") : W.Style.label("Nome file:", "File name:")
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 12
            }
            Campo {
                id: nome
                objectName: "fileWindowsNome"
                nomeAccessibile: W.Style.label("Nome file", "File name")
                x: 190
                y: 9
                width: parent.width - 447
                onInvio: dialogo.conferma()
            }
            TendinaWindows {
                id: filtro
                objectName: "fileWindowsFiltro"
                x: parent.width - 245
                y: 9
                width: 227
                height: 24
                visible: !dialogo.soloCartelle
                classica: true
                valore: "all"
                voci: [{valore: "all", testo: W.Style.label("Tutti i file", "All files")}, {valore: "images", testo: W.Style.label("Immagini", "Images")}]
                onScelto: function(v) { filtro.valore = v; }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 18
                y: 39
                spacing: 14
                Comando {
                    objectName: "fileWindowsConferma"
                    testo: dialogo.soloCartelle ? W.Style.label("Seleziona cartella", "Select folder") : dialogo.purpose === "save" ? W.Style.label("Salva", "Save") : dialogo.purpose === "file" ? W.Style.label("Apri", "Open") : W.Style.label("Scegli immagine", "Choose picture")
                    enabled: !dialogo.caricando && dialogo.daValidare === "" && (dialogo.soloCartelle || nome.text !== "")
                    onPremuto: dialogo.conferma()
                }
                Comando {
                    objectName: "fileWindowsAnnulla"
                    testo: W.Style.label("Annulla", "Cancel")
                    onPremuto: dialogo.annulla()
                }
            }
        }
    }
}
