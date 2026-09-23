#ifndef MINERVA_ANELLO_H
#define MINERVA_ANELLO_H

#include <stdbool.h>

struct wlr_buffer;

/// I quattro pezzi in cui è tagliato l'anello.
///
/// Non è un capriccio: un anello intero vorrebbe dire un'immagine grande
/// quanto la finestra, quasi tutta trasparente, ridisegnata dodici volte al
/// secondo. Per una finestra di mille per settecento sono due megabyte e
/// mezzo a fotogramma, trenta al secondo, per una banda di sei pixel.
///
/// Tagliato in quattro, gli stessi sei pixel stanno in centosessanta
/// kilobyte: il pezzo di sopra e quello di sotto sono larghi quanto la
/// finestra e alti quanto il bordo più l'angolo (gli angoli tondi stanno
/// dentro di loro), quelli di fianco sono larghi quanto il bordo.
enum anello_pezzo {
	ANELLO_ALTO,
	ANELLO_DESTRA,
	ANELLO_BASSO,
	ANELLO_SINISTRA,
	ANELLO_PEZZI,
};

/// Quanti colori si possono scegliere. Otto: sopra, girando, non si
/// distinguono più l'uno dall'altro.
#define ANELLO_TINTE_MAX 8

struct anello_stato {
	/// La finestra, barra del titolo compresa.
	int larghezza, altezza;
	/// Lo spessore del bordo e il raggio degli angoli DI DENTRO.
	int spessore, raggio;

	/// Dove sta il giro, da 0 a 1. Somma la fase alla posizione lungo il
	/// perimetro: è quello che fa scorrere i colori.
	double fase;

	/// I colori che si alternano. Zero vuol dire lo spettro intero.
	int quante_tinte;
	float tinte[ANELLO_TINTE_MAX][3];

	/// Quanto è opaco. La finestra attiva lo vuole pieno; quelle dietro, se
	/// si sceglie di accendergliela, molto meno — o otto finestre accese
	/// insieme diventano una fiera.
	double alfa;

	/// Vero quando il colore NON gira: allora il pezzo si dipinge di una
	/// tinta sola e non c'è nessuno sfumato da calcolare.
	bool fermo;
	float fermo_r, fermo_g, fermo_b;
};

/// Disegna un pezzo dell'anello. Restituisce un buffer da appendere alla
/// scena, oppure NULL — e NULL è un caso normale: un pezzo che non ha
/// superficie (una finestra più piccola dei suoi angoli) non si disegna.
///
/// `fuori_l`, `fuori_h`, `fuori_x`, `fuori_y` dicono quanto è grande il pezzo
/// e dove va messo, in coordinate della cornice (dove la finestra comincia a
/// 0,0). Chi lo appende non deve rifare il conto: rifarlo in due posti vuol
/// dire due conti che un giorno danno due risposte.
struct wlr_buffer *anello_disegna(const struct anello_stato *stato,
	enum anello_pezzo pezzo, int *fuori_l, int *fuori_h,
	int *fuori_x, int *fuori_y);

/// Il colore del giro a una certa posizione del perimetro, da 0 a 1.
///
/// Sta qui e non in `main.c` perché lo usano tutti e due — il disegno e la
/// cornice a tinta unica che gira — e due formule per lo stesso colore sono
/// due colori il giorno che una cambia.
void anello_colore(const struct anello_stato *stato, double dove,
	float *r, float *g, float *b);

#endif
