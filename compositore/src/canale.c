// canale.c — Il socket su cui si comanda minerva-wayland.
//
// ── Cosa fa questo file, e cosa NON fa ────────────────────────────────────
//
// Fa il trasporto: apre il socket, accetta chi si collega, legge una riga,
// consegna la riga a `minerva_comando()` e riscrive la risposta. Non sa cosa
// sia una finestra, non sa cosa voglia dire «ingrandisci».
//
// È la stessa divisione che la shell si è già data fra `core/Compositore.qml`
// (traduce) e `core/Windows.qml` (decide), e per lo stesso motivo: il giorno
// in cui il trasporto cambia — un socket diverso, un altro protocollo — non
// deve cambiare nient'altro.
//
// ── Righe, e non un protocollo binario ────────────────────────────────────
//
// Perché si può provare con `socat` e leggere con gli occhi. Un compositore è
// il pezzo che, rotto, toglie lo schermo: la possibilità di parlargli da una
// console testuale vale più dei microsecondi di un formato compatto.
//
//     fuoco 0x55f1c0
//     ok
//     finestre
//     ok [{"id":"0x55f1c0","titolo":"Alacritty",…}]

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <wayland-server-core.h>

#include "canale.h"
#include "comandi.h"

// Una riga di comando non è un romanzo. Il limite c'è perché senza, un client
// che non manda mai un a capo fa crescere il buffer finché c'è memoria.
#define RIGA_MAX 4096
// La risposta può essere l'elenco delle finestre: sta più larga.
#define RISPOSTA_MAX 65536
#define CLIENTI_MAX 16

/// Quanti nomi di annuncio può chiedere un collegamento.
///
/// Erano quattro, «la shell ne usa due». Ne usava sette, e i nomi oltre il
/// quarto venivano buttati via SENZA DIRLO: la shell chiedeva `attivo` e
/// `schermi` e non li ha mai ricevuti — né la fine dell'inattività né gli
/// schermi attaccati a caldo, per settimane (trovato il 23 settembre 2026,
/// cercando perché non arrivasse l'ottavo, `bordoalto`). Adesso sedici, e chi
/// ne chiede di più riceve un «no» invece di un'iscrizione tagliata.
#define FILTRI_MAX 16

struct cliente {
	struct canale *c;
	int fd;
	struct wl_event_source *sorgente;
	char buf[RIGA_MAX];
	size_t usati;
	char uscita[4 * RISPOSTA_MAX];
	size_t uscita_usati;
	bool vivo;
	// ── Chi ha chiesto di ascoltare ──────────────────────────────────
	//
	// L'iscrizione è una proprietà del COLLEGAMENTO, non delle finestre:
	// per questo `ascolta` lo tratta il canale e non `minerva_comando()`.
	// La riga di divisione fra i due file passa qui: il canale sa chi è
	// collegato, il compositore sa cosa sia una finestra.
	bool ascolta;
	/// Quali annunci vuole. Zero vuol dire **tutti**, ed è quello che chiede
	/// il demone. La shell invece ne chiede due — `scrivania` e `scorciatoia`
	/// — perché le finestre le riceve dal demone e di qui le serve solo
	/// quello che deve arrivare subito. Vedi `canale.h`.
	char filtri[FILTRI_MAX][24];
	int quanti_filtri;
};

struct canale {
	struct minerva *m;
	struct wl_event_loop *loop;
	int fd;
	struct wl_event_source *sorgente;
	// ── 108 byte, e non uno di più ────────────────────────────────────
	//
	// `sockaddr_un.sun_path` è lungo 108 byte su Linux, punto. Un percorso
	// più lungo NON dà errore: viene troncato, e il socket si apre in un
	// posto diverso da quello che si crede — che è il modo peggiore di
	// sbagliare, perché tutto sembra funzionare finché qualcuno non prova a
	// collegarsi.
	//
	// Trovato da `werror=true` mentre si compilava, il 24 agosto 2026, ed è
	// esattamente il tipo di difetto per cui quella riga sta nel meson.
	char percorso[108];
	struct cliente clienti[CLIENTI_MAX];
};

static void cliente_chiudi(struct cliente *cl) {
	if (!cl->vivo)
		return;
	if (cl->sorgente != NULL)
		wl_event_source_remove(cl->sorgente);
	close(cl->fd);
	cl->sorgente = NULL;
	cl->fd = -1;
	cl->usati = 0;
	cl->vivo = false;
}

// Svuota la coda di uscita di un cliente, per quanto il socket accetta.
//
// ── Il ciclo che poteva fermare lo schermo, in tre versioni ───────────────
//
// 1. Prima c'era scritto `if (errno == EAGAIN) continue;`, senza altro. Il
//    socket è non bloccante: un cliente che smette di leggere riempie il
//    proprio buffer, `write` risponde EAGAIN per sempre, e quel `continue`
//    girava a vuoto **dentro il ciclo di eventi del compositore**. Un
//    programma qualunque — fermato su un punto di interruzione, in swap —
//    bloccava il mouse e lo schermo di tutti. Uscito il 24 agosto 2026.
//
// 2. Poi un `poll` con una pazienza di 200 ms: un ciclo con una fine, ma
//    sempre un'attesa dentro il compositore. L'audit di Codex del 12
//    settembre 2026 l'ha misurata (C02): un cliente fermo costava a tutti
//    gli altri **203 ms**, mouse e schermo compresi.
//
// 3. Adesso (Codex, 13 settembre) nessuno aspetta nessuno. Quello che non
//    entra nel socket resta in `uscita`, una coda per cliente, e si riprova
//    quando il ciclo di eventi dice che il socket è tornato scrivibile
//    (`WL_EVENT_WRITABLE`). Chi non legge riempie la propria coda e viene
//    chiuso — `scrivi_tutto` torna falso — senza che il compositore si sia
//    fermato un istante. `write` che scrive meno del chiesto non è più un
//    caso da gestire: è il caso normale.
static bool svuota_uscita(struct cliente *cl) {
	size_t fatti = 0;
	while (fatti < cl->uscita_usati) {
		ssize_t w = send(cl->fd, cl->uscita + fatti, cl->uscita_usati - fatti, MSG_NOSIGNAL);
		if (w > 0) {
			fatti += (size_t)w;
			continue;
		}
		if (w < 0 && errno == EINTR)
			continue;
		if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
		return false;
	}
	cl->uscita_usati -= fatti;
	memmove(cl->uscita, cl->uscita + fatti, cl->uscita_usati);
	wl_event_source_fd_update(cl->sorgente, WL_EVENT_READABLE |
		(cl->uscita_usati ? WL_EVENT_WRITABLE : 0));
	return true;
}

// Coda limitata: mai poll o attese nel thread di input/rendering.
static bool scrivi_tutto(struct cliente *cl, const char *dati, size_t n,
                         int pazienza_ms) {
	(void)pazienza_ms;
	if (n > sizeof(cl->uscita) - cl->uscita_usati) return false;
	memcpy(cl->uscita + cl->uscita_usati, dati, n);
	cl->uscita_usati += n;
	return svuota_uscita(cl);
}

/// Quanto si aspetta un cliente lento. Una risposta vale qualche decimo di
/// secondo; un annuncio non vale un fotogramma perso.
#define PAZIENZA_RISPOSTA 0
#define PAZIENZA_ANNUNCIO 0

static void esegui_riga(struct cliente *cl, char *riga) {
	// Un `\r` in fondo capita a chi manda da `echo` di certe shell o da un
	// programma scritto per Windows. Toglierlo costa una riga e toglie una
	// classe di «comando sconosciuto» che non si spiega guardando lo schermo.
	size_t n = strlen(riga);
	while (n > 0 && (riga[n - 1] == '\r' || riga[n - 1] == '\n'))
		riga[--n] = '\0';
	if (n == 0)
		return;

	// `ascolta` e `zitto` non arrivano al compositore: riguardano questo
	// collegamento e nient'altro.
	if (strcmp(riga, "ascolta") == 0 || strncmp(riga, "ascolta ", 8) == 0) {
		// I nomi sono quelli degli annunci — `scrivania`, `aperta`, `fuoco` —
		// e non dei nomi loro: chi si iscrive scrive la parola che poi legge.
		//
		// Prima si leggono tutti, e solo se ci stanno tutti l'iscrizione
		// vale: un'iscrizione tagliata a metà è un annuncio che non arriva
		// e nessuno che lo sa.
		char nomi[FILTRI_MAX][24];
		int quanti = 0;
		const char *p = riga + 7;
		const char *rifiuto = NULL;
		while (*p != '\0') {
			while (*p == ' ')
				p++;
			if (*p == '\0')
				break;
			size_t n = 0;
			while (p[n] != '\0' && p[n] != ' ')
				n++;
			if (n >= sizeof(nomi[0])) {
				rifiuto = "no un nome di annuncio è troppo lungo\n";
				break;
			}
			if (quanti == FILTRI_MAX) {
				rifiuto = "no troppi nomi di annuncio (al massimo 16)\n";
				break;
			}
			memcpy(nomi[quanti], p, n);
			nomi[quanti][n] = '\0';
			quanti++;
			p += n;
		}
		if (rifiuto != NULL) {
			if (!scrivi_tutto(cl, rifiuto, strlen(rifiuto), PAZIENZA_RISPOSTA))
				cliente_chiudi(cl);
			return;
		}
		cl->ascolta = true;
		memcpy(cl->filtri, nomi, sizeof(nomi));
		cl->quanti_filtri = quanti;
		if (!scrivi_tutto(cl, "ok ascolto\n", 11, PAZIENZA_RISPOSTA))
			cliente_chiudi(cl);
		return;
	}
	if (strcmp(riga, "zitto") == 0) {
		cl->ascolta = false;
		cl->quanti_filtri = 0;
		if (!scrivi_tutto(cl, "ok\n", 3, PAZIENZA_RISPOSTA))
			cliente_chiudi(cl);
		return;
	}

	static char risposta[RISPOSTA_MAX];
	risposta[0] = '\0';
	minerva_comando(cl->c->m, riga, risposta, sizeof(risposta));

	size_t r = strlen(risposta);
	if (r == 0 || risposta[r - 1] != '\n') {
		if (r + 1 < sizeof(risposta)) {
			risposta[r] = '\n';
			risposta[r + 1] = '\0';
			r++;
		}
	}
	if (!scrivi_tutto(cl, risposta, r, PAZIENZA_RISPOSTA))
		cliente_chiudi(cl);
}

static int cliente_leggibile(int fd, uint32_t mask, void *dati) {
	struct cliente *cl = dati;

	if ((mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR)) != 0) {
		cliente_chiudi(cl);
		return 0;
	}
	if ((mask & WL_EVENT_WRITABLE) && !svuota_uscita(cl)) {
		cliente_chiudi(cl);
		return 0;
	}
	if (!(mask & WL_EVENT_READABLE)) return 0;

	ssize_t letti = read(fd, cl->buf + cl->usati, sizeof(cl->buf) - cl->usati - 1);
	if (letti <= 0) {
		if (letti < 0 && (errno == EINTR || errno == EAGAIN))
			return 0;
		cliente_chiudi(cl);
		return 0;
	}
	cl->usati += (size_t)letti;
	cl->buf[cl->usati] = '\0';

	// Una riga per volta. Il resto — un comando arrivato a metà — resta nel
	// buffer per la prossima lettura: senza questo, un comando spezzato in due
	// pacchetti diventerebbe due comandi sbagliati.
	char *inizio = cl->buf;
	char *fine;
	while ((fine = strchr(inizio, '\n')) != NULL) {
		*fine = '\0';
		esegui_riga(cl, inizio);
		if (!cl->vivo)
			return 0;
		inizio = fine + 1;
	}

	size_t resto = strlen(inizio);
	if (resto >= sizeof(cl->buf) - 1) {
		// Una riga più lunga del buffer: si butta e si dice, invece di
		// eseguire un troncone che vuol dire un'altra cosa.
		cliente_chiudi(cl);
		return 0;
	}
	memmove(cl->buf, inizio, resto + 1);
	cl->usati = resto;
	return 0;
}

static int socket_leggibile(int fd, uint32_t mask, void *dati) {
	struct canale *c = dati;
	(void)mask;

	int nuovo = accept4(fd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
	if (nuovo < 0)
		return 0;

	struct cliente *libero = NULL;
	for (int i = 0; i < CLIENTI_MAX; i++) {
		if (!c->clienti[i].vivo) {
			libero = &c->clienti[i];
			break;
		}
	}
	if (libero == NULL) {
		// Sedici collegamenti sono già tanti: la shell ne apre uno. Se sono
		// finiti, qualcosa non li sta chiudendo — e accettarne un
		// diciassettesimo nasconderebbe il difetto invece di mostrarlo.
		const char *no = "no troppi collegamenti\n";
		ssize_t ignorato = write(nuovo, no, strlen(no));
		(void)ignorato;
		close(nuovo);
		return 0;
	}

	memset(libero, 0, sizeof(*libero));
	libero->c = c;
	libero->fd = nuovo;
	libero->vivo = true;
	libero->sorgente = wl_event_loop_add_fd(c->loop, nuovo, WL_EVENT_READABLE,
	                                        cliente_leggibile, libero);
	if (!libero->sorgente) cliente_chiudi(libero);
	return 0;
}

// Restituisce falso se il percorso non ci sta: meglio nessun canale che un
// canale aperto in un posto che non è quello.
static bool percorso_socket(char *fuori, size_t n, const char *display) {
	const char *run = getenv("XDG_RUNTIME_DIR");
	// Senza `XDG_RUNTIME_DIR` non si inventa `/tmp`: lì il socket sarebbe in
	// una cartella scrivibile da chiunque abbia un account su questa macchina,
	// e chi apre quel socket comanda le finestre di chi ha fatto l'accesso.
	// Meglio nessun canale che un canale aperto a tutti.
	if (run == NULL || run[0] == '\0') {
		fuori[0] = '\0';
		return false;
	}
	int scritti = snprintf(fuori, n, "%s/minerva-wayland-%s.sock", run,
	                       display != NULL ? display : "0");
	if (scritti < 0 || (size_t)scritti >= n) {
		fuori[0] = '\0';
		return false;
	}
	return true;
}

struct canale *canale_apri(struct minerva *m, struct wl_event_loop *loop,
                           const char *nome_display) {
	struct canale *c = calloc(1, sizeof(*c));
	if (c == NULL)
		return NULL;
	c->m = m;
	c->loop = loop;
	c->fd = -1;

	if (!percorso_socket(c->percorso, sizeof(c->percorso), nome_display)) {
		free(c);
		return NULL;
	}

	// Un socket avanzato da un compositore morto male impedisce il `bind`.
	// Toglierlo è sicuro: il nostro percorso contiene il nome del display, e
	// due compositori sullo stesso display non possono esistere.
	unlink(c->percorso);

	c->fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (c->fd < 0) {
		free(c);
		return NULL;
	}

	struct sockaddr_un addr = {0};
	addr.sun_family = AF_UNIX;
	// `c->percorso` è già lungo quanto `sun_path`, e `percorso_socket` ha già
	// rifiutato quello che non ci stava: qui si copia e basta.
	memcpy(addr.sun_path, c->percorso, sizeof(addr.sun_path));
	addr.sun_path[sizeof(addr.sun_path) - 1] = '\0';

	// I permessi si stringono PRIMA di mettersi in ascolto: fra il `bind` e la
	// `chmod` c'è una finestra in cui il socket esiste coi permessi della
	// `umask`, e in quella finestra qualcuno potrebbe collegarsi. `umask`
	// intorno al bind chiude la finestra invece di rincorrerla.
	mode_t vecchia = umask(0177);
	int esito = bind(c->fd, (struct sockaddr *)&addr, sizeof(addr));
	umask(vecchia);
	if (esito < 0) {
		close(c->fd);
		free(c);
		return NULL;
	}

	if (listen(c->fd, 8) < 0) {
		close(c->fd);
		unlink(c->percorso);
		free(c);
		return NULL;
	}

	c->sorgente = wl_event_loop_add_fd(loop, c->fd, WL_EVENT_READABLE,
	                                   socket_leggibile, c);
	if (!c->sorgente) {
		canale_chiudi(c);
		return NULL;
	}
	return c;
}

void canale_chiudi(struct canale *c) {
	if (c == NULL)
		return;
	for (int i = 0; i < CLIENTI_MAX; i++)
		cliente_chiudi(&c->clienti[i]);
	if (c->sorgente != NULL)
		wl_event_source_remove(c->sorgente);
	if (c->fd >= 0)
		close(c->fd);
	if (c->percorso[0] != '\0')
		unlink(c->percorso);
	free(c);
}

void canale_annuncia(struct canale *c, const char *che, const char *riga) {
	if (c == NULL || riga == NULL || riga[0] == '\0')
		return;

	size_t n = strlen(riga);
	// L'a capo lo mette il canale e non chi annuncia: chi annuncia ha già
	// abbastanza da ricordare, e una riga senza a capo si incolla alla
	// successiva senza dare errore da nessuna parte.
	bool serve_acapo = riga[n - 1] != '\n';

	for (int i = 0; i < CLIENTI_MAX; i++) {
		struct cliente *cl = &c->clienti[i];
		if (!cl->vivo || !cl->ascolta)
			continue;
		if (cl->quanti_filtri > 0) {
			bool suo = false;
			for (int j = 0; j < cl->quanti_filtri; j++) {
				if (strcmp(cl->filtri[j], che) == 0) {
					suo = true;
					break;
				}
			}
			if (!suo)
				continue;
		}
		// ── Se non ascolta, si chiude, e non è un errore ─────────────
		//
		// Un cliente che non legge riempie il proprio buffer, e a quel
		// punto `write` non torna più. Insistere vorrebbe dire fermare il
		// COMPOSITORE — cioè lo schermo — perché un programma qualunque
		// non sta leggendo. Si chiude il collegamento: lui si riconnette,
		// noi continuiamo a disegnare.
		if (!scrivi_tutto(cl, riga, n, PAZIENZA_ANNUNCIO)
		    || (serve_acapo
		        && !scrivi_tutto(cl, "\n", 1, PAZIENZA_ANNUNCIO)))
			cliente_chiudi(cl);
	}
}

const char *canale_percorso(const struct canale *c) {
	return c != NULL ? c->percorso : "";
}
