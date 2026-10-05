// barra.h — La barra del titolo di Minerva, disegnata dal compositore.
//
// ── Perché è nata questa ─────────────────────────────────────────────────
//
// Giacomo, 19 agosto 2026, guardando la scrivania dentro minerva-wayland:
// «non vedo la barra del titolo o sbaglio?».
//
// Non sbagliava. Minerva sapeva disegnarla in due modi, e nessuno dei due
// funzionava lì dentro:
//
//  · dalla SHELL (`spine/TitleBars.qml`, tolta il 5 ottobre 2026), una
//    superficie appoggiata sopra le finestre, che chiedeva a Hyprland dove
//    stava ogni finestra. Dentro il nostro
//    compositore Hyprland non c'è: le barre comparivano tutte nell'angolo in
//    alto a sinistra, una sopra l'altra;
//  · dal PLUGIN (`plugins/minerva-bars`), che è codice dentro Hyprland, e
//    dentro il nostro compositore non esiste proprio.
//
// Questa è la terza, ed è quella per cui il piano prevedeva la Tappa 4: la
// barra è **parte del compositore**. Non c'è niente da inseguire perché la
// barra e la finestra sono lo stesso nodo della scena; non c'è nessuna ABI
// legata a un commit che possa far sparire le barre dopo un aggiornamento;
// e chi copre chi non è un'euristica, è l'albero.
//
// ── Le misure sono le stesse del plugin, di proposito ────────────────────
//
// 42 di altezza, 10 di raggio, pulsanti quadrati alti quanto la barra meno
// dieci. Non sono numeri nuovi: sono quelli che Giacomo guarda da settimane, e
// cambiarli qui vorrebbe dire far sembrare «diverso» un compositore che deve
// sembrare lo stesso, solo migliore.
#ifndef MINERVA_BARRA_H
#define MINERVA_BARRA_H

#include <stdbool.h>
#include <wlr/util/box.h>

struct wlr_buffer;

// I valori di FABBRICA. Restano `#define` perché sono il punto di partenza e
// il ripiego: quello che si regola dal pannello sta in `struct barra_aspetto`
// qui sotto, e parte esattamente da questi.
#define BARRA_ALTA     42
#define BARRA_RAGGIO   10
#define BARRA_PULSANTI 4

/// ── Quello che il pannello può cambiare ─────────────────────────────────
///
/// Fino al 31 agosto 2026 l'altezza della barra, il lato dei pulsanti e i
/// colori della cornice erano `#define`: il pannello «Finestre» mostrava
/// `windows.titleHeight` e `windows.buttonsSide`, li scriveva in
/// `settings.json`, e sotto minerva-wayland non succedeva **niente**.
///
/// Un comando che si vede e non fa nulla è peggio di un comando che non c'è:
/// chi lo tocca crede di aver cambiato qualcosa, e la prossima volta che una
/// cosa non cambia non sa più se è rotta o se è lui.
///
/// I colori sono in 0…1, come li vuole cairo.
struct barra_aspetto {
	int alta;
	/// Vero: pulsanti a destra (la convenzione di casa). Falso: a sinistra,
	/// come su macOS — c'è chi ci ha vissuto trent'anni.
	bool pulsanti_a_destra;
	double fondo_r, fondo_g, fondo_b;
	double testo_r, testo_g, testo_b;
};

/// L'aspetto in vigore adesso. Non si scrive a mano: si passa da
/// `barra_aspetto_imposta`, che è l'unico posto che sa mettere a posto i
/// valori storti.
const struct barra_aspetto *barra_aspetto_ora(void);

/// Cambia l'aspetto. Ogni campo si può lasciare stare passando un valore
/// «non detto»: `alta <= 0`, e un colore con la componente rossa negativa.
///
/// Torna falso se non ha cambiato niente perché i valori erano fuori misura —
/// e in quel caso l'aspetto di prima resta intatto, invece di finire a metà.
bool barra_aspetto_imposta(const struct barra_aspetto *nuovo);

/// L'altezza in vigore. Scorciatoia per chi deve solo fare il conto dello
/// spazio (`main.c`), senza interessarsi del resto.
int barra_alta(void);

// L'ordine è quello in cui sono disegnati da sinistra a destra; «chiudi» resta
// all'estremità, che è l'unica convenzione su cui tutti i sistemi vanno
// d'accordo.
enum pulsante {
	PULSANTE_RIDUCI = 0,
	PULSANTE_INGRANDISCI,
	PULSANTE_SCHERMO,
	PULSANTE_CHIUDI,
};

struct barra_stato {
	const char *titolo;
	int larghezza;
	bool fuoco;
	bool ingrandita;
	/// Quale pulsante sta sotto il puntatore adesso: -1 nessuno.
	int sotto_il_dito;
	/// ── Chi mette la trasparenza ─────────────────────────────────────
	///
	/// Falso: la barra se la mette da sé, 0,90 a fuoco e 0,70 senza. È
	/// come ha sempre funzionato, ed è giusto finché la barra è l'unica
	/// cosa trasparente sullo schermo.
	///
	/// Vero: la barra si disegna OPACA, perché la trasparenza la applica
	/// la scena a tutto l'albero della finestra — barra e contenuto
	/// insieme. Se se la mettesse anche lei, le due si moltiplicherebbero
	/// e la barra risulterebbe più chiara del resto: cioè proprio lo
	/// stacco che il corpo unico esiste per togliere.
	///
	/// Giacomo, 2 settembre 2026: «in blur o vetro dovrebbero far vedere
	/// un solo corpo trasparente [...] la barra e la finestra senza
	/// stacchi di blur o trasparenza».
	bool corpo_unico;
};

/// Disegna la barra e restituisce un buffer con un riferimento già preso: chi
/// lo riceve lo passa alla scena e poi fa `wlr_buffer_drop`.
///
/// Torna NULL se non c'è niente da disegnare (larghezza nulla o negativa).
struct wlr_buffer *barra_disegna(const struct barra_stato *stato);

/// Dove sta un pulsante, in coordinate della barra.
void barra_box_pulsante(int indice, int larghezza, struct wlr_box *fuori);

/// Quale pulsante c'è sotto questo punto della barra: -1 nessuno.
int barra_pulsante_a(double x, double y, int larghezza);

/// ── Un cartello a schermo ────────────────────────────────────────────────
///
/// Disegna una riga di testo dentro una pillola scura, e torna il buffer (con
/// un riferimento già preso, come `barra_disegna`) più la sua misura.
///
/// Serve a dire una cosa quando **non c'è più nessuno che possa dirla**: se la
/// scrivania muore e il suo guardiano si arrende, la shell non c'è, quindi non
/// ci sono avvisi, non c'è la barra, non c'è niente. L'unico rimasto in piedi
/// è il compositore.
///
/// Fino al 1º settembre 2026 quel messaggio lo dava `hyprctl notify`, e sotto
/// il nostro compositore non lo dava nessuno: schermo nero e nessuna
/// spiegazione. Questa è la stessa cosa, fatta da noi.
///
/// Sta in `barra.c` e non in un file suo per una ragione pratica: qui c'è già
/// l'involucro `wlr_buffer` sopra cairo e il carattere di Minerva tenuto da
/// parte. Un secondo file vorrebbe dire duplicare tutti e due.
///
/// Torna NULL se non c'è niente da disegnare.
struct wlr_buffer *barra_cartello(const char *testo, int largo_max,
                                  int *fuori_l, int *fuori_h);

/// Butta via il carattere tenuto da parte. Da chiamare all'uscita.
void barra_svuota(void);

#endif
