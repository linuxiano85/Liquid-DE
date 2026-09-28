import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ProcessRow — Una riga dell'elenco: chi è, quanto costa, e come mandarlo via.
Rectangle {
    id: row

    property var riga: ({})
    /// Vero quando il «chiudi» gentile non ha funzionato su questo processo.
    property bool ostinato: false

    signal chiudi(int pid, bool forza)

    readonly property bool it: Core.Strings.lang === "it"
    readonly property real cpu: riga.cpu === null || riga.cpu === undefined ? -1 : riga.cpu

    height: 46
    color: mouse.containsMouse ? Theme.Colors.hover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
    }

    // ── Il segno di quanto consuma ───────────────────────────────────────
    //
    // Una barra sottile dietro il nome, larga quanto la CPU che sta usando.
    // Non è decorazione: scorrendo l'elenco l'occhio trova il colpevole senza
    // leggere un numero, che è il motivo per cui si è aperto il monitor.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * Math.min(1, Math.max(0, row.cpu / 100))
        color: Qt.alpha(row.cpu > 60 ? Theme.Colors.danger : Theme.Colors.accent, 0.10)
        visible: row.cpu > 1
        Behavior on width { NumberAnimation { duration: Theme.Motion.surface } }
    }

    Image {
        id: icona
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space4
        anchors.verticalCenter: parent.verticalCenter
        width: 22; height: 22
        // Visibile quando l'immagine c'è DAVVERO: con un percorso che non si
        // carica restava «visibile» e vuota, e il punto che doveva prenderne
        // il posto non compariva — un buco nella colonna delle icone.
        visible: status === Image.Ready
        source: {
            if (!row.riga.finestra) return "";
            var p = Core.Apps.iconForClass(row.riga.classe || "");
            return p !== "" ? "file://" + p : "";
        }
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: 44
        sourceSize.height: 44
    }

    // Un programma con una finestra ma senza un'icona trovata: il segno
    // della finestra, che dice «è un programma» senza inventarne una.
    Ui.Icon {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space4 + 2
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18
        visible: !icona.visible && !!row.riga.finestra
        name: "window"
        color: Theme.Colors.textMuted
        alwaysDrawn: true
    }

    // Chi non ha finestra non ha icona: al suo posto un punto, che tiene la
    // colonna allineata senza fingere di essere un programma.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space4 + 8
        anchors.verticalCenter: parent.verticalCenter
        visible: !icona.visible && !row.riga.finestra
        width: 6; height: 6; radius: 3
        color: Theme.Colors.textFaint
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space4 + 30
        anchors.right: numeri.left
        anchors.rightMargin: Theme.Effects.space4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Row {
            spacing: Theme.Effects.space2

            Text {
                // Il nome del PROGRAMMA quando si sa, quello del processo
                // altrimenti. `qs` non dice niente a nessuno: le finestre di
                // Minerva sono cinque applicazioni eseguite dallo stesso
                // binario, e chi cerca «chi mi sta mangiando la memoria» deve
                // leggere «Anteprima», non il nome dell'interprete.
                text: {
                    var a = row.riga.classe
                            ? Core.Apps.forClass(row.riga.classe) : null;
                    if (a && a.name)
                        return a.name;
                    // `etichetta` la calcola il demone: `qs` è «Interfaccia di
                    // Minerva», `soffice.bin` è «LibreOffice». Vedi
                    // `processi_umani.dart`.
                    return row.riga.etichetta || row.riga.nome || "?";
                }
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: row.riga.finestra ? Theme.Typography.weightSemiBold
                                               : Theme.Typography.weightMedium
            }

            // «×3» invece di tre righe uguali: dice che il programma è fatto di
            // più processi senza costringere a contarli.
            Text {
                visible: (row.riga.quanti || 1) > 1
                text: "×" + row.riga.quanti
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Che cos'è, non come si chiama il binario ─────────────────────
        //
        // Qui c'era la riga di comando vera:
        //
        //     qs -p ~/Minerva Shell/…/app.qml
        //
        // precisa, lunga tre volte la finestra, e muta sulla domanda che si ha
        // in testa aprendo un gestore attività: «questa roba cos'è, e la posso
        // chiudere?». Ora c'è la spiegazione quando si sa; quando non si sa
        // resta la riga di comando, che è meglio di niente.
        //
        // Il carattere cambia con lei: la spiegazione è una frase e va nel
        // carattere del testo, la riga di comando è codice e resta a spaziatura
        // fissa. Chi guarda capisce quale delle due sta leggendo senza
        // pensarci.
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.riga.descrizione || row.riga.comando || ""
            color: Theme.Colors.textFaint
            font.family: row.riga.descrizione ? Theme.Typography.fontDisplay
                                              : Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    Row {
        id: numeri
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space4
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.Effects.space3

        Text {
            width: 76
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            // Il trattino non è uno zero: al primo giro la percentuale non
            // esiste ancora, e scrivere «0%» direbbe una cosa falsa.
            text: row.cpu < 0 ? "—" : row.cpu.toFixed(1) + " %"
            color: row.cpu > 60 ? Theme.Colors.danger
                 : row.cpu > 15 ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeSM
        }

        Text {
            width: 90
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var v = row.riga.memoria || 0;
                if (v <= 0) return "—";
                var u = ["B", "KB", "MB", "GB"];
                var i = 0;
                while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
                return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
            }
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeSM
        }

        Text {
            width: 60
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: row.riga.pid || ""
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
        }

        // ── I due pulsanti ───────────────────────────────────────────────
        //
        // Compaiono solo sulla riga sotto il puntatore. Un elenco con duecento
        // pulsanti rossi sempre accesi è un elenco che fa paura guardare, e
        // qui la maggior parte delle righe non va toccata mai.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 96; height: 28
            radius: Theme.Effects.radiusXS
            opacity: mouse.containsMouse || bottone.containsMouse || forza.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
            color: bottone.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.22)
                                         : Qt.alpha(Theme.Colors.danger, 0.10)
            border.width: Theme.Effects.hairline
            border.color: Qt.alpha(Theme.Colors.danger, 0.35)

            Text {
                anchors.centerIn: parent
                text: row.it ? "Chiudi" : "Close"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: bottone
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: parent.opacity > 0.5
                onClicked: row.chiudi(row.riga.pid, false)
            }
        }

        // Il secondo compare solo dopo che il primo non ha funzionato: prima di
        // allora offrirlo vorrebbe dire invitare a uccidere programmi che si
        // sarebbero chiusi da soli salvando il lavoro.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: row.ostinato ? 96 : 0
            height: 28
            radius: Theme.Effects.radiusXS
            clip: true
            visible: width > 0
            Behavior on width { NumberAnimation { duration: Theme.Motion.quick } }
            color: forza.containsMouse ? Theme.Colors.danger
                                       : Qt.alpha(Theme.Colors.danger, 0.55)

            Text {
                anchors.centerIn: parent
                text: row.it ? "Termina" : "Kill"
                color: "#FFFFFF"
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightSemiBold
            }

            MouseArea {
                id: forza
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.chiudi(row.riga.pid, true)
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.Effects.hairline
        color: Qt.alpha(Theme.Colors.edge, 0.5)
    }
}
