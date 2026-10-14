import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Bluetooth as BT
import "../core" as Core
import "../ui" as Ui

FocusScope {
    id: page
    objectName: "windowsBluetoothPage"
    signal backRequested()
    signal settingsRequested()
    property var adapters: BT.Bluetooth.adapters.values
    property var devices: BT.Bluetooth.devices.values
    readonly property bool powered: adapters.some(function(a) { return a.enabled; })
    readonly property int deviceCount: rows.count
    property string expandedPath: ""
    property string pendingPath: ""
    property bool pendingKeyboard: false
    property bool pendingConnected: false
    property bool sawTransition: false
    property string notice: ""
    property var changePower: function(on) {
        Core.SystemState.setBluetooth(on);
    }
    readonly property var entries: devices.filter(function(d) {
        return d.paired || d.bonded || d.connected;
    }).map(function(d) {
        return {
            identity: d.dbusPath,
            label: d.name || d.deviceName || d.address,
            connected: d.connected,
            transitioning: d.state === BT.BluetoothDeviceState.Connecting || d.state === BT.BluetoothDeviceState.Disconnecting,
            blocked: d.blocked,
            usable: d.adapter !== null && d.adapter.enabled,
            battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1,
            deviceIcon: d.icon.indexOf("audio") >= 0 ? "headphones" : "bluetooth"
        };
    }).sort(function(a, b) {
        if (a.connected !== b.connected)
            return a.connected ? -1 : 1;
        return a.label.localeCompare(b.label);
    })

    function updateRows() {
        // L'identità è il percorso BlueZ, che comprende l'adattatore: lo
        // stesso MAC su due radio non deve diventare un solo dispositivo.
        for (var i = rows.count - 1; i >= 0; i--) {
            var identity = rows.get(i).identity;
            if (!entries.some(function(e) { return e.identity === identity; }))
                rows.remove(i);
        }
        for (var n = 0; n < entries.length; n++) {
            var at = -1;
            for (var j = 0; j < rows.count; j++) {
                if (rows.get(j).identity === entries[n].identity)
                    at = j;
            }
            if (at < 0)
                rows.insert(n, entries[n]);
            else {
                if (at !== n)
                    rows.move(at, n, 1);
                rows.set(n, entries[n]);
            }
        }
        if (expandedPath !== "" && !entries.some(function(e) { return e.identity === expandedPath && e.connected; }))
            expandedPath = "";
        if (pendingPath === "")
            return;
        var entry = entries.find(function(e) { return e.identity === pendingPath; });
        if (!entry) {
            finish(Style.label("Dispositivo non più disponibile", "Device no longer available"));
        } else if (entry.transitioning) {
            sawTransition = true;
        } else if (entry.connected === pendingConnected) {
            finish("");
        } else if (sawTransition) {
            finish(Style.label("Connessione non riuscita. Riprova.", "Connection failed. Try again."));
        }
    }
    function finish(message) {
        var completed = pendingPath;
        var restoreFocus = pendingKeyboard;
        deadline.stop();
        pendingPath = "";
        notice = message;
        if (restoreFocus) {
            Qt.callLater(function() {
                for (var i = 0; i < rows.count; i++) {
                    if (rows.get(i).identity === completed) {
                        focusDevice(i);
                        return;
                    }
                }
                back.forceActiveFocus(Qt.TabFocusReason);
            });
        }
    }
    function toggleDevice(identity, keyboard) {
        if (pendingPath !== "")
            return;
        var device = devices.find(function(d) { return d.dbusPath === identity; });
        if (!device || !device.adapter || !device.adapter.enabled || device.blocked)
            return;
        if (device.state === BT.BluetoothDeviceState.Connecting || device.state === BT.BluetoothDeviceState.Disconnecting)
            return;
        pendingKeyboard = keyboard === true;
        pendingPath = identity;
        pendingConnected = !device.connected;
        sawTransition = false;
        notice = "";
        deadline.restart();
        // Quickshell conserva lo stato di transizione e conferma la risposta
        // di BlueZ: il clic non si trasforma in una connessione ottimistica.
        device.connected = pendingConnected;
    }
    function syncPower() {
        Core.SystemState.bluetoothOn = powered;
        Core.SystemState.bluetoothPresent = adapters.length > 0;
    }
    function focusDevice(index) {
        if (rows.count === 0)
            return;
        list.currentIndex = Math.max(0, Math.min(rows.count - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        Qt.callLater(function() {
            var item = list.itemAtIndex(list.currentIndex);
            if (item)
                item.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    onEntriesChanged: updateRows()
    onPoweredChanged: syncPower()
    onAdaptersChanged: syncPower()
    Component.onCompleted: {
        updateRows();
        syncPower();
        Qt.callLater(function() { back.forceActiveFocus(Qt.TabFocusReason); });
    }
    Timer {
        id: deadline
        interval: 30000
        onTriggered: page.finish(Style.label("Il dispositivo non risponde. Riprova.", "The device is not responding. Try again."))
    }
    ListModel { id: rows }
    Button {
        id: back
        objectName: "windowsBluetoothBack"
        x: 16
        y: 16
        tooltip: Style.label("Indietro", "Back")
        onClicked: page.backRequested()
        Glyph {
            anchors.centerIn: parent
            width: 18
            height: 18
            name: "chevronRight"
            rotation: 180
            color: Style.text
        }
    }
    Text {
        x: 64
        y: 25
        text: "Bluetooth"
        color: Style.text
        font.family: Style.font
        font.pixelSize: 16 * Style.textScale
        font.weight: Font.DemiBold
    }
    Controls.Switch {
        id: power
        objectName: "windowsBluetoothPower"
        anchors.right: parent.right
        anchors.rightMargin: 24
        y: 16
        width: 40
        height: 34
        checked: page.powered
        enabled: page.adapters.length > 0 && Core.SystemState.bluetoothBlock !== "hard"
        Accessible.name: Style.label("Bluetooth acceso", "Bluetooth enabled")
        onToggled: page.changePower(checked)
        indicator: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 20
            radius: 10
            color: power.checked ? Style.accent : "transparent"
            border.color: power.activeFocus ? Style.accentIndicator : Style.muted
            border.width: power.activeFocus ? 2 : 1
            opacity: power.enabled ? 1 : 0.5
            Rectangle {
                x: power.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 7
                color: power.checked ? Style.accentForeground : Style.muted
            }
        }
        contentItem: Item {}
        background: Item {}
    }
    Text {
        id: description
        x: 24
        y: 66
        width: parent.width - 48
        text: page.notice || (page.adapters.length === 0 ? Style.label("Nessun adattatore Bluetooth", "No Bluetooth adapter")
            : Core.SystemState.bluetoothBlock === "hard" ? Style.label("Bluetooth bloccato dall’interruttore fisico", "Bluetooth blocked by the hardware switch")
            : !page.powered ? Style.label("Bluetooth disattivato", "Bluetooth is off")
            : Style.label("Dispositivi personali", "Your devices"))
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        font.family: Style.font
        font.pixelSize: 12 * Style.textScale
        color: Style.muted
    }
    ListView {
        id: list
        x: 16
        y: description.y + description.height + 12
        width: parent.width - 50
        height: Math.max(0, footer.y - y - 12)
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: rows
        delegate: Button {
            required property string identity
            required property string label
            required property string deviceIcon
            required property bool connected
            required property bool transitioning
            required property bool blocked
            required property bool usable
            required property int battery
            required property int index
            objectName: "windowsBluetoothDevice-" + identity
            width: list.width
            height: Math.max(64, caption.implicitHeight + 32) + (connected && page.expandedPath === identity ? 38 : 0)
            selected: connected
            enabled: usable && !blocked && !transitioning && page.pendingPath === ""
            tooltip: label + " · " + (connected ? Style.label("Gestisci connessione", "Manage connection") : Style.label("Connetti", "Connect"))
            Accessible.name: tooltip
            onClicked: {
                if (connected)
                    page.expandedPath = page.expandedPath === identity ? "" : identity;
                else
                    page.toggleDevice(identity, !_focoDalMouse);
            }
            Keys.onDownPressed: page.focusDevice(index + 1)
            Keys.onUpPressed: {
                if (index === 0)
                    back.forceActiveFocus(Qt.TabFocusReason);
                else
                    page.focusDevice(index - 1);
            }
            Glyph {
                x: 12
                y: 16
                width: 22
                height: 22
                name: parent.deviceIcon
                color: Style.text
            }
            Text {
                id: caption
                x: 46
                y: 10
                width: parent.width - 58
                text: parent.label
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Style.text
                font.family: Style.font
                font.pixelSize: 13 * Style.textScale
            }
            Text {
                x: 46
                y: caption.y + caption.height + 4
                width: parent.width - 58
                text: parent.transitioning || page.pendingPath === parent.identity ? Style.label("Operazione in corso…", "Working…")
                    : parent.blocked ? Style.label("Bloccato", "Blocked")
                    : parent.connected ? Style.label("Connesso", "Connected") + (parent.battery >= 0 ? " · " + parent.battery + "%" : "")
                    : Style.label("Associato", "Paired")
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 11 * Style.textScale
            }
            // La disconnessione è esplicita: aprire la scheda di un mouse o
            // di un controller in uso non deve interromperlo per un solo clic.
            Button {
                objectName: "windowsBluetoothDisconnect-" + parent.identity
                x: 46
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: Style.label("Disconnetti", "Disconnect")
                selected: true
                visible: parent.connected && page.expandedPath === parent.identity
                enabled: visible
                onVisibleChanged: {
                    if (!visible)
                        focus = false;
                }
                onClicked: page.toggleDevice(parent.identity, !_focoDalMouse)
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 16
            visible: rows.count === 0 && page.powered
            text: Style.label("Nessun dispositivo associato", "No paired devices")
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Style.muted
            font.family: Style.font
            font.pixelSize: 12 * Style.textScale
        }
    }
    Ui.Scorrimento {
        objectName: "windowsBluetoothScrollBar"
        bersaglio: list
        tinta: Style.muted
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.top: list.top
        anchors.bottom: list.bottom
    }
    Rectangle {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: 56
        radius: 8
        color: Style.pannelloPiede
        Rectangle { width: parent.width; height: 8; color: Style.pannelloPiede }
        Button {
            objectName: "windowsBluetoothSettings"
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: Style.label("Altre impostazioni Bluetooth", "More Bluetooth settings")
            icon: "settings"
            onClicked: page.settingsRequested()
        }
    }
}
