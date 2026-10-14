import QtQuick
import "../theme" as Theme

// SchemaPreset — Il disegnino di uno schermo con un preset: dove sta la
// barra, se c'è la dock o l'Isola, da che parte sono i comandi della finestra.
//
// Nato dentro il selettore dei preset (`menu/SelettorePreset.qml`, Super+P);
// sta qui dall'11 ottobre 2026 perché lo usa anche la pagina Preset delle
// Impostazioni, e due copie dello stesso disegno un giorno direbbero cose
// diverse. Misura 152×92: per farlo più grande si usa `scale`.
//
// Uno schermo in miniatura con dentro una finestra e quello che il preset
// mette intorno: la capsula dell'Isola, la barra in alto o in basso, la
// dock. Disegnato, non fotografato: niente immagini da caricare, e segue
// da solo i colori del tema.
Rectangle {
    id: schermo
    property string quale: ""

    readonly property bool barraSopra: quale === "minerva" || quale === "mac"
    readonly property bool barraSotto: quale === "windows"
    readonly property bool conDock: quale === "minerva" || quale === "mac" || quale === "liquid"
    readonly property color segno: Theme.Colors.accent
    readonly property color tenue: Qt.alpha(Theme.Colors.text, 0.28)

    width: 152
    height: 92
    radius: Theme.Effects.radiusSM
    color: Qt.alpha(Theme.Colors.text, 0.06)
    border.width: Theme.Effects.hairline
    border.color: Theme.Colors.edge

    // La finestra in mezzo, con i comandi a destra o (Mac) a sinistra.
    Rectangle {
        x: 26
        y: schermo.barraSopra ? 18 : 14
        width: 100
        height: 52
        radius: 4
        color: Qt.alpha(Theme.Colors.text, 0.10)
        border.width: 1
        border.color: schermo.tenue
        Row {
            spacing: 2
            y: 3
            x: schermo.quale === "mac" ? 4 : parent.width - width - 4
            Repeater {
                model: 3
                delegate: Rectangle { width: 4; height: 4; radius: 2; color: schermo.tenue }
            }
        }
    }

    // Liquid: l'Isola, una capsula in alto al centro.
    Rectangle {
        visible: schermo.quale === "liquid"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: 46
        height: 9
        radius: 4.5
        color: schermo.segno
    }

    // Minerva e Mac: la barra in alto, a tutta larghezza.
    Rectangle {
        visible: schermo.barraSopra
        x: 0
        y: 0
        width: parent.width
        height: 9
        radius: 2
        color: schermo.segno
    }

    // Windows: la barra in basso, con le icone al centro.
    Rectangle {
        visible: schermo.barraSotto
        x: 0
        y: parent.height - height
        width: parent.width
        height: 11
        radius: 2
        color: schermo.segno
        Row {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: 5
                delegate: Rectangle { width: 5; height: 5; radius: 1; color: Theme.Colors.textOnAccent }
            }
        }
    }

    // La dock in fondo, più piccola nel Mac (che la toglie di mezzo).
    Rectangle {
        visible: schermo.conDock
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 4
        width: schermo.quale === "mac" ? 54 : 70
        height: 9
        radius: 4.5
        color: Qt.alpha(schermo.segno, 0.55)
    }

    // Libero: quello che hai messo tu, cioè niente di fisso — i
    // cursori delle preferenze.
    Column {
        visible: schermo.quale === "libero"
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 6
        spacing: 3
        Repeater {
            model: [0.3, 0.7, 0.5]
            delegate: Item {
                required property real modelData
                width: 60
                height: 4
                Rectangle { width: parent.width; height: 2; y: 1; color: schermo.tenue }
                Rectangle {
                    x: modelData * (parent.width - 6)
                    width: 6
                    height: 4
                    radius: 2
                    color: schermo.segno
                }
            }
        }
    }
}
