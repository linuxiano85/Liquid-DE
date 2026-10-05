import QtQuick
import QtMultimedia

import "../theme" as Theme
import "../ui" as Ui

// PiPWindow — Il video in miniatura sopra tutto.
//
// Quando il filmato si sposta di qui, il riproduttore smette di disegnare
// nella finestra e comincia a disegnare qui: un `VideoOutput` solo, due
// superfici, e il passaggio è il cambio di una proprietà.
//
// La finestra non ha bordo sistema: si trascina dal video, e i comandi
// compaiono sotto il puntatore e si ritirano da soli dopo tre secondi di
// quiete.
Item {
    id: pip
    visible: false

    /// Il MediaPlayer che si sta guardando.
    property var riproduttore: null
    /// Vera quando il PiP è aperto.
    property bool attivo: false
    /// Emesso quando si chiude: chi ospita deve rimettere il video al suo posto.
    signal chiuso()
    /// Emesso dal tasto «successivo»: la playlist è di chi ospita.
    signal successivoRichiesto()
    signal precedenteRichiesto()

    /// La superficie su cui il riproduttore disegna quando è in PiP.
    readonly property alias uscita: uscitaPip

    // ── I comandi ─────────────────────────────────────────────────────────

    function _comando(cosa) {
        var r = pip.riproduttore;
        if (!r)
            return;
        if (cosa === "play") {
            if (r.playing)
                r.pause();
            else
                r.play();
        } else if (cosa === "prev") {
            // Qui c'era `r.position = 0`, cioè «torna all'inizio di questo».
            // Il tasto ha lo stesso segno di quello della finestra grande, che
            // invece va al brano PRECEDENTE: due gesti uguali che facevano due
            // cose diverse, e chi ha usato il primo si fida del secondo.
            pip.precedenteRichiesto();
        } else if (cosa === "next") {
            pip.successivoRichiesto();
        } else if (cosa === "chiudi") {
            pip.attivo = false;
            pip.chiuso();
        }
    }

    function _mostraBarra() {
        barra.opacity = 1;
        nascondi.restart();
    }

    Window {
        id: finestra
        visible: pip.attivo
        width: 400
        height: 225
        title: "Minerva · Media"
        color: "transparent"
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
               | Qt.WindowDoesNotAcceptFocus
        x: Screen.width - width - 24
        y: 24

        Rectangle {
            id: tela
            anchors.fill: parent
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.base
            border.color: Theme.Colors.edgeBright
            clip: true

            VideoOutput {
                id: uscitaPip
                anchors.fill: parent
            }

            // La superficie che trascina e comanda. Sta sotto la barra dei
            // tasti: un clic sul vuoto fa pausa/riproduci, un trascinamento
            // sposta la finestra, e un movimento di un paio di pixel decide
            // quale dei due è successo.
            MouseArea {
                id: superficie
                anchors.fill: parent
                hoverEnabled: true

                property bool trascinando: false
                property point avvio: Qt.point(0, 0)

                onEntered: pip._mostraBarra()
                onExited: nascondi.restart()

                onPressed: function (m) {
                    superficie.trascinando = false;
                    superficie.avvio = Qt.point(m.x, m.y);
                    pip._mostraBarra();
                }

                onPositionChanged: function (m) {
                    if (!superficie.pressed)
                        return;
                    if (!superficie.trascinando
                            && Math.abs(m.x - superficie.avvio.x)
                               + Math.abs(m.y - superficie.avvio.y) > 8)
                        superficie.trascinando = true;
                    if (superficie.trascinando) {
                        finestra.x += m.x - superficie.avvio.x;
                        finestra.y += m.y - superficie.avvio.y;
                    }
                }

                onClicked: function (m) {
                    if (!superficie.trascinando)
                        pip._comando("play");
                }
            }

            // La barra dei comandi: sparisce da sola.
            Row {
                id: barra
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.Effects.space2
                spacing: Theme.Effects.space1
                opacity: 0

                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }

                TastoPiP { icona: "prev"; onPremuto: pip._comando("prev") }
                TastoPiP {
                    icona: pip.riproduttore && pip.riproduttore.playing
                           ? "pause" : "play"
                    onPremuto: pip._comando("play")
                }
                TastoPiP { icona: "next"; onPremuto: pip._comando("next") }
                TastoPiP { icona: "close"; onPremuto: pip._comando("chiudi") }
            }

            Timer {
                id: nascondi
                interval: 3000
                onTriggered: barra.opacity = 0
            }
        }
    }

    component TastoPiP: Rectangle {
        property string icona: ""
        signal premuto()
        width: 30
        height: 30
        radius: Theme.Effects.radiusFull
        color: presaPiP.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
        Ui.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: parent.icona
            // Non un bianco scritto a mano: su un tema chiaro un'icona
            // bianca su fondo trasparente sparisce.
            color: Theme.Colors.textOnAccent
        }
        MouseArea {
            id: presaPiP
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.premuto()
        }
    }
}