import QtQuick
import QtQuick.Shapes
import "../theme" as Theme
import "../core" as Core

// Membrane — La superficie continua di Minerva.
//
// ┌───────────────────────────────────────────────────────────┐  ← barra
// │                                          ╮         ╭      │
// └──────────────────────────────────────────╯         ╰──────┘
//                                            │  pannello  │
//                                            ╰────────────╯
//
// Barra e pannello NON sono due oggetti sovrapposti: sono un unico tracciato.
// Dove il pannello incontra la barra il profilo si raccorda con due fillet
// CONCAVI, come una goccia che scende da un bordo. È la differenza fra un
// pannello «appoggiato sotto la barra» e un pannello che «nasce dalla barra».
//
// Perché conta: due superfici distinte, per quanto allineate al pixel,
// lasciano sempre una cucitura — un bordo, una discontinuità del blur, una
// differenza di trasparenza dove si sovrappongono. Con un tracciato solo la
// cucitura non esiste perché non ci sono due pezzi.
//
// Il pannello si apre animando `panelHeight`: la membrana si allunga verso il
// basso e i raccordi si formano da soli.
Item {
    id: membrane

    // ── Geometria della barra ────────────────────────────────────────────
    property real barHeight: Theme.Effects.barHeight

    /// La barra sta in basso: il profilo è lo stesso rovesciato.
    ///
    /// ── Specchiata, non riscritta ────────────────────────────────────────
    ///
    /// Il tracciato qui sotto ha sedici punti e ogni punto ha una `y`. Con la
    /// barra in basso la lingua sale invece di scendere e i raccordi concavi
    /// guardano in su: si potrebbe mettere un segno davanti a ognuna di quelle
    /// sedici — e avere due geometrie da tenere d'accordo, di cui una guardata
    /// da nessuno finché qualcuno non sposta la barra.
    ///
    /// Si specchia invece l'intero disegno. Una curva sbagliata resta sbagliata
    /// in tutti e due i versi, che è esattamente ciò che si vuole: non esiste
    /// la metà che va alla deriva.
    ///
    /// Si può fare per una ragione precisa, e vale la pena scriverla perché è
    /// la stessa che rende questo file sostituibile: **la membrana disegna solo
    /// il profilo.** Il contenuto della barra e quello del pannello sono suoi
    /// fratelli, fuori di qui, e restano diritti.
    property bool inBasso: false

    /// La fascia della barra, in coordinate della membrana.
    readonly property real _bandaY: membrane.inBasso
                                    ? membrane.height - membrane.barHeight : 0

    // ── Geometria del pannello agganciato ────────────────────────────────
    /// Bordo sinistro del pannello, in coordinate della membrana.
    property real panelX: 0
    property real panelWidth: 0
    /// Altezza del pannello. A 0 resta solo la barra.
    property real panelHeight: 0

    /// Raggio del raccordo concavo barra→pannello.
    property real shoulder: Theme.Effects.shoulder
    /// Raggio degli angoli inferiori del pannello.
    property real bottomRadius: Theme.Effects.radiusLG

    // ── Gli angoli in basso della BARRA ──────────────────────────────────
    //
    // La barra arrivava agli spigoli dello schermo con due angoli retti, e in
    // mezzo a un'interfaccia dove ogni altra superficie è arrotondata quei due
    // spigoli si vedevano.
    //
    // ── E il raccordo va all'INFUORI, non all'indentro ────────────────────
    //
    // Prima li avevo smussati togliendo materiale alla barra: l'angolo veniva
    // tagliato, e sotto restava un morso di scrivania. Giacomo: «la barra
    // arrotondata la volevo verso l'esterno non verso l'interno, in modo che
    // una finestra a schermo intero combaci con la barra».
    //
    // Ha ragione, ed è la stessa curva che la membrana usa già dove il
    // pannello si aggancia: un raccordo CONCAVO. La barra non perde l'angolo,
    // lo allunga verso il basso lungo il bordo dello schermo e ci rientra con
    // una curva. Quello che si arrotonda è lo SPAZIO SOTTO, non la barra: una
    // finestra massimizzata, che ha gli angoli quadrati, ci si infila sotto e
    // combacia invece di lasciare una fessura.
    //
    // È anche la coerenza che mancava: in Minerva le superfici si raccordano
    // così — «come una goccia che scende da un bordo», dice il commento in
    // cima a questo file. Un angolo tagliato diceva un'altra cosa.
    property real barCorner: Theme.Effects.radiusMD

    // ── Aspetto ──────────────────────────────────────────────────────────
    property color fillColor: Theme.Colors.membrane
    property color edgeColor: Theme.Colors.edge

    // ── Il vetro ─────────────────────────────────────────────────────────
    //
    // Chi usa la membrana dice DOVE si trova sullo schermo e quanto è grande
    // lo schermo: senza, l'immagine sfocata non potrebbe combaciare con lo
    // sfondo vero che le sta dietro. Per la barra, che parte dall'angolo in
    // alto a sinistra, restano zero.
    property real origineX: 0
    property real origineY: 0
    property real schermoLargo: width
    property real schermoAlto: height

    /// Si può spegnere: chi non lo vuole, o chi disegna una membrana che non
    /// sta sopra lo sfondo (dentro una finestra, per esempio).
    property bool vetro: true

    /// Vero solo quando c'è davvero qualcosa da disegnare. Vuoto è un caso
    /// NORMALE — il primo mezzo secondo di ogni sessione, e per sempre su una
    /// macchina senza `magick` — e allora resta il colore di prima, che è
    /// quello che c'era anche ieri.
    readonly property bool vetroVisibile:
        membrane.vetro && Core.Vetro.daDisegnare !== ""

    /// Vero quando il pannello è aperto abbastanza da disegnarne il profilo.
    readonly property bool panelVisible: panelHeight > 0.5 && panelWidth > 1

    // I raccordi non possono essere più grandi dello spazio disponibile,
    // altrimenti a inizio animazione il tracciato si auto-interseca e la
    // sagoma «esplode» per un paio di fotogrammi.
    readonly property real _shoulder: Math.max(0, Math.min(shoulder, panelHeight))
    readonly property real _bottom: Math.max(0, Math.min(bottomRadius,
                                                         panelWidth / 2,
                                                         panelHeight - _shoulder))

    readonly property real _px: panelX
    readonly property real _pr: panelX + panelWidth
    readonly property real _pb: barHeight + panelHeight

    // Gli angoli della barra cedono il passo al pannello. Con una lingua
    // aperta vicino al bordo dello schermo, l'angolo e il raccordo concavo si
    // contenderebbero lo stesso tratto di profilo e la sagoma si
    // auto-intersecherebbe: qui l'angolo si stringe fino a sparire, e la
    // membrana resta un tracciato solo.
    readonly property real _angoloDx: Math.max(0, Math.min(barCorner,
        panelVisible ? Math.max(0, width - (_pr + _shoulder)) : width / 2))
    readonly property real _angoloSx: Math.max(0, Math.min(barCorner,
        panelVisible ? Math.max(0, _px - _shoulder) : width / 2))

    /// Dove finisce il profilo della barra a destra e a sinistra: il bordo del
    /// pannello se c'è, altrimenti l'inizio dell'angolo tondo.
    readonly property real _fineDx: panelVisible ? _pr : (width - _angoloDx)
    readonly property real _fineSx: panelVisible ? _px : _angoloSx

    // ── IL VETRO ─────────────────────────────────────────────────────────
    //
    // Lo sfondo già sfocato, disegnato **sotto** il riempimento della
    // membrana: quello che si vede è l'immagine più la tinta traslucida
    // sopra, cioè un vetro. Dichiarato prima della `Shape` apposta — in QML
    // l'ordine di dichiarazione è l'ordine di disegno, e un fondo dichiarato
    // per ultimo copre tutto il resto.
    //
    // ── Perché solo la fascia della barra ────────────────────────────────
    //
    // Perché quella fascia — da 0 a `barHeight`, per tutta la larghezza — è
    // l'unica parte del profilo che sia un RETTANGOLO PIENO: il tracciato va
    // da (0,0) a (width,0) e scende dritto, e i raccordi concavi cominciano
    // tutti sotto `barHeight`. Un `clip` in QML è rettangolare e basta, quindi
    // qui combacia esatto e altrove sborderebbe.
    //
    // La lingua del pannello resta senza vetro, ed è una scelta: è una
    // superficie grande e piena su cui si legge, non un filo di cornice.
    //
    // ── E perché l'immagine è grande quanto lo SCHERMO ───────────────────
    //
    // Perché deve combaciare con lo sfondo vero che le sta dietro: se si
    // disegnasse adattata alla sola barra, si vedrebbe un pezzo di cielo
    // schiacciato in una striscia, e ogni volta che la barra cambia altezza
    // il disegno salterebbe. Si disegna lo stesso quadro, alla stessa
    // misura, e se ne guarda la fetta che tocca.
    //
    // ── E perché qui non si usano le ancore ──────────────────────────────
    //
    // La fascia sta in alto o in basso secondo `inBasso`, e la forma naturale
    // sarebbe `anchors.top: inBasso ? undefined : parent.top`. Non funziona:
    // in QML `undefined` **non stacca** un'ancora già assegnata, la lascia
    // dov'era. È un difetto che si ripara riavviando, cioè il peggiore da
    // trovare. Una `y` calcolata non ha quel problema.
    Item {
        x: 0
        width: parent.width
        y: membrane._bandaY
        height: membrane.barHeight
        clip: true
        visible: membrane.vetroVisibile

        Image {
            // Si decodifica alla larghezza dello schermo e non a quella della
            // fotografia: sotto la barra è sfocato, e un 6000 pixel teneva in
            // memoria decine di megabyte per ogni schermo.
            sourceSize.width: membrane.schermoLargo
            x: -membrane.origineX
            y: -membrane.origineY - membrane._bandaY
            width: membrane.schermoLargo
            height: membrane.schermoAlto
            source: membrane.vetroVisibile
                    ? "file://" + Core.Vetro.daDisegnare : ""
            fillMode: Image.PreserveAspectCrop
            // È già sfocata: nessuno ci cerca il dettaglio, e `smooth` toglie
            // la scalettatura del ringrandimento senza costare niente.
            smooth: true
            asynchronous: true
            cache: true
        }
    }

    Shape {
        id: shape
        anchors.fill: parent
        // GeometryRenderer e non CurveRenderer: vedi `ui/Icon.qml`. Il
        // renderer analitico vuole la GPU, e queste finestre disegnano col
        // processore — dove lascia pixel di oggetti che non esistono più.
        // L'antialiasing analitico che si perde qui col processore non
        // c'era comunque.
        preferredRendererType: Shape.GeometryRenderer
        asynchronous: false

        // Lo specchio. Vedi `inBasso` in cima al file.
        transform: Scale {
            origin.y: membrane.height / 2
            yScale: membrane.inBasso ? -1 : 1
        }

        ShapePath {
            fillColor: membrane.fillColor
            strokeColor: membrane.edgeColor
            strokeWidth: Theme.Effects.hairline
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            // Spigolo in alto a sinistra dello schermo
            startX: 0
            startY: 0

            PathLine { x: membrane.width; y: 0 }
            // Il bordo destro dello schermo scende SOTTO la barra: è la
            // parte che poi rientra con la curva.
            PathLine {
                x: membrane.width
                y: membrane.barHeight + membrane._angoloDx
            }

            // Raccordo CONCAVO all'angolo destro dello schermo
            PathArc {
                x: membrane.width - membrane._angoloDx
                y: membrane.barHeight
                radiusX: membrane._angoloDx
                radiusY: membrane._angoloDx
                direction: PathArc.Counterclockwise
            }

            // ── Lato destro del pannello ─────────────────────────────────
            PathLine {
                x: membrane.panelVisible ? membrane._pr + membrane._shoulder
                                         : membrane.width - membrane._angoloDx
                y: membrane.barHeight
            }

            // Raccordo CONCAVO destro: la barra si incurva verso il pannello
            PathArc {
                x: membrane._fineDx
                y: membrane.barHeight + membrane._shoulder
                radiusX: membrane._shoulder
                radiusY: membrane._shoulder
                direction: PathArc.Counterclockwise
            }

            PathLine {
                x: membrane._fineDx
                y: membrane.panelVisible ? membrane._pb - membrane._bottom
                                         : membrane.barHeight
            }

            // ── Angoli inferiori del pannello (convessi) ─────────────────
            PathArc {
                x: membrane.panelVisible ? membrane._pr - membrane._bottom
                                         : membrane._fineDx
                y: membrane.panelVisible ? membrane._pb : membrane.barHeight
                radiusX: membrane._bottom
                radiusY: membrane._bottom
                direction: PathArc.Clockwise
            }

            PathLine {
                x: membrane.panelVisible ? membrane._px + membrane._bottom
                                         : membrane._fineSx
                y: membrane.panelVisible ? membrane._pb : membrane.barHeight
            }

            PathArc {
                x: membrane._fineSx
                y: membrane.panelVisible ? membrane._pb - membrane._bottom
                                         : membrane.barHeight
                radiusX: membrane._bottom
                radiusY: membrane._bottom
                direction: PathArc.Clockwise
            }

            // ── Lato sinistro del pannello ───────────────────────────────
            PathLine {
                x: membrane._fineSx
                y: membrane.panelVisible ? membrane.barHeight + membrane._shoulder
                                         : membrane.barHeight
            }

            // Raccordo CONCAVO sinistro
            PathArc {
                x: membrane.panelVisible ? membrane._px - membrane._shoulder
                                         : membrane._angoloSx
                y: membrane.barHeight
                radiusX: membrane._shoulder
                radiusY: membrane._shoulder
                direction: PathArc.Counterclockwise
            }

            PathLine { x: membrane._angoloSx; y: membrane.barHeight }

            // Raccordo CONCAVO all'angolo sinistro dello schermo
            PathArc {
                x: 0
                y: membrane.barHeight + membrane._angoloSx
                radiusX: membrane._angoloSx
                radiusY: membrane._angoloSx
                direction: PathArc.Counterclockwise
            }

            PathLine { x: 0; y: 0 }
        }
    }

    // Filo di luce lungo il bordo inferiore della barra: rende percepibile
    // lo spessore della membrana e stacca la barra dal contenuto sottostante.
    //
    // Il filo si INTERROMPE dove comincia il pannello. È il dettaglio che fa
    // tutta la differenza: un filo che attraversa anche la lingua la taglia in
    // due e la fa sembrare una finestra appoggiata sotto la barra — esattamente
    // l'effetto che questa membrana esiste per evitare. Interrompendolo, la
    // barra e la lingua restano un pezzo solo e i raccordi si leggono.
    Item {
        anchors.fill: parent

        readonly property real gapLeft:  membrane.panelVisible
                                         ? Math.max(0, membrane._px - membrane._shoulder)
                                         : membrane.width
        readonly property real gapRight: membrane.panelVisible
                                         ? Math.min(membrane.width, membrane._pr + membrane._shoulder)
                                         : membrane.width

        Rectangle {
            // Il filo sta sul bordo INTERNO della barra: sotto di lei se è in
            // alto, sopra se è in basso. Non passa dallo specchio perché le
            // sue sfumature sono orizzontali e specchiarlo non le toccherebbe:
            // costerebbe un altro `transform` per non cambiare niente.
            y: membrane.inBasso ? membrane._bandaY : membrane.barHeight - 1
            x: 0
            width: parent.gapLeft
            height: 1
            opacity: 0.55
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.35; color: Theme.Colors.edgeBright }
                // A pannello chiuso il filo sfuma anche a destra; a pannello
                // aperto arriva pieno fino al raccordo e lì si ferma.
                GradientStop {
                    position: 1.0
                    color: membrane.panelVisible ? Theme.Colors.edgeBright : "transparent"
                }
            }
        }

        Rectangle {
            y: membrane.inBasso ? membrane._bandaY : membrane.barHeight - 1
            x: parent.gapRight
            width: Math.max(0, membrane.width - parent.gapRight)
            height: 1
            opacity: 0.55
            visible: membrane.panelVisible
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.Colors.edgeBright }
                GradientStop { position: 0.65; color: Theme.Colors.edgeBright }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
