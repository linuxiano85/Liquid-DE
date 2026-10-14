import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "@CORE@" as Core
import "@SETTINGS@" as Settings
import "@THEME@" as Theme

// La finestra vera delle Impostazioni (`settings/System.qml`) per
// `tests/prova_impostazioni_windows.py`, con una porta IPC per leggere cosa
// mostra: navigazione, categoria, briciola, colori e dove stanno i comandi.
ShellRoot {
    id: radice

    Theme.LegaTema { }

    Settings.System {
        id: finestra
        section: "display"
        implicitWidth: 1100
        implicitHeight: 760
    }

    /// Ogni oggetto con un `objectName`, col suo centro in coordinate della
    /// finestra: la prova ci clicca sopra col mouse del compositore.
    function controlli() {
        var fuori = {};
        function giro(it) {
            if (!it)
                return;
            if (it.objectName && it.visible && it.width > 0 && it.height > 0) {
                var p = it.mapToItem(null, it.width / 2, it.height / 2);
                fuori[it.objectName] = { "x": Math.round(p.x), "y": Math.round(p.y),
                                         "w": Math.round(it.width), "h": Math.round(it.height),
                                         "testo": it.text !== undefined ? String(it.text) : "",
                                         "colore": it.color !== undefined ? String(it.color) : "",
                                         "enabled": it.enabled, "aperta": it.aperta !== undefined ? it.aperta : false,
                                         "status": it.status !== undefined ? it.status : -1 };
            }
            for (var k of (it.children || []))
                giro(k);
        }
        var window = finestra.contentItem.Window.window;
        giro(window ? window.contentItem : finestra.contentItem);
        return fuori;
    }

    /// Il primo interruttore che si vede nella pagina aperta: la prova lo
    /// clicca e guarda che la scelta arrivi al demone e torni indietro.
    function primoInterruttore() {
        var trovato = null;
        function giro(it) {
            if (!it || trovato || !it.visible)
                return;
            if (it.requestToggle !== undefined && it.checked !== undefined && it.width > 0) {
                var p = it.mapToItem(null, it.width / 2, it.height / 2);
                if (p.y > 120 && p.y < finestra.height - 20) {
                    trovato = { "x": Math.round(p.x), "y": Math.round(p.y),
                                "w": Math.round(it.width), "h": Math.round(it.height),
                                "acceso": it.checked };
                    return;
                }
            }
            for (var k of (it.children || []))
                giro(k);
        }
        giro(finestra.contentItem);
        return trovato;
    }

    /// Le pagine che non stanno in nessuna categoria, o in più di una.
    function fuoriPosto() {
        var fuori = [];
        for (var i = 0; i < finestra.sections.length; i++) {
            var id = finestra.sections[i].id, quante = 0;
            for (var c of finestra.categorieWindows)
                if (c.voci.indexOf(id) >= 0)
                    quante++;
            if (quante !== 1)
                fuori.push(id + ":" + quante);
        }
        return fuori;
    }

    function scelte() {
        var finestre = [];
        var viste = [];
        function visita(item) {
            if (!item || viste.indexOf(item) >= 0)
                return;
            viste.push(item);
            if (item.objectName === "selettoreFileWindows") {
                if (item.visible)
                    finestre.push(item);
                return;
            }
            for (var c of (item.data || []))
                visita(c);
            for (var c of (item.children || []))
                visita(c);
        }
        visita(finestra.contentItem);
        return finestre;
    }
    function controlliScelta(win) {
        var result = {};
        function leggi(item) {
            if (item.objectName && item.visible && item.width > 0 && item.height > 0) {
                var point = item.mapToItem(win.contentItem, item.width / 2, item.height / 2);
                result[item.objectName] = {x: point.x, y: point.y, w: item.width, h: item.height, text: item.text || ""};
            }
            for (var child of (item.children || []))
                leggi(child);
        }
        leggi(win.contentItem);
        return result;
    }
    IpcHandler {
        target: "impostazioni-windows"
        function updateState(): string { return JSON.stringify(Core.Ipc.liquidUpdateState); }
        function lingua(value: string): void { Core.Strings.requestedLanguage = value; }
        function sceltaModale(value: bool): void {
            var windows = radice.scelte();
            if (windows.length) {
                // Qt applica la modalità alla creazione della superficie:
                // ricrearla evita di verificare una proprietà senza effetto.
                var win = windows[0];
                win.visible = false;
                win.modality = value ? Qt.WindowModal : Qt.NonModal;
                win.visible = true;
            }
        }
        function sceltaStato(): string {
            var wins = radice.scelte();
            if (wins.length === 0)
                return JSON.stringify({visible: false});
            var win = wins[0];
            return JSON.stringify({visible: true, directory: win.cartella, loading: win.caricando,
                error: win.errore, request: win.richiesta, names: win.mostrate.map(function(v) { return v.name; }),
                modality: win.modality, hasOwner: win.transientParent !== null, folderOnly: win.soloCartelle,
                controls: radice.controlliScelta(win)});
        }

        function stato(): string {
            return JSON.stringify({
                "pronto": Core.Ipc.impostazioniArrivate,
                "preset": Core.DesktopStyle.attuale,
                "windows": finestra.stileWindows,
                "sezione": finestra.section,
                "categoria": finestra.paginaCategoria,
                "paginaWindows": finestra.paginaWindows,
                "percorso": finestra.percorsoAttuale(),
                "cronologia": finestra.cronologiaPercorsi,
                "categoriaAttiva": finestra.categoriaAttiva,
                "colori": {
                    "finestra": String(Theme.Colors.window),
                    "scheda": String(Theme.Colors.raised),
                    "testo": String(Theme.Colors.text),
                    "accento": String(Theme.Colors.accent),
                    "bordo": String(Theme.Colors.edge),
                    "scura": Theme.Colors.scura
                },
                "carattere": Theme.Typography.fontDisplay,
                "fuoriPosto": radice.fuoriPosto(),
                "interruttore": radice.primoInterruttore(),
                "controlli": radice.controlli()
            });
        }
        function scorrimento(valore: string): string {
            function trova(item) {
                if (item.posizioneScorrimento !== undefined) {
                    item.posizioneScorrimento = Number(valore);
                    return true;
                }
                for (var child of (item.children || [])) {
                    if (trova(child))
                        return true;
                }
                return false;
            }
            return trova(finestra.contentItem) ? "ok" : "assente";
        }
        function mostra(nome: string): string {
            function trova(item) {
                if (item.objectName === nome)
                    return item;
                for (var child of (item.children || [])) {
                    var found = trova(child);
                    if (found)
                        return found;
                }
                return null;
            }
            var item = trova(finestra.contentItem);
            var ancestor = item;
            while (ancestor && !ancestor.revealItem)
                ancestor = ancestor.parent;
            if (ancestor)
                ancestor.revealItem(item);
            return "ok";
        }
        function preset(nome: string): string { Core.DesktopStyle.applica(nome); return "ok"; }
        function sezione(id: string): string { finestra.apriSezione(id); return "ok"; }
        function tema(scuro: string): string {
            Core.Ipc.setSetting("windows11.theme", scuro === "scuro" ? "dark" : "light");
            return "ok";
        }
        function cerca(testo: string): string { finestra.ricerca = testo; return "ok"; }
        function paginaWindows(id: string): string { finestra.apriWindows(id); return "ok"; }
        function titoloStato(): string {
            var titoli = {};
            function leggi(item) {
                if (!item.visible)
                    return;
                if (["Scegli la modalità", "Effetti di trasparenza", "Colore principale"].indexOf(item.text) >= 0)
                    titoli[item.text] = item.width;
                for (var child of (item.children || []))
                    leggi(child);
            }
            leggi(finestra.contentItem);
            return JSON.stringify({pagina: finestra.paginaWindows, ricerca: finestra.ricerca,
                titoli: titoli, campo: controlli()["ricercaWindows"] || null});
        }
        function valore(chiave: string): string { return JSON.stringify(Core.Ipc.get(chiave, null)); }
        function fuoco(nome: string): bool {
            function trova(item) {
                if (item.objectName === nome)
                    return item;
                for (var child of (item.children || [])) {
                    var result = trova(child);
                    if (result)
                        return result;
                }
                return null;
            }
            var item = trova(finestra.contentItem);
            if (!item)
                return false;
            item.forceActiveFocus(Qt.TabFocusReason);
            return true;
        }
    }
}
