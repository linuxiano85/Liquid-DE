import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ── Il Centro di controllo di Liquid DE ──────────────────────────────────
//
// Giacomo, 23 settembre 2026: «e se nel caso vogliamo spegnere il pc o
// riavviarlo o bloccare lo schermo? e se vogliamo la modalità notte e wifi
// eccetera? modalità non disturbare e altro dove le mettiamo?». Qui, in un
// posto solo: scende dall'angolo in alto a destra (la sosta del puntatore,
// `Core.Compositore.angolo`) o dalla barra, con la molla.
//
// Esci, Riavvia e Spegni non chiedono «sei sicuro?»: si TENGONO premuti, e il
// pulsante si riempie d'acqua; lasciato prima, non succede niente.
//
// Come il Sottomarino, una finestra sola a tutto schermo che esiste solo
// mentre il Centro è aperto: il fondo raccoglie i clic fuori.
PanelWindow {
    id: centro

    property bool aperto: false
    property bool mostrato: false
    /// Spazio da lasciare in alto (la barra) e in basso (la dock).
    property real margineAlto: 0
    property real margineBasso: 0

    /// Un'azione dei pulsanti dell'energia: la esegue la shell.
    signal azione(string id)

    /// Vero in una sessione di prova: lì il Wi-Fi e il Bluetooth sono quelli
    /// VERI del computer, e spegnerli taglierebbe il collegamento con chi sta
    /// lavorando. In prova le due levette non toccano niente.
    readonly property bool inProva: !!Quickshell.env("MINERVA_PROVA")

    /// Il pulsante dell'energia armato dal primo tocco, se c'è: UNO solo.
    /// Toccarne un altro sposta la conferma lì, e chiudere il Centro la
    /// toglie — tre «Ancora» accesi insieme non dicevano più cosa sarebbe
    /// successo al tocco seguente.
    property string armato: ""
    onArmatoChanged: if (centro.armato !== "") disarma.restart(); else disarma.stop()
    Timer { id: disarma; interval: 3000; onTriggered: centro.armato = "" }

    function apri() {
        if (centro.aperto) return;
        centro.aperto = true;
        centro.mostrato = true;
        spegni.stop();
    }
    function chiudi() {
        if (!centro.aperto) return;
        centro.aperto = false;
        centro.armato = "";
        centro.modifica = false;
        centro.scegliDove = false;
        spegni.restart();
    }

    // ── I riquadri: quali, e in che ordine ──────────────────────────────
    //
    // Giacomo, 5 ottobre 2026: «la possibilità di personalizzare il menu in
    // alto a destra per accesso rapido alle impostazioni, e l'aggiunta ad
    // esempio del pulsante impostazioni e altre voci, l'ordine». Il catalogo
    // sta qui; quali si vedono e in che ordine sta in `centro.voci`, e si
    // cambia da qui dentro con «Personalizza».
    //
    // Due generi: le LEVETTE accendono e spengono qualcosa e dicono com'è;
    // le SCORCIATOIE aprono un posto, e il Centro si chiude.
    readonly property var catalogo: [
        { "id": "wifi",          "nome": "Wi-Fi",          "levetta": true },
        { "id": "bluetooth",     "nome": "Bluetooth",      "levetta": true },
        { "id": "notte",         "nome": "Luce notturna",  "levetta": true },
        { "id": "nondisturbare", "nome": "Non disturbare", "levetta": true },
        { "id": "risparmio",     "nome": "Risparmio",      "levetta": true },
        { "id": "gioco",         "nome": "Modo gioco",     "levetta": true },
        { "id": "trasmetti",     "nome": "Trasmetti",      "levetta": true },
        { "id": "impostazioni",  "nome": "Impostazioni",   "detto": "tutte le scelte" },
        { "id": "schermata",     "nome": "Schermata",      "detto": "cattura lo schermo" },
        { "id": "appunti",       "nome": "Appunti",        "detto": "quello che hai copiato" },
        { "id": "file",          "nome": "File",           "detto": "la cartella personale" },
        { "id": "terminale",     "nome": "Terminale",      "detto": "una riga di comando" },
        { "id": "attivita",      "nome": "Attività",       "detto": "programmi e risorse" },
        { "id": "scorciatoie",   "nome": "Scorciatoie",    "detto": "i tasti di Minerva" }
    ]
    readonly property var vociDiSerie: ["wifi", "bluetooth", "notte", "nondisturbare",
                                        "risparmio", "gioco", "trasmetti", "impostazioni"]

    function _voceDi(id) {
        for (var i = 0; i < centro.catalogo.length; i++)
            if (centro.catalogo[i].id === id) return centro.catalogo[i];
        return null;
    }

    /// I riquadri da mostrare: quelli scelti, nel loro ordine, senza doppioni
    /// e senza nomi che il catalogo non conosce più.
    readonly property var voci: {
        var scelte = Core.Ipc.get("centro.voci", centro.vociDiSerie) || [];
        var out = [];
        for (var i = 0; i < scelte.length; i++) {
            var id = String(scelte[i]);
            if (out.indexOf(id) === -1 && centro._voceDi(id) !== null)
                out.push(id);
        }
        return out;
    }
    /// Quelli del catalogo che non si vedono: si aggiungono da «Personalizza».
    readonly property var mancanti: centro.catalogo
        .map(function (c) { return c.id; })
        .filter(function (id) { return centro.voci.indexOf(id) === -1; })

    /// Vero mentre si personalizza: i riquadri si spostano e si tolgono, e
    /// toccarli non accende niente.
    property bool modifica: false

    function _salva(l) { Core.Ipc.setSetting("centro.voci", l); }
    function sposta(id, verso) {
        var l = centro.voci.slice();
        var i = l.indexOf(id), j = i + verso;
        if (i < 0 || j < 0 || j >= l.length) return;
        l[i] = l[j]; l[j] = id;
        centro._salva(l);
    }
    function togli(id) {
        centro._salva(centro.voci.filter(function (v) { return v !== id; }));
    }
    function aggiungi(id) {
        if (centro.voci.indexOf(id) === -1)
            centro._salva(centro.voci.concat([id]));
    }

    function accesoDi(id) {
        switch (id) {
        case "wifi":          return Core.SystemState.wifiOn;
        case "bluetooth":     return Core.SystemState.bluetoothOn;
        case "notte":         return Core.Ipc.get("display.nightLight", false) === true;
        case "nondisturbare": return Core.Notifications.doNotDisturb;
        case "risparmio":     return !!Core.Compositore.risparmio && Core.Compositore.risparmio.attivo === true;
        case "gioco":         return Core.Gioco.attiva;
        case "trasmetti":     return centro.trasmissioneVerso !== "";
        }
        return false;
    }

    function dettoDi(id) {
        switch (id) {
        // Radio accesa non vuol dire connessi (J2, PC di prova): diceva
        // «connesso» anche senza nessuna rete.
        case "wifi":          return Core.SystemState.networkWired ? "in rete col cavo"
                                   : Core.SystemState.networkName !== "" ? Core.SystemState.networkName
                                   : "non connesso";
        case "bluetooth":     return "acceso";
        case "notte":         return "schermo caldo";
        case "nondisturbare": return "notifiche in silenzio";
        case "risparmio":     return "effetti ridotti";
        case "gioco":         return "notifiche zitte";
        case "trasmetti":
            if (centro.trasmissioneVerso !== "")
                return (centro.trasmissioneSpecchio ? "schermo su " : "sto mandando a ")
                       + centro.trasmissioneVerso;
            if (centro.schermiTrovati.length === 0)
                return "nessuno schermo in rete";
            return centro.schermiTrovati.map(function (s) { return String(s.nome); }).join(", ");
        }
        var v = centro._voceDi(id);
        return v && v.detto ? v.detto : "";
    }

    function scegli(id) {
        switch (id) {
        case "wifi":
            if (!centro.inProva) Core.SystemState.setWifi(!Core.SystemState.wifiOn);
            return;
        case "bluetooth":
            if (!centro.inProva) Core.SystemState.setBluetooth(!Core.SystemState.bluetoothOn);
            return;
        case "notte":
            Core.Ipc.setSetting("display.nightLight", !centro.accesoDi("notte"));
            return;
        case "nondisturbare":
            Core.Ipc.setSetting("notifications.doNotDisturb", !centro.accesoDi("nondisturbare"));
            return;
        case "risparmio":
            // Spegnerla deve spegnere. Scriveva sempre «auto» quando era
            // accesa: ma accesa da sola — «auto», batteria bassa — voleva dire
            // riscrivere lo stesso valore, e la levetta non si spegneva mai
            // (30 settembre 2026). Accesa a mano («sempre») torna ad «auto»;
            // accesa dalla batteria diventa «mai», che si rimette dalle
            // Impostazioni → Energia.
            Core.Ipc.setSetting("power.risparmioEffetti",
                !centro.accesoDi("risparmio") ? "sempre"
                : Core.Ipc.get("power.risparmioEffetti", "auto") === "sempre" ? "auto" : "mai");
            return;
        case "gioco":
            Core.Gioco.forzato = !Core.Gioco.forzato;
            return;
        case "trasmetti":
            // Sempre premibile mentre trasmette: è l'unico modo di fermarla.
            if (centro.trasmissioneVerso !== "") {
                Core.Ipc.trasmettiFerma();
                centro.scegliDove = false;
                return;
            }
            centro.motivoFallito = "";
            // Un solo televisore: niente da scegliere.
            if (centro.schermiTrovati.length === 1) {
                Core.Ipc.trasmettiSchermo(String(centro.schermiTrovati[0].id), "");
                return;
            }
            if (centro.schermiTrovati.length === 0) {
                centro.motivoFallito = "Nessun televisore trovato in rete: deve essere acceso e sulla stessa rete.";
                return;
            }
            centro.scegliDove = true;
            return;
        }
        // Una scorciatoia: il posto lo apre la shell, e il Centro si toglie
        // di mezzo — resterebbe sopra a quello che si è appena aperto.
        centro.chiudi();
        centro.azione(id);
    }
    function commuta() { centro.aperto ? centro.chiudi() : centro.apri(); }

    // ── Trasmettere lo schermo a un televisore ───────────────────────────
    //
    // Stava nel pannello di prima (`spine/panels/ControlPanel.qml`), e quando
    // il Centro ne ha preso il posto è rimasto là: «Trasmetti lo schermo» non
    // si poteva più né avviare né FERMARE (5 ottobre 2026). Un file si manda
    // dal tasto destro, nel gestore file o in Anteprima; da qui si manda lo
    // schermo, dal vivo.
    //
    // Si chiede solo se il riquadro c'è e il Centro è aperto: la ricerca dei
    // televisori costa due secondi di rete.
    readonly property bool _trasmettiQui: centro.aperto && centro.voci.indexOf("trasmetti") !== -1
    property var schermiTrovati: []
    property string trasmissioneVerso: ""
    property bool trasmissioneSpecchio: false
    property bool scegliDove: false
    property string motivoFallito: ""
    on_TrasmettiQuiChanged: if (centro._trasmettiQui) Core.Ipc.condivisioneDove()
    Timer {
        interval: 4000
        repeat: true
        running: centro._trasmettiQui
        triggeredOnStart: true
        onTriggered: Core.Ipc.trasmettiChiediStato()
    }
    Connections {
        target: Core.Ipc
        function onCondivisioneDoveRicevute(dati) {
            var d = (dati && dati.destinazioni) || [];
            for (var i = 0; i < d.length; i++) {
                if (d[i].id === "schermo") {
                    centro.schermiTrovati = d[i].dispositivi || [];
                    return;
                }
            }
        }
        function onTrasmettiStato(st) {
            centro.trasmissioneVerso = st && st.inCorso === true ? String(st.verso || "") : "";
            centro.trasmissioneSpecchio = st ? st.specchio === true : false;
        }
        function onTrasmettiEsito(e) {
            if (e && e.ok === true && e.verso) {
                centro.trasmissioneVerso = String(e.verso);
                centro.scegliDove = false;
            } else {
                centro.trasmissioneVerso = "";
                centro.trasmissioneSpecchio = false;
                if (e && e.error)
                    centro.motivoFallito = String(e.error);
            }
        }
    }

    visible: centro.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-centro"
    WlrLayershell.layer: WlrLayer.Overlay
    // La tastiera la prende SUBITO, come il Sottomarino. Con «al primo clic»
    // (OnDemand) la finestra diventava attiva proprio sulla pressione, e Qt
    // annullava quel clic: levette e pulsanti non rispondevano mai col
    // touchpad vero (visto dalla sonda il 24/09: «premuto» e subito
    // «annullato»). Le barre si salvavano solo perché proteggono la presa.
    WlrLayershell.keyboardFocus: centro.aperto ? WlrKeyboardFocus.Exclusive
                                               : WlrKeyboardFocus.None

    Timer { id: spegni; interval: Theme.Motion.liquido ? 650 : 0; onTriggered: if (!centro.aperto) centro.mostrato = false }

    // Il fondo: premere fuori chiude, già alla pressione. Al rilascio non
    // bastava: col touchpad un tocco che si sposta di un soffio fra pressione
    // e rilascio non è un clic, e il Centro restava aperto.
    MouseArea {
        anchors.fill: parent
        enabled: centro.aperto
        onPressed: centro.chiudi()
    }

    Item {
        anchors.fill: parent
        focus: centro.aperto
        Keys.onEscapePressed: centro.chiudi()
    }

    // ── Il pannello ─────────────────────────────────────────────────────
    Rectangle {
        id: pannello
        readonly property int margine: Theme.Effects.space4
        width: 392
        height: colonna.implicitHeight + 2 * Theme.Effects.space4
        x: centro.width - margine - width
        y: centro.aperto ? margine + centro.margineAlto : -height - 30
        Behavior on y {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla * 0.6; damping: 0.42 }
        }
        radius: Theme.Effects.radiusLG
        // Quasi pieno: col vetro trasparente di serie i riquadri della
        // scrivania dietro si leggevano ATTRAVERSO le levette e le app.
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: colonna
            x: Theme.Effects.space4
            y: Theme.Effects.space4
            width: pannello.width - 2 * Theme.Effects.space4
            spacing: Theme.Effects.space3
            opacity: centro.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

            // ── I riquadri ──────────────────────────────────────────────
            Item {
                width: parent.width
                height: 18
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: centro.modifica ? "Fatto" : "Personalizza"
                    color: personalizzaMouse.containsMouse || centro.modifica
                           ? Theme.Colors.accent : Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                    font.weight: centro.modifica ? Theme.Typography.weightMedium
                                                 : Theme.Typography.weightRegular
                    MouseArea {
                        id: personalizzaMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: centro.modifica = !centro.modifica
                    }
                }
            }

            Grid {
                columns: 2
                spacing: Theme.Effects.space2
                width: parent.width

                Repeater {
                    model: centro.voci
                    delegate: Levetta {
                        required property var modelData
                        required property int index
                        readonly property var voce: centro._voceDi(modelData)
                        nome: voce ? voce.nome : modelData
                        scorciatoia: !(voce && voce.levetta)
                        acceso: centro.accesoDi(modelData)
                        detto: centro.dettoDi(modelData)
                        inModifica: centro.modifica
                        primo: index === 0
                        ultimo: index === centro.voci.length - 1
                        onScelto: centro.scegli(modelData)
                        onSpostato: function (verso) { centro.sposta(modelData, verso); }
                        onTolto: centro.togli(modelData)
                    }
                }
            }

            // ── Dove mandare lo schermo ─────────────────────────────────
            Column {
                width: parent.width
                spacing: Theme.Effects.space1
                visible: !centro.modifica && centro.scegliDove && centro.trasmissioneVerso === ""
                Text {
                    text: "Manda lo schermo a:"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
                Repeater {
                    model: centro.schermiTrovati
                    delegate: Rectangle {
                        id: tv
                        required property var modelData
                        width: parent.width
                        height: 36
                        radius: Theme.Effects.radiusMD
                        color: tvMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.22) : Theme.Colors.raised
                        Text {
                            x: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: String(tv.modelData.nome)
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        MouseArea {
                            id: tvMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                centro.motivoFallito = "";
                                Core.Ipc.trasmettiSchermo(String(tv.modelData.id), "");
                            }
                        }
                    }
                }
                // Come è fatto HLS: va detto prima, non scoperto davanti alla TV.
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Circa tre secondi di ritardo: per guardare va bene, per lavorare "
                          + "sullo schermo grande no. Un file si manda dal tasto destro, «Trasmetti a…»."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
            Text {
                width: parent.width
                visible: centro.motivoFallito !== "" && centro.trasmissioneVerso === ""
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: centro.motivoFallito
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            // In modifica: quello che si può aggiungere, e la via di ritorno.
            Column {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: centro.modifica

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: centro.mancanti.length > 0
                          ? "Tocca per aggiungere. Le frecce spostano, la croce toglie."
                          : "Ci sono già tutti. Le frecce spostano, la croce toglie."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
                Flow {
                    width: parent.width
                    spacing: Theme.Effects.space1
                    Repeater {
                        model: centro.mancanti
                        delegate: Rectangle {
                            id: daAggiungere
                            required property var modelData
                            width: aggiungiTesto.implicitWidth + Theme.Effects.space4
                            height: 30
                            radius: height / 2
                            color: aggiungiMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.22)
                                                               : Theme.Colors.raised
                            Text {
                                id: aggiungiTesto
                                anchors.centerIn: parent
                                text: "+ " + (centro._voceDi(daAggiungere.modelData) || { "nome": "" }).nome
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            MouseArea {
                                id: aggiungiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: centro.aggiungi(daAggiungere.modelData)
                            }
                        }
                    }
                }
                Text {
                    text: "↺ Come di serie"
                    color: serieMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                    MouseArea {
                        id: serieMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: centro._salva(centro.vociDiSerie)
                    }
                }
            }

            // Volume e luminosità: barre che si riempiono.
            Liquido {
                nome: "Volume"
                valore: Core.SystemState.volume
                visible: valore >= 0
                onCambiato: function(v) { Core.SystemState.setVolume(v); }
            }
            Liquido {
                nome: "Luminosità"
                valore: Core.SystemState.brightness
                visible: valore >= 0
                onCambiato: function(v) { Core.SystemState.setBrightness(Math.max(5, v)); }
            }

            // Il lettore, quando c'è qualcosa che suona.
            Rectangle {
                width: parent.width
                height: 56
                visible: Core.Media.cQualcosa
                radius: Theme.Effects.radiusMD
                color: Theme.Colors.raised

                Image {
                    id: copertina
                    x: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40
                    source: Core.Media.copertina || ""
                    sourceSize.width: 80; sourceSize.height: 80
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors.fill: copertina
                    visible: !copertina.visible
                    radius: Theme.Effects.radiusSM
                    color: Qt.alpha(Theme.Colors.accent, 0.35)
                }
                Column {
                    anchors.left: copertina.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: tasti.left
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: Core.Media.titolo
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }
                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        elide: Text.ElideRight
                        text: Core.Media.artista
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
                Row {
                    id: tasti
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [
                            { "icona": "prev", "fa": "prec" },
                            { "icona": Core.Media.inRiproduzione ? "pause" : "play", "fa": "suona" },
                            { "icona": "next", "fa": "succ" }
                        ]
                        delegate: Rectangle {
                            id: tasto
                            required property var modelData
                            width: 32; height: 32; radius: 16
                            color: tastoMouse.containsMouse ? Theme.Colors.hover : "transparent"
                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                name: tasto.modelData.icona
                                color: Theme.Colors.text
                            }
                            MouseArea {
                                id: tastoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (tasto.modelData.fa === "prec") Core.Media.precedente();
                                    else if (tasto.modelData.fa === "succ") Core.Media.successivo();
                                    else Core.Media.riproduci();
                                }
                            }
                        }
                    }
                }
            }

            // L'energia.
            Row {
                width: parent.width
                spacing: Theme.Effects.space1
                Repeater {
                    model: [
                        { "id": "blocca",   "it": "Blocca",   "tieni": false },
                        { "id": "sospendi", "it": "Sospendi", "tieni": false },
                        { "id": "esci",     "it": "Esci",     "tieni": true },
                        { "id": "riavvia",  "it": "Riavvia",  "tieni": true },
                        { "id": "spegni",   "it": "Spegni",   "tieni": true }
                    ]
                    delegate: Energia {
                        width: (colonna.width - 4 * Theme.Effects.space1) / 5
                        armato: centro.armato === modelData.id
                        onArma: function(id) { centro.armato = id; }
                        onFatto: function(id) { centro.chiudi(); centro.azione(id); }
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Esci, Riavvia e Spegni: tieni premuto finché non si riempie, o tocca due volte."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Una levetta ─────────────────────────────────────────────────────
    component Levetta: Rectangle {
        id: lev
        property string nome: ""
        property bool acceso: false
        property string detto: ""
        /// Apre un posto invece di accendere qualcosa: niente «spento».
        property bool scorciatoia: false
        property bool inModifica: false
        property bool primo: false
        property bool ultimo: false
        signal scelto()
        signal spostato(int verso)
        signal tolto()
        width: 179
        height: 58
        radius: Theme.Effects.radiusMD
        color: lev.acceso ? Qt.alpha(Theme.Colors.accent, 0.22) : Theme.Colors.raised
        border.width: 1
        border.color: lev.acceso ? Qt.alpha(Theme.Colors.accent, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
        scale: levMouse.pressed ? 0.96 : 1
        Behavior on scale {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
        }
        Column {
            x: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 2 * Theme.Effects.space3 - (lev.inModifica ? 80 : 0)
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: lev.nome
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: lev.scorciatoia || lev.acceso ? lev.detto : "spento"
                color: lev.acceso ? Theme.Colors.accent : Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
        MouseArea {
            id: levMouse
            anchors.fill: parent
            enabled: !lev.inModifica
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lev.scelto()
        }

        // In modifica: ‹ › spostano, × toglie.
        Row {
            visible: lev.inModifica
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: [
                    { "segno": "‹", "fa": -1, "si": !lev.primo },
                    { "segno": "›", "fa": 1,  "si": !lev.ultimo },
                    { "segno": "×", "fa": 0,  "si": true }
                ]
                delegate: Rectangle {
                    id: tastino
                    required property var modelData
                    width: 24; height: 24; radius: 12
                    opacity: tastino.modelData.si ? 1 : 0.3
                    color: tastinoMouse.containsMouse && tastino.modelData.si
                           ? (tastino.modelData.fa === 0 ? Qt.alpha(Theme.Colors.danger, 0.3)
                                                         : Theme.Colors.hover)
                           : Qt.alpha(Theme.Colors.panel, 0.6)
                    Text {
                        anchors.centerIn: parent
                        text: tastino.modelData.segno
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    MouseArea {
                        id: tastinoMouse
                        anchors.fill: parent
                        enabled: tastino.modelData.si
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tastino.modelData.fa === 0 ? lev.tolto()
                                                              : lev.spostato(tastino.modelData.fa)
                    }
                }
            }
        }
    }

    // ── Una barra che si riempie: volume, luminosità ────────────────────
    component Liquido: Rectangle {
        id: liq
        property string nome: ""
        property int valore: 0
        signal cambiato(int v)
        /// Mentre si trascina si mostra quello che dice il dito, non quello
        /// che il sistema ha già applicato: un volume che salta indietro
        /// sotto il dito è peggio di uno che arriva un attimo dopo.
        property int _dito: -1
        /// Il valore da mandare al sistema: uno per volta, al passo del timer.
        /// Mandarne uno a ogni pixel di trascinamento accodava comandi, e il
        /// volume arrivava in ritardo e a scatti.
        property int _daMandare: -1
        Timer {
            id: manda
            interval: 40
            repeat: true
            running: liq._daMandare >= 0
            onTriggered: {
                if (liq._daMandare >= 0) liq.cambiato(liq._daMandare);
                liq._daMandare = -1;
            }
        }
        readonly property int mostrato: liq._dito >= 0 ? liq._dito : Math.max(0, liq.valore)
        width: parent ? parent.width : 300
        height: 40
        radius: height / 2
        color: Theme.Colors.raised
        clip: true
        Rectangle {
            width: Math.max(liq.height, liq.width * liq.mostrato / 100)
            height: parent.height
            radius: height / 2
            color: Qt.alpha(Theme.Colors.accent, 0.45)
            Behavior on width {
                enabled: Theme.Motion.liquido && liq._dito < 0
                SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
            }
        }
        Text {
            x: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            text: liq.nome
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            text: liq.mostrato + "%"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeSM
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            function _da(ev) {
                return Math.round(Math.max(0, Math.min(1, ev.x / liq.width)) * 100);
            }
            onPressed: function(ev) { liq._dito = _da(ev); liq.cambiato(liq._dito); }
            onPositionChanged: function(ev) {
                if (!pressed) return;
                liq._dito = _da(ev);
                liq._daMandare = liq._dito;
            }
            onReleased: {
                // L'ultimo valore parte subito, non al prossimo giro del timer.
                if (liq._dito >= 0) liq.cambiato(liq._dito);
                liq._daMandare = -1;
                liq._dito = -1;
            }
            onWheel: function(ev) {
                liq.cambiato(Math.max(0, Math.min(100, liq.valore + (ev.angleDelta.y > 0 ? 5 : -5))));
            }
        }
    }

    // ── Un pulsante dell'energia ────────────────────────────────────────
    component Energia: Rectangle {
        id: en
        required property var modelData
        signal fatto(string id)
        /// Chiede di diventare il pulsante armato (o, con "", di smettere).
        signal arma(string id)
        /// Da 0 a 1 mentre lo si tiene premuto; a 1 parte.
        property real pieno: 0
        /// Armato da un primo tocco: il secondo, entro tre secondi, conferma.
        /// È la via del touchpad, dove tenere il dito appoggiato non tiene
        /// premuto niente. Lo decide il Centro, che ne tiene acceso uno solo.
        property bool armato: false
        height: 44
        radius: Theme.Effects.radiusMD
        clip: true
        color: en.modelData.tieni ? Theme.Colors.raised : Qt.alpha(Theme.Colors.accent, 0.12)
        border.width: 1
        border.color: enMouse.pressed && en.modelData.tieni ? Qt.alpha(Theme.Colors.danger, 0.7)
                                                            : "transparent"
        // L'acqua che sale. Con gli stessi angoli del pulsante: in QML il
        // ritaglio è rettangolare, e un'acqua squadrata sporgeva dagli angoli.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * en.pieno
            radius: Math.min(en.radius, height / 2)
            color: Qt.alpha(Theme.Colors.danger, 0.55)
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: en.armato
            color: Qt.alpha(Theme.Colors.danger, 0.35)
        }
        Text {
            anchors.centerIn: parent
            text: en.armato ? "Ancora" : en.modelData.it
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightMedium
        }
        NumberAnimation {
            id: riempi
            target: en
            property: "pieno"
            from: 0; to: 1
            duration: 900
            onFinished: if (en.pieno >= 1) { en.pieno = 0; en.fatto(en.modelData.id); }
        }
        MouseArea {
            id: enMouse
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: if (en.modelData.tieni) riempi.restart()
            onReleased: {
                if (!en.modelData.tieni) {
                    en.fatto(en.modelData.id);
                    return;
                }
                if (!riempi.running)
                    return;             // era pieno: è già partito
                riempi.stop();
                en.pieno = 0;
                // Un tocco breve: il primo arma, il secondo conferma.
                if (en.armato) {
                    en.arma("");
                    en.fatto(en.modelData.id);
                } else {
                    en.arma(en.modelData.id);
                }
            }
            onCanceled: { riempi.stop(); en.pieno = 0; }
        }
    }
}
