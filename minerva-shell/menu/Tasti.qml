import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../ui" as Ui

// ── I tasti sulla scrivania ──────────────────────────────────────────────
//
// La prima delle cinque regole della Riva: «Super da solo è la porta: lo
// tocchi e trovi tutto; lo tieni premuto e i tasti compaiono sulla
// scrivania». Compaiono DOVE stanno le cose che aprono — il menù nel suo
// angolo, il Centro nel suo, gli appunti sul bordo destro — perché un tasto
// imparato insieme al suo posto non si dimentica. In mezzo, quelli della
// finestra.
//
// Restano finché Super è giù (il compositore annuncia «tasti» dopo 400 ms e
// «tasti-via» al rilascio). Non prendono né tastiera né puntatore: sono un
// cartello, e sotto si deve poter continuare a lavorare.
PanelWindow {
    id: tasti

    property bool aperti: false
    property real margineAlto: 0
    property real margineBasso: 0

    visible: tasti.aperti || comparsa.running || tasti._opacita > 0.01
    property real _opacita: tasti.aperti ? 1 : 0
    Behavior on _opacita { NumberAnimation { id: comparsa; duration: Theme.Motion.liquido ? 160 : 0 } }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-tasti"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Nessuna zona che prende il puntatore: è un cartello.
    mask: Region {}

    Item {
        id: fondo
        anchors.fill: parent
        opacity: tasti._opacita
        scale: 0.97 + 0.03 * tasti._opacita

        // Un velo leggero: i cartelli devono staccarsi da qualunque sfondo.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.28)
        }

        readonly property real m: Theme.Effects.space4

        // ── Gli angoli e i bordi ──
        Cartello {
            x: fondo.m
            y: tasti.margineAlto + fondo.m
            nome: "Menù"
            chiavi: ["Super"]
            detto: "tocca e scrivi"
        }
        Cartello {
            x: fondo.width - fondo.m - width
            y: tasti.margineAlto + fondo.m
            nome: "Centro di controllo"
            chiavi: ["Super", "A"]
        }
        Cartello {
            x: fondo.width - fondo.m - width
            y: fondo.height - tasti.margineBasso - fondo.m - height
            nome: "Scrivania libera"
            chiavi: ["Super", "D"]
        }
        Cartello {
            x: fondo.width - fondo.m - width
            y: fondo.height / 2 - height / 2
            nome: "Appunti"
            chiavi: ["Super", "V"]
            detto: "o spingi sul bordo"
        }
        Cartello {
            x: fondo.width / 2 - width / 2
            y: tasti.margineAlto + fondo.m
            nome: "Oggi, il tempo, il calendario"
            chiavi: ["Super", "O"]
        }
        Cartello {
            x: fondo.m
            y: fondo.height / 2 - height / 2
            nome: "Stanza 1, 2, 3…"
            chiavi: ["Super", "1 2 3"]
            detto: "con Maiusc porti la finestra"
        }

        // ── La finestra, in mezzo ──
        Column {
            anchors.centerIn: parent
            spacing: Theme.Effects.space3
            Cartello { anchors.horizontalCenter: parent.horizontalCenter; nome: "Metà sinistra · metà destra"; chiavi: ["Super", "←", "→"] }
            Cartello { anchors.horizontalCenter: parent.horizontalCenter; nome: "Ingrandisci · torna com'era"; chiavi: ["Super", "↑", "↓"] }
            Cartello { anchors.horizontalCenter: parent.horizontalCenter; nome: "Chiudi la finestra"; chiavi: ["Super", "Q"] }
            Cartello { anchors.horizontalCenter: parent.horizontalCenter; nome: "File · Terminale · Blocca"; chiavi: ["Super", "E", "↵", "L"] }
            Cartello { anchors.horizontalCenter: parent.horizontalCenter; nome: "Tutti i tasti"; chiavi: ["Super", "K"] }
        }
    }

    // ── Un cartello: il nome e i tasti ──────────────────────────────────
    component Cartello: Rectangle {
        id: c
        property string nome: ""
        property var chiavi: []
        property string detto: ""
        width: riga.implicitWidth + 2 * Theme.Effects.space3
        height: 44
        radius: height / 2
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.96))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        Row {
            id: riga
            anchors.centerIn: parent
            spacing: Theme.Effects.space2
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: c.chiavi
                    delegate: Rectangle {
                        id: tasto
                        required property string modelData
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        width: Math.max(26, lettera.implicitWidth + 14)
                        radius: 7
                        color: Theme.Colors.raised
                        border.width: 1
                        border.color: Qt.alpha(Theme.Colors.accent, 0.45)
                        Text {
                            id: lettera
                            anchors.centerIn: parent
                            text: tasto.modelData
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                    }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: c.nome
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: Theme.Typography.weightMedium
                }
                Text {
                    visible: c.detto !== ""
                    text: c.detto
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }
    }
}
