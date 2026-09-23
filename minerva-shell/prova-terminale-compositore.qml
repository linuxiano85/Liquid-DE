import QtQuick
import Quickshell
import "terminale" as T

ShellRoot {
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 500; visible: true
        T.RigaComando { id: riga; width: 880 }
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            riga.apri();
            riga.accetta("git l");
            riga.risposta({testo: "git l", fantasma: "git log", proposte: [
                {inserimento: "git log", spiegazione: "Mostra la storia"}]});
            if (riga.proposte.length !== 1 || riga.fantasma !== "git log") throw new Error("risposta persa");
            riga.risposta({testo: "vecchio", proposte: []});
            if (riga.proposte.length !== 1) throw new Error("risposta obsoleta applicata");
            riga.chiedi({t: "confermaIncolla", motivo: "Due righe", testo: "echo uno\necho due"});
            if (!riga.conferma) throw new Error("conferma assente");
            riga.chiudi();
            if (riga.conferma || riga.aperta) throw new Error("annullamento fallito");
            console.log("COMPOSITORE OK");
            Qt.quit();
        }
    }
}
