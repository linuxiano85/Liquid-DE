import QtQuick
import "../theme" as Theme
import "." as Ui

// RigaScelta — Una riga che si preme, con un'icona e una scritta.
//
// Nasce per `ApriCon.qml`, dove le stesse tre cose si presentano due volte in
// due misure: le azioni in cima («Esegui nel terminale», «Apri con Kate») e
// l'elenco dei programmi più sotto. Due copie della stessa riga finiscono
// sempre per divergere, e il giorno che divergono si vede che una è alta due
// pixel più dell'altra.
//
// L'icona può venire da due posti e sono due cose diverse: `iconaFile` è
// l'icona di un PROGRAMMA, un file PNG o SVG del tema installato; `icona` è un
// tracciato disegnato da noi. Quando c'è la prima vince lei, e la seconda
// resta come ripiego per il programma che un'icona non ce l'ha.
Rectangle {
    id: riga

    signal scelto()

    property string icona: ""
    property string iconaFile: ""
    property string testo: ""
    property string nota: ""
    /// Le righe dell'elenco sono più basse di quelle delle azioni: le prime
    /// si scorrono, le seconde si guardano.
    property bool piccola: false

    height: riga.piccola ? 34 : (riga.nota !== "" ? 50 : 42)
    radius: Theme.Effects.radiusSM
    color: mouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.16)
                               : (riga.piccola ? "transparent" : Theme.Colors.raised)
    border.width: riga.piccola ? 0 : Theme.Effects.hairline
    border.color: Theme.Colors.edge
    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

    Image {
        id: immagine
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        width: riga.piccola ? 18 : 20
        height: width
        source: riga.iconaFile !== "" ? "file://" + riga.iconaFile : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: status === Image.Ready
    }

    Ui.Icon {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        width: riga.piccola ? 16 : 18
        height: width
        visible: !immagine.visible && riga.icona !== ""
        name: riga.icona
        color: Theme.Colors.accent
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3 + 20 + Theme.Effects.space3
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: riga.testo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: riga.piccola ? Theme.Typography.weightRegular
                                      : Theme.Typography.weightMedium
        }

        Text {
            width: parent.width
            visible: riga.nota !== ""
            elide: Text.ElideRight
            text: riga.nota
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: riga.scelto()
    }
}
