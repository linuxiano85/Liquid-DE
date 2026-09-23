import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Calcolatrice — La finestra della calcolatrice di Minerva.
//
// Era dichiarata dentro `calcolatrice.qml`, che era anche il punto d'ingresso
// del processo. Adesso è un componente a sé perché la calcolatrice non ha più
// un processo suo: vive dentro `app.qml` insieme a Editor, Anteprima e
// Attività, e il perché — con i numeri — sta scritto lì.
//
// Il file non è cambiato in nient'altro: stesso albero, stessi tasti, stessa
// griglia calcolata dalla finestra.
FloatingWindow {
    id: calco

    visible: Core.Ipc.prontoADipingere && !calco.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    //
    // Vera quando la calcolatrice c'è ma non si deve vedere. La decisione sta
    // fuori — in `core/TenutaPronta.qml` — qui c'è solo l'interruttore della
    // luce.
    property bool dormiente: false

    /// Chi la ospita decide se chiudere la finestra o l'intero programma.
    signal requestClose()
    title: Core.Strings.lang === "it" ? "Minerva · Calcolatrice"
                                      : "Minerva · Calculator"
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
    color: Theme.Colors.window
    implicitWidth: 320
    implicitHeight: 520

    /// Sotto questa misura i tasti comincerebbero a stringersi davvero.
    /// Non è un numero a occhio: con la barra del titolo, i margini e il
    /// display, a 470 di altezza una cella è ancora alta 40 pixel, e a 300
    /// di larghezza è larga 63. Sotto, si preme male.
    minimumSize: Qt.size(300, 470)

    onClosed: calco.requestClose()

    // ── Lo stato ─────────────────────────────────────────────────────

    /// L'espressione scritta finora, come la si vede.
    property string espressione: ""
    /// Il risultato dell'ultimo «=», se c'è.
    property string risultato: ""
    /// Vero subito dopo un «=»: la prossima cifra ricomincia da capo.
    property bool appenaCalcolato: false
    /// L'ultimo errore da mostrare, o vuoto.
    property string errore: ""

    // ── La memoria ───────────────────────────────────────────────────
    //
    // Come su KCalc: M+ aggiunge il valore corrente, M− lo toglie,
    // MR lo richiama dentro l'espressione, MC la svuota. La spia «M»
    // sul display dice quando contiene qualcosa.
    property real memoria: 0
    readonly property bool memoriaAttiva: calco.memoria !== 0

    // ── L'analizzatore ───────────────────────────────────────────────
    //
    // Una piccola macchina che legge l'espressione da sinistra a destra
    // e rispetta la precedenza: prima × e ÷, poi + e −, con le
    // parentesi per cambiare l'ordine. Niente `eval` di JavaScript:
    // un'espressione è solo numeri e operatori, e qualunque altra cosa
    // è un errore da dire, non da eseguire.

    function calcola(testo) {
        var p = { "s": testo, "i": 0 };

        function saltaSpazi() {
            while (p.i < p.s.length && p.s.charAt(p.i) === " ")
                p.i++;
        }

        function numero() {
            saltaSpazi();
            // π: una costante, non un simbolo da eseguire.
            if (p.s.indexOf("π", p.i) === p.i) {
                p.i++;
                return { "valore": Math.PI };
            }
            var inizio = p.i;
            while (p.i < p.s.length
                   && ((p.s.charAt(p.i) >= "0" && p.s.charAt(p.i) <= "9")
                       || p.s.charAt(p.i) === "."))
                p.i++;
            if (p.i === inizio)
                return { "errore": true };
            var v = parseFloat(p.s.substring(inizio, p.i));
            if (isNaN(v))
                return { "errore": true };
            return { "valore": v };
        }

        function fattore() {
            saltaSpazi();
            if (p.i < p.s.length && p.s.charAt(p.i) === "(") {
                p.i++;
                var dentro = somma();
                if (dentro.errore)
                    return dentro;
                saltaSpazi();
                if (p.i >= p.s.length || p.s.charAt(p.i) !== ")")
                    return { "errore": true };
                p.i++;
                return dentro;
            }
            if (p.i < p.s.length && (p.s.charAt(p.i) === "-"
                    || p.s.charAt(p.i) === "−")) {
                p.i++;
                var n = fattore();
                if (n.errore)
                    return n;
                return { "valore": -n.valore };
            }
            if (p.i < p.s.length && p.s.charAt(p.i) === "+") {
                p.i++;
                return fattore();
            }
            if (p.i < p.s.length && p.s.charAt(p.i) === "√") {
                p.i++;
                var sotto = fattore();
                if (sotto.errore || sotto.valore < 0)
                    return { "errore": true };
                return { "valore": Math.sqrt(sotto.valore) };
            }
            return numero();
        }

        function prodotto() {
            var sinistra = fattore();
            if (sinistra.errore)
                return sinistra;
            // I suffissi: ² e ¹/ₓ stanno attaccati al numero che li
            // precede, prima di qualunque operatore.
            saltaSpazi();
            if (p.i < p.s.length && p.s.charAt(p.i) === "²") {
                p.i++;
                sinistra = { "valore": sinistra.valore * sinistra.valore };
            } else if (p.i + 1 < p.s.length && p.s.charAt(p.i) === "⁻"
                       && p.s.charAt(p.i + 1) === "¹") {
                // ⁻¹ attaccato al numero è il reciproco: il tasto
                // «1/x» scrive questo.
                p.i += 2;
                if (sinistra.valore === 0)
                    return { "errore": true };
                sinistra = { "valore": 1 / sinistra.valore };
            }
            while (true) {
                saltaSpazi();
                var op = p.i < p.s.length ? p.s.charAt(p.i) : "";
                if (op !== "×" && op !== "*" && op !== "÷" && op !== "/") {
                    // La moltiplicazione implicita: 2π, 3√4, 2(3+1).
                    if (op === "π" || op === "√" || op === "("
                        || (op >= "0" && op <= "9") || op === ".") {
                        var implicita = fattore();
                        if (implicita.errore)
                            return implicita;
                        sinistra = { "valore": sinistra.valore * implicita.valore };
                        continue;
                    }
                    break;
                }
                p.i++;
                var destra = fattore();
                if (destra.errore)
                    return destra;
                if ((op === "÷" || op === "/") && destra.valore === 0)
                    return { "errore": true };
                sinistra = { "valore": (op === "×" || op === "*")
                             ? sinistra.valore * destra.valore
                             : sinistra.valore / destra.valore };
            }
            return sinistra;
        }

        function somma() {
            var sinistra = prodotto();
            if (sinistra.errore)
                return sinistra;
            while (true) {
                saltaSpazi();
                var op = p.i < p.s.length ? p.s.charAt(p.i) : "";
                if (op !== "+" && op !== "-")
                    break;
                p.i++;
                var destra = prodotto();
                if (destra.errore)
                    return destra;
                sinistra = { "valore": op === "+"
                             ? sinistra.valore + destra.valore
                             : sinistra.valore - destra.valore };
            }
            return sinistra;
        }

        var esito = somma();
        saltaSpazi();
        if (!esito.errore && p.i < p.s.length)
            return { "errore": true };
        return esito;
    }

    /// Come si scrive un numero: senza zeri in coda quando non servono.
    function formatta(v) {
        if (v === undefined || isNaN(v) || !isFinite(v))
            return "";
        var t = String(Math.round(v * 1e10) / 1e10);
        // Tanto piccolo da diventare esponenziale: si mostra com'è.
        if (t.indexOf("e") !== -1)
            return t;
        if (t.indexOf(".") !== -1) {
            while (t.length > 1 && t.charAt(t.length - 1) === "0")
                t = t.substring(0, t.length - 1);
            if (t.charAt(t.length - 1) === ".")
                t = t.substring(0, t.length - 1);
        }
        return t;
    }

    function premi(tasto) {
        calco.errore = "";
        if (tasto === "C") {
            calco.espressione = "";
            calco.risultato = "";
            calco.appenaCalcolato = false;
            return;
        }
        if (tasto === "⌫") {
            if (calco.appenaCalcolato) {
                calco.espressione = "";
                calco.risultato = "";
                calco.appenaCalcolato = false;
                return;
            }
            if (calco.espressione !== "")
                calco.espressione = calco.espressione.substring(
                    0, calco.espressione.length - 1);
            return;
        }
        if (tasto === "MC") {
            calco.memoria = 0;
            return;
        }
        if (tasto === "MR") {
            // Il richiamo è come scrivere una cifra: dopo un «=»
            // ricomincia da capo, altrimenti si accoda.
            if (calco.appenaCalcolato) {
                calco.espressione = calco.formatta(calco.memoria);
                calco.risultato = "";
                calco.appenaCalcolato = false;
            } else {
                calco.espressione += calco.formatta(calco.memoria);
            }
            return;
        }
        if (tasto === "M+" || tasto === "M−") {
            // Il valore da ricordare è quello che si sta guardando:
            // il risultato appena calcolato, o il conto
            // dell'espressione, o niente.
            var ricordo = 0;
            if (calco.appenaCalcolato && calco.risultato !== "")
                ricordo = parseFloat(calco.risultato);
            else if (calco.espressione !== "") {
                var esitoMem = calco.calcola(calco.espressione);
                if (!esitoMem.errore)
                    ricordo = esitoMem.valore;
            }
            calco.memoria += tasto === "M+" ? ricordo : -ricordo;
            return;
        }
        if (tasto === "=") {
            if (calco.espressione === "")
                return;
            var esito = calco.calcola(calco.espressione);
            if (esito.errore) {
                calco.errore = Core.Strings.lang === "it"
                    ? "Non si capisce" : "Cannot understand";
                return;
            }
            calco.risultato = calco.formatta(esito.valore);
            calco.appenaCalcolato = true;
            return;
        }
        // Le cifre e gli operatori.
        if (calco.appenaCalcolato) {
            // Dopo «=», una cifra ricomincia da capo; un operatore
            // continua dal risultato, come su ogni calcolatrice.
            if ("0123456789.π√".indexOf(tasto) !== -1) {
                calco.espressione = tasto;
            } else if (calco.risultato !== "") {
                calco.espressione = calco.risultato + " " + tasto;
            }
            calco.risultato = "";
            calco.appenaCalcolato = false;
            return;
        }
        calco.espressione += tasto;
    }

    // ── La tastiera della finestra ────────────────────────────────────

    Shortcut { sequence: "0"; onActivated: calco.premi("0") }
    Shortcut { sequence: "1"; onActivated: calco.premi("1") }
    Shortcut { sequence: "2"; onActivated: calco.premi("2") }
    Shortcut { sequence: "3"; onActivated: calco.premi("3") }
    Shortcut { sequence: "4"; onActivated: calco.premi("4") }
    Shortcut { sequence: "5"; onActivated: calco.premi("5") }
    Shortcut { sequence: "6"; onActivated: calco.premi("6") }
    Shortcut { sequence: "7"; onActivated: calco.premi("7") }
    Shortcut { sequence: "8"; onActivated: calco.premi("8") }
    Shortcut { sequence: "9"; onActivated: calco.premi("9") }
    Shortcut { sequence: "+"; onActivated: calco.premi(" + ") }
    Shortcut { sequence: "-"; onActivated: calco.premi(" − ") }
    Shortcut { sequence: "*"; onActivated: calco.premi(" × ") }
    Shortcut { sequence: "/"; onActivated: calco.premi(" ÷ ") }
    Shortcut { sequence: "."; onActivated: calco.premi(".") }
    Shortcut { sequence: "("; onActivated: calco.premi("(") }
    Shortcut { sequence: ")"; onActivated: calco.premi(")") }
    Shortcut { sequence: "Return"; onActivated: calco.premi("=") }
    Shortcut { sequence: "Enter"; onActivated: calco.premi("=") }
    Shortcut { sequence: "Backspace"; onActivated: calco.premi("⌫") }
    Shortcut { sequence: "Escape"; onActivated: calco.premi("C") }
    Shortcut { sequence: "%"; onActivated: calco.premi(" ÷ 100 × ") }
    Shortcut { sequence: "Ctrl+L"; onActivated: calco.premi("MC") }
    Shortcut { sequence: "Ctrl+R"; onActivated: calco.premi("MR") }
    Shortcut { sequence: "Ctrl+P"; onActivated: calco.premi("M+") }
    Shortcut { sequence: "Ctrl+Q"; onActivated: calco.premi("M−") }

    // ── Il viso ───────────────────────────────────────────────────────

    Ui.WindowTitleBar {
        id: titolo
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: calco.title
        // Qui c'era `calco.onClosed`, cioè LEGGERE il gestore invece di
        // chiudere: un'espressione che vale il gestore stesso, e la si butta
        // via. Non chiudeva niente, e non si vedeva perché le barre del
        // titolo di Giacomo le disegna il compositore — questa barra qui
        // dentro non compare mai.
        onCloseRequested: calco.requestClose()
    }

    // Un Item e non una Column: dentro ci sono un riquadro e uno
    // scorrimento ancorati a mano, e una Column con ancore dentro
    // smette di funzionare — il compilatore lo dice, i tasti lo
    // pagano.
    Item {
        anchors.top: titolo.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space3

        // Il display: sopra l'espressione, sotto il risultato. Il fondo
        // è OPACO di proposito: è uno schermo, non un vetro — il testo
        // deve reggersi da solo, non lottare con lo sfondo che ci passa
        // dietro.
        Item {
            // Largo quanto la tastiera, non quanto la finestra. Allargando
            // molto la calcolatrice i tasti si fermano a una misura
            // sensata e si centrano; uno schermo che invece continuasse
            // fino ai bordi farebbe sembrare la tastiera un ritaglio
            // rimasto in mezzo, invece che un oggetto solo.
            x: tastiera.orloX
            width: tastiera.grigliaW
            height: 74

            Rectangle {
                anchors.fill: parent
                radius: Theme.Effects.radiusSM
                color: Theme.Colors.base
                border.width: 1
                border.color: Theme.Colors.edge
            }

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: Theme.Effects.space2
                visible: calco.memoriaAttiva
                text: "M"
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: Theme.Effects.space2
                width: parent.width - Theme.Effects.space4
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: calco.espressione
                color: calco.errore !== "" ? Theme.Colors.danger
                                            : Theme.Colors.textMuted
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Theme.Effects.space2
                width: parent.width - Theme.Effects.space4
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: calco.errore !== "" ? calco.errore : calco.risultato
                color: Theme.Colors.text
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXL
                font.weight: Theme.Typography.weightLight
            }
        }

        // ── I tasti ──────────────────────────────────────────────────
        //
        // La cella si calcola dallo SPAZIO DISPONIBILE, non dalla griglia.
        // Il commento che stava qui temeva l'anello — «una cella calcolata
        // dalla griglia stessa è la strada per una griglia che si impila»
        // — e il timore era fondato: chiedere la misura a ciò che quella
        // misura la riceve non converge. Ma l'anello si toglie cambiando
        // interlocutore, non congelando i numeri. `tastiera` è ancorata ai
        // quattro lati: la sua larghezza discende dalla finestra e non dai
        // tasti, quindi non c'è nessun giro da chiudere.
        //
        // ── Perché metà dei tasti stava fuori dalla finestra ──────────
        //
        // Prima c'era una `Grid`, e una `Grid` dà a OGNI colonna la
        // larghezza del figlio più largo. «=» era dichiarato 148 perché
        // «da solo deve stare largo come due»; così tutte e quattro le
        // colonne diventavano 148, e la griglia
        //
        //     4 × 148 + 3 × 8 = 616 pixel
        //
        // stava centrata dentro un'area larga 296. Centosessanta pixel
        // tagliati per parte: la prima colonna (MC, C, 7, 4, 1, √, «(») e
        // l'ultima (M−, ÷, ×, −, +, =, x²) finivano fuori dalla finestra.
        // E il `Flickable` che le conteneva non dichiarava `contentWidth`,
        // quindi non ci si poteva nemmeno scorrere sopra: non invisibili,
        // irraggiungibili.
        //
        // Il tasto largo due è sparito, e non per pigrizia: **ventotto
        // tasti in sette righe da quattro fanno esattamente ventotto
        // celle.** Qualunque tasto largo due ne caccia via un altro. «=»
        // si distingue dal colore — l'accento — e un colore si riconosce
        // da più lontano di una larghezza doppia.
        Item {
            id: tastiera
            anchors.top: parent.top
            anchors.topMargin: 74 + Theme.Effects.space2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            readonly property int colonne: 4
            readonly property int righe: 7
            readonly property int passo: Theme.Effects.space2

            /// Il lato di una cella. Cresce con la finestra e a un certo
            /// punto si ferma: oltre una misura un tasto non si preme
            /// meglio, si spreca soltanto. Da lì in poi la tastiera resta
            /// della sua misura e si centra nello spazio che avanza.
            ///
            /// Il minimo non è una precauzione teorica: è la rete per il
            /// caso in cui il compositore imponga una finestra più piccola
            /// di `minimumSize`. Meglio ventotto tasti stretti che sette
            /// fuori dallo schermo.
            readonly property real cellW: Math.max(38, Math.min(132,
                (tastiera.width - (tastiera.colonne - 1) * tastiera.passo)
                / tastiera.colonne))
            readonly property real cellH: Math.max(30, Math.min(84,
                (tastiera.height - (tastiera.righe - 1) * tastiera.passo)
                / tastiera.righe))

            readonly property real grigliaW: tastiera.cellW * tastiera.colonne
                                   + tastiera.passo * (tastiera.colonne - 1)
            readonly property real grigliaH: tastiera.cellH * tastiera.righe
                                   + tastiera.passo * (tastiera.righe - 1)

            readonly property real orloX: Math.max(0, (tastiera.width - tastiera.grigliaW) / 2)
            readonly property real orloY: Math.max(0, (tastiera.height - tastiera.grigliaH) / 2)

            Repeater {
                // Sette righe da quattro, come su KCalc: le operazioni in
                // colonna a destra, le cifre in basso, «=» in fondo a
                // destra. Ogni tasto ha il suo posto e non balla mai.
                model: [
                    { "t": "MC", "tipo": "memoria" },
                    { "t": "MR", "tipo": "memoria" },
                    { "t": "M+", "tipo": "memoria" },
                    { "t": "M−", "tipo": "memoria" },
                    { "t": "C",  "tipo": "azione" },
                    { "t": "⌫",  "tipo": "azione" },
                    { "t": "%",  "tipo": "azione" },
                    { "t": "÷",  "tipo": "operatore" },
                    { "t": "7",  "tipo": "cifra" },
                    { "t": "8",  "tipo": "cifra" },
                    { "t": "9",  "tipo": "cifra" },
                    { "t": "×",  "tipo": "operatore" },
                    { "t": "4",  "tipo": "cifra" },
                    { "t": "5",  "tipo": "cifra" },
                    { "t": "6",  "tipo": "cifra" },
                    { "t": "−",  "tipo": "operatore" },
                    { "t": "1",  "tipo": "cifra" },
                    { "t": "2",  "tipo": "cifra" },
                    { "t": "3",  "tipo": "cifra" },
                    { "t": "+",  "tipo": "operatore" },
                    { "t": "√",  "tipo": "azione" },
                    { "t": "0",  "tipo": "cifra" },
                    { "t": ".",  "tipo": "cifra" },
                    { "t": "=",  "tipo": "uguale" },
                    { "t": "(",  "tipo": "azione" },
                    { "t": ")",  "tipo": "azione" },
                    { "t": "π",  "tipo": "azione" },
                    { "t": "x²", "tipo": "azione" }
                ]

                delegate: Rectangle {
                    id: tasto
                    required property var modelData
                    required property int index

                    readonly property string etichetta: tasto.modelData.t
                    readonly property bool memoria: tasto.modelData.tipo === "memoria"
                    readonly property bool operatore: tasto.modelData.tipo === "operatore"
                    readonly property bool uguale: tasto.modelData.tipo === "uguale"
                    readonly property bool cifra: tasto.modelData.tipo === "cifra"

                    x: tastiera.orloX + (tasto.index % tastiera.colonne)
                                      * (tastiera.cellW + tastiera.passo)
                    y: tastiera.orloY + Math.floor(tasto.index / tastiera.colonne)
                                      * (tastiera.cellH + tastiera.passo)
                    width: tastiera.cellW
                    height: tastiera.cellH
                    radius: Theme.Effects.radiusSM

                    color: tasto.uguale
                           ? (sopra.containsMouse ? Qt.lighter(Theme.Colors.accent, 1.15)
                                                  : Theme.Colors.accent)
                           : tasto.operatore || tasto.memoria
                           ? (sopra.containsMouse ? Theme.Colors.hover
                                                  : Theme.Colors.raised)
                           : sopra.containsMouse ? Theme.Colors.hover
                                                 : Theme.Colors.sunken
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        anchors.centerIn: parent
                        text: tasto.etichetta
                        color: tasto.uguale ? Theme.Colors.textOnAccent
                             : tasto.operatore ? Theme.Colors.accent
                             : tasto.memoria ? Theme.Colors.textMuted
                                             : Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        // Il corpo segue la cella, con due gradini come
                        // prima: le operazioni e «=» più grandi delle
                        // cifre, perché sono i tasti che si cercano.
                        font.pixelSize: tasto.operatore || tasto.uguale
                            ? Math.max(15, Math.min(30, Math.round(tastiera.cellH * 0.45)))
                            : Math.max(12, Math.min(24, Math.round(tastiera.cellH * 0.36)))
                    }

                    MouseArea {
                        id: sopra
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var e = tasto.etichetta;
                            if (e === "÷") calco.premi(" ÷ ");
                            else if (e === "×") calco.premi(" × ");
                            else if (e === "−") calco.premi(" − ");
                            else if (e === "+") calco.premi(" + ");
                            else if (e === "%") calco.premi(" ÷ 100 × ");
                            else if (e === "√") calco.premi("√");
                            else if (e === "x²") calco.premi("²");
                            else if (e === "1/x") calco.premi("⁻¹");
                            else if (e === "π") calco.premi("π");
                            else calco.premi(e);
                        }
                    }
                }
            }
        }
    }
}
