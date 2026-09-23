import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Notifiche — Non disturbare, e cosa si vede sulla schermata di blocco.
//
// Giacomo, 23 settembre 2026: «ovviamente può essere personalizzabile e poter
// nascondere per privacy parte della notifica, se mi arrivano mail mi dice
// solo che ci sono ad esempio 3 email, tipo come gli smartphone, e dobbiamo
// aggiungere la personalizzazione nelle impostazioni».
//
// «Non disturbare» stava nella pagina Minerva, in mezzo al menù delle app:
// è venuto qui, dove si cercano le notifiche. Una manopola sola in un posto
// solo — due interruttori per la stessa cosa divergono.
Page {
    id: page

    readonly property bool it: Core.Strings.lang === "it"
    readonly property string mostra: Core.Ipc.get("notifications.bloccoMostra", "numero")

    title: page.it ? "Notifiche" : "Notifications"
    subtitle: page.it ? "Quando interrompono, e cosa si vede a schermo bloccato"
                      : "When they interrupt, and what shows while locked"

    Card {
        heading: page.it ? "Interruzioni" : "Interruptions"

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("doNotDisturb")
            description: Core.Strings.t("doNotDisturbDesc")
            searchTerms: "non disturbare silenzio notifiche"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("notifications.doNotDisturb", false)
                onToggled: function(v) {
                    Core.Ipc.setSetting("notifications.doNotDisturb", v);
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
