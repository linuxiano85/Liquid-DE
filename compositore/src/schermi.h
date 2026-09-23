#ifndef MINERVA_SCHERMI_H
#define MINERVA_SCHERMI_H

#include <stdbool.h>
#include <stdint.h>

// La configurazione di UNO schermo, come la vuole chi la scrive.
//
// I campi a zero vogliono dire «non detto»: si tiene quello che il monitor
// preferisce. È voluto — una configurazione che non nomina la frequenza non
// deve costringere a scriverla.
struct schermo_voluto {
	char nome[64];        // `eDP-1`, oppure `*` per tutti
	int larghezza;        // 0 = modo preferito
	int altezza;
	int millihz;          // Frequenza esatta quando specificata con decimali
	int hz;               // 0 = quella che viene
	int x, y;             // posizione nel disegno complessivo
	bool posizione_detta;
	double scala;         // 0 = non detta → 1
	int rotazione;        // 0, 90, 180, 270; -1 = non detta
	bool acceso;
};

#define MINERVA_SCHERMI_MAX 8

struct schermi_config {
	struct schermo_voluto voci[MINERVA_SCHERMI_MAX];
	int quanti;
};

// Legge la configurazione degli schermi.
//
// `percorso` NULL = quello di serie:
//   `$MINERVA_CONFIG_DIR/schermi.conf`, o `$XDG_CONFIG_HOME/minerva/…`,
//   o `~/.config/minerva/schermi.conf`.
//
// Un file che non c'è non è un errore: si torna con `quanti = 0` e ogni
// schermo prende il suo modo preferito a scala 1. Un compositore che si
// rifiuta di partire perché manca un file di preferenze è un computer che non
// si accende.
void schermi_leggi(struct schermi_config *fuori, const char *percorso);

// La voce che vale per uno schermo, o NULL.
//
// Vince il nome esatto sul jolly `*`, sempre, anche se il jolly viene prima
// nel file: altrimenti l'ordine delle righe deciderebbe la risposta, e
// scrivere una riga per il proprio portatile sotto una generica non
// funzionerebbe.
const struct schermo_voluto *schermi_per(const struct schermi_config *c,
                                         const char *nome);

bool schermo_modo_parse(struct schermo_voluto *, const char *);

#endif
