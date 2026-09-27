// mercurio.c — Le finestre vicine che si fondono. Vedi mercurio.h.
#include "mercurio.h"

#include <math.h>
#include <stddef.h>

float mercurio_distanza(const struct mercurio_forma *f, float x, float y) {
	const float mw = f->r.larghezza * 0.5f, mh = f->r.altezza * 0.5f;
	float raggio = (float)f->raggio;
	if (raggio > mw)
		raggio = mw;
	if (raggio > mh)
		raggio = mh;
	if (raggio < 0)
		raggio = 0;
	const float qx = fabsf(x - (f->r.x + mw)) - (mw - raggio);
	const float qy = fabsf(y - (f->r.y + mh)) - (mh - raggio);
	const float fx = qx > 0 ? qx : 0, fy = qy > 0 ? qy : 0;
	const float dentro = qx > qy ? qx : qy;
	return sqrtf(fx * fx + fy * fy) + (dentro < 0 ? dentro : 0) - raggio;
}

// Lo smooth-min quadratico: uguale a min(a, b) quando le due distanze
// differiscono di più di k, e sotto di al più k/4 quando sono uguali. È il
// «di al più k/4» che fa il collo fra due bordi paralleli.
float mercurio_smin(float a, float b, float k) {
	float h = k - fabsf(a - b);
	if (h < 0)
		h = 0;
	h /= k;
	return (a < b ? a : b) - h * h * k * 0.25f;
}

// ── L'unione, coppia per coppia ───────────────────────────────────────────
//
// La prima versione incatenava lo smooth-min su tutte le forme,
// smin(smin(a, b), c): non è associativo, e una forma lontana (62 pixel, più
// di k) si faceva sentire attraverso una vicina, spostando il bordo di un
// pixel secondo l'ordine dell'elenco. Il minimo fra gli smooth-min di ogni
// COPPIA non dipende dall'ordine, e una coppia lontana dà il minimo esatto:
// il ponte che conosce solo le forme vicine dà esattamente lo stesso
// risultato dello schermo intero (`prova-mercurio.c`, l'ultima prova).
bool mercurio_coperto(const struct mercurio_forma *forme, int quante, int k,
		float x, float y) {
	if (quante <= 0 || quante > MERCURIO_MAX)
		return false;
	float d[MERCURIO_MAX];
	float minima = 1e30f, unione = 1e30f;
	for (int i = 0; i < quante; i++) {
		d[i] = mercurio_distanza(&forme[i], x, y);
		if (d[i] < minima)
			minima = d[i];
	}
	unione = minima;
	for (int i = 0; i < quante; i++)
		for (int j = i + 1; j < quante; j++) {
			const float u = mercurio_smin(d[i], d[j], (float)k);
			if (u < unione)
				unione = u;
		}
	return unione < 0 && minima > 0;
}

// ── Riquadri ──────────────────────────────────────────────────────────────

static struct riquadro allarga(struct riquadro r, int di) {
	return (struct riquadro){r.x - di, r.y - di, r.larghezza + 2 * di,
		r.altezza + 2 * di};
}

static bool vuoto(struct riquadro r) {
	return r.larghezza <= 0 || r.altezza <= 0;
}

static struct riquadro incrocio(struct riquadro a, struct riquadro b) {
	const int x1 = a.x > b.x ? a.x : b.x, y1 = a.y > b.y ? a.y : b.y;
	const int ax2 = a.x + a.larghezza, bx2 = b.x + b.larghezza;
	const int ay2 = a.y + a.altezza, by2 = b.y + b.altezza;
	const int x2 = ax2 < bx2 ? ax2 : bx2, y2 = ay2 < by2 ? ay2 : by2;
	return (struct riquadro){x1, y1, x2 - x1, y2 - y1};
}

static struct riquadro contenitore(struct riquadro a, struct riquadro b) {
	if (vuoto(a))
		return b;
	if (vuoto(b))
		return a;
	const int x1 = a.x < b.x ? a.x : b.x, y1 = a.y < b.y ? a.y : b.y;
	const int ax2 = a.x + a.larghezza, bx2 = b.x + b.larghezza;
	const int ay2 = a.y + a.altezza, by2 = b.y + b.altezza;
	const int x2 = ax2 > bx2 ? ax2 : bx2, y2 = ay2 > by2 ? ay2 : by2;
	return (struct riquadro){x1, y1, x2 - x1, y2 - y1};
}

static bool si_toccano(struct riquadro a, struct riquadro b) {
	return !vuoto(incrocio(a, b));
}

// La distanza fra i due rettangoli (zero se si sovrappongono): un limite da
// sotto di quella fra le forme arrotondate, quindi non perde nessun ponte.
static float scarto(struct riquadro a, struct riquadro b) {
	int dx = b.x - (a.x + a.larghezza);
	const int dx2 = a.x - (b.x + b.larghezza);
	if (dx2 > dx)
		dx = dx2;
	int dy = b.y - (a.y + a.altezza);
	const int dy2 = a.y - (b.y + b.altezza);
	if (dy2 > dy)
		dy = dy2;
	if (dx < 0)
		dx = 0;
	if (dy < 0)
		dy = 0;
	return sqrtf((float)(dx * dx + dy * dy));
}

static bool aggiungi(struct mercurio_ponte *p, int forma) {
	for (int i = 0; i < p->quante; i++)
		if (p->forme[i] == forma)
			return true;
	if (p->quante >= MERCURIO_MAX)
		return false;
	p->forme[p->quante++] = forma;
	return true;
}

int mercurio_ponti(const struct mercurio_forma *forme, int quante, int k,
		struct mercurio_ponte *ponti, int max) {
	if (forme == NULL || ponti == NULL || k <= 0)
		return 0;
	// L'unione esce dalla forma i solo dove i è a meno di k/4 e l'altra a
	// meno di k/4 + k (vedi mercurio_smin): il riquadro del ponte è quello,
	// più due pixel per l'ammorbidimento del bordo.
	const int vicino = (k + 3) / 4 + 2, lontano = (5 * k + 3) / 4 + 2;
	int n = 0;
	bool tagliato = false;
	for (int i = 0; i < quante; i++) {
		for (int j = i + 1; j < quante; j++) {
			if (scarto(forme[i].r, forme[j].r) >= (float)k)
				continue;
			const struct riquadro dove = contenitore(
				incrocio(allarga(forme[i].r, vicino), allarga(forme[j].r, lontano)),
				incrocio(allarga(forme[j].r, vicino), allarga(forme[i].r, lontano)));
			if (vuoto(dove))
				continue;
			if (n >= max) {
				tagliato = true;
				continue;
			}
			ponti[n] = (struct mercurio_ponte){.dove = dove};
			aggiungi(&ponti[n], i);
			aggiungi(&ponti[n], j);
			n++;
		}
	}

	// I riquadri che si toccano diventano uno: un pixel riceve il materiale
	// una volta sola.
	bool fuso = true;
	while (fuso) {
		fuso = false;
		for (int a = 0; a < n && !fuso; a++) {
			for (int b = a + 1; b < n && !fuso; b++) {
				if (!si_toccano(ponti[a].dove, ponti[b].dove))
					continue;
				ponti[a].dove = contenitore(ponti[a].dove, ponti[b].dove);
				for (int i = 0; i < ponti[b].quante; i++)
					tagliato |= !aggiungi(&ponti[a], ponti[b].forme[i]);
				ponti[b] = ponti[--n];
				fuso = true;
			}
		}
	}

	// Dentro il riquadro contano anche le forme che ci passano sopra senza
	// fare ponte: il materiale non va disegnato sotto di loro.
	for (int p = 0; p < n; p++)
		for (int i = 0; i < quante; i++)
			if (si_toccano(ponti[p].dove, forme[i].r))
				tagliato |= !aggiungi(&ponti[p], i);

	return tagliato ? -1 : n;
}
