import QtQuick
import Quickshell
import Quickshell.Io
import "@CORE@" as Core
import "@MENU@" as Menu

// La shell minima per `tests/prova_selettore_preset.py`: il selettore dei
// preset vero, sullo schermo di prova, e una porta IPC per guidarlo e
// leggerne lo stato.
ShellRoot {
    id: radice

    readonly property var schermo: Quickshell.screens.find(function (s) { return s.name === "HEADLESS-1"; })

    property string ultimoScelto: ""

    Menu.SelettorePreset {
        id: sel
        screen: radice.schermo
        onScelto: function (nome) { radice.ultimoScelto = nome; }
    }

    function trova(item, nome) {
        if (item.objectName === nome)
            return item;
        for (var c of (item.children || [])) {
            var r = trova(c, nome);
            if (r)
                return r;
        }
        return null;
    }

    IpcHandler {
        target: "preset-test"

        function commuta(): string { sel.commuta(); return "ok"; }

        /// Lo stato in JSON: aperto, quale scheda è evidenziata, il preset in
        /// uso e il centro di ogni scheda (coordinate dello schermo).
        function stato(): string {
            var schede = {};
            for (var i = 0; i < Core.DesktopStyle.elenco.length; i++) {
                var id = Core.DesktopStyle.elenco[i].id;
                var s = radice.trova(sel.contentItem, "presetScheda-" + id);
                if (s && s.visible) {
                    var p = s.mapToItem(sel.contentItem, s.width / 2, s.height / 2);
                    schede[id] = { "x": Math.round(p.x), "y": Math.round(p.y) };
                }
            }
            return JSON.stringify({
                "pronto": Core.Ipc.impostazioniArrivate,
                "aperto": sel.aperto,
                "mostrato": sel.mostrato,
                "indice": sel.indice,
                "evidenziato": Core.DesktopStyle.elenco[sel.indice].id,
                "attuale": Core.DesktopStyle.attuale,
                "ultimoScelto": radice.ultimoScelto,
                "schede": schede
            });
        }
    }
}
