#ifndef MINERVA_WOBBLY_H
#define MINERVA_WOBBLY_H
#include <stdbool.h>
#include "ondulazione.h"
#include <wlr/types/wlr_scene.h>
struct wlr_renderer;
struct wlr_allocator;
struct wlr_scene_tree;
struct wlr_scene_node;
struct wobbly;

struct wlr_scene_rect;
bool wobbly_prepara(struct wlr_renderer *, struct wlr_allocator *);

// Solo durante il gesto: crea il proxy grafico nello stesso livello della
// finestra, senza catturare lo schermo o modificare il buffer del client.
//
// `sfocatura` è il nodo di blur della finestra, o NULL. Se c'è resta al suo
// posto sotto il proxy e lo segue: la maschera di trasparenza di SceneFX
// sfoca solo dove il proxy dipinge, cioè ESATTAMENTE la forma deformata.
// Senza, la finestra al 69 % senza niente di sfocato dietro sembrava
// sciogliersi nello sfondo mentre la si trascinava — visto in fotografia il
// 13 settembre 2026.
struct wobbly *wobbly_crea(struct wlr_scene_tree *cornice,
	struct wlr_renderer *renderer, struct wlr_allocator *allocator,
	struct wlr_scene_rect *sfocatura);
bool wobbly_disegna(struct wobbly *w, const struct ondulazione *forma, double scala);
// Dopo `wobbly_disegna`: scala la copia di `sx`×`sy` attorno al punto
// (`ax`, `ay`, in coordinate della finestra) e la rende trasparente di `alfa`.
// Serve al respiro delle finestre (nascita, risucchio, ritorno).
void wobbly_trasforma(struct wobbly *w, double sx, double sy, double ax, double ay, float alfa);
void wobbly_distruggi(struct wobbly *w);
// Stacca la copia disegnata per ultima e la dà a chi chiama: il nodo passa
// sotto `genitore` (alla stessa posizione relativa) e in `*catena` arriva la
// catena di buffer su cui è disegnata, che da lì è sua — va distrutta con
// `wlr_swapchain_destroy` quando il nodo non serve più, e nessuno ci
// ridisegna sopra nel frattempo. Serve alla chiusura: la finestra se ne va,
// la sua copia resta per un respiro. NULL se non c'è niente di disegnato.
struct wlr_scene_buffer *wobbly_stacca(struct wobbly *w,
	struct wlr_scene_tree *genitore, struct wlr_swapchain **catena);
// Riporta il puntatore dal disegno deformato alla superficie originale.
struct wlr_scene_node *wobbly_nodo(struct wobbly *w, double x, double y,
	double *sx, double *sy);
bool wobbly_e_proxy(struct wobbly *w, struct wlr_scene_node *nodo);
void wobbly_visita(struct wobbly *w, wlr_scene_buffer_iterator_func_t visita, void *dati);
#endif
