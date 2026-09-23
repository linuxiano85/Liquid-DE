#ifndef WLR_MINERVA_TIMING_H
#define WLR_MINERVA_TIMING_H
#include <stdbool.h>
#include <wayland-server-core.h>
struct wlr_surface;
struct wlr_surface_state;
struct wlr_scene_output;
/* Uses CLOCK_MONOTONIC, the clock advertised by wlroots presentation-time. */
bool wlr_minerva_timing_create(struct wl_display *display);
bool wlr_minerva_timing_ready(struct wlr_surface *surface, struct wlr_surface_state *state);
void wlr_minerva_surface_drain(struct wlr_surface *surface);
void wlr_minerva_timing_latched(struct wlr_surface *surface);
/* Call only after a successful non-tearing output commit at a frame deadline.
 * Frame callbacks alone are not evidence that the output accepted a frame. */
void wlr_minerva_scene_output_latched(struct wlr_scene_output *output);
void wlr_minerva_timing_finish(struct wlr_surface *surface);
#endif
