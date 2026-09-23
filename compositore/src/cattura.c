// minerva-cattura — legge lo schermo e lo scrive grezzo sull'uscita standard.
//
// ── Perché esiste, e perché non è il compositore a farlo ──────────────────
//
// «Trasmetti lo schermo» ha due metà. La seconda — comprimere in H.264 e
// mandarla al televisore — la fa il demone. La prima è prendere i pixel, e
// per quella minerva-wayland implementa già `wlr-screencopy` (`main.c:7351`),
// lo stesso protocollo con cui `grim` fa le fotografie.
//
// Prenderli DENTRO il compositore sarebbe stato più corto e sbagliato: la
// compressione è lavoro a raffica, e ogni millisecondo speso lì è un
// millisecondo in cui la scrivania non disegna. Un programma a parte si può
// far morire, si può mettere a nice più alto, e se si inceppa si porta via
// solo sé stesso. È la stessa ragione per cui il demone è un processo suo.
//
// ── Cosa NON fa apposta ───────────────────────────────────────────────────
//
// Non comprime, non parla in rete, non conosce i televisori. Scrive frame
// grezzi e basta. Così si prova con `ffplay` senza avere una TV accesa, e il
// giorno che la compressione cambia non si tocca il codice che tocca Wayland.
//
// Uso:
//   minerva-cattura [--schermo NOME] [--fps N] [--cursore] > grezzo.raw
//   minerva-cattura --dimmi            (dice la forma e basta, non cattura)
//
// Sulla prima riga dell'uscita d'errore scrive una riga di intestazione che
// dice al chiamante che forma hanno i frame:
//
//   MINERVA_CATTURA larghezza altezza formato_ffmpeg
//
// senza la quale il chiamante dovrebbe indovinare, ed è l'errore che dà un
// video verde e storto invece di un errore.
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-screencopy-unstable-v1-client-protocol.h"

struct schermo {
	struct wl_output *output;
	uint32_t nome_globale;
	char *nome;            // «eDP-1», «HDMI-A-1»
	struct schermo *prossimo;
};

struct stato {
	struct wl_shm *shm;
	struct zwlr_screencopy_manager_v1 *copia;
	struct schermo *schermi;
	uint32_t versione_copia;
	// Il frame in corso.
	uint32_t larghezza, altezza, passo, formato;
	bool pronto, fallito, descritto, formato_scelto;
	struct wl_buffer *buffer;
	void *pixel;
	size_t pixel_byte;
};

static void reg_globale(void *dati, struct wl_registry *reg, uint32_t nome,
		const char *iface, uint32_t versione) {
	struct stato *s = dati;
	if (strcmp(iface, wl_shm_interface.name) == 0) {
		s->shm = wl_registry_bind(reg, nome, &wl_shm_interface, 1);
	} else if (strcmp(iface, zwlr_screencopy_manager_v1_interface.name) == 0) {
		uint32_t v = versione < 3 ? versione : 3;
		s->versione_copia = v;
		s->copia = wl_registry_bind(reg, nome,
			&zwlr_screencopy_manager_v1_interface, v);
	} else if (strcmp(iface, wl_output_interface.name) == 0) {
		// Versione 4: è quella che manda l'evento `name`, cioè l'unica in cui
		// «--schermo HDMI-A-1» può voler dire qualcosa. Sotto la 4 si può
		// ancora catturare, ma solo il primo schermo.
		uint32_t v = versione < 4 ? versione : 4;
		struct schermo *sc = calloc(1, sizeof(*sc));
		// Senza memoria non si cattura questo schermo, e pazienza: gli altri
		// restano. Tirare dritto invece vuol dire scrivere dentro il NULL,
		// cioè un crash — e chi cattura lo schermo sta di solito facendo
		// vedere qualcosa a qualcuno.
		if (sc == NULL)
			return;
		sc->output = wl_registry_bind(reg, nome, &wl_output_interface, v);
		sc->nome_globale = nome;
		sc->prossimo = s->schermi;
		s->schermi = sc;
	}
}

static void reg_via(void *dati, struct wl_registry *reg, uint32_t nome) {
	(void)dati; (void)reg; (void)nome;
}

static const struct wl_registry_listener reg_ascolto = {
	.global = reg_globale,
	.global_remove = reg_via,
};

// ── Gli eventi di wl_output: ci serve solo il nome ────────────────────────
static void out_geometria(void *d, struct wl_output *o, int32_t x, int32_t y,
		int32_t pw, int32_t ph, int32_t sub, const char *make,
		const char *model, int32_t trasf) {
	(void)d; (void)o; (void)x; (void)y; (void)pw; (void)ph; (void)sub;
	(void)make; (void)model; (void)trasf;
}
static void out_modo(void *d, struct wl_output *o, uint32_t f, int32_t w,
		int32_t h, int32_t refresh) {
	(void)d; (void)o; (void)f; (void)w; (void)h; (void)refresh;
}
static void out_fatto(void *d, struct wl_output *o) { (void)d; (void)o; }
static void out_scala(void *d, struct wl_output *o, int32_t s) {
	(void)d; (void)o; (void)s;
}
static void out_nome(void *d, struct wl_output *o, const char *nome) {
	(void)o;
	struct schermo *sc = d;
	// `strdup` può tornare NULL. Il nome serve solo a scegliere lo schermo per
	// nome: senza, si ricade sul primo, che è il comportamento di chi non ha
	// chiesto nessuno schermo in particolare. Meglio quello di un puntatore
	// nullo che gira.
	char *copia = strdup(nome);
	if (copia == NULL)
		return;
	free(sc->nome);
	sc->nome = copia;
}
static void out_descrizione(void *d, struct wl_output *o, const char *desc) {
	(void)d; (void)o; (void)desc;
}
static const struct wl_output_listener out_ascolto = {
	.geometry = out_geometria,
	.mode = out_modo,
	.done = out_fatto,
	.scale = out_scala,
	.name = out_nome,
	.description = out_descrizione,
};

// ── Gli eventi del frame ──────────────────────────────────────────────────
//
// L'ordine è: `buffer` (com'è fatto), poi noi chiediamo `copy`, poi arriva
// `flags` e infine `ready` — o `failed`. Il compositore può mandare `buffer`
// più di una volta (formati diversi): si tiene il primo shm che va bene, che
// è quello che fa anche grim.
static void fr_buffer(void *dati, struct zwlr_screencopy_frame_v1 *fr,
		uint32_t formato, uint32_t larghezza, uint32_t altezza,
		uint32_t passo) {
	(void)fr;
	struct stato *s = dati;
	if (s->formato_scelto) return;
	s->formato = formato;
	s->larghezza = larghezza;
	s->altezza = altezza;
	s->passo = passo;
	s->formato_scelto = true;
	// Dalla versione 3 il compositore elenca PIÙ modi di consegnare il frame
	// (shm e dmabuf) e chiude l'elenco con `buffer_done`: prima di quello non
	// si può chiedere la copia. Sotto la 3 l'elenco non esiste e `buffer` è
	// già il via libera. Dimenticarlo non dà un errore nostro: dà un abort
	// dentro libwayland, «listener function for opcode 5 is NULL».
	if (s->versione_copia < 3) s->descritto = true;
}

// dmabuf: il frame ci sarebbe offerto anche senza passare dalla memoria
// centrale, ed è la strada veloce. Non la prendiamo **adesso**: vuol dire
// parlare con la GPU (EGL, importazione, formati modificati), cioè un pezzo
// di codice grande quanto tutto il resto di questo file. Si dichiara e si
// ignora — dichiararla è obbligatorio comunque, perché un puntatore nullo
// qui fa abortire libwayland.
static void fr_dmabuf(void *dati, struct zwlr_screencopy_frame_v1 *fr,
		uint32_t formato, uint32_t larghezza, uint32_t altezza) {
	(void)dati; (void)fr; (void)formato; (void)larghezza; (void)altezza;
}

static void fr_buffer_fatto(void *dati, struct zwlr_screencopy_frame_v1 *fr) {
	(void)fr;
	((struct stato *)dati)->descritto = true;
}

static void fr_flags(void *dati, struct zwlr_screencopy_frame_v1 *fr,
		uint32_t flags) {
	(void)fr;
	// `Y_INVERT` vuol dire che il compositore ha scritto le righe dal basso.
	// Non lo raddrizziamo qui: girare un'immagine intera a ogni frame con il
	// processore è esattamente il costo che questo programma esiste per non
	// pagare. Lo diciamo al chiamante, che lo fa dire a ffmpeg con un filtro
	// che gira sulla GPU.
	(void)dati;
	if (flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT) {
		static bool detto = false;
		if (!detto) {
			fprintf(stderr, "MINERVA_CATTURA_ROVESCIA 1\n");
			fflush(stderr);
			detto = true;
		}
	}
}

static void fr_pronto(void *dati, struct zwlr_screencopy_frame_v1 *fr,
		uint32_t sec_hi, uint32_t sec_lo, uint32_t nsec) {
	(void)fr; (void)sec_hi; (void)sec_lo; (void)nsec;
	((struct stato *)dati)->pronto = true;
}

static void fr_fallito(void *dati, struct zwlr_screencopy_frame_v1 *fr) {
	(void)fr;
	((struct stato *)dati)->fallito = true;
}

static void fr_danno(void *dati, struct zwlr_screencopy_frame_v1 *fr,
		uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
	(void)dati; (void)fr; (void)x; (void)y; (void)w; (void)h;
}

static const struct zwlr_screencopy_frame_v1_listener fr_ascolto = {
	.buffer = fr_buffer,
	.flags = fr_flags,
	.ready = fr_pronto,
	.failed = fr_fallito,
	.damage = fr_danno,
	.linux_dmabuf = fr_dmabuf,
	.buffer_done = fr_buffer_fatto,
};

// ── Il nome ffmpeg del formato ────────────────────────────────────────────
//
// wl_shm parla in «canali dentro una parola a 32 bit», ffmpeg in «byte in
// ordine di memoria». Su una macchina little endian XRGB8888 è, byte per
// byte, B G R X — che ffmpeg chiama `bgr0`. Sbagliare qui non dà errore: dà
// un video con le facce blu, ed è il difetto che si scopre guardando.
static const char *nome_formato(uint32_t f) {
	switch (f) {
	case WL_SHM_FORMAT_XRGB8888: return "bgr0";
	case WL_SHM_FORMAT_ARGB8888: return "bgra";
	case WL_SHM_FORMAT_XBGR8888: return "rgb0";
	case WL_SHM_FORMAT_ABGR8888: return "rgba";
	default: return NULL;
	}
}

static int memoria_anonima(size_t byte) {
	char percorso[] = "/minerva-cattura-XXXXXX";
	// `memfd_create` sarebbe più pulito, ma shm_open c'è ovunque e non ha
	// bisogno di un #define di glibc: qui non vale una riga di portabilità.
	for (int tentativo = 0; tentativo < 100; tentativo++) {
		struct timespec t;
		clock_gettime(CLOCK_REALTIME, &t);
		snprintf(percorso, sizeof(percorso), "/minerva-cat-%06lx",
			(unsigned long)((t.tv_nsec + tentativo) & 0xffffff));
		int fd = shm_open(percorso, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd >= 0) {
			shm_unlink(percorso);
			if (ftruncate(fd, (off_t)byte) < 0) { close(fd); return -1; }
			return fd;
		}
		if (errno != EEXIST) return -1;
	}
	return -1;
}

static void aiuto(void) {
	fprintf(stderr,
		"minerva-cattura — lo schermo, grezzo, sull'uscita standard.\n"
		"\n"
		"  --schermo NOME   quale schermo (eDP-1, HDMI-A-1). Senza: il primo.\n"
		"  --fps N          quanti frame al secondo (2..60, di norma 30)\n"
		"  --frame N        fermati dopo N frame (di norma: mai)\n"
		"  --cursore        disegna anche il puntatore\n"
		"  --dimmi          scrivi la riga di intestazione e fermati\n"
		"  --schermi        elenca i nomi degli schermi, uno per riga\n"
		"\n"
		"Scrive su stderr, prima di tutto:\n"
		"  MINERVA_CATTURA <larghezza> <altezza> <formato-ffmpeg>\n");
}

int main(int argc, char **argv) {
	const char *voluto = NULL;
	int fps = 30, cursore = 0, dimmi = 0, elenca = 0;
	long limite = -1;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--schermo") == 0 && i + 1 < argc) {
			voluto = argv[++i];
		} else if (strcmp(argv[i], "--fps") == 0 && i + 1 < argc) {
			fps = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--frame") == 0 && i + 1 < argc) {
			limite = atol(argv[++i]);
		} else if (strcmp(argv[i], "--cursore") == 0) {
			cursore = 1;
		} else if (strcmp(argv[i], "--dimmi") == 0) {
			// Chi comprime deve sapere larghezza, altezza e formato PRIMA di
			// partire, e senza indovinarli: ffmpeg legge byte grezzi, e una
			// geometria sbagliata non dà errore — dà un video storto. Qui il
			// compositore la dice nell'evento `buffer`, cioè prima di copiare
			// un solo pixel: costa un giro di rete locale e niente memoria.
			dimmi = 1;
		} else if (strcmp(argv[i], "--schermi") == 0) {
			elenca = 1;
		} else {
			aiuto();
			return argc > 1 && strcmp(argv[1], "--aiuto") == 0 ? 0 : 2;
		}
	}
	if (fps < 2) fps = 2;
	if (fps > 60) fps = 60;

	struct wl_display *display = wl_display_connect(NULL);
	if (!display) {
		fprintf(stderr, "minerva-cattura: nessun compositore "
			"(WAYLAND_DISPLAY non è impostata?)\n");
		return 1;
	}

	struct stato s = {0};
	struct wl_registry *reg = wl_display_get_registry(display);
	wl_registry_add_listener(reg, &reg_ascolto, &s);
	wl_display_roundtrip(display);

	for (struct schermo *sc = s.schermi; sc; sc = sc->prossimo) {
		wl_output_add_listener(sc->output, &out_ascolto, sc);
	}
	wl_display_roundtrip(display);   // fa arrivare i nomi

	if (!s.shm || !s.copia) {
		fprintf(stderr, "minerva-cattura: questo compositore non offre "
			"wlr-screencopy\n");
		return 1;
	}

	struct schermo *scelto = NULL;
	if (voluto) {
		for (struct schermo *sc = s.schermi; sc; sc = sc->prossimo) {
			if (sc->nome && strcmp(sc->nome, voluto) == 0) { scelto = sc; break; }
		}
		if (!scelto) {
			fprintf(stderr, "minerva-cattura: nessuno schermo si chiama «%s». "
				"Ci sono:", voluto);
			for (struct schermo *sc = s.schermi; sc; sc = sc->prossimo) {
				fprintf(stderr, " %s", sc->nome ? sc->nome : "(senza nome)");
			}
			fprintf(stderr, "\n");
			return 1;
		}
	} else {
		// L'ultimo annunciato è il primo della lista: la si gira per prendere
		// quello che il compositore ha annunciato per primo, che è lo schermo
		// principale.
		for (struct schermo *sc = s.schermi; sc; sc = sc->prossimo) scelto = sc;
	}
	if (!scelto) {
		fprintf(stderr, "minerva-cattura: nessuno schermo\n");
		return 1;
	}

	if (elenca) {
		for (struct schermo *sc = s.schermi; sc; sc = sc->prossimo) {
			printf("%s\n", sc->nome ? sc->nome : "(senza nome)");
		}
		wl_display_disconnect(display);
		return 0;
	}

	const long periodo_ns = 1000000000L / fps;
	struct timespec prossimo;
	clock_gettime(CLOCK_MONOTONIC, &prossimo);
	long fatti = 0;
	bool intestazione = false;

	while (limite < 0 || fatti < limite) {
		s.pronto = s.fallito = s.descritto = s.formato_scelto = false;
		struct zwlr_screencopy_frame_v1 *fr =
			zwlr_screencopy_manager_v1_capture_output(s.copia, cursore,
				scelto->output);
		zwlr_screencopy_frame_v1_add_listener(fr, &fr_ascolto, &s);

		// Aspetta la descrizione del buffer.
		while (!s.descritto && !s.fallito) {
			if (wl_display_dispatch(display) < 0) { s.fallito = true; break; }
		}
		if (s.fallito) { zwlr_screencopy_frame_v1_destroy(fr); break; }

		const char *pf = nome_formato(s.formato);
		if (!pf) {
			fprintf(stderr, "minerva-cattura: formato %u sconosciuto\n",
				s.formato);
			return 1;
		}
		if (!intestazione) {
			fprintf(stderr, "MINERVA_CATTURA %u %u %s\n",
				s.larghezza, s.altezza, pf);
			fflush(stderr);
			intestazione = true;
		}
		if (dimmi) {
			// Sull'uscita standard anche, così chi legge non deve mettersi a
			// separare stderr per una domanda sola.
			printf("MINERVA_CATTURA %u %u %s\n", s.larghezza, s.altezza, pf);
			zwlr_screencopy_frame_v1_destroy(fr);
			wl_display_disconnect(display);
			return 0;
		}

		size_t byte = (size_t)s.passo * s.altezza;
		if (!s.buffer || byte != s.pixel_byte) {
			// Il buffer si crea una volta e si riusa: rifarlo trenta volte al
			// secondo vorrebbe dire trenta mmap e trenta munmap al secondo,
			// che è lavoro puro per niente.
			if (s.buffer) {
				wl_buffer_destroy(s.buffer);
				munmap(s.pixel, s.pixel_byte);
			}
			int fd = memoria_anonima(byte);
			if (fd < 0) {
				fprintf(stderr, "minerva-cattura: memoria condivisa: %s\n",
					strerror(errno));
				return 1;
			}
			s.pixel = mmap(NULL, byte, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
			if (s.pixel == MAP_FAILED) {
				fprintf(stderr, "minerva-cattura: mmap: %s\n", strerror(errno));
				return 1;
			}
			struct wl_shm_pool *pool = wl_shm_create_pool(s.shm, fd, (int32_t)byte);
			s.buffer = wl_shm_pool_create_buffer(pool, 0, (int32_t)s.larghezza,
				(int32_t)s.altezza, (int32_t)s.passo, s.formato);
			wl_shm_pool_destroy(pool);
			close(fd);
			s.pixel_byte = byte;
		}

		zwlr_screencopy_frame_v1_copy(fr, s.buffer);
		while (!s.pronto && !s.fallito) {
			if (wl_display_dispatch(display) < 0) { s.fallito = true; break; }
		}
		zwlr_screencopy_frame_v1_destroy(fr);
		if (s.fallito) break;

		// Scrivere può essere parziale: chi legge è ffmpeg, e una scrittura
		// mezza vuol dire un'immagine sfasata di qualche riga per sempre.
		const unsigned char *p = s.pixel;
		size_t resta = byte;
		while (resta > 0) {
			ssize_t n = write(STDOUT_FILENO, p, resta);
			if (n < 0) {
				if (errno == EINTR) continue;
				// EPIPE: chi leggeva se n'è andato. È il modo normale di
				// finire, non un errore.
				return errno == EPIPE ? 0 : 1;
			}
			p += n;
			resta -= (size_t)n;
		}
		fatti++;

		// Il ritmo si tiene su un orologio assoluto, non dormendo «il resto»:
		// così un frame lento non sposta in avanti tutti quelli dopo.
		prossimo.tv_nsec += periodo_ns;
		while (prossimo.tv_nsec >= 1000000000L) {
			prossimo.tv_nsec -= 1000000000L;
			prossimo.tv_sec++;
		}
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &prossimo, NULL);
	}

	if (s.buffer) {
		wl_buffer_destroy(s.buffer);
		munmap(s.pixel, s.pixel_byte);
	}
	wl_display_disconnect(display);
	return s.fallito ? 1 : 0;
}
