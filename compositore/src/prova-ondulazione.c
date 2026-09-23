#include "ondulazione.h"
#include "molla.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
	for (int forza = 1; forza <= 300; forza++) {
		struct molla s = {0}; molla_accendi(&s, 0, 0);
		for (int i = 0; i < 2000; i++) {
			molla_passo(&s, 300, -200, i % 5 ? 0.008 : 0.12, forza / 100.0);
			assert(isfinite(s.x) && isfinite(s.y) && isfinite(s.vx) && isfinite(s.vy));
		}
		assert(!s.viva && s.x == 300 && s.y == -200);
	}
	struct molla guasta = {.x = NAN, .viva = true};
	assert(!molla_passo(&guasta, 100, 200, .016, 1));
	assert(guasta.x == 100 && guasta.y == 200);
	for (int misura = 1; misura <= 8; misura++) for (int sx = -1; sx <= 1; sx += 2)
	for (int sy = -1; sy <= 1; sy += 2) {
		struct ondulazione o = {60 * misura, 40 * misura, 25, 10, sx * 100, sy * 100};
		ondulazione_limita(&o);
		double a, b;
		ondulazione_punto(&o, o.presa_x, o.presa_y, &a, &b);
		assert(a == o.presa_x && b == o.presa_y);
		for (int x = -10; x <= o.larghezza + 10; x += 5)
		for (int y = -10; y <= o.altezza + 10; y += 5) {
			double u, v;
			ondulazione_punto(&o, x, y, &a, &b);
			ondulazione_inversa(&o, a, b, &u, &v);
			assert(fabs(u - x) < .001 && fabs(v - y) < .001);
		}
	}
	puts("ok: 300 elasticità finite e convergenti, recupero NaN, presa e mappa inversa");
	return 0;
}
