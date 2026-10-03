import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme

// Created on demand by the shared IPC singleton; no app-specific launch bypass.
PanelWindow {
    id: prompt
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "liquid-launcher-consent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    visible: false
    property bool italiano: true
    property var proposta: ({})
    property string errore: ""
    readonly property bool autorizzabile: errore === "" && !!proposta.token
    signal accepted(string token, string path, string request)
    signal dismissed(string token, string path, string request)

    function visibile(value) {
        // Make control/bidi characters visible instead of letting them disguise
        // a path or command. This changes presentation, never the approved bytes.
        return String(value || "").replace(/[\u0000-\u001f\u007f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g,
            function(c) { return "\\u" + (0x10000 + c.charCodeAt(0)).toString(16).slice(1); });
    }

    function apri(data) {
        prompt.proposta = data || ({});
        prompt.errore = String(prompt.proposta.error || "");
        prompt.visible = true;
        scadenza.stop();
        if (prompt.proposta.expires && prompt.errore === "") {
            scadenza.interval = Math.max(1, Number(prompt.proposta.expires) - Date.now());
            scadenza.start();
        }
        Qt.callLater(function() { annulla.forceActiveFocus(); });
    }

    function chiudi() {
        var p = prompt.proposta;
        prompt.proposta = ({});
        prompt.visible = false;
        scadenza.stop();
        prompt.dismissed(String(p.token || ""), String(p.path || ""), String(p.request || ""));
    }

    function consenti() {
        if (!prompt.autorizzabile) return;
        if (Number(prompt.proposta.expires || 0) <= Date.now()) {
            prompt.errore = prompt.italiano ? "Conferma scaduta: riapri il launcher."
                                            : "Confirmation expired: open the launcher again.";
            return;
        }
        var p = prompt.proposta;
        prompt.proposta = ({});
        prompt.visible = false;
        scadenza.stop();
        prompt.accepted(String(p.token), String(p.path), String(p.request));
    }

    Timer {
        id: scadenza
        onTriggered: prompt.errore = prompt.italiano ? "Conferma scaduta: riapri il launcher."
                                                     : "Confirmation expired: open the launcher again."
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.scrim
        MouseArea { anchors.fill: parent; onClicked: prompt.chiudi() }

        Rectangle {
            id: riquadro
            anchors.centerIn: parent
            width: Math.min(640, parent.width - 32)
            height: Math.min(540, parent.height - 32)
            radius: 16
            color: Theme.Colors.panel
            border.color: Theme.Colors.edge
            Keys.onEscapePressed: prompt.chiudi()
            // A click inside the panel must not propagate to the cancel backdrop.
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors { fill: parent; margins: 20 }
                spacing: 12
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: prompt.errore !== "" ? (prompt.italiano ? "Avvio non consentito" : "Launch blocked")
                         : (prompt.italiano ? "Consenti l'avvio di questo launcher?" : "Allow this launcher to run?")
                    color: Theme.Colors.text
                    font.pixelSize: 20
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: prompt.errore !== "" ? (prompt.italiano ? "Operazione interrotta. Dettagli qui sotto."
                                                                 : "Operation stopped. Details below.") : (prompt.proposta.token
                        ? (prompt.italiano ? "Il launcher eseguirà il comando mostrato qui sotto, con i tuoi permessi."
                                           : "The launcher will run the command below with your permissions.")
                        : (prompt.italiano ? "Lettura del launcher…" : "Reading launcher…"))
                    color: Theme.Colors.text
                    wrapMode: Text.Wrap
                }
                ScrollView {
                    id: dettagli
                    width: parent.width
                    height: Math.max(60, riquadro.height - 232)
                    contentWidth: availableWidth
                    clip: true
                    TextArea {
                        width: dettagli.availableWidth
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.WrapAnywhere
                        text: (prompt.errore !== "" ? prompt.visibile(prompt.errore) + "\n\n" : "")
                              + prompt.visibile(prompt.proposta.path)
                              + (prompt.proposta.resolvedPath && prompt.proposta.resolvedPath !== prompt.proposta.path
                                 ? "\n→ " + prompt.visibile(prompt.proposta.resolvedPath) : "")
                              + "\n\n" + prompt.visibile(prompt.proposta.command)
                        color: Theme.Colors.text
                        font.family: "monospace"
                        background: Rectangle { color: Theme.Colors.panel }
                    }
                }
                Row {
                    spacing: 12
                    Button {
                        id: annulla
                        text: prompt.italiano ? "Annulla" : "Cancel"
                        onClicked: prompt.chiudi()
                        Keys.onEscapePressed: prompt.chiudi()
                    }
                    Button {
                        text: prompt.italiano ? "Consenti l'avvio" : "Allow launch"
                        enabled: prompt.autorizzabile
                        onClicked: prompt.consenti()
                        Keys.onEscapePressed: prompt.chiudi()
                    }
                }
            }
        }
    }
}
