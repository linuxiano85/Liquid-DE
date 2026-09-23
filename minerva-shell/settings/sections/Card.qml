import QtQuick
import "../../theme" as Theme

// Card — Un gruppo di impostazioni che stanno insieme.
//
// Le impostazioni si leggono a gruppi, non a elenco: «tutto quello che
// riguarda lo schermo esterno» è un pensiero solo, e va dentro un riquadro
// solo. Un elenco piatto di venti righe costringe a leggerle tutte per capire
// quali si riferiscono a cosa.
Rectangle {
    id: card

    property string heading: ""
    property string note: ""

    default property alias content: body.data

    width: parent ? parent.width : 0
    // Si somma l'altezza NATURALE dei due testi, non la loro altezza vera.
    //
    // Erano `headingText.height` e `noteText.height`, e i due testi a loro
    // volta si davano `height: visible ? implicitHeight : 0`. Assegnare
    // `height` a un elemento la cui altezza qualcun altro sta già leggendo
    // chiude il cerchio, e Qt lo segnalava a ogni apertura delle
    // impostazioni. `implicitHeight` è ciò che il testo occupa dato il suo
    // contenuto e la sua larghezza: si legge senza scriverlo, e il cerchio
    // non si chiude.
    implicitHeight: body.implicitHeight
                    + (heading !== "" ? headingText.implicitHeight + Theme.Effects.space3 : 0)
                    + (note !== "" ? noteText.implicitHeight + Theme.Effects.space2 : 0)
                    + Theme.Effects.space4 * 2
    radius: Theme.Effects.radiusMD
    color: Theme.Colors.raised

    Text {
        id: headingText
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        visible: card.heading !== ""
        text: card.heading
        color: Theme.Colors.text
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeMD
        font.weight: Theme.Typography.weightSemiBold
    }

    Column {
        id: body
        anchors.top: card.heading !== "" ? headingText.bottom : parent.top
        anchors.topMargin: card.heading !== "" ? Theme.Effects.space3
                                               : Theme.Effects.space4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        spacing: Theme.Effects.space3
    }

    Text {
        id: noteText
        anchors.top: body.bottom
        anchors.topMargin: Theme.Effects.space2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        visible: card.note !== ""
        wrapMode: Text.WordWrap
        text: card.note
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeXS
    }
}
