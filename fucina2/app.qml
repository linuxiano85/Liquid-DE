//@ pragma AppId minerva-fucina2
import QtQuick
import Quickshell
import Quickshell.Io
import "theme" as Theme
import "core" as Core
import "."

ShellRoot {
    Component.onCompleted: {
        Quickshell.watchFiles = false;
    }

    Theme.LegaTema {}
    Core.TenutaPronta {
        id: pronta
        nome: "fucina2"
        laFinestra: finestra
    }

    Fucina2 {
        id: finestra
        dormiente: pronta.dormiente
        onChiusa: pronta.chiudi()
    }

    IpcHandler {
        target: "fucina2"

        function apri(): string {
            pronta.risveglia();
            return "ok";
        }

        function ping(): string {
            return "ok";
        }

        function mostra(sezione: string): string {
            if (["panoramica", "configura", "compila", "kernel"].indexOf(sezione) < 0)
                return "sezione non valida";
            pronta.risveglia();
            finestra.pagina = sezione;
            if (sezione === "kernel") finestra.verificaKernelInUso();
            return "ok";
        }

        function stato(): string {
            return JSON.stringify({pagina: finestra.pagina, kernelInUso: finestra.kernelInUso,
                connesso: Core.Ipc.connected, revisioniStato: finestra.revisioniStato,
                amministrazione: finestra.amministrazioneKernel,
                targetCompilatori: finestra.targetCompilatori,
                supportoNativo: finestra.supportoNativo,
                compilando: finestra.compilando, secondi: finestra.secondiCompilazione,
                log: finestra.logCompilazione, esito: finestra.esitoCompilazione,
                ricetta: finestra.pianoCompilazione, riepilogo: finestra.riepilogoEsecuzione,
                verifica: finestra.verificaKernel});
        }

    }
}
