import QtQuick
import "../theme" as Theme

// ToolTipHint — La targhetta che spiega un pulsante senza etichetta.
//
// Serve dove un'icona da tredici pixel deve distinguersi da un'altra icona da
// tredici pixel che fa una cosa simile ma non uguale. Il caso per cui è nata:
// «ingrandisci» e «schermo intero» sulla barra del titolo. Sono due comandi
// diversi — uno si ferma sotto la barra della scrivania, l'altro copre tutto —
// e nessun disegno li distingue abbastanza da poterselo indovinare.
//
// Compare dopo mezzo secondo e non subito: passare sopra a una fila di
// pulsanti per arrivare all'ultimo non deve accendere tre targhette in fila.
Item {
    id: hint

    property string text: ""
    property bool shown: false
    /// Sotto il pulsante, o sopra se sotto non c'è posto.
    property int gap: 6

    /// Da che parte è finita davvero. Lo dice `guarda()`, che si chiama nel
    /// momento in cui la targhetta serve: `mapToItem` è una funzione e non si
    /// riaccorge da sé che il pulsante si è spostato, quindi legarcisi darebbe
    /// un valore aggiornato quando gli pare.
    ///
    /// Per un pezzo questa riga di commento c'era e il codice diceva sempre
    /// «sotto»: l'etichetta di una barra in fondo a una finestra finiva oltre
    /// il bordo, e restava un rettangolo tagliato che non si poteva leggere
    /// nemmeno a schermo intero.
    property bool sopra: false

    function guarda() {
        var finestra = hint.Window.window;
        if (!finestra) {
            hint.sopra = false;
            return;
        }
        var giu = hint.mapToItem(null, 0, hint.height);
        hint.sopra = (giu.y + hint.gap + bubble.height + 4) > finestra.height;
    }

    anchors.fill: parent
    // Non deve rubare i clic al pulsante che sta spiegando.
    enabled: false

    Timer {
        id: attesa
        interval: 500
        onTriggered: bubble.visible = true
    }

    onShownChanged: {
        if (hint.shown) {
            hint.guarda();
            attesa.restart();
        } else {
            attesa.stop();
            bubble.visible = false;
        }
    }

    Rectangle {
        id: bubble
        visible: false
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }

        // In coordinate del pulsante: centrata sotto di esso, o sopra quando
        // sotto non ci sta.
        x: (parent.width - width) / 2
        y: hint.sopra ? -height - hint.gap : parent.height + hint.gap
        width: etichetta.implicitWidth + Theme.Effects.space3 * 2
        height: etichetta.implicitHeight + Theme.Effects.space2 * 2
        radius: Theme.Effects.radiusXS
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        Text {
            id: etichetta
            anchors.centerIn: parent
            text: hint.text
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }
}
