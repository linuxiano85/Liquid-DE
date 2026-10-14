.pragma library
// Keep app order stable on focus changes; keep every individual surface.
function group(apps, windows, pinned, workspace, local, output, order) {
    function appFor(w) {
        var cls = String(w.appClass || "").toLowerCase();
        return apps.find(function(a) {return a.appId===w.resolvedAppId;}) || apps.find(function(a) { return String(a.wmClass || "").toLowerCase() === cls && cls !== ""; })
            || apps.find(function(a) { return String(a.appId).replace(/\.desktop$/, "").toLowerCase() === cls; });
    }
    var byId = Object.create(null), ids = [];
    function add(id, app, w) {
        if (!byId[id]) { byId[id] = {id:id, name:app ? app.name : (w.title || w.appClass || "Application"), icon:app ? app.icon || "" : "", app:app || null, pinned:pinned.indexOf(id)>=0, windows:[]}; ids.push(id); }
        if (w) byId[id].windows.push(w);
    }
    pinned.forEach(function(id) { var a=apps.find(function(a) {return a.appId===id;}); if (a) add(id,a,null); });
    windows.forEach(function(w) {
        if (!w.address || (local && w.workspace!==workspace) || (output && w.output && w.output!==output)) return;
        var a=appFor(w), id=a ? a.appId : (w.appClass || "surface:"+w.address+":"+w.birth);
        add(id,a,w);
    });
    var sorted=pinned.filter(function(id) {return !!byId[id];});
    order.concat(ids).forEach(function(id) {if(byId[id] && sorted.indexOf(id)<0) sorted.push(id);});
    return sorted.map(function(id) {return byId[id];});
}
