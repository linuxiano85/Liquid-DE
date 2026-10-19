import "../core" as Core
import "../ui" as Ui
import QtQuick
import QtQuick.Controls as Controls

FocusScope {
    id: panel

    property string page: "main"
    property var wifiView: null
    readonly property var toggles: [{
        "id": "wifi",
        "icon": "wifi",
        "label": "Wi-Fi",
        "available": Core.SystemState.wifiPresent,
        "on": Core.SystemState.wifiOn
    }, {
        "id": "bluetooth",
        "icon": "bluetooth",
        "label": "Bluetooth",
        "available": Core.SystemState.bluetoothPresent,
        "on": Core.SystemState.bluetoothOn
    }, {
        "id": "night",
        "icon": "moon",
        "label": Style.label("Luce notturna", "Night light"),
        "available": true,
        "on": Core.Ipc.get("display.nightLight", false)
    }, {
        "id": "dnd",
        "icon": "bell",
        "label": Style.label("Non disturbare", "Do not disturb"),
        "available": true,
        "on": Core.Notifications.nonDisturbareEffettivo
    }, {
        "id": "accessibility",
        "icon": "accessibility",
        "label": Style.label("Accessibilità", "Accessibility"),
        "available": true,
        "on": false
    }, {
        "id": "project",
        "icon": "monitor",
        "label": Style.label("Proietta", "Project"),
        "available": true,
        "on": false
    }].filter(function(t) {
        return t.available;
    })

    signal settingsRequested(string section)

    function goBack() {
        if (page === "main")
            return false;

        if (page === "wifi" && wifiView && wifiView.goBack())
            return true;
        var previous = page;
        page = "main";
        Qt.callLater(function() {
            if (previous === "audio") {
                audioButton.forceActiveFocus(Qt.TabFocusReason);
                return;
            }
            for (var i = 0; i < toggleRepeater.count; i++) {
                var item = toggleRepeater.itemAt(i);
                if (item && item.modelData.id === previous) {
                    item.detailControl.forceActiveFocus(Qt.TabFocusReason);
                    return;
                }
            }
            panel.forceActiveFocus(Qt.TabFocusReason);
        });
        return true;
    }

    function activate(id) {
        if (id === "wifi")
            Core.SystemState.setWifi(!Core.SystemState.wifiOn);
        else if (id === "bluetooth")
            Core.SystemState.setBluetooth(!Core.SystemState.bluetoothOn);
        else if (id === "night")
            Core.Ipc.setSetting("display.nightLight", !Core.Ipc.get("display.nightLight", false));
        else if (id === "dnd")
            Core.Notifications.impostaNonDisturbare(!Core.Notifications.nonDisturbareEffettivo);
        else if (id === "accessibility")
            panel.settingsRequested("accesso-facile");
        else if (id === "project")
            panel.settingsRequested("display");
    }

    objectName: "windowsQuickSettings"

    // ── I comandi multimediali ───────────────────────────────────────────
    //
    // In Windows 11 stanno in una scheda a sé SOPRA le impostazioni rapide,
    // e ci sono solo mentre un'app riproduce qualcosa: icona e nome
    // dell'app, copertina, titolo e artista, indietro / riproduci / avanti.
    // Qui li dà MPRIS (`core/Media.qml`): Minerva Media, il browser, Spotify.
    readonly property real schedaMedia: Core.Media.cQualcosa ? 124 : 0

    Rectangle {
        objectName: "windowsMediaCard"
        visible: panel.schedaMedia > 0
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: panel.schedaMedia - 12
        radius: 8
        color: Style.pannello
        border.color: Style.edge

        Row {
            x: 16; y: 12
            spacing: 8
            Glyph { width: 16; height: 16; name: "music"; color: Style.muted }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Core.Media.attivo ? (Core.Media.attivo.identity || "") : ""
                textFormat: Text.PlainText
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 12
            }
        }

        Rectangle {
            id: copertinaMedia
            x: 16; y: 40
            width: 56; height: 56
            radius: 4
            color: Style.field
            clip: true
            Glyph {
                anchors.centerIn: parent
                width: 24; height: 24
                visible: immagineMedia.status !== Image.Ready
                name: "music"
                color: Style.muted
            }
            Image {
                id: immagineMedia
                anchors.fill: parent
                source: Core.Media.copertina
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 112
                sourceSize.height: 112
            }
        }

        Column {
            anchors { left: copertinaMedia.right; leftMargin: 12
                      right: comandiMedia.left; rightMargin: 8
                      verticalCenter: copertinaMedia.verticalCenter }
            spacing: 2
            Text {
                width: parent.width
                text: Core.Media.titolo
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Style.text
                font.family: Style.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                visible: text !== ""
                text: Core.Media.artista
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 12
            }
        }

        Row {
            id: comandiMedia
            anchors { right: parent.right; rightMargin: 12
                      verticalCenter: copertinaMedia.verticalCenter }
            spacing: 4
            Button {
                width: 36; height: 36
                icon: "mediaPrevious"
                glyphSize: 16
                enabled: Core.Media.attivo !== null && Core.Media.attivo.canGoPrevious
                tooltip: Style.label("Precedente", "Previous")
                onClicked: Core.Media.precedente()
            }
            Button {
                width: 36; height: 36
                icon: Core.Media.inRiproduzione ? "mediaPause" : "mediaPlay"
                glyphSize: 18
                tooltip: Core.Media.inRiproduzione ? Style.label("Pausa", "Pause")
                                                   : Style.label("Riproduci", "Play")
                onClicked: Core.Media.riproduci()
            }
            Button {
                width: 36; height: 36
                icon: "mediaNext"
                glyphSize: 16
                enabled: Core.Media.attivo !== null && Core.Media.attivo.canGoNext
                tooltip: Style.label("Successivo", "Next")
                onClicked: Core.Media.successivo()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: panel.schedaMedia
        radius: 8
        color: Style.pannello
        border.color: Style.edge
    }

    Loader {
        id: audioLoader

        anchors.fill: parent
        anchors.topMargin: panel.schedaMedia
        active: panel.page === "audio"

        sourceComponent: Component {
            AudioDevices {
                onBackRequested: panel.goBack()
                onSettingsRequested: panel.settingsRequested("audio")
            }

        }

    }

    Loader {
        anchors.fill: parent
        anchors.topMargin: panel.schedaMedia
        active: panel.page === "bluetooth"
        sourceComponent: Component {
            BluetoothDevices {
                onBackRequested: panel.goBack()
                onSettingsRequested: panel.settingsRequested("bluetooth")
            }
        }
    }

    Loader {
        anchors.fill: parent
        anchors.topMargin: panel.schedaMedia
        active: panel.page === "wifi"
        onLoaded: panel.wifiView = item
        onActiveChanged: if (!active) panel.wifiView = null
        sourceComponent: Component {
            WifiNetworks {
                onBackRequested: panel.goBack()
                onSettingsRequested: panel.settingsRequested("network")
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.topMargin: panel.schedaMedia
        visible: panel.page === "main"

        Grid {
            id: tiles

            x: 24
            y: 24
            width: parent.width - 48
            columns: 3
            spacing: 12

            Repeater {
                id: toggleRepeater
                model: panel.toggles

                delegate: Item {
                    required property var modelData
                    property alias detailControl: detailButton

                    width: (tiles.width - 24) / 3
                    height: 90

                    Button {
                        objectName: "windowsQuick-" + parent.modelData.id
                        width: parent.width
                        height: 48
                        filled: parent.modelData.on
                        selected: true
                        icon: parent.modelData.icon
                        tooltip: parent.modelData.label
                        onClicked: panel.activate(parent.modelData.id)
                        onRightClicked: panel.settingsRequested(parent.modelData.id === "wifi" ? "network" : (parent.modelData.id === "bluetooth" ? "bluetooth" : "appearance"))

                        Button {
                            id: detailButton
                            objectName: "windowsQuickArrow-" + parent.parent.modelData.id
                            // Il fondo della freccia non deve coprire il bordo
                            // esterno: a piena altezza sembrava sporgere di un pixel.
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            width: 24
                            filled: parent.filled
                            icon: "chevronRight"
                            visible: parent.parent.modelData.id === "wifi" || parent.parent.modelData.id === "bluetooth"
                            tooltip: parent.parent.modelData.id === "wifi" ? Style.label("Reti Wi-Fi", "Wi-Fi networks") : Style.label("Dispositivi Bluetooth", "Bluetooth devices")
                            onClicked: {
                                panel.page = parent.parent.modelData.id;
                            }
                        }

                    }

                    Text {
                        y: 58
                        width: parent.width
                        text: parent.modelData.label
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        color: Style.text
                        font.family: Style.font
                        font.pixelSize: 12 * Style.textScale
                    }

                }

            }

        }

        Column {
            x: 24
            y: tiles.y + tiles.height + 14
            width: parent.width - 48
            spacing: 20

            Row {
                width: parent.width
                height: 32
                spacing: 16
                visible: Core.SystemState.hasBrightness

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    name: "sun"
                    color: Style.text
                    alwaysDrawn: true
                }

                Controls.Slider {
                    width: parent.width - 36
                    height: 32
                    from: 1
                    to: 100
                    value: Core.SystemState.brightness
                    Accessible.name: Style.label("Luminosità", "Brightness")
                    onMoved: Core.SystemState.setBrightness(value)

                    background: Rectangle {
                        x: parent.leftPadding
                        y: parent.topPadding + parent.availableHeight / 2 - 2
                        width: parent.availableWidth
                        height: 4
                        radius: 2
                        color: Style.edge

                        Rectangle {
                            width: parent.parent.visualPosition * parent.width
                            height: 4
                            radius: 2
                            color: Style.accent
                        }

                    }

                    handle: Rectangle {
                        x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width)
                        y: parent.topPadding + parent.availableHeight / 2 - height / 2
                        width: 20
                        height: 20
                        radius: 10
                        color: Style.field
                        border.color: Style.edge

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: 6
                            color: Style.accent
                        }

                    }

                }

            }

            Row {
                width: parent.width
                height: 32
                spacing: 16

                Button {
                    width: 24
                    height: 32
                    icon: Core.SystemState.muted ? "muted" : "volume"
                    tooltip: Style.label("Disattiva/attiva audio", "Mute/unmute")
                    onClicked: Core.SystemState.toggleMute()
                }

                VolumeSlider {
                    width: parent.width - 80
                    height: 32
                }

                Button {
                    id: audioButton

                    objectName: "windowsAudioDevices"
                    width: 24
                    height: 32
                    icon: "chevronRight"
                    tooltip: Style.label("Dispositivi audio", "Audio devices")
                    onClicked: panel.page = "audio"
                }

            }

        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 56
            color: Style.pannelloPiede
            radius: 8

            Rectangle {
                width: parent.width
                height: 8
                color: Style.pannelloPiede
            }

            Text {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: Core.SystemState.hasBattery ? Core.SystemState.batteryPercent + "%" : (Core.SystemState.networkConnected ? Core.SystemState.networkName : Style.label("Non connesso", "Disconnected"))
                textFormat: Text.PlainText
                color: Style.muted
                font.family: Style.font
                font.pixelSize: 12
            }

            Button {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                icon: "settings"
                tooltip: Style.label("Impostazioni", "Settings")
                onClicked: panel.settingsRequested("")
            }

        }

    }

}
