// lente.h — Quale fetta dello schermo si vede, quando la lente è accesa.
//
// ── Perché è un file a sé ─────────────────────────────────────────────────
//
// Per la stessa ragione di `aggancio.c` e `schermi.c` — è conto puro, non
// tocca wlroots — più una che vale solo qui: **questo conto non si può
// guardare.**
//
// La lente non ridisegna niente: mette un ritaglio in `buffer_src_box`, cioè
// agisce sullo scanout, sull'ultimo passaggio fra il buffer e il monitor.
// `grim` e wlr-screencopy catturano la SCENA, che sta prima. Due catture con
// lente spenta e accesa sono risultate identiche al pixel — verificato il
// 31 agosto 2026. Quindi una prova a fotografia, che per le barre del titolo
// è stata la sola strada, qui non esiste proprio.
//
// Restano i numeri. E i numeri avevano già un difetto dentro: il ritaglio si
// applicava a OGNI schermo intorno allo stesso puntatore, che ha una
// coordinata sola — quella della scrivania intera. Sul monitor dove il
// puntatore non c'era il ritaglio cadeva fuori, la trattenuta lo incollava a
// un angolo, e quel monitor restava ingrandito e fermo su un pezzo che
// nessuno aveva chiesto. Non si era mai visto perché questa macchina ha uno
// schermo solo.
#ifndef MINERVA_LENTE_H
#define MINERVA_LENTE_H

#include <stdbool.h>

/// Un rettangolo a virgola mobile, negli stessi campi di `struct wlr_fbox`.
///
/// Non si include wlroots: questo file deve poter essere compilato dentro una
/// prova che non ha né schermi né un compositore.
struct lente_box {
	double x, y, larghezza, altezza;
};

/// Il ritaglio da mostrare su QUESTO schermo, o niente.
///
///  · `scala` 1 o meno vuol dire lente spenta;
///  · `sx, sy, slarga, salta` è dove sta questo schermo nella scrivania —
///    serve a sapere se il puntatore è suo, e a portare le coordinate del
///    puntatore dentro casa;
///  · `blarga, balta` è la risoluzione del suo buffer, che con una rotazione
///    non è la stessa cosa delle misure qui sopra;
///  · `px, py` è il puntatore, in coordinate della scrivania.
///
/// Torna **falso** quando non c'è niente da ritagliare, e sono tre casi che
/// vanno tenuti distinti da chi legge il codice: lente spenta, misure
/// impossibili, e **il puntatore è su un altro schermo**. In tutti e tre lo
/// schermo mostra tutto sé stesso, che è la cosa giusta.
bool lente_ritaglio(double scala,
                    int sx, int sy, int slarga, int salta,
                    int blarga, int balta,
                    double px, double py,
                    struct lente_box *fuori);

#endif
