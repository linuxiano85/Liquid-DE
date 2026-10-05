import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Terminale — Il terminale di Minerva.
//
// ── Cosa c'è, adesso (tappa 1) ─────────────────────────────────────────────
//
// Una finestra con le schede, ognuna con la sua shell in uno pseudo-terminale
// vero: `vim`, `htop`, `less`, i colori a 24 bit, il mouse ai programmi che
// lo chiedono, lo scrollback con la rotella e Shift+Pagina, la selezione col
// mouse che copia, il tasto centrale che incolla. Il vetro e la sfocatura
// vengono dal compositore come per ogni altra finestra di Minerva.
//
// ── Cosa arriva dopo, e sta scritto nel piano ──────────────────────────────
//
// I blocchi con la riga di comando nostra e la predizione (tappa 2), la
// Palestra per imparare i comandi (tappa 3), la personalizzazione da dentro
// (tappa 4). Questa tappa è la base: un terminale che funziona, provato con
// i numeri (`emulatore_test.dart`) e con le fotografie.
//
// ── Come è fatto ───────────────────────────────────────────────────────────
//
//     Terminale (questa finestra)
//       └ Sessione, una per scheda: il processo del motore + la Griglia
//           └ minerva-terminale-motore (Dart) → minerva-pty (C) → la shell
//
// Il perché di tre pezzi sta in cima a `minervad/lib/terminale/motore.dart`.
FloatingWindow {
    id: terminale

    visible: Core.Ipc.prontoADipingere && !terminale.dormiente
    property bool dormiente: false

    readonly property bool it: Core.Strings.lang === "it"

    // Il colore della finestra, e non un rettangolo sopra una finestra
    // trasparente: col disegno a processore il secondo strato costa
    // quindici megabyte (misurato sull'Editor).
    color: Theme.Colors.window
    implicitWidth: 960
    implicitHeight: 620

    signal requestClose()
    onClosed: terminale.requestClose()

    /// Dove sta Minerva sul disco: da `shellDir` (la cartella di app.qml)
    /// la radice è quella sopra. Serve per trovare il motore.
    readonly property string radice: {
        var dir = String(Quickshell.shellDir);
        if (dir.indexOf("file://") === 0) dir = dir.substring(7);
        var cut = dir.lastIndexOf("/");
        return cut > 0 ? dir.substring(0, cut) : dir;
    }

    /// La cartella e il comando con cui aprire la PRIMA scheda: li passa
    /// `scripts/minerva-terminale` attraverso `app.qml` (`addTab`).
    property string cartellaIniziale: ""
    property string comandoIniziale: ""

    // `id: tav` e non `tavolozza`: dentro `Sessione` la riga
    // `tavolozza: tavolozza` risolveva il nome a DESTRA nella proprietà
    // stessa — cioè a null — e la griglia non disegnava niente, senza un
    // avviso. È l'ombra dei nomi di QML, e si prende solo guardando.
    Tavolozza {
        id: tav
        nome: String(Core.Ipc.get("terminale.tavolozza", "minerva") || "minerva")
    }

    // ── Le schede ────────────────────────────────────────────────────────
    ListModel { id: schede }
    property int schedaAttiva: 0
    readonly property int maxSchede: 12

    /// `app.qml` chiama questa per aprire: con un percorso apre lì, con
    /// `esegui://cmd` lancia il comando, senza niente apre la shell a casa.
    ///
    /// ── La prima scheda automatica si lascia sostituire ─────────────────
    ///
    /// Appena costruita, la finestra apre una scheda a casa da sola (così
    /// una tenuta pronta ha già una shell viva). Se la PRIMA apertura vera
    /// arriva con una cartella o un comando, quella scheda automatica se ne
    /// va: chi ha chiesto «apri nel terminale qui» vuole una scheda, non due.
    property bool primaAutomatica: false

    function addTab(argomento) {
        var cartella = "", comando = "";
        var a = String(argomento || "");
        if (a.indexOf("esegui://") === 0) {
            comando = a.substring(9);
        } else if (a !== "") {
            cartella = a;
        }
        var sostituisci = terminale.primaAutomatica && a !== "" && schede.count === 1;
        terminale.primaAutomatica = false;
        if (a === "" && schede.count > 0)
            return;
        terminale.nuovaScheda(cartella, comando);
        if (sostituisci)
            terminale.chiudiScheda(0);
    }

    function nuovaScheda(cartella, comando) {
        if (schede.count >= terminale.maxSchede) return;
        // Una scheda nuova parte dalla cartella di quella attiva: è quello che
        // uno vuole nove volte su dieci, e la decima cambia cartella.
        if ((cartella === undefined || cartella === "") && schede.count > 0) {
            var s = terminale.sessioneA(terminale.schedaAttiva);
            if (s && s.cartellaAdesso !== "") cartella = s.cartellaAdesso;
        }
        schede.append({ "cartella": cartella || "", "comando": comando || "",
                        "titolo": "", "chiusa": false, "codice": 0, "avvisa": false });
        terminale.schedaAttiva = schede.count - 1;
        Qt.callLater(function () {
            var s = terminale.sessioneA(terminale.schedaAttiva);
            if (s) s.prendiFuoco();
        });
    }

    function chiudiScheda(i) {
        if (i < 0 || i >= schede.count) return;
        schede.remove(i);
        if (schede.count === 0) {
            terminale.requestClose();
            return;
        }
        if (terminale.schedaAttiva >= schede.count)
            terminale.schedaAttiva = schede.count - 1;
        Qt.callLater(function () {
            var s = terminale.sessioneA(terminale.schedaAttiva);
            if (s) s.prendiFuoco();
        });
    }

    function sessioneA(i) {
        var it = elenco.itemAt(i);
        return it ? it.sessione : null;
    }

    function titoloDi(i) {
        if (i < 0 || i >= schede.count) return "";
        var t = schede.get(i).titolo;
        if (t === "") return terminale.it ? "Terminale" : "Terminal";
        return t;
    }

    // «Minerva · Terminale — …» sempre con quel prefisso: è così che la dock
    // riconosce la finestra (`core/Apps.qml`, `prefissi`). Il titolo della
    // shell — la cartella, il programma in corso — viene dopo il trattino.
    title: {
        var base = terminale.it ? "Minerva · Terminale" : "Minerva · Terminal";
        if (schede.count === 0 || terminale.schedaAttiva >= schede.count) return base;
        var t = schede.get(terminale.schedaAttiva).titolo;
        return t === "" ? base : base + " — " + t;
    }

    Component.onCompleted: {
        if (schede.count === 0) {
            terminale.nuovaScheda(terminale.cartellaIniziale, terminale.comandoIniziale);
            terminale.primaAutomatica = true;
        }
    }

    Ui.WindowTitleBar {
        id: barra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: terminale.title
        onCloseRequested: terminale.requestClose()
    }

    // ── La striscia delle schede: c'è solo quando servono ────────────────
    Rectangle {
        id: striscia
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: schede.count > 1 ? 34 : 0
        visible: schede.count > 1
        color: Theme.Colors.membrane

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.Colors.edge
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            Repeater {
                model: schede
                delegate: Rectangle {
                    id: scheda
                    required property int index
                    required property var model
                    readonly property bool attiva: scheda.index === terminale.schedaAttiva
                    width: Math.min(220, etichetta.implicitWidth + 40)
                    height: 26
                    radius: Theme.Effects.radiusSM
                    color: scheda.attiva ? Theme.Colors.raisedHigh
                         : (schedaMouse.containsMouse ? Theme.Colors.hover : "transparent")
                    border.width: scheda.attiva ? 1 : 0
                    border.color: Theme.Colors.edge
                    onAttivaChanged: if (scheda.attiva && scheda.model.avvisa) schede.setProperty(scheda.index, "avvisa", false);

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: Theme.Colors.accent
                        visible: scheda.model.avvisa === true
                    }

                    Text {
                        textFormat: Text.PlainText
                        id: etichetta
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.right: chiudi.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: terminale.titoloDi(scheda.index)
                        color: scheda.attiva ? Theme.Colors.text : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        elide: Text.ElideRight
                    }

                    Text {
                        id: chiudi
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: "×"
                        color: chiudiMouse.containsMouse ? Theme.Colors.danger : Theme.Colors.textFaint
                        font.pixelSize: Theme.Typography.sizeMD

                        MouseArea {
                            id: chiudiMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: terminale.chiudiScheda(scheda.index)
                        }
                    }

                    MouseArea {
                        id: schedaMouse
                        anchors.fill: parent
                        anchors.rightMargin: 24
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function (e) {
                            if (e.button === Qt.MiddleButton) { terminale.chiudiScheda(scheda.index); return; }
                            terminale.schedaAttiva = scheda.index;
                            var s = terminale.sessioneA(scheda.index);
                            if (s) s.prendiFuoco();
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26
            radius: Theme.Effects.radiusSM
            color: piuMouse.containsMouse ? Theme.Colors.hover : "transparent"
            Text {
                anchors.centerIn: parent
                text: "+"
                color: Theme.Colors.textMuted
                font.pixelSize: Theme.Typography.sizeMD
            }
            MouseArea {
                id: piuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: terminale.nuovaScheda("", "")
            }
        }
    }

    // ── Le sessioni ──────────────────────────────────────────────────────
    //
    // Tutte istanziate, una sola visibile: una scheda nascosta continua a
    // ricevere l'uscita della sua shell, come deve. Un `Loader` che le
    // scaricasse fermerebbe il programma dentro.
    Item {
        id: corpo
        anchors.top: striscia.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Repeater {
            id: elenco
            model: schede
            delegate: Item {
                id: cella
                required property int index
                required property var model
                readonly property alias sessione: s
                anchors.fill: parent
                visible: cella.index === terminale.schedaAttiva

                Sessione {
                    id: s
                    anchors.fill: parent
                    radice: terminale.radice
                    cartella: cella.model.cartella
                    esegui: cella.model.comando
                    tavolozza: tav
                    onTitoloCambiato: function (t) { schede.setProperty(cella.index, "titolo", t); }
                    // Il campanello di una scheda che non si guarda accende
                    // un puntino sulla sua linguetta, finché non la si apre.
                    onCampanello: {
                        if (cella.index !== terminale.schedaAttiva && cella.index < schede.count)
                            schede.setProperty(cella.index, "avvisa", true);
                    }
                    onChiusa: function (codice) {
                        // La shell è uscita: la scheda se ne va. Se era
                        // l'ultima, la finestra si chiude — è quello che fa
                        // `exit` in ogni terminale. Un comando lanciato
                        // apposta (`esegui://`) invece resta, col suo esito,
                        // finché non si preme un tasto: vedi `Sessione`.
                        if (cella.model.comando !== "") return;
                        if (cella.index < schede.count) terminale.chiudiScheda(cella.index);
                    }
                    onCongedo: {
                        if (cella.index < schede.count) terminale.chiudiScheda(cella.index);
                    }
                }
            }
        }
    }

    // ── Le scorciatoie delle schede ──────────────────────────────────────
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: terminale.nuovaScheda("", "") }
    Shortcut { sequence: "Ctrl+Shift+W"; onActivated: terminale.chiudiScheda(terminale.schedaAttiva) }
    Shortcut {
        sequence: "Ctrl+PgDown"
        onActivated: {
            if (schede.count > 1) {
                terminale.schedaAttiva = (terminale.schedaAttiva + 1) % schede.count;
                var s = terminale.sessioneA(terminale.schedaAttiva); if (s) s.prendiFuoco();
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+PgUp"
        onActivated: {
            if (schede.count > 1) {
                terminale.schedaAttiva = (terminale.schedaAttiva + schede.count - 1) % schede.count;
                var s = terminale.sessioneA(terminale.schedaAttiva); if (s) s.prendiFuoco();
            }
        }
    }
}
