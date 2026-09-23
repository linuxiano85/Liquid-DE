// sonno.h — Il blocco schermo PRIMA della sospensione, garantito da logind.
//
// ── Il difetto che chiude ──────────────────────────────────────────────────
//
// Audit del 12 settembre 2026 (Codex, S01): la shell lanciava `systemctl
// suspend` e basta. Al risveglio la scrivania era lì, sbloccata, con dentro
// tutto — a meno che l'inattività non avesse già fatto scattare il blocco,
// cosa che con una sospensione immediata da sessione viva non succede mai.
//
// ── Come lo garantisce logind ──────────────────────────────────────────────
//
// Con un **inibitore di ritardo** (`Inhibit("sleep", …, "delay")`): finché
// lo teniamo, logind non dorme; quando sta per farlo manda
// `PrepareForSleep(true)`, noi blocchiamo lo schermo, e SOLO ALLORA
// rilasciamo l'inibitore. Vale per ogni strada verso il sonno — il nostro
// menù, il coperchio, il tasto fisico, un `systemctl suspend` da terminale —
// perché è logind che le raccoglie tutte, non noi.
//
// Al risveglio (`PrepareForSleep(false)`) si riprende l'inibitore per la
// volta dopo.
//
// ── Cosa succede se logind NON c'è ─────────────────────────────────────────
//
// La prima versione bloccava lo schermo *subito*, all'avvio, se il bus non
// rispondeva — e di nuovo se il bus cadeva durante la sessione. È «chiuso
// per principio», ma tradotto: un singhiozzo di D-Bus e la schermata di
// blocco compare mentre stai lavorando. Un blocco che nessuno ha chiesto non
// è protezione, è un guasto travestito da protezione.
//
// Quindi: senza logind si AVVISA, e si rifiuta la sospensione chiesta da
// Minerva (il verbo `sospendi` guarda `sonno_pronto`). Quello che non si
// può garantire è la sospensione chiesta da fuori — e non si finge di
// poterlo fare bloccando tutto a caso.
#ifndef MINERVA_SONNO_H
#define MINERVA_SONNO_H
#include <stdbool.h>
struct wl_event_loop;
struct sonno;

/// Si collega a logind e prende l'inibitore. `proteggi` viene chiamata
/// quando il sonno sta per arrivare. La protezione è asincrona:
/// chiamare sonno_protetto SOLO dopo la presentazione protetta degli output.
struct sonno *sonno_crea(struct wl_event_loop *, void (*proteggi)(void *), void *);
void sonno_distruggi(struct sonno *);
void sonno_protetto(struct sonno *);

/// Vero quando l'inibitore è in mano nostra: si può dormire in sicurezza.
bool sonno_pronto(struct sonno *);
#endif
