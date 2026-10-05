import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Tabellone — La forma dei widget «grandi»: un'intestazione, un numero in
// evidenza, delle righe con un simbolo e una barra, e in fondo la storia.
//
// ── Da dove viene ──────────────────────────────────────────────────────────
//
// Giacomo, 14 settembre 2026, con l'immagine di un pannello «Monitoraggio
// batteria» di Windows: «ne vorrei uno simile per il bluetooth con icone
// eccetera, uno per le prestazioni che si vedano le varie misurazioni».
//
// Quel pannello ha una struttura che funziona, e si prende: in cima chi sei;
// poi LA cosa, grande, con una riga sotto che la spiega e una barra; poi le
// altre cose, una per riga, ognuna col suo simbolo, il suo numero e una
// parola che dice se va bene; e in fondo l'andamento nel tempo.
//
// ── Un file per la forma, due per il contenuto ─────────────────────────────
//
// `Prestazioni.qml` e `Bluetooth.qml` sono le due prime facce, e ognuna
// riempie le tre zone con le sue cose. La forma sta qui perché la terza
// faccia — la batteria, la rete, quello che verrà — deve nascere uguale
// senza copiarsi centoventi righe di disposizione.
//
// ── Si adatta all'altezza, e non finge ─────────────────────────────────────
//
// Le righe che non ci stanno non si disegnano: `quanteRighe` dice quante ne
// entrano, e chi riempie l'elenco si ferma lì. Un widget alto la metà mostra
// la metà delle righe, non le stesse righe schiacciate — un numero che non si
// legge è peggio di un numero che non c'è.
Item {
    id: tabellone

    /// Chi è: il simbolo e il nome in cima.
    property string icona: "info"
    property string titolo: ""

    /// La cosa grande: il numero, la riga sotto, la barra (0…1, o −1).
    property string valore: "—"
    property string sotto: ""
    property real quota: -1
    property color tinta: Theme.Colors.accent
    /// Il simbolo grande accanto al numero (vuoto: nessuno).
    property string iconaGrande: ""

    /// Le righe: `{ icona, nome, valore, stato, quota, tinta }`.
    property var righe: []

    /// La storia in fondo, se c'è: il nome di una grandezza per `Grafico`.
    property string storia: ""
    property string storiaNome: ""

    /// Senza vetro dietro: il testo si orla. Vedi `Telaio.qml`.
    property bool nudo: false

    readonly property color _orlo: Theme.Colors.scura ? "#000000" : "#FFFFFF"
    readonly property int _stile: tabellone.nudo ? Text.Outline : Text.Normal

    // ── Le misure, e quante righe ci stanno ──────────────────────────────
    readonly property int altaTesta: 26
    readonly property int altaCosa: 64
    readonly property int altaRiga: 44
    /// Il MINIMO della storia: le righe si contano lasciandole almeno
    /// questo. Poi la storia si prende tutto quello che avanza sotto — il
    /// primo tabellone lasciava un terzo di casella vuoto (Giacomo, 14
    /// settembre 2026: «ha molto spazio sotto vuoto»), perché il grafico
    /// era alto sempre cinquantasei pixel, qualunque fosse la casella.
    readonly property int altaStoria: tabellone.storia !== "" ? 56 : 0
    readonly property int spazio: Theme.Effects.space2

    readonly property int quanteRighe: Math.max(0, Math.floor(
        (tabellone.height - altaTesta - altaCosa - altaStoria - spazio * 3)
        / (altaRiga + spazio)))

    // ── L'intestazione ───────────────────────────────────────────────────
    Row {
        id: testa
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: tabellone.altaTesta
        spacing: Theme.Effects.space2

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            name: tabellone.icona
            color: Theme.Colors.accent
            alwaysDrawn: true
        }

        Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: tabellone.titolo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightMedium
            style: tabellone._stile
            styleColor: tabellone._orlo
        }
    }

    // ── La cosa grande ───────────────────────────────────────────────────
    Item {
        id: cosa
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: testa.bottom
        anchors.topMargin: tabellone.spazio
        height: tabellone.altaCosa

        Ui.Icon {
            id: grande
            visible: tabellone.iconaGrande !== ""
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            name: tabellone.iconaGrande
            color: tabellone.tinta
            alwaysDrawn: true
        }

        Column {
            anchors.left: grande.visible ? grande.right : parent.left
            anchors.leftMargin: grande.visible ? Theme.Effects.space3 : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: tabellone.valore
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: 34
                font.weight: Theme.Typography.weightLight
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.Typography.sizeLG
                elide: Text.ElideRight
                style: tabellone._stile
                styleColor: tabellone._orlo
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: tabellone.sotto
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                elide: Text.ElideRight
                style: tabellone._stile
                styleColor: tabellone._orlo
            }

            Rectangle {
                width: parent.width
                visible: tabellone.quota >= 0
                height: 5
                radius: 2.5
                color: tabellone.nudo ? "transparent" : Theme.Colors.raisedHigh

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, tabellone.quota))
                    height: parent.height
                    radius: parent.radius
                    color: tabellone.tinta
                }
            }
        }
    }

    // ── Le righe ─────────────────────────────────────────────────────────
    Column {
        id: elenco
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: cosa.bottom
        anchors.topMargin: tabellone.spazio
        spacing: tabellone.spazio

        Repeater {
            model: Math.min(tabellone.quanteRighe, tabellone.righe.length)

            delegate: Rectangle {
                required property int index
                readonly property var r: tabellone.righe[index] || ({})

                width: elenco.width
                height: tabellone.altaRiga
                radius: Theme.Effects.radiusSM
                // Nuda, la riga è solo i suoi numeri: un rettangolo scuro
                // sopra la fotografia sarebbe il vetro rientrato dalla
                // finestra.
                color: tabellone.nudo ? "transparent" : Theme.Colors.raised

                // Il simbolo, in un quadratino: è quello che l'immagine di
                // riferimento fa con le foto degli apparecchi, e qui basta
                // il glifo — l'occhio trova «il mouse» prima di leggere.
                Rectangle {
                    id: quadratino
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    radius: Theme.Effects.radiusSM
                    color: tabellone.nudo ? "transparent" : Theme.Colors.raisedHigh

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        name: String(r.icona || "info")
                        color: r.tinta !== undefined ? r.tinta : Theme.Colors.textMuted
                        alwaysDrawn: true
                    }
                }

                Column {
                    anchors.left: quadratino.right
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.right: destra.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        width: parent.width
                        text: String(r.nome || "")
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        elide: Text.ElideRight
                        style: tabellone._stile
                        styleColor: tabellone._orlo
                    }

                    Rectangle {
                        width: parent.width
                        visible: (r.quota !== undefined ? r.quota : -1) >= 0
                        height: 4
                        radius: 2
                        color: tabellone.nudo ? "transparent" : Theme.Colors.raisedHigh

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, r.quota !== undefined ? r.quota : 0))
                            height: parent.height
                            radius: parent.radius
                            color: r.tinta !== undefined ? r.tinta : Theme.Colors.accent
                        }
                    }
                }

                Column {
                    id: destra
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    width: Math.max(valoreTesto.implicitWidth, statoTesto.implicitWidth)

                    Text {
                        id: valoreTesto
                        anchors.right: parent.right
                        text: String(r.valore || "")
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeMD
                        style: tabellone._stile
                        styleColor: tabellone._orlo
                    }

                    Text {
                        id: statoTesto
                        anchors.right: parent.right
                        visible: text !== ""
                        text: String(r.stato || "")
                        color: r.tinta !== undefined ? r.tinta : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                        style: tabellone._stile
                        styleColor: tabellone._orlo
                    }
                }
            }
        }
    }

    // ── La storia, in fondo ──────────────────────────────────────────────
    Item {
        visible: tabellone.storia !== "" && height >= 30
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: elenco.bottom
        anchors.topMargin: tabellone.spazio
        anchors.bottom: parent.bottom

        Text {
            id: storiaNome
            anchors.left: parent.left
            anchors.top: parent.top
            text: tabellone.storiaNome
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            style: tabellone._stile
            styleColor: tabellone._orlo
        }

        Grafico {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: storiaNome.bottom
            anchors.topMargin: 2
            anchors.bottom: parent.bottom
            quale: tabellone.storia
            tinta: tabellone.tinta
            nudo: tabellone.nudo
        }
    }
}
