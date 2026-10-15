#include "schermi-posizioni.h"

#include <stdlib.h>
#include <wlr/types/wlr_output_layout.h>

struct posizione_salvata {
	struct wlr_output *output;
	int x;
	int y;
};

bool minerva_schermi_fissa_posizioni(struct wlr_output_layout *layout) {
	size_t count = wl_list_length(&layout->outputs);
	if (count == 0)
		return true;
	struct posizione_salvata *positions = calloc(count, sizeof(*positions));
	if (!positions)
		return false;

	// add() rende manuale una posizione e può riordinare gli altri output
	// ancora automatici. Fotografarli TUTTI prima evita di salvare coordinate
	// già spostate: altrimenti un annullamento può lasciare finestre nel vuoto.
	size_t index = 0;
	struct wlr_output_layout_output *entry;
	wl_list_for_each(entry, &layout->outputs, link) {
		positions[index].output = entry->output;
		positions[index].x = entry->x;
		positions[index].y = entry->y;
		index++;
	}
	for (index = 0; index < count; index++) {
		struct posizione_salvata *position = &positions[index];
		if (!wlr_output_layout_add(layout, position->output, position->x, position->y)) {
			free(positions);
			return false;
		}
	}
	free(positions);
	return true;
}
