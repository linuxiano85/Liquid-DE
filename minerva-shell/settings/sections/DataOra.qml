import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S
import "../../ui" as Ui

// Data, ora e lingua — il fuso, l'orologio, il luogo del meteo e la lingua.
// Fino al 28 settembre 2026 la lingua era una pagina a sé, «Lingua e
// regione», con una riga sola: riunite, perché è la stessa domanda — «dove e
// come vivo» — e una voce in meno nella colonna.
Page {
    id: page

    readonly property bool it: Core.Strings.lang === "it"
    title: page.it ? "Data, ora e lingua" : "Date, time and language"
    subtitle: page.it ? "Il fuso orario, l'orologio, il luogo del meteo e la lingua"
                      : "Time zone, clock, weather location and language"
    // ── Lo stato che arriva dal demone ───────────────────────────────────
    property string fuso: ""
    property bool ntp: false
    property bool ntpPossibile: false
    property bool sincronizzato: false
    property string errore: ""
    property var fusi: []
    property string esito: ""
    // L'ora da mostrare. Un timer al secondo e non al minuto: qui si sta
    // GUARDANDO l'orologio, ed è l'unico posto in Minerva dove i secondi che
    // scorrono sono l'informazione — servono a vedere che dopo un cambio di
    // fuso l'ora è saltata davvero.
    property date adesso: new Date()
    Timer {
        interval: 1000
        // Solo con le Impostazioni davanti: ridotte o dietro un'altra
        // finestra non c'è nessuno a guardare. Tornandoci si aggiorna
        // subito (`triggeredOnStart`).
        running: Qt.application.state === Qt.ApplicationActive
        triggeredOnStart: true
        repeat: true
        onTriggered: page.adesso = new Date()
    }
    Connections {
        target: Core.Ipc

        function onDatetimeStateReceived(s) {
            page.fuso = s.timezone || "";
            page.ntp = s.ntp === true;
            page.ntpPossibile = s.ntpPossibile === true;
            page.sincronizzato = s.sincronizzato === true;
            page.errore = s.errore || "";
        }

        function onDatetimeZonesReceived(f) { page.fusi = f; }

        function onDatetimeResult(r) {
            // Un annullamento nella finestrella della password arriva qui come
            // errore, ed è giusto che si veda: senza, l'utente preme, non
            // succede niente, e non c'è modo di sapere se ha sbagliato lui.
            page.esito = r.ok === true
                         ? (page.it ? "Fatto." : "Done.")
                         : (r.errore || (page.it ? "Non riuscito." : "Failed."));
            svanisci.restart();
        }

        function onConnectedChanged() { if (Core.Ipc.connected) page.chiedi(); }
    }
    Timer { id: svanisci; interval: 6000; onTriggered: page.esito = "" }
    function chiedi() {
        Core.Ipc.datetimeState();
        if (page.fusi.length === 0)
            Core.Ipc.datetimeZones();
    }
    Component.onCompleted: {
        chiedi();
        // La lingua (fino al 28 settembre 2026 una pagina sua).
        Core.Ipc.localeState();
    }
    // ── Che cosa è successo ─────────────────────────────────────────────
    //
    // In CIMA e non in fondo. L'esito di un comando che passa da polkit — un
    // «Annulla» nella finestrella della password, un permesso negato — è la
    // sola cosa che l'utente deve leggere subito dopo aver premuto. Messo in
    // fondo a una pagina che scorre, comparirebbe fuori dallo schermo.

    Card {
        visible: page.esito !== "" || page.errore !== ""
        heading: page.it ? "Esito" : "Result"

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.errore !== "" ? page.errore : page.esito
            color: page.errore !== "" ? Theme.Colors.danger : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }
    // ── Adesso ───────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Adesso" : "Right now"

        Column {
            width: parent.width
            spacing: 2

            Text {
                text: Qt.formatTime(page.adesso,
                                    page.ore24 ? "HH:mm:ss" : "h:mm:ss AP")
                color: Theme.Colors.text
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXL * 1.6
            }

            Text {
                text: page.adesso.toLocaleDateString(
                          page.it ? Qt.locale("it_IT") : Qt.locale("en_GB"),
                          "dddd d MMMM yyyy")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                visible: page.fuso !== ""
                text: page.fuso.replace(/_/g, " ")
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
    }
    // ── Fuso orario ──────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Fuso orario" : "Time zone"
        note: page.it
              ? "Sono quasi seicento: scrivi il nome della città per trovarlo."
              : "There are almost six hundred: type a city name to find yours."

        CampoTesto {
            id: cerca
            width: parent.width
            segnaposto: page.it ? "Cerca una città o un continente…"
                                : "Search for a city or continent…"
        }

        Rectangle {
            id: riquadro
            width: parent.width
            height: 220
            radius: Theme.Effects.radiusSM
            color: Theme.Colors.sunken
            border.width: Theme.Effects.hairline
            border.color: Theme.Colors.edge
            clip: true

            // Il filtro si rifà quando cambia la ricerca o l'elenco, e non
            // a ogni ridisegno: con seicento voci scorrere la lista a ogni
            // fotogramma si sentirebbe.
            readonly property var visibili: {
                var q = cerca.testo.trim().toLowerCase();
                if (q === "") return page.fusi;
                var out = [];
                for (var i = 0; i < page.fusi.length; i++) {
                    if (page.fusi[i].toLowerCase().replace(/_/g, " ").indexOf(q) >= 0)
                        out.push(page.fusi[i]);
                }
                return out;
            }

            // ── L'elenco si apre DOVE SI È, non all'inizio dell'alfabeto ──
            //
            // Senza questo, la lista partiva da «Africa/Abidjan» e il fuso in
            // uso stava seicento righe più giù: per vedere dov'era impostato
            // il proprio computer bisognava scorrere, o fidarsi. Con la
            // ricerca scritta invece si torna in cima, perché lì la prima
            // riga è il risultato migliore.
            function mostraCorrente() {
                if (cerca.testo.trim() !== "") {
                    elenco.positionViewAtBeginning();
                    return;
                }
                var i = elenco.model ? elenco.model.indexOf(page.fuso) : -1;
                if (i >= 0)
                    elenco.positionViewAtIndex(i, ListView.Center);
            }

            // `Qt.callLater`: chiamato subito, il ListView non ha ancora
            // costruito i delegati del modello nuovo e la posizione finirebbe
            // calcolata su una lista vuota.
            onVisibiliChanged: Qt.callLater(riquadro.mostraCorrente)

            Connections {
                target: page
                function onFusoChanged() { Qt.callLater(riquadro.mostraCorrente) }
            }

            Ui.Scorrimento {
                bersaglio: elenco
                anchors {
                    right: elenco.right
                    top: elenco.top
                    bottom: elenco.bottom
                }
            }

            ListView {
                id: elenco
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: parent.visibili
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property string modelData

                    width: elenco.width
                    height: 30
                    color: modelData === page.fuso ? Theme.Colors.selected
                         : voceMouse.containsMouse ? Theme.Colors.hover
                         : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space3
                        text: parent.modelData.replace(/_/g, " ")
                        color: parent.modelData === page.fuso ? Theme.Colors.accent
                                                              : Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: voceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.datetimeSet("timezone", parent.modelData)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: page.fusi.length === 0
                text: page.it ? "Elenco dei fusi non disponibile"
                              : "Time-zone list unavailable"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }
    // ── Sincronizzazione ─────────────────────────────────────────────────

    Card {
        heading: page.it ? "Ora automatica" : "Automatic time"
        note: page.ntpPossibile
              ? (page.it
                 ? "Con l'ora automatica il computer la chiede a internet e non "
                 + "resta mai indietro. È la scelta giusta per quasi tutti."
                 : "With automatic time the computer asks the internet and never "
                 + "drifts. It is the right choice for almost everyone.")
              : (page.it
                 ? "Su questo sistema non risulta nessun servizio capace di "
                 + "sincronizzare l'ora."
                 : "No time-synchronisation service is available on this system.")

        S.SettingRow {
            width: parent.width
            label: page.it ? "Prendi l'ora da internet" : "Get time from the internet"
            description: !page.ntp
                         ? (page.it ? "Spenta: l'ora la imposti tu"
                                    : "Off: you set the time yourself")
                         : page.sincronizzato
                         ? (page.it ? "Accesa e sincronizzata"
                                    : "On and synchronised")
                         : (page.it ? "Accesa, sincronizzazione in corso"
                                    : "On, synchronising")

            control: S.ToggleSwitch {
                checked: page.ntp
                enabled: page.ntpPossibile
                onToggled: function(v) { Core.Ipc.datetimeSet("ntp", v); }
            }
        }
    }
    // ── Ora a mano, solo quando ha senso ─────────────────────────────────
    //
    // Il riquadro NON compare con la sincronizzazione accesa, e non è per
    // pulizia: con quella accesa `timedatectl set-time` rifiuta il comando.
    // Un campo che accetta di essere riempito e poi non fa niente è peggio di
    // un campo che non c'è.

    Card {
        visible: !page.ntp
        heading: page.it ? "Imposta data e ora a mano" : "Set date and time by hand"

        Row {
            width: parent.width
            spacing: Theme.Effects.space2

            CampoTesto {
                id: campoData
                width: (parent.width - Theme.Effects.space2 * 2 - 110) * 0.5
                segnaposto: "2026-08-10"
            }

            CampoTesto {
                id: campoOra
                width: (parent.width - Theme.Effects.space2 * 2 - 110) * 0.5
                segnaposto: "14:30:00"
            }

            Pulsante {
                width: 110
                testo: page.it ? "Applica" : "Apply"
                attivo: campoData.testo !== "" && campoOra.testo !== ""
                onPremuto: Core.Ipc.datetimeSet(
                               "time", campoData.testo + " " + campoOra.testo)
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.it
                  ? "Data come 2026-08-10, ora come 14:30:00."
                  : "Date as 2026-08-10, time as 14:30:00."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }
    // ── Formato dell'orologio: è nostro, non del sistema ─────────────────

    readonly property bool ore24: Core.Ipc.get("clock.format24", true)
    Card {
        heading: page.it ? "Come si legge l'orologio" : "Clock format"
        note: page.it
              ? "Vale per l'orologio della barra e per la schermata di accesso."
              : "Applies to the bar clock and to the login screen."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Formato dell'ora" : "Time format"
            description: page.it ? "Ventiquattro ore, oppure con AM e PM"
                                 : "Twenty-four hour, or with AM and PM"
            controlWidth: 240

            control: S.ChoicePicker {
                value: page.ore24 ? "24" : "12"
                options: [
                    { "value": "24", "label": page.it ? "24 ore" : "24-hour" },
                    { "value": "12", "label": page.it ? "12 ore" : "12-hour" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("clock.format24", v === "24");
                    // Anche il greeter, che ha una chiave sua: le due
                    // impostazioni erano separate e nessuno se ne accorgeva
                    // finché non si arrivava alla schermata di accesso e
                    // l'ora era scritta nell'altro modo.
                    Core.Ipc.setSetting("greeter.clock24", v === "24");
                }
            }
        }
    }
    // ── Il tempo che fa ──────────────────────────────────────────────────
    //
    // Sta in questa pagina e non in una sua perché è la stessa domanda del
    // fuso orario: **dove sei**. Chi apre «Data, ora e luogo» per correggere
    // il fuso trova lì anche la città del meteo, e non deve cercarla altrove.

    property var luoghiTrovati: []
    property bool cercandoLuogo: false
    Connections {
        target: Core.Ipc
        function onWeatherPlaces(l) {
            page.luoghiTrovati = l;
            page.cercandoLuogo = false;
        }
    }
    Card {
        heading: page.it ? "Il tempo che fa" : "Weather"
        note: page.it
              ? "Con il meteo acceso, Minerva chiede le previsioni a "
              + "open-meteo.com mandando le coordinate della località scelta, "
              + "arrotondate al centesimo di grado — circa un chilometro. "
              + "Non parte nessun nome, nessun account, nessun identificativo "
              + "del computer. Senza una località scelta non parte niente."
              : "With weather on, Minerva asks open-meteo.com for the "
              + "forecast, sending the chosen place's coordinates rounded to "
              + "a hundredth of a degree — about a kilometre. No name, no "
              + "account, no identifier of this computer is sent. With no "
              + "place chosen, nothing is sent at all."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra il meteo nella barra" : "Show weather in the bar"
            description: Core.Ipc.get("weather.name", "") !== ""
                         ? Core.Ipc.get("weather.name", "")
                         : (page.it ? "Scegli prima una località, qui sotto"
                                    : "Choose a place below first")

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("weather.enabled", false)
                onToggled: function(v) { Core.Ipc.setSetting("weather.enabled", v); }
            }
        }

        CampoTesto {
            id: cercaLuogo
            width: parent.width
            segnaposto: page.it ? "Cerca una città…" : "Search for a city…"
            onAccettato: {
                if (cercaLuogo.testo.trim().length >= 2) {
                    page.cercandoLuogo = true;
                    Core.Ipc.weatherSearch(cercaLuogo.testo.trim());
                }
            }
        }

        Text {
            width: parent.width
            visible: page.cercandoLuogo
            text: page.it ? "Cerco…" : "Searching…"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        Column {
            width: parent.width
            spacing: 1
            visible: page.luoghiTrovati.length > 0

            Repeater {
                model: page.luoghiTrovati

                delegate: Rectangle {
                    id: luogo
                    required property var modelData

                    width: parent.width
                    height: 40
                    radius: Theme.Effects.radiusSM
                    color: luogoMouse.containsMouse ? Theme.Colors.hover
                                                    : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space3
                        text: luogo.modelData.nome
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space3
                        text: luogo.modelData.dove
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    MouseArea {
                        id: luogoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Le coordinate si scrivono arrotondate: è tutto
                            // ciò che serve alle previsioni, ed è anche tutto
                            // ciò che poi uscirà da questo computer.
                            Core.Ipc.setSetting("weather.lat",
                                Math.round(luogo.modelData.lat * 100) / 100);
                            Core.Ipc.setSetting("weather.lon",
                                Math.round(luogo.modelData.lon * 100) / 100);
                            Core.Ipc.setSetting("weather.name", luogo.modelData.nome);
                            Core.Ipc.setSetting("weather.enabled", true);
                            page.luoghiTrovati = [];
                            cercaLuogo.testo = "";
                        }
                    }
                }
            }
        }
    }
    // ── Pezzi comuni ─────────────────────────────────────────────────────

    component CampoTesto: Rectangle {
        id: campo

        property alias testo: dentro.text
        property string segnaposto: ""
        signal accettato()

        height: 34
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        border.width: Theme.Effects.hairline
        border.color: dentro.activeFocus ? Theme.Colors.edgeAccent
                                         : Theme.Colors.edge

        TextInput {
            id: dentro
            anchors.fill: parent
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space3
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            selectByMouse: true
            selectionColor: Theme.Colors.selected
            onAccepted: campo.accettato()
        }

        Text {
            anchors.fill: dentro
            verticalAlignment: Text.AlignVCenter
            visible: dentro.text === "" && !dentro.activeFocus
            text: campo.segnaposto
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }
    component Pulsante: Rectangle {
        id: bottone

        property string testo: ""
        property bool attivo: true
        signal premuto()

        height: 34
        radius: Theme.Effects.radiusSM
        color: !bottone.attivo ? Theme.Colors.sunken
             : premi.containsMouse ? Theme.Colors.raisedHigh
             : Theme.Colors.raised
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        opacity: bottone.attivo ? 1 : 0.5

        Text {
            anchors.centerIn: parent
            text: bottone.testo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        MouseArea {
            id: premi
            anchors.fill: parent
            hoverEnabled: true
            enabled: bottone.attivo
            cursorShape: Qt.PointingHandCursor
            onClicked: bottone.premuto()
        }
    }
    property string localeSistema: ""
    property var disponibili: []
    property var campi: ({})
    property string esitoLingua: ""
    Connections {
        target: Core.Ipc

        function onLocaleStateReceived(s) {
            page.localeSistema = s.lang || "";
            page.disponibili = s.disponibili || [];
            page.campi = s.campi || ({});
        }

        function onLocaleResult(r) {
            page.esitoLingua = r.ok === true
                         ? (page.it
                            ? "Fatto. La nuova lingua si vede al prossimo accesso."
                            : "Done. The new language appears at your next login.")
                         : (r.errore || (page.it ? "Non riuscito." : "Failed."));
            svanisciLingua.restart();
        }

        function onConnectedChanged() { if (Core.Ipc.connected) Core.Ipc.localeState(); }
    }
    Timer { id: svanisciLingua; interval: 8000; onTriggered: page.esitoLingua = "" }
    /// Il nome di una lingua scritto NELLA LINGUA STESSA.
    ///
    /// «Italiano», non «Italian»: chi ha sbagliato lingua e vuole tornare
    /// indietro deve poter riconoscere la propria in un elenco che non sa
    /// leggere. È la ragione per cui lo fanno così tutti i sistemi operativi.
    function nomeLocale(l) {
        var noti = {
            "it_IT.UTF-8": "Italiano (Italia)",
            "en_US.UTF-8": "English (United States)",
            "en_GB.UTF-8": "English (United Kingdom)",
            "de_DE.UTF-8": "Deutsch (Deutschland)",
            "fr_FR.UTF-8": "Français (France)",
            "es_ES.UTF-8": "Español (España)",
            "pt_BR.UTF-8": "Português (Brasil)",
            "C.UTF-8": page.it ? "Nessuna (inglese di base)" : "None (plain English)"
        };
        return noti[l] !== undefined ? noti[l] : l;
    }
    // ── Esito, in cima ───────────────────────────────────────────────────

    Card {
        visible: page.esitoLingua !== ""
        heading: page.it ? "Esito" : "Result"

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.esitoLingua
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }
    // ── La lingua di Minerva ─────────────────────────────────────────────

    Card {
        heading: page.it ? "Lingua di Minerva" : "Minerva's language"
        note: page.it
              ? "Cambia subito, mentre guardi: riguarda solo le finestre di "
              + "Minerva — la barra, le Impostazioni, il gestore file."
              : "Changes immediately, as you watch: it only affects Minerva's "
              + "own windows — the bar, Settings, the file manager."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Lingua dell'interfaccia" : "Interface language"
            description: page.it
                         ? "«Come il sistema» segue la lingua scelta qui sotto"
                         : "«Follow the system» uses the language chosen below"
            controlWidth: 320

            control: S.ChoicePicker {
                value: Core.Ipc.get("general.language", "auto")
                options: [
                    { "value": "auto", "label": page.it ? "Come il sistema"
                                                        : "Follow the system" },
                    { "value": "it",   "label": "Italiano" },
                    { "value": "en",   "label": "English" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("general.language", v); }
            }
        }
    }
    // ── La lingua del sistema ────────────────────────────────────────────

    Card {
        heading: page.it ? "Lingua del sistema" : "System language"
        note: page.it
              ? "Vale per tutti i programmi, non solo per Minerva, e si vede "
              + "al prossimo accesso. Compaiono solo le lingue installate: "
              + "aggiungerne una vuol dire generarla sul computer."
              : "Applies to every program, not just Minerva, and takes effect "
              + "at your next login. Only installed languages are listed: "
              + "adding one means generating it on this computer."

        Repeater {
            model: page.disponibili

            delegate: Rectangle {
                id: riga
                required property string modelData

                width: parent.width
                height: 44
                radius: Theme.Effects.radiusSM
                color: riga.modelData === page.localeSistema
                       ? Qt.alpha(Theme.Colors.accent, 0.16)
                       : rigaMouse.containsMouse ? Theme.Colors.hover
                                                 : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    text: page.nomeLocale(riga.modelData)
                    color: riga.modelData === page.localeSistema
                           ? Theme.Colors.accent : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    text: riga.modelData
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

                MouseArea {
                    id: rigaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: riga.modelData !== page.localeSistema
                    onClicked: Core.Ipc.localeSet(riga.modelData)
                }
            }
        }

        Text {
            width: parent.width
            visible: page.disponibili.length === 0
            wrapMode: Text.WordWrap
            text: page.it
                  ? "Nessuna lingua installata risulta disponibile: forse "
                  + "«localectl» non c'è su questo sistema."
                  : "No installed language is available: «localectl» may be "
                  + "missing on this system."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }
    // ── Che cosa segue la lingua ─────────────────────────────────────────
    //
    // Non è decorazione. Cambiare la lingua del sistema riscrive DIECI righe
    // in `/etc/locale.conf`, non una: le `LC_*` hanno la precedenza su `LANG`,
    // e finché restano inchiodate alla lingua vecchia il cambio non si vede.
    // Mostrarle qui è il modo di far vedere che cosa si sta per toccare.

    Card {
        visible: Object.keys(page.campi).length > 1
        heading: page.it ? "Che cosa segue la lingua" : "What follows the language"
        note: page.it
              ? "Numeri, date, valuta e unità di misura. Cambiando lingua "
              + "vengono aggiornati tutti insieme."
              : "Numbers, dates, currency and units. Changing the language "
              + "updates them all together."

        Column {
            width: parent.width
            spacing: 4

            Repeater {
                model: Object.keys(page.campi).sort()

                delegate: Row {
                    required property string modelData
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Text {
                        width: 190
                        text: modelData
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    Text {
                        text: page.campi[modelData]
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }
        }
    }
}
