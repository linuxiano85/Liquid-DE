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

    readonly property string casa: Quickshell.env("HOME") || "/home"

    /// I pezzi: ognuno ha l'etichetta da mostrare e il percorso dove porta.
    readonly property var pezzi: {
        var p = String(briciole.percorso || "");
        if (p === "")
            return [];

        var out = [];
        // La cartella di casa non si mostra come «home / giacomo»: è UN posto,
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

    // ── La fila ──────────────────────────────────────────────────────────

    Row {
        id: fila
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: briciole.pezzi

            delegate: Row {
                id: pezzo
                required property var modelData
                required property int index

                readonly property bool ultimo: pezzo.index === briciole.pezzi.length - 1
                /// Acceso mentre ci si trascina sopra qualcosa.
                property bool bersaglio: false
                /// Nascosto perché non ci sta: si vedono il primo, gli ultimi
                /// e un «…» in mezzo.
                readonly property bool tagliato:
                    briciole.pezzi.length > briciole.quantiStanno
                    && pezzo.index > 0
                    && pezzo.index < briciole.pezzi.length - (briciole.quantiStanno - 1)

                spacing: 0
                visible: !pezzo.tagliato

                // Il puntino di sospensione, una volta sola, al posto del
                // primo pezzo tagliato.
                Text {
                    visible: briciole.pezzi.length > briciole.quantiStanno
                             && pezzo.index === briciole.pezzi.length - (briciole.quantiStanno - 1)
                    text: "…  ›  "
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: contenuto.implicitWidth + Theme.Effects.space2 * 2
                    height: 22
                    radius: Theme.Effects.radiusXS
                    color: mouse.containsMouse && !pezzo.ultimo
                           ? Theme.Colors.raised : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Row {
                        id: contenuto
                        anchors.centerIn: parent
                        spacing: Theme.Effects.space1

                        Ui.Icon {
                            visible: pezzo.modelData.icona !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 13; height: 13
                            name: pezzo.modelData.icona || "folder"
                            color: pezzo.ultimo && briciole.attivo
                                   ? Theme.Colors.text : Theme.Colors.textMuted
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pezzo.modelData.etichetta
                            // L'ultimo pezzo è dove SI È: più chiaro e più
                            // pesante degli altri, che sono la strada per
                            // arrivarci. Senza questa differenza la fila è
                            // una sequenza di parole tutte uguali e non si
                            // capisce dove finisce.
                            color: pezzo.ultimo
                                   ? (briciole.attivo ? Theme.Colors.text
                                                      : Theme.Colors.textMuted)
                                   : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
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
                    visible: !pezzo.ultimo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
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
    function ricalcola() {
        briciole.quantiStanno = briciole.pezzi.length;
        if (briciole.width <= 0)
            return;
        // `fila.implicitWidth` è la larghezza che avrebbe con tutti i pezzi
        // visibili: se ci sta, non c'è niente da togliere.
        var giri = 0;
        while (fila.implicitWidth > briciole.width
               && briciole.quantiStanno > 2 && giri < 40) {
            briciole.quantiStanno--;
            giri++;
        }
    }

    onWidthChanged: Qt.callLater(briciole.ricalcola)
    onPercorsoChanged: Qt.callLater(briciole.ricalcola)
    Component.onCompleted: briciole.ricalcola()
}
