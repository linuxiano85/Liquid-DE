import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import "../../menu"

// AppsPanel — Il menu delle applicazioni.
//
// Struttura: ricerca in alto, categorie a sinistra, elenco a destra.
//
// Le app sono una LISTA, non una griglia di riquadri. È una scelta contro
// corrente e vale la pena spiegarla: in una griglia il nome sta sotto
// un'icona minuscola, va a capo, viene troncato, e per trovare qualcosa si
// legge a zigzag. In una lista i nomi sono incolonnati e si scorrono con un
// solo movimento dell'occhio. Le icone restano, grandi abbastanza da
// riconoscerle, ma il testo comanda.
//
// Si scrive per cercare senza dover prima cliccare nel campo: qualunque tasto
// premuto va nella ricerca.
Item {
    id: panel

    property var spine: null

    /// La categoria con cui il menu si apre. Chi tiene i preferiti vuoti e
    /// cerca sempre fra tutte non deve fare un clic in più ogni volta.
    property string category: Core.Ipc.get("launcher.startCategory", "favorites")
    property string query: ""
    property int selectedIndex: 0

    /// La lingua scende quanto serve al più alto fra la colonna delle
    /// categorie e l'elenco. Il registro della Spine impone comunque un tetto,
    /// oltre il quale l'elenco scorre.
    readonly property real implicitPanelHeight:
        Theme.Effects.space5 + searchBox.height + Theme.Effects.space3
        + Math.max(categoryColumn.implicitHeight, list.contentHeight)
        + Theme.Effects.space4

    /// Tutte le categorie che il menu sa fare. Quelle che si vedono davvero
    /// sono in `categories`, che toglie le nascoste dalle impostazioni.
    readonly property var allCategories: [
        { "id": "favorites",   "icon": "star",     "it": "Preferiti",  "en": "Favourites" },
        { "id": "all",         "icon": "apps",     "it": "Tutte",      "en": "All" },
        { "id": "internet",    "icon": "globe",    "it": "Internet",   "en": "Internet" },
        { "id": "development", "icon": "terminal", "it": "Sviluppo",   "en": "Development" },
        { "id": "office",      "icon": "document", "it": "Ufficio",    "en": "Office" },
        { "id": "graphics",    "icon": "image",    "it": "Grafica",    "en": "Graphics" },
        { "id": "media",       "icon": "music",    "it": "Multimedia", "en": "Media" },
        { "id": "games",       "icon": "gamepad",  "it": "Giochi",     "en": "Games" },
        { "id": "system",      "icon": "cpu",      "it": "Sistema",    "en": "System" },
        { "id": "utility",     "icon": "wrench",   "it": "Utility",    "en": "Utility" }
    ]

    /// Le categorie che si vedono. Chi non usa «Giochi» o «Grafica» se le
    /// toglie dalle Impostazioni invece di scorrerle tutti i giorni.
    ///
    /// «Preferiti» e «Tutte» non si possono nascondere: sono le due vie
    /// d'uscita se ci si nasconde per sbaglio la categoria in cui si stava.
    readonly property var hiddenCategories: Core.Ipc.get("launcher.hiddenCategories", [])

    readonly property var categories: {
        var fuori = [];
        for (var i = 0; i < panel.allCategories.length; i++) {
            var c = panel.allCategories[i];
            if (c.id !== "favorites" && c.id !== "all"
                && panel.hiddenCategories.indexOf(c.id) !== -1)
                continue;
            fuori.push(c);
        }
        return fuori;
    }

    /// Con la rotellina si passa da una categoria all'altra. È il gesto che
    /// costa meno di tutti — la mano è già sul mouse — e trasforma la colonna
    /// di sinistra da elenco da mirare in qualcosa che si sfoglia.
    readonly property bool wheelCategories: Core.Ipc.get("launcher.wheelCategories", true)

    /// Passando sopra una categoria la si apre, senza cliccare. Un menu si
    /// esplora, e chiedere un clic per ogni sguardo è una tassa su ogni
    /// apertura.
    readonly property bool hoverCategories: Core.Ipc.get("launcher.hoverCategories", true)

    /// Quale categoria il puntatore sta sfiorando, e da quanto.
    ///
    /// ── Perché una pausa, e non subito ───────────────────────────────────
    ///
    /// Perché il puntatore ATTRAVERSA la colonna per arrivare all'elenco, e
    /// senza pausa aprirebbe tre categorie per strada — con l'elenco che
    /// cambia sotto gli occhi mentre si sta puntando un programma. Un quinto
    /// di secondo distingue «sto guardando questa» da «sto passando di qui».
    property string categoriaSfiorata: ""

    Timer {
        id: attesaSfioro
        interval: 200
        onTriggered: {
            if (panel.categoriaSfiorata !== "" && panel.query === "")
                panel.category = panel.categoriaSfiorata;
        }
    }

    function sfiora(id) {
        if (!panel.hoverCategories) {
            attesaSfioro.stop();
            return;
        }
        panel.categoriaSfiorata = id;
        if (id === "")
            attesaSfioro.stop();
        else
            attesaSfioro.restart();
    }

    /// Quanto movimento di rotellina si è accumulato senza ancora aver
    /// cambiato categoria.
    ///
    /// ── Perché serve accumulare ──────────────────────────────────────────
    ///
    /// Uno scatto di rotellina non è un evento: è una raffica. Un mouse ne
    /// manda parecchi per ogni tacca, e un touchpad ne manda decine per un
    /// dito che scorre di un centimetro. Cambiando categoria a ogni evento si
    /// attraversa tutto il menu con un movimento minimo — Giacomo, 2 agosto:
    /// «la rotellina cambia troppo rapidamente e non si capisce perché».
    ///
    /// Centoventi è quanto vale una tacca per convenzione (`QWheelEvent`), e
    /// il resto si tiene da parte: così un touchpad che manda tanti pezzetti
    /// piccoli avanza di una categoria quando i pezzetti fanno una tacca, non
    /// a ogni pezzetto.
    property real wheelAccum: 0

    function wheelStep(delta) {
        if (!panel.wheelCategories || panel.query !== "" || delta === 0)
            return;

        // Cambiando verso si riparte da zero: il residuo di prima spingeva
        // dalla parte opposta, e tenerlo farebbe scattare subito indietro.
        if ((delta > 0) !== (panel.wheelAccum > 0))
            panel.wheelAccum = 0;

        panel.wheelAccum += delta;

        while (Math.abs(panel.wheelAccum) >= 120) {
            panel.stepCategory(panel.wheelAccum < 0);
            panel.wheelAccum += (panel.wheelAccum < 0 ? 120 : -120);
        }
    }

    function stepCategory(avanti) {
        if (!panel.wheelCategories || panel.query !== "")
            return;
        var elenco = panel.categories;
        var i = 0;
        for (var k = 0; k < elenco.length; k++)
            if (elenco[k].id === panel.category) { i = k; break; }
        // Ci si ferma agli estremi invece di ricominciare da capo: girando in
        // tondo non si capisce più quando si è arrivati in fondo.
        var nuovo = Math.max(0, Math.min(elenco.length - 1, i + (avanti ? 1 : -1)));
        if (elenco[nuovo].id !== panel.category)
            panel.category = elenco[nuovo].id;
    }

    /// Quali categorie freedesktop confluiscono in ciascuna voce del menu.
    readonly property var categoryMap: ({
        "internet":    ["Network", "WebBrowser", "Email", "InstantMessaging"],
        "development": ["Development", "IDE", "TextEditor"],
        "office":      ["Office", "WordProcessor", "Spreadsheet"],
        "graphics":    ["Graphics", "Photography", "2DGraphics"],
        "media":       ["AudioVideo", "Audio", "Video", "Player"],
        "games":       ["Game"],
        "system":      ["System", "Settings", "Monitor"],
        "utility":     ["Utility", "Accessories", "FileTools"]
    })

    property var favouriteIds: []
    property var results: []

    /// L'elenco completo, ordinato UNA VOLTA e con il nome già in minuscolo.
    ///
    /// Ordinare vuol dire chiamare `localeCompare`, che passa da ICU per
    /// sapere che «à» va vicino ad «a»: giusto, ma caro. Su duecento
    /// applicazioni sono più di millecinquecento confronti, e prima si
    /// rifacevano **a ogni battuta di tasto nella ricerca** — cioè proprio
    /// mentre si sta scrivendo, che è l'unico momento in cui l'inceppo si
    /// sente. Qui si paga una volta, quando il demone manda l'elenco.
    ///
    /// Ogni voce è `{ app, nome }`: anche `toLowerCase()` su duecento nomi a
    /// ogni tasto era lavoro rifatto per niente.
    property var ordinati: []

    function riordina() {
        var all = Core.Ipc.allApps || [];
        var v = [];
        for (var i = 0; i < all.length; i++)
            v.push({ "app": all[i], "nome": (all[i].name || "").toLowerCase() });
        v.sort(function(a, b) { return a.nome.localeCompare(b.nome); });
        panel.ordinati = v;
        panel.rebuild();
    }

    Component.onCompleted: {
        Core.Ipc.requestAllApps();
        Core.Ipc.searchApps("");
        riordina();
        searchField.forceActiveFocus();
    }

    Connections {
        target: Core.Ipc
        function onAllAppsReceived() { panel.riordina(); }
        function onMatrixNodesReceived(fixed) {
            var ids = [];
            for (var i = 0; i < fixed.length; i++)
                ids.push(fixed[i].appId);
            panel.favouriteIds = ids;
            panel.rebuild();
        }
    }

    onCategoryChanged: { selectedIndex = 0; rebuild(); }
    onQueryChanged: { selectedIndex = 0; rebuild(); }

    function matchesCategory(app) {
        if (panel.category === "all")
            return true;
        if (panel.category === "favorites")
            return panel.favouriteIds.indexOf(app.appId) !== -1;

        var wanted = panel.categoryMap[panel.category] || [];
        var have = app.categories || [];
        for (var i = 0; i < wanted.length; i++)
            if (have.indexOf(wanted[i]) !== -1)
                return true;
        return false;
    }

    /// Chi si vede adesso. **Non ordina niente**: filtra e basta.
    ///
    /// Può permetterselo perché `ordinati` è già in ordine alfabetico, e un
    /// sottoinsieme di una cosa ordinata resta ordinato. Cercando servono due
    /// gruppi — chi COMINCIA con quello che hai scritto prima di chi lo
    /// contiene a metà, che è quasi sempre quello che si cerca — e si
    /// ottengono riempiendo due secchi in un giro solo e attaccandoli:
    /// dentro ognuno l'ordine è già quello giusto.
    ///
    /// Da confronti `localeCompare` a n·log n per tasto, a un giro lineare di
    /// `indexOf`.
    function rebuild() {
        var v = panel.ordinati;
        var needle = panel.query.trim().toLowerCase();
        var out = [];

        if (needle === "") {
            for (var i = 0; i < v.length; i++)
                if (panel.matchesCategory(v[i].app))
                    out.push(v[i].app);
        } else {
            // Cercando, la categoria non conta: chi scrive «fire» vuole
            // Firefox, non «Firefox se è nella categoria giusta».
            var testa = [];
            var coda = [];
            for (var j = 0; j < v.length; j++) {
                var p = v[j].nome.indexOf(needle);
                if (p === 0)
                    testa.push(v[j].app);
                else if (p > 0)
                    coda.push(v[j].app);
            }
            out = testa.concat(coda);
        }

        panel.results = out;
    }

    /// Aggiunge o toglie dai preferiti. L'elenco vive nel demone, che lo
    /// conserva fra un accesso e l'altro; qui si manda solo quello nuovo.
    function toggleFavourite(appId) {
        if (!appId)
            return;
        var ids = panel.favouriteIds.slice();
        var i = ids.indexOf(appId);
        if (i === -1)
            ids.push(appId);
        else
            ids.splice(i, 1);
        panel.favouriteIds = ids;
        Core.Ipc.updateFixedApps(ids);
        panel.rebuild();
    }

    function isFavourite(appId) {
        return panel.favouriteIds.indexOf(appId) !== -1;
    }

    // ── Fissare nella dock ───────────────────────────────────────────────
    //
    // I preferiti e la dock sono due cose diverse e vanno tenute diverse. I
    // preferiti stanno in cima a QUESTO menu e servono a ritrovare un
    // programma fra i duecento installati. La dock sta sempre a schermo e
    // serve ad avviarlo senza aprire niente.
    //
    // Fin qui si poteva mettere una cosa fra i preferiti e non c'era modo di
    // fissarla nella dock se non trovandola già in esecuzione e usando il
    // tasto destro sulla sua icona — cioè si poteva fissare solo ciò che era
    // già aperto. Il posto giusto per dire «questo lo voglio sempre a portata»
    // è qui, dove i programmi si scelgono.

    readonly property var dockPinned: Core.Ipc.get("dock.pinned", [])

    function isPinned(appId) {
        return (panel.dockPinned || []).indexOf(appId) !== -1;
    }

    function togglePinned(appId) {
        if (!appId || appId === "")
            return;
        var list = (panel.dockPinned || []).slice();
        var at = list.indexOf(appId);
        if (at === -1)
            list.push(appId);
        else
            list.splice(at, 1);
        Core.Ipc.setSetting("dock.pinned", list);
    }

    /// Voci del menu di una applicazione. Ricostruite a ogni apertura perché
    /// cambiano a seconda di dove il programma si trova già.
    function appMenuItems(app) {
        var it = Core.Strings.lang === "it";
        var fav = panel.isFavourite(app.appId);
        var pin = panel.isPinned(app.appId);
        return [
            { "label": it ? "Avvia" : "Launch", "icon": "chevron", "action": "launch" },
            { "separator": true },
            { "label": pin ? (it ? "Togli dalla dock" : "Remove from the dock")
                           : (it ? "Fissa nella dock" : "Pin to the dock"),
              "icon": "pin", "action": "pin" },
            { "label": fav ? (it ? "Togli dai preferiti" : "Remove from favourites")
                           : (it ? "Aggiungi ai preferiti" : "Add to favourites"),
              "icon": "star", "action": "favourite" }
        ];
    }

    ContextMenu {
        id: appMenu

        /// Applicazione su cui si è aperto il menu.
        property var target: null

        onTriggered: function(action) {
            if (!appMenu.target)
                return;
            if (action === "launch") {
                Core.Ipc.launchApp(appMenu.target.exec, appMenu.target.appId);
                if (panel.spine)
                    panel.spine.close();
            } else if (action === "favourite") {
                panel.toggleFavourite(appMenu.target.appId);
            } else if (action === "pin") {
                panel.togglePinned(appMenu.target.appId);
            }
        }
    }

    function launch(index) {
        var app = panel.results[index];
        if (!app)
            return;
        Core.Ipc.launchApp(app.exec, app.appId);
        if (panel.spine)
            panel.spine.close();
    }

    function moveSelection(delta) {
        if (panel.results.length === 0)
            return;
        var next = panel.selectedIndex + delta;
        panel.selectedIndex = Math.max(0, Math.min(panel.results.length - 1, next));
        list.positionViewAtIndex(panel.selectedIndex, ListView.Contain);
    }

    // ── Ricerca ──────────────────────────────────────────────────────────

    Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space5
        height: 44
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        border.width: 1
        border.color: searchField.activeFocus ? Qt.alpha(Theme.Colors.accent, 0.55)
                                              : "transparent"
        Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }

        Ui.Icon {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            name: "search"
            color: searchField.activeFocus ? Theme.Colors.accent : Theme.Colors.textFaint
        }

        TextInput {
            id: searchField
            // Dichiarato, non solo chiesto all'avvio: dentro lo scope della
            // Spine questo è l'elemento che il fuoco deve trovare, anche se
            // il pannello viene costruito prima che la finestra abbia la
            // tastiera. La chiamata in `Component.onCompleted` resta perché
            // rimette il cursore qui quando il pannello si riapre.
            focus: true
            anchors.left: searchGlyph.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            clip: true

            color: Theme.Colors.text
            selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
            selectedTextColor: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeMD

            onTextChanged: panel.query = text

            Keys.onDownPressed: panel.moveSelection(1)
            Keys.onUpPressed: panel.moveSelection(-1)
            Keys.onReturnPressed: panel.launch(panel.selectedIndex)
            Keys.onEnterPressed: panel.launch(panel.selectedIndex)
            Keys.onEscapePressed: {
                if (text !== "")
                    text = "";
                else if (panel.spine)
                    panel.spine.close();
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.text === ""
                text: Core.Strings.lang === "it" ? "Scrivi per cercare…" : "Type to search…"
                color: Theme.Colors.textFaint
                font: searchField.font
            }
        }
    }

    // ── Categorie ────────────────────────────────────────────────────────

    Column {
        id: categoryColumn
        anchors.left: parent.left
        anchors.top: searchBox.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space3
        anchors.bottomMargin: Theme.Effects.space4
        width: 150
        spacing: 1

        // Durante una ricerca le categorie non filtrano più nulla: si
        // spengono invece di sparire, così il pannello non cambia forma.
        opacity: panel.query === "" ? 1 : 0.35
        enabled: panel.query === ""
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        Repeater {
            model: panel.categories

            delegate: Rectangle {
                id: cat
                required property var modelData

                readonly property bool current: panel.category === modelData.id

                width: parent.width
                height: 34
                radius: Theme.Effects.radiusXS
                color: current ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : catMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // Barretta di selezione a sinistra: dice quale voce è attiva
                // anche con la colonna spenta durante la ricerca.
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: cat.current ? 18 : 0
                    radius: 1.5
                    color: Theme.Colors.accent
                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.Motion.quick
                            easing.type: Easing.OutBack
                        }
                    }
                }

                Ui.Icon {
                    id: catIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: cat.modelData.icon
                    color: cat.current ? Theme.Colors.accent : Theme.Colors.textFaint
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                }

                Text {
                    anchors.left: catIcon.right
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: Core.Strings.lang === "it" ? cat.modelData.it : cat.modelData.en
                    color: cat.current ? Theme.Colors.text : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: cat.current ? Theme.Typography.weightSemiBold
                                             : Theme.Typography.weightMedium
                }

                MouseArea {
                    id: catMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Il clic non aspetta: chi ha già deciso non deve
                        // aspettare la pausa del passaggio.
                        attesaSfioro.stop();
                        panel.category = cat.modelData.id;
                    }

                    onEntered: panel.sfiora(cat.modelData.id)
                    onExited: {
                        if (panel.categoriaSfiorata === cat.modelData.id)
                            panel.sfiora("");
                    }

                    // La rotellina sfoglia le categorie. Sta su ogni voce e non
                    // su un'area sola sopra la colonna, perché un'area sopra
                    // ruberebbe il passaggio del puntatore alle voci e si
                    // spegnerebbe l'evidenziazione — lo stesso difetto che la
                    // dock aveva pagato con l'ingrandimento.
                    onWheel: function(w) {
                        panel.wheelStep(w.angleDelta.y);
                        w.accepted = true;
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.left: categoryColumn.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.top: categoryColumn.top
        anchors.bottom: categoryColumn.bottom
        width: 1
        color: Theme.Colors.edge
        opacity: 0.6
    }

    // ── Elenco applicazioni ──────────────────────────────────────────────

    Ui.Scorrimento {
        bersaglio: list
        anchors {
            right: list.right
            top: list.top
            bottom: list.bottom
        }
    }

    ListView {
        id: list
        anchors.left: categoryColumn.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.top: categoryColumn.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.Effects.space4
        clip: true
        spacing: 1
        model: panel.results
        currentIndex: panel.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

        // ── La rotellina sull'elenco ─────────────────────────────────────
        //
        // Se c'è da scorrere, scorre: è quello che chiunque si aspetta, e
        // rubarglielo per cambiare categoria sarebbe insopportabile.
        //
        // Ma quando l'elenco ci sta tutto — cioè in quasi tutte le categorie,
        // che hanno cinque o sei programmi — la rotellina non farebbe niente.
        // Lì passa alla categoria successiva, e il menu intero diventa una
        // cosa che si sfoglia senza mai mirare niente.
        WheelHandler {
            enabled: panel.wheelCategories && panel.query === ""
                     && list.contentHeight <= list.height + 1
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(w) {
                panel.wheelStep(w.angleDelta.y);
            }
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index

            readonly property bool current: index === panel.selectedIndex

            width: ListView.view.width
            height: 48
            radius: Theme.Effects.radiusSM
            color: current ? Qt.alpha(Theme.Colors.accent, 0.14)
                 : rowMouse.containsMouse ? Theme.Colors.hover
                 : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Image {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28
                source: row.modelData.icon ? "file://" + row.modelData.icon : ""
                sourceSize.width: 56
                sourceSize.height: 56
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }

            // Ripiego quando l'icona non si risolve: l'iniziale del nome in
            // un cerchio. Meglio di un riquadro vuoto, che sembra un errore.
            Rectangle {
                anchors.centerIn: appIcon
                width: 28; height: 28
                radius: 14
                visible: appIcon.status !== Image.Ready
                color: Theme.Colors.raisedHigh

                Text {
                    anchors.centerIn: parent
                    text: (row.modelData.name || "?").charAt(0).toUpperCase()
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightBold
                }
            }

            Text {
                anchors.left: appIcon.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: favStar.left
                anchors.rightMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: row.modelData.name || ""
                color: row.current ? Theme.Colors.text : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: row.current ? Theme.Typography.weightSemiBold
                                         : Theme.Typography.weightRegular
            }

            // Stellina dei preferiti: compare al passaggio, oppure resta
            // accesa se l'applicazione è già fra i preferiti. Il tasto destro
            // fa la stessa cosa dal menu — chi non scopre la stellina ci
            // arriva comunque.
            Rectangle {
                id: favStar
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                radius: 13
                visible: rowMouse.containsMouse || panel.isFavourite(row.modelData.appId)
                color: starMouse.containsMouse ? Theme.Colors.raisedHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 15; height: 15
                    name: "star"
                    filled: panel.isFavourite(row.modelData.appId)
                    color: panel.isFavourite(row.modelData.appId)
                           ? Theme.Colors.accentWarm : Theme.Colors.textFaint
                }

                MouseArea {
                    id: starMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.toggleFavourite(row.modelData.appId)
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // La stellina sta sopra: senza questo il clic su di lei
                // finirebbe qui sotto e lancerebbe l'applicazione.
                z: -1
                onEntered: panel.selectedIndex = row.index
                onClicked: function(m) {
                    panel.selectedIndex = row.index;
                    if (m.button === Qt.RightButton) {
                        appMenu.target = row.modelData;
                        var g = mapToGlobal(m.x, m.y);
                        appMenu.openAt(g.x, g.y, panel.appMenuItems(row.modelData));
                    } else {
                        panel.launch(row.index);
                    }
                }
            }
        }

        // Elenco vuoto
        Text {
            anchors.centerIn: parent
            visible: panel.results.length === 0
            width: parent.width - Theme.Effects.space6
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: panel.query !== ""
                  ? (Core.Strings.lang === "it" ? "Nessuna applicazione trovata"
                                                : "No application found")
                  : (Core.Strings.lang === "it" ? "Niente in questa categoria"
                                                : "Nothing in this category")
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeMD
        }
    }
}
