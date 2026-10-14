import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "sections" as Sezioni

// CategoriaWindows — La pagina di una categoria nel preset Windows, come
// «Sistema» o «Personalizzazione» in Impostazioni di Windows 11: una scheda
// per ogni pagina che contiene, con titolo, due parole su cosa c'è dentro e
// la freccia. Un clic apre la pagina vera, la stessa di Liquid.
//
// La carica il `Loader` di `System.qml` al posto di una sezione, e le passa
// la finestra dopo il caricamento.
Sezioni.Page {
    id: categoria

    property var finestra: null

    readonly property bool it: Core.Strings.lang === "it"
    readonly property var dati: categoria.finestra
        ? categoria.finestra.categoriaPer(categoria.finestra.paginaCategoria) : null

    title: categoria.dati ? (categoria.it ? categoria.dati.it : categoria.dati.en) : ""

    Repeater {
        model: categoria.dati ? categoria.dati.voci : []

        delegate: Rectangle {
            id: scheda

            required property var modelData
            readonly property var pagina: categoria.finestra.paginaPer(scheda.modelData)
            readonly property var descrizione: categoria.finestra.descrizioniWindows[scheda.modelData] || ["", ""]

            objectName: "categoriaVoce-" + scheda.modelData
            width: parent ? parent.width : 0
            height: 68
            radius: Theme.Effects.radiusXS
            color: presa.pressed ? Theme.Colors.raisedHigh
                 : presa.containsMouse ? Qt.tint(Theme.Colors.raised, Theme.Colors.hover)
                 : Theme.Colors.raised
            border.width: 1
            border.color: scheda.activeFocus ? Theme.Colors.text : Theme.Colors.edge
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: scheda.pagina ? (categoria.it ? scheda.pagina.it : scheda.pagina.en) : ""
            Accessible.description: categoria.it ? scheda.descrizione[0] : scheda.descrizione[1]
            Keys.onReturnPressed: categoria.finestra.apriSezione(scheda.modelData)
            Keys.onEnterPressed: categoria.finestra.apriSezione(scheda.modelData)
            Keys.onSpacePressed: categoria.finestra.apriSezione(scheda.modelData)

            Ui.Icon {
                id: simbolo
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                name: scheda.pagina ? scheda.pagina.icon : "settings"
                color: Theme.Colors.text
            }

            Column {
                anchors.left: simbolo.right
                anchors.leftMargin: 20
                anchors.right: freccia.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: scheda.pagina ? (categoria.it ? scheda.pagina.it : scheda.pagina.en) : ""
                    elide: Text.ElideRight
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: categoria.it ? scheda.descrizione[0] : scheda.descrizione[1]
                    elide: Text.ElideRight
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            Ui.Icon {
                id: freccia
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                name: "chevron"
                rotation: -90
                color: Theme.Colors.text
            }

            MouseArea {
                id: presa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: categoria.finestra.apriSezione(scheda.modelData)
            }
        }
    }
}
