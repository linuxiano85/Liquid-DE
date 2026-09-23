// prova-lente.c — Le prove del ritaglio della lente.
//
//     meson test -C build lente
//
// ── Perché queste prove ESISTONO ─────────────────────────────────────────
//
// Perché la lente è l'unica cosa del compositore che **non si può
// fotografare**. Agisce sullo scanout, e `grim` cattura la scena: due catture
// con lente spenta e accesa sono risultate identiche al pixel, il 31 agosto
// 2026. Per le barre del titolo fantasma la fotografia è stata la sola strada;
// qui quella strada non c'è, e restano i numeri.
//
// E i numeri avevano già un difetto dentro, trovato rileggendo: il ritaglio si
// applicava a ogni schermo intorno allo **stesso** puntatore.
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "lente.h"

static int passate = 0;
static int fallite = 0;

static void verifica(const char *nome, bool condizione, const char *dettaglio) {
	if (condizione) {
		passate++;
		printf("  ok   %s\n", nome);
	} else {
		fallite++;
		printf("  NO   %s%s%s\n", nome, dettaglio ? "  → " : "",
			dettaglio ? dettaglio : "");
	}
}

static void verifica_box(const char *nome, struct lente_box a,
                         double x, double y, double w, double h) {
	char detto[200];
	const bool uguale = fabs(a.x - x) < 0.01 && fabs(a.y - y) < 0.01
		&& fabs(a.larghezza - w) < 0.01 && fabs(a.altezza - h) < 0.01;
	if (!uguale)
		snprintf(detto, sizeof(detto),
			"atteso %.2f,%.2f %.2fx%.2f — avuto %.2f,%.2f %.2fx%.2f",
			x, y, w, h, a.x, a.y, a.larghezza, a.altezza);
	verifica(nome, uguale, uguale ? NULL : detto);
}

int main(void) {
	printf("── Prove del ritaglio della lente ────────────────────\n");

	struct lente_box r;

	// Uno schermo solo, 1920×1080 all'origine. I numeri di questa macchina.
	const int W = 1920, H = 1080;

	// ── Spenta ───────────────────────────────────────────────────────────
	verifica("a scala 1 non si ritaglia niente",
		!lente_ritaglio(1.0, 0, 0, W, H, W, H, 960, 540, &r), NULL);
	verifica("e nemmeno sotto 1",
		!lente_ritaglio(0.5, 0, 0, W, H, W, H, 960, 540, &r), NULL);

	// ── Accesa, puntatore al centro ──────────────────────────────────────
	verifica("a scala 2 si ritaglia",
		lente_ritaglio(2.0, 0, 0, W, H, W, H, 960, 540, &r), NULL);
	verifica_box("e col puntatore al centro il ritaglio è centrato",
		r, 480, 270, 960, 540);

	// ── La trattenuta ai bordi ───────────────────────────────────────────
	//
	// Senza, avvicinando il puntatore a un angolo si vedrebbe una fascia di
	// niente: il ritaglio uscirebbe dal buffer.
	lente_ritaglio(2.0, 0, 0, W, H, W, H, 0, 0, &r);
	verifica_box("nell'angolo in alto a sinistra si ferma a zero",
		r, 0, 0, 960, 540);
	lente_ritaglio(2.0, 0, 0, W, H, W, H, 1919, 1079, &r);
	verifica_box("e in basso a destra si ferma al bordo",
		r, 960, 540, 960, 540);

	// ── DUE SCHERMI, ed è il difetto vero ────────────────────────────────
	//
	// Il secondo schermo sta a x=1920. Col puntatore a 300,400 — che è sul
	// PRIMO — il secondo non deve ritagliare niente. Prima ritagliava, e la
	// trattenuta qui sopra gli incollava il ritaglio a un angolo: restava
	// ingrandito e fermo su un pezzo che nessuno aveva chiesto.
	verifica("il puntatore su un altro schermo NON ritaglia questo",
		!lente_ritaglio(2.0, 1920, 0, W, H, W, H, 300, 400, &r), NULL);
	verifica("e sul suo, invece, sì",
		lente_ritaglio(2.0, 1920, 0, W, H, W, H, 2880, 540, &r), NULL);
	verifica_box("col puntatore portato in coordinate di casa sua",
		r, 480, 270, 960, 540);

	// Il confine è di chi sta a sinistra: x=1920 esatto è del secondo.
	verifica("il bordo sinistro appartiene allo schermo che comincia lì",
		lente_ritaglio(2.0, 1920, 0, W, H, W, H, 1920, 540, &r), NULL);
	verifica("e non a quello che finisce lì",
		!lente_ritaglio(2.0, 0, 0, W, H, W, H, 1920, 540, &r), NULL);

	// ── Un buffer che non è grande come lo schermo ───────────────────────
	//
	// Succede con una rotazione (le due misure si scambiano) e con una scala.
	// Il puntatore va portato in coordinate del BUFFER, non solo spostato.
	lente_ritaglio(2.0, 0, 0, 960, 540, 1920, 1080, 480, 270, &r);
	verifica_box("un buffer del doppio dello schermo scala anche il puntatore",
		r, 480, 270, 960, 540);

	// ── I rifiuti ────────────────────────────────────────────────────────
	verifica("misure impossibili non ritagliano",
		!lente_ritaglio(2.0, 0, 0, W, H, 0, 0, 10, 10, &r), NULL);
	verifica("uno schermo di larghezza zero nemmeno",
		!lente_ritaglio(2.0, 0, 0, 0, 0, W, H, 10, 10, &r), NULL);
	verifica("e senza un posto dove scrivere si dice di no",
		!lente_ritaglio(2.0, 0, 0, W, H, W, H, 10, 10, NULL), NULL);

	printf("──\n");
	if (fallite == 0)
		printf("TUTTE PASSATE (%d)\n", passate);
	else
		printf("FALLITE %d su %d\n", fallite, passate + fallite);
	return fallite == 0 ? 0 : 1;
}
