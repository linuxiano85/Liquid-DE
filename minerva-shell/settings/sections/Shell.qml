import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Shell — Le preferenze di Minerva stessa.
//
// Separata dalle impostazioni di sistema di proposito: qui dentro non c'è
// niente che riguardi l'hardware. Chi cerca la luminosità non deve trovarsela
// in mezzo alle opzioni della barra.
Page {
    id: page

    title: "Minerva"
    subtitle: Core.Strings.lang === "it"
              ? "Comportamento della barra, dei pannelli e degli avvisi"
              : "Behaviour of the bar, the panels and the notifications"

    readonly property bool it: Core.Strings.lang === "it"

    /// Le categorie del menu applicazioni che si possono nascondere.
    /// «Preferiti» e «Tutte» non ci sono di proposito: sono le vie d'uscita.
    ///
    /// Stanno anche in `spine/panels/AppsPanel.qml`, e si ripetono qui per una
    /// ragione sola: quel pannello vive e muore con la propria apertura, e le
    /// Impostazioni devono poterle elencare anche a menu chiuso.
    function categoriaVisibile(id) {
        return Core.Ipc.get("launcher.hiddenCategories", []).indexOf(id) === -1;
    }

    function mostraCategoria(id, mostra) {
        var nascoste = Core.Ipc.get("launcher.hiddenCategories", []).slice();
        var i = nascoste.indexOf(id);
        if (mostra && i !== -1)
            nascoste.splice(i, 1);
        else if (!mostra && i === -1)
            nascoste.push(id);
        Core.Ipc.setSetting("launcher.hiddenCategories", nascoste);
    }

    /// Le categorie fra cui si può scegliere quella d'apertura. Una categoria
    /// nascosta non c'è: il menu si aprirebbe su una voce che nella colonna
    /// non esiste più.
    function opzioniApertura() {
        var o = [
            { "value": "favorites", "label": page.it ? "Preferiti" : "Favourites" },
            { "value": "all",       "label": page.it ? "Tutte" : "All" }
        ];
        // L'elenco può non esserci ancora: questa funzione viene chiamata
        // mentre la pagina si costruisce, e una proprietà dichiarata più sotto
        // a quel punto è `undefined`. Senza la rete, le Impostazioni si
        // aprivano con un avviso e la scelta vuota.
        var tutte = page.categorieMenu || [];
        for (var i = 0; i < tutte.length; i++) {
            var c = tutte[i];
            if (!page.categoriaVisibile(c.id))
                continue;
            o.push({ "value": c.id, "label": page.it ? c.it : c.en });
        }
        return o;
    }

    readonly property var categorieMenu: [
        { "id": "internet",    "it": "Internet",   "en": "Internet" },
        { "id": "development", "it": "Sviluppo",   "en": "Development" },
        { "id": "office",      "it": "Ufficio",    "en": "Office" },
        { "id": "graphics",    "it": "Grafica",    "en": "Graphics" },
        { "id": "media",       "it": "Multimedia", "en": "Media" },
        { "id": "games",       "it": "Giochi",     "en": "Games" },
        { "id": "system",      "it": "Sistema",    "en": "System" },
        { "id": "utility",     "it": "Utility",    "en": "Utility" }
    ]

    // ── La lingua stava anche qui ────────────────────────────────────────
    //
    // C'era una carta «Lingua» identica a quella di «Lingua e regione», con
    // le stesse tre scelte scritte con parole diverse («Automatica
    // (sistema)» contro «Come il sistema»). Scrivevano la stessa chiave,
    // quindi non si contraddicevano mai — ma due posti per la stessa cosa
    // sono due posti da cercare, ed è il difetto che i due livelli e la
    // ricerca esistono per togliere. La casa della lingua è «Ora e lingua ›
    // Lingua e regione»; questa pagina parla del comportamento della barra,
    // dei pannelli e degli avvisi, e la sua sottotitolo lo dice.

    Card {
        heading: page.it ? "Finestre" : "Windows"

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("windowControls")
            description: Core.Strings.t("windowControlsDesc")
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("windowControls.enabled", true)
                onToggled: function(v) { Core.Ipc.setSetting("windowControls.enabled", v); }
            }
        }

        // ── Le spiegazioni sotto ogni interruttore ───────────────────
        //
        // `general.beginnerMode` la leggono `ui/ToggleTile.qml` (le piastrelle
        // della tendina) e `menu/DesktopLayer.qml` (il suggerimento sulla
        // scrivania). Era accesa di fabbrica e non si poteva spegnere da
        // nessuna parte: chi Minerva la conosce si teneva le spiegazioni per
        // sempre.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Spiega le cose sotto ogni interruttore"
                           : "Explain each switch underneath"
            description: page.it
                ? "Le righe di spiegazione nella tendina e il suggerimento "
                  + "sulla scrivania. Chi Minerva la conosce può spegnerle."
                : "The explanation lines in the panel and the desktop hint."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("general.beginnerMode", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("general.beginnerMode", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("animations")
            description: Core.Strings.t("animationsDesc")
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.animations", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("desktop.animations", v);
                    Core.Compositore.animazioni(v);
                }
            }
        }
    }


    // ── Il menu delle applicazioni ───────────────────────────────────────
    Card {
        heading: page.it ? "Menu applicazioni" : "Application menu"

        S.SettingRow {
            width: parent.width
            label: page.it ? "La rotellina cambia categoria"
                           : "Wheel switches category"
            description: page.it
                ? "Girando la rotellina sul menu si passa da una categoria all'altra, invece di doverle cliccare"
                : "Scrolling over the menu moves between categories instead of clicking them"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("launcher.wheelCategories", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("launcher.wheelCategories", v);
                }
            }
        }

        // La sorella della riga qui sopra, e stava nei valori di fabbrica
        // senza un posto da cui toccarla: `AppsPanel.qml` la legge, e chi
        // trovava le categorie che cambiano al solo passaggio del mouse non
        // aveva modo di spegnerle.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Basta passarci sopra"
                           : "Hovering is enough"
            description: page.it
                ? "La categoria cambia al solo passaggio del mouse, senza cliccare"
                : "The category changes on hover, without clicking"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("launcher.hoverCategories", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("launcher.hoverCategories", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Categoria all'apertura" : "Category on opening"
            description: page.it
                ? "Con quale categoria si apre il menu"
                : "Which category the menu opens on"
            controlWidth: 320
            control: S.ChoicePicker {
                value: Core.Ipc.get("launcher.startCategory", "favorites")
                options: page.opzioniApertura()
                onPicked: function(v) {
                    Core.Ipc.setSetting("launcher.startCategory", v);
                }
            }
        }

        // ── Quali categorie si vedono ────────────────────────────────────
        //
        // Il Repeater sta dentro una Column sua: il contenuto della scheda è
        // un alias verso i `data` della sua colonna interna, e un Repeater
        // messo lì dentro ci finisce come oggetto senza che le righe generate
        // entrino nella colonna. Si vedeva come una scheda alta la metà, con
        // le otto voci semplicemente assenti.
        Column {
            width: parent.width
            spacing: Theme.Effects.space3

            Repeater {
                model: page.categorieMenu

                delegate: S.SettingRow {
                    required property var modelData
                    required property int index

                    width: parent.width
                    label: (page.it ? "Mostra «" : "Show “")
                           + (page.it ? modelData.it : modelData.en)
                           + (page.it ? "»" : "”")
                    // Solo la prima porta la spiegazione: otto righe che
                    // dicono la stessa cosa sono otto righe da saltare.
                    description: index === 0
                        ? (page.it
                           ? "Le categorie che non usi spariscono dalla colonna. «Preferiti» e «Tutte» restano sempre."
                           : "Categories you don't use disappear from the column. “Favourites” and “All” always stay.")
                        : ""
                    controlWidth: 60
                    control: S.ToggleSwitch {
                        checked: page.categoriaVisibile(modelData.id)
                        onToggled: function(v) {
                            page.mostraCategoria(modelData.id, v);
                        }
                    }
                }
            }
        }
    }

    // «Non disturbare» stava qui fino al 23 settembre 2026: adesso sta nella
    // pagina Notifiche, con quello che si vede a schermo bloccato.

    Card {
        heading: Core.Strings.t("help")

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("showCheatsheet")
            description: Core.Strings.t("showCheatsheetDesc")
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("cheatsheet.enabled", true)
                onToggled: function(v) { Core.Ipc.setSetting("cheatsheet.enabled", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("showOnFirstRun")
            description: Core.Strings.t("showOnFirstRunDesc")
            controlWidth: 60
            enabled: Core.Ipc.get("cheatsheet.enabled", true)
            opacity: enabled ? 1 : 0.4
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("cheatsheet.showOnFirstRun", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("cheatsheet.showOnFirstRun", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("cheatsheetOpacity")
            description: Core.Strings.t("cheatsheetOpacityDesc")
            controlWidth: 220
            enabled: Core.Ipc.get("cheatsheet.enabled", true)
            opacity: enabled ? 1 : 0.4
            control: S.ValueSlider {
                width: 220
                value: Core.Ipc.get("cheatsheet.backgroundOpacity", 0.55)
                onReleased: function(v) {
                    Core.Ipc.setSetting("cheatsheet.backgroundOpacity",
                                        Math.round(v * 100) / 100);
                }
            }
        }
    }

    Card {
        heading: page.it ? "Scrivania" : "Desktop"

        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("rightClickMenu")
            description: Core.Strings.t("rightClickMenuDesc")
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.rightClickMenu", true)
                onToggled: function(v) { Core.Ipc.setSetting("desktop.rightClickMenu", v); }
            }
        }
    }

    // ── Ripristino ───────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Ripristino" : "Reset"
        note: page.it
              ? "Riporta le preferenze di Minerva com'erano appena installate. "
                + "Non tocca schermo, audio, rete né la tastiera."
              : "Restores Minerva's own preferences to how they were on install. "
                + "Does not touch display, audio, network or keyboard."

        Rectangle {
            id: resetButton
            width: resetText.implicitWidth + Theme.Effects.space5
            height: 34
            radius: Theme.Effects.radiusXS

            // Un secondo clic per confermare: il ripristino cancella ogni
            // personalizzazione, e un dialogo in più si chiude senza leggerlo.
            property bool confirming: false

            color: confirming || resetMouse.containsMouse
                   ? Qt.alpha(Theme.Colors.danger, 0.16) : Theme.Colors.raisedHigh
            border.width: 1
            border.color: confirming ? Theme.Colors.danger : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Text {
                id: resetText
                anchors.centerIn: parent
                text: resetButton.confirming ? Core.Strings.t("resetConfirm")
                                             : Core.Strings.t("reset")
                color: resetButton.confirming || resetMouse.containsMouse
                       ? Theme.Colors.danger : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Timer {
                id: confirmTimeout
                interval: 4000
                onTriggered: resetButton.confirming = false
            }

            MouseArea {
                id: resetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (resetButton.confirming) {
                        Core.Ipc.resetSettings();
                        resetButton.confirming = false;
                        confirmTimeout.stop();
                    } else {
                        resetButton.confirming = true;
                        confirmTimeout.restart();
                    }
                }
            }
        }
    }
}
