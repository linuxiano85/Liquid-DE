// mercurio.h — Le finestre vicine che si fondono come gocce.
//
// ── Cos'è ─────────────────────────────────────────────────────────────────
//
// Il secondo materiale di Liquid, dopo l'acquerello. Due finestre che si
// avvicinano si toccano con un raccordo morbido, come due gocce di mercurio,
// e allontanandole il collo si assottiglia e si stacca. Nel disegno è
// l'unione MORBIDA (smooth-min) dei loro rettangoli arrotondati: dove l'unione
// esce dalle finestre c'è il ponte, riempito dello stesso materiale della
// barra del titolo.
//
// ── Perché è un file a sé ─────────────────────────────────────────────────
//
// Come `aggancio.c`: è conto puro, non tocca wlroots, e un difetto qui si
// vedrebbe come un ponte tagliato a metà o una macchia fra due finestre
// lontane — tardi, a occhio. Separato, si prova con dei numeri
// (`prove/prova-mercurio.c`), e la stessa funzione di distanza è quella che lo
// shader rifà per ogni pixel (`shaders/*.frag`, `minerva_mercurio`).
//
// ── I ponti, e perché non un nodo a tutto schermo ─────────────────────────
//
// Un nodo grande quanto lo schermo che cambia a ogni passo di trascinamento
// vorrebbe dire ridisegnare lo schermo intero a ogni fotogramma: il difetto
// che il blur e l'acquerello hanno appena tolto. Qui si calcola DOVE l'unione
// può uscire dalle finestre — il riquadro fra due finestre abbastanza vicine —
// e si disegna solo lì. I riquadri che si toccano si fondono in uno, così
// nessun pixel riceve il materiale due volte.
#ifndef MINERVA_MERCURIO_H
#define MINERVA_MERCURIO_H

#include <stdbool.h>

#include "aggancio.h"

/// Quanto lontano arriva la fusione, in pixel logici (il `k` dello
/// smooth-min quadratico). Due bordi paralleli si uniscono quando fra loro
/// ci sono meno di k/2 pixel: 24 con 48. Sopra, il collo si spezza.
#define MERCURIO_K 48

/// Quante forme vede un ponte. È anche la misura del vettore di uniformi
/// nello shader: cambiare l'uno senza l'altro vuol dire ponti tagliati.
#define MERCURIO_MAX 8

/// Una finestra vista da Mercurio: il suo rettangolo intero (barra compresa)
/// e il raggio degli angoli.
struct mercurio_forma {
	struct riquadro r;
	int raggio;
};

/// Un ponte: dove disegnare, e quali forme contano lì dentro (indici
/// nell'elenco passato a `mercurio_ponti`).
struct mercurio_ponte {
	struct riquadro dove;
	int forme[MERCURIO_MAX];
	int quante;
};

/// La distanza con segno dal bordo di una forma: negativa dentro, positiva
/// fuori. La stessa formula dello shader.
float mercurio_distanza(const struct mercurio_forma *f, float x, float y);

/// L'unione morbida di due distanze.
float mercurio_smin(float a, float b, float k);

/// Se il materiale del ponte copre il punto (x, y): dentro l'unione morbida
/// delle forme (il minimo degli smooth-min di ogni coppia) e fuori da tutte
/// le forme. È il conto dello shader, senza l'ammorbidimento del bordo. Al
/// più MERCURIO_MAX forme.
bool mercurio_coperto(const struct mercurio_forma *forme, int quante, int k,
	float x, float y);

/// Calcola i ponti fra `forme`. Scrive al più `max` ponti e dice quanti.
/// Due forme fanno un ponte se fra loro ci sono meno di `k` pixel (o si
/// sovrappongono: allora il raccordo sta negli angoli rientranti). Un ponte
/// con più forme di MERCURIO_MAX perde quelle in più, e lo dice tornando -1
/// (chi chiama non disegna niente piuttosto che un ponte tagliato).
int mercurio_ponti(const struct mercurio_forma *forme, int quante, int k,
	struct mercurio_ponte *ponti, int max);

#endif
