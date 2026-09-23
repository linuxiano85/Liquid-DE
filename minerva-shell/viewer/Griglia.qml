import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// Griglia — Il provino a contatto: tutte le immagini della cartella insieme.
//
// ── Perché una griglia e non due righe ───────────────────────────────────
//
// La domanda a cui risponde è «che cosa c'è in questa cartella?», e a quella
// domanda si risponde con la SUPERFICIE: più roba si vede in un colpo d'occhio,
// meglio è. Dividere la finestra in due strisce fa l'opposto — dimezza lo
// spazio di tutte e due, e per vedere la ventesima fotografia bisogna
// comunque scorrere. Un provino a contatto è quello che i fotografi stampano
// da sempre per la stessa identica ragione, ed è anche quello che si può
// ingrandire e rimpicciolire con la rotellina senza cambiare disposizione.
//
// Le miniature si caricano piccole (`sourceSize`) e in modo asincrono: una
// cartella di trecento fotografie da otto megapixel caricata a piena
// risoluzione sono dieci gigabyte di memoria per disegnare dei francobolli.
// Vedi anche `Filmstrip.qml`, che fa lo stesso conto in orizzontale.
Item {
    id: griglia

    property var album: []
    property int indice: -1

    /// Come si riconosce un video. Arriva da fuori — la griglia non deve
    /// sapere quali estensioni esistono, e chi lo sa lo sa già.
    property var eVideo: null

    /// Quanto sono grandi le miniature. Si regola con la rotellina tenendo
    /// premuto Ctrl, come in ogni griglia di file che sia mai esistita.
    property int lato: 168

    /// A che misura si decodificano le miniature — **a scatti di 64 pixel**,
    /// non alla misura esatta della cella.
    ///
    /// La rotellina cambia `lato` del quindici per cento a scatto. Legare la
    /// decodifica al valore esatto vuol dire rileggere dal disco e
    /// ridecodificare duecento fotografie a OGNI click: la griglia si
    /// impianta mentre la si ridimensiona, che è esattamente il momento in cui
    /// si sta guardando. A scatti, quasi tutti i click restano nello stesso
    /// scalino e la griglia si ridimensiona sul posto, con i pixel che ha già.
    ///
    /// Il fattore 1.35: una cella si riempie per RITAGLIO, quindi conta il
    /// lato corto dell'immagine, e in una fotografia 4:3 il lato corto è tre
    /// quarti del lungo. Decodificare al doppio (com'era prima) copriva anche
    /// il 16:9 ma pagava il doppio dei pixel a tutte le altre.
    readonly property int decodifica: Math.ceil(griglia.lato * 1.35 / 64) * 64

    signal scelto(int i)
    signal chiusa()

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.scura ? "#0B0D12" : "#1A1D24"
    }

    Ui.Scorrimento {
        bersaglio: vista
        anchors {
            right: vista.right
            rightMargin: Theme.Effects.space2
            top: vista.top
            bottom: vista.bottom
        }
    }

    GridView {
        id: vista
        anchors.fill: parent
        anchors.margins: Theme.Effects.space4
        model: griglia.album
        cellWidth: griglia.lato + Theme.Effects.space2
        cellHeight: griglia.lato + Theme.Effects.space2
        clip: true
        cacheBuffer: griglia.lato * 4
        currentIndex: griglia.indice

        // Quando si apre, quella che si stava guardando deve essere sotto gli
        // occhi: aprirsi in cima a una cartella di duecento file vuol dire
        // aver perso il posto.
        //
        // Alla NASCITA e non al cambio di `visible`: da quando la griglia sta
        // dentro un Loader nasce già visibile, e `onVisibleChanged` non
        // scatterebbe mai. `Qt.callLater` perché al momento in cui il
        // componente è finito la vista non conosce ancora la propria altezza,
        // e posizionarsi dentro un riquadro alto zero non porta da nessuna
        // parte.
        Component.onCompleted: Qt.callLater(
            () => vista.positionViewAtIndex(vista.currentIndex, GridView.Contain))

        delegate: Item {
            id: cella
            required property int index
            required property string modelData

            width: griglia.lato
            height: griglia.lato
            readonly property bool corrente: cella.index === griglia.indice

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Theme.Effects.radiusSM
                color: tocco.containsMouse ? Theme.Colors.hover : "transparent"
                border.width: cella.corrente ? 2 : 0
                border.color: Theme.Colors.accent
            }

            readonly property bool filmato:
                griglia.eVideo ? griglia.eVideo(cella.modelData) : false

            Image {
                anchors.fill: parent
                anchors.margins: 6
                source: cella.filmato ? "" : "file://" + cella.modelData
                sourceSize.width: griglia.decodifica
                sourceSize.height: griglia.decodifica
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                // Niente mipmap: costa un terzo di memoria video in più per
                // livelli di riduzione che qui non si guardano mai — si
                // decodifica già quasi alla misura in cui si disegna, e a
                // quella distanza il filtro bilineare non si distingue.
                clip: true
            }

            // Un video non ha una miniatura: Qt non sa aprire un mp4, e senza
            // un segno resterebbe un riquadro vuoto che sembra un file rotto.
            // Il triangolo dice che cos'è, e che si apre in un altro modo.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                visible: cella.filmato
                color: Qt.rgba(1, 1, 1, 0.05)
                radius: Theme.Effects.radiusXS

                Ui.Icon {
                    anchors.centerIn: parent
                    width: Math.min(46, parent.width * 0.4)
                    height: width
                    name: "video"
                    // Disegnata da noi anche con un tema di icone classico:
                    // qui è un SEGNO dentro una miniatura, non l'icona di un
                    // programma, e quella di un tema stona a colori pieni in
                    // mezzo alle fotografie.
                    alwaysDrawn: true
                    color: Theme.Colors.textMuted
                }
            }

            // Il nome, solo al passaggio del mouse e solo in fondo: scritto
            // sempre, sotto duecento miniature, diventa un muro di testo che
            // nessuno legge e che copre proprio le immagini che si è venuti a
            // guardare.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                height: 22
                color: Qt.rgba(0, 0, 0, 0.62)
                visible: tocco.containsMouse

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space1
                    anchors.rightMargin: Theme.Effects.space1
                    verticalAlignment: Text.AlignVCenter
                    text: {
                        var p = String(cella.modelData);
                        return p.substring(p.lastIndexOf("/") + 1);
                    }
                    elide: Text.ElideMiddle
                    color: "#FFFFFF"
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            MouseArea {
                id: tocco
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: griglia.scelto(cella.index)
            }
        }
    }

    // Ctrl+rotellina cambia la dimensione delle miniature; la rotellina da
    // sola scorre, che è quello che fa in ogni elenco.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (w) => {
            if (!(w.modifiers & Qt.ControlModifier)) {
                w.accepted = false;
                return;
            }
            var passi = w.angleDelta.y / 120.0;
            griglia.lato = Math.max(96, Math.min(360,
                                    Math.round(griglia.lato * Math.pow(1.15, passi))));
            w.accepted = true;
        }
    }
}
