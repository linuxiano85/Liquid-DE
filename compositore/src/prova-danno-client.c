// prova-danno-client — Un client Wayland che dichiara danneggiato SOLO
// quello che cambia davvero.
//
// ── Perché esiste ─────────────────────────────────────────────────────────
//
// Per provare il danno incrementale del blur serve qualcosa, SOTTO un filtro,
// che cambi pochi pixel e lo dica con esattezza. Nessun programma installato
// lo fa: alacritty dichiara danneggiata tutta la finestra a ogni fotogramma
// (misurato il 23 settembre 2026 col metro del compositore: 921.600 pixel su
// 921.600), e una finestra Qt col renderer software anche (67,6 % dello
// schermo per un quadrato di 70 pixel). Con client così il danno copre
// sempre il filtro intero, e una prova non può distinguere un danno giusto
// da uno sbagliato: `prova-danno-blur.py` è rimasta VERDE col filtro rotto
// apposta finché usava quelli.
//
// Questo disegna un quadrato bianco su fondo scuro, lo sposta a ogni
// fotogramma, e dichiara con `damage_buffer` solo il quadrato vecchio e
// quello nuovo. Due buffer in memoria condivisa, alternati: in ognuno si
// cancellano le ultime due posizioni e si disegna la nuova.
//
// Uso: prova-danno-client [larghezza altezza] [intero]   (di serie 800 500)
// Con «intero» chiede lo schermo intero: il banco dello scanout diretto.
// Con SIGSTOP si ferma dov'è: la prova lo usa per fotografare uno stato fermo.
#define _GNU_SOURCE
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "xdg-shell-client.h"

#define LATO 70
#define FONDO 0xff1d2630u
#define BIANCO 0xffffffffu

struct buffer {
	struct wl_buffer *wl;
	uint32_t *pixel;
	bool occupato;
	int storia[2][2];      // le ultime due posizioni disegnate qui
	int quante;
};

static struct wl_compositor *compositore;
static struct wl_shm *shm;
static struct xdg_wm_base *wm;
static struct wl_surface *superficie;
static struct buffer buffer[2];
static int larghezza = 800, altezza = 500;
static bool configurato = false;
static unsigned passo = 0;
static int vecchia[2] = {-1, -1};
static bool vuole_intero = false;

static void registro_globale(void *d, struct wl_registry *r, uint32_t nome,
		const char *interfaccia, uint32_t versione) {
	(void)d; (void)versione;
	if (strcmp(interfaccia, wl_compositor_interface.name) == 0)
		compositore = wl_registry_bind(r, nome, &wl_compositor_interface, 4);
	else if (strcmp(interfaccia, wl_shm_interface.name) == 0)
		shm = wl_registry_bind(r, nome, &wl_shm_interface, 1);
	else if (strcmp(interfaccia, xdg_wm_base_interface.name) == 0)
		wm = wl_registry_bind(r, nome, &xdg_wm_base_interface, 1);
}
static void registro_via(void *d, struct wl_registry *r, uint32_t nome) {
	(void)d; (void)r; (void)nome;
}
static const struct wl_registry_listener ascolta_registro = {
	registro_globale, registro_via,
};

static void wm_ping(void *d, struct xdg_wm_base *w, uint32_t serie) {
	(void)d;
	xdg_wm_base_pong(w, serie);
}
static const struct xdg_wm_base_listener ascolta_wm = { wm_ping };

static void buffer_rilasciato(void *d, struct wl_buffer *b) {
	(void)b;
	((struct buffer *)d)->occupato = false;
}
static const struct wl_buffer_listener ascolta_buffer = { buffer_rilasciato };

static void riempi(struct buffer *b, int x, int y, uint32_t colore) {
	for (int j = y; j < y + LATO && j < altezza; j++)
		for (int i = x; i < x + LATO && i < larghezza; i++)
			b->pixel[j * larghezza + i] = colore;
}

static void disegna(void);

static void fotogramma_fatto(void *d, struct wl_callback *cb, uint32_t t) {
	(void)d; (void)t;
	wl_callback_destroy(cb);
	disegna();
}
static const struct wl_callback_listener ascolta_fotogramma = { fotogramma_fatto };

static void disegna(void) {
	struct buffer *b = !buffer[0].occupato ? &buffer[0] :
		!buffer[1].occupato ? &buffer[1] : NULL;
	if (b == NULL) {
		// Tutti e due ancora in mano al compositore: si riprova al prossimo.
		struct wl_callback *cb = wl_surface_frame(superficie);
		wl_callback_add_listener(cb, &ascolta_fotogramma, NULL);
		wl_surface_commit(superficie);
		return;
	}
	// Salti che coprono tutta la finestra, sempre diversi.
	int x = (int)((passo * 173u) % (unsigned)(larghezza - LATO));
	int y = (int)((passo * 97u) % (unsigned)(altezza - LATO));
	passo++;

	// In QUESTO buffer si cancellano le posizioni che ci sono state disegnate
	// (può essere indietro di due fotogrammi), e si disegna la nuova.
	for (int k = 0; k < b->quante; k++)
		riempi(b, b->storia[k][0], b->storia[k][1], FONDO);
	riempi(b, x, y, BIANCO);
	b->storia[1][0] = b->storia[0][0]; b->storia[1][1] = b->storia[0][1];
	b->storia[0][0] = x; b->storia[0][1] = y;
	if (b->quante < 2) b->quante++;

	wl_surface_attach(superficie, b->wl, 0, 0);
	// Il danno rispetto al fotogramma PRESENTATO prima: il quadrato di prima
	// e questo. Niente di più — è tutto il senso di questo programma.
	if (vecchia[0] >= 0)
		wl_surface_damage_buffer(superficie, vecchia[0], vecchia[1], LATO, LATO);
	wl_surface_damage_buffer(superficie, x, y, LATO, LATO);
	vecchia[0] = x; vecchia[1] = y;
	b->occupato = true;
	struct wl_callback *cb = wl_surface_frame(superficie);
	wl_callback_add_listener(cb, &ascolta_fotogramma, NULL);
	wl_surface_commit(superficie);
}

static void superficie_configurata(void *d, struct xdg_surface *s, uint32_t serie) {
	(void)d;
	xdg_surface_ack_configure(s, serie);
	if (!configurato) {
		configurato = true;
		// Il primo: tutto il buffer è nuovo, si dichiara tutto.
		struct buffer *b = &buffer[0];
		wl_surface_attach(superficie, b->wl, 0, 0);
		wl_surface_damage_buffer(superficie, 0, 0, larghezza, altezza);
		b->occupato = true;
		struct wl_callback *cb = wl_surface_frame(superficie);
		wl_callback_add_listener(cb, &ascolta_fotogramma, NULL);
		wl_surface_commit(superficie);
	}
}
static const struct xdg_surface_listener ascolta_superficie = { superficie_configurata };

static void toplevel_configura(void *d, struct xdg_toplevel *t, int32_t w, int32_t h,
		struct wl_array *stati) {
	(void)d; (void)t; (void)w; (void)h; (void)stati;
}
static void toplevel_chiudi(void *d, struct xdg_toplevel *t) {
	(void)d; (void)t;
	exit(0);
}
static const struct xdg_toplevel_listener ascolta_toplevel = {
	.configure = toplevel_configura, .close = toplevel_chiudi,
};

int main(int argc, char **argv) {
	if (argc >= 4 && strcmp(argv[3], "intero") == 0)
		vuole_intero = true;
	if (argc >= 3) {
		larghezza = atoi(argv[1]);
		altezza = atoi(argv[2]);
		if (larghezza < LATO * 2 || altezza < LATO * 2 || larghezza > 4000 || altezza > 4000) {
			fprintf(stderr, "misura non valida\n");
			return 2;
		}
	}
	struct wl_display *display = wl_display_connect(NULL);
	if (display == NULL) {
		fprintf(stderr, "prova-danno-client: nessun compositore\n");
		return 1;
	}
	struct wl_registry *registro = wl_display_get_registry(display);
	wl_registry_add_listener(registro, &ascolta_registro, NULL);
	wl_display_roundtrip(display);
	if (compositore == NULL || shm == NULL || wm == NULL) {
		fprintf(stderr, "prova-danno-client: manca un protocollo\n");
		return 1;
	}
	xdg_wm_base_add_listener(wm, &ascolta_wm, NULL);

	const int passo_riga = larghezza * 4;
	const size_t per_buffer = (size_t)passo_riga * (size_t)altezza;
	int fd = memfd_create("prova-danno", MFD_CLOEXEC);
	if (fd < 0 || ftruncate(fd, (off_t)(per_buffer * 2)) != 0) {
		perror("prova-danno-client: memoria");
		return 1;
	}
	uint32_t *mem = mmap(NULL, per_buffer * 2, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (mem == MAP_FAILED) {
		perror("prova-danno-client: mmap");
		return 1;
	}
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)(per_buffer * 2));
	for (int k = 0; k < 2; k++) {
		buffer[k].pixel = mem + (per_buffer / 4) * (size_t)k;
		for (size_t i = 0; i < per_buffer / 4; i++)
			buffer[k].pixel[i] = FONDO;
		buffer[k].wl = wl_shm_pool_create_buffer(pool, (int32_t)(per_buffer * (size_t)k),
			larghezza, altezza, passo_riga, WL_SHM_FORMAT_ARGB8888);
		wl_buffer_add_listener(buffer[k].wl, &ascolta_buffer, &buffer[k]);
	}
	wl_shm_pool_destroy(pool);
	close(fd);

	superficie = wl_compositor_create_surface(compositore);
	// Il fondo è opaco, e lo si DICE, come fanno i programmi veri (Chrome,
	// alacritty col fondo pieno): è l'informazione con cui il compositore può
	// non ridipingere ciò che sta dietro. Senza, questo banco sarebbe una
	// finestra più «trasparente» di quelle che si usano.
	struct wl_region *opaca = wl_compositor_create_region(compositore);
	wl_region_add(opaca, 0, 0, larghezza, altezza);
	wl_surface_set_opaque_region(superficie, opaca);
	wl_region_destroy(opaca);
	struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm, superficie);
	xdg_surface_add_listener(xs, &ascolta_superficie, NULL);
	struct xdg_toplevel *top = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(top, &ascolta_toplevel, NULL);
	xdg_toplevel_set_title(top, "prova-danno");
	xdg_toplevel_set_app_id(top, "prova-danno");
	if (vuole_intero)
		xdg_toplevel_set_fullscreen(top, NULL);
	wl_surface_commit(superficie);

	while (wl_display_dispatch(display) != -1)
		;
	return 0;
}
