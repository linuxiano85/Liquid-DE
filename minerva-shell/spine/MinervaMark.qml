import QtQuick
import QtQuick.Shapes
import "../theme" as Theme

// MinervaMark — Il simbolo di Minerva.
//
// Un esagono con dentro una feretta: l'occhio della civetta, animale di
// Minerva, ridotto alla sua geometria minima. Serve che funzioni a 20 pixel,
// quindi niente dettagli: due forme, un vuoto in mezzo.
//
// Quando è acceso l'interno si riempie di ciano e l'esagono si illumina.
// È l'unico elemento della barra che ha un'identità propria, ed è giusto che
// sia quello da cui parte tutto.
Item {
    id: mark

    /// Acceso quando il menu è aperto o il puntatore è sopra
    property bool lit: false

    implicitWidth: 20
    implicitHeight: 20

    // Alone che pulsa lentamente quando è acceso: segnala che l'elemento è
    // vivo senza chiedere attenzione.
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 1.9
        height: width
        radius: width / 2
        color: Theme.Colors.accent
        opacity: mark.lit ? 0.18 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
    }

    Shape {
        anchors.fill: parent
        // GeometryRenderer e non CurveRenderer: vedi `ui/Icon.qml`.
        preferredRendererType: Shape.GeometryRenderer
        asynchronous: false

        // Esagono esterno, vertice in alto
        ShapePath {
            strokeColor: mark.lit ? Theme.Colors.accent : Theme.Colors.text
            strokeWidth: 1.6
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            scale: Qt.size(mark.width / 24, mark.height / 24)

            PathSvg { path: "M12 2.4l8.3 4.8v9.6L12 21.6l-8.3-4.8V7.2z" }

            Behavior on strokeColor { ColorAnimation { duration: Theme.Motion.quick } }
        }

        // Feritoia interna: due lati che convergono verso il basso, come una
        // pupilla stilizzata.
        ShapePath {
            strokeColor: "transparent"
            fillColor: mark.lit ? Theme.Colors.accent : Theme.Colors.textMuted
            scale: Qt.size(mark.width / 24, mark.height / 24)

            PathSvg { path: "M12 8.2l3.6 2.1v3.4L12 15.8l-3.6-2.1v-3.4z" }

            Behavior on fillColor { ColorAnimation { duration: Theme.Motion.quick } }
        }
    }
}
