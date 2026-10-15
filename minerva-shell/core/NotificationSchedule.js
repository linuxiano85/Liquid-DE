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
