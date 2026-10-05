import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Palette — La ricerca universale. Un campo, un elenco, Invio.
//
// Sostituisce il vecchio «Portal Matrix», che disponeva le applicazioni in
// bolle attorno a un centro. Era vistoso e inutilizzabile: le bolle uscivano
// dallo schermo appena le applicazioni superavano una ventina, i nomi lunghi
// venivano troncati a metà, e per lanciare qualcosa bisognava cercarlo con
// l'occhio in due dimensioni invece che leggerlo in colonna.
//
// Qui si scrive e si preme Invio. Non c'è niente da imparare, ed è il punto:
// questa è la finestra che si apre più spesso di ogni altra.
//
// Oltre alle applicazioni riconosce:
//
//   =  espressione     calcolo         (=12*7.5)        Invio copia il risultato
//   >  comando         esegue in shell (>systemctl …)
//      parola chiave   azioni della shell (impostazioni, spegni, blocca…)
//
// I prefissi non vanno imparati: chi scrive solo il nome di un'app trova
// l'app, ed è il novanta per cento dei casi.
PanelWindow {
    // `tavola` e non `palette`: dentro i delegati (Rectangle) «palette» è la
    // proprietà di serie di Qt (`Item.palette`), e `palette.selected` o
    // `palette.activate()` finivano lì — la selezione e il clic non
    // funzionavano (F1, PC di prova).
    id: tavola

    signal requestClose()

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    function close() {
        if (!tavola.visible)
            return;
        tavola.visible = false;
        tavola.requestClose();
    }

    // ── Modello dei risultati ────────────────────────────────────────────

    property string query: ""
    property int selected: 0
    property var results: []

    // Staccato: un programma lanciato dalla ricerca deve sopravvivere alla
    // ricerca, e a ogni ricaricamento della shell. Vedi `run()` in shell.qml.
    function run(argv) {
        if (!argv || argv.length === 0)
            return;
        Quickshell.execDetached(argv);
    }

    /// Azioni della shell raggiungibili per nome. Le parole chiave sono più
    /// d'una per voce: chi cerca «spegni» e chi cerca «shutdown» devono
    /// trovare la stessa cosa senza sapere in che lingua è l'interfaccia.
    readonly property var commands: [
        { "id": "settings",   "icon": "settings", "it": "Impostazioni di Minerva", "en": "Minerva settings",
          "keys": "impostazioni settings preferenze configura" },
        { "id": "cheatsheet", "icon": "keyboard", "it": "Elenco delle scorciatoie", "en": "Keyboard shortcuts",
          "keys": "scorciatoie tasti shortcuts keys aiuto help" },
        { "id": "clipboard",  "icon": "clipboard", "it": "Cronologia degli appunti", "en": "Clipboard history",
          "keys": "appunti clipboard copia incolla storia" },
        { "id": "files",      "icon": "folder",  "it": "Gestore file di Minerva", "en": "Minerva file manager",
          "keys": "file cartelle files folder gestore esplora" },
        { "id": "wallpaper",  "icon": "image",   "it": "Cambia lo sfondo", "en": "Change the wallpaper",
          "keys": "sfondo wallpaper scrivania desktop immagine background" },
        { "id": "display",    "icon": "cpu",     "it": "Impostazioni dello schermo", "en": "Display settings",
          "keys": "schermo display risoluzione monitor luminosita scala" },
        { "id": "power",      "icon": "battery", "it": "Impostazioni di alimentazione", "en": "Power settings",
          "keys": "alimentazione batteria energia power risparmio sospensione" },
        { "id": "audio",      "icon": "volume",  "it": "Impostazioni audio", "en": "Sound settings",
          "keys": "audio suono volume altoparlanti microfono cuffie" },
        { "id": "network",    "icon": "wifi",    "it": "Impostazioni di rete", "en": "Network settings",
          "keys": "rete wifi internet connessione network" },
        { "id": "bluetooth",  "icon": "bluetooth", "it": "Bluetooth e accoppiamento", "en": "Bluetooth and pairing",
          "keys": "bluetooth cuffie auricolari mouse tastiera accoppia pair" },
        { "id": "defaults",   "icon": "apps",    "it": "App predefinite", "en": "Default apps",
          "keys": "predefinite apri con default apps programmi associazioni mimeapps" },
        { "id": "lock",       "icon": "lock",    "it": "Blocca lo schermo", "en": "Lock the screen",
          "keys": "blocca lock schermo screen" },
        { "id": "suspend",    "icon": "moon",    "it": "Sospendi", "en": "Suspend",
          "keys": "sospendi suspend sleep standby" },
        { "id": "reboot",     "icon": "restart", "it": "Riavvia il computer", "en": "Restart the computer",
          "keys": "riavvia reboot restart" },
        { "id": "poweroff",   "icon": "power",   "it": "Spegni il computer", "en": "Shut down the computer",
          "keys": "spegni shutdown poweroff arresta" }
    ]

    /// Le applicazioni ordinate UNA VOLTA, col nome già in minuscolo.
    /// `localeCompare` passa da ICU, e qui si scrive a raffica: si ordina
    /// una volta sola, quando arriva l'elenco. Ogni voce è `{ app, nome }`.
    property var ordinati: []

    function riordina() {
        var apps = Core.Ipc.allApps || [];
        var v = [];
        for (var i = 0; i < apps.length; i++)
            v.push({ "app": apps[i], "nome": (apps[i].name || "").toLowerCase() });
        v.sort(function(a, b) { return a.nome.localeCompare(b.nome); });
        tavola.ordinati = v;
        tavola.rebuild();
    }

    Component.onCompleted: {
        Core.Ipc.requestAllApps();
        riordina();
    }

    Connections {
        target: Core.Ipc
        function onAllAppsReceived() { tavola.riordina(); }
    }

    onQueryChanged: { tavola.selected = 0; rebuild(); }

    /// Valuta un'espressione aritmetica. Accetta solo cifre e operatori: la
    /// stringa finisce in un valutatore, e tutto ciò che non è un calcolo non
    /// deve poterci arrivare.
    function evaluate(expr) {
        if (!/^[0-9+\-*/%.,()\s]+$/.test(expr))
            return null;
        try {
            var v = Function("return (" + expr.replace(/,/g, ".") + ")")();
            if (typeof v !== "number" || !isFinite(v))
                return null;
            return Math.round(v * 1e6) / 1e6;
        } catch (e) {
            return null;
        }
    }

    function rebuild() {
        var q = tavola.query.trim();
        var out = [];

        // ── Calcolo ──────────────────────────────────────────────────────
        if (q.indexOf("=") === 0) {
            var value = tavola.evaluate(q.substring(1));
            if (value !== null) {
                out.push({
                    "kind": "math", "icon": "plus",
                    "title": String(value),
                    "subtitle": Core.Strings.lang === "it"
                                ? "Invio per copiare il risultato"
                                : "Enter to copy the result",
                    "payload": String(value)
                });
            }
            tavola.results = out;
            return;
        }

        // ── Comando di shell ─────────────────────────────────────────────
        if (q.indexOf(">") === 0) {
            var cmd = q.substring(1).trim();
            if (cmd !== "") {
                out.push({
                    "kind": "shell", "icon": "terminal",
                    "title": cmd,
                    "subtitle": Core.Strings.lang === "it"
                                ? "Esegui questo comando"
                                : "Run this command",
                    "payload": cmd
                });
            }
            tavola.results = out;
            return;
        }

        var needle = q.toLowerCase();
        var it = Core.Strings.lang === "it";

        // ── Applicazioni ─────────────────────────────────────────────────
        //
        // Nessun ordinamento qui dentro: `ordinati` è già in ordine, e un
        // sottoinsieme di una cosa ordinata resta ordinato. Chi COMINCIA con
        // quello che si è scritto viene prima di chi lo contiene a metà — è
        // quasi sempre quello che si cerca — e i due gruppi si riempiono in
        // un giro solo, ognuno già alfabetico.
        var v = tavola.ordinati;
        var testa = [];
        var coda = [];
        for (var i = 0; i < v.length; i++) {
            if (needle === "") {
                testa.push(v[i].app);
                continue;
            }
            var p = v[i].nome.indexOf(needle);
            if (p === 0)
                testa.push(v[i].app);
            else if (p > 0)
                coda.push(v[i].app);
        }
        var matched = testa.concat(coda);

        for (var j = 0; j < matched.length && j < 40; j++) {
            out.push({
                "kind": "app", "icon": "",
                "iconPath": matched[j].icon || "",
                "title": matched[j].name || "",
                // Solo la descrizione vera del .desktop. Ripetere «Applicazione»
                // su ogni riga di un elenco di applicazioni non dice niente e
                // raddoppia l'altezza della riga per nulla.
                "subtitle": matched[j].comment || "",
                "exec": matched[j].exec,
                "appId": matched[j].appId
            });
        }

        // ── Azioni della shell ───────────────────────────────────────────
        // In coda alle applicazioni: chi scrive «fire» vuole Firefox, e una
        // voce di sistema in cima gli farebbe premere Invio sulla cosa
        // sbagliata.
        if (needle !== "") {
            for (var k = 0; k < tavola.commands.length; k++) {
                var c = tavola.commands[k];
                var label = (it ? c.it : c.en);
                if (c.keys.indexOf(needle) === -1
                        && label.toLowerCase().indexOf(needle) === -1)
                    continue;
                out.push({
                    "kind": "command", "icon": c.icon,
                    "title": label,
                    "subtitle": it ? "Minerva" : "Minerva",
                    "payload": c.id
                });
            }
        }

        tavola.results = out;
    }

    function activate(index) {
        var r = tavola.results[index];
        if (!r)
            return;

        switch (r.kind) {
        case "app":
            Core.Ipc.launchApp(r.exec, r.appId);
            break;
        case "shell":
            // Qui la riga È il comando: l'hai scritta tu apposta, preceduta
            // da «>». È l'unico punto di Minerva in cui questo è voluto.
            tavola.run(["sh", "-c", r.payload]);
            break;
        case "math":
            // Il risultato passa come argomento, non incollato nella riga:
            // vedi `Core.Exec.shArgs` per il perché.
            tavola.run(["sh", "-c", "printf %s \"$1\" | wl-copy",
                         "sh", String(r.payload)]);
            break;
        case "command":
            tavola.commandRequested(r.payload);
            break;
        }
        tavola.close();
    }

    /// Le azioni che la shell deve eseguire per conto della tavola. Non le
    /// esegue qui: aprire il pannello impostazioni è compito della shell, che
    /// è l'unica a sapere se è già aperto.
    signal commandRequested(string id)

    function move(delta) {
        if (tavola.results.length === 0)
            return;
        tavola.selected = Math.max(0, Math.min(tavola.results.length - 1,
                                                tavola.selected + delta));
        list.positionViewAtIndex(tavola.selected, ListView.Contain);
    }

    // ── Sfondo ───────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: tavola.close()
        }
    }

    // ── La scheda ────────────────────────────────────────────────────────

    Rectangle {
        id: card

        width: Math.min(640, tavola.width - Theme.Effects.space6 * 2)
        // Cresce con i risultati e si ferma: una scheda che salta da 80 a 600
        // pixel a ogni tasto premuto è illeggibile.
        height: Math.min(field.height + list.contentHeight + Theme.Effects.space2 * 2,
                         tavola.height * 0.62)

        anchors.horizontalCenter: parent.horizontalCenter
        // Non centrata: un po' sopra la metà. È dove cade lo sguardo, e lascia
        // spazio all'elenco che cresce verso il basso.
        y: Math.round(tavola.height * 0.18)

        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        Behavior on height {
            NumberAnimation {
                duration: Theme.Motion.quick
                easing.type: Easing.OutCubic
            }
        }

        opacity: 0
        scale: 0.97
        Component.onCompleted: appear.start()
        ParallelAnimation {
            id: appear
            NumberAnimation {
                target: card; property: "opacity"; to: 1
                duration: Theme.Motion.quick
            }
            NumberAnimation {
                target: card; property: "scale"; to: 1
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.emerge
            }
        }

        // ── Campo di ricerca ─────────────────────────────────────────────

        Item {
            id: field
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 58

            Ui.Icon {
                id: fieldGlyph
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space4
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                name: tavola.query.indexOf("=") === 0 ? "plus"
                    : tavola.query.indexOf(">") === 0 ? "terminal"
                    : "search"
                color: Theme.Colors.accent
            }

            TextInput {
                id: input
                anchors.left: fieldGlyph.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space4
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                focus: true

                color: Theme.Colors.text
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
                selectedTextColor: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeLG

                onTextChanged: tavola.query = text

                Keys.onDownPressed: tavola.move(1)
                Keys.onUpPressed: tavola.move(-1)
                Keys.onReturnPressed: tavola.activate(tavola.selected)
                Keys.onEnterPressed: tavola.activate(tavola.selected)
                Keys.onEscapePressed: {
                    if (text !== "")
                        text = "";
                    else
                        tavola.close();
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: Core.Strings.lang === "it"
                          ? "Cerca un'applicazione, «=» per calcolare, «>» per un comando"
                          : "Search an app, “=” to calculate, “>” for a command"
                    color: Theme.Colors.textFaint
                    font: input.font
                    elide: Text.ElideRight
                    width: input.width
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.rightMargin: Theme.Effects.space3
                height: 1
                color: Theme.Colors.edge
                visible: tavola.results.length > 0
            }
        }

        // ── Risultati ────────────────────────────────────────────────────

        Ui.Scorrimento {
            bersaglio: list
            anchors {
                right: list.right
                top: list.top
                bottom: list.bottom
            }
        }

        ListView {
            id: list
            anchors.top: field.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.Effects.space2
            clip: true
            spacing: 1
            model: tavola.results
            currentIndex: tavola.selected
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                readonly property bool current: index === tavola.selected

                width: ListView.view.width
                height: 52
                radius: Theme.Effects.radiusSM
                color: current ? Qt.alpha(Theme.Colors.accent, 0.14)
                     : rowMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // Icona: file per le applicazioni, tracciato per tutto il resto
                Image {
                    id: rowImage
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    source: row.modelData.iconPath ? "file://" + row.modelData.iconPath : ""
                    sourceSize.width: 56
                    sourceSize.height: 56
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Ui.Icon {
                    anchors.centerIn: rowImage
                    width: 20; height: 20
                    name: row.modelData.icon || ""
                    visible: rowImage.status !== Image.Ready && name !== ""
                    color: row.current ? Theme.Colors.accent : Theme.Colors.textMuted
                }

                Rectangle {
                    anchors.centerIn: rowImage
                    width: 28; height: 28
                    radius: 14
                    visible: rowImage.status !== Image.Ready
                             && (row.modelData.icon || "") === ""
                    color: Theme.Colors.raisedHigh

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: (row.modelData.title || "?").charAt(0).toUpperCase()
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightBold
                    }
                }

                Column {
                    anchors.left: rowImage.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: hintKey.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.modelData.title || ""
                        color: row.current ? Theme.Colors.text : Theme.Colors.textMuted
                        font.family: row.modelData.kind === "math"
                                     || row.modelData.kind === "shell"
                                     ? Theme.Typography.fontMono
                                     : Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: row.current ? Theme.Typography.weightSemiBold
                                                 : Theme.Typography.weightRegular
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: row.modelData.subtitle || ""
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                // Il promemoria di Invio compare solo sulla riga selezionata:
                // ripetuto su ogni riga sarebbe rumore.
                Rectangle {
                    id: hintKey
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: hintText.implicitWidth + Theme.Effects.space3
                    height: 22
                    radius: Theme.Effects.radiusXS
                    visible: row.current
                    color: Qt.alpha(Theme.Colors.accent, 0.16)

                    Text {
                        id: hintText
                        anchors.centerIn: parent
                        text: Core.Strings.keyName("return")
                        color: Theme.Colors.accent
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: tavola.selected = row.index
                    onClicked: tavola.activate(row.index)
                }
            }
        }

        // Stato vuoto: compare solo quando si è scritto qualcosa. A campo
        // vuoto l'elenco mostra tutte le applicazioni, quindi non capita.
        Text {
            anchors.top: field.bottom
            anchors.topMargin: Theme.Effects.space5
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tavola.results.length === 0 && tavola.query.trim() !== ""
            text: Core.Strings.t("noResults")
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeMD
        }
    }
}
