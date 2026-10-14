import QtQuick
import QtQuick.Controls
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

Rectangle {
    id: overview
    objectName: "panoramicaStanze"
    property var monitor
    property int selectedWorkspace: 1
    property var workspaceOrder: [1,2,3,4]
    function refreshOrder(reset) {
        var natural=[];for(var i=1;i<=workspaceCount;i++) natural.push(i);
        var desired=natural;
        if(Core.Tiling.recentWorkspacesFirst) {
            desired=[Core.Compositore.scrivaniaAttiva];
            for(var n of Core.Tiling.recentWorkspaces) if(n<=workspaceCount && desired.indexOf(n)<0) desired.push(n);
            for(var d of natural) if(desired.indexOf(d)<0) desired.push(d);
        }
        if(visible && !reset) {
            var kept=workspaceOrder.filter(function(n){return n<=overview.workspaceCount;});
            for(var missing of desired) if(kept.indexOf(missing)<0) kept.push(missing);
            desired=kept;
        }
        if(JSON.stringify(workspaceOrder)!==JSON.stringify(desired)) workspaceOrder=desired;
    }
    Connections {
        target:Core.Tiling
        function onRecentWorkspacesFirstChanged() {overview.refreshOrder(true);overview.revealSelection();}
        function onRecentWorkspacesChanged() {overview.refreshOrder(false);}
    }
    Item {id:dragLayer;anchors.fill:parent;z:10000}
    readonly property int columns: grid.columns
    function revealSelection() {
        if (!scroll.contentItem) return;
        var top=Math.floor(Math.max(0,workspaceOrder.indexOf(selectedWorkspace))/grid.columns)*(cardHeight+grid.spacing);
        var bottom=top+cardHeight;
        var y=scroll.contentItem.contentY;
        if(top<y) y=top;
        else if(bottom>y+scroll.height) y=bottom-scroll.height;
        scroll.contentItem.contentY=Math.max(0,Math.min(y,Math.max(0,grid.height-scroll.height)));
    }
    function navigate(event) {
        if(event.modifiers & (Qt.ControlModifier|Qt.AltModifier|Qt.ShiftModifier)) return;
        var at=Math.max(0,workspaceOrder.indexOf(selectedWorkspace)),col=at%grid.columns,n=at;
        switch(event.key) {
        case Qt.Key_Left: if(col>0) n--; break;
        case Qt.Key_Right: if(col<grid.columns-1 && n<workspaceOrder.length-1) n++; break;
        case Qt.Key_Up: if(n>=grid.columns) n-=grid.columns; break;
        case Qt.Key_Down: if(n+grid.columns<workspaceOrder.length) n+=grid.columns; break;
        case Qt.Key_Return: case Qt.Key_Enter: chosen(selectedWorkspace); event.accepted=true; return;
        default:
            if(event.key>=Qt.Key_0 && event.key<=Qt.Key_9) {
                chosen(event.key===Qt.Key_0 ? 10:event.key-Qt.Key_0);
                event.accepted=true;
            }
            return;
        }
        selectedWorkspace=workspaceOrder[n];
        if(event.modifiers & Qt.MetaModifier) forceActiveFocus();
        revealSelection();
        event.accepted=true;
    }
    signal chosen(int workspace)
    signal dismissed()
    Keys.onEscapePressed: overview.dismissed()
    Keys.onPressed: function(event) { overview.navigate(event); }
    Shortcut {sequence:"Meta+Left";enabled:overview.visible;onActivated:overview.navigate({key:Qt.Key_Left,modifiers:Qt.MetaModifier,accepted:false})}
    Shortcut {sequence:"Meta+Right";enabled:overview.visible;onActivated:overview.navigate({key:Qt.Key_Right,modifiers:Qt.MetaModifier,accepted:false})}
    Shortcut {sequence:"Meta+Up";enabled:overview.visible;onActivated:overview.navigate({key:Qt.Key_Up,modifiers:Qt.MetaModifier,accepted:false})}
    Shortcut {sequence:"Meta+Down";enabled:overview.visible;onActivated:overview.navigate({key:Qt.Key_Down,modifiers:Qt.MetaModifier,accepted:false})}
    readonly property bool it:Core.Strings.lang==="it"
    readonly property bool photographs:Core.Ipc.get("windows.workspacePhotographs",true)===true
    readonly property color opaqueWindow:Qt.rgba(Theme.Colors.window.r,Theme.Colors.window.g,Theme.Colors.window.b,1)
    readonly property string owner:monitor ? monitor.name:"overview"
    readonly property var windows:visible ? Core.Windows.all.filter(function(w) {
        // Output identity survives scrolling, minimization and hidden workspaces.
        // Unknown applications still own windows and must not disappear.
        return !overview.monitor || (w.output ? w.output===overview.monitor.name:
            (w.x+w.w>overview.monitor.x && w.x<overview.monitor.x+overview.monitor.width && w.y+w.h>overview.monitor.y && w.y<overview.monitor.y+overview.monitor.height));
    }):[]
    readonly property int workspaceCount: {
        var n=Math.max(3,Core.Compositore.scrivaniaAttiva);
        windows.forEach(function(w) {n=Math.max(n,w.workspace);});
        return Math.min(10,n+1);
    }
    readonly property real scrollY:scroll.contentItem ? scroll.contentItem.contentY || 0:0
    readonly property real cardHeight:Math.max(170,Math.min(((grid.width-(grid.columns-1)*grid.spacing)/grid.columns)*0.62+78,(scroll.height-14)/2))
    readonly property string captureSignature:JSON.stringify(windows.filter(function(w) {
        var row=Math.floor(overview.workspaceOrder.indexOf(w.workspace)/grid.columns),top=row*(cardHeight+grid.spacing);
        return top+cardHeight>=scrollY && top<scrollY+scroll.height;
    }).map(function(w){return w.address;}))
    function refresh() {Core.Anteprime.watch(owner,visible && photographs ? JSON.parse(captureSignature):null);}
    onPhotographsChanged:refresh()
    onCaptureSignatureChanged:refresh()
    onVisibleChanged: {
        refresh();
        refreshOrder(true);
        if(visible) {
            selectedWorkspace=Core.Compositore.scrivaniaAttiva;
            forceActiveFocus();
            Qt.callLater(revealSelection);
        }
    }
    onWorkspaceCountChanged: {if(selectedWorkspace>workspaceCount) selectedWorkspace=workspaceCount;refreshOrder(false);}
    onWindowsChanged:refresh()
    Component.onCompleted: {
        refresh();
        refreshOrder(true);
        if(visible) {selectedWorkspace=Core.Compositore.scrivaniaAttiva;forceActiveFocus();Qt.callLater(revealSelection);}
    }
    Component.onDestruction:Core.Anteprime.watch(owner,null)
    function inWorkspace(number) {return windows.filter(function(w){return w.workspace===number;});}
    color:Qt.rgba(Theme.Colors.window.r,Theme.Colors.window.g,Theme.Colors.window.b,1)
    radius:24
    gradient: Gradient {
        GradientStop {position:0;color:Qt.tint(overview.opaqueWindow,Qt.alpha(Theme.Colors.accent,0.07))}
        GradientStop {position:1;color:overview.opaqueWindow}
    }
    border.color:Theme.Colors.edge
    Text {
        id:heading; x:24; y:18
        text:overview.it ? "Le tue Stanze":"Your workspaces"
        color:Theme.Colors.text; font.pixelSize:24
        font.weight:Font.DemiBold
    }
    Rectangle {
        anchors.right:parent.right;anchors.rightMargin:24;y:20
        width:contextLabel.implicitWidth+28;height:30;radius:15
        color:Qt.alpha(Theme.Colors.accent,0.12)
        Text {id:contextLabel;anchors.centerIn:parent;text:(overview.it ? "STANZA ":"WORKSPACE ")+Core.Compositore.scrivaniaAttiva;color:Theme.Colors.accent;font.pixelSize:11;font.weight:Font.DemiBold;font.letterSpacing:1}
    }
    Text {
        x:24; anchors.top:heading.bottom; anchors.topMargin:6
        text:overview.it ? "Frecce: scegli stanza · Invio: entra · Esc: torna · Trascina le finestre tra le stanze":"Arrows: choose workspace · Enter: open · Esc: return · Drag windows between workspaces"
        color:Theme.Colors.textMuted; font.pixelSize:13;width:parent.width-48;elide:Text.ElideRight
    }
    ScrollView {
        id:scroll; x:20;y:82;width:parent.width-40;height:parent.height-108
        clip:true
        contentWidth:availableWidth
        Grid {
            id:grid; width:scroll.availableWidth; columns:overview.workspaceCount>4 && width>=850 ? 3:2; spacing:14
            Repeater {
                model:overview.workspaceOrder
                delegate: Rectangle {
                    id:card; required property int index;required property int modelData
                    objectName:"workspaceCard"+modelData
                    readonly property int number:modelData
                    readonly property bool selected:number===overview.selectedWorkspace
                    readonly property bool current:number===Core.Compositore.scrivaniaAttiva
                    readonly property var entries:overview.inWorkspace(number)
                    readonly property string entrySignature:JSON.stringify(entries.map(function(w){return w.address;}).sort())
                    readonly property var entryIds:JSON.parse(entrySignature)
                    width:(grid.width-(grid.columns-1)*grid.spacing)/grid.columns
                    height:overview.cardHeight
                    radius:16
                    color:selected ? Qt.tint(Theme.Colors.raised,Qt.alpha(Theme.Colors.accent,0.08)):Theme.Colors.raised
                    border.width:selected || drop.containsDrag ? 2:1
                    border.color:selected || drop.containsDrag ? Theme.Colors.accent:Theme.Colors.edge
                    Rectangle {
                        x:12;y:12;width:28;height:28;radius:9
                        color:card.selected ? Theme.Colors.accent:Qt.alpha(Theme.Colors.accent,0.12)
                        Text {anchors.centerIn:parent;text:card.number;color:card.selected ? Theme.Colors.textOnAccent:Theme.Colors.accent;font.pixelSize:14;font.weight:Font.DemiBold}
                    }
                    MouseArea {anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:overview.chosen(card.number)}
                    DropArea {
                        id:drop; anchors.fill:parent; keys:["minerva-window"]
                        onDropped:function(event) {
                            var address=event.source ? event.source.windowAddress:"";
                            if(address) Core.Compositore._nostro("portaascrivania",[Core.Compositore._selettore(address),String(card.number),"si"]);
                            event.acceptProposedAction();
                        }
                    }
                    Text {
                        x:50;y:10;width:parent.width-140;elide:Text.ElideRight
                        textFormat:Text.PlainText
                        text:Core.Tiling.workspaceNames[card.number-1] || ((overview.it ? "Stanza ":"Workspace ")+card.number)
                        color:card.entries.some(function(w){return w.attention;}) ? Theme.Colors.accentWarm:Theme.Colors.text; font.pixelSize:14;font.weight:Font.DemiBold
                    }
                    Text {x:50;y:29;text:card.entries.length ? card.entries.length+(overview.it ? (card.entries.length===1 ? " finestra":" finestre"):(card.entries.length===1 ? " window":" windows")):(overview.it ? "Spazio libero":"Empty workspace");color:Theme.Colors.textMuted;font.pixelSize:11}
                    Text {anchors.right:parent.right;anchors.rightMargin:14;y:19;visible:card.current;text:overview.it ? "IN USO":"CURRENT";color:Theme.Colors.accent;font.pixelSize:10;font.weight:Font.DemiBold;font.letterSpacing:0.6}
                    Row {
                        x:8;anchors.bottom:parent.bottom;anchors.bottomMargin:6;spacing:6
                        Ui.Campo {
                            width:Math.max(90,card.width-174);height:30
                            text:Core.Tiling.workspaceNames[card.number-1] || ""
                            segnaposto:overview.it ? "Nome stanza":"Workspace name"
                            onAccettato:{Core.Tiling.nameWorkspace(card.number,text);overview.forceActiveFocus();}
                            onAttivoChanged:if(attivo) overview.selectedWorkspace=card.number;else Core.Tiling.nameWorkspace(card.number,text)
                        }
                        ComboBox {
                            id:layoutPicker
                            width:152;height:30
                            textRole:"label";valueRole:"value"
                            model:[
                                {value:"eredita",label:overview.it ? "Predefinito":"Default"},
                                {value:"classico",label:overview.it ? "Classico":"Floating"},
                                {value:"uguale",label:overview.it ? "Parti uguali":"Equal split"},
                                {value:"maestro",label:overview.it ? "Maestro + pila":"Master + stack"},
                                {value:"griglia",label:overview.it ? "Griglia":"Grid"},
                                {value:"nuovo",label:overview.it ? "Nuova stanza":"New workspace"}]
                            currentIndex:Math.max(0,model.findIndex(function(v){return v.value===Core.Tiling.workspaceLayouts[card.number-1];}))
                            onActivated:{Core.Tiling.setWorkspace(card.number,currentValue);overview.forceActiveFocus();}
                            background:Rectangle {radius:7;color:Theme.Colors.window;border.color:Theme.Colors.edge}
                            contentItem:Text {leftPadding:8;rightPadding:22;text:layoutPicker.displayText;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight;color:Theme.Colors.text;font.pixelSize:12}
                            indicator:Text {x:layoutPicker.width-20;y:5;text:"⌄";color:Theme.Colors.text}
                            delegate:ItemDelegate {
                                id:layoutOption
                                width:layoutPicker.width;height:32
                                contentItem:Text {text:modelData.label;color:Theme.Colors.text;verticalAlignment:Text.AlignVCenter;font.pixelSize:12}
                                background:Rectangle {color:layoutOption.highlighted ? Theme.Colors.selected:Theme.Colors.window}
                                highlighted:layoutPicker.highlightedIndex===index
                            }
                            popup:Popup {
                                y:layoutPicker.height+3;width:layoutPicker.width;padding:4
                                implicitHeight:contentItem.implicitHeight+8
                                background:Rectangle {radius:7;color:Qt.rgba(Theme.Colors.window.r,Theme.Colors.window.g,Theme.Colors.window.b,1);border.color:Theme.Colors.edge}
                                contentItem:ListView {clip:true;implicitHeight:contentHeight;model:layoutPicker.popup.visible ? layoutPicker.delegateModel:null;currentIndex:layoutPicker.highlightedIndex}
                            }
                        }
                    }
                    Rectangle {
                        id:previewFrame; x:8;y:52;width:parent.width-16;height:parent.height-98
                        radius:9;color:Qt.alpha(Theme.Colors.window,0.65)
                        Item {
                        id:map;anchors.centerIn:parent
                        anchors.margins:6
                        anchors.fill:parent
                        readonly property int cols:card.entryIds.length<=1 ? 1:card.entryIds.length<=4 ? 2:Math.ceil(Math.sqrt(card.entryIds.length*width/Math.max(1,height)))
                        readonly property int rows:Math.max(1,Math.ceil(card.entryIds.length/cols))
                        readonly property real cellW:(width-(cols-1)*6)/cols
                        readonly property real cellH:(height-(rows-1)*6)/rows
                        Column {
                            anchors.centerIn:parent;spacing:8;visible:card.entryIds.length===0
                            Ui.Icon {anchors.horizontalCenter:parent.horizontalCenter;width:26;height:26;name:"plus";color:Theme.Colors.textFaint}
                            Text {text:overview.it ? "Il tuo prossimo spazio":"Your next workspace";color:Theme.Colors.textMuted;font.pixelSize:12}
                        }
                        Repeater {
                            model:card.entryIds
                            delegate:Rectangle {
                                id:tile;required property string modelData;required property int index
                                objectName:"windowThumbnail"+modelData
                                readonly property var windowData:overview.windows.find(function(w){return w.address===tile.modelData;}) || ({x:0,y:0,w:1,h:1,stack:9999,title:"",appClass:""})
                                readonly property string windowAddress:modelData
                                readonly property real px:(index%map.cols)*(map.cellW+6)
                                readonly property real py:Math.floor(index/map.cols)*(map.cellH+6)
                                x:px;y:py;width:Math.max(1,map.cellW);height:Math.max(1,map.cellH)
                                clip:true
                                z:1
                                readonly property var app:Core.Apps.forWindow(windowData)
                                readonly property string iconPath:app && app.icon ? app.icon:""
                                color:Theme.Colors.window;radius:6;border.color:mouse.containsMouse ? Theme.Colors.accent:Theme.Colors.edge
                                opacity:windowData.minimized ? 0.45:1
                                Ui.WindowPreview {
                                    anchors.fill:parent;anchors.margins:1
                                    path:overview.photographs ? Core.Anteprime.images[tile.windowAddress] || "":""
                                }
                                Column {
                                    anchors.centerIn:parent;spacing:4
                                    visible:!overview.photographs || !Core.Anteprime.images[tile.windowAddress]
                                    Ui.Icon {anchors.horizontalCenter:parent.horizontalCenter;width:20;height:20;name:"window";color:Theme.Colors.accent;visible:tile.iconPath===""}
                                    Image {anchors.horizontalCenter:parent.horizontalCenter;width:24;height:24;source:tile.iconPath ? "file://"+tile.iconPath:"";sourceSize.width:32;sourceSize.height:32;visible:tile.iconPath!=="";asynchronous:true}
                                    Text {width:Math.max(1,tile.width-8);horizontalAlignment:Text.AlignHCenter;text:tile.app ? tile.app.name:tile.windowData.appClass;textFormat:Text.PlainText;elide:Text.ElideRight;color:Theme.Colors.text;font.pixelSize:10}
                                }
                                Rectangle {
                                    anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:20
                                    color:Qt.alpha(Theme.Colors.window,0.9)
                                    Image {x:4;y:3;width:14;height:14;source:tile.iconPath ? "file://"+tile.iconPath:"";sourceSize.width:28;sourceSize.height:28;asynchronous:true;visible:tile.iconPath!==""}
                                    Text {anchors.fill:parent;anchors.leftMargin:tile.iconPath ? 22:4;anchors.rightMargin:4;verticalAlignment:Text.AlignVCenter;text:tile.windowData.title || tile.windowData.appClass;textFormat:Text.PlainText;elide:Text.ElideRight;color:Theme.Colors.text;font.pixelSize:10}
                                }
                                Rectangle {
                                    id:ghost;parent:dragLayer
                                    property bool dragging:false
                                    readonly property string windowAddress:tile.windowAddress
                                    visible:dragging;width:tile.width;height:tile.height;z:100
                                    color:overview.opaqueWindow;radius:8;border.color:Theme.Colors.accent;border.width:2
                                    Drag.active:dragging;Drag.keys:["minerva-window"];Drag.source:ghost
                                    Drag.hotSpot.x:mouse.pressX;Drag.hotSpot.y:mouse.pressY
                                    Ui.WindowPreview {anchors.fill:parent;anchors.margins:3;path:overview.photographs ? Core.Anteprime.images[tile.windowAddress] || "":""}
                                    Text {anchors.bottom:parent.bottom;anchors.horizontalCenter:parent.horizontalCenter;width:parent.width-8;elide:Text.ElideRight;text:tile.windowData.title;color:Theme.Colors.text;textFormat:Text.PlainText}
                                }
                                MouseArea {
                                    id:mouse;anchors.fill:parent;drag.target:ghost;drag.threshold:8;hoverEnabled:true;cursorShape:pressed ? Qt.ClosedHandCursor:Qt.OpenHandCursor
                                    property bool moved:false
                                    property real pressX:0;property real pressY:0
                                    onPressed:function(event) {
                                        moved=false;pressX=event.x;pressY=event.y;
                                        var p=tile.mapToItem(dragLayer,0,0);ghost.x=p.x;ghost.y=p.y;
                                    }
                                    onPositionChanged:if(drag.active) {moved=true;ghost.dragging=true;}
                                    onReleased: {if(moved) ghost.Drag.drop();ghost.dragging=false;}
                                    onCanceled:ghost.dragging=false
                                    onClicked:if(!moved) {overview.chosen(card.number);if(tile.windowData.minimized) Core.Windows.restore(tile.windowAddress);else Core.Tiling.recall(tile.windowAddress);}
                                }
                            }
                        }
                        }
                    }
                }
            }
        }
    }
    Text {x:24;anchors.bottom:parent.bottom;anchors.bottomMargin:9;text:overview.it ? "Schema delle finestre · Frecce ed Invio per scegliere · Trascina una finestra per cambiarle stanza":"Window map · Arrows and Enter to choose · Drag a window to another workspace";color:Theme.Colors.textMuted;font.pixelSize:11;width:parent.width-48;elide:Text.ElideRight}
}
