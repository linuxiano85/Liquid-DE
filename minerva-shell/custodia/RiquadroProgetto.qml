import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// RiquadroProgetto — un progetto nella griglia della Custodia.
//
// ── Tre cose, e non una di più ─────────────────────────────────────────────
//
// Un riquadro deve rispondere a tre domande, quelle che uno si fa guardando
// una cartella dopo una settimana:
//
//   1. **quanto ho da salvare?**   il numero grande
//   2. **quand'è l'ultima volta?**  la riga sotto
//   3. **sono al sicuro fuori?**    il pallino a destra
//
// Tutto il resto — l'elenco dei file, la storia, i punti — sta dentro, a un
// clic. Un riquadro che dice tutto è un riquadro che non si legge, e
// quattordici riquadri che dicono tutto sono la schermata che fa chiudere il
// programma.
Rectangle {
    id: riquadro

    property var dati: ({})
    property bool it: true

    signal apri()

    readonly property bool esiste: riquadro.dati.esiste !== false
    readonly property var stato: riquadro.dati.stato || ({})
    readonly property int quante: riquadro.stato.quante || 0
    readonly property bool tieneStoria: riquadro.stato.tieneStoria === true
    readonly property int punti: riquadro.dati.punti || 0
    readonly property bool fuori: riquadro.stato.haDestinazione === true
                                  && (riquadro.stato.daMandare || 0) === 0

    implicitHeight: 148
    radius: Theme.Effects.radiusLG
    color: mouse.containsMouse ? Theme.Colors.raisedHigh : Theme.Colors.raised
    border.width: 1
    border.color: mouse.containsMouse ? Theme.Colors.edgeBright
                                      : Theme.Colors.edge

    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: riquadro.apri()
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.Effects.space4
        spacing: Theme.Effects.space2

        // ── Nome e stato «fuori» ─────────────────────────────────────────
        Item {
            width: parent.width
            height: nome.implicitHeight

            Text {
                id: nome
                width: parent.width - 96
                text: riquadro.dati.nome || ""
                elide: Text.ElideRight
                color: riquadro.esiste ? Theme.Colors.text
                                       : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightSemiBold
            }

            // Non un pallino colorato: una parola.
            //
            // Un colore senza spiegazione non si legge — chi guarda deve
            // ricordarsi che verde vuol dire «al sicuro», e non se lo ricorda.
            // Il colore resta, ma accompagna la parola invece di sostituirla.
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: nome.verticalCenter
                visible: riquadro.esiste
                width: dove.implicitWidth + 14
                height: dove.implicitHeight + 6
                radius: height / 2
                color: Qt.alpha(riquadro.fuori ? Theme.Colors.positive
                                               : Theme.Colors.textFaint, 0.16)

                Text {
                    id: dove
                    anchors.centerIn: parent
                    text: riquadro.fuori
                          ? (riquadro.it ? "AL SICURO" : "SAFE")
                          : (riquadro.it ? "SOLO QUI" : "LOCAL ONLY")
                    color: riquadro.fuori ? Theme.Colors.positive
                                          : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                    font.weight: Theme.Typography.weightSemiBold
                    font.letterSpacing: Theme.Typography.trackingLabel
                }
            }
        }

        Text {
            width: parent.width
            text: riquadro.dati.percorso || ""
            elide: Text.ElideLeft
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
        }

        Item { width: 1; height: Theme.Effects.space1 }

        // ── La risposta grossa ───────────────────────────────────────────
        Row {
            spacing: Theme.Effects.space2
            visible: riquadro.esiste

            Text {
                anchors.baseline: etichetta.baseline
                text: riquadro.tieneStoria ? riquadro.quante : "—"
                color: riquadro.quante > 0 ? Theme.Colors.accent
                                           : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXL
                font.weight: Theme.Typography.weightBold
            }

            Text {
                id: etichetta
                text: !riquadro.tieneStoria
                      ? (riquadro.it ? "non tiene ancora una storia"
                                     : "no history yet")
                      : riquadro.quante === 0
                        ? (riquadro.it ? "tutto salvato" : "all saved")
                        : riquadro.quante === 1
                          ? (riquadro.it ? "cosa da salvare" : "thing to save")
                          : (riquadro.it ? "cose da salvare" : "things to save")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        Text {
            width: parent.width
            visible: !riquadro.esiste
            wrapMode: Text.WordWrap
            text: riquadro.dati.avviso || ""
            color: Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── L'ultima riga: quando, e quanti punti di ritorno ─────────────────
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space4
        spacing: Theme.Effects.space3
        visible: riquadro.esiste

        Row {
            spacing: 5
            Ui.Icon {
                name: "clock"
                width: 13; height: 13
                color: Theme.Colors.textFaint
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var s = riquadro.dati.ultimoSalvataggio;
                    if (!s) return riquadro.it ? "mai salvato" : "never saved";
                    return Tempo.quandoBreve(s.quando, riquadro.it);
                }
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        Row {
            spacing: 5
            visible: riquadro.punti > 0
            Ui.Icon {
                name: "restore"
                width: 13; height: 13
                color: Theme.Colors.textFaint
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: riquadro.punti + " "
                      + (riquadro.it
                         ? (riquadro.punti === 1 ? "punto di ritorno"
                                                 : "punti di ritorno")
                         : (riquadro.punti === 1 ? "restore point"
                                                 : "restore points"))
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }
}
