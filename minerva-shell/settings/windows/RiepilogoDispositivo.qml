import QtQuick
import Quickshell
import "../../core" as Core

// Una lettura per visita; un nuovo tentativo parte solo su richiesta.
QtObject {
    id: riepilogo
    property var dati: ({})
    property bool pronto: false
    property string errore: ""
    readonly property bool busy: lettura.busy
    readonly property string helper: (Quickshell.env("LIQUID_DE") || Quickshell.shellDir + "/..") + "/scripts/liquid-system-summary.py"
    function leggi() {
        if (busy) return;
        pronto = false;
        errore = "";
        lettura.start(["python3", "-I", helper].concat(Quickshell.env("MINERVA_PROVA") === "1" ? ["--fixture"] : []));
    }
    property Core.Exec lettura: Core.Exec {
        timeoutMs: 10000
        onCompleted: function(code, out, stderr) {
            try {
                if (code !== 0) throw new Error("helper-exit");
                var result = JSON.parse(out);
                if (!result || Array.isArray(result) || typeof result.cpu !== "string" || typeof result.kernel !== "string" || typeof result.architecture !== "string")
                    throw new Error("invalid-summary");
                riepilogo.dati = result;
            } catch (error) {
                riepilogo.errore = Core.Strings.lang === "it" ? "Impossibile leggere le informazioni del dispositivo. Premi per riprovare." : "Cannot read device information. Click to retry.";
                console.warn("[Liquid][SystemSummary] read failed; exitCode=" + code + "; characters=" + out.length);
            }
            riepilogo.pronto = true;
        }
    }
    Component.onCompleted: leggi()
}
