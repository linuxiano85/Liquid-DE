import QtQuick
import Quickshell.Services.Pipewire
import "../../core" as Core
import "../../windows11" as W
import ".." as S

// Audio nativo: la selezione viene confermata dal demone; i livelli arrivano
// da PipeWire senza interrogazioni periodiche e senza registrare il microfono.
PaginaWindows {
    id: pagina
    objectName: "impostazioniAudioWindows"
    briciole: [
        {testo: W.Style.label("Sistema", "System"), pagina: "w-sistema"},
        {testo: W.Style.label("Audio", "Sound")}
    ]
    property string defaultSink: ""
    property string defaultSource: ""
    property string audioError: ""
    property bool selecting: false
    property bool loading: true
    property bool subscribed: false
    property var hdmi: []
    property real feedbackPending: 40
    readonly property PwNode microphone: Pipewire.defaultAudioSource
    readonly property var streams: mixerEspansore.aperto ? Pipewire.nodes.values.filter(function(node) {
        return node.type === PwNodeType.AudioOutStream;
    }) : []
    ListModel { id: sinks }
    ListModel { id: sources }
    PwObjectTracker { objects: [pagina.microphone].concat(pagina.streams) }

    function updateDevices(model, incoming) {
        var devices = (incoming || []).filter(function(item) { return item.name; });
        for (var i = model.count - 1; i >= 0; i--) {
            var name = model.get(i).name;
            if (!devices.some(function(item) { return item.name === name; }))
                model.remove(i);
        }
        devices.forEach(function(item) {
            var row = {name: item.name, label: item.description || item.name};
            for (var j = 0; j < model.count; j++) {
                if (model.get(j).name === item.name) {
                    model.set(j, row);
                    return;
                }
            }
            model.append(row);
        });
    }
    function takeState(data, preserveError) {
        if (!data.ok) {
            audioError = data.error || W.Style.label("Audio non disponibile", "Audio unavailable");
            loading = false;
            return;
        }
        if (!preserveError)
            audioError = data.warning || "";
        updateDevices(sinks, data.sinks);
        updateDevices(sources, data.sources);
        hdmi = (data.hdmi || []).filter(function(item) { return item.available; });
        defaultSink = data.defaultSink || "";
        defaultSource = data.defaultSource || "";
        loading = false;
    }
    function refresh() {
        if (!Core.Ipc.connected)
            return;
        if (!subscribed) {
            Core.Ipc.iscriviAudio();
            subscribed = true;
        }
        loading = true;
        audioError = "";
        deadline.restart();
        Core.Ipc.send({action: "system_audio_state"});
    }
    function selectAudio(request) {
        if (selecting || loading || !Core.Ipc.connected)
            return;
        selecting = true;
        audioError = "";
        request.action = "system_audio_select";
        deadline.restart();
        Core.Ipc.send(request);
    }
    Timer {
        id: deadline
        interval: 10000
        onTriggered: {
            pagina.loading = false;
            pagina.selecting = false;
            pagina.audioError = W.Style.label("Il servizio audio non risponde. Riprova.", "The audio service is not responding. Try again.");
        }
    }
    Timer {
        id: saveFeedback
        interval: 150
        onTriggered: Core.Ipc.setSetting("audio.feedbackVolume", pagina.feedbackPending / 100)
    }
    Component.onCompleted: refresh()
    Component.onDestruction: {
        if (subscribed)
            Core.Ipc.disiscriviAudio();
        if (saveFeedback.running)
            Core.Ipc.setSetting("audio.feedbackVolume", feedbackPending / 100);
    }
    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (Core.Ipc.connected) {
                pagina.refresh();
            } else {
                pagina.subscribed = false;
                pagina.loading = false;
                pagina.selecting = false;
                deadline.stop();
                pagina.audioError = W.Style.label("Servizio audio disconnesso", "Audio service disconnected");
            }
        }
        function onSystemAudioState(data) {
            pagina.takeState(data, pagina.selecting);
            if (!pagina.selecting)
                deadline.stop();
        }
        function onSystemAudioSelected(data) {
            pagina.selecting = false;
            pagina.takeState(data);
            if (data.state)
                pagina.takeState(data.state, true);
            deadline.stop();
        }
        function onAzioneFallita(action, why) {
            if (action !== "system_audio_select" && action !== "system_audio_state")
                return;
            pagina.selecting = false;
            pagina.loading = false;
            pagina.audioError = why;
            deadline.stop();
        }
    }

    SchedaImpostazione {
        visible: pagina.audioError !== "" || pagina.loading || pagina.selecting
        titolo: pagina.audioError !== "" ? W.Style.label("Stato audio", "Audio status")
            : pagina.selecting ? W.Style.label("Cambio dispositivo…", "Changing device…")
            : W.Style.label("Caricamento dispositivi…", "Loading devices…")
        descrizione: pagina.audioError
        PulsanteWindows {
            objectName: "audioRiprova"
            testo: W.Style.label("Riprova", "Retry")
            enabled: !pagina.loading && !pagina.selecting
            onPremuto: pagina.refresh()
        }
    }
    GruppoImpostazioni { testo: W.Style.label("Output", "Output") }
    Repeater {
        model: sinks
        delegate: Dispositivo {
            required property string name
            required property string label
            objectName: "audioOutput-" + name
            titolo: label
            kind: "sink"
            deviceName: name
            selectedDevice: pagina.defaultSink === name
        }
    }
    SchedaImpostazione {
        visible: !pagina.loading && sinks.count === 0
        titolo: W.Style.label("Nessun dispositivo di output trovato", "No output devices found")
    }
    SchedaImpostazione {
        titolo: W.Style.label("Volume", "Volume")
        icona: "volume"
        W.VolumeSlider {
            objectName: "audioVolumeOutput"
            width: 250
            opacity: enabled ? 1 : 0.45
            enabled: Core.SystemState.sink && Core.SystemState.sink.audio
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Disattiva audio", "Mute")
        S.ToggleSwitch {
            objectName: "audioMuteOutput"
            enabled: Core.SystemState.sink && Core.SystemState.sink.audio
            checked: Core.SystemState.muted
            onToggled: Core.SystemState.toggleMute()
        }
    }
    Repeater {
        model: pagina.hdmi
        delegate: SchedaImpostazione {
            required property var modelData
            titolo: modelData.label
            descrizione: "HDMI / DisplayPort"
            PulsanteWindows {
                testo: W.Style.label("Seleziona", "Select")
                enabled: !pagina.selecting && !pagina.loading
                onPremuto: pagina.selectAudio({kind: "sink", card: modelData.card,
                    profile: modelData.profile, port: modelData.port})
            }
        }
    }
    GruppoImpostazioni { testo: W.Style.label("Input", "Input") }
    Repeater {
        model: sources
        delegate: Dispositivo {
            required property string name
            required property string label
            objectName: "audioInput-" + name
            titolo: label
            kind: "source"
            deviceName: name
            selectedDevice: pagina.defaultSource === name
        }
    }
    SchedaImpostazione {
        visible: !pagina.loading && sources.count === 0
        titolo: W.Style.label("Nessun dispositivo di input trovato", "No input devices found")
    }
    SchedaImpostazione {
        titolo: W.Style.label("Volume di input", "Input volume")
        W.VolumeSlider {
            objectName: "audioVolumeInput"
            width: 250
            from: 0
            to: 100
            opacity: enabled ? 1 : 0.45
            Accessible.name: W.Style.label("Volume di input", "Input volume") + ": " + Math.round(value) + "%"
            enabled: pagina.microphone && pagina.microphone.audio
            value: enabled ? pagina.microphone.audio.volume * 100 : 0
            changeVolume: function(percent) {
                if (enabled)
                    pagina.microphone.audio.volume = Math.max(0, Math.min(100, percent)) / 100;
            }
        }
    }
    GruppoImpostazioni { testo: W.Style.label("Avanzate", "Advanced") }
    EspansoreImpostazione {
        id: mixerEspansore
        objectName: "audioMixerEspansore"
        titolo: W.Style.label("Mixer volume", "Volume mixer")
        descrizione: W.Style.label("Volume delle app in riproduzione", "Volume for playing apps")
        W.AudioMixer { width: parent.width; streams: pagina.streams }
    }
    GruppoImpostazioni { testo: "Liquid" }
    EspansoreImpostazione {
        objectName: "audioLiquidOptions"
        titolo: W.Style.label("Suoni di Liquid", "Liquid sounds")
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Suono quando regoli il volume", "A sound when you change the volume")
            S.ToggleSwitch {
                objectName: "audioFeedback"
                checked: Core.Ipc.get("audio.feedbackSounds", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("audio.feedbackSounds", v);
                    if (v)
                        Core.Sounds.volumeStep(Core.SystemState.volume);
                }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Volume del suono di conferma", "Feedback sound volume")
            W.VolumeSlider {
                width: 220
                from: 5
                to: 100
                value: Core.Ipc.get("audio.feedbackVolume", 0.4) * 100
                changeVolume: function(percent) {
                    pagina.feedbackPending = Math.round(percent);
                    saveFeedback.restart();
                }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Consenti di superare il 100%", "Allow volume above 100%")
            S.ToggleSwitch {
                objectName: "audioOverdrive"
                checked: Core.Ipc.get("audio.allowOverdrive", false)
                onToggled: function(v) { Core.Ipc.setSetting("audio.allowOverdrive", v); }
            }
        }
    }
    component Dispositivo: SchedaImpostazione {
        property string kind: "sink"
        property string deviceName: ""
        property bool selectedDevice: false
        porta: true
        mostraFreccia: false
        enabled: !pagina.loading && Core.Ipc.connected
        descrizione: selectedDevice ? W.Style.label("Dispositivo predefinito", "Default device") : ""
        Accessible.role: Accessible.RadioButton
        Accessible.checkable: true
        Accessible.checked: selectedDevice
        Accessible.onPressAction: if (enabled) attivata()
        Accessible.onToggleAction: if (enabled) attivata()
        onAttivata: pagina.selectAudio({kind: kind, name: deviceName})
        Rectangle {
            width: 20
            height: 20
            radius: 10
            color: "transparent"
            border.width: selectedDevice ? 5 : 1
            border.color: selectedDevice ? W.Style.accent : W.Style.muted
        }
    }
}
