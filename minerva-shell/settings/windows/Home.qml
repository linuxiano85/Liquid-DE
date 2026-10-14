import QtQuick
import "../../core" as Core
import "../../windows11" as W

// Home dalla VM (categoria-home-01.png): riepilogo, due colonne di schede,
// raccomandazioni a sinistra e temi/specifiche a destra. I dati sono Linux,
// non i dati inventati del PC Windows fotografato.
PaginaWindows {
    id: pagina
    function tr(it, en) { return W.Style.label(it, en); }
    function apri(id) { if (finestra) finestra.apriWindows(id); }
    briciole: [{testo: "Home"}]
    RiepilogoDispositivo { id: dispositivo }
    CatalogoTemi { id: catalogo }
    readonly property var update: Core.Ipc.liquidUpdateState
    Component.onCompleted: if (Core.Ipc.connected) Core.Ipc.send({action: "liquid_update_subscribe"});
    Component.onDestruction: if (Core.Ipc.connected) Core.Ipc.send({action: "liquid_update_unsubscribe"});
    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (Core.Ipc.connected) Core.Ipc.send({action: "liquid_update_subscribe"});
        }
    }
    IntestazioneDispositivo {
        dati: dispositivo.dati
        prefisso: "home"
        onAggiornamentiChiesti: pagina.apri("w-update")
    }
    Grid {
        width: parent.width
        columns: width >= 760 ? 2 : 1
        spacing: 8
        readonly property real colonna: (width - (columns - 1)*spacing)/columns
        Column {
            width: parent.colonna
            spacing: 8
            SchedaHome {
                width: parent.width
                titolo: pagina.tr("Impostazioni consigliate", "Recommended settings")
                descrizione: pagina.tr("Impostazioni di uso comune", "Commonly used settings")
                Repeater {
                    model: [
                        {id:"power", title:pagina.tr("Arresta", "Power"), icon:"power"},
                        {id:"accesso", title:pagina.tr("Schermata di blocco", "Lock screen"), icon:"lock"},
                        {id:"defaults", title:pagina.tr("App predefinite", "Default apps"), icon:"apps"}
                    ]
                    delegate: SchedaImpostazione {
                        required property var modelData
                        objectName: "homeRecommended-" + modelData.id
                        interna: true
                        implicitHeight: 69
                        icona: modelData.icon
                        titolo: modelData.title
                        porta: true
                        onAttivata: pagina.apri(modelData.id)
                    }
                }
            }
            SchedaHome {
                width: parent.width
                titolo: pagina.tr("Preferenze di accessibilità", "Accessibility preferences")
                descrizione: pagina.tr("Ottimizza le impostazioni per una migliore esperienza", "Optimize settings for a better experience")
                SchedaImpostazione {
                    objectName: "homeAccessibility"
                    interna: true
                    icona: "accessibility"
                    titolo: pagina.tr("Dimensioni del testo e accessibilità", "Text size and accessibility")
                    porta: true
                    onAttivata: pagina.apri("accesso-facile")
                }
            }
        }
        Column {
            width: parent.colonna
            spacing: 8
            SchedaHome {
                width: parent.width
                titolo: pagina.tr("Personalizza il dispositivo", "Personalize your device")
                descrizione: ""
                Item {
                    width: parent.width
                    height: griglia.height + 24
                    Grid {
                        id: griglia
                        x: 24
                        y: 0
                        columns: 3
                        spacing: 8
                        Repeater {
                            model: catalogo.temi.filter(function(t) { return t.disponibile !== false; }).slice(0, 6)
                            delegate: Rectangle {
                                id: tema
                                required property var modelData
                                objectName: "homeTheme-" + modelData.id
                                width: Math.min(112, (griglia.parent.width - 64)/3)
                                height: 90
                                radius: 4
                                color: "#202020"
                                border.width: modelData.id === catalogo.corrente ? 2 : 0
                                border.color: W.Style.accent
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.nome
                                Keys.onReturnPressed: catalogo.applica(modelData)
                                Keys.onSpacePressed: catalogo.applica(modelData)
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: Core.Wallpaper.urlFile(tema.modelData.sfondo)
                                    sourceSize: Qt.size(224, 180)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    width: 38
                                    height: 40
                                    radius: 4
                                    color: tema.modelData.tema === "dark" ? "#202020" : "#FFFFFF"
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 25
                                        width: 22
                                        height: 7
                                        radius: 2
                                        color: tema.modelData.accento
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: catalogo.applica(tema.modelData)
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    color: "transparent"
                                    border.width: 2
                                    border.color: W.Style.text
                                    visible: tema.activeFocus
                                }
                            }
                        }
                    }
                }
                SchedaImpostazione {
                    interna: true
                    icona: "tavolozza"
                    titolo: pagina.tr("Modalità colore", "Color mode")
                    TendinaWindows {
                        objectName: "homeColorMode"
                        valore: Core.Ipc.get("windows11.theme", "light")
                        voci: [{valore:"light", testo:pagina.tr("Chiara", "Light")}, {valore:"dark", testo:pagina.tr("Scura", "Dark")}]
                        onScelto: function(valore) { Core.Ipc.setSetting("windows11.theme", valore); }
                    }
                }
                SchedaImpostazione {
                    objectName: "homePersonalization"
                    interna: true
                    titolo: pagina.tr("Esplora più sfondi, colori e temi", "Explore more backgrounds, colors and themes")
                    porta: true
                    onAttivata: pagina.apri("w-personalizzazione")
                }
            }
            SchedaHome {
                width: parent.width
                titolo: pagina.tr("Informazioni sul dispositivo", "Device information")
                descrizione: pagina.tr("Visualizza le specifiche del tuo dispositivo e del sistema operativo", "View your device and operating system specifications")
                Grid {
                    x: 24
                    width: parent.width - 48
                    columns: width >= 340 ? 2 : 1
                    columnSpacing: 20
                    rowSpacing: 20
                    Repeater {
                        model: [
                            [pagina.tr("Processore", "Processor"), dispositivo.dati.cpu || "…"],
                            [pagina.tr("RAM utilizzabile", "Usable RAM"), dispositivo.dati.memory ? (dispositivo.dati.memory/1073741824).toLocaleString(Qt.locale(Core.Strings.lang), 'f', 2) + " GB" : "…"],
                            [pagina.tr("Sistema operativo", "Operating system"), dispositivo.dati.os || "…"],
                            ["Kernel", dispositivo.dati.kernel || "…"]
                        ]
                        delegate: Column {
                            required property var modelData
                            width: (parent.width - (parent.columns - 1)*parent.columnSpacing)/parent.columns
                            height: Math.max(70, implicitHeight)
                            spacing: 5
                            Text {
                                text: modelData[0]
                                textFormat: Text.PlainText
                                color: W.Style.text
                                font.family: W.Style.font
                                font.pixelSize: 14
                            }
                            Text {
                                width: parent.width
                                text: modelData[1]
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                color: W.Style.muted
                                font.family: W.Style.font
                                font.pixelSize: 14
                            }
                        }
                    }
                    Item { width: 1; height: 14 }
                }
                SchedaImpostazione {
                    objectName: "homeAbout"
                    interna: true
                    titolo: pagina.tr("Altre informazioni sul dispositivo", "More device information")
                    porta: true
                    onAttivata: pagina.apri("shell")
                }
            }
        }
    }
}
