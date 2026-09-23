// energia.h — La batteria e il profilo energetico, ascoltati e non chiesti.
//
// ── Perché il compositore, e non la shell ─────────────────────────────────
//
// Il modo risparmio abbassa gli effetti quando la batteria scende: niente
// blur né trasparenza, la cornice smette di girare, l'elastico si ferma. Sono
// tutte cose del COMPOSITORE, e a deciderle è lui (piano del 22 settembre
// 2026, «Costa meno: batteria e calore»). Se lo decidesse la shell, una shell
// ferma o che riparte lascerebbe gli effetti accesi a batteria scarica — cioè
// proprio quando serve che si spengano.
//
// ── Come si sa, senza svegliarsi ───────────────────────────────────────────
//
// UPower annuncia ogni cambio della batteria (`PropertiesChanged` sul
// `DisplayDevice`, la batteria «vista dall'utente» che somma le altre), e
// power-profiles-daemon annuncia il profilo scelto. Qui ci si iscrive e
// basta: nessun timer, nessun giro su `/sys` ogni tanto. Il bus si innesta
// nel ciclo di wayland come in `sonno.c`.
//
// ── Se UPower non c'è ──────────────────────────────────────────────────────
//
// Un fisso senza batteria, un sistema senza UPower: `batteria` resta falso e
// la batteria non fa scattare niente. Non si inventa uno stato che non si sa.
#ifndef MINERVA_ENERGIA_H
#define MINERVA_ENERGIA_H
#include <stdbool.h>
struct wl_event_loop;
struct energia;

struct energia_stato {
	/// C'è una batteria, e UPower ce l'ha detto.
	bool batteria;
	/// Si sta scaricando: né attaccati alla corrente né carichi e fermi.
	bool scarica;
	/// Da 0 a 100.
	double percento;
	/// Il profilo energetico scelto è «risparmio energetico» (`power-saver`).
	bool profilo_risparmio;
	/// power-profiles-daemon ha risposto.
	bool profilo_noto;
};

/// Si iscrive agli annunci e chiede lo stato di partenza. `cambiata` viene
/// chiamata a ogni cambio vero, anche il primo. NULL se il bus di sistema non
/// c'è: vuol dire «non si sa», e non è un errore che ferma il compositore.
struct energia *energia_crea(struct wl_event_loop *, void (*cambiata)(void *), void *);
void energia_distruggi(struct energia *);
struct energia_stato energia_stato(const struct energia *);

/// La regola del modo «auto», da sola perché si possa provare senza
/// compositore. Si risparmia se la batteria SI STA SCARICANDO ed è arrivata
/// alla soglia, oppure se è stato scelto il profilo «risparmio energetico»:
/// chi lo sceglie ha già detto cosa vuole, anche attaccato alla corrente.
/// `motivo` diventa «batteria» o «profilo», o NULL.
bool energia_da_risparmiare(struct energia_stato, int soglia, const char **motivo);
#endif
