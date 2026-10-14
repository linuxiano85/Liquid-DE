import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S
import "Dati.js" as Dati

// Ordine e raggruppamenti dalla VM: ogni comando disponibile cambia davvero
// la barra. Nascondere un pulsante conserva l'accesso tramite scorciatoie.
PaginaWindows {
    id: pagina
    readonly property string lingua: Core.Strings.lang
    briciole: [
        { "testo": Dati.t(lingua, "personalizzazione"), "pagina": "w-personalizzazione" },
        { "testo": Dati.t(lingua, "barra") }
    ]
    EspansoreImpostazione {
        titolo: W.Style.label("Elementi della barra delle applicazioni", "Taskbar items")
        descrizione: W.Style.label("Mostra o nasconde i pulsanti visualizzati sulla barra delle applicazioni", "Show or hide buttons that appear on the taskbar")
        aperto: true
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Cerca", "Search")
            icona: "search"
            TendinaWindows {
                objectName: "barraCerca"
                valore: Core.Ipc.get("windows11.taskbarSearch", "icon")
                voci: [
                    { "valore": "hidden", "testo": W.Style.label("Nascondi", "Hide") },
                    { "valore": "icon", "testo": W.Style.label("Solo icona di ricerca", "Search icon only") },
                    { "valore": "label", "testo": W.Style.label("Icona ed etichetta di ricerca", "Search icon and label") },
                    { "valore": "box", "testo": W.Style.label("Casella di ricerca", "Search box") }
                ]
                onScelto: function(v) { Core.Ipc.setSetting("windows11.taskbarSearch", v); }
            }
        }
        Repeater {
            model: [
                { "id": "TaskView", "testo": W.Style.label("Visualizzazione attività", "Task view"), "icona": "window" },
                { "id": "Widgets", "testo": W.Style.label("Widget", "Widgets"), "icona": "apps" }
            ]
            delegate: SchedaImpostazione {
                required property var modelData
                interna: true
                titolo: modelData.testo
                icona: modelData.icona
                S.ToggleSwitch {
                    objectName: "barra" + modelData.id
                    Accessible.name: modelData.testo
                    checked: Core.Ipc.get("windows11.taskbar" + modelData.id, true)
                    onToggled: function(v) { Core.Ipc.setSetting("windows11.taskbar" + modelData.id, v); }
                }
            }
        }
    }
    EspansoreImpostazione {
        titolo: W.Style.label("Icone della barra delle applicazioni", "System tray icons")
        descrizione: W.Style.label("Scegli le icone che possono apparire nella barra delle applicazioni", "Choose which icons can appear on the taskbar")
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Menu Penna", "Pen menu")
            disponibile: false
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Tastiera virtuale", "Touch keyboard")
            disponibile: false
        }
    }
    EspansoreImpostazione {
        titolo: W.Style.label("Comportamenti della barra delle applicazioni", "Taskbar behaviors")
        descrizione: W.Style.label("Allineamento della barra delle applicazioni e visualizzazione del desktop", "Taskbar alignment and show desktop")
        aperto: true
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Allineamento della barra delle applicazioni", "Taskbar alignment")
            TendinaWindows {
                objectName: "barraAllineamento"
                valore: Core.Ipc.get("windows11.taskbarAlignment", "center")
                voci: [
                    { "valore": "left", "testo": W.Style.label("Sinistra", "Left") },
                    { "valore": "center", "testo": W.Style.label("Al centro", "Center") }
                ]
                onScelto: function(v) { Core.Ipc.setSetting("windows11.taskbarAlignment", v); }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Seleziona l'angolo della barra delle applicazioni per mostrare il desktop", "Select the far corner of the taskbar to show the desktop")
            S.ToggleSwitch {
                objectName: "barraMostraDesktop"
                Accessible.name: W.Style.label("Mostra desktop", "Show desktop")
                checked: Core.Ipc.get("windows11.taskbarShowDesktop", true)
                onToggled: function(v) { Core.Ipc.setSetting("windows11.taskbarShowDesktop", v); }
            }
        }
    }
    GruppoImpostazioni { testo: Dati.t(pagina.lingua, "opzioniLiquid") }
    SchedaImpostazione {
        titolo: W.Style.label("Pulsante tiling / classico", "Tiling / classic button")
        icona: "grid"
        S.ToggleSwitch {
            objectName: "barraTiling"
            Accessible.name: W.Style.label("Pulsante tiling", "Tiling button")
            checked: Core.Ipc.get("windows11.showTilingButton", false)
            onToggled: function(v) { Core.Ipc.setSetting("windows11.showTilingButton", v); }
        }
    }
    GruppoImpostazioni { testo: Dati.t(pagina.lingua, "correlate") }
    Repeater {
        model: [
            { "id": "dataora", "testo": W.Style.label("Data e ora", "Date and time"), "icona": "calendar" },
            { "id": "notifiche", "testo": W.Style.label("Notifiche", "Notifications"), "icona": "bell" }
        ]
        delegate: SchedaImpostazione {
            required property var modelData
            titolo: modelData.testo
            icona: modelData.icona
            porta: true
            onAttivata: if (pagina.finestra) pagina.finestra.apriWindows(modelData.id)
        }
    }
}
