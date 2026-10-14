pragma Singleton
import QtQuick

QtObject {
    id: cache
    property var images: ({})
    property var imageBirths: ({})
    readonly property bool enabled:Ipc.get("windows.workspacePhotographs",true)===true
    onEnabledChanged:configure()
    function clear() {images={};imageBirths={};}
    function configure() {if(Compositore.canaleAperto && Compositore.scrivania) Compositore._nostro("anteprime",[enabled ? "si":"no"]);if(!enabled) {clear();pending=[];}else if(active) refill();}
    Component.onCompleted:configure()
    function accept(entry) {
        if(!enabled || !entry || !entry.id || !entry.path) return;
        var window=Windows.all.find(function(w){return w.address===entry.id;});
        if(window && entry.birth && window.birth!==entry.birth) return;
        var next=Object.assign({},images);
        var births=Object.assign({},imageBirths);
        if(next[entry.id]!==entry.path) {
            delete next[entry.id];
            next[entry.id]=entry.path;
            births[entry.id]=entry.birth || 0;
            var ids=Object.keys(next);
            while(ids.length>64) {var oldest=ids.shift();delete next[oldest];delete births[oldest];}
            imageBirths=births;
            images=next;
        }
    }
    property var viewers: ({})
    property var pending: []
    readonly property bool active: enabled && Object.keys(viewers).some(function(key){return viewers[key].length>0;})
    function watch(owner, addresses) {
        if(addresses!==null && JSON.stringify(viewers[owner])===JSON.stringify(addresses)) return;
        var next=Object.assign({},viewers);
        if(addresses===null) delete next[owner]; else next[owner]=addresses;
        viewers=next;
        if(active) refill(); else pending=[];
    }
    function refill() {
        if(!enabled) {pending=[];return;}
        var ids=[];
        Object.keys(viewers).forEach(function(k) {
            viewers[k].forEach(function(id) {if(ids.indexOf(id)<0 && ids.length<64) ids.push(id);});
        });
        pending=ids;

    }
    property Connections model:Connections {target:Windows;function onAllChanged() {var keep={},births={};for(var w of Windows.all) if(cache.images[w.address] && cache.imageBirths[w.address]===(w.birth || 0)) {keep[w.address]=cache.images[w.address];births[w.address]=cache.imageBirths[w.address];}if(JSON.stringify(keep)!==JSON.stringify(cache.images)) {cache.imageBirths=births;cache.images=keep;}}}
    property Timer period: Timer {interval:2000; repeat:true; running:cache.active; onTriggered:if(!cache.pending.length) cache.refill()}
    property Timer pump: Timer {
        interval:120; repeat:true; running:cache.active && cache.pending.length>0
        onTriggered: {
            var ids=cache.pending.slice(),id=ids.shift(); cache.pending=ids;
            Compositore._nostro("anteprima",[Compositore._selettore(id)]);
        }
    }
    property Connections replies: Connections {
        target:Compositore
        function onRisposta(what,text) {
            if(what!=="anteprima" || !cache.enabled) return;
            if(text.indexOf("ok ")!==0) {
                if(text.indexOf("bloccato")>=0) {cache.clear();cache.viewers={};cache.pending=[];}
                return;
            }
            try {
                var entry=JSON.parse(text.substring(3));
                cache.accept(entry);
            } catch(e) { console.warn("Anteprima:",e); }
        }
        function onScrivaniaChanged() {cache.configure();}
        function onPreviewReady(entry) {cache.accept(entry);}
        function onBloccoCambiato(locked) {if(locked) {cache.clear();cache.viewers={};cache.pending=[];}else cache.configure();}
        function onCanaleApertoChanged() {if(!Compositore.canaleAperto) cache.clear();else cache.configure();}
    }
}
