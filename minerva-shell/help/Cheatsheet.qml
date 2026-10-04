import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Cheatsheet — Pannello a schermo intero con TUTTE le scorciatoie configurate.
//
// È la risposta alla domanda «e adesso cosa faccio?»: si apre con Super+K
// (o F1), lascia intravedere la scrivania dietro di sé, e mostra ogni
// combinazione tradotta nella lingua dell'utente.
//
// Le voci arrivano dal demone, che legge config/scorciatoie.minerva: aggiungere
// una scorciatoia lì la fa comparire qui, senza toccare questo file.
PanelWindow {
    id: sheet

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Copre l'intero schermo, barra compresa: senza questo il layer verrebbe
    // spinto sotto la zona esclusiva della barra e le coordinate del mouse
    // risulterebbero sfalsate di tutta l'altezza della barra stessa.
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    signal requestClose()

    /// Quanto è coprente lo sfondo. Regolabile dalle Impostazioni: a 0 si
    /// vede la scrivania quasi per intero, a 1 il pannello è opaco.
    readonly property real backgroundOpacity: {
        var v = Number(Core.Ipc.get("cheatsheet.backgroundOpacity", 0.55));
        if (isNaN(v))
            return 0.55;
        return Math.max(0.0, Math.min(1.0, v));
    }

    property string filter: ""

    /// Scorciatoie raggruppate per categoria: [{ key, entries: [...] }, …]
    ///
    /// Deliberatamente un array JavaScript e non un ListModel: ListModel
    /// converte gli array annidati in altri ListModel, e le combinazioni di
    /// tasti (array dentro array) ne uscirebbero stravolte.
    property var groups: []

    /// Quante colonne di schede stanno sullo schermo
    property int columnCount: 3

    /// Le stesse categorie distribuite in colonne: [[gruppo, …], …]
    property var columns: []

    /// Riempie sempre la colonna più corta.
    ///
    /// Con una disposizione a righe (Flow) una categoria breve accanto a una
    /// lunga lascia un buco verticale grande quanto la differenza. Impilando
    /// invece per colonne, e scegliendo ogni volta la più corta, le schede si
    /// incastrano e lo spazio sprecato sparisce.
    function distribute() {
        var n = Math.max(1, sheet.columnCount);
        var cols = [];
        var heights = [];
        for (var c = 0; c < n; c++) {
            cols.push([]);
            heights.push(0);
        }

        for (var i = 0; i < sheet.groups.length; i++) {
            var shortest = 0;
            for (var k = 1; k < n; k++)
                if (heights[k] < heights[shortest])
                    shortest = k;

            cols[shortest].push(sheet.groups[i]);
            // Stima dell'ingombro: intestazione + una riga per scorciatoia
            heights[shortest] += 2 + sheet.groups[i].entries.length;
        }

        sheet.columns = cols;
    }

    onGroupsChanged: distribute()
    onColumnCountChanged: distribute()

    /// Comprime le serie lunghe in un intervallo: «Super 1 … 0».
    ///
    /// Le scrivanie hanno dieci scorciatoie identiche a meno della cifra.
    /// Elencarle una per una riempirebbe mezza colonna senza dire nulla di
    /// più di quanto dica l'intervallo.
    function collapse(combos) {
        if (!combos || combos.length < 4)
            return combos;

        var mods = (combos[0].mods || []).join("+");
        for (var i = 0; i < combos.length; i++) {
            // Solo tasti singoli con gli stessi modificatori: qualunque
            // altra cosa va mostrata per esteso, o si perde informazione.
            if ((combos[i].mods || []).join("+") !== mods)
                return combos;
            if (!combos[i].key || combos[i].key.length > 1)
                return combos;
        }

        return [{
            "mods": combos[0].mods,
            "key": combos[0].key,
            "rangeTo": combos[combos.length - 1].key
        }];
    }

    function rebuild() {
        var entries = Core.Ipc.keybindings || [];
        var needle = sheet.filter.trim().toLowerCase();
        var order = [];
        var buckets = {};

        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            var combos = e.combos || [];

            if (needle !== "") {
                var hay = (e.description || "").toLowerCase() + " " +
                          Core.Strings.categoryName(e.category).toLowerCase();
                for (var c = 0; c < combos.length; c++)
                    hay += " " + Core.Strings.comboText(combos[c]).toLowerCase();
                if (hay.indexOf(needle) === -1)
                    continue;
            }

            if (buckets[e.category] === undefined) {
                buckets[e.category] = [];
                order.push(e.category);
            }
            buckets[e.category].push(e);
        }

        var result = [];
        for (var k = 0; k < order.length; k++)
            result.push({ "key": order[k], "entries": buckets[order[k]] });

        sheet.groups = result;
    }

    Component.onCompleted: {
        Core.Ipc.requestKeybindings();
        rebuild();
        openAnim.start();
        searchInput.forceActiveFocus();
    }

    Connections {
        target: Core.Ipc
        function onKeybindingsReceived() { sheet.rebuild(); }
    }

    // La lingua cambia le etichette usate anche per la ricerca
    Connections {
        target: Core.Strings
        function onLangChanged() { sheet.rebuild(); }
    }

    onFilterChanged: rebuild()

    function close() {
        closeAnim.start();
    }

    // ── Sfondo ───────────────────────────────────────────────────────────

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.06, sheet.backgroundOpacity)
        opacity: 0

        // Chiudere cliccando fuori è il gesto che tutti provano per primo.
        MouseArea {
            anchors.fill: parent
            onClicked: sheet.close()
        }

        NumberAnimation {
            id: openAnim
            target: backdrop
            property: "opacity"
            from: 0; to: 1
            duration: Theme.Motion.panel
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: closeAnim
            target: backdrop
            property: "opacity"
            to: 0
            duration: Theme.Motion.instant
            easing.type: Easing.OutCubic
            onFinished: sheet.requestClose()
        }
    }

    // ── Contenuto ────────────────────────────────────────────────────────

    Item {
        id: content
        anchors.fill: parent
        // Il promemoria copre lo schermo: si scosta dalla barra, da qualunque
        // parte essa stia. Prima erano 44 pixel in cima e basta.
        anchors.topMargin: Core.Posizioni.barraInBasso
                           ? 24 : Theme.Effects.barHeight + 24
        anchors.bottomMargin: Core.Posizioni.barraInBasso
                              ? Theme.Effects.barHeight + 24 : 24
        anchors.leftMargin: 40
        anchors.rightMargin: 40
        opacity: backdrop.opacity
        focus: true

        // Esc chiude anche se il fuoco è finito su un altro elemento
        Keys.onEscapePressed: sheet.close()

        // Assorbe i clic: cliccare sul pannello non deve chiuderlo
        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            spacing: 20

            // Intestazione: titolo, ricerca, suggerimento di chiusura
            Item {
                id: header
                width: parent.width
                height: 52

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Core.Strings.t("shortcuts").toUpperCase()
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXL
                    font.weight: Theme.Typography.weightBold
                    font.letterSpacing: Theme.Typography.trackingTitle
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(420, parent.width * 0.4)
                    height: 40
                    radius: Theme.Effects.radiusMD
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: searchInput.activeFocus
                                  ? Theme.Colors.accent
                                  : Theme.Colors.edge

                    Behavior on border.color {
                        ColorAnimation { duration: Theme.Motion.instant }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌕"
                        color: Theme.Colors.textFaint
                        font.pixelSize: 18
                    }

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 38
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeMD
                        selectionColor: Theme.Colors.accent
                        clip: true

                        onTextChanged: sheet.filter = text

                        // Primo Esc: svuota la ricerca. Secondo Esc: chiude.
                        Keys.onEscapePressed: function(event) {
                            if (text !== "") {
                                text = "";
                                event.accepted = true;
                            } else {
                                sheet.close();
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Core.Strings.t("searchShortcuts")
                            color: Theme.Colors.textFaint
                            font: searchInput.font
                            visible: searchInput.text === ""
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Core.Strings.t("shortcutsHint")
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            // Nessun risultato
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: sheet.groups.length === 0
                text: Core.Strings.t("noResults")
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeLG
                topPadding: 60
            }

            // Schede impilate in colonne: una scheda per categoria.
            //
            // Avvolte in un Item perché la barra dev'essere FRATELLA del
            // Flickable, e qui intorno c'è una `Column`: un fratello diretto
            // diventerebbe un'altra riga.
            Item {
                width: parent.width
                height: parent.height - header.height - parent.spacing
                visible: sheet.groups.length > 0

                Ui.Scorrimento {
                    bersaglio: schede
                    anchors {
                        right: schede.right
                        top: schede.top
                        bottom: schede.bottom
                    }
                }

                Flickable {
                    id: schede
                    anchors.fill: parent
                    contentHeight: cards.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: cards
                        width: parent.width
                        spacing: 16

                        // Da 1 a 3 colonne secondo lo spazio disponibile
                        onWidthChanged: sheet.columnCount =
                            Math.max(1, Math.min(3, Math.floor(width / 400)))

                        readonly property real cardWidth:
                            (width - spacing * (sheet.columnCount - 1)) / sheet.columnCount

                        Repeater {
                            model: sheet.columns

                            delegate: Column {
                                id: columnItem
                                required property var modelData

                                width: cards.cardWidth
                                spacing: 16

                                Repeater {
                                    model: columnItem.modelData

                                    delegate: Rectangle {
                                        id: card
                                        required property var modelData

                                        width: columnItem.width
                                        implicitHeight: cardColumn.implicitHeight + 28

                                        radius: Theme.Effects.radiusMD
                                        color: Theme.Colors.raised
                                        border.width: 1
                                        border.color: Theme.Colors.edge

                                        Column {
                                            id: cardColumn
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 14
                                            spacing: 10

                                            Text {
                                                text: Core.Strings.categoryName(card.modelData.key).toUpperCase()
                                                color: Theme.Colors.textFaint
                                                font.family: Theme.Typography.fontDisplay
                                                font.pixelSize: Theme.Typography.sizeXS
                                                font.weight: Theme.Typography.weightBold
                                                font.letterSpacing: Theme.Typography.trackingLabel
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Theme.Colors.edge
                                            }

                                            Repeater {
                                                model: card.modelData.entries

                                                delegate: Item {
                                                    id: row
                                                    required property var modelData

                                                    width: cardColumn.width
                                                    implicitHeight: Math.max(descText.implicitHeight,
                                                                             comboFlow.implicitHeight) + 8

                                                    Text {
                                                        id: descText
                                                        anchors.left: parent.left
                                                        anchors.right: comboFlow.left
                                                        anchors.rightMargin: 12
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: row.modelData.description
                                                        color: Theme.Colors.text
                                                        font.family: Theme.Typography.fontDisplay
                                                        font.weight: Theme.Typography.weightRegular
                                                        font.pixelSize: Theme.Typography.sizeMD
                                                        wrapMode: Text.WordWrap
                                                    }

                                                    // Le combinazioni che fanno la stessa cosa,
                                                    // nell'ordine in cui sono scritte nel file di
                                                    // configurazione e separate da "/" perché si
                                                    // capisca che sono alternative, non una sequenza.
                                                    Flow {
                                                        id: comboFlow
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: cardColumn.width * 0.5
                                                        spacing: 5

                                                        Repeater {
                                                            model: sheet.collapse(row.modelData.combos)

                                                            delegate: Row {
                                                                id: comboRow
                                                                required property var modelData
                                                                required property int index
                                                                spacing: 4

                                                                // La barra fra due
                                                                // combinazioni
                                                                // alternative.
                                                                //
                                                                // Niente `width`
                                                                // legata a
                                                                // `implicitWidth`:
                                                                // era un anello
                                                                // (la larghezza
                                                                // dipendeva da sé
                                                                // stessa) e Qt lo
                                                                // segnalava a ogni
                                                                // apertura. Una
                                                                // `Row` salta da
                                                                // sola i figli
                                                                // invisibili,
                                                                // quindi non serve
                                                                // azzerarla.
                                                                Text {
                                                                    visible: comboRow.index > 0
                                                                    height: 30
                                                                    verticalAlignment: Text.AlignVCenter
                                                                    text: "/"
                                                                    color: Theme.Colors.textFaint
                                                                    font.family: Theme.Typography.fontMono
                                                                    font.pixelSize: Theme.Typography.sizeSM
                                                                }

                                                                Repeater {
                                                                    model: comboRow.modelData.mods
                                                                    delegate: KeyCap {
                                                                        required property string modelData
                                                                        label: Core.Strings.modName(modelData)
                                                                        isModifier: true
                                                                    }
                                                                }

                                                                KeyCap {
                                                                    label: Core.Strings.keyName(comboRow.modelData.key)
                                                                }

                                                                // Coda dell'intervallo: «1 … 0»
                                                                Text {
                                                                    visible: comboRow.modelData.rangeTo !== undefined
                                                                    height: 30
                                                                    verticalAlignment: Text.AlignVCenter
                                                                    text: "…"
                                                                    color: Theme.Colors.textFaint
                                                                    font.family: Theme.Typography.fontMono
                                                                    font.pixelSize: Theme.Typography.sizeSM
                                                                }

                                                                KeyCap {
                                                                    visible: comboRow.modelData.rangeTo !== undefined
                                                                    label: Core.Strings.keyName(comboRow.modelData.rangeTo || "")
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
