import QtQuick
import "../theme" as Theme
import "../core" as Core

// Riassunto — Una casella sola, in colonna, con dentro tutto.
//
// ── Perché non sei scatole ─────────────────────────────────────────────────
//
// Giacomo, 9 settembre 2026, guardando i sei widget sparsi: «voglio che sia a
// colonna e non così il widget mi raccomando o magari poter avere una singola
// casella di queste».
//
// Ha ragione, e la ragione è che la domanda è una sola. Nessuno guarda la
// scrivania per sapere «quanta memoria»: la guarda per sapere **come sta il
// computer**, e sei rettangoli sparsi la stessa risposta la danno spezzata in
// sei, obbligando l'occhio a rimetterla insieme.
//
// Una colonna si legge dall'alto in basso in un colpo, come una ricevuta.
//
// ── Le righe si scelgono ───────────────────────────────────────────────────
//
// `righe` è l'elenco dei tipi da mostrare, nell'ordine in cui li si vuole. Chi
// non vuole la rete la toglie; chi vuole solo processore e memoria ne mette
// due. È la stessa forma dell'elenco dei widget, un livello più sotto.
Item {
    id: riassunto

    /// Quali valori, in che ordine.
    property var righe: ["processore", "memoria", "gpu", "temperatura"]

    /// Senza vetro dietro: allora il testo si orla, o su una fotografia
    /// chiara sparisce. Vedi `Telaio.qml`.
    property bool nudo: false

    Accessible.role: Accessible.StaticText
    Accessible.name: Core.Strings.lang === "it" ? "Come sta il computer"
                                                : "How the computer is doing"

    Column {
        id: colonna
        anchors.fill: parent
        spacing: Math.max(2, Math.min(10, riassunto.height / 24))

        Repeater {
            model: riassunto.righe

            delegate: Item {
                required property var modelData
                width: colonna.width
                // Le righe si dividono lo spazio: allargando la casella
                // dalla scrivania crescono tutte insieme, invece di lasciare
                // un buco in fondo.
                height: Math.max(18,
                    (colonna.height - colonna.spacing * (riassunto.righe.length - 1))
                    / Math.max(1, riassunto.righe.length))

                // Da qui escono il numero, il nome e la percentuale: è lo
                // stesso pezzo che disegna un widget singolo, usato solo per
                // i suoi conti. Due tabelle dei valori sarebbero due verità.
                Contenuto {
                    id: conti
                    tipo: parent.modelData
                    visible: false
                }

                Text {
                    id: nome
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: conti.nome
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Math.max(Theme.Typography.sizeXS,
                                             Math.min(Theme.Typography.sizeSM,
                                                      parent.height * 0.36))
                    style: riassunto.nudo ? Text.Outline : Text.Normal
                    styleColor: Theme.Colors.scura ? "#000000" : "#FFFFFF"
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // Metà riga al massimo: il nome sta a sinistra, e un
                    // valore lungo — «624,9 GB» — gli finirebbe sopra.
                    // Restringersi è meglio che sovrapporsi.
                    width: Math.min(implicitWidth, parent.width * 0.5)
                    horizontalAlignment: Text.AlignRight
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: Theme.Typography.sizeXS
                    text: conti.valore
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Math.max(Theme.Typography.sizeSM,
                                             Math.min(Theme.Typography.sizeMD,
                                                      parent.height * 0.46))
                    style: riassunto.nudo ? Text.Outline : Text.Normal
                    styleColor: Theme.Colors.scura ? "#000000" : "#FFFFFF"
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: conti.quota >= 0 && parent.height >= 26
                    height: 3
                    radius: 1.5
                    // Nuda la traccia sparisce: larga quanto la riga e scura
                    // sopra una fotografia, si legge come una riga tirata
                    // sopra il numero. Resta la parte piena. Il perché per
                    // esteso sta in `Contenuto.qml`.
                    color: riassunto.nudo ? "transparent"
                                          : Theme.Colors.raisedHigh

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, conti.quota))
                        height: parent.height
                        radius: parent.radius
                        color: conti.tinta
                    }
                }
            }
        }
    }
}
