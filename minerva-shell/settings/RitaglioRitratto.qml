import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core

// RitaglioRitratto — Prendere un pezzo di una foto e farne un ritratto.
//
// Giacomo: «se ad esempio ho un'immagine dove ho più persone e voglio
// selezionare la mia faccia posso farlo oppure tutta l'immagine».
//
// ── Il taglio non lo fa nessun programma esterno ───────────────────────────
//
// `Image` ha `sourceClipRect`: gli si dà un rettangolo in pixel dell'immagine
// VERA e lui disegna solo quello. Quindi l'anteprima non è una previsione del
// ritaglio, **è** il ritaglio — e salvarla è tutto quello che resta da fare:
//
//     anteprima.grabToImage(function (e) { e.saveToFile(dove); },
//                           Qt.size(512, 512));
//
// `targetSize` non è un dettaglio: senza, `grabToImage` fotografa l'oggetto
// alla misura che ha a schermo — centoquaranta pixel — e il ritratto salvato
// sarebbe una miniatura sgranata ingrandita. È lo stesso difetto già trovato
// nel trascinamento delle icone della scrivania.
//
// Quei 512 sono pixel LOGICI: su uno schermo scalato 1,25 il file che esce è
// 640×640. Misurato, non temuto. Va bene così — di troppo grande non si è mai
// rovinata una foto — ma è il motivo per cui il file non misura quello che
// dice la riga qui sopra.
//
// Niente ImageMagick, niente `convert`: un programma in più da installare per
// una cosa che Qt fa da sé è una dipendenza che un giorno manca.
//
// ── L'anteprima è QUADRATA, e non è una scorciatoia ────────────────────────
//
// Il file che si salva è un PNG quadrato: è la schermata di accesso a
// ritagliarlo tondo quando lo disegna. Un'anteprima tonda qui mostrerebbe meno
// di quello che si salva, e chi taglia una faccia vicino al bordo si
// ritroverebbe l'orecchio dentro senza averlo visto.
Rectangle {
    id: ritaglio

    /// Il file salvato, pronto da applicare.
    signal ritagliato(string percorso)

    anchors.fill: parent
    color: Theme.Colors.scrim
    visible: false
    z: 31

    property string sorgente: ""
    readonly property bool it: Core.Strings.lang === "it"

    /// Dove finiscono i ritratti ritagliati. Nella cartella dei dati e non fra
    /// le immagini dell'utente: è roba che abbiamo generato noi, e mescolarla
    /// alle sue foto vuol dire lasciargliela da riordinare.
    readonly property string cartella: Core.Ipc.cartellaDati + "/ritratti"

    function apri(percorso) {
        ritaglio.sorgente = percorso;
        ritaglio.tutta = false;
        ritaglio.visible = true;
        // La selezione si rimette al centro a ogni apertura: ereditare quella
        // della foto prima, su un'immagine di un'altra forma, la lascia fuori
        // dal bordo.
        quadro.centrati();
    }

    function chiudi() {
        ritaglio.visible = false;
        ritaglio.sorgente = "";
    }

    // ── Il salvataggio ───────────────────────────────────────────────────
    //
    // Prima la cartella, poi il file: `saveToFile` non crea le cartelle che
    // mancano e fallisce restituendo `false`, cioè in silenzio.
    property string _destinazione: ""

    /// «Tutta l'immagine» non è un quadro grande quanto ci sta: è NESSUN
    /// quadro. Il primo giro la faceva chiamando `quadro.centrati()`, cioè il
    /// quadrato più grande centrato — che su una foto orizzontale butta via i
    /// due lati e su una verticale la testa. Il bottone diceva una cosa e ne
    /// faceva un'altra.
    property bool tutta: false

    function salva(tutta) {
        ritaglio.tutta = tutta === true;
        ritaglio._destinazione = ritaglio.cartella + "/ritratto-"
                                 + Date.now() + ".png";
        cartellaPronta.start(["mkdir", "-p", ritaglio.cartella]);
    }

    Core.Exec {
        id: cartellaPronta
        onDone: {
            // Un giro dopo: cambiando `sourceClipRect` un istante fa, la
            // fotografia presa adesso sarebbe ancora quella di prima.
            Qt.callLater(function () {
                anteprima.grabToImage(function (esito) {
                    if (esito.saveToFile(ritaglio._destinazione)) {
                        ritaglio.ritagliato(ritaglio._destinazione);
                        ritaglio.chiudi();
                    } else {
                        avviso.text = ritaglio.it
                            ? "Non sono riuscito a salvare il ritratto."
                            : "Could not save the portrait.";
                    }
                }, Qt.size(512, 512));
            });
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ritaglio.chiudi()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Effects.space6, 760)
        height: Math.min(parent.height - Theme.Effects.space6, 600)
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent }

        Text {
            id: titolo
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: Theme.Effects.space3
            text: ritaglio.it ? "Scegli il pezzo da tenere"
                              : "Choose the part to keep"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
        }

        // ── L'immagine, e il quadro sopra ────────────────────────────────
        Item {
            id: area
            anchors.top: titolo.bottom
            anchors.topMargin: Theme.Effects.space3
            anchors.left: parent.left
            anchors.right: fianco.left
            anchors.bottom: piede.top
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space3
            anchors.bottomMargin: Theme.Effects.space2

            Image {
                id: mostra
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                // Nessun `sourceSize`: serve la misura VERA dell'immagine per
                // tradurre il quadro in pixel del file, e con `sourceSize`
                // `implicitWidth` risponderebbe la misura ridotta.
                source: ritaglio.sorgente !== ""
                        ? "file://" + ritaglio.sorgente : ""
                onStatusChanged: if (status === Image.Ready) quadro.centrati()
            }

            /// Quanto l'immagine è rimpicciolita per starci dentro, e dove
            /// comincia. Tutto il resto discende da questi quattro numeri.
            readonly property real nw: mostra.implicitWidth
            readonly property real nh: mostra.implicitHeight
            readonly property real fatt: (nw > 0 && nh > 0)
                ? Math.min(width / nw, height / nh) : 1
            readonly property real dw: nw * fatt
            readonly property real dh: nh * fatt
            readonly property real ox: (width - dw) / 2
            readonly property real oy: (height - dh) / 2

            Rectangle {
                id: quadro
                color: "transparent"
                border.width: 2
                border.color: Theme.Colors.accent
                visible: area.nw > 0 && !ritaglio.tutta

                property real lato: 100

                function centrati() {
                    if (area.dw <= 0 || area.dh <= 0)
                        return;
                    quadro.lato = Math.min(area.dw, area.dh);
                    quadro.x = area.ox + (area.dw - quadro.lato) / 2;
                    quadro.y = area.oy + (area.dh - quadro.lato) / 2;
                }

                width: quadro.lato
                height: quadro.lato

                // Il velo scuro fuori dal quadro: quattro rettangoli invece di
                // una maschera, perché una maschera vera vorrebbe un effetto
                // grafico e qui bastano quattro rettangoli che nessuno guarda.
                Rectangle {
                    parent: area
                    // I quattro veli sono figli di `area` e non del quadro: se
                    // fossero suoi figli starebbero DENTRO al ritaglio, che è
                    // il contrario del loro mestiere. Il prezzo è che non
                    // spariscono con lui, e va detto a mano.
                    visible: quadro.visible
                    color: Qt.rgba(0, 0, 0, 0.5)
                    x: 0; y: 0; width: area.width; height: quadro.y
                }
                Rectangle {
                    parent: area
                    visible: quadro.visible
                    color: Qt.rgba(0, 0, 0, 0.5)
                    x: 0; y: quadro.y + quadro.height
                    width: area.width; height: area.height - quadro.y - quadro.height
                }
                Rectangle {
                    parent: area
                    visible: quadro.visible
                    color: Qt.rgba(0, 0, 0, 0.5)
                    x: 0; y: quadro.y; width: quadro.x; height: quadro.height
                }
                Rectangle {
                    parent: area
                    visible: quadro.visible
                    color: Qt.rgba(0, 0, 0, 0.5)
                    x: quadro.x + quadro.width; y: quadro.y
                    width: area.width - quadro.x - quadro.width; height: quadro.height
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: 10
                    cursorShape: Qt.SizeAllCursor
                    drag.target: quadro
                    drag.minimumX: area.ox
                    drag.minimumY: area.oy
                    drag.maximumX: area.ox + area.dw - quadro.lato
                    drag.maximumY: area.oy + area.dh - quadro.lato
                }

                // La maniglia in basso a destra. Una sola: un quadrato ha un
                // solo numero da cambiare, e quattro maniglie che fanno la
                // stessa cosa sono tre bugie.
                Rectangle {
                    width: 18
                    height: 18
                    radius: 4
                    color: Theme.Colors.accent
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -6

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeFDiagCursor
                        property real partenza: 0
                        property real latoIniziale: 0
                        onPressed: function (m) {
                            partenza = m.x + m.y;
                            latoIniziale = quadro.lato;
                        }
                        onPositionChanged: function (m) {
                            if (!pressed)
                                return;
                            var d = (m.x + m.y - partenza) / 2;
                            var massimo = Math.min(area.ox + area.dw - quadro.x,
                                                   area.oy + area.dh - quadro.y);
                            quadro.lato = Math.max(48,
                                Math.min(massimo, latoIniziale + d));
                        }
                    }
                }
            }
        }

        // ── Come verrà ───────────────────────────────────────────────────
        Column {
            id: fianco
            anchors.top: titolo.bottom
            anchors.topMargin: Theme.Effects.space3
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            width: 150
            spacing: Theme.Effects.space2

            Text {
                text: ritaglio.it ? "Come verrà" : "How it will look"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            Rectangle {
                width: 140
                height: 140
                radius: Theme.Effects.radiusSM
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Theme.Colors.edge

                Image {
                    id: anteprima
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectFit
                    source: mostra.source
                    // ── Senza questa riga il ritaglio non si vedeva ────────
                    //
                    // Qt tiene le immagini caricate in una cache, e la chiave
                    // è il PERCORSO. `mostra` aveva già chiesto la stessa foto
                    // intera un attimo prima, quindi qui tornava quella: il
                    // riquadro si spostava e l'anteprima non cambiava mai.
                    // Visto a schermo, non dedotto.
                    cache: false
                    // Il ritaglio vero, in pixel dell'immagine. È questo che
                    // viene fotografato e salvato: l'anteprima non somiglia al
                    // risultato, è il risultato.
                    sourceClipRect: {
                        if (area.fatt <= 0 || !ritaglio.visible)
                            return Qt.rect(0, 0, 0, 0);
                        // Un rettangolo vuoto vuol dire «tutta»: è la stessa
                        // cosa che `Image` fa quando non gliene si dà nessuno.
                        if (ritaglio.tutta)
                            return Qt.rect(0, 0, 0, 0);
                        return Qt.rect(Math.round((quadro.x - area.ox) / area.fatt),
                                       Math.round((quadro.y - area.oy) / area.fatt),
                                       Math.round(quadro.lato / area.fatt),
                                       Math.round(quadro.lato / area.fatt));
                    }
                }
            }

            Text {
                id: avviso
                width: parent.width
                wrapMode: Text.WordWrap
                text: ""
                color: Theme.Colors.danger
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        // ── I comandi ────────────────────────────────────────────────────
        Row {
            id: piede
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space3
            spacing: Theme.Effects.space2

            Rectangle {
                width: 130
                height: 34
                radius: Theme.Effects.radiusSM
                color: tuttaMouse.containsMouse ? Theme.Colors.raisedHigh
                                                : Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge

                Text {
                    anchors.centerIn: parent
                    text: ritaglio.it ? "Tutta l'immagine" : "Whole image"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: tuttaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ritaglio.salva(true)
                }
            }

            Rectangle {
                width: 110
                height: 34
                radius: Theme.Effects.radiusSM
                color: ritagliaMouse.containsMouse
                       ? Qt.alpha(Theme.Colors.accent, 0.35)
                       : Qt.alpha(Theme.Colors.accent, 0.20)
                border.width: Theme.Effects.hairline
                border.color: Qt.alpha(Theme.Colors.accent, 0.5)

                Text {
                    anchors.centerIn: parent
                    text: ritaglio.it ? "Ritaglia" : "Crop"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: ritagliaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ritaglio.salva(false)
                }
            }
        }
    }
}
