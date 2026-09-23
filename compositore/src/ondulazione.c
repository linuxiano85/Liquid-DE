#include "ondulazione.h"
#include <math.h>

void ondulazione_limita(struct ondulazione *o) {
	o->larghezza = fmax(1.0, o->larghezza);
	o->altezza = fmax(1.0, o->altezza);
	// Mantiene la mappa invertibile anche sulle finestre piccole: nessuna
	// piega può rovesciare la superficie o spostare i clic in modo ambiguo.
	double limite = fmin(100.0, 0.12 * fmin(o->larghezza, o->altezza));
	o->dx = isfinite(o->dx) ? fmax(-limite, fmin(limite, o->dx)) : 0;
	o->dy = isfinite(o->dy) ? fmax(-limite, fmin(limite, o->dy)) : 0;
}

void ondulazione_punto(const struct ondulazione *o, double x, double y,
		double *ox, double *oy) {
	double u = (x - o->presa_x) / o->larghezza;
	double v = (y - o->presa_y) / o->altezza;
	double r = u * u + v * v;
	double peso = r / (0.18 + r);
	*ox = x + o->dx * peso;
	*oy = y + o->dy * peso;
}

void ondulazione_inversa(const struct ondulazione *o, double x, double y,
		double *ox, double *oy) {
	double a = x, b = y;
	for (int i = 0; i < 24; i++) {
		double ax, by;
		ondulazione_punto(o, a, b, &ax, &by);
		a += x - ax;
		b += y - by;
	}
	*ox = a;
	*oy = b;
}
