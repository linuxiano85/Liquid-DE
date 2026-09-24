import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ── Il Centro di controllo di Liquid DE ──────────────────────────────────
//
// Giacomo, 23 settembre 2026: «e se nel caso vogliamo spegnere il pc o
// riavviarlo o bloccare lo schermo? e se vogliamo la modalità notte e wifi
// eccetera? modalità non disturbare e altro dove le mettiamo?». Qui, in un
// posto solo: scende dall'angolo in alto a destra (la sosta del puntatore,
// `Core.Compositore.angolo`) o dalla barra, con la molla.
//
// Le levette usano gli stessi comandi del pannello di prima
// (`spine/panels/ControlPanel.qml`): cambia la forma, non chi fa le cose.
// Esci, Riavvia e Spegni non chiedono «sei sicuro?»: si TENGONO premuti, e il
// pulsante si riempie d'acqua; lasciato prima, non succede niente.
//
// Come il Sottomarino, una finestra sola a tutto schermo che esiste solo
// mentre il Centro è aperto: il fondo raccoglie i clic fuori.
PanelWindow {
    id: centro

    property bool aperto: false
    property bool mostrato: false
    /// Spazio da lasciare in alto (la barra) e in basso (la dock).
    property real margineAlto: 0
    property real margineBasso: 0

    /// Un'azione dei pulsanti dell'energia: la esegue la shell.
    signal azione(string id)

    /// Vero in una sessione di prova: lì il Wi-Fi e il Bluetooth sono quelli
    /// VERI del computer, e spegnerli taglierebbe il collegamento con chi sta
    /// lavorando. In prova le due levette non toccano niente.
    readonly property bool inProva: !!Quickshell.env("MINERVA_PROVA")

    function apri() {
        if (centro.aperto) return;
        centro.aperto = true;
        centro.mostrato = true;
        spegni.stop();
    }
    function chiudi() {
        if (!centro.aperto) return;
        centro.aperto = false;
        spegni.restart();
    }
    function commuta() { centro.aperto ? centro.chiudi() : centro.apri(); }

    visible: centro.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-centro"
    WlrLayershell.layer: WlrLayer.Overlay
    // La tastiera la prende SUBITO, come il Sottomarino. Con «al primo clic»
    // (OnDemand) la finestra diventava attiva proprio sulla pressione, e Qt
    // annullava quel clic: levette e pulsanti non rispondevano mai col
    // touchpad vero (visto dalla sonda il 24/09: «premuto» e subito
    // «annullato»). Le barre si salvavano solo perché proteggono la presa.
    WlrLayershell.keyboardFocus: centro.aperto ? WlrKeyboardFocus.Exclusive
                                               : WlrKeyboardFocus.None

    Timer { id: spegni; interval: Theme.Motion.liquido ? 650 : 0; onTriggered: if (!centro.aperto) centro.mostrato = false }

    // Il fondo: premere fuori chiude, già alla pressione. Al rilascio non
    // bastava: col touchpad un tocco che si sposta di un soffio fra pressione
    // e rilascio non è un clic, e il Centro restava aperto.
    MouseArea {
        anchors.fill: parent
        enabled: centro.aperto
        onPressed: centro.chiudi()
    }

    Item {
        anchors.fill: parent
        focus: centro.aperto
        Keys.onEscapePressed: centro.chiudi()
    }

    // ── Il pannello ─────────────────────────────────────────────────────
    Rectangle {
        id: pannello
        readonly property int margine: Theme.Effects.space4
        width: 392
        height: colonna.implicitHeight + 2 * Theme.Effects.space4
        x: centro.width - margine - width
        y: centro.aperto ? margine + centro.margineAlto : -height - 30
        Behavior on y {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla * 0.6; damping: 0.42 }
        }
        radius: Theme.Effects.radiusLG
        // Quasi pieno: col vetro trasparente di serie i riquadri della
        // scrivania dietro si leggevano ATTRAVERSO le levette e le app.
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: colonna
            x: Theme.Effects.space4
            y: Theme.Effects.space4
            width: pannello.width - 2 * Theme.Effects.space4
            spacing: Theme.Effects.space3
            opacity: centro.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

            // Le sei levette.
            Grid {
                columns: 2
                spacing: Theme.Effects.space2
                width: parent.width

                Levetta {
                    nome: "Wi-Fi"
                    acceso: Core.SystemState.wifiOn
                    detto: "connesso"
                    onScelto: if (!centro.inProva) Core.SystemState.setWifi(!Core.SystemState.wifiOn)
                }
                Levetta {
                    nome: "Bluetooth"
                    acceso: Core.SystemState.bluetoothOn
                    detto: "acceso"
                    onScelto: if (!centro.inProva) Core.SystemState.setBluetooth(!Core.SystemState.bluetoothOn)
                }
                Levetta {
                    nome: "Luce notturna"
                    acceso: Core.Ipc.get("display.nightLight", false) === true
                    detto: "schermo caldo"
                    onScelto: Core.Ipc.setSetting("display.nightLight", !acceso)
                }
                Levetta {
                    nome: "Non disturbare"
                    acceso: Core.Notifications.doNotDisturb
                    detto: "notifiche in silenzio"
                    onScelto: Core.Ipc.setSetting("notifications.doNotDisturb", !acceso)
                }
                Levetta {
                    nome: "Risparmio"
                    acceso: Core.Compositore.risparmio && Core.Compositore.risparmio.attivo === true
                    detto: "effetti ridotti"
                    onScelto: Core.Ipc.setSetting("power.risparmioEffetti", acceso ? "auto" : "sempre")
                }
                Levetta {
                    nome: "Modo gioco"
                    acceso: Core.Gioco.attiva
                    detto: "notifiche zitte"
                    onScelto: Core.Gioco.forzato = !Core.Gioco.forzato
                }
            }

            // Volume e luminosità: barre che si riempiono.
            Liquido {
                nome: "Volume"
                valore: Core.SystemState.volume
                visible: valore >= 0
                onCambiato: function(v) { Core.SystemState.setVolume(v); }
            }
            Liquido {
                nome: "Luminosità"
                valore: Core.SystemState.brightness
                visible: valore >= 0
                onCambiato: function(v) { Core.SystemState.setBrightness(Math.max(5, v)); }
            }

            // Il lettore, quando c'è qualcosa che suona.
            Rectangle {
                width: parent.width
                height: 56
                visible: Core.Media.cQualcosa
                radius: Theme.Effects.radiusMD
                color: Theme.Colors.raised

                Image {
                    id: copertina
                    x: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: Core.Media.copertina || ""
                    sourceSize.width: 80; sourceSize.height: 80
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors.fill: copertina
                    visible: !copertina.visible
                    radius: Theme.Effects.radiusSM
                    color: Qt.alpha(Theme.Colors.accent, 0.35)
                }
                Column {
                    anchors.left: copertina.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: tasti.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Core.Media.titolo
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Core.Media.artista
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
                Row {
                    id: tasti
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [
                            { "icona": "prev", "fa": "prec" },
                            { "icona": Core.Media.inRiproduzione ? "pause" : "play", "fa": "suona" },
                            { "icona": "next", "fa": "succ" }
                        ]
                        delegate: Rectangle {
                            id: tasto
                            required property var modelData
                            width: 32; height: 32; radius: 16
                            color: tastoMouse.containsMouse ? Theme.Colors.hover : "transparent"
                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                name: tasto.modelData.icona
                                color: Theme.Colors.text
                            }
                            MouseArea {
                                id: tastoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (tasto.modelData.fa === "prec") Core.Media.precedente();
                                    else if (tasto.modelData.fa === "succ") Core.Media.successivo();
                                    else Core.Media.riproduci();
                                }
                            }
                        }
                    }
                }
            }

            // L'energia.
            Row {
                width: parent.width
                spacing: Theme.Effects.space1
                Repeater {
                    model: [
                        { "id": "blocca",   "it": "Blocca",   "tieni": false },
                        { "id": "sospendi", "it": "Sospendi", "tieni": false },
                        { "id": "esci",     "it": "Esci",     "tieni": true },
                        { "id": "riavvia",  "it": "Riavvia",  "tieni": true },
                        { "id": "spegni",   "it": "Spegni",   "tieni": true }
                    ]
                    delegate: Energia {
                        width: (colonna.width - 4 * Theme.Effects.space1) / 5
                        onFatto: function(id) { centro.chiudi(); centro.azione(id); }
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Esci, Riavvia e Spegni: tieni premuto finché non si riempie, o tocca due volte."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Una levetta ─────────────────────────────────────────────────────
    component Levetta: Rectangle {
        id: lev
        property string nome: ""
        property bool acceso: false
        property string detto: ""
        signal scelto()
        width: 179
        height: 58
        radius: Theme.Effects.radiusMD
        color: lev.acceso ? Qt.alpha(Theme.Colors.accent, 0.22) : Theme.Colors.raised
        border.width: 1
        border.color: lev.acceso ? Qt.alpha(Theme.Colors.accent, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
        scale: levMouse.pressed ? 0.96 : 1
        Behavior on scale {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
        }
        Column {
            x: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 2 * Theme.Effects.space3
            Text {
                text: lev.nome
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: lev.acceso ? lev.detto : "spento"
                color: lev.acceso ? Theme.Colors.accent : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
        MouseArea {
            id: levMouse
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lev.scelto()
        }
    }

    // ── Una barra che si riempie: volume, luminosità ────────────────────
    component Liquido: Rectangle {
        id: liq
        property string nome: ""
        property int valore: 0
        signal cambiato(int v)
        /// Mentre si trascina si mostra quello che dice il dito, non quello
        /// che il sistema ha già applicato: un volume che salta indietro
        /// sotto il dito è peggio di uno che arriva un attimo dopo.
        property int _dito: -1
        /// Il valore da mandare al sistema: uno per volta, al passo del timer.
        /// Mandarne uno a ogni pixel di trascinamento accodava comandi, e il
        /// volume arrivava in ritardo e a scatti.
        property int _daMandare: -1
        Timer {
            id: manda
            interval: 40
            repeat: true
            running: liq._daMandare >= 0
            onTriggered: {
                if (liq._daMandare >= 0) liq.cambiato(liq._daMandare);
                liq._daMandare = -1;
            }
        }
        readonly property int mostrato: liq._dito >= 0 ? liq._dito : Math.max(0, liq.valore)
        width: parent ? parent.width : 300
        height: 40
        radius: height / 2
        color: Theme.Colors.raised
        clip: true
        Rectangle {
            width: Math.max(liq.height, liq.width * liq.mostrato / 100)
            height: parent.height
            radius: height / 2
            color: Qt.alpha(Theme.Colors.accent, 0.45)
            Behavior on width {
                enabled: Theme.Motion.liquido && liq._dito < 0
                SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
            }
        }
        Text {
            x: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            text: liq.nome
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            text: liq.mostrato + "%"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeSM
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            function _da(ev) {
                return Math.round(Math.max(0, Math.min(1, ev.x / liq.width)) * 100);
            }
            onPressed: function(ev) { liq._dito = _da(ev); liq.cambiato(liq._dito); }
            onPositionChanged: function(ev) {
                if (!pressed) return;
                liq._dito = _da(ev);
                liq._daMandare = liq._dito;
            }
            onReleased: {
                // L'ultimo valore parte subito, non al prossimo giro del timer.
                if (liq._dito >= 0) liq.cambiato(liq._dito);
                liq._daMandare = -1;
                liq._dito = -1;
            }
            onWheel: function(ev) {
                liq.cambiato(Math.max(0, Math.min(100, liq.valore + (ev.angleDelta.y > 0 ? 5 : -5))));
            }
        }
    }

    // ── Un pulsante dell'energia ────────────────────────────────────────
    component Energia: Rectangle {
        id: en
        required property var modelData
        signal fatto(string id)
        /// Da 0 a 1 mentre lo si tiene premuto; a 1 parte.
        property real pieno: 0
        /// Armato da un primo tocco: il secondo, entro tre secondi, conferma.
        /// È la via del touchpad, dove tenere il dito appoggiato non tiene
        /// premuto niente.
        property bool armato: false
        height: 44
        radius: Theme.Effects.radiusMD
        clip: true
        color: en.modelData.tieni ? Theme.Colors.raised : Qt.alpha(Theme.Colors.accent, 0.12)
        border.width: 1
        border.color: enMouse.pressed && en.modelData.tieni ? Qt.alpha(Theme.Colors.danger, 0.7)
                                                            : "transparent"
        // L'acqua che sale. Con gli stessi angoli del pulsante: in QML il
        // ritaglio è rettangolare, e un'acqua squadrata sporgeva dagli angoli.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * en.pieno
            radius: Math.min(en.radius, height / 2)
            color: Qt.alpha(Theme.Colors.danger, 0.55)
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: en.armato
            color: Qt.alpha(Theme.Colors.danger, 0.35)
        }
        Timer { id: disarma; interval: 3000; onTriggered: en.armato = false }
        Text {
            anchors.centerIn: parent
            text: en.armato ? "Ancora" : en.modelData.it
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightMedium
        }
        NumberAnimation {
            id: riempi
            target: en
            property: "pieno"
            from: 0; to: 1
            duration: 900
            onFinished: if (en.pieno >= 1) { en.pieno = 0; en.fatto(en.modelData.id); }
        }
        MouseArea {
            id: enMouse
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: if (en.modelData.tieni) riempi.restart()
            onReleased: {
                if (!en.modelData.tieni) {
                    en.fatto(en.modelData.id);
                    return;
                }
                if (!riempi.running)
                    return;             // era pieno: è già partito
                riempi.stop();
                en.pieno = 0;
                // Un tocco breve: il primo arma, il secondo conferma.
                if (en.armato) {
                    en.armato = false;
                    disarma.stop();
                    en.fatto(en.modelData.id);
                } else {
                    en.armato = true;
                    disarma.restart();
                }
            }
            onCanceled: { riempi.stop(); en.pieno = 0; }
        }
    }
}
