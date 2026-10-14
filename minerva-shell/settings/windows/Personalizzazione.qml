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
        width: parent.width
        height: 212
        AnteprimaDesktop { y: 24; width: 336; height: 188 }
        Text {
            x: 382; y: 0
            text: pagina.tt("selezionaTema")
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Grid {
            x: 382; y: 31
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
                    width: 116; height: 94; radius: 6
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
}
