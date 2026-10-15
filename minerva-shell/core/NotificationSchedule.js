// Gli intervalli notturni appartengono al giorno in cui iniziano: venerdì
// 22:00–07:00 deve restare attivo anche sabato prima delle 07:00.
function minuteOfDay(value) {
    if (typeof value !== "string" || !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value))
        return -1;
    return Number(value.slice(0, 2)) * 60 + Number(value.slice(3));
}

function matchesDay(group, day) {
    if (group === "daily")
        return true;
    if (group === "weekdays")
        return day >= 1 && day <= 5;
    if (group === "weekends")
        return day === 0 || day === 6;
    return false;
}

function isActive(now, from, to, days) {
    var start = minuteOfDay(from);
    var end = minuteOfDay(to);
    if (start < 0 || end < 0 || !now || !isFinite(now.getTime()))
        return false;
    var minute = now.getHours() * 60 + now.getMinutes();
    var day = now.getDay();
    if (start === end)
        return matchesDay(days, day);
    if (start < end)
        return matchesDay(days, day) && minute >= start && minute < end;
    if (minute >= start)
        return matchesDay(days, day);
    return minute < end && matchesDay(days, (day + 6) % 7);
}

function intervalEnd(now, from, to, days) {
    if (!isActive(now, from, to, days))
        return 0;
    var start = minuteOfDay(from);
    var end = minuteOfDay(to);
    var minute = now.getHours() * 60 + now.getMinutes();
    var result = new Date(now.getTime());
    if (start === end) {
        result.setDate(result.getDate() + 1);
        result.setHours(0, 0, 0, 0);
    } else {
        if (start > end && minute >= start)
            result.setDate(result.getDate() + 1);
        result.setHours(Math.floor(end / 60), end % 60, 0, 0);
    }
    return result.getTime();
}

// La sospensione identifica una sola occorrenza, non una preferenza eterna.
// Include orari/giorni: modificare la regola non eredita un vecchio silenzio.
function intervalToken(now, get) {
    if (!get("notifications.scheduleEnabled", false))
        return "";
    var from = get("notifications.scheduleFrom", "22:00");
    var to = get("notifications.scheduleTo", "07:00");
    var days = get("notifications.scheduleDays", "daily");
    var end = intervalEnd(now, from, to, days);
    return end ? [from, to, days, end].join("|") : "";
}

function isPaused(now, get) {
    var token = intervalToken(now, get);
    return token !== "" && token === get("notifications.scheduleDismissed", "");
}

function scheduledQuiet(now, get) {
    var token = intervalToken(now, get);
    return token !== "" && token !== get("notifications.scheduleDismissed", "");
}

function isQuiet(now, get) {
    return get("notifications.doNotDisturb", false) || scheduledQuiet(now, get);
}

function setQuiet(now, get, set, enabled) {
    set("notifications.doNotDisturb", enabled);
    if (get("notifications.scheduleDismissed", undefined) !== undefined)
        set("notifications.scheduleDismissed", enabled ? "" : intervalToken(now, get));
}

function setSchedule(get, set, path, value) {
    set(path, value);
    if (get("notifications.scheduleDismissed", undefined) !== undefined)
        set("notifications.scheduleDismissed", "");
}
