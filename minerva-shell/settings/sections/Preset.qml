import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S
import "../../windows11" as Windows11

// Preset — Quale scrivania: Liquid, Minerva, Mac, Windows 11 o Libera, e le
// cose che ha solo lei.
//
// ── Perché è una pagina sua (11 ottobre 2026) ────────────────────────────
//
// il manutentore: «impostazioni per ogni preset grafica come Windows», «c'è il
// chaos». La scelta dello stile stava in cima ad Aspetto, come una tendina
// fra tante, e le opzioni di Windows 11 in fondo alla stessa pagina. Ma il
// preset non è un'opzione dell'aspetto: decide quali opzioni esistono.
// Adesso è la prima voce di Personalizzazione, con un disegno per ogni
// preset (lo stesso del selettore Super+P, `ui/SchemaPreset.qml`) e, sotto,
// le schede che valgono solo per il preset in uso.
//
// Ogni preset ricorda le sue preferenze (`minervad/lib/core/desktop_profiles.dart`):
// cambiare qui non perde niente, si ritrova tutto tornando indietro.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Preset" : "Preset"
    subtitle: Core.Strings.lang === "it"
              ? "Lo stile della scrivania e le cose che ha solo lui"
              : "The desktop style and what only it has"

    readonly property bool it: Core.Strings.lang === "it"
    readonly property string attuale: Core.DesktopStyle.attuale
    function applica(nome) { Core.DesktopStyle.applica(nome); }

    /// Quale selettore di colore è aperto (lo usa la scheda Windows 11).
    property string coloreAperto: ""

    Card {
        heading: page.it ? "Stile della scrivania" : "Desktop style"
        // La scelta del preset è la ragione della pagina: sempre aperta.
        chiudibile: false
        note: page.it
              ? "Ogni stile ricorda le proprie impostazioni: effetti, angoli attivi, colori, sfondo, icone, tiling e scorciatoie. Si cambia anche al volo con Super+P."
              : "Each style remembers its own effects, hot corners, colors, wallpaper, icons, tiling and shortcuts. Switch quickly with Super+P too."

        Flow {
            id: disegni
            width: parent.width
            spacing: Theme.Effects.space3
            // Cinque per riga finché c'è posto, ma mai più piccoli di 150.
            readonly property real lato: Math.max(150, (width - spacing * 4) / 5)

            Repeater {
                model: Core.DesktopStyle.elenco

                delegate: Rectangle {
                    id: scheda
                    required property var modelData
                    readonly property bool scelto: page.attuale === modelData.id
                    // Lo stesso nome della tendina di prima: le prove
                    // (`tests/prova_windows11.py`) la cercano così.
                    objectName: "desktopStyleChoice-" + modelData.id
                    width: disegni.lato
                    height: disegni.lato * 0.62 + 64
                    radius: Theme.Effects.radiusMD
                    color: scheda.scelto ? Qt.alpha(Theme.Colors.accent, 0.16)
                         : presa.containsMouse ? Theme.Colors.hover : Theme.Colors.sunken
                    border.width: scheda.scelto || scheda.activeFocus ? 2 : 1
                    border.color: scheda.scelto ? Theme.Colors.accent
                                : scheda.activeFocus ? Theme.Colors.edgeAccent : Theme.Colors.edge
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.nome
                    Accessible.checked: scelto
                    Keys.onReturnPressed: page.applica(modelData.id)
                    Keys.onSpacePressed: page.applica(modelData.id)

                    Item {
                        id: disegno
                        readonly property real quanto: (scheda.width - Theme.Effects.space3 * 2) / 152
                        x: (parent.width - width) / 2
                        y: Theme.Effects.space3
                        width: 152 * quanto
                        height: 92 * quanto
                        Ui.SchemaPreset {
                            quale: scheda.modelData.id
                            scale: parent.quanto
                            transformOrigin: Item.TopLeft
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: disegno.bottom
                        anchors.topMargin: Theme.Effects.space2
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.rightMargin: Theme.Effects.space3
                        spacing: 2

                        Text {
                            width: parent.width
                            text: scheda.modelData.nome + (scheda.scelto ? (page.it ? " · in uso" : " · in use") : "")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: scheda.scelto ? Theme.Colors.accent : Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightSemiBold
                        }
                        Text {
                            width: parent.width
                            text: scheda.modelData.breve || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }

                    MouseArea {
                        id: presa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            scheda.forceActiveFocus(Qt.MouseFocusReason);
                            page.applica(scheda.modelData.id);
                        }
                    }
                }
            }
        }

        // La descrizione lunga del preset in uso.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: {
                var v = Core.DesktopStyle.voce(page.attuale);
                return v ? v.descrizione : "";
            }
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    Card {
        objectName: "windowsAppearance"
        preset: ["windows"]
        apertaDiSerie: true
        heading: "Windows 11"
        note: page.it ? "Scegli il menu e il tema della barra. Le modifiche valgono solo per questo preset, compresi effetti e tiling." : "Choose the taskbar menu and theme. Changes apply only to this preset, including effects and tiling."
        S.SettingRow {
            width: parent.width
            label: page.it ? "Menu Start" : "Start menu"
            controlWidth: 280
            control: S.ChoicePicker {
                objectName: "windowsMenuChoice"
                value: Core.Ipc.get("windows11.menu", "windows11")
                options: [{value:"windows11",label:"Windows 11"},{value:"liquid",label:"Liquid"}]
                onPicked: function(v) {Core.Ipc.setSetting("windows11.menu",v);}
            }
        }
        S.SettingRow {
            width: parent.width
            label: page.it ? "Tema del desktop Windows" : "Windows desktop theme"
            controlWidth: 280
            control: S.ChoicePicker {
                objectName: "windowsThemeChoice"
                value: Core.Ipc.get("windows11.theme", "light")
                options: [{value:"light",label:page.it ? "Chiaro":"Light"},{value:"dark",label:page.it ? "Scuro":"Dark"}]
                onPicked: function(v) {Core.Ipc.setSetting("windows11.theme",v);}
            }
        }
        S.SettingRow {
            width:parent.width
            label:page.it ? "Sfondo Windows":"Windows wallpaper"
            controlWidth:460
            control:S.ChoicePicker {
                value:Core.Ipc.get("windows11.wallpaper","auto")
                options:[{value:"auto",label:page.it ? "Segue il tema":"Follow theme"},{value:"light",label:"Bloom Light"},{value:"dark",label:"Bloom Dark"},{value:"current",label:page.it ? "Il mio sfondo":"My wallpaper"}]
                onPicked:function(v) {Core.Ipc.setSetting("windows11.wallpaper",v);}
            }
        }
        Text {
            text: page.it ? "Colore d'accento Windows" : "Windows accent color"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: ["auto", "#0078D4", "#8764B8", "#C239B3", "#E74856", "#CA5010", "#10893E", "#038387", "#FFB900"]
                delegate: Rectangle {
                    id: windowsSwatch
                    required property string modelData
                    objectName: "windowsAccent-" + (modelData === "auto" ? "auto" : modelData.slice(1))
                    readonly property bool chosen: String(Core.Ipc.get("windows11.accent", "auto")).toUpperCase() === modelData.toUpperCase()
                    readonly property color tone: modelData === "auto" ? Windows11.Style.accent : modelData
                    width: 40; height: 40; radius: 4; color: tone
                    border.width: chosen || activeFocus ? 2 : 1
                    border.color: chosen || activeFocus ? Theme.Colors.text : Theme.Colors.edge
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData === "auto" ? (page.it ? "Accento automatico" : "Automatic accent") : modelData
                    Accessible.checked: chosen
                    function pick() { Core.Ipc.setSetting("windows11.accent", modelData); }
                    Accessible.onPressAction: pick()
                    Keys.onSpacePressed: pick()
                    Keys.onReturnPressed: pick()
                    Text {
                        anchors.centerIn: parent; visible: windowsSwatch.modelData === "auto"
                        text: "Auto"; color: Windows11.Style.foregroundFor(windowsSwatch.tone)
                        font.family: Windows11.Style.font; font.pixelSize: 11
                    }
                    Windows11.Glyph {
                        anchors.centerIn: parent; width: 20; height: 20
                        visible: windowsSwatch.chosen && windowsSwatch.modelData !== "auto"
                        name: "check"; color: Windows11.Style.foregroundFor(windowsSwatch.tone)
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { windowsSwatch.forceActiveFocus(Qt.MouseFocusReason); windowsSwatch.pick(); } }
                }
            }
            Windows11.Button {
                objectName: "windowsAccentCustom"
                text: page.it ? "Personalizzato" : "Custom"
                foreground: Theme.Colors.text
                onClicked: page.coloreAperto = page.coloreAperto === "windowsAccent" ? "" : "windowsAccent"
            }
        }
        S.SelettoreColore {
            width: parent.width; visible: page.coloreAperto === "windowsAccent"
            valore: Windows11.Style.accent
            onScelto: function(c) { Core.Ipc.setSetting("windows11.accent", c.toString().toUpperCase()); }
        }
        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra il colore d'accento su Start e barra" : "Show accent color on Start and taskbar"
            description: page.it ? "Disponibile nel tema scuro. I colori degli altri preset restano separati." : "Available in dark mode. Other presets keep their separate colors."
            control: S.ToggleSwitch {
                objectName: "windowsAccentOnStart"
                enabled: Windows11.Style.dark; opacity: enabled ? 1 : .5
                checked: Core.Ipc.get("windows11.accentOnStart", false)
                onToggled: function(v) { Core.Ipc.setSetting("windows11.accentOnStart", v); }
            }
        }
        S.SettingRow {
            width: parent.width
            label: page.it ? "Barra e pannelli di vetro" : "Glass taskbar and panels"
            description: page.it
                ? "Come l'Acrylic di Windows 11: la barra, il calendario, le impostazioni rapide e i Widget lasciano intravedere lo sfondo, sfocato. Le finestre restano piene. Si spegne da solo col risparmio energetico."
                : "Like Windows 11 Acrylic: the taskbar, calendar, quick settings and Widgets show the wallpaper through, blurred. Windows stay solid. Turns itself off in power saving."
            control: S.ToggleSwitch {
                objectName: "windowsAcrylic"
                checked: Core.Ipc.get("windows11.acrylic", true)
                onToggled: function (v) { Core.Ipc.setSetting("windows11.acrylic", v); }
            }
        }
        S.SettingRow {
            width:parent.width
            label:page.it ? "Icona tiling nella barra Windows":"Tiling icon on the Windows taskbar"
            control:S.ToggleSwitch {
                checked:Core.Ipc.get("windows11.showTilingButton",false)
                onToggled:function(v){Core.Ipc.setSetting("windows11.showTilingButton",v);}
            }
        }
        S.SettingRow {
            width: parent.width
            label: page.it ? "Documenti consigliati" : "Recommended documents"
            description: page.it ? "Mostra nello Start Windows i documenti locali aperti di recente." : "Show recently opened local documents in Windows Start."
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("windows11.recommendations",true)
                onToggled: function(v) {Core.Ipc.setSetting("windows11.recommendations",v);}
            }
        }
    }

    // ── La ricerca ───────────────────────────────────────────────────────
    //
    // Dove porta l'ingranaggio del pannello Cerca. Le stesse due cose di
    // Windows (Privacy e sicurezza › Autorizzazioni per la ricerca):
    // «Cronologia delle ricerche su questo dispositivo» e «Cancella
    // cronologia delle ricerche del dispositivo». Le ricerche restano qui.
    Card {
        objectName: "windowsSearchSettingsCard"
        preset: ["windows"]
        heading: page.it ? "Ricerca" : "Search"
        note: page.it
              ? "Le ultime ricerche compaiono quando apri Cerca. Restano su questo computer e non escono da qui."
              : "Your latest searches appear when you open Search. They stay on this computer."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Cronologia delle ricerche su questo dispositivo" : "Search history on this device"
            control: S.ToggleSwitch {
                objectName: "windowsSearchHistoryOn"
                checked: Core.Ipc.get("windows11.cronologiaRicerche", true)
                onToggled: function (v) { Core.Ipc.setSetting("windows11.cronologiaRicerche", v); }
            }
        }

        S.SettingRow {
            id: rigaCancella
            width: parent.width
            readonly property int quante: Core.Ipc.get("windows11.ricercheRecenti", []).length
            label: page.it ? "Cancella la cronologia delle ricerche del dispositivo"
                           : "Clear device search history"
            description: quante === 0
                ? (page.it ? "Nessuna ricerca salvata." : "No saved searches.")
                : (page.it ? quante + (quante === 1 ? " ricerca salvata." : " ricerche salvate.")
                           : quante + (quante === 1 ? " saved search." : " saved searches."))
            control: Rectangle {
                objectName: "windowsSearchHistoryClear"
                implicitWidth: cancella.implicitWidth + Theme.Effects.space4 * 2
                implicitHeight: 32
                radius: Theme.Effects.radiusSM
                opacity: rigaCancella.quante > 0 ? 1 : 0.45
                color: premi.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge
                Text {
                    id: cancella
                    anchors.centerIn: parent
                    text: page.it ? "Cancella" : "Clear"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                MouseArea {
                    id: premi
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: rigaCancella.quante > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Ipc.setSetting("windows11.ricercheRecenti", [])
                }
            }
        }
    }

    // ── Le notizie dei Widget ────────────────────────────────────────────
    //
    // Dove porta «Personalizza interessi» della bacheca Widget. Gli
    // interessi restano su questo computer: si scaricano le notizie delle
    // fonti accese e si sceglie qui quali mostrare
    // (`minervad/lib/services/notizie_service.dart`).
    Card {
        id: cardNotizie
        objectName: "windowsNewsSettings"
        preset: ["windows"]
        heading: page.it ? "Notizie dei Widget" : "Widgets news"
        note: page.it
              ? "Le notizie arrivano dai feed pubblici delle testate, senza account e senza tracciamento: gli interessi restano su questo computer, e le immagini le scarica Minerva senza cookie."
              : "News comes from the publishers' public feeds, with no account and no tracking: your interests stay on this computer, and Minerva downloads the images without cookies."

        readonly property var interessi: Core.Ipc.get("notizie.interessi", [])
        readonly property var spente: Core.Ipc.get("notizie.fontiSpente", [])
        property var fonti: []

        Component.onCompleted: Core.Ipc.fontiNotizie(page.it ? "it" : "en", cardNotizie.spente)
        Connections {
            target: Core.Ipc
            function onFontiNotizieRicevute(r) { cardNotizie.fonti = r.fonti || []; }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra le notizie" : "Show news"
            control: S.ToggleSwitch {
                objectName: "windowsNewsOn"
                checked: Core.Ipc.get("notizie.attive", true)
                onToggled: function (v) { Core.Ipc.setSetting("notizie.attive", v); }
            }
        }

        Text {
            text: page.it ? "Interessi" : "Interests"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Flow {
            width: parent.width
            spacing: Theme.Effects.space2

            Repeater {
                model: [
                    { "id": "attualita", "it": "Attualità", "en": "Top stories" },
                    { "id": "tecnologia", "it": "Tecnologia", "en": "Technology" },
                    { "id": "scienza", "it": "Scienza", "en": "Science" },
                    { "id": "economia", "it": "Economia", "en": "Business" },
                    { "id": "sport", "it": "Sport", "en": "Sport" },
                    { "id": "cultura", "it": "Cultura", "en": "Culture" }
                ]

                delegate: Rectangle {
                    id: interesse
                    required property var modelData
                    readonly property bool scelto: cardNotizie.interessi.indexOf(modelData.id) >= 0
                    objectName: "windowsNewsInterest-" + modelData.id
                    width: nomeInteresse.implicitWidth + Theme.Effects.space4 * 2
                    height: 32
                    radius: height / 2
                    color: scelto ? Qt.alpha(Theme.Colors.accent, 0.22)
                         : presaInteresse.containsMouse ? Theme.Colors.hover : Theme.Colors.sunken
                    border.width: 1
                    border.color: scelto ? Theme.Colors.edgeAccent : "transparent"
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: nomeInteresse.text
                    Accessible.checked: scelto

                    Text {
                        id: nomeInteresse
                        anchors.centerIn: parent
                        text: page.it ? interesse.modelData.it : interesse.modelData.en
                        color: interesse.scelto ? Theme.Colors.text : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    MouseArea {
                        id: presaInteresse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var ora = cardNotizie.interessi.filter(function (x) { return x !== interesse.modelData.id; });
                            if (!interesse.scelto)
                                ora.push(interesse.modelData.id);
                            Core.Ipc.setSetting("notizie.interessi", ora);
                        }
                    }
                }
            }
        }

        Text {
            text: page.it ? "Fonti" : "Sources"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Repeater {
            model: cardNotizie.fonti

            delegate: S.SettingRow {
                id: fonte
                required property var modelData
                width: parent ? parent.width : 0
                label: fonte.modelData.nome
                description: fonte.modelData.url
                control: S.ToggleSwitch {
                    checked: cardNotizie.spente.indexOf(fonte.modelData.url) < 0
                    onToggled: function (v) {
                        var ora = cardNotizie.spente.filter(function (u) { return u !== fonte.modelData.url; });
                        if (!v)
                            ora.push(fonte.modelData.url);
                        Core.Ipc.setSetting("notizie.fontiSpente", ora);
                    }
                }
            }
        }
    }
}
