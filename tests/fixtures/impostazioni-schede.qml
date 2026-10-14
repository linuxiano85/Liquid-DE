import QtQuick
import Quickshell
import Quickshell.Io
import "@CORE@" as Core
import "@SECTIONS@" as Settings
import "@THEME@" as Theme

// La shell minima per `tests/prova_impostazioni_schede.py`: le pagine vere
// «Barra e dock» e «Preset», in due finestre, e una porta IPC per leggere
// quali schede si vedono, quali sono aperte e dove stanno.
ShellRoot {
    id: radice

    /// Quale pagina si vede: le due stanno nella stessa finestra, una alla
    /// volta. Due finestre si sovrapponevano, e il clic andava a quella sopra.
    property string mostra: "dock"

    FloatingWindow {
        id: finestra
        title: "Impostazioni di prova"
        implicitWidth: 1000
        implicitHeight: 700
        color: Theme.Colors.window
        Settings.Dock {
            id: dock
            anchors.fill: parent
            visible: radice.mostra === "dock"
            // Come fa `System.qml` dopo il caricamento.
            Component.onCompleted: sezione = "dock"
        }
        Settings.Preset {
            id: preset
            anchors.fill: parent
            visible: radice.mostra === "preset"
            Component.onCompleted: sezione = "preset"
        }
    }

    function schede(pagina) {
        var fuori = [];
        function giro(it) {
            if (it.chiudibile !== undefined && it.heading !== undefined) {
                var testa = null;
                for (var c of it.children)
                    if (c.objectName === "schedaTestata")
                        testa = c;
                var p = testa ? testa.mapToItem(null, testa.width / 2, testa.height / 2) : { "x": 0, "y": 0 };
                fuori.push({ "titolo": it.heading, "indice": it.indice, "visibile": it.valePerIlPreset,
                             "aperta": it.aperta, "altezza": it.height, "chiave": it.chiave,
                             "x": Math.round(p.x), "y": Math.round(p.y) });
            }
            for (var k of (it.children || []))
                giro(k);
        }
        giro(pagina);
        return fuori;
    }

    IpcHandler {
        target: "schede-prova"

        function stato(): string {
            return JSON.stringify({
                "pronto": Core.Ipc.impostazioniArrivate,
                "preset": Core.DesktopStyle.attuale,
                "ricordate": Core.Ipc.get("settings.schedeAperte", ({})),
                "dock": radice.schede(dock),
                "pagPreset": radice.schede(preset)
            });
        }
        function preset(nome: string): string { Core.DesktopStyle.applica(nome); return "ok"; }
        function cerca(testo: string): string { dock.revealSetting(testo); return "ok"; }
        function mostra(nome: string): string { radice.mostra = nome; return "ok"; }
    }
}
