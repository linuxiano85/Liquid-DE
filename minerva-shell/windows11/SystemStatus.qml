import QtQuick
import "../core" as Core

Button {
    id: status
    objectName: "windowsStatusButton"
    // Le prove modificano solo questi ingressi: mai PipeWire o la rete reale.
    property real batteryPercent: Core.SystemState.batteryPercent
    property bool batteryCharging: Core.SystemState.batteryCharging
    property bool energySaving: Core.Compositore.risparmio.profiloRisparmio === true
    property int volume: Core.SystemState.volume
    property bool muted: Core.SystemState.muted
    property bool wired: Core.SystemState.networkWired
    property bool connected: Core.SystemState.networkConnected
    property int strength: Core.SystemState.networkStrength
    property string networkName: Core.SystemState.networkName
    property var changeVolume: function(delta) {
        Core.SystemState.stepVolume(delta);
    }
    signal audioContextRequested(real centre)
    readonly property string volumeIcon: muted ? "muted"
        : volume <= 0 ? "volumeZero"
        : volume <= 33 ? "volumeLow" : "volume"
    readonly property string networkIcon: wired ? "network"
        : !connected ? "globe"
        : strength > 65 ? "wifi"
        : strength > 30 ? "wifiMedium" : "wifiWeak"
    readonly property string batteryState: battery.state
    readonly property color batteryColor: battery.ink
    readonly property real batteryFraction: battery.fraction
    readonly property bool hasBattery: battery.available
    width: symbols.implicitWidth + 16
    height: 40
    tooltip: {
        var lines = [Style.label("Impostazioni rapide", "Quick settings")];
        lines.push(wired ? Style.label("Ethernet connessa", "Ethernet connected")
            : connected ? (networkName || Style.label("Wi-Fi connesso", "Wi-Fi connected"))
            : Style.label("Nessuna connessione", "Not connected"));
        lines.push(muted ? Style.label("Audio disattivato", "Sound muted")
            : Style.label("Volume: ", "Volume: ") + Math.max(0, volume) + "%");
        if (hasBattery) {
            var note = batteryCharging ? Style.label("In carica", "Charging")
                : batteryState === "critical" ? Style.label("Batteria quasi scarica", "Battery critically low")
                : energySaving ? Style.label("Risparmio energetico", "Energy saver")
                : Style.label("A batteria", "On battery");
            lines.push(Math.round(batteryFraction * 100) + "% · " + note);
        }
        return lines.join("\n");
    }
    Row {
        id: symbols
        anchors.centerIn: parent
        spacing: 6
        Glyph {
            objectName: "windowsNetworkIcon"
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            name: status.networkIcon
            color: Style.barraTesto
        }
        Glyph {
            id: volumeGlyph
            objectName: "windowsVolumeIcon"
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            name: status.volumeIcon
            color: Style.barraTesto
        }
        BatteryIcon {
            id: battery
            objectName: "windowsBatteryIcon"
            percent: status.batteryPercent
            charging: status.batteryCharging
            saving: status.energySaving
        }
    }
    // Windows regola il volume sopra l'altoparlante, non sopra la rete.
    // La zona si allarga di tre pixel per lato senza intercettare i clic.
    MouseArea {
        id: volumeWheel
        objectName: "windowsVolumeWheel"
        x: symbols.x + volumeGlyph.x - 3
        width: volumeGlyph.width + 6
        height: status.height
        acceptedButtons: Qt.RightButton
        onClicked: status.audioContextRequested(x + width / 2)
        hoverEnabled: true
        property real remainder: 0
        onExited: remainder = 0
        onWheel: function(event) {
            if (event.angleDelta.y === 0) {
                event.accepted = false;
                return;
            }
            // Un mouse ad alta risoluzione può spezzare una tacca in più
            // eventi: si accumulano, senza trasformarli tutti in tacche intere.
            remainder += event.angleDelta.y / 120;
            var steps = remainder < 0 ? Math.ceil(remainder) : Math.floor(remainder);
            remainder -= steps;
            if (steps !== 0)
                status.changeVolume(steps * 2);
            event.accepted = true;
        }
    }
}
