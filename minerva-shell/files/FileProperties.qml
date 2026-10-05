import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Properties — Che cos'è questo file, e chi può farci che cosa.
//
// Mancava del tutto, e la mancanza si sentiva in tre momenti diversi:
// quando un file non si lascia scrivere e non si capisce perché; quando si
// vuole sapere quanto occupa davvero una cartella; e quando Minerva apre
// un'immagine col browser e non c'è nessun posto dove dire di no.
//
// Sono tre domande diverse ma si fanno tutte davanti allo stesso file, quindi
// stanno in una finestra sola invece che in tre.
//
// ── I PERMESSI SONO NOVE CASELLE E BASTA ─────────────────────────────────
//
// Non un campo dove scrivere `755`. Il numero ottale è una scorciatoia per chi
// lo sa già a memoria, e per tutti gli altri è una password da indovinare: si
// mostra, in piccolo, ma quello che si tocca sono le caselle. Chi il numero lo
// sa lo legge cambiare mentre clicca, e impara.
Rectangle {
    id: props

    anchors.fill: parent
    color: Theme.Colors.scrim
    visible: false

    readonly property bool it: Core.Strings.lang === "it"

    property string path: ""
    property var info: null
    /// Byte contati dentro una cartella, -1 finché non si è chiesto.
    property double measured: -1
    property bool measuring: false

    /// I permessi come si stanno modificando adesso, tre cifre ottali.
    property int ownerBits: 0
    property int groupBits: 0
    property int otherBits: 0

    readonly property string mode: "" + props.ownerBits + props.groupBits + props.otherBits
    readonly property bool modeDirty: props.info
                                        && props.mode !== String(props.info.mode)

    function open(path) {
        props.path = path;
        props.info = null;
        props.measured = -1;
        props.measuring = false;
        props.visible = true;
        Core.Ipc.fsInfo(path);
    }

    function close() {
        props.visible = false;
        props.info = null;
    }

    Connections {
        target: Core.Ipc

        function onFileInfoReceived(info) {
            if (!props.visible || info.path !== props.path)
                return;
            props.info = info;
            var m = String(info.mode || "644");
            // `stat` risponde con tre cifre per i file normali e quattro
            // quando ci sono setuid o sticky: si tengono le ultime tre, che
            // sono quelle che questa finestra sa mostrare.
            if (m.length > 3)
                m = m.substring(m.length - 3);
            props.ownerBits = parseInt(m.charAt(0), 10) || 0;
            props.groupBits = parseInt(m.charAt(1), 10) || 0;
            props.otherBits = parseInt(m.charAt(2), 10) || 0;
        }

        function onFileMeasureReceived(measure) {
            if (!props.visible || measure.path !== props.path)
                return;
            props.measuring = false;
            props.measured = measure.ok === true ? measure.bytes : -1;
        }
    }

    function applyMode() {
        if (!props.modeDirty)
            return;
        Core.Ipc.fsChmod(props.path, props.mode, false);
        // Si richiede subito: se il cambio non è passato — un file di un
        // altro utente — la finestra deve tornare a mostrare la verità
        // invece delle caselle che abbiamo appena spuntato noi.
        refresh.restart();
    }

    Timer {
        id: refresh
        interval: 250
        onTriggered: if (props.visible) Core.Ipc.fsInfo(props.path)
    }

    function humanDate(ms) {
        if (!ms || ms <= 0)
            return "—";
        return new Date(ms).toLocaleString(Qt.locale(), Locale.ShortFormat);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: props.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: 520
        height: Math.min(parent.height - 60, body.implicitHeight + Theme.Effects.space5 * 2)
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge
        clip: true

        MouseArea { anchors.fill: parent }

        Ui.Scorrimento {
            bersaglio: corpoScorrevole
            anchors {
                right: corpoScorrevole.right
                top: corpoScorrevole.top
                bottom: corpoScorrevole.bottom
            }
        }

        Flickable {
            id: corpoScorrevole
            anchors.fill: parent
            anchors.margins: Theme.Effects.space5
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: body
                width: parent.width
                spacing: Theme.Effects.space3

                // ── Nome e tipo ──────────────────────────────────────────

                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: props.info ? props.info.name : "…"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightMedium
                }

                Text {
                    width: parent.width
                    visible: props.info !== null
                    wrapMode: Text.WrapAnywhere
                    text: props.info
                          ? (props.info.kind + "   ·   " + (props.info.mime || "?"))
                          : ""
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Rectangle { width: parent.width; height: 1; color: Theme.Colors.edge }

                // ── I dati ───────────────────────────────────────────────

                Column {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: {
                            if (!props.info)
                                return [];
                            var i = props.info;
                            var rows = [];
                            rows.push({ "k": props.it ? "Percorso" : "Path",
                                        "v": i.path, "mono": true });
                            if (i.linkTarget && i.linkTarget !== "")
                                rows.push({ "k": props.it ? "Punta a" : "Points to",
                                            "v": i.linkTarget, "mono": true });
                            rows.push({ "k": props.it ? "Dimensione" : "Size",
                                        "v": i.isDir
                                             ? (props.measured >= 0
                                                ? Core.Formato.peso(props.measured)
                                                : (props.measuring
                                                   ? (props.it ? "sto contando…" : "counting…")
                                                   : "—"))
                                             : Core.Formato.peso(i.size)
                                               + "   (" + i.size + " byte)",
                                        "mono": false });
                            rows.push({ "k": props.it ? "Modificato" : "Modified",
                                        "v": props.humanDate(i.modified), "mono": false });
                            rows.push({ "k": props.it ? "Aperto" : "Accessed",
                                        "v": props.humanDate(i.accessed), "mono": false });
                            rows.push({ "k": props.it ? "Proprietario" : "Owner",
                                        "v": i.owner + " : " + i.group, "mono": true });
                            return rows;
                        }

                        delegate: Item {
                            id: row
                            required property var modelData
                            width: body.width
                            height: Math.max(20, rowValue.implicitHeight)

                            Text {
                                id: rowKey
                                width: 120
                                anchors.left: parent.left
                                anchors.top: parent.top
                                text: row.modelData.k
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.weight: Theme.Typography.weightRegular
                                font.pixelSize: Theme.Typography.sizeSM
                            }

                            Text {
                                id: rowValue
                                anchors.left: rowKey.right
                                anchors.right: parent.right
                                anchors.top: parent.top
                                wrapMode: Text.WrapAnywhere
                                text: row.modelData.v
                                color: Theme.Colors.textMuted
                                font.family: row.modelData.mono
                                             ? Theme.Typography.fontMono
                                             : Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }
                    }
                }

                // Contare una cartella è lento, quindi lo si chiede. Farlo
                // da soli all'apertura vorrebbe dire che aprire le proprietà
                // della home fa lavorare il disco per un minuto senza che
                // nessuno l'abbia chiesto.
                Rectangle {
                    visible: props.info && props.info.isDir && props.measured < 0
                    width: countText.implicitWidth + Theme.Effects.space4
                    height: 28
                    radius: Theme.Effects.radiusXS
                    color: countMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.16)
                                                    : Theme.Colors.raised

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: props.measuring
                              ? (props.it ? "Sto contando…" : "Counting…")
                              : (props.it ? "Conta quanto occupa" : "Measure contents")
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: countMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !props.measuring
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            props.measuring = true;
                            Core.Ipc.fsMeasure(props.path);
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.Colors.edge }

                // ── Permessi ─────────────────────────────────────────────

                Text {
                    text: props.it ? "Chi può fare che cosa" : "Who can do what"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD
                }

                // ── La levetta che dice la cosa che si vuole davvero ──────
                //
                // Richiesta di Giacomo: una spunta per rendere il file
                // eseguibile. La griglia sotto ce l'ha già — la colonna
                // «eseguire» — ma sono tre caselle su tre righe, e chi vuole
                // «questo script deve partire» non pensa in ottale.
                //
                // Non scrive da sé: accende o spegne le tre caselle `x`, e a
                // scrivere resta «Applica i permessi». Due strade che scrivono
                // i permessi sono due strade che un giorno dicono cose diverse
                // — e così la griglia mostra sempre quello che sta per
                // succedere davvero.
                Item {
                    width: parent.width
                    height: 30
                    visible: props.info && props.info.kind !== "directory"

                    readonly property bool acceso:
                        (props.ownerBits & 1) === 1

                    Rectangle {
                        id: levetta
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 20
                        radius: 10
                        color: parent.acceso ? Theme.Colors.accent
                                             : Theme.Colors.sunken
                        border.width: 1
                        border.color: parent.acceso ? Theme.Colors.accent
                                                    : Theme.Colors.edge
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            y: 3
                            x: levetta.parent.acceso ? 19 : 3
                            color: Theme.Colors.text
                            Behavior on x { NumberAnimation { duration: Theme.Motion.instant } }
                        }
                    }

                    Text {
                        anchors.left: levetta.right
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: props.it ? "Si può eseguire" : "Can be run"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Il permesso si dà a chi già poteva LEGGERE: dare
                            // l'esecuzione a chi il file non lo vede nemmeno
                            // non serve a niente e allarga i permessi di
                            // nascosto.
                            var su = !parent.acceso;
                            props.ownerBits = su ? (props.ownerBits | 1)
                                                 : (props.ownerBits & ~1);
                            if (su) {
                                if ((props.groupBits & 4) === 4)
                                    props.groupBits |= 1;
                                if ((props.otherBits & 4) === 4)
                                    props.otherBits |= 1;
                            } else {
                                props.groupBits &= ~1;
                                props.otherBits &= ~1;
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 24

                    Repeater {
                        model: [
                            { "x": 120, "it": "leggere",  "en": "read" },
                            { "x": 210, "it": "scrivere", "en": "write" },
                            { "x": 300, "it": "eseguire", "en": "run" }
                        ]
                        delegate: Text {
                            required property var modelData
                            x: modelData.x
                            anchors.verticalCenter: parent.verticalCenter
                            text: props.it ? modelData.it : modelData.en
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }
                }

                Repeater {
                    model: [
                        { "who": "owner", "it": "Il proprietario", "en": "The owner" },
                        { "who": "group", "it": "Il suo gruppo",   "en": "Its group" },
                        { "who": "other", "it": "Tutti gli altri", "en": "Everyone else" }
                    ]

                    delegate: Item {
                        id: permRow
                        required property var modelData
                        width: body.width
                        height: 30

                        function bits() {
                            if (permRow.modelData.who === "owner") return props.ownerBits;
                            if (permRow.modelData.who === "group") return props.groupBits;
                            return props.otherBits;
                        }

                        function setBits(v) {
                            if (permRow.modelData.who === "owner") props.ownerBits = v;
                            else if (permRow.modelData.who === "group") props.groupBits = v;
                            else props.otherBits = v;
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: props.it ? permRow.modelData.it : permRow.modelData.en
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        Repeater {
                            model: [ { "x": 120, "bit": 4 },
                                     { "x": 210, "bit": 2 },
                                     { "x": 300, "bit": 1 } ]

                            delegate: Rectangle {
                                id: box
                                required property var modelData

                                readonly property bool on:
                                    (permRow.bits() & box.modelData.bit) !== 0

                                x: box.modelData.x
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20
                                radius: Theme.Effects.radiusXS
                                color: box.on ? Theme.Colors.accent : "transparent"
                                border.width: 1
                                border.color: box.on ? Theme.Colors.accent
                                              : boxMouse.containsMouse
                                                ? Theme.Colors.edgeBright
                                                : Theme.Colors.edge
                                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                                Ui.Icon {
                                    anchors.centerIn: parent
                                    width: 12; height: 12
                                    visible: box.on
                                    name: "check"
                                    color: Theme.Colors.textOnAccent
                                }

                                MouseArea {
                                    id: boxMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: permRow.setBits(
                                        permRow.bits() ^ box.modelData.bit)
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 34

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: props.mode + (props.info ? "   " + props.info.modeString : "")
                        color: props.modeDirty ? Theme.Colors.accent : Theme.Colors.textFaint
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: applyText.implicitWidth + Theme.Effects.space4
                        height: 28
                        radius: Theme.Effects.radiusXS
                        visible: props.modeDirty
                        color: applyMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.22)
                                                        : Theme.Colors.raised

                        Text {
                            id: applyText
                            anchors.centerIn: parent
                            text: props.it ? "Applica i permessi" : "Apply permissions"
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.weight: Theme.Typography.weightRegular
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: applyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: props.applyMode()
                        }
                    }
                }

                // ── Con che cosa si apre ─────────────────────────────────

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.Colors.edge
                    visible: openWith.visible
                }

                Column {
                    id: openWith
                    width: parent.width
                    spacing: Theme.Effects.space2
                    // Prima spariva del tutto quando i candidati erano zero,
                    // e per uno script era proprio quello che succedeva: la
                    // finestra restava coi permessi e la data e nessun modo di
                    // aprire il file. Adesso l'elenco vuoto è raro
                    // (l'ereditarietà dei tipi lo riempie, vedi
                    // `mime_database.dart`) ma possibile — e quando capita si
                    // dice, invece di far sparire una sezione.
                    visible: props.info && !props.info.isDir

                    Text {
                        text: props.it ? "Si apre con" : "Opens with"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeMD
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: !props.info || !props.info.candidates
                                 || props.info.candidates.length === 0
                        text: props.it
                              ? "Nessun programma installato dichiara di saper "
                                + "aprire questo tipo di file."
                              : "No installed program declares that it can open "
                                + "this kind of file."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Repeater {
                        model: props.info ? props.info.candidates : []

                        delegate: Rectangle {
                            id: cand
                            required property var modelData

                            readonly property bool isDefault:
                                props.info && props.info.defaultApp === cand.modelData.id

                            width: openWith.width
                            height: 36
                            radius: Theme.Effects.radiusXS
                            color: candMouse.containsMouse
                                   ? Qt.alpha(Theme.Colors.accent, 0.14)
                                   : (cand.isDefault ? Theme.Colors.raised : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                            Image {
                                id: candIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20
                                source: cand.modelData.iconPath
                                        && cand.modelData.iconPath !== ""
                                        ? "file://" + cand.modelData.iconPath : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.left: candIcon.right
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.right: makeDefault.left
                                anchors.rightMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: cand.modelData.name
                                      + (cand.isDefault
                                         ? (props.it ? "   · predefinito" : "   · default")
                                         : "")
                                color: cand.isDefault ? Theme.Colors.text
                                                      : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.weight: Theme.Typography.weightRegular
                                font.pixelSize: Theme.Typography.sizeSM
                            }

                            // Due gesti diversi sulla stessa riga, e la
                            // differenza conta: il corpo della riga apre il
                            // file ADESSO con quel programma; il pulsante
                            // decide che lo aprirà sempre lui. Confonderli
                            // vorrebbe dire cambiare le impostazioni di
                            // sistema a chi voleva solo dare un'occhiata.
                            Rectangle {
                                id: makeDefault
                                // Sopra l'area della riga: quella è
                                // dichiarata dopo e senza questo `z` gli
                                // starebbe sopra, mangiandosi il clic. Il
                                // pulsante si vedrebbe e non funzionerebbe —
                                // premendolo si aprirebbe il file invece di
                                // scegliere chi lo apre sempre.
                                z: 2
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: defaultText.implicitWidth + Theme.Effects.space3
                                height: 24
                                radius: Theme.Effects.radiusXS
                                // ── Si vede SEMPRE ────────────────────
                                //
                                // Compariva solo passandoci sopra col mouse.
                                // Una funzione che si scopre per caso non
                                // esiste: chi cercava dove si cambia il
                                // programma predefinito guardava una riga e
                                // non vedeva niente. Adesso la riga che non è
                                // il predefinito offre di diventarlo, e quella
                                // che lo è offre di smettere — che è la
                                // richiesta di Giacomo, «nelle proprietà si
                                // può anche cambiare o rimuovere la
                                // selezione».
                                visible: true
                                color: defaultMouse.containsMouse
                                       ? (cand.isDefault
                                          ? Qt.alpha(Theme.Colors.danger, 0.25)
                                          : Qt.alpha(Theme.Colors.accent, 0.25))
                                       : Theme.Colors.raised
                                opacity: candMouse.containsMouse
                                         || defaultMouse.containsMouse ? 1 : 0.55
                                Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }

                                Text {
                                    id: defaultText
                                    anchors.centerIn: parent
                                    text: cand.isDefault
                                          ? (props.it ? "non ricordare più"
                                                      : "stop remembering")
                                          : (props.it ? "sempre questo"
                                                      : "always this")
                                    color: cand.isDefault ? Theme.Colors.danger
                                                          : Theme.Colors.accent
                                    font.family: Theme.Typography.fontDisplay
                                    font.weight: Theme.Typography.weightRegular
                                    font.pixelSize: Theme.Typography.sizeXS
                                }

                                MouseArea {
                                    id: defaultMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // Togliere la scelta non lascia
                                        // per forza il vuoto: sotto la nostra
                                        // c'è quella della distribuzione, e
                                        // sotto ancora l'eredità dal tipo
                                        // genitore. È giusto così — il vuoto
                                        // vero sarebbe «nessuno apre questo
                                        // file», che non è quello che si è
                                        // chiesto.
                                        if (cand.isDefault)
                                            Core.Ipc.mimeForgetDefault(props.info.mime);
                                        else
                                            Core.Ipc.mimeSetDefault(props.info.mime,
                                                                    cand.modelData.id);
                                        refresh.restart();
                                    }
                                }
                            }

                            MouseArea {
                                id: candMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Core.Ipc.openWith(cand.modelData.id, [props.path]);
                                    props.close();
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: props.it ? "Esc per chiudere." : "Esc to close."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }
    }

    focus: props.visible
    Keys.onEscapePressed: props.close()
}
