import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S

// Questa pagina espone soltanto protezioni realmente gestite da Liquid:
// non simula autorizzazioni globali per le app Linux non isolate.
PaginaWindows {
    id: pagina
    briciole: [{ testo: W.Style.label("Privacy e sicurezza", "Privacy & security") }]

    GruppoImpostazioni { testo: W.Style.label("Privacy", "Privacy") }
    SchedaImpostazione {
        titolo: W.Style.label("Notifiche sulla schermata di blocco", "Lock screen notifications")
        descrizione: W.Style.label("Scegli quali informazioni mostrare quando il computer è bloccato.",
                                   "Choose which information appears while the computer is locked.")
        icona: "bell"
        TendinaWindows {
            objectName: "privacyNotificheBlocco"
            valore: Core.Ipc.get("notifications.bloccoMostra", "numero")
            voci: [
                { valore: "numero", testo: W.Style.label("Solo il numero", "Count only") },
                { valore: "tutto", testo: W.Style.label("Contenuto completo", "Full content") },
                { valore: "niente", testo: W.Style.label("Nessuna notifica", "No notifications") }
            ]
            onScelto: function(v) { Core.Ipc.setSetting("notifications.bloccoMostra", v); }
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("File recenti nel menu Start", "Recent files in Start")
        descrizione: W.Style.label("Mostra i file consigliati nel menu del preset Familiare.",
                                   "Show recommended files in the Familiare preset menu.")
        icona: "document"
        S.ToggleSwitch {
            objectName: "privacyFileRecenti"
            Accessible.name: W.Style.label("File recenti nel menu Start", "Recent files in Start")
            checked: Core.Ipc.get("windows11.recommendations", true)
            onToggled: function(v) { Core.Ipc.setSetting("windows11.recommendations", v); }
        }
    }
    GruppoImpostazioni { testo: W.Style.label("Sicurezza", "Security") }
    SchedaImpostazione {
        objectName: "privacyAccesso"
        titolo: W.Style.label("Opzioni di accesso", "Sign-in options")
        descrizione: W.Style.label("Schermata di accesso e accesso automatico", "Sign-in screen and automatic sign-in")
        icona: "lock"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriSezione("accesso", "privacy")
    }
    SchedaImpostazione {
        objectName: "privacyBlocco"
        titolo: W.Style.label("Blocco e sospensione", "Lock and sleep")
        descrizione: W.Style.label("Inattività, blocco automatico e sospensione", "Idle time, automatic locking and sleep")
        icona: "power"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriSezione("power", "privacy")
    }
    SchedaImpostazione {
        objectName: "privacyUpdate"
        titolo: "Liquid Update"
        descrizione: W.Style.label("Controlla gli aggiornamenti del desktop", "Check for desktop updates")
        icona: "download"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriWindows("w-update")
    }
}
