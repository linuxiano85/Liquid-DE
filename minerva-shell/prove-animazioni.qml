import QtQuick
import Quickshell
import "theme" as Theme

// ProveAnimazioni — Che l'interruttore arrivi DAVVERO alle animazioni.
//
//     qs -p minerva-shell/prove-animazioni.qml
//
// ── Perché questa prova esiste ─────────────────────────────────────────────
//
// Giacomo, 19 agosto 2026: «la disabilitazione dalla barra sul desktop e nelle
// impostazioni non porta a nessun cambiamento».
//
// Aveva ragione. `Compositore.animazioni()` spegneva quelle del COMPOSITORE —
// finestre che si aprono, cambio scrivania — mentre i pannelli, la dock e i
// menu li anima la shell con le durate di `Theme.Motion`, che erano numeri
// fissi: nessuna impostazione poteva toccarli.
//
// Il difetto è durato mesi perché è di quelli che non si vedono leggendo il
// codice: l'interruttore c'era, scriveva l'impostazione, e chiamava una
// funzione che faceva qualcosa. Semplicemente non tutto.
//
// ── E perché prova l'ARITMETICA e non lo schermo ──────────────────────────
//
// Perché lo schermo, qui, non si lascia misurare. Provato lo stesso giorno:
// aprire un pannello e fotografarlo con `grim` dà lo stesso numero di pixel
// con le animazioni accese e spente — `grim` ci mette più dei 320 ms
// dell'animazione, e quando scatta è già tutto finito. Una misura che non
// distingue i due casi non è una misura, e non va spacciata per tale.
//
// Quello che si può provare a macchina è che `scala` arrivi alle durate, e
// che ZERO voglia dire zero. Che poi lo schermo si muova o no, lo dicono gli
// occhi di chi guarda — ed è scritto nel piano.
ShellRoot {
    id: banco

    property int passate: 0
    property int fallite: 0

    function verifica(nome, condizione, dettaglio) {
        if (condizione) {
            banco.passate++;
            console.log("  ok   " + nome);
        } else {
            banco.fallite++;
            console.log("  NO   " + nome + (dettaglio ? "  → " + dettaglio : ""));
        }
    }

    Component.onCompleted: {
        console.log("── Prove delle animazioni ────────────────────────────");

        var M = Theme.Motion;

        // ── A velocità normale, i numeri sono quelli di sempre ───────────
        //
        // Le durate sono il vocabolario del movimento di Minerva: se cambiano
        // per sbaglio, tutta la scrivania cambia ritmo senza che nessuno
        // l'abbia chiesto.
        M.scala = 1.0;
        banco.verifica("a velocità normale le durate sono quelle di sempre",
                       M.instant === 110 && M.quick === 190 && M.panel === 320
                       && M.surface === 380 && M.exit === 160,
                       M.instant + "/" + M.quick + "/" + M.panel + "/"
                       + M.surface + "/" + M.exit);

        // ── Zero vuol dire NIENTE animazioni ─────────────────────────────
        //
        // È il difetto segnalato. In QML una durata di zero non è
        // un'animazione lampo: è nessuna animazione, il valore arriva a
        // destinazione nello stesso fotogramma.
        M.scala = 0.0;
        banco.verifica("spente, tutte le durate vanno a zero",
                       M.instant === 0 && M.quick === 0 && M.panel === 0
                       && M.surface === 0 && M.exit === 0,
                       M.instant + "/" + M.quick + "/" + M.panel + "/"
                       + M.surface + "/" + M.exit);

        // ── E si torna indietro ──────────────────────────────────────────
        //
        // Chi le spegne e le riaccende deve ritrovare il movimento di prima,
        // non un'approssimazione.
        M.scala = 1.0;
        banco.verifica("riaccese, tornano esattamente quelle di prima",
                       M.instant === 110 && M.panel === 320,
                       M.instant + "/" + M.panel);

        // ── La velocità è un moltiplicatore, in tutti e due i versi ──────
        M.scala = 0.5;
        banco.verifica("a metà durata il movimento è il doppio più rapido",
                       M.instant === 55 && M.panel === 160,
                       M.instant + "/" + M.panel);

        M.scala = 2.0;
        banco.verifica("a durata doppia è la metà più lento",
                       M.instant === 220 && M.panel === 640,
                       M.instant + "/" + M.panel);

        // ── I numeri restano interi ──────────────────────────────────────
        //
        // `duration` in QML vuole un intero: un 82,5 verrebbe troncato da
        // qualcun altro, e in un posto solo su cinque.
        M.scala = 0.75;
        banco.verifica("le durate restano numeri interi",
                       M.instant === Math.round(M.instant)
                       && M.quick === Math.round(M.quick)
                       && M.panel === Math.round(M.panel),
                       M.instant + "/" + M.quick + "/" + M.panel);

        M.scala = 1.0;

        console.log("");
        if (banco.fallite > 0)
            console.log("FALLITE " + banco.fallite + " su "
                        + (banco.passate + banco.fallite));
        else
            console.log("TUTTE PASSATE (" + banco.passate + ")");
    }
}
