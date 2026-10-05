import QtQuick
import Quickshell.Io
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// ClipboardPanel — La cronologia degli appunti.
//
// Ogni voce mostra il testo su due righe al massimo. Non di più: la cronologia
// serve a RICONOSCERE qualcosa che si è copiato poco fa, non a rileggerlo.
// Due righe bastano a riconoscere, e tenendole tutte della stessa altezza
// l'elenco resta scorribile a colpo d'occhio.
//
// Un clic incolla e chiude — è l'unica cosa che si vuole fare da qui.
Item {
    id: panel

    property var spine: null
    property var entries: []
    property bool available: true

    /// La lingua si ferma sul contenuto reale: con tre voci copiate non deve
    /// scendere per mezzo schermo.
    readonly property real implicitPanelHeight:
        panel.entries.length === 0
        ? 200
        : Theme.Effects.space5 + 26 + Theme.Effects.space3
          + list.contentHeight + Theme.Effects.space4

    Component.onCompleted: load()

    function load() {
        listProc.running = true;
    }

    Process {
        id: listProc
        command: ["sh", "-c",
                  "command -v cliphist >/dev/null || { echo '__MISSING__'; exit 0; }; " +
                  "cliphist list 2>/dev/null | head -60"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("__MISSING__") === 0) {
                    panel.available = false;
                    panel.entries = [];
                    return;
                }
                panel.available = true;

                var out = [];
                var lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    if (line.trim() === "")
                        continue;
                    // cliphist antepone un id numerico separato da tabulazione
                    var tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    out.push({
                        "id": line.substring(0, tab),
                        "text": line.substring(tab + 1)
                    });
                }
                panel.entries = out;
            }
        }
    }

    Process { id: pasteProc }

    function paste(id) {
        // L'identificativo arriva dall'uscita di `cliphist`, cioè da fuori:
        // passa come argomento (`$1`), non incollato nella riga.
        pasteProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy",
                             "sh", String(id)];
        pasteProc.running = true;
        if (panel.spine)
            panel.spine.close();
    }

    Process { id: wipeProc }

    function wipe() {
        wipeProc.command = ["sh", "-c", "cliphist wipe"];
        wipeProc.running = true;
        panel.entries = [];
    }

    // ── Intestazione ─────────────────────────────────────────────────────

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space5
        height: 26

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: (Core.Strings.lang === "it" ? "Appunti" : "Clipboard").toUpperCase()
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightBold
            font.letterSpacing: Theme.Typography.trackingLabel
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: wipeText.implicitWidth + Theme.Effects.space3
            height: 24
            radius: Theme.Effects.radiusXS
            visible: panel.entries.length > 0
            color: wipeMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.16) : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Text {
                id: wipeText
                anchors.centerIn: parent
                text: Core.Strings.lang === "it" ? "Svuota" : "Clear"
                color: wipeMouse.containsMouse ? Theme.Colors.danger : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: wipeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.wipe()
            }
        }
    }

    // ── Elenco ───────────────────────────────────────────────────────────

    Ui.Scorrimento {
        bersaglio: list
        anchors {
            right: list.right
            top: list.top
            bottom: list.bottom
        }
    }

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.topMargin: Theme.Effects.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        anchors.bottomMargin: Theme.Effects.space4
        clip: true
        spacing: Theme.Effects.space1
        model: panel.entries
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: entry
            required property var modelData
            required property int index

            width: ListView.view.width
            height: 52
            radius: Theme.Effects.radiusSM
            color: entryMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            // Numeretto d'ordine: dà un riferimento stabile mentre si scorre
            Text {
                id: ordinal
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                text: entry.index + 1
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: ordinal.right
                anchors.leftMargin: Theme.Effects.space2
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                text: entry.modelData.text
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
            }

            MouseArea {
                id: entryMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.paste(entry.modelData.id)
            }
        }

        // Stato vuoto: dice cosa fare, non solo che non c'è niente.
        Column {
            anchors.centerIn: parent
            width: parent.width - Theme.Effects.space6
            spacing: Theme.Effects.space2
            visible: panel.entries.length === 0

            Ui.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 32
                name: "clipboard"
                color: Theme.Colors.textFaint
                alwaysDrawn: true
                opacity: 0.5
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: !panel.available
                      ? (Core.Strings.lang === "it"
                         ? "cliphist non è installato: la cronologia non viene registrata"
                         : "cliphist is not installed, so history is not recorded")
                      : (Core.Strings.lang === "it"
                         ? "Niente negli appunti. Copia qualcosa e ricomparirà qui."
                         : "Clipboard is empty. Copy something and it will show up here.")
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }
}
