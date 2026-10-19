import QtQuick
import "." as Theme
import "../core" as Core

// LegaTema — Attacca la tavolozza alle impostazioni. Una volta per processo.
//
// ── Perché esiste ──────────────────────────────────────────────────────────
//
// `Colors.qml` non legge le impostazioni, e non deve: è la tavolozza, e una
// tavolozza che sa dove sta il file di configurazione non si può più usare
// dentro una prova né dentro un'applicazione che il demone non ce l'ha.
// Qualcuno però quel legame deve farlo, e quel qualcuno era **ogni punto
// d'ingresso**: `shell.qml`, `settings.qml`, `filemanager.qml`, `viewer.qml`,
// `minervamedia.qml`, `app.qml`. Sei copie dello stesso blocco.
//
// Finché i legami erano quattro si poteva reggere. Con il tema personale
// diventano sette, cioè quarantadue righe ripetute sei volte, e la prima volta
// che se ne aggiunge uno solo in cinque file su sei si ottiene la cosa
// peggiore: un'applicazione di Minerva con i colori di un'altra Minerva.
//
// È già successo con le icone — cambiando tema la dock non seguiva, perché il
// demone mandava un elenco solo — e il rimedio è lo stesso: un posto solo.
//
// ── Come si usa ────────────────────────────────────────────────────────────
//
//     Theme.LegaTema { }                      dentro un'applicazione
//     Theme.LegaTema { animazioni: true }     dentro la shell
//
// `animazioni` è separato perché `Theme.Motion.scala` governa le animazioni
// dei PANNELLI e della dock, che vivono solo nella shell. Un'applicazione che
// se lo legasse non farebbe danno, ma direbbe una cosa che non è: che quelle
// durate le usa lei.
QtObject {
    id: lega

    /// Lega anche la velocità delle animazioni della shell.
    property bool animazioni: false

    // ── Il testo ─────────────────────────────────────────────────────────
    //
    // La dimensione del testo di tutta Minerva. Si lega qui e non dentro
    // `Typography.qml`, che non deve sapere dove stanno le impostazioni. Vale
    // in ogni processo, e per questo cambiarla li ingrandisce tutti insieme,
    // nello stesso istante.
    property Binding _scala: Binding {
        target: Theme.Typography
        property: "scala"
        value: Core.Ipc.get("accessibility.textScale", 1.0)
    }

    // ── Le animazioni della SHELL, che l'interruttore non toccava ────────
    //
    // Il manutentore, 19 agosto 2026: spegnere le animazioni «non porta a nessun
    // cambiamento». Era vero: `Compositore.animazioni()` spegne quelle del
    // COMPOSITORE — finestre che si aprono, cambio scrivania — mentre i
    // pannelli, la dock e i menu li anima la shell con le durate di
    // `Theme.Motion`, che erano numeri fissi.
    //
    // Zero vuol dire nessuna animazione: in QML una durata di zero fa arrivare
    // il valore a destinazione nello stesso fotogramma.
    //
    // La velocità è separata dall'interruttore apposta: chi le spegne e poi le
    // riaccende ritrova la SUA velocità, non quella di fabbrica.
    property Binding _motion: Binding {
        target: Theme.Motion
        property: "scala"
        when: lega.animazioni
        value: Core.Ipc.get("desktop.animations", true)
               ? Core.Ipc.get("desktop.animationSpeed", 1.0) : 0.0
    }

    // ── Il tema ──────────────────────────────────────────────────────────
    property Binding _carattere: Binding {
        target: Theme.Motion
        property: "carattere"
        value: Core.Ipc.get("riva.molla", "liquida")
    }

    property Binding _scheme: Binding {
        target: Theme.Colors
        property: "scheme"
        value: Core.Ipc.get("shell.scheme", "notte")
    }

    property Binding _accent: Binding {
        target: Theme.Colors
        property: "accentoScelto"
        value: Core.Ipc.get("shell.accent", "#22D3EE")
    }

    // La tinta e il verso del tema personale. Valgono solo quando il tema è
    // «personale», ma si legano sempre: una proprietà che cambia mentre
    // nessuno la guarda non costa niente, e legarla solo a volte vorrebbe dire
    // che scegliendo il tema personale i suoi valori arrivano un istante dopo
    // — cioè un lampo del colore sbagliato a ogni cambio.
    property Binding _tinta: Binding {
        target: Theme.Colors
        property: "tintaPersonale"
        value: Core.Ipc.get("shell.tintaPersonale", "#101018")
    }

    property Binding _verso: Binding {
        target: Theme.Colors
        property: "versoPersonale"
        value: Core.Ipc.get("shell.versoPersonale", true)
    }

    property Binding _scavalca: Binding {
        target: Theme.Colors
        property: "scavalca"
        value: Core.Ipc.get("shell.scavalca", ({}))
    }

    // ── Il vetro ─────────────────────────────────────────────────────────
    //
    // ── Due numeri, perché la domanda ha due risposte giuste ─────────────
    //
    // «Quanto è coprente la barra» dipende da cosa c'è dietro. Senza blur c'è
    // una fotografia NITIDA, e sotto 0,75 il testo ci si perde — è la soglia
    // misurata scritta in `theme/Colors.qml`, dove si ferma il cursore. Col
    // blur del compositore c'è una macchia morbida e un po' scurita (SceneFX
    // porta luminosità e contrasto a 0,9), che non ruba leggibilità a niente:
    // lì 0,93 vuol dire non vedere la sfocatura per cui si paga un passaggio
    // di disegno. Misurato il 9 settembre 2026: fra `vetro` e `blur` nella
    // fascia della barra non cambiava NEMMENO UN PIXEL su 84.480.
    //
    // La prima cura era un TETTO — `Math.min(chiesta, 0.75)` — e aveva il
    // difetto che questo progetto si è messo per iscritto di non commettere:
    // col blur acceso il cursore delle Impostazioni va da 0,75 a 1,00, quindi
    // il tetto lo annullava tutto. Girato da un capo all'altro non cambiava
    // niente, e nemmeno lo diceva. Misurato: 0,0 % di pixel diversi fra 0,75 e
    // 1,00.
    //
    // Quindi due chiavi, e ognuna si ricorda com'era.
    //
    // ── E solo nella SCRIVANIA ───────────────────────────────────────────
    //
    // Perché il fondo sfocato il compositore lo mette dietro le superfici
    // appoggiate — barra e dock — e dietro le finestre. Dentro una finestra
    // di Minerva, un menù che usa la stessa tinta non ha il blur dietro: ha
    // il contenuto della finestra. Abbassarlo anche lì vorrebbe dire pagare
    // in leggibilità un effetto che in quel punto non esiste. È la stessa
    // riga di `Core.Vetro._chiedi`, e per la stessa ragione.
    readonly property bool _colBlur:
        Core.Vetro.filtroVero && Core.Compositore.scrivania

    property Binding _membrana: Binding {
        target: Theme.Colors
        property: "membraneOpacity"
        value: lega._colBlur
               ? Core.Ipc.get("shell.membraneOpacityBlur", 0.68)
               : Core.Ipc.get("shell.membraneOpacity", 0.93)
    }

    // «Nessuno» deve togliere anche il vetro locale: riattivare qui il
    // vecchio cursore rendeva le app trasparenti proprio spegnendo l'effetto.
    // Il vetro moltiplica l'alfa nel compositore; l'acquerello invece filtra
    // soltanto i pixel già traslucidi, quindi gli si dà l'alfa del fondo.
    property Binding _finestre: Binding {
        target: Theme.Colors
        property: "windowOpacity"
        value: Core.Vetro.filtroVero
               ? Core.Ipc.get("windows.effettoOpacita", 0.88)
               : 1.0
    }
}
