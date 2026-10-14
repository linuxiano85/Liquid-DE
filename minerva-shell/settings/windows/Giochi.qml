import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S

// I controller restano nella categoria Dispositivi; Giochi offre l'accesso
// contestuale alle stesse preferenze, senza un secondo stato divergente.
PaginaWindows {
    id: pagina
    briciole: [{ testo: W.Style.label("Giochi", "Gaming") }]
    SchedaImpostazione {
        titolo: W.Style.label("Gestione automatica dei controller", "Automatic controller management")
        descrizione: W.Style.label("Usa il servizio InputPlumber per i profili dei controller.",
                                   "Use the InputPlumber service for controller profiles.")
        icona: "settings"
        S.ToggleSwitch {
            objectName: "giochiControllerAutomatico"
            Accessible.name: W.Style.label("Gestione automatica dei controller", "Automatic controller management")
            checked: Core.Ipc.get("input.controllerAutomatico", true)
            onToggled: function(v) { Core.Ipc.setSetting("input.controllerAutomatico", v); }
        }
    }
    SchedaImpostazione {
        objectName: "giochiController"
        titolo: W.Style.label("Controller", "Game controllers")
        descrizione: W.Style.label("Profili per dispositivo, disposizione dei tasti, colori e vibrazione",
                                   "Per-device profiles, button layout, colors and vibration")
        icona: "settings"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriSezione("controller", "giochi")
    }
    GruppoImpostazioni { testo: W.Style.label("Impostazioni correlate", "Related settings") }
    SchedaImpostazione {
        objectName: "giochiSchermo"
        titolo: W.Style.label("Schermo", "Display")
        descrizione: W.Style.label("Monitor, risoluzione e frequenza di aggiornamento", "Monitors, resolution and refresh rate")
        icona: "monitor"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriSezione("display", "giochi")
    }
    SchedaImpostazione {
        objectName: "giochiAudio"
        titolo: W.Style.label("Audio", "Sound")
        descrizione: W.Style.label("Dispositivi di uscita e microfono", "Output devices and microphone")
        icona: "volume"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriSezione("audio", "giochi")
    }
}
