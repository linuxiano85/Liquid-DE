/* SPDX-License-Identifier: MIT */
#ifndef WLR_RENDER_MINERVA_H
#define WLR_RENDER_MINERVA_H
#include <stdbool.h>
#include <wlr/util/box.h>
struct wlr_minerva_radii { float top_left, top_right, bottom_right, bottom_left; };
struct wlr_minerva_clip { struct wlr_box area; struct wlr_minerva_radii corners; };
/* Mercurio: le finestre vicine che si fondono. Le forme sono rettangoli
 * arrotondati nelle coordinate del rettangolo che si disegna; il materiale
 * copre dove l'unione morbida (il minimo degli smooth-min di ogni coppia)
 * esce dalle forme. Vedi compositore/src/mercurio.c, che fa lo stesso conto
 * in C e lo prova. */
#define WLR_MINERVA_MERCURIO_MAX 8
struct wlr_minerva_mercurio {
	int quante;
	float k, raggio;
	struct wlr_fbox forme[WLR_MINERVA_MERCURIO_MAX];
};
struct wlr_minerva_style {
	struct wlr_minerva_radii corners;
	struct wlr_minerva_clip hole;
	struct wlr_minerva_mercurio mercurio;
};
static inline struct wlr_minerva_radii wlr_minerva_radii_all(float r) {
	return (struct wlr_minerva_radii){r, r, r, r};
}
static inline bool wlr_minerva_has_radii(struct wlr_minerva_radii r) {
	return r.top_left > 0 || r.top_right > 0 || r.bottom_left > 0 || r.bottom_right > 0;
}
#endif
