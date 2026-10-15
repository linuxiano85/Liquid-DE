import QtQuick
import Quickshell
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W

Column {
    id: content
    spacing: 12
    readonly property bool it: Core.Strings.lang === "it"
    readonly property bool windows: Core.DesktopStyle.attuale === "windows"
    readonly property color foreground: windows ? W.Style.text : Theme.Colors.text
    readonly property color secondary: windows ? W.Style.muted : Theme.Colors.textMuted
    readonly property color surface: windows ? W.Style.card : Theme.Colors.raised
    readonly property color outline: windows ? W.Style.cardStroke : Qt.alpha(foreground, 0.14)
    readonly property real textScale: windows ? W.Style.textScale : Theme.Typography.scala
    property bool showPackages: false
    property string confirmation: ""
    property string driverMessage: ""
    property var selectedDevice: null
    property string driverQuery: ""
    component PrintLabel: Text {
        textFormat: Text.PlainText
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        font.family: content.windows ? W.Style.font : Theme.Typography.fontDisplay
        font.pixelSize: 14 * content.textScale
    }
    function label(italian, english) { return it ? italian : english; }
    function action(key, request) {
        if (confirmation !== key) { confirmation = key; expiry.restart(); return; }
        confirmation = "";
        expiry.stop();
        Core.Printing.request(request);
    }
    function manage() {
        driverMessage = "";
        manager.start(["python3", "-I", Core.Printing.helper, JSON.stringify({action:"support"})]);
    }
    Connections {
        target: Core.Printing
        function onRefreshed() {
            if (Core.Printing.lastAction === "drivers") revealQueue.restart();
            if (Core.Printing.lastAction === "configure" && Core.Printing.available) {
                content.selectedDevice = null;
                Core.Printing.drivers = [];
            }
        }
    }
    // Il risultato asincrono può inserire un messaggio sopra al modulo.
    // Accompagniamo il campo dopo il layout, senza rubare nuovamente il focus.
    Timer {
        id: revealQueue
        interval: 60
        onTriggered: {
            if (!queueName.activeFocus || !content.selectedDevice) return;
            var ancestor = content.parent;
            while (ancestor && typeof ancestor.revealItem !== "function") ancestor = ancestor.parent;
            if (ancestor) ancestor.revealItem(queueName);
        }
    }
    Timer { id: expiry; interval: 8000; onTriggered: content.confirmation = "" }
    Core.Exec {
        id: manager
        onCompleted: function(code, out, stderr) {
            try {
                var result = JSON.parse(out);
                if (!result.manager) throw new Error(content.label("Installa system-config-printer dal gestore pacchetti.", "Install system-config-printer using your package manager."));
                Quickshell.execDetached([result.manager]);
                content.driverMessage = content.label("Il gestore CUPS si è aperto: aggiungi una stampante o modifica il driver. Poi premi Aggiorna.",
                    "CUPS manager opened: add a printer or change its driver. Then press Refresh.");
            } catch (e) { content.driverMessage = String(e.message || stderr || e); }
        }
    }
    Component.onCompleted: Core.Printing.refresh()
    PrintLabel {
        width: parent.width
        text: content.label("Stampanti installate", "Installed printers")
        color: content.foreground
        font.pixelSize: 20 * content.textScale
        wrapMode: Text.Wrap
    }
    Flow {
        width: parent.width
        spacing: 8
        PrintingAction { text: Core.Printing.busy ? content.label("Attendi…", "Please wait…") : content.label("Aggiorna", "Refresh"); enabled: !Core.Printing.busy; onClicked: Core.Printing.refresh() }
        PrintingAction { text: content.label("Cerca USB e rete", "Find USB and network"); enabled: !Core.Printing.busy; onClicked: Core.Printing.request({action:"discover"}) }
        PrintingAction {
            text: content.label("Driver aggiuntivi", "Additional drivers")
            enabled: !Core.Printing.busy
            onClicked: {
                content.showPackages = !content.showPackages;
                if (content.showPackages) Core.Printing.request({action:"packages"});
            }
        }
        PrintingAction { text: content.label("Aggiungi e gestisci driver", "Add and manage drivers"); enabled: !manager.busy; onClicked: content.manage() }
    }
    PrintLabel {
        width: parent.width
        visible: text !== ""
        text: Core.Printing.error || Core.Printing.lastResult || content.driverMessage
        wrapMode: Text.Wrap
        color: content.foreground
        font.pixelSize: 14 * content.textScale
    }
    PrintLabel {
        width: parent.width
        visible: Core.Printing.available && !Core.Printing.printers.length
        text: content.label("Nessuna coda installata. Cerca una stampante USB o di rete, poi aggiungila con il gestore dei driver.",
            "No installed queues. Find a USB or network printer, then add it using the driver manager.")
        color: content.secondary
        wrapMode: Text.Wrap
    }
    Column {
        width: parent.width
        visible: content.showPackages
        spacing: 10
        PrintLabel {
            text: content.label("Driver dai repository configurati", "Drivers from configured repositories")
            color: content.foreground
            font.pixelSize: 18 * content.textScale
        }
        PrintLabel {
            text: content.label("Installa soltanto il pacchetto necessario al modello. Dopo l’installazione, cerca nuovamente il driver e scegli il modello esatto. I pacchetti non sostituiscono automaticamente i driver delle code esistenti.",
                "Install only the package required for your model. Afterwards, search for drivers again and choose the exact model. Packages do not automatically replace drivers of existing queues.")
            color: content.secondary
        }
        PrintLabel {
            visible: !Core.Printing.packageInstallSupported
            text: content.label("Installazione integrata disponibile su Arch e derivate. Su questa distribuzione usa il gestore pacchetti.",
                "Integrated installation supports Arch and derivatives. Use your package manager on this distribution.")
            color: content.secondary
        }
        Repeater {
            model: Core.Printing.packages
            delegate: Column {
                required property var modelData
                width: content.width
                spacing: 4
                PrintLabel {
                    text: modelData.title + " · " + modelData.id + (modelData.installed ? content.label(" · Installato", " · Installed") : "")
                    color: content.foreground
                }
                PrintingAction {
                    visible: !modelData.installed
                    enabled: !Core.Printing.busy
                    text: content.confirmation === "package:" + modelData.id ? content.label("Conferma installazione", "Confirm installation") : content.label("Installa pacchetto", "Install package")
                    onClicked: content.action("package:" + modelData.id, {action:"install-driver",package:modelData.id})
                }
            }
        }
    }
    Repeater {
        model: Core.Printing.printers
        delegate: Rectangle {
            id: card
            required property var modelData
            width: content.width
            height: body.height + 32
            color: content.surface
            radius: content.windows ? 4 : 12
            border.width: 1
            border.color: content.outline
            Column {
                id: body
                x: 16; y: 16
                width: parent.width - 32
                spacing: 10
                PrintLabel {
                    width: parent.width
                    text: card.modelData.description + (card.modelData.default ? content.label(" · Predefinita", " · Default") : "")
                    color: content.foreground
                    font.pixelSize: 17 * content.textScale
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                PrintLabel {
                    width: parent.width
                    text: Core.Printing.stateLabel(card.modelData) + "\n" + card.modelData.model
                    color: content.secondary
                    wrapMode: Text.Wrap
                    font.pixelSize: 14 * content.textScale
                }
                PrintLabel {
                    width: parent.width
                    text: content.label("Inchiostro e toner · ultimi dati comunicati dal driver", "Ink and toner · last data reported by driver")
                    color: content.foreground
                    wrapMode: Text.Wrap
                    font.pixelSize: 14 * content.textScale
                }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: card.modelData.supplies || []
                        delegate: Column {
                            id: supply
                            required property var modelData
                            width: Math.min(170, body.width)
                            spacing: 5
                            PrintLabel {
                                width: parent.width
                                text: Core.Printing.supplyLabel(supply.modelData) + " · " + (supply.modelData.level === null
                                    ? content.label("non disponibile", "unavailable") : supply.modelData.level + "%")
                                    + (supply.modelData.low ? " !" : "")
                                wrapMode: Text.Wrap
                                color: content.foreground
                                font.pixelSize: 13 * content.textScale
                            }
                            Rectangle {
                                width: parent.width; height: 8; radius: 4
                                color: Qt.alpha(content.foreground, 0.13)
                                Rectangle {
                                    visible: supply.modelData.level !== null
                                    width: parent.width * (supply.modelData.level || 0) / 100
                                    height: parent.height; radius: 4
                                    color: supply.modelData.color
                                    border.width: 1; border.color: Qt.alpha(content.foreground, 0.25)
                                }
                            }
                        }
                    }
                }
                PrintLabel {
                    width: parent.width
                    text: (card.modelData.supplies || []).length ? content.label("I livelli non verificano la qualità di stampa o lo stato degli ugelli. La quantità di carta è mostrata solo se segnalata dalla stampante.",
                        "Levels do not verify print quality or nozzle condition. Paper quantity is shown only when reported by the printer.")
                        : content.label("Il driver non comunica i livelli dei consumabili.", "The driver does not report supply levels.")
                    color: content.secondary
                    wrapMode: Text.Wrap
                    font.pixelSize: 13 * content.textScale
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    PrintingAction {
                        text: content.label("Imposta predefinita", "Set as default")
                        visible: !card.modelData.default
                        enabled: !Core.Printing.busy
                        onClicked: Core.Printing.request({action:"default", printer:card.modelData.name})
                    }
                    PrintingAction {
                        text: content.confirmation === card.modelData.name + ":test" ? content.label("Conferma stampa B/N", "Confirm B/W print") : content.label("Pagina di prova B/N", "B/W test page")
                        enabled: !Core.Printing.busy && card.modelData.accepting
                        onClicked: content.action(card.modelData.name + ":test", {action:"test-page", printer:card.modelData.name, options:{color:"monochrome"}})
                    }
                    Repeater {
                        model: card.modelData.maintenance || []
                        delegate: PrintingAction {
                            required property string modelData
                            readonly property string key: card.modelData.name + ":" + modelData
                            readonly property var titles: ({"self-test":content.label("Autotest del driver (colore)", "Driver self-test (color)"),
                                clean:content.label("Pulizia testina", "Clean print head"), levels:content.label("Rileggi livelli", "Refresh supply levels")})
                            text: content.confirmation === key ? content.label("Conferma", "Confirm") + " · " + titles[modelData] : titles[modelData]
                            enabled: !Core.Printing.busy
                            onClicked: content.action(key, {action:"maintenance", printer:card.modelData.name, operation:modelData})
                        }
                    }
                }
                PrintLabel {
                    width: parent.width
                    text: content.label("Pulizia, test ugelli e allineamento dipendono dal modello e dal driver. Se non esposti, usa il pannello della stampante; non inviamo comandi generici. La pulizia consuma inchiostro.",
                        "Cleaning, nozzle checks and alignment depend on the model and driver. When unavailable, use the printer's own controls; generic commands are not sent. Cleaning uses ink.")
                    color: content.secondary
                    wrapMode: Text.Wrap
                    font.pixelSize: 13 * content.textScale
                }
            }
        }
    }
    PrintLabel {
        width: parent.width
        text: content.label("Coda di stampa · lavori dell’utente corrente", "Print queue · current user's jobs")
        color: content.foreground; font.pixelSize: 18 * content.textScale; wrapMode: Text.Wrap
    }
    PrintLabel {
        visible: !Core.Printing.jobs.length
        text: content.label("Nessun documento in attesa.", "No pending documents.")
        color: content.secondary; font.pixelSize: 14 * content.textScale
    }
    Repeater {
        model: Core.Printing.jobs
        delegate: Column {
            required property var modelData
            width: content.width
            spacing: 5
            PrintLabel {
                width: parent.width
                text: "#" + modelData.id + " · " + modelData.title + "\n" + modelData.printer + " · " + modelData.sheets + content.label(" fogli completati", " completed sheets")
                color: content.foreground; wrapMode: Text.Wrap; font.pixelSize: 14 * content.textScale
            }
            PrintingAction {
                text: content.confirmation === "job:" + modelData.id ? content.label("Conferma annullamento", "Confirm cancel") : content.label("Annulla lavoro", "Cancel job")
                enabled: !Core.Printing.busy
                onClicked: content.action("job:" + modelData.id, {action:"cancel", job:modelData.id})
            }
        }
    }
    PrintLabel {
        width: parent.width
        visible: Core.Printing.discovered.length > 0
        text: content.label("Dispositivi rilevati · possono essere già configurati", "Discovered devices · may already be configured")
        color: content.foreground; font.pixelSize: 18 * content.textScale; wrapMode: Text.Wrap
    }
    Repeater {
        model: Core.Printing.discovered
        delegate: Column {
            required property var modelData
            width: content.width
            spacing: 6
            PrintLabel {
                width: parent.width
                text: modelData.description + " · " + (modelData.kind === "usb" ? "USB" : content.label("Rete", "Network")) + "\n" + modelData.model
                color: content.secondary; wrapMode: Text.Wrap; font.pixelSize: 14 * content.textScale
            }
            PrintingAction {
                text: content.label("Configura", "Set up")
                enabled: !Core.Printing.busy
                onClicked: {
                    content.selectedDevice = modelData;
                    content.driverQuery = modelData.model || modelData.description;
                    queueName.text = String(modelData.description || "Stampante").replace(/[^A-Za-z0-9_-]/g,"-").substring(0,63);
                    if (!/^[A-Za-z0-9]/.test(queueName.text)) queueName.text = "Stampante";
                    driverQueryInput.text = content.driverQuery;
                    Qt.callLater(function() { queueName.forceActiveFocus(); revealQueue.restart(); });
                    Core.Printing.drivers = [];
                    Core.Printing.request({action:"drivers", query:content.driverQuery});
                }
            }
        }
    }
    Column {
        visible: content.selectedDevice !== null
        width: parent.width
        spacing: 10
        PrintLabel {
            width: parent.width
            text: content.label("Configura la stampante · autorizzazione di sistema richiesta", "Set up printer · system authorization required")
            color: content.foreground; wrapMode: Text.Wrap; font.pixelSize: 18 * content.textScale
        }
        PrintLabel { text: content.label("Nome della coda (lettere, numeri, trattini)", "Queue name (letters, digits, hyphens)"); color:content.secondary }
        Rectangle {
            width: parent.width; height: 38; radius: 4
            color: content.surface; border.width: 1; border.color: content.outline
            TextInput {
                id: queueName
                objectName: "nomeCodaStampante"
                anchors.fill: parent; anchors.margins: 8
                color: content.foreground; font.pixelSize: 14 * content.textScale; selectByMouse: true; clip:true
                Accessible.name: content.label("Nome della coda", "Queue name")
            }
        }
        PrintLabel { text: content.label("Cerca nei driver installati", "Search installed drivers"); color:content.secondary }
        Rectangle {
            width: parent.width; height: 38; radius: 4
            color: content.surface; border.width: 1; border.color: content.outline
            TextInput {
                id: driverQueryInput
                anchors.fill: parent; anchors.margins: 8
                color: content.foreground; font.pixelSize: 14 * content.textScale; selectByMouse:true; clip:true
                Accessible.name: content.label("Modello del driver", "Driver model")
            }
        }
        Flow {
            width: parent.width; spacing: 8
            PrintingAction {
                text: content.label("Cerca driver", "Find drivers")
                enabled: !Core.Printing.busy && driverQueryInput.text.trim() !== ""
                onClicked: {
                    content.driverQuery = driverQueryInput.text.trim();
                    Core.Printing.request({action:"drivers", query:content.driverQuery});
                }
            }
            PrintingAction {
                text: content.confirmation === "install:everywhere" ? content.label("Conferma IPP Everywhere", "Confirm IPP Everywhere") : "IPP Everywhere"
                visible: content.selectedDevice !== null && /^ipps?:/.test(content.selectedDevice.uri)
                enabled: !Core.Printing.busy
                onClicked: content.action("install:everywhere", {action:"configure",name:queueName.text,
                    uri:content.selectedDevice.uri,driver:"everywhere"})
            }
            PrintingAction { text:content.label("Chiudi", "Close"); onClicked:content.selectedDevice=null }
        }
        PrintLabel {
            width: parent.width
            text: content.label("IPP Everywhere non richiede pacchetti del produttore. Per i driver mancanti puoi usare il gestore CUPS, che ricerca il modello e guida l’installazione. Le code esistenti non vengono sostituite né condivise in rete.",
                "IPP Everywhere needs no vendor packages. For missing drivers, the CUPS manager searches your model and guides installation. Existing queues are not replaced or shared over the network.")
            color: content.secondary; wrapMode:Text.Wrap; font.pixelSize:13
        }
        Repeater {
            model: Core.Printing.drivers
            delegate: Column {
                required property var modelData
                width: content.width
                spacing: 4
                PrintLabel { width:parent.width; text:modelData.model; color:content.foreground; wrapMode:Text.Wrap }
                PrintingAction {
                    text: content.confirmation === "install:" + modelData.id ? content.label("Conferma installazione", "Confirm installation") : content.label("Usa questo driver", "Use this driver")
                    enabled: !Core.Printing.busy
                    onClicked: content.action("install:" + modelData.id, {action:"configure",name:queueName.text,
                        uri:content.selectedDevice.uri,driver:modelData.id,query:content.driverQuery})
                }
            }
        }
    }
}
