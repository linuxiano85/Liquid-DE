import QtQuick
import Quickshell
import "../../core" as Core
import "../../core/NotificationSchedule.js" as NotificationSchedule
import "../../windows11" as W
import ".." as S

PaginaWindows {
    id: pagina
    objectName: "impostazioniNotificheWindows"
    briciole: [{testo:W.Style.label("Sistema", "System"), pagina:"w-sistema"},
        {testo:W.Style.label("Notifiche", "Notifications")}]
    readonly property bool ricezione: Core.Ipc.get("notifications.enabled", true)
    readonly property bool schemaCompleto: Core.Ipc.get("notifications.enabled", undefined) !== undefined
        && Core.Ipc.get("notifications.banners", undefined) !== undefined
    readonly property string privacy: Core.Ipc.get("notifications.bloccoMostra", "numero")
    property SystemClock orologio: SystemClock { precision: SystemClock.Minutes }
    readonly property bool programmaAttivo: Core.Ipc.get("notifications.scheduleEnabled", false)
        && NotificationSchedule.isActive(orologio.date,
            Core.Ipc.get("notifications.scheduleFrom", "22:00"),
            Core.Ipc.get("notifications.scheduleTo", "07:00"),
            Core.Ipc.get("notifications.scheduleDays", "daily"))
    // Riattivare la vista sul blocco nella stessa pagina conserva la scelta
    // precedente. Dopo una nuova apertura si riparte dal valore più privato.
    property string ultimaPrivacy: "numero"
    onPrivacyChanged: if (privacy !== "niente") ultimaPrivacy = privacy
    Component.onCompleted: if (privacy !== "niente") ultimaPrivacy = privacy

    EspansoreImpostazione {
        objectName: "notificheGenerali"
        titolo: W.Style.label("Notifiche", "Notifications")
        descrizione: W.Style.label("Ricevi notifiche dalle app e da altri mittenti", "Get notifications from apps and other senders")
        aperto: true
        comando: S.ToggleSwitch {
            objectName: "notificheRicezione"
            enabled: pagina.schemaCompleto
            Accessible.name: W.Style.label("Notifiche", "Notifications")
            checked: pagina.ricezione
            onToggled: function(value) { Core.Ipc.setSetting("notifications.enabled", value); }
        }
        Item {
            width: parent.width
            height: opzioni.implicitHeight + 32
            Column {
                id: opzioni
                x: 16
                y: 16
                width: parent.width-32
                spacing: 16
                CasellaWindows {
                    objectName: "notificheBanner"
                    testo: W.Style.label("Mostra banner di notifica", "Show notification banners")
                    enabled: pagina.ricezione && pagina.schemaCompleto
                    checked: Core.Ipc.get("notifications.banners", true)
                    onScelta: function(value) { Core.Ipc.setSetting("notifications.banners", value); }
                }
                CasellaWindows {
                    objectName: "notificheBlocco"
                    testo: W.Style.label("Mostra notifiche nella schermata di blocco", "Show notifications on the lock screen")
                    enabled: pagina.ricezione
                    checked: pagina.privacy !== "niente"
                    onScelta: function(value) { Core.Ipc.setSetting("notifications.bloccoMostra", value ? pagina.ultimaPrivacy : "niente"); }
                }
            }
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Non disturbare", "Do not disturb")
        descrizione: W.Style.label("Le notifiche vengono inviate direttamente al centro notifiche", "Notifications are sent directly to notification center")
        searchTerms: "silenzio interruzioni do not disturb"
        S.ToggleSwitch {
            objectName: "notificheNonDisturbare"
            enabled: pagina.ricezione
            Accessible.name: W.Style.label("Non disturbare", "Do not disturb")
            checked: Core.Ipc.get("notifications.doNotDisturb", false)
            onToggled: function(value) { Core.Ipc.setSetting("notifications.doNotDisturb", value); }
        }
    }
    EspansoreImpostazione {
        objectName: "notificheRegole"
        visible: Core.Ipc.get("notifications.scheduleEnabled", undefined) !== undefined
        titolo: W.Style.label("Attiva Non disturbare automaticamente", "Turn on do not disturb automatically")
        descrizione: pagina.programmaAttivo
            ? W.Style.label("Regola oraria attiva", "Time rule active")
            : W.Style.label("Scegli quando silenziare le notifiche", "Choose when to silence notifications")
        aperto: true
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Durante questi orari", "During these times")
            S.ToggleSwitch {
                objectName: "notificheProgramma"
                enabled: pagina.ricezione
                Accessible.name: W.Style.label("Durante questi orari", "During these times")
                checked: Core.Ipc.get("notifications.scheduleEnabled", false)
                onToggled: function(value) { Core.Ipc.setSetting("notifications.scheduleEnabled", value); }
            }
        }
        Repeater {
            model: [{key:"scheduleFrom", it:"Ora di inizio", en:"Start time", fallback:"22:00"},
                {key:"scheduleTo", it:"Ora di fine", en:"End time", fallback:"07:00"}]
            delegate: SchedaImpostazione {
                id: rigaOra
                required property var modelData
                interna: true
                titolo: W.Style.label(modelData.it, modelData.en)
                OraWindows {
                    objectName: "notificheOra-" + rigaOra.modelData.key
                    etichetta: rigaOra.titolo
                    enabled: pagina.ricezione && Core.Ipc.get("notifications.scheduleEnabled", false)
                    valore: Core.Ipc.get("notifications." + rigaOra.modelData.key, rigaOra.modelData.fallback)
                    onScelta: function(value) { Core.Ipc.setSetting("notifications." + rigaOra.modelData.key, value); }
                }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Ripeti", "Repeats")
            TendinaWindows {
                objectName: "notificheGiorni"
                width: Math.max(implicitWidth, 180)
                enabled: pagina.ricezione && Core.Ipc.get("notifications.scheduleEnabled", false)
                valore: Core.Ipc.get("notifications.scheduleDays", "daily")
                voci: [{valore:"daily", testo:W.Style.label("Ogni giorno", "Daily")},
                    {valore:"weekdays", testo:W.Style.label("Giorni feriali", "Weekdays")},
                    {valore:"weekends", testo:W.Style.label("Fine settimana", "Weekends")}]
                onScelto: function(value) { Core.Ipc.setSetting("notifications.scheduleDays", value); }
            }
        }
        Text {
            width: parent.width
            padding: 16
            wrapMode: Text.Wrap
            text: W.Style.label("La regola segue l'ora locale e i giorni in cui inizia l'intervallo. Orari uguali coprono l'intera giornata. Non modifica l'interruttore manuale Non disturbare.",
                "The rule follows local time and the day the interval starts. Equal times cover the whole day. It does not change the manual Do not disturb switch.")
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 12
        }
    }
    GruppoImpostazioni { testo: "Liquid" }
    SchedaImpostazione {
        titolo: W.Style.label("Contenuto sulla schermata di blocco", "Lock screen notification content")
        descrizione: W.Style.label("Solo quante nasconde titolo e testo dei messaggi", "Just how many hides message titles and text")
        TendinaWindows {
            objectName: "notifichePrivacy"
            enabled: pagina.ricezione
            valore: pagina.privacy
            voci: [{valore:"numero", testo:W.Style.label("Solo quante", "Just how many")},
                {valore:"tutto", testo:W.Style.label("Tutto", "Everything")},
                {valore:"niente", testo:W.Style.label("Niente", "Nothing")}]
            onScelto: function(value) { Core.Ipc.setSetting("notifications.bloccoMostra", value); }
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: W.Style.label("Le impostazioni di ricezione valgono per tutti i preset. Non disturbare conserva le notifiche nel centro notifiche. Disattivare Notifiche impedisce la ricezione di nuove notifiche e conserva quelle già presenti.",
            "Notification reception settings apply to all presets. Do not disturb keeps notifications in notification center. Turning Notifications off stops new notifications and keeps the existing history.")
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 12
    }
}
