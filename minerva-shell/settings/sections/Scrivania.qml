import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Scrivania — lo sfondo, le icone e i widget. Lo sfondo e le icone stavano in
// «Aspetto» fino al 28 settembre 2026, e la scheda «Scrivania» in «Minerva»:
// tre posti per la stessa cosa.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Scrivania" : "Desktop"
    subtitle: Core.Strings.lang === "it"
              ? "Lo sfondo, le icone e i widget"
              : "The wallpaper, the icons and the widgets"

    readonly property bool it: Core.Strings.lang === "it"
    // La finestrella per scegliere un'immagine. `parent: page` la tira fuori
    // dalla colonna che scorre: dichiarata lì dentro sarebbe un riquadro in
    // fila alto quanto la pagina. Stessa disposizione di `sections/Utente.qml`.
    S.SelettoreImmagine {
        id: sceltaSfondo
        parent: page
        onScelta: function (percorso) { Core.Wallpaper.scegli(percorso); }
    }
    // ── Sfondi ───────────────────────────────────────────────────────────

    readonly property string current: Core.Ipc.get("desktop.wallpaper", "")
    /// Cartella da cui si stanno pescando le immagini. Vuota = le solite.
    readonly property string folder: Core.Ipc.get("desktop.wallpaperFolder", "")
    property var images: []
    property var _pending: []
    property bool loading: false
    readonly property var _extensions: [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".jxl"]
    // ── Si guarda solo dove si sta guardando ─────────────────────────────
    //
    // `scan()` elenca centinaia di file e riempie il modello di una griglia
    // di anteprime. Serve alla sola modalità «immagine»: con gli sfondi di
    // Minerva o con la cartella che gira da sé quella griglia è invisibile,
    // e fino all'11 agosto 2026 veniva costruita e DECODIFICATA lo stesso.
    // Nella cartella di Giacomo (311 fotografie di telefono) erano
    // ventiquattro immagini decodificate a 420×260 che nessuno vedeva.
    //
    // La regola, che vale per tutto Qt: `visible: false` NASCONDE, NON
    // SOSPENDE. Un `Repeater` dentro un riquadro invisibile costruisce le sue
    // celle e carica le sue immagini come se fosse in primo piano.
    Component.onCompleted: if (page.mode === "image") scan()
    onFolderChanged: if (page.mode === "image") scan()
    function scan() {
        page.images = [];
        page.loading = true;
        if (page.folder !== "") {
            // Una cartella scelta a mano è LA cartella: non si mescola con le
            // altre, altrimenti non si capisce più da dove viene cosa.
            page._pending = [page.folder];
        } else {
            page._pending = [
                page.home + "/Immagini/Sfondi",
                page.home + "/Pictures/Wallpapers",
                "/usr/share/backgrounds",
                page.home + "/Immagini",
                page.home + "/Pictures"
            ];
        }
        _next();
    }
    function _next() {
        if (page._pending.length === 0) {
            page.loading = false;
            return;
        }
        Core.Ipc.fsList(page._pending.shift(), false, "wallpaper");
    }
    function isImage(name) {
        var lower = name.toLowerCase();
        for (var k = 0; k < page._extensions.length; k++) {
            var ext = page._extensions[k];
            if (lower.lastIndexOf(ext) === lower.length - ext.length)
                return true;
        }
        return false;
    }
    Connections {
        target: Core.Ipc
        function onFileListingReceived(listing) {
            if (listing.pane !== "wallpaper")
                return;
            var found = page.images.slice();
            var entries = listing.entries || [];
            for (var i = 0; i < entries.length; i++) {
                var e = entries[i];
                if (e.isDir || !page.isImage(e.name))
                    continue;
                if (found.indexOf(e.path) === -1)
                    found.push(e.path);
            }
            page.images = found;
            if (page.images.length < 120)
                page._next();
            else
                page.loading = false;
        }
    }
    /// Applicare è compito di `Core.Wallpaper`, che sa anche far girare una
    /// cartella da sola. Qui resta solo la scelta.
    function apply(path) {
        Core.Wallpaper.apply(path);
    }
    readonly property string mode: Core.Wallpaper.mode
    /// Quante anteprime si mostrano per volta.
    ///
    /// Ventiquattro, e un pulsante per averne altre ventiquattro. Il difetto
    /// da cui nasce questo numero: indicando una cartella con dentro mille
    /// fotografie, il pannello le disegnava tutte e diventava una pagina da
    /// scorrere per un minuto. Nessuno sceglie uno sfondo così — o si sa già
    /// quale si vuole, e allora bastano le prime, o non si sa, e allora
    /// conviene la modalità «cartella», che le fa girare da sé.
    property int shown: 24
    onModeChanged: {
        page.shown = 24;
        // Arrivando adesso sulla modalità «immagine», l'elenco va fatto ora:
        // all'apertura non lo si è fatto apposta.
        if (page.mode === "image" && page.images.length === 0 && !page.loading)
            page.scan();
    }
    readonly property string home: Quickshell.env("HOME") || ""
    // ── Scelta della cartella ────────────────────────────────────────────

    Rectangle {
        id: folderPicker
        parent: page
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false
        z: 20

        property string path: ""
        property var entries: []

        function open(start) {
            folderPicker.path = start;
            folderPicker.visible = true;
            folderPicker.load();
        }

        function load() {
            Core.Ipc.fsList(folderPicker.path, false, "wallpaperFolder");
        }

        function up() {
            var p = folderPicker.path;
            if (p.length > 1 && p.charAt(p.length - 1) === "/")
                p = p.substring(0, p.length - 1);
            var cut = p.lastIndexOf("/");
            folderPicker.path = cut <= 0 ? "/" : p.substring(0, cut);
            folderPicker.load();
        }

        Connections {
            target: Core.Ipc
            function onFileListingReceived(listing) {
                if (listing.pane !== "wallpaperFolder")
                    return;
                // Solo cartelle: si sta scegliendo dove cercare, non cosa.
                var dirs = [];
                var all = listing.entries || [];
                for (var i = 0; i < all.length; i++)
                    if (all[i].isDir)
                        dirs.push(all[i]);
                folderPicker.entries = dirs;
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: folderPicker.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(520, parent.width - Theme.Effects.space6 * 2)
            height: Math.min(460, parent.height - Theme.Effects.space6 * 2)
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Item {
                id: pickerHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                height: 30

                Rectangle {
                    id: upButton
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    radius: Theme.Effects.radiusXS
                    color: upMouse.containsMouse ? Theme.Colors.hover : "transparent"

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 15; height: 15
                        name: "chevronUp"
                        color: Theme.Colors.textMuted
                        alwaysDrawn: true
                    }

                    MouseArea {
                        id: upMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: folderPicker.up()
                    }
                }

                Text {
                    anchors.left: upButton.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: folderPicker.path
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            Ui.Scorrimento {
                bersaglio: elencoCartelle
                anchors {
                    right: elencoCartelle.right
                    top: elencoCartelle.top
                    bottom: elencoCartelle.bottom
                }
            }

            ListView {
                id: elencoCartelle
                anchors.top: pickerHeader.bottom
                anchors.topMargin: Theme.Effects.space2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: pickerFooter.top
                anchors.leftMargin: Theme.Effects.space3
                anchors.rightMargin: Theme.Effects.space3
                clip: true
                spacing: 1
                model: folderPicker.entries
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: dir
                    required property var modelData

                    width: ListView.view.width
                    height: 34
                    radius: Theme.Effects.radiusXS
                    color: dirMouse.containsMouse ? Theme.Colors.hover : "transparent"

                    Ui.Icon {
                        id: dirIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15; height: 15
                        name: "folder"
                        color: Theme.Colors.accent
                    }

                    Text {
                        anchors.left: dirIcon.right
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: dir.modelData.name
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: dirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            folderPicker.path = dir.modelData.path;
                            folderPicker.load();
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: folderPicker.entries.length === 0
                    text: page.it ? "Nessuna sottocartella" : "No subfolders"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            Item {
                id: pickerFooter
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                height: 34

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.it ? "Entra nelle cartelle, poi conferma"
                                  : "Browse into a folder, then confirm"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: [
                            { "id": "cancel",  "primary": false },
                            { "id": "confirm", "primary": true }
                        ]

                        delegate: Rectangle {
                            id: pickBtn
                            required property var modelData

                            width: pickLabel.implicitWidth + Theme.Effects.space5
                            height: 32
                            radius: Theme.Effects.radiusXS
                            color: modelData.primary
                                   ? (pickMouse.containsMouse ? Theme.Colors.accent
                                      : Qt.alpha(Theme.Colors.accent, 0.85))
                                   : (pickMouse.containsMouse ? Theme.Colors.hover
                                      : Theme.Colors.raised)
                            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                            Text {
                                id: pickLabel
                                anchors.centerIn: parent
                                text: pickBtn.modelData.id === "cancel"
                                      ? (page.it ? "Annulla" : "Cancel")
                                      : (page.it ? "Usa questa cartella" : "Use this folder")
                                color: pickBtn.modelData.primary
                                       ? Theme.Colors.textOnAccent : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightSemiBold
                            }

                            MouseArea {
                                id: pickMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    folderPicker.visible = false;
                                    if (pickBtn.modelData.id === "confirm")
                                        Core.Ipc.setSetting("desktop.wallpaperFolder",
                                                            folderPicker.path);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    readonly property var messi: Core.Ipc.get("desktop.widgets", [])
    readonly property bool bloccati: Core.Ipc.get("desktop.widgetBloccati", true)
    // ── Quali widget esistono ────────────────────────────────────────────
    //
    // Il costo sta accanto al nome, e non è pedanteria: il progetto lo fa già
    // una volta sola nel gestore file — «Costa 131 MB di memoria, sempre» — ed
    // è l'unico modo di scegliere davvero. Un interruttore che dice «più
    // informazioni» e non dice quanto costa non è una scelta, è una spinta.
    //
    // Qui il costo è lo stesso per tutti e quasi zero, e va detto anche
    // questo: la sorgente è UNA, la cadenza è UNA, e dieci widget costano
    // quanto uno. È il contrario di come funzionano di solito.
    readonly property var disponibili: [
        { "tipo": "prestazioni", "it": "Prestazioni", "en": "Performance",
          "detta": page.it ? "Il tabellone: processore in grande, poi memoria, GPU, temperatura, disco e rete con simbolo e barra, e la storia in fondo"
                           : "The board: processor big, then memory, GPU, temperature, disk and network, with the history at the bottom" },
        { "tipo": "bluetooth",   "it": "Bluetooth", "en": "Bluetooth",
          "detta": page.it ? "Gli apparecchi accoppiati, ognuno col suo simbolo e la batteria — se la dice"
                           : "Paired devices, each with its symbol and battery — when it reports one" },
        { "tipo": "riassunto",   "it": "Come sta il computer",
          "en": "How the computer is doing",
          "detta": page.it ? "Una casella sola, in colonna: processore, memoria, GPU, temperatura"
                           : "One card, in a column" },
        { "tipo": "processore",  "it": "Processore", "en": "Processor",
          "detta": page.it ? "Con quattro minuti di storia dietro" : "With four minutes of history" },
        { "tipo": "memoria",     "it": "Memoria", "en": "Memory",
          "detta": page.it ? "Usata e totale" : "Used and total" },
        { "tipo": "gpu",         "it": "GPU sveglia", "en": "GPU awake",
          "detta": page.it ? "Quanto la scheda video è sveglia. Non è l'uso: è il tempo in cui NON dorme"
                           : "How long the GPU is awake — not its usage" },
        { "tipo": "temperatura", "it": "Temperatura", "en": "Temperature",
          "detta": page.it ? "La sonda più calda" : "The hottest probe" },
        { "tipo": "rete",        "it": "Rete", "en": "Network",
          "detta": page.it ? "Byte al secondo, in arrivo e in partenza" : "Bytes per second" },
        { "tipo": "batteria",    "it": "Batteria", "en": "Battery",
          "detta": page.it ? "E se sta caricando" : "And whether it is charging" },
        { "tipo": "disco",       "it": "Liberi sul disco", "en": "Free on disk",
          "detta": page.it ? "Quanto spazio resta. Si rilegge una volta al minuto"
                           : "How much space is left — read once a minute" },
        { "tipo": "carico",      "it": "Carico", "en": "Load",
          "detta": page.it ? "La media di un minuto" : "One-minute average" },
        { "tipo": "acceso",      "it": "Acceso da", "en": "Up for",
          "detta": page.it ? "Da quanto tempo non si riavvia" : "Since the last restart" },
        { "tipo": "orologio",    "it": "Orologio", "en": "Clock",
          "detta": page.it ? "Ora e data, grandi" : "Time and date, big" },
        { "tipo": "meteo",       "it": "Meteo", "en": "Weather",
          "detta": page.it ? "Va acceso in Data e ora" : "Turn it on in Date & time" }
    ]
    function nomeDi(tipo) {
        for (var i = 0; i < page.disponibili.length; i++)
            if (page.disponibili[i].tipo === tipo)
                return page.it ? page.disponibili[i].it : page.disponibili[i].en;
        return tipo;
    }
    /// Una copia della voce: `Core.Ipc.get` restituisce l'oggetto vero, e
    /// cambiarlo sul posto vorrebbe dire che nessun legame se ne accorge.
    function copia(v) {
        return { "id": v.id, "tipo": v.tipo, "aspetto": v.aspetto,
                 "righe": v.righe, "grafico": v.grafico,
                 "fx": v.fx, "fy": v.fy, "fw": v.fw, "fh": v.fh };
    }
    function tutti() {
        var l = [];
        for (var k = 0; k < page.messi.length; k++)
            l.push(page.copia(page.messi[k]));
        return l;
    }
    function aggiungi(tipo) {
        var l = page.tutti();
        var n = l.length;
        // I tabelloni nascono grandi: cinque righe e un grafico non stanno
        // in una casella da widget singolo.
        var grande = tipo === "prestazioni" || tipo === "bluetooth";
        l.push({ "id": "w" + Date.now(), "tipo": tipo,
                 "aspetto": "vetro", "grafico": true,
                 // A scacchiera e non tutti nello stesso punto: due widget
                 // aggiunti di fila si coprirebbero, e il secondo sembrerebbe
                 // non essere comparso.
                 "fx": 0.32 + (n % 3) * 0.21,
                 "fy": 0.12 + Math.floor(n / 3) * 0.22,
                 "fw": grande ? 0.24 : 0.19, "fh": grande ? 0.62 : 0.19 });
        Core.Ipc.setSetting("desktop.widgets", l);
    }
    function togli(i) {
        var l = [];
        for (var k = 0; k < page.messi.length; k++)
            if (k !== i)
                l.push(page.copia(page.messi[k]));
        Core.Ipc.setSetting("desktop.widgets", l);
    }
    // ── La barra ─────────────────────────────────────────────────────────
    //
    // Non tutti i tipi: il riassunto è una colonna, e una colonna dentro una
    // barra alta trentaquattro pixel non è un widget, è un pasticcio.
    // L'orologio la barra ce l'ha già, e il meteo pure — metterceli due volte
    // sarebbe la stessa cosa detta due volte.
    readonly property var perLaBarra: [
        "processore", "memoria", "gpu", "temperatura",
        "rete", "disco", "batteria", "carico"
    ]
    readonly property var nellaBarra: Core.Ipc.get("bar.widgets", [])
    /// Accende o spegne un valore nella barra, tenendo l'ordine dell'elenco
    /// qui sopra: chi ne riaccende uno se lo ritrova al suo posto.
    function barra(quale, acceso) {
        var ora = page.nellaBarra;
        var l = [];
        for (var k = 0; k < page.perLaBarra.length; k++) {
            var t = page.perLaBarra[k];
            var c = (t === quale) ? acceso : (ora.indexOf(t) !== -1);
            if (c)
                l.push(t);
        }
        Core.Ipc.setSetting("bar.widgets", l);
    }
    // ── Le righe che un riassunto può contenere ──────────────────────────
    //
    // Non tutte quelle che esistono: dentro una colonna alta cinque righe,
    // l'orologio e il meteo sarebbero due righe di testo lungo in mezzo a dei
    // numeri, e la colonna smetterebbe di leggersi in un colpo.
    readonly property var righeRiassunto: [
        "processore", "memoria", "gpu", "temperatura",
        "rete", "disco", "batteria", "carico", "acceso"
    ]
    /// Le righe di un riassunto, con il valore di serie quando non le ha
    /// ancora scelte nessuno. Lo stesso elenco è scritto in `Riassunto.qml`
    /// come ripiego: qui è quello che si VEDE nelle spunte, e devono
    /// combaciare o le spunte mentirebbero al primo colpo d'occhio.
    function leRighe(v) {
        if (v && v.righe && v.righe.length > 0)
            return v.righe;
        return ["processore", "memoria", "gpu", "temperatura"];
    }
    function dentroLeRighe(v, quale) {
        return page.leRighe(v).indexOf(quale) !== -1;
    }
    /// Accende o spegne una riga, tenendo l'ordine dell'elenco qui sopra: chi
    /// riaccende «memoria» se la ritrova al suo posto e non in fondo.
    function riga(i, quale, acceso) {
        var l = page.tutti();
        if (i < 0 || i >= l.length)
            return;
        var ora = page.leRighe(page.messi[i]);
        var nuove = [];
        for (var k = 0; k < page.righeRiassunto.length; k++) {
            var r = page.righeRiassunto[k];
            var c = (r === quale) ? acceso : (ora.indexOf(r) !== -1);
            if (c)
                nuove.push(r);
        }
        // Mai vuoto: una casella senza righe è un rettangolo di vetro che non
        // dice niente, e chi ha spento l'ultima non capirebbe come tornare
        // indietro. Si tiene l'ultima accesa.
        if (nuove.length === 0)
            return;
        l[i].righe = nuove;
        Core.Ipc.setSetting("desktop.widgets", l);
    }
    function cambia(i, campo, valore) {
        var l = page.tutti();
        if (i < 0 || i >= l.length)
            return;
        l[i][campo] = valore;
        Core.Ipc.setSetting("desktop.widgets", l);
    }
    Card {
        heading: page.it ? "Sfondo della scrivania" : "Desktop wallpaper"
        note: page.it
              ? "Si arriva qui anche col tasto destro sulla scrivania."
              : "You can also get here by right-clicking the desktop."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Da dove" : "Where from"
            controlWidth: 360
            control: S.ChoicePicker {
                value: page.mode
                options: [
                    { "value": "minerva",
                      "label": page.it ? "Di Minerva" : "Minerva's" },
                    { "value": "image",
                      "label": page.it ? "Una tua immagine" : "An image of yours" },
                    { "value": "folder",
                      "label": page.it ? "Una cartella che gira" : "A rotating folder" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("desktop.wallpaperMode", v);
                }
            }
        }

        // ── Una sola immagine, presa dove sta ────────────────────────────
        //
        // Giacomo, 18 agosto 2026: «per impostare lo sfondo devo copiare il
        // percorso dal file manager e incollarlo in impostazioni».
        //
        // Il selettore per farlo esisteva da giorni — `SelettoreImmagine`,
        // scritto per il ritratto utente — e questa pagina non lo usava: qui
        // si poteva scegliere una CARTELLA e poi pescare da una griglia, che è
        // il gesto giusto per farsi girare gli sfondi e quello sbagliato per
        // mettere quella foto lì.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Una immagine precisa" : "One particular image"
            description: page.it
                ? "Si sfoglia il disco e si sceglie, senza uscire da qui"
                : "Browse the disk and pick one, without leaving this page"
            controlWidth: 200
            control: Rectangle {
                width: parent ? parent.width : 200
                height: 30
                radius: Theme.Effects.radiusXS
                color: sceglMouse.containsMouse
                       ? Qt.alpha(Theme.Colors.accent, 0.16) : Theme.Colors.raisedHigh
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Scegli dal disco…" : "Choose from disk…"
                    color: sceglMouse.containsMouse ? Theme.Colors.accent
                                                    : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightMedium
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: sceglMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sceltaSfondo.apri(page.folder !== "" ? page.folder
                                                                    : page.home)
                }
            }
        }

        // ── Gli sfondi di Minerva ────────────────────────────────────────
        //
        // Sei, disegnati dalla stessa tavolozza dell'interfaccia. Ci stanno
        // tutti in due righe: non c'è niente da scorrere, e questo è il punto.

        Grid {
            id: ownGrid
            width: parent.width
            columns: 3
            spacing: Theme.Effects.space2
            visible: page.mode === "minerva"

            readonly property real cell: (width - spacing * (columns - 1)) / columns

            Repeater {
                model: Core.Wallpaper.own

                delegate: Rectangle {
                    id: ownThumb
                    required property var modelData

                    readonly property string path: Core.Wallpaper.ownPath(modelData.file)
                    readonly property bool chosen: path === Core.Wallpaper.current

                    width: ownGrid.cell
                    height: Math.round(ownGrid.cell * 9 / 16)
                    radius: Theme.Effects.radiusSM
                    color: Theme.Colors.sunken
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Theme.Colors.accent
                               : ownMouse.containsMouse ? Theme.Colors.edgeBright
                               : Theme.Colors.edge
                    Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: ownThumb.chosen ? 2 : 1
                        // Niente sorgente se la griglia non si vede: senza
                        // questa guardia l'immagine si decodifica lo stesso.
                        source: ownGrid.visible ? "file://" + ownThumb.path : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 420
                        sourceSize.height: 260
                        smooth: true
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 24
                        color: Qt.rgba(0, 0, 0, 0.55)

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.Effects.space2
                            verticalAlignment: Text.AlignVCenter
                            text: page.it ? ownThumb.modelData.it : ownThumb.modelData.en
                            color: "#FFFFFF"
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Theme.Effects.space2
                        width: 22; height: 22
                        radius: 11
                        visible: ownThumb.chosen
                        color: Theme.Colors.accent

                        Ui.Icon {
                            anchors.centerIn: parent
                            width: 13; height: 13
                            name: "check"
                            color: Theme.Colors.textOnAccent
                        }
                    }

                    MouseArea {
                        id: ownMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.apply(ownThumb.path)
                    }
                }
            }
        }

        // Da dove pescare
        Item {
            width: parent.width
            visible: page.mode !== "minerva"
            height: visible ? 34 : 0

            Text {
                id: folderLabel
                anchors.left: parent.left
                anchors.right: folderButtons.left
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                text: page.folder !== ""
                      ? page.folder
                      : (page.it ? "Immagini, Sfondi e sfondi di sistema"
                                 : "Pictures, Wallpapers and system backgrounds")
                color: Theme.Colors.textMuted
                font.family: page.folder !== "" ? Theme.Typography.fontMono
                                                : Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Row {
                id: folderButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.Effects.space2

                Rectangle {
                    width: resetFolderText.implicitWidth + Theme.Effects.space3
                    height: 28
                    radius: Theme.Effects.radiusXS
                    visible: page.folder !== ""
                    color: resetFolderMouse.containsMouse ? Theme.Colors.hover
                                                          : "transparent"

                    Text {
                        id: resetFolderText
                        anchors.centerIn: parent
                        text: page.it ? "Le solite" : "Default"
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    MouseArea {
                        id: resetFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("desktop.wallpaperFolder", "")
                    }
                }

                Rectangle {
                    width: pickFolderText.implicitWidth + Theme.Effects.space4
                    height: 28
                    radius: Theme.Effects.radiusXS
                    color: pickFolderMouse.containsMouse
                           ? Qt.alpha(Theme.Colors.accent, 0.16) : Theme.Colors.raisedHigh
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        id: pickFolderText
                        anchors.centerIn: parent
                        text: page.it ? "Scegli una cartella…" : "Choose a folder…"
                        color: pickFolderMouse.containsMouse ? Theme.Colors.accent
                                                             : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    MouseArea {
                        id: pickFolderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: folderPicker.open(page.folder !== "" ? page.folder
                                                                        : page.home)
                    }
                }
            }
        }

        // La griglia. Tre per riga, alte abbastanza da riconoscere una
        // fotografia: era questo il problema della striscia di prima.
        Grid {
            id: grid
            width: parent.width
            columns: 3
            spacing: Theme.Effects.space2
            visible: page.mode === "image"

            readonly property real cell: (width - spacing * (columns - 1)) / columns

            Repeater {
                model: page.images.slice(0, page.shown)

                delegate: Rectangle {
                    id: thumb
                    required property var modelData

                    readonly property bool chosen: modelData === page.current

                    width: grid.cell
                    height: Math.round(grid.cell * 9 / 16)
                    radius: Theme.Effects.radiusSM
                    color: Theme.Colors.sunken
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Theme.Colors.accent
                               : thumbMouse.containsMouse ? Theme.Colors.edgeBright
                               : Theme.Colors.edge
                    Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: thumb.chosen ? 2 : 1
                        source: grid.visible ? "file://" + thumb.modelData : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Ridotte in memoria: caricare a piena risoluzione
                        // cento fotografie da otto megapixel blocca tutto.
                        sourceSize.width: 420
                        sourceSize.height: 260
                        smooth: true
                    }

                    // Il nome del file, solo al passaggio: serve a distinguere
                    // due fotografie simili, non a stare sempre lì.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 22
                        visible: thumbMouse.containsMouse
                        color: Qt.rgba(0, 0, 0, 0.65)

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.Effects.space2
                            anchors.rightMargin: Theme.Effects.space2
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideMiddle
                            text: {
                                var p = thumb.modelData;
                                var cut = p.lastIndexOf("/");
                                return cut < 0 ? p : p.substring(cut + 1);
                            }
                            color: "#FFFFFF"
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Theme.Effects.space2
                        width: 22; height: 22
                        radius: 11
                        visible: thumb.chosen
                        color: Theme.Colors.accent

                        Ui.Icon {
                            anchors.centerIn: parent
                            width: 13; height: 13
                            name: "check"
                            color: Theme.Colors.textOnAccent
                        }
                    }

                    MouseArea {
                        id: thumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.apply(thumb.modelData)
                    }
                }
            }
        }

        // «Ne mostro altre», invece di mostrarle tutte e sempre.
        Item {
            width: parent.width
            visible: page.mode === "image" && page.images.length > page.shown
            height: visible ? 38 : 0

            Rectangle {
                anchors.centerIn: parent
                width: moreText.implicitWidth + Theme.Effects.space5
                height: 30
                radius: Theme.Effects.radiusXS
                color: moreMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    id: moreText
                    anchors.centerIn: parent
                    text: {
                        var left = page.images.length - page.shown;
                        var n = Math.min(24, left);
                        return page.it ? "Mostrane altre " + n + " (ne restano " + left + ")"
                                       : "Show " + n + " more (" + left + " left)";
                    }
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: moreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.shown += 24
                }
            }
        }

        Text {
            width: parent.width
            visible: page.mode === "image" && page.images.length === 0
            wrapMode: Text.WordWrap
            text: page.loading
                  ? (page.it ? "Cerco…" : "Looking…")
                  : (page.it
                     ? "Nessuna immagine in questa cartella. Provane un'altra con "
                       + "«Scegli una cartella…»."
                     : "No image in this folder. Try another with “Choose a folder…”.")
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        // ── La cartella che gira da sola ─────────────────────────────────
        //
        // Qui NON c'è nessuna griglia, ed è una scelta. Chi indica una
        // cartella con mille fotografie non sta scegliendo una fotografia:
        // sta dicendo «pescale tu». Quindi si mostra quella di adesso, ogni
        // quanto cambia, e un pulsante per saltare avanti — che è tutto ciò
        // che serve, e sta in mezzo schermo invece che in dieci.

        Column {
            width: parent.width
            spacing: Theme.Effects.space2
            visible: page.mode === "folder"

            Rectangle {
                width: parent.width
                height: Math.round(width * 9 / 16 * 0.45)
                radius: Theme.Effects.radiusSM
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Theme.Colors.edge
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: page.mode === "folder" && Core.Wallpaper.current !== ""
                            ? "file://" + Core.Wallpaper.current : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 900
                    sourceSize.height: 500
                    smooth: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: Core.Wallpaper.pool.length === 0
                    text: page.it ? "Scegli una cartella con delle immagini"
                                  : "Choose a folder with images in it"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 26
                    color: Qt.rgba(0, 0, 0, 0.6)
                    visible: Core.Wallpaper.pool.length > 0

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.rightMargin: Theme.Effects.space3
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideMiddle
                        text: {
                            var n = Core.Wallpaper.pool.length;
                            var at = Core.Wallpaper.poolAt + 1;
                            var name = Core.Wallpaper.current;
                            var cut = name.lastIndexOf("/");
                            if (cut >= 0)
                                name = name.substring(cut + 1);
                            return name + "   ·   " + (at > 0 ? at : "?") + " di " + n;
                        }
                        color: "#FFFFFF"
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }
        }

        // ── Il giro, per tutti e due i mazzi ─────────────────────────────
        //
        // Questi tre comandi stavano DENTRO il blocco della cartella, e con
        // gli sfondi di Minerva davanti sparivano. Ma «cambia ogni cinque
        // minuti, a caso» ha senso identico su sei sfondi nostri e su mille
        // fotografie tue: quello che cambia è dove si pescano, non che
        // girino. Adesso stanno fuori da tutti e due i blocchi e valgono per
        // entrambi. Restano nascosti solo per «una tua immagine», dove il
        // mazzo è di una carta e non c'è niente da far girare.

        Column {
            width: parent.width
            spacing: Theme.Effects.space2
            visible: page.mode === "minerva" || page.mode === "folder"

            S.SettingRow {
                width: parent.width
                label: page.it ? "Cambia ogni" : "Change every"
                controlWidth: 380
                control: S.ChoicePicker {
                    value: String(Core.Wallpaper.rotateMinutes)
                    options: [
                        { "value": "0",    "label": page.it ? "Mai" : "Never" },
                        { "value": "5",    "label": "5 min" },
                        { "value": "15",   "label": "15 min" },
                        { "value": "60",   "label": page.it ? "1 ora" : "1 hour" },
                        { "value": "1440", "label": page.it ? "1 giorno" : "1 day" }
                    ]
                    onPicked: function(v) {
                        Core.Ipc.setSetting("desktop.rotateMinutes", parseInt(v, 10));
                    }
                }
            }

            S.SettingRow {
                width: parent.width
                label: page.it ? "In che ordine" : "In what order"
                controlWidth: 260
                control: S.ChoicePicker {
                    value: Core.Wallpaper.rotateRandom ? "random" : "order"
                    options: [
                        { "value": "order",  "label": page.it ? "In ordine" : "In order" },
                        { "value": "random", "label": page.it ? "A caso" : "At random" }
                    ]
                    onPicked: function(v) {
                        Core.Ipc.setSetting("desktop.rotateRandom", v === "random");
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "prev", "it": "Precedente", "en": "Previous" },
                        { "id": "next", "it": "La prossima", "en": "Next one" }
                    ]

                    delegate: Rectangle {
                        id: skip
                        required property var modelData

                        width: skipText.implicitWidth + Theme.Effects.space5
                        height: 32
                        radius: Theme.Effects.radiusXS
                        enabled: Core.Wallpaper.pool.length > 0
                        opacity: enabled ? 1 : 0.4
                        color: skipMouse.containsMouse ? Theme.Colors.hover
                                                       : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: skipText
                            anchors.centerIn: parent
                            text: page.it ? skip.modelData.it : skip.modelData.en
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: skipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: skip.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Core.Wallpaper.next(skip.modelData.id === "prev" ? -1 : 1)
                        }
                    }
                }
            }
        }
    }
    // ── Colore d'accento ─────────────────────────────────────────────────

    Card {
        heading: page.it ? "Scrivania" : "Desktop"
        note: page.it
              ? "Le icone dei file, come su ogni ambiente classico: doppio clic per aprire, trascina per spostarle."
              : "File icons, like on any classic desktop: double-click to open, drag to move them."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Icone sulla scrivania" : "Desktop icons"
            description: page.it
                ? "Il contenuto della cartella Scrivania, e il posto di ogni icona resta dove lo metti"
                : "The contents of the Desktop folder, and every icon remembers where you put it"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.icons", true)
                onToggled: function(v) { Core.Ipc.setSetting("desktop.icons", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Menu col tasto destro" : "Right-click menu"
            description: page.it
                ? "Aprire programmi e cambiare sfondo dal tasto destro sulla scrivania"
                : "Open programs and change the wallpaper from the desktop right-click"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.rightClickMenu", true)
                onToggled: function(v) { Core.Ipc.setSetting("desktop.rightClickMenu", v); }
            }
        }

        // ── Le cinque che si potevano toccare SOLO dal tasto destro ───────
        //
        // `iconSize`, `iconAutoArrange`, `iconSnap`, `iconSort`,
        // `iconSortDesc`: tutte e cinque funzionano da sempre, e stavano
        // dentro il menù della scrivania e in nessun altro posto. Un'opzione
        // che si trova solo se sai già dove cliccare è un'opzione che per
        // molti non esiste — è la stessa cosa che è successa alla dock, che
        // aveva sette voci e Giacomo scriveva «non ci sono impostazioni per
        // essa».
        //
        // Restano anche nel menù: là si aggiustano mentre si guardano le
        // icone, che è il momento in cui uno lo vuole fare.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("desktop.icons", true)
            label: page.it ? "Dimensione delle icone" : "Icon size"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 32
                to: 96
                unit: "pixel"
                value: Core.Ipc.get("desktop.iconSize", 46)
                onReleased: function(v) {
                    Core.Ipc.setSetting("desktop.iconSize", Math.round(v));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("desktop.icons", true)
            label: page.it ? "Disponile da sole" : "Arrange them automatically"
            description: page.it
                ? "Si mettono in colonna da sé, e non si possono più trascinare"
                : "They line up by themselves, and can no longer be dragged"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.iconAutoArrange", false)
                onToggled: function(v) {
                    Core.Ipc.setSetting("desktop.iconAutoArrange", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("desktop.icons", true)
                     && !Core.Ipc.get("desktop.iconAutoArrange", false)
            label: page.it ? "Allinea alla griglia" : "Snap to the grid"
            description: page.it
                ? "Lasciandole cadere si mettono in riga con le altre"
                : "When dropped, they line up with the others"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.iconSnap", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("desktop.iconSnap", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("desktop.icons", true)
                     && Core.Ipc.get("desktop.iconAutoArrange", false)
            label: page.it ? "In che ordine" : "In what order"
            controlWidth: 320
            control: S.ChoicePicker {
                value: Core.Ipc.get("desktop.iconSort", "name")
                options: [
                    { "value": "name",     "label": page.it ? "Nome" : "Name" },
                    { "value": "type",     "label": page.it ? "Tipo" : "Type" },
                    { "value": "size",     "label": page.it ? "Dimensione" : "Size" },
                    { "value": "modified", "label": page.it ? "Data" : "Date" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("desktop.iconSort", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("desktop.icons", true)
                     && Core.Ipc.get("desktop.iconAutoArrange", false)
            label: page.it ? "Dal fondo" : "Reversed"
            description: page.it ? "Z prima di A, il più grande per primo"
                                 : "Z before A, biggest first"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.iconSortDesc", false)
                onToggled: function(v) {
                    Core.Ipc.setSetting("desktop.iconSortDesc", v);
                }
            }
        }
    }
    // ── Il blocco ────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Personalizza" : "Customise"
        note: page.it
              ? "Sbloccati si trascinano e si ridimensionano dalla scrivania, "
                + "e col tasto destro si tolgono. Bloccati diventano parte "
                + "dello sfondo: il clic ci passa attraverso."
              : "Unlocked they drag and resize on the desktop. Locked they "
                + "become part of the wallpaper: clicks pass through."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Widget sulla scrivania" : "Desktop widgets"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.widgetAccesi", true)
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.widgetAccesi", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Bloccati" : "Locked"
            description: page.it
                ? "Si sbloccano anche col tasto destro sulla barra, "
                  + "«Personalizza scrivania»"
                : "Also unlocked with a right click on the bar"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.bloccati
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.widgetBloccati", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Scrivania pulita" : "Clean desktop"
            description: page.it
                ? "Niente icone e niente widget, con un clic. Per una "
                  + "schermata, o per mostrarla a qualcuno."
                : "No icons and no widgets, in one click."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.puliti", false)
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.puliti", v);
                }
            }
        }
    }
    // ── Quelli che ci sono ───────────────────────────────────────────────

    Card {
        heading: page.it ? "Quelli che hai" : "The ones you have"
        note: page.messi.length === 0
              ? (page.it ? "Nessuno. Se ne aggiunge uno qui sotto."
                         : "None yet. Add one below.")
              : ""

        Repeater {
            model: page.messi

            // Un widget non è una riga sola: ha l'aspetto, e quelli che hanno
            // una storia hanno anche il grafico, e il riassunto ha le sue
            // righe. Una colonna per widget invece di una riga tiene insieme
            // le cose che parlano dello stesso oggetto — che è il motivo per
            // cui questa pagina esiste al posto di sette voci sparse.
            delegate: Column {
                id: voce
                required property var modelData
                required property int index
                width: parent.width
                spacing: 0

                readonly property string tipo: String(voce.modelData.tipo || "")
                readonly property bool nudo:
                    String(voce.modelData.aspetto || "vetro") === "nudo"

                S.SettingRow {
                    width: parent.width
                    label: page.nomeDi(voce.tipo)
                    description: voce.nudo
                        ? (page.it ? "Senza vetro: si vede lo sfondo dietro"
                                   : "No glass: the wallpaper shows through")
                        : (page.it ? "Col vetro" : "With glass")
                    controlWidth: 320

                    control: Row {
                        spacing: Theme.Effects.space2

                        // ── La larghezza si DICE, dentro una Row ────────
                        //
                        // `ChoicePicker` è largo quanto il genitore
                        // (`width: parent.width`): è fatto per stare da solo
                        // nel posto del controllo. Dentro una Row il
                        // genitore è la Row, e la Row è larga quanto i figli:
                        // si rincorrono, e la pagina resta VUOTA — titolo,
                        // sottotitolo, e sotto niente, con «possible
                        // QQuickItem::polish() loop» nel registro a ripetizione.
                        // Giacomo, 13 settembre 2026: «la sezione desktop è
                        // vuota e non posso aggiungere o rimuovere widget».
                        S.ChoicePicker {
                            width: 200
                            value: voce.nudo ? "nudo" : "vetro"
                            options: [
                                { "value": "vetro", "label": page.it ? "Vetro" : "Glass" },
                                { "value": "nudo",  "label": page.it ? "Nudo" : "Bare" }
                            ]
                            onPicked: function (v) {
                                page.cambia(voce.index, "aspetto", v);
                            }
                        }

                        // Togliere è irreversibile quanto lo è rimettere: un
                        // widget si riaggiunge in un clic, quindi non si chiede
                        // conferma. Chiedere conferma per una cosa che si disfa
                        // da sola è il modo di insegnare a cliccare «sì» senza
                        // leggere.
                        // Centrata con `y` e non con un'ancora al genitore:
                        // stessa ragione qui sopra, la Row non deve dipendere
                        // da un figlio che dipende da lei.
                        Rectangle {
                            y: Math.round((parent.height - height) / 2)
                            width: 30
                            height: 26
                            radius: Theme.Effects.radiusSM
                            color: viaMouse.containsMouse
                                   ? Qt.alpha(Theme.Colors.danger, 0.18)
                                   : Theme.Colors.raised
                            border.width: 1
                            border.color: Theme.Colors.edge

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: viaMouse.containsMouse ? Theme.Colors.danger
                                                              : Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeSM
                            }

                            MouseArea {
                                id: viaMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.togli(voce.index)
                            }
                        }
                    }
                }

                // ── La storia dietro il numero ───────────────────────────
                //
                // Solo per le grandezze che una storia ce l'hanno, e chi lo
                // sa è `Core.Macchina`: l'elenco sta in un posto solo, o si
                // aggiunge una grandezza qui e ci si dimentica là.
                S.SettingRow {
                    width: parent.width
                    visible: Core.Macchina.haStoria(voce.tipo)
                    label: page.it ? "La storia, dietro" : "The history, behind"
                    description: page.it
                        ? "Quattro minuti di grafico dietro al numero. «42 %» "
                          + "non dice se è tanto; «42 % e sale da un minuto» sì."
                        : "Four minutes of graph behind the number."
                    controlWidth: 60
                    control: S.ToggleSwitch {
                        checked: voce.modelData.grafico !== false
                        onToggled: function (v) {
                            page.cambia(voce.index, "grafico", v);
                        }
                    }
                }

                // ── Le righe del riassunto ───────────────────────────────
                //
                // Giacomo: «magari poter avere una singola casella di
                // queste». Una casella sola che le tiene tutte è utile solo
                // se si può dire QUALI: quattro righe fisse sono un widget
                // in più, non una casella su misura.
                Column {
                    width: parent.width
                    visible: voce.tipo === "riassunto"
                    spacing: 0

                    Repeater {
                        model: page.righeRiassunto

                        delegate: S.SettingRow {
                            required property var modelData
                            width: parent.width
                            label: "    " + page.nomeDi(String(modelData))
                            controlWidth: 60
                            control: S.ToggleSwitch {
                                checked: page.dentroLeRighe(voce.modelData,
                                                            String(modelData))
                                onToggled: function (v) {
                                    page.riga(voce.index, String(modelData), v);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // ── E gli stessi, nella barra ────────────────────────────────────────

    Card {
        heading: page.it ? "Nella barra" : "In the bar"
        note: page.it
              ? "Gli stessi valori, in piccolo, accanto al meteo. Con quattro "
                + "minuti di storia in ventotto pixel: non si legge un numero, "
                + "si vede se sale. Il clic apre il Monitor.\n\n"
                + "La barra c'è sempre, quindi un valore qui tiene acceso il "
                + "campionamento per tutta la sessione — quattro file ogni "
                + "cinque secondi. Sulla scrivania invece si spegne da solo "
                + "quando una finestra la copre."
              : "The same values, small, next to the weather. The bar is "
                + "always there, so a value here keeps the sampling on for the "
                + "whole session."

        // Erano undici righe con undici interruttori. Dal 28 settembre 2026
        // una riga di pastiglie: accesa, il valore sta nella barra.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Valori nella barra" : "Values in the bar"
            description: page.it ? "Accesi stanno accanto al meteo, spenti no"
                                 : "Lit ones sit next to the weather"
            searchTerms: "barra processore memoria gpu temperatura rete disco batteria carico"
            controlWidth: 420

            control: Flow {
                width: parent ? parent.width : implicitWidth
                spacing: 6

                Repeater {
                    model: page.perLaBarra

                    delegate: Rectangle {
                        id: pastiglia
                        required property var modelData
                        readonly property bool accesa: page.nellaBarra.indexOf(String(modelData)) !== -1

                        implicitWidth: nomeValore.implicitWidth + 24
                        width: implicitWidth
                        height: 30
                        radius: Theme.Effects.radiusSM
                        color: accesa ? Qt.alpha(Theme.Colors.accent, 0.18)
                                      : (tocco.containsMouse ? Theme.Colors.hover : Theme.Colors.raised)
                        border.width: 1
                        border.color: accesa ? Theme.Colors.accent : Theme.Colors.edge
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: nomeValore.text
                        Accessible.checked: accesa

                        Text {
                            id: nomeValore
                            anchors.centerIn: parent
                            text: page.nomeDi(String(pastiglia.modelData))
                            color: pastiglia.accesa ? Theme.Colors.accent : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: tocco
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.barra(String(pastiglia.modelData), !pastiglia.accesa)
                        }
                    }
                }
            }
        }
    }
    // ── Quelli che si possono aggiungere ─────────────────────────────────

    Card {
        heading: page.it ? "Aggiungine uno" : "Add one"
        note: page.it
              ? "Dieci widget costano quanto uno: la sorgente è una sola e la "
                + "cadenza è una sola — il demone legge quattro file ogni "
                + "cinque secondi, e solo mentre almeno un widget guarda. "
                + "L'unica eccezione è il disco, che non si legge da un file: "
                + "quello si chiede una volta al minuto."
              : "Ten widgets cost as much as one: a single source, a single "
                + "cadence, and only while at least one widget is watching. "
                + "The exception is the disk, asked once a minute."

        Repeater {
            model: page.disponibili

            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: page.it ? modelData.it : modelData.en
                description: modelData.detta
                controlWidth: 120

                control: Ui.SpineButton {
                    height: 30
                    horizontalPadding: Theme.Effects.space4
                    onClicked: page.aggiungi(String(modelData.tipo))
                    content: Text {
                        text: page.it ? "Aggiungi" : "Add"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }
        }
    }
}
