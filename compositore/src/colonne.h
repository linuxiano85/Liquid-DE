#ifndef MINERVA_COLONNE_H
#define MINERVA_COLONNE_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
// Pure layout, independent of focus stacking and Wayland client lifetimes.
struct colonna_finestra {
    void *finestra;
    int64_t colonna;
    uint64_t riga;
    int larghezza, minima_larghezza, minima_altezza;
    int altezza, cella_altezza; // preferred height, reserved grid-row height
    bool fissa;
    int massima_larghezza, massima_altezza; // zero means unbounded
    int x,y,w,h;
};
// Sorts by explicit column/row order; scrolls only enough to reveal focus.
int colonne_disponi(struct colonna_finestra *,size_t,int,int,int,int,int,int,void *);
// Fit columns into the available area. Returns an incompatible window index,
// or -1 on success. Does not request impossible client sizes.
int colonne_adatta(struct colonna_finestra *,size_t,int,int,int);
int colonne_adatta_scorribile(struct colonna_finestra *,size_t,int,int,int,int *);
#endif
