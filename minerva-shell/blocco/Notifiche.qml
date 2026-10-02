import QtQuick
import Quickshell
import Quickshell.Io

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Notifiche — Quello che è arrivato mentre eri via, sulla schermata di blocco.
//
// Giacomo, 23 settembre 2026: «se mi arrivano mail mi dice solo che ci sono ad
// esempio 3 email, tipo come gli smartphone», e «sulla parte libera metterei
// tutte le notifiche».
//
// ── Da dove arrivano ───────────────────────────────────────────────────────
//
// Le notifiche le riceve la SHELL, che è un altro processo. Le scrive in un
// file della cartella di sessione (`Core.Notifications._perIlBlocco`), e lo
// scrive già filtrato secondo la privacy scelta: con «numero» qui dentro non
// arriva il testo di niente, solo i nomi dei programmi e quante. Questo file
// quindi non decide cosa nascondere — non può mostrare quello che non ha.
//
// Se la shell non c'è (ferma, riavviata), il file resta quello dell'ultima
// scrittura, o non c'è: il pannello resta vuoto. Una schermata di blocco non
// aspetta nessuno per disegnarsi.
Item {
    id: pannello

    property bool it: Core.Strings.lang === "it"

    property var dati: ({ "modo": "numero", "gruppi": [], "voci": [] })
    readonly property bool completo: pannello.dati.modo === "tutto"
    readonly property var elenco: pannello.completo ? pannello.dati.voci : pannello.dati.gruppi
    readonly property int totale: {
        var n = 0;
        var g = pannello.dati.gruppi || [];
        for (var i = 0; i < g.length; i++)
            n += g[i].quante;
        return n;
    }

    visible: pannello.totale > 0 && pannello.dati.modo !== "niente"

    FileView {
        id: file
        path: Core.Ipc.cartellaSessione !== ""
              ? Core.Ipc.cartellaSessione + "/notifiche-blocco.json" : ""
        // Si guarda il file: una mail che arriva mentre il blocco è su deve
        // comparire, come sul telefono.
        watchChanges: true
        printErrors: false
        onFileChanged: file.reload()
        onLoaded: pannello._leggi()
    }

    function _leggi() {
        try {
            var d = JSON.parse(file.text());
            if (d && d.gruppi !== undefined)
                pannello.dati = d;
        } catch (e) {
            // Un file a metà (non capita: si scrive in modo atomico) o vuoto.
        }
    }

    function _ora(ms) {
        if (!ms) return "";
        return Qt.formatTime(new Date(ms), Core.Ipc.get("clock.format24", true) ? "HH:mm" : "h:mm AP");
    }

    function _quante(g) {
        if (g.posta)
            return g.quante === 1 ? (pannello.it ? "1 email" : "1 email")
                                  : g.quante + (pannello.it ? " email" : " emails");
        return g.quante === 1 ? (pannello.it ? "1 notifica" : "1 notification")
                              : g.quante + (pannello.it ? " notifiche" : " notifications");
    }

    Column {
        id: colonna
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.Effects.space2

        Text {
            text: (pannello.it ? "Mentre eri via" : "While you were away")
                  + "  ·  " + pannello.totale
            color: Qt.alpha(Theme.Colors._bianco, 0.62)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
            font.letterSpacing: Theme.Typography.trackingLabel
            bottomPadding: Theme.Effects.space1
        }

        Repeater {
            model: pannello.elenco

            delegate: Rectangle {
                id: scheda
                required property var modelData
                required property int index

                width: colonna.width
                height: corpo.implicitHeight + Theme.Effects.space4 * 2
                radius: 18
                color: Qt.alpha(Theme.Colors._nero, 0.34)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors._bianco, 0.14)

                // Entrano una dopo l'altra, dal basso: una lista che compare
                // tutta insieme sembra un modulo, una che arriva sembra posta.
                opacity: 0
                transform: Translate { id: entrata; y: 12 }
                Component.onCompleted: arrivo.start()
                SequentialAnimation {
                    id: arrivo
                    PauseAnimation { duration: 60 * scheda.index }
                    ParallelAnimation {
                        NumberAnimation { target: scheda; property: "opacity"; to: 1
                                          duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
                        NumberAnimation { target: entrata; property: "y"; to: 0
                                          duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
                    }
                }

                // Il simbolo: una busta per la posta, una campanella per il resto.
                Rectangle {
                    id: bollo
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space4
                    anchors.top: parent.top
                    anchors.topMargin: Theme.Effects.space4
                    width: 34; height: 34
                    radius: width / 2
                    color: Qt.alpha(Theme.Colors.accent, 0.22)

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 17; height: 17
                        // `posta` arriva già nel file: da QUI non si tocca
                        // `Core.Notifications`, che nel processo del blocco
                        // aprirebbe un secondo server di notifiche.
                        name: scheda.modelData.posta ? "mail" : "bell"
                        color: Theme.Colors._bianco
                    }
                }

                Column {
                    id: corpo
                    anchors.left: bollo.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space4
                    anchors.top: parent.top
                    anchors.topMargin: Theme.Effects.space4
                    spacing: 2

                    Item {
                        width: parent.width
                        height: nomeApp.implicitHeight

                        Text {
                            id: nomeApp
                            anchors.left: parent.left
                            anchors.right: quando.left
                            anchors.rightMargin: Theme.Effects.space2
                            textFormat: Text.PlainText
                            text: scheda.modelData.app
                            elide: Text.ElideRight
                            color: Qt.alpha(Theme.Colors._bianco, pannello.completo ? 0.62 : 0.95)
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: pannello.completo ? Theme.Typography.sizeXS
                                                              : Theme.Typography.sizeMD
                            font.weight: pannello.completo ? Theme.Typography.weightMedium
                                                           : Theme.Typography.weightSemiBold
                        }
                        Text {
                            id: quando
                            anchors.right: parent.right
                            anchors.verticalCenter: nomeApp.verticalCenter
                            text: pannello._ora(pannello.completo ? scheda.modelData.quando
                                                                  : scheda.modelData.ultima)
                            color: Qt.alpha(Theme.Colors._bianco, 0.45)
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }

                    // «numero»: solo quante. «tutto»: titolo e testo.
                    Text {
                        width: parent.width
                        visible: !pannello.completo
                        textFormat: Text.PlainText
                        text: pannello.completo ? "" : pannello._quante(scheda.modelData)
                        color: Qt.alpha(Theme.Colors._bianco, 0.70)
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    Text {
                        width: parent.width
                        visible: pannello.completo && text !== ""
                        textFormat: Text.PlainText
                        text: pannello.completo ? scheda.modelData.titolo : ""
                        elide: Text.ElideRight
                        color: Theme.Colors._bianco
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightSemiBold
                    }
                    Text {
                        width: parent.width
                        visible: pannello.completo && text !== ""
                        textFormat: Text.PlainText
                        text: pannello.completo ? scheda.modelData.testo : ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Qt.alpha(Theme.Colors._bianco, 0.72)
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }
        }
    }
}
