#ifndef MINERVA_COMANDI_H
#define MINERVA_COMANDI_H

#include <stdbool.h>
#include <stddef.h>

struct minerva;

// Esegue UNA riga di comando e scrive la risposta.
//
// La risposta comincia sempre con `ok` o con `no `, come il protocollo di
// greetd e per la stessa ragione: chi legge deve poter distinguere il successo
// dal fallimento senza interpretare il resto.
//
//     fuoco 0x55f1c0        →  ok
//     fuoco 0xdeadbeef      →  no nessuna finestra con quell'indirizzo
//     finestre              →  ok [{"id":"0x55f1c0",…}]
//
// ── Perché sta in main.c e non nel canale ─────────────────────────────────
//
// Perché è la POLITICA — cosa vuol dire ingrandire, chi ha il fuoco — e la
// politica sta col compositore. Il canale fa solo il trasporto. È la stessa
// divisione che la shell si è data fra `core/Compositore.qml` e
// `core/Windows.qml`, e serve alla stessa cosa: cambiare il trasporto senza
// toccare il significato dei verbi.
void minerva_comando(struct minerva *m, const char *riga,
                     char *risposta, size_t n);

#endif
