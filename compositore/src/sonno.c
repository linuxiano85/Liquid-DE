// sonno.c — L'inibitore di logind. Il perché sta in `sonno.h`.
//
// Il bus di sd-bus si innesta nel ciclo di wayland con il suo fd e il suo
// timer, come fa ogni compositore che parla con logind: non c'è un secondo
// ciclo, non c'è un filo in più, e `sd_bus_process` gira solo quando c'è
// qualcosa da leggere.
#define _POSIX_C_SOURCE 200809L
#include "sonno.h"
#include <systemd/sd-bus.h>
#include <wayland-server-core.h>
#include <wlr/util/log.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

struct sonno {
	sd_bus *bus;
	sd_bus_slot *segnale, *richiesta;
	struct wl_event_source *fd, *timer, *protezione_timer;
	void (*proteggi)(void *);
	void *dati;
	int inibitore;
	bool dorme, guasto;
};

static void rilascia(struct sonno *s) {
	if (s->inibitore >= 0) close(s->inibitore);
	s->inibitore = -1;
}

static void aggiorna(struct sonno *s) {
	if (s->guasto) return;
	int eventi = sd_bus_get_events(s->bus);
	uint64_t quando = UINT64_MAX;
	if (eventi < 0 || sd_bus_get_timeout(s->bus, &quando) < 0) return;
	wl_event_source_fd_update(s->fd, ((eventi & POLLIN) ? WL_EVENT_READABLE : 0) |
		((eventi & POLLOUT) ? WL_EVENT_WRITABLE : 0));
	int ms = 0;
	if (quando != UINT64_MAX) {
		struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
		uint64_t ora = (uint64_t)now.tv_sec * 1000000 + now.tv_nsec / 1000;
		uint64_t delta = quando > ora ? (quando - ora) / 1000 + 1 : 1;
		ms = delta > INT_MAX ? INT_MAX : (int)delta;
	}
	wl_event_source_timer_update(s->timer, ms);
}

static int inibito(sd_bus_message *m, void *data, sd_bus_error *error) {
	(void)error;
	struct sonno *s = data;
	int fd;
	if (sd_bus_message_is_method_error(m, NULL) || sd_bus_message_read(m, "h", &fd) < 0) {
		// Senza inibitore non si può garantire il blocco prima del sonno:
		// `sonno_pronto` dirà falso e il verbo `sospendi` rifiuterà. Non si
		// blocca lo schermo adesso — nessuno sta dormendo.
		wlr_log(WLR_ERROR, "minerva: logind non concede l'inibitore sleep: "
			"la sospensione da Minerva resta rifiutata");
		return 0;
	}
	rilascia(s);
	if (!s->dorme) s->inibitore = fcntl(fd, F_DUPFD_CLOEXEC, 3);
	return 0;
}

static void acquisisci(struct sonno *s) {
	s->richiesta = sd_bus_slot_unref(s->richiesta);
	int r = sd_bus_call_method_async(s->bus, &s->richiesta,
		"org.freedesktop.login1", "/org/freedesktop/login1",
		"org.freedesktop.login1.Manager", "Inhibit", inibito, s, "ssss",
		"sleep", "Minerva", "Proteggere la sessione prima della sospensione", "delay");
	if (r < 0) wlr_log(WLR_ERROR, "minerva: richiesta inibitore fallita");
}

static int protezione_lenta(void *data) {
	struct sonno *s = data;
	if (s->dorme && s->inibitore >= 0)
		wlr_log(WLR_ERROR, "minerva: protezione non presentata dopo 2 secondi; logind puo superare il limite dell'inibitore delay");
	return 0;
}

static int prepara(sd_bus_message *m, void *data, sd_bus_error *error) {
	(void)error;
	struct sonno *s = data;
	int dorme;
	if (sd_bus_message_read(m, "b", &dorme) < 0) return 0;
	s->dorme = dorme;
	if (dorme) {
		wl_event_source_timer_update(s->protezione_timer, 2000);
		// Include richieste esterne, tasto fisico e coperchio gestiti da logind.
		s->proteggi(s->dati);
	} else {
		wl_event_source_timer_update(s->protezione_timer, 0);
		acquisisci(s);
	}
	return 0;
}

static int ascolto_installato(sd_bus_message *m, void *data, sd_bus_error *error) {
	(void)error;
	struct sonno *s = data;
	if (sd_bus_message_is_method_error(m, NULL)) {
		// Senza il segnale non sapremmo QUANDO bloccare: si molla anche
		// l'inibitore, o terremmo logind fermo per sempre senza mai
		// rispondergli. Da qui in poi `sonno_pronto` è falso.
		s->guasto = true;
		rilascia(s);
		wlr_log(WLR_ERROR, "minerva: ascolto PrepareForSleep non disponibile: "
			"la sospensione da Minerva resta rifiutata");
	}
	return 0;
}

static int elabora(void *data) {
	struct sonno *s = data;
	int r = 0;
	for (int i = 0; i < 32; i++) {
		r = sd_bus_process(s->bus, NULL);
		if (r <= 0) break;
	}
	if (r < 0) {
		// Perso il bus. Si smette di ascoltare e si dice: NON si blocca lo
		// schermo — vedi in cima a `sonno.h`. La sospensione da Minerva resta
		// rifiutata finché la sessione non riparte.
		s->guasto = true;
		rilascia(s);
		wl_event_source_fd_update(s->fd, 0);
		wl_event_source_timer_update(s->timer, 0);
		wlr_log(WLR_ERROR, "minerva: bus logind perso: la sospensione da "
			"Minerva resta rifiutata");
		return 0;
	}
	aggiorna(s);
	if (r > 0) wl_event_source_timer_update(s->timer, 1);
	return 0;
}

static int leggibile(int fd, uint32_t mask, void *data) {
	(void)fd; (void)mask;
	return elabora(data);
}

struct sonno *sonno_crea(struct wl_event_loop *loop, void (*proteggi)(void *), void *data) {
	struct sonno *s = calloc(1, sizeof(*s));
	if (!s) return NULL;
	s->inibitore = -1; s->proteggi = proteggi; s->dati = data;
	if (sd_bus_open_system(&s->bus) < 0) goto fail;
	sd_bus_set_method_call_timeout(s->bus, 2000000);
	s->fd = wl_event_loop_add_fd(loop, sd_bus_get_fd(s->bus), WL_EVENT_READABLE, leggibile, s);
	s->timer = wl_event_loop_add_timer(loop, elabora, s);
	s->protezione_timer = wl_event_loop_add_timer(loop, protezione_lenta, s);
	if (!s->fd || !s->timer || !s->protezione_timer) goto fail;
	if (sd_bus_match_signal_async(s->bus, &s->segnale, "org.freedesktop.login1",
		"/org/freedesktop/login1", "org.freedesktop.login1.Manager",
		"PrepareForSleep", prepara, ascolto_installato, s) < 0) goto fail;
	acquisisci(s);
	aggiorna(s);
	return s;
fail:
	sonno_distruggi(s);
	return NULL;
}

bool sonno_pronto(struct sonno *s) { return s && !s->guasto && s->inibitore >= 0; }

void sonno_protetto(struct sonno *s) {
	if (s && s->dorme) {
		wl_event_source_timer_update(s->protezione_timer, 0);
		rilascia(s);
	}
}

void sonno_distruggi(struct sonno *s) {
	if (!s) return;
	if (s->fd) wl_event_source_remove(s->fd);
	if (s->timer) wl_event_source_remove(s->timer);
	if (s->protezione_timer) wl_event_source_remove(s->protezione_timer);
	sd_bus_slot_unref(s->segnale); sd_bus_slot_unref(s->richiesta);
	rilascia(s);
	sd_bus_flush_close_unref(s->bus);
	free(s);
}
