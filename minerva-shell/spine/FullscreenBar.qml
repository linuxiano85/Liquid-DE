import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// FullscreenBar — La via d'uscita dallo schermo intero.
//
// A schermo intero Hyprland copre TUTTO: barra di sistema, dock e barre del
// titolo spariscono, perché il livello `top` di layer-shell finisce sotto la
// finestra. Verificato a mano su questa macchina, non dedotto: con una
// finestra a schermo intero la fotografia dello schermo non contiene un solo
// pixel della shell.
//
// Il risultato è che chi ci finisce dentro senza saperlo — e ci si finisce con
// un tasto solo — non ha più niente da cliccare. Deve indovinare la
// scorciatoia, e se non la conosce resta prigioniero della finestra.
//
// Questa barra vive su `overlay`, l'unico livello che una finestra a schermo
// intero non copre, ed è l'unica cosa di Minerva che si vede là dentro. Sta
// nascosta sopra il bordo alto e scende portando il puntatore in cima allo
// schermo, che è il gesto che chiunque prova per primo. Chi la vuole sempre
// visibile la fissa dalle Impostazioni.
PanelWindow {
    id: fs

    /// "hover" (scende avvicinandosi al bordo), "always" (sempre visibile),
    /// "off" (mai).
    property string mode: "hover"

    property int barHeight: 34

    readonly property bool it: Core.Strings.lang === "it"

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // ── E questa resta in cima anche con la barra in fondo ───────────────
    //
    // Sembra una dimenticanza e non lo è. Questa non è la barra di Minerva: è
    // la barra del TITOLO della finestra a schermo intero, cioè la stessa cosa
    // che `spine/TitleBars.qml` disegna sopra ogni altra finestra. Le barre
    // del titolo stanno in cima alla loro finestra, e una finestra a schermo
    // intero ha la cima dove ce l'ha lo schermo.
    //
    // Legarla a `bar.position` vorrebbe dire che spostando la barra della
    // scrivania si sposta anche il titolo delle finestre — due cose diverse
    // che si muovono insieme perché una volta si somigliavano.
    anchors { top: true; left: true; right: true }
    color: "transparent"

    // ── Qual è la finestra a schermo intero ──────────────────────────────

    readonly property int currentWorkspace: Core.Compositore.scrivaniaAttiva

    readonly property var target: {
        var all = Core.Windows.all || [];
        for (var i = 0; i < all.length; i++) {
            var w = all[i];
            if (!w.fullscreen || w.minimized)
                continue;
            if (fs.currentWorkspace >= 0 && w.workspace !== fs.currentWorkspace)
                continue;
            return w;
        }
        return null;
    }

    // ── Montata solo quando serve, sotto il nostro compositore ───────────
    //
    // Per accorgersi del puntatore in cima questa superficie restava montata
    // per tutto il film, con una striscia sensibile di tre pixel. Ma una
    // superficie qualunque sopra la finestra a schermo intero obbliga la
    // scheda video a ricomporre ogni fotogramma: niente scanout diretto
    // (misurato il 23 settembre 2026, lista di disegno da tre elementi
    // invece che da uno). Il bordo alto lo sorveglia il compositore, che
    // vede il puntatore comunque, e lo annuncia (`evento bordoalto`): la
    // barra si monta allora, e si smonta finita la discesa all'indietro.
    // Sotto Hyprland resta com'era: là nessuno lo annuncia.
    readonly property bool soloAlBordo: fs.mode === "hover" && Core.Compositore.nostro

    visible: fs.mode !== "off" && fs.target !== null
             && (!fs.soloAlBordo || fs.revealed || smonta.running)

    Timer {
        id: smonta
        interval: Theme.Motion.panel + 80
    }

    Connections {
        target: Core.Compositore
        function onBordoAlto(schermo) {
            if (!fs.soloAlBordo || fs.target === null)
                return;
            fs.revealed = true;
            // Il puntatore è già in cima, fermo: la superficie nasce sotto di
            // lui e l'«entrata» arriva solo al primo movimento. Se non si
            // muove, la barra non deve restare giù per sempre.
            primoIngresso.restart();
        }
    }

    Timer {
        id: primoIngresso
        interval: 2500
        onTriggered: if (fs.soloAlBordo && !area.containsMouse) fs.revealed = false
    }
    implicitHeight: fs.barHeight + Theme.Effects.space5

    // Hyprland non manda nessun evento quando una finestra entra o esce dallo
    // schermo intero: si guarda ogni tanto. Due secondi bastano — è una cosa
    // che si fa una volta ogni tanto, non dieci volte al secondo.
    //
    // Il nostro compositore invece lo annuncia (`evento stato`, che il demone
    // ascolta e gira come elenco delle finestre): lì questo giro era una
    // sveglia di shell, demone e compositore ogni secondo e mezzo, per tutta
    // la sessione, senza sapere niente di nuovo.
    Timer {
        interval: 1500
        running: !Core.Compositore.nostro
        repeat: true
        onTriggered: Core.Windows.refresh()
    }

    // ── Comparsa ─────────────────────────────────────────────────────────

    property bool revealed: fs.mode === "always"
    onModeChanged: fs.revealed = (fs.mode === "always")

    /// Il suggerimento si dice le prime volte e poi smette. Una istruzione
    /// ripetuta a ogni comparsa passa da aiuto a rimprovero, e chi l'ha
    /// imparata la legge come rumore.
    property int hintsLeft: 3
    readonly property bool showHint: fs.mode === "hover" && fs.revealed && fs.hintsLeft > 0

    onRevealedChanged: {
        if (fs.revealed && fs.mode === "hover" && fs.hintsLeft > 0)
            hintSpent.restart();
        if (!fs.revealed)
            smonta.restart();
    }

    Timer {
        id: hintSpent
        interval: 4000
        onTriggered: if (fs.hintsLeft > 0) fs.hintsLeft -= 1
    }

    Timer {
        id: hideSoon
        interval: 700
        onTriggered: if (fs.mode === "hover" && !area.containsMouse) fs.revealed = false
    }

    // Come per la dock: la maschera segue la geometria a riposo e non il corpo
    // animato. Da nascosta è cliccabile solo una striscia di tre pixel in cima
    // allo schermo; da visibile, tutta la barra.
    //
    // Tre pixel e non di più: da nascosta questa superficie sta sopra un gioco
    // a schermo intero, e ogni pixel che si prende è un pixel in cui il mouse
    // non arriva al gioco. Tre bastano per accorgersi che il puntatore è
    // arrivato in cima, e non si notano mai.
    mask: Region {
        x: 0
        y: 0
        width: fs.width
        height: fs.revealed ? fs.barHeight + Theme.Effects.space2 : 3
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: {
            if (containsMouse) {
                fs.revealed = true;
                hideSoon.stop();
                primoIngresso.stop();
            } else if (fs.mode === "hover") {
                hideSoon.restart();
            }
        }
    }

    // ── La barra ─────────────────────────────────────────────────────────
    //
    // Era una pillola larga quanto il testo, centrata in mezzo allo schermo.
    // Sembrava un cartello di passaggio, e c'erano due cose che non tornavano:
    //
    //  · con un titolo corto era un francobollo in mezzo a duemila pixel di
    //    niente, e i pulsanti finivano dove capitava — da qualche parte al
    //    centro, diversa ogni volta a seconda di quanto era lungo il nome;
    //  · scendendo copriva una striscia di gioco o di filmato PROPRIO al
    //    centro, che è dove si sta guardando.
    //
    // Larga tutto invece è una barra: i pulsanti stanno sempre nello stesso
    // posto — all'estremità destra, dove stanno in ogni finestra — e quello
    // che copre è il bordo alto, che in un filmato è nero e in un gioco è
    // l'ultima cosa che si guarda.
    //
    // Chiesta da Giacomo l'11 agosto: «quella piccola barra del titolo che
    // compare la vorrei per tutta la larghezza, non per un pezzettino».
    Rectangle {
        id: pill

        x: 0
        y: fs.revealed ? 0 : -fs.barHeight - 4
        width: fs.width
        height: fs.barHeight

        // Nessun angolo tondo e nessun bordo attorno: una barra attaccata al
        // bordo dello schermo non ha angoli da arrotondare, e una cornice
        // tutt'intorno la farebbe sembrare di nuovo un riquadro appoggiato.
        // Resta la sola riga sotto, che è quella che la stacca da ciò che
        // copre.
        radius: 0
        color: Theme.Colors.membrane

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.alpha(Theme.Colors.accent, 0.35)
        }

        Behavior on y {
            NumberAnimation {
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.emerge
            }
        }

        // ── A sinistra chi sei, a destra cosa puoi fare ──────────────────
        //
        // Con la pillola stretta tutto stava in mezzo, incolonnato: era
        // l'unico posto che c'era. Larga tutto, incolonnare al centro sarebbe
        // una scelta e sarebbe quella sbagliata — i pulsanti finirebbero in un
        // punto diverso a ogni finestra, a seconda di quanto è lungo il nome.
        //
        // Nome a sinistra, comandi a destra: è dove stanno in ogni barra del
        // titolo di ogni finestra, compresa la nostra. La mano ci va senza
        // guardare.
        Row {
            id: content
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: comandi.left
            anchors.rightMargin: Theme.Effects.space3
            spacing: Theme.Effects.space2

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                source: {
                    var a = Core.Apps.forWindow(fs.target);
                    return (a && a.icon) ? "file://" + a.icon : "";
                }
                sourceSize.width: 32
                sourceSize.height: 32
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
                visible: status === Image.Ready
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Prende lo spazio che resta fra l'icona e i comandi: un
                // titolo lungo si accorcia invece di spingere via i pulsanti.
                width: Math.max(0, content.width - 16 - Theme.Effects.space2 * 2)
                elide: Text.ElideRight
                text: fs.target ? (fs.target.title || fs.target.appClass) : ""
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }

        }

        Row {
            id: comandi
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            // ── «Esci dallo schermo intero», scritto per esteso ──────────
            //
            // Era un'icona fra tre, senza nome: Giacomo, 25 settembre 2026,
            // «vedo scritto qualcosa che spiega come portarlo allo stato
            // normale ma non capisco come». La cosa che si cerca quassù è
            // proprio questa, e si scrive con le parole.
            Rectangle {
                id: esci
                anchors.verticalCenter: parent.verticalCenter
                height: fs.barHeight - 8
                width: esciRiga.implicitWidth + 2 * Theme.Effects.space3
                radius: height / 2
                color: esciMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.30)
                                               : Qt.alpha(Theme.Colors.accent, 0.16)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.45)
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                Row {
                    id: esciRiga
                    anchors.centerIn: parent
                    spacing: Theme.Effects.space2
                    Ui.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        name: "restore"
                        color: Theme.Colors.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: fs.it ? "Esci dallo schermo intero" : "Leave fullscreen"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }
                }
                MouseArea {
                    id: esciMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fs.run("restore")
                }
            }

            Repeater {
                model: [
                    { "id": "minimize", "icon": "minimize",
                      "it": "Riduci a icona", "en": "Minimise", "danger": false },
                    { "id": "close",    "icon": "close",
                      "it": "Chiudi", "en": "Close", "danger": true }
                ]

                delegate: Rectangle {
                    id: ctl
                    required property var modelData

                    anchors.verticalCenter: parent.verticalCenter
                    width: fs.barHeight - 10
                    height: fs.barHeight - 10
                    radius: Theme.Effects.radiusXS
                    color: ctlMouse.containsMouse
                           ? (ctl.modelData.danger ? Qt.alpha(Theme.Colors.danger, 0.28)
                                                   : Theme.Colors.hover)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 14; height: 14
                        name: ctl.modelData.icon
                        color: ctlMouse.containsMouse
                               ? (ctl.modelData.danger ? Theme.Colors.danger
                                                       : Theme.Colors.text)
                               : Theme.Colors.textMuted
                    }

                    MouseArea {
                        id: ctlMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fs.run(ctl.modelData.id)
                    }
                }
            }
        }

        // Il nome del comando sotto il pulsante puntato. A schermo intero non
        // c'è nient'altro da guardare: vale la pena scriverlo per esteso.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 4
            // Prima diceva «Torna indietro portando il puntatore quassù»: voleva
            // dire «questa barra ricompare quassù», e si leggeva come il modo di
            // uscire dallo schermo intero — che invece non era scritto da
            // nessuna parte.
            text: fs.it ? "Per uscire: il pulsante qui sopra, oppure Super+↓  ·  Questa barra torna tenendo Super e portando il puntatore in cima"
                        : "To leave: the button above, or Super+↓  ·  This bar comes back holding Super with the pointer at the top"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
            visible: fs.showHint && opacity > 0
            opacity: fs.showHint ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
        }
    }

    // ── Comandi ──────────────────────────────────────────────────────────

    function run(id) {
        if (!fs.target)
            return;
        var a = fs.target.address;
        switch (id) {
        case "restore":
            // `fullscreenstate` e non `fullscreen`: il secondo agisce sulla
            // finestra attiva e basta, e da qui la finestra attiva potrebbe
            // essere un'altra. Due zeri: si azzera sia lo stato deciso dal
            // compositore sia quello chiesto dal programma, altrimenti un
            // riproduttore video ci rientra da solo un istante dopo.
            Core.Compositore.schermoIntero(a, false);
            break;
        case "minimize":
            Core.Compositore.schermoIntero(a, false);
            Core.Windows.minimize(a);
            break;
        case "close":
            Core.Windows.close(a);
            break;
        }
        Core.Windows.refresh();
    }
}
