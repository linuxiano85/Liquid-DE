// -1 eredita la soglia precedente: installare l'aggiornamento non cambia
// improvvisamente quando il computer si spegne o va in sospensione.
function supportsSources(get) {
    return get("power.ac.screenOffAfter", undefined) !== undefined
        && get("power.ac.suspendAfter", undefined) !== undefined
        && get("power.battery.screenOffAfter", undefined) !== undefined
        && get("power.battery.suspendAfter", undefined) !== undefined;
}

function sourcePath(key, onBattery) {
    return "power." + (onBattery ? "battery" : "ac") + "." + key;
}

function minutes(get, key, onBattery) {
    var defaults = {dimAfter:5, lockAfter:10, screenOffAfter:15, suspendAfter:30};
    var common = Number(get("power." + key, defaults[key]));
    if (!isFinite(common) || common < 0)
        common = defaults[key];
    if (key !== "screenOffAfter" && key !== "suspendAfter")
        return common;
    var specific = Number(get(sourcePath(key, onBattery), -1));
    return isFinite(specific) && specific >= 0 ? specific : common;
}

function editPath(get, key, onBattery) {
    if (supportsSources(get) && (key === "screenOffAfter" || key === "suspendAfter"))
        return sourcePath(key, onBattery);
    return "power." + key;
}
