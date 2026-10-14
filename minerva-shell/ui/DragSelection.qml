import QtQuick
import "../theme" as Theme
import "Selection.js" as Selection

Item {
    id: band
    property var selection: []
    property var hitTest: function(rect) { return []; }
    property var scrollView: null
    property var acceptsPoint: function(point) { return true; }
    property bool overlay: false
    // Il gestore file Windows usa un accento locale; le altre superfici
    // mantengono il colore predefinito senza dipendere dal preset dei File.
    property color accent: Theme.Colors.accent
    clip: overlay
    property bool pending: false
    property bool dragging: false
    property point origin: Qt.point(0,0)
    property point pointer: Qt.point(0,0)
    property point pressedAt: Qt.point(0,0)
    property var original: []
    property string operation: "replace"
    signal selectionRequested(var keys)
    signal started()
    signal finished()
    readonly property real scrollX: scrollView ? scrollView.contentX:0
    readonly property real scrollY: scrollView ? scrollView.contentY:0
    readonly property var rectangle: Selection.rectangle(origin,Qt.point(pointer.x+scrollX,pointer.y+scrollY))
    // A disabled handler exposes the platform's drag threshold.
    DragHandler { id: platformDrag; target:null; enabled:false }
    function begin(point,modifiers) {
        if(pending) cancel();
        original=selection.slice(); pressedAt=point; pointer=point;
        origin=Qt.point(point.x+scrollX,point.y+scrollY);
        operation=(modifiers & Qt.ControlModifier) ? "toggle":(modifiers & Qt.ShiftModifier) ? "add":"replace";
        dragging=false; pending=true; forceActiveFocus(); started();
    }
    function move(point) {
        if(!pending) return;
        pointer=point;
        if(!dragging && Math.hypot(point.x-pressedAt.x,point.y-pressedAt.y)<platformDrag.dragThreshold) return;
        dragging=true;
        var result=Selection.merge(original,hitTest(rectangle),operation);
        if(JSON.stringify(result)!==JSON.stringify(selection)) selectionRequested(result);
    }
    function finish() {
        if(!pending) return;
        if(!dragging && operation==='replace') selectionRequested([]);
        pending=false; dragging=false; finished();
    }
    function cancel() {
        if(!pending) return;
        selectionRequested(original.slice());pending=false;dragging=false;finished();
    }
    onVisibleChanged: if(!visible) cancel()
    onEnabledChanged: if(!enabled) cancel()
    onWidthChanged: cancel()
    onHeightChanged: cancel()
    Keys.onEscapePressed: function(event) { if(pending) {cancel();event.accepted=true;} }
    MouseArea {
        anchors.fill:parent; acceptedButtons:Qt.LeftButton; preventStealing:true
        onPressed:function(m) {
            var point=Qt.point(m.x,m.y);
            if(!band.acceptsPoint(point)) {m.accepted=false;return;}
            band.begin(point,m.modifiers);
        }
        onPositionChanged:function(m) {if(pressed) band.move(Qt.point(m.x,m.y));}
        onReleased:band.finish()
        onCanceled:band.cancel()
    }
    // The component sits below delegates; its rectangle is reparented above them.
    Rectangle {
        parent:band.overlay ? band:band.parent
        z:100
        visible:band.dragging
        x:(band.overlay ? 0:band.x)+band.rectangle.x-band.scrollX
        y:(band.overlay ? 0:band.y)+band.rectangle.y-band.scrollY
        width:band.rectangle.width; height:band.rectangle.height
        color: Qt.alpha(band.accent, .16)
        border.color: band.accent
        border.width: 1
    }
    Timer {
        interval:16; repeat:true
        running:band.dragging && band.scrollView && (band.pointer.y<28 || band.pointer.y>band.height-28)
        onTriggered: {
            var view=band.scrollView;
            var dy=band.pointer.y<28 ? -12:12;
            var min=view.originY || 0,max=Math.max(min,min+view.contentHeight-view.height);
            var next=Math.max(min,Math.min(max,view.contentY+dy));
            if(next!==view.contentY) {view.contentY=next;band.move(band.pointer);}
        }
    }
}
