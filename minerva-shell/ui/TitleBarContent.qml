import QtQuick
import "../theme" as Theme
import "../core" as Core

// TitleBarContent — Quello che c'è DENTRO una barra del titolo.
//
// Solo il contenuto: icona, titolo, pulsanti. Non disegna nessuno sfondo e non
// gestisce nessun trascinamento, e non è una svista.
//
// Lo usa `ui/WindowTitleBar.qml`, la barra dentro le NOSTRE finestre, che fa
// parte della finestra stessa: stessa superficie, stesso vetro. Le barre
// delle finestre altrui le disegna il compositore (`compositore/src/barra.c`)
// con gli stessi colori e la stessa altezza, che gli manda
// `Compositore.aspettoBarra`.
Item {
    id: content

    /// Il titolo, al centro.
    property string label: ""
    property color foreground: Theme.Colors.text
    property color mutedForeground: Theme.Colors.textMuted
    property color faintForeground: Theme.Colors.textFaint
    property string fontFamily: Theme.Typography.fontDisplay
    /// Percorso dell'icona del programma, o vuoto.
    property string iconPath: ""
    /// Vero per la finestra con cui si sta lavorando.
    property bool active: true
    /// Da che parte stanno i pulsanti: "destra" o "sinistra".
    property string side: "destra"
    /// Vero quando la finestra è già ingrandita: cambia il segno del pulsante.
    property bool maximized: false
    /// Vero quando è a schermo intero.
    property bool fullscreen: false
    /// Pulsanti come Windows 11: tre rettangoli da 46 pixel attaccati
    /// all'angolo destro, «chiudi» rosso sotto il puntatore, niente schermo
    /// intero (resta Super+F). Gli stessi della barra del compositore
    /// (`compositore/src/barra.h`, «Lo stile dei pulsanti»).
    property bool stileWindows: false

    signal minimizeRequested()
    signal maximizeRequested()
    signal fullscreenRequested()
    signal closeRequested()

    readonly property int side_: 6

    implicitHeight: 34

    // ── I pulsanti ───────────────────────────────────────────────────────
    //
    // Quattro e non tre. «Ingrandisci» e «schermo intero» sono due cose
    // diverse e su Minerva lo si vede: ingrandire ferma la finestra sotto la
    // barra della scrivania — resta un ambiente, con l'orologio e le icone di
    // stato al loro posto — mentre schermo intero copre tutto, barra
    // compresa, ed è quello che serve a un video o a una presentazione.
    // Averne uno solo vuol dire non poter fare una delle due.

    readonly property var buttons: [
        { "id": "minimize",   "icon": "minimize", "danger": false,
          "it": "Riduci a icona",  "en": "Minimise" },
        { "id": "maximize",   "icon": content.maximized ? "restore" : "maximize",
          "danger": false,
          "it": content.maximized ? "Ripristina" : "Ingrandisci",
          "en": content.maximized ? "Restore" : "Maximise" },
        { "id": "fullscreen", "icon": content.fullscreen ? "collapse" : "expand",
          "danger": false,
          "it": content.fullscreen ? "Esci da schermo intero" : "Schermo intero",
          "en": content.fullscreen ? "Leave full screen" : "Full screen" },
        { "id": "close",      "icon": "close",    "danger": true,
          "it": "Chiudi",          "en": "Close" }
    ]

    function fire(id) {
        switch (id) {
        case "minimize":   content.minimizeRequested();   break;
        case "maximize":   content.maximizeRequested();   break;
        case "fullscreen": content.fullscreenRequested(); break;
        case "close":      content.closeRequested();      break;
        }
    }

    /// I pulsanti che si vedono: in stile Windows senza lo schermo intero.
    readonly property var visibleButtons: content.stileWindows
        ? content.buttons.filter(function(b) { return b.id !== "fullscreen"; })
        : content.buttons

    /// In stile Windows i pulsanti stanno sempre a destra; il lato scelto
    /// resta salvato per gli altri preset.
    readonly property bool buttonsLeft: content.side === "sinistra" && !content.stileWindows

    /// Larghezza di un pulsante in stile Windows.
    readonly property int windowsButtonWidth: 46

    // ── PERCHÉ `x` E NON DUE ANCORE A TURNO ──────────────────────────────
    //
    // Qui c'erano quattro ancore accese e spente da un ternario:
    //
    //     anchors.right: buttonsLeft ? undefined : parent.right
    //     anchors.left:  buttonsLeft ? parent.left : undefined
    //
    // Sembra la cosa naturale e non funziona nel verso del ritorno.
    // Assegnare `undefined` a una linea d'ancoraggio NON la stacca: l'ancora
    // messa prima resta attaccata. Passando «a sinistra» e poi di nuovo «a
    // destra», i pulsanti restavano incollati a sinistra per sempre.
    //
    // Segnalato da il manutentore il 18 agosto 2026: «se imposti i pulsanti a
    // sinistra compaiono parecchi bug e anche se li rimetti a posto non si
    // tolgono, devi riavviare la sessione». Riprodotto in tre clic e
    // fotografato: i pulsanti tornavano nell'ordine di destra ma restavano
    // ancorati a sinistra, l'icona finiva in mezzo alla barra e il titolo
    // spariva del tutto — perché la sua larghezza si calcola da quella dei
    // pulsanti, e con le ancore in contraddizione veniva zero.
    //
    // Il riavvio della sessione «riparava» perché ricostruiva le barre da
    // capo, cioè con una sola ancora messa una volta sola.
    //
    // La regola generale, che vale per tutta Minerva: **un lato che può
    // cambiare non si esprime con le ancore.** O si usa `AnchorChanges` in
    // uno stato, o — come qui — si scrive la posizione, che è una sola
    // proprietà e non ha memoria di quella di prima.

    Row {
        id: controls
        // In stile Windows attaccati all'angolo, senza margine.
        x: content.stileWindows
           ? Math.max(0, content.width - width)
           : content.buttonsLeft
             ? content.side_
             : Math.max(0, content.width - width - content.side_)
        anchors.verticalCenter: parent.verticalCenter
        spacing: content.stileWindows ? 0 : 2

        Repeater {
            // A sinistra l'ordine si specchia: il pulsante che chiude resta
            // quello all'estremità, come su qualunque finestra di macOS.
            model: content.buttonsLeft
                   ? content.visibleButtons.slice().reverse()
                   : content.visibleButtons

            delegate: Rectangle {
                id: ctl
                required property var modelData

                objectName: "titleButton-" + ctl.modelData.id
                width: content.stileWindows ? content.windowsButtonWidth : content.height - 10
                height: content.stileWindows ? content.height : content.height - 10
                radius: content.stileWindows ? 0 : Theme.Effects.radiusXS
                color: content.stileWindows ? ctl.coloreWindows
                       : ctlMouse.containsMouse
                         ? (ctl.modelData.danger
                            ? Qt.alpha(Theme.Colors.danger, 0.30)
                            : Theme.Colors.hover)
                         : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // Windows: il fondo pieno al passaggio e alla pressione. Per
                // «chiudi» il rosso #C42B1C (premuto, appena più trasparente);
                // per gli altri il colore del testo appena accennato, come il
                // «SubtleFill» di Windows, che vale in chiaro e in scuro.
                readonly property color coloreWindows: {
                    if (!ctlMouse.containsMouse && !ctlMouse.pressed)
                        return "transparent";
                    if (ctl.modelData.danger)
                        return ctlMouse.pressed ? Qt.rgba(0.769, 0.169, 0.110, 0.9)
                                                : Qt.rgba(0.769, 0.169, 0.110, 1);
                    return Qt.alpha(content.foreground, ctlMouse.pressed ? 0.05 : 0.08);
                }
                // Il segno: bianco sul rosso, altrimenti il testo della barra,
                // velato quando la finestra non è attiva.
                readonly property color segnoWindows: ctl.modelData.danger
                                                      && (ctlMouse.containsMouse || ctlMouse.pressed)
                    ? "white"
                    : (content.active ? content.foreground : content.faintForeground)

                Canvas {
                    id: segno
                    objectName: "titleGlyph-" + ctl.modelData.id
                    visible: content.stileWindows
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    readonly property color tinta: ctl.segnoWindows
                    readonly property string forma: ctl.modelData.icon
                    onTintaChanged: requestPaint()
                    onFormaChanged: requestPaint()
                    onVisibleChanged: requestPaint()

                    // Le stesse forme di `segno_windows` nel compositore: un
                    // quadrato di dieci pixel, tratto di uno, sulla griglia.
                    onPaint: {
                        var g = getContext("2d");
                        g.reset();
                        g.strokeStyle = segno.tinta;
                        g.lineWidth = 1;
                        var x = 1.5;
                        var y = 1.5;
                        var S = 10;
                        g.beginPath();
                        if (segno.forma === "minimize") {
                            g.moveTo(x, y + S / 2);
                            g.lineTo(x + S - 1, y + S / 2);
                        } else if (segno.forma === "maximize") {
                            g.roundedRect(x, y, S - 1, S - 1, 1, 1);
                        } else if (segno.forma === "restore") {
                            var D = 2;
                            g.rect(x, y + D, S - 1 - D, S - 1 - D);
                            g.moveTo(x + D, y + D);
                            g.lineTo(x + D, y);
                            g.lineTo(x + S - 1, y);
                            g.lineTo(x + S - 1, y + S - 1 - D);
                            g.lineTo(x + S - 1 - D, y + S - 1 - D);
                        } else if (segno.forma === "close") {
                            g.moveTo(x - 0.5, y - 0.5);
                            g.lineTo(x + S - 0.5, y + S - 0.5);
                            g.moveTo(x + S - 0.5, y - 0.5);
                            g.lineTo(x - 0.5, y + S - 0.5);
                        }
                        g.stroke();
                    }
                }

                Icon {
                    visible: !content.stileWindows
                    anchors.centerIn: parent
                    width: 13; height: 13
                    name: ctl.modelData.icon
                    // I comandi della finestra restano SEMPRE disegnati da
                    // noi anche con le icone classiche: nei temi
                    // `window-maximize` è una freccia in su e
                    // `window-restore` un rombo, e su una barra del titolo
                    // non dicono più quello che fanno.
                    alwaysDrawn: true
                    color: ctlMouse.containsMouse
                           ? (ctl.modelData.danger ? Theme.Colors.danger
                                                   : content.foreground)
                           : (content.active ? content.mutedForeground
                                             : content.faintForeground)
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                }

                MouseArea {
                    id: ctlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // In Windows i pulsanti della barra hanno la freccia.
                    cursorShape: content.stileWindows ? Qt.ArrowCursor : Qt.PointingHandCursor
                    // I pulsanti non devono far partire un trascinamento:
                    // premendo «chiudi» e muovendo di due pixel la finestra
                    // partiva dietro al puntatore.
                    onClicked: content.fire(ctl.modelData.id)
                }

                ToolTipHint {
                    text: Core.Strings.lang === "it" ? ctl.modelData.it
                                                     : ctl.modelData.en
                    shown: ctlMouse.containsMouse
                }
            }
        }
    }

    // ── L'icona del programma ────────────────────────────────────────────
    //
    // Dalla parte opposta ai pulsanti, così il titolo resta davvero al
    // centro e non spinto da un lato.
    Image {
        id: appIcon
        // Come i pulsanti: la posizione e non le ancore. Vedi la nota sopra —
        // era questa a lasciare l'icona in mezzo alla barra.
        x: content.buttonsLeft
           ? Math.max(0, content.width - width - Theme.Effects.space2)
           : Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        source: content.iconPath !== "" ? "file://" + content.iconPath : ""
        sourceSize.width: 32
        sourceSize.height: 32
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        visible: status === Image.Ready
        opacity: content.active ? 1 : 0.6
    }

    // ── Il titolo ────────────────────────────────────────────────────────
    //
    // Al centro della BARRA, non dello spazio che avanza. Centrarlo nello
    // spazio libero lo farebbe ballare ogni volta che cambia il numero dei
    // pulsanti o la larghezza dell'icona, e su due finestre affiancate i due
    // titoli non starebbero mai sulla stessa colonna.
    //
    // I margini servono solo a impedirgli di finire sotto ai pulsanti quando
    // la finestra è stretta: si accorcia lui, non si sposta.
    //
    // ── Quanto spazio togliere, e perché non è la somma ──────────────────
    //
    // Il titolo sta al centro della barra, quindi per ogni pixel tolto da una
    // parte se ne toglie uno anche dall'altra: è il prezzo del restare
    // centrati. Ma da OGNI lato l'ostacolo è uno solo — i pulsanti da una
    // parte, l'icona dall'altra — e qui si sottraevano tutti e due da tutti e
    // due i lati.
    //
    // Con quattro pulsanti larghi trentadue fanno 2 × (134 + 16 + 24) = 348
    // pixel tolti a una barra che, su una finestra da trecentocinquanta, ne ha
    // trecentocinquanta: al titolo ne restavano DUE, cioè niente. Sotto i
    // trecentocinquanta pixel di larghezza nessuna finestra ha mai mostrato il
    // proprio nome, e non c'era nessun segno che qualcosa fosse andato storto
    // — semplicemente non c'era scritto niente.
    //
    // Da ogni lato si toglie il PIÙ INGOMBRANTE dei due, che è quanto basta a
    // non finirci sotto.
    Text {
        textFormat: Text.PlainText
        readonly property int ostacolo: Math.max(
            controls.width + content.side_,
            appIcon.width + Theme.Effects.space2)

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(
            implicitWidth,
            content.width - 2 * (ostacolo + Theme.Effects.space2)))
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: content.label
        color: content.active ? content.foreground : content.mutedForeground
        font.family: content.fontFamily
        font.pixelSize: Theme.Typography.sizeSM
        font.weight: content.active ? Theme.Typography.weightMedium : Font.Normal
    }
}
