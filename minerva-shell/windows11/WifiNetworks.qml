import QtQuick
import QtQuick.Controls as Controls
import "../core" as Core
import "../ui" as Ui

FocusScope {
    id: page
    objectName: "windowsWifiPage"
    signal backRequested()
    signal settingsRequested()
    property string expandedSsid: ""
    property string passwordSsid: ""
    property string passwordText: ""
    readonly property int networkCount: rows.count
    readonly property bool powered: network.wifiOn
    readonly property string connecting: network.collegando
    readonly property string error: network.error
    readonly property var entries: network.networks.map(function(n) {
        return {ssid: n.ssid, active: n.active, secure: n.secure, signalStrength: n.signal};
    })
    function cancelPassword() {
        passwordText = "";
        passwordSsid = "";
        network.awaitingPassword = false;
    }
    function goBack() {
        if (passwordSsid === "")
            return false;
        cancelPassword();
        return true;
    }
    function choose(ssid, active, secure) {
        if (connecting !== "")
            return;
        if (active) {
            expandedSsid = expandedSsid === ssid ? "" : ssid;
            return;
        }
        cancelPassword();
        expandedSsid = expandedSsid === ssid ? "" : ssid;
        var index = entries.findIndex(function(entry) { return entry.ssid === ssid; });
        Qt.callLater(function() { list.positionViewAtIndex(index, ListView.Contain); });
    }
    function submitPassword() {
        var ssid = passwordSsid;
        var secret = passwordText;
        cancelPassword();
        network.connect(ssid, secret, true);
    }
    function updateRows() {
        for (var i = rows.count - 1; i >= 0; i--) {
            var ssid = rows.get(i).ssid;
            if (!entries.some(function(entry) { return entry.ssid === ssid; }))
                rows.remove(i);
        }
        entries.forEach(function(entry, position) {
            var at = -1;
            for (var i = 0; i < rows.count; i++) {
                if (rows.get(i).ssid === entry.ssid)
                    at = i;
            }
            if (at < 0)
                rows.insert(position, entry);
            else {
                if (at !== position)
                    rows.move(at, position, 1);
                rows.set(position, entry);
            }
        });
    }
    function focusNetwork(index) {
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
    Component.onCompleted: Qt.callLater(function() { back.forceActiveFocus(Qt.TabFocusReason); })
    Core.WifiController {
        id: network
        initialReadOnly: true
        onPasswordRequested: function(ssid) {
            page.passwordText = "";
            page.passwordSsid = ssid;
            page.expandedSsid = ssid;
            var index = page.entries.findIndex(function(entry) { return entry.ssid === ssid; });
            list.currentIndex = index;
            list.positionViewAtIndex(index, ListView.Contain);
            Qt.callLater(function() {
                list.positionViewAtIndex(index, ListView.Contain);
                var item = list.itemAtIndex(index);
                if (item)
                    item.passwordControl.forceActiveFocus(Qt.TabFocusReason);
            });
        }
        onPasswordDismissed: page.cancelPassword()
    }
    ListModel { id: rows }
    Button {
        id: back
        objectName: "windowsWifiBack"
        x: 16
        y: 16
        tooltip: Style.label("Indietro", "Back")
        onClicked: {
            if (!page.goBack())
                page.backRequested();
        }
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
        text: "Wi-Fi"
        color: Style.text
        font.family: Style.font
        font.pixelSize: 16 * Style.textScale
        font.weight: Font.DemiBold
    }
    Controls.Switch {
        id: power
        objectName: "windowsWifiPower"
        anchors.right: parent.right
        anchors.rightMargin: 24
        y: 16
        width: 40
        height: 34
        checked: page.powered
        enabled: Core.SystemState.wifiPresent
        Accessible.name: Style.label("Wi-Fi acceso", "Wi-Fi enabled")
        onToggled: network.setWifi(checked)
        indicator: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 20
            radius: 10
            color: power.checked ? Style.accent : "transparent"
            border.color: power.activeFocus ? Style.accentIndicator : Style.muted
            border.width: power.activeFocus ? 2 : 1
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
        y: 64
        width: parent.width - 48
        text: page.error || (!page.powered ? Style.label("Wi-Fi disattivato", "Wi-Fi is off")
            : network.scanning ? Style.label("Ricerca delle reti…", "Looking for networks…")
            : Style.label("Reti disponibili", "Available networks"))
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: page.error ? Style.critical : Style.muted
        font.family: Style.font
        font.pixelSize: 12 * Style.textScale
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
            id: networkRow
            required property string ssid
            required property bool active
            required property bool secure
            required property int signalStrength
            required property int index
            property alias passwordControl: passwordInput
            readonly property int tooltipTextFormat: networkTooltip.contentItem.textFormat
            objectName: "windowsWifiNetwork-" + ssid
            width: list.width
            height: 64 + (page.passwordSsid === ssid ? 116 : page.expandedSsid === ssid ? 38 : 0)
            selected: active || page.expandedSsid === ssid
            enabled: page.powered && page.connecting === ""
            // L'SSID arriva dalla radio: anche la targhetta deve restare
            // testo letterale, senza interpretare tag o caricare immagini.
            tooltip: ""
            Controls.ToolTip {
                id: networkTooltip
                visible: networkRow.hovered
                delay: 700
                text: networkRow.ssid
                contentItem: Text {
                    text: networkTooltip.text
                    textFormat: Text.PlainText
                    font: networkTooltip.font
                    color: Style.text
                }
                background: Rectangle {
                    color: Style.field
                    border.color: Style.edge
                    radius: 4
                }
            }
            Accessible.name: ssid + (active ? Style.label(" · connesso", " · connected") : "")
            onClicked: page.choose(ssid, active, secure)
            Keys.onDownPressed: page.focusNetwork(index + 1)
            Keys.onUpPressed: page.focusNetwork(index - 1)
            Glyph {
                x: 12
                y: 16
                width: 22
                height: 22
                name: parent.signalStrength > 65 ? "wifi" : parent.signalStrength > 30 ? "wifiMedium" : "wifiWeak"
                color: Style.text
            }
            Text {
                x: 46
                y: 10
                width: parent.width - 58
                text: parent.ssid
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Style.text
                font.family: Style.font
                font.pixelSize: 13 * Style.textScale
            }
            Text {
                x: 46
                y: 32
                width: parent.width - 58
                text: page.connecting === parent.ssid ? Style.label("Connessione…", "Connecting…")
                    : parent.active ? Style.label("Connesso", "Connected")
                    : parent.secure ? Style.label("Protetta", "Secured") : Style.label("Aperta", "Open")
                textFormat: Text.PlainText
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 11 * Style.textScale
            }
            Column {
                x: 46
                y: 58
                width: parent.width - 58
                spacing: 8
                visible: page.passwordSsid === parent.ssid
                enabled: visible
                Text {
                    text: Style.label("Chiave di sicurezza di rete", "Network security key")
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 11 * Style.textScale
                }
                Controls.TextField {
                    id: passwordInput
                    objectName: "windowsWifiPassword"
                    width: parent.width
                    height: 32
                    echoMode: TextInput.Password
                    text: page.passwordText
                    color: Style.text
                    selectionColor: Style.accent
                    selectedTextColor: Style.accentForeground
                    font.family: Style.font
                    font.pixelSize: 12 * Style.textScale
                    Accessible.name: Style.label("Chiave di sicurezza di rete", "Network security key")
                    onVisibleChanged: {
                        if (!visible) {
                            text = "";
                            focus = false;
                        }
                    }
                    onTextEdited: page.passwordText = text
                    onAccepted: page.submitPassword()
                    Keys.onEscapePressed: page.cancelPassword()
                    background: Rectangle {
                        radius: 4
                        color: Style.field
                        border.color: passwordInput.activeFocus ? Style.accentIndicator : Style.edge
                    }
                }
                Row {
                    spacing: 8
                    Button {
                        objectName: "windowsWifiPasswordCancel"
                        text: Style.label("Annulla", "Cancel")
                        onClicked: page.cancelPassword()
                    }
                    Button {
                        objectName: "windowsWifiPasswordSubmit"
                        text: Style.label("Avanti", "Next")
                        filled: true
                        enabled: page.passwordText !== ""
                        onClicked: page.submitPassword()
                    }
                }
            }
            Button {
                objectName: "windowsWifiConnect-" + parent.ssid
                x: 46
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: Style.label("Connetti", "Connect")
                filled: true
                visible: !parent.active && page.expandedSsid === parent.ssid && page.passwordSsid !== parent.ssid
                enabled: visible
                onVisibleChanged: if (!visible) focus = false
                onClicked: network.connect(parent.ssid, "", parent.secure)
            }
            Button {
                objectName: "windowsWifiDisconnect-" + parent.ssid
                x: 46
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: Style.label("Disconnetti", "Disconnect")
                selected: true
                visible: parent.active && page.expandedSsid === parent.ssid
                enabled: visible
                onVisibleChanged: if (!visible) focus = false
                onClicked: network.disconnect()
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 16
            visible: page.powered && rows.count === 0 && !network.scanning
            text: Style.label("Nessuna rete trovata", "No networks found")
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Style.muted
            font.family: Style.font
            font.pixelSize: 12 * Style.textScale
        }
    }
    Ui.Scorrimento {
        objectName: "windowsWifiScrollBar"
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
        Rectangle {
            width: parent.width
            height: 8
            color: Style.pannelloPiede
        }
        Button {
            objectName: "windowsWifiSettings"
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: Style.label("Altre impostazioni Wi-Fi", "More Wi-Fi settings")
            icon: "settings"
            onClicked: page.settingsRequested()
        }
        Button {
            objectName: "windowsWifiRefresh"
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            icon: "refresh"
            tooltip: Style.label("Aggiorna reti", "Refresh networks")
            enabled: page.powered && page.connecting === ""
            onClicked: network.rescan()
        }
    }
}
