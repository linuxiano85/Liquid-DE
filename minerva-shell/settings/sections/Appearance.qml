import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Appearance — Sfondo, colore d'accento e trasparenza.
//
// Lo sfondo era una striscia di francobolli sepolta in fondo alle opzioni, e
// cercava solo in due cartelle fisse. Adesso è la prima cosa che si vede, le
// anteprime sono grandi abbastanza da riconoscere una fotografia, e la
// cartella da cui pescare la sceglie chi guarda.
Page {
    id: page


    title: Core.Strings.lang === "it" ? "Aspetto" : "Appearance"
    subtitle: Core.Strings.lang === "it"
              ? "Sfondo della scrivania e colore d'accento"
              : "Desktop wallpaper and accent colour"

    readonly property bool it: Core.Strings.lang === "it"

    /// Vero quando la cornice si muove: «gira» o «striscia». Le due manopole
    /// del giro — quanto ci mette e con che colori — valgono per tutte e due.
    readonly property bool _corniceGira: {
        var c = String(Core.Ipc.get("windows.cornice", "spento"));
        return c === "gira" || c === "striscia";
    }

    /// Le pasticche che si possono aggiungere. Sono i colori dell'accento di
    /// Minerva più l'accento scelto adesso: chi vuole «i miei colori invece
    /// dell'arcobaleno» quasi sempre vuole questi.
    readonly property var tinteProposte: [
        String(Theme.Colors.accent), "#22D3EE", "#F97316", "#A855F7",
        "#22C55E", "#EF4444", "#EAB308", "#EC4899", "#3B82F6"
    ]

    function tintaTogli(colore) {
        var l = Core.Ipc.get("windows.corniceTinte", []).slice();
        var i = l.indexOf(colore);
        if (i < 0)
            return;
        l.splice(i, 1);
        Core.Ipc.setSetting("windows.corniceTinte", l);
    }

    function tintaAggiungi(colore) {
        var l = Core.Ipc.get("windows.corniceTinte", []).slice();
        // Otto è il tetto del compositore: sopra, girando, non si distinguono
        // più l'uno dall'altro.
        if (l.length >= 8 || l.indexOf(colore) >= 0)
            return;
        l.push(colore);
        Core.Ipc.setSetting("windows.corniceTinte", l);
    }

    /// Toglie un programma dall'elenco di quelli che si disegnano la barra da
    /// soli. Da quel momento la barra gliela mette Minerva — al PROSSIMO
    /// avvio di quella finestra: la decisione si prende quando la finestra
    /// nasce (`finestra_decidi_barra`), e cambiarla a metà vita vorrebbe dire
    /// una finestra che si ridisegna sotto le dita.
    function csdTogli(nome) {
        var l = Core.Ipc.get("windows.csdApps", []).slice();
        var i = l.indexOf(nome);
        if (i < 0)
            return;
        l.splice(i, 1);
        Core.Ipc.setSetting("windows.csdApps", l);
    }

    /// E ne aggiunge uno. Uno spazio dentro il nome spezzerebbe la riga che va
    /// al compositore in due nomi: si rifiuta invece di mandare una cosa che
    /// là dentro diventa un'altra.
    function csdAggiungi(nome) {
        var v = String(nome || "").trim().toLowerCase();
        if (v === "" || v.indexOf(" ") >= 0)
            return;
        var l = Core.Ipc.get("windows.csdApps", []).slice();
        if (l.indexOf(v) >= 0)
            return;
        l.push(v);
        Core.Ipc.setSetting("windows.csdApps", l);
    }
    readonly property string home: Quickshell.env("HOME") || ""

    // ── I colori messi a mano ────────────────────────────────────────────
    //
    // La mappa sta in `shell.scavalca`, e si scrive intera ogni volta: il
    // demone SOSTITUISCE il valore in fondo al percorso invece di fonderlo,
    // quindi è anche l'unico modo di togliere una voce. Fonderla vorrebbe dire
    // che «rimetti a posto» aggiunge invece di levare.
    readonly property var scavalca: Core.Ipc.get("shell.scavalca", ({})) || ({})

    function _copiaScavalca() {
        var fuori = {};
        var m = page.scavalca;
        for (var k in m)
            if (m[k] !== undefined && m[k] !== null && String(m[k]) !== "")
                fuori[k] = m[k];
        return fuori;
    }

    function mettiColore(nome, esa) {
        var m = page._copiaScavalca();
        m[nome] = String(esa).toUpperCase();
        Core.Ipc.setSetting("shell.scavalca", m);
    }

    function togliColore(nome) {
        var m = page._copiaScavalca();
        delete m[nome];
        Core.Ipc.setSetting("shell.scavalca", m);
    }

    /// Quale riga ha il selettore aperto. Una sola per volta: due quadrati
    /// aperti insieme fanno una pagina alta il doppio dello schermo, e si
    /// perde di vista quello che si sta cambiando.
    property string coloreAperto: ""

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

    // ── Il tema di colore ────────────────────────────────────────────────
    //
    // Sta per primo, prima ancora dello sfondo, ed è una scelta: è la cosa
    // che cambia di più l'aspetto di Minerva, e chi apre questa pagina di
    // solito è venuto per quella.
    //
    // Le anteprime sono i colori veri del tema, non dei quadratini decisi a
    // parte: il fondo, la superficie dei pannelli, l'accento. Un elenco di
    // NOMI («Rosa», «Ametista») non dice niente finché non lo si prova, e
    // provarlo vuol dire ridipingere tutto lo schermo per scoprire che non
    // era quello.
    Card {
        heading: page.it ? "Tema" : "Theme"
        note: page.it
              ? "Cambia tutta Minerva: barra, pannelli, finestre e icone."
              : "Changes all of Minerva: bar, panels, windows and icons."

        Flow {
            width: parent.width
            spacing: 10

            Repeater {
                model: Object.keys(Theme.Colors.schemes)

                delegate: Rectangle {
                    id: chip
                    required property var modelData

                    readonly property var tema: Theme.Colors.schemes[chip.modelData]
                    readonly property bool selected:
                        Core.Ipc.get("shell.scheme", "notte") === chip.modelData

                    width: 132
                    height: 84
                    radius: Theme.Effects.radiusMD
                    color: chip.tema.base
                    border.width: chip.selected ? 2 : 1
                    border.color: chip.selected ? Theme.Colors.accent
                                                : Theme.Colors.edge
                    Behavior on border.color {
                        ColorAnimation { duration: Theme.Motion.instant }
                    }

                    // La superficie dei pannelli, dentro il fondo: è ciò che
                    // distingue un tema chiaro con vetro da uno piatto, e a
                    // parole non si spiega.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        height: 30
                        radius: Theme.Effects.radiusSM
                        color: chip.tema.scura ? Qt.rgba(1, 1, 1, 0.10)
                                               : Qt.rgba(1, 1, 1, 0.75)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            width: 12; height: 12; radius: 6
                            color: chip.tema.accento
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 25
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            elide: Text.ElideRight
                            text: page.it ? chip.tema.it : chip.tema.en
                            color: chip.tema.scura ? "#F2F4F8" : "#1B1D22"
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightMedium
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Anche l'accento, e non è invadenza: l'accento
                            // salvato vince sempre su quello del tema, quindi
                            // senza questa riga si sceglie «Rosa» e resta il
                            // ciano di prima acceso in mezzo al rosa. Chi ne
                            // vuole un altro lo cambia qui sotto, e da quel
                            // momento è suo.
                            Core.Ipc.setSetting("shell.scheme", chip.modelData);
                            Core.Ipc.setSetting("shell.accent", chip.tema.accento);
                        }
                    }
                }
            }

            // ── Il settimo, che è tuo ────────────────────────────────
            //
            // Sta nella stessa fila degli altri sei e non in un riquadro a
            // parte: è un tema come loro, e metterlo altrove direbbe che è
            // una cosa da esperti. L'anteprima è la tinta VERA che si è
            // scelta, come per gli altri.
            //
            // L'accento non si riscrive scegliendolo — a differenza dei sei.
            // Quelli portano l'accento che sta bene con la loro tinta, che è
            // una scelta nostra; qui la tinta la sceglie chi guarda, e
            // decidere anche l'accento vorrebbe dire cancellargli una scelta
            // che ha già fatto.
            Rectangle {
                id: chipMio

                readonly property bool selected:
                    Core.Ipc.get("shell.scheme", "notte") === "personale"
                readonly property color tinta:
                    Theme.Colors.tinta(Core.Ipc.get("shell.tintaPersonale",
                                                    "#101018"))
                readonly property bool scuro:
                    Core.Ipc.get("shell.versoPersonale", true)

                width: 132
                height: 84
                radius: Theme.Effects.radiusMD
                color: chipMio.tinta
                border.width: chipMio.selected ? 2 : 1
                border.color: chipMio.selected ? Theme.Colors.accent
                                               : Theme.Colors.edge

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 30
                    radius: Theme.Effects.radiusSM
                    color: chipMio.scuro ? Qt.rgba(1, 1, 1, 0.10)
                                         : Qt.rgba(1, 1, 1, 0.75)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        width: 12; height: 12; radius: 6
                        color: Theme.Colors.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 25
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        elide: Text.ElideRight
                        text: page.it ? "Personale" : "Personal"
                        color: chipMio.scuro ? "#F2F4F8" : "#1B1D22"
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Ipc.setSetting("shell.scheme", "personale")
                }
            }
        }

        // ── La tinta e il verso, solo quando serve ───────────────────────
        //
        // Compaiono scegliendo «Personale» e spariscono altrimenti: mostrarli
        // sempre vorrebbe dire due manopole che non fanno niente per sei temi
        // su sette, ed è la forma esatta del difetto di `bar.position`.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("shell.scheme", "notte") === "personale"
            label: page.it ? "Chiaro o scuro" : "Light or dark"
            description: page.it
                ? "Non si indovina dalla tinta: un grigio medio sta bene in tutti e due i modi, e da questo dipende il verso di veli, bordi e testo"
                : "It cannot be guessed from the tint: a mid grey works either way, and the direction of veils, borders and text depends on it"
            controlWidth: 240
            control: S.ChoicePicker {
                value: Core.Ipc.get("shell.versoPersonale", true) ? "scuro"
                                                                  : "chiaro"
                options: [
                    { "value": "scuro",  "label": page.it ? "Scuro" : "Dark" },
                    { "value": "chiaro", "label": page.it ? "Chiaro" : "Light" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("shell.versoPersonale", v === "scuro");
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("shell.scheme", "notte") === "personale"
            label: page.it ? "La tinta" : "The tint"
            description: page.it
                ? "Il colore del vetro. Superfici, veli, bordi e testo escono da qui"
                : "The colour of the glass. Surfaces, veils, borders and text all derive from it"
            control: Rectangle {
                width: 44; height: 30
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.tinta(Core.Ipc.get("shell.tintaPersonale",
                                                       "#101018"))
                border.width: page.coloreAperto === "tinta" ? 2 : 1
                border.color: page.coloreAperto === "tinta"
                              ? Theme.Colors.accent : Theme.Colors.edge

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.coloreAperto =
                        (page.coloreAperto === "tinta") ? "" : "tinta"
                }
            }
        }

        S.SelettoreColore {
            width: parent.width
            visible: page.coloreAperto === "tinta"
                     && Core.Ipc.get("shell.scheme", "notte") === "personale"
            valore: Theme.Colors.tinta(Core.Ipc.get("shell.tintaPersonale",
                                                    "#101018"))
            onScelto: function(c) {
                Core.Ipc.setSetting("shell.tintaPersonale",
                                    c.toString().toUpperCase());
            }
        }
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

    Card {
        heading: page.it ? "Colore d'accento" : "Accent colour"
        note: page.it
              ? "È il colore di ciò che è attivo: la scrivania in uso, il pannello "
                + "aperto, il cursore che stai trascinando."
              : "The colour of whatever is active: the current desktop, the open "
                + "panel, the slider you are dragging."

        Row {
            width: parent.width
            spacing: Theme.Effects.space2

            Repeater {
                model: [
                    { "value": "#22D3EE", "it": "Ciano",    "en": "Cyan" },
                    { "value": "#38BDF8", "it": "Azzurro",  "en": "Sky" },
                    { "value": "#818CF8", "it": "Indaco",   "en": "Indigo" },
                    { "value": "#A78BFA", "it": "Viola",    "en": "Violet" },
                    { "value": "#F472B6", "it": "Rosa",     "en": "Pink" },
                    { "value": "#34D399", "it": "Verde",    "en": "Green" },
                    { "value": "#FBBF24", "it": "Ambra",    "en": "Amber" },
                    { "value": "#FB7185", "it": "Corallo",  "en": "Coral" }
                ]

                delegate: Rectangle {
                    id: swatch
                    required property var modelData

                    readonly property bool chosen:
                        Core.Ipc.get("shell.accent", "#22D3EE") === modelData.value

                    width: 44; height: 44
                    radius: 22
                    color: modelData.value
                    border.width: chosen ? 3 : 0
                    border.color: Theme.Colors.text

                    scale: swatchMouse.containsMouse ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        name: "check"
                        visible: swatch.chosen
                        color: "#04121A"
                        thickness: 2.4
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("shell.accent",
                                                       swatch.modelData.value)
                    }
                }
            }

            // ── E il nono, che è qualunque ───────────────────────────
            //
            // Le otto restano perché scelgono BENE: sono accenti che stanno
            // insieme a tutti e sei i temi, e chi non ha voglia di scegliere
            // un colore non deve essere costretto a farlo. Questo è per chi
            // ce l'ha già in mano — il colore di un logo, di un'altra
            // scrivania, di una fotografia.
            Rectangle {
                id: altroAccento

                readonly property bool aperto: page.coloreAperto === "accento"
                /// Nessuna delle otto: allora è uno suo, e va mostrato acceso.
                readonly property bool suo: {
                    var a = String(Core.Ipc.get("shell.accent", "#22D3EE"))
                            .toUpperCase();
                    var otto = ["#22D3EE", "#38BDF8", "#818CF8", "#A78BFA",
                                "#F472B6", "#34D399", "#FBBF24", "#FB7185"];
                    return otto.indexOf(a) < 0;
                }

                width: 44; height: 44
                radius: 22
                color: altroAccento.suo ? Theme.Colors.accent
                                        : Theme.Colors.raised
                border.width: (altroAccento.suo || altroAccento.aperto) ? 3 : 1
                border.color: altroAccento.suo ? Theme.Colors.text
                                               : Theme.Colors.edge

                scale: altroMouse.containsMouse ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    name: "plus"
                    visible: !altroAccento.suo
                    color: Theme.Colors.textMuted
                    thickness: 2.0
                    alwaysDrawn: true
                }

                MouseArea {
                    id: altroMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.coloreAperto =
                        altroAccento.aperto ? "" : "accento"
                }
            }
        }

        S.SelettoreColore {
            width: parent.width
            visible: page.coloreAperto === "accento"
            valore: Theme.Colors.tinta(Core.Ipc.get("shell.accent", "#22D3EE"))
            onScelto: function(c) {
                Core.Ipc.setSetting("shell.accent", c.toString().toUpperCase());
            }
        }
    }

    // ── I colori messi a mano ────────────────────────────────────────────
    //
    // Fin qui si sceglie una TINTA e tutto il resto si ricava: è il modo in cui
    // Minerva resta coerente da sola, e per quasi tutti è quello giusto. Ma
    // «coerente da sola» vuol dire anche «non puoi avere i caratteri viola su
    // un fondo rosa», e ogni tanto è proprio quello che si vuole.
    //
    // Qui la derivazione si scavalca, uno per uno. Sette e non quaranta:
    // questi sono i sette da cui escono tutti gli altri, e una pagina con
    // quaranta quadratini non è più libertà — è un lavoro.
    Card {
        heading: page.it ? "Colori a mano" : "Colours by hand"
        note: page.it
              ? "Ogni colore qui vince sul conto che lo avrebbe calcolato. "
                + "Quei conti erano misurati: sotto ogni scelta trovi il "
                + "contrasto che ne esce, e un avviso quando scende sotto la "
                + "soglia in cui un testo piccolo si legge senza sforzo."
              : "Each colour here overrides the value that would have been "
                + "derived. Those derivations were measured: under each choice "
                + "you get the resulting contrast, and a warning when it drops "
                + "below what small text needs."

        Repeater {
            model: [
                { "nome": "base",     "it": "Il fondo",
                  "en": "The background",
                  "itd": "La tinta del vetro: la usano finestre, pannelli e barra",
                  "end": "The tint of the glass: windows, panels and bar all use it" },
                { "nome": "testo",    "it": "I caratteri",
                  "en": "The text",
                  "itd": "Anche le due gradazioni più smorzate escono da qui",
                  "end": "The two dimmer grades derive from this one" },
                { "nome": "membrana", "it": "Barra e pannelli",
                  "en": "Bar and panels",
                  "itd": "La superficie continua. La trasparenza resta la sua",
                  "end": "The continuous surface. Transparency stays its own" },
                { "nome": "bordo",    "it": "I contorni",
                  "en": "The outlines",
                  "itd": "Il filo che fa cogliere la curvatura delle superfici",
                  "end": "The hairline that makes the curvature readable" },
                { "nome": "positivo", "it": "Va bene",
                  "en": "All good",
                  "itd": "Connesso, carico, riuscito",
                  "end": "Connected, charged, succeeded" },
                { "nome": "avviso",   "it": "Attenzione",
                  "en": "Careful",
                  "itd": "Batteria bassa, spazio che finisce",
                  "end": "Low battery, running out of room" },
                { "nome": "pericolo", "it": "Pericolo",
                  "en": "Danger",
                  "itd": "Cancella, chiudi senza salvare, disconnetti",
                  "end": "Delete, close without saving, disconnect" }
            ]

            delegate: Column {
                id: riga
                required property var modelData

                width: parent.width
                spacing: Theme.Effects.space2

                readonly property string nome: riga.modelData.nome
                readonly property string messo:
                    String(page.scavalca[riga.nome] || "")
                readonly property bool aperto: page.coloreAperto === riga.nome

                /// Il colore che si vede adesso, scavalcato o derivato. Si
                /// chiede alla tavolozza invece di rifare il conto: rifarlo
                /// qui vorrebbe dire una seconda verità, e il quadratino
                /// mostrerebbe un colore che sullo schermo non c'è.
                readonly property color ora: {
                    switch (riga.nome) {
                    case "base":     return Theme.Colors.base;
                    case "testo":    return Theme.Colors.text;
                    case "membrana": return Theme.Colors.membrane;
                    case "bordo":    return Theme.Colors.edge;
                    case "positivo": return Theme.Colors.positive;
                    case "avviso":   return Theme.Colors.warning;
                    }
                    return Theme.Colors.danger;
                }

                S.SettingRow {
                    width: parent.width
                    label: page.it ? riga.modelData.it : riga.modelData.en
                    description: page.it ? riga.modelData.itd
                                         : riga.modelData.end
                    controlWidth: 108

                    control: Row {
                        spacing: Theme.Effects.space2

                        // Il quadratino: si apre e si chiude.
                        Rectangle {
                            width: 44; height: 30
                            radius: Theme.Effects.radiusXS
                            color: riga.ora
                            border.width: riga.aperto ? 2 : 1
                            border.color: riga.aperto ? Theme.Colors.accent
                                                      : Theme.Colors.edge

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.coloreAperto =
                                    riga.aperto ? "" : riga.nome
                            }
                        }

                        // ── E il modo di tornare indietro ────────────
                        //
                        // Sta accanto alla scelta e non solo in fondo alla
                        // pagina: chi ha appena sbagliato un colore vuole
                        // disfare QUELLO, non tutto.
                        Rectangle {
                            width: 30; height: 30
                            radius: Theme.Effects.radiusXS
                            visible: riga.messo !== ""
                            color: rimettiMouse.containsMouse
                                   ? Theme.Colors.hover : "transparent"
                            border.width: 1
                            border.color: Theme.Colors.edge

                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                name: "close"
                                color: Theme.Colors.textMuted
                                thickness: 2.0
                                alwaysDrawn: true
                            }

                            MouseArea {
                                id: rimettiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.togliColore(riga.nome)
                            }
                        }
                    }
                }

                S.SelettoreColore {
                    width: parent.width
                    visible: riga.aperto
                    valore: riga.ora
                    onScelto: function(c) {
                        page.mettiColore(riga.nome, c.toString());
                    }
                }

                // ── Il contrasto, mentre lo si sceglie ───────────────
                //
                // Non dopo, e non in una nota: qui, sotto il quadrato aperto,
                // col numero. È il conto che ha già corretto due volte questa
                // tavolozza a colpi di misura, e lasciarlo fuori vorrebbe dire
                // rifare a occhio proprio ciò che era stato tolto dall'occhio.
                Text {
                    width: parent.width
                    visible: riga.aperto
                             && (riga.nome === "testo" || riga.nome === "base"
                                 || riga.nome === "membrana")
                    wrapMode: Text.WordWrap
                    text: {
                        var r = Theme.Colors.contrasto(Theme.Colors.text,
                                                       Theme.Colors.membrane);
                        var n = Math.round(r * 10) / 10;
                        if (r >= 4.5)
                            return page.it
                                ? "Testo sui pannelli: contrasto " + n
                                  + ":1 — si legge."
                                : "Text on panels: contrast " + n
                                  + ":1 — readable.";
                        return page.it
                            ? "⚠ Testo sui pannelli: contrasto " + n + ":1. "
                              + "Sotto 4,5 un testo piccolo non si legge senza "
                              + "sforzo. Puoi tenerlo lo stesso."
                            : "⚠ Text on panels: contrast " + n + ":1. "
                              + "Below 4.5 small text is hard to read. You can "
                              + "keep it anyway.";
                    }
                    color: Theme.Colors.contrasto(Theme.Colors.text,
                                                  Theme.Colors.membrane) >= 4.5
                           ? Theme.Colors.textFaint : Theme.Colors.warning
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }

        // ── La via d'uscita, che non si può perdere ──────────────────────
        //
        // Si disegna con i colori DI FABBRICA e non con quelli scelti: se si
        // vestisse come il resto, la prima cosa a sparire dietro una
        // combinazione illeggibile sarebbe proprio il modo di uscirne.
        Rectangle {
            width: 220
            height: 34
            radius: Theme.Effects.radiusSM
            visible: Object.keys(page.scavalca).length > 0
            color: rimettiTuttoMouse.containsMouse ? "#2A2F3A" : "#1B1F27"
            border.width: 1
            border.color: "#4A5162"

            Text {
                anchors.centerIn: parent
                text: page.it ? "Rimetti tutti i colori a posto"
                              : "Reset every colour"
                color: "#EEF4FF"
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }

            MouseArea {
                id: rimettiTuttoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Core.Ipc.setSetting("shell.scavalca", ({}));
                    page.coloreAperto = "";
                }
            }
        }
    }

    // ── Icone ────────────────────────────────────────────────────────────
    //
    // Le icone di Minerva sono disegnate da noi: tratto sottile, luminoso,
    // tutte con lo stesso peso. È una scelta di stile, e come tutte le scelte
    // di stile non va bene a tutti — a qualcuno quel tratto sembra freddo, e
    // preferisce le icone che ha già visto per anni. Non c'è ragione di
    // imporre le nostre: qui si sceglie.
    //
    // Il ripiego non è un dettaglio da mettere in una nota a piè di pagina, ed
    // è per questo che c'è scritto nel riquadro: nessun tema di icone copre
    // tutti i nomi che usiamo, e le icone che mancano restano disegnate. Chi
    // non lo sa pensa che il tema si sia installato a metà.

    Card {
        heading: page.it ? "Icone" : "Icons"
        note: page.it
            ? "Le icone che un tema non ha restano disegnate da Minerva: nessun "
              + "tema copre tutto, e un'icona fuori stile si guarda meglio di un buco."
            : "Icons a theme does not provide stay drawn by Minerva: no theme covers "
              + "everything, and an icon in the wrong style beats an empty space."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Come sono disegnate" : "How they are drawn"
            description: page.it
                ? "Le nostre, a tratto sottile, oppure quelle del tema installato sul computer"
                : "Ours, thin-stroked, or those of the icon theme installed on this computer"
            controlWidth: 260

            control: S.ChoicePicker {
                value: Core.Ipc.get("icons.style", "minerva")
                options: [
                    { "value": "minerva",   "label": page.it ? "Minerva"   : "Minerva" },
                    { "value": "classiche", "label": page.it ? "Classiche" : "Classic" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("icons.style", v); }
            }
        }

        // ── Quanto copre il tema scelto ──────────────────────────────────
        //
        // «Ci sono icone che non si trovano» è una sensazione finché non c'è
        // un numero. Il demone lo sa già — lo scrive nel registro a ogni
        // risoluzione — e da qui in poi lo dice anche a chi guarda.
        Item {
            width: parent.width
            visible: Core.Ipc.get("icons.style", "minerva") !== "minerva"
                     && Core.Ipc.iconChieste > 0
            height: visible ? copertura.implicitHeight + Theme.Effects.space2 : 0

            Text {
                id: copertura
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
                text: {
                    var tot = Core.Ipc.iconChieste;
                    var mancano = Core.Ipc.iconMancanti || [];
                    var ha = tot - mancano.length;
                    var tema = Core.Ipc.iconTheme || "?";
                    if (mancano.length === 0)
                        return page.it
                            ? "Con «" + tema + "» tutte e " + tot + " le icone vengono dal tema."
                            : "With “" + tema + "” all " + tot + " icons come from the theme.";
                    return (page.it
                        ? "Con «" + tema + "», " + ha + " icone su " + tot
                          + " vengono dal tema. Queste " + mancano.length
                          + " il tema non le ha, e restano disegnate da Minerva: "
                        : "With “" + tema + "”, " + ha + " icons out of " + tot
                          + " come from the theme. The theme does not have these "
                          + mancano.length + ", so Minerva keeps drawing them: ")
                        + mancano.join(", ") + ".";
                }
            }
        }

        // L'elenco dei temi si chiede una volta sola, aprendo la pagina: è
        // una lettura del disco, e i temi non si installano da soli mentre
        // si guardano le impostazioni.
        Component.onCompleted: Core.Ipc.requestIconThemes()

        Connections {
            target: Core.Ipc
            // Se il demone non era ancora in piedi quando la pagina si è
            // aperta, la richiesta di prima è andata persa. Senza questo, la
            // scelta del tema resta una riga vuota fino alla riapertura.
            function onConnectedChanged() {
                if (Core.Ipc.connected) Core.Ipc.requestIconThemes();
            }
        }

        Item {
            width: parent.width
            height: themeFlow.implicitHeight + themeLabel.implicitHeight + 10
            // Scegliere il tema mentre le icone sono le nostre non cambierebbe
            // niente sullo schermo, e una scelta che non fa niente è peggio di
            // una scelta assente.
            visible: Core.Ipc.get("icons.style", "minerva") !== "minerva"

            Text {
                id: themeLabel
                width: parent.width
                text: page.it ? "Da quale tema" : "From which theme"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightMedium
            }

            // Un `Flow` e non una tendina: i temi installati sono pochi, e
            // vederli tutti insieme vuol dire poterli provare uno dietro
            // l'altro guardando la barra dietro questa finestra cambiare.
            // Una tendina obbligherebbe a un clic in più per ogni prova.
            Flow {
                id: themeFlow
                anchors.top: themeLabel.bottom
                anchors.topMargin: 10
                width: parent.width
                spacing: 6

                Repeater {
                    // La prima voce non è un tema: è «quello che ho già
                    // scelto altrove». Salvata come stringa vuota, così se
                    // domani si cambia tema da qualche altra parte Minerva
                    // segue senza che nessuno debba tornare qui.
                    model: [""].concat(Core.Ipc.iconThemes)

                    delegate: Rectangle {
                        id: themeChip
                        required property var modelData

                        readonly property bool isAuto: themeChip.modelData === ""
                        // Si confronta con la famiglia che il demone dice di
                        // aver preso, non con il nome salvato: nelle
                        // impostazioni può esserci ancora una variante
                        // («Colloid-Light») scritta quando l'elenco le
                        // mostrava, e nessuna voce si accenderebbe.
                        readonly property bool selected:
                            Core.Ipc.iconChosen === themeChip.modelData

                        implicitWidth: chipLabel.implicitWidth + 24
                        height: 30
                        radius: Theme.Effects.radiusSM

                        color: themeChip.selected ? Qt.alpha(Theme.Colors.accent, 0.18)
                                                  : (chipArea.containsMouse ? Theme.Colors.hover
                                                                            : Theme.Colors.raised)
                        border.width: 1
                        border.color: themeChip.selected ? Theme.Colors.accent
                                                         : Theme.Colors.edge

                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: themeChip.isAuto
                                  ? (page.it ? "Come il sistema" : "Follow the system")
                                  : themeChip.modelData
                            color: themeChip.selected ? Theme.Colors.accent
                                                      : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightMedium
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Core.Ipc.setSetting("icons.theme",
                                                           themeChip.modelData)
                        }
                    }
                }
            }
        }
    }

    // ── Qui c'era la dock, e adesso ha una pagina sua ────────────────────
    //
    // Sette voci — mostra, si nasconde, dimensione, ingrandimento, estensione,
    // trasparenza, nome al passaggio — dentro una pagina da milleseicento
    // righe. C'erano tutte, e Giacomo dopo settimane d'uso ha scritto: «la
    // dock ancora non si nasconde da sola e non ci sono impostazioni per
    // essa». Nel suo file `dock.autoHide` era `false`: era spenta, non rotta.
    //
    // Un'opzione che non si trova è un'opzione che non esiste, e questo non è
    // un difetto di chi guarda. Le voci si sono spostate in
    // `sections/Dock.qml`, che nell'elenco di sinistra ha il suo nome.
    //
    // NON si lascia una copia qui: due posti per la stessa impostazione sono
    // due posti che divergono, ed è un difetto che questo progetto ha già
    // pagato più di una volta.

    Card {
        heading: page.it ? "Finestre" : "Windows"

        // ── I programmi che si disegnano la barra da soli ─────────────────
        //
        // `windows.csdApps` esisteva dal primo giorno, la legge il compositore
        // e decide chi tiene la propria barra del titolo invece della nostra
        // — i browser, Thunderbird, i programmi GNOME. E in `main.c:521` c'è
        // scritto per iscritto che è «modificabile dal pannello Impostazioni».
        //
        // Non lo era. Il compositore dichiarava una cosa che non esisteva, ed
        // è il difetto peggiore della famiglia: non una funzione mancante, ma
        // una promessa scritta.
        //
        // Si scrive per NOME del programma — quello che appare nella classe
        // della finestra — e basta un pezzo del nome: «firefox» prende anche
        // «firefox-esr». Uno spazio dentro spezzerebbe la riga che va al
        // compositore in due nomi, e per questo si rifiuta.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Programmi con la barra loro"
                           : "Programs with their own title bar"
            description: page.it
                ? "Chrome, Firefox e gli altri disegnano già i propri pulsanti: "
                  + "dare loro anche la nostra barra vorrebbe dire due barre "
                  + "una sopra l'altra"
                : "Chrome, Firefox and the others already draw their own "
                  + "buttons: giving them our bar too would mean two bars"
            controlWidth: 0
        }

        Item {
            width: parent.width
            height: csdFlow.implicitHeight + 40

            Flow {
                id: csdFlow
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: Core.Ipc.get("windows.csdApps", [])
                    delegate: Rectangle {
                        required property var modelData
                        height: 28
                        width: nome.implicitWidth + croce.width
                               + Theme.Effects.space4
                        radius: Theme.Effects.radiusFull
                        color: Theme.Colors.raised
                        border.width: 1
                        border.color: Theme.Colors.edge

                        Text {
                            id: nome
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(parent.modelData)
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        // La crocetta è un testo e non un tracciato: col
                        // renderer software una `Shape` dentro una lista
                        // deposita copie di sé sopra il resto. Vedi
                        // `minerva-residui-software`.
                        Text {
                            id: croce
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space2
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✕"
                            color: viaMouse.containsMouse
                                   ? Theme.Colors.danger : Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: viaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.csdTogli(String(parent.modelData))
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 34
                anchors.bottom: parent.bottom

                Ui.Campo {
                    id: csdNuovo
                    anchors.fill: parent
                    segnaposto: page.it
                        ? "Aggiungi un programma (per esempio: thunderbird)"
                        : "Add a program (for example: thunderbird)"
                    onAccettato: {
                        page.csdAggiungi(csdNuovo.text);
                        csdNuovo.text = "";
                    }
                }
            }
        }

        // ── Il colore intorno ────────────────────────────────────────────
        //
        // Giacomo, 3 settembre 2026: «se voglio che il colore intorno diventi
        // tipo rgb e cambi colore costantemente oppure che giri sempre come
        // una striscia led?».
        //
        // Non c'è niente di nuovo da disegnare: attorno a ogni finestra c'è
        // già un anello di sei pixel — quello con cui la si prende per
        // ridimensionarla — ed era trasparente.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Il colore intorno alla finestra attiva"
                           : "The colour around the active window"
            description: page.it
                ? "Solo intorno a quella attiva: un arcobaleno attorno a otto finestre insieme non è un effetto"
                : "Only around the active one: a rainbow around eight windows at once is not an effect"
            controlWidth: 340
            control: S.ChoicePicker {
                value: Core.Ipc.get("windows.cornice", "spento")
                options: [
                    { "value": "spento", "label": page.it ? "Niente" : "None" },
                    { "value": "fisso",  "label": page.it ? "L'accento"
                                                          : "The accent" },
                    { "value": "gira",   "label": page.it ? "Gira" : "Cycles" },
                    { "value": "striscia", "label": page.it ? "Striscia LED"
                                                            : "LED strip" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("windows.cornice", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: page._corniceGira
            label: page.it ? "Quanto ci mette a fare il giro"
                           : "How long a full cycle takes"
            description: page.it
                ? "Sotto i due secondi non è un colore che gira, è un lampeggio, e il compositore lo rifiuta"
                : "Under two seconds it is not a cycle but a flicker, and the compositor refuses it"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 2
                to: 120
                // «secondi» non è un'unità di `ValueSlider`: cadeva nel caso
                // di ripiego e otto secondi si leggevano «800%». Il nome
                // dell'unità è un termine fisso — è il suffisso che si
                // traduce.
                unit: "intero"
                suffix: page.it ? "s" : "s"
                value: Core.Ipc.get("windows.cornicePeriodo", 8000) / 1000
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.cornicePeriodo",
                                        Math.round(v) * 1000);
                }
            }
        }

        // ── Lo spessore ──────────────────────────────────────────────────
        //
        // Giacomo, 9 settembre 2026: «voglio poter regolare lo spessore del
        // colore intorno alla finestra attiva».
        //
        // Era sei pixel fissi, e non per scelta: era lo STESSO numero della
        // presa per ridimensionare, che è una misura per le dita. Adesso sono
        // due cose, e la presa segue il più grande dei due — un bordo che si
        // vede e non si afferra sarebbe peggio di uno che non si vede.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("windows.cornice", "spento") !== "spento"
            label: page.it ? "Quanto è spesso" : "How thick"
            description: page.it
                ? "Sopra i venti pixel non è più un bordo, ed è anche una "
                  + "banda in cui il clic non arriva più al programma"
                : "Over twenty pixels it stops being a border"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 1
                to: 20
                unit: "pixel"
                value: Core.Ipc.get("windows.corniceSpessore", 6)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.corniceSpessore",
                                        Math.round(v));
                }
            }
        }

        // ── Anche attorno a quelle che non hanno il fuoco ────────────────
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("windows.cornice", "spento") !== "spento"
            label: page.it ? "Anche attorno alle altre finestre"
                           : "Around the other windows too"
            description: page.it
                ? "Il bordo serve a dire QUALE finestra risponde alla "
                  + "tastiera: acceso su tutte, smette di dirlo. Con una "
                  + "velatura bassa diventa il contorno di ognuna."
                : "The border says which window has the keyboard: on all of "
                  + "them, it stops saying it."
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0
                to: 0.60
                value: Core.Ipc.get("windows.corniceSpente", 0)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.corniceSpente",
                                        Math.round(v * 100) / 100);
                }
            }
        }

        // ── I colori che si alternano ────────────────────────────────────
        //
        // Vuoto è lo SPETTRO intero — l'arcobaleno di sempre — e resta il
        // ripiego: chi non sceglie niente lo vede. Da un colore in su, il giro
        // passa per quelli e per nessun altro; con uno solo si ottiene una
        // striscia di un colore che scorre, che è una cosa che si può volere.
        S.SettingRow {
            width: parent.width
            visible: page._corniceGira
            label: page.it ? "I colori che si alternano"
                           : "The colours that take turns"
            description: page.it
                ? "Nessuno scelto: l'arcobaleno intero"
                : "None chosen: the whole spectrum"
            controlWidth: 0
        }

        Item {
            width: parent.width
            visible: page._corniceGira
            height: tinteFlow.implicitHeight + 12

            Flow {
                id: tinteFlow
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: Core.Ipc.get("windows.corniceTinte", [])
                    delegate: Rectangle {
                        required property var modelData
                        width: 54
                        height: 28
                        radius: Theme.Effects.radiusFull
                        color: String(parent.modelData)
                        border.width: 1
                        border.color: Theme.Colors.edge

                        // La crocetta è un testo e non un tracciato: col
                        // renderer software una `Shape` dentro una lista
                        // deposita copie di sé sopra il resto.
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: viaTinta.containsMouse
                                   ? Theme.Colors._bianco : "transparent"
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: viaTinta
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.tintaTogli(String(parent.modelData))
                        }
                    }
                }

                // Otto pasticche pronte, e l'accento in cima: scegliere un
                // colore qualunque vuole il selettore, e il selettore vuole
                // una finestra sua. Otto colori che stanno bene insieme sono
                // la risposta giusta per il novanta per cento di chi vuole
                // «i miei colori invece dell'arcobaleno».
                Repeater {
                    model: page.tinteProposte
                    delegate: Rectangle {
                        required property var modelData
                        width: 28
                        height: 28
                        radius: Theme.Effects.radiusFull
                        color: String(modelData)
                        opacity: 0.55
                        border.width: 1
                        border.color: Theme.Colors.edge

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.tintaAggiungi(String(parent.modelData))
                        }
                    }
                }
            }
        }

        // ── Un attrezzo da officina, e si può riporre ────────────────────
        //
        // Giacomo, 2 settembre 2026: «mettiamo un tasto disattivabile accanto
        // al meteo dove posso riavviare la shell».
        //
        // Sta fra le voci della barra e non fra quelle degli sviluppatori
        // perché è una cosa che si VEDE: chi lo spegne lo spegne perché non
        // vuole quel simbolo lì, non perché ha smesso di sviluppare.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Tasto «ricarica» nella barra"
                           : "«Reload» button in the bar"
            description: page.it
                ? "Accanto al meteo. Rilegge la scrivania restando viva: la barra non sparisce"
                : "Next to the weather. Re-reads the desktop while staying alive: the bar never disappears"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("shell.tastoRiavvio", true)
                onToggled: function(v) { Core.Ipc.setSetting("shell.tastoRiavvio", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Barra del titolo su ogni finestra"
                           : "A title bar on every window"
            description: page.it
                ? "Nome, icona e i tre pulsanti sopra ogni finestra. Serve anche per spostarle e agganciarle ai bordi"
                : "Name, icon and the three buttons above every window. Also how you move and snap them"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("windows.titleBars", true)
                onToggled: function(v) { Core.Ipc.setSetting("windows.titleBars", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Altezza della barra del titolo" : "Title bar height"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 26
                to: 46
                unit: "pixel"
                value: Core.Ipc.get("windows.titleHeight", 34)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.titleHeight", Math.round(v));
                }
            }
        }

        // ── Da che parte stanno i pulsanti ───────────────────────────────
        //
        // Qui c'era la scelta fra finestre affiancate e libere. Non c'è più:
        // in Minerva le finestre sono libere e basta. Il perché sta in
        // `core/WindowRules.qml`, e in breve è che una finestra poteva
        // diventare libera in cinque modi che non si conoscevano fra loro.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Pulsanti della finestra"
                           : "Window buttons"
            description: page.it
                ? "Riduci, ingrandisci, schermo intero e chiudi: a destra come "
                  + "su Windows, a sinistra come su macOS"
                : "Minimise, maximise, full screen and close: on the right like "
                  + "Windows, on the left like macOS"
            controlWidth: 300

            control: S.ChoicePicker {
                value: Core.Ipc.get("windows.buttonsSide", "destra")
                options: [
                    { "value": "destra",   "label": page.it ? "A destra"   : "Right" },
                    { "value": "sinistra", "label": page.it ? "A sinistra" : "Left" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("windows.buttonsSide", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "A schermo intero" : "In fullscreen"
            description: page.it
                ? "A schermo intero il compositore copre tutto: questa barra è l'unico modo di tornare indietro col mouse"
                : "In fullscreen the compositor covers everything: this bar is the only way back with the mouse"
            controlWidth: 320
            control: S.ChoicePicker {
                value: Core.Ipc.get("windows.fullscreenBar", "hover")
                options: [
                    { "value": "hover",
                      "label": page.it ? "Compare in cima" : "Appears at the top" },
                    { "value": "always",
                      "label": page.it ? "Sempre visibile" : "Always visible" },
                    { "value": "off",
                      "label": page.it ? "Mai" : "Never" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("windows.fullscreenBar", v); }
            }
        }
    }

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
}
