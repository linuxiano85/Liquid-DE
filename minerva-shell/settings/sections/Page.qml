import QtQuick
import "../../theme" as Theme
import "../../ui" as Ui
import "../../core" as Core

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

    // ── Nel preset Windows ───────────────────────────────────────────────
    //
    // Il titolo è quello di Impostazioni di Windows 11: 28 px, seminero, e
    // davanti la categoria da cui si è arrivati («Sistema › Schermo»), che
    // si clicca per tornarci. Il sottotitolo non c'è: Windows non lo ha, e
    // quello che dice sta già nelle schede. La briciola la mette
    // `System.qml`; vuota, si vede solo il titolo.
    readonly property bool stileWindows: Core.DesktopStyle.attuale === "windows"
    property string briciola: ""
    signal briciolaCliccata()

    /// L'id della sezione (`System.qml` lo mette dopo il caricamento): con
    /// la posizione, fa la chiave con cui ogni scheda ricorda se è aperta.
    property string sezione: ""
    property alias posizioneScorrimento: rotolo.contentY

    // Ogni scheda sa in che pagina sta e in che posizione: la prima di serie
    // è aperta, le altre chiuse. Si contano solo i figli diretti della
    // colonna, che sono le schede vere della pagina, e solo quelle che si
    // chiudono: una scheda fissa in cima (un avviso, la scelta del preset)
    // non deve far partire chiusa la prima scheda vera.
    Component.onCompleted: {
        var n = 0;
        var figli = stack.children;
        for (var i = 0; i < figli.length; i++) {
            if (figli[i].chiudibile === undefined)
                continue;
            figli[i].pagina = page;
            if (!figli[i].chiudibile)
                continue;
            figli[i].indice = n++;
        }
    }
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
            // La riga può stare in una scheda chiusa: la si apre, e la
            // posizione si legge dopo che si è aperta.
            for (var p = row.parent; p && p !== stack; p = p.parent) {
                if (p.chiudibile !== undefined && p.imposta) {
                    p.imposta(true);
                    break;
                }
            }
            var y = row.mapToItem(stack, 0, 0).y;
            // Flickable reparents visual children into its contentItem. The
            // parent of stack is not the scroll view: address it explicitly.
            rotolo.contentY = Math.max(0, Math.min(y, rotolo.contentHeight - rotolo.height));
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
        height: page.subtitle !== "" && !page.stileWindows ? 52 : 40

        Text {
            id: briciolaText
            objectName: "briciolaCategoria"
            anchors.verticalCenter: titleText.verticalCenter
            anchors.left: parent.left
            visible: page.briciola !== ""
            width: visible ? implicitWidth : 0
            text: page.briciola
            textFormat: Text.PlainText
            color: presaBriciola.containsMouse ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: 28
            font.weight: Theme.Typography.weightSemiBold
            Accessible.role: Accessible.Link
            Accessible.name: page.briciola

            MouseArea {
                id: presaBriciola
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.briciolaCliccata()
            }
        }

        Ui.Icon {
            id: separatore
            anchors.left: briciolaText.right
            anchors.leftMargin: visible ? 12 : 0
            anchors.verticalCenter: titleText.verticalCenter
            visible: page.briciola !== ""
            width: visible ? 14 : 0
            height: 14
            name: "chevron"
            rotation: -90
            color: Theme.Colors.textMuted
        }

        Text {
            textFormat: Text.PlainText
            id: titleText
            objectName: "paginaTitolo"
            anchors.top: parent.top
            anchors.left: separatore.right
            anchors.leftMargin: page.briciola !== "" ? 12 : 0
            text: page.title
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: page.stileWindows ? 28 : Theme.Typography.sizeXL
            font.weight: page.stileWindows ? Theme.Typography.weightSemiBold : Theme.Typography.weightBold
        }

        Text {
            anchors.top: titleText.bottom
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            elide: Text.ElideRight
            visible: page.subtitle !== "" && !page.stileWindows
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
        // il manutentore, 5 settembre 2026: «l'errore si trova sempre in verticale e
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
