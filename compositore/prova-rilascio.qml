// Una finestra che si sposta da sé, come le app di Minerva e Chrome: la
// pressione arriva a lei, e se il puntatore si muove chiede al compositore di
// trascinarla (`startSystemMove`). Serve a `prova-rilascio.py`.
import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        id: finestra
        implicitWidth: 500
        implicitHeight: 300
        color: "#202030"
        title: "prova-rilascio"

        MouseArea {
            anchors.fill: parent
            property real px: 0
            property real py: 0
            property bool armata: false
            onPressed: function (m) {
                px = m.x; py = m.y; armata = true;
                console.warn("PREMUTO", Math.round(m.x), Math.round(m.y));
            }
            onPositionChanged: function (m) {
                if (!armata || (Math.abs(m.x - px) < 3 && Math.abs(m.y - py) < 3))
                    return;
                armata = false;
                console.warn("SPOSTAMI");
                finestra.startSystemMove();
            }
            onReleased: function (m) { armata = false; console.warn("LASCIATO"); }
            onClicked: console.warn("CLIC")
        }
    }
}
