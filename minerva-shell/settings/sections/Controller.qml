import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Controller — I pad di gioco, uguali per tutti i giochi.
//
// Il lavoro lo fa il demone (`ControllerService`): quando un pad si accende
// lo affida a InputPlumber, che lo presenta ai giochi come un pad Xbox o
// PlayStation. Questa pagina mostra cosa sta succedendo e, per ogni pad,
// lascia scegliere:
//
//   · il PRESET — cosa vedono i giochi;
//   · «scambia ✕ e ○», per i pad alla giapponese (Giacomo, 4 ottobre 2026:
//     un Battletron identico a quello della PS5, che conferma con ○);
//   · i due colori della barra luminosa, a riposo e mentre un gioco usa il
//     pad;
//   · la mappa dei tasti, che è il preset «Personalizzato».
//
// Le scelte stanno in `input.controllerPad`, una voce per pad con chiave il
// suo indirizzo. La pagina mostra i valori che il demone ha RISOLTO (quelli
// di serie dove non si è scelto niente) e scrive solo quello che si tocca.
Page {
    id: page

    title: page.it ? "Controller" : "Game controllers"
    subtitle: page.it
              ? "Pad e joystick, in ogni gioco e in ogni launcher"
              : "Gamepads, in every game and every launcher"

    readonly property bool it: Core.Strings.lang === "it"

    readonly property bool automatico: Core.Ipc.get("input.controllerAutomatico", true)

    property string motore: ""
    property var pad: []
    property bool inGioco: false
    /// Quale selettore di colore è aperto: «<chiave>|riposo» o «…|gioco».
    property string coloreAperto: ""

    // Ci si iscrive finché la pagina è aperta: un pad acceso, spento o con
    // la batteria che scende si vede senza ricaricare.
    Component.onCompleted: Core.Ipc.iscriviController()
    Component.onDestruction: Core.Ipc.disiscriviController()
    Connections {
        target: Core.Ipc
        function onControllerState(data) {
            page.motore = data.motore || "";
            page.pad = data.pad || [];
            page.inGioco = data.inGioco === true;
        }
    }

    function set(key, value) {
        Core.Ipc.setSetting("input." + key, value);
    }

    /// Cambia una scelta di UN pad senza toccare quelle degli altri.
    function salvaPad(chiave, cambia) {
        var tutti = JSON.parse(JSON.stringify(Core.Ipc.get("input.controllerPad", {}) || {}));
        var mio = tutti[chiave] || {};
        cambia(mio);
        tutti[chiave] = mio;
        Core.Ipc.setSetting("input.controllerPad", tutti);
    }

    // ── I nomi dei tasti ─────────────────────────────────────────────────
    //
    // A sinistra il tasto che si PREME, coi simboli PlayStation stampati sul
    // pad; a destra quello che ARRIVA al gioco, con tutti e due i nomi —
    // il gioco può mostrarli alla Xbox o alla PlayStation.
    readonly property var premuti: ({
        "South": "✕", "East": "○", "West": "□", "North": "△",
        "LeftBumper": "L1", "RightBumper": "R1",
        "LeftStick": "L3", "RightStick": "R3",
        "Select": "Share / Create", "Start": "Options", "Guide": "PS",
        "DPadUp": page.it ? "Croce ↑" : "D-pad ↑",
        "DPadDown": page.it ? "Croce ↓" : "D-pad ↓",
        "DPadLeft": page.it ? "Croce ←" : "D-pad ←",
        "DPadRight": page.it ? "Croce →" : "D-pad →"
    })
    readonly property var arrivi: [
        { "value": "South", "label": "A · ✕" },
        { "value": "East", "label": "B · ○" },
        { "value": "West", "label": "X · □" },
        { "value": "North", "label": "Y · △" },
        { "value": "LeftBumper", "label": "LB · L1" },
        { "value": "RightBumper", "label": "RB · R1" },
        { "value": "LeftStick", "label": "LS · L3" },
        { "value": "RightStick", "label": "RS · R3" },
        { "value": "Select", "label": "View · Share" },
        { "value": "Start", "label": "Menu · Options" },
        { "value": "Guide", "label": "Xbox · PS" },
        { "value": "DPadUp", "label": page.it ? "Croce ↑" : "D-pad ↑" },
        { "value": "DPadDown", "label": page.it ? "Croce ↓" : "D-pad ↓" },
        { "value": "DPadLeft", "label": page.it ? "Croce ←" : "D-pad ←" },
        { "value": "DPadRight", "label": page.it ? "Croce →" : "D-pad →" }
    ]
    readonly property var tasti: ["South", "East", "West", "North", "LeftBumper",
        "RightBumper", "LeftStick", "RightStick", "Select", "Start", "Guide",
        "DPadUp", "DPadDown", "DPadLeft", "DPadRight"]

    Card {
        visible: page.motore === "assente" || page.motore === "spento"
        heading: "InputPlumber"
        note: page.motore === "assente"
              ? (page.it
                 ? "Non è installato: i pad funzionano come prima, ma alcuni giochi (quelli avviati fuori da Steam) potrebbero non vederli, e preset e tasti non si possono cambiare. Installa il pacchetto «inputplumber»."
                 : "Not installed: gamepads work as before, but some games (those launched outside Steam) may not see them, and presets and buttons can't be changed. Install the «inputplumber» package.")
              : (page.it
                 ? "È installato ma spento. Accendilo una volta con «sudo systemctl enable --now inputplumber»."
                 : "Installed but not running. Turn it on once with «sudo systemctl enable --now inputplumber».")
    }

    Card {
        heading: page.it ? "Compatibilità" : "Compatibility"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Pad uguali in tutti i giochi" : "Same gamepad in every game"
            description: page.it
                         ? "Ogni pad che colleghi diventa un pad virtuale che tutti i giochi capiscono, anche quelli di Faugus, Heroic e Lutris"
                         : "Every gamepad you connect becomes a virtual one that every game understands, including Faugus, Heroic and Lutris"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.automatico
                onToggled: function(v) { page.set("controllerAutomatico", v); }
            }
        }
    }

    Card {
        visible: page.pad.length === 0
        heading: page.it ? "Pad collegati" : "Connected gamepads"
        note: page.it ? "Nessun pad collegato. Accendine uno, via cavo o Bluetooth."
                      : "No gamepad connected. Turn one on, wired or Bluetooth."
    }

    // ── Un riquadro per pad ──────────────────────────────────────────────

    Repeater {
        model: page.pad

        delegate: Card {
            id: scheda
            required property var modelData
            readonly property string chiave: modelData.chiave
            readonly property var mappa: modelData.mappa || {}
            enabled: modelData.gestito === true

            width: parent ? parent.width : 0
            heading: modelData.nome
                     + (modelData.collegamento === "bluetooth" ? " · Bluetooth"
                        : modelData.collegamento === "usb" ? " · USB" : "")
                     + (modelData.batteria !== null && modelData.batteria !== undefined
                        ? " · " + modelData.batteria + "%" : "")
            note: !page.automatico
                  ? (page.it ? "La compatibilità è spenta: preset e tasti valgono solo quando è accesa."
                             : "Compatibility is off: presets and buttons only apply when it is on.")
                  : modelData.gestito
                    ? (page.it ? "Pronto per tutti i giochi." : "Ready for every game.")
                  : (page.it
                     ? "InputPlumber non ha preso in carico questo pad: i controlli sono disattivati. Verifica che il servizio sia attivo e che il dispositivo sia supportato; scollega e ricollega il pad dopo aver avviato InputPlumber."
                     : "InputPlumber has not claimed this gamepad, so its controls are disabled. Check that the service is running and the device is supported; reconnect the gamepad after starting InputPlumber.")

            S.SettingRow {
                width: parent.width
                label: page.it ? "Preset" : "Preset"
                description: scheda.modelData.preset === "playstation"
                             ? (page.it ? "I giochi vedono un DualSense: simboli PlayStation, barra luminosa e touchpad"
                                        : "Games see a DualSense: PlayStation symbols, light bar and touchpad")
                             : scheda.modelData.preset === "personalizzato"
                               ? (page.it ? "I giochi vedono un pad Xbox, con i tasti scelti qui sotto"
                                          : "Games see an Xbox pad, with the buttons chosen below")
                               : (page.it ? "I giochi vedono un pad Xbox: ✕ è A, ○ è B. Va bene quasi ovunque"
                                          : "Games see an Xbox pad: ✕ is A, ○ is B. Works almost everywhere")
                controlWidth: 340
                control: S.ChoicePicker {
                    value: scheda.modelData.preset
                    options: [
                        { "value": "xbox", "label": "Xbox" },
                        { "value": "playstation", "label": "PlayStation" },
                        { "value": "personalizzato", "label": page.it ? "Personalizzato" : "Custom" }
                    ]
                    onPicked: function(v) {
                        page.salvaPad(scheda.chiave, function(c) { c.preset = v; });
                    }
                }
            }

            S.SettingRow {
                width: parent.width
                label: page.it ? "Scambia ✕ e ○" : "Swap ✕ and ○"
                description: page.it
                             ? "Per i pad alla giapponese, dove si conferma con ○"
                             : "For Japanese-style pads, where ○ confirms"
                controlWidth: 60
                control: S.ToggleSwitch {
                    checked: scheda.modelData.scambiaXO === true
                    onToggled: function(v) {
                        page.salvaPad(scheda.chiave, function(c) { c.scambiaXO = v; });
                    }
                }
            }

            // ── I colori ─────────────────────────────────────────────────

            Repeater {
                model: scheda.modelData.led ? ["riposo", "gioco"] : []

                delegate: Column {
                    id: colore
                    required property string modelData
                    readonly property string campo: modelData === "riposo" ? "ledRiposo" : "ledGioco"
                    readonly property string aperto: scheda.chiave + "|" + modelData
                    width: parent.width
                    spacing: Theme.Effects.space2

                    S.SettingRow {
                        width: parent.width
                        label: colore.modelData === "riposo"
                               ? (page.it ? "Colore normale" : "Normal color")
                               : (page.it ? "Colore in gioco" : "In-game color")
                        description: colore.modelData === "riposo"
                                     ? (page.it ? "Quando nessun gioco usa il pad"
                                                : "When no game is using the pad")
                                     : (page.it ? "Quando un gioco ha riconosciuto il pad"
                                                  + (page.inGioco ? " — adesso" : "")
                                                : "When a game has picked up the pad"
                                                  + (page.inGioco ? " — now" : ""))
                        controlWidth: 60
                        control: Rectangle {
                            width: 44; height: 26
                            radius: Theme.Effects.radiusSM
                            color: scheda.modelData[colore.campo]
                            border.width: page.coloreAperto === colore.aperto ? 2 : 1
                            border.color: page.coloreAperto === colore.aperto
                                          ? Theme.Colors.accent : Theme.Colors.textFaint
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.coloreAperto =
                                    page.coloreAperto === colore.aperto ? "" : colore.aperto
                            }
                        }
                    }

                    S.SelettoreColore {
                        width: parent.width
                        visible: page.coloreAperto === colore.aperto
                        valore: scheda.modelData[colore.campo]
                        onScelto: function(c) {
                            var hex = String(c).substring(0, 7);
                            page.salvaPad(scheda.chiave, function(conf) { conf[colore.campo] = hex; });
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: scheda.modelData.led && scheda.modelData.ledScrivibile === false
                wrapMode: Text.WordWrap
                text: page.it
                      ? "Il sistema non lascia cambiare i colori: rilancia install-minerva.sh, che installa la regola per i LED dei pad."
                      : "The system won't let the colors change: run install-minerva.sh again, it installs the gamepad LED rule."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── I tasti ──────────────────────────────────────────────────
            //
            // Si vedono col preset «Personalizzato». Cambiare un tasto con
            // un altro preset lo fa diventare «Personalizzato» da sé: è la
            // stessa cosa detta col gesto invece che con la scelta.

            Repeater {
                model: scheda.modelData.preset === "personalizzato" ? page.tasti : []

                delegate: S.SettingRow {
                    id: riga
                    required property string modelData
                    width: parent.width
                    label: page.premuti[riga.modelData]
                    controlWidth: 200
                    control: S.Tendina {
                        width: 200
                        value: scheda.mappa[riga.modelData] || riga.modelData
                        options: page.arrivi
                        onPicked: function(v) {
                            page.salvaPad(scheda.chiave, function(c) {
                                c.preset = "personalizzato";
                                c.mappa = c.mappa || {};
                                if (v === riga.modelData)
                                    delete c.mappa[riga.modelData];
                                else
                                    c.mappa[riga.modelData] = v;
                            });
                        }
                    }
                }
            }
        }
    }
}
