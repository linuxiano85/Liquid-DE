import QtQuick
import "../theme" as Theme
import "../core" as Core
import "." as Ui

// StatoSchermata — La riga in alto delle schermate di accesso e di blocco:
// il meteo al centro, tastiera e batteria a destra.
//
// Giacomo, 23 settembre 2026: «il meteo lo metterei in alto centrato come le
// icone IT e batteria, alla stessa altezza». È una riga sola e non due pezzi
// sparsi perché le due schermate si vedono una dopo l'altra, e devono dire le
// stesse cose negli stessi posti.
//
// Si ancora in cima con i margini che si vogliono; l'altezza è quella della
// riga di destra, e il meteo si allinea al suo centro.
Item {
    id: schermata

    property bool it: Core.Strings.lang === "it"
    /// Il meteo: solo se acceso E con un posto scelto (`Core.Meteo.attivo`).
    property bool conMeteo: true
    /// Batteria e tastiera.
    property bool conStato: true
    /// «IT», «US»; vuoto = non mostrare la tastiera.
    property string disposizione: ""

    implicitHeight: Math.max(statoRiga.implicitHeight, meteoRiga.implicitHeight)
    height: implicitHeight

    // ── Batteria e tastiera ──────────────────────────────────────────────
    //
    // In alto a destra, dove ogni schermo mette lo stato. La batteria perché
    // su un portatile chiuso da ieri è la prima cosa che serve sapere; la
    // tastiera perché è la risposta a «perché la password non va» quando la
    // disposizione non è quella che si crede — e fino al 23 settembre 2026
    // questa schermata ha avuto la tastiera AMERICANA senza che niente lo
    // dicesse (vedi `scripts/minerva-greetd`).
    Row {
        id: statoRiga
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: Theme.Effects.space4
        visible: schermata.conStato

        Row {
            spacing: Theme.Effects.space1
            visible: schermata.disposizione !== ""

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 17; height: 17
                name: "keyboard"
                color: Qt.alpha(Theme.Colors._bianco, 0.62)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: schermata.disposizione
                color: Qt.alpha(Theme.Colors._bianco, 0.72)
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        Row {
            spacing: Theme.Effects.space1
            visible: Core.SystemState.hasBattery

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                name: "battery"
                color: Core.SystemState.batteryCharging ? Theme.Colors.positive
                     : Core.SystemState.batteryPercent <= 15 ? Theme.Colors.danger
                     : Qt.alpha(Theme.Colors._bianco, 0.62)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Core.SystemState.batteryPercent + "%"
                      + (Core.SystemState.batteryCharging
                         ? (schermata.it ? " · in carica" : " · charging") : "")
                color: Qt.alpha(Theme.Colors._bianco, 0.72)
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    // ── Il meteo ─────────────────────────────────────────────────────
    //
    // In alto al centro, alla stessa altezza di tastiera e batteria: è
    // un'informazione di stato come loro, e lì la voleva Giacomo («il meteo
    // lo metterei in alto centrato come le icone IT e batteria»). Stesso
    // bianco velato: non deve gridare più dell'ora. Il simbolo, i gradi, com'è, e la massima e la
    // minima di oggi; la città in fondo, perché è quella scelta nella
    // sessione e chi guarda deve sapere di quale posto si parla.
    Row {
        id: meteoRiga
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: statoRiga.verticalCenter
        spacing: Theme.Effects.space2
        visible: schermata.conMeteo && Core.Meteo.pronto

        readonly property var oggi: Core.Meteo.giorni.length > 0
                                    ? Core.Meteo.giorni[0] : null

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            name: Core.Meteo.adesso
                  ? Core.Meteo.icona(Core.Meteo.adesso.codice, Core.Meteo.adesso.giorno)
                  : "nuvole"
            color: Qt.alpha(Theme.Colors._bianco, 0.86)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Core.Meteo.adesso ? Core.Meteo.gradi(Core.Meteo.adesso.temperatura) : ""
            color: Theme.Colors._bianco
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightSemiBold
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!Core.Meteo.adesso) return "";
                var t = Core.Meteo.descrizione(Core.Meteo.adesso.codice);
                var o = meteoRiga.oggi;
                if (o && o.max !== undefined && o.min !== undefined)
                    t += "  ·  " + Core.Meteo.gradi(o.max) + " / " + Core.Meteo.gradi(o.min);
                if (o && o.pioggia !== undefined && o.pioggia >= 30)
                    t += "  ·  " + (schermata.it ? "pioggia " : "rain ") + Math.round(o.pioggia) + "%";
                if (Core.Meteo.luogo !== "")
                    t += "  ·  " + Core.Meteo.luogo;
                return t;
            }
            color: Qt.alpha(Theme.Colors._bianco, 0.72)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }
    }

}
