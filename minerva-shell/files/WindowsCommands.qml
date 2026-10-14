import "../core" as Core
import "../ui" as Ui
import "../windows11" as Windows
import QtQuick
import QtQuick.Controls as Controls

Item {
    id: bar

    required property var controller
    readonly property var pane: controller.current
    readonly property bool compact: width < 620
    readonly property bool selected: pane && pane.selection.length > 0
    readonly property bool writable: pane && (pane.scrivibile || controller.amministratore)
    readonly property bool trash: pane && Files.inTrash(pane.path)
    property string menu: ""
    property alias menuContent: popupBody
    readonly property bool menuVisible: commandMenu.visible
    readonly property var commands: [{
        "id": "new",
        "icon": "plus",
        "label": Windows.Style.label("Nuovo", "New")
    }, {
        "id": "cut",
        "icon": "cut",
        "label": Windows.Style.label("Taglia", "Cut")
    }, {
        "id": "copy",
        "icon": "copy",
        "label": Windows.Style.label("Copia", "Copy")
    }, {
        "id": "paste",
        "icon": "paste",
        "label": Windows.Style.label("Incolla", "Paste")
    }, {
        "id": "rename",
        "icon": "rename",
        "label": Windows.Style.label("Rinomina", "Rename")
    }, {
        "id": "delete",
        "icon": "delete",
        "label": Windows.Style.label("Sposta nel cestino", "Move to Recycle Bin")
    }, {
        "id": "sort",
        "icon": "sort",
        "label": Windows.Style.label("Ordina", "Sort")
    }, {
        "id": "view",
        "icon": "view",
        "label": Windows.Style.label("Visualizza", "View")
    }, {
        "id": "more",
        "icon": "more",
        "label": Windows.Style.label("Altre opzioni", "More options")
    }]
    readonly property var menuItems: {
        if (menu === "new")
            return [{
            "id": "newFolder",
            "icon": "folder",
            "label": Windows.Style.label("Cartella", "Folder")
        }, {
            "id": "newFile",
            "icon": "document",
            "label": Windows.Style.label("Documento", "Document")
        }];

        if (menu === "sort")
            return [{
            "id": "sort-name",
            "label": Windows.Style.label("Nome", "Name"),
            "checked": pane && pane.sortBy === "name"
        }, {
            "id": "sort-modified",
            "label": Windows.Style.label("Data di modifica", "Date modified"),
            "checked": pane && pane.sortBy === "modified"
        }, {
            "id": "sort-type",
            "label": Windows.Style.label("Tipo", "Type"),
            "checked": pane && pane.sortBy === "type"
        }, {
            "id": "sort-size",
            "label": Windows.Style.label("Dimensione", "Size"),
            "checked": pane && pane.sortBy === "size"
        }, {
            "separator": true
        }, {
            "id": "ascending",
            "label": Windows.Style.label("Crescente", "Ascending"),
            "checked": pane && !pane.sortDesc
        }, {
            "id": "descending",
            "label": Windows.Style.label("Decrescente", "Descending"),
            "checked": pane && pane.sortDesc
        }];

        if (menu === "view")
            return [{
            "id": "grid",
            "icon": "grid",
            "label": Windows.Style.label("Icone", "Icons"),
            "checked": pane && pane.viewMode === "grid"
        }, {
            "id": "list",
            "icon": "view",
            "label": Windows.Style.label("Dettagli", "Details"),
            "checked": pane && pane.viewMode === "list"
        }, {
            "separator": true
        }, {
            "id": "checkboxes",
            "label": Windows.Style.label("Caselle di selezione", "Item check boxes"),
            "checked": Core.Ipc.get("files.caselleSelezione", false)
        }, {
            "id": "hidden",
            "label": Windows.Style.label("Elementi nascosti", "Hidden items"),
            "checked": pane && pane.showHidden
        }, {
            "separator": true
        }, {
            "id": "detailsPane",
            "label": Windows.Style.label("Riquadro dettagli", "Details pane"),
            "checked": controller.pannelloLaterale === "dettagli"
        }, {
            "id": "previewPane",
            "label": Windows.Style.label("Riquadro di anteprima", "Preview pane"),
            "checked": controller.pannelloLaterale === "anteprima"
        }];

        return [{
            "id": "refresh",
            "icon": "refresh",
            "label": Windows.Style.label("Aggiorna", "Refresh")
        }, {
            "id": "selectAll",
            "label": Windows.Style.label("Seleziona tutto", "Select all")
        }, {
            "id": "properties",
            "label": Windows.Style.label("Proprietà", "Properties"),
            "available": selected
        }, {
            "separator": true
        }, {
            "id": "split",
            "label": Windows.Style.label("Affianca cartelle", "Split folders"),
            "checked": !controller.tabbed
        }];
    }

    function available(id) {
        if (id === "cut" || id === "rename" || id === "delete")
            return selected && writable && !trash;

        if (id === "copy")
            return selected;

        if (id === "paste")
            return writable && !trash && Files.puoiIncollare;

        if (id === "new")
            return writable && !trash;

        return !!pane;
    }

    function focusMenu(index, direction) {
        for (var i = index; i >= 0 && i < menuRepeater.count; i += direction) {
            var button = menuRepeater.itemAt(i);
            if (!button || !button.enabled)
                continue;

            button.forceActiveFocus(Qt.TabFocusReason);
            menuScroll.contentY = Math.max(0, Math.min(Math.max(0, menuScroll.contentHeight - menuScroll.height), button.y - (menuScroll.height - button.height) / 2));
            return ;
        }
    }

    function openMenu(id, button) {
        menu = id;
        var point = button.mapToItem(controller.contentItem, 0, button.height + 8);
        commandMenu.x = Math.max(8, Math.min(controller.contentItem.width - commandMenu.width - 8, point.x));
        commandMenu.y = point.y;
        commandMenu.open();
    }

    function activate(id) {
        if (controller.dialogOpen)
            return ;

        commandMenu.close();
        if (id === "cut") {
            controller.doCut();
        } else if (id === "copy") {
            controller.doCopy();
        } else if (id === "paste") {
            controller.doPaste();
        } else if (id === "rename") {
            controller.doRename();
        } else if (id === "delete") {
            controller.doTrash();
        } else if (id === "newFolder") {
            controller.doNewFolder();
        } else if (id === "newFile") {
            controller.doNewFile();
        } else if (id.indexOf("sort-") === 0) {
            pane.sortByColumn(id.slice(5));
        } else if (id === "ascending" || id === "descending") {
            pane.sortDesc = id === "descending";
            Files.rememberSort(pane.sortBy, pane.sortDesc);
        } else if (id === "grid" || id === "list")
            pane.setViewMode(id);
        else if (id === "hidden")
            pane.commutaNascosti();
        else if (id === "checkboxes")
            Core.Ipc.setSetting("files.caselleSelezione", !Core.Ipc.get("files.caselleSelezione", false));
        else if (id === "refresh")
            pane.reload();
        else if (id === "selectAll")
            pane.selectAll();
        else if (id === "properties")
            controller.doProperties();
        else if (id === "split")
            controller.toggleLayout();
        else if (id === "detailsPane")
            controller.commutaPannello("dettagli");
        else if (id === "previewPane")
            controller.commutaPannello("anteprima");
    }

    objectName: "filesWindowsCommands"
    // I pulsanti mantengono la propria identità quando cambia la selezione:
    // cambia solo enabled, altrimenti un aggiornamento perde il clic/fuoco.
    onVisibleChanged: {
        if (!visible)
            commandMenu.close();

    }

    Rectangle {
        anchors.fill: parent
        color: FileStyle.lettura

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: FileStyle.edge
        }

    }

    Flickable {
        id: scroll

        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        clip: true
        contentWidth: buttons.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: buttons

            height: scroll.height
            spacing: 4

            Repeater {
                model: bar.commands

                delegate: Windows.Button {
                    id: button

                    required property var modelData
                    readonly property bool caption: !bar.compact && ["new", "sort", "view"].indexOf(modelData.id) >= 0

                    objectName: "filesCommand-" + modelData.id
                    width: caption ? labelRow.implicitWidth + 24 : 36
                    height: 34
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: bar.available(modelData.id) && !bar.controller.dialogOpen
                    opacity: enabled ? 1 : 0.4
                    tooltip: modelData.label
                    selected: commandMenu.visible && bar.menu === modelData.id
                    onClicked: {
                        if (["new", "sort", "view", "more"].indexOf(modelData.id) >= 0)
                            bar.openMenu(modelData.id, button);
                        else
                            bar.activate(modelData.id);
                    }

                    Row {
                        id: labelRow

                        anchors.centerIn: parent
                        spacing: 8

                        CommandGlyph {
                            width: 18
                            height: 18
                            name: button.modelData.icon
                        }

                        Text {
                            visible: button.caption
                            text: button.modelData.label
                            color: FileStyle.text
                            font.family: FileStyle.font
                            font.pixelSize: 13
                        }

                        CommandGlyph {
                            visible: button.caption
                            width: 12
                            height: 12
                            name: "chevron"
                        }

                    }

                }

            }

        }

    }

    Ui.Scorrimento {
        objectName: "filesCommandScrollBar"
        bersaglio: scroll
        orizzontale: true
        tinta: FileStyle.textMuted
        anchors.left: scroll.left
        anchors.right: scroll.right
        anchors.bottom: scroll.bottom
    }

    Controls.Popup {
        id: commandMenu

        parent: bar.controller.contentItem
        width: 236
        height: Math.min(menuColumn.implicitHeight + 16, Math.max(40, bar.controller.contentItem.height - y - 12))
        padding: 8
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
        onOpened: bar.focusMenu(0, 1)
        onClosed: bar.menu = ""

        background: Rectangle {
            radius: 8
            color: FileStyle.panel
            border.color: FileStyle.edge
        }

        contentItem: Item {
            id: popupBody

            Flickable {
                id: menuScroll

                anchors.fill: parent
                anchors.rightMargin: contentHeight > height ? 18 : 0
                contentHeight: menuColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: menuColumn

                    width: menuScroll.width
                    spacing: 2

                    Repeater {
                        id: menuRepeater

                        model: bar.menuItems

                        delegate: Windows.Button {
                            required property var modelData
                            required property int index

                            Keys.onDownPressed: bar.focusMenu(index + 1, 1)
                            Keys.onUpPressed: bar.focusMenu(index - 1, -1)
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Home)
                                    bar.focusMenu(0, 1);
                                else if (event.key === Qt.Key_End)
                                    bar.focusMenu(menuRepeater.count - 1, -1);
                                else
                                    return;
                                event.accepted = true;
                            }
                            objectName: modelData.separator ? "" : "filesMenu-" + modelData.id
                            width: menuColumn.width
                            height: modelData.separator ? 9 : 32
                            enabled: !modelData.separator && modelData.available !== false && !bar.controller.dialogOpen
                            opacity: modelData.available === false ? 0.4 : 1
                            tooltip: modelData.label || ""
                            text: ""
                            onClicked: bar.activate(modelData.id)

                            Rectangle {
                                visible: parent.modelData.separator === true
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 1
                                color: FileStyle.edge
                            }

                            CommandGlyph {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                name: parent.modelData.checked ? "check" : parent.modelData.icon || ""
                            }

                            Text {
                                x: 34
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 42
                                text: parent.modelData.label || ""
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: FileStyle.text
                                font.family: FileStyle.font
                                font.pixelSize: 13
                            }

                        }

                    }

                }

            }

            Ui.Scorrimento {
                objectName: "filesMenuScrollBar"
                bersaglio: menuScroll
                tinta: FileStyle.textMuted
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
            }

        }

    }

}
