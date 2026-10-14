import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../menu" as Menu

Item {
    id: tray
    objectName: "windowsTray"
    readonly property bool menuOpen: actions.visible
    property var screen: null
    property var entries: SystemTray.items.values || []
    property bool expanded: false
    property QtObject menuOwner: null
    property var menuRoot: null
    property bool menuPending: false
    property bool menuUpdateScheduled: false
    property int menuGeneration: 0
    property var menuAnchor: null
    readonly property var menuEntries: tree.entries
    readonly property var menuItems: tree.items
    property alias contextMenu: actions
    signal toggleRequested()
    signal closeRequested()
    implicitWidth: entries.length > 0 ? 28 : 0
    implicitHeight: 40

    onEntriesChanged: {
        if (menuOwner && entries.indexOf(menuOwner) < 0) {
            actions.close();
            clearMenu();
        }
    }

    function clearMenu() {
        menuPending = false;
        menuRoot = null;
        menuOwner = null;
    }

    function openMenu(owner, anchor) {
        actions.close();
        releaseMenu.stop();
        clearMenu();
        menuGeneration++;
        menuOwner = owner;
        menuAnchor = anchor || null;
        menuPending = true;
        menuRoot = owner ? owner.menu : null;
        presentMenu();
    }

    function presentMenu() {
        // Un riordino del modello rimuove e ricrea più delegate nello stesso
        // giro: mostriamo il risultato intero, non gli stati intermedi vuoti.
        if (menuUpdateScheduled)
            return;
        menuUpdateScheduled = true;
        Qt.callLater(function() {
            tray.menuUpdateScheduled = false;
            tray.presentMenuNow();
        });
    }

    function presentMenuNow() {
        if (!tree.items.length) {
            // Durante il primo caricamento aspettiamo D-Bus. Se invece il
            // servizio svuota un menu già aperto, le vecchie azioni decadono.
            if (actions.visible)
                actions.close();
            return;
        }
        if (menuPending) {
            menuPending = false;
            if (menuAnchor)
                actions.openAt(menuAnchor.x, menuAnchor.y, tree.items);
            else
                actions.openAtCursor(tree.items);
        } else if (!actions.visible && actions._inArrivo !== null) {
            actions._inArrivo = tree.items;
        } else if (actions.visible) {
            // Icone, spunte e disponibilità possono cambiare a menu aperto.
            actions.items = tree.items;
        }
    }

    Button {
        objectName: "windowsTrayToggle"
        width: 28
        height: 40
        icon: "chevronUp"
        tooltip: Style.label("Icone nascoste", "Hidden icons")
        visible: tray.entries.length > 0
        selected: tray.expanded
        onClicked: tray.toggleRequested()
    }

    // Le voci D-Bus devono restare vive fino al segnale triggered: ContextMenu
    // emette dismissed prima dell'azione, quindi le liberiamo al giro seguente.
    Timer {
        id: releaseMenu
        interval: 0
        onTriggered: tray.clearMenu()
    }
    TrayMenuModel {
        id: tree
        source: tray.menuRoot
        prefix: String(tray.menuGeneration)
        onItemsChanged: tray.presentMenu()
    }
    Menu.ContextMenu {
        id: actions
        screen: tray.screen
        windowsAppearance: true
        bottomInset: 48
        onDismissed: releaseMenu.restart()
        onTriggered: function(action) {
            var entry = tree.find(action);
            if (entry && entry.enabled !== false && !entry.hasChildren)
                entry.triggered();
            releaseMenu.restart();
        }
    }

    property Component panel: Component {
        Rectangle {
            id: overflow
            color: Style.pannello
            radius: 8
            border.color: Style.edge
            property int selectedIndex: 0

            function focusEntry(index) {
                var button = buttons.itemAt(Math.max(0, Math.min(index, buttons.count - 1)));
                if (button)
                    button.forceActiveFocus(Qt.TabFocusReason);
            }
            Keys.onLeftPressed: focusEntry(selectedIndex - 1)
            Keys.onRightPressed: focusEntry(selectedIndex + 1)
            Keys.onUpPressed: focusEntry(selectedIndex - 4)
            Keys.onDownPressed: focusEntry(selectedIndex + 4)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                    focusEntry(event.key === Qt.Key_Home ? 0 : buttons.count - 1);
                    event.accepted = true;
                }
            }
            Component.onCompleted: Qt.callLater(function() { overflow.focusEntry(0); })

            Grid {
                anchors.fill: parent
                anchors.margins: 12
                columns: 4
                spacing: 8
                Repeater {
                    id: buttons
                    model: tray.entries
                    delegate: Button {
                        required property var modelData
                        required property int index
                        objectName: "windowsTrayItem-" + modelData.title
                        width: 32
                        height: 32
                        tooltip: modelData.title || modelData.tooltipTitle || ""
                        onActiveFocusChanged: if (activeFocus) overflow.selectedIndex = index
                        Keys.onMenuPressed: {
                            tray.openMenu(modelData, mapToItem(null, 0, height));
                            tray.closeRequested();
                        }
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier) {
                                tray.openMenu(modelData, mapToItem(null, 0, height));
                                tray.closeRequested();
                                event.accepted = true;
                            }
                        }
                        AppIcon {
                            anchors.centerIn: parent
                            path: parent.modelData.icon
                            width: 20
                            height: 20
                        }
                        onClicked: {
                            if (modelData.onlyMenu)
                                tray.openMenu(modelData);
                            else
                                modelData.activate();
                            tray.closeRequested();
                        }
                        onRightClicked: {
                            tray.openMenu(modelData);
                            tray.closeRequested();
                        }
                        onMiddleClicked: {
                            modelData.secondaryActivate();
                            tray.closeRequested();
                        }
                    }
                }
            }
        }
    }
}
