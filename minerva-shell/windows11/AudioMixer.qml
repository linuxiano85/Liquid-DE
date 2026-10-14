import QtQuick
import "../core" as Core

Column {
    id: mixer
    objectName: "windowsAudioMixer"
    property var streams: []
    property var viewport: null
    readonly property int streamCount: rows.count
    spacing: 12
    function reveal(item) {
        if (!viewport)
            return;
        var top = item.mapToItem(viewport.contentItem, 0, 0).y;
        var nextY = viewport.contentY;
        if (top < nextY)
            nextY = top;
        else if (top + item.height > nextY + viewport.height)
            nextY = top + item.height - viewport.height;
        viewport.contentY = Math.max(viewport.originY,
            Math.min(nextY, viewport.originY + Math.max(0, viewport.contentHeight - viewport.height)));
    }

    // Le righe seguono il nodo, non il nome dell'app: due flussi con lo
    // stesso titolo non devono condividere un cursore o perdere il fuoco.
    function updateRows() {
        for (var i = rows.count - 1; i >= 0; i--) {
            var oldNode = rows.get(i).node;
            if (streams.indexOf(oldNode) < 0)
                rows.remove(i);
        }
        streams.forEach(function(node) {
            for (var j = 0; j < rows.count; j++) {
                if (rows.get(j).node === node)
                    return;
            }
            rows.append({node: node});
        });
    }
    onStreamsChanged: updateRows()
    Component.onCompleted: updateRows()
    ListModel {
        id: rows
        dynamicRoles: true
    }
    Rectangle {
        width: parent.width
        height: 1
        color: Style.edge
    }
    Text {
        x: 8
        text: Style.label("Mixer volume", "Volume mixer")
        color: Style.text
        font.family: Style.font
        font.pixelSize: 13 * Style.textScale
        font.weight: Font.DemiBold
    }
    Text {
        x: 8
        width: parent.width - 16
        visible: rows.count === 0
        text: Style.label("Le app che riproducono audio compariranno qui.", "Apps playing sound will appear here.")
        wrapMode: Text.WordWrap
        color: Style.muted
        font.family: Style.font
        font.pixelSize: 12 * Style.textScale
    }
    Repeater {
        id: streamRows
        model: rows
        delegate: Item {
            id: row
            property alias volumeControl: volumeSlider
            required property var node
            readonly property bool available: node && node.ready && node.audio
            readonly property string appLabel: available
                ? String(node.properties["application.name"] || node.description || node.name)
                : Style.label("Caricamento…", "Loading…")
            readonly property string mediaLabel: available
                ? String(node.properties["media.name"] || "") : ""
            objectName: "windowsAudioStream-" + (node ? node.id : "")
            width: mixer.width
            height: 94
            Text {
                objectName: "windowsAudioStreamLabel-" + (row.node ? row.node.id : "")
                x: 8
                width: parent.width - 16
                text: row.appLabel
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Style.text
                font.family: Style.font
                font.pixelSize: 13 * Style.textScale
            }
            Text {
                x: 8
                y: 21
                width: parent.width - 16
                text: row.mediaLabel
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 11 * Style.textScale
            }
            Button {
                objectName: "windowsAudioStreamMute-" + (row.node ? row.node.id : "")
                x: 0
                y: 43
                enabled: row.available
                icon: row.available && row.node.audio.muted ? "muted" : "volume"
                // Nessun metadato esterno nel tooltip AutoText comune.
                tooltip: Style.label("Attiva o disattiva l'audio", "Mute or unmute")
                Accessible.name: tooltip + ": " + row.appLabel
                Accessible.role: Accessible.CheckBox
                Accessible.checked: row.available && row.node.audio.muted
                onClicked: row.node.audio.muted = !row.node.audio.muted
                onActiveFocusChanged: if (activeFocus) mixer.reveal(row)
            }
            VolumeSlider {
                id: volumeSlider
                objectName: "windowsAudioStreamVolume-" + (row.node ? row.node.id : "")
                x: 44
                y: 43
                width: parent.width - 52
                height: 34
                stepSize: 1
                enabled: row.available
                value: row.available ? row.node.audio.volume * 100 : 0
                Accessible.name: row.appLabel + ": " + Math.round(value) + "%"
                    + (amplified ? Style.label(" — amplificazione oltre il 100%", " — amplification above 100%") : "")
                onActiveFocusChanged: if (activeFocus) mixer.reveal(row)
                changeVolume: function(percent) {
                    if (!row.available || !isFinite(percent))
                        return;
                    row.node.audio.volume = Math.max(0, Math.min(Core.SystemState.volumeCeiling, percent)) / 100;
                }
            }
        }
    }
}
