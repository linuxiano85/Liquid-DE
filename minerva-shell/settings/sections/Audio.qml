import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Audio — Dove esce il suono, da dove entra, e quanto forte.
//
// L'elenco arriva da `pactl`. I nomi tecnici delle schede audio sono
// illeggibili (`alsa_output.pci-0000_00_1f.3.analog-stereo`), quindi si mostra
// la descrizione — che è quella che il produttore ha scritto per gli umani —
// e il nome tecnico resta solo come chiave interna.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Audio" : "Sound"
    subtitle: Core.Strings.lang === "it"
              ? "Altoparlanti, microfono e volumi"
              : "Speakers, microphone and volumes"

    readonly property bool it: Core.Strings.lang === "it"

    property var sinks: []
    property var sources: []
    property string defaultSink: ""
    property string defaultSource: ""

    property var hdmi: []
    property string audioError: ""
    property bool selecting: false
    // Si chiede lo stato E ci si iscrive ai cambiamenti: quello che PipeWire
    // annuncia (cuffie inserite, HDMI collegato) arriva da solo finché la
    // pagina è aperta, e alla chiusura ci si disiscrive — vedi
    // `Core.Ipc.iscriviAudio`.
    Component.onCompleted: { Core.Ipc.iscriviAudio(); refresh(); }
    Component.onDestruction: Core.Ipc.disiscriviAudio()
    Connections {
        target: Core.Ipc
        function onSystemAudioState(data) { page.takeState(data); }
        function onSystemAudioSelected(data) {
            page.selecting = false;
            page.takeState(data);
            if (data.state) page.takeState(data.state, true);
        }
        function onAzioneFallita(action, why) {
            if (action === "system_audio_select" || action === "system_audio_state") {
                page.selecting = false; page.audioError = why;
            }
        }
    }
    function takeState(data, preserveError) {
        if (!preserveError) page.audioError = data.ok ? (data.warning || "") : (data.error || "Audio non disponibile");
        if (!data.ok) return;
        page.sinks = (data.sinks || []).map(function(s) { return {name: s.name, label: s.description || s.name}; });
        page.sources = (data.sources || []).map(function(s) { return {name: s.name, label: s.description || s.name}; });
        page.hdmi = data.hdmi || [];
        page.defaultSink = data.defaultSink || "";
        page.defaultSource = data.defaultSource || "";
    }
    function refresh() { Core.Ipc.send({action: "system_audio_state"}); }
    function selectAudio(request) {
        if (page.selecting) return;
        page.selecting = true;
        request.action = "system_audio_select";
        Core.Ipc.send(request);
    }
    function pretty(name) {
        if (!name)
            return "";
        var s = name;
        s = s.replace(/^alsa_(output|input)\./, "");
        s = s.replace(/^bluez_(output|input)\./, "Bluetooth ");
        s = s.replace(/pci-[0-9_]+\./, "");
        s = s.replace(/usb-[^.]+\./, "USB ");
        s = s.replace(/[._-]+/g, " ").trim();
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function setDefault(kind, name) { selectAudio({kind: kind, name: name}); }

    Card {
        visible: page.audioError !== ""
        heading: page.it ? "Stato audio" : "Audio status"
        note: page.audioError
    }
    Card {
        visible: page.hdmi.length > 0
        heading: "HDMI / DisplayPort"
        note: page.it ? "Scegli l’uscita del monitor. Il profilo audio viene attivato se necessario."
                      : "Choose the monitor output. Its audio profile is activated if needed."
        Repeater {
            model: page.hdmi
            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: modelData.label
                description: modelData.available ? "" : (page.it ? "Non collegato" : "Disconnected")
                control: Ui.SpineButton {
                    tooltip: page.it ? "Usa questa uscita" : "Use this output"
                    content: Text { text: page.it ? "Seleziona" : "Select"; color: Theme.Colors.text }
                    enabled: modelData.available && !page.selecting
                    onClicked: page.selectAudio({kind: "sink", card: modelData.card,
                        profile: modelData.profile, port: modelData.port})
                }
            }
        }
    }

    // ── Volume ───────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Volume" : "Volume"

        Ui.Slider {
            width: parent.width
            icon: Core.SystemState.muted || Core.SystemState.volume === 0
                  ? "muted" : "volume"
            value: Core.SystemState.volume
            accent: Core.SystemState.muted ? Theme.Colors.textFaint : Theme.Colors.accent
            onMoved: function(v) { Core.SystemState.setVolume(v); }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Silenzia" : "Mute"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.SystemState.muted
                onToggled: function(v) { Core.SystemState.toggleMute(); }
            }
        }
    }

    // ── Uscita ───────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Uscita" : "Output"
        note: page.it
              ? "Cambiando uscita, anche ciò che sta già suonando si sposta."
              : "Changing the output also moves whatever is already playing."

        Repeater {
            model: page.sinks

            delegate: Rectangle {
                id: sink
                required property var modelData

                readonly property bool current: page.defaultSink === modelData.name

                width: parent.width
                height: 44
                radius: Theme.Effects.radiusSM
                color: current ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : sinkMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    id: sinkIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17; height: 17
                    name: sink.modelData.name.indexOf("bluez") !== -1 ? "bluetooth" : "volume"
                    color: sink.current ? Theme.Colors.accent : Theme.Colors.textFaint
                }

                Text {
                    anchors.left: sinkIcon.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: sinkCheck.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: page.pretty(sink.modelData.label)
                    color: sink.current ? Theme.Colors.text : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Ui.Icon {
                    id: sinkCheck
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15; height: 15
                    name: "check"
                    visible: sink.current
                    color: Theme.Colors.accent
                }

                MouseArea {
                    id: sinkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setDefault("sink", sink.modelData.name)
                }
            }
        }

        Text {
            width: parent.width
            visible: page.sinks.length === 0
            text: page.it ? "Nessun dispositivo di uscita trovato."
                          : "No output device found."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── Ingresso ─────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Microfono" : "Microphone"
        visible: page.sources.length > 0

        Repeater {
            model: page.sources

            delegate: Rectangle {
                id: src
                required property var modelData

                readonly property bool current: page.defaultSource === modelData.name

                width: parent.width
                height: 44
                radius: Theme.Effects.radiusSM
                color: current ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : srcMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: srcCheck.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: page.pretty(src.modelData.label)
                    color: src.current ? Theme.Colors.text : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Ui.Icon {
                    id: srcCheck
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15; height: 15
                    name: "check"
                    visible: src.current
                    color: Theme.Colors.accent
                }

                MouseArea {
                    id: srcMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setDefault("source", src.modelData.name)
                }
            }
        }
    }

    // ── La voce di Minerva ───────────────────────────────────────────────

    Card {
        heading: page.it ? "Suoni di Minerva" : "Minerva sounds"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Suono quando regoli il volume"
                           : "A sound when you change the volume"
            description: page.it
                ? "Una nota che sale col volume: dice a che punto sei senza guardare lo schermo. Al massimo cambia, per dire che oltre non si va"
                : "A note that rises with the volume: it tells you where you are without looking. At the top it changes, to say there is no further"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("audio.feedbackSounds", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("audio.feedbackSounds", v);
                    // Si prova subito: un interruttore per un suono che non
                    // fa sentire il suono è un interruttore da provare a caso.
                    if (v)
                        Core.Sounds.volumeStep(Core.SystemState.volume);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Quanto forte" : "How loud"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0.05
                to: 1.0
                value: Core.Ipc.get("audio.feedbackVolume", 0.4)
                onReleased: function(v) {
                    Core.Ipc.setSetting("audio.feedbackVolume",
                                        Math.round(v * 100) / 100);
                    Core.Sounds.volumeStep(Core.SystemState.volume);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Lascia superare il 100%" : "Allow going over 100%"
            description: page.it
                ? "Oltre il 100% non c'è più volume da dare: c'è amplificazione, e con lei la distorsione. Spento, il massimo è cento"
                : "Past 100% there is no more volume to give: there is amplification, and distortion with it. Off, the maximum is one hundred"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("audio.allowOverdrive", false)
                onToggled: function(v) {
                    Core.Ipc.setSetting("audio.allowOverdrive", v);
                }
            }
        }
    }
}
