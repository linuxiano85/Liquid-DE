// prova-molla.c — L'elastico, provato sui numeri.
//
// ── Perché a numeri e non a fotografia ────────────────────────────────────
//
// Perché una fotografia è un istante e questo è un comportamento nel tempo.
// I due modi in cui un elastico si rompe — «la finestra scatta e basta» e
// «la finestra ondeggia per sempre» — danno esattamente la stessa fotografia
// di uno che funziona, se la si scatta nel momento giusto.
//
// E c'è il caso che fa danno vero: con un passo troppo lungo rispetto alla
// rigidezza, l'integrazione di Eulero **guadagna** energia invece di
// perderla. La finestra non ondeggia: parte per la tangente e sparisce dallo
// schermo. È un difetto che si vede una volta su venti, quando la macchina
// è sotto carico e un fotogramma salta — cioè il tipo di difetto che non si
// riproduce mai quando lo cerchi.
#include "molla.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int falliti = 0;

static void bene(const char *cosa, bool ok) {
	printf("%s %s\n", ok ? "ok  " : "NO  ", cosa);
	if (!ok)
		falliti++;
}

/// Fa girare la molla per `ms` millisecondi verso un bersaglio fermo.
static void riposa(struct molla *s, double bx, double by, int ms,
		double forza) {
	for (int t = 0; t < ms; t += MOLLA_PASSO_MS)
		molla_passo(s, bx, by, (double)MOLLA_PASSO_MS / 1000.0, forza);
}

int main(void) {
	// ── Spenta, non fa niente ───────────────────────────────────────────
	{
		struct molla s = {0};
		molla_accendi(&s, 100, 100);
		const bool viva = molla_passo(&s, 400, 400, 0.008, 0.0);
		int dx = 0, dy = 0;
		molla_scarto(&s, 400, 400, &dx, &dy);
		bene("forza 0: si spegne e va in pari",
			!viva && !s.viva && dx == 0 && dy == 0);
	}

	// ── In pari resta in pari ───────────────────────────────────────────
	{
		struct molla s = {0};
		molla_accendi(&s, 300, 200);
		const bool viva = molla_passo(&s, 300, 200, 0.008, 1.0);
		bene("ferma sul bersaglio: si spegne subito", !viva);
	}

	// ── Il ritardo si vede, e non è enorme ──────────────────────────────
	//
	// Si trascina a mille pixel al secondo per mezzo secondo, che è un gesto
	// normale. Il ritardo deve stare fra dieci e ottanta pixel: sotto dieci
	// non si nota, sopra ottanta la finestra sembra staccata dal dito.
	{
		struct molla s = {0};
		double bx = 500, by = 500;
		molla_accendi(&s, bx, by);
		for (int t = 0; t < 500; t += MOLLA_PASSO_MS) {
			bx += 1000.0 * MOLLA_PASSO_MS / 1000.0;
			molla_passo(&s, bx, by, (double)MOLLA_PASSO_MS / 1000.0, 1.0);
		}
		int dx = 0, dy = 0;
		molla_scarto(&s, bx, by, &dx, &dy);
		printf("     (ritardo a 1000 px/s, forza 1: %d px)\n", dx);
		bene("trascinando resta indietro, ma non troppo",
			dx <= -10 && dx >= -80);
		bene("resta indietro, non avanti", dx < 0);
	}

	// ── Più forza, più ritardo ──────────────────────────────────────────
	//
	// La manopola vale il contrario di quel che sembra: più forza vuol dire
	// molla più morbida. Se questa prova si invertisse, il cursore nelle
	// Impostazioni girerebbe al contrario e nessun errore lo direbbe.
	{
		int deboli = 0, forti = 0;
		for (int giro = 0; giro < 2; giro++) {
			struct molla s = {0};
			double bx = 500;
			molla_accendi(&s, bx, 0);
			for (int t = 0; t < 500; t += MOLLA_PASSO_MS) {
				bx += 1000.0 * MOLLA_PASSO_MS / 1000.0;
				molla_passo(&s, bx, 0, (double)MOLLA_PASSO_MS / 1000.0,
					giro == 0 ? 0.5 : 2.0);
			}
			int dx = 0, dy = 0;
			molla_scarto(&s, bx, 0, &dx, &dy);
			if (giro == 0) deboli = -dx; else forti = -dx;
		}
		printf("     (forza 0,5: %d px · forza 2: %d px)\n", deboli, forti);
		bene("più forza vuol dire più ritardo", forti > deboli);
	}

	// ── Lasciando, supera e torna ───────────────────────────────────────
	//
	// È l'effetto. Senza il superamento la finestra «arriva» e basta, e non
	// si vede niente: è la differenza fra smorzamento critico e sotto il
	// critico, cioè fra un movimento e un rimbalzo.
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		s.x = -60;  // sessanta pixel indietro, come dopo un trascinamento
		bool superato = false;
		for (int t = 0; t < 2000 && s.viva; t += MOLLA_PASSO_MS) {
			molla_passo(&s, 0, 0, (double)MOLLA_PASSO_MS / 1000.0, 1.0);
			if (s.x > 0.5)
				superato = true;
		}
		bene("lasciando, supera la posizione", superato);
	}

	// ── E si posa. Sempre, e presto ─────────────────────────────────────
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		s.x = -90;
		s.y = 70;
		int ms = 0;
		while (s.viva && ms < 5000) {
			molla_passo(&s, 0, 0, (double)MOLLA_PASSO_MS / 1000.0, 1.0);
			ms += MOLLA_PASSO_MS;
		}
		printf("     (si posa in %d ms)\n", ms);
		bene("si posa, e non ondeggia per sempre", !s.viva);
		bene("si posa entro un secondo", ms <= 1000);
	}

	// ── Il passo lungo NON manda in orbita ──────────────────────────────
	//
	// Il caso che fa danno: un fotogramma perso, e chi chiama arriva con
	// centoventi millisecondi in una volta. Con Eulero e un passo così, una
	// molla a ventiquattro radianti al secondo raddoppiava l'energia a ogni
	// giro: vista rossa il 10 settembre 2026 con la finestra a 4·10³⁹ pixel
	// dal bersaglio. La forma chiusa non ha questo problema per costruzione,
	// e la prova resta perché è la guardia contro chi la rimettesse.
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		s.x = -60;
		double massimo = 0;
		for (int giro = 0; giro < 40; giro++) {
			molla_passo(&s, 0, 0, 0.120, 1.0);
			if (fabs(s.x) > massimo)
				massimo = fabs(s.x);
		}
		printf("     (con passi da 120 ms, escursione massima %.1f px)\n",
			massimo);
		bene("un passo lungo non fa esplodere la molla", massimo < 100.0);
	}

	// ── E la forza minuscola nemmeno (C01 dell'audit) ───────────────────
	//
	// Forza 0,01 vuol dire ω = 2400 rad/s: con Eulero a otto millisecondi
	// erano quasi venti radianti per passo, e la molla esplodeva. Il verbo
	// `elastico` accetta da 0 in su, quindi il caso è raggiungibile dal
	// canale — non è una curiosità numerica.
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		s.x = -60;
		int ms = 0;
		while (s.viva && ms < 3000) {
			molla_passo(&s, 0, 0, (double)MOLLA_PASSO_MS / 1000.0, 0.01);
			ms += MOLLA_PASSO_MS;
		}
		bene("con forza 0,01 si posa e resta finita",
			!s.viva && isfinite(s.x) && fabs(s.x) < 1.0);
	}

	// ── Il salto si trattiene ───────────────────────────────────────────
	//
	// Una finestra che va da un angolo all'altro — un aggancio, un cambio di
	// scrivania — non deve lasciare il disegno fuori dallo schermo.
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		int dx = 0, dy = 0;
		molla_scarto(&s, 1900, 1000, &dx, &dy);
		// Negativo: il disegno è rimasto INDIETRO rispetto alla finestra,
		// che è saltata avanti. Il segno conta — sbagliarlo vuol dire un
		// disegno che scappa dalla parte opposta.
		bene("uno scarto enorme si trattiene a cento pixel",
			dx == -100 && dy == -100);
	}

	// ── Spegnere rimette in pari ────────────────────────────────────────
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		s.x = -50;
		s.vx = 300;
		molla_spegni(&s, 700, 400);
		int dx = 0, dy = 0;
		molla_scarto(&s, 700, 400, &dx, &dy);
		bene("spegnendo, il disegno torna dov'è la finestra",
			!s.viva && dx == 0 && dy == 0 && s.vx == 0);
	}

	// ── E un bersaglio che si muove non la tiene viva per sempre ────────
	{
		struct molla s = {0};
		molla_accendi(&s, 0, 0);
		riposa(&s, 0, 0, 3000, 3.0);
		bene("anche alla forza massima si posa", !s.viva);
	}

    // Parametri avanzati: nessuna instabilità con refresh irregolare.
    for (int stiffness = 0; stiffness < 2; stiffness++) {
        for (int damping = 0; damping < 2; damping++) {
            struct molla s = {0};
            molla_accendi(&s, -60, 30);
            double elapsed = 0;
            while (s.viva && elapsed < 30) {
                double dt = elapsed < 1 ? 0.007 : 0.037;
                molla_passo_regolato(&s, 0, 0, dt, 3,
                    stiffness ? 2 : 0.5, damping ? 0.95 : 0.15);
                elapsed += dt;
            }
            bene("parametri estremi: si posa e resta finita", !s.viva && isfinite(s.x) && isfinite(s.vx));
        }
    }
    {
        struct molla s = {0};
        molla_accendi(&s, -30, 0);
        molla_passo_regolato(&s, 0, 0, 0.016, 1, NAN, 0.42);
        bene("rigidità non finita: ripristino senza deformazione", !s.viva && s.x == 0);
    }
	if (falliti > 0) {
		printf("\n%d prove fallite\n", falliti);
		return 1;
	}
	printf("\ntutte a posto\n");
	return 0;
}
