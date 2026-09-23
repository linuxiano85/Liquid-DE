pragma Singleton
import QtQuick
import QtQml
import Quickshell

// Sounds — La voce di Minerva.
//
// Un ambiente che non fa nessun rumore quando lo si comanda lascia sempre un
// dubbio: il tasto ha funzionato? Il segno a schermo risponde, ma bisogna
// guardarlo — e chi alza il volume di solito sta guardando altro.
//
// ── COSA SUONA, E PERCHÉ COSÌ ────────────────────────────────────────────
//
// Il volume ha undici suoni e non uno. Non è un vezzo: il volume ha una
// POSIZIONE, e una nota che sale la racconta all'orecchio mentre l'occhio è
// impegnato. Le undici note sono una pentatonica maggiore, cioè una scala in
// cui non esistono due note che suonino male una dopo l'altra: tenendo premuto
// il tasto si sente una frase, non una sirena. I file li genera
// `scripts/make-sounds.py`, dove c'è scritto per esteso come sono fatti.
//
// ── PERCHÉ `SoundEffect` E NON UN COMANDO ESTERNO ────────────────────────
//
// Perché lanciare `pw-play` a ogni pressione vuol dire avviare un processo,
// aprire un flusso audio e chiuderlo, sessanta millisecondi buoni prima che si
// senta qualcosa: il suono arriverebbe DOPO il gesto, e un ritorno in ritardo
// è peggio di nessun ritorno. `SoundEffect` tiene i campioni già in memoria e
// li fa partire all'istante. Sono quattordici file da otto kilobyte.
//
// ── PERCHÉ SI SVEGLIANO TARDI ────────────────────────────────────────────
//
// Quei quattordici file da otto kilobyte tengono in piedi TUTTO lo stack
// multimediale di Qt: `libQt6Multimedia`, il backend ffmpeg (`libavcodec`) e
// perfino il driver di decodifica video di Intel (`iHD_drv_video`), che si
// carica perché ffmpeg va a cercare l'accelerazione hardware. Misurato: una
// ventina di megabyte residenti, e il tempo di aprire la scheda video una
// seconda volta — **all'avvio della sessione**, che è il momento in cui c'è
// più fretta e meno pazienza.
//
// Quindi non si costruisce niente finché non serve. Chi non tocca mai il
// volume non carica mai un decodificatore video, e chi lo tocca lo paga una
// volta sola: il primo suono può arrivare in ritardo, tutti gli altri no.
// Un `Loader` non asincrono costruisce DENTRO la chiamata, quindi anche il
// primo suono parte — solo dopo il caricamento.
//
// ── QUANDO NON SUONA ─────────────────────────────────────────────────────
//
// Solo per le regolazioni fatte DA QUI. Se il volume cambia perché l'ha
// cambiato un altro programma, Minerva non dice niente: il suono è la conferma
// di un gesto, e di un gesto che non hai fatto non c'è niente da confermare.
QtObject {
    id: sounds

    property bool enabled: true
    /// Quanto forte, da 0 a 1. Sopra la metà diventa invadente.
    property real level: 0.4

    /// Dove stanno i campioni, come indirizzo assoluto su disco.
    ///
    /// NON `Qt.resolvedUrl("../assets/…")`, ed è un errore che costa un'ora
    /// se non si sa dove guardare: Quickshell carica i QML da una radice
    /// virtuale (`qrc:/qs-blackhole/…`), quindi un percorso relativo si
    /// risolve DENTRO quella radice e non sul disco. Il risultato era
    /// `qrc:/qs-blackholevolume-04.wav`, un indirizzo che non esiste — e i
    /// suoni tacevano senza che niente sembrasse rotto.
    ///
    /// `Quickshell.shellDir` è la cartella vera di `shell.qml`, quindi qui
    /// si parte da lì. Vuol dire anche che i suoni si spostano insieme alla
    /// shell, senza percorsi scritti a mano da nessuna parte.
    readonly property string dir: "file://" + Quickshell.shellDir + "/assets/sounds/"

    /// Falso finché nessuno ha chiesto un suono: prima di allora qui dentro
    /// non esiste nemmeno un oggetto, e Qt non ha motivo di caricare l'audio.
    property bool desti: false

    /// I campioni, costruiti tutti insieme al primo suono richiesto.
    ///
    /// `asynchronous: false` non è una svista: il `Loader` deve costruire
    /// DENTRO la chiamata che lo sveglia, o il primo suono chiederebbe di
    /// suonare a un oggetto che non c'è ancora.
    ///
    /// ── PERCHÉ UN FILE E NON UN COMPONENTE IN LINEA ──────────────────────
    ///
    /// Qui c'era un `sourceComponent`, e questo file importava `QtMultimedia`
    /// in cima. Un componente in linea si compila insieme al file che lo
    /// contiene: era pigro all'esecuzione e avido alla compilazione. Il 26
    /// agosto 2026, tolto `qt6-multimedia` insieme a KDE, quell'`import` ha
    /// reso indisponibile l'INTERA cartella `core` — perché chi importa una
    /// cartella deve poter compilare tutti i tipi del suo `qmldir` — e con
    /// essa la schermata di accesso. Schermo nero, cinque tentativi di greetd.
    /// Il racconto per esteso sta in `core/suoni/Campioni.qml`.
    ///
    /// Caricato per indirizzo, un modulo che manca fa fallire QUESTO `Loader`
    /// e nient'altro.
    property Loader _campioni: Loader {
        active: sounds.desti
        asynchronous: false
        source: "suoni/Campioni.qml"

        // Il livello si lega dopo, perché l'oggetto nasce solo al primo suono.
        // La cartella è costante e potrebbe passare da `setSource`, ma tenerle
        // insieme fa sì che si leggano insieme.
        Binding {
            target: sounds._campioni.item
            property: "cartella"
            value: sounds.dir
            when: sounds._campioni.item !== null
        }
        Binding {
            target: sounds._campioni.item
            property: "livello"
            value: sounds.level
            when: sounds._campioni.item !== null
        }

        // ── Il silenzio si dice una volta, e poi si tace ──────────────────
        //
        // Se `qt6-multimedia` non c'è, questo `Loader` va in errore. Non è una
        // ragione per riprovare a ogni tasto del volume né per riempire il
        // journal: si scrive una riga che dice cosa manca e cosa si perde, si
        // spegne `enabled`, e Minerva continua muta senza altre lamentele.
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[MINERVA][Suoni] Niente audio: manca «qt6-multimedia». "
                             + "Il resto funziona; si perdono solo i suoni del volume.");
                sounds.enabled = false;
            }
        }
    }

    // Trascinando il cursore del volume arrivano decine di richieste al
    // secondo. Senza un freno si sovrappongono in un ronzio; con un freno
    // troppo lento si perde il legame col gesto. Cinquanta millesimi è la
    // distanza sotto la quale due suoni si fondono in uno solo per chi
    // ascolta, quindi è esattamente quanto conviene aspettare.
    property double _lastAt: 0

    function _ready() {
        if (!sounds.enabled)
            return false;
        // È qui che si sveglia l'audio, e solo qui: un `enabled` a falso non
        // deve caricare niente, mai.
        if (!sounds.desti)
            sounds.desti = true;
        var now = Date.now();
        if (now - sounds._lastAt < 50)
            return false;
        sounds._lastAt = now;
        return true;
    }

    /// Il passo del volume, con la nota che corrisponde al livello.
    function volumeStep(percent) {
        if (!sounds._ready())
            return;
        var i = Math.round(Math.max(0, Math.min(100, percent)) / 10);
        var c = sounds._campioni.item;
        var e = c ? c.steps.objectAt(i) : null;
        if (e)
            e.play();
    }

    /// Sei arrivato in fondo, da una parte o dall'altra.
    function limit() {
        if (!sounds._ready())
            return;
        if (sounds._campioni.item)
            sounds._campioni.item.limite.play();
    }

    function mute(on) {
        if (!sounds._ready())
            return;
        var c = sounds._campioni.item;
        if (!c)
            return;
        if (on)
            c.muteOn.play();
        else
            c.muteOff.play();
    }
}
