import QtQuick

// Simboli originali per la barra: Ricerca è una lente, Attività sono
// due pannelli affiancati. Il vecchio «restore» indicava massimizzazione.
Item {
    id: root

    property string kind: "search"

    implicitWidth: 24
    implicitHeight: 24

    Item {
        width: 24
        height: 24
        scale: root.width / 24
        transformOrigin: Item.TopLeft

        Rectangle {
            visible: root.kind === "search"
            x: 3
            y: 2
            width: 14
            height: 14
            radius: 7
            color: "transparent"
            border.width: 1.8
            border.color: Style.barraTesto
        }

        Rectangle {
            visible: root.kind === "search"
            x: 15
            y: 14
            width: 8
            height: 2
            radius: 1
            rotation: 45
            transformOrigin: Item.Left
            color: Style.barraTesto
        }

        Rectangle {
            visible: root.kind === "overview"
            x: 2
            y: 3
            width: 8
            height: 18
            radius: 1
            color: Style.dark ? "#c9d8e9" : "#eff5fb"
            border.color: Style.dark ? "#eaf3fc" : "#596c7f"
        }

        Rectangle {
            visible: root.kind === "overview"
            x: 12
            y: 3
            width: 10
            height: 18
            radius: 1
            border.color: "#0871b8"

            Rectangle {
                x: 1
                y: 5
                width: parent.width - 2
                height: 1
                color: "#8cd5ff"
            }

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "#53b4f8"
                }

                GradientStop {
                    position: 1
                    color: "#0878cc"
                }

            }

        }

    }

}
