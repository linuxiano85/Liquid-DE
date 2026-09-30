import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ── Le Stanze, dal bordo sinistro ────────────────────────────────────────
//
// La Riva: «i bordi vivi: banchina in basso, stanze a sinistra, Cassetto a
// destra». Con l'Isola al posto della barra i pallini delle scrivanie non
// ci sono più: le stanze stanno qui, sul bordo sinistro, e si vedono in due
// modi.
//
//  · APERTE: spingendo il puntatore contro il bordo sinistro (lo stesso
//    gesto del Cassetto a destra) o con Super+Tab. Ogni stanza con le icone
//    delle sue finestre; un tocco ci porta.
//  · DI SBIECO: quando si cambia stanza da tastiera (Super+1…9, Super+Ctrl+
//    frecce) o con la rotellina, sbuca per un attimo la colonna delle stanze
//    con quella nuova accesa, e torna dentro. Senza, cambiare stanza sarebbe
//    un salto al buio: niente dice dove si è arrivati.
PanelWindow {
    id: stanze

    property bool aperto: false
    property bool mostrato: false
    /// La colonna che sbuca un attimo quando si cambia stanza.
    property bool sbirciata: false
    property real margineAlto: 0
    property real margineBasso: 0
    /// Escono dal bordo destro (quando il Cassetto è stato messo a sinistra).
    property bool aDestra: false
    /// Trascinate verso l'altro bordo: chi ascolta scambia i bordi.
    signal scambioChiesto()

    // ── Sotto la mano ────────────────────────────────────────────────────
    //
    // Giacomo, 27 settembre 2026: «vorrei averli sotto il mouse quando li
    // trascino e rilascio». La colonna aveva la molla sulla posizione anche
    // mentre la si teneva: inseguiva la mano e restava indietro (51 pixel
    // misurati a mano ferma, `prova-riva-scambio.py`). E al rilascio lo
    // scarto tornava a zero SUBITO, mentre il lato nuovo arriva dal demone un
    // giro dopo: la colonna tornava al posto di partenza e solo dopo volava
    // dall'altra parte.
    //
    // Adesso mentre la si tiene la molla è spenta (la colonna è dove è la
    // mano, come `ui/Slider.qml`), e lasciata per lo scambio resta dov'è
    // finché il lato nuovo non arriva: da lì la molla la porta al suo posto.

    /// Vera mentre la colonna è in mano.
    property bool _tiene: false
    /// Lo scarto si azzera quando arriva il lato nuovo — o dopo un secondo e
    /// mezzo, se il demone non risponde: la colonna non resta appesa.
    onADestraChanged: presaStanze.scarto = 0
    Timer {
        id: scambioRiserva
        interval: 1500
        onTriggered: if (!stanze._tiene) presaStanze.scarto = 0
    }

    function _prendi(xSchermo) {
        presaStanze.inizio = xSchermo;
        presaStanze.scarto = 0;
        stanze._tiene = true;
    }
    function _porta(xSchermo) {
        if (stanze._tiene)
            presaStanze.scarto = xSchermo - presaStanze.inizio;
    }
    /// Lasciata: oltre un terzo dello schermo verso l'altro bordo si
    /// scambia. `_tiene` si spegne PRIMA di toccare lo scarto: i legami si
    /// rifanno subito, e la molla deve essere già accesa quando la posizione
    /// cambia, o la colonna salta invece di scivolare.
    ///
    /// Anche ANNULLATA vale: annullata a metà vuol dire, quasi sempre, che
    /// la spinta sull'altro bordo ha aperto il Cassetto e rubato la presa
    /// (PC di prova, 29 settembre 2026, K4). Scartarla lasciava le Stanze
    /// incastrate dall'altra parte con l'impostazione di prima.
    function _lascia(annullato) {
        if (!stanze._tiene)
            return;
        stanze._tiene = false;
        var verso = stanze.aDestra ? -presaStanze.scarto : presaStanze.scarto;
        if (verso > stanze.width / 3) {
            scambioRiserva.restart();
            stanze.scambioChiesto();
        } else {
            presaStanze.scarto = 0;
        }
    }

    readonly property int attiva: Core.Compositore.scrivaniaAttiva

    /// Le stanze da mostrare: almeno quattro, fino all'ultima occupata o
    /// attiva, più una vuota in fondo (per andarci si tocca quella).
    // ── L'elenco cambia solo quando cambia quello che si vede ───────────
    //
    // Era un legame diretto su Core.Windows.all: un array NUOVO a ogni
    // aggiornamento delle finestre, compreso un TITOLO che cambia — e c'è
    // chi lo cambia di continuo (Claude fa girare ◐◑ nel titolo del
    // terminale, un browser il contatore dei messaggi). Il Repeater, con un
    // array nuovo, rifà da capo tutte le stanze e le loro icone: una volta al
    // secondo, su ogni schermo, anche a Stanze chiuse. Misurato il 29
    // settembre 2026: metà del lavoro della shell a scrivania ferma.
    //
    // Il disegno usa il numero, quante finestre e di quale app (l'icona o
    // l'iniziale): la firma è quella, e l'elenco si sostituisce solo quando
    // la firma cambia.
    readonly property var _calcolato: {
        Core.Compositore.scrivanie;
        var tutte = Core.Windows.all || [];
        var massima = Math.max(3, stanze.attiva);
        for (var i = 0; i < tutte.length; i++)
            if (tutte[i].workspace > massima && tutte[i].workspace <= 10)
                massima = tutte[i].workspace;
        var fuori = [];
        for (var n = 1; n <= Math.min(10, massima + 1); n++) {
            var dentro = [];
            for (var j = 0; j < tutte.length; j++) {
                var w = tutte[j];
                // Le finestre della shell no, le APP di Minerva sì: prima
                // `!w.own` toglieva anche Impostazioni, File e Terminale, e
                // una stanza con dentro solo loro si diceva «vuota».
                if (w.workspace === n && (!w.own || Core.Apps.forWindow(w)))
                    dentro.push(w);
            }
            fuori.push({ "numero": n, "finestre": dentro });
        }
        return fuori;
    }
    property var elenco: []
    property string _firma: ""
    /// Quante volte l'elenco è stato rifatto: per le prove.
    property int rifatte: 0
    function _aggiornaElenco() {
        var c = stanze._calcolato;
        var f = c.map(function(s) {
            return s.numero + ":" + s.finestre.map(function(w) {
                // L'app riconosciuta, non la classe: le nostre app in un
                // processo solo si chiamano tutte `minerva-app` e le
                // distingue il titolo (vedi l'icona più sotto).
                var a = Core.Apps.forWindow(w);
                return a ? a.appId : w.appClass;
            }).join(",");
        }).join("|");
        if (f === stanze._firma) return;
        stanze._firma = f;
        stanze.elenco = c;
        stanze.rifatte++;
    }
    on_CalcolatoChanged: _aggiornaElenco()
    Component.onCompleted: _aggiornaElenco()

    function apri() {
        if (stanze.aperto) return;
        stanze.sbirciata = false;
        stanze.aperto = true;
        stanze.mostrato = true;
        spegni.stop();
    }
    property real _chiuseAlle: 0
    // ── Il trascinamento finisce SEMPRE (vedi lo stesso in Cassetto.qml) ──
    //
    // Annullato a metà — l'altro bordo che apre il Cassetto, la colonna che
    // si chiude — lo `scarto` restava appiccicato e le Stanze restavano
    // incastrate oltre il bordo. E un trascinamento partito da una stanza
    // non vale anche come tocco su quella stanza (prima si finiva lì dentro).
    readonly property bool inTrascinamento: presaStanze.pressed || stanze._tiene

    function chiudi() {
        if (!stanze.aperto) return;
        stanze._lascia(true);
        stanze._chiuseAlle = Date.now();
        stanze.aperto = false;
        spegni.restart();
    }
    function commuta() { stanze.aperto ? stanze.chiudi() : stanze.apri(); }
    function vai(numero) {
        Core.Compositore.vaiAScrivania(numero);
        stanze.chiudi();
    }

    /// Per le prove: che cosa si vede.
    function riassunto() {
        var r = ["stanze: " + (stanze.aperto ? "aperte" : stanze.sbirciata ? "di sbieco" : "chiuse")
                 + " · attiva " + stanze.attiva];
        // Da che parte e dove: «aperte» con la colonna fuori schermo è il
        // difetto che da `aperto` non si vede.
        r.push("lato: " + (stanze.aDestra ? "destra" : "sinistra")
               + " · x " + Math.round(colonna.x) + " su " + Math.round(stanze.width)
               + " · y " + Math.round(colonna.y) + "-" + Math.round(colonna.y + colonna.height));
        for (var i = 0; i < stanze.elenco.length; i++) {
            var s = stanze.elenco[i];
            r.push(s.numero + ": " + s.finestre.map(function(w) { return w.appClass; }).join(", "));
        }
        r.push("rifatte: " + stanze.rifatte);
        return r.join("\n");
    }

    // Cambiata la stanza, e non da qui: la colonna sbuca un attimo.
    onAttivaChanged: {
        // Aperte, o appena chiuse toccando una stanza: la si è appena vista,
        // sbucare di nuovo sarebbe dirlo due volte.
        if (stanze.aperto || Date.now() - stanze._chiuseAlle < 800)
            return;
        stanze.sbirciata = true;
        stanze.mostrato = true;
        spegni.stop();
        rientra.restart();
    }
    Timer {
        id: rientra
        interval: 1100
        onTriggered: { stanze.sbirciata = false; if (!stanze.aperto) spegni.restart(); }
    }

    // Le molle solo dopo il primo fotogramma vero (`Ui.Pronto`), e la
    // colonna entra solo DOPO che le molle ci sono: prima la finestra misura
    // zero, e una posizione calcolata dalla sua misura volava attraverso lo
    // schermo (il menù «a metà fuori schermo» della prima apertura).
    Ui.Pronto { id: pronto }
    property bool _entra: false
    Connections {
        target: pronto
        function onVistoChanged() {
            if (pronto.visto) Qt.callLater(function() { stanze._entra = true; });
            else stanze._entra = false;
        }
    }

    visible: stanze.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-stanze"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: stanze.aperto ? WlrKeyboardFocus.Exclusive
                                               : WlrKeyboardFocus.None
    // Di sbieco non prende niente: è un cartello, sotto si lavora.
    mask: Region { item: stanze.aperto ? fondo : null }

    Timer { id: spegni; interval: Theme.Motion.liquido ? 650 : 0; onTriggered: if (!stanze.aperto && !stanze.sbirciata) stanze.mostrato = false }

    Item {
        id: fondo
        anchors.fill: parent
        MouseArea {
            anchors.fill: parent
            enabled: stanze.aperto
            onPressed: stanze.chiudi()
        }
        Item {
            anchors.fill: parent
            focus: stanze.aperto
            Keys.onEscapePressed: stanze.chiudi()
            Keys.onPressed: function(e) {
                if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                    stanze.vai(e.key - Qt.Key_0);
                    e.accepted = true;
                }
            }
        }
    }

    // ── La colonna ──────────────────────────────────────────────────────
    Rectangle {
        id: colonna
        readonly property int margine: Theme.Effects.space4
        readonly property real larga: stanze.aperto ? 260 : 64
        width: larga
        Behavior on width {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla * 0.7; damping: 0.4 }
        }
        height: Math.min(pila.implicitHeight + 2 * Theme.Effects.space3,
                         stanze.height - stanze.margineAlto - stanze.margineBasso - 2 * margine)
        y: stanze.margineAlto + (stanze.height - stanze.margineAlto - stanze.margineBasso - height) / 2
        // ── A destra, dalla larghezza d'ARRIVO ───────────────────────────
        //
        // Qui c'era `width`, che durante l'apertura è la larghezza animata
        // (64 → 260 con la sua molla): la molla della `x` inseguiva un
        // bersaglio che si spostava a ogni fotogramma, e a destra la colonna
        // restava fuori dallo schermo per un secondo buono prima di entrare
        // (PC di prova, 29 settembre 2026). A sinistra non succedeva perché
        // lì la `x` non dipende dalla larghezza. Con `larga` il bersaglio sta
        // fermo e le due molle non si rincorrono più.
        x: {
            var dentro = stanze.aDestra ? stanze.width - margine - colonna.larga : margine;
            var fuori = stanze.aDestra ? stanze.width + 30 : -colonna.larga - 30;
            return ((stanze.aperto || stanze.sbirciata) && stanze._entra ? dentro : fuori) + presaStanze.scarto;
        }
        Behavior on x {
            enabled: Theme.Motion.liquido && pronto.visto && !stanze._tiene
            SpringAnimation { spring: Theme.Motion.molla * 0.6; damping: 0.42 }
        }
        radius: Theme.Effects.radiusLG
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        clip: true

        // Tutta la colonna si trascina: lasciata oltre un terzo dello
        // schermo verso l'altro bordo, scambia posto col Cassetto. Un tocco
        // resta delle stanze (le loro aree stanno sopra questa).
        MouseArea {
            id: presaStanze
            anchors.fill: parent
            enabled: stanze.aperto
            preventStealing: true
            property real inizio: 0
            property real scarto: 0
            onPressed: function(m) { stanze._prendi(mapToItem(null, m.x, 0).x); }
            onPositionChanged: function(m) { stanze._porta(mapToItem(null, m.x, 0).x); }
            onReleased: stanze._lascia(false)
            onCanceled: stanze._lascia(true)
        }

        Ui.Goccia {
            id: goccia
            radius: Theme.Effects.radiusMD
            color: Qt.alpha(Theme.Colors.accent, 0.22)
            attiva: stanze.attiva >= 1 && stanze.attiva <= ripetitore.count
                    ? ripetitore.itemAt(stanze.attiva - 1) : null
        }

        Column {
            id: pila
            x: Theme.Effects.space2
            y: Theme.Effects.space3
            width: colonna.width - 2 * Theme.Effects.space2
            spacing: Theme.Effects.space1

            Repeater {
                id: ripetitore
                model: stanze.elenco
                delegate: Item {
                    id: stanza
                    required property var modelData
                    width: pila.width
                    height: 48
                    readonly property bool vuota: stanza.modelData.finestre.length === 0

                    MouseArea {
                        id: stanzaMouse
                        anchors.fill: parent
                        enabled: stanze.aperto
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: goccia.punta(stanza, containsMouse)
                        // Un trascinamento non è un clic. Precauzione, non un
                        // difetto visto: la `MouseArea` dà `clicked` a ogni
                        // rilascio sopra di sé, e lasciando la colonna sopra
                        // la stanza da cui la si era presa si andrebbe a
                        // quella scrivania chiudendo le Stanze a metà dello
                        // scambio. In prova non è successo, e lo si dice.
                        property bool _mosso: false
                        onClicked: if (!stanzaMouse._mosso) stanze.vai(stanza.modelData.numero)
                        // Anche da una stanza si trascina la colonna intera.
                        onPressed: function(m) {
                            stanzaMouse._mosso = false;
                            stanze._prendi(mapToItem(null, m.x, 0).x);
                        }
                        onPositionChanged: function(m) {
                            if (!pressed)
                                return;
                            stanze._porta(mapToItem(null, m.x, 0).x);
                            if (Math.abs(presaStanze.scarto) > 8)
                                stanzaMouse._mosso = true;
                        }
                        onReleased: stanze._lascia(false)
                        onCanceled: stanze._lascia(true)
                    }

                    // Il numero, sempre.
                    Rectangle {
                        id: numero
                        x: (48 - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30; radius: 15
                        color: stanza.modelData.numero === stanze.attiva ? Theme.Colors.accent
                             : stanza.vuota ? "transparent" : Theme.Colors.raised
                        border.width: stanza.vuota && stanza.modelData.numero !== stanze.attiva ? 1 : 0
                        border.color: Theme.Colors.edge
                        Text {
                            anchors.centerIn: parent
                            text: stanza.modelData.numero
                            color: stanza.modelData.numero === stanze.attiva ? Theme.Colors.textOnAccent
                                 : stanza.vuota ? Theme.Colors.textFaint : Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightMedium
                        }
                    }

                    // Aperte, le icone delle finestre che ci stanno.
                    Row {
                        anchors.left: numero.right
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        opacity: stanze.aperto ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
                        Repeater {
                            model: stanza.modelData.finestre.slice(0, 5)
                            delegate: Item {
                                id: finestraIcona
                                required property var modelData
                                width: 26; height: 26
                                // `forWindow` e non la classe: le app di
                                // Minerva che vivono in un processo solo si
                                // chiamano tutte `minerva-app`, e le
                                // distingue il titolo.
                                readonly property var app: Core.Apps.forWindow(finestraIcona.modelData)
                                readonly property string icona: finestraIcona.app && finestraIcona.app.icon
                                                                ? finestraIcona.app.icon : ""
                                Image {
                                    anchors.fill: parent
                                    visible: finestraIcona.icona !== ""
                                    sourceSize.width: 52; sourceSize.height: 52
                                    asynchronous: true
                                    source: finestraIcona.icona !== "" ? "file://" + finestraIcona.icona : ""
                                }
                                // Senza icona, l'iniziale — come nella dock.
                                // Prima la riga restava vuota: una stanza con
                                // dentro una finestra che non si vedeva.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: finestraIcona.icona === ""
                                    radius: Theme.Effects.radiusSM
                                    color: Qt.alpha(Theme.Colors.accent, 0.18)
                                    border.width: Theme.Effects.hairline
                                    border.color: Qt.alpha(Theme.Colors.accent, 0.5)
                                    Text {
                                        anchors.centerIn: parent
                                        text: String(finestraIcona.app && finestraIcona.app.name
                                                     ? finestraIcona.app.name
                                                     : (finestraIcona.modelData.appClass || finestraIcona.modelData.title || "?"))
                                              .charAt(0).toUpperCase()
                                        color: Theme.Colors.accent
                                        font.family: Theme.Typography.fontDisplay
                                        font.pixelSize: Theme.Typography.sizeSM
                                        font.weight: Theme.Typography.weightMedium
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: stanza.modelData.finestre.length > 5
                            text: "+" + (stanza.modelData.finestre.length - 5)
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: stanza.vuota
                            text: "vuota"
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }
                }
            }
        }
    }
}
