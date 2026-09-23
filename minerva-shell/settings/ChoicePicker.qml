import QtQuick
import "../theme" as Theme

// ChoicePicker — Scelta fra poche alternative, mostrate tutte insieme.
//
// Preferito a una tendina: con due o tre opzioni un menu a discesa nasconde
// le possibilità dietro un clic in più, che è esattamente ciò che confonde
// chi non conosce l'ambiente.
//
// ── Va a capo, non fuori ─────────────────────────────────────────────────
//
// Era una `Row`: una fila sola, larga quanto le serviva, dentro un riquadro
// che la ritagliava. Con sei disposizioni di tastiera — «Italiano, English
// (US), English (UK), Deutsch, Français, Español» — se ne vedevano tre e
// mezza, e le ultime tre **non si potevano premere**: non erano nascoste
// dietro uno scorrimento, erano fuori dal mondo.
//
// Trovato il 5 settembre 2026 guardando le sezioni una per una, ed è
// esattamente il tipo di difetto che Giacomo chiama «blocco»: l'opzione c'è,
// si vede che c'è, e non si arriva.
//
// Un `Flow` manda a capo quello che non ci sta. Chi ci sta in una riga non
// si accorge di niente.
Flow {
    id: picker

    /// [{ value: "it", label: "Italiano" }, …]
    property var options: []
    property string value: ""

    signal picked(string value)

    // Una scelta fra poche: per un lettore di schermo è una lista, e ciò che
    // conta è QUALE voce è quella scelta adesso. Si dice il valore, non
    // l'etichetta: l'etichetta la legge da sola la voce quando ci si arriva.
    Accessible.role: Accessible.PageTabList
    Accessible.name: picker.value

    // Il `Flow` ha bisogno di sapere dove finisce la riga. Il genitore è
    // `controlHolder` di `SettingRow`, largo `controlWidth`: è lì che si va a
    // capo. Senza genitore — se qualcuno lo usa da solo — resta una fila.
    width: parent ? parent.width : implicitWidth

    spacing: 6

    Repeater {
        model: picker.options

        delegate: Rectangle {
            id: chip
            required property var modelData

            readonly property bool selected: picker.value === modelData.value

            implicitWidth: chipText.implicitWidth + 24
            height: 30
            radius: Theme.Effects.radiusSM

            color: selected ? Qt.alpha(Theme.Colors.accent, 0.18)
                            : (chipMouse.containsMouse ? Theme.Colors.hover
                                                       : Theme.Colors.raised)
            border.width: 1
            border.color: selected ? Theme.Colors.accent : Theme.Colors.edge

            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Text {
                id: chipText
                anchors.centerIn: parent
                text: chip.modelData.label
                color: chip.selected ? Theme.Colors.accent : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }

            MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.picked(chip.modelData.value)
            }
        }
    }
}
