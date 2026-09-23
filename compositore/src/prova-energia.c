// prova-energia — La batteria e il profilo, con UPower e power-profiles-daemon
// FINTI su un bus privato: la prova non deve poter guardare (né disturbare)
// quelli veri. Si lancia come `prova-sonno`, dentro `dbus-run-session`.
//
// Si prova quello che conta per il modo risparmio:
//   · lo stato di partenza arriva da solo, senza che nessuno lo chieda due volte;
//   · un cambio annunciato arriva, e arriva UNA volta;
//   · un annuncio di cose che non contano (l'energia in wattora) non sveglia
//     il compositore;
//   · la regola dell'«auto»: soglia, scarica, profilo.
#define _POSIX_C_SOURCE 200809L
#include "energia.h"
#include <systemd/sd-bus.h>
#include <wayland-server-core.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>

struct batteria_finta {
	double percentuale, energia;
	uint32_t stato, tipo;
	int presente;
};
static struct batteria_finta batteria = { 87.0, 40.0, 2, 2, 1 };
static const char *profilo = "balanced";

static int leggi_profilo(sd_bus *bus, const char *path, const char *iface,
		const char *prop, sd_bus_message *risposta, void *dati, sd_bus_error *err) {
	(void)bus; (void)path; (void)iface; (void)prop; (void)dati; (void)err;
	return sd_bus_message_append(risposta, "s", profilo);
}

static const sd_bus_vtable batteria_vt[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_PROPERTY("Percentage", "d", NULL, offsetof(struct batteria_finta, percentuale),
		SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_PROPERTY("Energy", "d", NULL, offsetof(struct batteria_finta, energia),
		SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_PROPERTY("State", "u", NULL, offsetof(struct batteria_finta, stato),
		SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_PROPERTY("Type", "u", NULL, offsetof(struct batteria_finta, tipo), 0),
	SD_BUS_PROPERTY("IsPresent", "b", NULL, offsetof(struct batteria_finta, presente), 0),
	SD_BUS_VTABLE_END
};

static const sd_bus_vtable profili_vt[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_PROPERTY("ActiveProfile", "s", leggi_profilo, 0,
		SD_BUS_VTABLE_PROPERTY_EMITS_CHANGE),
	SD_BUS_VTABLE_END
};

static int avvisi;
static void cambiata(void *dati) { (void)dati; avvisi++; }

static void pompa(sd_bus *server, struct wl_event_loop *loop) {
	for (int i = 0; i < 60; i++) {
		while (sd_bus_process(server, NULL) > 0) {}
		assert(wl_event_loop_dispatch(loop, 0) >= 0);
		struct timespec t = {.tv_nsec = 2000000};
		nanosleep(&t, NULL);
	}
}

static void annuncia(sd_bus *server, const char *path, const char *iface, const char *prop) {
	assert(sd_bus_emit_properties_changed(server, path, iface, prop, NULL) >= 0);
}

int main(void) {
	const char *system = getenv("DBUS_SYSTEM_BUS_ADDRESS");
	const char *session = getenv("DBUS_SESSION_BUS_ADDRESS");
	if (!system || !session || strcmp(system, session) || !strstr(system, "/tmp/")) {
		fprintf(stderr, "serve un dbus-run-session privato con indirizzi coincidenti in /tmp\n");
		return 2;
	}

	// ── La regola, da sola ───────────────────────────────────────────────
	const char *perche = NULL;
	struct energia_stato s = { .batteria = true, .scarica = true, .percento = 21 };
	assert(!energia_da_risparmiare(s, 20, &perche) && perche == NULL);
	s.percento = 20;
	assert(energia_da_risparmiare(s, 20, &perche) && strcmp(perche, "batteria") == 0);
	s.scarica = false;   // attaccato: al 20 % ma si ricarica
	assert(!energia_da_risparmiare(s, 20, &perche));
	s.batteria = false; s.scarica = true; s.percento = 0;   // un fisso: UPower dice 0
	assert(!energia_da_risparmiare(s, 20, &perche));
	s.profilo_noto = true; s.profilo_risparmio = true;
	assert(energia_da_risparmiare(s, 20, &perche) && strcmp(perche, "profilo") == 0);

	// ── Il bus finto ─────────────────────────────────────────────────────
	sd_bus *upower = NULL, *profili = NULL;
	assert(sd_bus_open_system(&upower) >= 0);
	assert(sd_bus_request_name(upower, "org.freedesktop.UPower", 0) >= 0);
	assert(sd_bus_add_object_vtable(upower, NULL, "/org/freedesktop/UPower/devices/DisplayDevice",
		"org.freedesktop.UPower.Device", batteria_vt, &batteria) >= 0);
	assert(sd_bus_open_system(&profili) >= 0);
	assert(sd_bus_request_name(profili, "org.freedesktop.UPower.PowerProfiles", 0) >= 0);
	assert(sd_bus_add_object_vtable(profili, NULL, "/org/freedesktop/UPower/PowerProfiles",
		"org.freedesktop.UPower.PowerProfiles", profili_vt, NULL) >= 0);

	struct wl_event_loop *loop = wl_event_loop_create();
	assert(loop);
	struct energia *e = energia_crea(loop, cambiata, NULL);
	assert(e);
	for (int i = 0; i < 2; i++) { pompa(upower, loop); pompa(profili, loop); }

	s = energia_stato(e);
	assert(s.batteria && s.scarica && (int)s.percento == 87);
	assert(s.profilo_noto && !s.profilo_risparmio);
	assert(avvisi >= 1 && avvisi <= 2);

	// Scende: un avviso, e il numero nuovo.
	int prima = avvisi;
	batteria.percentuale = 15.0;
	annuncia(upower, "/org/freedesktop/UPower/devices/DisplayDevice",
		"org.freedesktop.UPower.Device", "Percentage");
	pompa(upower, loop);
	s = energia_stato(e);
	assert((int)s.percento == 15 && avvisi == prima + 1);
	assert(energia_da_risparmiare(s, 20, &perche) && strcmp(perche, "batteria") == 0);

	// L'energia in wattora cambia di continuo e qui non conta: nessun avviso.
	prima = avvisi;
	batteria.energia = 39.5;
	annuncia(upower, "/org/freedesktop/UPower/devices/DisplayDevice",
		"org.freedesktop.UPower.Device", "Energy");
	pompa(upower, loop);
	assert(avvisi == prima);

	// Si attacca la corrente: non si scarica più, e non si risparmia più.
	batteria.stato = 1;
	annuncia(upower, "/org/freedesktop/UPower/devices/DisplayDevice",
		"org.freedesktop.UPower.Device", "State");
	pompa(upower, loop);
	s = energia_stato(e);
	assert(!s.scarica && !energia_da_risparmiare(s, 20, NULL));

	// Il profilo «risparmio energetico», anche attaccati.
	prima = avvisi;
	profilo = "power-saver";
	annuncia(profili, "/org/freedesktop/UPower/PowerProfiles",
		"org.freedesktop.UPower.PowerProfiles", "ActiveProfile");
	pompa(profili, loop);
	s = energia_stato(e);
	assert(s.profilo_risparmio && avvisi == prima + 1);
	assert(energia_da_risparmiare(s, 20, &perche) && strcmp(perche, "profilo") == 0);

	energia_distruggi(e);
	wl_event_loop_destroy(loop);
	sd_bus_flush_close_unref(upower);
	sd_bus_flush_close_unref(profili);
	puts("ok: batteria e profilo letti all'avvio, cambi annunciati una volta, "
		"l'energia in wattora non sveglia, la regola dell'auto (UPower simulato)");
	return 0;
}
