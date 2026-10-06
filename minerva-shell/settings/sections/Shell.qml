import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Minerva — l'aiuto e il ripristino. Il resto che stava qui (le finestre, il
// menù delle applicazioni, la scrivania) dal 28 settembre 2026 sta nella
// pagina della cosa di cui parla.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Minerva" : "Minerva"
    subtitle: Core.Strings.lang === "it"
              ? "Aiuto, ripristino e informazioni"
              : "Help, reset and about"

    readonly property bool it: Core.Strings.lang === "it"
    property string infoSistema: ""
    property string versione: "…"
    property bool infoCaricata: false

    // Legge solo informazioni pubbliche del sistema: non interroga l'utente,
    // il nome della macchina, né i percorsi personali.
    Process {
        id: leggiSistema
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || printf 'unknown\\n'; . /etc/os-release 2>/dev/null; printf '%s\\n' \"${PRETTY_NAME:-Linux}\"; uname -r; awk -F: '/model name/ {gsub(/^[ \\t]+/, \"\", $2); print $2; exit}' /proc/cpuinfo; lspci 2>/dev/null | awk -F: '/VGA compatible controller|3D controller|Display controller/ {gsub(/^[ \\t]+/, \"\", $3); print $3; exit}'", "minerva-about", Quickshell.shellDir + "/VERSION"]
        stdout: StdioCollector {
            onStreamFinished: {
                var righe = text.trim().split("\n");
                page.versione = righe.shift() || "unknown";
                page.infoSistema = righe.filter(function(r) { return r.length > 0; }).join(" · ");
                page.infoCaricata = true;
            }
        }
        onExited: function(code) {
            if (code !== 0 && !page.infoCaricata) {
                page.infoSistema = page.it ? "Informazioni di sistema non disponibili" : "System information unavailable";
                page.infoCaricata = true;
            }
        }
    }

    Component.onCompleted: leggiSistema.running = true
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


        // ── Le spiegazioni sotto ogni interruttore ───────────────────
        //
        // `general.beginnerMode` la legge `menu/DesktopLayer.qml` (il
        // suggerimento sulla scrivania). Le spiegazioni delle piastrelle della
        // tendina se ne sono andate con lei (5 ottobre 2026). Era accesa di fabbrica e non si poteva spegnere da
        // nessuna parte: chi Minerva la conosce si teneva le spiegazioni per
        // sempre.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Suggerimenti per chi comincia"
                           : "Hints for beginners"
            description: page.it
                ? "La riga in fondo alla scrivania vuota: «Super+K per le "
                  + "scorciatoie · Clic destro qui per il menu». Chi Minerva "
                  + "la conosce può spegnerla."
                : "The hint on the desktop. Turn it off once you know Minerva."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("general.beginnerMode", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("general.beginnerMode", v);
                }
            }
        }
    }

    Card {
        heading: page.it ? "Informazioni" : "About"
        note: page.it
              ? "Liquid DE è un ambiente desktop libero, costruito attorno a Minerva."
              : "Liquid DE is a free desktop environment built around Minerva."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Sistema" : "System"
            description: page.infoCaricata ? page.infoSistema
                         : (page.it ? "Rilevamento…" : "Detecting…")
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Liquid DE" : "Liquid DE"
            description: page.it ? "Versione " + page.versione : "Version " + page.versione
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Componenti" : "Components"
            description: "Minerva shell · minervad · minerva-wayland"
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Progetto" : "Project"
            description: "GPL-3.0"
            controlWidth: 140
            control: Text {
                width: 140
                text: page.it ? "Apri su GitHub ↗" : "Open on GitHub ↗"
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                horizontalAlignment: Text.AlignRight
                Accessible.role: Accessible.Button
                Accessible.name: text
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally("https://github.com/linuxiano85/Liquid-DE")
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Isola a schermo intero" : "Island in fullscreen"
            description: page.it
                         ? "Quando un'app occupa tutto lo schermo, premi Super per mostrare la barra e aprire l'Isola."
                         : "When an app fills the screen, press Super to reveal the bar and open the Island."
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
