import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

// La striscia non possiede percorsi né selezioni: riordina i riquadri vivi,
// conservando la loro identità e la scheda attiva anche dopo una chiusura.
Item {
    id: strip

    required property var controller
    readonly property bool windows: Core.DesktopStyle.attuale === "windows"
    readonly property real tabWidth: Math.max(120, Math.min(210, scroll.width / Math.max(1, Math.min(4, controller.tabs.count)) - row.spacing))

    height: strip.windows ? 40 : 42
    objectName: "fileTabs"

    Flickable {
        id: scroll

        function reveal() {
            var left = strip.controller.currentIndex * (strip.tabWidth + row.spacing);
            contentX = Math.max(0, Math.min(left, Math.max(0, contentWidth - width)));
        }

        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: 8
        height: parent.height
        contentWidth: row.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: row

            spacing: 4
            height: parent.height

            Repeater {
                model: strip.controller.tabs

                delegate: Rectangle {
                    id: tab

                    required property int index
                    required property string identity
                    readonly property var pane: strip.controller.panes[index] || null
                    readonly property bool selected: index === strip.controller.currentIndex
                    readonly property string label: pane && pane.recenti ? (Core.Strings.lang === "it" ? "Recenti" : "Recent") : Files.baseName(pane ? pane.path : "") || "/"

                    width: strip.tabWidth
                    height: strip.windows ? 36 : 34
                    y: 4
                    radius: strip.windows ? 7 : Theme.Effects.radiusSM
                    color: selected ? (strip.windows ? FileStyle.lettura : FileStyle.raised) : mouse.containsMouse ? FileStyle.hover : "transparent"
                    border.width: selected ? 1 : 0
                    border.color: FileStyle.edge
                    objectName: "fileTab-" + identity
                    Accessible.role: Accessible.PageTab
                    Accessible.name: label
                    Accessible.selected: selected

                    FileIcon {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        name: Files.iconFor({
                            "isDir": true,
                            "path": tab.pane ? tab.pane.path : ""
                        })
                        color: FileStyle.accent
                    }

                    Text {
                        x: 36
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 62
                        text: tab.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: FileStyle.font
                        font.pixelSize: 12
                        color: tab.selected ? FileStyle.text : FileStyle.textMuted
                    }

                    MouseArea {
                        id: mouse

                        property real startX: 0
                        property bool moved: false

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        preventStealing: true
                        onPressed: function(event) {
                            startX = mapToItem(row, event.x, event.y).x;
                            moved = false;
                        }
                        onPositionChanged: function(event) {
                            if (pressedButtons & Qt.LeftButton)
                                moved = moved || Math.abs(mapToItem(row, event.x, event.y).x - startX) > 12;

                        }
                        onReleased: function(event) {
                            if (event.button !== Qt.LeftButton || !moved)
                                return ;

                            var position = mapToItem(row, event.x, event.y).x;
                            var target = Math.max(0, Math.min(strip.controller.tabs.count - 1, Math.floor(position / (strip.tabWidth + row.spacing))));
                            strip.controller.moveTab(tab.index, target);
                        }
                        onClicked: function(event) {
                            if (event.button === Qt.MiddleButton)
                                strip.controller.closeTab(tab.index);
                            else if (!moved)
                                strip.controller.focusIndex(tab.index);
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        radius: 4
                        visible: strip.controller.tabs.count > 1
                        color: closeMouse.containsMouse ? FileStyle.hover : "transparent"

                        Ui.Icon {
                            anchors.centerIn: parent
                            width: 10
                            height: 10
                            name: "close"
                            alwaysDrawn: true
                            color: FileStyle.textMuted
                        }

                        MouseArea {
                            id: closeMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: strip.controller.closeTab(tab.index)
                        }

                    }

                    DropArea {
                        anchors.fill: parent
                        keys: ["text/uri-list"]
                        onEntered: strip.controller.focusIndex(tab.index)
                    }

                }

            }

        }

    }

    Row {
        id: actions

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: ["add", "layout"]

            delegate: Rectangle {
                required property string modelData

                width: 32
                height: 32
                radius: 5
                color: actionMouse.containsMouse ? FileStyle.hover : "transparent"
                objectName: "fileTabs-" + modelData
                Accessible.role: Accessible.Button
                Accessible.name: modelData === "add" ? (Core.Strings.lang === "it" ? "Nuova scheda" : "New tab") : (Core.Strings.lang === "it" ? "Schede o affiancamento" : "Tabs or split view")
                opacity: enabled ? 1 : 0.4
                enabled: modelData !== "add" || strip.controller.tabs.count < strip.controller.maxTabs

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    name: parent.modelData === "add" ? "plus" : "apps"
                    color: FileStyle.textMuted
                    alwaysDrawn: true
                }

                MouseArea {
                    id: actionMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (parent.modelData === "add")
                            strip.controller.addTab();
                        else
                            strip.controller.toggleLayout();
                    }
                }

                Ui.ToolTipHint {
                    anchors.fill: parent
                    shown: actionMouse.containsMouse
                    text: parent.modelData === "add" ? "Ctrl+T" : (strip.controller.tabbed ? (Core.Strings.lang === "it" ? "Affianca cartelle" : "Split folders") : (Core.Strings.lang === "it" ? "Mostra a schede" : "Show tabs"))
                }

            }

        }

    }

    Connections {
        function onCurrentIndexChanged() {
            Qt.callLater(scroll.reveal);
        }

        target: strip.controller
    }

}
