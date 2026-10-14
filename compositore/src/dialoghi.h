#ifndef MINERVA_DIALOGHI_H
#define MINERVA_DIALOGHI_H
#include <stdbool.h>
struct wlr_xdg_toplevel;
bool minerva_dialogo_blocca_antenato(struct wlr_xdg_toplevel *dialogo,
    struct wlr_xdg_toplevel *antenato);
#endif
