#include <stddef.h>

#include "lente.h"

bool lente_ritaglio(double scala,
                    int sx, int sy, int slarga, int salta,
                    int blarga, int balta,
                    double px, double py,
                    struct lente_box *fuori) {
	if (fuori == NULL)
		return false;
	if (!(scala > 1.0))
		return false;
	if (blarga <= 0 || balta <= 0 || slarga <= 0 || salta <= 0)
		return false;

	// ── Il puntatore deve essere di QUESTO schermo ───────────────────────
	//
	// È la riga che mancava. Il chiamante gira su tutti gli schermi e il
	// puntatore ne ha uno solo: senza, gli altri ritagliavano intorno a un
	// punto che nei loro confini non c'è, e la trattenuta più sotto li
	// incollava a un angolo. Ingranditi, e fermi.
	if (px < sx || py < sy || px >= sx + slarga || py >= sy + salta)
		return false;

	const double w = (double)blarga / scala;
	const double h = (double)balta / scala;

	// Le coordinate del puntatore portate dentro casa, e poi in coordinate
	// del BUFFER: con una scala o una rotazione le due misure non coincidono.
	const double qx = (px - sx) * ((double)blarga / (double)slarga);
	const double qy = (py - sy) * ((double)balta / (double)salta);

	double x = qx - w / 2.0;
	double y = qy - h / 2.0;

	// Trattenuta dentro i bordi: senza, avvicinando il puntatore a un angolo
	// si vedrebbe una fascia di niente.
	if (x < 0) x = 0;
	if (y < 0) y = 0;
	if (x + w > blarga) x = blarga - w;
	if (y + h > balta) y = balta - h;

	fuori->x = x;
	fuori->y = y;
	fuori->larghezza = w;
	fuori->altezza = h;
	return true;
}
