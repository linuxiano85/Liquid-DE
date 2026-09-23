import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// Registro — quello che sta succedendo, riga per riga, mentre succede.
//
// ── Perché non basta una rotella che gira ──────────────────────────────────
//
// Giacomo, 8 settembre 2026: «mettiamoci barre di progresso e live log».
//
// Una rotella dice «aspetta» e non dice altro: non dice a che punto è, non
// dice cosa sta guardando, e soprattutto non dice niente **dopo**. Il
// registro dice tutte e tre le cose, e la terza è quella che conta: quando la
// scansione è finita, le sue righe restano lì e sono il resoconto di cosa è
// stato guardato e cosa ci si è trovato.
//
// E vale doppio per il giorno in cui questa roba si cancella davvero. Un
// programma che cancella in silenzio e poi dice «fatto» chiede una fiducia
// che non si è guadagnato: qui la richiesta e l'esito di ogni singola cosa
// restano scritti, e chi guarda può controllare.
//
// ── Perché tiene solo le ultime duecento righe ─────────────────────────────
//
// Perché un elenco che cresce senza fine è memoria che cresce senza fine, e
// questa finestra può restare aperta per ore. Duecento righe sono più di
// quante ne fa una scansione intera (undici) e più di quante se ne leggono.
Item {
    id: registro

    property alias righe: modello

    /// A che punto è: da 0 a 1. Meno di zero vuol dire «non sto facendo
    /// niente», e allora la barra sparisce del tutto invece di restare lì
    /// vuota a promettere qualcosa.
    property real avanzamento: -1
    readonly property bool attivo: registro.avanzamento >= 0

    property string titolo: "Registro"

    function scrivi(testo) {
        if (!testo || testo === "") return;
        modello.append({ "testo": String(testo),
                         "quando": Qt.formatTime(new Date(), "HH:mm:ss") });
        if (modello.count > 200)
            modello.remove(0, modello.count - 200);
        // In coda, sempre: chi guarda un registro dal vivo guarda l'ultima
        // riga. `positionViewAtEnd` e non un `contentY` calcolato a mano —
        // con righe di altezza diversa il conto a mano sbaglia.
        elenco.positionViewAtEnd();
    }

    function pulisci() { modello.clear(); }

    ListModel { id: modello }

    // ── La barra ────────────────────────────────────────────────────────
    //
    // Si anima la larghezza, e qui si può: è un rettangolo alto sei pixel.
    // La regola «anima la posizione, non la dimensione» — che col processore
    // vale caro — parla delle superfici grandi.
    Rectangle {
        id: pista
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: registro.attivo ? 6 : 0
        visible: height > 0
        radius: 3
        color: Theme.Colors.sunken

        Behavior on height {
            NumberAnimation { duration: Theme.Motion.quick
                              easing.type: Easing.OutCubic }
        }

        Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * Math.max(0, Math.min(1, registro.avanzamento))
            color: Theme.Colors.accent

            Behavior on width {
                NumberAnimation { duration: Theme.Motion.quick
                                  easing.type: Easing.OutCubic }
            }
        }
    }

    Text {
        id: intestazione
        anchors.top: pista.bottom
        anchors.topMargin: registro.attivo ? Theme.Effects.space3 : 0
        anchors.left: parent.left
        text: registro.titolo.toUpperCase()
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeXS
        font.weight: Theme.Typography.weightSemiBold
        font.letterSpacing: Theme.Typography.trackingLabel
    }

    Rectangle {
        anchors.top: intestazione.bottom
        anchors.topMargin: Theme.Effects.space2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        ListView {
            id: elenco
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            clip: true
            model: modello
            spacing: 2
            // Le righe sono poche e corte: tenerle tutte vive costa meno che
            // ricostruirle scorrendo.
            cacheBuffer: 2000

            delegate: Row {
                width: elenco.width
                spacing: Theme.Effects.space2

                Text {
                    id: ora
                    // Larghezza fissa e non `implicitWidth`: le ore in colonna
                    // devono stare in colonna, e «09:04:07» e «12:14:31» non
                    // misurano uguale con un carattere proporzionale.
                    width: 56
                    text: model.quando
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Text {
                    width: elenco.width - ora.width - Theme.Effects.space2
                    text: model.testo
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }
        }

        Ui.Scorrimento {
            bersaglio: elenco
            anchors {
                right: elenco.right
                top: elenco.top
                bottom: elenco.bottom
            }
        }
    }
}
