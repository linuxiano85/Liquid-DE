import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// System — Le impostazioni di Minerva e del sistema.
//
// È una finestra vera, non una sovrapposizione. Le impostazioni si tengono
// aperte accanto a ciò che si sta regolando: si sposta un cursore, si guarda
// cosa succede, si aggiusta. Un pannello che copre tutto costringe a chiudere
// e riaprire a ogni tentativo.
//
// Ogni comando ha effetto immediato. Nessun pulsante «Applica»: se una cosa
// non piace si rimette com'era, ed è più veloce che leggere un dialogo di
// conferma. Le scelte finiscono in ~/.config/hypr/minerva-user.conf, che
// appartiene a chi usa il computer e sopravvive agli aggiornamenti di Minerva.
FloatingWindow {
    id: settings

    // Non ci si mostra col tema di fabbrica.
    //
    // I colori arrivano dal demone. Finché non sono arrivati, il tema è quello
    // di ripiego (`notte`, ciano): chi ne ha scelto un altro vedeva la
    // finestra aprirsi del colore sbagliato e poi scattare. Misurato, le
    // impostazioni vincevano la corsa per SEDICI MILLISECONDI — un fotogramma,
    // cioè per caso. All'accesso, con più finestre insieme e il demone che sta
    // ancora partendo, quel margine non c'è.
    //
    // `Core.Ipc.prontoADipingere` scade da solo dopo un quarto di secondo, così
    // un demone spento non lascia senza finestra: vedi `core/Ipc.qml`.
    visible: Core.Ipc.prontoADipingere && !settings.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    //
    // Vera quando il programma c'è ma non si deve vedere: è così che una app
    // «tenuta pronta» aspetta di essere richiamata senza pagare i 516 ms di
    // ricostruzione. La decisione sta tutta in `core/TenutaPronta.qml`, qui
    // c'è solo l'interruttore della luce.
    property bool dormiente: false

    title: "Minerva · " + Core.Strings.t("settings")
    implicitWidth: 940
    implicitHeight: 660
    // ── Il colore lo mette la FINESTRA, e costa quindici megabyte di meno ─
    //
    // Il 2 settembre 2026 qui c'era `color: "transparent"` più un
    // `Ui.FondoFinestra` — un rettangolo a tutta finestra col raggio — per
    // arrotondare gli angoli, che Giacomo aveva chiesto.
    //
    // Funzionava, e si è visto nelle fotografie. Costava però **quindici
    // megabyte per applicazione**, misurati: 55 MB senza, 69-72 con. Provato
    // in quattro modi per isolarne la causa — raggio zero, finestra opaca,
    // senza `z: -1` — e il conto non cambiava: in Qt Quick col renderer
    // software un rettangolo grande quanto la finestra costa così, comunque
    // lo si scriva.
    //
    // Su una scrivania che pesa 430 MB, quindici per applicazione non è un
    // prezzo che si paga per un angolo tondo. Gli angoli si faranno nel
    // COMPOSITORE, dove costano una volta sola e valgono anche per i
    // programmi degli altri — che è poi dove deve stare anche il «corpo
    // unico» fra barra e finestra.
    // ── Ridipingere tutto, ogni tanto, apposta ───────────────────────────
    //
    // Col renderer software Qt ridipinge solo quello che dichiara sporco. Chi
    // sbaglia a dichiararlo lascia i propri pixel sul posto, e li' restano:
    // e' la famiglia dei «+» delle icone, ed e' quella dei residui che
    // Giacomo ha visto il 5 settembre 2026 («e' pieno di artefatti»).
    //
    // Le cause trovate una per una — misure animate a virgola in quattro
    // punti — sono state riparate. Ma tolte quelle il difetto compariva
    // ancora, e solo al PRIMO avvio dopo una modifica: cioe' quando la
    // macchina e' carica e qualche fotogramma salta. Non e' un pezzo
    // sbagliato: e' il modo in cui Qt tiene il conto dello sporco, e non e'
    // nostro.
    //
    // Allora si toglie l'occasione: si ridipinge la finestra da cima a fondo,
    // apposta, nei momenti in cui le scie si depositano. Come si fa senza che
    // si veda niente sta scritto sotto «Il pennello».
    //
    // Si ridipinge in tre momenti, e ognuno ha alle spalle il suo difetto:
    //
    //  · al cambio di SEZIONE — i residui trovati la mattina del 5 settembre;
    //  · quando cambia un'IMPOSTAZIONE — i «+» che tornavano passando alle
    //    icone classiche: cambiare set di icone non cambia sezione, quindi
    //    non ridipingeva niente e i residui restavano;
    //  · mentre si SCORRE — le scie verticali che Giacomo ha riconosciuto per
    //    primo («l'errore si trova sempre in verticale, e sempre sulla parte
    //    dove c'e' l'effetto glass»): una `Shape` dipinge fuori dal ritaglio
    //    del `Flickable`, e sopra l'intestazione ogni fotogramma ne lascia
    //    una copia. Il perche' per esteso sta in `sections/Page.qml`.
    color: Theme.Colors.window

    /// Si alterna a ogni scatto del pittore, qui sotto. Non e' un colore:
    /// e' il segnale che dice al rettangolo del fondo di cambiare, e quindi
    /// a Qt che c'e' da ridisegnare.
    property bool _altraTinta: false

    /// Ridipingi tutto — non una volta, ma per un terzo di secondo.
    ///
    /// ── Perche' non basta una volta sola ─────────────────────────────────
    ///
    /// Giacomo, 5 settembre 2026: «appena cliccato su classiche sono
    /// ricomparse». Un solo ridisegno chiesto con `Qt.callLater` arriva
    /// PRIMA che la pagina abbia finito di ridisporsi: si ridipinge, e un
    /// istante dopo la riga che si sposta deposita la sua scia. Ridipingere
    /// prima del difetto non serve a niente.
    ///
    /// Quindi si ridipinge per una ventina di fotogrammi. Mentre si scorre i
    /// richiami si accavallano e il conto riparte, cioe' si ridipinge per
    /// tutta la durata dello scorrimento e per un terzo di secondo dopo —
    /// che e' quanto basta perche' tutto si sia fermato.
    ///
    /// E c'e' un secondo motivo, meno ovvio: alternare fra DUE tinte puo'
    /// annullarsi. Se il richiamo arriva due volte fra un disegno e l'altro,
    /// il colore torna quello di prima, il legame non cambia e non si
    /// ridipinge niente. Con venti scatti il caso non si pone.
    function ridipingiTutto() {
        pittore.restanti = 20;
        pittore.start();
    }

    Timer {
        id: pittore
        interval: 16
        repeat: true
        property int restanti: 0
        onTriggered: {
            settings._altraTinta = !settings._altraTinta;
            if (--pittore.restanti <= 0)
                pittore.stop();
        }
    }

    // ── Il pennello ──────────────────────────────────────────────────────
    //
    // Cambiare il COLORE DELLA FINESTRA non bastava: misurato, ridipingeva
    // il 3,8 % della fascia in cima e lasciava le scie dov'erano. Il colore
    // della finestra e' il fondo, e il fondo non e' un oggetto della scena.
    //
    // Questo invece lo e': un rettangolo grande quanto la finestra, sotto
    // tutto, che cambia di un livello su 255. Cambiando, dichiara sporca la
    // propria area — cioe' tutta la finestra — e Qt e' costretto a
    // ridisegnare ogni cosa che ci sta sopra. Le scie non sono oggetti di
    // nessuno: nessuno le ridisegna, e spariscono.
    //
    // Due neri quasi trasparenti (1 e 2 su 255) invece di uno trasparente e
    // basta: un rettangolo davvero trasparente Qt lo salta, e saltandolo non
    // sporca niente.
    Rectangle {
        anchors.fill: parent
        z: -1
        color: settings._altraTinta ? Qt.rgba(0, 0, 0, 1 / 255)
                                    : Qt.rgba(0, 0, 0, 2 / 255)
    }

    // ── Il pennello lungo serve alle ICONE, non a ogni manopola ──────────
    //
    // Qui c'era `ridipingiTutto` a ogni `settings_changed`, cioe' venti
    // ridisegni pieni della finestra — un terzo di secondo di lavoro col
    // renderer software — ogni volta che si tocca un cursore. Misurato il 9
    // settembre 2026: **0,12 secondi di processore per ogni scatto di
    // manopola**, e col blur acceso ogni fotogramma se lo ripaga anche il
    // compositore.
    //
    // Venti fotogrammi servono al caso per cui il pennello e' nato: cambiare
    // set di icone rifa' la disposizione di tutta la pagina, e le scie si
    // depositano MENTRE le righe si spostano — ridipingere prima non serve a
    // niente (Giacomo, 5 settembre: «appena cliccato su classiche sono
    // ricomparse»). Girare un cursore non sposta niente: li' basta una
    // pennellata sola.
    property string _firmaIcone: ""

    function _pennellataSola() {
        settings._altraTinta = !settings._altraTinta;
    }

    Connections {
        target: Core.Ipc
        function onSettingsChanged() {
            var firma = String(Core.Ipc.get("icons.style", ""))
                        + "|" + String(Core.Ipc.get("icons.theme", ""));
            if (firma !== settings._firmaIcone) {
                settings._firmaIcone = firma;
                Qt.callLater(settings.ridipingiTutto);
            } else {
                Qt.callLater(settings._pennellataSola);
            }
        }
    }

    signal requestClose()
    onClosed: settings.requestClose()

    /// Sezione da mostrare all'apertura. La shell la usa per portare l'utente
    /// direttamente dove ha chiesto di andare (per esempio agli sfondi dal
    /// menu della scrivania).
    property string section: "appearance"

    // Il gruppo che contiene la pagina aperta si apre da sé: riaprendo le
    // Impostazioni si riprende da dove si era, e la voce corrente deve
    // vedersi senza andarla a cercare dentro un gruppo chiuso.
    onSectionChanged: {
        settings.apriGruppoDi(settings.section);
        // Dopo che la pagina nuova si e' disposta, non prima: ridipingere la
        // finestra vecchia non cancella i residui di quella nuova.
        Qt.callLater(settings.ridipingiTutto);
    }

    readonly property bool it: Core.Strings.lang === "it"

    // ── Il demone c'è? ───────────────────────────────────────────────────
    //
    // Non basta `Core.Ipc.connected`: all'apertura è falso per il tempo che
    // la connessione impiega a salire, e una fascia rossa che lampeggia a
    // ogni avvio sarebbe un difetto suo. Si aspetta qualche secondo prima di
    // dire che manca; a ricomparire invece si è immediati, perché una buona
    // notizia si può dare subito.
    property bool senzaDemone: false

    Timer {
        id: pazienza
        interval: 4000
        onTriggered: settings.senzaDemone = !Core.Ipc.connected
    }

    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (Core.Ipc.connected) {
                pazienza.stop();
                settings.senzaDemone = false;
            } else {
                pazienza.restart();
            }
        }
    }

    Component.onCompleted: {
        // Uno solo: due `Component.onCompleted` sullo stesso oggetto non sono
        // due gestori, sono il secondo che cancella il primo — in silenzio.
        if (!Core.Ipc.connected)
            pazienza.restart();
        settings.apriGruppoDi(settings.section);
    }

    // ── Le PAGINE che esistono ───────────────────────────────────────────
    //
    // Questo elenco dice quali pagine ci sono, non come si presentano: il
    // raggruppamento sta in `gruppi`, più sotto. Tenerli separati serve a due
    // cose — la prova che allinea elenco, `switch` e `qmldir` continua a
    // leggere di qui, e riordinare la colonna non tocca mai le pagine.
    //
    // `cerca` è quello che la pagina CONTIENE, non come si chiama. È la
    // differenza fra una ricerca che serve e una che chiede di indovinare il
    // nome giusto: chi cerca «luce notturna» non sa che sta dentro «Schermo».
    readonly property var sections: [
        // Personalizzazione in quattro pagine, dal 28 settembre 2026: erano
        // sei (Aspetto, Scrivania, Stile, La Riva, Dock e barra, Effetti e
        // animazioni) e si pestavano i piedi — lo sfondo in Aspetto, le
        // animazioni in due posti, le finestre in tre. Giacomo: «è diventato
        // tutto troppo confusionario e servirebbe riorganizzare tutto in
        // maniera più semplice e compatta». I nomi vecchi si traducono in
        // `sezioneNuova`, così un'ultima sezione ricordata o uno script che
        // apre «riva» arrivano nel posto giusto.
        { "id": "appearance", "icon": "image",     "it": "Aspetto",       "en": "Appearance",
          "cerca": "tema chiaro scuro colore accento colori tinta icone stile preset mac windows minerva libero animazioni velocità movimento theme accent style motion" },
        { "id": "scrivania",  "icon": "home",      "it": "Scrivania",     "en": "Desktop",
          "cerca": "sfondo wallpaper immagine cartella icone scrivania griglia widget processore memoria gpu temperatura rete orologio blocca pulita desktop" },
        { "id": "finestre",   "icon": "window",    "it": "Finestre",      "en": "Windows",
          "cerca": "finestre barra del titolo pulsanti chiudi riduci ingrandisci effetto vetro acquerello trasparenza mercurio cornice anello elasticità wobbly rigidità smorzamento windows" },
        { "id": "dock",       "icon": "dock",      "it": "Barra e dock", "en": "Bar & dock",
          "cerca": "barra dock posizione alto basso nascondi elude ingrandimento etichette riva angoli bordi isola molla appunti stanze cassetto consenso super menu applicazioni categorie taskbar" },
        { "id": "display",    "icon": "screen",    "it": "Schermo",       "en": "Display",
          "cerca": "risoluzione frequenza scala rotazione monitor hdmi estendi solo notebook disposizione luce notturna night light" },
        { "id": "notifiche",  "icon": "bell",      "it": "Notifiche",     "en": "Notifications",
          "cerca": "notifiche non disturbare silenzio schermata blocco privacy email nascondi contenuto" },
        { "id": "power",      "icon": "battery",   "it": "Alimentazione", "en": "Power",
          "cerca": "batteria energia sospensione coperchio spegnimento blocco inattività" },
        { "id": "audio",      "icon": "volume",    "it": "Audio",         "en": "Sound",
          "cerca": "volume altoparlanti microfono uscita ingresso suoni hdmi displayport profilo" },
        { "id": "network",    "icon": "wifi",      "it": "Rete",          "en": "Network",
          "cerca": "wifi rete cavo ethernet password connessione" },
        { "id": "bluetooth",  "icon": "bluetooth", "it": "Bluetooth",     "en": "Bluetooth",
          "cerca": "bluetooth accoppiamento cuffie dispositivi" },
        { "id": "controller", "icon": "gamepad",   "it": "Controller",    "en": "Game controllers",
          "cerca": "controller pad joystick gamepad giochi dualshock dualsense xbox playstation steam input inputplumber" },
        { "id": "input",      "icon": "keyboard",  "it": "Tastiera e mouse", "en": "Keyboard & mouse",
          "cerca": "tastiera disposizione layout mouse touchpad sensibilità ripetizione tap puntatore cursore grandezza dimensione" },
        { "id": "dataora",    "icon": "clock",     "it": "Data, ora e lingua", "en": "Date, time & language",
          "cerca": "ora data fuso orario orologio 24 meteo luogo lingua italiano inglese regione formato" },
        { "id": "accesso-facile", "icon": "accessibilita", "it": "Accessibilità", "en": "Accessibility",
          "cerca": "accessibilità testo grande lente puntatore contrasto" },
        { "id": "defaults",   "icon": "apps",      "it": "App predefinite", "en": "Default apps",
          "cerca": "predefinite apri con browser terminale posta associazioni" },
        { "id": "avvio",      "icon": "restart",   "it": "Avvio",         "en": "Startup",
          "cerca": "avvio autostart programmi tenute pronte" },
        { "id": "account",    "icon": "cloud",     "it": "Account online", "en": "Online accounts",
          "cerca": "account google kdrive nuvola sincronizzazione" },
        { "id": "utente",     "icon": "star",      "it": "Utente",        "en": "User",
          "cerca": "utente nome foto ritratto password" },
        { "id": "accesso",    "icon": "lock",      "it": "Accesso",       "en": "Login",
          "cerca": "accesso login greeter sfondo aurora automatico" },
        { "id": "shell",      "icon": "settings",  "it": "Minerva",       "en": "Minerva",
          "cerca": "aiuto scorciatoie promemoria ripristino valori di fabbrica" }
    ]

    // ── Come si presentano ───────────────────────────────────────────────
    //
    // Diciannove voci in un elenco piatto sono un elenco che si scorre, non
    // che si legge. Giacomo, 4 settembre 2026: «completare il pannello
    // impostazioni facendo una sezione come cosmic con tutte le sottosezioni
    // divise per parte del desktop».
    //
    // I gruppi con una voce sola non esistono: «Suono» o «Rete» restano voci
    // dirette, come fa COSMIC. Un gruppo che si apre per mostrarti una riga
    // sola è un clic in più che non dà niente.
    readonly property var gruppi: [
        // Sei gruppi, come COSMIC, dal 20 settembre 2026: prima c'erano
        // sette voci dirette in mezzo e la pagina Energia stava da sola.
        { "id": "g-scrivania", "icon": "image", "it": "Personalizzazione", "en": "Personalization",
          "voci": ["appearance", "scrivania", "finestre", "dock"] },
        { "id": "g-dispositivi", "icon": "screen", "it": "Dispositivi", "en": "Devices",
          "voci": ["display", "audio", "input", "bluetooth", "controller"] },
        { "id": "g-connessioni", "icon": "wifi", "it": "Connessioni", "en": "Connections",
          "voci": ["network", "account"] },
        { "id": "g-app", "icon": "apps", "it": "Applicazioni", "en": "Applications",
          "voci": ["defaults", "avvio"] },
        { "id": "g-sistema", "icon": "settings", "it": "Sistema", "en": "System",
          "voci": ["notifiche", "power", "utente", "accesso", "dataora", "shell"] },
        { "id": "accesso-facile" }
    ]

    /// Quello che si sta cercando. Vuoto: si vede la colonna normale.
    property string ricerca: ""

    /// La pagina che corrisponde a un id.
    function paginaPer(id) {
        for (var i = 0; i < settings.sections.length; i++)
            if (settings.sections[i].id === id)
                return settings.sections[i];
        return null;
    }

    /// Le pagine che corrispondono a quello che si cerca. Si guarda il nome
    /// nelle due lingue E le parole chiave: chi cerca «luce notturna» non sa
    /// che sta dentro «Schermo», ed è esattamente per quello che cerca.
    readonly property var trovate: {
        var q = settings.ricerca.trim().toLowerCase();
        if (q === "")
            return [];
        var out = [];
        for (var i = 0; i < settings.sections.length; i++) {
            var s = settings.sections[i];
            var testo = (s.it + " " + s.en + " " + (s.cerca || "")).toLowerCase();
            if (testo.indexOf(q) >= 0)
                out.push(s);
        }
        return out;
    }

    /// I gruppi aperti. Si apre da sé quello che contiene la pagina corrente:
    /// tornando alle Impostazioni si riprende da dove si era, e la voce
    /// aperta deve vedersi senza cercarla.
    property var aperti: ({})

    function apriGruppoDi(id) {
        for (var i = 0; i < settings.gruppi.length; i++) {
            var g = settings.gruppi[i];
            if (g.voci && g.voci.indexOf(id) >= 0) {
                var copia = JSON.parse(JSON.stringify(settings.aperti));
                copia[g.id] = true;
                settings.aperti = copia;
                return;
            }
        }
    }

    // ── La barra del titolo ──────────────────────────────────────────────
    //
    // DENTRO la finestra e non sopra: vedi il perché in cima a
    // `ui/WindowTitleBar.qml`. Una barra disegnata fuori insegue la finestra e
    // arriva sempre in ritardo; una barra che È la finestra non ha niente da
    // inseguire.
    Ui.WindowTitleBar {
        id: titolo
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        label: settings.title
        onCloseRequested: settings.requestClose()
    }

    // ── Colonna delle sezioni ────────────────────────────────────────────

    Rectangle {
        id: sidebar
        anchors.top: titolo.bottom
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        // 248 e non 208: a 208 «Personalizzazione» e «Data, ora e lingua» si
        // leggevano tagliati a metà, con i puntini (28 settembre 2026).
        width: 248
        color: Theme.Colors.membrane

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Theme.Colors.edge
        }

        Text {
            id: sidebarTitle
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space4
            anchors.topMargin: Theme.Effects.space5
            text: Core.Strings.t("settings").toUpperCase()
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightBold
            font.letterSpacing: Theme.Typography.trackingLabel
        }

        // ── La colonna SCORRE ────────────────────────────────────────────
        //
        // Era una `Column` ancorata solo in alto, cioè libera di crescere
        // quanto voleva. Con dodici voci ci stava; alla quattordicesima
        // («Data e ora» e «Lingua e regione») l'ultima è finita sopra la spia
        // del demone, in fondo — due scritte una addosso all'altra, e nessun
        // avviso da nessuna parte, perché in QML nulla vieta a due elementi di
        // sovrapporsi.
        //
        // Adesso il limite è dichiarato: la colonna arriva al massimo fino
        // alla spia, e se le voci non ci stanno si scorre. Aggiungerne
        // un'altra non può più rompere niente.
        // La colonna delle voci scorre da sempre — il commento qui sopra
        // dice perché — ma non si vedeva che si potesse.
        Ui.Scorrimento {
            bersaglio: colonnaVoci
            anchors {
                right: colonnaVoci.right
                top: colonnaVoci.top
                bottom: colonnaVoci.bottom
            }
        }

        Flickable {
            id: colonnaVoci
            anchors.top: sidebarTitle.bottom
            anchors.topMargin: Theme.Effects.space4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: spiaDemone.top
            anchors.bottomMargin: Theme.Effects.space2
            contentHeight: voci.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Anche qui dentro ci sono icone, e anche qui il ritaglio non le
            // trattiene: vedi `sections/Page.qml`.
            onContentYChanged: Qt.callLater(settings.ridipingiTutto)

            Column {
                id: voci
                x: Theme.Effects.space2
                width: colonnaVoci.width - Theme.Effects.space2 * 2
                spacing: 1

                // ── Cercare, invece di ricordarsi dov'è ──────────────────
                //
                // Con diciannove pagine in dieci gruppi, sapere dove sta una
                // cosa è un lavoro. La casella non cerca solo i NOMI delle
                // pagine: cerca quello che contengono (`cerca` nell'elenco
                // qui sopra). Chi cerca «luce notturna» non sa che sta dentro
                // «Schermo», ed è esattamente per quello che cerca.
                Item {
                    width: parent.width
                    height: 34

                    Ui.Campo {
                        anchors.fill: parent
                        segnaposto: Core.Strings.lang === "it" ? "Cerca…" : "Search…"
                        onCambiato: function (t) { settings.ricerca = t; }
                    }
                }

                Item { width: 1; height: Theme.Effects.space2 }

                // ── Quello che si è trovato ─────────────────────────────
                Repeater {
                    model: settings.ricerca.trim() !== "" ? settings.trovate : []
                    delegate: VoceRiga {
                        required property var modelData
                        pagina: modelData
                        width: voci.width
                    }
                }

                Text {
                    width: parent.width
                    visible: settings.ricerca.trim() !== ""
                             && settings.trovate.length === 0
                    text: Core.Strings.lang === "it" ? "  Niente con questo nome."
                                                     : "  Nothing by that name."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // ── La colonna normale, a due livelli ───────────────────
                Repeater {
                    model: settings.ricerca.trim() === "" ? settings.gruppi : []

                    delegate: Column {
                        id: nodo
                        required property var modelData
                        width: voci.width
                        spacing: 1

                        readonly property bool eGruppo:
                            modelData.voci !== undefined
                        readonly property bool aperto:
                            settings.aperti[modelData.id] === true

                        // Una voce diretta: nessun gruppo, nessun clic in più.
                        // Un gruppo che si apre per mostrare una riga sola
                        // sarebbe un clic che non dà niente.
                        VoceRiga {
                            visible: !nodo.eGruppo
                            width: parent.width
                            pagina: nodo.eGruppo ? null
                                                 : settings.paginaPer(nodo.modelData.id)
                        }

                        // La testata di un gruppo.
                        Rectangle {
                            visible: nodo.eGruppo
                            width: parent.width
                            height: 38
                            radius: Theme.Effects.radiusSM
                            color: testaMouse.containsMouse ? Theme.Colors.hover
                                                            : "transparent"
                            Behavior on color {
                                ColorAnimation { duration: Theme.Motion.instant }
                            }

                            Ui.Icon {
                                id: testaIcona
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.Effects.space4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 17; height: 17
                                name: nodo.modelData.icon || "settings"
                                color: Theme.Colors.textFaint
                            }

                            Text {
                                anchors.left: testaIcona.right
                                anchors.leftMargin: Theme.Effects.space3
                                anchors.right: freccia.left
                                anchors.rightMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: Core.Strings.lang === "it"
                                      ? (nodo.modelData.it || "")
                                      : (nodo.modelData.en || "")
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeMD
                                font.weight: Theme.Typography.weightSemiBold
                            }

                            Ui.Icon {
                                id: freccia
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14
                                name: "chevron"
                                color: Theme.Colors.textFaint
                                rotation: nodo.aperto ? 90 : 0
                                Behavior on rotation {
                                    NumberAnimation { duration: Theme.Motion.quick }
                                }
                            }

                            MouseArea {
                                id: testaMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var c = JSON.parse(JSON.stringify(settings.aperti));
                                    c[nodo.modelData.id] = !nodo.aperto;
                                    settings.aperti = c;
                                }
                            }
                        }

                        // Le voci del gruppo, rientrate.
                        Repeater {
                            model: nodo.eGruppo && nodo.aperto
                                   ? nodo.modelData.voci : []
                            delegate: VoceRiga {
                                required property var modelData
                                width: nodo.width
                                rientro: Theme.Effects.space5
                                pagina: settings.paginaPer(modelData)
                            }
                        }
                    }
                }
            }
        }

        // Stato del demone, in fondo: quando è assente metà delle impostazioni
        // non funziona, e vale la pena poterlo vedere invece di dedurlo.
        Row {
            id: spiaDemone
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.Effects.space4
            spacing: Theme.Effects.space2

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7
                radius: 3.5
                color: Core.Ipc.connected ? Theme.Colors.positive : Theme.Colors.danger
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Core.Ipc.connected ? "minervad" : "minervad assente"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }

    // ── Quando il demone non risponde ────────────────────────────────────
    //
    // Ogni comando di questa finestra legge il proprio valore dalle
    // impostazioni, che stanno nel demone. Senza demone `Core.Ipc.get()`
    // restituisce il valore PREDEFINITO — ed è quello che si vedeva: una
    // finestra intera di valori plausibili e tutti falsi.
    //
    // Trovato il 29 luglio provando l'ambiente. Il demone era morto e le
    // Impostazioni dicevano «icone: Minerva» con le icone classiche accese,
    // «barra del titolo: 34 px» con le barre alte 39, «la dock non si
    // nasconde» con la dock che si nascondeva. Ci sono voluti venti minuti
    // per capire che il difetto non era in nessuna delle cose che guardavo.
    //
    // La parte pericolosa non è quello che si legge: è quello che si può
    // scrivere. Toccare un solo cursore in quello stato avrebbe salvato il
    // valore finto sopra a quello vero, e il resto sarebbe rimasto vero —
    // cioè le impostazioni sarebbero diventate un miscuglio, senza che
    // nessuno avesse sbagliato niente.
    //
    // Quindi: lo si dice, e finché dura non si scrive. Il guardiano
    // (`scripts/minerva-demone`) intanto lo sta già rimettendo in piedi, e
    // appena torna questa fascia sparisce da sola.
    Rectangle {
        id: avviso
        anchors.top: titolo.bottom
        anchors.left: sidebar.right
        anchors.right: parent.right
        height: visible ? riga.implicitHeight + Theme.Effects.space4 * 2 : 0
        visible: settings.senzaDemone
        color: Qt.alpha(Theme.Colors.warning, 0.14)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3
            color: Theme.Colors.warning
        }

        Column {
            id: riga
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.Effects.space5
            anchors.rightMargin: Theme.Effects.space4
            spacing: 2

            Text {
                width: parent.width
                text: settings.it ? "Minerva non risponde"
                                  : "Minerva is not responding"
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightSemiBold
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: settings.it
                    ? "Quelli che vedi qui sotto NON sono i tuoi valori: sono "
                      + "quelli di fabbrica. Non si può cambiare niente finché "
                      + "non torna, o si sovrascriverebbero le tue scelte."
                    : "The values below are NOT yours: they are the factory "
                      + "ones. Nothing can be changed until it is back, or "
                      + "your choices would be overwritten."
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Contenuto ────────────────────────────────────────────────────────

    Loader {
        id: page
        anchors.top: avviso.bottom
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        asynchronous: false


        // Niente scritture al buio: vedi la fascia qui sopra. `enabled` a
        // falso ferma ogni clic e ogni trascinamento dentro la pagina, che è
        // esattamente quanto basta — restano leggibili, e si vede che sono
        // spenti.
        enabled: !settings.senzaDemone

        /// Quanto si vede la pagina quando è a posto. Non è un legame diretto
        /// su `opacity` perché quella la muove anche la dissolvenza d'entrata,
        /// e due cose che scrivono la stessa proprietà non possono convivere.
        readonly property real livello: settings.senzaDemone ? 0.45 : 1
        onLivelloChanged: page.opacity = page.livello

        source: {
            switch (settings.section) {
            case "finestre": return "sections/Finestre.qml";
            case "dock":     return "sections/Dock.qml";
            case "display":  return "sections/Display.qml";
            case "scrivania": return "sections/Scrivania.qml";
            case "power":    return "sections/Power.qml";
            case "notifiche": return "sections/Notifiche.qml";
            case "audio":    return "sections/Audio.qml";
            case "network":   return "sections/Network.qml";
            case "bluetooth": return "sections/Bluetooth.qml";
            case "controller": return "sections/Controller.qml";
            case "input":    return "sections/Input.qml";
            case "dataora":  return "sections/DataOra.qml";
            case "accesso-facile": return "sections/Accessibilita.qml";
            case "defaults": return "sections/Defaults.qml";
            case "avvio":    return "sections/Avvio.qml";
            case "account":  return "sections/Account.qml";
            case "utente":   return "sections/Utente.qml";
            case "accesso":  return "sections/Accesso.qml";
            case "shell":    return "sections/Shell.qml";
            default:         return "sections/Appearance.qml";
            }
        }

        // La pagina dice quando si e' mossa, e la finestra si ridipinge:
        // vedi `sections/Page.qml`. `ignoreUnknownSignals` perche' il Loader
        // e' vuoto finche' non carica.
        Connections {
            target: page.item
            ignoreUnknownSignals: true
            function onScorso() { Qt.callLater(settings.ridipingiTutto); }
        }

        // Le sezioni entrano con una dissolvenza breve. Senza, cambiando voce
        // il contenuto salta di colpo e non si capisce che è cambiato lui e
        // non tutta la finestra.
        opacity: 0
        onLoaded: fadeIn.start()
        NumberAnimation {
            id: fadeIn
            target: page
            property: "opacity"
            from: 0; to: page.livello
            duration: Theme.Motion.quick
        }
    }

    // ── Una riga della colonna ───────────────────────────────────────────
    //
    // Era scritta a mano dentro il `Repeater`, e adesso serve in tre posti:
    // le voci dirette, le voci dentro un gruppo (rientrate) e i risultati
    // della ricerca. Tre copie della stessa riga sarebbero tre righe che un
    // giorno si comportano in tre modi.
    component VoceRiga: Rectangle {
        id: riga

        /// La pagina che apre. Nulla: la riga non si vede.
        property var pagina: null
        /// Di quanto rientra: le voci dentro un gruppo stanno più a destra.
        property real rientro: 0

        readonly property bool current:
            riga.pagina !== null && settings.section === riga.pagina.id

        visible: riga.pagina !== null
        height: riga.pagina !== null ? 38 : 0
        radius: Theme.Effects.radiusSM
        color: riga.current ? Qt.alpha(Theme.Colors.accent, 0.16)
             : rigaMouse.containsMouse ? Theme.Colors.hover
             : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        // Barretta di selezione: dice quale sezione è aperta anche a colpo
        // d'occhio, senza leggere.
        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: riga.current ? 20 : 0
            radius: 1.5
            color: Theme.Colors.accent
            // Niente `Behavior` sull'altezza: vedi `ui/Slider.qml`. In piu'
            // `OutBack` sfonda il valore d'arrivo, quindi passava anche per
            // altezze a virgola.
        }

        Ui.Icon {
            id: rigaIcona
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space4 + riga.rientro
            anchors.verticalCenter: parent.verticalCenter
            width: 17; height: 17
            name: riga.pagina ? riga.pagina.icon : ""
            color: riga.current ? Theme.Colors.accent : Theme.Colors.textFaint
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        }

        Text {
            anchors.left: rigaIcona.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: !riga.pagina ? ""
                  : (Core.Strings.lang === "it" ? riga.pagina.it : riga.pagina.en)
            color: riga.current ? Theme.Colors.text : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: riga.current ? Theme.Typography.weightSemiBold
                                      : Theme.Typography.weightMedium
        }

        MouseArea {
            id: rigaMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!riga.pagina)
                    return;
                settings.section = riga.pagina.id;
                // Arrivandoci dalla ricerca, il gruppo che la contiene si
                // apre: chiudendo la ricerca la voce dev'essere lì, non
                // sepolta in un gruppo chiuso.
                settings.apriGruppoDi(riga.pagina.id);
                Qt.callLater(function() { if (page.item && page.item.revealSetting) page.item.revealSetting(settings.ricerca); });
            }
        }
    }
}
