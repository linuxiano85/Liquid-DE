import QtQuick
import Quickshell

import "../theme" as Theme
import "../ui" as Ui

// Briciole — Il percorso come una fila di pezzi cliccabili.
//
// ── Perché non basta scriverlo ─────────────────────────────────────────────
//
// Qui c'era il percorso in monospazio, tutto d'un pezzo:
//
//     ~/Minerva Shell/minerva-shell/files
//
// È preciso e non serve a niente. Per risalire di due cartelle si preme due
// volte la freccia in su contando a mente dove si arriva, oppure si clicca nel
// testo, si cancella la coda a mano e si preme Invio. Nessuna delle due è
// quello che si vuole fare: si vuole *toccare* «Progetti» e essere lì.
//
// È anche la cosa che più fa sembrare grezzo un gestore file, perché è la
// prima riga che si guarda e l'unica che non somiglia a niente di moderno.
//
// ── Quando lo spazio non basta ─────────────────────────────────────────────
//
// Un percorso lungo non si accorcia togliendo l'ultimo pezzo: l'ultimo è dove
// si è, ed è quello che serve di più. Si toglie da CENTRO, dove stanno le
// cartelle che si attraversano e non si guardano, e si lascia un «…» che le
// riapre tutte in un menu.
Item {
    id: briciole

    /// Il percorso da mostrare.
    property string percorso: ""
    /// Vero quando il riquadro è quello attivo (colore più acceso).
    property bool attivo: true

    signal andare(string dove)
    /// Lasciati sopra un pezzo del percorso. È la strada più corta per
    /// risalire: si prende un file e lo si molla due cartelle più su.
    signal rilasciato(var sorgenti, string dove)
    /// Chiesto di poterlo scrivere a mano.
    signal scrivere()

    implicitHeight: 26
    // Il percorso non deve disegnare sopra il riquadro vicino in affiancamento.
    clip: true
    readonly property real larghezzaVisibile: fila.width

    readonly property string casa: Quickshell.env("HOME") || "/home"

    /// I pezzi: ognuno ha l'etichetta da mostrare e il percorso dove porta.
    readonly property var pezzi: {
        var p = String(briciole.percorso || "");
        if (p === "")
            return [];

        var out = [];
        // La cartella di casa non si mostra come «home / utente»: è UN posto,
        // e ha un nome che tutti riconoscono.
        var dentroCasa = briciole.casa !== "" && p.indexOf(briciole.casa) === 0;
        var resto = p;
        if (dentroCasa) {
            out.push({ "etichetta": "Home", "dove": briciole.casa, "icona": "home" });
            resto = p.substring(briciole.casa.length);
        } else {
            out.push({ "etichetta": "/", "dove": "/", "icona": "disco" });
        }

        var costruito = dentroCasa ? briciole.casa : "";
        var parti = resto.split("/");
        for (var i = 0; i < parti.length; i++) {
            if (parti[i] === "")
                continue;
            costruito += "/" + parti[i];
            out.push({ "etichetta": parti[i], "dove": costruito, "icona": "" });
        }
        return out;
    }

    /// Quanti pezzi si riescono a mostrare per intero. Si misura sul serio
    /// invece di indovinare dal numero di caratteri: «Immagini» e «lm» non
    /// occupano lo stesso spazio, e un percorso che scompare a metà è peggio
    /// di uno accorciato apposta.
    property int quantiStanno: briciole.pezzi.length

    // Un Timer figlio viene distrutto con la scheda. Qt.callLater poteva
    // invece eseguire ricalcola dopo la chiusura su un QObject già distrutto.
    Timer {
        id: ricalcolo
        interval: 0
        onTriggered: briciole.ricalcola()
    }

    // ── La fila ──────────────────────────────────────────────────────────

    Row {
        id: fila
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            id: ripetitore
            model: briciole.pezzi
            onItemAdded: ricalcolo.restart()

            delegate: Row {
                id: pezzo
                required property var modelData
                required property int index

                readonly property bool ultimo: pezzo.index === briciole.pezzi.length - 1
                readonly property real larghezzaIntera: etichetta.implicitWidth
                    + Theme.Effects.space2 * 2
                    + (modelData.icona !== "" ? 13 + Theme.Effects.space1 : 0)
                    + (ultimo ? 0 : separatore.implicitWidth)
                /// Acceso mentre ci si trascina sopra qualcosa.
                property bool bersaglio: false
                /// Nascosto perché non ci sta: si vedono il primo, gli ultimi
                /// e un «…» in mezzo.
                readonly property bool tagliato:
                    briciole.quantiStanno === 1 ? !ultimo
                    : briciole.pezzi.length > briciole.quantiStanno
                    && pezzo.index > 0
                    && pezzo.index < briciole.pezzi.length - (briciole.quantiStanno - 1)

                spacing: 0
                visible: !pezzo.tagliato

                // Il puntino di sospensione, una volta sola, al posto del
                // primo pezzo tagliato.
                Text {
                    id: omissione
                    visible: briciole.pezzi.length > briciole.quantiStanno
                             && briciole.quantiStanno > 1
                             && pezzo.index === briciole.pezzi.length - (briciole.quantiStanno - 1)
                    text: "…  ›  "
                    color: FileStyle.textFaint
                    font.family: FileStyle.font
                    font.pixelSize: Theme.Typography.sizeSM
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: pezzo.ultimo ? Math.min(pezzo.larghezzaIntera,
                        Math.max(0, briciole.width - briciole.larghezzaPrimaDellUltimo()))
                        : pezzo.larghezzaIntera - separatore.implicitWidth
                    height: 22
                    radius: Theme.Effects.radiusXS
                    color: mouse.containsMouse && !pezzo.ultimo
                           ? FileStyle.raised : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Row {
                        id: contenuto
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.Effects.space1

                        Ui.Icon {
                            visible: pezzo.modelData.icona !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13; height: 13
                            name: pezzo.modelData.icona || "folder"
                            color: pezzo.ultimo && briciole.attivo
                                   ? FileStyle.text : FileStyle.textMuted
                        }

                        Text {
                            id: etichetta
                            width: pezzo.ultimo ? Math.max(0, parent.parent.width
                                - Theme.Effects.space2 * 2
                                - (pezzo.modelData.icona !== "" ? 13 + Theme.Effects.space1 : 0))
                                : implicitWidth
                            elide: Text.ElideMiddle
                            onImplicitWidthChanged: ricalcolo.restart()
                            anchors.verticalCenter: parent.verticalCenter
                            text: pezzo.modelData.etichetta
                            // L'ultimo pezzo è dove SI È: più chiaro e più
                            // pesante degli altri, che sono la strada per
                            // arrivarci. Senza questa differenza la fila è
                            // una sequenza di parole tutte uguali e non si
                            // capisce dove finisce.
                            color: pezzo.ultimo
                                   ? (briciole.attivo ? FileStyle.text
                                                      : FileStyle.textMuted)
                                   : FileStyle.textMuted
                            font.family: FileStyle.font
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: pezzo.ultimo ? Theme.Typography.weightSemiBold
                                                      : Theme.Typography.weightMedium
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        keys: ["minerva/file", "text/uri-list"]
                        onEntered: pezzo.bersaglio = true
                        onExited: pezzo.bersaglio = false
                        onDropped: function (d) {
                            pezzo.bersaglio = false;
                            var sorgenti = (d.source && d.source.percorsi)
                                           ? d.source.percorsi
                                           : Files.percorsiDaUrl(d.urls);
                            if (sorgenti.length > 0)
                                briciole.rilasciato(sorgenti,
                                                    pezzo.modelData.dove);
                            d.accept();
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: pezzo.ultimo ? Qt.ArrowCursor : Qt.PointingHandCursor
                        // Sull'ultimo non si va: ci si è già. Cliccarlo però
                        // apre la scrittura a mano, che è il gesto di chi
                        // vuole aggiungere un pezzo in fondo.
                        onClicked: {
                            if (pezzo.ultimo)
                                briciole.scrivere();
                            else
                                briciole.andare(pezzo.modelData.dove);
                        }
                    }
                }

                Text {
                    id: separatore
                    visible: !pezzo.ultimo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    color: FileStyle.textFaint
                    font.family: FileStyle.font
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }
    }

    // Lo spazio vuoto dopo l'ultima briciola apre la scrittura a mano: è il
    // gesto che si fa istintivamente per «scrivo io dove andare», ed è come si
    // comporta la barra degli indirizzi di ogni browser.
    MouseArea {
        anchors.left: fila.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        cursorShape: Qt.IBeamCursor
        onClicked: briciole.scrivere()
    }

    // ── Quanti ce ne stanno ──────────────────────────────────────────────
    //
    // Si misura la fila com'è e si tolgono pezzi dal centro finché non entra.
    // Il conto si rifà quando cambia il percorso o la larghezza, non a ogni
    // fotogramma.
    TextMetrics {
        id: misuraOmissione
        text: "…  ›  "
        font.family: FileStyle.font
        font.pixelSize: Theme.Typography.sizeSM
    }

    function larghezzaPer(quanti, escludiUltimo) {
        var totale = quanti > 1 && quanti < pezzi.length ? misuraOmissione.advanceWidth : 0;
        for (var i = 0; i < ripetitore.count; i++) {
            var pezzo = ripetitore.itemAt(i);
            if (!pezzo)
                continue;
            if (escludiUltimo && i === pezzi.length - 1)
                continue;
            if ((quanti === 1 && i === pezzi.length - 1)
                    || (quanti > 1 && (i === 0 || i >= pezzi.length - (quanti - 1))))
                totale += pezzo.larghezzaIntera;
        }
        return totale;
    }

    function larghezzaPrimaDellUltimo() {
        return larghezzaPer(quantiStanno, true);
    }

    function ricalcola() {
        if (briciole.width <= 0)
            return;
        // Row aggiorna implicitWidth dopo il polish: leggerlo nel ciclo dava
        // la misura precedente e lasciava il percorso fuori dalla capsula.
        var quanti = pezzi.length;
        while (quanti > 2 && larghezzaPer(quanti, false) > width) {
            quanti -= 1;
        }
        // Nel tiling stretto conta ancora il nome corrente: non deve sparire
        // per lasciare spazio alla radice e al simbolo di omissione.
        if (quanti === 2 && larghezzaPer(2, true) + 40 > width) {
            quanti = 1;
        }
        quantiStanno = quanti;
    }

    onWidthChanged: ricalcolo.restart()
    onPercorsoChanged: ricalcolo.restart()
    Component.onCompleted: ricalcolo.restart()
}
