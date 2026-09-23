import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// ControlPanel — Il centro di controllo: volume, luminosità, connessioni.
//
// L'ordine non è casuale. In alto le due cose che si regolano più spesso e
// che vanno cambiate mentre si guarda altro (volume e luminosità): sono
// cursori, quindi si azzeccano senza precisione. Sotto le connessioni, che si
// toccano di rado ma vanno lette. In fondo le scorciatoie verso i pannelli
// completi, per chi cerca qualcosa che qui non c'è.
//
// Ogni comando ha effetto immediato sul sistema: nessun pulsante «Applica».
Item {
    id: panel

    property var spine: null

    /// Altezza esatta del contenuto: la lingua si ferma qui invece di scendere
    /// fino al massimo dichiarato nel registro.
    // ── L'altezza conta anche i MARGINI, e per un po' non li contava ─────
    //
    // Giacomo, 2 settembre 2026: «controllare perché non si adatta al
    // contenuto la sezione del desktop dedicata alla connessione trasmetti
    // eccetera perché i 3 tasti sotto sono a malapena visibili».
    //
    // Non era l'adattamento a non funzionare: era il conto a essere corto.
    // `stack` è ancorato in cima con `topMargin: space5` e la sua
    // `implicitHeight` è la sola altezza dei figli — non sa niente del margine
    // sopra né dello spazio da lasciare sotto. Il pannello nasceva 40 pixel
    // più basso del suo contenuto, e quei 40 pixel sono l'ultima riga.
    //
    // Gli altri pannelli il conto lo facevano già: `PowerPanel` somma
    // `space5 + space4`, `CalendarPanel` e `WeatherPanel` elencano ogni
    // margine uno per uno. Questo era l'unico rimasto indietro, e si vedeva
    // solo qui perché è l'unico pannello abbastanza pieno da arrivare in
    // fondo.
    readonly property real implicitPanelHeight: stack.implicitHeight
                                                + Theme.Effects.space5
                                                + Theme.Effects.space4

    Core.Exec { id: runner }

    // Staccato: vedi `run()` in shell.qml.
    // ── Gli schermi esterni ──────────────────────────────────────────────
    //
    // Giacomo, 30 agosto 2026: «un trasmetti schermo fisso nella barra dove si
    // regola la luminosità». Sta qui e non nel menù «Condividi» perché sono due
    // domande diverse: là si manda UN file a qualcuno, qui si sceglie dove
    // guardare — accanto al volume e alla luminosità, che sono le altre due
    // cose che riguardano lo schermo e le orecchie.
    //
    // Si chiede all'apertura del pannello e non di continuo: la scoperta
    // costa due secondi di rete, e il demone tiene in caldo l'ultimo elenco
    // per mezzo minuto. Chiederla a ogni fotogramma sarebbe la trappola già
    // pagata altrove — svegliare qualcuno per un dato che non cambia.
    property var schermiTrovati: []

    /// Il nome del televisore a cui si sta trasmettendo, o vuoto.
    property string trasmissioneVerso: ""

    /// Vero mentre quello che sta andando in onda è lo SCHERMO e non un file.
    property bool trasmissioneSpecchio: false

    /// Vero da quando qualcuno accende la levetta: fa comparire la scelta del
    /// televisore. Non scrive niente da nessuna parte.
    property bool scegliDove: false

    Connections {
        target: Core.Ipc
        function onTrasmettiStato(st) {
            panel.trasmissioneVerso = st && st.inCorso === true
                                      ? String(st.verso || "") : "";
            panel.trasmissioneSpecchio = st ? st.specchio === true : false;
        }
        function onTrasmettiEsito(e) {
            if (e && e.ok === true && e.verso) {
                panel.trasmissioneVerso = String(e.verso);
                panel.scegliDove = false;
            } else {
                panel.trasmissioneVerso = "";
                panel.trasmissioneSpecchio = false;
                // L'errore non si perde: chi ha appena premuto sta guardando
                // qui, e «non è successo niente» è la risposta peggiore.
                if (e && e.error)
                    panel.motivoFallito = String(e.error);
            }
        }
    }

    // Solo mentre il pannello è aperto: chiedere in continuazione «stai
    // trasmettendo?» a un pannello chiuso è la stessa spesa silenziosa che
    // il calendario evita coi suoi tre numeri.
    Timer {
        interval: 4000
        repeat: true
        running: panel.visible
        triggeredOnStart: true
        onTriggered: Core.Ipc.trasmettiChiediStato()
    }
    property string schermiMotivo: ""
    property bool schermiPronti: false

    /// Perché l'ultima trasmissione non è partita. Vuoto se è andata.
    property string motivoFallito: ""

    // Tutte e due, e non è una ripetizione: `onVisibleChanged` scatta solo al
    // CAMBIO, e questo pannello nasce già visibile perché lo costruisce un
    // `Loader` quando lo si apre. Con il solo primo gestore la domanda non
    // partiva mai, e la casella diceva «nessuno schermo» anche con due
    // televisori accesi — visto il 30 agosto 2026, guardando.
    Component.onCompleted: Core.Ipc.condivisioneDove()
    onVisibleChanged: if (visible) Core.Ipc.condivisioneDove()

    Connections {
        target: Core.Ipc
        function onCondivisioneDoveRicevute(dati) {
            var d = (dati && dati.destinazioni) || [];
            for (var i = 0; i < d.length; i++) {
                if (d[i].id !== "schermo")
                    continue;
                panel.schermiTrovati = d[i].dispositivi || [];
                panel.schermiMotivo = String(d[i].motivo || "");
                panel.schermiPronti = d[i].disponibile === true;
                return;
            }
        }
    }

    function launch(argv) {
        if (argv && argv.length > 0)
            Quickshell.execDetached(argv);
        if (panel.spine)
            panel.spine.close();
    }

    Column {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space5
        spacing: Theme.Effects.space3

        // ── Cosa sta suonando ────────────────────────────────────────────
        //
        // Sopra ai cursori, e solo quando c'è qualcosa: è la riga che si
        // cerca per prima quando c'è musica, e non deve esserci quando non
        // c'è. Il riquadro si annulla da solo (`implicitHeight: 0`), quindi
        // la `Column` non lascia il vuoto al suo posto.
        Ui.MediaCard {
            width: parent.width
        }

        // ── Volume ───────────────────────────────────────────────────────
        Ui.Slider {
            width: parent.width
            icon: Core.SystemState.muted || Core.SystemState.volume === 0
                  ? "muted" : "volume"
            value: Core.SystemState.volume
            accent: Core.SystemState.muted ? Theme.Colors.textFaint : Theme.Colors.accent
            onMoved: function(v) { Core.SystemState.setVolume(v); }
        }

        // ── Luminosità: solo se lo schermo la supporta ────────────────────
        Ui.Slider {
            width: parent.width
            visible: Core.SystemState.hasBrightness
            icon: "sun"
            from: 1
            value: Core.SystemState.brightness
            accent: Theme.Colors.warning
            onMoved: function(v) { Core.SystemState.setBrightness(v); }
        }

        Item { width: 1; height: Theme.Effects.space1 }

        // ── Connessioni ──────────────────────────────────────────────────
        Grid {
            width: parent.width
            columns: 2
            columnSpacing: Theme.Effects.space2
            rowSpacing: Theme.Effects.space2

            readonly property real cell: (width - columnSpacing) / 2

            // ── L'interruttore comanda la RADIO, e mostra la radio ──────────
            //
            // Guardava `networkConnected`, cioè «c'è una connessione». Ma il
            // tasto non accende una connessione: accende il Wi-Fi. Col cavo
            // attaccato risultava acceso a radio spenta, e con la radio accesa
            // ma nessuna rete agganciata risultava spento — così premerlo la
            // spegneva invece di accenderla. La riga sotto, il DETTAGLIO,
            // continua giustamente a raccontare la connessione: è lì che serve
            // sapere a che cosa si è attaccati.
            Ui.ToggleTile {
                width: parent.cell
                icon: Core.SystemState.networkWired ? "globe" : "wifi"
                label: Core.Strings.lang === "it" ? "Wi-Fi" : "Wi-Fi"
                detail: Core.SystemState.networkConnected
                        ? Core.SystemState.networkName
                        : (Core.SystemState.wifiOn
                           ? (Core.Strings.lang === "it" ? "Nessuna rete" : "No network")
                           : (Core.Strings.lang === "it" ? "Spento" : "Off"))
                checked: Core.SystemState.wifiOn
                onToggled: function(v) { Core.SystemState.setWifi(v); }
            }

            Ui.ToggleTile {
                width: parent.cell
                icon: "bluetooth"
                label: "Bluetooth"
                // Se la radio è bloccata da `rfkill` lo si dice qui: senza,
                // l'interruttore scatta, non succede niente, e torna indietro
                // da solo un secondo dopo senza spiegare perché.
                detail: Core.SystemState.bluetoothBlock === "hard"
                        ? (Core.Strings.lang === "it" ? "Interruttore fisico" : "Physical switch")
                        : Core.SystemState.bluetoothDevice !== ""
                        ? Core.SystemState.bluetoothDevice
                        : (Core.SystemState.bluetoothOn
                           ? (Core.Strings.lang === "it" ? "Acceso" : "On")
                           : (Core.Strings.lang === "it" ? "Spento" : "Off"))
                checked: Core.SystemState.bluetoothOn
                onToggled: function(v) { Core.SystemState.setBluetooth(v); }
            }

            Ui.ToggleTile {
                width: parent.cell
                icon: "moon"
                label: Core.Strings.lang === "it" ? "Non disturbare" : "Do not disturb"
                spiegazione: Core.Strings.lang === "it" ? "Silenzia le notifiche"
                                                        : "Silence notifications"
                checked: Core.Notifications.doNotDisturb
                // Si scrive nell'impostazione, non nel singleton: la shell
                // tiene il singleton legato all'impostazione, e così lo stato
                // sopravvive al riavvio della shell.
                onToggled: function(v) { Core.Ipc.setSetting("notifications.doNotDisturb", v); }
            }

            // ── Luce notturna ────────────────────────────────────────────
            //
            // Sta qui e non solo nelle Impostazioni perché è una cosa che si
            // accende quando cala il sole e si spegne quando si guarda una
            // foto: due volte al giorno, e ogni volta si vuole un clic, non
            // una finestra da aprire.
            Ui.ToggleTile {
                width: parent.cell
                icon: "sun"
                label: Core.Strings.lang === "it" ? "Luce notturna" : "Night light"
                // Corta apposta: la piastrella è larga una ventina di
                // caratteri, e «Toglie il blu dallo schermo» ci finiva tagliato
                // a «…dallo sch…». Una frase troncata dice meno di una corta
                // che ci sta — e questa dice la stessa cosa.
                spiegazione: Core.Strings.lang === "it" ? "Toglie il blu"
                                                        : "Takes the blue out"
                checked: Core.Ipc.get("display.nightLight", false)
                onToggled: function(v) { Core.Ipc.setSetting("display.nightLight", v); }
            }

            // ── Modalità gioco ───────────────────────────────────────────
            //
            // Si accende da sola quando qualcosa va a schermo intero: questa
            // levetta serve a chi la vuole ANCHE senza schermo intero — un
            // gioco in finestra, una videochiamata lunga — e a chi vuole
            // vedere che c'è.
            Ui.ToggleTile {
                width: parent.cell
                icon: "play"
                label: Core.Strings.lang === "it" ? "Modalità gioco" : "Game mode"
                // «Accesa da sola» è un fatto — la modalità si è accesa senza
                // che tu l'abbia chiesta — e va detto sempre. Che cosa faccia
                // la modalità è invece una spiegazione, e sta sotto solo per
                // chi la vuole.
                detail: Core.Gioco.attiva && !Core.Gioco.forzato
                        ? (Core.Strings.lang === "it" ? "Accesa da sola" : "On by itself")
                        : ""
                spiegazione: Core.Strings.lang === "it" ? "Niente interruzioni"
                                                        : "No interruptions"
                checked: Core.Gioco.attiva
                onToggled: function(v) { Core.Gioco.forzato = v; }
            }

            // ── Trasmetti a schermo ──────────────────────────────────────
            //
            // Spenta finché il motore non c'è, e con dentro **i nomi veri dei
            // televisori trovati**: «Cucina e TV cameretta». Una voce che
            // dice cosa ha trovato e cosa non sa ancora fare è la verità; una
            // voce che manca sembra un difetto, e una che si accende senza
            // funzionare è peggio di tutte e due.
            Ui.ToggleTile {
                width: parent.cell
                icon: "screen"
                // ── Sempre premibile mentre sta trasmettendo ──────────
                //
                // Era `enabled: panel.schermiPronti` e basta, cioè: la
                // piastrella si accende solo quando la ricerca dei televisori
                // è arrivata. Ma la ricerca ricomincia da capo ogni volta che
                // si apre il pannello, e nei suoi due secondi la piastrella è
                // **spenta** — anche se una trasmissione è in corso.
                //
                // Il risultato è il difetto peggiore che potesse avere: si
                // riesce a far partire lo schermo sulla TV e poi **non si
                // riesce a fermarlo**, perché il solo comando che lo ferma è
                // grigio. Visto il 4 settembre 2026, provando a spegnere una
                // trasmissione vera verso la cucina.
                enabled: panel.schermiPronti || panel.trasmissioneVerso !== ""
                label: Core.Strings.lang === "it" ? "Trasmetti" : "Cast"
                // Solo i NOMI, e non anche il motivo: la riga del dettaglio
                // è larga una ventina di caratteri, e «Trovato: Cucina — non
                // ancora» ci finiva tagliata a metà — visto guardando, il 30
                // agosto 2026. I nomi sono l'informazione che serve qui; il
                // perché per esteso sta nel menù «Condividi», che ha lo spazio
                // per una frase intera.
                detail: {
                    // Mentre sta andando, il dettaglio dice DOVE: è
                    // l'informazione che serve, e le altre non contano più.
                    if (panel.trasmissioneVerso !== "")
                        return (Core.Strings.lang === "it"
                                ? (panel.trasmissioneSpecchio ? "Schermo su "
                                                              : "Sto mandando a ")
                                : (panel.trasmissioneSpecchio ? "Screen on "
                                                              : "Sending to "))
                               + panel.trasmissioneVerso;
                    if (panel.schermiTrovati.length === 0)
                        return Core.Strings.lang === "it"
                               ? "Nessuno schermo in rete" : "No screen found";
                    var nomi = [];
                    for (var i = 0; i < panel.schermiTrovati.length; i++)
                        nomi.push(String(panel.schermiTrovati[i].nome));
                    return nomi.join(", ");
                }
                checked: panel.trasmissioneVerso !== ""
                // ── Da qui si trasmette lo SCHERMO ──────────────────────
                //
                // Fino al 3 settembre 2026 questa levetta poteva solo fermare:
                // un televisore non riceve «lo schermo», riceve un indirizzo e
                // si va a prendere una cosa — e quella cosa non c'era. Adesso
                // c'è: `minerva-cattura` legge lo schermo, la GPU lo comprime
                // in H.264, e ne esce un flusso HLS che il televisore si viene
                // a prendere.
                //
                // Un FILE si manda da un'altra parte, ed è giusto così: dal
                // menù del tasto destro, nel gestore file o in Anteprima, dove
                // si sa quale file.
                //
                // ── E le prove si fanno SOLO verso «Cucina» ─────────────
                //
                // Giacomo, 2 settembre 2026: «se devi fare prove sulla
                // funzione trasmetti falle verso cucina perché i bimbi
                // dormono». Gli altri apparecchi stanno in stanze dove dorme
                // qualcuno. La prova non sceglie da sé e non prende «il primo
                // trovato»: se «Cucina» non c'è, si salta.
                onToggled: function(v) {
                    if (!v) {
                        Core.Ipc.trasmettiFerma();
                        panel.scegliDove = false;
                        return;
                    }
                    panel.motivoFallito = "";
                    // Un solo televisore: non c'è niente da scegliere, e
                    // chiederlo lo stesso sarebbe una domanda per finta.
                    if (panel.schermiTrovati.length === 1) {
                        Core.Ipc.trasmettiSchermo(
                            String(panel.schermiTrovati[0].id), "");
                        return;
                    }
                    panel.scegliDove = true;
                }
            }

            Ui.ToggleTile {
                width: parent.cell
                icon: "sliders"
                label: Core.Strings.lang === "it" ? "Animazioni" : "Animations"
                spiegazione: Core.Strings.lang === "it" ? "Effetti delle finestre"
                                                        : "Window effects"
                checked: Core.Ipc.get("desktop.animations", true)
                // `runner` non esisteva. Non era un refuso innocuo: la levetta
                // scattava, l'impostazione veniva scritta, e alla riga dopo
                // saltava fuori «ReferenceError: runner is not defined» —
                // quindi Hyprland non riceveva niente e le animazioni
                // restavano com'erano. L'errore finiva nel registro della
                // shell, dove nessuno lo guarda: da fuori sembrava soltanto
                // che l'interruttore non servisse a niente.
                onToggled: function(v) {
                    Core.Ipc.setSetting("desktop.animations", v);
                    Core.Compositore.animazioni(v);
                }
            }
        }

        // ── Dove mandarlo ────────────────────────────────────────────
        //
        // La scelta resta a schermo invece di passare come un avviso: chi ha
        // appena premuto «Trasmetti» sta guardando proprio qui.
        Column {
            width: parent.width
            spacing: Theme.Effects.space1
            visible: panel.scegliDove && panel.trasmissioneVerso === ""

            Text {
                width: parent.width
                text: Core.Strings.lang === "it"
                      ? "Manda lo schermo a:" : "Send the screen to:"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            Repeater {
                model: panel.schermiTrovati
                Ui.RigaScelta {
                    width: parent.width
                    icona: "screen"
                    testo: String(modelData.nome)
                    onScelto: {
                        panel.motivoFallito = "";
                        Core.Ipc.trasmettiSchermo(String(modelData.id), "");
                    }
                }
            }

            // ── I tre secondi, detti PRIMA ──────────────────────────────
            //
            // È come è fatto HLS: il televisore si viene a prendere pezzetti
            // da un secondo, e prima di cominciare ne vuole qualcuno in mano.
            // Non è un difetto da riparare, ed è il tipo di cosa che va detta
            // prima invece di lasciarla scoprire davanti alla TV.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: Core.Strings.lang === "it"
                    ? "Ci sono circa tre secondi di ritardo: per guardare va "
                      + "bene, per lavorare sullo schermo grande no. Per "
                      + "mandare una sola fotografia o un video, tasto destro "
                      + "sul file, «Trasmetti a…»."
                    : "There is about a three-second delay: fine for watching, "
                      + "not for working on the big screen. To send a single "
                      + "photo or video, right-click the file, «Cast to…»."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        // Perché non è partita. Senza questa riga un errore di rete diventa
        // «ho premuto e non è successo niente», che è il modo peggiore di
        // fallire.
        Text {
            width: parent.width
            visible: panel.motivoFallito !== ""
                     && panel.trasmissioneVerso === ""
            wrapMode: Text.WordWrap
            text: panel.motivoFallito
            color: Theme.Colors.warning
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }

        Item { width: 1; height: Theme.Effects.space1 }

        // ── Scorciatoie ai pannelli completi ─────────────────────────────
        Row {
            id: quickLinks
            width: parent.width
            spacing: Theme.Effects.space2

            readonly property real cell: (width - spacing * 2) / 3

            Repeater {
                model: [
                    { "id": "settings",   "icon": "settings", "label": Core.Strings.t("settings") },
                    { "id": "cheatsheet", "icon": "keyboard", "label": Core.Strings.t("shortcuts") },
                    { "id": "system",     "icon": "cpu",
                      "label": Core.Strings.lang === "it" ? "Sistema" : "System" }
                ]

                delegate: Rectangle {
                    id: link
                    required property var modelData

                    width: quickLinks.cell
                    height: 44
                    radius: Theme.Effects.radiusSM
                    color: linkMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.Effects.space2

                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 17; height: 17
                            name: link.modelData.icon
                            color: linkMouse.containsMouse ? Theme.Colors.accent
                                                           : Theme.Colors.textMuted
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: link.modelData.label
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightMedium
                        }
                    }

                    MouseArea {
                        id: linkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Tutti e tre sono roba nostra, e li apre la Spine
                        // che li conosce.
                        //
                        // «Sistema» lanciava `systemsettings`, cioè il pannello
                        // di controllo di KDE: una finestra di un'altra
                        // scrivania, con un altro carattere e altre parole, in
                        // mezzo alla nostra. Apre il gestore attività di
                        // Minerva, che è quello che l'icona (una CPU) ha sempre
                        // promesso.
                        onClicked: {
                            if (!panel.spine)
                                return;
                            panel.spine.close();
                            if (link.modelData.id === "settings")
                                panel.spine.settingsRequested();
                            else if (link.modelData.id === "system")
                                panel.spine.monitorRequested();
                            else
                                panel.spine.cheatsheetRequested();
                        }
                    }
                }
            }
        }
    }
}
