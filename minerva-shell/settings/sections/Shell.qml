import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Minerva — l'aiuto e il ripristino. Il resto che stava qui (le finestre, il
// menù delle applicazioni, la scrivania) dal 28 settembre 2026 sta nella
// pagina della cosa di cui parla.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Minerva" : "Minerva"
    subtitle: Core.Strings.lang === "it"
              ? "L'aiuto e il ripristino"
              : "Help and reset"

    readonly property bool it: Core.Strings.lang === "it"
    // «Non disturbare» stava qui fino al 23 settembre 2026: adesso sta nella
    // pagina Notifiche, con quello che si vede a schermo bloccato.

    Card {
        heading: Core.Strings.t("help")

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("showCheatsheet")
            description: Core.Strings.t("showCheatsheetDesc")
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("cheatsheet.enabled", true)
                onToggled: function(v) { Core.Ipc.setSetting("cheatsheet.enabled", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("showOnFirstRun")
            description: Core.Strings.t("showOnFirstRunDesc")
            controlWidth: 60
            enabled: Core.Ipc.get("cheatsheet.enabled", true)
            opacity: enabled ? 1 : 0.4
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("cheatsheet.showOnFirstRun", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("cheatsheet.showOnFirstRun", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("cheatsheetOpacity")
            description: Core.Strings.t("cheatsheetOpacityDesc")
            controlWidth: 220
            enabled: Core.Ipc.get("cheatsheet.enabled", true)
            opacity: enabled ? 1 : 0.4
            control: S.ValueSlider {
                width: 220
                value: Core.Ipc.get("cheatsheet.backgroundOpacity", 0.55)
                onReleased: function(v) {
                    Core.Ipc.setSetting("cheatsheet.backgroundOpacity",
                                        Math.round(v * 100) / 100);
                }
            }
        }
    }
    // ── Ripristino ───────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Ripristino" : "Reset"
        note: page.it
              ? "Riporta le preferenze di Minerva com'erano appena installate. "
                + "Non tocca schermo, audio, rete né la tastiera."
              : "Restores Minerva's own preferences to how they were on install. "
                + "Does not touch display, audio, network or keyboard."

        Rectangle {
            id: resetButton
            width: resetText.implicitWidth + Theme.Effects.space5
            height: 34
            radius: Theme.Effects.radiusXS

            // Un secondo clic per confermare: il ripristino cancella ogni
            // personalizzazione, e un dialogo in più si chiude senza leggerlo.
            property bool confirming: false

            color: confirming || resetMouse.containsMouse
                   ? Qt.alpha(Theme.Colors.danger, 0.16) : Theme.Colors.raisedHigh
            border.width: 1
            border.color: confirming ? Theme.Colors.danger : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Text {
                id: resetText
                anchors.centerIn: parent
                text: resetButton.confirming ? Core.Strings.t("resetConfirm")
                                             : Core.Strings.t("reset")
                color: resetButton.confirming || resetMouse.containsMouse
                       ? Theme.Colors.danger : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Timer {
                id: confirmTimeout
                interval: 4000
                onTriggered: resetButton.confirming = false
            }

            MouseArea {
                id: resetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (resetButton.confirming) {
                        Core.Ipc.resetSettings();
                        resetButton.confirming = false;
                        confirmTimeout.stop();
                    } else {
                        resetButton.confirming = true;
                        confirmTimeout.restart();
                    }
                }
            }
        }
    }
}
