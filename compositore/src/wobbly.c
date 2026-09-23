// wobbly.c — La finestra che si piega mentre la trascini.
//
// ── Che cosa fa ────────────────────────────────────────────────────────────
//
// Giacomo, 10 settembre 2026: «voglio le finestre tremolanti». Il modello è
// Compiz: mentre trascini, il punto preso resta sotto il dito e il resto
// della finestra resta indietro e si piega; al rilascio rimbalza e si posa.
//
// ── Come, e perché così ────────────────────────────────────────────────────
//
// La scena di wlroots (e SceneFX) disegna RETTANGOLI con una texture: non ha
// una maglia di vertici, e le sue opzioni di disegno hanno solo un
// rettangolo sorgente e uno destinazione. Deformare non si può chiedere: si
// fa da soli.
//
// La strada scelta — di Codex, 12 settembre 2026 — non tocca il passaggio di
// disegno dello schermo. Durante il gesto:
//
//  1. i nodi della finestra (barra, contenuto, anello, maniglia) vengono
//     spostati in un sottoalbero SPENTO, `originali`;
//  2. ogni battito si disegnano in un buffer fuori schermo tutto nostro
//     (`swapchain`), come maglia di 24×24 triangoli passata per
//     `ondulazione_punto()`, con GLES2 dentro un passaggio di disegno di
//     wlroots — che ci dà il contesto e il framebuffer;
//  3. quel buffer va in un nodo normale della scena, il `proxy`, al posto
//     della finestra. La scena resta coerente, il blur e il resto non sanno
//     niente, e se il disegno fallisce si torna ai nodi originali.
//
// Il puntatore passa per `wobbly_nodo()`, che inverte la deformazione: un
// clic sul pulsante piegato arriva al pulsante. E i `frame_done` del monitor
// arrivano alle superfici vive attraverso il proxy, o un video si fermerebbe
// mentre lo trascini.
//
// ── Le tre cose imparate a fotografia, il 13 settembre 2026 ────────────────
//
//  · la barra del titolo non c'era: la scena lascia il buffer delle nostre
//    decorazioni dopo averlo caricato in texture (vedi `elenco()`);
//  · senza blur dietro, una finestra al 69 % si scioglieva nello sfondo: il
//    nodo di sfocatura ora segue il proxy con la maschera di trasparenza;
//  · togliere la maschera con NULL fa cadere SceneFX (vedi `wobbly_distruggi`).
//
// I numeri della fisica stanno in `molla.c`, la forma della piega in
// `ondulazione.c`: tutti e due si provano senza compositore.
#include "wobbly.h"
#include <math.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <drm_fourcc.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <wlr/render/gles2.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/render/allocator.h>
#include <wlr/render/swapchain.h>
#include <wlr/render/wlr_texture.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/util/log.h>

#define PAD 112
#define PEZZI 24
#define NODI_MAX 256

struct riserva {
	struct wl_list link, buffers;
	struct wl_listener distrutto;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_swapchain *contesto;
	struct wlr_buffer *contesto_buffer;
	GLuint programmi[2];
	size_t bytes;
};
struct buffer_fermo {
	struct wl_list link;
	struct wlr_swapchain *chain;
	size_t bytes;
};
static struct wl_list riserve = {&riserve, &riserve};
#define CACHE_BYTES (64u * 1024u * 1024u)

struct disegno {
	struct wlr_scene_node *nodo;
	struct wlr_texture *texture;
	bool propria;
	int x, y, width, height;
};

struct wobbly {
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_scene_tree *cornice, *originali;
	struct wlr_scene_buffer *proxy;
	/// Il blur della finestra, che resta fuori da `originali` e segue il
	/// proxy. E com'era prima, per rimetterlo a posto alla fine.
	struct wlr_scene_rect *sfocatura;
	int sfocatura_w, sfocatura_h, sfocatura_x, sfocatura_y;
	struct wlr_minerva_radii sfocatura_angoli;
	struct wl_listener frame;
	struct wlr_swapchain *swapchain;
	struct ondulazione forma;
	struct riserva *riserva;
	bool mostrata;
};

// Ogni foglia usa la stessa trasformazione in coordinate della finestra:
// niente crepe tra barra, contenuto, sottosuperfici e bordo.
static const char *vertice =
	"attribute vec2 posizione; attribute vec2 uv; attribute vec2 locale;"
	"varying vec2 v_uv; varying vec2 v_locale;"
	"void main(){ v_uv=uv; v_locale=locale;"
	"gl_Position=vec4(posizione,0.0,1.0); }";
static const char *frammento =
	"precision mediump float; varying vec2 v_uv; varying vec2 v_locale;"
	"uniform CAMPIONE immagine; uniform vec4 colore; uniform float texture_on;"
	"uniform vec2 misura; uniform vec4 raggi; uniform vec4 buco;"
	"uniform vec4 raggi_buco;"
	"float bordo(vec2 p,vec2 s,vec4 r){"
	"if(p.x<0.0||p.y<0.0||p.x>s.x||p.y>s.y)return 0.0;"
	"float a=p.x<s.x*0.5?(p.y<s.y*0.5?r.x:r.w):(p.y<s.y*0.5?r.y:r.z);"
	"a=min(a,min(s.x,s.y)*0.5);"
	"vec2 q=min(p,s-p); if(q.x>=a||q.y>=a)return 1.0;"
	"float d=length(vec2(a)-q)-a;"
	"return 1.0-smoothstep(-0.65,0.65,d); }"
	"void main(){ float a=bordo(v_locale,misura,raggi);"
	"if(buco.z>0.0&&buco.w>0.0)"
	"a*=1.0-bordo(v_locale-buco.xy,buco.zw,raggi_buco);"
	"vec4 c=colore; if(texture_on>0.5)c*=texture2D(immagine,v_uv);"
	"gl_FragColor=c*a; }";

static GLuint shader(GLenum tipo, const char *testo, const char *inizio) {
	GLuint s = glCreateShader(tipo);
	const char *parti[] = {inizio, testo};
	glShaderSource(s, 2, parti, NULL);
	glCompileShader(s);
	GLint ok = 0;
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[1024]; glGetShaderInfoLog(s, sizeof(log), NULL, log);
		wlr_log(WLR_ERROR, "wobbly: shader: %s", log);
		glDeleteShader(s); return 0;
	}
	return s;
}

static GLuint programma(bool esterno) {
	GLuint v = shader(GL_VERTEX_SHADER, vertice, "");
	GLuint f = shader(GL_FRAGMENT_SHADER, frammento, esterno
		? "#extension GL_OES_EGL_image_external : require\n#define CAMPIONE samplerExternalOES\n"
		: "#define CAMPIONE sampler2D\n");
	if (!v || !f) { glDeleteShader(v); glDeleteShader(f); return 0; }
	GLuint p = glCreateProgram();
	glAttachShader(p, v); glAttachShader(p, f);
	glBindAttribLocation(p, 0, "posizione");
	glBindAttribLocation(p, 1, "uv");
	glBindAttribLocation(p, 2, "locale");
	glLinkProgram(p);
	glDeleteShader(v); glDeleteShader(f);
	GLint ok = 0; glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok) { glDeleteProgram(p); return 0; }
	return p;
}

static void riserva_distrutta(struct wl_listener *l, void *data) {
	(void)data;
	struct riserva *r = wl_container_of(l, r, distrutto);
	struct wlr_buffer *b = r->contesto_buffer;
	struct wlr_render_pass *p = b ? wlr_renderer_begin_buffer_pass(r->renderer, b, NULL) : NULL;
	if (p) {
		glDeleteProgram(r->programmi[0]); glDeleteProgram(r->programmi[1]);
		wlr_render_pass_submit(p);
	}
	if (b) wlr_buffer_unlock(b);
	struct buffer_fermo *f, *tmp;
	wl_list_for_each_safe(f, tmp, &r->buffers, link) {
		wl_list_remove(&f->link); wlr_swapchain_destroy(f->chain); free(f);
	}
	wlr_swapchain_destroy(r->contesto);
	wl_list_remove(&r->distrutto.link); wl_list_remove(&r->link); free(r);
}

static struct riserva *riserva_per(struct wlr_renderer *renderer, struct wlr_allocator *allocator) {
	struct riserva *r;
	wl_list_for_each(r, &riserve, link) if (r->renderer == renderer && r->allocator == allocator) return r;
	r = calloc(1, sizeof(*r));
	if (!r) return NULL;
	r->renderer = renderer; r->allocator = allocator; wl_list_init(&r->buffers);
	uint64_t mod = DRM_FORMAT_MOD_LINEAR;
	struct wlr_drm_format fmt = {.format = DRM_FORMAT_ARGB8888, .len = 1, .capacity = 1, .modifiers = &mod};
	r->contesto = wlr_swapchain_create(allocator, 2, 2, &fmt);
	struct wlr_buffer *b = r->contesto ? wlr_swapchain_acquire(r->contesto) : NULL;
	struct wlr_render_pass *p = b ? wlr_renderer_begin_buffer_pass(renderer, b, NULL) : NULL;
	if (!p) {
		if (b) wlr_buffer_unlock(b);
		if (r->contesto) wlr_swapchain_destroy(r->contesto);
		free(r); return NULL;
	}
	r->programmi[0] = programma(false); r->programmi[1] = programma(true);
	wlr_render_pass_submit(p); r->contesto_buffer = b;
	r->distrutto.notify = riserva_distrutta;
	wl_signal_add(&renderer->events.destroy, &r->distrutto);
	wl_list_insert(&riserve, &r->link);
	return r;
}

bool wobbly_prepara(struct wlr_renderer *renderer, struct wlr_allocator *allocator) {
	if (!wlr_renderer_is_gles2(renderer)) return false;
	struct riserva *r = riserva_per(renderer, allocator);
	return r && r->programmi[0];
}

static void conserva(struct riserva *r, struct wlr_swapchain *chain) {
	if (!chain) return;
	size_t bytes = (size_t)chain->width * chain->height * 4 * WLR_SWAPCHAIN_CAP;
	if (!r || bytes > CACHE_BYTES) { wlr_swapchain_destroy(chain); return; }
	while (!wl_list_empty(&r->buffers) && (r->bytes + bytes > CACHE_BYTES || wl_list_length(&r->buffers) >= 8)) {
		struct buffer_fermo *f = wl_container_of(r->buffers.prev, f, link);
		r->bytes -= f->bytes; wl_list_remove(&f->link); wlr_swapchain_destroy(f->chain); free(f);
	}
	struct buffer_fermo *f = calloc(1, sizeof(*f));
	if (!f) { wlr_swapchain_destroy(chain); return; }
	f->chain = chain; f->bytes = bytes; r->bytes += bytes;
	wl_list_insert(&r->buffers, &f->link);
}

static struct wlr_swapchain *riprendi(struct riserva *r, int w, int h) {
	struct buffer_fermo *f;
	wl_list_for_each(f, &r->buffers, link) {
		if (f->chain->width != w || f->chain->height != h || !f->chain->allocator) continue;
		struct wlr_swapchain *c = f->chain;
		r->bytes -= f->bytes; wl_list_remove(&f->link); free(f); return c;
	}
	return NULL;
}

static void frame_originali(struct wlr_scene_buffer *b, int x, int y, void *dati) {
	(void)x; (void)y;
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(b);
	if (s) wlr_surface_send_frame_done(s->surface, dati);
}

static void frame(struct wl_listener *l, void *dati) {
	struct wobbly *w = wl_container_of(l, w, frame);
	struct wlr_scene_frame_done_event *e = dati;
	// Il proxy riceve il frame_done dal monitor: lo inoltra alle superfici
	// vive, perché video e animazioni continuino anche durante il gesto.
	w->originali->node.enabled = true;
	wlr_scene_node_for_each_buffer(&w->originali->node, frame_originali,
		&e->when);
	w->originali->node.enabled = false;
}

static void raccogli_originali(struct wobbly *w) {
	struct wlr_scene_node *n, *tmp;
	wl_list_for_each_safe(n, tmp, &w->cornice->children, link) {
		if (n == &w->originali->node || n == &w->proxy->node)
			continue;
		if (w->sfocatura && n == &w->sfocatura->node)
			continue;
		wlr_scene_node_reparent(n, w->originali);
	}
}

static bool accetta_punto(struct wlr_scene_buffer *b, double *sx, double *sy) {
	struct wl_listener *l = wl_signal_get(&b->events.frame_done, frame);
	if (!l) return false;
	struct wobbly *w = wl_container_of(l, w, frame);
	double x, y;
	return wobbly_nodo(w, *sx, *sy, &x, &y) != NULL;
}

struct wobbly *wobbly_crea(struct wlr_scene_tree *cornice,
		struct wlr_renderer *renderer, struct wlr_allocator *allocator,
		struct wlr_scene_rect *sfocatura) {
	if (!wlr_renderer_is_gles2(renderer)) return NULL;
	struct wobbly *w = calloc(1, sizeof(*w));
	if (!w) return NULL;
	w->renderer = renderer; w->allocator = allocator; w->cornice = cornice;
	w->riserva = riserva_per(renderer, allocator);
	if (!w->riserva) { free(w); return NULL; }
	w->sfocatura = sfocatura;
	if (sfocatura) {
		w->sfocatura_w = sfocatura->width;
		w->sfocatura_h = sfocatura->height;
		w->sfocatura_x = sfocatura->node.x;
		w->sfocatura_y = sfocatura->node.y;
		w->sfocatura_angoli = sfocatura->corners;
	}
	w->originali = wlr_scene_tree_create(cornice);
	w->proxy = wlr_scene_buffer_create(cornice, NULL);
	if (!w->originali || !w->proxy) {
		if (w->originali) wlr_scene_node_destroy(&w->originali->node);
		if (w->proxy) wlr_scene_node_destroy(&w->proxy->node);
		free(w); return NULL;
	}
	w->frame.notify = frame;
	wl_signal_add(&w->proxy->events.frame_done, &w->frame);
	w->proxy->point_accepts_input = accetta_punto;
	wlr_scene_node_set_enabled(&w->proxy->node, false);
	raccogli_originali(w);
	return w;
}

static bool elenco(struct wobbly *w, struct wlr_scene_node *n, int x, int y,
		struct disegno *d, int *quanti) {
	if (!n->enabled) return true;
	x += n->x; y += n->y;
	if (n->type == WLR_SCENE_NODE_TREE) {
		struct wlr_scene_tree *t = wl_container_of(n, t, node);
		struct wlr_scene_node *figlio;
		wl_list_for_each(figlio, &t->children, link)
			if (!elenco(w, figlio, x, y, d, quanti)) return false;
		return true;
	}
	// Il blur dello sfondo è sospeso mentre la superficie si deforma.
	// Non si campiona mai lo schermo, né si inglobano finestre sovrapposte.
	if (n->type == WLR_SCENE_NODE_RECT && wlr_scene_rect_from_node(n)->minerva_blur) return true;
	if (n->type != WLR_SCENE_NODE_RECT && n->type != WLR_SCENE_NODE_BUFFER)
		return false;
	if (*quanti == NODI_MAX) return false;
	struct disegno *e = &d[(*quanti)++];
	*e = (struct disegno){.nodo = n, .x = x, .y = y};
	if (n->type == WLR_SCENE_NODE_RECT) {
		struct wlr_scene_rect *r = wl_container_of(n, r, node);
		e->width = r->width; e->height = r->height;
		return true;
	}
	struct wlr_scene_buffer *b = wlr_scene_buffer_from_node(n);
	// Il disegno GL diretto non può scavalcare una fence di acquisizione
	// esplicita: si ripiega sul passaggio di scena nativo, che aspetta e
	// segnala il rilascio come si deve.
	if (b->WLR_PRIVATE.wait_timeline) return false;
	// ── La barra del titolo non ha più il suo buffer, e va bene così ─────
	//
	// Visto in fotografia il 13 settembre 2026: durante il trascinamento la
	// finestra compariva SENZA la barra del titolo. Qui c'era
	// `if (!b->buffer) return true;`, e per la barra era sempre vero.
	//
	// Il perché sta nella scena: per un buffer che non è la superficie di un
	// programma (la nostra barra cairo, i pezzi dell'anello) la scena lo
	// carica in una texture **e poi lascia il buffer** — `own_buffer` va a
	// falso, il buffer viene rilasciato, e al segnale di rilascio
	// `scene_buffer->buffer` diventa NULL. La scena da lì in poi disegna dalla
	// texture, che tiene in un campo dichiarato privato.
	//
	// Quindi: prima la superficie del programma (che la texture ce l'ha
	// sempre), poi la texture che la scena si è già fatta, e solo se manca
	// anche quella si importa il buffer da capo. Il campo è privato — la
	// struttura si chiama `WLR_PRIVATE` perché wlroots non promette di
	// tenerla — ma tutto questo file vive dentro SceneFX a quel livello, e
	// il giorno che cambia si rompe qui e non a schermo.
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(b);
	if (s) e->texture = wlr_surface_get_texture(s->surface);
	if (!e->texture) e->texture = b->WLR_PRIVATE.texture;
	if (!e->texture && b->buffer) {
		e->texture = wlr_texture_from_buffer(w->renderer, b->buffer);
		e->propria = true;
	}
	// Un nodo senza niente da disegnare — l'anello spento, una barra non
	// ancora dipinta — non è un errore: si salta, e il resto si disegna.
	if (!e->texture) { (*quanti)--; return true; }
	e->width = b->dst_width ? b->dst_width : (int)e->texture->width;
	e->height = b->dst_height ? b->dst_height : (int)e->texture->height;
	return true;
}

static void raggi(GLuint p, const char *nome, struct wlr_minerva_radii r) {
	glUniform4f(glGetUniformLocation(p, nome), r.top_left, r.top_right,
		r.bottom_right, r.bottom_left);
}

static void uv_trasforma(enum wl_output_transform t, double *u, double *v) {
	double x = *u, y = *v;
	switch (t % 4) {
	case 1: *u = 1.0 - y; *v = x; break;
	case 2: *u = 1.0 - x; *v = 1.0 - y; break;
	case 3: *u = y; *v = 1.0 - x; break;
	default: *u = x; *v = y; break;
	}
	if (t >= WL_OUTPUT_TRANSFORM_FLIPPED) *u = 1.0 - *u;
}

static bool dipingi(struct wobbly *w, struct disegno *d, int bw, int bh, double scala) {
	if (d->width <= 0 || d->height <= 0) return true;
	struct wlr_gles2_texture_attribs attr = {0};
	if (d->texture) wlr_gles2_texture_get_attribs(d->texture, &attr);
	int esterno = attr.target == GL_TEXTURE_EXTERNAL_OES;
	GLuint p = w->riserva->programmi[esterno];
	if (!p) return false;
	glUseProgram(p);
	glUniform1i(glGetUniformLocation(p, "immagine"), 0);
	glUniform1f(glGetUniformLocation(p, "texture_on"), d->texture ? 1 : 0);
	glUniform2f(glGetUniformLocation(p, "misura"), d->width, d->height);
	glUniform4f(glGetUniformLocation(p, "buco"), 0, 0, 0, 0);
	glUniform4f(glGetUniformLocation(p, "raggi_buco"), 0, 0, 0, 0);
	struct wlr_fbox src = {0};
	enum wl_output_transform trasformazione = WL_OUTPUT_TRANSFORM_NORMAL;
	if (d->texture) {
		struct wlr_scene_buffer *b = wlr_scene_buffer_from_node(d->nodo);
		raggi(p, "raggi", b->corners);
		glUniform4f(glGetUniformLocation(p, "colore"), b->opacity,
			b->opacity, b->opacity, b->opacity);
		glActiveTexture(GL_TEXTURE0); glBindTexture(attr.target, attr.tex);
		glTexParameteri(attr.target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(attr.target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(attr.target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(attr.target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		src = b->src_box;
		if (src.width <= 0 || src.height <= 0)
			src = (struct wlr_fbox){0, 0, d->texture->width, d->texture->height};
		trasformazione = b->transform;
	} else if (d->nodo->type == WLR_SCENE_NODE_RECT) {
		struct wlr_scene_rect *r = wl_container_of(d->nodo, r, node);
		raggi(p, "raggi", r->corners);
		glUniform4fv(glGetUniformLocation(p, "colore"), 1, r->color);
		struct wlr_box b = r->clipped_region.area;
		glUniform4f(glGetUniformLocation(p, "buco"), b.x, b.y, b.width, b.height);
		raggi(p, "raggi_buco", r->clipped_region.corners);
	} else return true;

	// Triangoli continui, non strisce di rettangoli. Al massimo 1152
	// triangoli per foglia; le decorazioni sottili usano meno suddivisioni.
	int nx = d->width < PEZZI ? d->width : PEZZI;
	int ny = d->height < PEZZI ? d->height : PEZZI;
	float vertici[(PEZZI + 1) * 2 * 6];
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	for (int a = 0; a < 3; a++) glEnableVertexAttribArray(a);
	for (int y = 0; y < ny; y++) {
		int count = 0;
		for (int x = 0; x <= nx; x++) for (int k = 0; k < 2; k++) {
			double u = (double)x / nx, v = (double)(y + k) / ny;
			double lx = u * d->width, ly = v * d->height, ox, oy;
			ondulazione_punto(&w->forma, d->x + lx, d->y + ly, &ox, &oy);
			uv_trasforma(trasformazione, &u, &v);
			float *punto = &vertici[count++ * 6];
			punto[0] = 2.0 * (ox + PAD) * scala / bw - 1.0;
			// I buffer di SceneFX hanno origine in alto a sinistra anche
			// quando sono destinazioni GLES: non capovolgere la texture.
			punto[1] = 2.0 * (oy + PAD) * scala / bh - 1.0;
			punto[2] = d->texture ? (src.x + u * src.width) / d->texture->width : 0;
			punto[3] = d->texture ? (src.y + v * src.height) / d->texture->height : 0;
			punto[4] = lx; punto[5] = ly;
		}
		for (int a = 0; a < 3; a++)
			glVertexAttribPointer(a, 2, GL_FLOAT, GL_FALSE, 6 * sizeof(float), vertici + a * 2);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, count);
	}
	for (int a = 0; a < 3; a++) glDisableVertexAttribArray(a);
	return true;
}

bool wobbly_disegna(struct wobbly *w, const struct ondulazione *forma, double scala) {
	w->forma = *forma; ondulazione_limita(&w->forma);
	raccogli_originali(w);
	scala = fmax(1.0, fmin(3.0, scala));
	int bw = ceil((forma->larghezza + 2 * PAD) * scala);
	int bh = ceil((forma->altezza + 2 * PAD) * scala);
	// Tetto alle allocazioni per finestra. Il ripiego è la scena normale.
	if (bw > 8192 || bh > 8192 || (double)bw * bh > 16 * 1024 * 1024) return false;
	if (w->swapchain && (w->swapchain->width != bw || w->swapchain->height != bh)) {
		conserva(w->riserva, w->swapchain); w->swapchain = NULL;
	}
	if (!w->swapchain) w->swapchain = riprendi(w->riserva, bw, bh);
	if (!w->swapchain) {
		uint64_t modificatore = DRM_FORMAT_MOD_LINEAR;
		struct wlr_drm_format fmt = {.format = DRM_FORMAT_ARGB8888,
			.len = 1, .capacity = 1, .modifiers = &modificatore};
		w->swapchain = wlr_swapchain_create(w->allocator, bw, bh, &fmt);
		if (!w->swapchain) return false;
	}
	struct disegno d[NODI_MAX] = {0}; int quanti = 0;
	w->originali->node.enabled = true;
	bool ok = elenco(w, &w->originali->node, 0, 0, d, &quanti);
	w->originali->node.enabled = !w->mostrata;
	struct wlr_buffer *buffer = ok ? wlr_swapchain_acquire(w->swapchain) : NULL;
	struct wlr_render_pass *pass = buffer
		? wlr_renderer_begin_buffer_pass(w->renderer, buffer, NULL) : NULL;
	if (pass) {
		glViewport(0, 0, bw, bh);
		glDisable(GL_SCISSOR_TEST); glDisable(GL_DEPTH_TEST); glDisable(GL_CULL_FACE);
		glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
		glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT);
		glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		for (int i = 0; i < quanti && ok; i++) ok = dipingi(w, &d[i], bw, bh, scala);
		if (glGetError() != GL_NO_ERROR) ok = false;
		glUseProgram(0);
		ok = wlr_render_pass_submit(pass) && ok;
	} else ok = false;
	for (int i = 0; i < quanti; i++)
		if (d[i].propria && d[i].texture) wlr_texture_destroy(d[i].texture);
	if (ok) {
		wlr_scene_buffer_set_buffer(w->proxy, buffer);
		wlr_scene_buffer_set_dest_size(w->proxy,
			forma->larghezza + 2 * PAD, forma->altezza + 2 * PAD);
		wlr_scene_node_set_position(&w->proxy->node, -PAD, -PAD);
		wlr_scene_node_set_enabled(&w->originali->node, false);
		wlr_scene_node_set_enabled(&w->proxy->node, true);
		// Il blur segue il proxy: stessa area, e la FORMA la dà la
		// maschera — dove il proxy non dipinge (il margine, e la parte
		// che la piega ha lasciato scoperta) non si sfoca niente. Gli
		// angoli vanno a zero per la stessa ragione: sono già nel proxy.
		if (w->sfocatura) {
			wlr_scene_node_set_position(&w->sfocatura->node, -PAD, -PAD);
			wlr_scene_rect_set_size(w->sfocatura,
				forma->larghezza + 2 * PAD, forma->altezza + 2 * PAD);
			wlr_minerva_rect_set_corners(w->sfocatura,
				(struct wlr_minerva_radii){0, 0, 0, 0});
			wlr_minerva_blur_set_mask(w->sfocatura,
				w->proxy);
		}
		w->mostrata = true;
	}
	if (buffer) wlr_buffer_unlock(buffer);
	return ok;
}

bool wobbly_e_proxy(struct wobbly *w, struct wlr_scene_node *nodo) {
	return w && nodo == &w->proxy->node;
}

void wobbly_visita(struct wobbly *w, wlr_scene_buffer_iterator_func_t visita, void *dati) {
	raccogli_originali(w);
	bool prima = w->originali->node.enabled;
	w->originali->node.enabled = true;
	wlr_scene_node_for_each_buffer(&w->originali->node, visita, dati);
	w->originali->node.enabled = prima;
}

struct wlr_scene_node *wobbly_nodo(struct wobbly *w, double x, double y,
		double *sx, double *sy) {
	double ox, oy;
	ondulazione_inversa(&w->forma, x - PAD, y - PAD, &ox, &oy);
	w->originali->node.enabled = true;
	struct wlr_scene_node *n = wlr_scene_node_at(&w->originali->node, ox, oy, sx, sy);
	w->originali->node.enabled = false;
	return n;
}

void wobbly_distruggi(struct wobbly *w) {
	if (!w) return;
	wl_list_remove(&w->frame.link);
	// Shader condivisi: restano fino alla distruzione del renderer.
	// Il blur torna com'era. La maschera NON si toglie a mano: la scioglie
	// SceneFX quando il proxy muore, due righe più sotto (`linked_node_destroy`
	// nel distruttore del nodo). E non è pigrizia — è che
	// `wlr_minerva_blur_set_mask(blur, NULL)` in SceneFX
	// 0.4.1 fa `linked_node_destroy(&source->blur)` **anche con source
	// NULL**, cioè dereferenzia un puntatore nullo. Preso il 13 settembre
	// 2026: il compositore annidato moriva al rilascio della finestra, con
	// `linked_node_destroy` in cima alla traccia.
	if (w->sfocatura) {
		wlr_scene_node_set_position(&w->sfocatura->node,
			w->sfocatura_x, w->sfocatura_y);
		wlr_scene_rect_set_size(w->sfocatura, w->sfocatura_w, w->sfocatura_h);
		wlr_minerva_rect_set_corners(w->sfocatura, w->sfocatura_angoli);
	}
	struct wlr_scene_node *n, *tmp;
	wl_list_for_each_safe(n, tmp, &w->originali->children, link)
		wlr_scene_node_reparent(n, w->cornice);
	wlr_scene_node_destroy(&w->proxy->node);
	wlr_scene_node_destroy(&w->originali->node);
	conserva(w->riserva, w->swapchain);
	free(w);
}
