import QtQuick
import QtMultimedia

// Campioni.qml — I quattordici suoni, e l'unico posto di Minerva dove si
// nomina QtMultimedia.
//
// ── PERCHÉ QUESTO FILE ESISTE ────────────────────────────────────────────
//
// Il 26 agosto 2026 un `pacman -Rns plasma kde-applications` si è portato via
// `qt6-multimedia` insieme a KDE. Da quel momento il computer non è più
// arrivato alla schermata di accesso: schermo nero, e greetd che ci riprovava
// cinque volte prima di arrendersi.
//
// La catena, presa dal log del guasto e riportata qui perché non si ripeta:
//
//     greeter.qml → Accesso.Greeter → Ui.Icon → Apps → Compositore
//                 → Gioco → Core.Exec → Media → Meteo → Notifications
//                 → Overlays → Sounds → «module "QtMultimedia" is not installed»
//
// `ui/Icon.qml` importa la CARTELLA `"../core"`, e risolvere una cartella vuol
// dire compilare tutti i tipi che il suo `qmldir` dichiara — venti. Bastava
// che uno solo non compilasse perché `core` diventasse indisponibile a
// chiunque: al greeter, alla shell, a ogni app. **Un'icona nella schermata di
// accesso tirava dentro il motore dei suoni, e i suoni impedivano di entrare
// nel computer.**
//
// I campioni erano già costruiti pigri, dentro un `Loader` — ma con
// `sourceComponent`, cioè un componente scritto in linea. Un componente in
// linea si compila insieme al file che lo contiene, quindi l'`import` in cima
// restava obbligatorio lo stesso: pigro all'esecuzione, avido alla
// compilazione. Solo un file SEPARATO, caricato per indirizzo, sposta il
// costo dove deve stare.
//
// ── PERCHÉ QUI E NON IN `core/` ──────────────────────────────────────────
//
// `core/suoni/` è una sottocartella: `core/qmldir` non la nomina, e
// `import "../core"` non ci entra. Se QtMultimedia manca, a fallire è questo
// file soltanto — il `Loader` che lo chiama va in stato d'errore, `Sounds` si
// spegne da sé, e tutto il resto di Minerva continua a funzionare in silenzio.
//
// **La regola che ne esce, e vale per tutta la cartella `core/`:** nessun file
// dichiarato in `core/qmldir` può importare un modulo Qt che potrebbe non
// esserci. Se serve, si mette in un file a parte come questo e si carica per
// indirizzo.
QtObject {
    id: campioni

    /// Dove stanno i `.wav`, come indirizzo assoluto su disco. Lo passa
    /// `Sounds`, che sa risolverlo da `Quickshell.shellDir`.
    property string cartella: ""

    /// Quanto forte, da 0 a 1. `Sounds` lo tiene legato al suo `level`.
    property real livello: 0.4

    /// Gli undici passi del volume, dal silenzio al massimo: uno ogni dieci
    /// per cento. Sono una pentatonica maggiore — non esistono due note che
    /// suonino male una dopo l'altra — così tenendo premuto il tasto si sente
    /// una frase e non una sirena.
    property Instantiator steps: Instantiator {
        model: 11
        delegate: SoundEffect {
            required property int index
            source: campioni.cartella + "volume-"
                    + (index < 10 ? "0" + index : index) + ".wav"
            volume: campioni.livello
        }
    }

    property SoundEffect limite: SoundEffect {
        source: campioni.cartella + "volume-limit.wav"
        volume: campioni.livello
    }

    property SoundEffect muteOn: SoundEffect {
        source: campioni.cartella + "mute-on.wav"
        volume: campioni.livello
    }

    property SoundEffect muteOff: SoundEffect {
        source: campioni.cartella + "mute-off.wav"
        volume: campioni.livello
    }
}
