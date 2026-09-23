import QtQuick
import "../../theme" as Theme
import "../../ui" as Ui

// Page — L'impalcatura comune a ogni sezione delle impostazioni.
//
// Titolo, sottotitolo e una colonna che scorre. Ogni sezione la usa così:
//
//     Page {
//         title: "Schermo"
//         subtitle: "Risoluzione, frequenza e disposizione"
//         Card { ... }
//         Card { ... }
//     }
//
// Esiste perché sette sezioni scritte a mano finiscono per avere sette
// margini diversi, e la differenza si vede passando dall'una all'altra.
Item {
    id: page

    property string title: ""
    property string subtitle: ""
    function revealSetting(query) {
        var q = String(query || "").trim().toLowerCase();
        if (!q) return;
        function walk(item) {
            if (item.searchHighlighted !== undefined) {
                item.searchHighlighted = false;
                var text = (item.label + " " + item.description + " " + item.searchTerms).toLowerCase();
                if (item.visible && text.indexOf(q) >= 0) return item;
            }
            var children = item.children || [];
            for (var i = 0; i < children.length; i++) {
                var found = walk(children[i]);
                if (found) return found;
            }
            return null;
        }
        var row = walk(stack);
        if (row) {
            row.searchHighlighted = true;
            var y = row.mapToItem(stack, 0, 0).y;
            stack.parent.contentY = Math.max(0, Math.min(y, stack.parent.contentHeight - stack.parent.height));
        }
    }


    /// I figli finiscono nella colonna scorrevole.
    default property alias content: stack.data

    /// La pagina si e' mossa. Chi la contiene deve ridipingere TUTTA la
    /// finestra — vedi il commento sotto `Flickable`.
    signal scorso()

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space6
        anchors.rightMargin: Theme.Effects.space6
        anchors.topMargin: Theme.Effects.space6
        height: page.subtitle !== "" ? 52 : 36

        Text {
            id: titleText
            anchors.top: parent.top
            anchors.left: parent.left
            text: page.title
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXL
            font.weight: Theme.Typography.weightBold
        }

        Text {
            anchors.top: titleText.bottom
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            elide: Text.ElideRight
            visible: page.subtitle !== ""
            text: page.subtitle
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    Flickable {
        id: rotolo
        anchors.top: header.bottom
        anchors.topMargin: Theme.Effects.space5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.Effects.space6
        anchors.rightMargin: Theme.Effects.space6
        anchors.bottomMargin: Theme.Effects.space5
        contentHeight: stack.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // ── Le scie verticali ────────────────────────────────────────────
        //
        // Giacomo, 5 settembre 2026: «l'errore si trova sempre in verticale e
        // se noti bene e' sempre sulla parte dove c'e' l'effetto glass».
        // Aveva ragione su tutto: e' una SCIA, e va per il verso in cui si
        // scorre.
        //
        // Col renderer software una `Shape` — cioe' ogni icona nostra —
        // dipinge anche FUORI da questo ritaglio, sopra l'intestazione e la
        // barra del titolo. Li' non ridipinge mai nessuno, quindi ogni
        // fotogramma dello scorrimento lascia una copia dell'icona, e dopo
        // due scorrimenti c'e' una colonna di «+».
        //
        // Si vede con le icone CLASSICHE perche' allora quasi tutte le icone
        // diventano immagini, e gli unici tracciati rimasti sono i cinque
        // «sempre disegnati» (`Icon.qml`): il piu' visibile e' il «+» del
        // nono accento.
        //
        // Il ritaglio andrebbe rispettato da Qt e non lo e': non e' una cosa
        // che possiamo riparare da qui. Quello che possiamo fare e' togliere
        // il posto dove le scie si depositano — si ridipinge tutta la
        // finestra mentre si scorre. `Qt.callLater` raggruppa: al massimo un
        // ridisegno per fotogramma, non uno per pixel di scorrimento.
        onContentYChanged: Qt.callLater(page.scorso)

        Column {
            id: stack
            width: parent.width
            spacing: Theme.Effects.space3
        }
    }

    // ── La barra di scorrimento ──────────────────────────────────────────
    //
    // Qui, e non in ognuna delle diciotto sezioni: il Flickable è uno solo per
    // tutte, ed è esattamente la ragione per cui questo file esiste — «sette
    // sezioni scritte a mano finiscono per avere sette margini diversi».
    //
    // È FRATELLA del Flickable e non sua figlia. I figli di un Flickable si
    // spostano già di `-contentY`: una barra messa lì dentro scorrerebbe via
    // insieme a quello che deve misurare.
    Ui.Scorrimento {
        bersaglio: rotolo
        anchors {
            right: rotolo.right
            top: rotolo.top
            bottom: rotolo.bottom
        }
    }
}
