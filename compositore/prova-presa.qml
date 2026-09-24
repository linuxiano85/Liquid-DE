// Un pannello che dice dove riceve il puntatore mentre un pulsante è giù.
//
// Serve a `prova-presa.py`: si preme qui dentro, si esce dai bordi tenendo
// premuto, e si lascia fuori. Con la presa implicita il pannello continua a
// ricevere i movimenti e il rilascio anche fuori dai suoi bordi.
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

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPressed: function (m) { console.warn("PREMUTO", Math.round(m.x), Math.round(m.y)); }
            onPositionChanged: function (m) { console.warn("MOSSO", Math.round(m.x), Math.round(m.y)); }
            onReleased: function (m) { console.warn("LASCIATO", Math.round(m.x), Math.round(m.y)); }
            onCanceled: console.warn("ANNULLATO")
        }
    }
}
