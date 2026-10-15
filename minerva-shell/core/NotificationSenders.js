// Una chiave esadecimale evita che punti, slash e nomi Unicode diventino
// percorsi nelle impostazioni. L'UTF-8 conserva identità diverse senza hash.
function hex(text) {
    var encoded = encodeURIComponent(text);
    var result = "";
    for (var i = 0; i < encoded.length; i++) {
        if (encoded[i] === "%") {
            result += encoded.slice(i+1, i+3).toLowerCase();
            i += 2;
        } else {
            result += encoded.charCodeAt(i).toString(16).padStart(2, "0");
        }
    }
    return result;
}

function identity(name, desktop) {
    var label = String(name || "Sistema").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 128);
    label = label.replace(/[\ud800-\udbff]$/, "") || "Sistema";
    var entry = String(desktop || "").trim().replace(/\.desktop$/, "");
    if (entry.length > 128 || /[\/\\\u0000-\u0020\u007f]/.test(entry))
        entry = "";
    return {key:(entry ? "d" : "n") + hex(entry || label), name:label, desktop:entry};
}

function keys(records) {
    return Object.keys(records || {}).sort(function(a,b) {
        return String(records[a].name).localeCompare(String(records[b].name)) || a.localeCompare(b);
    });
}

function enabled(get, key) {
    return get("notifications.enabled", true) && get("notifications.apps." + key + ".enabled", true);
}

function banner(get, key, quiet) {
    if (!enabled(get, key) || !get("notifications.banners", true)
            || !get("notifications.apps." + key + ".banners", true))
        return false;
    return !quiet || get("notifications.apps." + key + ".priority", false);
}

// Il suono resta indipendente dal banner: chi nasconde il popup può ancora
// volere un avviso acustico. Non disturbare e la richiesta dell'app prevalgono.
function sound(get, key, quiet, suppressed) {
    return enabled(get, key) && get("notifications.sounds", true)
        && !suppressed && (!quiet || get("notifications.apps." + key + ".priority", false));
}
