import "../core" as Core
import "../ui" as Ui
import QtQuick
import Quickshell

FocusScope {
    // ── «Sposta in» col tasto destro (11 ottobre 2026) ───────────────────
    // In Windows 11 una finestra della Visualizzazione attività si sposta in
    // un altro desktop in due modi: trascinandola sulla sua miniatura, o col
    // tasto destro → «Sposta in». Il secondo mancava (il manutentore: «non sposta le
    // app da un desktop ad un altro»).

    id: view

    property string output: ""
    property int selectedWindow: 0
    property int selectedDesktop: 0
    property bool desktopsFocus: false
    property var draggingHandler: null
    // Il modello resta vivo durante i polling: prima Repeater distruggeva
    // il DragHandler tra pressione e rilascio quando cambiava un titolo.
    property string selectedIdentity: ""
    property int selectedDesktopId: 0
    readonly property int currentDesktop: Core.Compositore.scrivaniaAttiva
    readonly property var entries: Core.Windows.all.filter(function(w) {
        return w.workspace === Core.Compositore.scrivaniaAttiva && (!view.output || !w.output || w.output === view.output);
    }).sort(function(a, b) {
        return a.birth - b.birth || a.address.localeCompare(b.address);
    })
    readonly property var desktops: {
        var ids = Core.Ipc.get("windows11.desktops", [1]).slice();
        Core.Windows.all.forEach(function(w) {
            if (w.workspace > 0 && ids.indexOf(w.workspace) < 0)
                ids.push(w.workspace);

        });
        if (ids.indexOf(Core.Compositore.scrivaniaAttiva) < 0)
            ids.push(Core.Compositore.scrivaniaAttiva);

        return ids.sort(function(a, b) {
            return a - b;
        });
    }
    readonly property int columns: Math.max(1, Math.min(4, Math.floor((width - 40) / 264), entries.length <= 4 ? entries.length : Math.ceil(Math.sqrt(entries.length))))
    readonly property string watchId: "windows-taskview-" + Date.now() + "-" + Math.random()
    readonly property var watched: Core.Windows.all.map(function(w) {
        return w.address;
    })
    /// La finestra il cui menu è aperto: `{address, birth, workspace}`, o null.
    property var menuFinestra: null
    property int menuDesktop: 0
    /// Il desktop di cui si sta scrivendo il nome (0: nessuno). In Windows
    /// 11 un desktop si rinomina dalla sua miniatura: doppio clic sul nome,
    /// o tasto destro → «Rinomina». Il nome va in `windows.workspaceNames`
    /// (`Core.Tiling.nameWorkspace`), lo stesso delle Stanze di Liquid.
    property int rinominando: 0
    property point menuPunto: Qt.point(0, 0)

    signal closeRequested()

    function updateWindows() {
        var identity = selectedIdentity;
        windowRows.update(entries);
        var index = entries.findIndex(function(w) {
            return w.address + ":" + w.birth === identity;
        });
        selectedWindow = index >= 0 ? index : Math.max(0, Math.min(selectedWindow, entries.length - 1));
        var selected = entries[selectedWindow];
        selectedIdentity = selected ? selected.address + ":" + selected.birth : "";
        Qt.callLater(ensureSelectionVisible);
    }

    function updateDesktops() {
        for (var index = desktopRows.count - 1; index >= 0; index--) if (desktops.indexOf(desktopRows.get(index).desktopId) < 0) {
            desktopRows.remove(index);
        }
        desktops.forEach(function(id, position) {
            if (position >= desktopRows.count || desktopRows.get(position).desktopId !== id)
                desktopRows.insert(position, {
                "desktopId": id
            });

        });
        var selected = desktops.indexOf(selectedDesktopId);
        selectedDesktop = selected >= 0 ? selected : Math.max(0, desktops.indexOf(currentDesktop));
    }

    function ensureSelectionVisible() {
        if (desktopsFocus) {
            var x = selectedDesktop * 240;
            desktopStrip.contentX = Math.max(0, Math.min(Math.max(0, desktopStrip.contentWidth - desktopStrip.width), Math.max(x + 220 - desktopStrip.width, Math.min(desktopStrip.contentX, x))));
        } else {
            var tile = windowRepeater.itemAt(selectedWindow);
            if (tile)
                windowScroll.contentY = Math.max(0, Math.min(Math.max(0, windowScroll.contentHeight - windowScroll.height), Math.max(tile.y + tile.height - windowScroll.height, Math.min(windowScroll.contentY, tile.y))));

        }
    }

    function selectWindow(w) {
        var live = Core.Windows.find("address:" + w.address);
        if (live && live.birth === w.birth)
            Core.Windows.focus(w.address);

        closeRequested();
    }

    function selectDesktop(index) {
        var id = desktops[index];
        if (id) {
            desktopsFocus = true;
            selectedDesktop = index;
            Core.Compositore.vaiAScrivania(id);
        }
    }
    function activateCurrent() {
        if (desktopsFocus)
            selectDesktop(selectedDesktop);
        else if (entries[selectedWindow])
            selectWindow(entries[selectedWindow]);
    }
    // I pulsanti hanno un proprio gestore di Invio. Una scorciatoia della
    // vista sceglie invece la selezione indicata dalle frecce, anche quando
    // un pulsante conserva il sottofuoco del FocusScope dopo un clic.
    Shortcut {
        sequence: "Return"
        enabled: view.visible && view.enabled && view.menuFinestra === null && view.menuDesktop === 0 && view.rinominando === 0
        onActivated: view.activateCurrent()
    }
    Shortcut {
        sequence: "Enter"
        enabled: view.visible && view.enabled && view.menuFinestra === null && view.menuDesktop === 0 && view.rinominando === 0
        onActivated: view.activateCurrent()
    }

    function apriMenuFinestra(w, punto) {
        view.menuDesktop = 0;
        view.menuFinestra = {
            "address": w.address,
            "birth": w.birth,
            "workspace": w.workspace
        };
        view.menuPunto = punto;
        Qt.callLater(function() {
            view.focusMove(0);
        });
    }

    function apriMenuDesktop(id, punto) {
        view.menuFinestra = null;
        view.menuDesktop = id;
        view.menuPunto = punto;
        Qt.callLater(function() {
            renameDesktop.forceActiveFocus();
        });
    }

    function focusMove(index) {
        if (index < 0)
            index = moveTargets.count;

        if (index >= moveTargets.count)
            moveNew.forceActiveFocus();
        else if (moveTargets.itemAt(index))
            moveTargets.itemAt(index).forceActiveFocus();
    }

    /// Sposta la finestra nel desktop `id` senza seguirla: si resta a
    /// guardare quello di prima, come in Windows. `id` 0 vuol dire «un
    /// desktop nuovo».
    function spostaIn(w, id) {
        view.menuFinestra = null;
        var live = Core.Windows.find("address:" + w.address);
        if (!live || live.birth !== w.birth)
            return ;

        if (id === 0) {
            for (var n = 1; n <= 10; n++) {
                if (view.desktops.indexOf(n) < 0) {
                    id = n;
                    break;
                }
            }
            if (id === 0)
                return ;

            Core.Ipc.setSetting("windows11.desktops", view.desktops.concat([id]));
        }
        Core.Compositore._nostro("portaascrivania", [Core.Compositore._selettore(live.address), String(id), "si"]);
    }

    function salvaNome(id, testo) {
        view.rinominando = 0;
        // Senza caratteri di controllo: il demone li rifiuterebbe tutti
        // insieme, e con loro gli altri nove nomi.
        Core.Tiling.nameWorkspace(id, String(testo).replace(/[\x00-\x1f]/g, " "));
        view.forceActiveFocus();
    }

    function newDesktop() {
        for (var id = 1; id <= 10; id++) if (desktops.indexOf(id) < 0) {
            Core.Ipc.setSetting("windows11.desktops", desktops.concat([id]));
            Core.Compositore.vaiAScrivania(id);
            return ;
        }
    }

    function removeDesktop(id) {
        if (desktops.length < 2)
            return ;

        var ids = desktops.filter(function(n) {
            return n !== id;
        }), destination = ids[Math.max(0, desktops.indexOf(id) - 1)];
        Core.Windows.all.filter(function(w) {
            return w.workspace === id;
        }).forEach(function(w) {
            Core.Compositore._nostro("portaascrivania", [Core.Compositore._selettore(w.address), String(destination), "si"]);
        });
        Core.Ipc.setSetting("windows11.desktops", ids);
        if (Core.Compositore.scrivaniaAttiva === id)
            Core.Compositore.vaiAScrivania(destination);

    }

    objectName: "windowsTaskView"
    onCurrentDesktopChanged: selectedDesktop = Math.max(0, desktops.indexOf(currentDesktop))
    onEntriesChanged: updateWindows()
    onDesktopsChanged: updateDesktops()
    onSelectedWindowChanged: {
        var w = entries[selectedWindow];
        selectedIdentity = w ? w.address + ":" + w.birth : "";
        Qt.callLater(ensureSelectionVisible);
    }
    onSelectedDesktopChanged: {
        selectedDesktopId = desktops[selectedDesktop] || 0;
        Qt.callLater(ensureSelectionVisible);
    }
    onDesktopsFocusChanged: {
        // Dopo una rinomina un pulsante conservava il fuoco: le frecce
        // cambiavano la scelta, ma Invio attivava quel vecchio pulsante.
        view.forceActiveFocus();
        Qt.callLater(ensureSelectionVisible);
    }
    onWatchedChanged: Core.Anteprime.watch(watchId, watched)
    Component.onCompleted: {
        updateWindows();
        updateDesktops();
        selectedDesktop = Math.max(0, desktops.indexOf(Core.Compositore.scrivaniaAttiva));
        forceActiveFocus();
        Core.Anteprime.watch(watchId, watched);
    }
    Component.onDestruction: Core.Anteprime.watch(watchId, null)
    Keys.onTabPressed: function(event) {
        desktopsFocus = !desktopsFocus;
        view.forceActiveFocus();
        event.accepted = true;
    }
    Keys.onLeftPressed: {
        if (desktopsFocus)
            selectedDesktop = Math.max(0, selectedDesktop - 1);
        else
            selectedWindow = Math.max(0, selectedWindow - 1);
        view.forceActiveFocus();
    }
    Keys.onRightPressed: {
        if (desktopsFocus)
            selectedDesktop = Math.min(desktops.length - 1, selectedDesktop + 1);
        else
            selectedWindow = Math.min(entries.length - 1, selectedWindow + 1);
        view.forceActiveFocus();
    }
    Keys.onUpPressed: {
        if (desktopsFocus)
            desktopsFocus = false;
        else
            selectedWindow = Math.max(0, selectedWindow - columns);
    }
    Keys.onDownPressed: {
        if (desktopsFocus)
            return ;
        else
            selectedWindow = Math.min(entries.length - 1, selectedWindow + columns);
    }
    // Esc chiude prima il menu «Sposta in»; senza menu passa a chi
    // contiene la vista, che la chiude.
    Keys.onEscapePressed: function(event) {
        if (view.menuFinestra !== null || view.menuDesktop !== 0) {
            view.menuFinestra = null;
            view.menuDesktop = 0;
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }
    Keys.onReturnPressed: {
        if (desktopsFocus)
            selectDesktop(selectedDesktop);
        else if (entries[selectedWindow])
            selectWindow(entries[selectedWindow]);
    }
    Keys.onEnterPressed: {
        if (desktopsFocus)
            selectDesktop(selectedDesktop);
        else if (entries[selectedWindow])
            selectWindow(entries[selectedWindow]);
    }

    WindowModel {
        id: windowRows
    }

    ListModel {
        id: desktopRows
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Style.surface, 0.65)
    }

    Rectangle {
        x: 8
        y: view.height - 202
        width: view.width - 16
        height: 194
        radius: 8
        color: Style.pannello
        border.color: Style.edge
    }

    Flickable {
        id: windowScroll

        x: 32
        y: 32
        width: parent.width - 64
        height: Math.max(80, parent.height - 240)
        contentWidth: width
        contentHeight: Math.max(height, windowsGrid.height)
        clip: true

        Grid {
            id: windowsGrid

            width: parent.width
            y: Math.max(0, (windowScroll.height - height) / 2)
            columns: view.columns
            spacing: 24

            Repeater {
                id: windowRepeater

                model: windowRows

                delegate: Button {
                    id: tile

                    required property string rowJson
                    required property int index
                    readonly property var modelData: JSON.parse(rowJson)
                    property string windowAddress: modelData.address
                    property int windowBirth: modelData.birth

                    objectName: "windowsTaskViewWindow-" + windowAddress
                    width: (windowsGrid.width - (view.columns - 1) * 24) / view.columns
                    height: Math.min(250, Math.max(150, view.height / 3))
                    selected: !view.desktopsFocus && view.selectedWindow === index
                    tooltip: modelData.title
                    onClicked: view.selectWindow(modelData)
                    onRightClicked: view.apriMenuFinestra(tile.modelData, tile.mapToItem(view, tile.width / 2, tile.height / 2))

                    Text {
                        x: 12
                        y: 8
                        width: parent.width - 48
                        text: tile.modelData.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.font
                        font.pixelSize: 13
                    }

                    Ui.WindowPreview {
                        id: windowImage

                        x: 8
                        y: 36
                        width: parent.width - 16
                        height: parent.height - 44
                        path: Core.Anteprime.images[tile.windowAddress] || ""
                    }

                    AppIcon {
                        anchors.centerIn: parent
                        width: 48
                        height: 48
                        path: {
                            var app = Core.Apps.forWindow(tile.modelData);
                            return app ? app.icon : "";
                        }
                        visible: !windowImage.ready
                    }

                    Button {
                        anchors.right: parent.right
                        y: 0
                        width: 32
                        height: 30
                        icon: "close"
                        tooltip: Style.label("Chiudi finestra", "Close window")
                        onClicked: {
                            var live = Core.Windows.find("address:" + tile.windowAddress);
                            if (live && live.birth === tile.windowBirth)
                                Core.Windows.close(live.address);

                        }
                    }
                    // Dragging moves this explicit surface, even for same-title/PID apps.

                    DragHandler {
                        id: drag

                        target: null
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                        onActiveChanged: {
                            if (active) {
                                view.draggingHandler = drag;
                                dragProxy.windowAddress = tile.windowAddress;
                                dragProxy.windowBirth = tile.windowBirth;
                                dragProxy.Drag.active = true;
                            } else {
                                dragProxy.Drag.drop();
                                dragProxy.Drag.active = false;
                                view.draggingHandler = null;
                            }
                        }
                    }

                }

            }

        }

    }

    Rectangle {
        id: dragProxy

        property string windowAddress: ""
        property int windowBirth: 0

        z: 20
        visible: view.draggingHandler !== null
        width: 160
        height: 100
        radius: 6
        color: Style.field
        border.color: Style.accent
        border.width: 2
        opacity: 0.9
        x: view.draggingHandler ? view.mapFromItem(null, view.draggingHandler.centroid.scenePosition.x, view.draggingHandler.centroid.scenePosition.y).x - width / 2 : 0
        y: view.draggingHandler ? view.mapFromItem(null, view.draggingHandler.centroid.scenePosition.x, view.draggingHandler.centroid.scenePosition.y).y - height / 2 : 0
        Drag.keys: ["minerva-window"]
        Drag.source: dragProxy
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        Ui.WindowPreview {
            anchors.fill: parent
            anchors.margins: 4
            path: Core.Anteprime.images[dragProxy.windowAddress] || ""
        }

    }

    Text {
        anchors.centerIn: parent
        visible: view.entries.length === 0
        text: Style.label("Nessuna finestra in questo desktop", "No windows on this desktop")
        color: Style.muted
        font.family: Style.font
        font.pixelSize: 18
    }

    Flickable {
        id: desktopStrip

        x: 32
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        width: parent.width - 64
        height: 180
        contentWidth: Math.max(width, desktopRow.width)
        contentHeight: 180
        clip: true
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: desktopRow

            x: Math.max(0, (desktopStrip.width - width) / 2)
            spacing: 20

            Repeater {
                model: desktopRows

                delegate: Item {
                    id: desktop

                    required property int desktopId
                    required property int index
                    readonly property int modelData: desktopId
                    readonly property bool selected: view.desktopsFocus && view.selectedDesktop === index

                    width: 220
                    height: 176

                    Button {
                        id: desktopButton

                        objectName: "windowsDesktop-" + desktop.modelData
                        clip: true
                        width: 220
                        height: 142
                        selected: desktop.selected || Core.Compositore.scrivaniaAttiva === desktop.modelData
                        tooltip: Core.Tiling.workspaceNames[desktop.modelData - 1] || Style.label("Desktop ", "Desktop ") + desktop.modelData
                        onRightClicked: view.apriMenuDesktop(desktop.modelData, desktopButton.mapToItem(view, desktopButton.width / 2, 0))
                        onClicked: view.selectDesktop(desktop.index)

                        Image {
                            anchors.fill: parent
                            anchors.margins: 6
                            source: "file://" + Core.Wallpaper.current
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 440
                            sourceSize.height: 270
                            asynchronous: true
                        }

                        WindowModel {
                            id: desktopWindows

                            property var sourceWindows: Core.Windows.all.filter(function(w) {
                                return w.workspace === desktop.modelData && !w.minimized && (!view.output || !w.output || w.output === view.output);
                            })

                            onSourceWindowsChanged: update(sourceWindows)
                            Component.onCompleted: update(sourceWindows)
                        }

                        Repeater {
                            model: desktopWindows

                            delegate: Ui.WindowPreview {
                                required property string rowJson
                                readonly property var modelData: JSON.parse(rowJson)
                                readonly property var area: Core.Windows.spazioPer(modelData)
                                readonly property real scaleX: 208 / Math.max(1, area ? area.w : 1920)
                                readonly property real scaleY: 130 / Math.max(1, area ? area.h : 1080)

                                x: 6 + Math.max(0, modelData.x - (area ? area.x : 0)) * scaleX
                                y: 6 + Math.max(0, modelData.y - (area ? area.y : 0)) * scaleY
                                width: Math.min(208, modelData.w * scaleX)
                                height: Math.min(130, modelData.h * scaleY)
                                path: Core.Anteprime.images[modelData.address] || ""
                            }

                        }

                        Button {
                            anchors.right: parent.right
                            width: 30
                            height: 30
                            icon: "close"
                            visible: view.desktops.length > 1
                            tooltip: Style.label("Chiudi desktop", "Close desktop")
                            onClicked: view.removeDesktop(desktop.modelData)
                        }

                        DropArea {
                            anchors.fill: parent
                            keys: ["minerva-window"]
                            onDropped: function(event) {
                                var source = event.source, w = source ? Core.Windows.find("address:" + source.windowAddress) : null;
                                if (w && w.birth === source.windowBirth)
                                    Core.Compositore._nostro("portaascrivania", [Core.Compositore._selettore(w.address), String(desktop.modelData), "si"]);

                                event.acceptProposedAction();
                            }
                        }

                    }

                    Text {
                        id: nomeDesktop

                        objectName: "windowsDesktopName-" + desktop.modelData
                        y: 152
                        width: parent.width
                        visible: view.rinominando !== desktop.modelData
                        text: Core.Tiling.workspaceNames[desktop.modelData - 1] || Style.label("Desktop ", "Desktop ") + desktop.modelData
                        textFormat: Text.PlainText
                        color: Style.text
                        font.family: Style.font
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onDoubleClicked: view.rinominando = desktop.modelData
                            onClicked: function(event) {
                                if (event.button === Qt.RightButton)
                                    view.rinominando = desktop.modelData;

                            }
                        }

                    }
                    // Il nome mentre lo si scrive: Invio salva, Esc lascia com'era.

                    Rectangle {
                        y: 148
                        width: parent.width
                        height: 26
                        visible: view.rinominando === desktop.modelData
                        radius: 4
                        color: Style.field
                        border.width: 2
                        border.color: Style.accentIndicator

                        TextInput {
                            id: campoNome

                            objectName: "windowsDesktopRename-" + desktop.modelData
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            clip: true
                            maximumLength: 40
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 13
                            selectByMouse: true
                            onVisibleChanged: {
                                if (!visible)
                                    return ;

                                text = Core.Tiling.workspaceNames[desktop.modelData - 1] || "";
                                forceActiveFocus();
                                selectAll();
                            }
                            Keys.onReturnPressed: function(event) {
                                view.salvaNome(desktop.modelData, text);
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: function(event) {
                                view.salvaNome(desktop.modelData, text);
                                event.accepted = true;
                            }
                            Keys.onEscapePressed: function(event) {
                                view.rinominando = 0;
                                view.forceActiveFocus();
                                event.accepted = true;
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && view.rinominando === desktop.modelData) {
                                    view.salvaNome(desktop.modelData, text);
                                }
                            }
                        }

                    }

                }

            }

            Button {
                objectName: "windowsNewDesktop"
                width: 220
                height: 142
                icon: "plus"
                text: Style.label("Nuovo desktop", "New desktop")
                enabled: view.desktops.length < 10
                selected: true
                onClicked: view.newDesktop()
            }

        }

    }

    // ── Il menu «Sposta in» ─────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 29
        visible: view.menuFinestra !== null || view.menuDesktop !== 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
            view.menuFinestra = null;
            view.menuDesktop = 0;
        }
    }

    Rectangle {
        id: menuSposta

        readonly property var mete: view.menuFinestra ? view.desktops.filter(function(d) {
            return d !== view.menuFinestra.workspace;
        }) : []

        objectName: "windowsTaskViewMoveMenu"
        z: 30
        visible: view.menuFinestra !== null || view.menuDesktop !== 0
        width: 240
        height: colonnaSposta.implicitHeight + 8
        x: Math.max(8, Math.min(view.width - width - 8, view.menuPunto.x))
        y: Math.max(8, Math.min(view.height - height - 8, view.menuPunto.y))
        radius: 8
        color: Style.field
        border.color: Style.edge

        Column {
            id: colonnaSposta

            x: 4
            y: 4
            width: parent.width - 8

            Text {
                width: parent.width
                height: 30
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                text: view.menuDesktop ? Style.label("Desktop", "Desktop") : Style.label("Sposta in", "Move to")
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 12
            }

            Repeater {
                id: moveTargets

                model: menuSposta.mete

                delegate: Button {
                    required property int modelData
                    required property int index

                    Keys.onDownPressed: view.focusMove(index + 1)
                    Keys.onUpPressed: view.focusMove(index - 1)
                    objectName: "windowsTaskViewMoveTo-" + modelData
                    width: parent.width
                    height: 36
                    text: Core.Tiling.workspaceNames[modelData - 1] || Style.label("Desktop ", "Desktop ") + modelData
                    onClicked: view.spostaIn(view.menuFinestra, modelData)
                }

            }

            Button {
                id: moveNew

                visible: view.menuDesktop === 0
                height: visible ? 34 : 0
                objectName: "windowsTaskViewMoveToNew"
                Keys.onUpPressed: view.focusMove(moveTargets.count - 1)
                Keys.onDownPressed: view.focusMove(0)
                width: parent.width
                icon: "plus"
                text: Style.label("Nuovo desktop", "New desktop")
                enabled: view.desktops.length < 10
                onClicked: view.spostaIn(view.menuFinestra, 0)
            }

            Button {
                id: renameDesktop

                objectName: "windowsDesktopMenu-rename"
                visible: view.menuDesktop !== 0
                height: visible ? 34 : 0
                width: parent.width
                text: Style.label("Rinomina", "Rename")
                Keys.onDownPressed: closeDesktop.forceActiveFocus()
                onClicked: {
                    view.rinominando = view.menuDesktop;
                    view.menuDesktop = 0;
                }
            }

            Button {
                id: closeDesktop

                objectName: "windowsDesktopMenu-close"
                visible: view.menuDesktop !== 0
                enabled: view.desktops.length > 1
                height: visible ? 34 : 0
                width: parent.width
                text: Style.label("Chiudi desktop", "Close desktop")
                Keys.onUpPressed: renameDesktop.forceActiveFocus()
                onClicked: {
                    var id = view.menuDesktop;
                    view.menuDesktop = 0;
                    view.removeDesktop(id);
                }
            }

        }

    }

    Ui.Scorrimento {
        objectName: "windowsOverviewScrollBar"
        tinta: Style.muted
        bersaglio: windowScroll
        anchors.right: windowScroll.right
        anchors.top: windowScroll.top
        anchors.bottom: windowScroll.bottom
    }

    Ui.Scorrimento {
        objectName: "windowsDesktopScrollBar"
        tinta: Style.muted
        bersaglio: desktopStrip
        orizzontale: true
        anchors.left: desktopStrip.left
        anchors.right: desktopStrip.right
        anchors.bottom: desktopStrip.bottom
        height: 18
    }

}
