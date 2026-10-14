import QtQuick

// Illustrazione vettoriale originale e statica: nessuna animazione o
// immagine di rete per mostrare lo stato del meteo sulla barra.
Item {
    id: root

    property int code: 0
    property bool day: true
    readonly property bool cloud: code >= 2
    readonly property bool rain: (code >= 51 && code <= 67) || (code >= 80 && code <= 82)
    readonly property bool snow: (code >= 71 && code <= 77) || code === 85 || code === 86
    readonly property bool storm: code >= 95

    implicitWidth: 48
    implicitHeight: 48

    Item {
        width: 48
        height: 48
        scale: root.width / 48
        transformOrigin: Item.TopLeft

        Rectangle {
            x: root.cloud ? 2 : 5
            y: root.cloud ? 1 : 5
            width: root.cloud ? 29 : 38
            height: width
            radius: width / 2
            visible: root.code <= 2

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: root.day ? "#fff69a" : "#edf5ff"
                }

                GradientStop {
                    position: 0.45
                    color: root.day ? "#ffd445" : "#c4d8f8"
                }

                GradientStop {
                    position: 1
                    color: root.day ? "#f6a313" : "#8cafe5"
                }

            }

        }

        Item {
            visible: root.cloud
            y: root.rain || root.snow || root.storm ? 0 : 4

            Rectangle {
                x: 2
                y: 18
                width: 26
                height: 24
                radius: 12
                color: "#cadbe9"
            }

            Rectangle {
                x: 14
                y: 10
                width: 27
                height: 30
                radius: 14
                color: "#e6f0f7"
            }

            Rectangle {
                x: 29
                y: 22
                width: 17
                height: 20
                radius: 9
                color: "#dce9f2"
            }

            Rectangle {
                x: 9
                y: 27
                width: 32
                height: 15
                radius: 7

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#e6f0f7"
                    }

                    GradientStop {
                        position: 1
                        color: "#bdd0e3"
                    }

                }

            }

        }

        Row {
            x: 13
            y: 37
            spacing: 7
            visible: root.rain || root.snow

            Repeater {
                model: 3

                Rectangle {
                    width: root.snow ? 4 : 3
                    height: root.snow ? 4 : 9
                    radius: 2
                    rotation: root.snow ? 0 : 20
                    color: root.snow ? "#8cd7ff" : "#208cdd"
                }

            }

        }

        Glyph {
            x: 18
            y: 28
            width: 22
            height: 22
            visible: root.storm
            name: "bolt"
            color: "#f6b91f"
        }

    }

}
