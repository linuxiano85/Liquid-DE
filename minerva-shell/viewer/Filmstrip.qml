import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// Filmstrip — La striscia delle altre immagini della cartella.
//
// Serve a due domande che un visualizzatore riceve in continuazione e a cui
// due frecce non rispondono: «dove sono arrivato?» e «qual era quella di
// prima?». Un provino a contatto le risponde tutte e due a colpo d'occhio.
//
// Le miniature si caricano a `sourceSize` piccola e NON alla dimensione vera:
// una cartella di trecento fotografie da otto megapixel caricata intera sono
// dieci gigabyte di memoria per disegnare dei francobolli. È lo stesso
// ragionamento che c'è nelle miniature del gestore file.
Item {
    id: strip

    /// I percorsi, nell'ordine dell'album.
    property var album: []
    property int indice: -1

    /// Come si riconosce un video: lo stesso della griglia, e per lo stesso
    /// motivo — un mp4 qui sarebbe un francobollo vuoto.
    property var eVideo: null

    signal scelto(int i)

    readonly property int lato: 60

    // Il vetro: qui sì. La cornice di Minerva resta trasparente e sfocata, è
    // solo il tavolo dell'immagine a essere opaco (vedi `Stage.qml`).
    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.raised
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.Effects.hairline
        color: Theme.Colors.edge
    }

    // La striscia scorre di lato: la barra pure.
    Ui.Scorrimento {
        bersaglio: lista
        orizzontale: true
        anchors {
            left: lista.left
            right: lista.right
            bottom: lista.bottom
        }
    }

    ListView {
        id: lista
        anchors.fill: parent
        anchors.margins: Theme.Effects.space2
        orientation: ListView.Horizontal
        spacing: Theme.Effects.space2
        model: strip.album
        clip: true
        // La rotellina scorre la striscia anche in verticale: sopra una fila
        // orizzontale il gesto naturale resta quello, e chiedere shift è una
        // regola che nessuno ha voglia di imparare.
        boundsBehavior: Flickable.StopAtBounds

        // Quando cambia l'immagine la striscia la porta in vista da sé, o
        // sfogliando con le frecce si perde di vista dopo dieci scatti.
        highlightRangeMode: ListView.NoHighlightRange
        currentIndex: strip.indice
        onCurrentIndexChanged: lista.positionViewAtIndex(lista.currentIndex,
                                                         ListView.Contain)

        delegate: Item {
            id: cella
            required property int index
            required property string modelData

            width: strip.lato
            height: strip.lato
            readonly property bool corrente: cella.index === strip.indice

            Rectangle {
                anchors.fill: parent
                radius: Theme.Effects.radiusXS
                color: cella.corrente ? Theme.Colors.selected
                                      : (tocco.containsMouse ? Theme.Colors.hover
                                                             : "transparent")
                border.width: cella.corrente ? 1.5 : 0
                border.color: Theme.Colors.accent
            }

            readonly property bool filmato:
                strip.eVideo ? strip.eVideo(cella.modelData) : false

            Ui.Icon {
                anchors.centerIn: parent
                width: 22
                height: 22
                visible: cella.filmato
                name: "video"
                alwaysDrawn: true
                color: Theme.Colors.textMuted
            }

            Image {
                anchors.fill: parent
                anchors.margins: 3
                visible: !cella.filmato
                source: cella.filmato ? "" : "file://" + cella.modelData
                // Il doppio dei pixel del riquadro: basta per uno schermo a
                // densità alta e non un byte di più.
                sourceSize.width: strip.lato * 2
                sourceSize.height: strip.lato * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                clip: true
                opacity: cella.corrente || tocco.containsMouse ? 1.0 : 0.72
                Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }
            }

            MouseArea {
                id: tocco
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: strip.scelto(cella.index)
            }
        }
    }
}
