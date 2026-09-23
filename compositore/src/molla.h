// molla.h — L'elastico: dove sta il DISEGNO di una finestra rispetto a dove
// sta la finestra.
//
// ── Che cosa fa, in una riga ──────────────────────────────────────────────
//
// Mentre trascini, la finestra resta un po' indietro rispetto al dito, e
// quando lasci raggiunge la posizione, la supera di poco e si posa. È
// l'oscillatore usato dalla deformazione di `ondulazione.c`. `wobbly.c`
// disegna la superficie deformata con un passaggio GLES di Minerva.
//
// ── Perché è un file a sé, e senza wlroots dentro ─────────────────────────
//
// Stessa ragione di `lente.c` e `aggancio.c`: è conto puro. Un elastico
// sbagliato si vede come «la finestra scatta» oppure «la finestra ondeggia
// per sempre», e sono due difetti che a fotografia non si prendono — una
// fotografia è un istante, e questo è un comportamento nel tempo. L'unica
// prova possibile è sui numeri, e per averla i numeri devono stare fuori.
//
// ── Il modello ────────────────────────────────────────────────────────────
//
// Una massa attaccata con una molla al punto dove la finestra sta DAVVERO,
// con dell'attrito:
//
//     accelerazione = rigidezza · (dove_sta − dove_si_disegna)
//                     − smorzamento · velocità
//
// Un oscillatore smorzato guida un campo continuo di deformazione. Non è
// una copia del modello a griglia di altri compositori.
//
// Lo smorzamento si sceglie SOTTO il critico — rapporto 0,42 — ed è la riga
// che fa la differenza fra «arriva» e «si posa»: a smorzamento critico la
// finestra raggiunge la posizione e si ferma, e non si vede niente. Il
// rimbalzo è l'effetto.
#ifndef MINERVA_MOLLA_H
#define MINERVA_MOLLA_H

#include <stdbool.h>

/// Il passo di riferimento, in millisecondi. Lo usano le prove; il
/// compositore batte a sedici e passa il tempo VERO trascorso.
///
/// La prima versione integrava con Eulero a passi di otto millisecondi, e
/// aveva un difetto che l'audit del 12 settembre 2026 ha preso (C01): con
/// una forza piccola — 0,1, cioè una molla rigidissima — il passo era troppo
/// lungo rispetto alla rigidezza, la molla GUADAGNAVA energia invece di
/// perderla, e le coordinate diventavano infinite. Adesso `molla_passo` usa
/// la soluzione in forma chiusa dell'oscillatore smorzato: esatta per
/// qualunque passo, costo costante, e nessun passo è «troppo lungo».
///
/// Il battito esiste solo mentre qualcosa si muove: parte con la presa e si
/// spegne da solo quando la finestra si è posata. Vedi `molla_ferma()`.
#define MOLLA_PASSO_MS 8

/// Lo stato di una finestra che insegue. Tutto in coordinate della scrivania.
struct molla {
	/// Dove si disegna adesso.
	double x, y;
	/// Quanto si sta muovendo, in pixel al secondo.
	double vx, vy;
	/// Viva: c'è da integrare. Falso vuol dire che il disegno è esattamente
	/// dove sta la finestra, e non c'è niente da fare.
	bool viva;
};

/// Accende l'elastico partendo fermo e in pari: nessuno scarto, nessuna
/// velocità. Si chiama quando comincia un trascinamento.
void molla_accendi(struct molla *s, double x, double y);

/// Spegne l'elastico e rimette il disegno dove sta la finestra.
void molla_spegni(struct molla *s, double x, double y);

/// ── Un passo ─────────────────────────────────────────────────────────────
///
/// `forza` è la manopola, e vale il contrario di quel che sembra: PIÙ forza
/// vuol dire molla più MORBIDA, quindi più ritardo e più rimbalzo. È così
/// perché è quello che uno si aspetta girando un cursore chiamato «quanto
/// tremano le finestre».
///
///  · `bersaglio_x/y` è dove la finestra sta davvero adesso;
///  · `dt` è il passo in secondi;
///  · `forza` fino a 3,0. Zero o meno vuol dire spento, e allora il
///    disegno salta in pari immediatamente.
///
/// Torna **vero** finché c'è ancora qualcosa da vedere. Falso vuol dire che
/// si è posata: chi chiama può spegnere il battito.
bool molla_passo(struct molla *s, double bersaglio_x, double bersaglio_y,
                 double dt, double forza);

/// Lo scarto fra il disegno e la finestra, già trattenuto entro un limite.
///
/// Il limite non è prudenza: una finestra che passa da un angolo all'altro
/// dello schermo — un aggancio, un cambio di scrivania, un ingrandimento —
/// darebbe uno scarto di mille pixel, e per un istante il disegno sarebbe
/// **fuori dallo schermo**. Cento pixel sono più di quanti l'elastico ne
/// produca trascinando a mano, e molto meno di un salto.
void molla_scarto(const struct molla *s, double bersaglio_x,
                  double bersaglio_y, int *dx, int *dy);

/// Vero quando la finestra si è posata: scarto sotto mezzo pixel e velocità
/// sotto un pixel al secondo. Sono le due condizioni insieme, e devono
/// esserlo: nel punto di massima escursione la velocità è zero, e nel
/// passaggio per lo zero lo scarto è zero. Guardarne una sola vorrebbe dire
/// spegnere l'elastico a metà oscillazione, cioè con uno scatto.
bool molla_ferma(const struct molla *s, double bersaglio_x, double bersaglio_y);

bool molla_passo_regolato(struct molla *, double, double, double, double, double, double);

#endif
