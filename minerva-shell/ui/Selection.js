.pragma library
function rectangle(a,b) { return {x:Math.min(a.x,b.x),y:Math.min(a.y,b.y),width:Math.abs(a.x-b.x),height:Math.abs(a.y-b.y)}; }
function intersects(a,b) { return a.x<b.x+b.width && b.x<a.x+a.width && a.y<b.y+b.height && b.y<a.y+a.height; }
function merge(original,hits,mode) {
    if(mode==='replace') return hits.slice();
    var seen=Object.create(null),result=[];
    for(var i=0;i<original.length;i++) seen[original[i]]=true;
    for(i=0;i<hits.length;i++) {
        if(mode==='toggle' && seen[hits[i]]) delete seen[hits[i]];
        else seen[hits[i]]=true;
    }
    // Preserve selection order and use a null prototype in callers' key maps.
    var candidates=original.concat(hits),used=Object.create(null);
    for(i=0;i<candidates.length;i++) if(seen[candidates[i]] && !used[candidates[i]]) {
        used[candidates[i]]=true; result.push(candidates[i]);
    }
    return result;
}
