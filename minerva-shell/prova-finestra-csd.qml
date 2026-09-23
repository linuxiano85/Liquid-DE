//@ pragma AppId firefox
import QtQuick
import Quickshell

// ProvaFinestraCsd — Una finestra che si finge Firefox: la barra del titolo
// se la disegna da sé, e Minerva deve quindi ingrandirla DICENDOGLIELO
// (fullscreenstate 0 1) invece di spostarla e basta. Serve a provare quel
// percorso, che è esattamente quello dei browser veri.
FloatingWindow {
    visible: true
    title: "Prova CSD"
    implicitWidth: 620
    implicitHeight: 480
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#241f2e"
        Text {
            anchors.centerIn: parent
            text: "prova csd (firefox)"
            color: "#eef4ff"
        }
    }
}
