import QtQuick
import "../theme" as Theme

// WindowRules — L'aspetto delle finestre deciso nelle Impostazioni e mandato
// al compositore: colore del bordo, cornice, effetto, molla, respiro,
// mercurio.
//
// Le finestre sono tutte libere — minerva-wayland non affianca niente — e la
// misura con cui nascono la decide il compositore (`finestra_misura_alla_
// nascita`). Qui resta solo quello che dipende da una scelta dell'utente.
//
// Le scrive la SCRIVANIA e nessun'altra finestra: vedi `write()`.
QtObject {
    id: rules

    /// Da un colore QML alla forma del verbo `bordo` del compositore:
    /// `rgba(RRGGBBAA)`.
    function rgbaEsa(c, alpha) {
        function due(v) {
            var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        }
        return "rgba(" + due(c.r) + due(c.g) + due(c.b) + due(alpha) + ")";
    }

    /// Il colore della barra della finestra attiva: l'accento di Minerva.
    /// Una finestra senza fuoco non cambia colore, si allontana (cambia
    /// l'alfa): per questo un colore «spento» non c'è.
    readonly property string borderActive: rules.rgbaEsa(Theme.Colors.accent, 0.95)

    // ── La cornice attorno alla finestra attiva ──────────────────────────
    //
    // «spento» (come nasce), «fisso» (la tinta dell'accento) o «gira» (la
    // striscia LED: la tinta fa il giro dello spettro). Il colore lo prende
    // dall'accento, e non è una manopola in meno per pigrizia: una cornice di
    // un colore e un accento di un altro sono due segni che dicono «questa è
    // quella attiva» litigando fra loro.
    //
    // Il giro lo fa il COMPOSITORE. Da qui parte un messaggio quando si
    // cambia idea, non dodici al secondo.
    property string cornice: "spento"

    /// Quanto è spesso il bordo colorato, in pixel. Il compositore lo tiene
    /// fra 1 e 20: sopra non è più un bordo, è una seconda finestra intorno
    /// alla finestra — e sarebbe anche una banda in cui il clic non arriva
    /// più al programma, perché la presa per ridimensionare lo segue.
    property int corniceSpessore: 6

    /// I colori che si alternano girando. Vuoto è lo spettro intero.
    property var corniceTinte: []

    /// Quanto è accesa la cornice sulle finestre che non hanno il fuoco.
    /// Zero: solo quella attiva.
    property real corniceSpente: 0
    /// Millisecondi per un giro intero. Il compositore rifiuta sotto i due
    /// secondi: più veloce non è un colore che gira, è un lampeggio.
    property int cornicePeriodo: 8000

    /// ── Quanto tremano le finestre ───────────────────────────────────────
    ///
    /// Zero spento. Trascinando, la finestra resta indietro rispetto al dito
    /// e al rilascio rimbalza. Il conto lo fa il compositore, in `molla.c`:
    /// da qui parte un numero quando si cambia idea, non centoventicinque
    /// messaggi al secondo.
    property real elastico: 0
    /// Le finestre che nascono come una goccia e si riducono con un
    /// risucchio (il «respiro», nel compositore). Segue l'interruttore delle
    /// animazioni: chi le spegne — anche perché il movimento gli fa male —
    /// non deve ritrovarselo.
    property bool respiro: true
    /// Mercurio: le finestre vicine che si fondono come gocce (vedi
    /// `compositore/src/mercurio.h`). Non è un'animazione — è la forma — e
    /// non costa niente a scrivania ferma, quindi ha il suo interruttore e
    /// non segue quello delle animazioni.
    property bool mercurio: true
    property real rigidita: 1
    property real smorzamento: 0.42

    /// «nessuno», «vetro» o «acquerello» (`compositore/src/main.c`,
    /// `comando_effetto`). Col vetro il compositore mette UNA trasparenza su
    /// tutto l'albero della finestra — barra e contenuto insieme — invece di
    /// due attaccate con una linea in mezzo.
    property string effetto: "nessuno"
    property real effettoOpacita: 0.88

    // ── Applicazione immediata ───────────────────────────────────────────

    onEffettoChanged: applySoon.restart()
    onElasticoChanged: applySoon.restart()
    onRespiroChanged: applySoon.restart()
    onMercurioChanged: applySoon.restart()
    onRigiditaChanged: applySoon.restart()
    onSmorzamentoChanged: applySoon.restart()
    onEffettoOpacitaChanged: applySoon.restart()
    onBorderActiveChanged: applySoon.restart()
    onCorniceChanged: applySoon.restart()
    onCornicePeriodoChanged: applySoon.restart()
    onCorniceSpessoreChanged: applySoon.restart()
    onCorniceTinteChanged: applySoon.restart()
    onCorniceSpenteChanged: applySoon.restart()
    Component.onCompleted: applySoon.restart()

    property Timer _applySoon: Timer {
        id: applySoon
        // Le impostazioni arrivano dal demone una alla volta: si aspetta che
        // abbiano finito invece di riscrivere a ogni singolo valore.
        interval: 500
        onTriggered: rules.write()
    }

    /// Manda tutto al compositore, in un colpo solo.
    function write() {
        // ── Le regole delle finestre le manda la SCRIVANIA, non ogni app ──
        //
        // Questo file sta dentro ogni nostra applicazione, e
        // `Component.onCompleted` lo fa partire in tutte. Fino al 31 agosto
        // 2026 aprire il gestore file rimandava al compositore l'aspetto di
        // TUTTA la sessione — che non è affare di una finestra.
        //
        // Le regole restano LEGGIBILI da tutti: quello che si limita è chi
        // le SCRIVE.
        if (!Compositore.scrivania)
            return;
        Compositore.coloriBordo(rules.borderActive);
        Compositore.effetto(rules.effetto, rules.effettoOpacita);
        Compositore.cornice(rules.cornice, rules.cornicePeriodo,
                            Theme.Colors.accent, rules.corniceSpessore);
        Compositore.corniceColori(rules.corniceTinte);
        Compositore.corniceSpente(rules.corniceSpente);
        Compositore.elastico(rules.elastico);
        Compositore.respiro(rules.respiro);
        Compositore.mercurio(rules.mercurio);
        Compositore.parametriEffetti(rules.rigidita, rules.smorzamento);
    }
}
