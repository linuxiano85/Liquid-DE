// Un pannello che chiede la tastiera e dice se gliela danno.
//
// Serve a `prova-fuoco-pannello.py`. È il pezzo più piccolo che riproduce la
// finestra della password: una superficie appoggiata che chiede
// `keyboardFocus: Exclusive`, cioè «datemi la tastiera appena compaio».
//
// Non fa altro: scrive su stdout ogni tasto che riceve. Se non ne riceve
// nessuno senza averci cliccato sopra, il compositore non gliela sta dando.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 400
        implicitHeight: 120
        color: "#202030"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Text {
            anchors.centerIn: parent
            color: "white"
            text: "pannello di prova"
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: function (e) {
                console.log("TASTO", e.key, e.text);
            }
        }
    }
}
