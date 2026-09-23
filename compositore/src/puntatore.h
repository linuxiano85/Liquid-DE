#ifndef MINERVA_PUNTATORE_H
#define MINERVA_PUNTATORE_H
#include <stdbool.h>
#include <stdint.h>
struct wl_display;
struct wlr_seat;
struct wlr_cursor;
struct puntatore;
struct puntatore *puntatore_crea(struct wl_display *, struct wlr_seat *, struct wlr_cursor *);
void puntatore_distruggi(struct puntatore *);
void puntatore_consenti(struct puntatore *, bool);
void puntatore_movimento(struct puntatore *, uint64_t usec, double *dx, double *dy,
    double grezzo_x, double grezzo_y, bool relativo);
#endif
