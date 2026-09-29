import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "../monitor" as Mon

// ── Attività, dentro la shell ────────────────────────────────────────────
//
// Giacomo, 28 settembre 2026: il gestore dei processi «molto pesante per
// essere un task manager che dovrebbe essere piccolissimo […] rifacessi il
// look per liquid e la rendessi fondamentale per il sistema». Fra tre strade
// ha scelto questa: un pannello della shell, come il Centro. Una finestra Qt
// Quick a sé costa ~69 MB prima di disegnare una riga (`minerva-peso-app`);
// qui Quickshell, il tema e il collegamento col demone ci sono già, e si
// paga solo quello che si disegna.
//
// Scende dall'alto con la molla, con Ctrl+Maiusc+Esc — la scorciatoia che
// tutti conoscono — e se ne va premendo fuori o Esc. I dati sono gli stessi
// della finestra (`monitor/Processi.qml`): il demone legge `/proc` SOLO
// mentre il pannello è aperto. «In una finestra» apre la finestra di sempre,
// per chi lo vuole tenere accanto a quello che sta guardando.
PanelWindow {
    id: attivita

    property bool aperto: false
    property bool mostrato: false
    /// Spazio da lasciare in alto (la barra) e in basso (la dock).
    property real margineAlto: 0
    property real margineBasso: 0

    /// «In una finestra»: la shell apre la finestra di sempre.
    signal finestraChiesta()

    readonly property bool it: Core.Strings.lang === "it"

    function apri() {
        if (attivita.aperto) return;
        attivita.aperto = true;
        attivita.mostrato = true;
        spegni.stop();
        dati.filtro = "";
        if (contenuto.item)
            contenuto.item.cerca();
    }
    function chiudi() {
        if (!attivita.aperto) return;
        attivita.aperto = false;
        spegni.restart();
    }
    function commuta() { attivita.aperto ? attivita.chiudi() : attivita.apri(); }

    function pausa() { dati.inPausa = !dati.inPausa; }
    function vista(v) { dati.vista = v; }

    /// Per le prove: che cosa si vede.
    function riassunto() {
        return "attività: " + (attivita.aperto ? "aperta" : "chiusa")
               + " · vista " + dati.vista + " · righe " + dati.modello.count
               + " · processi " + dati.processi.length
               + (dati.inPausa ? " · in pausa" : "");
    }

    Mon.Processi {
        id: dati
        attivo: attivita.aperto
    }

    visible: attivita.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-attivita"
    WlrLayershell.layer: WlrLayer.Overlay
    // La tastiera SUBITO, come il Centro: si apre per cercare, e con
    // «al primo clic» Qt annullava proprio quel clic (qml-fuoco-annulla-clic).
    WlrLayershell.keyboardFocus: attivita.aperto ? WlrKeyboardFocus.Exclusive
                                                 : WlrKeyboardFocus.None

    Timer { id: spegni; interval: Theme.Motion.liquido ? 650 : 0; onTriggered: if (!attivita.aperto) attivita.mostrato = false }

    // Il fondo: premere fuori chiude, già alla pressione.
    MouseArea {
        anchors.fill: parent
        enabled: attivita.aperto
        onPressed: attivita.chiudi()
    }

    // ── La carta, solo mentre si vede ────────────────────────────────────
    //
    // Nasce all'apertura e se ne va quando la molla l'ha portata fuori: un
    // pannello su ogni schermo che tiene in memoria quattro grafici e un
    // elenco per tutto il giorno, per essere aperto due volte, costava 3,5 MB
    // alla shell a riposo (misurati il 28 settembre 2026, shell di prova).
    Loader {
        id: contenuto
        anchors.fill: parent
        active: attivita.mostrato
        onLoaded: if (attivita.aperto) contenuto.item.cerca()

        // Il Loader allarga quello che carica alla sua misura, cioè a tutto
        // lo schermo: la carta sta DENTRO un contenitore, o diventa lei
        // grande quanto lo schermo.
        sourceComponent: Component {
          Item {
            function cerca() { carta.cerca(); }
            // ── La carta ─────────────────────────────────────────────────────────
            Rectangle {
                id: carta
                readonly property int margine: Theme.Effects.space4
                width: Math.min(860, attivita.width - 2 * margine)
                height: Math.min(640, attivita.height - attivita.margineAlto
                                      - attivita.margineBasso - 2 * margine)
                x: (attivita.width - width) / 2
                // `entrata` si accende un battito dopo la nascita: nata già
            // «aperta», la carta comparirebbe al suo posto senza scendere.
            property bool entrata: false
            Component.onCompleted: Qt.callLater(function() { carta.entrata = true; })
            y: attivita.aperto && carta.entrata ? attivita.margineAlto + margine : -height - 30
                Behavior on y {
                    enabled: Theme.Motion.liquido
                    SpringAnimation { spring: Theme.Motion.molla * 0.6; damping: 0.42 }
                }
                radius: Theme.Effects.radiusLG
                color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                               Math.max(Theme.Colors.panel.a, 0.98))
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge
                clip: true

                MouseArea { anchors.fill: parent; onClicked: {} }

            // Chi guarda l'elenco ferma l'ordine: lo dice la lista, che vive qui.
            Binding {
                target: dati
                property: "ordineFermo"
                value: elenco.moving || sopraElenco.hovered
            }

            function cerca() { campo.forceActiveFocus(); }

                Item {
                    id: dentro
                    anchors.fill: parent
                    anchors.margins: Theme.Effects.space4
                    opacity: attivita.aperto ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

                    // ── Come sta, e le due uscite ────────────────────────────────
                    Item {
                        id: testa
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.right: uscite.left
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: String(dati.macchina.comeSta || (attivita.it ? "Attività" : "Activity"))
                                      .replace(/\.$/, "")
                                  + (dati.macchina.acceso
                                     ? "  ·  " + (attivita.it ? "acceso da " : "up ")
                                       + dati.durata(dati.macchina.acceso)
                                     : "")
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightMedium
                        }

                        Row {
                            id: uscite
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.Effects.space2

                            Pastiglia {
                                testo: attivita.it ? "In una finestra" : "In a window"
                                onPremuta: { attivita.chiudi(); attivita.finestraChiesta(); }
                            }
                            Pastiglia {
                                testo: "Esc"
                                onPremuta: attivita.chiudi()
                            }
                        }
                    }

                    // ── Quattro numeri, coi loro ultimi due minuti ───────────────
                    Row {
                        id: cruscotto
                        anchors.top: testa.bottom
                        anchors.topMargin: Theme.Effects.space3
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Effects.space2
                        readonly property real largo: (width - spacing * 3) / 4

                        Mon.StatTile {
                            width: cruscotto.largo
                            titolo: attivita.it ? "PROCESSORE" : "CPU"
                            valore: dati.macchina.cpu !== undefined ? Math.round(dati.macchina.cpu) : "—"
                            unita: "%"
                            sotto: (dati.macchina.core || 0) + (attivita.it ? " core" : " cores")
                            punti: dati.storiaCpu
                            massimo: 100
                            allarme: (dati.macchina.cpu || 0) > 85
                        }
                        Mon.StatTile {
                            width: cruscotto.largo
                            titolo: attivita.it ? "MEMORIA" : "MEMORY"
                            valore: dati.macchina.memoriaTotale > 0
                                    ? Math.round(dati.macchina.memoriaUsata / dati.macchina.memoriaTotale * 100) : "—"
                            unita: "%"
                            // Con qualcosa di compresso, il conto del respiro al
                            // posto di «usata / totale» (che resta nella percentuale).
                            sotto: dati.risparmio.pagine > 0
                                   ? (attivita.it ? "respiro: " : "breathing: ")
                                     + dati.byte(dati.risparmio.pagine - dati.risparmio.occupa)
                                     + (attivita.it ? " risparmiati" : " saved")
                                   : dati.byte(dati.macchina.memoriaUsata) + " / " + dati.byte(dati.macchina.memoriaTotale)
                            punti: dati.storiaMem
                            massimo: 100
                            colore: Theme.Colors.accentAlt !== undefined ? Theme.Colors.accentAlt : Theme.Colors.accent
                            allarme: dati.macchina.memoriaTotale > 0
                                     && dati.macchina.memoriaUsata / dati.macchina.memoriaTotale > 0.9
                        }
                        Mon.StatTile {
                            width: cruscotto.largo
                            titolo: attivita.it ? "RETE" : "NETWORK"
                            valore: dati.byte((dati.macchina.reteGiu || 0) + (dati.macchina.reteSu || 0))
                            unita: "/s"
                            sotto: "↓ " + dati.byte(dati.macchina.reteGiu) + "   ↑ " + dati.byte(dati.macchina.reteSu)
                            punti: dati.storiaRete
                            massimo: 0
                        }
                        Mon.StatTile {
                            width: cruscotto.largo
                            titolo: attivita.it ? "TEMPERATURA" : "TEMPERATURE"
                            valore: dati.macchina.temperatura !== undefined ? Math.round(dati.macchina.temperatura) : "—"
                            unita: "°C"
                            sotto: {
                                var t = dati.macchina.temperatura || 0;
                                if (t > 80) return attivita.it ? "calda" : "hot";
                                if (t > 65) return attivita.it ? "tiepida" : "warm";
                                return attivita.it ? "fresca" : "cool";
                            }
                            punti: dati.storiaTemp
                            massimo: 100
                            allarme: (dati.macchina.temperatura || 0) > 80
                        }
                    }

                    // ── Viste, ricerca, ordine, pausa ────────────────────────────
                    Item {
                        id: comandi
                        anchors.top: cruscotto.bottom
                        anchors.topMargin: Theme.Effects.space3
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 34

                        Row {
                            id: viste
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: [ { "id": "app", "it": "App", "en": "Apps" },
                                         { "id": "tutti", "it": "Processi", "en": "Processes" } ]
                                delegate: Pastiglia {
                                    required property var modelData
                                    testo: attivita.it ? modelData.it : modelData.en
                                    scelta: dati.vista === modelData.id
                                    onPremuta: dati.vista = modelData.id
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: viste.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.right: destra.left
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            height: 32
                            radius: height / 2
                            color: Theme.Colors.sunken
                            border.width: Theme.Effects.hairline
                            border.color: campo.activeFocus ? Theme.Colors.edgeAccent : Theme.Colors.edge

                            Ui.Icon {
                                id: lente
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14
                                name: "search"
                                color: Theme.Colors.textFaint
                                alwaysDrawn: true
                            }
                            TextInput {
                                id: campo
                                anchors.left: lente.right
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                onTextChanged: dati.filtro = text
                                color: Theme.Colors.text
                                selectionColor: Qt.alpha(Theme.Colors.accent, 0.35)
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                Keys.onEscapePressed: {
                                    if (campo.text !== "") campo.text = "";
                                    else attivita.chiudi();
                                }
                                Text {
                                    anchors.fill: parent
                                    visible: campo.text === ""
                                    verticalAlignment: Text.AlignVCenter
                                    text: attivita.it ? "Cerca un programma o un processo…"
                                                      : "Search a program or process…"
                                    color: Theme.Colors.textFaint
                                    font: campo.font
                                }
                            }
                        }

                        Row {
                            id: destra
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Pastiglia {
                                testo: dati.inPausa ? (attivita.it ? "Riprendi" : "Resume")
                                                    : (attivita.it ? "Pausa" : "Pause")
                                scelta: dati.inPausa
                                tinta: Theme.Colors.warning
                                onPremuta: dati.inPausa = !dati.inPausa
                            }
                            Repeater {
                                model: [ { "id": "cpu", "it": "CPU", "en": "CPU" },
                                         { "id": "memoria", "it": "Memoria", "en": "Memory" },
                                         { "id": "nome", "it": "Nome", "en": "Name" } ]
                                delegate: Pastiglia {
                                    required property var modelData
                                    testo: attivita.it ? modelData.it : modelData.en
                                    scelta: dati.ordine === modelData.id
                                    onPremuta: dati.ordine = modelData.id
                                }
                            }
                        }
                    }

                    // ── L'elenco ─────────────────────────────────────────────────
                    Rectangle {
                        id: cornice
                        anchors.top: comandi.bottom
                        anchors.topMargin: Theme.Effects.space3
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: piede.top
                        anchors.bottomMargin: Theme.Effects.space2
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        clip: true

                        ListView {
                            id: elenco
                            anchors.fill: parent
                            clip: true
                            model: dati.modello
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 300

                            HoverHandler { id: sopraElenco }

                            delegate: Mon.ProcessRow {
                                required property var model
                                width: ListView.view.width
                                riga: model.riga
                                ostinato: dati.pidOstinato === model.riga.pid
                                onChiudi: function(pid, forza) { Core.Ipc.killProcess(pid, forza); }
                            }
                        }

                        Ui.Scorrimento {
                            bersaglio: elenco
                            anchors { right: elenco.right; top: elenco.top; bottom: elenco.bottom }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: dati.modello.count === 0
                            text: dati.filtro !== ""
                                  ? (attivita.it ? "Nessun processo con questo nome" : "No process with that name")
                                  : dati.processi.length === 0
                            ? (attivita.it ? "In attesa dei dati…" : "Waiting for data…")
                            // I dati ci sono: è che nessun programma ha una
                            // finestra. Dirlo «in attesa» sarebbe una bugia.
                            : (attivita.it ? "Nessun programma ha una finestra aperta"
                                           : "No program has an open window")
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }

                    Text {
                        id: piede
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        text: {
                            var n = dati.modello.count;
                            var t = dati.processi.length;
                            var base = dati.vista === "app"
                                ? (attivita.it ? n + (n === 1 ? " applicazione" : " applicazioni")
                                                 + " · " + t + " processi in tutto"
                                               : n + (n === 1 ? " application" : " applications")
                                                 + " · " + t + " processes in total")
                                : (attivita.it ? n + (n === 1 ? " processo" : " processi")
                                               : n + (n === 1 ? " process" : " processes"));
                            return base + (dati.inPausa ? (attivita.it ? "  ·  in pausa" : "  ·  paused") : "");
                        }
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }
          }
        }
    }

    // ── Una pastiglia: scelta, comando o uscita ──────────────────────────
    component Pastiglia: Rectangle {
        id: pas
        property string testo: ""
        property bool scelta: false
        property color tinta: Theme.Colors.accent
        signal premuta()

        width: pasTesto.implicitWidth + Theme.Effects.space4
        height: 30
        radius: height / 2
        color: pas.scelta ? Qt.alpha(pas.tinta, 0.20)
             : pasMouse.containsMouse ? Theme.Colors.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        Text {
            id: pasTesto
            anchors.centerIn: parent
            text: pas.testo
            color: pas.scelta ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }
        MouseArea {
            id: pasMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pas.premuta()
        }
    }
}
