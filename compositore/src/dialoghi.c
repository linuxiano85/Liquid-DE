#include "dialoghi.h"
#include <wlr/types/wlr_xdg_dialog_v1.h>
#include <wlr/types/wlr_xdg_shell.h>

// Un dialogo non modale lascia lavorare la madre. Solo il protocollo
// xdg-dialog-v1 consente di distinguere questa scelta senza indovinare
// titoli o classi; gli antenati permettono anche finestre modali annidate.
bool minerva_dialogo_blocca_antenato(struct wlr_xdg_toplevel *dialogo,
        struct wlr_xdg_toplevel *antenato) {
    struct wlr_xdg_dialog_v1 *stato =
        wlr_xdg_dialog_v1_try_from_wlr_xdg_toplevel(dialogo);
    if (!stato || !stato->modal) {
        return false;
    }
    const unsigned profondita_massima = 128;
    unsigned profondita = 0;
    for (struct wlr_xdg_toplevel *padre = dialogo->parent;
            padre && profondita < profondita_massima;
            padre = padre->parent, profondita++) {
        if (padre == antenato) {
            return true;
        }
    }
    return false;
}
