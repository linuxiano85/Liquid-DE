import QtQuick
import "../../core" as Core
import "../../windows11" as W

// AnteprimaDesktop — Il piccolo monitor in cima a Sfondo, Colori e Temi in
// Impostazioni di Windows 11: una cornice nera con dentro lo sfondo vero, una
// finestrella nei colori del tema col pulsante d'accento e, in fondo, la
// striscia della barra delle applicazioni.
//
// Mostra quello che c'è davvero (`Core.Wallpaper.current`, il tema e
// l'accento di Windows), così cambiando una scelta l'anteprima cambia con
// lei, come in Windows.
Rectangle {
    id: anteprima

    /// Uno sfondo da mostrare al posto di quello in uso (un'anteprima di una
    /// scelta non ancora fatta). Vuoto: quello in uso.
    property string sfondo: ""
    /// Tinta unita al posto dell'immagine.
    property color tinta: "transparent"

    width: 300
    height: 192
    radius: 10
    color: "#000000"

    Rectangle {
        id: schermo
        anchors.fill: parent
        anchors.margins: 9
        radius: 4
        clip: true
        color: anteprima.tinta.a > 0 ? anteprima.tinta : "#202020"

        Image {
            objectName: "anteprimaSfondoFoto"
            anchors.fill: parent
            visible: anteprima.tinta.a === 0
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(560, 350)
            source: {
                var p = anteprima.sfondo !== "" ? anteprima.sfondo : Core.Wallpaper.current;
                return Core.Wallpaper.urlFile(p);
            }
        }

        // La finestrella: sfondo del tema, righe di testo, pulsante d'accento.
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -6
            width: 102
            height: 100
            radius: 4
            color: W.Style.dark ? "#2b2b2b" : "#f9f9f9"

            Column {
                x: 12
                y: 14
                spacing: 7
                Repeater {
                    model: [62, 70, 62, 38]
                    Rectangle {
                        required property var modelData
                        width: modelData
                        height: 2
                        color: W.Style.dark ? "#9d9d9d" : "#5c5c5c"
                    }
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                width: 26
                height: 8
                radius: 2
                color: W.Style.accent
            }
        }

        // La barra delle applicazioni.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 12
            color: W.Style.dark ? Qt.rgba(0.13, 0.13, 0.13, 0.85) : Qt.rgba(0.93, 0.93, 0.93, 0.85)
        }
    }
}
