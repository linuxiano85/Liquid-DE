import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core

// WallpaperLayer — Lo sfondo lo disegna Minerva.
//
// Prima lo disegnava `hyprpaper`, un programma a parte del progetto Hyprland,
// e ci sono tre buone ragioni per non farlo più.
//
//  1. INDIPENDENZA. Uno sfondo è un'immagine su una superficie: è la cosa più
//     semplice che un ambiente grafico sappia fare. Delegarla a un programma
//     di un altro progetto significa dipendere da quel progetto per una cosa
//     che sappiamo fare in venti righe.
//
//  2. NON FUNZIONAVA BENE. hyprpaper 0.8.4 su questa macchina IGNORA il
//     proprio file di configurazione: risponde «Monitor X has no target» con
//     qualunque forma della riga `wallpaper`, con `-c` e senza. Si riusciva a
//     comandarlo solo a caldo, con un ciclo di tentativi che insisteva finché
//     il programma non era in piedi. Tutto quel meccanismo sparisce qui.
//
//  3. RUBAVA I CLIC. hyprpaper non dichiara una regione d'ingresso vuota:
//     agganciandosi al livello di sfondo DOPO la scrivania di Minerva si
//     prendeva tutti i clic del tasto destro. È il guasto per cui il menu
//     della scrivania «aveva smesso di funzionare» senza che nulla fosse
//     cambiato nella shell. Qui la regione d'ingresso è vuota e dichiarata.
//
// Il cambio di immagine è una DISSOLVENZA e non un salto: due riquadri
// sovrapposti, quello nuovo che sale da trasparente. Serve soprattutto alla
// cartella che gira da sola — uno sfondo che cambia di scatto mentre stai
// lavorando fa alzare gli occhi, uno che sfuma no.
PanelWindow {
    id: paper

    WlrLayershell.namespace: "minerva-wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.Colors.base

    // Nessun clic, mai. Senza questa riga lo sfondo si mangia il tasto destro
    // sulla scrivania — vedi il punto 3 qui sopra.
    mask: Region {}

    /// Lo sfondo che si sta guardando, come lo dice il mazzo.
    readonly property string source: Core.Wallpaper.current

    // ── Una copia già rimpicciolita: PROVATA E SCARTATA ──────────────────
    //
    // `sourceSize` dice a Qt di decodificare più piccolo, e vale già una
    // cinquantina di megabyte (vedi il blocco qui sotto). Il 2 settembre 2026
    // ho provato a fare un passo in più: far preparare al demone una copia
    // dello sfondo **già** della misura dello schermo, come si fa per la
    // sfocatura del vetro, così che Qt non debba nemmeno aprire un JPEG da
    // otto milioni di pixel.
    //
    // Su una sonda isolata sembrava valere diciannove megabyte per riquadro:
    //
    //     pavimento nudo                       48 MB
    //     + questo sfondo 4K, con sourceSize    83 MB   →  35
    //     + lo stesso GIÀ scalato a 1280        64 MB   →  16
    //
    // Nella shell VERA, misurata due volte in una sessione annidata col
    // demone acceso, non ha reso niente — anzi:
    //
    //     shell con la copia scalata          131 MB
    //     shell con l'originale               127 MB
    //
    // Quattro megabyte in PIÙ. La sonda e la shell dicono cose diverse e non
    // so ancora perché: forse il rapporto fra le due misure (libjpeg sa
    // decodificare a metà, un quarto, un ottavo — e 3840 su 1280 è un terzo),
    // forse il secondo caricamento quando la copia arriva. **Non lo so, e per
    // questo la correzione non c'è.**
    //
    // Quello che resta è il numero, che vale comunque: **lo sfondo è la voce
    // più grossa della shell dopo il pavimento**, 35 MB su 79. Chi ci
    // riproverà parta da qui, e misuri nella shell vera — non su una sonda.
    // Il lato demone (`Vetro.perSchermo`) è stato tolto insieme a questo.

    /// I due riquadri: `back` tiene l'immagine vecchia mentre `front` sale.
    property string backSource: ""
    property string frontSource: ""

    onSourceChanged: paper.swap()
    Component.onCompleted: {
        paper.frontSource = paper.source;
        front.opacity = 1;
    }

    // ── Quanto in grande si decodifica ───────────────────────────────────
    //
    // Un JPEG non occupa in memoria quello che occupa su disco: occupa
    // larghezza × altezza × 4 byte, decodificato. Lo sfondo di prova era una
    // fotografia da 3556×4741 — **67 megabyte** — e siccome i riquadri sono
    // due (uno tiene la vecchia mentre la nuova sale) erano 135 megabyte su
    // uno schermo che ne avrebbe chiesti 5. Era la metà della memoria di tutta
    // la shell, per dei pixel che nessuno può vedere.
    //
    // `sourceSize.width` dice a Qt di decodificare direttamente più piccola,
    // una volta sola, invece di leggere tutto e rimpicciolire ogni fotogramma.
    //
    // Si dà la sola LARGHEZZA e non tutte e due le misure: con tutte e due Qt
    // fa entrare l'immagine dentro il riquadro, e un'immagine verticale
    // entrerebbe alta come lo schermo ma stretta — poi `PreserveAspectCrop` la
    // deve ringrandire per coprire, e si vede. Con la sola larghezza l'altezza
    // la calcola lui tenendo le proporzioni, e per tutto ciò che è verticale,
    // quadrato o quasi panoramico basta.
    //
    // Resta il caso opposto: un panorama molto più largo che alto, decodificato
    // alla larghezza dello schermo, verrebbe più basso dello schermo. Lo si
    // scopre DOPO la prima decodifica — che è anche l'unico momento in cui si
    // conoscono le proporzioni vere — e si rifà una volta sola, più grande.
    readonly property real densita: paper.screen ? paper.screen.devicePixelRatio : 1
    property int decodeW: Math.max(1, Math.round(paper.width * paper.densita))

    function adeguaDecodifica(img) {
        if (img.implicitWidth <= 0 || img.implicitHeight <= 0)
            return;
        var serve = Math.ceil(paper.height * paper.densita
                              * img.implicitWidth / img.implicitHeight);
        if (serve > paper.decodeW)
            paper.decodeW = serve;
    }

    function swap() {
        if (paper.source === paper.frontSource)
            return;
        // Si riparte dalla misura dello schermo: l'allargamento che ha chiesto
        // un panorama non deve restare addosso alla fotografia che viene dopo.
        paper.decodeW = Math.max(1, Math.round(paper.width * paper.densita));
        // La vecchia scende dietro e resta lì a coprire il vuoto finché la
        // nuova non ha finito di caricare: senza, per un fotogramma si vede il
        // colore di fondo, e sembra uno sfarfallio.
        paper.backSource = paper.frontSource;
        paper.frontSource = paper.source;
        front.opacity = 0;
        fade.restart();
    }

    Image {
        id: back
        anchors.fill: parent
        source: paper.backSource !== ""
                ? "file://" + paper.backSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        sourceSize.width: paper.decodeW
        visible: back.status === Image.Ready
        onStatusChanged: if (back.status === Image.Ready) paper.adeguaDecodifica(back)
    }

    Image {
        id: front
        anchors.fill: parent
        source: paper.frontSource !== ""
                ? "file://" + paper.frontSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        opacity: 0
        sourceSize.width: paper.decodeW
        visible: front.status === Image.Ready

        // Si scopre solo quando l'immagine è davvero pronta: far partire la
        // dissolvenza su un riquadro ancora vuoto mostrerebbe il fondo.
        onStatusChanged: {
            if (front.status !== Image.Ready)
                return;
            paper.adeguaDecodifica(front);
            if (paper.backSource !== "")
                fade.restart();
        }
    }

    NumberAnimation {
        id: fade
        target: front
        property: "opacity"
        to: 1
        duration: 900
        easing.type: Easing.InOutQuad
        onFinished: paper.backSource = ""
    }
}
