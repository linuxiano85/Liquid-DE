import QtQuick

// A pending/error image never replaces ready pixels.
Item {
    id:root
    property string path:""
    property int front:0
    readonly property bool ready:(front===0 ? first:second).status===Image.Ready
    onPathChanged: {
        if(path==="") {first.source="";second.source="";return;}
        var url="file://"+path;
        if((front===0 ? first:second).source.toString()===url) return;
        (front===0 ? second:first).source=url;
    }
    Image {
        id:first;anchors.fill:parent;visible:root.front===0
        asynchronous:true;cache:true;fillMode:Image.PreserveAspectFit
        onStatusChanged:if(status===Image.Ready) root.front=0
    }
    Image {
        id:second;anchors.fill:parent;visible:root.front===1
        asynchronous:true;cache:true;fillMode:Image.PreserveAspectFit
        onStatusChanged:if(status===Image.Ready) root.front=1
    }
}
