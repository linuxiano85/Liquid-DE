import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core" as Core
PanelWindow {
    id: toast
    property var items: []
    property bool locked:false
    visible:items.length>0
    anchors {right:true;bottom:true}
    // Include the shadow in the Wayland surface; its edges must not be clipped.
    margins {right:0;bottom:24}
    implicitWidth:424;implicitHeight:stack.height+64
    color:"transparent";exclusionMode:ExclusionMode.Ignore
    WlrLayershell.namespace:"liquid-windows-toast"
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
    function remove(id){items=items.filter(function(item){return item.id!==id;});}
    Connections {target:Core.Notifications
        function onArrived(item) {
            if(toast.locked || Core.Notifications.inSilenzio)return;
            toast.items=toast.items.filter(function(old){return old.id!==item.id;}).concat([item]).slice(-3);
        }
    }
    mask:Region {item:stack}
    Column {id:stack;x:32;y:24;width:360;spacing:12
        Repeater {model:toast.items;delegate:Rectangle {
            id:card;required property var modelData;width:stack.width;height:body.height+64;radius:8;color:Style.pannello;border.color:Style.edge
            Shadow {}
            MouseArea {anchors.fill:parent;onClicked:{Core.Notifications.apri(card.modelData);toast.remove(card.modelData.id);}}
            Column {id:body;x:20;y:20;width:parent.width-58;spacing:8
                Text {width:parent.width;text:card.modelData.appName || "";textFormat:Text.PlainText;elide:Text.ElideRight;color:Style.muted;font.family:Style.font;font.pixelSize:12}
                Text {width:parent.width;text:card.modelData.summary || "";textFormat:Text.PlainText;wrapMode:Text.WordWrap;maximumLineCount:2;elide:Text.ElideRight;color:Style.text;font.family:Style.font;font.pixelSize:14;font.weight:Font.DemiBold}
                Text {width:parent.width;text:card.modelData.body || "";textFormat:Text.PlainText;wrapMode:Text.WordWrap;maximumLineCount:3;elide:Text.ElideRight;color:Style.text;font.family:Style.font;font.pixelSize:13}
            }
            Button {anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;width:28;height:28;icon:"close";tooltip:Style.label("Nascondi notifica","Hide notification");onClicked:toast.remove(card.modelData.id)}
            HoverHandler {id:hover}
            Timer {interval:Math.min(10000,Math.max(3000,card.modelData.timeout || 6000));running:!hover.hovered;onTriggered:toast.remove(card.modelData.id)}
        }}
    }
    Connections {target:Core.Compositore;function onBloccoCambiato(locked){toast.locked=locked;if(locked)toast.items=[];}}
}
