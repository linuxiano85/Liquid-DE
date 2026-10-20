import QtQuick
import "../../core" as Core
import "../../windows11" as W
import "../../windows11/Gettoni.js" as Gettoni
import "Dati.js" as Dati

// CatalogoTemi — I temi di Personalizzazione › Temi e della pagina
// Personalizzazione: quelli di serie e quelli salvati, quale è in uso, come
// applicarne uno e come salvare quello attuale (`windows11.temi`).
QtObject {
    id: pagina

    readonly property string lingua: Core.Strings.lang
    function tt(k) { return Dati.t(pagina.lingua, k); }
    readonly property bool it: pagina.lingua === "it"

    readonly property string cartellaBloom: decodeURIComponent(Qt.resolvedUrl("../../windows11/wallpapers/").toString().replace(/^file:\/\//, ""))

    // Solo queste preferenze fanno parte del tema: nessuna impostazione
    // arbitraria viene eseguita importando o riapplicando un tema.
    readonly property var preferenzeTema: [
        "desktop.wallpaperMode", "desktop.wallpaper", "desktop.wallpaperFolder",
        "desktop.wallpaperColor", "desktop.wallpaperFit", "desktop.rotateMinutes",
        "desktop.rotateRandom", "windows11.wallpaper", "windows11.themeApp"
    ]
    function fotografaPreferenze() {
        var result = {};
        for (var key of preferenzeTema) result[key] = Core.Ipc.get(key);
        return result;
    }

    /// I temi di serie e quelli salvati.
    readonly property var temi: {
        var l = [];
        var bl = Core.Wallpaper.bloomPresente;
        l.push({ "id": "windows-chiaro", "nome": pagina.it ? "Liquid (chiaro)" : "Liquid (light)", "tema": "light", "accento": Gettoni.azzurroDiSerie.accento,
                 "sfondo": bl ? pagina.cartellaBloom + "bloom-light.jpg" : Core.Wallpaper.ownPath("quiete.png"), "auto": true });
        l.push({ "id": "windows-scuro", "nome": pagina.it ? "Liquid (scuro)" : "Liquid (dark)", "tema": "dark", "accento": Gettoni.azzurroDiSerie.accento,
                 "sfondo": bl ? pagina.cartellaBloom + "bloom-dark.jpg" : Core.Wallpaper.ownPath("orbite.png"), "auto": true });
        l.push({ "id": "evidenza", "nome": pagina.tt("inEvidenza"), "disponibile": false, "tema": "light", "accento": "#0078D4", "sfondo": "" });
        var propri = [["aurora", "Aurora", "dark", "#8764B8"], ["continuum", "Continuum", "dark", "#0099BC"],
                      ["onda", "Onda", "light", "#0063B1"], ["reticolo", "Reticolo", "dark", "#00B294"]];
        for (var i = 0; i < propri.length; i++)
            l.push({ "id": "liquid-" + propri[i][0], "nome": propri[i][1], "tema": propri[i][2], "accento": propri[i][3],
                     "sfondo": Core.Wallpaper.ownPath(propri[i][0] + ".png") });
        var salvati = Core.Ipc.get("windows11.temi", []) || [];
        for (var j = 0; j < salvati.length; j++)
            l.push({ "id": "utente-" + j, "nome": salvati[j].nome, "tema": salvati[j].tema, "accento": salvati[j].accento, "sfondo": salvati[j].sfondo,
                     "preferenze": salvati[j].preferenze || null,
                     "base": salvati[j].preferenze && salvati[j].preferenze["desktop.wallpaperMode"] === "color"
                         ? salvati[j].preferenze["desktop.wallpaperColor"] : undefined });
        return l;
    }
    readonly property string corrente: Core.Ipc.get("windows11.temaCorrente", "windows-chiaro")
    readonly property string nomeCorrente: {
        for (var i = 0; i < pagina.temi.length; i++)
            if (pagina.temi[i].id === pagina.corrente)
                return pagina.temi[i].nome;
        return pagina.tt("personalizzato");
    }
    readonly property string accento: {
        var a = String(Core.Ipc.get("windows11.accent", "auto"));
        return a === "auto" ? W.Style.accentBase.toUpperCase() : a.toUpperCase();
    }

    function applica(t) {
        if (t.disponibile === false)
            return;
        var v = { "windows11.theme": t.tema, "windows11.themeApp": "", "windows11.accent": t.accento,
                  "windows11.temaCorrente": t.id, "desktop.wallpaperMode": "image" };
        if (t.preferenze) {
            for (var key of preferenzeTema)
                if (t.preferenze[key] !== undefined) v[key] = t.preferenze[key];
        } else if (t.auto) {
            v["windows11.wallpaper"] = "auto";
        } else {
            v["windows11.wallpaper"] = "current";
            v["desktop.wallpaper"] = t.sfondo;
        }
        Core.Ipc.setSettings(v);
        Core.Wallpaper.ricorda(t.sfondo);
    }
    function salva() {
        var salvati = (Core.Ipc.get("windows11.temi", []) || []).slice();
        if (salvati.length >= 20)
            return;
        var n = salvati.length + 1;
        salvati.push({ "nome": (pagina.it ? "Tema personalizzato " : "Custom theme ") + n,
                       "sfondo": Core.Wallpaper.current, "tema": Core.Ipc.get("windows11.theme", "light"),
                       "accento": pagina.accento, "preferenze": pagina.fotografaPreferenze() });
        Core.Ipc.setSettings({ "windows11.temi": salvati, "windows11.temaCorrente": "utente-" + (n - 1) });
    }

}
