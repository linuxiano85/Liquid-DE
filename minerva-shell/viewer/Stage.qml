import QtQuick
import "../theme" as Theme
import "../core" as Core

// Stage — Il tavolo su cui sta l'immagine.
//
// Fa tre cose e nient'altro: mostra il file, lo ingrandisce, lo sposta. Non sa
// che cos'è un album, non sa che esiste una barra degli strumenti, e non
// chiede niente al demone. È il pezzo che si può guardare da solo.
//
// ── Perché il fondo è OPACO ──────────────────────────────────────────────
//
// Tutto il resto di Minerva è vetro, e qui no. Non è una dimenticanza: un
// colore si giudica CONTRO quello che gli sta intorno, e uno sfondo che
// traspare dietro una fotografia le cambia i colori sotto gli occhi di chi la
// guarda. Un cielo su un muro di mattoni non è più quel cielo. La cornice —
// barra del titolo e strumenti — resta vetro; il tavolo no.
//
// ── La scacchiera ────────────────────────────────────────────────────────
//
// Sta SOTTO l'immagine e si vede solo dove l'immagine è trasparente. Senza,
// un PNG con lo sfondo trasparente e un PNG con lo sfondo bianco sono
// indistinguibili, ed è esattamente la differenza che si sta cercando quando
// si apre un PNG. È ancorata alla FINESTRA e non all'immagine: così non si
// ridisegna a ogni scatto dello zoom, e resta ferma mentre l'immagine si
// muove sopra — che è anche il modo in cui la disegnano i programmi di
// fotografia da trent'anni.
Item {
    id: stage
    clip: true

    /// Il file da mostrare. Percorso vero, senza `file://`.
    property string percorso: ""

    /// Quarti di giro in senso orario. Solo per guardare: il file non si tocca.
    property int rotazione: 0

    /// Le misure VERE del file, lette dall'intestazione dal demone e passate
    /// da chi ci contiene. Zero quando non si sanno.
    ///
    /// Sono la chiave di tutto il risparmio di memoria qui sotto: sapendo
    /// quanto è grande un file PRIMA di aprirlo si può chiedere a Qt di
    /// decodificarlo direttamente alla misura che serve. Senza, l'unico modo
    /// di sapere quanto è grande è decodificarlo tutto — cioè pagare proprio
    /// il prezzo che si voleva evitare.
    property int veroW: 0
    property int veroH: 0
    readonly property bool sappiamoLeMisure: stage.veroW > 0 && stage.veroH > 0

    /// Vero finché l'immagine segue la finestra. Diventa falso al primo zoom a
    /// mano, e ci si torna con «adatta»: senza questa distinzione, ogni
    /// ridimensionamento della finestra butterebbe via lo zoom scelto.
    property bool adatta: true

    property real scala: 1.0
    /// Angolo in alto a sinistra dell'immagine, in coordinate della finestra.
    property real posX: 0
    property real posY: 0

    // ── Le dimensioni naturali ───────────────────────────────────────────
    //
    // Si COPIANO quando l'immagine è pronta, invece di leggerle dall'oggetto
    // `Image` a ogni fotogramma. Non è un'ottimizzazione: la larghezza
    // dell'immagine dipende dalla scala, la scala dipende dalle dimensioni
    // naturali, e leggerle dall'oggetto che stiamo dimensionando chiude
    // l'anello. Qt lo riconosce e lo dice — «Binding loop detected» — e la
    // prima immagine si disegna a una misura sbagliata.
    property bool pronta: false
    /// Quello che ha detto l'oggetto `Image` dopo aver caricato. Serve SOLO
    /// quando le misure vere non si sanno (un formato che il demone non
    /// riconosce): in quel caso non si mette nessun tetto alla decodifica e
    /// queste sono le misure buone.
    property int caricataW: 0
    property int caricataH: 0
    readonly property int natW: stage.sappiamoLeMisure ? stage.veroW : stage.caricataW
    readonly property int natH: stage.sappiamoLeMisure ? stage.veroH : stage.caricataH

    /// Vero per i file che possono muoversi.
    ///
    /// Solo `.gif`, e per estensione. Non per pigrizia: `AnimatedImage` tiene
    /// in piedi un `QMovie` anche su un file fermo, e passarci OGNI fotografia
    /// costerebbe a tutti per il vantaggio di pochi. I `.webp` animati
    /// esistono ma sono rari, e mandarli tutti da questa parte metterebbe a
    /// rischio i molti `.webp` fermi per i pochi che si muovono.
    readonly property bool animata: {
        var p = String(stage.percorso).toLowerCase();
        return p.endsWith(".gif");
    }

    /// Vero mentre si sta caricando, qualunque dei due elementi lo stia
    /// facendo.
    readonly property bool caricando: stage.animata
                                      ? mossa.status === Image.Loading
                                      : img.status === Image.Loading

    /// Chi ha finito di caricare dice quanto è venuto.
    function misura(chi) {
        stage.caricataW = chi.implicitWidth;
        stage.caricataH = chi.implicitHeight;
        stage.pronta = true;
        // La scala «adatta» si può calcolare solo adesso: prima non si sapeva
        // quanto è grande l'immagine.
        if (stage.adatta) {
            stage.scala = stage.scalaAdatta;
            stage.centra();
        }
    }
    readonly property int dispW: (stage.rotazione % 180 === 0) ? stage.natW : stage.natH
    readonly property int dispH: (stage.rotazione % 180 === 0) ? stage.natH : stage.natW

    /// La scala a cui l'immagine ci sta tutta.
    ///
    /// Non supera MAI 1: un'icona da 32 pixel «adattata» a schermo intero è un
    /// mosaico sfocato, e non è quello che chiede chi apre un file piccolo. Chi
    /// la vuole più grande lo dice, con lo zoom.
    readonly property real scalaAdatta: {
        if (stage.dispW <= 0 || stage.dispH <= 0 || stage.width <= 0 || stage.height <= 0)
            return 1.0;
        return Math.min(stage.width / stage.dispW,
                        stage.height / stage.dispH,
                        1.0);
    }

    readonly property real scalaMin: Math.min(0.05, stage.scalaAdatta)
    readonly property real scalaMax: 20.0

    // ── Quanto in grande decodificare ────────────────────────────────────
    //
    // Una fotografia da 1840×4080 occupa **trenta megabyte** decodificata, più
    // altrettanti sulla scheda video. Dentro una finestra da 1180×662 se ne
    // vedono tre. Per dieci anni i visualizzatori hanno pagato quella
    // differenza perché era invisibile; su una macchina che deve reggere una
    // scrivania intera non lo è più.
    //
    // `sourceSize` chiede a Qt di decodificare DIRETTAMENTE alla misura utile
    // — una volta sola, non decodificare tutto e poi rimpicciolire a ogni
    // fotogramma. Si passano tutte e due le misure: qui l'immagine sta DENTRO
    // la finestra (contenuta, non ritagliata), e «entra nel riquadro tenendo
    // le proporzioni» è esattamente la regola giusta. È il contrario dello
    // sfondo, che invece deve coprire — vedi `menu/WallpaperLayer.qml`.
    //
    // Quando si ingrandisce servono più pixel, e si va a potenze di due: fra
    // 1× e 16× sono quattro ricariche in tutto, invece di una a ogni scatto
    // della rotellina. Qt non ingrandisce mai oltre il file vero, quindi il
    // tetto vero resta la fotografia.
    readonly property int qualita: {
        if (!stage.sappiamoLeMisure || stage.scalaAdatta <= 0)
            return 1;
        var k = stage.scala / stage.scalaAdatta;
        if (k <= 1.01)
            return 1;
        return Math.min(16, Math.pow(2, Math.ceil(Math.log(k) / Math.LN2)));
    }

    signal clicSecondario(real x, real y)

    // ── Comandi ──────────────────────────────────────────────────────────

    /// Torna a far seguire la finestra all'immagine.
    function adattaAllaFinestra() {
        stage.adatta = true;
        stage.scala = stage.scalaAdatta;
        stage.centra();
    }

    /// Un pixel del file, un pixel dello schermo.
    function dimensioneVera() {
        stage.zoomAl(1.0, stage.width / 2, stage.height / 2);
    }

    /// Zoom tenendo fermo il punto (cx, cy) della finestra.
    ///
    /// È la differenza fra uno zoom che si usa e uno che fa perdere il segno:
    /// ingrandire «dal centro della finestra» sposta via quello che si stava
    /// guardando ogni volta che si gira la rotellina.
    function zoomAl(nuova, cx, cy) {
        var n = Math.max(stage.scalaMin, Math.min(stage.scalaMax, nuova));
        if (Math.abs(n - stage.scala) < 0.0001)
            return;
        var k = n / stage.scala;
        stage.posX = cx - (cx - stage.posX) * k;
        stage.posY = cy - (cy - stage.posY) * k;
        stage.scala = n;
        stage.adatta = false;
        stage.sistema();
    }

    function zoomDi(fattore, cx, cy) {
        stage.zoomAl(stage.scala * fattore, cx, cy);
    }

    function centra() {
        stage.posX = (stage.width - stage.dispW * stage.scala) / 2;
        stage.posY = (stage.height - stage.dispH * stage.scala) / 2;
    }

    /// Rimette l'immagine dentro i bordi.
    ///
    /// Quando ci sta tutta si centra; quando non ci sta, non le si lascia
    /// scoprire un bordo — trascinare un'immagine fuori dalla finestra e
    /// ritrovarsi con il vuoto è il modo più veloce di perderla.
    function sistema() {
        var w = stage.dispW * stage.scala;
        var h = stage.dispH * stage.scala;
        if (w <= stage.width)
            stage.posX = (stage.width - w) / 2;
        else
            stage.posX = Math.max(stage.width - w, Math.min(0, stage.posX));
        if (h <= stage.height)
            stage.posY = (stage.height - h) / 2;
        else
            stage.posY = Math.max(stage.height - h, Math.min(0, stage.posY));
    }

    // Quando cambia il file, la finestra o la rotazione, si riparte adattati —
    // a meno che chi guarda abbia scelto uno zoom suo, che va rispettato.
    onScalaAdattaChanged: if (stage.adatta) { stage.scala = stage.scalaAdatta; stage.centra(); }
    onWidthChanged: stage.adatta ? stage.centra() : stage.sistema()
    onHeightChanged: stage.adatta ? stage.centra() : stage.sistema()
    onPercorsoChanged: {
        stage.rotazione = 0;
        stage.adatta = true;
        // Finché la nuova non è pronta non si sanno le sue misure, e quelle
        // della precedente sono di un'altra immagine.
        stage.pronta = false;
        stage.caricataW = 0;
        stage.caricataH = 0;
    }
    onRotazioneChanged: if (stage.adatta) { stage.scala = stage.scalaAdatta; stage.centra(); }

    // ── Il tavolo ────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        // Neutro e profondo, non nero pieno: il nero assoluto fa sembrare più
        // chiare le ombre di una fotografia, ed è il colore che nessun
        // laboratorio ha mai messo intorno a una stampa.
        color: Theme.Colors.scura ? "#0B0D12" : "#1A1D24"
    }

    // ── L'immagine ───────────────────────────────────────────────────────

    Item {
        id: tela
        x: stage.posX
        y: stage.posY
        width: Math.max(1, stage.dispW * stage.scala)
        height: Math.max(1, stage.dispH * stage.scala)
        clip: true
        visible: stage.pronta

        // La scacchiera, ferma rispetto alla finestra e ritagliata su di lei.
        Canvas {
            id: scacchi
            x: -tela.x
            y: -tela.y
            width: stage.width
            height: stage.height
            renderStrategy: Canvas.Cooperative

            readonly property int lato: 12
            readonly property color chiaro: Qt.rgba(1, 1, 1, 0.055)
            readonly property color scuro: Qt.rgba(1, 1, 1, 0.02)

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = scacchi.scuro;
                ctx.fillRect(0, 0, width, height);
                ctx.fillStyle = scacchi.chiaro;
                for (var r = 0; r * lato < height; r++)
                    for (var c = (r % 2); c * lato < width; c += 2)
                        ctx.fillRect(c * lato, r * lato, lato, lato);
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // ── Le immagini che si muovono ───────────────────────────────────
        //
        // Una GIF aperta con un `Image` normale mostra il PRIMO FOTOGRAMMA e
        // basta. Non dà errore, non manca niente: sembra solo una GIF rotta —
        // ed è il motivo per cui esistono due elementi qui dentro invece di
        // uno. `AnimatedImage` eredita da `Image`, quindi tutto il resto (le
        // misure, la rotazione, lo zoom) non sa nemmeno quale dei due sta
        // guardando.
        AnimatedImage {
            id: mossa
            anchors.centerIn: parent
            width: img.width
            height: img.height
            rotation: stage.rotazione
            visible: stage.animata
            source: (stage.animata && stage.percorso !== "")
                    ? "file://" + stage.percorso : ""
            fillMode: Image.Stretch
            cache: false
            smooth: true
            // Si ferma quando la finestra non si vede: venti fotogrammi al
            // secondo disegnati per nessuno sono venti fotogrammi di batteria.
            playing: stage.visible && stage.animata
            onStatusChanged: if (mossa.status === Image.Ready) stage.misura(mossa)
        }

        Image {
            id: img
            // Ruotare significa scambiare larghezza e altezza: l'immagine
            // riempie la tela con i lati scambiati e poi gira su sé stessa.
            anchors.centerIn: parent
            width: (stage.rotazione % 180 === 0) ? tela.width : tela.height
            height: (stage.rotazione % 180 === 0) ? tela.height : tela.width
            rotation: stage.rotazione
            visible: !stage.animata

            source: (!stage.animata && stage.percorso !== "")
                    ? "file://" + stage.percorso : ""
            fillMode: Image.Stretch
            // Asincrono: un JPEG da venti megapixel bloccherebbe l'interfaccia
            // per mezzo secondo, e mezzo secondo di finestra morta si vede.
            asynchronous: true
            cache: false
            smooth: true

            // Il tetto alla decodifica. Zero vuol dire «nessun tetto», ed è
            // quello che si fa quando le misure vere non si sanno: senza
            // sapere quanto è grande il file non si può mettere un tetto senza
            // rischiare di mostrarlo sgranato.
            sourceSize.width: stage.sappiamoLeMisure
                              ? Math.ceil(stage.width * stage.qualita) : 0
            sourceSize.height: stage.sappiamoLeMisure
                               ? Math.ceil(stage.height * stage.qualita) : 0

            // `mipmap` serve a chi RIMPICCIOLISCE molto, e da quando la
            // decodifica arriva già alla misura giusta non è più il nostro
            // caso: costa un terzo di memoria in più sulla scheda video per
            // livelli che non si guardano mai. Resta acceso solo quando il
            // tetto non c'è, cioè quando stiamo davvero rimpicciolendo un
            // file intero.
            mipmap: !stage.sappiamoLeMisure && stage.scala < 1.0

            onStatusChanged: if (img.status === Image.Ready) stage.misura(img)
        }
    }

    // ── Il file che non si legge ─────────────────────────────────────────

    Column {
        anchors.centerIn: parent
        spacing: Theme.Effects.space2
        visible: stage.percorso !== ""
                 && (stage.animata ? mossa.status === Image.Error
                                   : img.status === Image.Error)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Core.Strings.lang === "it" ? "Non riesco ad aprire questa immagine"
                                             : "Cannot open this image"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeLG
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.percorso
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, stage.width - Theme.Effects.space7 * 2)
        }
    }

    // ── Il caricamento ───────────────────────────────────────────────────
    //
    // Una riga sottile in cima, non una rotella al centro: la rotella
    // annuncia un'attesa e la rende più lunga di quello che è. Compare solo
    // dopo un quarto di secondo, perché sotto quella soglia lampeggerebbe e
    // basta.

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        color: Theme.Colors.accent
        opacity: attesa.running ? 0 : (stage.caricando ? 0.85 : 0)
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }
    }

    Timer {
        id: attesa
        interval: 250
        running: stage.caricando
    }

    // ── Il mouse ─────────────────────────────────────────────────────────
    //
    // La rotellina INGRANDISCE, non cambia immagine. È la scelta che divide i
    // visualizzatori: girare la rotellina su una fotografia vuol dire
    // «avvicinati», e cambiare foto ha già due frecce, due pulsanti e la
    // striscia in basso. Con Ctrl premuto fa comunque la stessa cosa, perché
    // metà del mondo arriva da programmi in cui lo zoom è Ctrl+rotellina e
    // non deve scoprire una regola nuova.

    // L'id NON si chiama `mouse`: Qt inietta nei gestori di MouseArea un
    // parametro con quel nome, e da dentro `onPressed` `mouse.qualcosa`
    // finirebbe sull'evento invece che su questo oggetto. Il compilatore lo
    // dice, ma solo come avviso — e il difetto sarebbe un trascinamento che
    // ogni tanto parte dal punto sbagliato.
    MouseArea {
        id: puntatore
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: {
            if (!stage.pronta)
                return Qt.ArrowCursor;
            if (puntatore.trascina)
                return Qt.ClosedHandCursor;
            return stage.puoScorrere ? Qt.OpenHandCursor : Qt.ArrowCursor;
        }

        property bool trascina: false
        property real presoX: 0
        property real presoY: 0

        onPressed: (e) => {
            if (e.button === Qt.RightButton) {
                stage.clicSecondario(e.x, e.y);
                return;
            }
            puntatore.presoX = e.x - stage.posX;
            puntatore.presoY = e.y - stage.posY;
            puntatore.trascina = stage.puoScorrere;
        }
        onReleased: puntatore.trascina = false
        onPositionChanged: (e) => {
            if (!puntatore.trascina)
                return;
            stage.posX = e.x - puntatore.presoX;
            stage.posY = e.y - puntatore.presoY;
            stage.adatta = false;
            stage.sistema();
        }

        // Doppio clic: avanti e indietro fra «tutta dentro» e «dimensione
        // vera». Sono i due modi in cui si guarda un'immagine, e questo è il
        // gesto che li scambia senza cercare un pulsante.
        onDoubleClicked: (e) => {
            if (Math.abs(stage.scala - 1.0) < 0.01)
                stage.adattaAllaFinestra();
            else
                stage.zoomAl(1.0, e.x, e.y);
        }

        onWheel: (w) => {
            if (!stage.pronta)
                return;
            // I mouse a scatti mandano 120 per scatto; i touchpad mandano
            // frazioni. Usare il segno e basta farebbe scattare un touchpad
            // come un mouse: il fattore segue quanto si è girato davvero.
            var passi = w.angleDelta.y / 120.0;
            if (passi === 0)
                return;
            stage.zoomDi(Math.pow(1.25, passi), w.x, w.y);
            w.accepted = true;
        }
    }

    readonly property bool puoScorrere:
        stage.pronta && (stage.dispW * stage.scala > stage.width + 1
                         || stage.dispH * stage.scala > stage.height + 1)
}
