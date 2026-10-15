import QtQuick
import Quickshell
import "../../core" as Core
import "../../core/NotificationSchedule.js" as NotificationSchedule
import "../../core/NotificationSenders.js" as NotificationSenders
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
    readonly property var mittenti: Core.Ipc.get("notifications.apps", ({}))
    readonly property var chiaviMittenti: NotificationSenders.keys(mittenti)
    property ListModel modelloMittenti: ListModel { }
    property string ordineMittenti: ""
    function aggiornaMittenti() {
        var keys = pagina.chiaviMittenti;
        var signature = keys.join("|");
        if (signature === pagina.ordineMittenti)
            return;
        // Si aggiornano le identità, non si ricreano le righe a ogni checkbox:
        // una preferenza non deve chiudere la scheda né perdere il focus.
        for (var old = modelloMittenti.count-1; old >= 0; old--) {
            if (keys.indexOf(modelloMittenti.get(old).senderKey) < 0)
                modelloMittenti.remove(old);
        }
        for (var i = 0; i < keys.length; i++) {
            var found = -1;
            for (var j = i; j < modelloMittenti.count; j++) {
                if (modelloMittenti.get(j).senderKey === keys[i]) {
                    found = j;
                    break;
                }
            }
            if (found < 0)
                modelloMittenti.insert(i, {senderKey:keys[i]});
            else if (found !== i)
                modelloMittenti.move(found, i, 1);
        }
        pagina.ordineMittenti = signature;
    }
    Connections {
        target: Core.Ipc
        function onSettingsChanged() { Qt.callLater(pagina.aggiornaMittenti); }
    }
    readonly property string privacy: Core.Ipc.get("notifications.bloccoMostra", "numero")
    property SystemClock orologio: SystemClock { precision: SystemClock.Minutes }
    readonly property bool programmaAttivo: NotificationSchedule.scheduledQuiet(orologio.date, Core.Ipc.get)
    readonly property bool programmaSospeso: NotificationSchedule.isPaused(orologio.date, Core.Ipc.get)
    readonly property bool nonDisturbare: NotificationSchedule.isQuiet(orologio.date, Core.Ipc.get)
    // Riattivare la vista sul blocco nella stessa pagina conserva la scelta
    // precedente. Dopo una nuova apertura si riparte dal valore più privato.
    property string ultimaPrivacy: "numero"
    onPrivacyChanged: if (privacy !== "niente") ultimaPrivacy = privacy
    Component.onCompleted: {
        if (privacy !== "niente") ultimaPrivacy = privacy;
        aggiornaMittenti();
    }

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
            checked: pagina.nonDisturbare
            onToggled: function(value) { NotificationSchedule.setQuiet(new Date(), Core.Ipc.get, Core.Ipc.setSetting, value); }
        }
    }
    EspansoreImpostazione {
        objectName: "notificheRegole"
        visible: Core.Ipc.get("notifications.scheduleEnabled", undefined) !== undefined
        titolo: W.Style.label("Attiva Non disturbare automaticamente", "Turn on do not disturb automatically")
        descrizione: pagina.programmaSospeso
            ? W.Style.label("Sospesa fino al prossimo intervallo", "Paused until the next interval")
            : pagina.programmaAttivo
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
                onToggled: function(value) { NotificationSchedule.setSchedule(Core.Ipc.get, Core.Ipc.setSetting, "notifications.scheduleEnabled", value); }
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
                    onScelta: function(value) { NotificationSchedule.setSchedule(Core.Ipc.get, Core.Ipc.setSetting, "notifications." + rigaOra.modelData.key, value); }
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
                onScelto: function(value) { NotificationSchedule.setSchedule(Core.Ipc.get, Core.Ipc.setSetting, "notifications.scheduleDays", value); }
            }
        }
        Text {
            width: parent.width
            padding: 16
            wrapMode: Text.Wrap
            text: W.Style.label("La regola segue l'ora locale e i giorni in cui inizia l'intervallo. Orari uguali coprono l'intera giornata. Disattivare Non disturbare sospende la regola solo per questo intervallo.",
                "The rule follows local time and the day the interval starts. Equal times cover the whole day. Turning Do not disturb off pauses the rule for this interval only.")
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 12
        }
    }
    GruppoImpostazioni {
        visible: Core.Ipc.get("notifications.apps", undefined) !== undefined
        testo: W.Style.label("Notifiche da app e da altri mittenti", "Notifications from apps and other senders")
    }
    Text {
        visible: Core.Ipc.get("notifications.apps", undefined) !== undefined && pagina.chiaviMittenti.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        text: W.Style.label("Le app appariranno qui dopo la prima notifica.", "Apps will appear here after their first notification.")
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 14
    }
    Repeater {
        model: pagina.modelloMittenti
        delegate: EspansoreImpostazione {
            id: gruppoApp
            required property string senderKey
            readonly property var record: pagina.mittenti[senderKey] || ({})
            objectName: "notificheApp-" + senderKey
            titolo: record.name || ""
            icona: "apps"
            immagine: record.desktop && Quickshell.hasThemeIcon(record.desktop) ? Quickshell.iconPath(record.desktop) : ""
            descrizione: !record.enabled ? W.Style.label("Disattivate", "Off")
                : !record.banners ? W.Style.label("Solo centro notifiche", "Notification center only")
                : record.priority ? W.Style.label("Priorità", "Priority")
                : W.Style.label("Banner e centro notifiche", "Banners and notification center")
            comando: S.ToggleSwitch {
                objectName: "notificheAppRicezione-" + gruppoApp.senderKey
                enabled: pagina.ricezione
                Accessible.name: gruppoApp.titolo
                checked: gruppoApp.record.enabled === true
                onToggled: function(value) { Core.Ipc.setSetting("notifications.apps." + gruppoApp.senderKey + ".enabled", value); }
            }
            Loader {
                active: gruppoApp.aperto
                width: parent.width
                height: item ? item.implicitHeight : 0
                sourceComponent: Item {
                    implicitHeight: opzioniApp.implicitHeight + 32
                    Column {
                        id: opzioniApp
                        x: 16
                        y: 16
                        width: parent.width-32
                        spacing: 16
                        CasellaWindows {
                            objectName: "notificheAppBanner-" + gruppoApp.senderKey
                            testo: W.Style.label("Mostra banner di notifica", "Show notification banners")
                            enabled: pagina.ricezione && gruppoApp.record.enabled === true
                            checked: gruppoApp.record.banners === true
                            onScelta: function(value) { Core.Ipc.setSetting("notifications.apps." + gruppoApp.senderKey + ".banners", value); }
                        }
                        CasellaWindows {
                            objectName: "notificheAppPriorita-" + gruppoApp.senderKey
                            testo: W.Style.label("Consenti notifiche quando Non disturbare è attivo", "Allow notifications when do not disturb is on")
                            enabled: pagina.ricezione && gruppoApp.record.enabled === true
                            checked: gruppoApp.record.priority === true
                            onScelta: function(value) { Core.Ipc.setSetting("notifications.apps." + gruppoApp.senderKey + ".priority", value); }
                        }
                    }
                }
            }
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
