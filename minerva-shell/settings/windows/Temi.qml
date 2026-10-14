import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S
import "Dati.js" as Dati

// Personalizzazione › Temi, come in Windows 11 (macchina di riferimento, 12
// ottobre 2026): l'anteprima con Sfondo, Colore, Suoni e Cursore del mouse,
// «Salva», poi «Tema corrente» con la galleria.
//
// Un tema è sfondo + modalità + colore principale. La galleria ha la forma
// di quella di Windows ma il contenuto è di Liquid: i temi di Windows usano
// immagini Microsoft che non si possono distribuire. Ci sono «Windows
// (chiaro)» e «Windows (scuro)» (con Bloom se è sul disco), i temi fatti con
// gli sfondi di Liquid e quelli salvati con «Salva» (`windows11.temi`): i
// temi personali che il manutentore ha chiesto.
PaginaWindows {
    id: pagina

    readonly property string lingua: Core.Strings.lang
    function tt(k) { return Dati.t(pagina.lingua, k); }
    readonly property bool it: pagina.lingua === "it"

    briciole: [{ "testo": tt("personalizzazione"), "pagina": "w-personalizzazione" }, { "testo": tt("temi") }]

    CatalogoTemi { id: catalogo }
    readonly property var temi: catalogo.temi
    readonly property string corrente: catalogo.corrente
    readonly property string nomeCorrente: catalogo.nomeCorrente
    readonly property string accento: catalogo.accento
    function applica(t) { catalogo.applica(t); }
    function salva() { catalogo.salva(); }

    // ── L'anteprima e le quattro voci ──
    Item {
        width: parent.width
        height: 188
        AnteprimaDesktop { width: 336; height: 188 }
        Grid {
            x: 355
            y: -8
            columns: 2
            Repeater {
                model: [
                    { "icona": "immagine", "titolo": pagina.tt("sfondo"), "valore": String(Core.Wallpaper.current).replace(/^.*\//, "").replace(/\.[a-z]+$/, ""), "pagina": "w-sfondo" },
                    { "icona": "tavolozza", "titolo": pagina.tt("colore"), "valore": Dati.nomeColore(pagina.accento), "pagina": "w-colori" },
                    { "icona": "suoni", "titolo": pagina.tt("suoni"), "valore": pagina.it ? "Predefiniti di Liquid" : "Liquid defaults", "liquid": "audio" },
                    { "icona": "cursore", "titolo": pagina.tt("cursore"), "valore": pagina.it ? "Predefinito" : "Default", "liquid": "accesso-facile" }
                ]
                delegate: Rectangle {
                    id: voce
                    required property var modelData
                    width: 208
                    height: 54
                    radius: 4
                    color: presa.containsMouse ? W.Style.hover : "transparent"
                    W.Glyph { x: 14; y: 8; width: 20; height: 20; name: voce.modelData.icona; color: W.Style.text }
                    Column {
                        x: 48; y: 7
                        Text { text: voce.modelData.titolo; color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14 }
                        Text { width: 150; elide: Text.ElideRight; text: voce.modelData.valore; color: W.Style.muted; font.family: W.Style.font; font.pixelSize: 14 }
                    }
                    MouseArea {
                        id: presa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (pagina.finestra) pagina.finestra.apriWindows(voce.modelData.pagina || voce.modelData.liquid)
                    }
                }
            }
        }
        PulsanteWindows {
            objectName: "salvaTema"
            x: 367
            y: 103
            testo: pagina.tt("salva")
            onPremuto: pagina.salva()
        }
    }
    Item { width: 1; height: 21 }

    EspansoreImpostazione {
        objectName: "temaCorrente"
        titolo: pagina.tt("temaCorrente")
        descrizione: pagina.tt("temaCorrenteDescr")
        aperto: true
        comando: Text {
            text: pagina.nomeCorrente
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 14
        }
        Item {
            width: parent.width
            height: galleria.height + 36
            Rectangle { width: parent.width; height: 1; color: W.Style.divider }
            Flow {
                id: galleria
                x: 59; y: 18
                width: parent.width - 59 - 44
                spacing: 4
                Repeater {
                    model: pagina.temi
                    delegate: Rectangle {
                        id: riquadro
                        required property var modelData
                        readonly property bool usabile: modelData.disponibile !== false
                        readonly property bool scelto: modelData.id === pagina.corrente
                        activeFocusOnTab: usabile
                        Keys.onReturnPressed: if (usabile) catalogo.applica(modelData)
                        Keys.onSpacePressed: if (usabile) catalogo.applica(modelData)
                        objectName: "tema-" + modelData.id
                        width: 116
                        height: 94
                        radius: 6
                        color: "transparent"
                        border.width: riquadro.scelto ? 2 : ((presaTema.containsMouse || activeFocus) && riquadro.usabile ? 1 : 0)
                        border.color: activeFocus ? W.Style.accentIndicator : riquadro.scelto ? W.Style.accent : W.Style.text
                        opacity: riquadro.usabile ? 1 : 0.5
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: riquadro.modelData.nome
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 4
                            clip: true
                            color: "#202020"
                            Image {
                                anchors.fill: parent
                                visible: riquadro.modelData.sfondo !== ""
                                source: riquadro.modelData.sfondo !== "" ? Core.Wallpaper.urlFile(riquadro.modelData.sfondo) : ""
                                sourceSize: Qt.size(220, 180)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            // La finestrella del tema col pulsante d'accento.
                            Rectangle {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                width: 38
                                height: 26
                                radius: 3
                                color: riquadro.modelData.tema === "dark" ? "#202020" : "#FFFFFF"
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 6
                                    radius: 2
                                    color: riquadro.modelData.accento
                                }
                            }
                        }
                        MouseArea {
                            id: presaTema
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: riquadro.usabile
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pagina.applica(riquadro.modelData)
                        }
                    }
                }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: pagina.tt("altriTemi")
            disponibile: false
        }
    }

    GruppoImpostazioni { testo: pagina.tt("correlate") }
    SchedaImpostazione {
        icona: "schermoPC"
        titolo: pagina.tt("iconeDesktop")
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriWindows("scrivania")
    }
    SchedaImpostazione {
        icona: "contrasto"
        titolo: pagina.tt("contrasto")
        descrizione: pagina.tt("contrastoDescr")
        porta: true
        disponibile: false
    }
}
