import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Transfers — I trasferimenti in corso, con pausa, ripresa e annullamento.
//
// La striscia compare solo quando c'è qualcosa da mostrare e sparisce da sola
// qualche secondo dopo l'ultimo lavoro concluso. Un'area permanentemente vuota
// in fondo alla finestra ruba spazio all'elenco per non dire niente.
//
// Tre pulsanti per lavoro perché sono tre cose diverse: la pausa serve a
// liberare il disco mentre si fa altro, la ripresa a tornarci, l'annullamento
// a dire che ci si era sbagliati. Un solo pulsante «ferma» costringerebbe a
// ricominciare una copia da venti minuti per liberare il disco un attimo.
Item {
    id: transfers

    /// Lavori conosciuti, dal più recente. Chiave: identificativo.
    property var jobs: []

    readonly property bool busy: {
        for (var i = 0; i < transfers.jobs.length; i++) {
            var s = transfers.jobs[i].state;
            if (s === "running" || s === "paused")
                return true;
        }
        return false;
    }

    /// Quanti se ne mostrano. Oltre questi la striscia si mangerebbe i
    /// riquadri, che sono il motivo per cui la finestra è aperta.
    readonly property int maximumVisible: 3

    readonly property var visibleJobs: jobs.slice(0, maximumVisible)
    readonly property int hiddenCount: Math.max(0, jobs.length - maximumVisible)

    visible: jobs.length > 0
    implicitHeight: visible ? column.implicitHeight + Theme.Effects.space2 * 2 : 0

    Component.onCompleted: Core.Ipc.fsJobs()

    Connections {
        target: Core.Ipc
        function onFileJobChanged(job) { transfers._merge(job); }
        // Come in Pane.qml: la domanda fatta prima del collegamento va
        // rifatta, altrimenti una copia già in corso quando si apre la
        // finestra non compare finché non avanza.
        function onConnectedChanged() {
            if (Core.Ipc.connected)
                Core.Ipc.fsJobs();
        }
        function onFileJobsReceived(list) {
            transfers.jobs = list ? list.slice().reverse() : [];
        }
    }

    function _merge(job) {
        var copy = transfers.jobs.slice();
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].id === job.id) {
                copy[i] = job;
                transfers.jobs = copy;
                sweeper.restart();
                return;
            }
        }
        copy.unshift(job);
        transfers.jobs = copy;
        sweeper.restart();
    }

    /// Toglie di mezzo i lavori conclusi dopo qualche secondo: serve il tempo
    /// di leggere «fatto», non di guardarlo per sempre.
    Timer {
        id: sweeper
        interval: 6000
        repeat: true
        running: transfers.jobs.length > 0
        onTriggered: {
            var keep = [];
            for (var i = 0; i < transfers.jobs.length; i++) {
                var j = transfers.jobs[i];
                if (j.state === "done" || j.state === "cancelled")
                    continue;
                keep.push(j);
            }
            if (keep.length !== transfers.jobs.length)
                transfers.jobs = keep;
            if (keep.length === 0)
                sweeper.stop();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.raised
        visible: transfers.visible
    }

    // ── I trasferimenti scorrono ─────────────────────────────────────────
    //
    // Qui c'era una `Column` ancorata in alto e basta: con tre copie in corso
    // andava bene, con dieci le ultime **uscivano dal riquadro** e non c'era
    // modo di arrivarci. Non è un caso di scuola — una copia di una cartella
    // grande si spezza in tanti lavori, e il gestore file li mostra tutti.
    Flickable {
        id: rotoloTrasferimenti
        anchors.fill: parent
        contentHeight: column.implicitHeight + Theme.Effects.space2 * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.Effects.space2
            spacing: Theme.Effects.space1

            Repeater {
                model: transfers.visibleJobs

                delegate: Item {
                    id: job
                    required property var modelData

                    width: column.width
                    height: 42

                    readonly property real fraction:
                        modelData.bytesTotal > 0
                        ? Math.max(0, Math.min(1, modelData.bytesDone / modelData.bytesTotal))
                        : 0
                    readonly property bool running: modelData.state === "running"
                    readonly property bool paused: modelData.state === "paused"
                    readonly property bool active: running || paused
                                                   || modelData.state === "cancelling"

                    readonly property color tone:
                        modelData.state === "failed" ? Theme.Colors.danger
                      : modelData.state === "cancelled" ? Theme.Colors.textFaint
                      : modelData.state === "done" ? Theme.Colors.positive
                      : paused ? Theme.Colors.warning
                      : Theme.Colors.accent

                    Ui.Icon {
                        id: jobIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        name: job.modelData.state === "done" ? "check"
                            : job.modelData.state === "failed" ? "close"
                            : job.modelData.move ? "back" : "clipboard"
                        color: job.tone
                    }

                    Column {
                        anchors.left: jobIcon.right
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.right: controls.left
                        anchors.rightMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: {
                                var it = Core.Strings.lang === "it";
                                switch (job.modelData.state) {
                                case "done":
                                    return it ? "Completato" : "Finished";
                                case "cancelled":
                                    return it ? "Annullato" : "Cancelled";
                                case "failed":
                                    return (it ? "Non riuscito: " : "Failed: ")
                                           + (job.modelData.error || "");
                                case "cancelling":
                                    return it ? "Annullamento in corso…" : "Cancelling…";
                                case "paused":
                                    return (it ? "In pausa · " : "Paused · ")
                                           + (job.modelData.currentFile || "");
                                default:
                                    return (job.modelData.move
                                            ? (it ? "Sposto " : "Moving ")
                                            : (it ? "Copio " : "Copying "))
                                           + (job.modelData.currentFile || "");
                                }
                            }
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        // La barra di avanzamento. Con i byte totali già contati
                        // prima di cominciare, non si riempie per poi allungarsi.
                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.Colors.sunken

                            Rectangle {
                                width: parent.width * job.fraction
                                height: parent.height
                                radius: parent.radius
                                color: job.tone
                                Behavior on width {
                                    NumberAnimation { duration: Theme.Motion.instant }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: Files.humanSize(job.modelData.bytesDone) + " / "
                                  + Files.humanSize(job.modelData.bytesTotal)
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                            visible: job.active
                        }
                    }

                    Row {
                        id: controls
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        visible: job.active

                        Repeater {
                            model: [
                                { "id": "pauseResume" },
                                { "id": "cancel" }
                            ]

                            delegate: Rectangle {
                                id: ctl
                                required property var modelData

                                readonly property bool isCancel: modelData.id === "cancel"
                                readonly property color tone: isCancel ? Theme.Colors.danger
                                                                       : Theme.Colors.accent

                                width: 24; height: 24
                                radius: 12
                                color: ctlMouse.containsMouse ? Qt.alpha(tone, 0.18) : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                                Ui.Icon {
                                    anchors.centerIn: parent
                                    width: 13; height: 13
                                    name: ctl.isCancel ? "close"
                                        : (job.paused ? "chevron" : "minimize")
                                    color: ctlMouse.containsMouse ? ctl.tone : Theme.Colors.textFaint
                                }

                                MouseArea {
                                    id: ctlMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (ctl.isCancel)
                                            Core.Ipc.fsCancel(job.modelData.id);
                                        else if (job.paused)
                                            Core.Ipc.fsResume(job.modelData.id);
                                        else
                                            Core.Ipc.fsPause(job.modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: column.width
                horizontalAlignment: Text.AlignHCenter
                visible: transfers.hiddenCount > 0
                text: Core.Strings.lang === "it"
                      ? "e altri " + transfers.hiddenCount + " in coda"
                      : "and " + transfers.hiddenCount + " more queued"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

    }

    // FUORI dal Flickable, non dentro: un figlio si sposta insieme al
    // contenuto, e la barra scorrerebbe via con quello che deve misurare.
    Ui.Scorrimento {
        bersaglio: rotoloTrasferimenti
        anchors {
            right: rotoloTrasferimenti.right
            top: rotoloTrasferimenti.top
            bottom: rotoloTrasferimenti.bottom
        }
    }
}
