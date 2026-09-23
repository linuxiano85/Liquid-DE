// Test della politica locale; l'invio sul protocollo è sostituito da sonde.
// Non sostituisce una prova end-to-end con un client Wayland/giochi.
#define wlr_pointer_constraint_v1_send_activated prova_attiva
#define wlr_pointer_constraint_v1_send_deactivated prova_disattiva
#define wlr_relative_pointer_manager_v1_send_relative_motion prova_relativo
#include "puntatore.c"
#include <assert.h>
#include <stdio.h>

static int attivazioni, disattivazioni, movimenti;
static double relativo_x, grezzo_x;
static uint64_t tempo;
void prova_attiva(struct wlr_pointer_constraint_v1 *c) { (void)c; attivazioni++; }
void prova_disattiva(struct wlr_pointer_constraint_v1 *c) {
    disattivazioni++;
    // La disattivazione può emettere destroy sincrono (oneshot).
    wl_signal_emit_mutable(&c->events.destroy, c);
}
void prova_relativo(struct wlr_relative_pointer_manager_v1 *m, struct wlr_seat *s,
        uint64_t t, double dx, double dy, double ux, double uy) {
    (void)m; (void)s; (void)dy; (void)uy;
    movimenti++; relativo_x = dx; grezzo_x = ux; tempo = t;
}

int main(void) {
    struct wl_display *display = wl_display_create();
    assert(display);
    struct wlr_seat *seat = wlr_seat_create(display, "test");
    struct wlr_cursor *cursor = wlr_cursor_create();
    assert(seat && cursor);
    struct puntatore *p = puntatore_crea(display, seat, cursor);
    assert(p);
    struct wlr_surface surface = {0}, other = {0};
    seat->pointer_state.focused_surface = &surface;
    seat->keyboard_state.focused_surface = &surface;
    seat->pointer_state.sx = seat->pointer_state.sy = 50;
    struct wlr_pointer_constraint_v1 c = {
        .surface = &surface, .seat = seat, .type = WLR_POINTER_CONSTRAINT_V1_LOCKED,
    };
    pixman_region32_init_rect(&c.region, 0, 0, 100, 100);
    wl_signal_init(&c.events.destroy); wl_signal_init(&c.events.set_region);
    wl_list_insert(&p->constraints->constraints, &c.link);
    puntatore_consenti(p, true);
    assert(p->active == &c && attivazioni == 1);
    double dx = 20, dy = -5;
    puntatore_movimento(p, 123000, &dx, &dy, 10, -2, true);
    assert(dx == 0 && dy == 0);
    assert(movimenti == 1 && relativo_x == 20 && grezzo_x == 10 && tempo == 123000);
    dx = 30; dy = 30;
    puntatore_movimento(p, 124000, &dx, &dy, 30, 30, false);
    assert(movimenti == 1 && dx == 0 && dy == 0);
    puntatore_consenti(p, false);
    assert(!p->active && disattivazioni == 1);
    dx = 3; dy = 4;
    puntatore_movimento(p, 125000, &dx, &dy, 3, 4, true);
    assert(movimenti == 1 && dx == 3 && dy == 4);
    c.type = WLR_POINTER_CONSTRAINT_V1_CONFINED;
    puntatore_consenti(p, true);
    dx = 500; dy = 0;
    puntatore_movimento(p, 126000, &dx, &dy, 500, 0, true);
    assert(dx > 0 && dx <= 50 && dy == 0);
    seat->keyboard_state.focused_surface = &other;
    puntatore_consenti(p, true);
    assert(!p->active && disattivazioni == 2);
    seat->keyboard_state.focused_surface = &surface;
    puntatore_consenti(p, true);
    assert(p->active == &c);
    wl_signal_emit_mutable(&c.events.destroy, &c);
    assert(!p->active);
    wl_list_remove(&c.link);
    pixman_region32_fini(&c.region);
    seat->pointer_state.focused_surface = NULL;
    seat->keyboard_state.focused_surface = NULL;
    puntatore_distruggi(p);
    wlr_cursor_destroy(cursor);
    wl_display_destroy(display);
    puts("ok: delta relativi, lock, confine, revoca, focus e destroy sincrono");
    return 0;
}
