import QtQuick
import "../../windows11" as W

// La Home della VM usa riquadri da 496 px, intestazione da 106 e righe
// interne senza angoli. La larghezza può scendere fino a una sola colonna.
Rectangle {
    id: scheda
    property string titolo: ""
    property string descrizione: ""
    default property alias contenuto: corpo.data
    implicitHeight: corpo.y + corpo.implicitHeight
    height: implicitHeight
    radius: 8
    color: W.Style.card
    border.width: 1
    border.color: W.Style.cardStroke
    Column {
        x: 24
        y: 24
        width: parent.width - 48
        spacing: 12
        Text {
            width: parent.width
            text: scheda.titolo
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: scheda.descrizione
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 14
        }
    }
    Column {
        id: corpo
        y: scheda.descrizione === "" ? 74 : 106
        width: parent.width
        spacing: 0
    }
}
