import QtQuick
import QtMultimedia
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Lettore — Un video da guardare, coi comandi che servono e basta.
//
// ── Perché esiste ──────────────────────────────────────────────────────────
//
// Giacomo, 6 ottobre 2026: «se sono in galleria e clicco su un video si apre
// Minerva Media… è disorganizzato». Deciso con lui: ognuno il suo mestiere.
// Le fotografie e i video della propria vita si guardano dove stanno — in
// Anteprima, scorrendo foto e filmati insieme — e Minerva Media resta il
// lettore di musica e film, con playlist, taglio e scaricamenti.
//
// Questo è il pezzo che fa vedere un video, scritto una volta: lo usa
// Anteprima, e lo potrà usare Media al posto della sua superficie.
//
// ── Cosa NON fa ────────────────────────────────────────────────────────────
//
// Niente playlist, niente sottotitoli da scegliere, niente picture-in-picture:
// sono le cose per cui si apre Minerva Media. Qui: play, pausa, dove sei,
// salta, volume.
Item {
    id: lettore

    /// Il file da riprodurre (percorso assoluto). Cambiandolo si ferma quello
    /// di prima e parte questo.
    property string sorgente: ""
    property bool parteDaSolo: true

    /// Sta suonando: chi ci ospita tiene lo schermo acceso (vedi Anteprima).
    readonly property bool suona: player.playbackState === MediaPlayer.PlayingState
    readonly property bool it: Core.Strings.lang === "it"

    /// Doppio clic: chi ci ospita sa come si va a schermo intero.
    signal schermoInteroChiesto()

    function commuta() {
        if (lettore.suona)
            player.pause();
        else
            player.play();
        lettore.mostraComandi();
    }

    function salta(ms) {
        player.position = Math.max(0, Math.min(player.duration, player.position + ms));
        lettore.mostraComandi();
    }

    function volumeDi(delta) {
        uscitaAudio.volume = Math.max(0, Math.min(1, uscitaAudio.volume + delta));
        lettore.mostraComandi();
    }

    function ferma() {
        player.stop();
    }

    function _url(p) {
        return p === "" ? "" : "file://" + String(p).split("/").map(encodeURIComponent).join("/");
    }

    onSorgenteChanged: {
        player.stop();
        player.source = lettore._url(lettore.sorgente);
        if (lettore.sorgente !== "" && lettore.parteDaSolo)
            player.play();
        lettore.mostraComandi();
    }

    // Un lettore nascosto (si torna alla galleria, si passa a una foto) non
    // deve continuare a suonare dove non lo si vede.
    onVisibleChanged: if (!visible) player.pause()

    AudioOutput {
        id: uscitaAudio
        volume: 1.0
    }

    MediaPlayer {
        id: player
        audioOutput: uscitaAudio
        videoOutput: uscita
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    VideoOutput {
        id: uscita
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    // ── I comandi spariscono mentre si guarda ────────────────────────────
    property bool _comandiVisibili: true

    function mostraComandi() {
        lettore._comandiVisibili = true;
        nascondi.restart();
    }

    Timer {
        id: nascondi
        interval: 2500
        onTriggered: if (lettore.suona && !barraMouse.containsMouse) lettore._comandiVisibili = false
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: lettore._comandiVisibili ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: lettore.mostraComandi()
        onClicked: lettore.commuta()
        onDoubleClicked: lettore.schermoInteroChiesto()
    }

    // In pausa, il triangolo grande in mezzo: si capisce che è un video e
    // che si può far partire.
    Rectangle {
        anchors.centerIn: parent
        width: 84
        height: 84
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: !lettore.suona && player.error === MediaPlayer.NoError && lettore.sorgente !== ""
        Ui.Icon {
            anchors.centerIn: parent
            width: 34
            height: 34
            name: "play"
            color: "white"
            alwaysDrawn: true
        }
    }

    // Quando non si riesce: si dice perché, e cosa si può fare.
    Column {
        anchors.centerIn: parent
        spacing: Theme.Effects.space2
        visible: player.error !== MediaPlayer.NoError
        width: Math.min(parent.width - 40, 460)
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: lettore.it ? "Questo video non si riesce a riprodurre qui."
                             : "This video can't be played here."
            color: "white"
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: player.errorString
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── La barra ─────────────────────────────────────────────────────────
    Rectangle {
        id: barra
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space3
        height: 44
        radius: Theme.Effects.radiusMD
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: lettore._comandiVisibili || !lettore.suona ? 1 : 0
        visible: opacity > 0 && player.error === MediaPlayer.NoError
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        MouseArea {
            id: barraMouse
            anchors.fill: parent
            hoverEnabled: true
        }

        Row {
            id: sinistra
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space3

            Item {
                width: 28
                height: 28
                Ui.Icon {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    name: lettore.suona ? "pause" : "play"
                    color: "white"
                    alwaysDrawn: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: lettore.commuta()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Core.Formato.durata(player.position / 1000) + " / "
                      + Core.Formato.durata(player.duration / 1000)
                color: "white"
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        // Il volume, a destra: clic sull'icona per il muto.
        Item {
            id: volumeBox
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28
            Ui.Icon {
                anchors.centerIn: parent
                width: 18
                height: 18
                name: uscitaAudio.muted || uscitaAudio.volume === 0 ? "muted" : "volume"
                color: "white"
                alwaysDrawn: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: uscitaAudio.muted = !uscitaAudio.muted
                onWheel: function (w) { lettore.volumeDi(w.angleDelta.y > 0 ? 0.05 : -0.05); }
            }
        }

        // Dove sei: si clicca o si trascina per saltare.
        Item {
            anchors.left: sinistra.right
            anchors.leftMargin: Theme.Effects.space4
            anchors.right: volumeBox.left
            anchors.rightMargin: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            height: 20

            Rectangle {
                id: binario
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle {
                    width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                    height: parent.height
                    radius: 2
                    color: Theme.Colors.accent
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function vai(x) {
                    if (player.duration > 0)
                        player.position = Math.max(0, Math.min(1, x / width)) * player.duration;
                    lettore.mostraComandi();
                }
                onPressed: function (m) { vai(m.x); }
                onPositionChanged: function (m) { if (pressed) vai(m.x); }
            }
        }
    }
}
