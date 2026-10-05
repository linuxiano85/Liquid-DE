import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// CalendarPanel — Il calendario che scende dall'orologio.
//
// Un mese alla volta, con oggi in evidenza. Niente appuntamenti: non abbiamo
// un'agenda da cui prenderli, e un calendario che finge di averla mostrando
// sempre «nessun evento» è peggio di uno che non ci prova.
//
// Serve a rispondere a una domanda sola — «che giorno è il 14?» — e a quella
// deve rispondere senza far pensare.
Item {
    id: panel

    property var spine: null

    readonly property real implicitPanelHeight:
        Theme.Effects.space5 + header.height + Theme.Effects.space3
        + weekRow.height + grid.height + Theme.Effects.space4 + footer.height
        + Theme.Effects.space3 + macchina.height + Theme.Effects.space4

    // ── Come sta il computer ─────────────────────────────────────────────
    //
    // Tre numeri sotto il calendario: quanto lavora il processore, quanta
    // memoria è occupata, quanto scalda. Sono le tre cose che si guardano
    // quando il computer «va piano», e finora bisognava aprire il gestore
    // attività per saperlo — una finestra intera per tre numeri.
    //
    // ── Perché non chiede l'elenco dei processi ──────────────────────────
    //
    // L'elenco dei processi porta anche questi numeri. Ma legge `/proc` per
    // OGNI processo del computer: farlo ogni tre secondi per riempire una
    // striscia alta venti pixel vorrebbe dire diventare il consumo che si sta
    // misurando. Il demone ha un'azione apposta che legge solo `/proc/stat`,
    // `/proc/meminfo` e il termometro.
    //
    // E si chiede SOLO mentre il pannello è aperto: un calendario chiuso che
    // continua a interrogare la macchina è esattamente il genere di spreco che
    // non si vede e non si spegne più.
    property var stato: ({})

    Connections {
        target: Core.Ipc
        function onMachineStateReceived(m) { panel.stato = m || ({}); }
    }

    Timer {
        id: ronda
        interval: 3000
        repeat: true
        running: panel.visible
        triggeredOnStart: true
        onTriggered: Core.Ipc.machineState()
    }

    function percento(v) {
        return (v === undefined || v === null) ? "—" : Math.round(v) + "%"
    }

    readonly property real memoriaPercento: {
        var t = panel.stato.memoriaTotale || 0;
        var u = panel.stato.memoriaUsata || 0;
        return t > 0 ? (u / t) * 100 : -1;
    }

    readonly property var locale: Core.Strings.lang === "it" ? Qt.locale("it_IT")
                                                             : Qt.locale("en_GB")

    /// Primo del mese mostrato. Si sposta con le frecce.
    property date shown: new Date()
    readonly property date today: new Date()

    function step(months) {
        var d = new Date(panel.shown);
        d.setDate(1);
        d.setMonth(d.getMonth() + months);
        panel.shown = d;
    }

    function backToToday() {
        panel.shown = new Date();
    }

    readonly property int shownYear: shown.getFullYear()
    readonly property int shownMonth: shown.getMonth()

    /// Quante caselle vuote prima del giorno 1. La settimana comincia di lunedì
    /// in italiano e di lunedì anche in inglese britannico: `getDay()` invece
    /// conta da domenica, quindi va ruotato.
    readonly property int leadingBlanks: {
        var first = new Date(shownYear, shownMonth, 1).getDay();
        return (first + 6) % 7;
    }

    readonly property int daysInMonth:
        new Date(shownYear, shownMonth + 1, 0).getDate()

    function isToday(day) {
        return day === today.getDate()
            && shownMonth === today.getMonth()
            && shownYear === today.getFullYear();
    }

    // ── Intestazione: mese, anno, frecce ─────────────────────────────────

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space5
        height: 30

        Text {
            id: monthLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var name = panel.shown.toLocaleDateString(panel.locale, "MMMM");
                return name.charAt(0).toUpperCase() + name.slice(1)
                       + " " + panel.shownYear;
            }
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightSemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Repeater {
                model: [
                    { "id": "prev",  "icon": "chevronUp",  "rot": -90 },
                    { "id": "today", "icon": "pin",        "rot": 0 },
                    { "id": "next",  "icon": "chevronUp",  "rot": 90 }
                ]

                delegate: Rectangle {
                    id: navBtn
                    required property var modelData

                    width: 26; height: 26
                    radius: Theme.Effects.radiusXS
                    color: navMouse.containsMouse ? Theme.Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        name: navBtn.modelData.icon
                        rotation: navBtn.modelData.rot
                        color: navMouse.containsMouse ? Theme.Colors.accent
                                                      : Theme.Colors.textFaint
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            switch (navBtn.modelData.id) {
                            case "prev":  panel.step(-1); break;
                            case "next":  panel.step(1); break;
                            case "today": panel.backToToday(); break;
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Iniziali dei giorni ──────────────────────────────────────────────

    Row {
        id: weekRow
        anchors.top: header.bottom
        anchors.topMargin: Theme.Effects.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        height: 22

        readonly property real cell: width / 7

        Repeater {
            // Lunedì → domenica. Scritte a mano e non prese dal locale perché
            // in italiano tre giorni su sette comincerebbero per «m» o «s».
            model: Core.Strings.lang === "it"
                   ? ["L", "M", "M", "G", "V", "S", "D"]
                   : ["M", "T", "W", "T", "F", "S", "S"]

            delegate: Item {
                required property var modelData
                required property int index
                width: weekRow.cell
                height: weekRow.height

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    // Sabato e domenica più tenui: si distingue il fine
                    // settimana senza colorarlo.
                    color: parent.index >= 5 ? Theme.Colors.textFaint
                                             : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                    font.weight: Theme.Typography.weightBold
                    font.letterSpacing: Theme.Typography.trackingLabel
                }
            }
        }
    }

    // ── La griglia dei giorni ────────────────────────────────────────────

    Grid {
        id: grid
        anchors.top: weekRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        columns: 7
        rows: 6

        readonly property real cell: width / 7

        Repeater {
            model: 42

            delegate: Item {
                id: box
                required property int index

                readonly property int day: box.index - panel.leadingBlanks + 1
                readonly property bool inMonth: day >= 1 && day <= panel.daysInMonth
                readonly property bool weekend: (box.index % 7) >= 5

                width: grid.cell
                height: grid.cell

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) - 4
                    height: width
                    radius: width / 2
                    visible: box.inMonth
                    color: panel.isToday(box.day) ? Theme.Colors.accent
                         : dayMouse.containsMouse ? Theme.Colors.hover
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        anchors.centerIn: parent
                        text: box.day
                        color: panel.isToday(box.day) ? Theme.Colors.textOnAccent
                             : box.weekend ? Theme.Colors.textFaint
                             : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: panel.isToday(box.day)
                                     ? Theme.Typography.weightBold
                                     : Theme.Typography.weightRegular
                    }
                }

                MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    hoverEnabled: box.inMonth
                    acceptedButtons: Qt.NoButton
                }
            }
        }
    }

    // ── La data di oggi, per esteso ──────────────────────────────────────

    Item {
        id: footer
        anchors.top: grid.bottom
        anchors.topMargin: Theme.Effects.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        height: 34

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.Colors.edge
        }

        Text {
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: {
                var s = panel.today.toLocaleDateString(panel.locale, "dddd d MMMM yyyy");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── La striscia di come sta il computer ──────────────────────────────

    Row {
        id: macchina
        anchors.top: footer.bottom
        anchors.topMargin: Theme.Effects.space3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        height: 44
        spacing: Theme.Effects.space2

        readonly property real cella: (width - spacing * 2) / 3

        component Misura: Item {
            id: misura
            property string titolo: ""
            property string valore: "—"
            /// Da 0 a 100. Sotto zero = non lo sappiamo, e la barra non si
            /// disegna invece di disegnarsi vuota: «zero» e «non lo so» sono
            /// due notizie diverse.
            property real quanto: -1

            width: macchina.cella
            height: macchina.height

            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: 3

                Text {
                    textFormat: Text.PlainText
                    text: misura.titolo
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Text {
                    text: misura.valore
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 1.5
                    visible: misura.quanto >= 0
                    color: Theme.Colors.sunken

                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, misura.quanto / 100))
                        height: parent.height
                        radius: parent.radius
                        // Sopra l'ottanta per cento il colore cambia: è il
                        // punto in cui il numero smette di essere una
                        // curiosità e diventa la ragione per cui il computer
                        // sta andando piano.
                        color: misura.quanto >= 80 ? Theme.Colors.warning
                                                   : Theme.Colors.accent
                        Behavior on width {
                            NumberAnimation { duration: Theme.Motion.quick }
                        }
                    }
                }
            }
        }

        Misura {
            titolo: Core.Strings.lang === "it" ? "Processore" : "Processor"
            valore: panel.percento(panel.stato.cpu)
            quanto: panel.stato.cpu !== undefined ? panel.stato.cpu : -1
        }

        Misura {
            titolo: Core.Strings.lang === "it" ? "Memoria" : "Memory"
            valore: panel.memoriaPercento >= 0
                    ? panel.percento(panel.memoriaPercento) : "—"
            quanto: panel.memoriaPercento
        }

        Misura {
            titolo: Core.Strings.lang === "it" ? "Temperatura" : "Temperature"
            // Senza termometro leggibile non si inventa un numero: si dice
            // che non c'è. Su parecchi portatili il sensore non è esposto.
            valore: panel.stato.temperatura !== undefined
                    ? Math.round(panel.stato.temperatura) + "°" : "—"
            // La barra della temperatura andrebbe da 30 a 100 gradi, non da
            // 0: sotto i trenta un computer acceso non ci sta mai, e una
            // barra che parte da lì sembra sempre a metà.
            quanto: panel.stato.temperatura !== undefined
                    ? (panel.stato.temperatura - 30) / 0.7 : -1
        }
    }
}
