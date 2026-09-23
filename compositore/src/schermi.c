// schermi.c — Che schermi vuole Minerva, e come.
//
// ── Perché un file e non il demone (per adesso) ────────────────────────────
//
// La risposta giusta a «quanto è grande lo schermo» ce l'ha il demone, che
// tiene le impostazioni di tutta Minerva. Ma il canale di controllo fra
// compositore e demone è la Tappa 6, e la scala serve PRIMA di tutto il resto:
// senza, entrando in minerva-wayland si trova ogni cosa piccolissima, e
// nessuna prova a schermo dice il vero — misuri una barra alta 42 pixel e ne
// vedi 33.
//
// Quindi si legge un file, come fa ogni compositore all'avvio. Non è lavoro da
// buttare quando arriverà il canale: questa resta la configurazione
// PERSISTENTE, quella che si applica all'accensione prima che ci sia qualcuno
// con cui parlare. Il canale servirà a cambiarla mentre gira.
//
// ── Il formato ─────────────────────────────────────────────────────────────
//
//     # commento
//     eDP-1  = 1920x1080@60  0,0   1.25
//     HDMI-A-1 = preferito   1536,0  1
//     *      = preferito     auto   1
//     eDP-1  = spento
//
// Le parole sono posizionali e tutte facoltative tranne la prima: modo,
// posizione, scala, rotazione. `preferito` e `auto` dicono «quello che
// decideresti tu». Si accetta anche la sintassi di Hyprland — virgole invece
// di spazi, `1920x1080@60,0x0,1.25` — perché è quella che il pannello
// Impostazioni scrive già oggi, e chiedere all'utente di tenere due file
// diversi con gli stessi numeri è il modo migliore per farli divergere.

#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// `strcasecmp` sta qui e non in <string.h>: è POSIX, non ISO C. Senza questa
// riga clang la dichiara implicitamente e il progetto è a `werror=true`.
#include <strings.h>

#include "schermi.h"
#include <math.h>
#include <errno.h>
#include <limits.h>

static void togli_spazi(char *s) {
	char *p = s;
	while (*p != '\0' && isspace((unsigned char)*p))
		p++;
	if (p != s)
		memmove(s, p, strlen(p) + 1);
	size_t n = strlen(s);
	while (n > 0 && isspace((unsigned char)s[n - 1]))
		s[--n] = '\0';
}

// Una parola per volta, saltando spazi E virgole.
//
// Le virgole ci sono perché il pannello Impostazioni di Minerva scrive già la
// riga nella sintassi di Hyprland (`1920x1080@60,0x0,1.25`), e questo file
// deve poterla leggere senza che nessuno la ricopi a mano. Un numero copiato a
// mano in due posti è un numero che prima o poi differisce.
static char *prossima(char **resto) {
	char *p = *resto;
	while (*p != '\0' && (isspace((unsigned char)*p) || *p == ','))
		p++;
	if (*p == '\0') {
		*resto = p;
		return NULL;
	}
	char *inizio = p;
	while (*p != '\0' && !isspace((unsigned char)*p) && *p != ',')
		p++;
	if (*p != '\0')
		*p++ = '\0';
	*resto = p;
	return inizio;
}

static bool e_uguale(const char *a, const char *b) {
	return strcasecmp(a, b) == 0;
}

// `1920x1080@60`, `1920x1080`, `preferito`, `preferred`, `auto`.
static void leggi_modo(struct schermo_voluto *v, const char *parola) {
	if (e_uguale(parola, "preferito") || e_uguale(parola, "preferred") ||
	    e_uguale(parola, "auto")) {
		return;
	}
	schermo_modo_parse(v, parola);
}

// `0,0` non arriva mai intero: `prossima()` taglia anche sulle virgole,
// quindi la posizione può presentarsi come `0x0` (Hyprland) o come due parole
// separate. Si accettano tutte e due, e `auto` vuol dire «mettilo dove vuoi».
static void leggi_posizione(struct schermo_voluto *v, const char *parola,
                            char **resto) {
	if (e_uguale(parola, "auto"))
		return;
	int x = 0, y = 0;
	if (sscanf(parola, "%dx%d", &x, &y) == 2) {
		v->x = x;
		v->y = y;
		v->posizione_detta = true;
		return;
	}
	// Una sola cifra: la seconda è la parola dopo (era separata da una
	// virgola, che abbiamo appena mangiato).
	if (sscanf(parola, "%d", &x) == 1) {
		char *seconda = prossima(resto);
		if (seconda != NULL && sscanf(seconda, "%d", &y) == 1) {
			v->x = x;
			v->y = y;
			v->posizione_detta = true;
		}
	}
}

static void leggi_riga(struct schermi_config *c, char *riga) {
	char *cancelletto = strchr(riga, '#');
	if (cancelletto != NULL)
		*cancelletto = '\0';
	togli_spazi(riga);
	if (riga[0] == '\0')
		return;

	char *uguale = strchr(riga, '=');
	if (uguale == NULL)
		return;
	*uguale = '\0';
	char *nome = riga;
	char *valore = uguale + 1;
	togli_spazi(nome);
	togli_spazi(valore);
	if (nome[0] == '\0')
		return;

	if (c->quanti >= MINERVA_SCHERMI_MAX)
		return;

	struct schermo_voluto *v = &c->voci[c->quanti];
	memset(v, 0, sizeof(*v));
	snprintf(v->nome, sizeof(v->nome), "%s", nome);
	v->rotazione = -1;
	v->acceso = true;

	char *resto = valore;
	char *parola = prossima(&resto);
	if (parola == NULL) {
		c->quanti++;
		return;
	}

	// Uno schermo spento si dice in una parola, ed è tutta la riga.
	if (e_uguale(parola, "spento") || e_uguale(parola, "off") ||
	    e_uguale(parola, "disable")) {
		v->acceso = false;
		c->quanti++;
		return;
	}

	leggi_modo(v, parola);

	parola = prossima(&resto);
	if (parola != NULL)
		leggi_posizione(v, parola, &resto);

	parola = prossima(&resto);
	if (parola != NULL) {
		double s = atof(parola);
		// Una scala a zero o negativa non è una scala: è un file scritto male,
		// e applicarla darebbe uno schermo di larghezza infinita. Si ignora.
		if (s > 0.1 && s < 10.0)
			v->scala = s;
	}

	parola = prossima(&resto);
	if (parola != NULL) {
		int r = atoi(parola);
		if (r == 0 || r == 90 || r == 180 || r == 270)
			v->rotazione = r;
	}

	c->quanti++;
}

static void percorso_di_serie(char *fuori, size_t n) {
	const char *conf = getenv("MINERVA_CONFIG_DIR");
	if (conf != NULL && conf[0] != '\0') {
		snprintf(fuori, n, "%s/schermi.conf", conf);
		return;
	}
	const char *xdg = getenv("XDG_CONFIG_HOME");
	if (xdg != NULL && xdg[0] != '\0') {
		snprintf(fuori, n, "%s/minerva/schermi.conf", xdg);
		return;
	}
	const char *casa = getenv("HOME");
	snprintf(fuori, n, "%s/.config/minerva/schermi.conf",
	         casa != NULL ? casa : "");
}

void schermi_leggi(struct schermi_config *fuori, const char *percorso) {
	memset(fuori, 0, sizeof(*fuori));

	char scelto[512];
	if (percorso == NULL) {
		percorso_di_serie(scelto, sizeof(scelto));
		percorso = scelto;
	}

	FILE *f = fopen(percorso, "r");
	if (f == NULL)
		return;   // non c'è: ogni schermo prende il suo modo preferito

	char riga[512];
	while (fgets(riga, sizeof(riga), f) != NULL)
		leggi_riga(fuori, riga);
	fclose(f);
}

const struct schermo_voluto *schermi_per(const struct schermi_config *c,
                                         const char *nome) {
	const struct schermo_voluto *jolly = NULL;
	for (int i = 0; i < c->quanti; i++) {
		if (strcmp(c->voci[i].nome, "*") == 0) {
			if (jolly == NULL)
				jolly = &c->voci[i];
			continue;
		}
		if (nome != NULL && strcmp(c->voci[i].nome, nome) == 0)
			return &c->voci[i];
	}
	return jolly;
}

// Usato sia dal file sia dal canale: niente troncamento di 59.94 a 59.
bool schermo_modo_parse(struct schermo_voluto *v, const char *text) {
    char *next;
    errno = 0;
    long w = strtol(text, &next, 10);
    if (errno || next == text || *next != 'x' || w <= 0 || w > INT_MAX) return false;
    const char *height = next + 1;
    long h = strtol(height, &next, 10);
    if (errno || next == height || h <= 0 || h > INT_MAX) return false;
    const char *tail = next;
    double hz = 0;
    int exact = 0;
    if (*tail) {
        if (*tail++ != '@' || !*tail) return false;
        char *end;
        hz = strtod(tail, &end);
        if (end == tail || *end || !isfinite(hz) || hz <= 0 || hz > 1000) return false;
        if (strchr(tail, '.')) exact = (int)(hz * 1000 + 0.5);
    }
    v->larghezza = w; v->altezza = h;
    v->hz = (int)(hz + 0.5); v->millihz = exact;
    return true;
}
