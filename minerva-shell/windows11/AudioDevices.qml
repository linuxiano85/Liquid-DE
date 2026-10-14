import "../core" as Core
import "../ui" as Ui
import QtQuick
import Quickshell.Services.Pipewire

FocusScope {
    id: page

    property string defaultSink: ""
    property string audioError: ""
    property bool loading: true
    property bool selecting: false
    property bool subscribed: false
    readonly property int deviceCount: devices.count
    readonly property real scrollY: outputs.contentY
    readonly property real scrollMaximum: Math.max(0, outputs.contentHeight - outputs.height)
    readonly property var playbackStreams: Pipewire.nodes.values.filter(function(node) {
        // In Quickshell AudioOutStream ha il flag Sink: usare il tipo
        // esplicito evita di mostrare i flussi di registrazione al suo posto.
        return node.type === PwNodeType.AudioOutStream;
    })
    // Si legano soltanto i flussi di riproduzione mentre la pagina esiste:
    // nessuna lettura del microfono e nessuna iscrizione a pannello chiuso.
    PwObjectTracker {
        objects: page.playbackStreams
    }

    signal backRequested()
    signal settingsRequested()

    // L'iscrizione vive quanto questa pagina: il pannello chiuso non mantiene
    // processi pactl né richieste periodiche. Il demone conferma ogni cambio.
    function refresh() {
        if (!Core.Ipc.connected)
            return ;

        if (!subscribed) {
            Core.Ipc.iscriviAudio();
            subscribed = true;
        }
        loading = true;
        audioError = "";
        deadline.restart();
        Core.Ipc.send({
            "action": "system_audio_state"
        });
    }

    function takeState(data, preserveError) {
        if (!data.ok) {
            audioError = data.error || Style.label("Audio non disponibile", "Audio unavailable");
            loading = false;
            if (!selecting)
                deadline.stop();

            return ;
        }
        if (!preserveError && !selecting)
            audioError = data.warning || "";

        var incoming = (data.sinks || []).filter(function(s) {
            return typeof s.name === "string" && s.name !== "";
        });
        // Le righe sopravvivono agli aggiornamenti: un evento di hotplug non
        // deve distruggere il pulsante sotto il mouse o rubare il fuoco.
        for (var i = devices.count - 1; i >= 0; i--) {
            var oldName = devices.get(i).name;
            if (!incoming.some(function(s) {
                return s.name === oldName;
            }))
                devices.remove(i);

        }
        for (var n = 0; n < incoming.length; n++) {
            var sink = incoming[n];
            var at = -1;
            for (var j = 0; j < devices.count; j++) {
                if (devices.get(j).name === sink.name)
                    at = j;

            }
            var row = {
                "name": sink.name,
                "label": sink.description || sink.name
            };
            if (at < 0)
                devices.append(row);
            else
                devices.set(at, row);
        }
        defaultSink = data.defaultSink || "";
        loading = false;
        if (!selecting)
            deadline.stop();

    }

    function selectDevice(name) {
        if (loading || selecting || !Core.Ipc.connected)
            return ;

        if (name === defaultSink)
            return ;

        selecting = true;
        audioError = "";
        deadline.restart();
        Core.Ipc.send({
            "action": "system_audio_select",
            "kind": "sink",
            "name": name
        });
    }

    function focusDevice(index) {
        if (devices.count === 0)
            return ;

        outputs.currentIndex = Math.max(0, Math.min(devices.count - 1, index));
        outputs.positionViewAtIndex(outputs.currentIndex, ListView.Contain);
        Qt.callLater(function() {
            var item = outputs.itemAtIndex(outputs.currentIndex);
            if (item)
                item.forceActiveFocus(Qt.TabFocusReason);

        });
    }

    objectName: "windowsAudioPage"
    Component.onCompleted: {
        refresh();
        Qt.callLater(function() {
            back.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    Component.onDestruction: {
        if (subscribed)
            Core.Ipc.disiscriviAudio();

    }

    Connections {
        function onConnectedChanged() {
            if (Core.Ipc.connected) {
                page.refresh();
            } else {
                page.subscribed = false;
                page.loading = true;
                page.selecting = false;
                page.audioError = Style.label("Servizio audio disconnesso", "Audio service disconnected");
                deadline.stop();
            }
        }

        function onSystemAudioState(data) {
            page.takeState(data);
        }

        function onSystemAudioSelected(data) {
            page.selecting = false;
            deadline.stop();
            page.audioError = data.ok ? (data.warning || "") : (data.error || Style.label("Cambio uscita non riuscito", "Could not change output"));
            page.takeState(data, true);
            if (data.state)
                page.takeState(data.state, true);

        }

        function onAzioneFallita(action, why) {
            if (action !== "system_audio_select" && action !== "system_audio_state")
                return ;

            deadline.stop();
            page.selecting = false;
            page.loading = false;
            page.audioError = why;
        }

        target: Core.Ipc
    }

    Timer {
        id: deadline

        interval: 10000
        onTriggered: {
            page.loading = false;
            page.selecting = false;
            page.audioError = Style.label("Il servizio audio non risponde. Riprova.", "The audio service is not responding. Try again.");
        }
    }

    ListModel {
        id: devices
    }

    Button {
        id: back

        objectName: "windowsAudioBack"
        x: 16
        y: 16
        tooltip: Style.label("Indietro", "Back")
        onClicked: page.backRequested()

        Glyph {
            anchors.centerIn: parent
            width: 18
            height: 18
            name: "chevronRight"
            color: Style.text
            alwaysDrawn: true
            rotation: 180
        }

    }

    Text {
        x: 64
        y: 25
        width: parent.width - 80
        text: Style.label("Uscita audio", "Sound output")
        color: Style.text
        font.family: Style.font
        font.pixelSize: 16 * Style.textScale
        font.weight: Font.DemiBold
    }

    Text {
        id: status

        x: 24
        y: 66
        width: parent.width - 48
        text: page.audioError || (page.loading ? Style.label("Caricamento…", "Loading…") : Style.label("Scegli dove riprodurre l’audio", "Choose where to play sound"))
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: page.audioError ? Style.text : Style.muted
        font.family: Style.font
        font.pixelSize: 12 * Style.textScale
    }

    ListView {
        id: outputs
        objectName: "windowsAudioOutputList"

        x: 16
        y: status.y + status.height + 12
        width: parent.width - 50
        height: Math.max(0, footer.y - y - 12)
        clip: true
        spacing: 4
        model: devices
        footer: AudioMixer {
            width: outputs.width
            streams: page.playbackStreams
            viewport: outputs
        }
        boundsBehavior: Flickable.StopAtBounds

        header: Item {
            width: outputs.width
            height: !page.loading && devices.count === 0 ? 40 : 0
            visible: height > 0
            Text {
                anchors.centerIn: parent
                text: Style.label("Nessuna uscita disponibile", "No output available")
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 12 * Style.textScale
            }
        }

        delegate: Button {
            required property string name
            required property string label
            required property int index

            objectName: "windowsAudioSink-" + name
            width: outputs.width
            height: Math.max(48, caption.implicitHeight + 20)
            selected: page.defaultSink === name
            enabled: !page.loading && !page.selecting && Core.Ipc.connected
            tooltip: label
            Accessible.name: label
            Accessible.role: Accessible.RadioButton
            Accessible.checked: selected
            onClicked: page.selectDevice(name)
            Keys.onDownPressed: page.focusDevice(index + 1)
            Keys.onUpPressed: {
                if (index === 0)
                    back.forceActiveFocus(Qt.TabFocusReason);
                else
                    page.focusDevice(index - 1);
            }

            Glyph {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                name: parent.name.indexOf("bluez") >= 0 ? "bluetooth" : "volume"
                color: Style.text
                alwaysDrawn: true
            }

            Text {
                id: caption

                x: 44
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 80
                text: parent.label
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Style.text
                font.family: Style.font
                font.pixelSize: 13 * Style.textScale
            }

            Glyph {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                name: "check"
                color: Style.accentIndicator
                alwaysDrawn: true
                visible: parent.selected
            }

        }

    }

    Ui.Scorrimento {
        objectName: "windowsAudioScrollBar"
        bersaglio: outputs
        tinta: Style.muted
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.top: outputs.top
        anchors.bottom: outputs.bottom
    }

    Rectangle {
        id: footer

        anchors.bottom: parent.bottom
        width: parent.width
        height: 56
        color: Style.pannelloPiede

        Button {
            objectName: "windowsAudioRetry"
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: Style.label("Riprova", "Retry")
            visible: page.audioError !== ""
            enabled: !page.loading && !page.selecting && Core.Ipc.connected
            onClicked: page.refresh()
        }

        Button {
            objectName: "windowsAudioSettings"
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            icon: "settings"
            tooltip: Style.label("Altre impostazioni audio", "More sound settings")
            onClicked: page.settingsRequested()
        }

    }

}
