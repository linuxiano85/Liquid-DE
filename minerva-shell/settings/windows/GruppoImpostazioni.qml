import QtQuick
import "../../windows11" as W

// GruppoImpostazioni — Il titolo sopra un gruppo di schede in Impostazioni di
// Windows 11 («Impostazioni correlate», «Temi a contrasto»…): 14 px
// seminero, con più aria sopra che sotto.
Item {
    id: gruppo
    property string testo: ""
    width: parent ? parent.width : 400
    implicitHeight: etichetta.implicitHeight + 28
    height: implicitHeight
    Accessible.role: Accessible.Heading
    Accessible.name: gruppo.testo

    Text {
        id: etichetta
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        text: gruppo.testo
        textFormat: Text.PlainText
        color: W.Style.text
        font.family: W.Style.font
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }
}
