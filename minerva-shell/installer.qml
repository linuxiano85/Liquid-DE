import QtQuick
import Quickshell
import Quickshell.Io

// Installer autonomo: nessun import del demone o delle impostazioni utente.
ShellRoot {
    id: app
    readonly property string rootPath: String(Quickshell.env("MINERVA_INSTALL_ROOT") || "")
    readonly property color paper: "#0B1424"
    readonly property color ink: "#F5FAFF"
    readonly property color mutedInk: "#CFDDEA"
    readonly property color quietInk: "#B5C8D9"
    readonly property color card: "#192D42"
    readonly property color cardBorder: "#4C6D87"
    readonly property color pigment: "#55E3EB"
    property int step: 0 // benvenuto, controllo, installazione, accesso, fine, errore
    property bool scanning: false
    property bool scanReady: false
    property bool choosing: false
    property int totalPackages: 0
    property var missingPackages: []
    property var managers: []
    property string currentManager: ""
    property string selectedManager: ""
    property string stage: ""
    property string logText: ""
    property string logPath: ""
    property string errorText: ""
    property string resultText: ""

    function addLog(line) {
        if (line.indexOf("@@MINERVA_STAGE@@") === 0) {
            app.stage = line.substring(17).trim();
            return;
        }
        if (line.indexOf("@@MINERVA_LOG@@") === 0) {
            app.logPath = line.substring(15).trim();
            return;
        }
        app.logText = (app.logText + line.replace(/\x1b\[[0-9;]*m/g, "") + "\n").slice(-24000);
        Qt.callLater(function() { logView.contentY = Math.max(0, logView.contentHeight - logView.height); });
    }

    function scan() {
        console.info("[installer] Controllo dipendenze avviato");
        app.step = 1;
        app.scanning = true;
        app.scanReady = false;
        app.errorText = "";
        app.missingPackages = [];
        app.totalPackages = 0;
        scanProc.command = [app.rootPath + "/scripts/install-minerva.sh", "--scan"];
        scanProc.running = true;
    }

    function install() {
        console.info("[installer] Installazione confermata dall’utente");
        app.step = 2;
        app.stage = "Preparazione dell’installazione";
        app.logText = "";
        app.logPath = "";
        app.errorText = "";
        installProc.command = [app.rootPath + "/scripts/minerva-install-run"];
        installProc.running = true;
    }

    function loadManagers() {
        console.info("[installer] Installazione terminata; leggo i gestori di accessi");
        app.managers = [];
        app.currentManager = "";
        app.selectedManager = "";
        managersProc.command = [app.rootPath + "/scripts/minerva-installer-managers"];
        managersProc.running = true;
    }

    function finishChoice() {
        if (app.selectedManager === "" || app.selectedManager === app.currentManager) {
            console.info("[installer] Gestore di accessi conservato: " + app.currentManager);
            app.resultText = app.currentManager === ""
                ? "Liquid DE è pronto. Nessun gestore di accessi è stato cambiato."
                : "Liquid DE è pronto. Il gestore di accessi attuale resta in uso.";
            app.step = 4;
            return;
        }
        app.choosing = true;
        console.info("[installer] Cambio gestore richiesto: " + app.selectedManager);
        app.errorText = "";
        changeProc.command = ["pkexec", "/usr/local/bin/minerva-greetd", "gestore", app.selectedManager];
        changeProc.running = true;
    }

    Process {
        id: scanProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var fields = line.trim().split("\t");
                if (fields[0] === "total") app.totalPackages = Number(fields[1]);
                else if (fields[0] === "missing") {
                    var next = app.missingPackages.slice();
                    next.push(fields[1]);
                    app.missingPackages = next;
                }
            }
        }
        stderr: SplitParser { splitMarker: "\n"; onRead: function(line) { app.errorText = line; } }
        onExited: function(code) {
            console.info("[installer] Controllo dipendenze terminato: codice " + code
                         + ", mancanti " + app.missingPackages.length);
            app.scanning = false;
            app.scanReady = code === 0;
            if (code !== 0) {
                app.errorText = app.errorText || "Controllo delle dipendenze non riuscito.";
                app.step = 5;
            }
        }
    }

    Process {
        id: installProc
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) { app.addLog(line); } }
        stderr: SplitParser { splitMarker: "\n"; onRead: function(line) { app.addLog(line); } }
        onExited: function(code) {
            console.info("[installer] Installazione terminata: codice " + code
                         + ", fase " + app.stage);
            if (code === 0) app.loadManagers();
            else {
                app.errorText = "Installazione interrotta durante: " + app.stage;
                app.step = 5;
            }
        }
    }

    Process {
        id: managersProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var fields = line.trim().split("\t");
                if (fields[0] === "current") app.currentManager = fields[1] || "";
                else if (fields[0] === "manager") {
                    var next = app.managers.slice();
                    next.push({ unit: fields[1], name: fields[2] });
                    app.managers = next;
                }
            }
        }
        onExited: function(code) {
            console.info("[installer] Elenco gestori terminato: codice " + code
                         + ", trovati " + app.managers.length);
            if (code === 0) {
                app.selectedManager = app.managers.some(function(m) { return m.unit === app.currentManager; })
                    ? app.currentManager : "";
                app.step = 3;
            }
            else {
                app.errorText = "Non riesco a leggere i gestori di accessi installati.";
                app.step = 5;
            }
        }
    }

    Process {
        id: changeProc
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) { app.addLog(line); } }
        stderr: SplitParser { splitMarker: "\n"; onRead: function(line) { app.addLog(line); app.errorText = line; } }
        onExited: function(code) {
            console.info("[installer] Cambio gestore terminato: codice " + code);
            app.choosing = false;
            if (code === 0) {
                app.resultText = "Liquid DE è pronto. Il gestore scelto sarà usato dal prossimo riavvio.";
                app.step = 4;
            } else if (code !== 126) {
                app.errorText = app.errorText || "Il gestore non è stato cambiato.";
                app.step = 5;
            }
        }
    }

    component ActionButton: Rectangle {
        id: button
        property string label: ""
        property bool primary: false
        property bool enabled: true
        signal clicked()
        implicitWidth: Math.max(150, caption.implicitWidth + 40)
        implicitHeight: 46
        radius: 15
        color: !enabled ? "#344458" : primary ? app.pigment
               : pointer.containsMouse ? "#2A455C" : app.card
        border.width: primary ? 0 : 1.5
        border.color: app.cardBorder
        Accessible.role: Accessible.Button
        Accessible.name: label
        Text {
            id: caption
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? app.paper : app.ink
            font.family: "Adwaita Sans"
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    FloatingWindow {
        id: window
        visible: true
        title: "Liquid DE · Installazione"
        implicitWidth: 1020
        implicitHeight: 690
        minimumSize: Qt.size(720, 520)
        color: app.paper

        // Pigmenti sovrapposti, senza shader: il disegno resta visibile anche
        // prima che esistano il compositore e le impostazioni di Minerva.
        Canvas {
            id: watercolor
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            function wash(ctx, x, y, radius, inner, middle) {
                var gradient = ctx.createRadialGradient(x, y, radius * 0.07,
                                                        x, y, radius);
                gradient.addColorStop(0, inner);
                gradient.addColorStop(0.48, middle);
                gradient.addColorStop(1, "rgba(0,0,0,0)");
                ctx.fillStyle = gradient;
                ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2);
            }
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                wash(ctx, width * 0.08, height * 0.14, 285,
                     "rgba(45,213,226,0.67)", "rgba(31,152,190,0.24)");
                wash(ctx, width * 0.25, height * 0.44, 255,
                     "rgba(180,139,248,0.52)", "rgba(111,80,186,0.19)");
                wash(ctx, width * 0.05, height * 0.85, 260,
                     "rgba(75,212,190,0.47)", "rgba(38,157,151,0.16)");
                wash(ctx, width * 0.74, height * 0.03, 340,
                     "rgba(68,199,222,0.31)", "rgba(51,126,170,0.11)");
                wash(ctx, width * 0.96, height * 0.93, 345,
                     "rgba(179,128,242,0.38)", "rgba(119,78,176,0.12)");
            }
        }

        Rectangle {
            id: brand
            width: Math.min(315, parent.width * 0.34)
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: "#85101D30"
            border.color: app.cardBorder
            border.width: 1
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24; topMargin: 30 }
                height: 250; radius: 25
                color: "#4414253B"
                border.width: 1
                border.color: "#7193A8"
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 40; topMargin: 48 }
                spacing: 20
                Image {
                    source: "file://" + app.rootPath + "/assets/marchio/minerva.svg"
                    width: 86; height: 86
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    text: "LIQUID DE"
                    color: app.ink
                    font.family: "Adwaita Sans"
                    font.pixelSize: 27
                    font.weight: Font.Bold
                }
                Rectangle { width: 70; height: 4; radius: 2; color: app.pigment }
                Text {
                    width: parent.width
                    text: "Una scrivania fluida, costruita attorno a te."
                    wrapMode: Text.WordWrap
                    color: app.mutedInk
                    font.family: "Adwaita Sans"
                    font.pixelSize: 17
                    lineHeight: 1.35
                }
            }
            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 32; bottomMargin: 36 }
                spacing: 14
                Text { text: "01  ·  Scopri"; color: app.step === 0 ? app.pigment : app.mutedInk; font.pixelSize: 13 }
                Text { text: "02  ·  Prepara"; color: app.step === 1 ? app.pigment : app.mutedInk; font.pixelSize: 13 }
                Text { text: "03  ·  Installa"; color: app.step === 2 ? app.pigment : app.mutedInk; font.pixelSize: 13 }
                Text { text: "04  ·  Accesso"; color: app.step >= 3 ? app.pigment : app.mutedInk; font.pixelSize: 13 }
            }
        }

        Rectangle {
            anchors { left: brand.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            color: "#AE0B1424"
        }

        Flickable {
            id: contentView
            anchors { left: brand.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 0 }
            contentWidth: width
            contentHeight: content.implicitHeight + 80
            clip: true
            Column {
                id: content
                x: 46; y: 44
                width: contentView.width - 92
                spacing: 20

                Text {
                    width: parent.width
                    text: app.step === 0 ? "Benvenuto in Minerva" :
                          app.step === 1 ? "Prepariamo il sistema" :
                          app.step === 2 ? "Liquid DE prende forma" :
                          app.step === 3 ? "Scegli come entrare" :
                          app.step === 4 ? "Tutto pronto" : "Serve un intervento"
                    color: app.ink
                    font.family: "Adwaita Sans"
                    font.pixelSize: 29
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: app.step === 0 ? "Compositore Wayland, interfaccia e applicazioni: un ambiente completo che si muove come un unico materiale." :
                          app.step === 1 ? "Controlliamo i componenti necessari. Installeremo solo quelli che mancano." :
                          app.step === 2 ? "Puoi seguire ogni fase. L’autorizzazione comparirà quando serve." :
                          app.step === 3 ? "La scelta vale dal prossimo riavvio. Il gestore attuale resta selezionato finché non decidi di cambiarlo." :
                          app.step === 4 ? app.resultText : app.errorText
                    color: app.step === 5 ? "#FFACBC" : app.mutedInk
                    font.family: "Adwaita Sans"
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }

                Column {
                    visible: app.step === 0
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: [
                            ["Compositore Minerva", "Finestre ed effetti su Wayland, costruiti per Liquid DE."],
                            ["Interfaccia unificata", "Barra, menu, impostazioni e applicazioni nello stesso linguaggio visivo."],
                            ["Accesso a tua scelta", "Minerva Login è pronta, senza imporre un cambio al sistema."]
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: content.width; height: 82; radius: 16
                            color: app.card
                            border.color: app.cardBorder; border.width: 1.5
                            Column {
                                anchors { fill: parent; margins: 16 }
                                spacing: 6
                                Text { text: modelData[0]; color: app.ink; font.pixelSize: 16; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: modelData[1]; color: app.mutedInk; font.pixelSize: 13; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                    ActionButton { label: "Controlla il sistema"; primary: true; onClicked: app.scan() }
                }

                Column {
                    visible: app.step === 1
                    width: parent.width
                    spacing: 16
                    Text {
                        width: parent.width
                        text: app.scanning ? "Controllo in corso…" :
                              app.missingPackages.length === 0 ? "Tutte le " + app.totalPackages + " dipendenze sono già presenti." :
                              app.missingPackages.length + " pacchetti da installare su " + app.totalPackages + " dipendenze."
                        color: app.ink
                        font.pixelSize: 18; font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        width: parent.width; height: Math.min(260, Math.max(74, packageText.implicitHeight + 28)); radius: 15
                        color: "#E60C1A2B"; border.color: app.cardBorder; border.width: 1.5
                        Flickable {
                            anchors { fill: parent; margins: 14 }
                            contentWidth: width; contentHeight: packageText.implicitHeight
                            clip: true
                            Text {
                                id: packageText
                                width: parent.width
                                text: app.scanning ? "Ricerca delle dipendenze…" :
                                      app.missingPackages.length ? app.missingPackages.join("  ·  ") : "Nessun pacchetto mancante"
                                wrapMode: Text.WordWrap
                                color: app.mutedInk
                                font.family: "Noto Sans Mono"; font.pixelSize: 13
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: "Installeremo i componenti del desktop, compileremo Minerva e prepareremo la sua schermata di accesso. Il login manager attivo non cambia in questa fase."
                        color: app.mutedInk; font.pixelSize: 14; wrapMode: Text.WordWrap
                    }
                    Row {
                        spacing: 12
                        ActionButton { label: "Indietro"; onClicked: app.step = 0 }
                        ActionButton { label: "Installa Liquid DE"; primary: true; enabled: app.scanReady; onClicked: app.install() }
                    }
                }

                Column {
                    visible: app.step === 2 || (app.step === 5 && app.logText !== "")
                    width: parent.width; spacing: 14
                    Text { width: parent.width; text: app.stage; color: app.pigment; font.pixelSize: 17; wrapMode: Text.WordWrap }
                    Rectangle {
                        width: parent.width; height: 300; radius: 15
                        color: "#E60C1A2B"; border.color: app.cardBorder; border.width: 1.5
                        Flickable {
                            id: logView
                            anchors { fill: parent; margins: 14 }
                            contentWidth: width; contentHeight: logLabel.implicitHeight
                            clip: true
                            Text {
                                id: logLabel
                                width: parent.width
                                text: app.logText || "In attesa del primo passaggio…"
                                color: app.mutedInk
                                font.family: "Noto Sans Mono"; font.pixelSize: 12
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                    Text { visible: app.logPath !== ""; width: parent.width; text: "Registro completo: " + app.logPath; color: app.quietInk; font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
                }

                Column {
                    visible: app.step === 3
                    width: parent.width; spacing: 11
                    Repeater {
                        model: [{ unit: "", name: "Non cambiare adesso" }].concat(app.managers)
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: app.selectedManager === modelData.unit
                            width: content.width; height: 65; radius: 15
                            color: selected ? "#28526A" : app.card
                            border.color: selected ? app.pigment : app.cardBorder
                            border.width: selected ? 2 : 1.5
                            Row {
                                anchors { fill: parent; margins: 16 }
                                spacing: 14
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 19; height: 19; radius: 10
                                    color: "transparent"; border.color: selected ? app.pigment : app.mutedInk; border.width: 2
                                    Rectangle { anchors.centerIn: parent; width: 9; height: 9; radius: 5; color: app.pigment; visible: selected }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Text { text: modelData.name; color: app.ink; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text {
                                        text: modelData.unit === "" ? "Conserva la configurazione attuale" :
                                              modelData.unit === app.currentManager ? "Attualmente attivo" :
                                              modelData.unit === "greetd.service" ? "Schermata di accesso di Minerva" : modelData.unit
                                        color: app.mutedInk; font.pixelSize: 12
                                    }
                                }
                            }
                            MouseArea { anchors.fill: parent; enabled: !app.choosing; cursorShape: Qt.PointingHandCursor; onClicked: app.selectedManager = modelData.unit }
                        }
                    }
                    ActionButton { label: app.choosing ? "Cambio in corso…" : "Conferma e termina"; primary: true; enabled: !app.choosing; onClicked: app.finishChoice() }
                    Text { width: parent.width; text: "Se la nuova schermata non funziona: entra da una console testuale e usa sudo minerva-greetd indietro."; color: app.mutedInk; font.pixelSize: 12; wrapMode: Text.WordWrap }
                }

                Column {
                    visible: app.step === 4 || app.step === 5
                    width: parent.width; spacing: 14
                    ActionButton { visible: app.step === 5; label: "Riprova dal controllo"; primary: true; onClicked: app.scan() }
                    Text {
                        visible: app.step === 4
                        width: parent.width
                        text: "Esci dalla sessione e scegli «Liquid DE» nel gestore di accessi. Se hai cambiato gestore, la scelta sarà attiva dal prossimo riavvio."
                        color: app.mutedInk; font.pixelSize: 15; wrapMode: Text.WordWrap
                    }
                    Text {
                        visible: app.step === 4 && app.logPath !== ""
                        width: parent.width
                        text: "Registro dell’installazione: " + app.logPath
                        color: app.quietInk; font.pixelSize: 12; wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }
}
