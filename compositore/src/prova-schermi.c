// prova-schermi.c — Le prove del lettore di `schermi.conf`.
//
//     ninja -C build && ./build/prova-schermi
//
// ── Perché queste prove esistono ───────────────────────────────────────────
//
// Perché una riga sbagliata in quel file dà uno SCHERMO NERO, e per correggere
// quella riga serve lo schermo. È l'unico pezzo del compositore in cui un
// difetto si porta via il modo di ripararlo.
//
// Il compositore ha già la sua rete — se il commit fallisce riprova nudo, modo
// preferito e scala 1 — ma la rete serve per l'imprevisto, non per l'ovvio. Le
// prove qui sotto sono l'ovvio: che una scala si legga, che una scala assurda
// si ignori, che il nome esatto vinca sul jolly.
//
// Non serve wlroots: questo file legge testo e riempie una struttura. È
// deliberato — la parte che si può provare senza uno schermo è stata tenuta
// separata da quella che non si può.

#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "schermi.h"

static int passate = 0;
static int fallite = 0;

static void verifica(const char *nome, bool condizione, const char *dettaglio) {
	if (condizione) {
		passate++;
		printf("  ok   %s\n", nome);
	} else {
		fallite++;
		printf("  NO   %s%s%s\n", nome,
		       dettaglio != NULL ? "  → " : "",
		       dettaglio != NULL ? dettaglio : "");
	}
}

// Scrive un file temporaneo col contenuto dato e lo legge.
static void con(const char *contenuto, struct schermi_config *fuori) {
	char percorso[] = "/tmp/minerva-prova-schermi-XXXXXX";
	int fd = mkstemp(percorso);
	if (fd < 0) {
		fprintf(stderr, "non riesco a creare un file temporaneo\n");
		exit(2);
	}
	FILE *f = fdopen(fd, "w");
	fputs(contenuto, f);
	fclose(f);
	schermi_leggi(fuori, percorso);
	unlink(percorso);
}

int main(void) {
    struct schermo_voluto parsed = {0};
    verifica("frequenza esatta 59.940", schermo_modo_parse(&parsed, "1920x1080@59.940") && parsed.millihz == 59940, NULL);
    verifica("frequenza intera compatibile", schermo_modo_parse(&parsed, "1920x1080@60") && parsed.hz == 60 && parsed.millihz == 0, NULL);
    verifica("nessun suffisso ignorato", !schermo_modo_parse(&parsed, "1920x1080@60garbage"), NULL);
    verifica("dimensione fuori intervallo", !schermo_modo_parse(&parsed, "9999999999999999999999x1080@60"), NULL);
    verifica("frequenza non finita", !schermo_modo_parse(&parsed, "1920x1080@nan"), NULL);

	struct schermi_config c;
	const struct schermo_voluto *v;
	char msg[128];

	printf("── Prove degli schermi ──\n");

	// ── Il caso di Giacomo ───────────────────────────────────────────────
	//
	// 1920×1080 a 1,25. È la riga che il pannello Impostazioni scrive già
	// oggi, nella sintassi di Hyprland, virgole comprese.
	con("eDP-1 = 1920x1080@60,0x0,1.25\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("legge la riga che scrive il pannello Impostazioni", v != NULL, NULL);
	if (v != NULL) {
		snprintf(msg, sizeof(msg), "%dx%d@%d scala %.2f",
		         v->larghezza, v->altezza, v->hz, v->scala);
		verifica("la risoluzione", v->larghezza == 1920 && v->altezza == 1080, msg);
		verifica("la frequenza", v->hz == 60, msg);
		verifica("LA SCALA", v->scala > 1.24 && v->scala < 1.26, msg);
		verifica("la posizione", v->posizione_detta && v->x == 0 && v->y == 0, msg);
		verifica("ed è acceso", v->acceso, NULL);
	}

	// ── La stessa cosa scritta a spazi ───────────────────────────────────
	con("eDP-1 = 1920x1080@60  0,0  1.25\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("gli spazi valgono quanto le virgole",
	         v != NULL && v->scala > 1.24 && v->larghezza == 1920, NULL);

	// ── Quello che si può non dire ───────────────────────────────────────
	con("eDP-1 = preferito auto 2\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("«preferito» lascia decidere al monitor",
	         v != NULL && v->larghezza == 0 && v->altezza == 0, NULL);
	verifica("«auto» lascia decidere la posizione",
	         v != NULL && !v->posizione_detta, NULL);
	verifica("ma la scala resta quella chiesta",
	         v != NULL && v->scala > 1.99 && v->scala < 2.01, NULL);

	// ── Le righe scritte male non devono spegnere lo schermo ─────────────
	//
	// Una scala a zero darebbe una divisione per zero dentro wlroots; una
	// negativa, uno schermo di larghezza negativa. In tutti e due i casi si
	// preferisce ignorare la parola e tenere 1: uno schermo troppo piccolo si
	// vede e si corregge, uno schermo nero no.
	con("eDP-1 = 1920x1080 0,0 0\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("una scala a zero si ignora", v != NULL && v->scala == 0, NULL);

	con("eDP-1 = 1920x1080 0,0 -3\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("una scala negativa si ignora", v != NULL && v->scala == 0, NULL);

	con("eDP-1 = 1920x1080 0,0 99\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("una scala assurda si ignora", v != NULL && v->scala == 0, NULL);

	// ── I commenti e le righe vuote ──────────────────────────────────────
	con("# tutto commento\n"
	    "\n"
	    "   \n"
	    "eDP-1 = 1920x1080 0,0 1.25   # e questo pure\n", &c);
	verifica("commenti e righe vuote non contano", c.quanti == 1, NULL);
	v = schermi_per(&c, "eDP-1");
	verifica("un commento in fondo non entra nella scala",
	         v != NULL && v->scala > 1.24 && v->scala < 1.26, NULL);

	// ── Il jolly, e chi vince ────────────────────────────────────────────
	//
	// Il nome esatto vince SEMPRE sul jolly, anche se il jolly viene prima nel
	// file. Altrimenti l'ordine delle righe deciderebbe la risposta, e
	// scrivere una riga per il proprio portatile sotto una generica non
	// funzionerebbe — un difetto che si manifesta come «l'ho scritto e non
	// cambia niente».
	con("* = preferito auto 1\n"
	    "eDP-1 = 1920x1080 0,0 1.25\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("il nome esatto vince sul jolly che sta PRIMA",
	         v != NULL && v->scala > 1.24, NULL);
	v = schermi_per(&c, "HDMI-A-1");
	verifica("e uno schermo non nominato prende il jolly",
	         v != NULL && strcmp(v->nome, "*") == 0, NULL);

	// ── Spegnere uno schermo ─────────────────────────────────────────────
	con("HDMI-A-1 = spento\n", &c);
	v = schermi_per(&c, "HDMI-A-1");
	verifica("uno schermo si può spegnere", v != NULL && !v->acceso, NULL);
	v = schermi_per(&c, "eDP-1");
	verifica("e non spegne gli altri", v == NULL, NULL);

	// ── La rotazione ─────────────────────────────────────────────────────
	con("eDP-1 = 1920x1080 0,0 1 90\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("la rotazione si legge", v != NULL && v->rotazione == 90, NULL);

	con("eDP-1 = 1920x1080 0,0 1 47\n", &c);
	v = schermi_per(&c, "eDP-1");
	verifica("una rotazione che non esiste si ignora",
	         v != NULL && v->rotazione == -1, NULL);

	// ── Un file che non c'è ──────────────────────────────────────────────
	//
	// Non è un errore. Un compositore che si rifiuta di partire perché manca
	// un file di preferenze è un computer che non si accende.
	schermi_leggi(&c, "/non/esisto/schermi.conf");
	verifica("un file che non c'è dà zero voci, non un guasto", c.quanti == 0, NULL);
	verifica("e nessuno schermo risulta configurato",
	         schermi_per(&c, "eDP-1") == NULL, NULL);

	// ── Un file spazzatura ───────────────────────────────────────────────
	con("questo non e' una riga\n"
	    "= senza nome\n"
	    "\x01\x02 binario\n", &c);
	verifica("le righe senza senso si saltano", c.quanti == 0, NULL);

	// ── Più schermi ──────────────────────────────────────────────────────
	con("eDP-1 = 1920x1080 0,0 1.25\n"
	    "HDMI-A-1 = 2560x1440@144 1536,0 1\n", &c);
	verifica("due schermi si leggono tutti e due", c.quanti == 2, NULL);
	v = schermi_per(&c, "HDMI-A-1");
	verifica("il secondo sta dove gli è stato detto",
	         v != NULL && v->posizione_detta && v->x == 1536 && v->y == 0, NULL);
	verifica("e ha la sua frequenza", v != NULL && v->hz == 144, NULL);

	printf("──\n");
	if (fallite == 0)
		printf("TUTTE PASSATE (%d)\n", passate);
	else
		printf("FALLITE %d su %d\n", fallite, passate + fallite);
	return fallite == 0 ? 0 : 1;
}
