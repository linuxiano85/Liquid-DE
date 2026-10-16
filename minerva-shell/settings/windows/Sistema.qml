import QtQuick
import "../../core" as Core
import "../../windows11" as W

// Ordine dalla VM: categoria-sistema-01/02.png. Le funzioni non costruite
// restano riconoscibili ma non aprono una pagina diversa per fingere supporto.
PaginaWindows {
    id: pagina
    function tr(it, en) { return W.Style.label(it, en); }
    briciole: [{testo: tr("Sistema", "System")}]
    RiepilogoDispositivo { id: dispositivo }
    Component.onCompleted: if (Core.Ipc.connected) Core.Ipc.send({action: "liquid_update_subscribe"});
    Component.onDestruction: if (Core.Ipc.connected) Core.Ipc.send({action: "liquid_update_unsubscribe"});
    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (Core.Ipc.connected) Core.Ipc.send({action: "liquid_update_subscribe"});
        }
    }
    SchedaImpostazione {
        objectName: "systemSummaryError"
        visible: dispositivo.errore !== ""
        titolo: W.Style.label("Informazioni non disponibili", "Information unavailable")
        descrizione: dispositivo.errore
        icona: "informazioni"
        porta: true
        enabled: !dispositivo.busy
        onAttivata: dispositivo.leggi()
    }
    IntestazioneDispositivo {
        prefisso: "system"
        dati: dispositivo.dati
        onAggiornamentiChiesti: if (pagina.finestra) pagina.finestra.apriWindows("w-update")
    }
    readonly property var voci: [
        {id:"display", icon:"monitor", it:"Schermo", en:"Display", descIt:"Monitor, luminosità, luce notturna, profilo schermo", descEn:"Monitors, brightness, night light, display profile", pagina:"display"},
        {id:"audio", icon:"volume", it:"Audio", en:"Sound", descIt:"Livelli del volume, output, input, dispositivi audio", descEn:"Volume levels, output, input, sound devices", pagina:"audio"},
        {id:"notifiche", icon:"bell", it:"Notifiche", en:"Notifications", descIt:"Avvisi dalle app e dal sistema, non disturbare", descEn:"App and system alerts, do not disturb", pagina:"notifiche"},
        {id:"concentrazione", icon:"moon", it:"Concentrazione", en:"Focus", descIt:"Consente di ridurre le distrazioni", descEn:"Helps reduce distractions"},
        {id:"power", icon:"power", it:Core.SystemState.hasBattery ? "Alimentazione e batteria" : "Alimentazione", en:Core.SystemState.hasBattery ? "Power & battery" : "Power", descIt:"Schermo e sospensione, modalità risparmio energia", descEn:"Screen and sleep, energy saving" , pagina:"power"},
        {id:"archiviazione", icon:"folder", it:"Archiviazione", en:"Storage", descIt:"Spazio di archiviazione, unità, regole di configurazione", descEn:"Storage space, drives, configuration rules"},
        {id:"condivisione", icon:"network", it:"Condivisione in prossimità", en:"Nearby sharing", descIt:"Rilevabilità, percorso dei file ricevuti", descEn:"Discoverability, received file location"},
        {id:"multitasking", icon:"restore", it:"Multitasking", en:"Multitasking", descIt:"Ancoraggio finestre, desktop, cambio attività", descEn:"Window snapping, desktops, task switching", pagina:"finestre"},
        {id:"sviluppatori", icon:"settings", it:"Per sviluppatori", en:"For developers", descIt:"Impostazioni per attività di sviluppo", descEn:"Settings for development tasks"},
        {id:"licenza", icon:"check", it:"Licenza", en:"License", descIt:"Liquid DE è software libero, licenza GPL-3.0", descEn:"Liquid DE is free software, GPL-3.0 license", destinazione:"w-licenza"},
        {id:"risoluzione", icon:"settings", it:"Risoluzione problemi", en:"Troubleshoot", descIt:"Strumenti consigliati, preferenze, cronologia", descEn:"Recommended tools, preferences, history"},
        {id:"ripristino", icon:"restore", it:"Ripristino", en:"Recovery", descIt:"Ripristina le impostazioni di Liquid", descEn:"Reset Liquid settings", destinazione:"w-ripristino"},
        {id:"proiezione", icon:"monitor", it:"Proiezione su questo PC", en:"Projecting to this PC", descIt:"Autorizzazioni, associazione, rilevabilità", descEn:"Permissions, pairing, discoverability"},
        {id:"remoto", icon:"network", it:"Desktop remoto", en:"Remote Desktop", descIt:"Utenti desktop remoto, autorizzazioni di connessione", descEn:"Remote desktop users, connection permissions"},
        {id:"appunti", icon:"document", it:"Appunti", en:"Clipboard", descIt:"Cronologia delle operazioni di taglia e copia, sincronizzazione, cancellazione", descEn:"Cut and copy history, synchronization, clearing"},
        {id:"componenti", icon:"window", it:"Componenti di sistema", en:"System components", descIt:"Versione e componenti di Liquid DE", descEn:"Liquid DE version and components", pagina:"shell"},
        {id:"facoltative", icon:"apps", it:"Funzionalità facoltative", en:"Optional features", descIt:"Funzionalità aggiuntive per il dispositivo", descEn:"Additional device features"},
        {id:"shell", icon:"informazioni", it:"Informazioni sul sistema", en:"About", descIt:"Specifiche dei dispositivi e di Linux, versione di Liquid", descEn:"Device and Linux specifications, Liquid version", pagina:"shell"}
    ]
    Repeater {
        model: pagina.voci
        delegate: SchedaImpostazione {
            required property var modelData
            objectName: "categoriaVoce-" + modelData.id
            icona: modelData.icon
            titolo: pagina.tr(modelData.it, modelData.en)
            descrizione: pagina.tr(modelData.descIt, modelData.descEn)
            disponibile: !!modelData.pagina || !!modelData.destinazione
            porta: true
            onAttivata: {
                if (!pagina.finestra) return;
                if (modelData.destinazione) pagina.finestra.apriWindows(modelData.destinazione);
                else pagina.finestra.apriSezione(modelData.pagina, "sistema");
            }
        }
    }
    Item { width: 1; height: 20 }
    SchedaImpostazione {
        objectName: "categoriaVoce-scorciatoie"
        titolo: pagina.tr("Scorciatoie di Liquid", "Liquid shortcuts")
        descrizione: pagina.tr("Combinazioni di tasti della Shell e del compositore", "Shell and compositor key bindings")
        icona: "tastiera"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriSezione("scorciatoie", "sistema");
    }
}
