// aggancio.h — Dove finisce una finestra trascinata contro un bordo.
//
// ── Perché è un file a sé ─────────────────────────────────────────────────
//
// Per la stessa ragione di `schermi.c`: è **conto puro**, non tocca wlroots, e
// un difetto qui si vede come una finestra nel posto sbagliato — cioè tardi, a
// mano, e solo se qualcuno ci passa sopra. Separandolo si può provare con dei
// numeri, senza uno schermo e senza un compositore acceso.
//
// E non è teoria: questo conto ha già sbagliato una volta, dall'altra parte.
// In `spine/TitleBars.qml` partiva dallo schermo INTERO invece che dallo spazio
// utile, e la finestra agganciata in alto finiva sotto la barra di sistema, con
// la propria maniglia nascosta. Si vedeva come «finestra incollata alla barra e
// senza barra del titolo», e per capirlo è servito guardarla.
#ifndef MINERVA_AGGANCIO_H
#define MINERVA_AGGANCIO_H

#include <stdbool.h>

/// Un rettangolo, negli stessi campi di `struct wlr_box`.
///
/// Non si include wlroots qui: questo file deve poter essere compilato dentro
/// una prova che non ha né schermi né un compositore. I campi sono gli stessi e
/// nello stesso ordine, quindi la conversione è una copia.
struct riquadro {
	int x, y, larghezza, altezza;
};

/// Le zone contro cui si può agganciare una finestra.
enum zona_aggancio {
	ZONA_NIENTE = 0,
	ZONA_SINISTRA,
	ZONA_DESTRA,
	ZONA_CIMA,
	ZONA_ALTO_SX,
	ZONA_ALTO_DX,
	ZONA_BASSO_SX,
	ZONA_BASSO_DX,
};

/// Quanto è larga la fascia sensibile lungo i bordi, in pixel logici.
///
/// Ventiquattro, come `snapEdge` in `spine/TitleBars.qml`. Lo stesso numero da
/// tutte e due le parti non è pignoleria: chi passa da un compositore all'altro
/// deve trovare lo stesso gesto sotto il dito.
#define AGGANCIO_FASCIA 24

/// Quanto conta come «angolo», misurato LUNGO il bordo.
///
/// ── Perché non basta la fascia ────────────────────────────────────────────
///
/// Giacomo, 7 settembre 2026: «il posizionamento non è preciso e molte volte
/// le finestre non vengono messe come dovrebbero».
///
/// Con la sola fascia, un angolo è il quadratino dove le due fasce si
/// incrociano: **ventiquattro pixel per ventiquattro**, su uno schermo che ne
/// fa 1920×1080. Centrarlo mentre si trascina una finestra è una lotteria: si
/// mira al quarto di schermo e si ottiene la metà, perché si è mancato un
/// quadrato più piccolo di un'icona. Il conto era giusto e il gesto no.
///
/// Adesso un angolo si prende anche **camminando lungo il bordo**: si resta
/// nella fascia di 24 px da un lato, e si è entro questa distanza dall'altro.
///
/// Un ottavo del bordo, fra 72 e 200 pixel. L'ottavo perché su uno schermo
/// piccolo un numero fisso mangerebbe mezzo bordo; il tetto perché su uno
/// grande il bordo di sopra deve restare in gran parte «ingrandisci», che è
/// il gesto che si fa più spesso.
#define AGGANCIO_ANGOLO_MIN 72
#define AGGANCIO_ANGOLO_MAX 200

static inline int aggancio_angolo(int bordo) {
	int a = bordo / 8;
	if (a < AGGANCIO_ANGOLO_MIN) a = AGGANCIO_ANGOLO_MIN;
	if (a > AGGANCIO_ANGOLO_MAX) a = AGGANCIO_ANGOLO_MAX;
	// Su uno schermo minuscolo l'angolo non può mangiarsi metà bordo: due
	// angoli opposti si toccherebbero e il lato non esisterebbe più.
	if (a > bordo / 2) a = bordo / 2;
	return a;
}

/// In quale zona cade il puntatore, dato il rettangolo FISICO dello schermo.
///
/// Fisico e non utile, di proposito: sopra c'è la barra di sistema, e il
/// puntatore la può toccare. Chiedere l'aggancio arrivando fin sopra la barra è
/// il gesto naturale, e misurare la fascia sullo spazio utile vorrebbe dire una
/// striscia morta larga quanto la barra proprio dove la gente punta.
enum zona_aggancio aggancio_zona_di(const struct riquadro *fisico,
                                    double px, double py);

/// Dove va la finestra, dentro lo spazio UTILE.
///
/// Utile e non fisico: qui ci va il rettangolo che resta tolte barra e dock, o
/// la finestra finisce sotto di loro. È l'errore già pagato una volta.
void aggancio_riquadro(enum zona_aggancio zona, const struct riquadro *utile,
                       struct riquadro *fuori);

#endif
