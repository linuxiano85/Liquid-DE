#include "puntatore.h"
#include <stdlib.h>
#include <math.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <wlr/types/wlr_pointer_constraints_v1.h>
#include <wlr/util/region.h>

struct puntatore {
    struct wlr_seat *seat;
    struct wlr_cursor *cursor;
    struct wlr_relative_pointer_manager_v1 *relative;
    struct wlr_pointer_constraints_v1 *constraints;
    struct wlr_pointer_constraint_v1 *active;
    struct wl_listener focus, keyboard, nuovo, destroy, region;
    bool consentito;
};

static void disattiva(struct puntatore *p) {
    struct wlr_pointer_constraint_v1 *c = p->active;
    if (!c) return;
    p->active = NULL;
    wl_list_remove(&p->destroy.link); wl_list_remove(&p->region.link);
    // Può distruggere un vincolo oneshot: non leggere c dopo questa chiamata.
    wlr_pointer_constraint_v1_send_deactivated(c);
}

static void distrutto(struct wl_listener *l, void *data) {
    (void)data;
    struct puntatore *p = wl_container_of(l, p, destroy);
    struct wlr_pointer_constraint_v1 *c = p->active;
    if (p->consentito && c->surface->mapped &&
        p->seat->pointer_state.focused_surface == c->surface &&
        c->type == WLR_POINTER_CONSTRAINT_V1_LOCKED && c->current.cursor_hint.enabled) {
        double x = c->current.cursor_hint.x, y = c->current.cursor_hint.y;
        if (isfinite(x) && isfinite(y) && x >= 0 && y >= 0 &&
            x < c->surface->current.width && y < c->surface->current.height) {
            wlr_cursor_warp(p->cursor, NULL,
                p->cursor->x + x - p->seat->pointer_state.sx,
                p->cursor->y + y - p->seat->pointer_state.sy);
            wlr_seat_pointer_notify_motion(p->seat, 0, x, y);
        }
    }
    p->active = NULL;
    wl_list_remove(&p->destroy.link); wl_list_remove(&p->region.link);
}

static void aggiorna(struct puntatore *p);
static void regione(struct wl_listener *l, void *data) {
    (void)data;
    struct puntatore *p = wl_container_of(l, p, region);
    struct wlr_pointer_constraint_v1 *c = p->active;
    if (c && !pixman_region32_not_empty(&c->region)) { disattiva(p); return; }
    if (c && c->type == WLR_POINTER_CONSTRAINT_V1_CONFINED) {
        double sx = p->seat->pointer_state.sx, sy = p->seat->pointer_state.sy;
        if (!pixman_region32_contains_point(&c->region, floor(sx), floor(sy), NULL)) {
            int n;
            pixman_box32_t *r = pixman_region32_rectangles(&c->region, &n);
            double best = INFINITY, bx = sx, by = sy;
            for (int i = 0; i < n; i++) {
                double x = fmax(r[i].x1, fmin(sx, r[i].x2 - 1));
                double y = fmax(r[i].y1, fmin(sy, r[i].y2 - 1));
                double d = (x-sx)*(x-sx)+(y-sy)*(y-sy);
                if (d < best) { best = d; bx = x; by = y; }
            }
            wlr_cursor_warp(p->cursor, NULL, p->cursor->x + bx-sx, p->cursor->y + by-sy);
            wlr_seat_pointer_notify_motion(p->seat, 0, bx, by);
        }
    }
    aggiorna(p);
}

static void aggiorna(struct puntatore *p) {
    struct wlr_surface *s = p->seat->pointer_state.focused_surface;
    struct wlr_surface *k = p->seat->keyboard_state.focused_surface;
    bool focus = s && k && wlr_surface_get_root_surface(s) == wlr_surface_get_root_surface(k);
    struct wlr_pointer_constraint_v1 *c = p->consentito && focus
        ? wlr_pointer_constraints_v1_constraint_for_surface(p->constraints, s, p->seat) : NULL;
    if (p->active && p->active != c) disattiva(p);
    if (!c || p->active) return;
    if (!pixman_region32_contains_point(&c->region, floor(p->seat->pointer_state.sx),
            floor(p->seat->pointer_state.sy), NULL)) return;
    p->active = c;
    p->destroy.notify = distrutto; p->region.notify = regione;
    wl_signal_add(&c->events.destroy, &p->destroy);
    wl_signal_add(&c->events.set_region, &p->region);
    wlr_pointer_constraint_v1_send_activated(c);
}

static void focus(struct wl_listener *l, void *data) {
    (void)data; struct puntatore *p = wl_container_of(l, p, focus); aggiorna(p);
}
static void keyboard(struct wl_listener *l, void *data) {
    (void)data; struct puntatore *p = wl_container_of(l, p, keyboard); aggiorna(p);
}
static void nuovo(struct wl_listener *l, void *data) {
    (void)data; struct puntatore *p = wl_container_of(l, p, nuovo); aggiorna(p);
}

struct puntatore *puntatore_crea(struct wl_display *display, struct wlr_seat *seat, struct wlr_cursor *cursor) {
    struct puntatore *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->seat = seat; p->cursor = cursor; p->consentito = true;
    p->relative = wlr_relative_pointer_manager_v1_create(display);
    p->constraints = wlr_pointer_constraints_v1_create(display);
    if (!p->relative || !p->constraints) { free(p); return NULL; }
    p->focus.notify = focus; p->keyboard.notify = keyboard; p->nuovo.notify = nuovo;
    wl_signal_add(&seat->pointer_state.events.focus_change, &p->focus);
    wl_signal_add(&seat->keyboard_state.events.focus_change, &p->keyboard);
    wl_signal_add(&p->constraints->events.new_constraint, &p->nuovo);
    return p;
}

void puntatore_consenti(struct puntatore *p, bool consenti) {
    if (!p) return;
    p->consentito = consenti;
    if (!consenti) disattiva(p);
    else aggiorna(p);
}

void puntatore_movimento(struct puntatore *p, uint64_t time, double *dx, double *dy,
        double rawx, double rawy, bool relativo) {
    if (!p) return;
    aggiorna(p);
    if (p->consentito && relativo) {
        wlr_relative_pointer_manager_v1_send_relative_motion(p->relative, p->seat,
            time, *dx, *dy, rawx, rawy);
    }
    struct wlr_pointer_constraint_v1 *c = p->active;
    if (!c) return;
    if (c->type == WLR_POINTER_CONSTRAINT_V1_LOCKED) { *dx = *dy = 0; return; }
    double sx = p->seat->pointer_state.sx, sy = p->seat->pointer_state.sy, x, y;
    if (wlr_region_confine(&c->region, sx, sy, sx + *dx, sy + *dy, &x, &y)) {
        *dx = x - sx; *dy = y - sy;
    } else { *dx = *dy = 0; }
}

void puntatore_distruggi(struct puntatore *p) {
    if (!p) return;
    disattiva(p);
    wl_list_remove(&p->focus.link); wl_list_remove(&p->keyboard.link); wl_list_remove(&p->nuovo.link);
    free(p);
}
