import QtQuick
import QtQuick.Window
import "../../ui" as Ui
import "../../windows11" as W

// PaginaWindows — L'impalcatura di una pagina di Impostazioni nel preset
// Windows, con le misure di Windows 11 (macchina di riferimento, 12 ottobre
// 2026, finestra a 1920 px):
//   · le briciole «Personalizzazione › Sfondo» ferme in alto, 28 px
//     seminero, le precedenti in grigio e cliccabili;
//   · sotto, la colonna larga al massimo 1000 px che scorre; schede a 3 px
//     l'una dall'altra.
// La finestra (`System.qml`) le passa `finestra` dopo il caricamento.
Item {
    id: pagina

    /// La finestra delle Impostazioni: navigazione e lingua.
    property var finestra: null
    /// Le briciole: [{ "testo": "Personalizzazione", "pagina": "w-personalizzazione" }, { "testo": "Sfondo" }].
    property var briciole: []
    /// Come in `sections/Page.qml`: la sezione e la ricerca.
    property string sezione: ""
    default property alias contenuto: colonna.data
    readonly property real larghezza: colonna.width
    property alias posizioneScorrimento: rotolo.contentY
    signal scorso()
    // Le sottopagine interne (cronologia, opzioni) possono tornare alla
    // propria pagina senza chiedere al Loader di ricaricare lo stesso URL.
    signal briciolaChiesta(string destinazione)

    function revealSetting(testo) { }
    // Una colonna dentro Flickable non accompagna da sola il focus da Tab:
    // portiamo il comando a schermo senza cambiare il punto scelto col mouse.
    function revealItem(item) {
        if (!item)
            return;
        var ancestor = item;
        while (ancestor && ancestor !== colonna)
            ancestor = ancestor.parent;
        if (ancestor !== colonna)
            return;
        var point = item.mapToItem(rotolo, 0, 0);
        var next = rotolo.contentY;
        if (point.y < 8)
            next += point.y - 8;
        else if (point.y + item.height > rotolo.height - 8)
            next += point.y + item.height - rotolo.height + 8;
        rotolo.contentY = Math.max(0, Math.min(next, Math.max(0, rotolo.contentHeight - rotolo.height)));
    }
    Connections {
        target: pagina.Window.window
        function onActiveFocusItemChanged() {
            var focused = pagina.Window.window.activeFocusItem;
            if (focused && focused.activeFocus)
                pagina.revealItem(focused);
        }
    }

    // ── Le briciole ──────────────────────────────────────────────────────
    Row {
        id: briciole
        objectName: "bricioleWindows"
        x: colonna.x + rotolo.x
        y: 19
        height: 44
        spacing: 0

        Repeater {
            model: pagina.briciole
            delegate: Row {
                required property var modelData
                required property int index
                readonly property bool ultima: index === pagina.briciole.length - 1
                spacing: 0
                height: 44

                Text {
                    id: voce
                    objectName: ultima ? "paginaTitolo" : "briciolaCategoria"
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.testo
                    textFormat: Text.PlainText
                    color: ultima ? W.Style.text : (presa.containsMouse ? W.Style.text : W.Style.muted)
                    font.family: W.Style.font
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    Accessible.role: ultima ? Accessible.Heading : Accessible.Link
                    Accessible.name: modelData.testo

                    MouseArea {
                        id: presa
                        anchors.fill: parent
                        enabled: !ultima && modelData.pagina !== undefined
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            var destinazione = modelData.pagina;
                            var finestra = pagina.finestra;
                            // La risposta può distruggere questo delegate:
                            // conservare il destinatario prima di emettere.
                            if (finestra)
                                finestra.apriWindows(destinazione);
                            else
                                pagina.briciolaChiesta(destinazione);
                        }
                    }
                }
                Item {
                    visible: !ultima
                    width: 42
                    height: 44
                    W.Glyph {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        name: "chevronRight"
                        color: W.Style.muted
                    }
                }
            }
        }
    }

    // ── La colonna che scorre ────────────────────────────────────────────
    Flickable {
        id: rotolo
        anchors.top: parent.top
        anchors.topMargin: 74
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: colonna.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: Qt.callLater(pagina.scorso)

        Column {
            id: colonna
            width: Math.min(1000, rotolo.width - 48)
            x: Math.max(24, Math.round((rotolo.width - 12 - width) / 2))
            spacing: 3
        }
    }

    Ui.Scorrimento {
        bersaglio: rotolo
        anchors {
            right: rotolo.right
            top: rotolo.top
            bottom: rotolo.bottom
        }
    }
}
