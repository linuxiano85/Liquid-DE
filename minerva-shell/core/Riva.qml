pragma Singleton
import QtQuick
import "." as Core

// Riva — che cosa fa ogni angolo e ogni bordo, e com'è la molla.
//
// Giacomo, 25 settembre 2026: «massima flessibilità: tutto deve essere
// facilmente personalizzabile». La Riva (angoli, bordi, Isola) nasce con
// le scelte della simulazione, ma ogni scelta è un'impostazione: qui ci
// sono il catalogo delle azioni e le scelte correnti, lette in un posto
// solo. Le usano la shell (che fa le cose), i tasti sulla scrivania (che le
// disegnano al loro posto) e la pagina «La Riva» delle Impostazioni (che le
// fa scegliere).
QtObject {
    id: riva

    /// Le azioni che un angolo può avere.
    readonly property var azioni: [
        { "id": "menu",      "it": "Menù",              "en": "Menu",             "icona": "apps",      "tasto": "Super" },
        { "id": "centro",    "it": "Centro di controllo", "en": "Control centre", "icona": "sliders",   "tasto": "Super A" },
        { "id": "scrivania", "it": "Scrivania libera",  "en": "Show desktop",     "icona": "window",    "tasto": "Super D" },
        { "id": "stanze",    "it": "Le stanze",         "en": "Rooms",            "icona": "screen",    "tasto": "Super Tab" },
        { "id": "isola",     "it": "Oggi",              "en": "Today",            "icona": "clock",     "tasto": "Super O" },
        { "id": "appunti",   "it": "Appunti",           "en": "Clipboard",        "icona": "clipboard", "tasto": "Super V" },
        { "id": "niente",    "it": "Niente",            "en": "Nothing",          "icona": "close",     "tasto": "" }
    ]

    /// Di serie, come nella Riva studiata.
    readonly property var _diSerie: ({
        "altoSx": "niente", "altoDx": "centro", "bassoSx": "menu", "bassoDx": "scrivania"
    })

    function _valida(v, chiave) {
        for (var i = 0; i < riva.azioni.length; i++)
            if (riva.azioni[i].id === v)
                return v;
        return riva._diSerie[chiave] || "niente";
    }
    function angolo(chiave) {
        switch (chiave) {
        case "altoSx":  return riva.altoSx;
        case "altoDx":  return riva.altoDx;
        case "bassoSx": return riva.bassoSx;
        case "bassoDx": return riva.bassoDx;
        }
        return "niente";
    }
    /// Gli angoli come di serie, in un colpo.
    function angoliDiSerie() {
        Core.Ipc.setSetting("riva.angoli", JSON.parse(JSON.stringify(riva._diSerie)));
    }
    /// L'Isola che mostra tutto, come di serie.
    function isolaDiSerie() {
        Core.Ipc.setSetting("isola.mostra", { "data": true, "meteo": true, "musica": true,
                                              "vassoio": true, "stato": true });
    }
    function azione(id) {
        for (var i = 0; i < riva.azioni.length; i++)
            if (riva.azioni[i].id === id)
                return riva.azioni[i];
        return riva.azioni[riva.azioni.length - 1];
    }
    /// «alto-sx» (l'evento del compositore) → «altoSx» (l'impostazione).
    function chiaveDi(quale) {
        switch (quale) {
        case "alto-sx": return "altoSx";
        case "alto-dx": return "altoDx";
        case "basso-sx": return "bassoSx";
        case "basso-dx": return "bassoDx";
        }
        return "";
    }

    // Col nome intero, perché chi cerca l'impostazione la trovi.
    readonly property string altoSx: riva._valida(Core.Ipc.get("riva.angoli.altoSx", "niente"), "altoSx")
    readonly property string altoDx: riva._valida(Core.Ipc.get("riva.angoli.altoDx", "centro"), "altoDx")
    readonly property string bassoSx: riva._valida(Core.Ipc.get("riva.angoli.bassoSx", "menu"), "bassoSx")
    readonly property string bassoDx: riva._valida(Core.Ipc.get("riva.angoli.bassoDx", "scrivania"), "bassoDx")

    /// Il Cassetto a sinistra (e le Stanze a destra).
    readonly property bool cassettoASinistra: Core.Ipc.get("riva.cassetto", "destra") === "sinistra"
    /// Con una finestra che riempie lo schermo, la riva chiede Super.
    readonly property bool conConsenso: Core.Ipc.get("riva.consenso", true) !== false
    /// Il carattere della molla: «calma», «liquida», «viva».
    readonly property string molla: Core.Ipc.get("riva.molla", "liquida")

    /// Che cosa mostra l'Isola.
    readonly property bool isolaMeteo: Core.Ipc.get("isola.mostra.meteo", true) !== false
    readonly property bool isolaMusica: Core.Ipc.get("isola.mostra.musica", true) !== false
    readonly property bool isolaVassoio: Core.Ipc.get("isola.mostra.vassoio", true) !== false
    readonly property bool isolaStato: Core.Ipc.get("isola.mostra.stato", true) !== false
    readonly property bool isolaData: Core.Ipc.get("isola.mostra.data", true) !== false
}
