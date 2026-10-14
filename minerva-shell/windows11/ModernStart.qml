import QtQuick
import QtQuick.Window
import "../core" as Core
import "../ui" as Ui
import "StartCatalog.js" as Catalog

// Un solo ListView conserva la virtualizzazione del catalogo. Ricerca e
// piede appartengono allo Start esterno e non scorrono con le applicazioni.
FocusScope {
    id: modern
    property var pinnedApps: []
    property var catalog: []
    property var recent: []
    property string category: ""
    property string draggedPin: ""
    property string dropPin: ""
    property point dragPosition: Qt.point(0, 0)
    property bool dragCancelled: false
    readonly property int columns: width >= 640 ? 8 : 6
    readonly property int categoryColumns: width >= 640 ? 4 : 3
    readonly property bool expanded: Core.Ipc.get("windows11.startPinnedExpanded", false)
    readonly property bool moreRecent: Core.Ipc.get("windows11.startRecommendedExpanded", false)
    readonly property bool recommendations: Core.Ipc.get("windows11.recommendations", true)
    readonly property string view: Core.Ipc.get("windows11.startAppsView", "category")
    readonly property var categories: Catalog.grouped(catalog)
    readonly property var shown: category === "" ? catalog : (
        categories.filter(function(group) { return group.id === category; })[0] || {apps: []}).apps
    readonly property var rows: category === "" && view === "category"
        ? Catalog.rows(categories, categoryColumns, "category")
        : Catalog.rows(shown, view === "list" && category === "" ? 1 : columns, "app")
    readonly property real tileHeight: 80 * Math.max(1, Style.textScale)
    signal launchRequested(var app)
    signal contextRequested(var app)
    signal fileRequested(string path)
    signal searchRequested(string text)
    signal searchFocusRequested()

    function updatePinDrag(id, position) {
        if (dragCancelled)
            return;
        draggedPin = id;
        dragPosition = position;
        dropPin = listing.headerItem ? listing.headerItem.pinAt(position) : "";
    }
    function cancelPinDrag() {
        dragCancelled = true;
        draggedPin = "";
        dropPin = "";
    }
    function finishPinDrag() {
        var source = draggedPin;
        var target = dropPin;
        cancelPinDrag();
        if (!source || !target || source === target)
            return;
        var ordered = Core.Ipc.get("launcher.fixedApps", []).slice();
        var from = ordered.indexOf(source);
        var to = ordered.indexOf(target);
        if (from < 0 || to < 0)
            return;
        // Un'unica scrittura al rilascio conserva il grab del mouse:
        // riordinare a ogni movimento distruggerebbe il delegate trascinato.
        ordered.splice(from, 1);
        ordered.splice(to, 0, source);
        Core.Ipc.setSetting("launcher.fixedApps", ordered);
        Qt.callLater(function() {
            if (listing.headerItem)
                listing.headerItem.focusPin(source);
        });
    }
    Timer {
        interval: 40
        repeat: true
        running: modern.draggedPin !== "" && (modern.dragPosition.y < 28 || modern.dragPosition.y > modern.height - 28)
        onTriggered: {
            var direction = modern.dragPosition.y < 28 ? -1 : 1;
            var beginning = -listing.headerItem.height;
            listing.contentY = Math.max(beginning, Math.min(listing.contentY + direction * 10,
                Math.max(beginning, listing.contentHeight - listing.height)));
            modern.dropPin = listing.headerItem.pinAt(modern.dragPosition);
        }
    }

    function enter() {
        if (listing.headerItem)
            listing.headerItem.enter();
    }
    function focusPin(id) {
        if (listing.headerItem)
            listing.headerItem.focusPin(id);
    }
    function reveal(item) {
        if (!item)
            return;
        var ancestor = item;
        while (ancestor && ancestor !== listing.contentItem)
            ancestor = ancestor.parent;
        if (ancestor !== listing.contentItem)
            return;
        var point = item.mapToItem(listing, 0, 0);
        var next = listing.contentY;
        if (point.y < 4)
            next += point.y - 4;
        else if (point.y + item.height > listing.height - 4)
            next += point.y + item.height - listing.height + 4;
        var beginning = -listing.headerItem.height;
        listing.contentY = Math.max(beginning, Math.min(next, Math.max(beginning, listing.contentHeight - listing.height)));
    }
    function focusRow(index, column) {
        if (index < 0) {
            if (listing.headerItem)
                listing.headerItem.focusCatalogue();
            return;
        }
        if (index >= rows.length)
            return;
        listing.positionViewAtIndex(index, ListView.Contain);
        listing.forceLayout();
        Qt.callLater(function() {
            var row = listing.itemAtIndex(index);
            if (row)
                row.focusCell(column);
        });
    }
    // Il modello può arrivare prima che la testata abbia la sua altezza:
    // riposizionare al primo delegate in quel momento tagliava i preferiti.
    onRowsChanged: resetTop.restart()
    Timer {
        id: resetTop
        interval: 1
        onTriggered: {
            listing.forceLayout();
            if (listing.headerItem)
                listing.contentY = -listing.headerItem.height;
            if (modern.category !== "")
                modern.focusRow(0, 0);
        }
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape && draggedPin !== "") {
            cancelPinDrag();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && category !== "") {
            category = "";
            event.accepted = true;
        } else if (event.text && event.text.charCodeAt(0) >= 32 && event.key !== Qt.Key_Space
                   && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            searchRequested(event.text);
            event.accepted = true;
        }
    }
    Connections {
        target: modern.Window.window
        function onActiveFocusItemChanged() {
            if (modern.Window.window)
                modern.reveal(modern.Window.window.activeFocusItem);
        }
    }

    ListView {
        id: listing
        objectName: "windowsModernScroll"
        anchors.fill: parent
        // La maniglia è larga18px anche a riposo: i comandi della testata
        // devono fermarsi prima del suo binario e conservarne il bersaglio.
        anchors.rightMargin: scrollBar.width + 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: modern.rows
        spacing: 4
        cacheBuffer: 160
        reuseItems: true
        header: Column {
            id: sections
            width: listing.width
            spacing: 12
            function enter() {
                if (pins.count)
                    pins.itemAt(0).forceActiveFocus(Qt.TabFocusReason);
                else
                    focusCatalogue();
            }
            function focusCatalogue() { categoryView.forceActiveFocus(Qt.TabFocusReason); }
            function pinAt(position) {
                var point = modern.mapToItem(pinnedGrid, position.x, position.y);
                if (point.x < 0 || point.x >= pinnedGrid.width || point.y < 0 || point.y >= pinnedGrid.height)
                    return "";
                var column = Math.floor(point.x / (pinnedGrid.width / modern.columns));
                var row = Math.floor(point.y / modern.tileHeight);
                var item = pins.itemAt(row * modern.columns + column);
                return item && item.app ? item.app.appId : "";
            }
            function focusPin(id) {
                for (var index = 0; index < pins.count; index++) {
                    var item = pins.itemAt(index);
                    if (item.app && item.app.appId === id) {
                        item.forceActiveFocus(Qt.TabFocusReason);
                        modern.reveal(item);
                        return;
                    }
                }
            }
            Item {
                width: parent.width
                height: 32
                Text {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: Style.label("Preferiti", "Pinned")
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 14 * Style.textScale
                    font.weight: Font.DemiBold
                }
                Button {
                    objectName: "windowsModernExpandPins"
                    anchors.right: parent.right
                    height: 28
                    visible: modern.pinnedApps.length > modern.columns * 2
                    text: modern.expanded ? Style.label("Mostra meno", "Show less") : Style.label("Mostra tutto", "Show all")
                    fontPixelSize: 14 * Style.textScale
                    trailingIcon: "chevron"
                    trailingRotation: modern.expanded ? 180 : 0
                    onClicked: Core.Ipc.setSetting("windows11.startPinnedExpanded", !modern.expanded)
                }
            }
            Grid {
                id: pinnedGrid
                width: parent.width
                columns: modern.columns
                Repeater {
                    id: pins
                    model: modern.expanded ? modern.pinnedApps : modern.pinnedApps.slice(0, modern.columns * 2)
                    delegate: AppTile {
                        required property var modelData
                        required property int index
                        objectName: "windowsModernPin-" + modelData.appId
                        app: modelData
                        dragHost: modern
                        width: pinnedGrid.width / modern.columns
                        height: modern.tileHeight
                        onActivated: modern.launchRequested(app)
                        onContext: modern.contextRequested(app)
                        Keys.onLeftPressed: if (index > 0) pins.itemAt(index - 1).forceActiveFocus(Qt.TabFocusReason)
                        Keys.onRightPressed: if (index + 1 < pins.count) pins.itemAt(index + 1).forceActiveFocus(Qt.TabFocusReason)
                        Keys.onUpPressed: {
                            if (index >= modern.columns)
                                pins.itemAt(index - modern.columns).forceActiveFocus(Qt.TabFocusReason);
                            else
                                modern.searchFocusRequested();
                        }
                        Keys.onDownPressed: {
                            if (index + modern.columns < pins.count)
                                pins.itemAt(index + modern.columns).forceActiveFocus(Qt.TabFocusReason);
                            else if (recentItems.count)
                                recentItems.itemAt(0).forceActiveFocus(Qt.TabFocusReason);
                            else
                                sections.focusCatalogue();
                        }
                    }
                }
            }
            Text {
                width: parent.width
                visible: pins.count === 0
                text: Style.label("Aggiungi app dal catalogo qui sotto.", "Pin apps from the catalog below.")
                color: Style.startMuted
                font.family: Style.font
                font.pixelSize: 13 * Style.textScale
                wrapMode: Text.WordWrap
            }
            Item {
                width: parent.width
                height: 32
                visible: modern.recommendations
                Text {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: Style.label("Elementi consigliati", "Recommended")
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 14 * Style.textScale
                    font.weight: Font.DemiBold
                }
                Button {
                    objectName: "windowsModernExpandRecent"
                    anchors.right: parent.right
                    height: 28
                    visible: modern.recent.length > 6
                    text: modern.moreRecent ? Style.label("Mostra meno", "Show less") : Style.label("Mostra tutto", "Show all")
                    fontPixelSize: 14 * Style.textScale
                    trailingIcon: "chevron"
                    trailingRotation: modern.moreRecent ? 180 : -90
                    onClicked: Core.Ipc.setSetting("windows11.startRecommendedExpanded", !modern.moreRecent)
                }
            }
            Grid {
                id: recentGrid
                width: parent.width
                columns: modern.width >= 640 ? 3 : 2
                visible: modern.recommendations
                Repeater {
                    id: recentItems
                    model: modern.recommendations ? modern.recent.slice(0, modern.moreRecent ? 20 : 6) : []
                    delegate: Button {
                        required property var modelData
                        required property int index
                        objectName: "windowsModernRecent-" + index
                        width: recentGrid.width / recentGrid.columns
                        height: 56 * Math.max(1, Style.textScale)
                        tooltip: modelData.name
                        onClicked: modern.fileRequested(modelData.path)
                        Keys.onDownPressed: {
                            if (index + recentGrid.columns < recentItems.count)
                                recentItems.itemAt(index + recentGrid.columns).forceActiveFocus(Qt.TabFocusReason);
                            else
                                sections.focusCatalogue();
                        }
                        Keys.onUpPressed: {
                            if (index >= recentGrid.columns)
                                recentItems.itemAt(index - recentGrid.columns).forceActiveFocus(Qt.TabFocusReason);
                            else
                                sections.enter();
                        }
                        Glyph { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; name: "document"; rasterized: true }
                        Text {
                            x: 40
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 48
                            text: modelData.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 12 * Style.textScale
                        }
                    }
                }
            }
            Text {
                width: parent.width
                visible: modern.recommendations && modern.recent.length === 0
                text: Style.label("Qui compariranno i documenti aperti di recente.", "Recently opened documents will appear here.")
                color: Style.startMuted
                font.family: Style.font
                font.pixelSize: 12 * Style.textScale
                wrapMode: Text.WordWrap
            }
            Item {
                width: parent.width
                height: 40
                Text {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: modern.category === "" ? Style.label("Tutte", "All") : Style.label("Categoria", "Category")
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 14 * Style.textScale
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    spacing: 6
                    Button {
                        objectName: "windowsModernCategoryBack"
                        text: Style.label("‹ Tutte", "‹ All")
                        visible: modern.category !== ""
                        onClicked: modern.category = ""
                    }
                    Button {
                        id: categoryView
                        objectName: "windowsModernView"
                        text: Style.label("Visualizza: ", "View: ") + (modern.view === "category"
                            ? Style.label("Categorie", "Category") : modern.view === "grid"
                            ? Style.label("Griglia", "Grid") : Style.label("Elenco", "List"))
                        fontPixelSize: 14 * Style.textScale
                        trailingIcon: "chevron"
                        onClicked: viewOptions.visible = !viewOptions.visible
                        Keys.onDownPressed: modern.focusRow(0, 0)
                        Keys.onUpPressed: sections.enter()
                    }
                }
            }
            MouseArea {
                parent: modern
                anchors.fill: parent
                z: 5
                visible: viewOptions.visible
                onClicked: {
                    viewOptions.visible = false;
                    categoryView.forceActiveFocus(Qt.PopupFocusReason);
                }
            }
            Rectangle {
                id: viewOptions
                parent: modern
                z: 6
                x: Math.max(0, modern.width - width - 4)
                y: Math.max(4, Math.min(modern.height - height - 4,
                    categoryView.mapToItem(modern, 0, categoryView.height).y + 4 + listing.contentY * 0))
                width: 200 * Math.max(1, Style.textScale)
                height: 104 * Math.max(1, Style.textScale)
                visible: false
                color: Style.field
                border.color: Style.edge
                radius: 8
                Accessible.role: Accessible.PopupMenu
                Accessible.name: Style.label("Visualizzazione app", "App view")
                property int current: 0
                onVisibleChanged: {
                    if (visible) {
                        current = Math.max(0, ["category", "grid", "list"].indexOf(modern.view));
                        viewButtons.itemAt(current).forceActiveFocus(Qt.PopupFocusReason);
                    }
                }
                function step(delta) {
                    current = (current + delta + 3) % 3;
                    viewButtons.itemAt(current).forceActiveFocus(Qt.TabFocusReason);
                }
                Keys.onDownPressed: step(1)
                Keys.onUpPressed: step(-1)
                Keys.onEscapePressed: {
                    visible = false;
                    categoryView.forceActiveFocus(Qt.PopupFocusReason);
                }
                Shadow { surface: viewOptions }
                Column {
                    anchors.fill: parent
                    anchors.margins: 4
                    Repeater {
                        id: viewButtons
                        model: ["category", "grid", "list"]
                        delegate: Button {
                            required property string modelData
                            objectName: "windowsModernView-" + modelData
                            width: parent.width
                            height: 32 * Math.max(1, Style.textScale)
                            aSinistra: true
                            fontPixelSize: 14 * Style.textScale
                            Accessible.role: Accessible.MenuItem
                            text: modelData === "category" ? Style.label("Categorie", "Category")
                                : modelData === "grid" ? Style.label("Griglia", "Grid") : Style.label("Elenco", "List")
                            selected: modern.view === modelData
                            onClicked: {
                                // Salvare può ricostruire i delegate del catalogo.
                                var owner = modern;
                                var value = modelData;
                                viewOptions.visible = false;
                                categoryView.forceActiveFocus(Qt.TabFocusReason);
                                owner.category = "";
                                Core.Ipc.setSetting("windows11.startAppsView", value);
                            }
                        }
                    }
                }
            }
        }
        delegate: Row {
            id: catalogueRow
            required property var modelData
            required property int index
            width: listing.width
            height: modelData.kind === "category" ? 184 * Math.max(1, Style.textScale) : modern.tileHeight
            function focusCell(column) {
                var cell = cells.itemAt(Math.max(0, Math.min(column, cells.count - 1)));
                if (cell)
                    cell.forceActiveFocus(Qt.TabFocusReason);
            }
            Repeater {
                id: cells
                model: catalogueRow.modelData.cells
                delegate: AppTile {
                    required property var modelData
                    required property int index
                    readonly property bool grouped: catalogueRow.modelData.kind === "category"
                    objectName: "windowsModernCell-" + catalogueRow.index + "-" + index
                    app: grouped ? null : modelData
                    group: grouped ? modelData : null
                    list: modern.view === "list" && modern.category === ""
                    width: listing.width / (grouped ? modern.categoryColumns : list ? 1 : modern.columns)
                    height: catalogueRow.height
                    onActivated: {
                        if (grouped) {
                            // Il cambio modello distrugge questo delegate.
                            var owner = modern;
                            var destination = modelData.id;
                            owner.category = destination;
                            owner.focusRow(0, 0);
                        } else {
                            modern.launchRequested(app);
                        }
                    }
                    onContext: if (!grouped) modern.contextRequested(app)
                    Keys.onLeftPressed: catalogueRow.focusCell(index - 1)
                    Keys.onRightPressed: catalogueRow.focusCell(index + 1)
                    Keys.onUpPressed: modern.focusRow(catalogueRow.index - 1, index)
                    Keys.onDownPressed: modern.focusRow(catalogueRow.index + 1, index)
                }
            }
        }
        footer: Item {
            width: listing.width
            height: visible ? emptyCatalog.implicitHeight + 16 : 0
            visible: modern.catalog.length === 0
            Text {
                id: emptyCatalog
                y: 8
                width: parent.width
                text: Style.label("Nessuna applicazione disponibile", "No applications available")
                color: Style.startMuted
                font.family: Style.font
                font.pixelSize: 14 * Style.textScale
                wrapMode: Text.WordWrap
            }
        }
    }
    Ui.Scorrimento {
        id: scrollBar
        objectName: "windowsModernScrollbar"
        tinta: Style.muted
        bersaglio: listing
        anchors.right: modern.right
        anchors.top: listing.top
        anchors.bottom: listing.bottom
    }

    Rectangle {
        objectName: "windowsModernPinDragPreview"
        visible: modern.draggedPin !== ""
        z: 20
        x: modern.dragPosition.x - width / 2
        y: modern.dragPosition.y - height / 2
        width: 44
        height: 44
        radius: 6
        color: Style.field
        border.color: Style.edge
        AppIcon {
            anchors.centerIn: parent
            width: 32
            height: 32
            clipSafe: true
            path: (modern.pinnedApps.find(function(app) { return app.appId === modern.draggedPin; }) || {}).icon || ""
        }
    }

    component AppTile: Button {
        id: tile
        property var app: null
        property var group: null
        property bool list: false
        property var dragHost: null
        readonly property bool dragSource: dragHost !== null && app !== null && dragHost.draggedPin === app.appId
        readonly property bool dragTarget: dragHost !== null && app !== null && dragHost.dropPin === app.appId && dragHost.draggedPin !== app.appId
        property point dragOrigin: Qt.point(0, 0)
        property bool dragMoved: false
        opacity: dragSource ? 0.45 : 1
        signal activated()
        signal context()
        tooltip: group ? Style.label(group.it, group.en) : app ? app.name : ""
        onClicked: activated()
        onRightClicked: context()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Menu || event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier) {
                context();
                event.accepted = true;
            }
        }
        AppIcon {
            clipSafe: true
            visible: tile.app !== null
            path: tile.app ? tile.app.icon || "" : ""
            width: 32
            height: 32
            x: tile.list ? 12 : (parent.width - width) / 2
            y: tile.list ? (parent.height - height) / 2 : 8
        }
        Rectangle {
            id: categoryFrame
            visible: tile.group !== null
            width: Math.min(144, parent.width - 24)
            height: width
            x: (parent.width - width) / 2
            y: 8
            radius: 8
            color: Style.dark ? "#08FFFFFF" : "#18FFFFFF"
            border.color: Style.edge
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 24
                Repeater {
                    model: tile.group ? tile.group.apps.slice(0, 4) : []
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool miniature: index === 3 && tile.group.apps.length > 4
                        width: 32
                        height: 32
                        AppIcon {
                            anchors.fill: parent
                            clipSafe: true
                            visible: !parent.miniature
                            path: parent.modelData.icon || ""
                        }
                        Grid {
                            visible: parent.miniature
                            columns: 2
                            spacing: 4
                            Repeater {
                                model: parent.visible ? tile.group.apps.slice(3, 7) : []
                                delegate: AppIcon {
                                    required property var modelData
                                    clipSafe: true
                                    width: 14
                                    height: 14
                                    path: modelData.icon || ""
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            x: tile.list ? 56 : 4
            y: tile.group ? categoryFrame.y + categoryFrame.height + 12 : tile.list ? (parent.height - height) / 2 : 48
            width: parent.width - x - 4
            text: tile.tooltip
            textFormat: Text.PlainText
            color: Style.text
            font.family: Style.font
            font.pixelSize: 12 * Style.textScale
            horizontalAlignment: tile.list ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 4
            color: "transparent"
            border.color: Style.accentIndicator
            border.width: 2
            visible: tile.dragTarget
        }
        Binding {
            target: tile.pointerArea
            property: "preventStealing"
            value: tile.dragHost !== null
        }
        Connections {
            target: tile.dragHost !== null ? tile.pointerArea : null
            function onPressed(event) {
                tile.dragHost.dragCancelled = false;
                tile.dragOrigin = tile.pointerArea.mapToItem(tile.dragHost, event.x, event.y);
                tile.dragMoved = false;
                tile._focoDalMouse = true;
                tile.forceActiveFocus(Qt.MouseFocusReason);
            }
            function onPositionChanged(event) {
                if (!(tile.pointerArea.pressedButtons & Qt.LeftButton))
                    return;
                var point = tile.pointerArea.mapToItem(tile.dragHost, event.x, event.y);
                var distance = Math.hypot(point.x - tile.dragOrigin.x, point.y - tile.dragOrigin.y);
                if (distance >= 8)
                    tile.dragMoved = true;
                if (tile.dragMoved && tile.app) {
                    tile.suppressClick = true;
                    tile.dragHost.updatePinDrag(tile.app.appId, point);
                }
            }
            function onReleased(event) {
                if (!tile.dragMoved)
                    return;
                var host = tile.dragHost;
                tile.suppressClick = true;
                host.finishPinDrag();
            }
            function onCanceled() {
                tile.suppressClick = true;
                if (tile.dragHost)
                    tile.dragHost.cancelPinDrag();
            }
        }
    }
}
