// aggancio.c — Il conto dell'aggancio ai bordi. Vedi `aggancio.h`.
#include <stddef.h>
#include "aggancio.h"

enum zona_aggancio aggancio_zona_di(const struct riquadro *fisico,
                                    double px, double py) {
	if (fisico == NULL || fisico->larghezza <= 0 || fisico->altezza <= 0)
		return ZONA_NIENTE;

	// ── Un punto FUORI da questo schermo non aggancia a questo schermo ───
	//
	// Sembra ovvio e non lo era: senza questa riga, un puntatore trenta pixel
	// a sinistra del secondo monitor risultava «vicino al suo bordo sinistro»,
	// perché il confronto era solo `px <= x + 24` e non guardava se il punto
	// stesse dentro. Con due schermi affiancati vuol dire agganciare sul
	// monitor sbagliato mentre si passa da uno all'altro.
	//
	// Dentro `main.c` non capitava — lo schermo lo trova
	// `wlr_output_layout_output_at`, che il punto ce l'ha dentro per
	// definizione — ma una funzione che risponde una cosa falsa quando la
	// chiami in un altro modo è una trappola per chi la userà domani. Trovata
	// dalle sue stesse prove, scrivendole.
	if (px < fisico->x || px >= fisico->x + fisico->larghezza
			|| py < fisico->y || py >= fisico->y + fisico->altezza)
		return ZONA_NIENTE;

	const int e = AGGANCIO_FASCIA;
	const bool sx = px <= fisico->x + e;
	const bool dx = px >= fisico->x + fisico->larghezza - e;
	const bool su = py <= fisico->y + e;
	const bool giu = py >= fisico->y + fisico->altezza - e;

	// ── L'angolo si prende anche camminando lungo il bordo ───────────────
	//
	// Con le sole fasce, un angolo è il quadratino di 24×24 dove si
	// incrociano: si mira al quarto di schermo e si ottiene la metà. Vedi
	// `aggancio_angolo` in `aggancio.h`.
	const int av = aggancio_angolo(fisico->altezza);
	const int ao = aggancio_angolo(fisico->larghezza);
	const bool alto_lungo  = py <= fisico->y + av;
	const bool basso_lungo = py >= fisico->y + fisico->altezza - av;
	const bool sx_lungo    = px <= fisico->x + ao;
	const bool dx_lungo    = px >= fisico->x + fisico->larghezza - ao;

	// ── Gli angoli prima dei lati ────────────────────────────────────────
	//
	// Chi porta il dito in un angolo vuole un quarto di schermo. Provando
	// prima i lati, un angolo darebbe sempre «metà», e il quarto di schermo
	// sarebbe irraggiungibile: le fasce si sovrappongono proprio lì.
	if ((sx && alto_lungo) || (su && sx_lungo)) return ZONA_ALTO_SX;
	if ((dx && alto_lungo) || (su && dx_lungo)) return ZONA_ALTO_DX;
	if ((sx && basso_lungo) || (giu && sx_lungo)) return ZONA_BASSO_SX;
	if ((dx && basso_lungo) || (giu && dx_lungo)) return ZONA_BASSO_DX;
	if (su) return ZONA_CIMA;
	if (sx) return ZONA_SINISTRA;
	if (dx) return ZONA_DESTRA;
	// In basso, da solo, NON aggancia: sotto c'è la dock, e un gesto che
	// scatta passando di lì renderebbe impossibile trascinare una finestra
	// vicino al bordo inferiore senza spalmarla. Gli angoli in basso sì,
	// perché lì l'intenzione è chiara.
	return ZONA_NIENTE;
}

void aggancio_riquadro(enum zona_aggancio zona, const struct riquadro *utile,
                       struct riquadro *fuori) {
	if (fuori == NULL)
		return;
	if (utile == NULL) {
		*fuori = (struct riquadro){0, 0, 0, 0};
		return;
	}
	// Metà si prende per DIFETTO, e l'altra è «quello che resta»: con una
	// larghezza dispari, due metà arrotondate uguali lascerebbero una riga di
	// sfondo in mezzo — o una in più fuori dallo schermo.
	const int mw = utile->larghezza / 2;
	const int mh = utile->altezza / 2;
	const int rw = utile->larghezza - mw;
	const int rh = utile->altezza - mh;

	switch (zona) {
	case ZONA_SINISTRA:
		*fuori = (struct riquadro){utile->x, utile->y, mw, utile->altezza};
		break;
	case ZONA_DESTRA:
		*fuori = (struct riquadro){utile->x + mw, utile->y, rw, utile->altezza};
		break;
	case ZONA_CIMA:
		*fuori = *utile;
		break;
	case ZONA_ALTO_SX:
		*fuori = (struct riquadro){utile->x, utile->y, mw, mh};
		break;
	case ZONA_ALTO_DX:
		*fuori = (struct riquadro){utile->x + mw, utile->y, rw, mh};
		break;
	case ZONA_BASSO_SX:
		*fuori = (struct riquadro){utile->x, utile->y + mh, mw, rh};
		break;
	case ZONA_BASSO_DX:
		*fuori = (struct riquadro){utile->x + mw, utile->y + mh, rw, rh};
		break;
	default:
		*fuori = (struct riquadro){0, 0, 0, 0};
		break;
	}
}
