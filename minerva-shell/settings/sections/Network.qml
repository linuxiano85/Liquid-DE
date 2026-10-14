import QtQuick
import Quickshell.Io
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Network — Wi-Fi e rete via cavo.
//
// Si appoggia a NetworkManager (`nmcli`), che è quello che gestisce davvero le
// connessioni: reinventarlo significherebbe riscrivere la gestione delle
// password, dei certificati e della riconnessione automatica.
//
// La password si chiede solo quando serve: se la rete è già nota, NetworkManager
// ce l'ha e connettersi è un clic solo.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Rete" : "Network"
    subtitle: Core.Strings.lang === "it"
              ? "Wi-Fi e connessione via cavo"
              : "Wi-Fi and wired connection"

    readonly property bool it: Core.Strings.lang === "it"
    property alias networks: network.networks
    property alias wired: network.wired
    property alias scanning: network.scanning
    property alias error: network.error
    readonly property bool wifiOn: network.wifiOn
    readonly property string collegando: network.collegando
    Core.WifiController {
        id: network
        active: Qt.application.state === Qt.ApplicationActive
        onPasswordRequested: function(ssid) { connectDialog.open(ssid); }
        onPasswordDismissed: connectDialog.cancel()
    }
    function refresh(soloLettura) { network.refresh(soloLettura); }
    function rescan() { network.rescan(); }
    function connect(ssid, password, protetta) { return network.connect(ssid, password, protetta); }
    function disconnect() { network.disconnect(); }
    function stopWifi() { network.stopWifi(); }
    function setWifi(on) { network.setWifi(on); }

    Card {
        heading: page.it ? "Rete via cavo" : "Wired network"
        visible: page.wired !== ""

        Row {
            width: parent.width
            spacing: Theme.Effects.space3

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                name: "globe"
                color: Theme.Colors.positive
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.wired
                textFormat: Text.PlainText
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.it ? "connesso" : "connected"
                color: Theme.Colors.positive
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    // ── Wi-Fi ────────────────────────────────────────────────────────────

    Card {
        heading: "Wi-Fi"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Wi-Fi acceso" : "Wi-Fi on"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: page.wifiOn
                onToggled: function(v) { page.setWifi(v); }
            }
        }

        Item {
            width: parent.width
            height: 28
            visible: page.wifiOn

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: page.scanning
                      ? (page.it ? "Cerco le reti…" : "Scanning…")
                      // «1 reti trovate» era la scritta che c'era: il plurale
                      // scritto a mano attaccato a un numero. Con una rete
                      // sola — cioè in casa del manutentore — si legge sempre.
                      : (page.networks.length + (page.it
                            ? (page.networks.length === 1 ? " rete trovata"
                                                          : " reti trovate")
                            : (page.networks.length === 1 ? " network found"
                                                          : " networks found")))
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: rescanText.implicitWidth + Theme.Effects.space3
                height: 24
                radius: Theme.Effects.radiusXS
                color: rescanMouse.containsMouse ? Theme.Colors.hover : "transparent"

                Text {
                    id: rescanText
                    anchors.centerIn: parent
                    text: page.it ? "Cerca di nuovo" : "Scan again"
                    color: rescanMouse.containsMouse ? Theme.Colors.accent
                                                     : Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                MouseArea {
                    id: rescanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.rescan()
                }
            }
        }

        Text {
            width: parent.width
            visible: page.error !== ""
            wrapMode: Text.WordWrap
            text: page.error
            textFormat: Text.PlainText
            color: Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        Repeater {
            model: page.wifiOn ? page.networks : []

            delegate: Rectangle {
                id: net
                required property var modelData

                width: parent.width
                height: 46
                radius: Theme.Effects.radiusSM
                color: net.modelData.active ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : netMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // Forza del segnale, in quattro tacche: il numero esatto non
                // aiuta a decidere niente, la tacca sì.
                Row {
                    id: bars
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            width: 3
                            height: 4 + index * 3
                            anchors.bottom: parent.bottom
                            radius: 1.5
                            color: net.modelData.signal >= (index + 1) * 22
                                   ? (net.modelData.active ? Theme.Colors.accent
                                                           : Theme.Colors.textMuted)
                                   : Theme.Colors.raisedHigh
                        }
                    }
                }

                Text {
                    id: netName
                    textFormat: Text.PlainText
                    anchors.left: bars.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: netLock.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: net.modelData.ssid
                          + (page.collegando === net.modelData.ssid
                             ? (page.it ? "  ·  mi collego…" : "  ·  connecting…")
                             : net.modelData.active ? (page.it ? "  ·  connesso" : "  ·  connected")
                             : "")
                    color: net.modelData.active ? Theme.Colors.text : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: net.modelData.active ? Theme.Typography.weightSemiBold
                                                      : Theme.Typography.weightRegular
                }

                Ui.Icon {
                    id: netLock
                    anchors.right: stacca.visible ? stacca.left : parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14
                    name: "lock"
                    visible: net.modelData.secure
                    color: Theme.Colors.textFaint
                    alwaysDrawn: true
                }

                // Un clic sulla riga della rete connessa la STACCAVA. È la
                // riga più grande e più colorata della pagina, quella su cui
                // si clicca per vedere com'è messa: la rete se ne andava per
                // un clic dato per guardare. Staccarsi adesso è un pulsante a
                // sé, che dice quello che fa.
                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: page.collegando === ""
                    cursorShape: net.modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (net.modelData.active)
                            return;
                        page.connect(net.modelData.ssid, "", net.modelData.secure);
                    }
                }

                Rectangle {
                    id: stacca
                    visible: net.modelData.active
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: staccaTesto.implicitWidth + Theme.Effects.space4
                    height: 26
                    radius: Theme.Effects.radiusXS
                    color: staccaMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raisedHigh

                    Text {
                        id: staccaTesto
                        anchors.centerIn: parent
                        text: page.it ? "Disconnetti" : "Disconnect"
                        color: staccaMouse.containsMouse ? Theme.Colors.text : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    MouseArea {
                        id: staccaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.disconnect()
                    }
                }
            }
        }
    }

    // ── Richiesta della password ─────────────────────────────────────────
    //
    // Vive dentro la pagina e non in una finestra a parte: una finestra nuova
    // per tre campi nascerebbe altrove, e chi la chiude per sbaglio non sa più
    // da dove tornare. Si apre solo quando NetworkManager ha detto che la
    // password gli manca (vedi `connect`).

    Rectangle {
        id: connectDialog
        parent: page
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false
        z: 10

        property string ssid: ""

        function open(s) {
            connectDialog.ssid = s;
            passwordInput.text = "";
            connectDialog.visible = true;
            passwordInput.forceActiveFocus();
        }

        function cancel() {
            passwordInput.text = "";
            connectDialog.ssid = "";
            connectDialog.visible = false;
            network.awaitingPassword = false;
        }

        function submit() {
            if (!connectDialog.visible) return;
            var secret = passwordInput.text;
            var target = connectDialog.ssid;
            connectDialog.cancel();
            page.connect(target, secret, true);
        }

        onVisibleChanged: if (!visible) passwordInput.text = "";

        MouseArea {
            anchors.fill: parent
            onClicked: connectDialog.cancel()
        }

        Rectangle {
            anchors.centerIn: parent
            width: 380
            height: 168
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Text {
                id: dialogTitle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                elide: Text.ElideRight
                text: connectDialog.ssid
                textFormat: Text.PlainText
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightSemiBold
            }

            Text {
                id: dialogHint
                anchors.top: dialogTitle.bottom
                anchors.topMargin: 2
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space4
                text: page.it ? "Password della rete" : "Network password"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                id: passwordBox
                anchors.top: dialogHint.bottom
                anchors.topMargin: Theme.Effects.space3
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                height: 36
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.45)

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    // Solo ai lati: lo stesso conto della casella del nome nel
                    // gestore file (`files/FileManager.qml`). Con il margine
                    // anche sopra e sotto restavano dodici pixel per un
                    // carattere da sedici, e la password si vedeva tagliata.
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    echoMode: revealMouse.pressed ? TextInput.Normal
                                                        : TextInput.Password
                    color: Theme.Colors.text
                    selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD

                    onAccepted: connectDialog.submit()
                    Keys.onEscapePressed: connectDialog.cancel()
                }

                // Occhio per rivelare: tenerlo premuto mostra la password.
                // Un interruttore che la lascia visibile la dimentica visibile.
                Ui.Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: "search"
                    color: revealMouse.pressed ? Theme.Colors.accent
                                                     : Theme.Colors.textFaint

                    MouseArea {
                        id: revealMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "cancel",  "primary": false },
                        { "id": "connect", "primary": true }
                    ]

                    delegate: Rectangle {
                        id: dlgBtn
                        required property var modelData

                        width: dlgLabel.implicitWidth + Theme.Effects.space5
                        height: 32
                        radius: Theme.Effects.radiusXS
                        color: modelData.primary
                               ? (dlgMouse.containsMouse ? Theme.Colors.accent
                                                         : Qt.alpha(Theme.Colors.accent, 0.85))
                               : (dlgMouse.containsMouse ? Theme.Colors.hover
                                                         : Theme.Colors.raised)
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: dlgLabel
                            anchors.centerIn: parent
                            text: dlgBtn.modelData.id === "cancel"
                                  ? (page.it ? "Annulla" : "Cancel")
                                  : (page.it ? "Connetti" : "Connect")
                            color: dlgBtn.modelData.primary ? Theme.Colors.textOnAccent
                                                            : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightSemiBold
                        }

                        MouseArea {
                            id: dlgMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (dlgBtn.modelData.id === "cancel")
                                    connectDialog.cancel();
                                else
                                    connectDialog.submit();
                            }
                        }
                    }
                }
            }
        }
    }
}
