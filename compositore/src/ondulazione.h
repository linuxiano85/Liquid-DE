#ifndef MINERVA_ONDULAZIONE_H
#define MINERVA_ONDULAZIONE_H

// Deformazione continua in coordinate logiche. Il punto preso dal mouse
// resta fermo; le parti lontane seguono l'oscillatore con più ritardo.
struct ondulazione {
	double larghezza, altezza, presa_x, presa_y, dx, dy;
};
void ondulazione_limita(struct ondulazione *o);
void ondulazione_punto(const struct ondulazione *o, double x, double y,
	double *ox, double *oy);
void ondulazione_inversa(const struct ondulazione *o, double x, double y,
	double *ox, double *oy);
#endif
