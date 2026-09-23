import QtQuick
import "../theme" as Theme

// StatTile — Una grandezza della macchina: nome, numero grande, grafico.
//
// Le piastrelle sono tutte della stessa forma di proposito, anche quando il
// dato sotto è di natura diversa (una percentuale, dei byte al secondo, dei
// gradi). Chi guarda un cruscotto non legge: SCORRE. Se ogni riquadro ha un
// impaginato suo, scorrere non funziona e bisogna leggerli uno per uno.
Rectangle {
    id: tile

    /// Il nome della grandezza, in alto e piccolo.
    property string titolo: ""

    /// Il numero grande. Già formattato: la formattazione la sa chi ha il dato.
    property string valore: "—"

    /// L'unità, accanto al numero e più piccola.
    property string unita: ""

    /// Una riga di contesto sotto il numero (il totale, il dettaglio).
    property string sotto: ""

    property var punti: []
    property real massimo: 100
    property color colore: Theme.Colors.accent

    /// Quando la grandezza è in allarme la piastrella lo dice col colore, non
    /// con un'icona in più: il colore si vede senza guardare.
    property bool allarme: false

    readonly property color tinta: tile.allarme ? Theme.Colors.danger : tile.colore

    implicitHeight: 104
    radius: Theme.Effects.radiusMD
    color: Theme.Colors.raised
    border.width: Theme.Effects.hairline
    border.color: tile.allarme ? Qt.alpha(Theme.Colors.danger, 0.45)
                               : Theme.Colors.edge
    Behavior on border.color { ColorAnimation { duration: Theme.Motion.quick } }

    Text {
        id: etichetta
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space3
        text: tile.titolo
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeXS
        font.weight: Theme.Typography.weightMedium
        font.letterSpacing: Theme.Typography.trackingLabel
    }

    Row {
        id: numero
        anchors.left: parent.left
        anchors.top: etichetta.bottom
        anchors.leftMargin: Theme.Effects.space4
        anchors.topMargin: 2
        spacing: 3

        Text {
            text: tile.valore
            color: Theme.Colors.text
            // Monospaziato, e non è pignoleria: un numero che cambia due volte
            // al secondo con un font proporzionale BALLA, perché il 1 è più
            // stretto dello 0. Con le cifre di larghezza fissa il valore
            // cambia e la riga sta ferma.
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXL
        }

        Text {
            text: tile.unita
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
        }
    }

    Text {
        anchors.left: parent.left
        anchors.top: numero.bottom
        anchors.leftMargin: Theme.Effects.space4
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space4
        anchors.topMargin: 1
        text: tile.sotto
        elide: Text.ElideRight
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeXS
    }

    // Il grafico sta in fondo e occupa tutta la larghezza: è uno sfondo che
    // racconta, non un elemento da guardare per primo.
    Sparkline {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 34
        punti: tile.punti
        massimo: tile.massimo
        colore: tile.tinta
    }
}
