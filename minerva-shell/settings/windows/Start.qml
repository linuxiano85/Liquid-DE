import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S
import "Dati.js" as Dati

// Le misure e l'ordine provengono dalla pagina Start della VM del 12 ottobre.
// Le opzioni senza un servizio equivalente restano esplicitamente disabilitate.
PaginaWindows {
    id: pagina
    readonly property string lingua: Core.Strings.lang
    readonly property string layout: Core.Ipc.get("windows11.startLayout", "default")
    readonly property bool moderno: Core.Ipc.get("windows11.startExperience", "modern") === "modern"
    briciole: [
        { "testo": Dati.t(lingua, "personalizzazione"), "pagina": "w-personalizzazione" },
        { "testo": "Start" }
    ]

    SchedaImpostazione {
        titolo: W.Style.label("Design del menu Start", "Start menu design")
        icona: "grid"
        TendinaWindows {
            objectName: "startDesign"
            valore: Core.Ipc.get("windows11.startExperience", "modern")
            voci: [
                { valore: "modern", testo: W.Style.label("Pannello unico", "Unified panel") },
                { valore: "classic", testo: W.Style.label("Design precedente", "Previous design") }
            ]
            onScelto: function(v) { Core.Ipc.setSetting("windows11.startExperience", v); }
        }
    }
    SchedaImpostazione {
        visible: pagina.moderno
        titolo: W.Style.label("Visualizzazione delle app", "App view")
        icona: "apps"
        TendinaWindows {
            objectName: "startVistaApp"
            valore: Core.Ipc.get("windows11.startAppsView", "category")
            voci: [
                { valore: "category", testo: W.Style.label("Categorie", "Category") },
                { valore: "grid", testo: W.Style.label("Griglia", "Grid") },
                { valore: "list", testo: W.Style.label("Elenco", "List") }
            ]
            onScelto: function(v) { Core.Ipc.setSetting("windows11.startAppsView", v); }
        }
    }
    Repeater {
        model: [
            { key: "startPinnedExpanded", it: "Espandi i preferiti", en: "Expand pinned apps" },
            { key: "startRecommendedExpanded", it: "Espandi gli elementi consigliati", en: "Expand recommendations" }
        ]
        delegate: SchedaImpostazione {
            required property var modelData
            visible: pagina.moderno
            titolo: W.Style.label(modelData.it, modelData.en)
            S.ToggleSwitch {
                objectName: "start-" + modelData.key
                Accessible.name: W.Style.label(modelData.it, modelData.en)
                checked: Core.Ipc.get("windows11." + modelData.key, false)
                onToggled: function(v) { Core.Ipc.setSetting("windows11." + modelData.key, v); }
            }
        }
    }
    GruppoImpostazioni { testo: "Layout"; visible: !pagina.moderno }
    Row {
        visible: !pagina.moderno
        width: parent.width
        spacing: 24
        Repeater {
            model: [
                { "id": "pinned", "righe": 4, "testo": W.Style.label("Altri elementi ancorati", "More pins") },
                { "id": "default", "righe": 3, "testo": W.Style.label("Predefinito", "Default") },
                { "id": "recommended", "righe": 2, "testo": W.Style.label("Altri elementi consigliati", "More recommendations") }
            ]
            delegate: Rectangle {
                id: scelta
                required property var modelData
                readonly property bool selezionata: pagina.layout === modelData.id
                objectName: "layoutStart-" + modelData.id
                width: (parent.width - 48) / 3
                height: miniatura.height + 48
                radius: 8
                color: "transparent"
                border.width: selezionata || activeFocus ? 2 : 0
                border.color: activeFocus ? W.Style.accent : W.Style.text
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.testo
                Accessible.checkable: true
                Accessible.checked: selezionata
                Accessible.onPressAction: applica()
                function applica() {
                    Core.Ipc.setSetting("windows11.startLayout", modelData.id);
                }
                Keys.onReturnPressed: applica()
                Keys.onSpacePressed: applica()
                AnteprimaStart {
                    id: miniatura
                    width: parent.width
                    height: width * 204 / 312
                    righe: scelta.modelData.righe
                }
                Rectangle {
                    x: 14
                    y: miniatura.height + 17
                    width: 20
                    height: 20
                    radius: 10
                    color: scelta.selezionata ? W.Style.accent : "transparent"
                    border.width: scelta.selezionata ? 0 : 1
                    border.color: W.Style.muted
                    Rectangle {
                        anchors.centerIn: parent
                        width: 10
                        height: 10
                        radius: 5
                        color: "white"
                        visible: scelta.selezionata
                    }
                }
                Text {
                    x: 42
                    y: miniatura.height + 17
                    width: parent.width - x - 8
                    text: scelta.modelData.testo
                    color: W.Style.text
                    font.family: W.Style.font
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: scelta.applica()
                }
            }
        }
    }
    Item { width: 1; height: 12 }
    SchedaImpostazione {
        titolo: W.Style.label("Mostra le app aggiunte di recente", "Show recently added apps")
        icona: "download"
        disponibile: false
    }
    SchedaImpostazione {
        titolo: W.Style.label("Mostra le app più usate", "Show most used apps")
        icona: "star"
        disponibile: false
    }
    SchedaImpostazione {
        titolo: W.Style.label("Mostra i file consigliati in Start", "Show recommended files in Start")
        icona: "document"
        S.ToggleSwitch {
            objectName: "startConsigliati"
            Accessible.name: parent.parent.titolo
            checked: Core.Ipc.get("windows11.recommendations", true)
            onToggled: function(v) { Core.Ipc.setSetting("windows11.recommendations", v); }
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Mostra consigli per suggerimenti, collegamenti, nuove app e altro ancora", "Show recommendations for tips, shortcuts, new apps, and more")
        icona: "lampadina"
        disponibile: false
    }
    SchedaImpostazione {
        titolo: W.Style.label("Mostra notifiche correlate all'account", "Show account-related notifications")
        icona: "user"
        disponibile: false
    }
    SchedaImpostazione {
        objectName: "startCartelle"
        titolo: W.Style.label("Cartelle", "Folders")
        descrizione: W.Style.label("Queste cartelle vengono visualizzate su Start accanto al pulsante Arresta.", "These folders appear on Start next to the Power button.")
        icona: "folder"
        porta: true
        onAttivata: if (pagina.finestra) pagina.finestra.apriWindows("w-start-cartelle")
    }
    GruppoImpostazioni { testo: Dati.t(pagina.lingua, "opzioniLiquid") }
    SchedaImpostazione {
        titolo: W.Style.label("Menu Start", "Start menu")
        TendinaWindows {
            objectName: "startTipo"
            valore: Core.Ipc.get("windows11.menu", "windows11")
            voci: [ { "valore": "windows11", "testo": "Familiare" }, { "valore": "liquid", "testo": "Liquid" } ]
            onScelto: function(v) { Core.Ipc.setSetting("windows11.menu", v); }
        }
    }
}
