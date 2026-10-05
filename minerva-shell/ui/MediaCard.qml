import QtQuick
import "../theme" as Theme
import "../core" as Core


// MediaCard — Cosa sta suonando, e i tre comandi che servono davvero.
//
// ── Perché sta qui e non accanto al pannello che lo usa ──────────────────
//
// Perché in `spine/panels/` NON C'È UN `qmldir`, e senza quello un file
// vicino non diventa un tipo: `MediaCard { }` scritto dentro `ControlPanel`
// dava «MediaCard is not a type». Il guaio è come si presenta — Quickshell
// non si ferma, tiene in piedi la shell e apre il pannello **vuoto**: nessuna
// finestra rossa, nessun errore a schermo, solo un riquadro scuro dove prima
// c'erano i cursori. Se ne accorge solo chi va a leggere il registro.
//
// Qui invece il `qmldir` c'è ed è il posto degli altri pezzi riusabili.
//
// Sta in cima al pannello di controllo perché quando c'è musica è la cosa che
// si cerca per prima; e **sparisce del tutto quando non c'è niente**, invece
// di restare lì vuoto con scritto «Nessun brano». Un riquadro che non ha nulla
// da dire occupa spazio e insegna a ignorare quella zona dello schermo.
//
// ── Perché la copertina e non l'icona del programma ──────────────────────
//
// Perché la copertina si riconosce da lontano e senza leggere: è l'unico
// elemento del pannello che si identifica con la coda dell'occhio. Quando
// manca — una radio, un video senza miniatura — resta il quadrato con la nota,
// che tiene il posto e non fa saltare il resto delle righe.
//
// ── Perché nessuna barra di avanzamento ──────────────────────────────────
//
// Perché costerebbe un risveglio al secondo per ridisegnare qualcosa su cui
// non si può nemmeno cliccare — e i risvegli inutili sono già il difetto di
// prestazioni più caro che questo progetto abbia avuto. Se un giorno si potrà
// TRASCINARE quella barra allora vale il prezzo: ci si sposta dentro un brano.
// Guardarla scorrere, no.
Rectangle {
    id: card

    /// Il chiamante ci mette solo la larghezza: l'altezza la decide il
    /// contenuto, così questo riquadro si può infilare in una `Column`.
    implicitHeight: card.visible ? 78 : 0

    visible: Core.Media.cQualcosa
    radius: Theme.Effects.radiusMD
    color: Theme.Colors.raised
    border.width: 1
    border.color: Theme.Colors.edge
    clip: true

    readonly property bool it: Core.Strings.lang === "it"

    // ── La copertina ─────────────────────────────────────────────────────
    Rectangle {
        id: cover
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.verticalCenter: parent.verticalCenter
        width: 54
        height: 54
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        clip: true

        Icon {
            anchors.centerIn: parent
            width: 24; height: 24
            name: "music"
            color: Theme.Colors.textFaint
            // È un segnaposto, non l'icona di un programma: resta il nostro
            // tracciato anche con le icone classiche accese. Vedi la regola
            // in `ui/Icon.qml`.
            alwaysDrawn: true
            visible: arte.status !== Image.Ready
        }

        Image {
            id: arte
            anchors.fill: parent
            source: Core.Media.copertina
            fillMode: Image.PreserveAspectCrop
            // Le copertine di Spotify e dei browser arrivano dalla rete: se
            // l'indirizzo non risponde, `asynchronous` evita che il pannello
            // resti bloccato ad aspettarlo.
            asynchronous: true
            cache: true
            sourceSize.width: 108   // il doppio, per gli schermi scalati
            sourceSize.height: 108
            visible: status === Image.Ready
        }
    }

    // ── Titolo e artista ─────────────────────────────────────────────────
    //
    // Cliccando si porta in primo piano il lettore. È il gesto che uno fa
    // d'istinto («dov'è finita quella finestra?») e senza di esso bisogna
    // cercarla fra le altre.
    Column {
        id: testi
        anchors.left: cover.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.right: comandi.left
        anchors.rightMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: Core.Media.titolo
            elide: Text.ElideRight
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            text: Core.Media.artista
            visible: text.length > 0
            elide: Text.ElideRight
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    MouseArea {
        anchors.left: cover.left
        anchors.right: testi.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        enabled: Core.Media.attivo !== null && Core.Media.attivo.canRaise
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: Core.Media.mostra()
    }

    // ── I comandi ────────────────────────────────────────────────────────
    Row {
        id: comandi
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: [
                { "id": "prev", "icona": "prev", "grande": false },
                { "id": "play", "icona": "",     "grande": true  },
                { "id": "next", "icona": "next", "grande": false }
            ]

            delegate: Rectangle {
                id: tasto
                required property var modelData

                // Il Play è più grande degli altri due: è quello che si preme
                // al buio, e la dimensione lo rende trovabile senza guardare.
                readonly property bool grande: tasto.modelData.grande
                readonly property bool attivabile: {
                    if (Core.Media.attivo === null)
                        return false;
                    if (tasto.modelData.id === "play") return Core.Media.attivo.canTogglePlaying;
                    if (tasto.modelData.id === "next") return Core.Media.attivo.canGoNext;
                    return Core.Media.attivo.canGoPrevious;
                }

                width: tasto.grande ? 40 : 34
                height: width
                radius: Theme.Effects.radiusFull
                color: !tasto.attivabile ? "transparent"
                     : premi.pressed ? Theme.Colors.pressed
                     : premi.containsMouse ? Theme.Colors.hover
                     : (tasto.grande ? Theme.Colors.raisedHigh : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                scale: premi.pressed && tasto.attivabile ? 0.92 : 1
                Behavior on scale {
                    NumberAnimation { duration: Theme.Motion.instant; easing.type: Easing.OutCubic }
                }

                Icon {
                    anchors.centerIn: parent
                    width: tasto.grande ? 17 : 14
                    height: width
                    // Il tasto centrale cambia disegno con lo stato: chi
                    // guarda vede se la musica sta andando senza leggere
                    // niente. Una sola icona «play» costringerebbe a
                    // indovinare se vuol dire «sta suonando» o «premi qui».
                    name: tasto.modelData.id === "play"
                          ? (Core.Media.inRiproduzione ? "pause" : "play")
                          : tasto.modelData.icona
                    filled: true
                    alwaysDrawn: true
                    color: tasto.attivabile
                           ? (tasto.grande ? Theme.Colors.text : Theme.Colors.textMuted)
                           : Theme.Colors.textFaint
                    opacity: tasto.attivabile ? 1 : 0.35
                }

                MouseArea {
                    id: premi
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: tasto.attivabile
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        switch (tasto.modelData.id) {
                        case "play": Core.Media.riproduci(); break;
                        case "next": Core.Media.successivo(); break;
                        case "prev": Core.Media.precedente(); break;
                        }
                    }
                }

                // Niente didascalia al passaggio del mouse, per due motivi.
                //
                // Il primo è di sostanza: ▶ ⏸ ⏭ ⏮ sono i quattro simboli che
                // non hanno bisogno di essere spiegati a nessuno, e nemmeno
                // gli interruttori qui sotto nel pannello ne hanno una.
                //
                // Il secondo l'ho visto: il riquadro ha `clip`, e la
                // didascalia usciva TAGLIATA a metà sopra il cursore del
                // volume. Peggio di non averla.
            }
        }
    }
}
