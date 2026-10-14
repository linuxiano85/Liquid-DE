import QtQuick
import "../core" as Core
import "Groups.js" as Groups
Item {
    id: root
    visible: false
    property string output: ""
    property var order: []
    property ListModel model: ListModel {}
    readonly property var entries: Groups.group(Core.Apps.all, Core.Windows.all.map(function(w){var a=Core.Apps.forWindow(w);return Object.assign({},w,{resolvedAppId:a ? a.appId:""});}),
        Core.Ipc.get("dock.pinned", []), Core.Compositore.scrivaniaAttiva,
        Core.Ipc.get("windows.dockLocalWindows", true), output, order)
    onEntriesChanged: Qt.callLater(rebuild)
    Component.onCompleted: rebuild()
    function rebuild() {
        var ids=entries.map(function(g) {return g.id;});
        if (JSON.stringify(order)!==JSON.stringify(ids)) order=ids;
        for (var i=model.count-1;i>=0;--i) if(ids.indexOf(model.get(i).key)<0) model.remove(i);
        entries.forEach(function(g,index) {
            var at=-1;
            for(var j=0;j<model.count;j++) if(model.get(j).key===g.id) {at=j;break;}
            if(at<0) model.insert(index,{key:g.id,rowJson:JSON.stringify(g)});
            else {if(at!==index) model.move(at,index,1);var data=JSON.stringify(g);if(model.get(index).rowJson!==data) model.setProperty(index,"rowJson",data);}
        });
    }
    function launch(g, fresh) {
        if(g.app) Core.Ipc.launchApp(fresh ? (g.app.nuovaFinestra || g.app.exec) : g.app.exec,g.app.appId,fresh ? "new-window" : "activate-or-launch");
    }
    function pin(g) {
        if(!g.app) return;
        var list=Core.Ipc.get("dock.pinned",[]).slice(),index=list.indexOf(g.app.appId);
        if(index<0) list.push(g.app.appId);else list.splice(index,1);
        Core.Ipc.setSetting("dock.pinned",list);
    }
}
