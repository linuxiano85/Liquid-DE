import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// WeatherPanel — Il tempo, per esteso.
//
// Nella barra c'è quello che si guarda di sfuggita: un simbolo e una
// temperatura. Qui c'è il resto, che si viene a leggere apposta — quanto
// scalda davvero, quanta umidità, quanto vento, e i prossimi sette giorni.
//
// I sette giorni sono righe e non una griglia di piastrelle: si leggono
// dall'alto in basso come un elenco di giorni, che è come li pensa chi si
// chiede «e domani?».
Item {
    id: panel

    property var spine: null

    readonly property bool it: Core.Strings.lang === "it"
    readonly property var m: Core.Meteo.adesso

    readonly property real implicitPanelHeight:
        Theme.Effects.space5 + testa.height + Theme.Effects.space4
        + dettagli.height + Theme.Effects.space4
        + settimana.implicitHeight + Theme.Effects.space5

    // ── Adesso ───────────────────────────────────────────────────────────

    Item {
        id: testa
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.Effects.space5
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        height: 78

        Ui.Icon {
            id: simbolo
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 54; height: 54
            name: panel.m ? Core.Meteo.icona(panel.m.codice, panel.m.giorno)
                          : "nuvole"
            color: Theme.Colors.accent
        }

        Column {
            anchors.left: simbolo.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: panel.m ? Core.Meteo.gradi(panel.m.temperatura) : "—"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXL
            }

            Text {
                text: panel.m ? Core.Meteo.descrizione(panel.m.codice) : ""
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: Core.Meteo.luogo
                      + (Core.Meteo.vecchio
                         ? (panel.it ? "  ·  dati non aggiornati"
                                     : "  ·  data not current")
                         : "")
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }

    // ── I dettagli ───────────────────────────────────────────────────────

    Grid {
        id: dettagli
        anchors.top: testa.bottom
        anchors.topMargin: Theme.Effects.space4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        columns: 2
        columnSpacing: Theme.Effects.space2
        rowSpacing: Theme.Effects.space2

        readonly property real cella: (width - columnSpacing) / 2

        component Voce: Rectangle {
            id: voce
            property string titolo: ""
            property string valore: "—"

            width: dettagli.cella
            height: 44
            radius: Theme.Effects.radiusSM
            color: Theme.Colors.raised

            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                spacing: 1

                Text {
                    text: voce.titolo
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }
                Text {
                    text: voce.valore
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }

        Voce {
            titolo: panel.it ? "Percepita" : "Feels like"
            valore: panel.m ? Core.Meteo.gradi(panel.m.percepita) : "—"
        }
        Voce {
            titolo: panel.it ? "Umidità" : "Humidity"
            valore: panel.m && panel.m.umidita !== null
                    ? Math.round(panel.m.umidita) + "%" : "—"
        }
        Voce {
            titolo: panel.it ? "Vento" : "Wind"
            valore: panel.m && panel.m.vento !== null
                    ? Math.round(panel.m.vento) + " km/h" : "—"
        }
        Voce {
            titolo: panel.it ? "Pioggia" : "Precipitation"
            valore: panel.m && panel.m.pioggia !== null
                    ? panel.m.pioggia.toFixed(1) + " mm" : "—"
        }
    }

    // ── I prossimi giorni ────────────────────────────────────────────────

    Column {
        id: settimana
        anchors.top: dettagli.bottom
        anchors.topMargin: Theme.Effects.space4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        spacing: 1

        Repeater {
            model: Core.Meteo.giorni

            delegate: Item {
                id: riga
                required property var modelData
                required property int index

                width: settimana.width
                height: 26

                readonly property var quando: new Date(riga.modelData.data)

                Text {
                    id: nomeGiorno
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 84
                    // Il primo si chiama «Oggi»: nessuno pensa a oggi come
                    // «lunedì», e leggere il proprio giorno per nome in cima
                    // a un elenco di previsioni fa fermare un istante.
                    text: riga.index === 0
                          ? (panel.it ? "Oggi" : "Today")
                          : riga.quando.toLocaleDateString(
                                panel.it ? Qt.locale("it_IT") : Qt.locale("en_GB"),
                                "ddd d")
                    color: riga.index === 0 ? Theme.Colors.text
                                            : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Ui.Icon {
                    id: iconaGiorno
                    anchors.left: nomeGiorno.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17; height: 17
                    name: Core.Meteo.icona(riga.modelData.codice, true)
                    color: Theme.Colors.textMuted
                }

                Text {
                    anchors.left: iconaGiorno.right
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: riga.modelData.pioggia > 5
                    text: Math.round(riga.modelData.pioggia) + "%"
                    color: Theme.Colors.accent
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Core.Meteo.gradi(riga.modelData.min) + "   "
                          + Core.Meteo.gradi(riga.modelData.max)
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }
    }
}
