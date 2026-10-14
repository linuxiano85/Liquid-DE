import QtQuick
import "../../windows11" as W

// Disegno originale in QML: le miniature restano nitide a ogni scala e non
// incorporano fotografie o risorse Microsoft della macchina di riferimento.
Item {
    id: anteprima
    property int righe: 3
    width: 312
    height: 204

    Item {
        width: 312
        height: 204
        scale: anteprima.width / 312
        transformOrigin: Item.TopLeft
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 8
        color: "#202020"
        Rectangle {
            anchors.fill: parent
            anchors.margins: 9
            radius: 2
            color: "#91CEE7"
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.52
                height: parent.height * 0.88
                radius: 6
                color: "#E1F5FF"
                Grid {
                    id: griglia
                    x: 15
                    y: 15
                    width: parent.width - 30
                    columns: 6
                    spacing: 9
                    Repeater {
                        model: anteprima.righe * 6
                        Rectangle {
                            width: (griglia.width - 45) / 6
                            height: 10
                            radius: 2
                            color: W.Style.accent
                        }
                    }
                }
                Grid {
                    x: 15
                    y: griglia.y + griglia.height + 16
                    columns: 2
                    columnSpacing: 18
                    rowSpacing: 12
                    Repeater {
                        model: anteprima.righe === 4 ? 2 : anteprima.righe === 2 ? 8 : 6
                        Row {
                            spacing: 5
                            Rectangle {
                                width: 8
                                height: 8
                                radius: 1
                                color: "#8FADB9"
                            }
                            Rectangle {
                                width: 20
                                height: 2
                                y: 2
                                color: "#8FADB9"
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
