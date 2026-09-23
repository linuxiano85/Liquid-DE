import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// Freccia — Il bersaglio grande per sfogliare, ai lati dell'immagine.
//
// Esiste perché sfogliare è l'azione che si ripete di più, e la barra in basso
// la fa fare con un pulsante da trentadue pixel a cui bisogna mirare ogni
// volta. Qui il bersaglio è la fascia laterale intera: il disco disegnato è
// solo il segno di dove si è, l'area cliccabile è molto più larga di lui.
//
// Si accende al passaggio del mouse e resta appena visibile altrimenti: una
// freccia piena sopra una fotografia è un dito puntato su qualcosa che non è
// la fotografia.
Item {
    id: freccia

    property bool sinistra: true
    /// Vero mentre la cornice della finestra è visibile: a schermo intero, con
    /// il mouse fermo, spariscono anche queste.
    property bool cornice: true

    signal premuta()

    width: 76
    height: 132
    opacity: zona.containsMouse ? 1.0 : (freccia.cornice ? 0.4 : 0)
    Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

    Rectangle {
        anchors.centerIn: parent
        width: 46
        height: 46
        radius: width / 2
        color: zona.containsMouse ? Theme.Colors.raisedHigh : Theme.Colors.raised
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        Ui.Icon {
            anchors.centerIn: parent
            width: 22
            height: 22
            name: "chevron"
            alwaysDrawn: true
            color: Theme.Colors.text
            rotation: freccia.sinistra ? 90 : -90
        }
    }

    MouseArea {
        id: zona
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: freccia.premuta()
    }
}
