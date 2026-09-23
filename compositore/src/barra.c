// `_XOPEN_SOURCE` e non solo `_POSIX_C_SOURCE`: con `-std=c11` stretto la
// glibc nasconde `M_PI`, che è XOPEN e non ISO C. Il compilatore lo dice
// chiaramente («did you mean G_PI?»), ma la tentazione di scriversi il pi
// greco a mano è forte e sbagliata.
#define _XOPEN_SOURCE 700

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <cairo/cairo.h>
#include <drm_fourcc.h>
#include <pango/pangocairo.h>

#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/types/wlr_buffer.h>

#include "barra.h"

// ── Il buffer: un disegno di cairo che la scena sa mostrare ───────────────
//
// `wlr_scene_buffer` vuole un `wlr_buffer`, che è un'interfaccia: chi ne
// fornisce uno dichiara come si leggono i suoi pixel. Qui dentro i pixel sono
// una superficie di cairo in memoria, e questa è tutta la colla che serve.
//
// ── L'ordine dei byte, che è l'unica cosa che si può sbagliare in silenzio ─
//
// cairo `ARGB32` è un intero a 32 bit nell'ordine della macchina, con l'alfa
// nei bit alti e i colori **premoltiplicati**. `DRM_FORMAT_ARGB8888` è la
// stessa cosa detta nel modo di DRM. Su una macchina little-endian coincidono
// byte per byte, e questo è il presupposto: su un processore big-endian i
// colori uscirebbero scambiati senza nessun errore. Non ne abbiamo, e quando
// ne avremo uno se ne accorgerà chi guarda lo schermo — ma almeno sta scritto.

struct barra_buffer {
	struct wlr_buffer base;
	cairo_surface_t *superficie;
};

static void bb_distruggi(struct wlr_buffer *b) {
	struct barra_buffer *bb = wl_container_of(b, bb, base);
	cairo_surface_destroy(bb->superficie);
	free(bb);
}

static bool bb_apri(struct wlr_buffer *b, uint32_t flags, void **dati,
		uint32_t *formato, size_t *passo) {
	(void)flags;
	struct barra_buffer *bb = wl_container_of(b, bb, base);
	*dati = cairo_image_surface_get_data(bb->superficie);
	*formato = DRM_FORMAT_ARGB8888;
	*passo = (size_t)cairo_image_surface_get_stride(bb->superficie);
	return true;
}

static void bb_chiudi(struct wlr_buffer *b) {
	(void)b;
}

static const struct wlr_buffer_impl bb_impl = {
	.destroy = bb_distruggi,
	.begin_data_ptr_access = bb_apri,
	.end_data_ptr_access = bb_chiudi,
};

// ── I colori ──────────────────────────────────────────────────────────────
//
// Gli stessi del plugin, e non per pigrizia: sono quelli della membrana di
// Minerva, e una barra di un colore diverso su un compositore diverso vorrebbe
// dire che la scrivania cambia aspetto a seconda di chi la disegna.
//
//   0x0B0F1A  il fondo scuro della membrana
//   0xEEF4FF  il testo, bianco appena azzurrato
//
// Cambia solo l'ALFA fra a fuoco e non a fuoco: 0.90 contro 0.70. È la stessa
// scelta della shell — una finestra spenta non cambia colore, si allontana.
#define FONDO_R 0.043
#define FONDO_G 0.059
#define FONDO_B 0.102

#define TESTO_R 0.933
#define TESTO_G 0.957
#define TESTO_B 1.000

// ── E quello che il pannello può cambiare ────────────────────────────────
//
// Parte dai valori di fabbrica qui sopra: una scrivania che non ha mai
// toccato niente si vede identica a prima, che è il punto.
static struct barra_aspetto aspetto = {
	.alta = BARRA_ALTA,
	.pulsanti_a_destra = true,
	.fondo_r = FONDO_R, .fondo_g = FONDO_G, .fondo_b = FONDO_B,
	.testo_r = TESTO_R, .testo_g = TESTO_G, .testo_b = TESTO_B,
};

const struct barra_aspetto *barra_aspetto_ora(void) {
	return &aspetto;
}

int barra_alta(void) {
	return aspetto.alta;
}

// I limiti, e sono limiti veri non decorazioni.
//
// Sotto i 20 pixel una barra non si prende col dito — è una maniglia, e una
// maniglia che non si afferra è una finestra che non si sposta. Sopra i 120 si
// mangia lo schermo. Un valore fuori misura NON si accorcia in silenzio: si
// rifiuta, perché uno che scrive 400 ha sbagliato, e correggerlo di nascosto
// gli fa credere che 400 sia andato bene.
#define BARRA_MIN 20
#define BARRA_MAX 120

static bool colore_buono(double r, double g, double b) {
	return r >= 0.0 && r <= 1.0 && g >= 0.0 && g <= 1.0
		&& b >= 0.0 && b <= 1.0;
}

bool barra_aspetto_imposta(const struct barra_aspetto *nuovo) {
	if (nuovo == NULL)
		return false;

	// Si controlla TUTTO prima di scrivere QUALUNQUE cosa: un aspetto
	// applicato a metà — l'altezza nuova e i colori vecchi — è uno stato che
	// nessuno ha chiesto e che nessuno sa descrivere.
	struct barra_aspetto d = aspetto;

	if (nuovo->alta > 0) {
		if (nuovo->alta < BARRA_MIN || nuovo->alta > BARRA_MAX)
			return false;
		d.alta = nuovo->alta;
	}
	if (nuovo->fondo_r >= 0.0) {
		if (!colore_buono(nuovo->fondo_r, nuovo->fondo_g, nuovo->fondo_b))
			return false;
		d.fondo_r = nuovo->fondo_r;
		d.fondo_g = nuovo->fondo_g;
		d.fondo_b = nuovo->fondo_b;
	}
	if (nuovo->testo_r >= 0.0) {
		if (!colore_buono(nuovo->testo_r, nuovo->testo_g, nuovo->testo_b))
			return false;
		d.testo_r = nuovo->testo_r;
		d.testo_g = nuovo->testo_g;
		d.testo_b = nuovo->testo_b;
	}
	d.pulsanti_a_destra = nuovo->pulsanti_a_destra;

	aspetto = d;
	return true;
}

// ── Dove stanno i pulsanti ────────────────────────────────────────────────

void barra_box_pulsante(int indice, int larghezza, struct wlr_box *fuori) {
	*fuori = (struct wlr_box){0};
	if (indice < 0 || indice >= BARRA_PULSANTI || larghezza <= 0)
		return;

	const int lato = aspetto.alta - 10;
	const int passo = lato + 2;
	const int bordo = 6;

	// «Chiudi» all'ESTREMITÀ, da qualunque parte stiano: è l'unica convenzione
	// su cui tutti i sistemi vanno d'accordo, e vale a destra come a sinistra.
	// Quindi a sinistra l'ordine si specchia — chiudi resta il più esterno —
	// invece di traslare in blocco, che metterebbe «riduci» sul bordo e
	// «chiudi» in mezzo agli altri.
	if (aspetto.pulsanti_a_destra) {
		// Il pulsante 0 (riduci) è il più lontano dal bordo: si conta
		// all'indietro dall'ultimo.
		fuori->x = larghezza - bordo - lato
			- passo * (BARRA_PULSANTI - 1 - indice);
	} else {
		fuori->x = bordo + passo * (BARRA_PULSANTI - 1 - indice);
	}
	fuori->y = (aspetto.alta - lato) / 2;
	fuori->width = lato;
	fuori->height = lato;
}

int barra_pulsante_a(double x, double y, int larghezza) {
	for (int i = 0; i < BARRA_PULSANTI; i++) {
		struct wlr_box b;
		barra_box_pulsante(i, larghezza, &b);
		if (b.width <= 0)
			continue;
		if (x >= b.x && x < b.x + b.width && y >= b.y && y < b.y + b.height)
			return i;
	}
	return -1;
}

// ── I segni dentro i pulsanti ─────────────────────────────────────────────
//
// Disegnati da noi e non presi da un tema di icone, per la stessa ragione per
// cui lo fa già la barra della shell: nei temi `window-maximize` è una freccia
// in su e `window-restore` un rombo, e su una barra del titolo non dicono più
// quello che fanno.

static void segno(cairo_t *cr, int quale, bool ingrandita, double x, double y,
		double L) {
	// Tratto sottile e coi capi tondi: su una barra del titolo un segno spesso
	// sembra un errore, e un capo tagliato di netto si vede a occhio nudo
	// anche a tredici pixel.
	const double T = fmax(1.0, L / 12.0);
	const double M = L * 0.28;
	const double A = x + M;
	const double B = x + L - M;
	const double AY = y + M;
	const double BY = y + L - M;

	cairo_set_line_width(cr, T);
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);

	switch (quale) {
	case PULSANTE_RIDUCI:
		// Una lineetta in basso, non al centro: «riduci» vuol dire «vai giù»,
		// e il segno lo dice da sé.
		cairo_move_to(cr, A, y + L * 0.62);
		cairo_line_to(cr, B, y + L * 0.62);
		cairo_stroke(cr);
		break;

	case PULSANTE_INGRANDISCI:
		if (!ingrandita) {
			cairo_rectangle(cr, A, AY, B - A, BY - AY);
			cairo_stroke(cr);
		} else {
			// Due quadrati sfalsati: quello davanti è la finestra che torna
			// piccola, quello dietro il posto da cui è tornata.
			const double S = (B - A) * 0.72;
			cairo_rectangle(cr, A, BY - S, S, S);
			cairo_stroke(cr);
			cairo_move_to(cr, A + (B - A - S), BY - S);
			cairo_line_to(cr, A + (B - A - S), AY);
			cairo_line_to(cr, B, AY);
			cairo_line_to(cr, B, AY + S);
			cairo_line_to(cr, A + S, AY + S);
			cairo_stroke(cr);
		}
		break;

	case PULSANTE_SCHERMO:
		// Due frecce che scappano in diagonale.
		cairo_move_to(cr, A, AY + L * 0.18);
		cairo_line_to(cr, A, AY);
		cairo_line_to(cr, A + L * 0.18, AY);
		cairo_stroke(cr);
		cairo_move_to(cr, B - L * 0.18, BY);
		cairo_line_to(cr, B, BY);
		cairo_line_to(cr, B, BY - L * 0.18);
		cairo_stroke(cr);
		cairo_move_to(cr, A + T, AY + T);
		cairo_line_to(cr, B - T, BY - T);
		cairo_stroke(cr);
		break;

	case PULSANTE_CHIUDI:
		cairo_move_to(cr, A, AY);
		cairo_line_to(cr, B, BY);
		cairo_stroke(cr);
		cairo_move_to(cr, B, AY);
		cairo_line_to(cr, A, BY);
		cairo_stroke(cr);
		break;

	default:
		break;
	}
}

// ── Il rettangolo tondo solo in cima ──────────────────────────────────────
//
// La finestra sotto ha gli angoli quadrati e la barra li ha tondi: se si
// arrotondassero tutti e quattro resterebbe una tacca di scrivania là dove la
// barra e la finestra si toccano. Quindi si arrotondano solo i due di sopra.

static void tondo_in_cima(cairo_t *cr, double l, double h, double r) {
	cairo_new_sub_path(cr);
	cairo_arc(cr, r, r, r, M_PI, 1.5 * M_PI);
	cairo_arc(cr, l - r, r, r, 1.5 * M_PI, 2.0 * M_PI);
	cairo_line_to(cr, l, h);
	cairo_line_to(cr, 0, h);
	cairo_close_path(cr);
}

// ── Il carattere, tenuto da parte ─────────────────────────────────────────
//
// Adwaita Sans è il carattere di Minerva (`theme/Typography.qml`). Cercarlo
// costa una interrogazione a fontconfig, e rifarla a ogni ridisegno — cioè a
// ogni cambio di titolo, e ci sono programmi che lo cambiano a ogni tasto
// premuto — si sente. La descrizione si costruisce una volta.
//
// ── E DEVE essere lo stesso della shell ──────────────────────────────────
//
// Questa riga disegna la barra del titolo di ogni programma esterno; la shell
// disegna tutto il resto. Se le due nominano caratteri diversi, la scrivania
// parla due lingue sulla stessa finestra — il titolo in una faccia e il
// contenuto di Minerva in un'altra — ed è il genere di stonatura che si nota
// senza saper dire cos'è.
//
// Fino al 3 settembre 2026 qui c'era `Rajdhani`, insieme a `theme/
// Typography.qml`. Sono cambiati insieme, e vanno cambiati insieme.
static PangoFontDescription *carattere(void) {
	static PangoFontDescription *tenuto = NULL;
	if (tenuto == NULL) {
		tenuto = pango_font_description_new();
		pango_font_description_set_family(tenuto, "Adwaita Sans, sans-serif");
		// Rajdhani è condensato e a peso normale leggeva grigio: da qui il
		// MEDIUM. Adwaita Sans ha aste piene, quindi il peso normale basta —
		// ed è quello che usa la shell per il testo corrente.
		pango_font_description_set_weight(tenuto, PANGO_WEIGHT_NORMAL);
		pango_font_description_set_absolute_size(tenuto, 15 * PANGO_SCALE);
	}
	return tenuto;
}

void barra_svuota(void) {
	// Non si libera la descrizione tenuta da parte: è una allocazione sola per
	// tutta la vita del programma, e liberarla qui vorrebbe dire ricostruirla
	// se qualcuno chiamasse ancora `barra_disegna`. Sta qui perché il posto in
	// cui pulire esista, non perché ci sia molto da pulire.
	pango_cairo_font_map_set_default(NULL);
}

// ── Il cartello ──────────────────────────────────────────────────────────
//
// Vedi `barra.h` per il perché esiste. Qui c'è solo il disegno: una pillola
// scura con dentro una riga, a capo se serve.
struct wlr_buffer *barra_cartello(const char *testo, int largo_max,
                                  int *fuori_l, int *fuori_h) {
	if (testo == NULL || testo[0] == '\0' || largo_max < 80)
		return NULL;

	const int margine = 22;
	const int massimo = largo_max - margine * 2;

	// ── Si misura prima, e si disegna dopo ───────────────────────────
	//
	// La pillola deve stare addosso al testo: farla di misura fissa
	// vorrebbe dire una frase corta persa in mezzo al nulla, o una lunga
	// tagliata. Pango sa dire quanto occupa prima che si disegni, quindi si
	// fa un giro a vuoto su una superficie di un pixel.
	cairo_surface_t *finta = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
		1, 1);
	cairo_t *misura = cairo_create(finta);
	PangoLayout *l = pango_cairo_create_layout(misura);
	pango_layout_set_font_description(l, carattere());
	pango_layout_set_text(l, testo, -1);
	pango_layout_set_width(l, massimo * PANGO_SCALE);
	pango_layout_set_wrap(l, PANGO_WRAP_WORD_CHAR);
	pango_layout_set_alignment(l, PANGO_ALIGN_CENTER);
	int tw = 0, th = 0;
	pango_layout_get_pixel_size(l, &tw, &th);
	g_object_unref(l);
	cairo_destroy(misura);
	cairo_surface_destroy(finta);

	if (tw <= 0 || th <= 0)
		return NULL;

	const int larghezza = tw + margine * 2;
	const int altezza = th + margine;

	cairo_surface_t *sup = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
		larghezza, altezza);
	if (cairo_surface_status(sup) != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(sup);
		return NULL;
	}
	cairo_t *cr = cairo_create(sup);

	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	// Il fondo è quello della barra del titolo, più coprente: questo si legge
	// sopra qualunque cosa ci sia sotto — spesso niente, cioè il nero.
	tondo_in_cima(cr, larghezza, altezza, BARRA_RAGGIO);
	// `tondo_in_cima` arrotonda solo sopra; qui la pillola è staccata dal
	// bordo, quindi si arrotonda anche sotto rifacendo il tracciato intero.
	cairo_new_path(cr);
	const double r = BARRA_RAGGIO;
	cairo_new_sub_path(cr);
	cairo_arc(cr, larghezza - r, r, r, -G_PI / 2, 0);
	cairo_arc(cr, larghezza - r, altezza - r, r, 0, G_PI / 2);
	cairo_arc(cr, r, altezza - r, r, G_PI / 2, G_PI);
	cairo_arc(cr, r, r, r, G_PI, 3 * G_PI / 2);
	cairo_close_path(cr);
	const struct barra_aspetto *a = barra_aspetto_ora();
	cairo_set_source_rgba(cr, a->fondo_r, a->fondo_g, a->fondo_b, 0.96);
	cairo_fill_preserve(cr);
	cairo_set_source_rgba(cr, 1, 1, 1, 0.14);
	cairo_set_line_width(cr, 1);
	cairo_stroke(cr);

	PangoLayout *t = pango_cairo_create_layout(cr);
	pango_layout_set_font_description(t, carattere());
	pango_layout_set_text(t, testo, -1);
	pango_layout_set_width(t, massimo * PANGO_SCALE);
	pango_layout_set_wrap(t, PANGO_WRAP_WORD_CHAR);
	pango_layout_set_alignment(t, PANGO_ALIGN_CENTER);
	// L'origine è il bordo sinistro: al centro ci pensa Pango. Aggiungere
	// uno scarto a mano sarebbe il centraggio DOPPIO già pagato una volta
	// nelle barre del titolo.
	cairo_move_to(cr, (larghezza - massimo) / 2.0, margine / 2.0);
	cairo_set_source_rgba(cr, a->testo_r, a->testo_g, a->testo_b, 1.0);
	pango_cairo_show_layout(cr, t);
	g_object_unref(t);

	cairo_destroy(cr);
	cairo_surface_flush(sup);

	struct barra_buffer *bb = calloc(1, sizeof(*bb));
	if (bb == NULL) {
		cairo_surface_destroy(sup);
		return NULL;
	}
	bb->superficie = sup;
	wlr_buffer_init(&bb->base, &bb_impl, larghezza, altezza);
	if (fuori_l != NULL)
		*fuori_l = larghezza;
	if (fuori_h != NULL)
		*fuori_h = altezza;
	return &bb->base;
}

struct wlr_buffer *barra_disegna(const struct barra_stato *stato) {
	const int l = stato->larghezza;
	const int h = aspetto.alta;
	if (l <= 0)
		return NULL;

	cairo_surface_t *sup = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, l, h);
	if (cairo_surface_status(sup) != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(sup);
		return NULL;
	}
	cairo_t *cr = cairo_create(sup);

	// Si parte dal vuoto vero, non dal nero: gli angoli tondi devono lasciar
	// vedere quello che c'è dietro, e `CAIRO_OPERATOR_SOURCE` con alfa zero è
	// l'unico modo di azzerare davvero un buffer già allocato.
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	cairo_set_source_rgba(cr, 0, 0, 0, 0);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	// Col corpo unico il fondo è pieno: la trasparenza la mette la scena su
	// tutto l'albero, e metterla anche qui la moltiplicherebbe. Vedi
	// `corpo_unico` in `barra.h`.
	const double alfa_fondo = stato->corpo_unico
		? 1.00 : (stato->fuoco ? 0.90 : 0.70);
	const double alfa_testo = stato->fuoco ? 1.00 : 0.62;

	tondo_in_cima(cr, l, h, BARRA_RAGGIO);
	cairo_set_source_rgba(cr, aspetto.fondo_r, aspetto.fondo_g,
		aspetto.fondo_b, alfa_fondo);
	cairo_fill(cr);

	// ── I pulsanti ───────────────────────────────────────────────────────
	for (int i = 0; i < BARRA_PULSANTI; i++) {
		struct wlr_box b;
		barra_box_pulsante(i, l, &b);
		if (b.width <= 0)
			continue;

		// La pastiglia si accende solo sotto il dito. Disegnarla sempre
		// riempirebbe la barra di quattro quadrati grigi, e il senso di un
		// pulsante è che si accende quando lo si può premere.
		if (i == stato->sotto_il_dito) {
			const double r = b.width / 2.0;
			cairo_new_sub_path(cr);
			cairo_arc(cr, b.x + r, b.y + r, r, 0, 2 * M_PI);
			if (i == PULSANTE_CHIUDI)
				cairo_set_source_rgba(cr, 0.94, 0.27, 0.27, 0.55);
			else
				cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.16);
			cairo_fill(cr);
		}

		cairo_set_source_rgba(cr, aspetto.testo_r, aspetto.testo_g,
			aspetto.testo_b, alfa_testo);
		segno(cr, i, stato->ingrandita, b.x, b.y, b.width);
	}

	// ── Il titolo ────────────────────────────────────────────────────────
	//
	// Sta al centro della barra, e si ferma prima dei pulsanti. Lo spazio
	// disponibile si calcola simmetrico — tanto a sinistra quanto a destra —
	// o un titolo lungo resterebbe centrato rispetto alla barra ma sovrapposto
	// ai pulsanti da un lato solo.
	if (stato->titolo != NULL && stato->titolo[0] != '\0') {
		struct wlr_box primo;
		barra_box_pulsante(0, l, &primo);
		const int margine = l - primo.x + 8;
		const int massimo = l - 2 * margine;

		if (massimo > 40) {
			PangoLayout *testo = pango_cairo_create_layout(cr);
			pango_layout_set_font_description(testo, carattere());
			pango_layout_set_text(testo, stato->titolo, -1);
			// Una riga sola, e i tre puntini se non ci sta: un titolo che va
			// a capo dentro una barra alta 42 pixel esce dalla barra.
			pango_layout_set_single_paragraph_mode(testo, TRUE);
			pango_layout_set_width(testo, massimo * PANGO_SCALE);
			pango_layout_set_ellipsize(testo, PANGO_ELLIPSIZE_END);
			pango_layout_set_alignment(testo, PANGO_ALIGN_CENTER);

			int tw, th;
			pango_layout_get_pixel_size(testo, &tw, &th);
			(void)tw;

			// ── Centrare una volta sola ──────────────────────────────
			//
			// Qui c'era `margine + (massimo - tw) / 2`, e il titolo usciva
			// appiccicato ai pulsanti invece che al centro. Non era un errore
			// di conto: era un centraggio DOPPIO.
			//
			// `pango_layout_set_width` + `PANGO_ALIGN_CENTER` centrano già la
			// riga dentro `massimo`. `pango_layout_get_pixel_size` però
			// restituisce la larghezza del TESTO, non quella impostata: lo
			// scarto che si aggiungeva a mano era esattamente quello che Pango
			// aggiungeva per conto suo, e i due si sommavano.
			//
			// L'origine è quindi il bordo sinistro della scatola: al centro ci
			// pensa Pango.
			cairo_move_to(cr, margine, (h - th) / 2.0);
			cairo_set_source_rgba(cr, aspetto.testo_r, aspetto.testo_g,
			aspetto.testo_b, alfa_testo);
			pango_cairo_show_layout(cr, testo);
			g_object_unref(testo);
		}
	}

	cairo_destroy(cr);
	cairo_surface_flush(sup);

	struct barra_buffer *bb = calloc(1, sizeof(*bb));
	if (bb == NULL) {
		cairo_surface_destroy(sup);
		return NULL;
	}
	bb->superficie = sup;
	wlr_buffer_init(&bb->base, &bb_impl, l, h);
	return &bb->base;
}
