import QtQuick
import Quickshell
import Quickshell.Io

// Nessun timer o monitor: questi dati non cambiano durante la visita.
QtObject {
    id: riepilogo
    property var dati: ({})
    property bool pronto: false
    property Process lettura: Process {
        command: ["python3", "-I", decodeURIComponent(Qt.resolvedUrl("../../../scripts/liquid-system-summary.py").toString().replace(/^file:\/\//, ""))].concat(Quickshell.env("MINERVA_PROVA") === "1" ? ["--fixture"] : [])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    riepilogo.dati = JSON.parse(text);
                } catch (errore) {
                    riepilogo.dati = {};
                }
                riepilogo.pronto = true;
            }
        }
        onExited: riepilogo.pronto = true
    }
    Component.onCompleted: lettura.running = true
}
