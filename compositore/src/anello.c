// anello.c — Il bordo colorato attorno alla finestra, disegnato con cairo.
//
// ── Perché non bastavano dei rettangoli ───────────────────────────────────
//
// La prima versione della striscia LED era fatta di ventotto rettangoli della
// scena: quattro gomiti agli angoli e sei segmenti per lato, ognuno di un
// colore. Funzionava, costava zero, e Giacomo l'ha guardata e ha detto:
//
//     «non è venuto bene come rgb, si vedono delle linee intorno e non è un
//      rgb simile alla strip led. cosa sono quelle linee?»
//
// Quelle linee erano le giunzioni. Un rettangolo ha UN colore, quindi
// ventiquattro rettangoli sono ventiquattro gradini — e fra un gradino e
// l'altro il salto di tinta si vede, perché l'occhio sui bordi netti è
// bravissimo. Una striscia LED vera non ha gradini: ha uno sfumato.
//
// Uno sfumato lo sa fare cairo, e non lo sa fare `wlr_scene_rect`. Quindi il
// bordo diventa un'IMMAGINE, come la barra del titolo — che è disegnata così
// da sempre, in `barra.c`, con la stessa macchina.
//
// ── E perché in quattro pezzi ─────────────────────────────────────────────
//
// Perché un anello intero è un'immagine grande quanto la finestra e quasi
// tutta trasparente. Per una finestra di 1000×676 sono 2,7 MB per fotogramma,
// dodici volte al secondo, per dipingere una banda di sei pixel: trentatré
// megabyte al secondo di roba da cancellare e da caricare sulla scheda video,
// su un portatile, per sempre.
//
// Tagliato in quattro, la stessa banda sta in centosessanta kilobyte — il
// duecentesimo. I due pezzi orizzontali sono alti quanto il bordo più
// l'angolo, così gli angoli tondi restano dentro di loro e non vanno cuciti.
//
// ── Il conto del perimetro ────────────────────────────────────────────────
//
// Ogni punto del bordo ha una posizione lungo il giro, da 0 a 1, e da quella
// esce il suo colore. Il giro parte dall'angolo in alto a sinistra e va nel
// verso dell'orologio. Gli archi degli angoli contano per quello che sono —
// un quarto di circonferenza — o su una finestra con gli angoli grandi i
// colori scorrerebbero più in fretta sugli angoli che sui lati.
// `_XOPEN_SOURCE` e non solo `_POSIX_C_SOURCE`: con `-std=c11` stretto la
// glibc nasconde `M_PI`, che è XOPEN e non ISO C. Stessa riga in cima a
// `barra.c`, e per la stessa ragione.
#define _XOPEN_SOURCE 700

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <cairo/cairo.h>
#include <drm_fourcc.h>

#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/types/wlr_buffer.h>

#include "anello.h"

// ── Il buffer, identico a quello della barra ──────────────────────────────
//
// `wlr_scene_buffer` vuole un `wlr_buffer`, che è un'interfaccia: chi ne
// fornisce uno dice come si apre e come si chiude. Qui dentro c'è una
// superficie cairo, e basta.
//
// È una copia di `struct barra_buffer` in `barra.c`, e la copia è
// deliberata: quel file disegna testo con pango e questo disegna sfumati:
// unirli vorrebbe dire un file che fa due mestieri per risparmiare venti
// righe di infrastruttura.
struct anello_buffer {
	struct wlr_buffer base;
	cairo_surface_t *superficie;
};

static void ab_distruggi(struct wlr_buffer *b) {
	struct anello_buffer *ab = wl_container_of(b, ab, base);
	cairo_surface_destroy(ab->superficie);
	free(ab);
}

static bool ab_apri(struct wlr_buffer *b, uint32_t flags, void **dati,
		uint32_t *formato, size_t *passo) {
	(void)flags;
	struct anello_buffer *ab = wl_container_of(b, ab, base);
	*dati = cairo_image_surface_get_data(ab->superficie);
	*formato = DRM_FORMAT_ARGB8888;
	*passo = (size_t)cairo_image_surface_get_stride(ab->superficie);
	return true;
}

static void ab_chiudi(struct wlr_buffer *b) {
	(void)b;
}

static const struct wlr_buffer_impl ab_impl = {
	.destroy = ab_distruggi,
	.begin_data_ptr_access = ab_apri,
	.end_data_ptr_access = ab_chiudi,
};

// ── I colori ──────────────────────────────────────────────────────────────

/// Da una tinta (0…1 attorno alla ruota) a rosso, verde e blu, a saturazione e
/// luminosità piene.
static void tinta_a_rgb(double h, float *r, float *g, float *b) {
	h = h - floor(h);
	const double sei = h * 6.0;
	const int settore = (int)sei;
	const double f = sei - settore;
	const double q = 1.0 - f;
	switch (settore % 6) {
	case 0: *r = 1.0f; *g = (float)f; *b = 0.0f; break;
	case 1: *r = (float)q; *g = 1.0f; *b = 0.0f; break;
	case 2: *r = 0.0f; *g = 1.0f; *b = (float)f; break;
	case 3: *r = 0.0f; *g = (float)q; *b = 1.0f; break;
	case 4: *r = (float)f; *g = 0.0f; *b = 1.0f; break;
	default: *r = 1.0f; *g = 0.0f; *b = (float)q; break;
	}
}

void anello_colore(const struct anello_stato *s, double dove,
		float *r, float *g, float *b) {
	if (s->quante_tinte <= 0) {
		tinta_a_rgb(dove, r, g, b);
		return;
	}
	if (s->quante_tinte == 1) {
		*r = s->tinte[0][0];
		*g = s->tinte[0][1];
		*b = s->tinte[0][2];
		return;
	}
	dove = dove - floor(dove);
	const double scala = dove * s->quante_tinte;
	int i = (int)scala;
	if (i >= s->quante_tinte)
		i = s->quante_tinte - 1;
	const int j = (i + 1) % s->quante_tinte;
	const double f = scala - floor(scala);
	*r = (float)(s->tinte[i][0] * (1.0 - f) + s->tinte[j][0] * f);
	*g = (float)(s->tinte[i][1] * (1.0 - f) + s->tinte[j][1] * f);
	*b = (float)(s->tinte[i][2] * (1.0 - f) + s->tinte[j][2] * f);
}

// ── La forma ──────────────────────────────────────────────────────────────

/// Un rettangolo con gli angoli tondi, aggiunto al tracciato corrente.
static void rettangolo_tondo(cairo_t *cr, double x, double y,
		double w, double h, double r) {
	if (r <= 0.0) {
		cairo_rectangle(cr, x, y, w, h);
		return;
	}
	const double meta = (w < h ? w : h) / 2.0;
	if (r > meta)
		r = meta;
	cairo_new_sub_path(cr);
	cairo_arc(cr, x + w - r, y + r, r, -M_PI_2, 0.0);
	cairo_arc(cr, x + w - r, y + h - r, r, 0.0, M_PI_2);
	cairo_arc(cr, x + r, y + h - r, r, M_PI_2, M_PI);
	cairo_arc(cr, x + r, y + r, r, M_PI, 1.5 * M_PI);
	cairo_close_path(cr);
}

/// Dove sta il pezzo e quanto è grande, in coordinate della cornice.
static bool pezzo_misura(const struct anello_stato *s, enum anello_pezzo p,
		int *x, int *y, int *l, int *h) {
	const int sp = s->spessore;
	const int rr = s->raggio;
	const int alto = sp + rr;      // quanto è alta la fascia orizzontale
	const int dritto_y = s->altezza - 2 * rr;

	switch (p) {
	case ANELLO_ALTO:
		*x = -sp; *y = -sp;
		*l = s->larghezza + 2 * sp; *h = alto;
		break;
	case ANELLO_BASSO:
		*x = -sp; *y = s->altezza - rr;
		*l = s->larghezza + 2 * sp; *h = alto;
		break;
	case ANELLO_SINISTRA:
		*x = -sp; *y = rr;
		*l = sp; *h = dritto_y;
		break;
	default: // ANELLO_DESTRA
		*x = s->larghezza; *y = rr;
		*l = sp; *h = dritto_y;
		break;
	}
	return *l > 0 && *h > 0;
}

// ── Il giro ───────────────────────────────────────────────────────────────
//
// Le lunghezze in ordine, a partire dall'angolo in alto a sinistra e nel verso
// dell'orologio: arco, lato di sopra, arco, lato di destra, arco, lato di
// sotto, arco, lato di sinistra.
struct giro {
	double arco;
	double dritto_x, dritto_y;
	double tutto;
};

static struct giro giro_di(const struct anello_stato *s) {
	struct giro g;
	g.arco = M_PI_2 * s->raggio;
	g.dritto_x = s->larghezza - 2.0 * s->raggio;
	g.dritto_y = s->altezza - 2.0 * s->raggio;
	if (g.dritto_x < 0.0)
		g.dritto_x = 0.0;
	if (g.dritto_y < 0.0)
		g.dritto_y = 0.0;
	g.tutto = 4.0 * g.arco + 2.0 * g.dritto_x + 2.0 * g.dritto_y;
	if (g.tutto <= 0.0)
		g.tutto = 1.0;
	return g;
}

/// Quanti gradini mette lo sfumato di un pezzo.
///
/// Trentadue. Non è il numero dei rettangoli di prima travestito: là ogni
/// gradino era un colore PIENO con un bordo netto, qui sono i punti di appiglio
/// di uno sfumato che cairo interpola pixel per pixel. Fra due appigli non
/// c'è nessuna linea — c'è la sfumatura.
#define ANELLO_APPIGLI 32

/// Mette gli appigli di colore su uno sfumato lineare, da `da` a `a` lungo il
/// perimetro.
static void appigli(cairo_pattern_t *sf, const struct anello_stato *s,
		double da, double a) {
	for (int i = 0; i <= ANELLO_APPIGLI; i++) {
		const double t = (double)i / ANELLO_APPIGLI;
		float r, g, b;
		anello_colore(s, da + (a - da) * t + s->fase, &r, &g, &b);
		cairo_pattern_add_color_stop_rgba(sf, t, r, g, b, s->alfa);
	}
}

struct wlr_buffer *anello_disegna(const struct anello_stato *s,
		enum anello_pezzo pezzo, int *fuori_l, int *fuori_h,
		int *fuori_x, int *fuori_y) {
	int px, py, pl, ph;
	if (!pezzo_misura(s, pezzo, &px, &py, &pl, &ph))
		return NULL;
	if (s->larghezza <= 0 || s->altezza <= 0 || s->spessore <= 0)
		return NULL;

	cairo_surface_t *sup =
		cairo_image_surface_create(CAIRO_FORMAT_ARGB32, pl, ph);
	if (cairo_surface_status(sup) != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(sup);
		return NULL;
	}
	cairo_t *cr = cairo_create(sup);
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	// Si lavora in coordinate della CORNICE — la finestra comincia a (0,0) —
	// e si sposta l'origine di quanto il pezzo è spostato. Così il tracciato
	// dell'anello si scrive una volta sola, uguale per tutti e quattro i
	// pezzi, e il ritaglio lo fa il bordo dell'immagine.
	cairo_translate(cr, -px, -py);

	// L'anello: il rettangolo di fuori meno quello di dentro, con la regola
	// pari-dispari. Gli angoli di fuori sono più aperti di quelli di dentro
	// esattamente dello spessore, o il bordo si assottiglierebbe sulla curva.
	cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD);
	rettangolo_tondo(cr, -s->spessore, -s->spessore,
		s->larghezza + 2 * s->spessore, s->altezza + 2 * s->spessore,
		s->raggio > 0 ? s->raggio + s->spessore : 0);
	rettangolo_tondo(cr, 0, 0, s->larghezza, s->altezza, s->raggio);

	if (s->fermo) {
		cairo_set_source_rgba(cr, s->fermo_r, s->fermo_g, s->fermo_b,
			s->alfa);
		cairo_fill(cr);
	} else {
		const struct giro g = giro_di(s);
		// ── Da dove a dove va questo pezzo, lungo il perimetro ───────
		//
		// I due pezzi orizzontali contengono gli angoli INTERI: sono alti
		// quanto il bordo più il raggio, e un angolo sta tutto lì dentro.
		// Quelli verticali hanno solo il tratto dritto. Il giro parte
		// dall'angolo in alto a sinistra e va nel verso dell'orologio:
		//
		//     alto      arco + lato di sopra + arco
		//     destra    lato di destra
		//     basso     arco + lato di sotto + arco
		//     sinistra  lato di sinistra
		//
		// Sbagliare questi quattro numeri non dà nessun errore: dà una
		// striscia in cui il colore salta a ogni angolo, che è esattamente il
		// difetto da cui veniamo.
		double da = 0.0, a = 0.0;
		double x0 = 0, y0 = 0, x1 = 0, y1 = 0;
		switch (pezzo) {
		case ANELLO_ALTO:
			da = 0.0;
			a = 2.0 * g.arco + g.dritto_x;
			x0 = -s->spessore; y0 = 0;
			x1 = s->larghezza + s->spessore; y1 = 0;
			break;
		case ANELLO_DESTRA:
			da = 2.0 * g.arco + g.dritto_x;
			a = da + g.dritto_y;
			x0 = 0; y0 = s->raggio;
			x1 = 0; y1 = s->altezza - s->raggio;
			break;
		case ANELLO_BASSO:
			da = 2.0 * g.arco + g.dritto_x + g.dritto_y;
			a = da + 2.0 * g.arco + g.dritto_x;
			// Sotto si va verso SINISTRA: lo sfumato parte da destra.
			x0 = s->larghezza + s->spessore; y0 = 0;
			x1 = -s->spessore; y1 = 0;
			break;
		default: // ANELLO_SINISTRA
			da = 4.0 * g.arco + 2.0 * g.dritto_x + g.dritto_y;
			a = da + g.dritto_y;
			// A sinistra si risale.
			x0 = 0; y0 = s->altezza - s->raggio;
			x1 = 0; y1 = s->raggio;
			break;
		}
		cairo_pattern_t *sf = cairo_pattern_create_linear(x0, y0, x1, y1);
		appigli(sf, s, da / g.tutto, a / g.tutto);
		cairo_set_source(cr, sf);
		cairo_fill(cr);
		cairo_pattern_destroy(sf);
	}

	cairo_destroy(cr);
	cairo_surface_flush(sup);

	struct anello_buffer *ab = calloc(1, sizeof(*ab));
	if (ab == NULL) {
		cairo_surface_destroy(sup);
		return NULL;
	}
	ab->superficie = sup;
	wlr_buffer_init(&ab->base, &ab_impl, pl, ph);
	if (fuori_l != NULL) *fuori_l = pl;
	if (fuori_h != NULL) *fuori_h = ph;
	if (fuori_x != NULL) *fuori_x = px;
	if (fuori_y != NULL) *fuori_y = py;
	return &ab->base;
}
