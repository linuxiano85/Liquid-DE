// molla.c — L'elastico delle finestre. Il perché sta tutto in `molla.h`.
#include "molla.h"

#include <math.h>

/// Quanto scarto si tollera, in pixel. Vedi `molla_scarto`.
#define MOLLA_SCARTO_MAX 100.0

/// Quanto è rigida la molla a forza 1, in radianti al secondo.
///
/// Ventiquattro, cioè quasi quattro oscillazioni al secondo. Il ritardo che
/// se ne ricava trascinando è `2·ζ/ω` per la velocità del dito: a mille pixel
/// al secondo sono trentacinque pixel, che si vedono senza sembrare un
/// difetto. A forza 2 la molla si dimezza e il ritardo raddoppia.
#define MOLLA_OMEGA 24.0

/// Il rapporto di smorzamento. Sotto uno, cioè sotto il critico: è la riga
/// che fa il rimbalzo. A 0,42 la finestra supera la posizione di circa un
/// quarto dello scarto e torna indietro una volta sola — due rimbalzi sono
/// un giocattolo, zero è un movimento che non si nota.
#define MOLLA_ZETA 0.42

void molla_accendi(struct molla *s, double x, double y) {
	s->x = x;
	s->y = y;
	s->vx = 0;
	s->vy = 0;
	s->viva = true;
}

void molla_spegni(struct molla *s, double x, double y) {
	s->x = x;
	s->y = y;
	s->vx = 0;
	s->vy = 0;
	s->viva = false;
}

bool molla_passo(struct molla *s, double x, double y, double dt, double forza) {
 return molla_passo_regolato(s, x, y, dt, forza, 1.0, MOLLA_ZETA);
}

bool molla_passo_regolato(struct molla *s, double bersaglio_x, double bersaglio_y,
        double dt, double forza, double rigidita, double smorzamento) {
	if (!s->viva)
		return false;
	if (!isfinite(rigidita) || rigidita < 0.5 || rigidita > 2 ||
            !isfinite(smorzamento) || smorzamento < 0.15 || smorzamento > 0.95 ||
            !isfinite(forza) || !isfinite(dt) || !isfinite(s->x)
			|| !isfinite(s->y) || !isfinite(s->vx) || !isfinite(s->vy)
			|| forza <= 0.0 || dt <= 0.0 || dt > 60.0) {
		molla_spegni(s, bersaglio_x, bersaglio_y);
		return false;
	}
	if (forza > 3.0)
		forza = 3.0;

	// ── La soluzione in forma chiusa, non l'integrazione ─────────────────
	//
	// Per l'oscillatore x'' + 2ζω x' + ω² x = 0, con a = ζω e b = ω√(1−ζ²):
	//
	//     x(t) = e^(−at) [ x₀ cos(bt) + (v₀ + a x₀)/b · sin(bt) ]
	//     v(t) = e^(−at) [ v₀ cos(bt) − (a v₀ + ω² x₀)/b · sin(bt) ]
	//
	// È esatta per qualunque `dt`: un fotogramma perso non fa guadagnare
	// energia alla molla, e una forza di 0,01 non la manda all'infinito. Era
	// il difetto C01 dell'audit del 12 settembre 2026, e la correzione è di
	// Codex — la versione con Eulero a passi spezzati lo prendeva solo fino
	// a un certo punto.
	const double omega = MOLLA_OMEGA * rigidita / fmax(forza, 0.001);
	const double a = smorzamento * omega;
	const double b = omega * sqrt(1.0 - smorzamento * smorzamento);
	const double e = exp(-a * dt), c = cos(b * dt), sn = sin(b * dt);
	const double x = s->x - bersaglio_x, y = s->y - bersaglio_y;
	const double vx = s->vx, vy = s->vy;
	s->x = bersaglio_x + e * (x * c + (vx + a * x) * sn / b);
	s->y = bersaglio_y + e * (y * c + (vy + a * y) * sn / b);
	s->vx = e * (vx * c - (a * vx + omega * omega * x) * sn / b);
	s->vy = e * (vy * c - (a * vy + omega * omega * y) * sn / b);

	if (molla_ferma(s, bersaglio_x, bersaglio_y)) {
		molla_spegni(s, bersaglio_x, bersaglio_y);
		return false;
	}
	return true;
}

void molla_scarto(const struct molla *s, double bersaglio_x,
		double bersaglio_y, int *dx, int *dy) {
	double sx = s->viva ? s->x - bersaglio_x : 0.0;
	double sy = s->viva ? s->y - bersaglio_y : 0.0;
	if (!isfinite(sx)) sx = 0;
	if (!isfinite(sy)) sy = 0;
	if (sx > MOLLA_SCARTO_MAX)
		sx = MOLLA_SCARTO_MAX;
	else if (sx < -MOLLA_SCARTO_MAX)
		sx = -MOLLA_SCARTO_MAX;
	if (sy > MOLLA_SCARTO_MAX)
		sy = MOLLA_SCARTO_MAX;
	else if (sy < -MOLLA_SCARTO_MAX)
		sy = -MOLLA_SCARTO_MAX;
	*dx = (int)lround(sx);
	*dy = (int)lround(sy);
}

bool molla_ferma(const struct molla *s, double bersaglio_x,
		double bersaglio_y) {
	return fabs(s->x - bersaglio_x) < 0.5
		&& fabs(s->y - bersaglio_y) < 0.5
		&& fabs(s->vx) < 1.0
		&& fabs(s->vy) < 1.0;
}
