#ifndef MINERVA_CANALE_H
#define MINERVA_CANALE_H

#include <stdbool.h>

struct minerva;
struct wl_event_loop;

// Il canale di controllo di minerva-wayland.
//
// Un socket Unix su cui la shell manda i suoi verbi — «chiudi questa
// finestra», «mettila a fuoco», «spostala lì» — e riceve una risposta.
//
// ── Perché un socket e non D-Bus ──────────────────────────────────────────
//
// Perché è quello che fanno tutti i compositori Wayland, e non per moda: D-Bus
// vuole un bus di sessione già avviato, e il compositore parte PRIMA della
// sessione. Un socket nella cartella di esecuzione c'è dal primo istante.
//
// ── La sicurezza è nei permessi, e basta così ─────────────────────────────
//
// Il socket sta in `$XDG_RUNTIME_DIR`, che logind crea `0700`: dentro ci entra
// solo chi ha fatto l'accesso. Non serve una parola d'ordine come per il
// canale del demone — quella serviva perché lì si ascolta su TCP, e su TCP i
// permessi del filesystem non esistono. Vedi `minervad/lib/ipc/canale_segreto.dart`,
// che spiega per esteso perché un socket Unix sarebbe stata la scelta giusta
// anche là.
struct canale;

// Apre il canale. `NULL` se non ci riesce — e non è un motivo per non partire:
// un compositore senza canale disegna lo stesso, semplicemente non si comanda.
struct canale *canale_apri(struct minerva *m, struct wl_event_loop *loop,
                           const char *nome_display);

void canale_chiudi(struct canale *c);

// Il percorso del socket, per chi deve stamparlo.
const char *canale_percorso(const struct canale *c);

// ── Annunciare, invece di farsi interrogare ───────────────────────────────
//
// Manda `riga` a tutti i collegati che hanno chiesto `ascolta`. Chi non l'ha
// chiesto non riceve niente: un programma che fa una domanda e legge una
// risposta non deve trovarsi in mezzo degli annunci che non aspettava.
//
// Serve al demone, che ha bisogno di sapere QUANDO una finestra si apre, si
// chiude o cambia titolo. L'alternativa era che chiedesse l'elenco a
// ripetizione, ed è la strada che questo progetto ha già percorso e
// abbandonato: `hyprctl clients` ogni nove decimi di secondo per processo. Il
// costo non era la domanda, era svegliarsi per farla — vedi
// `minervad/lib/providers/hyprland/hyprland_provider.dart`, che oggi ascolta
// `.socket2.sock` esattamente così.
//
// `NULL` come canale è lecito e non fa niente: il compositore parte anche
// senza, e nessuno dei punti che annunciano deve saperlo.
// ── E chi vuole sentire una cosa sola ────────────────────────────────────
//
// `ascolta` senza argomenti vuol dire tutto, ed è quello che chiede il demone:
// lui deve sapere ogni cosa che succede alle finestre. `ascolta scrivanie`
// vuol dire una riga sola — quale scrivania è in uso — ed è quello che chiede
// la SHELL.
//
// La differenza non è pignoleria. Un terminale che cambia titolo a ogni tasto
// premuto produce un annuncio a ogni tasto premuto: farlo arrivare anche alla
// shell vorrebbe dire svegliare il processo che DISEGNA per una cosa che non
// la riguarda, e questo progetto quel conto l'ha già pagato una volta — la
// scansione Wi-Fi ogni dodici secondi e il titolo animato che inchiodava il
// demone. Chi ascolta tutto sono in uno; gli altri sentono solo il loro nome.
//
// `che` è il nome dell'evento («aperta», «scrivania», …) e non si ricava dalla
// riga: chi annuncia ce l'ha già in mano, e dedurlo qui vorrebbe dire un
// secondo posto che deve sapere com'è fatta una riga di annuncio.
void canale_annuncia(struct canale *c, const char *che, const char *riga);

#endif
