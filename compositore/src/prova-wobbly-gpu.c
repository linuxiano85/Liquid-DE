// Prova C separata: solo GPU e superfici in memoria, nessun output fisico.
#include "wobbly.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <drm_fourcc.h>
#include <wlr/render/gles2.h>
#include <wlr/render/egl.h>
#include <wlr/backend/headless.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_texture.h>
#include <wlr/render/drm_format_set.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/types/wlr_output.h>

struct campione { struct wlr_buffer base; uint32_t pixel[64 * 64]; };
static void campione_via(struct wlr_buffer *b) { free(b); }
static bool campione_leggi(struct wlr_buffer *b, uint32_t flags, void **data,
		uint32_t *format, size_t *stride) {
	(void)flags;
	struct campione *c = wl_container_of(b, c, base);
	*data = c->pixel; *format = DRM_FORMAT_ARGB8888; *stride = 64 * 4;
	return true;
}
static void campione_fine(struct wlr_buffer *b) { (void)b; }
static const struct wlr_buffer_impl campione_impl = {.destroy = campione_via,
	.begin_data_ptr_access = campione_leggi, .end_data_ptr_access = campione_fine};

static uint32_t pixel(struct wlr_renderer *renderer, struct wlr_scene_buffer *proxy,
		int x, int y) {
	struct wlr_texture *t = wlr_texture_from_buffer(renderer, proxy->buffer);
	assert(t);
	uint32_t valore = 0;
	struct wlr_texture_read_pixels_options o = {.data = &valore,
		.format = DRM_FORMAT_ARGB8888, .stride = 4, .src_box = {x, y, 1, 1}};
	assert(wlr_texture_read_pixels(t, &o));
	wlr_texture_destroy(t);
	return valore;
}

struct sample_counter { struct wl_listener listener; unsigned count; };
static void sampled(struct wl_listener *listener, void *data) {
	(void)data;
	struct sample_counter *counter = wl_container_of(listener, counter, listener);
	counter->count++;
}

static void prova_blur_occlusione(struct wlr_backend *backend,
		struct wlr_renderer *renderer, struct wlr_allocator *allocator) {
	struct wlr_output *output = wlr_headless_add_output(backend, 200, 160);
	assert(output && wlr_output_init_render(output, allocator, renderer));
	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, true);
	assert(wlr_output_commit_state(output, &state));
	wlr_output_state_finish(&state);
	struct wlr_scene *scene = wlr_scene_create();
	assert(scene);
	struct wlr_scene_rect *background = wlr_scene_rect_create(&scene->tree, 200, 160, (float[]){1,0,0,1});
	assert(background);
	struct wlr_scene_rect *blur = wlr_minerva_blur_create(&scene->tree, 160, 120);
	assert(blur);
	wlr_scene_node_set_position(&blur->node, 20, 20);
	struct wlr_scene_rect *cover = wlr_scene_rect_create(&scene->tree, 100, 160, (float[]){0,0,1,1});
	assert(cover);
	wlr_scene_node_set_position(&cover->node, 100, 0);
	struct wlr_scene_output *so = wlr_scene_output_create(scene, output);
	assert(so);
	wlr_output_state_init(&state);
	assert(wlr_scene_output_build_state(so, &state, NULL));
	assert(state.buffer);
	struct wlr_scene_buffer reference = {.buffer=state.buffer};
	uint32_t edge = pixel(renderer, &reference, 95, 80);
	printf("blur accanto a finestra coprente: %08x (atteso rosso uniforme)\n", edge);
	assert(edge == 0xffff0000);
	assert(pixel(renderer, &reference, 105, 80) == 0xff0000ff);
	wlr_output_state_finish(&state);
	// Riutilizzare la scena cambiando lo sfondo e spostando la copertura:
	// non devono riapparire pixel vecchi dalle aree prima nascoste.
	wlr_scene_rect_set_color(background, (float[]){0,1,0,1});
	wlr_scene_rect_set_color(cover, (float[]){0,0,0,1});
	wlr_scene_node_set_position(&cover->node, 60, 0);
	wlr_output_state_init(&state);
	assert(wlr_scene_output_build_state(so, &state, NULL) && state.buffer);
	reference.buffer = state.buffer;
	assert(pixel(renderer, &reference, 55, 80) == 0xff00ff00);
	assert(pixel(renderer, &reference, 65, 80) == 0xff000000);
	wlr_output_state_finish(&state);
	// Un buffer coperto e lontano dal filtro non deve essere campionato.
	// Questo controlla il lavoro effettivo del renderer, non solo i pixel.
	wlr_scene_rect_set_size(blur, 40, 40);
	wlr_scene_rect_set_size(cover, 140, 160);
	struct campione *hidden_pixels = calloc(1, sizeof(*hidden_pixels));
	assert(hidden_pixels);
	wlr_buffer_init(&hidden_pixels->base, &campione_impl, 64, 64);
	struct wlr_scene_buffer *hidden = wlr_scene_buffer_create(&scene->tree, &hidden_pixels->base);
	assert(hidden);
	wlr_scene_node_set_position(&hidden->node, 170, 80);
	wlr_scene_node_place_below(&hidden->node, &cover->node);
	struct sample_counter counter = {.listener.notify=sampled};
	wl_signal_add(&hidden->events.output_sample, &counter.listener);
	wlr_output_state_init(&state);
	assert(wlr_scene_output_build_state(so, &state, NULL) && state.buffer);
	assert(counter.count == 0);
	reference.buffer = state.buffer;
	assert(pixel(renderer, &reference, 55, 40) == 0xff00ff00);
	assert(pixel(renderer, &reference, 175, 100) == 0xff000000);
	wlr_output_state_finish(&state);
	wl_list_remove(&counter.listener.link);
	wlr_scene_node_destroy(&scene->tree.node);
	wlr_buffer_drop(&hidden_pixels->base);
	// L'output possiede la swapchain: liberarla prima del renderer EGL.
	wlr_output_destroy(output);
}

int main(int argc, char **argv) {
	setvbuf(stdout, NULL, _IONBF, 0);
	struct wl_display *display = wl_display_create();
	struct wlr_backend *backend = wlr_headless_backend_create(wl_display_get_event_loop(display));
	struct wlr_renderer *renderer = wlr_renderer_autocreate(backend);
	assert(renderer);
	struct wlr_allocator *allocator = wlr_allocator_autocreate(backend, renderer);
	assert(allocator);
	// Solo per isolare la ritenzione del display EGL: questo processo di
	// prova ne è l'unico utilizzatore, diversamente da un'applicazione host.
	bool baseline_release = argc == 2 && strcmp(argv[1], "--renderer-only-release-display") == 0;
	bool release_display = baseline_release || (argc == 2 && strcmp(argv[1], "--release-owned-display") == 0);
	bool baseline = baseline_release || (argc == 2 && strcmp(argv[1], "--renderer-only") == 0);
	EGLDisplay egl_display = wlr_egl_get_display(wlr_gles2_renderer_get_egl(renderer));
	assert(argc == 1 || baseline || release_display);
	if (baseline) goto finish;
	struct wlr_scene *scene = wlr_scene_create();
	struct wlr_scene_tree *window = wlr_scene_tree_create(&scene->tree);
	const float red[] = {1, 0, 0, 1};
	struct wlr_scene_rect *r = wlr_scene_rect_create(window, 200, 160, red);
	struct wobbly *w = wobbly_crea(window, renderer, allocator, NULL);
	assert(w);
	struct ondulazione o = {200, 160, 100, 0, 18, 0};
	assert(wobbly_disegna(w, &o, 1));
	struct wlr_scene_node *n;
	struct wlr_scene_buffer *proxy = NULL;
	wl_list_for_each(n, &window->children, link)
		if (wobbly_e_proxy(w, n)) proxy = wlr_scene_buffer_from_node(n);
	assert(proxy && proxy->buffer);
	struct wlr_texture *tex = wlr_texture_from_buffer(renderer, proxy->buffer);
	assert(tex);
	uint32_t *pixels = calloc(tex->width * tex->height, 4);
	assert(pixels);
	struct wlr_texture_read_pixels_options opts = {
		.data = pixels, .format = DRM_FORMAT_ARGB8888, .stride = tex->width * 4};
	assert(wlr_texture_read_pixels(tex, &opts));
	int first[2] = {-1, -1};
	for (int row = 0; row < 2; row++) {
		int y = 112 + (row ? 145 : 15);
		for (unsigned x = 0; x < tex->width; x++) {
			uint32_t p = pixels[y * tex->width + x];
			if ((p >> 24) > 128) { first[row] = x; break; }
		}
	}
	printf("bordi deformati: sopra=%d sotto=%d\n", first[0], first[1]);
	printf("pixel centrale=%08x misura=%ux%u\n", pixels[(112 + 80) * tex->width + 212], tex->width, tex->height);
	assert(first[0] >= 112 && first[1] > first[0] + 2);
	assert((pixels[(112 + 80) * tex->width + 212] & 0xffffff) == 0xff0000);
	free(pixels); wlr_texture_destroy(tex);
	double x, y, sx, sy;
	ondulazione_punto(&o, 20, 80, &x, &y);
	assert(wobbly_nodo(w, x + 112, y + 112, &sx, &sy) == &r->node);
	assert(fabs(sx - 20) < .01 && fabs(sy - 80) < .01);
	// Le texture non sono rettangoli colorati: verifica orientamento,
	// aggiornamento live, angoli, ritaglio e scala del contenuto.
	struct campione *c = calloc(1, sizeof(*c));
	assert(c);
	wlr_buffer_init(&c->base, &campione_impl, 64, 64);
	for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		c->pixel[y * 64 + x] = y < 32 ? 0xff00ff00 : 0xff0000ff;
	struct wlr_scene_buffer *image = wlr_scene_buffer_create(window, &c->base);
	wlr_scene_buffer_set_dest_size(image, 200, 160);
	assert(wobbly_disegna(w, &o, 1));
	assert(pixel(renderer, proxy, 212, 132) == 0xff00ff00);
	assert(pixel(renderer, proxy, 212, 252) == 0xff0000ff);
	for (int i = 0; i < 64 * 64; i++) c->pixel[i] = 0xffffff00;
	assert(wobbly_disegna(w, &o, 1));
	assert(pixel(renderer, proxy, 212, 192) == 0xffffff00);
	// Il padding trasparente non deve intercettare clic sullo sfondo.
	double px = 5, py = 5;
	assert(!proxy->point_accepts_input(proxy, &px, &py));
	for (int i = 0; i < 120; i++) assert(wobbly_disegna(w, &o, i < 60 ? 1 : 2));
	assert(pixel(renderer, proxy, 424, 384) == 0xffffff00);
	// Con deformazione nulla, tutte le trasformazioni e i ritagli devono
	// coincidere coi pixel del passaggio standard del renderer nativo.
	for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		c->pixel[y * 64 + x] = y < 32 ? (x < 32 ? 0xffff0000 : 0xff00ff00)
			: (x < 32 ? 0xff0000ff : 0xffffff00);
	o.dx = o.dy = 0;
	uint64_t mod = DRM_FORMAT_MOD_LINEAR;
	struct wlr_drm_format fmt = {.format = DRM_FORMAT_ARGB8888, .len = 1,
		.capacity = 1, .modifiers = &mod};
	struct wlr_buffer *dest = wlr_allocator_create_buffer(allocator, 200, 160, &fmt);
	assert(dest);
	struct wlr_scene_buffer riferimento = {.buffer = dest};
	for (int crop = 0; crop < 2; crop++) for (int t = 0; t < 8; t++) {
		struct wlr_fbox box = crop ? (struct wlr_fbox){8, 12, 40, 36}
			: (struct wlr_fbox){0, 0, 64, 64};
		wlr_scene_buffer_set_transform(image, t);
		wlr_scene_buffer_set_source_box(image, &box);
		assert(wobbly_disegna(w, &o, 1));
		struct wlr_texture *src = wlr_texture_from_buffer(renderer, &c->base);
		assert(src);
		struct wlr_render_pass *pass = wlr_renderer_begin_buffer_pass(renderer, dest, NULL);
		assert(pass);
		struct wlr_render_texture_options op = {.texture = src, .src_box = box,
			.dst_box = {0, 0, 200, 160}, .transform = t};
		wlr_render_pass_add_texture(pass, &op);
		assert(wlr_render_pass_submit(pass));
		wlr_texture_destroy(src);
		for (int y = 20; y < 160; y += 40) for (int x = 20; x < 200; x += 40) {
			uint32_t a = pixel(renderer, proxy, x + 112, y + 112);
			uint32_t b = pixel(renderer, &riferimento, x, y);
			if (a != b) fprintf(stderr, "trasformazione %d crop %d a %d,%d: %08x != %08x\n", t, crop, x, y, a, b);
			assert(a == b);
		}
	}
	// Blur nativo: sfuma un bordo netto rosso/blu, conserva i pixel fuori
	// dalla destinazione, e rispetta una maschera tutta trasparente.
	struct campione *mask_buffer = calloc(1, sizeof(*mask_buffer));
	assert(mask_buffer);
	wlr_buffer_init(&mask_buffer->base, &campione_impl, 64, 64);
	struct wlr_texture *mask_texture = wlr_texture_from_buffer(renderer, &mask_buffer->base);
	assert(mask_texture);
	for (int masked = 0; masked < 2; masked++) {
		struct wlr_render_pass *pass = wlr_renderer_begin_buffer_pass(renderer, dest, NULL);
		assert(pass);
		wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options){
			.box={0,0,100,160}, .color={1,0,0,1}});
		wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options){
			.box={100,0,100,160}, .color={0,0,1,1}});
		struct wlr_render_texture_options mask = {.texture=mask_texture};
		assert(wlr_minerva_render_blur(pass, &(struct wlr_render_rect_options){
			.box={20,20,160,120}, .minerva.corners=wlr_minerva_radii_all(12)}, masked ? &mask : NULL));
		assert(wlr_render_pass_submit(pass));
		uint32_t center=pixel(renderer,&riferimento,100,80);
		if (masked) assert(center==0xff0000ff);
		else {
			assert(((center>>16)&255)>20 && (center&255)>20);
			assert((center>>24)==255);
		}
		assert(pixel(renderer,&riferimento,10,80)==0xffff0000);
		assert(pixel(renderer,&riferimento,190,80)==0xff0000ff);
	}
	// Cattura fuori centro: colori diversi sopra/sotto rendono visibile
	// un'inversione verticale anche quando il filtro conserva colori uniformi.
	for (int top = 0; top <= 120; top += 120) {
		struct wlr_render_pass *pass = wlr_renderer_begin_buffer_pass(renderer, dest, NULL);
		assert(pass);
		wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options){
			.box={0,0,200,80}, .color={1,0,0,1}});
		wlr_render_pass_add_rect(pass, &(struct wlr_render_rect_options){
			.box={0,80,200,80}, .color={0,0,1,1}});
		assert(wlr_minerva_render_blur(pass, &(struct wlr_render_rect_options){
			.box={20,top,160,40}}, NULL));
		assert(wlr_render_pass_submit(pass));
		assert(pixel(renderer, &riferimento, 100, top + 20) ==
			(top == 0 ? 0xffff0000 : 0xff0000ff));
		assert(pixel(renderer, &riferimento, 100, top == 0 ? 140 : 20) ==
			(top == 0 ? 0xff0000ff : 0xffff0000));
	}
	wlr_texture_destroy(mask_texture); wlr_buffer_drop(&mask_buffer->base);
	// Coordinate estreme fuori schermo: nessun overflow del padding e
	// nessuna modifica del framebuffer (esercitato anche sotto UBSan).
	struct wlr_render_pass *outside = wlr_renderer_begin_buffer_pass(renderer, dest, NULL);
	assert(outside);
	wlr_render_pass_add_rect(outside, &(struct wlr_render_rect_options){
		.box={0,0,200,160}, .color={0,1,0,1}});
	const int extremes[] = {INT_MIN, INT_MAX};
	for (size_t i = 0; i < 2; i++) {
		assert(wlr_minerva_render_blur(outside, &(struct wlr_render_rect_options){
			.box={extremes[i],20,40,40}}, NULL));
		assert(wlr_minerva_render_blur(outside, &(struct wlr_render_rect_options){
			.box={20,extremes[i],40,40}}, NULL));
	}
	assert(wlr_render_pass_submit(outside));
	assert(pixel(renderer, &riferimento, 100, 80) == 0xff00ff00);
	wlr_buffer_drop(dest);
	wobbly_distruggi(w);
	assert(r->node.parent == window && r->node.enabled);
	assert(image->node.parent == window && image->node.enabled);
	// Gesti successivi: riutilizzo della riserva e distruzione ripetuta,
	// alternando dimensioni per esercitare la cache delle swapchain.
	for (int i = 0; i < 32; i++) {
		w = wobbly_crea(window, renderer, allocator, NULL);
		assert(w);
		assert(wobbly_disegna(w, &o, i % 2 ? 1 : 2));
		wobbly_distruggi(w);
		assert(image->node.parent == window && image->node.enabled);
	}
	wlr_scene_node_destroy(&scene->tree.node);
	wlr_buffer_drop(&c->base);
	prova_blur_occlusione(backend, renderer, allocator);
finish:
	wlr_allocator_destroy(allocator);
	wlr_renderer_destroy(renderer);
	if (release_display) assert(eglTerminate(egl_display));
	wlr_backend_destroy(backend);
	wl_display_destroy(display);
	puts(baseline ? "ok: sola creazione e distruzione del renderer" :
		"ok: deformazione GPU, blur e maschera, pixel, input, scala, 120 fotogrammi e 32 riaperture");
	return 0;
}
