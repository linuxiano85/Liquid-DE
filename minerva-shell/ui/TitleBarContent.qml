import QtQuick
import "../theme" as Theme
import "../core" as Core

// TitleBarContent — Quello che c'è DENTRO una barra del titolo.
//
// Solo il contenuto: icona, titolo, pulsanti. Non disegna nessuno sfondo e non
// gestisce nessun trascinamento, e non è una svista.
//
// Le barre del titolo di Minerva sono due cose diverse per necessità:
//
//  · dentro le NOSTRE finestre (gestore file, Impostazioni) la barra è parte
//    della finestra stessa. Stessa superficie, stesso vetro, stessa
//    sfocatura, e soprattutto: quando la finestra si sposta, la barra è già
//    lì, perché è lei. Vedi `ui/WindowTitleBar.qml`.
//
//  · sopra le finestre ALTRUI (un terminale, un browser) la barra non può
//    essere parte di niente: Hyprland non disegna cornici e nessun programma
//    accetta che gliene aggiungiamo una dentro. Resta una superficie a parte
//    che insegue la finestra leggendo dove si trova, con tutto quello che
//    l'inseguimento comporta. Vedi `spine/TitleBars.qml`.
//
// Questo file è ciò che le rende IDENTICHE da guardare. Senza, sarebbero due
// disegni che somigliano, e la differenza si noterebbe esattamente dove non
// deve: fra due finestre affiancate.
Item {
    id: content

    /// Il titolo, al centro.
    property string label: ""
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

    readonly property bool buttonsLeft: content.side === "sinistra"

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
    // Segnalato da Giacomo il 18 agosto 2026: «se imposti i pulsanti a
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
        x: content.buttonsLeft
           ? content.side_
           : Math.max(0, content.width - width - content.side_)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            // A sinistra l'ordine si specchia: il pulsante che chiude resta
            // quello all'estremità, come su qualunque finestra di macOS.
            model: content.buttonsLeft
                   ? content.buttons.slice().reverse()
                   : content.buttons

            delegate: Rectangle {
                id: ctl
                required property var modelData

                width: content.height - 10
                height: content.height - 10
                radius: Theme.Effects.radiusXS
                color: ctlMouse.containsMouse
                       ? (ctl.modelData.danger
                          ? Qt.alpha(Theme.Colors.danger, 0.30)
                          : Theme.Colors.hover)
                       : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Icon {
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
                                                   : Theme.Colors.text)
                           : (content.active ? Theme.Colors.textMuted
                                             : Theme.Colors.textFaint)
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                }

                MouseArea {
                    id: ctlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
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
        color: content.active ? Theme.Colors.text : Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeSM
        font.weight: content.active ? Theme.Typography.weightMedium : Font.Normal
    }
}
