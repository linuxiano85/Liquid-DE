import QtQuick
import Quickshell
import "../core" as Core
import "../ui" as Ui

FocusScope {
    id: menu

    property bool searchOnly: false
    readonly property color mutedInk: searchOnly ? Style.muted : Style.startMuted
    property bool allApps: false
    property string searchCategory: "all"
    readonly property string layout: Core.Ipc.get("windows11.startLayout", "default")
    readonly property int pinnedRows: layout === "pinned" ? 4 : layout === "recommended" ? 2 : 3
    readonly property int pageSize: pinnedRows * 6
    readonly property int recommendedY: 78 + pinnedRows * 80
    readonly property var folderShortcuts: {
        var enabled = Core.Ipc.get("windows11.startFolders", []);
        return StartPlaces.entries.filter(function(entry) {
            return entry.available !== false && enabled.indexOf(entry.id) >= 0;
        });
    }
    onPageSizeChanged: page = Math.floor(selectedIndex / pageSize)
    property int page: 0
    property int selectedIndex: 0
    property var recent: []
    property var files: []
    property string recentId: "windows-recent-" + Date.now() + "-" + Math.random()
    property string searchId: ""
    property var contextApp: null

    /// Il menu piccolo aperto sopra un pulsante del piede: "power" sopra
    /// l'alimentazione, "account" sopra il nome. Vuoto: nessuno.
    ///
    /// In Windows 11 il pulsante di alimentazione apre lì, sopra di sé,
    /// Opzioni di accesso, Sospendi, Arresta il sistema e Riavvia il
    /// sistema, e un clic esegue. Qui si apriva un pannello separato sul
    /// lato destro dello schermo, con un secondo clic di conferma come in
    /// Liquid (il manutentore, 11 ottobre 2026: «deve essere identico a Windows»).
    property string piccolo: ""

    /// Una voce dei menu piccoli: si chiude il menu e si manda l'azione.
    function sceltaPiccolo(azione) {
        menu.piccolo = "";
        menu.actionRequested(azione);
    }
    readonly property string query: field.text.trim().toLowerCase()
    readonly property var pinned: Core.Ipc.get("launcher.fixedApps", [])
    readonly property var catalog: Core.Apps.all.slice().sort(function(a, b) {
        return a.name.localeCompare(b.name);
    })
    // I modelli restano separati durante l'uscita: Tutte le app non deve
    // sostituire i riquadri aggiunti mentre sono ancora visibili.
    readonly property var pinnedApps: pinned.map(function(id) {
        return Core.Apps.byId(id);
    }).filter(function(app) {
        return !!app;
    })
    readonly property var listApps: {
        if (searchOnly && searchCategory === "documents")
            return [];

        if (query !== "")
            return catalog.filter(function(a) {
            return (a.name + " " + (a.genericName || "") + " " + a.appId).toLowerCase().indexOf(query) >= 0;
        });

        return catalog;
    }
    readonly property bool listMode: searchOnly || allApps || query !== ""
    readonly property var apps: listMode ? listApps : pinnedApps
    readonly property bool searchLanding: searchOnly && query === ""
    readonly property var featured: {
        var ids = pinned.length ? pinned : Core.Ipc.get("dock.pinned", []);
        var result = ids.map(function(id) {
            return Core.Apps.byId(id);
        }).filter(function(a) {
            return !!a;
        });
        if (!result.length)
            result = catalog;

        return result.slice(0, 5);
    }

    signal closeRequested()
    signal actionRequested(string action)
    signal folderRequested(string path)

    function openFolder(id) {
        if (id === "settings") {
            menu.actionRequested("w-home");
            return;
        }
        var path = StartPlaces.pathFor(id);
        if (path !== "")
            menu.folderRequested(path);
    }

    function launch(a) {
        if (!a)
            return ;

        Core.Ipc.launchApp(a.exec, a.appId, "new-window");
        closeRequested();
    }

    function activateSelection() {
        if (searchLanding)
            return ;

        if (searchOnly && searchCategory === "documents") {
            var file = files[selectedIndex];
            if (file) {
                Core.Ipc.apriOChiedi(file.path);
                closeRequested();
            }
        } else {
            launch(apps[selectedIndex]);
        }
    }

    function move(delta) {
        var count = searchOnly && searchCategory === "documents" ? Math.min(3, files.length) : apps.length;
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta));
        if (listMode)
            appList.positionViewAtIndex(selectedIndex, ListView.Contain);
        else
            page = Math.floor(selectedIndex / pageSize);
    }

    // Il primo Giù dalla ricerca vuota entra nella griglia, invece di
    // cambiare un indice senza un riquadro visibile. Il campo resta pronto
    // quando si comincia a scrivere, anche dopo aver navigato con le frecce.
    function enterPinned() {
        if (pinnedApps.length === 0)
            return;
        pinnedGrid.forceActiveFocus(Qt.TabFocusReason);
        revealPinnedSelection();
    }
    function revealPinnedSelection() {
        if (listMode || !pinnedGrid.activeFocus)
            return;
        var row = Math.floor((selectedIndex % pageSize) / 6);
        var top = pinnedGrid.y + row * 80;
        var bottom = top + 80;
        var next = pinnedArea.contentY;
        if (top < next)
            next = top;
        else if (bottom > next + pinnedArea.height)
            next = bottom - pinnedArea.height;
        pinnedArea.contentY = Math.max(0, Math.min(next, Math.max(0, pinnedArea.contentHeight - pinnedArea.height)));
    }
    onSelectedIndexChanged: Qt.callLater(revealPinnedSelection)
    onPageChanged: pinnedArea.contentY = 0

    function changePinnedPage(delta) {
        if (pinnedApps.length === 0)
            return;
        var last = Math.floor((pinnedApps.length - 1) / pageSize);
        var target = Math.max(0, Math.min(last, page + delta));
        var offset = selectedIndex % pageSize;
        selectedIndex = Math.min(pinnedApps.length - 1, target * pageSize + offset);
        page = target;
        enterPinned();
    }

    function begin(text) {
        field.text = text || "";
        field.forceActiveFocus();
    }

    function showApps(show) {
        contextApp = null;
        allApps = show;
        if (!show)
            field.text = "";

        selectedIndex = 0;
        page = 0;
        appList.positionViewAtBeginning();
        pinnedArea.contentY = 0;
        field.forceActiveFocus();
    }

    function pin(start) {
        if (!contextApp)
            return ;

        var key = start ? "launcher.fixedApps" : "dock.pinned", list = Core.Ipc.get(key, []).slice(), id = contextApp.appId, at = list.indexOf(id);
        if (at < 0)
            list.push(id);
        else
            list.splice(at, 1);
        Core.Ipc.setSetting(key, list);
        contextApp = null;
    }

    objectName: "windowsStart"
    onAppsChanged: {
        selectedIndex = Math.max(0, Math.min(selectedIndex, apps.length - 1));
        page = Math.floor(selectedIndex / pageSize);
    }
    onListModeChanged: contextApp = null
    Component.onCompleted: {
        Core.Apps.aggiorna();
        field.forceActiveFocus();
        if (searchOnly || Core.Ipc.get("windows11.recommendations", true))
            Core.Ipc.send({
            "action": "fs_recenti",
            "id": recentId
        });

    }
    Component.onDestruction: {
        if (searchId !== "") {
            Core.Ipc.fsSearchCancel(searchId);
        }
    }
    onQueryChanged: {
        selectedIndex = 0;
        page = 0;
        files = [];
        if (searchId !== "")
            Core.Ipc.fsSearchCancel(searchId);

        searchId = "";
        searchDelay.restart();
    }
    onSearchCategoryChanged: {
        selectedIndex = 0;
        if (searchId !== "")
            Core.Ipc.fsSearchCancel(searchId);

        files = [];
        searchId = "";
        searchDelay.restart();
    }
    Keys.onEscapePressed: function(event) {
        if (piccolo !== "")
            piccolo = "";
        else if (contextApp)
            contextApp = null;
        else if (query !== "" && !searchOnly) {
            field.text = "";
            field.forceActiveFocus();
        } else if (allApps)
            showApps(false);
        else
            closeRequested();
        event.accepted = true;
    }

    ViewMotion {
        id: navigation

        objectName: "windowsStartNavigation"
        active: menu.listMode
        allowed: !menu.searchOnly && menu.query === "" && menu.visible && menu.enabled
    }

    Row {
        x: 32
        y: 82
        spacing: 8
        visible: menu.searchOnly

        Repeater {
            model: [{
                "id": "all",
                "label": Style.label("Tutti", "All")
            }, {
                "id": "apps",
                "label": Style.label("App", "Apps")
            }, {
                "id": "documents",
                "label": Style.label("Documenti", "Documents")
            }]

            delegate: Button {
                required property var modelData

                objectName: "windowsSearchFilter-" + modelData.id
                text: modelData.label
                selected: menu.searchCategory === modelData.id
                onClicked: {
                    menu.searchCategory = modelData.id;
                    menu.selectedIndex = 0;
                    field.forceActiveFocus();
                }
            }

        }

    }

    Flickable {
        id: searchLandingScroll
        x: 32
        y: 136
        width: parent.width - 64
        height: parent.height - 160
        clip: true
        contentWidth: width
        contentHeight: searchContent.height
        visible: menu.searchLanding

        Column {
            id: searchContent

            width: parent.width
            spacing: 18

            Text {
                visible: menu.searchCategory !== "documents"
                text: Style.label("Applicazioni principali", "Top apps")
                color: Style.text
                font.family: Style.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Row {
                visible: menu.searchCategory !== "documents"
                width: parent.width
                spacing: 8

                Repeater {
                    model: menu.featured

                    delegate: Button {
                        required property var modelData

                        objectName: "windowsSearchFeatured-" + modelData.appId
                        width: (searchContent.width - 32) / 5
                        height: 90
                        selected: true
                        tooltip: modelData.name
                        onClicked: menu.launch(modelData)

                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 14
                            width: 32
                            height: 32
                            path: parent.modelData.icon || ""
                        }

                        Text {
                            x: 6
                            y: 58
                            width: parent.width - 12
                            text: parent.modelData.name
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 12
                        }

                    }

                }

            }

            Text {
                text: Style.label("Recenti", "Recent")
                color: Style.text
                font.family: Style.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
                visible: menu.recent.length > 0 && menu.searchCategory !== "apps"
            }

            Repeater {
                model: menu.searchCategory === "apps" ? [] : menu.recent

                delegate: Button {
                    required property var modelData

                    objectName: "windowsSearchRecent-" + modelData.name
                    width: searchContent.width
                    height: 42
                    text: modelData.name
                    icon: "document"
                    onClicked: {
                        Core.Ipc.apriOChiedi(modelData.path);
                        menu.closeRequested();
                    }
                }

            }

            Text {
                text: Style.label("Ricerca rapida", "Quick searches")
                color: Style.text
                font.family: Style.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Row {
                spacing: 8

                Button {
                    text: Style.label("Meteo", "Weather")
                    icon: "sun"
                    selected: true
                    onClicked: menu.actionRequested("weather")
                }

                Button {
                    text: Style.label("Impostazioni", "Settings")
                    icon: "settings"
                    selected: true
                    onClicked: menu.actionRequested("settings")
                }

            }

        }

    }

    Timer {
        id: searchDelay

        interval: 250
        onTriggered: {
            if (menu.query.length >= 2 && (!menu.searchOnly || menu.searchCategory !== "apps")) {
                menu.searchId = "windows-search-" + Date.now() + "-" + Math.random();
                Core.Ipc.fsSearch(menu.searchId, Quickshell.env("HOME"), menu.query, false);
            }
        }
    }

    Connections {
        function onRicercaAvanza(data) {
            if (!data)
                return ;

            if (data.id === menu.recentId)
                menu.recent = (data.voci || []).slice(0, 6);

            if (menu.searchId !== "" && data.id === menu.searchId)
                menu.files = menu.files.concat(data.voci || []).slice(0, 20);

        }

        target: Core.Ipc
    }

    Rectangle {
        objectName: "windowsStartSurface"
        z: -1
        anchors.fill: parent
        radius: 8
        color: menu.searchOnly ? Style.surface : Style.startSurface
        border.color: Style.edge
    }

    Rectangle {
        id: searchBox

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
            anchors.left: parent.left
            anchors.right: parent.right
            height: 2
            color: Style.accentInk
            radius: 1
        }

        Glyph {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            name: "search"
            color: menu.mutedInk
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
            Accessible.name: Style.label("Cerca applicazioni e file", "Search apps and files")
            Keys.onDownPressed: {
                if (menu.listMode)
                    menu.move(1);
                else
                    menu.enterPinned();
            }
            Keys.onUpPressed: {
                if (menu.listMode)
                    menu.move(-1);
                else
                    menu.enterPinned();
            }
            Keys.onReturnPressed: menu.activateSelection()
            Keys.onEnterPressed: menu.activateSelection()
            Keys.onTabPressed: {
                if (menu.searchLanding)
                    menu.nextItemInFocusChain(true).forceActiveFocus();
                else if (menu.searchOnly && menu.searchCategory === "documents")
                    fileResults.forceActiveFocus();
                else if (menu.listMode)
                    appList.forceActiveFocus();
                else
                    pinnedGrid.forceActiveFocus();
            }

            Text {
                anchors.fill: parent
                visible: field.text === ""
                text: Style.label("Cerca applicazioni e file", "Search apps and files")
                font: field.font
                color: menu.mutedInk
            }

        }

    }

    Flickable {
        id: pinnedArea

        objectName: "windowsPinnedArea"
        contentWidth: width
        contentHeight: 546
        clip: true
        x: 32
        y: 110
        width: parent.width - 64
        height: parent.height - 184
        visible: !menu.searchOnly && (!menu.listMode || navigation.progress < 1)
        enabled: !menu.listMode
        opacity: 1 - navigation.progress

        Text {
            x: 32
            text: Style.label("Aggiunte", "Pinned")
            color: Style.text
            font.family: Style.font
            font.pixelSize: 14 * Style.textScale
            font.weight: Font.DemiBold
        }

        Button {
            objectName: "windowsAllAppsButton"
            anchors.right: parent.right
            anchors.rightMargin: 32
            height: 26
            text: Style.label("Tutte le app  ›", "All apps  ›")
            selected: true
            onClicked: menu.showApps(true)
        }

        Grid {
            id: pinnedGrid

            objectName: "windowsPinnedGrid"
            y: 42
            width: parent.width
            columns: 6
            spacing: 0
            activeFocusOnTab: true
            Keys.onLeftPressed: menu.move(-1)
            Keys.onRightPressed: menu.move(1)
            Keys.onUpPressed: menu.move(-6)
            Keys.onDownPressed: menu.move(6)
            Keys.onReturnPressed: menu.launch(menu.apps[menu.selectedIndex])
            Keys.onEnterPressed: menu.launch(menu.apps[menu.selectedIndex])
            Keys.onSpacePressed: menu.launch(menu.apps[menu.selectedIndex])
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                    menu.move(event.key === Qt.Key_Home ? -menu.selectedIndex : menu.pinnedApps.length - 1 - menu.selectedIndex);
                    event.accepted = true;
                } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.key !== Qt.Key_Space
                           && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    field.text += event.text;
                    field.forceActiveFocus(Qt.OtherFocusReason);
                    event.accepted = true;
                }
            }

            Repeater {
                model: menu.pinnedApps.slice(menu.page * menu.pageSize, menu.page * menu.pageSize + menu.pageSize)

                delegate: Rectangle {
                    id: tile

                    required property var modelData
                    required property int index

                    objectName: "windowsPinned-" + modelData.appId
                    width: pinnedGrid.width / 6
                    height: 80
                    radius: 4
                    color: tileMouse.containsMouse || (pinnedGrid.activeFocus && menu.selectedIndex === menu.page * menu.pageSize + index) ? Style.hover : "transparent"
                    border.width: pinnedGrid.activeFocus && menu.selectedIndex === menu.page * menu.pageSize + index ? 2 : 0
                    border.color: Style.accentIndicator
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    Accessible.onPressAction: menu.launch(modelData)

                    AppIcon {
                        path: tile.modelData.icon || ""
                        width: 32
                        height: 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8
                    }

                    Text {
                        x: 4
                        y: 48
                        width: parent.width - 8
                        text: tile.modelData.name
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.font
                        font.pixelSize: 12 * Style.textScale
                    }

                    MouseArea {
                        id: tileMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(event) {
                            menu.selectedIndex = menu.page * menu.pageSize + tile.index;
                            if (event.button === Qt.RightButton)
                                menu.contextApp = tile.modelData;
                            else
                                menu.launch(tile.modelData);
                        }
                    }

                }

            }

        }

        Text {
            y: 70
            width: parent.width
            visible: menu.pinnedApps.length === 0
            text: Style.label("Aggiungi applicazioni da Tutte le app", "Pin applications from All apps")
            color: menu.mutedInk
            font.family: Style.font
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        Row {
            anchors.right: parent.right
            y: 42 + menu.pinnedRows * 80
            visible: menu.pinnedApps.length > menu.pageSize
            spacing: 4

            Button {
                objectName: "windowsStartPagePrevious"
                text: "‹"
                enabled: menu.page > 0
                onClicked: menu.changePinnedPage(-1)
            }

            Text {
                text: (menu.page + 1) + " / " + Math.ceil(menu.pinnedApps.length / menu.pageSize)
                color: menu.mutedInk
                font.family: Style.font
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                objectName: "windowsStartPageNext"
                text: "›"
                enabled: (menu.page + 1) * menu.pageSize < menu.pinnedApps.length
                onClicked: menu.changePinnedPage(1)
            }

        }

        Text {
            x: 32
            y: menu.recommendedY
            visible: Core.Ipc.get("windows11.recommendations", true)
            text: Style.label("Consigliati", "Recommended")
            color: Style.text
            font.family: Style.font
            font.pixelSize: 14 * Style.textScale
            font.weight: Font.DemiBold
        }

        Grid {
            x: 32
            y: menu.recommendedY + 38
            width: parent.width - 64
            columns: 2
            visible: Core.Ipc.get("windows11.recommendations", true)

            Repeater {
                model: menu.recent.slice(0, menu.layout === "pinned" ? 2 : 6)

                delegate: Button {
                    required property var modelData

                    width: parent.width / 2
                    height: 52
                    tooltip: modelData.name
                    onClicked: {
                        Core.Ipc.apriOChiedi(modelData.path);
                        menu.closeRequested();
                    }

                    Glyph {
                        x: 8
                        y: 10
                        width: 30
                        height: 30
                        name: "document"
                        color: Style.accentInk
                    }

                    Text {
                        x: 48
                        y: 10
                        width: parent.width - 56
                        text: parent.modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.font
                        font.pixelSize: 12 * Style.textScale
                    }

                    Text {
                        x: 48
                        y: 28
                        width: parent.width - 56
                        text: parent.modelData.dove || Style.label("Recente", "Recent")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: menu.mutedInk
                        font.family: Style.font
                        font.pixelSize: 11 * Style.textScale
                    }

                }

            }

        }

        Text {
            x: 32
            y: menu.recommendedY + 42
            visible: Core.Ipc.get("windows11.recommendations", true) && menu.recent.length === 0
            text: Style.label("Qui compariranno i documenti aperti di recente.", "Recently opened documents will appear here.")
            color: menu.mutedInk
            font.family: Style.font
            font.pixelSize: 12 * Style.textScale
            wrapMode: Text.WordWrap
            width: parent.width - 32
        }

        transform: Translate {
            x: -Style.viewTravel * navigation.progress
        }

    }

    Item {
        id: listArea

        objectName: "windowsListArea"
        x: 32
        y: menu.searchOnly ? 136 : 88
        width: parent.width - 64
        height: parent.height - y - 80
        visible: !menu.searchLanding && (menu.listMode || navigation.progress > 0)
        enabled: menu.listMode && !menu.searchLanding
        opacity: navigation.progress

        Text {
            text: menu.searchOnly && menu.searchCategory === "documents" ? Style.label("Documenti", "Documents") : (menu.query !== "" ? Style.label("Applicazioni", "Apps") : Style.label("Tutte le app", "All apps"))
            color: Style.text
            font.family: Style.font
            font.pixelSize: 14 * Style.textScale
            font.weight: Font.DemiBold
        }

        Button {
            objectName: "windowsAllAppsBack"
            anchors.right: parent.right
            height: 26
            text: Style.label("‹  Indietro", "‹  Back")
            visible: !menu.searchOnly
            onClicked: menu.showApps(false)
        }

        Ui.Scorrimento {
            objectName: "windowsAppsScrollBar"
            tinta: Style.muted
            bersaglio: appList
            anchors.right: appList.right
            anchors.top: appList.top
            anchors.bottom: appList.bottom
            visible: appList.visible && _serve
        }
        ListView {
            id: appList

            objectName: "windowsAllApps"
            y: 40
            width: parent.width
            height: menu.files.length > 0 ? parent.height * 0.58 : parent.height - 40
            visible: !menu.searchOnly || menu.searchCategory !== "documents"
            clip: true
            model: menu.listApps
            currentIndex: menu.selectedIndex
            activeFocusOnTab: true
            Keys.onUpPressed: menu.move(-1)
            Keys.onDownPressed: menu.move(1)
            Keys.onReturnPressed: menu.launch(menu.apps[menu.selectedIndex])
            Keys.onEnterPressed: menu.launch(menu.apps[menu.selectedIndex])

            delegate: Button {
                required property var modelData
                required property int index

                objectName: "windowsApp-" + modelData.appId
                width: appList.width
                height: 48
                selected: appList.activeFocus && menu.selectedIndex === index
                tooltip: modelData.name
                onClicked: menu.launch(modelData)
                onRightClicked: menu.contextApp = modelData

                AppIcon {
                    x: 12
                    y: 8
                    width: 32
                    height: 32
                    path: parent.modelData.icon || ""
                }

                Text {
                    x: 58
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 70
                    text: parent.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 14 * Style.textScale
                }

            }

        }

        Column {
            id: fileResults

            activeFocusOnTab: true
            Keys.onUpPressed: menu.move(-1)
            Keys.onDownPressed: menu.move(1)
            Keys.onReturnPressed: menu.activateSelection()
            Keys.onEnterPressed: menu.activateSelection()
            visible: menu.files.length > 0 && (!menu.searchOnly || menu.searchCategory !== "apps")
            y: menu.searchOnly && menu.searchCategory === "documents" ? 40 : appList.y + appList.height + 10
            width: parent.width
            spacing: 4

            Text {
                text: Style.label("File", "Files")
                color: menu.mutedInk
                font.family: Style.font
                font.pixelSize: 12
            }

            Repeater {
                model: menu.files.slice(0, 3)

                delegate: Button {
                    required property var modelData
                    required property int index

                    selected: fileResults.activeFocus && menu.selectedIndex === index
                    width: listArea.width
                    height: 36
                    text: modelData.name
                    icon: "document"
                    onClicked: {
                        Core.Ipc.apriOChiedi(modelData.path);
                        menu.closeRequested();
                    }
                }

            }

        }

        Text {
            y: 65
            visible: menu.apps.length === 0 && menu.files.length === 0
            width: parent.width
            text: Style.label("Nessun risultato", "No results")
            color: menu.mutedInk
            font.family: Style.font
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }

        transform: Translate {
            x: Style.viewTravel * (1 - navigation.progress)
        }

    }

    Rectangle {
        id: piede
        objectName: "windowsStartFooter"
        visible: !menu.searchOnly
        anchors.bottom: parent.bottom
        width: parent.width
        height: 64
        color: Style.startFooter
        radius: 8

        Rectangle {
            width: parent.width
            height: 8
            color: Style.startFooter
        }

        Button {
            id: pulsanteAccount
            objectName: "windowsStartAccount"
            x: 64
            anchors.verticalCenter: parent.verticalCenter
            // Il nome e la foto di chi usa il computer, come in Windows 11.
            // Prima c'era «Account locale» con un simbolo: «Disconnetti»
            // sta nel menu di questo pulsante, e così non lo si trovava
            // (il manutentore, 12 ottobre 2026: «non vedo esci dalla sessione»).
            text: Core.Utente.nome
            maximumTextWidth: Math.max(0, collegamenti.x - x - 76)
            avatar: true
            ritratto: Core.Utente.ritratto
            tooltip: Core.Utente.nome
            selected: menu.piccolo === "account"
            onClicked: menu.piccolo = menu.piccolo === "account" ? "" : "account"
        }

        Button {
            id: pulsanteAlimentazione
            objectName: "windowsStartPower"
            anchors.right: parent.right
            anchors.rightMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            icon: "power"
            tooltip: Style.label("Alimentazione", "Power")
            selected: menu.piccolo === "power"
            onClicked: menu.piccolo = menu.piccolo === "power" ? "" : "power"
        }

        Row {
            id: collegamenti
            objectName: "windowsStartFolders"
            anchors.right: pulsanteAlimentazione.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: menu.folderShortcuts
                delegate: Button {
                    required property var modelData
                    objectName: "windowsStartFolder-" + modelData.id
                    width: 36
                    height: 40
                    icon: modelData.icon
                    tooltip: Style.label(modelData.it, modelData.en)
                    onClicked: menu.openFolder(modelData.id)
                }
            }
        }

    }

    MouseArea {
        anchors.fill: parent
        visible: menu.contextApp !== null || menu.piccolo !== ""
        onClicked: {
            menu.contextApp = null;
            menu.piccolo = "";
        }
    }

    // ── I menu piccoli del piede ────────────────────────────────────────
    //
    // Si aprono sopra il loro pulsante, come in Windows 11. Le voci
    // mandano l'azione a chi contiene lo Start (`Taskbar.qml`), che chiude
    // e la passa alla shell (`azioneDalCentro`).
    Rectangle {
        id: menuPiccolo
        objectName: "windowsStartPowerMenu"
        visible: menu.piccolo !== ""
        readonly property var voci: menu.piccolo === "power" ? [
            { "id": "accesso", "icon": "settings", "label": Style.label("Opzioni di accesso", "Sign-in options") },
            { "id": "sospendi", "icon": "moon", "label": Style.label("Sospendi", "Sleep") },
            { "id": "spegni", "icon": "power", "label": Style.label("Arresta il sistema", "Shut down") },
            { "id": "riavvia", "icon": "restart", "label": Style.label("Riavvia il sistema", "Restart") }
        ] : [
            { "id": "utente", "icon": "user", "label": Style.label("Cambia impostazioni account", "Change account settings") },
            { "id": "blocca", "icon": "lock", "label": Style.label("Blocca", "Lock") },
            { "id": "esci", "icon": "logout", "label": Style.label("Disconnetti", "Sign out") }
        ]
        width: 240
        height: voci.length * 40 + 8
        // Sopra il piede, allineato al suo pulsante: a destra quello
        // dell'alimentazione, a sinistra quello dell'account. Ancorato e non
        // calcolato con `mapToItem`, che non si ricalcola quando le cose si
        // spostano: il clic su «Blocca» arrivava a «Disconnetti».
        anchors.bottom: piede.top
        anchors.bottomMargin: 6
        anchors.right: menu.piccolo === "power" ? piede.right : undefined
        anchors.rightMargin: 24
        anchors.left: menu.piccolo === "power" ? undefined : piede.left
        anchors.leftMargin: 56
        radius: 8
        color: Style.field
        border.color: Style.edge

        Column {
            anchors.fill: parent
            anchors.margins: 4

            Repeater {
                model: menuPiccolo.voci

                delegate: Button {
                    required property var modelData
                    objectName: "windowsStartPower-" + modelData.id
                    width: parent.width
                    height: 40
                    icon: modelData.icon
                    text: modelData.label
                    // Passa dallo Start e non fa niente qui dopo: chiudere il
                    // menu cambia l'elenco, il Repeater distrugge questa voce
                    // e il suo codice non vede più né `modelData` né `menu`
                    // («ReferenceError: menu is not defined», trovato dalla
                    // prova l'11 ottobre 2026).
                    onClicked: menu.sceltaPiccolo(modelData.id)
                }
            }
        }
    }

    Rectangle {
        visible: menu.contextApp !== null
        x: Math.max(16, menu.width - 280)
        y: 100
        width: 256
        height: 144
        radius: 8
        color: Style.field
        border.color: Style.edge

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Button {
                width: parent.width
                height: 40
                text: Style.label("Apri nuova finestra", "Open new window")
                icon: "plus"
                onClicked: {
                    menu.launch(menu.contextApp);
                    menu.contextApp = null;
                }
            }

            Button {
                width: parent.width
                height: 40
                text: menu.contextApp && menu.pinned.indexOf(menu.contextApp.appId) >= 0 ? Style.label("Rimuovi da Start", "Unpin from Start") : Style.label("Aggiungi a Start", "Pin to Start")
                onClicked: menu.pin(true)
            }

            Button {
                width: parent.width
                height: 40
                text: menu.contextApp && Core.Ipc.get("dock.pinned", []).indexOf(menu.contextApp.appId) >= 0 ? Style.label("Rimuovi dalla barra", "Unpin from taskbar") : Style.label("Aggiungi alla barra", "Pin to taskbar")
                onClicked: menu.pin(false)
            }

        }

    }

    Ui.Scorrimento {
        objectName: "windowsSearchScrollBar"
        tinta: Style.muted
        bersaglio: searchLandingScroll
        anchors.right: searchLandingScroll.right
        anchors.top: searchLandingScroll.top
        anchors.bottom: searchLandingScroll.bottom
        visible: searchLandingScroll.visible && _serve
    }
    Ui.Scorrimento {
        objectName: "windowsPinnedScrollBar"
        tinta: Style.muted
        bersaglio: pinnedArea
        anchors.right: pinnedArea.right
        anchors.top: pinnedArea.top
        anchors.bottom: pinnedArea.bottom
        visible: pinnedArea.visible && _serve
    }

}
