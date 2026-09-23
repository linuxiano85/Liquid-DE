import QtQuick
import QtQuick.Shapes

import "../theme" as Theme

// Anello — quanto pesa ogni famiglia, in una figura sola.
//
// ── Perché un anello e non un mucchio di barre ─────────────────────────────
//
// Perché la domanda che si fa guardando questa finestra è **«di che cosa è
// fatto quel numero grande»**, e quella è una domanda su delle proporzioni:
// che i pacchetti scaricati siano quasi metà del totale si vede in un colpo
// d'occhio qui e non si vede in un elenco. Il buco in mezzo non è
// decorazione: è dove sta il numero grande, così la parte e il tutto si
// leggono senza spostare gli occhi.
//
// ── Perché è disegnato con `Shape` ─────────────────────────────────────────
//
// Perché le nostre finestre disegnano **col processore**
// (`QT_QUICK_BACKEND=software`, vale una trentina di megabyte per finestra), e
// lì `MultiEffect`, `ShaderEffect` e `layer.enabled` non danno errore: fanno
// sparire l'oggetto, in silenzio. È già successo al ritratto tondo delle
// Impostazioni, e c'è una prova che lo vieta
// (`minervad/test/disegno_senza_gpu_test.dart`).
//
// `Shape` invece col processore disegna, ed è come sono fatte tutte le nostre
// icone (`ui/Icon.qml`).
Item {
    id: anello

    /// Le fette, già in ordine: `[{ categoria, byte, colore }]`.
    property var fette: []

    /// Il totale su cui si calcolano le proporzioni. Si passa da fuori invece
    /// di sommare qui, perché deve essere lo **stesso** numero che sta scritto
    /// in mezzo: sommando due volte, il giorno che una fetta viene esclusa i
    /// due conti divergono.
    property real totale: 0

    /// Quale fetta è sotto il dito, per nome di famiglia. La ingrossa e spegne
    /// un poco le altre — il collegamento fra la riga dell'elenco e il pezzo
    /// di anello va fatto vedere, o l'anello resta un bel disegno muto.
    property string evidenziata: ""

    property int spessore: 22

    // ── La comparsa ─────────────────────────────────────────────────────
    //
    // L'anello si chiude in mezzo secondo la prima volta che arrivano i dati.
    // Non è vezzo: la scansione ci mette quasi un secondo, e una figura che
    // si compone dice «è arrivato adesso» meglio di qualunque scritta.
    //
    // Si anima un ANGOLO, non una dimensione: col processore animare la
    // dimensione di un oggetto vuol dire rifare il tracciato a ogni
    // fotogramma su un'area che cambia, ed è la cosa che si vede scattare.
    property real avanzamento: 0

    onFetteChanged: {
        if (anello.fette.length === 0) {
            anello.avanzamento = 0;
            return;
        }
        if (anello.avanzamento === 0)
            comparsa.restart();
        else
            anello.avanzamento = 1;
    }

    NumberAnimation {
        id: comparsa
        target: anello
        property: "avanzamento"
        from: 0
        to: 1
        // `scala` è zero quando le animazioni sono spente, e in QML una
        // durata di zero non è un lampo: è il valore che arriva subito.
        duration: Math.round(620 * Theme.Motion.scala)
        easing.type: Easing.OutCubic
    }

    // Il fondo: si vede dove finirebbe l'anello se ci fosse tutto, e serve
    // quando si spuntano poche voci — senza, l'anello mezzo vuoto sembra un
    // errore invece che una scelta.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        asynchronous: false

        ShapePath {
            strokeColor: Theme.Colors.sunken
            fillColor: "transparent"
            strokeWidth: anello.spessore
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: anello.width / 2
                centerY: anello.height / 2
                radiusX: (Math.min(anello.width, anello.height) - anello.spessore) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Repeater {
        model: anello.fette

        Shape {
            id: fetta
            anchors.fill: parent
            preferredRendererType: Shape.GeometryRenderer
            asynchronous: false

            readonly property bool sua: anello.evidenziata === modelData.categoria
            readonly property bool altrui: anello.evidenziata !== ""
                                           && !fetta.sua

            /// Dove comincia: la somma di tutte quelle prima. In gradi, con lo
            /// zero in cima — un anello che comincia a ore tre si legge male
            /// perché non è lì che l'occhio parte.
            readonly property real inizio: {
                var s = 0;
                for (var i = 0; i < index; i++)
                    s += Number(anello.fette[i].byte) || 0;
                return anello.totale > 0 ? -90 + (s / anello.totale) * 360 : -90;
            }

            readonly property real ampiezza: anello.totale > 0
                ? ((Number(modelData.byte) || 0) / anello.totale) * 360 * anello.avanzamento
                : 0

            ShapePath {
                strokeColor: fetta.altrui
                             ? Qt.alpha(modelData.colore, 0.34)
                             : modelData.colore
                fillColor: "transparent"
                // La fetta sotto il dito si ingrossa di quattro pixel: è
                // abbastanza da vedersi e poco da non spostare le altre.
                strokeWidth: anello.spessore + (fetta.sua ? 4 : 0)
                capStyle: ShapePath.FlatCap

                PathAngleArc {
                    centerX: anello.width / 2
                    centerY: anello.height / 2
                    radiusX: (Math.min(anello.width, anello.height) - anello.spessore) / 2
                    radiusY: radiusX
                    startAngle: fetta.inizio
                    // Un grado e mezzo di stacco fra una fetta e l'altra, e
                    // solo se la fetta è più larga di così: sulle briciole
                    // toglierlo vorrebbe dire farle sparire del tutto, e una
                    // voce che pesa poco deve comunque potersi vedere.
                    sweepAngle: fetta.ampiezza > 3 ? fetta.ampiezza - 1.5
                                                   : fetta.ampiezza
                }
            }
        }
    }
}
