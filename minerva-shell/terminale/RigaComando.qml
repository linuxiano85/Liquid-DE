import QtQuick
import QtQuick.Controls
import Quickshell
import "../theme" as Theme

// Esplicito: non deduce il prompt da output OSC falsificabile.
Rectangle {
    id: riga
    property bool aperta: false
    property var proposte: []
    property string fantasma: ""
    property string avviso: ""
    property string anteprima: ""
    property bool conferma: false
    signal predici(string testo)
    signal prepara(string testo)
    signal confermaIncolla()
    signal annullaIncolla()
    signal restituisciFuoco()
    height: aperta ? contenuto.implicitHeight + 20 : 30
    color: Theme.Colors.window
    border.color: aperta ? Theme.Colors.accent : Theme.Colors.textFaint
    radius: Theme.Effects.radiusSM
    clip: true
    function apri() { aperta = true; campo.forceActiveFocus(); }
    function chiudi() {
        annullaIncolla(); conferma = false; avviso = ""; anteprima = "";
        aperta = false; restituisciFuoco();
    }
    function risposta(m) {
        if (m.testo !== campo.text) return;
        var visti = [];
        proposte = (m.proposte || []).filter(function(p) {
            if (!p.inserimento || visti.indexOf(p.inserimento) !== -1) return false;
            visti.push(p.inserimento); return true;
        });
        fantasma = m.fantasma || "";
    }
    function chiedi(m) {
        aperta = true; avviso = m.motivo; anteprima = m.testo || "";
        conferma = m.t === "confermaIncolla";
        chiusura.forceActiveFocus();
    }
    function accetta(testo) {
        campo.text = testo; campo.cursorPosition = testo.length;
        campo.forceActiveFocus();
    }
    Text {
        anchors.centerIn: parent; visible: !riga.aperta
        text: "Componi un comando · Ctrl+Shift+Spazio"
        font.pixelSize: 12; color: Theme.Colors.textMuted
    }
    MouseArea { anchors.fill: parent; enabled: !riga.aperta; onClicked: riga.apri() }
    Column {
        id: contenuto
        visible: riga.aperta
        x: 10; y: 10; width: parent.width - 20; spacing: 6
        Text {
            width: parent.width
            text: "→ una parola · Invio inserisce, non esegue · Usa solo al prompt vuoto"
            color: Theme.Colors.textMuted; font.pixelSize: 12; elide: Text.ElideRight
        }
        TextField {
            id: campo
            width: parent.width; enabled: !riga.conferma
            font.family: Theme.Typography.fontMono; color: Theme.Colors.text
            placeholderText: "Componi qui il comando…"
            maximumLength: 4096
            onTextChanged: { riga.fantasma = ""; riga.proposte = []; attesa.restart(); }
            Keys.onPressed: function(e) {
                if (e.key === Qt.Key_Escape) { riga.chiudi(); e.accepted = true; }
                else if ((e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier))
                         || (e.key === Qt.Key_Insert && (e.modifiers & Qt.ShiftModifier))) {
                    var t = Quickshell.clipboardText || "";
                    if (/[\x00-\x1f\x7f-\x9f]/.test(t))
                        riga.avviso = "Incolla rifiutato: nel compositore usa una sola riga senza controlli.";
                    else campo.insert(campo.cursorPosition, t);
                    e.accepted = true;
                } else if ((e.key === Qt.Key_Right || e.key === Qt.Key_Tab)
                         && cursorPosition === text.length && selectedText === ""
                         && riga.proposte.length > 0) {
                    riga.accetta(riga.proposte[0].inserimento); e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (text.trim() !== "") riga.prepara(text);
                    e.accepted = true;
                }
            }
        }
        Text {
            width: parent.width; visible: riga.fantasma !== ""
            text: riga.fantasma; textFormat: Text.PlainText
            font.family: Theme.Typography.fontMono; color: Theme.Colors.textMuted
            elide: Text.ElideRight
        }
        Repeater {
            model: riga.proposte.slice(0, 3)
            delegate: Item {
                required property var modelData
                width: contenuto.width; height: 24
                Text {
                    anchors.fill: parent
                    text: modelData.inserimento + " — " + modelData.spiegazione
                    textFormat: Text.PlainText; color: Theme.Colors.text; elide: Text.ElideRight
                }
                MouseArea { anchors.fill: parent; onClicked: riga.accetta(modelData.inserimento) }
            }
        }
        Text {
            width: parent.width; visible: riga.avviso !== ""
            text: riga.avviso
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            color: Theme.Colors.danger
        }
        ScrollView {
            visible: riga.conferma
            width: parent.width; height: visible ? 90 : 0
            TextArea {
                text: riga.anteprima; readOnly: true; textFormat: TextEdit.PlainText
                font.family: Theme.Typography.fontMono; color: Theme.Colors.text
                wrapMode: TextEdit.WrapAnywhere
            }
        }
        Row {
            spacing: 8
            Button {
                text: riga.conferma ? "Incolla comunque" : "Inserisci nella shell"
                onClicked: {
                    if (riga.conferma) riga.confermaIncolla();
                    else if (campo.text.trim() !== "") riga.prepara(campo.text);
                }
            }
            Button { id: chiusura; text: "Chiudi"; onClicked: riga.chiudi() }
        }
    }
    Timer { id: attesa; interval: 120; onTriggered: riga.predici(campo.text) }
}
