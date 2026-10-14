import QtQuick
import "../../core" as Core
import "../../windows11" as W
import "Dati.js" as Dati

// Personalizzazione, la pagina della categoria, come in Windows 11
// (macchina di riferimento, 12 ottobre 2026): l'anteprima del desktop,
// «Seleziona un tema da applicare» con sei temi, poi le schede delle
// sottopagine nell'ordine di Windows (`Dati.personalizzazione`).
PaginaWindows {
    id: pagina

    readonly property string lingua: Core.Strings.lang
    function tt(k) { return Dati.t(pagina.lingua, k); }

    briciole: [{ "testo": tt("personalizzazione") }]

    CatalogoTemi { id: temi }

    Item {
        id: anteprimaTemi
        readonly property bool affiancati: width >= 740
        width: parent.width
        height: Math.max(212, temiRapidi.y + temiRapidi.height)
        AnteprimaDesktop {
            id: anteprima
            y: 24
            width: Math.min(336, parent.width)
            height: width * 188 / 336
        }
        Text {
            x: anteprimaTemi.affiancati ? 382 : 0
            y: anteprimaTemi.affiancati ? 0 : anteprima.y + anteprima.height + 16
            width: parent.width - x
            wrapMode: Text.WordWrap
            text: pagina.tt("selezionaTema")
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Grid {
            id: temiRapidi
            x: anteprimaTemi.affiancati ? 382 : 0
            y: anteprimaTemi.affiancati ? 31 : anteprima.y + anteprima.height + 64
            columns: 3
            spacing: 4
            Repeater {
                model: temi.temi.filter(function (t) { return t.id.indexOf("utente-") !== 0; }).slice(0, 6)
                delegate: Rectangle {
                    id: riquadro
                    required property var modelData
                    readonly property bool usabile: modelData.disponibile !== false
                    activeFocusOnTab: usabile
                    Keys.onReturnPressed: if (usabile) temi.applica(modelData)
                    Keys.onSpacePressed: if (usabile) temi.applica(modelData)
                    objectName: "temaRapido-" + modelData.id
                    width: Math.min(116, (anteprimaTemi.width - temiRapidi.x - 8) / 3)
                    height: width * 94 / 116
                    radius: 6
                    color: "transparent"
                    border.width: modelData.id === temi.corrente ? 2 : (presa.containsMouse && usabile ? 1 : 0)
                    border.color: modelData.id === temi.corrente ? W.Style.accent : W.Style.text
                    opacity: usabile ? 1 : 0.5
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 3; radius: 4; clip: true; color: "#202020"
                        Image {
                            anchors.fill: parent
                            visible: riquadro.modelData.sfondo !== ""
                            source: riquadro.modelData.sfondo !== "" ? Core.Wallpaper.urlFile(riquadro.modelData.sfondo) : ""
                            sourceSize: Qt.size(220, 180)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
                            width: 38; height: 26; radius: 3
                            color: riquadro.modelData.tema === "dark" ? "#202020" : "#FFFFFF"
                            Rectangle { anchors.centerIn: parent; width: 22; height: 6; radius: 2; color: riquadro.modelData.accento }
                        }
                    }
                    MouseArea {
                        id: presa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: riquadro.usabile
                        cursorShape: Qt.PointingHandCursor
                        onClicked: temi.applica(riquadro.modelData)
                    }
                }
            }
        }
    }
    Item { width: 1; height: 4 }

    Repeater {
        model: Dati.personalizzazione
        delegate: SchedaImpostazione {
            required property var modelData
            objectName: "categoriaVoce-" + modelData.id
            icona: ({ "image": "immagine", "colori": "tavolozza", "temi": "pennello", "illuminazione": "lampadina",
                      "lock": "lucchetto", "tastiera": "tastiera", "grid": "grid", "barra": "finestra",
                      "caratteri": "carattere" })[modelData.icona] || "settings"
            titolo: pagina.tt(modelData.id)
            descrizione: pagina.tt(modelData.id + "Descr")
            porta: true
            disponibile: modelData.pagina !== undefined || modelData.liquid !== undefined
            onAttivata: if (pagina.finestra) pagina.finestra.apriWindows(modelData.pagina || modelData.liquid)
        }
    }

    GruppoImpostazioni { testo: pagina.tt("opzioniLiquid") }
    Repeater {
        // Le pagine esistenti devono restare raggiungibili anche senza
        // indovinare una parola nella ricerca della barra laterale.
        model: pagina.finestra ? pagina.finestra.categoriaPer("personalizzazione").voci : []
        delegate: SchedaImpostazione {
            required property string modelData
            readonly property var destinazione: pagina.finestra.paginaPer(modelData)
            objectName: "categoriaVoce-liquid-" + modelData
            icona: destinazione ? destinazione.icon : "settings"
            titolo: destinazione ? (W.Style.it ? destinazione.it : destinazione.en) : ""
            porta: true
            onAttivata: pagina.finestra.apriSezione(modelData)
        }
    }
}
