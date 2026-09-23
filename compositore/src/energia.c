// energia.c — UPower e power-profiles-daemon. Il perché sta in `energia.h`.
//
// Stessa innestatura di `sonno.c`: il fd di sd-bus nel ciclo di wayland, e
// `sd_bus_process` solo quando c'è qualcosa da leggere.
#define _POSIX_C_SOURCE 200809L
#include "energia.h"
#include <systemd/sd-bus.h>
#include <wayland-server-core.h>
#include <wlr/util/log.h>
#include <limits.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define UPOWER "org.freedesktop.UPower"
#define BATTERIA "/org/freedesktop/UPower/devices/DisplayDevice"
#define BATTERIA_IF "org.freedesktop.UPower.Device"
#define PROFILI "org.freedesktop.UPower.PowerProfiles"
#define PROFILI_PATH "/org/freedesktop/UPower/PowerProfiles"
#define PROPRIETA "org.freedesktop.DBus.Properties"

struct energia {
	sd_bus *bus;
	sd_bus_slot *batteria_segnale, *profilo_segnale;
	sd_bus_slot *batteria_chiesta, *profilo_chiesto;
	struct wl_event_source *fd, *timer;
	void (*cambiata)(void *);
	void *dati;
	struct energia_stato stato;
	/// Le due cose che fanno la batteria «vera»: presente, e di tipo
	/// batteria (2). Il DisplayDevice di un fisso esiste lo stesso, vuoto.
	bool presente;
	uint32_t tipo;
	bool guasto;
};

static void aggiorna(struct energia *e) {
	if (e->guasto)
		return;
	int eventi = sd_bus_get_events(e->bus);
	uint64_t quando = UINT64_MAX;
	if (eventi < 0 || sd_bus_get_timeout(e->bus, &quando) < 0)
		return;
	wl_event_source_fd_update(e->fd, ((eventi & POLLIN) ? WL_EVENT_READABLE : 0) |
		((eventi & POLLOUT) ? WL_EVENT_WRITABLE : 0));
	int ms = 0;
	if (quando != UINT64_MAX) {
		struct timespec ora;
		clock_gettime(CLOCK_MONOTONIC, &ora);
		uint64_t adesso = (uint64_t)ora.tv_sec * 1000000 + ora.tv_nsec / 1000;
		uint64_t delta = quando > adesso ? (quando - adesso) / 1000 + 1 : 1;
		ms = delta > INT_MAX ? INT_MAX : (int)delta;
	}
	wl_event_source_timer_update(e->timer, ms);
}

/// Legge un `a{sv}` e aggiorna solo i campi che ci sono: vale per la
/// risposta di `GetAll` (tutti) e per `PropertiesChanged` (quelli cambiati).
static int leggi_proprieta(sd_bus_message *m, struct energia *e) {
	int r = sd_bus_message_enter_container(m, 'a', "{sv}");
	if (r < 0)
		return r;
	while ((r = sd_bus_message_enter_container(m, 'e', "sv")) > 0) {
		const char *nome = NULL;
		if ((r = sd_bus_message_read(m, "s", &nome)) < 0)
			return r;
		if (strcmp(nome, "Percentage") == 0) {
			double p = 0;
			r = sd_bus_message_read(m, "v", "d", &p);
			if (r >= 0 && isfinite(p))
				e->stato.percento = p < 0 ? 0 : (p > 100 ? 100 : p);
		} else if (strcmp(nome, "State") == 0) {
			uint32_t s = 0;
			r = sd_bus_message_read(m, "v", "u", &s);
			// 2 in scarica, 6 «in attesa di scaricarsi». Tutto il resto —
			// in carica, carica, vuota, in attesa di caricarsi — vuol dire
			// che la corrente c'è o che non c'è più niente da salvare.
			if (r >= 0)
				e->stato.scarica = s == 2 || s == 6;
		} else if (strcmp(nome, "IsPresent") == 0) {
			int b = 0;
			r = sd_bus_message_read(m, "v", "b", &b);
			if (r >= 0)
				e->presente = b;
		} else if (strcmp(nome, "Type") == 0) {
			uint32_t t = 0;
			r = sd_bus_message_read(m, "v", "u", &t);
			if (r >= 0)
				e->tipo = t;
		} else if (strcmp(nome, "ActiveProfile") == 0) {
			const char *p = NULL;
			r = sd_bus_message_read(m, "v", "s", &p);
			if (r >= 0 && p != NULL) {
				e->stato.profilo_risparmio = strcmp(p, "power-saver") == 0;
				e->stato.profilo_noto = true;
			}
		} else {
			r = sd_bus_message_skip(m, "v");
		}
		if (r < 0)
			return r;
		if ((r = sd_bus_message_exit_container(m)) < 0)
			return r;
	}
	if (r < 0)
		return r;
	return sd_bus_message_exit_container(m);
}

/// Chiama `cambiata` solo se qualcosa è cambiato davvero: UPower annuncia
/// anche l'energia in wattora e il tempo che resta, che qui non contano, e
/// ognuno di quegli annunci sarebbe un giro di ricalcolo per niente.
static void forse_avvisa(struct energia *e, struct energia_stato prima) {
	e->stato.batteria = e->presente && e->tipo == 2;
	const struct energia_stato *d = &e->stato;
	if (d->batteria == prima.batteria && d->scarica == prima.scarica
			&& (int)d->percento == (int)prima.percento
			&& d->profilo_risparmio == prima.profilo_risparmio
			&& d->profilo_noto == prima.profilo_noto)
		return;
	if (e->cambiata != NULL)
		e->cambiata(e->dati);
}

static int risposta_letta(sd_bus_message *m, void *data, sd_bus_error *err) {
	(void)err;
	struct energia *e = data;
	if (sd_bus_message_is_method_error(m, NULL)) {
		// Non c'è: UPower assente, o power-profiles-daemon assente. Non è
		// un guasto — vuol dire che quella metà non farà mai scattare niente.
		const sd_bus_error *be = sd_bus_message_get_error(m);
		wlr_log(WLR_INFO, "minerva: energia: %s",
			be && be->message ? be->message : "servizio assente");
		return 0;
	}
	struct energia_stato prima = e->stato;
	if (leggi_proprieta(m, e) < 0) {
		wlr_log(WLR_ERROR, "minerva: energia: risposta illeggibile");
		return 0;
	}
	forse_avvisa(e, prima);
	return 0;
}

static int cambiate(sd_bus_message *m, void *data, sd_bus_error *err) {
	(void)err;
	struct energia *e = data;
	const char *interfaccia = NULL;
	if (sd_bus_message_read(m, "s", &interfaccia) < 0)
		return 0;
	if (strcmp(interfaccia, BATTERIA_IF) != 0 && strcmp(interfaccia, PROFILI) != 0)
		return 0;
	struct energia_stato prima = e->stato;
	if (leggi_proprieta(m, e) < 0)
		return 0;
	forse_avvisa(e, prima);
	return 0;
}

static int elabora(void *data) {
	struct energia *e = data;
	int r = 0;
	for (int i = 0; i < 32; i++) {
		r = sd_bus_process(e->bus, NULL);
		if (r <= 0)
			break;
	}
	if (r < 0) {
		// Perso il bus: si resta con l'ultimo stato saputo. Non si spegne
		// e non si accende niente per un singhiozzo di D-Bus.
		e->guasto = true;
		wl_event_source_fd_update(e->fd, 0);
		wl_event_source_timer_update(e->timer, 0);
		wlr_log(WLR_ERROR, "minerva: energia: bus di sistema perso, "
			"resta l'ultimo stato saputo della batteria");
		return 0;
	}
	aggiorna(e);
	if (r > 0)
		wl_event_source_timer_update(e->timer, 1);
	return 0;
}

static int leggibile(int fd, uint32_t mask, void *data) {
	(void)fd; (void)mask;
	return elabora(data);
}

struct energia *energia_crea(struct wl_event_loop *loop, void (*cambiata)(void *), void *dati) {
	struct energia *e = calloc(1, sizeof(*e));
	if (e == NULL)
		return NULL;
	e->cambiata = cambiata;
	e->dati = dati;
	if (sd_bus_open_system(&e->bus) < 0)
		goto fallito;
	sd_bus_set_method_call_timeout(e->bus, 2000000);
	e->fd = wl_event_loop_add_fd(loop, sd_bus_get_fd(e->bus), WL_EVENT_READABLE, leggibile, e);
	e->timer = wl_event_loop_add_timer(loop, elabora, e);
	if (e->fd == NULL || e->timer == NULL)
		goto fallito;
	// Iscritti PRIMA di chiedere: un cambio che arrivasse fra la domanda e
	// l'iscrizione andrebbe perso, e la batteria resterebbe «al 40 %» per
	// tutto il pomeriggio.
	if (sd_bus_match_signal_async(e->bus, &e->batteria_segnale, UPOWER, BATTERIA,
			PROPRIETA, "PropertiesChanged", cambiate, NULL, e) < 0
		|| sd_bus_match_signal_async(e->bus, &e->profilo_segnale, PROFILI,
			PROFILI_PATH, PROPRIETA, "PropertiesChanged", cambiate, NULL, e) < 0)
		goto fallito;
	sd_bus_call_method_async(e->bus, &e->batteria_chiesta, UPOWER, BATTERIA,
		PROPRIETA, "GetAll", risposta_letta, e, "s", BATTERIA_IF);
	sd_bus_call_method_async(e->bus, &e->profilo_chiesto, PROFILI, PROFILI_PATH,
		PROPRIETA, "GetAll", risposta_letta, e, "s", PROFILI);
	aggiorna(e);
	return e;
fallito:
	wlr_log(WLR_INFO, "minerva: energia: niente bus di sistema, "
		"il modo risparmio non guarderà la batteria");
	energia_distruggi(e);
	return NULL;
}

bool energia_da_risparmiare(struct energia_stato s, int soglia, const char **motivo) {
	const char *perche = NULL;
	if (s.batteria && s.scarica && s.percento <= soglia)
		perche = "batteria";
	else if (s.profilo_noto && s.profilo_risparmio)
		perche = "profilo";
	if (motivo != NULL)
		*motivo = perche;
	return perche != NULL;
}

struct energia_stato energia_stato(const struct energia *e) {
	struct energia_stato vuoto = {0};
	return e != NULL ? e->stato : vuoto;
}

void energia_distruggi(struct energia *e) {
	if (e == NULL)
		return;
	if (e->fd != NULL)
		wl_event_source_remove(e->fd);
	if (e->timer != NULL)
		wl_event_source_remove(e->timer);
	sd_bus_slot_unref(e->batteria_segnale);
	sd_bus_slot_unref(e->profilo_segnale);
	sd_bus_slot_unref(e->batteria_chiesta);
	sd_bus_slot_unref(e->profilo_chiesto);
	sd_bus_flush_close_unref(e->bus);
	free(e);
}
