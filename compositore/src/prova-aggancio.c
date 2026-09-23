// prova-aggancio.c — Le prove del conto dell'aggancio ai bordi.
//
//     meson test -C build aggancio
//
// Non serve uno schermo, non serve un compositore, non serve wlroots: qui si
// provano dei numeri. È lo stesso motivo per cui esiste `prova-schermi.c`, e la
// stessa ragione per cui vale la pena: **il difetto di questo conto si vede
// come una finestra nel posto sbagliato**, cioè tardi e solo guardando.
#include <stdio.h>
#include <string.h>
#include "aggancio.h"

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

static void verifica_riquadro(const char *nome, struct riquadro a,
                              int x, int y, int w, int h) {
	char detto[160];
	const bool uguale = a.x == x && a.y == y && a.larghezza == w
		&& a.altezza == h;
	if (!uguale)
		snprintf(detto, sizeof(detto),
			"atteso %d,%d %dx%d — avuto %d,%d %dx%d",
			x, y, w, h, a.x, a.y, a.larghezza, a.altezza);
	verifica(nome, uguale, uguale ? NULL : detto);
}

int main(void) {
	printf("── Prove dell'aggancio ai bordi ──────────────────────\n");

	// Uno schermo 1920×1080 con una barra alta 42 in cima: lo spazio utile
	// comincia a y=42 ed è alto 1038. Sono i numeri veri di questa macchina.
	const struct riquadro fisico = {0, 0, 1920, 1080};
	const struct riquadro utile = {0, 42, 1920, 1038};

	// ── Le zone ──────────────────────────────────────────────────────────
	verifica("il centro non aggancia niente",
		aggancio_zona_di(&fisico, 960, 540) == ZONA_NIENTE, NULL);
	verifica("il bordo sinistro dà la metà di sinistra",
		aggancio_zona_di(&fisico, 3, 540) == ZONA_SINISTRA, NULL);
	verifica("il bordo destro dà la metà di destra",
		aggancio_zona_di(&fisico, 1918, 540) == ZONA_DESTRA, NULL);
	verifica("il bordo di sopra ingrandisce",
		aggancio_zona_di(&fisico, 960, 2) == ZONA_CIMA, NULL);

	// ── E gli angoli battono i lati ──────────────────────────────────────
	//
	// La prova che conta di più fra queste: le fasce si sovrappongono
	// nell'angolo, e provando prima i lati il quarto di schermo sarebbe
	// IRRAGGIUNGIBILE — un gesto che non si può fare, senza nessun errore.
	verifica("l'angolo in alto a sinistra dà un quarto, non metà",
		aggancio_zona_di(&fisico, 3, 3) == ZONA_ALTO_SX, NULL);
	verifica("e quello in alto a destra",
		aggancio_zona_di(&fisico, 1918, 3) == ZONA_ALTO_DX, NULL);
	verifica("e quello in basso a sinistra",
		aggancio_zona_di(&fisico, 3, 1078) == ZONA_BASSO_SX, NULL);
	verifica("e quello in basso a destra",
		aggancio_zona_di(&fisico, 1918, 1078) == ZONA_BASSO_DX, NULL);

	// ── Il bordo di sotto, da solo, NON aggancia ─────────────────────────
	//
	// Sotto c'è la dock. Un aggancio che scatta passando di lì vorrebbe dire
	// che avvicinare una finestra al bordo inferiore la spalma, e non c'è modo
	// di dire «no, volevo lasciarla lì».
	verifica("il bordo di sotto, da solo, non aggancia (c'è la dock)",
		aggancio_zona_di(&fisico, 960, 1078) == ZONA_NIENTE, NULL);

	// ── L'angolo si prende anche camminando lungo il bordo ───────────────
	//
	// Prima un angolo era il quadratino di 24×24 dove le due fasce si
	// incrociano: si mirava al quarto di schermo e si otteneva la metà.
	// Su 1920×1080 l'angolo arriva a 135 px in verticale (un ottavo di 1080)
	// e a 200 in orizzontale (un ottavo di 1920, col tetto).
	verifica("scendendo lungo il bordo sinistro, in alto è ancora l'angolo",
		aggancio_zona_di(&fisico, 3, 100) == ZONA_ALTO_SX, NULL);
	verifica("e camminando sul bordo di sopra, a sinistra pure",
		aggancio_zona_di(&fisico, 100, 3) == ZONA_ALTO_SX, NULL);
	verifica("in basso a sinistra lo stesso",
		aggancio_zona_di(&fisico, 3, 1000) == ZONA_BASSO_SX, NULL);
	verifica("e in basso a destra",
		aggancio_zona_di(&fisico, 1917, 1000) == ZONA_BASSO_DX, NULL);

	// ── Ma il lato resta un lato ─────────────────────────────────────────
	//
	// Se l'angolo si mangiasse il bordo, «metà schermo» diventerebbe
	// irraggiungibile: è il difetto opposto, e non è meglio.
	verifica("a metà del bordo sinistro è la metà, non il quarto",
		aggancio_zona_di(&fisico, 3, 540) == ZONA_SINISTRA, NULL);
	verifica("e in mezzo al bordo di sopra si ingrandisce",
		aggancio_zona_di(&fisico, 960, 3) == ZONA_CIMA, NULL);

	// ── La fascia è larga 24, e si misura dal bordo ──────────────────────
	verifica("a 24 pixel dal bordo aggancia ancora",
		aggancio_zona_di(&fisico, 24, 540) == ZONA_SINISTRA, NULL);
	verifica("a 25 no",
		aggancio_zona_di(&fisico, 25, 540) == ZONA_NIENTE, NULL);

	// ── Uno schermo che non comincia a zero ──────────────────────────────
	//
	// Il secondo monitor. Qui la prima versione di questo conto, dall'altra
	// parte, sbagliava: misurava sulla superficie INTERA invece che sullo
	// schermo, e il bordo destro esisteva solo sul monitor più a destra.
	const struct riquadro secondo = {1920, 0, 1280, 720};
	verifica("sul secondo monitor il bordo sinistro è il SUO bordo",
		aggancio_zona_di(&secondo, 1923, 300) == ZONA_SINISTRA, NULL);
	verifica("e a 1918 (che è il primo monitor) non aggancia il secondo",
		aggancio_zona_di(&secondo, 1890, 300) == ZONA_NIENTE, NULL);

	// ── I rettangoli, ed è qui che si finisce sotto la barra ─────────────
	struct riquadro r;
	aggancio_riquadro(ZONA_SINISTRA, &utile, &r);
	verifica_riquadro("metà sinistra: parte dallo spazio UTILE, non da y=0",
		r, 0, 42, 960, 1038);

	aggancio_riquadro(ZONA_DESTRA, &utile, &r);
	verifica_riquadro("metà destra", r, 960, 42, 960, 1038);

	aggancio_riquadro(ZONA_CIMA, &utile, &r);
	verifica_riquadro("in cima: tutto lo spazio utile", r, 0, 42, 1920, 1038);

	aggancio_riquadro(ZONA_ALTO_SX, &utile, &r);
	verifica_riquadro("quarto in alto a sinistra", r, 0, 42, 960, 519);

	aggancio_riquadro(ZONA_BASSO_DX, &utile, &r);
	verifica_riquadro("quarto in basso a destra", r, 960, 561, 960, 519);

	// ── Le misure dispari non lasciano righe di sfondo ───────────────────
	//
	// Con 1921 di larghezza, due metà arrotondate uguali fanno 1920: resta una
	// riga di sfondo in mezzo, larga un pixel, che si vede su uno sfondo
	// chiaro e non si capisce da dove venga.
	const struct riquadro dispari = {0, 0, 1921, 1081};
	struct riquadro a, b;
	aggancio_riquadro(ZONA_SINISTRA, &dispari, &a);
	aggancio_riquadro(ZONA_DESTRA, &dispari, &b);
	verifica("due metà di una larghezza dispari coprono tutto",
		a.larghezza + b.larghezza == dispari.larghezza, NULL);
	verifica("e si toccano senza sovrapporsi",
		a.x + a.larghezza == b.x, NULL);

	aggancio_riquadro(ZONA_ALTO_SX, &dispari, &a);
	aggancio_riquadro(ZONA_BASSO_SX, &dispari, &b);
	verifica("e così i due quarti in colonna",
		a.altezza + b.altezza == dispari.altezza && a.y + a.altezza == b.y,
		NULL);

	// ── I rifiuti ────────────────────────────────────────────────────────
	aggancio_riquadro(ZONA_NIENTE, &utile, &r);
	verifica_riquadro("«nessuna zona» dà un rettangolo vuoto", r, 0, 0, 0, 0);
	verifica("uno schermo di larghezza zero non aggancia",
		aggancio_zona_di(&(struct riquadro){0, 0, 0, 0}, 0, 0) == ZONA_NIENTE,
		NULL);
	verifica("e nemmeno uno schermo che non c'è",
		aggancio_zona_di(NULL, 10, 10) == ZONA_NIENTE, NULL);

	printf("──\n");
	if (fallite == 0)
		printf("TUTTE PASSATE (%d)\n", passate);
	else
		printf("FALLITE %d su %d\n", fallite, passate + fallite);
	return fallite == 0 ? 0 : 1;
}
