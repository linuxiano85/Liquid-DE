import QtQuick
import QtQuick.Window
import "../core" as Core
import "../ui" as Ui
import "../windows11" as W

// NavigazioneWindows — La colonna di sinistra di Impostazioni di Windows 11,
// con le misure della macchina di riferimento (12 ottobre 2026, finestra a
// 1920 px; la barra del titolo, alta 32, è sopra):
//   · il riquadro utente: pulsante 290 × 75 a (5, 17), foto da 60 a (16, 25),
//     nome a (88, 38), «Account locale» sotto, 12 px;
//   · le 12 categorie dalla y 111: voci 280 × 36 a x 16, una ogni 40 px,
//     icona a colori da 20 a 10 px dal bordo, testo a 44, 14 px; la voce
//     scelta ha il fondo velato e la barretta d'accento 3 × 16.
// La ricerca sta nella barra del titolo (`System.qml`), come in Windows.
Item {
    id: nav

    property var finestra: null
    readonly property bool it: Core.Strings.lang === "it"

    // ── Chi usa il computer ──
    Rectangle {
        id: utente
        objectName: "utenteWindows"
        x: 5
        y: 17
        width: 290
        height: 75
        radius: 4
        color: presaUtente.containsMouse ? W.Style.hover : "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: Core.Utente.nome
        activeFocusOnTab: true
        border.width: activeFocus ? 2 : 0
        border.color: W.Style.text
        Keys.onReturnPressed: if (nav.finestra) nav.finestra.apriSezione("utente")
        Keys.onSpacePressed: if (nav.finestra) nav.finestra.apriSezione("utente")
        Accessible.onPressAction: if (nav.finestra) nav.finestra.apriSezione("utente")

        Rectangle {
            id: iniziale
            x: 11; y: 8
            width: 60; height: 60
            radius: 30
            color: W.Style.dark ? "#3A3A3A" : "#E3E3E3"
            visible: !foto.pronto
            W.Glyph {
                anchors.centerIn: parent
                width: 32; height: 32
                name: "user"
                color: W.Style.muted
            }
        }
        Ui.RitrattoTondo {
            id: foto
            anchors.fill: iniziale
            fonte: Core.Utente.ritratto
        }
        Column {
            x: 83
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: Core.Utente.nome
                textFormat: Text.PlainText
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                text: nav.it ? "Account locale" : "Local account"
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 12
            }
        }
        MouseArea {
            id: presaUtente
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (nav.finestra) nav.finestra.apriSezione("utente")
        }
    }

    // ── Le categorie ──
    Flickable {
        id: elenco
        y: 109
        width: parent.width
        height: parent.height - y
        contentHeight: voci.height + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: voci
            x: 16
            y: 2
            width: 280
            spacing: 4

            // Mentre si cerca: le pagine trovate.
            Repeater {
                model: nav.finestra && nav.finestra.ricerca.trim() !== "" ? nav.finestra.trovate : []
                delegate: Voce {
                    required property var modelData
                    objectName: "navCerca-" + modelData.id
                    simbolo: modelData.icon
                    testo: nav.it ? modelData.it : modelData.en
                    scelta: nav.finestra.section === modelData.id && nav.finestra.paginaWindows === ""
                    onAttivata: {
                        nav.finestra.apriSezione(modelData.id);
                        var cercato = nav.finestra.ricerca;
                        Qt.callLater(function () { nav.finestra.mostraRiga(cercato); });
                    }
                }
            }
            Repeater {
                model: nav.finestra && nav.finestra.ricerca.trim() === "" ? nav.finestra.categorieWindows : []
                delegate: Voce {
                    required property var modelData
                    objectName: "navWindows-" + modelData.id
                    immagine: modelData.icona
                    testo: nav.it ? modelData.it : modelData.en
                    scelta: nav.finestra.categoriaAttiva === modelData.id
                    onAttivata: nav.finestra.apriCategoria(modelData.id)
                }
            }
        }
    }

    Ui.Scorrimento {
        bersaglio: elenco
        anchors.right: elenco.right
        anchors.top: elenco.top
        anchors.bottom: elenco.bottom
    }

    // Tab deve accompagnare il focus anche quando una finestra bassa
    // nasconde le ultime categorie o i risultati della ricerca.
    Connections {
        target: nav.Window.window
        function onActiveFocusItemChanged() {
            var item = nav.Window.window.activeFocusItem;
            var ancestor = item;
            while (ancestor && ancestor !== voci)
                ancestor = ancestor.parent;
            if (!item || ancestor !== voci)
                return;
            var point = item.mapToItem(voci, 0, 0);
            var next = elenco.contentY;
            if (point.y < next)
                next = point.y;
            else if (point.y + item.height > next + elenco.height)
                next = point.y + item.height - elenco.height;
            elenco.contentY = Math.max(0, Math.min(next, Math.max(0, elenco.contentHeight - elenco.height)));
        }
    }

    component Voce: Rectangle {
        id: voce
        property url immagine: ""
        property string simbolo: ""
        property string testo: ""
        property bool scelta: false
        signal attivata()

        width: 280
        height: 36
        radius: 4
        color: presa.pressed ? W.Style.pressed
             : (voce.scelta || presa.containsMouse) ? W.Style.hover : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.PageTab
        Accessible.name: voce.testo
        Accessible.selected: voce.scelta
        Accessible.onPressAction: voce.attivata()
        Keys.onReturnPressed: voce.attivata()
        Keys.onSpacePressed: voce.attivata()

        Rectangle {
            anchors.fill: parent; anchors.margins: -2; radius: 6
            color: "transparent"; border.width: 2; border.color: W.Style.text
            visible: voce.activeFocus
        }
        Rectangle {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 16
            radius: 1.5
            visible: voce.scelta
            color: W.Style.accent
        }
        Image {
            visible: voce.immagine.toString() !== ""
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20
            sourceSize: Qt.size(40, 40)
            source: voce.immagine
        }
        W.Glyph {
            visible: voce.immagine.toString() === ""
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20
            name: voce.simbolo || "settings"
            color: W.Style.text
        }
        Text {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 52
            text: voce.testo
            elide: Text.ElideRight
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 14
        }
        MouseArea {
            id: presa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: voce.attivata()
        }
    }
}
