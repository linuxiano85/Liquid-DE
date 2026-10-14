import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Informazioni — il sistema, la versione, il progetto e il ripristino.
//
// Si chiamava «Minerva». Le finestre, il menù delle applicazioni e la
// scrivania se ne sono andati il 28 settembre 2026; l'11 ottobre anche le
// voci grafiche (promemoria delle scorciatoie, suggerimenti, Isola a schermo
// intero), che il manutentore voleva in Personalizzazione: ora stanno in Aspetto e
// nella scheda dell'Isola. Qui resta solo quello che non si vede.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Informazioni" : "About"
    subtitle: Core.Strings.lang === "it"
              ? "Sistema, versione e ripristino"
              : "System, version and reset"

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
