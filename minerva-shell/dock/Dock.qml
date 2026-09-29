import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Dock — La riga di icone in basso.
//
// Non è un secondo menu applicazioni: è il posto dove si vede COSA STA GIRANDO
// e ci si torna sopra con un colpo di mouse. La barra in alto racconta il
// sistema (ora, batteria, rete); la dock racconta il lavoro.
//
// ── L'INGRANDIMENTO, che è la parte difficile ────────────────────────────
//
// La prima versione respirava da sola: le icone crescevano e si sgonfiavano
// senza che nessuno le sfiorasse. Non era un difetto di animazione, era un
// ANELLO DI RETROAZIONE, ed è l'errore che chiunque scriva una dock fa una
// volta:
//
//     la larghezza della dock dipende da quanto sono grandi le icone
//     → la dock si ricentra, quindi le icone si spostano
//     → cambia la loro distanza dal puntatore
//     → cambia quanto sono grandi
//     → torna alla prima riga.
//
// Con una animazione di mezzo sulla larghezza, il giro non converge: oscilla.
// Da qui il battito.
//
// La cura non è smorzare l'oscillazione, è togliere l'anello. Qui la geometria
// A RIPOSO è fissa — larghezza della dock, posizione di ogni casella — e non
// dipende MAI dall'ingrandimento. L'ingrandimento è una funzione pura della
// posizione del puntatore applicata sopra quella geometria: le icone crescono
// verso l'alto e si scostano lateralmente, ma la casella sotto di loro non si
// muove di un pixel. Niente retroazione, niente battito, e nessuna animazione
// in mezzo che possa restare indietro rispetto al mouse.
//
// L'unica cosa animata è la FORZA dell'effetto, che sale da zero a uno quando
// il puntatore entra nella dock e torna a zero quando esce. È una animazione
// sola per tutta la dock, quindi le icone si muovono insieme invece di
// inseguirsi.
PanelWindow {
    id: dock

    // ── Preferenze ───────────────────────────────────────────────────────
    // Le lega la shell: qui non si sa che esiste un demone.

    property bool enabled: true
    /// Lato delle icone a riposo.
    property int iconSize: 48
    /// Ingrandimento sotto il puntatore, in stile macOS. 1.0 = spento.
    property real magnification: 1.6
    /// Quanto lontano si sente l'ingrandimento, in icone.
    property real magnificationReach: 2.2
    // ── Come sta sullo schermo: tre modi, non una levetta ────────────────
    //
    //   'sempre'   riserva il suo spazio: le finestre si fermano sopra di lei
    //              e non ci passano mai sotto;
    //   'nascondi' sparisce, e torna avvicinando il puntatore al bordo basso;
    //   'elude'    resta visibile finché nessuna finestra la coprirebbe, e si
    //              ritira quando una ci arriva sopra.
    //
    // Il terzo l'ha chiesto Giacomo il 2 settembre 2026 — «o che elude le
    // finestre» — e non esisteva. È il modo che si vorrebbe quasi sempre: la
    // dock c'è quando serve, cioè quando lo schermo è libero, e non ruba
    // spazio a una finestra che lo sta usando tutto.
    property string modo: "sempre"

    /// Il puntatore è sopra la dock. Si rimanda alla shell per l'IPC
    /// `minerva dock`: è la ragione per cui una dock che dovrebbe nascondersi
    /// resta dov'è, e senza dirlo sembra un guasto.
    readonly property bool sottoIlDito: dockArea.containsMouse

    /// Sparisce da sola e torna col puntatore.
    readonly property bool siNasconde: dock.modo === "nascondi"
    /// Si ritira quando una finestra la coprirebbe.
    readonly property bool elude: dock.modo === "elude"
    /// Vero nei due modi in cui la dock può sparire. È la vecchia `autoHide`,
    /// e serve a tutto il meccanismo del nascondersi qui sotto.
    readonly property bool autoHide: dock.siNasconde || dock.elude

    // ── Quando una finestra la coprirebbe ────────────────────────────────
    //
    // Si confronta il rettangolo del CORPO della dock con quello di ogni
    // finestra visibile della scrivania in uso. Non basta «c'è una finestra»:
    // una finestra piccola in alto non ha nessun motivo di far sparire la
    // dock, ed è la differenza fra «elude» e «si nasconde sempre».
    //
    // Si guarda `shownY` e non la posizione di adesso: altrimenti, appena
    // ritirata, la dock non si sovrapporrebbe più a niente e tornerebbe su —
    // e da lì avanti e indietro per sempre. È un anello di retroazione, la
    // stessa forma del difetto del volume.
    readonly property rect ingombro: Qt.rect(
        dock.originX + Math.round(dock.bodyX),
        dock.originY + dock.shownY,
        Math.round(dock.bodyWidth), dock.barHeight)

    readonly property bool copertaDaUnaFinestra: {
        if (!dock.elude)
            return false;
        var f = Core.Windows.all || [];
        var r = dock.ingombro;
        for (var i = 0; i < f.length; i++) {
            var w = f[i];
            if (w.minimized === true)
                continue;
            // Solo la scrivania che si sta guardando: una finestra su
            // un'altra scrivania non copre niente di quello che si vede.
            if (w.workspace !== undefined && Core.Compositore.scrivaniaAttiva > 0
                && w.workspace !== Core.Compositore.scrivaniaAttiva)
                continue;
            if (w.w === undefined || w.h === undefined)
                continue;
            if (w.x < r.x + r.width && w.x + w.w > r.x
                && w.y < r.y + r.height && w.y + w.h > r.y)
                return true;
        }
        return false;
    }

    onCopertaDaUnaFinestraChanged: {
        if (!dock.elude)
            return;
        if (dock.copertaDaUnaFinestra) {
            if (!dockArea.containsMouse)
                hideSoon.restart();
        } else {
            hideSoon.stop();
            dock.revealed = true;
        }
    }
    property real opacity_: 0.90
    /// Etichetta col nome al passaggio.
    property bool showLabels: true
    /// Righe di app tenute ferme, per identificatore .desktop.
    property var pinned: []

    readonly property bool it: Core.Strings.lang === "it"

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: dock.consenso ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    /// Il menu di un'icona deve crescere verso il basso: lo legge chi lo apre,
    /// che sta fuori di qui (`shell.qml`). È una conseguenza di `inAlto` e non
    /// una preferenza a sé — sta scritta perché chi apre il menu non può
    /// dedurla, e indovinandola la sbaglierebbe metà delle volte.
    readonly property bool menuVersoIlBasso: dock.inAlto

    /// La dock sta in cima allo schermo invece che in fondo.
    ///
    /// ── Tutto quello che «va verso l'alto» cambia verso ──────────────────
    ///
    /// La dock non è una striscia appoggiata da qualche parte: è geometria che
    /// sa da che parte è il bordo dello schermo. Le icone crescono verso
    /// l'INTERNO, l'etichetta esce dalla parte opposta al bordo, il segno di
    /// «in esecuzione» sta dal lato del bordo, la colonna sensibile al
    /// puntatore arriva fino al bordo perché lì il puntatore ci si ferma
    /// contro, e ritirandosi la dock esce dal bordo. Sono sei cose, e sbagliare
    /// il verso di una sola vuol dire un bersaglio che non si può prendere.
    ///
    /// Il verso passa da qui, e da nessun'altra parte in questo file si guarda
    /// l'impostazione.
    property bool inAlto: false

    // ── Questi tre ancoraggi li legge anche il VETRO ─────────────────────
    //
    // `vetroDock.schermoX/schermoY` ricavano da qui dove sta l'angolo della
    // dock sullo schermo, e da lì quale fetta dello sfondo sfocato mostrare.
    // Il conto è: in basso → `screen.height - dock.height + body.y`; in alto →
    // `body.y` e basta, perché la finestra parte dal bordo dello schermo. A
    // sinistra e a destra → x zero. Cambiando questi ancoraggi va cambiato
    // anche quello, o il vetro slitta e mostra un pezzo di cielo che non è
    // quello che c'è dietro. È scritto qui e non solo là perché una dipendenza
    // che si vede da un capo solo è una dipendenza che si rompe.
    anchors { top: dock.inAlto; bottom: !dock.inAlto; left: true; right: true }
    color: "transparent"
    visible: dock.enabled && dock.items.length > 0

    // Solo il modo «sempre» si prende il suo spazio: le finestre affiancate si
    // fermano sopra invece di finirci sotto. Gli altri due non riservano
    // niente — è il senso di togliersi di mezzo, e per «elude» è tutto il
    // punto: la finestra prende lo schermo intero, e la dock si sposta.
    exclusionMode: dock.autoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: dock.autoHide ? 0 : dock.barHeight + Theme.Effects.space2

    // ── Geometria a riposo ───────────────────────────────────────────────
    //
    // Tutto quello che sta qui sotto dipende SOLO dalle preferenze e da quante
    // icone ci sono. Nessuna di queste grandezze può cambiare per via del
    // puntatore, ed è precisamente ciò che impedisce il battito.

    readonly property int cell: dock.iconSize
    readonly property int gapPx: Theme.Effects.space2
    readonly property int barHeight: dock.iconSize + Theme.Effects.space3 * 2

    /// Di quanto si scosta al massimo una icona per far posto alla vicina
    /// ingrandita. Costante: dipende dall'ingrandimento massimo, non da quello
    /// in corso.
    readonly property real spread: (dock.magnification - 1) * dock.iconSize * 0.55

    readonly property int count: dock.items.length
    readonly property real restWidth: dock.count > 0
                                      ? dock.count * dock.cell + (dock.count - 1) * dock.gapPx
                                      : 0
    /// Margine interno: quello standard più lo spazio che serve alle icone di
    /// bordo per scostarsi senza uscire dalla dock.
    readonly property real padX: Theme.Effects.space3 + dock.spread

    readonly property real bodyWidth: Math.min(dock.width - Theme.Effects.space5 * 2,
                                               dock.restWidth + dock.padX * 2)
    readonly property real bodyX: (dock.width - dock.bodyWidth) / 2
    /// Sinistra della fila di caselle, in coordinate della finestra.
    readonly property real stripX: dock.bodyX + (dock.bodyWidth - dock.restWidth) / 2

    /// Di quanto un'icona può salire sopra la propria casella, al massimo.
    /// Costante — dipende dall'ingrandimento MASSIMO, non da quello in corso —
    /// perché su questa misura si disegnano i bersagli dei clic, e un
    /// bersaglio che si muove è il difetto che questo file combatte da cima a
    /// fondo.
    readonly property int crescitaMax: Math.ceil(dock.cell * (dock.magnification - 1))

    /// I due bordi della fila di icone quando sono cresciute tutte. Cresce
    /// solo dalla parte dell'interno dello schermo: dall'altra c'è il bordo.
    readonly property int cimaIcone: dock.shownY
                                     + (dock.barHeight - dock.cell) / 2
                                     - (dock.inAlto ? 0 : dock.crescitaMax)
    readonly property int fondoIcone: dock.shownY
                                      + (dock.barHeight + dock.cell) / 2
                                      + (dock.inAlto ? dock.crescitaMax : 0)

    /// Spazio sopra la dock in cui l'icona ingrandita può crescere.
    readonly property int headroom: Math.ceil(dock.iconSize * (dock.magnification - 1))
                                    + Theme.Effects.space5

    implicitHeight: dock.barHeight + dock.headroom + Theme.Effects.space3

    // Dichiarata, non dedotta dal contenuto. La dock è ancorata a sinistra e a
    // destra, quindi la sua larghezza la decide lo schermo — ma se non lo si
    // dice, Quickshell la ricava dai figli, e siccome la larghezza del corpo si
    // ricava dalla larghezza della finestra si chiude un anello: Qt lo segnala
    // come «Binding loop detected for property width» e ricalcola il gruppo a
    // ogni fotogramma per niente.
    implicitWidth: dock.screen ? dock.screen.width : 1920

    readonly property int shownY: dock.inAlto
        ? Theme.Effects.space3
        : dock.height - dock.barHeight - Theme.Effects.space3
    /// Ritirata: resta due pixel dentro lo schermo, dal lato da cui è uscita.
    readonly property int hiddenY: dock.inAlto ? 2 - dock.barHeight
                                               : dock.height - 2

    /// Angolo in alto a sinistra della dock in coordinate dello SCHERMO.
    ///
    /// Serve per aprire i menu nel punto giusto, e va calcolato: su Wayland un
    /// programma non sa dove sia la propria finestra, e `mapToGlobal` di una
    /// superficie layer-shell risponde come se stesse in cima allo schermo. È
    /// il motivo per cui il menu del tasto destro compariva in alto invece che
    /// sopra l'icona. Qui lo sappiamo per costruzione: la dock è ancorata in
    /// basso e larga quanto lo schermo.
    readonly property int originX: dock.screen ? dock.screen.x : 0
    readonly property int originY: dock.inAlto
        ? (dock.screen ? dock.screen.y : 0)
        : (dock.screen ? dock.screen.y + dock.screen.height : dock.height)
          - dock.height

    /// La striscia che la dock occupa SEMPRE, aperta o chiusa.
    ///
    /// Serve alla Spine: con un pannello aperto la sua maschera si prende tutto
    /// lo schermo per poter raccogliere il clic che chiude (vedi `Spine.qml`),
    /// e così facendo si prendeva anche il fondo — dove la dock aspetta di
    /// essere sfiorata. Risultato: con il menù aperto la dock non compariva
    /// più. Giacomo, 2 agosto.
    ///
    /// `screenRect` qui sotto non basta, perché esiste solo a dock GIÀ aperta:
    /// è il rettangolo da non coprire, non quello da cui farla uscire.
    /// Largo quanto il CORPO della dock, non quanto lo schermo: la dock sta in
    /// mezzo, e farla uscire mettendo il puntatore nell'angolo in basso a
    /// destra sarebbe una sorpresa. Un margine per parte perché il bersaglio
    /// non sia più stretto di quello che si vede.
    readonly property rect hoverRect: dock.visible
        ? Qt.rect(dock.originX + Math.round(dock.bodyX) - Theme.Effects.space5,
                  dock.originY,
                  Math.round(dock.bodyWidth) + Theme.Effects.space5 * 2,
                  dock.height)
        : Qt.rect(0, 0, 0, 0)

    /// Dove sta il CORPO della dock, in coordinate dello schermo. Serve a chi
    /// mette superfici sopra tutto e non vuole coprire proprio la dock.
    readonly property rect screenRect: (dock.visible && dock.revealed)
        ? Qt.rect(dock.originX + Math.round(dock.bodyX) - 6,
                  dock.originY + dock.shownY - 2,
                  Math.round(dock.bodyWidth) + 12,
                  dock.barHeight + 4)
        : Qt.rect(0, 0, 0, 0)

    // ── Cosa mostrare ────────────────────────────────────────────────────
    //
    // Le voci sono APPLICAZIONI, non finestre. Tre finestre dello stesso
    // programma sono una icona con tre pallini sotto, non tre icone: è così
    // che si ritrova la cosa che si stava usando invece di leggere una fila di
    // rettangoli tutti uguali.
    //
    // Le finestre di Minerva stessa non arrivano fin qui: le toglie
    // `Core.Windows`, e il motivo è scritto lì.

    property var items: []

    Connections {
        target: Core.Apps
        function onAllChanged() { dock.rebuild(); }
    }

    Connections {
        target: Core.Windows
        function onAllChanged() { dock.rebuild(); }
    }

    // La dock si rifà anche quando cambia l'ELENCO DEI PROGRAMMI, e non solo
    // quando cambiano le finestre.
    //
    // Sembra superfluo — le finestre cambiano di continuo — e non lo è: quando
    // il tema delle icone cambia, il demone rimanda l'elenco con i percorsi
    // nuovi, ma le finestre restano quelle di prima. Senza questa riga la dock
    // aspetta il primo movimento di una finestra per accorgersene, e a
    // scrivania ferma non se ne accorge mai. È metà del difetto che Giacomo ha
    // descritto come «le icone anche se le cambio nella dock non cambiano»;
    // l'altra metà stava nel demone, che l'elenco non lo rimandava affatto.
    Connections {
        target: Core.Apps
        function onAllChanged() { dock.rebuild(); }
    }

    onPinnedChanged: dock.rebuild()
    Component.onCompleted: dock.rebuild()

    /// Vero se è arrivato un cambiamento mentre si trascinava.
    property bool _daRifare: false

    function rebuild() {
        // ── Non si riordina con un'icona in mano ─────────────────────────
        //
        // Da quando il modello si aggiorna sul posto (vedi `sincronizza`) i
        // delegati non muoiono più, quindi il gesto non si spezza. Ma vedersi
        // riordinare le icone sotto le dita mentre se ne sta spostando una
        // resterebbe comunque incomprensibile: il cambiamento si segna e si
        // applica appena la mano lascia (`finisciTrascina`).
        if (dock.dragIndex >= 0) {
            dock._daRifare = true;
            return;
        }
        var out = [];
        var byKey = {};
        var i, key;

        // Prima le fisse, nell'ordine scelto: la dock deve stare ferma. Se le
        // icone si spostano ogni volta che si apre un programma, la memoria
        // muscolare non si forma mai e ogni clic diventa una ricerca.
        for (i = 0; i < dock.pinned.length; i++) {
            var app = Core.Apps.byId(dock.pinned[i]);
            if (!app)
                continue;
            key = app.appId;
            byKey[key] = out.length;
            out.push({
                "key": key, "appId": app.appId, "name": app.name,
                "icon": app.icon || "", "exec": app.exec,
                "nuovaFinestra": app.nuovaFinestra || "",
                "pinned": true, "addresses": [], "active": false
            });
        }

        // Poi ciò che sta girando e non era già in elenco.
        var wins = Core.Windows.all || [];
        for (i = 0; i < wins.length; i++) {
            var w = wins[i];
            var wapp = Core.Apps.forWindow(w);
            key = wapp ? wapp.appId : ("class:" + w.appClass);
            if (byKey[key] === undefined) {
                byKey[key] = out.length;
                out.push({
                    "key": key,
                    "appId": wapp ? wapp.appId : "",
                    "name": wapp ? wapp.name : (w.appClass || w.title),
                    "icon": wapp ? (wapp.icon || "") : "",
                    "exec": wapp ? wapp.exec : "",
                    "nuovaFinestra": wapp ? (wapp.nuovaFinestra || "") : "",
                    "pinned": false, "addresses": [], "active": false
                });
            }
            var slot = out[byKey[key]];
            slot.addresses.push({
                "address": w.address, "title": w.title, "minimized": w.minimized
            });
            if (w.address === Core.Windows.activeAddress)
                slot.active = true;
        }

        // La finestra è arrivata: il segno «sto partendo» ha finito il suo
        // lavoro e si spegne, senza aspettare gli otto secondi.
        if (dock._avviando !== "") {
            for (var q = 0; q < out.length; q++) {
                if (out[q].key === dock._avviando
                    && out[q].addresses.length > 0) {
                    dock._avviando = "";
                    fineAvvio.stop();
                    break;
                }
            }
        }

        dock.items = out;
        dock.sincronizza();
    }

    // ── Il modello del Repeater si aggiorna SUL POSTO ────────────────────
    //
    // Qui c'era `model: dock.items`, cioè un array JavaScript rifatto a ogni
    // lettura delle finestre. Un Repeater con un array nuovo non aggiorna i
    // delegati: **li distrugge e li ricostruisce tutti**.
    //
    // Costava due cose. La prima è che qualunque gesto in corso moriva a metà,
    // perché fra i figli distrutti c'è l'area che sta tenendo la presa del
    // mouse. La seconda è che a ogni lettura ripartiva tutto da zero:
    // animazioni, passaggio del puntatore, icone da ricaricare.
    //
    // E non è raro. Misurato il 4 agosto: il demone manda l'elenco finestre
    // **1,1 volte al secondo** — basta un terminale con una rotellina animata
    // nel titolo, o un lettore che ci scrive il minuto della canzone. Una
    // dock che si ricostruisce intera ogni secondo, per sempre.
    //
    // Un `ListModel` aggiornato sul posto non ha nessuno dei due problemi: le
    // righe restano le stesse finché l'icona esiste, cambiano solo i valori,
    // e i delegati se ne accorgono senza morire. È la stessa lezione già
    // imparata dalle barre del titolo (`spine/TitleBars.qml`), applicata qui.
    ListModel {
        id: modelloIcone
        dynamicRoles: true
    }

    function sincronizza() {
        var voluti = dock.items;
        var i, j;

        // Via quelle che non ci sono più.
        for (i = modelloIcone.count - 1; i >= 0; i--) {
            var vivo = false;
            for (j = 0; j < voluti.length; j++) {
                if (voluti[j].key === modelloIcone.get(i).chiave) {
                    vivo = true;
                    break;
                }
            }
            if (!vivo)
                modelloIcone.remove(i);
        }

        // Le altre: al posto giusto, coi valori aggiornati.
        for (i = 0; i < voluti.length; i++) {
            var v = voluti[i];
            var dove = -1;
            for (j = 0; j < modelloIcone.count; j++) {
                if (modelloIcone.get(j).chiave === v.key) {
                    dove = j;
                    break;
                }
            }
            if (dove === -1) {
                modelloIcone.insert(Math.min(i, modelloIcone.count),
                                    { "chiave": v.key, "voce": v });
            } else {
                if (dove !== i)
                    modelloIcone.move(dove, i, 1);
                // `setProperty` e non `set`: `set` riscrive la riga intera e
                // il delegato la vede come un'altra icona.
                modelloIcone.setProperty(i, "voce", v);
            }
        }
    }

    // ── Nascondersi ──────────────────────────────────────────────────────
    //
    // Da nascosta resta una striscia di due pixel in fondo allo schermo che
    // aspetta il puntatore. Due e non zero: a zero non c'è niente da toccare,
    // e la dock non tornerebbe più.

    /// Chiesta da fuori. La usa la Spine quando un pannello aperto le ha
    /// tolto il passaggio del puntatore — vedi `Spine.qml`, e il difetto noto
    /// di Hyprland citato lì.
    property bool forceReveal: false

    /// La riva riservata (una finestra riempie lo schermo): sfiorarla non la
    /// fa uscire. Giacomo, 25 settembre 2026: «se ho una app a schermo
    /// intero compaiono le isole passandoci sopra».
    property bool riservata: false
    /// Super tenuto con la riva riservata: esce, sopra a tutto.
    property bool consenso: false
    onConsensoChanged: {
        if (dock.consenso) {
            dock.revealed = true;
            hideSoon.stop();
        } else if (dock.autoHide && !dockArea.containsMouse) {
            hideSoon.restart();
        }
    }

    property bool revealed: !dock.autoHide

    onForceRevealChanged: {
        if (dock.forceReveal) {
            dock.revealed = true;
            hideSoon.stop();
        } else if (dock.autoHide && !dockArea.containsMouse) {
            hideSoon.restart();
        }
    }

    Timer {
        id: hideSoon
        interval: 450
        onTriggered: {
            if (!dock.autoHide || dockArea.containsMouse || dock.consenso)
                return;
            // In «elude» ci si ritira solo se una finestra la copre davvero:
            // a scrivania libera la dock resta dov'è.
            if (dock.elude && !dock.copertaDaUnaFinestra)
                return;
            dock.revealed = false;
        }
    }

    onModoChanged: {
        // Cambiando modo si riparte da visibile: qualunque sia il modo nuovo,
        // la dock si fa vedere e poi decide. Sparire nell'istante in cui si
        // tocca l'impostazione farebbe sembrare che si sia rotto qualcosa.
        //
        // E POI decide davvero. La prima versione di questa riga si fermava
        // qui per «nascondi», e la prova l'ha presa subito: scegliendo «si
        // nasconde da sola» la dock restava lì finché non le si passava sopra
        // col puntatore. Un'impostazione che non fa niente finché non la
        // tocchi con la mano sembra un'impostazione rotta.
        hideSoon.stop();
        dock.revealed = true;
        if (dockArea.containsMouse)
            return;

        // ── Si legge `modo`, NON `siNasconde` ed `elude` ─────────────────
        //
        // Quelle due sono legami che dipendono da `modo`, e quando `modo`
        // cambia QML non promette in che ordine rivaluta i legami e chiama i
        // gestori: dentro questo gestore possono valere ancora quelle di
        // PRIMA. Passando da «elude» a «nascondi» succedeva esattamente
        // questo — `siNasconde` era ancora falso, `elude` ancora vero, e
        // nessuno dei due rami faceva ripartire il timer: la dock restava lì.
        //
        // Trovato da `compositore/prova-dock.py` alla prima passata, e la
        // prima ipotesi (il puntatore sopra la dock) era sbagliata: l'ha
        // smentita il pezzo di diagnosi aggiunto all'IPC, che diceva
        // «presente» senza «col-puntatore».
        //
        // `modo` invece è il valore appena arrivato, per definizione: è quello
        // il cui cambiamento ci ha portati qui.
        if (dock.modo === "nascondi"
            || (dock.modo === "elude" && dock.copertaDaUnaFinestra))
            hideSoon.restart();
    }

    // La maschera dichiara quale parte della finestra è cliccabile. Segue la
    // geometria A RIPOSO e non il corpo animato: una maschera che cambia a
    // ogni fotogramma obbliga il compositore a ricalcolare la regione di
    // input sessanta volte al secondo, e si vede — è metà della sensazione di
    // «scatti».
    //
    // Copre il corpo della dock e TUTTO ciò che sta sotto, fino al bordo dello
    // schermo — e in alto arriva fino alla CIMA DELLE ICONE CRESCIUTE, non al
    // bordo del corpo.
    //
    // Prima si fermava al corpo, e la differenza si vedeva: un'icona
    // ingrandita è alta settantadue pixel contro i quarantacinque della sua
    // casella, quindi la sua parte alta sporgeva in una zona che non
    // raccoglieva clic. Giacomo, 4 agosto: «se la trascino dal lato basso si
    // spostano, se la trascino dal lato alto no, anche l'apertura a volte non
    // va». Si stava cliccando sull'icona — si vedeva benissimo — e non
    // succedeva niente.
    //
    // Sopra la cima delle icone lo schermo resta dell'utente, che era il
    // motivo giusto per cui la maschera non saliva: si regala solo quello che
    // non è disegnato.
    //
    // La striscia in fondo è la parte che al primo tentativo mancava, ed era
    // un errore mio nel disegnare questa maschera: sotto la dock restavano una
    // decina di pixel morti, in cui il puntatore non veniva più sentito. Si
    // notava eccome — è proprio lì che il mouse finisce quando lo si butta
    // giù di slancio.
    //
    // E il bordo dello schermo non è un pixel qualunque: è un bersaglio che
    // non si può mancare, perché il puntatore ci si ferma contro. Regalarlo
    // vuol dire trasformare il gesto «vai in fondo e clicca» — che non
    // richiede nessuna mira — in «centra una fila di icone alta quarantotto
    // pixel». Adesso la dock arriva davvero fino in fondo.
    //
    // La striscia arriva sempre fino al bordo DELLO SCHERMO, che con la dock
    // in cima è il bordo alto: è lo stesso ragionamento specchiato, e vale
    // uguale — il puntatore si ferma contro il bordo di sopra come contro
    // quello di sotto.
    mask: Region {
        x: dock.revealed ? Math.round(dock.bodyX) - 6 : 0
        y: dock.revealed ? (dock.inAlto ? 0 : dock.cimaIcone - 2)
                         : (dock.inAlto ? 0 : dock.height - 3)
        width: dock.revealed ? Math.round(dock.bodyWidth) + 12 : dock.width
        height: dock.revealed
                ? (dock.inAlto ? dock.fondoIcone + 2
                               : dock.height - dock.cimaIcone + 2)
                : 3
    }

    // UN SOLO rilevatore del puntatore per tutta la dock, ed è importante che
    // sia uno solo.
    //
    // La prima versione lasciava che ogni icona sentisse il mouse per conto
    // suo (`hoverEnabled` sul riquadro dell'icona). In Qt un'area che ascolta
    // il passaggio del mouse se lo PRENDE, e chi sta sotto non lo vede più:
    // appoggiando il puntatore in mezzo a una icona, l'area della dock
    // smetteva di sentirlo e l'ingrandimento si spegneva. Restava acceso solo
    // sul bordo alto e sul bordo basso della dock, dove nessuna icona lo
    // intercettava — ed è esattamente il difetto che si vedeva: «devo stare o
    // sulla parte alta o sulla parte bassa per farla ingrandire».
    //
    // Qui il puntatore lo sente solo questa area. Ogni icona ricava da sé se
    // è quella sotto il dito, confrontando le coordinate: un conto che dà
    // sempre la stessa risposta e non se la può far rubare da nessuno.
    MouseArea {
        id: dockArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: {
            if (containsMouse) {
                // Riservata e nascosta: il passaggio non basta, serve Super.
                if (dock.riservata && !dock.consenso && !dock.revealed)
                    return;
                dock.revealed = true;
                hideSoon.stop();
            } else if (dock.siNasconde) {
                hideSoon.restart();
            } else if (dock.elude && dock.copertaDaUnaFinestra) {
                hideSoon.restart();
            }
        }
    }

    /// Forza dell'ingrandimento: 0 a riposo, 1 col puntatore sulla dock.
    /// È l'UNICA cosa animata dell'effetto, ed è una sola per tutta la fila:
    /// così le icone entrano e escono dall'ingrandimento insieme.
    /// Mentre si trascina, l'ingrandimento si spegne. Due motivi, e il primo
    /// da solo basterebbe:
    ///
    ///  · l'ingrandimento SPOSTA le caselle di lato (`shift`), e su quelle
    ///    caselle si misura dove sta il dito. Muovere il metro mentre si
    ///    misura chiude un anello: misurato, il valore rimbalzava fra due
    ///    numeri all'infinito e il gesto non finiva mai;
    ///  · e a icone equidistanti si vede molto meglio dove si sta per
    ///    lasciare quella che si ha in mano.
    readonly property real magStrength:
        (dockArea.containsMouse && dock.revealed && dock.magnification > 1.001
         && dock.dragIndex < 0) ? 1 : 0
    property real magEased: 0
    Behavior on magEased {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    onMagStrengthChanged: dock.magEased = dock.magStrength

    /// Puntatore in coordinate della fila di caselle. Non è animato: le icone
    /// devono stare SOTTO il dito, non rincorrerlo.
    readonly property real pointerLocal:
        dockArea.containsMouse ? dockArea.mouseX - dock.stripX : -99999

    // ── Rimettere le icone in ordine trascinandole ───────────────────────
    //
    // Giacomo, 3 agosto: «la dock non mi fa spostare le icone se voglio
    // cambiare l'ordine». L'ordine c'era già — è `dock.pinned`, e la dock lo
    // rispetta apposta perché la memoria muscolare si formi — ma si poteva
    // cambiare solo togliendo e rimettendo le icone, cioè non si poteva.
    //
    // Si trascinano SOLO le fisse. Le altre sono lì perché stanno girando, e
    // il loro posto lo decide l'ordine in cui le hai aperte: spostarle
    // vorrebbe dire promettere un ordine che sparisce alla prossima chiusura.
    //
    // ── Perché una soglia prima di cominciare ───────────────────────────
    //
    // Senza, ogni clic un po' mosso diventerebbe un trascinamento da un
    // pixel, e chi voleva aprire un programma si ritroverebbe l'ordine
    // cambiato. Sei pixel sono più del tremolio di una mano e meno di un
    // gesto voluto.
    readonly property int sogliaTrascina: 6

    /// Indice dell'icona che si sta trascinando, -1 se nessuna.
    property int dragIndex: -1
    /// Dove sta adesso, in coordinate della fila.
    property real dragX: 0
    /// Dove andrebbe a finire se la lasciassi ora.
    property int dragTarget: -1

    /// Quante icone in testa sono fisse: oltre quelle non si può spostare
    /// niente, perché lì l'ordine non è nostro.
    readonly property int quanteFisse: {
        var n = 0;
        for (var i = 0; i < dock.items.length; i++) {
            if (!dock.items[i].pinned)
                break;
            n++;
        }
        return n;
    }

    /// Il posto che un'icona OCCUPA mentre un'altra la sta scavalcando.
    ///
    /// Non si sposta niente davvero finché non si lascia: si sposta solo il
    /// disegno, così il buco si apre dove l'icona andrebbe a finire e si vede
    /// dove si sta per lasciarla.
    function postoVisivo(i) {
        if (dock.dragIndex < 0 || dock.dragTarget < 0 || i === dock.dragIndex)
            return i;
        var da = dock.dragIndex;
        var a = dock.dragTarget;
        if (da < a && i > da && i <= a)
            return i - 1;
        if (da > a && i >= a && i < da)
            return i + 1;
        return i;
    }

    function iniziaTrascina(i, x) {
        if (i < 0 || i >= dock.quanteFisse)
            return;
        dock.dragIndex = i;
        dock.dragTarget = i;
        dock.dragX = x;
    }

    function muoviTrascina(x) {
        if (dock.dragIndex < 0)
            return;
        dock.dragX = x;
        // Il bersaglio è la casella in cui è finito il CENTRO dell'icona
        // trascinata. Si arrotonda, così scambia a metà strada e non quando
        // ha già scavalcato del tutto la vicina.
        var passo = dock.cell + dock.gapPx;
        var t = Math.round((x - dock.cell / 2) / passo);
        dock.dragTarget = Math.max(0, Math.min(dock.quanteFisse - 1, t));
    }

    function finisciTrascina() {
        if (dock.dragIndex < 0)
            return;
        var da = dock.dragIndex;
        var a = dock.dragTarget;
        dock.dragIndex = -1;
        dock.dragTarget = -1;
        // Se nel frattempo è cambiato qualcosa, adesso si può recepire.
        if (dock._daRifare) {
            dock._daRifare = false;
            dock.rebuild();
        }
        if (da === a || a < 0)
            return;

        // ── Si cerca PER NOME, non per posizione ─────────────────────────
        //
        // `items` e `pinned` sembrano allineati e non lo sono: `rebuild()`
        // SALTA le fisse che non risultano più installate (`Apps.byId` non le
        // trova — un programma disinstallato lascia il suo `.desktop` nelle
        // preferenze). Basta che ne manchi una e i due elenchi scorrono:
        // trascinando la terza icona se ne sposterebbe una quarta, e chi
        // guarda non capirebbe perché.
        //
        // Quindi si prende l'identificatore dell'icona spostata e quello
        // dell'icona su cui è stata lasciata, e si riordina su QUELLI.
        var chiDa = (dock.items[da] || {}).appId || "";
        var chiA = (dock.items[a] || {}).appId || "";
        if (chiDa === "" || chiA === "")
            return;

        var lista = [];
        for (var i = 0; i < dock.pinned.length; i++)
            lista.push(dock.pinned[i]);
        var pDa = lista.indexOf(chiDa);
        var pA = lista.indexOf(chiA);
        if (pDa < 0 || pA < 0 || pDa === pA)
            return;
        var preso = lista.splice(pDa, 1)[0];
        lista.splice(pA, 0, preso);
        dock.pinnedChangeRequested(lista);
    }

    // ── Il corpo ─────────────────────────────────────────────────────────

    Rectangle {
        id: body

        x: dock.bodyX
        width: dock.bodyWidth
        y: dock.revealed ? dock.shownY : dock.hiddenY
        height: dock.barHeight

        radius: Theme.Effects.radiusLG

        // ── Il colore viene dal TEMA, non da qui ─────────────────────────
        //
        // Qui c'era `Qt.rgba(0.031, 0.043, 0.078, …)`: un blu quasi nero
        // scritto a mano. Con un tema chiaro la barra della scrivania
        // diventava chiara e la dock restava nera — le due estremità dello
        // stesso schermo, di due mondi diversi. Visto l'11 agosto passando a
        // «giorno»: barra (189,197,206), dock (29,35,48).
        //
        // `membrane` è la stessa superficie della barra, e segue la tinta e il
        // verso del tema. La sola cosa che resta della dock è la sua
        // trasparenza, che è una manopola sua.
        color: Qt.rgba(Theme.Colors.membrane.r, Theme.Colors.membrane.g,
                       Theme.Colors.membrane.b, dock.opacity_)
        border.width: 1
        border.color: Theme.Colors.edge

        // ── IL VETRO ─────────────────────────────────────────────────────
        //
        // Lo sfondo già sfocato, ritagliato sulla forma della dock, e sopra di
        // lui la tinta del tema.
        //
        // ── Il commento che stava qui diceva il falso ────────────────────
        //
        // «Disegnato SOTTO la tinta del rettangolo — questo Canvas gli sta
        // dentro come primo figlio, quindi sotto a tutto il resto.» In QML è
        // il contrario: un figlio si disegna SOPRA il fondo del padre, sempre,
        // e «primo figlio» vuol dire solo primo fra i figli.
        //
        // Conseguenza, misurata il 3 settembre 2026 con due fotografie: il
        // quadro sfocato copriva la tinta, e **la dock non seguiva il tema**.
        // Passando da «notte» a «giorno» il pixel a (1350,1035) restava
        // identico, (49,102,146), mentre la barra si schiariva. È lo stesso
        // difetto già corretto una volta l'11 agosto — «la dock restava nera
        // mentre tutto il resto si schiariva» — tornato per un'altra strada,
        // e invisibile perché su uno sfondo scuro una dock scura sembra giusta.
        //
        // Adesso la tinta la mette il Canvas, dentro lo stesso ritaglio: prima
        // il quadro, poi il velo del tema, poi il filo del bordo. Il colore del
        // rettangolo qui intorno resta, e serve quando il vetro non c'è —
        // macchina senza `magick`, o il primo mezzo secondo di sessione.
        //
        // ── Perché un Canvas e non un ritaglio ───────────────────────────
        //
        // Perché `clip` in QML è rettangolare, e la dock ha gli angoli tondi:
        // un ritaglio normale farebbe sbordare l'immagine ai quattro angoli.
        // La barra non ha questo problema — la sua fascia è un rettangolo
        // pieno — e infatti là il vetro si fa senza Canvas.
        //
        // E non `ShapePath.fillItem`, che sarebbe la strada elegante di
        // Qt 6.8: col renderer software la forma esce **vuota**. Provato il
        // 31 agosto 2026 con una cattura, mentre la stessa forma con un colore
        // pieno si disegna perfettamente. Il Canvas invece è QPainter, cioè
        // esattamente ciò che la shell già usa per tutto il resto.
        Canvas {
            id: vetroDock
            anchors.fill: parent
            visible: Core.Vetro.daDisegnare !== "" && !!dock.screen
            renderStrategy: Canvas.Immediate
            renderTarget: Canvas.Image

            /// Dove sta l'angolo in alto a sinistra della dock sullo schermo.
            /// Serve a far combaciare l'immagine con lo sfondo VERO che le sta
            /// dietro: senza, si vedrebbe un pezzo di cielo fuori posto.
            ///
            /// I due conti vengono dagli ANCORAGGI della finestra (in alto in
            /// questo file: `bottom`, `left`, `right`), non da una misura
            /// chiesta a qualcuno: su Wayland una finestra non sa dove il
            /// compositore l'ha messa. Se quegli ancoraggi cambiano, queste
            /// due righe vanno rifatte — e lassù c'è scritto.
            readonly property real schermoX: body.x
            readonly property real schermoY: dock.inAlto
                ? body.y
                : (dock.screen ? dock.screen.height - dock.height + body.y : 0)

            /// La tinta del tema con la trasparenza della dock. Sta qui e non
            /// dentro `onPaint` perché un Canvas si ridisegna solo se glielo si
            /// chiede: senza questa proprietà e il suo `onChanged`, cambiare
            /// tema lascerebbe la dock com'era fino al primo movimento.
            readonly property color tinta:
                Qt.rgba(Theme.Colors.membrane.r, Theme.Colors.membrane.g,
                        Theme.Colors.membrane.b, dock.opacity_)
            readonly property color filo: Theme.Colors.edge

            onTintaChanged: vetroDock.requestPaint()
            onFiloChanged: vetroDock.requestPaint()

            property var _img: null

            onVisibleChanged: if (visible) vetroDock.carica()
            Component.onCompleted: if (visible) vetroDock.carica()

            function carica() {
                // Col blur vero non c'è niente da caricare: `loadImage("file://")`
                // sarebbe una richiesta a un percorso che non esiste, ripetuta
                // a ogni cambio di sfondo.
                if (Core.Vetro.daDisegnare === "")
                    return;
                var u = "file://" + Core.Vetro.daDisegnare;
                if (vetroDock._img === u && vetroDock.isImageLoaded(u)) {
                    vetroDock.requestPaint();
                    return;
                }
                vetroDock._img = u;
                vetroDock.loadImage(u);
            }

            onImageLoaded: vetroDock.requestPaint()

            Connections {
                target: Core.Vetro
                function onDaDisegnareChanged() { vetroDock.carica(); }
            }

            // Si ridisegna quando la dock si SISTEMA, non a ogni fotogramma
            // dell'animazione: durante la comparsa il vetro scorre insieme
            // alla dock, che è quello che fa un vetro vero portato in giro.
            onSchermoXChanged: rifai.restart()
            onSchermoYChanged: rifai.restart()
            onWidthChanged: rifai.restart()
            // E l'altezza: entra nel raggio degli angoli tondi, quindi una
            // dock più bassa disegnata col raggio di prima ha gli angoli
            // sbagliati. Mancava, e sarebbe stato un difetto che si vede solo
            // dopo aver cambiato la misura delle icone.
            onHeightChanged: rifai.restart()

            Timer {
                id: rifai
                interval: 60
                onTriggered: vetroDock.requestPaint()
            }

            onPaint: {
                var ctx = vetroDock.getContext("2d");
                ctx.reset();
                if (!vetroDock._img || !vetroDock.isImageLoaded(vetroDock._img))
                    return;

                var w = vetroDock.width, h = vetroDock.height;
                var r = Math.min(Theme.Effects.radiusLG, w / 2, h / 2);

                // Il ritaglio a forma: è tutto il motivo per cui qui c'è un
                // Canvas invece di un `clip`.
                ctx.beginPath();
                ctx.moveTo(r, 0);
                ctx.lineTo(w - r, 0);
                ctx.arcTo(w, 0, w, r, r);
                ctx.lineTo(w, h - r);
                ctx.arcTo(w, h, w - r, h, r);
                ctx.lineTo(r, h);
                ctx.arcTo(0, h, 0, h - r, r);
                ctx.lineTo(0, r);
                ctx.arcTo(0, 0, r, 0, r);
                ctx.closePath();
                ctx.save();
                ctx.clip();

                // Lo stesso quadro alla stessa misura dello schermo, e se ne
                // guarda la fetta che tocca: è così che combacia con lo sfondo
                // vero invece di mostrare un cielo schiacciato.
                var sw = dock.screen ? dock.screen.width : w;
                var sh = dock.screen ? dock.screen.height : h;
                ctx.drawImage(vetroDock._img,
                              -vetroDock.schermoX, -vetroDock.schermoY,
                              sw, sh);

                // E sopra il quadro, il velo del tema: è questo che rende la
                // dock della stessa materia della barra invece di una finestra
                // sul muro. Dentro lo stesso ritaglio, quindi con gli stessi
                // angoli tondi.
                ctx.fillStyle = vetroDock.tinta;
                ctx.fillRect(0, 0, w, h);
                ctx.restore();

                // Il filo del bordo, che il rettangolo qui intorno disegna e
                // che questo Canvas gli copriva.
                ctx.strokeStyle = vetroDock.filo;
                ctx.lineWidth = 1;
                ctx.stroke();
            }
        }

        // Si anima la comparsa e la scomparsa, non la larghezza sotto il
        // puntatore: quella non cambia più.
        Behavior on y {
            NumberAnimation {
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.emerge
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: Theme.Motion.quick
                easing.type: Easing.OutCubic
            }
        }
        Behavior on x {
            NumberAnimation {
                duration: Theme.Motion.quick
                easing.type: Easing.OutCubic
            }
        }

        // Un filo di luce sul bordo alto. È l'unico ornamento della dock e
        // serve a staccarla dallo sfondo quando dietro c'è una foto chiara.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 1
            width: parent.width * 0.7
            height: 1
            // Un filo di LUCE su fondo scuro, di OMBRA su fondo chiaro: il
            // bianco che stacca la dock dal nero, sul chiaro non si vede.
            color: Theme.Colors.velo(0.07)
        }
    }

    // ── Le icone ─────────────────────────────────────────────────────────
    //
    // Vivono FUORI dal corpo, non dentro: crescono oltre il suo bordo alto e
    // un figlio non può sporgere dal padre senza che qualcuno prima o poi lo
    // ritagli. Seguono il corpo quando scende, e basta.

    Item {
        id: strip
        x: dock.stripX
        y: body.y + (dock.barHeight - dock.cell) / 2
        width: dock.restWidth
        height: dock.cell

        Repeater {
            model: modelloIcone

            delegate: Item {
                id: slot
                required property var voce
                required property int index

                readonly property var modelData: slot.voce

                readonly property bool running: modelData.addresses.length > 0
                readonly property bool isActive: modelData.active

                /// Se il puntatore è su questa icona. Si calcola invece di
                /// chiederlo a Qt, per il motivo scritto sopra `dockArea`.
                ///
                /// ── Sulla griglia A RIPOSO, non su dove l'icona si trova ────
                ///
                /// Guardava `slot.x`, che comprende lo scostamento
                /// dell'ingrandimento. Due conseguenze, tutte e due sbagliate:
                /// mentre la fila si apre fra un'icona e l'altra restavano
                /// pixel che non appartenevano a nessuno, e il bersaglio si
                /// spostava sotto il dito che lo stava cercando.
                ///
                /// A riposo invece le caselle piastrellano la dock senza
                /// buchi, e ogni pixel appartiene a un'icona sola. È anche
                /// l'unica scelta coerente: `t` — e quindi quanto un'icona
                /// cresce — si calcola già dalla posizione a riposo, quindi
                /// l'icona che cresce di più è esattamente quella nella cui
                /// casella sta il puntatore.
                readonly property real mezzoPasso: (dock.cell + dock.gapPx) / 2

                readonly property bool hovered:
                    dockArea.containsMouse
                    && dock.pointerLocal >= slot.restCentre - slot.mezzoPasso
                    && dock.pointerLocal < slot.restCentre + slot.mezzoPasso

                /// Centro della casella a riposo. Costante.
                readonly property real restCentre: slot.index * (dock.cell + dock.gapPx)
                                                   + dock.cell / 2

                /// Distanza dal puntatore, normalizzata sul raggio d'azione e
                /// limitata a ±1. Il segno dice da che parte scostarsi.
                readonly property real t: {
                    if (dock.magEased <= 0.001)
                        return 1;
                    var reach = Math.max(1, dock.magnificationReach * dock.cell);
                    var d = (slot.restCentre - dock.pointerLocal) / reach;
                    return Math.max(-1, Math.min(1, d));
                }

                /// Quanto cresce. La curva è un coseno e non una retta: una
                /// retta fa «spigolo» sotto il dito e si vede benissimo che è
                /// finta.
                readonly property real grow: {
                    var f = (Math.cos(Math.abs(slot.t) * Math.PI) + 1) / 2;
                    return 1 + (dock.magnification - 1) * f * dock.magEased;
                }

                /// Di quanto si sposta di lato per far posto. Funzione dispari
                /// della distanza: zero sotto il puntatore, zero al limite del
                /// raggio d'azione, massimo a metà strada. Così la fila si
                /// apre e si richiude senza che i due estremi si muovano.
                readonly property real shift:
                    dock.spread * Math.sin(Math.PI * slot.t) * dock.magEased

                /// Vero mentre è questa a essere trascinata.
                readonly property bool inMano: dock.dragIndex === slot.index

                // ── La CASELLA non si muove mai, nemmeno quella in mano ──
                //
                // È la stessa lezione dell'ingrandimento, in cima al file: se
                // la casella seguisse il dito, la posizione del dito — che si
                // misura RISPETTO alla casella — cambierebbe perché la casella
                // si è mossa, e il conto si chiuderebbe su sé stesso. Misurato:
                // il valore rimbalzava fra due numeri all'infinito e il gesto
                // non finiva mai.
                //
                // Quindi qui si muove solo il DISEGNO (vedi `iconHolder`), e
                // la casella con la sua area sensibile resta dov'è. Gli altri
                // scivolano al posto nuovo, ed è quel movimento a dire dove
                // l'icona andrà a finire.
                x: dock.postoVisivo(slot.index) * (dock.cell + dock.gapPx) + slot.shift
                Behavior on x {
                    enabled: dock.dragIndex >= 0 && !slot.inMano
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                // Quella in mano passa sopra le altre, o le scavalcherebbe
                // sparendoci sotto.
                z: slot.inMano ? 10 : 0

                width: dock.cell
                height: dock.cell

                // L'icona cresce verso l'INTERNO dello schermo: dall'altra
                // parte c'è il bordo, e crescere verso il bordo vorrebbe dire
                // uscirne.
                //
                // ── E il verso si dà con una `y`, non con un'ancora ───────
                //
                // La forma naturale sarebbe `anchors.bottom: inAlto ?
                // undefined : parent.bottom`. Non funziona: in QML
                // `undefined` **non stacca** un'ancora già assegnata. L'icona
                // resterebbe incollata al fondo con la dock in cima, e il
                // difetto sparirebbe riavviando la shell — cioè il modo
                // peggiore di sbagliare.
                Item {
                    id: iconHolder
                    width: dock.cell * slot.grow
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Mentre la si trascina, il disegno segue il dito: la
                    // casella sotto resta ferma (vedi sopra il perché).
                    anchors.horizontalCenterOffset:
                        slot.inMano ? dock.dragX - slot.restCentre : 0

                    // E si stacca un po' dal bordo, come una cosa presa in
                    // mano. Piccolo: due pixel bastano a dire «questa la stai
                    // tenendo tu», di più sembra che stia scappando.
                    y: dock.inAlto
                       ? (slot.inMano ? 6 : 0)
                       : parent.height - height - (slot.inMano ? 6 : 0)

                    scale: slotMouse.pressed ? 0.88 : 1
                    Behavior on scale {
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        anchors.margins: Math.round(parent.width * 0.07)
                        source: slot.modelData.icon !== ""
                                ? "file://" + slot.modelData.icon : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        // Si chiede l'immagine già alla dimensione massima:
                        // ridimensionarla a ogni fotogramma mentre cresce
                        // costa più dell'intera animazione.
                        sourceSize.width: Math.ceil(dock.iconSize * dock.magnification)
                        sourceSize.height: Math.ceil(dock.iconSize * dock.magnification)
                        visible: status === Image.Ready
                    }

                    // Ripiego: l'iniziale in un tondo. Un quadrato vuoto dove
                    // le altre hanno un'icona sembra un errore; una lettera
                    // sembra una scelta.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Math.round(parent.width * 0.09)
                        radius: Theme.Effects.radiusSM
                        visible: appIcon.status !== Image.Ready
                        color: Qt.alpha(Theme.Colors.accent, 0.18)
                        border.width: 1
                        border.color: Qt.alpha(Theme.Colors.accent, 0.35)

                        Text {
                            anchors.centerIn: parent
                            text: (slot.modelData.name || "?").charAt(0).toUpperCase()
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Math.max(9, Math.round(parent.height * 0.5))
                            font.weight: Theme.Typography.weightBold
                        }
                    }

                    // Le finestre ridotte a icona si vedono spente: sono lì,
                    // non sono davanti, e la differenza si deve cogliere senza
                    // leggere niente.
                    opacity: {
                        if (!slot.running)
                            return 0.78;
                        for (var i = 0; i < slot.modelData.addresses.length; i++)
                            if (!slot.modelData.addresses[i].minimized)
                                return 1;
                        return 0.45;
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Theme.Motion.quick }
                    }
                }

                // Segno di «in esecuzione»: una lineetta sotto l'icona che si
                // allunga quando la finestra è quella davanti. Un solo segno
                // che cambia forma si legge meglio di tre pallini da contare.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Dal lato del bordo dello schermo, cioè dalla parte da
                    // cui l'icona NON cresce: è l'unico posto in cui una
                    // lineetta non finisce sotto l'icona ingrandita.
                    y: dock.inAlto ? -3 - height : parent.height + 3
                    height: 3
                    radius: 1.5
                    width: !slot.running ? 0 : (slot.isActive ? 18 : 6)
                    color: slot.isActive ? Theme.Colors.accent
                                         : Qt.alpha(Theme.Colors.text, 0.45)

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.Motion.quick
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.Motion.standard
                        }
                    }
                    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
                }

                // ── Il segno «sto partendo» ─────────────────────────────
                //
                // Un punto che pulsa sotto l'icona, dove poi comparirà la
                // lineetta di «sta girando»: quando la finestra arriva, il
                // punto lascia il posto alla lineetta senza che niente si
                // sposti. Sparisce da sé appena il programma è vivo.
                Rectangle {
                    id: spiaAvvio
                    visible: dock._avviando === slot.modelData.key
                             && !slot.running
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dock.inAlto ? -3 - height : parent.height + 3
                    width: 6
                    height: 3
                    radius: 1.5
                    color: Theme.Colors.accent
                    z: 2

                    SequentialAnimation on opacity {
                        running: spiaAvvio.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.25; to: 1
                                          duration: Theme.Motion.panel
                                          easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1; to: 0.25
                                          duration: Theme.Motion.panel
                                          easing.type: Easing.InOutQuad }
                    }
                }

                // ── Il confine fra le tenute e le aperte ────────────────
                //
                // In `rebuild()` le due liste sono concatenate e basta: le app
                // che tieni sempre e quelle che stanno girando adesso finivano
                // una accanto all'altra senza niente in mezzo, e la dock
                // sembrava una fila sola che cambia da sé.
                //
                // Una riga sottile, alta poco più di mezza icona: si vede che
                // c'è un confine e non si vede altro.
                Rectangle {
                    visible: dock.quanteFisse > 0
                             && slot.index === dock.quanteFisse
                    width: Theme.Effects.hairline
                    height: dock.cell * 0.5
                    radius: width / 2
                    color: Theme.Colors.edge
                    x: -dock.gapPx / 2
                    anchors.verticalCenter: iconHolder.verticalCenter
                    z: 1
                }

                // ── Quante sono ─────────────────────────────────────────
                //
                // La lineetta dice «sta girando» e basta: due finestre di
                // Chrome e sette avevano lo stesso identico segno. Il numero
                // c'era già nel modello — `addresses` è l'elenco delle
                // finestre di quell'applicazione, coi loro titoli — e non lo
                // guardava nessuno.
                //
                // Compare solo da due in su: su una finestra sola un «1»
                // sarebbe rumore, perché la lineetta lo dice già.
                Rectangle {
                    id: contatore
                    readonly property int quante:
                        slot.modelData.addresses
                        ? slot.modelData.addresses.length : 0
                    visible: contatore.quante > 1
                    width: 16
                    height: 16
                    radius: 8
                    color: Theme.Colors.accent
                    border.width: Theme.Effects.hairline
                    border.color: Qt.alpha(Theme.Colors.base, 0.6)
                    // Sull'angolo dell'icona, dal lato del bordo dello
                    // schermo: dall'altro finirebbe sotto l'ingrandimento
                    // delle vicine.
                    x: iconHolder.x + iconHolder.width - width + 2
                    y: dock.inAlto ? iconHolder.y + iconHolder.height - height + 2
                                   : iconHolder.y - 2
                    z: 20

                    Text {
                        anchors.centerIn: parent
                        text: contatore.quante > 9 ? "9+" : contatore.quante
                        color: Theme.Colors.textOnAccent
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                        font.weight: Theme.Typography.weightBold
                    }
                }

                // ── Il nome al passaggio ────────────────────────────────
                //
                // Qui c'era una targhetta rifatta a mano: stesso disegno di
                // `ui/ToolTipHint.qml` — quella che usa tutto il resto della
                // shell — ma senza la cosa che conta, il **mezzo secondo di
                // attesa**. Attraversando una fila di dodici icone per
                // arrivare all'ultima si accendevano dodici targhette una
                // dopo l'altra.
                //
                // E si girava da sé guardando `dock.inAlto`; la targhetta di
                // tutti si gira guardando dove finisce, che è la stessa cosa
                // detta senza sapere di essere una dock.
                Ui.ToolTipHint {
                    text: slot.modelData.name
                    shown: dock.showLabels && slot.hovered
                    z: 50
                }

                // L'area sensibile NON è l'icona: è la sua COLONNA, dal bordo
                // alto dell'icona fino al bordo dello schermo.
                //
                // Fermarla al riquadro dell'icona lasciava una striscia morta
                // fra la lineetta di «in esecuzione» e il fondo dello schermo:
                // il puntatore era visibilmente sulla dock, il corpo era lì
                // sotto il dito, e il clic non faceva niente. Il bordo dello
                // schermo è invece il bersaglio più facile che esista — ci si
                // sbatte contro senza mirare — e sprecarlo è un peccato che
                // costa a ogni clic della giornata.
                //
                // Larga quanto la casella, non quanto l'icona ingrandita: la
                // colonna deve restare ferma mentre l'icona cresce, altrimenti
                // il bersaglio si muove sotto il dito che lo sta cercando.
                MouseArea {
                    id: slotMouse
                    // Ferma sulla casella a riposo, non su dove l'icona si
                    // trova adesso: `slot.x` comprende lo scostamento
                    // dell'ingrandimento, e seguirlo faceva scappare il
                    // bersaglio da sotto il dito. Il mezzo passo per parte
                    // chiude anche i vuoti fra un'icona e l'altra: così ogni
                    // pixel della dock apre qualcosa. Giacomo, 2 agosto: «per
                    // aprire una app devi metterti giusto al centro
                    // dell'icona».
                    x: -slot.shift - dock.gapPx / 2
                    // Comincia dove comincia l'icona CRESCIUTA, non dove
                    // comincia la casella: fra le due ci sono ventisette
                    // pixel di icona che si vede e non si poteva toccare.
                    // Costante, come tutto il resto dei bersagli qui dentro:
                    // segue la crescita MASSIMA e non quella in corso, o il
                    // bersaglio si muoverebbe sotto il dito.
                    //
                    // E arriva al bordo DELLO SCHERMO dalla parte giusta: in
                    // basso se la dock sta in fondo, in cima se sta in cima.
                    // È il bersaglio che non si può mancare, perché il
                    // puntatore ci si ferma contro — regalarlo vuol dire
                    // trasformare «vai al bordo e clicca» in «centra una fila
                    // di icone».
                    y: dock.inAlto ? -strip.y : -dock.crescitaMax
                    width: dock.cell + dock.gapPx
                    height: dock.inAlto
                            ? strip.y + dock.cell + dock.crescitaMax
                            : Math.max(dock.cell, dock.height - strip.y)
                              + dock.crescitaMax
                    // Niente `hoverEnabled`: ruberebbe il puntatore all'area
                    // della dock e spegnerebbe l'ingrandimento. Vedi sopra.
                    hoverEnabled: false
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    // Senza, appena il puntatore si muove col tasto premuto
                    // l'area grande della dock — quella che serve
                    // all'ingrandimento — si riprende la presa, e al posto del
                    // rilascio arriva un annullamento: il trascinamento
                    // moriva a metà senza dire niente.
                    preventStealing: true

                    /// Dove il tasto è stato premuto, in coordinate della
                    /// fila. Serve a misurare quanto ci si è spostati prima di
                    /// decidere che è un trascinamento e non un clic mosso.
                    property real premutoA: -99999
                    property bool trascinando: false

                    onPressed: function(m) {
                        slotMouse.trascinando = false;
                        slotMouse.premutoA = (m.button === Qt.LeftButton
                                              && slot.index < dock.quanteFisse)
                                             ? slotMouse.mapToItem(strip, m.x, 0).x
                                             : -99999;
                    }

                    onPositionChanged: function(m) {
                        if (slotMouse.premutoA < -9999)
                            return;
                        // ── Misurare in un metro CHE NON SI MUOVE ────────
                        //
                        // Qui c'era `slot.x + m.x + slotMouse.x`, cioè la
                        // posizione del dito calcolata a partire da dove sta
                        // l'icona. Ma l'icona trascinata SEGUE il dito:
                        // spostandola cambiava il metro con cui la si stava
                        // misurando, e il valore oscillava fra due numeri per
                        // sempre — un anello di retroazione, lo stesso errore
                        // che questa dock aveva già fatto con l'ingrandimento
                        // (vedi in cima al file). Le coordinate della fila
                        // stanno ferme, e sono quelle giuste.
                        var ora = slotMouse.mapToItem(strip, m.x, 0).x;
                        if (!slotMouse.trascinando) {
                            if (Math.abs(ora - slotMouse.premutoA) < dock.sogliaTrascina)
                                return;
                            slotMouse.trascinando = true;
                            dock.iniziaTrascina(slot.index, ora);
                        }
                        dock.muoviTrascina(ora);
                    }

                    // ── Il gesto finisce QUI, e in nessun altro posto ────
                    //
                    // Non su `onReleased`: quello copre solo il caso gentile.
                    // Un trascinamento può finire anche perché il puntatore è
                    // uscito, perché un altro ha preso la presa, o perché
                    // l'elenco si è rifatto sotto le mani. Se anche uno solo
                    // di quei casi non azzerasse lo stato, la dock resterebbe
                    // convinta di avere un'icona in mano per sempre: niente
                    // più ingrandimento, e le altre icone ferme nel posto
                    // «aperto» per far spazio a un buco che non si chiude più.
                    //
                    // `pressed` diventa falso in tutti i casi, uno solo.
                    onPressedChanged: {
                        if (slotMouse.pressed)
                            return;
                        slotMouse.premutoA = -99999;
                        if (slotMouse.trascinando) {
                            slotMouse.trascinando = false;
                            dock.finisciTrascina();
                        }
                    }

                    onClicked: function(m) {
                        // Un trascinamento finisce con un rilascio, e Qt lo
                        // fa seguire da un clic: senza questo, spostare
                        // un'icona la aprirebbe anche.
                        if (slotMouse.trascinando)
                            return;
                        if (m.button === Qt.RightButton) {
                            // Il menu esce dal CENTRO dell'icona e cresce
                            // dalla parte dove c'è spazio: verso l'alto se la
                            // dock sta in fondo, verso il basso se sta in
                            // cima. Le coordinate le calcoliamo noi: vedi
                            // `originY`. Da che parte crescere lo dice
                            // `menuVersoIlBasso` a chi apre il menu, perché
                            // il menu non è nostro.
                            dock.menuRequested(slot.index, Qt.point(
                                dock.originX + dock.stripX + slot.x + dock.cell / 2,
                                dock.inAlto
                                ? dock.originY + dock.shownY + dock.barHeight
                                  + Theme.Effects.space2
                                : dock.originY + dock.shownY - Theme.Effects.space2));
                            return;
                        }
                        if (m.button === Qt.MiddleButton) {
                            dock.launch(slot.modelData);
                            return;
                        }
                        dock.activate(slot.modelData);
                    }
                }
            }
        }
    }

    // ── Azioni ───────────────────────────────────────────────────────────

    signal menuRequested(int index, point where)

    /// Chi è stato avviato in questo momento, e quando.
    ///
    /// ── Fra il clic e la finestra non succedeva niente ──────────────────
    ///
    /// Un programma pesante ci mette due o tre secondi ad aprirsi. In quei
    /// secondi la dock non dava **nessun** segno di aver sentito: si preme,
    /// non succede niente, e il gesto naturale è premere di nuovo — cioè
    /// avviarlo due volte.
    ///
    /// Il segno finisce da sé anche se il programma non si apre mai: dura
    /// otto secondi al massimo, poi si spegne. Un'animazione che gira per
    /// sempre perché un programma è morto all'avvio è peggio del silenzio.
    property string _avviando: ""

    Timer {
        id: fineAvvio
        interval: 8000
        onTriggered: dock._avviando = ""
    }

    function launch(item) {
        if (item.exec && item.exec !== "") {
            dock._avviando = item.key;
            fineAvvio.restart();
            Core.Ipc.launchApp(item.exec, item.appId);
        }
    }

    /// Clic sinistro. Se non gira, parte. Se gira, la porta davanti. Se ne
    /// girano più d'una, gira fra loro — che è il motivo per cui esiste una
    /// icona sola con più finestre dietro.
    ///
    /// ── Un clic qui non riduce mai ───────────────────────────────────────
    ///
    /// Prima una finestra sola passava da `toggleWindow`: se era già quella
    /// attiva, il clic la RIDUCEVA. È quello che fanno le barre delle
    /// applicazioni di Windows e di KDE, ed è per questo che c'era.
    ///
    /// Ma la nostra dock non è una barra delle applicazioni: è una fila di
    /// icone in basso, che si ingrandiscono al passaggio. Chi la guarda legge
    /// «dock», e in una dock il clic PORTA DAVANTI — sempre. Il risultato era
    /// che tornando dalla finestra alla sua icona per riprenderla in mano, la
    /// finestra spariva. Parole di Giacomo: «se clicco sulla dock Chrome si
    /// minimizza».
    ///
    /// Ridurre resta a portata di mano in due posti dove è quello che si sta
    /// chiedendo: il pulsante sulla barra del titolo e il menu del tasto
    /// destro qui sulla dock.
    function activate(item) {
        var addrs = item.addresses;
        if (addrs.length === 0) {
            dock.launch(item);
            return;
        }
        if (addrs.length === 1) {
            if (addrs[0].minimized)
                Core.Windows.restore(addrs[0].address);
            else
                Core.Windows.focus(addrs[0].address);
            return;
        }
        var active = Core.Windows.activeAddress;
        var at = -1;
        for (var i = 0; i < addrs.length; i++)
            if (addrs[i].address === active)
                at = i;
        var next = addrs[(at + 1) % addrs.length];
        if (next.minimized)
            Core.Windows.restore(next.address);
        else
            Core.Windows.focus(next.address);
    }

    function menuItems(index) {
        var item = dock.items[index];
        if (!item)
            return [];
        var out = [];
        if (item.exec !== "")
            out.push({ "label": dock.it ? "Apri una nuova finestra" : "Open a new window",
                       "icon": "plus", "action": "nuova" });

        // ── Le finestre, una per una ────────────────────────────────────
        //
        // `addresses` contiene già `{address, title, minimized}` per ognuna,
        // ed è servito finora solo a contarle. Con più di una finestra dello
        // stesso programma, «riduci a icona» le riduceva TUTTE e non c'era
        // nessun modo di arrivare a quella che si voleva se non
        // l'Alt+Tab — cioè indovinandola dal titolo in un elenco a parte.
        //
        // Da due in su si elencano: il titolo è l'unica cosa che le
        // distingue, ed è quello che sta scritto nella loro barra.
        if (item.addresses.length > 1) {
            out.push({ "separator": true });
            for (var k = 0; k < item.addresses.length; k++) {
                var w = item.addresses[k];
                var t = String(w.title || "").trim();
                if (t === "")
                    t = dock.it ? "Senza titolo" : "Untitled";
                out.push({ "label": t,
                           "icon": w.minimized ? "minimize" : "window",
                           "action": "vaiA:" + w.address });
            }
        }

        if (item.addresses.length > 0) {
            out.push({ "separator": true });
            out.push({ "label": item.addresses.length > 1
                                ? (dock.it ? "Riduci tutte" : "Minimise all")
                                : (dock.it ? "Riduci a icona" : "Minimise"),
                       "icon": "minimize", "action": "minimize" });
        }
        if (item.appId !== "") {
            out.push({ "separator": true });
            out.push({ "label": item.pinned
                                ? (dock.it ? "Togli dalla dock" : "Remove from the dock")
                                : (dock.it ? "Tieni nella dock" : "Keep in the dock"),
                       "icon": "pin", "action": "pin" });
        }
        if (item.addresses.length > 0) {
            out.push({ "separator": true });
            out.push({ "label": item.addresses.length > 1
                                ? (dock.it ? "Chiudi tutte (" + item.addresses.length + ")"
                                           : "Close all (" + item.addresses.length + ")")
                                : (dock.it ? "Chiudi" : "Close"),
                       "icon": "close", "action": "close", "danger": true });
        }
        return out;
    }

    function runMenuAction(index, action) {
        var item = dock.items[index];
        if (!item)
            return;
        var i;
        // «Vai a questa finestra»: l'indirizzo viaggia dentro il nome
        // dell'azione, perché il menu passa stringhe e non oggetti.
        if (String(action).indexOf("vaiA:") === 0) {
            Core.Windows.focus(String(action).substring(5));
            return;
        }
        switch (action) {
        case "launch":
            dock.launch(item);
            break;
        // ── Una finestra IN PIÙ ─────────────────────────────────────────
        //
        // Era `launch`, cioè il comando principale: per un programma a
        // istanza unica — il nostro gestore file — riportava davanti la
        // finestra che c'era già («chiude e riapre la stessa finestra»,
        // Giacomo, 29 settembre 2026). Il comando giusto lo dichiara il
        // programma nell'azione `new-window` del suo .desktop; chi non la
        // dichiara riparte col comando principale, come prima.
        case "nuova":
            if (item.nuovaFinestra && item.nuovaFinestra !== "") {
                dock._avviando = item.key;
                fineAvvio.restart();
                Core.Ipc.launchApp(item.nuovaFinestra, item.appId);
            } else {
                dock.launch(item);
            }
            break;
        case "minimize":
            for (i = 0; i < item.addresses.length; i++)
                Core.Windows.minimize(item.addresses[i].address);
            break;
        case "close":
            for (i = 0; i < item.addresses.length; i++)
                Core.Windows.close(item.addresses[i].address);
            break;
        case "pin":
            dock.togglePinned(item.appId);
            break;
        }
    }

    signal pinnedChangeRequested(var list)

    function togglePinned(appId) {
        if (appId === "")
            return;
        var list = (dock.pinned || []).slice();
        var at = list.indexOf(appId);
        if (at === -1)
            list.push(appId);
        else
            list.splice(at, 1);
        dock.pinnedChangeRequested(list);
    }
}
