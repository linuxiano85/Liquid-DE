import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../menu" as Menu
Item {
    id: tray
    objectName:"windowsTray"
    readonly property bool menuOpen:actions.visible
    property var screen: null
    property var entries: SystemTray.items.values || []
    property bool expanded: false
    signal toggleRequested()
    signal closeRequested()
    property var menuEntries: []
    implicitWidth: entries.length>0 ? 28:0
    implicitHeight:40
    Button {objectName:"windowsTrayToggle";width:28;height:40;icon:"chevronUp";tooltip:Style.label("Icone nascoste","Hidden icons");visible:tray.entries.length>0;selected:tray.expanded;onClicked:tray.toggleRequested()}
    // A separate input region avoids covering the applications underneath.
    Menu.ContextMenu {
        id: actions;screen:tray.screen;windowsAppearance:true
        onTriggered:function(action) {var item=tray.menuEntries[Number(action)];if(item && item.enabled!==false){if(item.hasChildren){tray.menuEntries=item.children.values;actions.openAtCursor(tray.menuEntries.map(function(child,index){return child.isSeparator ? {separator:true}:{label:child.text || "",action:String(index),enabled:child.enabled!==false};}));}else item.triggered();}}
    }
    function openMenu(root) {
        opener.menu=root;
        var items=opener.children ? opener.children.values:[];
        if(items.length===0){retry.restart();return;}
        menuEntries=items;
        actions.openAtCursor(items.map(function(item,index) {return item.isSeparator ? {separator:true}:{label:item.text || "",action:String(index),enabled:item.enabled!==false};}));
    }
    Timer {id:retry;interval:150;onTriggered: {var items=opener.children ? opener.children.values:[];if(items.length>0){tray.menuEntries=items;actions.openAtCursor(items.map(function(item,index){return item.isSeparator ? {separator:true}:{label:item.text || "",action:String(index),enabled:item.enabled!==false};}));}}}
    QsMenuOpener {id:opener}
    property Component panel:Component {Rectangle {
        color:Style.pannello;radius:8;border.color:Style.edge
        Grid {anchors.fill:parent;anchors.margins:12;columns:4;spacing:8
            Repeater {model:tray.entries;delegate:Button {
                required property var modelData;objectName:"windowsTrayItem-"+modelData.title;width:32;height:32;tooltip:modelData.title || modelData.tooltipTitle || ""
                AppIcon {anchors.centerIn:parent;path:parent.modelData.icon;width:20;height:20}
                onClicked:{if(modelData.onlyMenu)tray.openMenu(modelData.menu);else modelData.activate();tray.closeRequested();}
                onRightClicked:{tray.openMenu(modelData.menu);tray.closeRequested();}
                onMiddleClicked:{modelData.secondaryActivate();tray.closeRequested();}
            }}
        }
    }}
}
