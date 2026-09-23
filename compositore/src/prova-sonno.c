#define _POSIX_C_SOURCE 200809L
#include "sonno.h"
#include <systemd/sd-bus.h>
#include <wayland-server-core.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>

static int blocchi, inibizioni;
static void blocca(void *data) { (void)data; blocchi++; }
static int inhibit(sd_bus_message *m, void *data, sd_bus_error *error) {
	(void)data; (void)error;
	const char *what, *who, *why, *mode;
	assert(sd_bus_message_read(m, "ssss", &what, &who, &why, &mode) > 0);
	assert(strcmp(what, "sleep") == 0 && strcmp(mode, "delay") == 0);
	int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
	assert(fd >= 0);
	int r = sd_bus_reply_method_return(m, "h", fd);
	close(fd); inibizioni++;
	return r;
}
static const sd_bus_vtable metodi[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("Inhibit", "ssss", "h", inhibit, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_SIGNAL("PrepareForSleep", "b", 0),
	SD_BUS_VTABLE_END
};

static void pompa(sd_bus *server, struct wl_event_loop *loop) {
	for (int i = 0; i < 100; i++) {
		while (sd_bus_process(server, NULL) > 0) {}
		assert(wl_event_loop_dispatch(loop, 0) >= 0);
		struct timespec t = {.tv_nsec = 2000000}; nanosleep(&t, NULL);
	}
}

int main(void) {
	// Rifiuta categoricamente il bus di sistema reale.
	const char *system = getenv("DBUS_SYSTEM_BUS_ADDRESS");
	const char *session = getenv("DBUS_SESSION_BUS_ADDRESS");
	if (!system || !session || strcmp(system, session) || !strstr(system, "/tmp/")) {
		fprintf(stderr, "serve un dbus-run-session privato con indirizzi coincidenti in /tmp\n");
		return 2;
	}
	sd_bus *server = NULL;
	assert(sd_bus_open_system(&server) >= 0);
	assert(sd_bus_request_name(server, "org.freedesktop.login1", 0) >= 0);
	assert(sd_bus_add_object_vtable(server, NULL, "/org/freedesktop/login1",
		"org.freedesktop.login1.Manager", metodi, NULL) >= 0);
	struct wl_event_loop *loop = wl_event_loop_create();
	assert(loop);
	struct sonno *guard = sonno_crea(loop, blocca, NULL);
	assert(guard);
	pompa(server, loop);
	assert(sonno_pronto(guard) && inibizioni == 1 && blocchi == 0);
	assert(sd_bus_emit_signal(server, "/org/freedesktop/login1",
		"org.freedesktop.login1.Manager", "PrepareForSleep", "b", 1) >= 0);
	pompa(server, loop);
	assert(blocchi == 1 && sonno_pronto(guard));
	sonno_protetto(guard);
	assert(!sonno_pronto(guard));
	assert(sd_bus_emit_signal(server, "/org/freedesktop/login1",
		"org.freedesktop.login1.Manager", "PrepareForSleep", "b", 0) >= 0);
	pompa(server, loop);
	assert(sonno_pronto(guard) && inibizioni == 2);
	sonno_distruggi(guard);
	wl_event_loop_destroy(loop);
	sd_bus_flush_close_unref(server);
	puts("ok: inibitore acquisito, protezione prima del rilascio, riacquisizione al risveglio (logind simulato)");
	return 0;
}
