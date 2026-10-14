import QtQuick
import "../../windows11" as W
import ".." as S

// ScegliColoreWindows — Il riquadro di «Visualizza colori» (Sfondo › Tinta
// unita, Colori › Colori personalizzati): il quadrato dei colori di Liquid,
// che si prova muovendo, e «Fine» / «Annulla» come i dialoghi di Windows.
// Si mette sopra la pagina (`parent: pagina`).
Item {
    id: riquadro
    anchors.fill: parent
    visible: false
    z: 50
    property color pendente: "#000000"
    signal confermato(color colore)

    function apri(c) {
        selettore.valore = c;
        riquadro.pendente = c;
        riquadro.visible = true;
    }

    MouseArea { anchors.fill: parent; onClicked: riquadro.visible = false }
    Rectangle { anchors.fill: parent; color: "#4D000000" }
    Rectangle {
        anchors.centerIn: parent
        width: 380
        height: corpo.implicitHeight + 32 + 80
        radius: 8
        color: W.Style.dark ? "#2C2C2C" : "#F9F9F9"
        border.width: 1
        border.color: W.Style.gettoni.surfaceStrokeFlyout
        MouseArea { anchors.fill: parent }
        Column {
            id: corpo
            x: 16; y: 16
            width: parent.width - 32
            S.SelettoreColore {
                id: selettore
                width: parent.width
                onScelto: function (c) { riquadro.pendente = c; selettore.valore = c; }
            }
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 80
            radius: 8
            color: W.Style.dark ? "#202020" : "#F3F3F3"
            Row {
                anchors.centerIn: parent
                spacing: 8
                PulsanteWindows {
                    objectName: "coloreFine"
                    width: 166
                    accento: true
                    testo: W.Style.it ? "Fine" : "Done"
                    onPremuto: { riquadro.visible = false; riquadro.confermato(riquadro.pendente); }
                }
                PulsanteWindows {
                    width: 166
                    testo: W.Style.it ? "Annulla" : "Cancel"
                    onPremuto: riquadro.visible = false
                }
            }
        }
    }
}
