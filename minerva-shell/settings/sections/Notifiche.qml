import QtQuick
import Quickshell
import "../../core/NotificationSchedule.js" as NotificationSchedule
import "../../core/NotificationSenders.js" as NotificationSenders
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Notifiche — Non disturbare, e cosa si vede sulla schermata di blocco.
//
// il manutentore, 23 settembre 2026: «ovviamente può essere personalizzabile e poter
// nascondere per privacy parte della notifica, se mi arrivano mail mi dice
// solo che ci sono ad esempio 3 email, tipo come gli smartphone, e dobbiamo
// aggiungere la personalizzazione nelle impostazioni».
//
// «Non disturbare» stava nella pagina Minerva, in mezzo al menù delle app:
// è venuto qui, dove si cercano le notifiche. Una manopola sola in un posto
// solo — due interruttori per la stessa cosa divergono.
Page {
    id: page

    property SystemClock orologio: SystemClock { precision: SystemClock.Minutes }
    readonly property bool it: Core.Strings.lang === "it"
    readonly property var mittenti: Core.Ipc.get("notifications.apps", ({}))
    readonly property var chiaviMittenti: NotificationSenders.keys(mittenti)
    property string mittenteScelto: ""
    readonly property string mittente: mittenti[mittenteScelto] ? mittenteScelto : (chiaviMittenti[0] || "")
    readonly property string mostra: Core.Ipc.get("notifications.bloccoMostra", "numero")

    title: page.it ? "Notifiche" : "Notifications"
    subtitle: page.it ? "Quando interrompono, e cosa si vede a schermo bloccato"
                      : "When they interrupt, and what shows while locked"

    Card {
        heading: page.it ? "Interruzioni" : "Interruptions"

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("notifications.enabled", undefined) !== undefined
            label: page.it ? "Ricevi notifiche" : "Receive notifications"
            description: page.it ? "Disattivando, le nuove notifiche non vengono conservate" : "When off, new notifications are not stored"
            controlWidth: 60
            control: S.ToggleSwitch {
                Accessible.name: page.it ? "Ricevi notifiche" : "Receive notifications"
                checked: Core.Ipc.get("notifications.enabled", true)
                onToggled: function(value) { Core.Ipc.setSetting("notifications.enabled", value); }
            }
        }
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("notifications.banners", undefined) !== undefined
            label: page.it ? "Mostra banner" : "Show banners"
            description: page.it ? "Senza banner, le notifiche restano nel centro notifiche" : "Without banners, notifications stay in notification center"
            controlWidth: 60
            control: S.ToggleSwitch {
                Accessible.name: page.it ? "Mostra banner" : "Show banners"
                enabled: Core.Ipc.get("notifications.enabled", true)
                checked: Core.Ipc.get("notifications.banners", true)
                onToggled: function(value) { Core.Ipc.setSetting("notifications.banners", value); }
            }
        }
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("notifications.sounds", undefined) !== undefined
            label: page.it ? "Riproduci suoni" : "Play sounds"
            controlWidth: 60
            control: S.ToggleSwitch {
                objectName: "notificheSuoniLiquid"
                Accessible.name: page.it ? "Riproduci suoni" : "Play sounds"
                enabled: Core.Ipc.get("notifications.enabled", true)
                checked: Core.Ipc.get("notifications.sounds", true)
                onToggled: function(value) { Core.Ipc.setSetting("notifications.sounds", value); }
            }
        }
        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("doNotDisturb")
            description: Core.Strings.t("doNotDisturbDesc")
            searchTerms: "non disturbare silenzio notifiche"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: NotificationSchedule.isQuiet(page.orologio.date, Core.Ipc.get)
                onToggled: function(v) {
                    NotificationSchedule.setQuiet(new Date(), Core.Ipc.get, Core.Ipc.setSetting, v);
                }
            }
        }
    }

    Card {
        visible: Core.Ipc.get("notifications.scheduleEnabled", undefined) !== undefined
        objectName: "notificheRegoleLiquid"
        heading: page.it ? "Non disturbare programmato" : "Scheduled do not disturb"
        note: page.it ? "Ora locale. I giorni si riferiscono all'inizio dell'intervallo; orari uguali coprono l'intera giornata. Disattivare Non disturbare sospende la regola per il solo intervallo attuale."
                      : "Local time. Days refer to the start of the interval; equal times cover the whole day. Turning Do not disturb off pauses the rule for this interval only."
        S.SettingRow {
            width: parent.width
            label: page.it ? "Durante questi orari" : "During these times"
            controlWidth: 60
            control: S.ToggleSwitch {
                objectName: "notificheProgrammaLiquid"
                checked: Core.Ipc.get("notifications.scheduleEnabled", false)
                onToggled: function(value) { NotificationSchedule.setSchedule(Core.Ipc.get, Core.Ipc.setSetting, "notifications.scheduleEnabled", value); }
            }
        }
        Repeater {
            model: [{key:"scheduleFrom",it:"Dalle",en:"From",fallback:"22:00"},
                {key:"scheduleTo",it:"Alle",en:"Until",fallback:"07:00"}]
            delegate: S.SettingRow {
                id: riga
                required property var modelData
                width: parent.width
                label: page.it ? modelData.it : modelData.en
                controlWidth: 200
                control: S.Tendina {
                    objectName: "notificheOraLiquid-" + riga.modelData.key
                    width: 200
                    enabled: Core.Ipc.get("notifications.scheduleEnabled", false)
                    value: Core.Ipc.get("notifications." + riga.modelData.key,riga.modelData.fallback)
                    options: {
                        var result = [];
                        for (var minute = 0; minute < 1440; minute += 15) {
                            var text = String(Math.floor(minute/60)).padStart(2,"0") + ":" + String(minute%60).padStart(2,"0");
                            result.push({value:text,label:text});
                        }
                        if (!result.some(function(item) { return item.value === value; }))
                            result.push({value:value,label:value});
                        return result.sort(function(a,b) { return a.value.localeCompare(b.value); });
                    }
                    onPicked: function(value) { NotificationSchedule.setSchedule(Core.Ipc.get, Core.Ipc.setSetting, "notifications." + riga.modelData.key, value); }
                }
            }
        }
        S.SettingRow {
            width: parent.width
            label: page.it ? "Ripeti" : "Repeats"
            controlWidth: 240
            control: S.ChoicePicker {
                enabled: Core.Ipc.get("notifications.scheduleEnabled", false)
                value: Core.Ipc.get("notifications.scheduleDays", "daily")
                options: [{value:"daily",label:page.it ? "Ogni giorno" : "Daily"},
                    {value:"weekdays",label:page.it ? "Giorni feriali" : "Weekdays"},
                    {value:"weekends",label:page.it ? "Fine settimana" : "Weekends"}]
                onPicked: function(value) { NotificationSchedule.setSchedule(Core.Ipc.get, Core.Ipc.setSetting, "notifications.scheduleDays", value); }
            }
        }
    }

    Card {
        objectName: "notificheMittentiLiquid"
        visible: Core.Ipc.get("notifications.apps", undefined) !== undefined
        heading: page.it ? "Notifiche delle app" : "App notifications"
        note: page.chiaviMittenti.length === 0
            ? (page.it ? "Le app appaiono dopo la prima notifica." : "Apps appear after their first notification.") : ""
        S.SettingRow {
            visible: page.mittente !== ""
            width: parent.width
            label: page.it ? "App" : "App"
            controlWidth: 260
            control: S.Tendina {
                objectName: "notificheAppSceltaLiquid"
                width: 260
                value: page.mittente
                options: page.chiaviMittenti.map(function(key) { return {value:key,label:page.mittenti[key].name}; })
                onPicked: function(value) { page.mittenteScelto = value; }
            }
        }
        Repeater {
            model: [{key:"enabled",it:"Ricevi notifiche",en:"Receive notifications"},
                {key:"banners",it:"Mostra banner",en:"Show banners"},
                {key:"priority",it:"Consenti con Non disturbare",en:"Allow during do not disturb"}]
            delegate: S.SettingRow {
                id: rigaApp
                required property var modelData
                visible: page.mittente !== ""
                width: parent.width
                label: page.it ? modelData.it : modelData.en
                controlWidth: 60
                control: S.ToggleSwitch {
                    objectName: "notificheAppLiquid-" + rigaApp.modelData.key
                    Accessible.name: rigaApp.label
                    enabled: Core.Ipc.get("notifications.enabled", true) &&
                        (rigaApp.modelData.key === "enabled" || Core.Ipc.get("notifications.apps." + page.mittente + ".enabled", true))
                    checked: Core.Ipc.get("notifications.apps." + page.mittente + "." + rigaApp.modelData.key, rigaApp.modelData.key !== "priority")
                    onToggled: function(value) { Core.Ipc.setSetting("notifications.apps." + page.mittente + "." + rigaApp.modelData.key, value); }
                }
            }
        }
    }

    Card {
        heading: page.it ? "Sulla schermata di blocco" : "On the lock screen"
        note: page.it
            ? "Quelle arrivate e non ancora viste, nella metà libera della schermata. "
              + "Con «Solo quante» il testo non lascia nemmeno la scrivania: la schermata "
              + "di blocco riceve solo i nomi dei programmi e i numeri. Sulla schermata di "
              + "accesso non compaiono mai: prima dell'accesso di tuo non gira niente."
            : "The ones that arrived and you haven't seen yet, on the free half of the screen. "
              + "With “Just how many” the text never leaves the desktop: the lock screen only "
              + "gets app names and counts. They never show on the login screen: before you "
              + "sign in, nothing of yours is running."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra" : "Show"
            searchTerms: "privacy blocco notifiche email contenuto nascondi schermata"
            controlWidth: 360

            control: S.ChoicePicker {
                value: page.mostra
                options: [
                    { "value": "numero", "label": page.it ? "Solo quante" : "Just how many" },
                    { "value": "tutto",  "label": page.it ? "Tutto" : "Everything" },
                    { "value": "niente", "label": page.it ? "Niente" : "Nothing" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("notifications.bloccoMostra", v); }
            }
        }

        // ── L'anteprima ─────────────────────────────────────────────────
        //
        // Una scheda d'esempio, disegnata come sulla schermata di blocco: una
        // scelta di privacy si capisce guardandola, non leggendone la
        // descrizione. Il contenuto è inventato e lo dice.
        Item {
            width: parent.width
            height: esempio.height + Theme.Effects.space4

            Rectangle {
                id: esempio
                width: Math.min(parent.width, 420)
                height: page.mostra === "niente" ? 52 : corpo.implicitHeight + Theme.Effects.space4 * 2
                anchors.horizontalCenter: parent.horizontalCenter
                radius: 18
                color: Qt.rgba(0.05, 0.07, 0.10, 0.92)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                Text {
                    anchors.centerIn: parent
                    visible: page.mostra === "niente"
                    text: page.it ? "La schermata di blocco non mostra notifiche"
                                  : "The lock screen shows no notifications"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Rectangle {
                    id: bollo
                    visible: page.mostra !== "niente"
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space4
                    anchors.top: parent.top
                    anchors.topMargin: Theme.Effects.space4
                    width: 34; height: 34
                    radius: width / 2
                    color: Qt.alpha(Theme.Colors.accent, 0.28)
                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 17; height: 17
                        name: "mail"
                        color: "white"
                    }
                }

                Column {
                    id: corpo
                    visible: page.mostra !== "niente"
                    anchors.left: bollo.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space4
                    anchors.top: parent.top
                    anchors.topMargin: Theme.Effects.space4
                    spacing: 2

                    Text {
                        text: "Thunderbird"
                        color: Qt.rgba(1, 1, 1, page.mostra === "tutto" ? 0.62 : 0.95)
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: page.mostra === "tutto" ? Theme.Typography.sizeXS
                                                                : Theme.Typography.sizeMD
                        font.weight: page.mostra === "tutto" ? Theme.Typography.weightMedium
                                                             : Theme.Typography.weightSemiBold
                    }
                    Text {
                        visible: page.mostra === "numero"
                        text: page.it ? "3 email" : "3 emails"
                        color: Qt.rgba(1, 1, 1, 0.70)
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    Text {
                        visible: page.mostra === "tutto"
                        width: parent.width
                        elide: Text.ElideRight
                        text: page.it ? "Anna — La cena di sabato" : "Anna — Saturday dinner"
                        color: "white"
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightSemiBold
                    }
                    Text {
                        visible: page.mostra === "tutto"
                        width: parent.width
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: page.it ? "Ciao! Confermi per le otto? Porto io il dolce…"
                                      : "Hi! Is eight still fine? I'll bring dessert…"
                        color: Qt.rgba(1, 1, 1, 0.72)
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }
        }
    }
}
