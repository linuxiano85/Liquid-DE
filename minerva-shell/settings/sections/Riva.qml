import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// La Riva — la pagina dove si decide com'è fatta la scrivania liquida.
//
// Giacomo, 25 settembre 2026: «massima flessibilità e liquid per ogni cosa:
// deve essere facilmente personalizzabile e spaventosamente bello». La Riva
// (angoli, bordi, Isola, molla) nasce con le scelte della simulazione; qui
// ognuna si cambia guardandola. In cima uno schermo in miniatura, vivo:
// gli angoli, i bordi, l'Isola e la dock stanno dove stanno davvero, e si
// toccano. Sotto, le stesse cose scritte per esteso.
Page {
    id: page

    title: page.it ? "La Riva" : "The Shore"
    subtitle: page.it
        ? "Gli angoli, i bordi, l'Isola e la molla: com'è fatta la tua scrivania"
        : "Corners, edges, the Island and the spring: how your desktop is made"

    readonly property bool it: Core.Strings.lang === "it"

    /// L'angolo toccato nella miniatura: la scelta qui sotto è la sua.
    property string angoloScelto: "bassoSx"

    readonly property var nomiAngoli: ({
        "altoSx": "in alto a sinistra", "altoDx": "in alto a destra",
        "bassoSx": "in basso a sinistra", "bassoDx": "in basso a destra"
    })

    // ── Lo schermo in miniatura ─────────────────────────────────────────
    Card {
        heading: page.it ? "Il tuo schermo" : "Your screen"
        note: page.it
            ? "Tocca un angolo e scegli che cosa fa. Tocca l'Isola per nasconderla o tenerla sempre. ⇄ scambia i bordi."
            : "Tap a corner and choose what it does. Tap the Island to hide it or keep it. ⇄ swaps the edges."

        Item {
            id: miniatura
            width: parent.width
            height: Math.min(340, Math.round(width * 0.56))

            readonly property bool dockInAlto: Core.Posizioni.dockInAlto
            readonly property bool barraInBasso: Core.Posizioni.barraInBasso

            // Lo schermo: un fondo che prende l'accento, come uno sfondo.
            Rectangle {
                id: schermo
                anchors.fill: parent
                anchors.margins: 2
                radius: 20
                clip: true
                border.width: 1
                border.color: Theme.Colors.edge
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.tint(Theme.Colors.raised, Qt.alpha(Theme.Colors.accent, 0.30)) }
                    GradientStop { position: 1.0; color: Qt.tint(Theme.Colors.sunken, Qt.alpha(Theme.Colors.accent, 0.08)) }
                }

                // Il TUO sfondo: la miniatura deve sembrare il tuo schermo, non
                // uno schema. Disegnato in una Canvas tagliata a rettangolo
                // tondo: col renderer del processore `clip` taglia diritto, e
                // coprire gli angoli col colore della carta non si può — la
                // finestra può essere trasparente, e sotto c'è la scrivania.
                // La Canvas disegna una copia piccola (640 px, `fonte`), non
                // lo sfondo intero.
                // La copia piccola sta fuori dallo schermo (tagliata via dal
                // `clip`) e se ne fa una fotografia (`grabToImage`): la Canvas
                // disegna la fotografia, non un Image — un Image passato a
                // `drawImage` qui non si disegnava. Caricare lo sfondo intero
                // nella Canvas funzionerebbe, ma sono 33 MB per uno sfondo 4K
                // solo per disegnare una miniatura.
                Image {
                    id: fonte
                    x: -width - 10
                    width: 640; height: 360
                    source: Core.Wallpaper.current !== "" ? "file://" + Core.Wallpaper.current : ""
                    sourceSize.width: 640
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    property string foto: ""
                    onStatusChanged: {
                        if (status !== Image.Ready)
                            return;
                        // La fotografia si salva in un file piccolo: la Canvas
                        // non sa leggere gli indirizzi `itemgrabber:` (provato:
                        // la foto c'è, `onImageLoaded` non arriva mai).
                        fonte.grabToImage(function(risultato) {
                            var file = Core.Ipc.cartellaRuntime + "/miniatura-sfondo"
                                       + (Quickshell.env("MINERVA_PROVA") ? "-prova" : "") + ".png";
                            if (!risultato.saveToFile(file))
                                return;
                            // Un numero in coda perché la Canvas non riusi la
                            // copia vecchia quando lo sfondo cambia.
                            fonte.foto = "file://" + file + "?" + Date.now();
                            tela.loadImage(fonte.foto);
                        });
                    }
                }
                Canvas {
                    id: tela
                    anchors.fill: parent
                    onImageLoaded: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var w = width, h = height, r = schermo.radius;
                        ctx.beginPath();
                        ctx.roundedRect(0.5, 0.5, w - 1, h - 1, r, r);
                        ctx.clip();
                        if (fonte.foto !== "" && isImageLoaded(fonte.foto)) {
                            // La fotografia è 640×360, già ritagliata come
                            // `PreserveAspectCrop`: qui si adatta allo schermo
                            // in miniatura, tagliando in mezzo quel che avanza.
                            var iw = 640, ih = 360;
                            var s = Math.max(w / iw, h / ih);
                            var sw = w / s, sh = h / s;
                            ctx.drawImage(fonte.foto, (iw - sw) / 2, (ih - sh) / 2, sw, sh, 0, 0, w, h);
                        }
                        // Il velo, perché bolle e scritte si leggano su
                        // qualunque sfondo.
                        var g = ctx.createLinearGradient(0, 0, 0, h);
                        g.addColorStop(0, "rgba(0,0,0,0.25)");
                        g.addColorStop(1, "rgba(0,0,0,0.45)");
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, w, h);
                    }
                }

                // Una finestra, per dare la misura.
                Rectangle {
                    x: parent.width * 0.26; y: parent.height * 0.26
                    width: parent.width * 0.48; height: parent.height * 0.46
                    radius: 10
                    color: Qt.alpha(Theme.Colors.panel, 0.85)
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Rectangle {
                        width: parent.width; height: 14; radius: 10
                        color: Qt.alpha(Theme.Colors.text, 0.06)
                    }
                }

                // La dock.
                Rectangle {
                    visible: Core.Ipc.get("dock.enabled", true) === true
                    width: parent.width * 0.44; height: 16; radius: 8
                    x: (parent.width - width) / 2
                    y: miniatura.dockInAlto ? 10 : parent.height - height - 10
                    color: Qt.alpha(Theme.Colors.panel, 0.9)
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Repeater {
                            model: 7
                            delegate: Rectangle { width: 8; height: 8; radius: 3; color: Qt.alpha(Theme.Colors.accent, 0.5 + (index % 3) * 0.15) }
                        }
                    }
                }

                // L'Isola: a scomparsa sbuca per metà dal bordo.
                Rectangle {
                    id: isolaMini
                    readonly property bool nascosta: Core.Ipc.get("bar.aScomparsa", true) === true
                    width: parent.width * 0.3; height: 20; radius: 10
                    x: (parent.width - width) / 2
                    y: miniatura.barraInBasso
                       ? (isolaMini.nascosta ? parent.height - 8 : parent.height - height - 34)
                       : (isolaMini.nascosta ? -12 : 8)
                    Behavior on y {
                        enabled: Theme.Motion.liquido
                        SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                    }
                    color: Theme.Colors.panel
                    border.width: 1
                    border.color: isolaMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.edge
                    Text {
                        anchors.centerIn: parent
                        visible: !isolaMini.nascosta
                        text: Qt.formatTime(new Date(), "HH:mm") + "  ·  ☁ 22°"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: isolaMouse
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("bar.aScomparsa", !isolaMini.nascosta)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: miniatura.barraInBasso ? parent.height - 30 : 14
                    visible: isolaMini.nascosta
                    text: page.it ? "l'Isola, a scomparsa" : "the Island, auto-hidden"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                // I bordi di lato: le Stanze e il Cassetto.
                Repeater {
                    model: [ { "sx": true }, { "sx": false } ]
                    delegate: Item {
                        id: bordo
                        required property var modelData
                        readonly property bool cassetto: bordo.modelData.sx === Core.Riva.cassettoASinistra
                        width: 60; height: parent.height * 0.36
                        x: bordo.modelData.sx ? 6 : parent.width - width - 6
                        y: (parent.height - height) / 2
                        Rectangle {
                            width: 6; height: parent.height; radius: 3
                            x: bordo.modelData.sx ? 0 : parent.width - width
                            color: Qt.alpha(Theme.Colors.accent, 0.55)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: bordo.modelData.sx ? 12 : parent.width - width - 12
                            text: bordo.cassetto ? (page.it ? "Appunti" : "Clipboard")
                                                 : (page.it ? "Stanze" : "Rooms")
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                    }
                }

                // ⇄: scambia i bordi.
                Rectangle {
                    width: 34; height: 34; radius: 17
                    x: (parent.width - width) / 2
                    y: parent.height * 0.72 + 8
                    color: scambioMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.3) : Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Text {
                        anchors.centerIn: parent
                        text: "⇄"
                        color: Theme.Colors.text
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: scambioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("riva.cassetto",
                                                       Core.Riva.cassettoASinistra ? "destra" : "sinistra")
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: schermo.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.Colors.edge
                    z: 3
                }

                // Gli angoli: bolle che si toccano.
                Repeater {
                    model: [
                        { "chiave": "altoSx",  "sx": true,  "alto": true },
                        { "chiave": "altoDx",  "sx": false, "alto": true },
                        { "chiave": "bassoSx", "sx": true,  "alto": false },
                        { "chiave": "bassoDx", "sx": false, "alto": false }
                    ]
                    delegate: Item {
                        id: bolla
                        required property var modelData
                        readonly property var azione: {
                            Core.Riva.altoSx; Core.Riva.altoDx; Core.Riva.bassoSx; Core.Riva.bassoDx;
                            return Core.Riva.azione(Core.Riva.angolo(bolla.modelData.chiave));
                        }
                        readonly property bool scelta: page.angoloScelto === bolla.modelData.chiave
                        width: 44; height: 44
                        x: bolla.modelData.sx ? 10 : parent.width - width - 10
                        y: bolla.modelData.alto ? 10 : parent.height - height - 10
                        z: 2

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: bolla.scelta ? Theme.Colors.accent
                                 : bolla.azione.id === "niente" ? Qt.alpha(Theme.Colors.panel, 0.55)
                                 : Theme.Colors.panel
                            border.width: bolla.scelta ? 0 : 1
                            border.color: bollaMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.edge
                            scale: bolla.scelta ? 1.12 : (bollaMouse.pressed ? 0.92 : 1)
                            Behavior on scale {
                                enabled: Theme.Motion.liquido
                                SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                            }
                            Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                name: bolla.azione.icona
                                color: bolla.scelta ? Theme.Colors.textOnAccent
                                     : bolla.azione.id === "niente" ? Theme.Colors.textFaint
                                     : Theme.Colors.text
                            }
                        }
                        Text {
                            x: bolla.modelData.sx ? parent.width + 8 : -width - 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.it ? bolla.azione.it : bolla.azione.en
                            color: bolla.scelta ? Theme.Colors.accent : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                        MouseArea {
                            id: bollaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.angoloScelto = bolla.modelData.chiave
                        }
                    }
                }
            }
        }

        // La scelta per l'angolo toccato.
        Column {
            width: parent.width
            spacing: Theme.Effects.space2
            topPadding: Theme.Effects.space3
            Text {
                text: (page.it ? "L'angolo " : "The corner ") + page.nomiAngoli[page.angoloScelto]
                      + (page.it ? ": una sosta del puntatore lì" : ": rest the pointer there")
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightMedium
            }
            S.ChoicePicker {
                width: parent.width
                value: {
                    Core.Riva.altoSx; Core.Riva.altoDx; Core.Riva.bassoSx; Core.Riva.bassoDx;
                    return Core.Riva.angolo(page.angoloScelto);
                }
                options: Core.Riva.azioni.map(function(a) {
                    return { "value": a.id, "label": page.it ? a.it : a.en };
                })
                onPicked: function(v) { Core.Ipc.setSetting("riva.angoli." + page.angoloScelto, v); }
            }
            Text {
                text: page.it ? "↺ Torna agli angoli di serie" : "↺ Back to default corners"
                color: angoliMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                MouseArea {
                    id: angoliMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Riva.angoliDiSerie()
                }
            }
        }
    }

    // ── La molla ────────────────────────────────────────────────────────
    Card {
        heading: page.it ? "La molla" : "The spring"
        note: page.it
            ? "Com'è il movimento di tutta la riva: menù, Centro, Isola, Cassetto, Stanze. La pallina te lo fa vedere."
            : "How the whole shore moves: menu, Centre, Island, drawer, rooms. The ball shows you."

        // La pallina che va e viene con la molla scelta.
        Item {
            width: parent.width
            height: 56
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 12; width: parent.width - 24; height: 2; radius: 1
                color: Theme.Colors.edge
            }
            Rectangle {
                id: pallina
                property bool destra: false
                width: 26; height: 26; radius: 13
                anchors.verticalCenter: parent.verticalCenter
                x: pallina.destra ? parent.width - width - 12 : 12
                color: Theme.Colors.accent
                Behavior on x {
                    enabled: Theme.Motion.liquido
                    SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                }
                Timer {
                    interval: 1500
                    running: page.visible
                    repeat: true
                    onTriggered: pallina.destra = !pallina.destra
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Carattere" : "Character"
            description: page.it
                ? "Calma si posa senza rimbalzo; Liquida supera di un soffio e torna; Viva è svelta e ondeggia."
                : "Calm settles without bouncing; Liquid overshoots a breath and returns; Lively is quick and sways."
            controlWidth: 280
            control: S.ChoicePicker {
                value: Core.Riva.molla
                options: [
                    { "value": "calma",   "label": page.it ? "Calma" : "Calm" },
                    { "value": "liquida", "label": page.it ? "Liquida" : "Liquid" },
                    { "value": "viva",    "label": page.it ? "Viva" : "Lively" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("riva.molla", v); }
            }
        }
    }

    // ── L'Isola ─────────────────────────────────────────────────────────
    Card {
        heading: page.it ? "L'Isola" : "The Island"
        visible: Core.Ipc.get("bar.stile", "isola") !== "classica"

        S.SettingRow {
            width: parent.width
            label: page.it ? "A scomparsa" : "Auto-hide"
            description: page.it
                ? "Nascosta oltre il bordo, torna fermando il puntatore lassù: le finestre usano tutto lo schermo."
                : "Hidden past the edge, it comes back when the pointer rests up there."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("bar.aScomparsa", true) === true
                onToggled: function(v) { Core.Ipc.setSetting("bar.aScomparsa", v); }
            }
        }

        Repeater {
            model: [
                { "chiave": "data",    "it": "La data",            "en": "The date",        "d": "Accanto all'ora" },
                { "chiave": "meteo",   "it": "Il tempo che fa",     "en": "The weather",     "d": "Il simbolo e i gradi" },
                { "chiave": "musica",  "it": "La musica",           "en": "Music",           "d": "Quando qualcosa suona, il titolo e le barrette che respirano" },
                { "chiave": "vassoio", "it": "I programmi del vassoio", "en": "Tray apps",   "d": "Le icone dei programmi che vivono senza finestra" },
                { "chiave": "stato",   "it": "I segni di stato",    "en": "Status",          "d": "Rete, Bluetooth, volume e batteria: toccati, il Centro" }
            ]
            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: page.it ? modelData.it : modelData.en
                description: modelData.d
                controlWidth: 60
                control: S.ToggleSwitch {
                    checked: Core.Ipc.get("isola.mostra." + modelData.chiave, true) !== false
                    onToggled: function(v) { Core.Ipc.setSetting("isola.mostra." + modelData.chiave, v); }
                }
            }
        }

        Text {
            text: page.it ? "↺ L'Isola come di serie" : "↺ Default Island"
            color: isolaSerieMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            MouseArea {
                id: isolaSerieMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Core.Riva.isolaDiSerie()
            }
        }
    }

    // ── I bordi e il consenso ───────────────────────────────────────────
    Card {
        heading: page.it ? "I bordi" : "The edges"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Da che parte gli appunti" : "Clipboard side"
            description: page.it
                ? "Spingendo il puntatore contro un bordo escono gli Appunti, contro l'altro le Stanze. Si scambiano anche trascinandoli."
                : "Push against one edge for the clipboard, the other for the rooms. Drag them to swap."
            controlWidth: 240
            control: S.ChoicePicker {
                value: Core.Riva.cassettoASinistra ? "sinistra" : "destra"
                options: [
                    { "value": "sinistra", "label": page.it ? "A sinistra" : "Left" },
                    { "value": "destra",   "label": page.it ? "A destra" : "Right" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("riva.cassetto", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Il consenso di Super" : "Super's consent"
            description: page.it
                ? "Con una finestra che riempie lo schermo, angoli e bordi rispondono solo tenendo Super: niente compare passando col mouse. Tenendo Super salgono l'Isola e la dock."
                : "With a window filling the screen, corners and edges answer only while Super is held."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Riva.conConsenso
                onToggled: function(v) { Core.Ipc.setSetting("riva.consenso", v); }
            }
        }
    }
}
