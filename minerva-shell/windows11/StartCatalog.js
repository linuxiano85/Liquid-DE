.pragma library

// Ogni desktop file appartiene a un solo gruppo: categorie freedesktop
// multiple non devono duplicare un'app nella vista a categorie.
var groups = [
    {id: "office", it: "Produttività", en: "Productivity", keys: ["Office", "Development", "Education", "Science"]},
    {id: "tools", it: "Strumenti", en: "Utilities & tools", keys: ["Utility", "System", "Settings"]},
    {id: "creative", it: "Creatività", en: "Creativity", keys: ["Graphics"]},
    {id: "media", it: "Intrattenimento", en: "Entertainment", keys: ["Game", "AudioVideo", "Audio", "Video"]},
    {id: "internet", it: "Comunicazione", en: "Communication", keys: ["Network"]},
    {id: "other", it: "Altre app", en: "Other apps", keys: []}
];

function grouped(apps) {
    var result = groups.map(function(group) {
        return {id: group.id, it: group.it, en: group.en, apps: []};
    });
    var seen = Object.create(null);
    for (var i = 0; i < apps.length; i++) {
        var app = apps[i];
        if (!app || !app.appId || seen[app.appId])
            continue;
        seen[app.appId] = true;
        var keys = app.categories || [];
        if (typeof keys === "string")
            keys = keys.split(";");
        var destination = groups.length - 1;
        for (var g = 0; g < groups.length - 1; g++) {
            if (groups[g].keys.some(function(key) { return keys.indexOf(key) >= 0; })) {
                destination = g;
                break;
            }
        }
        result[destination].apps.push(app);
    }
    return result.filter(function(group) { return group.apps.length > 0; });
}

function rows(items, columns, kind) {
    var result = [];
    for (var i = 0; i < items.length; i += columns)
        result.push({kind: kind, cells: items.slice(i, i + columns)});
    return result;
}
