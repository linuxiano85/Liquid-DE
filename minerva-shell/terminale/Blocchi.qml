import QtQuick
import QtQuick.Controls
import Quickshell
import "../theme" as Theme
import "../ui" as Ui

Rectangle {
    id: pannello
    property var blocchi: []
    property bool aperto: true
    signal riproponi(string comando)
    color: Theme.Colors.window
    border.color: Theme.Colors.textFaint
    radius: Theme.Effects.radiusSM
    function aggiorna(blocco) {
        var lista = blocchi.slice();
        var indice = lista.findIndex(function(b) { return b.id === blocco.id; });
        if (indice >= 0) lista[indice] = blocco;
        else lista.unshift(blocco);
        blocchi = lista.slice(0, 100);
    }
    Button {
        id: intestazione
        width: parent.width; height: 32
        text: "Blocchi · " + pannello.blocchi.length + (pannello.aperto ? "  ▾" : "  ▸")
        onClicked: pannello.aperto = !pannello.aperto
    }
    Text {
        visible: pannello.aperto && pannello.blocchi.length === 0
        anchors.top: intestazione.bottom; anchors.margins: 12
        anchors.left: parent.left; anchors.right: parent.right
        text: "In attesa di un comando.\nBlocchi automatici con integrazione bash/zsh; le altre shell restano classiche."
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: Theme.Colors.textMuted
    }
    ListView {
        id: elencoBlocchi
        anchors.top: intestazione.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 8
        visible: pannello.aperto
        clip: true; spacing: 10; model: pannello.blocchi
        delegate: Rectangle {
            id: scheda
            required property var modelData
            property bool espansa: false
            width: ListView.view.width
            height: contenuto.implicitHeight + 16
            color: "transparent"
            border.color: modelData.stato === "corsa" ? Theme.Colors.accent
                : modelData.codice === 0 ? Theme.Colors.textFaint : Theme.Colors.danger
            radius: Theme.Effects.radiusSM
            Column {
                id: contenuto
                x: 8; y: 8; width: parent.width - 16; spacing: 5
                Text {
                    width: parent.width; text: scheda.modelData.comando || "Comando non disponibile"
                    textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3; elide: Text.ElideRight
                    color: Theme.Colors.text; font.family: Theme.Typography.fontMono
                }
                Text {
                    width: parent.width
                    text: scheda.modelData.cartella
                    textFormat: Text.PlainText; elide: Text.ElideMiddle
                    color: Theme.Colors.textMuted; font.pixelSize: 11
                }
                Text {
                    width: parent.width
                    text: (scheda.modelData.stato === "corsa" ? "In corso"
                        : (scheda.modelData.codice < 0 ? "Esito sconosciuto" : "Esito " + scheda.modelData.codice)
                          + " · " + scheda.modelData.durata + " ms")
                        + (scheda.modelData.comandoParziale ? " · primo comando bash" : "")
                    wrapMode: Text.Wrap; color: Theme.Colors.textMuted; font.pixelSize: 11
                }
                Flow {
                    width: parent.width; spacing: 3
                    Button { text: scheda.espansa ? "Chiudi output" : "Output"; onClicked: scheda.espansa = !scheda.espansa }
                    Button { text: "Copia"; onClicked: Quickshell.clipboardText = scheda.modelData.uscita }
                    Button {
                        text: scheda.modelData.comandoParziale ? "Componi" : "Riproponi"
                        enabled: scheda.modelData.comando !== ""
                        onClicked: pannello.riproponi(scheda.modelData.comando)
                    }
                }
                Text {
                    visible: scheda.espansa
                    width: parent.width
                    text: scheda.modelData.interattivo ? "Programma a schermo alternativo: output non archiviato."
                        : scheda.modelData.troncato ? "Estratto finale (output troncato)." : "Testo a schermo (non un log grezzo)"
                    wrapMode: Text.Wrap; color: Theme.Colors.textMuted
                }
                Loader {
                    active: scheda.espansa && !scheda.modelData.interattivo
                    width: parent.width
                    sourceComponent: ScrollView {
                        height: 160
                        TextArea {
                            text: scheda.modelData.uscita; readOnly: true
                            textFormat: TextEdit.PlainText; wrapMode: TextEdit.WrapAnywhere
                            color: Theme.Colors.text; font.family: Theme.Typography.fontMono
                        }
                    }
                }
            }
        }
    }
    // La nostra barra, fuori dall'elenco: quella di serie di Qt aveva il
    // colore e la forma di un'altra scrivania, e dentro un ListView i figli
    // scorrono insieme al contenuto.
    Ui.Scorrimento {
        // Quando serve lo decide lei (`_serve`); qui si aggiunge solo che col
        // pannello chiuso non c'è niente da scorrere.
        visible: pannello.aperto && _serve
        bersaglio: elencoBlocchi
        anchors {
            right: elencoBlocchi.right
            top: elencoBlocchi.top
            bottom: elencoBlocchi.bottom
        }
    }
}
