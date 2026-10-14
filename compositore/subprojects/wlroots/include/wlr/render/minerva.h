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
/* L'Acrylic di Windows 11 sopra l'acquerello: la ricetta di WinUI
 * (microsoft-ui-xaml, AcrylicBrush.cpp, MIT). Sul fondo sfocato prima la
 * LUMINOSITÀ del colore `luminosita` (rgb) con opacità `luminosita[3]`: tinta
 * e saturazione restano dello sfondo, la chiarezza la decide lui. Poi il
 * COLORE della `tinta` con opacità `tinta[3]`. Infine il rumore. Colori non
 * premoltiplicati, da 0 a 1. Vedi `minerva_blur.frag`. */
struct wlr_minerva_acrylic {
	bool attivo;
	float tinta[4];
	float luminosita[4];
	float rumore;
};
struct wlr_minerva_style {
	float desaturation; // 0 = original color, 1 = luminance; alpha unchanged
	struct wlr_minerva_radii corners;
	struct wlr_minerva_clip hole;
	struct wlr_minerva_mercurio mercurio;
	struct wlr_minerva_acrylic acrylic;
};
static inline struct wlr_minerva_radii wlr_minerva_radii_all(float r) {
	return (struct wlr_minerva_radii){r, r, r, r};
}
static inline bool wlr_minerva_has_radii(struct wlr_minerva_radii r) {
	return r.top_left > 0 || r.top_right > 0 || r.bottom_left > 0 || r.bottom_right > 0;
}
#endif
