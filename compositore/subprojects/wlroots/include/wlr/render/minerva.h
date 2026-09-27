/* SPDX-License-Identifier: MIT */
#ifndef WLR_RENDER_MINERVA_H
#define WLR_RENDER_MINERVA_H
#include <stdbool.h>
#include <wlr/util/box.h>
struct wlr_minerva_radii { float top_left, top_right, bottom_right, bottom_left; };
struct wlr_minerva_clip { struct wlr_box area; struct wlr_minerva_radii corners; };
struct wlr_minerva_style {
	float blur_radius; /* Physical sampling step; zero preserves legacy default. */
	/* Acquerello: behind the surface only the COLOUR of what's there, the
	 * whole rectangle averaged down to 1/32 and spread back softly. */
	bool acquerello;
	struct wlr_minerva_radii corners;
	struct wlr_minerva_clip hole;
};
static inline struct wlr_minerva_radii wlr_minerva_radii_all(float r) {
	return (struct wlr_minerva_radii){r, r, r, r};
}
static inline bool wlr_minerva_has_radii(struct wlr_minerva_radii r) {
	return r.top_left > 0 || r.top_right > 0 || r.bottom_left > 0 || r.bottom_right > 0;
}
#endif
