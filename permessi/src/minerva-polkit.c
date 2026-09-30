// minerva-polkit — L'agente delle password di Minerva.
//
//     minerva-polkit
//
// Lo avvia `scripts/minerva-dentro-wayland` all'accesso, e da lì in poi è lui
// che compare quando qualcosa chiede il permesso di amministratore: montare un
// disco, cambiare l'ora, aprire il gestore file come root.
//
// ── Perché scriverne uno ──────────────────────────────────────────────────
//
// Perché era l'ultimo pezzo di sessione preso in prestito. Fino al
// 1º settembre 2026 `minerva-dentro-wayland` ne provava sei in fila —
// hyprpolkitagent, KDE, GNOME, LXQt, MATE — e prendeva il primo che trovava:
// cioè la finestra della password era di un altro ambiente, con la sua grafica
// e il suo carattere, in mezzo alla scrivania di Minerva. È lo stesso motivo
// per cui il blocco schermo ha smesso di essere `hyprlock`.
//
// ── Cosa fa un agente, esattamente ────────────────────────────────────────
//
// Poco, ed è importante saperlo perché la parte delicata NON è nostra.
//
// Chi decide se hai il permesso è `polkitd`, che gira come root. Chi verifica
// la password è `polkit-agent-helper-1`, un programma setuid che sta in
// `/usr/lib/polkit-1/` e parla PAM. L'agente sta in mezzo e fa due cose:
// registrarsi presso polkitd come «quello che sa chiedere», e mostrare una
// finestra quando l'helper chiede qualcosa.
//
// La password quindi **non la verifichiamo noi**, e non potremmo: polkitd non
// si fida di nessun agente. `libpolkit-agent-1` (`PolkitAgentSession`) fa da
// sé tutto il giro con l'helper; a noi resta di raccogliere il testo.
//
// ── Dove va a finire la password ──────────────────────────────────────────
//
// In un socket Unix, e in nient'altro. Mai in `argv` — `/proc/<pid>/cmdline`
// lo legge chiunque sulla macchina — mai in una variabile d'ambiente, mai su
// disco.
//
// Il socket lo creiamo qui, in `$XDG_RUNTIME_DIR` (che logind fa `0700`), con
// un nome che contiene il nostro pid, e ci accettiamo UN collegamento solo:
// quello della finestra che abbiamo appena avviato noi. Il percorso glielo
// diciamo in una variabile d'ambiente, che è il percorso — non il segreto.
//
// È la stessa regola scritta in `minervad/lib/ipc/canale_segreto.dart` e in
// `compositore/src/canale.h`.
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <glib.h>
#include <glib-unix.h>

// ── La riga che polkit chiede di scrivere ────────────────────────────────
//
// `polkitagent.h` comincia con un `#error` se questa non c'è: è polkit che
// dichiara di non promettere compatibilità fra una versione e l'altra, e
// chiede di dirlo per iscritto. È la stessa cosa che fa wlroots con
// `WLR_USE_UNSTABLE` (vedi `compositore/meson.build`), e per noi va bene
// uguale: questo programma sta nel nostro repository e si ricompila.
#define POLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE
#include <polkit/polkit.h>
#include <polkitagent/polkitagent.h>

// ── La finestra ──────────────────────────────────────────────────────────
//
// Non è una finestra scritta in C: è la stessa Quickshell del resto di
// Minerva, `minerva-shell/permessi.qml`. Qui si sa solo come avviarla e come
// parlarle.
//
// Si avvia UNA VOLTA PER RICHIESTA e si chiude quando la richiesta finisce.
// L'alternativa — tenerne una viva sempre — vorrebbe dire una settantina di
// megabyte di Qt fermi in memoria per una finestra che compare tre volte al
// giorno. Il prezzo è il tempo di avvio, che su questa macchina è misurato:
// 180 ms di Qt più il nostro QML (vedi `minerva-avvio-latenza`).

struct richiesta {
	// Il socket su cui parla la finestra, e il collegamento accettato.
	int ascolto;
	int con;
	// ── Le sorgenti del giro di eventi, e perché si tengono ──────────
	//
	// `g_unix_fd_add` lascia una sorgente attaccata al giro di eventi. Se si
	// chiude il descrittore e si libera la struttura senza TOGLIERE la
	// sorgente, quella scatta ancora — su un descrittore chiuso e con un
	// puntatore a memoria liberata. È un crollo che arriva quando la
	// finestra della password si chiude, cioè nel momento peggiore.
	guint fonte_ascolto;
	guint fonte_socket;
	gchar *percorso;
	GPid figlio;
	// La sorgente che raccoglie la finestra quando esce (`figlio_uscito`).
	guint fonte_figlio;
	// L'annullamento di polkitd: il `GCancellable` della richiesta e il
	// nostro aggancio. `dentro_annullo` vale durante il suo gestore, dove
	// staccarsi bloccherebbe per sempre (vedi `richiesta_chiudi`).
	GCancellable *annullabile;
	gulong aggancio_annullo;
	bool dentro_annullo;
	GString *coda;
	PolkitAgentSession *sessione;
	GTask *compito;
	// Vero quando `completed` è già arrivato: da lì in poi non si scrive
	// più niente sul socket, e si chiude tutto.
	bool finita;
	gchar *utente;
	gchar *messaggio;
};

static void figlio_raccolto(GPid pid, gint stato, gpointer dati) {
	(void)stato;
	(void)dati;
	g_spawn_close_pid(pid);
}

static void richiesta_chiudi(struct richiesta *r) {
	if (r->fonte_socket != 0) {
		g_source_remove(r->fonte_socket);
		r->fonte_socket = 0;
	}
	if (r->fonte_ascolto != 0) {
		g_source_remove(r->fonte_ascolto);
		r->fonte_ascolto = 0;
	}
	if (r->con >= 0) {
		close(r->con);
		r->con = -1;
	}
	if (r->ascolto >= 0) {
		close(r->ascolto);
		r->ascolto = -1;
	}
	if (r->percorso != NULL) {
		unlink(r->percorso);
		g_clear_pointer(&r->percorso, g_free);
	}
	if (r->aggancio_annullo != 0 && !r->dentro_annullo)
		g_cancellable_disconnect(r->annullabile, r->aggancio_annullo);
	r->aggancio_annullo = 0;
	if (r->figlio > 0) {
		// La finestra si chiude da sé quando il socket cade; il segnale è
		// la rete di sicurezza per il caso in cui non lo faccia.
		kill(r->figlio, SIGTERM);
		// ── E chi è uscito va RACCOLTO ───────────────────────────────
		//
		// Con `G_SPAWN_DO_NOT_REAP_CHILD` il processo non lo raccoglie
		// nessuno, e `g_spawn_close_pid` su Unix non fa niente: ogni
		// password chiesta lasciava uno `qs` zombie per tutta la vita
		// dell'agente. La sorgente legata a questa richiesta si stacca
		// (la richiesta sta per essere liberata) e al suo posto ne resta
		// una che raccoglie e basta. 30 settembre 2026.
		if (r->fonte_figlio != 0) {
			g_source_remove(r->fonte_figlio);
			r->fonte_figlio = 0;
		}
		g_child_watch_add(r->figlio, figlio_raccolto, NULL);
		r->figlio = 0;
	}
	if (r->coda != NULL) {
		// La coda può aver contenuto una password: si azzera prima di
		// liberarla. Non è teatro — la memoria liberata resta scritta.
		memset(r->coda->str, 0, r->coda->allocated_len);
		g_string_free(r->coda, TRUE);
		r->coda = NULL;
	}
	g_clear_pointer(&r->utente, g_free);
	g_clear_pointer(&r->messaggio, g_free);
}

static void richiesta_libera(struct richiesta *r) {
	richiesta_chiudi(r);
	g_clear_object(&r->sessione);
	g_free(r);
}

static gboolean libera_dopo(gpointer dati) {
	richiesta_libera(dati);
	return G_SOURCE_REMOVE;
}

/// Manda una riga alla finestra. Le righe sono il confine, come sul canale del
/// compositore: `\n` chiude il messaggio e non c'è nient'altro da contare.
static void alla_finestra(struct richiesta *r, const char *riga) {
	if (r->con < 0)
		return;
	gchar *con_a_capo = g_strdup_printf("%s\n", riga);
	const size_t n = strlen(con_a_capo);
	size_t scritti = 0;
	while (scritti < n) {
		const ssize_t v = write(r->con, con_a_capo + scritti, n - scritti);
		if (v <= 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		scritti += (size_t)v;
	}
	g_free(con_a_capo);
}

// ── Le tre cose che la sessione di polkit può dire ───────────────────────

static void su_richiesta(PolkitAgentSession *s, const gchar *prompt,
                         gboolean eco, gpointer dati) {
	(void)s;
	struct richiesta *r = dati;
	if (r->finita)
		return;
	// `eco` vero vuol dire che la risposta NON è un segreto (capita: certe
	// configurazioni PAM chiedono un codice a sei cifre da leggere). La
	// finestra deve saperlo, o mostrerebbe dei pallini dove va del testo.
	gchar *fuga = g_strescape(prompt != NULL ? prompt : "", NULL);
	gchar *riga = g_strdup_printf("chiedi %s \"%s\"",
		eco ? "visibile" : "segreto", fuga);
	alla_finestra(r, riga);
	g_free(riga);
	g_free(fuga);
}

static void su_errore(PolkitAgentSession *s, const gchar *testo,
                      gpointer dati) {
	(void)s;
	struct richiesta *r = dati;
	if (r->finita)
		return;
	gchar *fuga = g_strescape(testo != NULL ? testo : "", NULL);
	gchar *riga = g_strdup_printf("errore \"%s\"", fuga);
	alla_finestra(r, riga);
	g_free(riga);
	g_free(fuga);
}

static void su_informazione(PolkitAgentSession *s, const gchar *testo,
                            gpointer dati) {
	(void)s;
	struct richiesta *r = dati;
	if (r->finita)
		return;
	gchar *fuga = g_strescape(testo != NULL ? testo : "", NULL);
	gchar *riga = g_strdup_printf("nota \"%s\"", fuga);
	alla_finestra(r, riga);
	g_free(riga);
	g_free(fuga);
}

static void su_completata(PolkitAgentSession *s, gboolean ottenuto,
                          gpointer dati) {
	(void)s;
	struct richiesta *r = dati;
	r->finita = true;
	alla_finestra(r, ottenuto ? "fatto" : "rifiutato");

	GTask *compito = r->compito;
	r->compito = NULL;
	richiesta_chiudi(r);

	// ── Perché non si libera qui ─────────────────────────────────────
	//
	// Perché questo segnale può arrivare MENTRE si sta leggendo dal socket:
	// `dal_socket` chiama `esegui_riga`, che chiama
	// `polkit_agent_session_response`, che un giorno potrebbe rispondere
	// subito. Liberare adesso vorrebbe dire tornare dentro `dal_socket` con
	// un puntatore a memoria liberata — un crollo che arriva quando la
	// finestra si chiude, cioè nel momento in cui nessuno lo sta guardando.
	//
	// Una tappa del giro di eventi separa le due cose, e costa niente.
	g_idle_add(libera_dopo, r);

	// ── Si risponde sempre, anche quando la risposta è «no» ──────────
	//
	// polkit aspetta che l'agente dica di aver finito. Un agente che non
	// risponde lascia la richiesta appesa per sempre: il programma che ha
	// chiesto il permesso resta lì, senza finestra e senza errore, e
	// sembra bloccato.
	if (compito != NULL) {
		if (ottenuto) {
			g_task_return_boolean(compito, TRUE);
		} else {
			g_task_return_new_error(compito, POLKIT_ERROR,
				POLKIT_ERROR_FAILED,
				"autenticazione non riuscita o annullata");
		}
		g_object_unref(compito);
	}
}

// ── Annullare una richiesta, a qualunque punto sia ──────────────────────
//
// Se la finestra ha già parlato la sessione è partita, e annullarla fa
// arrivare `completed` (quindi `su_completata`, che chiude e risponde). Se
// invece la finestra non si è mai collegata la sessione non è mai partita, e
// nessun `completed` arriverebbe: si chiude e si risponde qui.
static void richiesta_annulla(struct richiesta *r) {
	if (r->finita)
		return;
	if (r->con >= 0 && r->sessione != NULL) {
		polkit_agent_session_cancel(r->sessione);
		return;
	}
	r->finita = true;
	GTask *compito = r->compito;
	r->compito = NULL;
	richiesta_chiudi(r);
	g_idle_add(libera_dopo, r);
	if (compito != NULL) {
		g_task_return_new_error(compito, POLKIT_ERROR, POLKIT_ERROR_CANCELLED,
			"richiesta annullata prima che la finestra rispondesse");
		g_object_unref(compito);
	}
}

// ── La finestra è uscita da sola ─────────────────────────────────────────
//
// Chiusa dall'utente, o caduta prima ancora di collegarsi (`qs` che non
// parte, un QML che non si carica): senza questo la richiesta restava appesa
// per sempre — polkit aspettava una risposta che nessuno avrebbe dato, e il
// programma che chiedeva il permesso sembrava bloccato. 30 settembre 2026.
static void figlio_uscito(GPid pid, gint stato, gpointer dati) {
	(void)stato;
	struct richiesta *r = dati;
	r->fonte_figlio = 0;   // una sorgente di figlio scatta una volta sola
	r->figlio = 0;
	g_spawn_close_pid(pid);
	richiesta_annulla(r);
}

// ── polkitd ritira la richiesta ──────────────────────────────────────────
//
// Il `GCancellable` scatta quando polkitd annulla — il programma che
// chiedeva è uscito, o l'attesa è scaduta. Qui non lo ascoltava nessuno: la
// finestra della password restava aperta per una domanda che non c'era più,
// e la sessione con l'aiutante di polkit restava viva. 30 settembre 2026.
static void su_annullata(GCancellable *annullabile, gpointer dati) {
	(void)annullabile;
	struct richiesta *r = dati;
	// Dentro questo gestore `g_cancellable_disconnect` aspetterebbe la fine
	// del gestore stesso, cioè per sempre: `richiesta_chiudi` non stacca.
	r->dentro_annullo = true;
	richiesta_annulla(r);
	r->dentro_annullo = false;
}

// ── Leggere quello che dice la finestra ──────────────────────────────────

static void esegui_riga(struct richiesta *r, const char *riga) {
	if (g_str_has_prefix(riga, "risposta ")) {
		// Qui passa la password. Non si registra, non si copia, non si
		// mette in un messaggio di errore: si dà alla sessione e si
		// azzera il posto in cui stava.
		gchar *segreto = g_strdup(riga + 9);
		if (r->sessione != NULL)
			polkit_agent_session_response(r->sessione, segreto);
		memset(segreto, 0, strlen(segreto));
		g_free(segreto);
		return;
	}
	if (g_strcmp0(riga, "annulla") == 0) {
		if (r->sessione != NULL && !r->finita)
			polkit_agent_session_cancel(r->sessione);
		return;
	}
	// Una riga che non conosciamo si butta in silenzio: dall'altra parte
	// c'è una finestra nostra, e se dice cose nuove è perché è più recente
	// di questo programma.
}

static gboolean dal_socket(gint fd, GIOCondition cond, gpointer dati) {
	struct richiesta *r = dati;

	if ((cond & (G_IO_HUP | G_IO_ERR)) != 0) {
		// La finestra è sparita — chiusa con la X, o morta. Vale come
		// «annulla»: meglio una richiesta rifiutata di una appesa.
		r->fonte_socket = 0;
		if (r->sessione != NULL && !r->finita)
			polkit_agent_session_cancel(r->sessione);
		return G_SOURCE_REMOVE;
	}

	char pezzo[1024];
	const ssize_t n = read(fd, pezzo, sizeof(pezzo));
	if (n <= 0) {
		if (n < 0 && (errno == EAGAIN || errno == EINTR))
			return G_SOURCE_CONTINUE;
		r->fonte_socket = 0;
		if (r->sessione != NULL && !r->finita)
			polkit_agent_session_cancel(r->sessione);
		return G_SOURCE_REMOVE;
	}

	g_string_append_len(r->coda, pezzo, n);
	memset(pezzo, 0, sizeof(pezzo));

	// ── Il tetto sulla coda ──────────────────────────────────────────
	//
	// Senza, chi arriva su questo socket può farci allocare all'infinito
	// mandando byte senza mai un a-capo. Il socket è nostro e nella nostra
	// cartella, ma una rete che costa tre righe si mette.
	if (r->coda->len > 64 * 1024) {
		r->fonte_socket = 0;
		if (r->sessione != NULL && !r->finita)
			polkit_agent_session_cancel(r->sessione);
		return G_SOURCE_REMOVE;
	}

	char *a_capo;
	// `esegui_riga` può far arrivare l'esito, e con lui `richiesta_chiudi`,
	// che libera la coda: ogni giro si ricontrolla che ci sia ancora.
	while (r->coda != NULL
	       && (a_capo = memchr(r->coda->str, '\n', r->coda->len)) != NULL) {
		const size_t quanto = (size_t)(a_capo - r->coda->str);
		gchar *riga = g_strndup(r->coda->str, quanto);
		g_string_erase(r->coda, 0, (gssize)(quanto + 1));
		esegui_riga(r, riga);
		memset(riga, 0, strlen(riga));
		g_free(riga);
	}
	return G_SOURCE_CONTINUE;
}

static gboolean qualcuno_si_collega(gint fd, GIOCondition cond,
                                    gpointer dati) {
	struct richiesta *r = dati;
	if ((cond & G_IO_IN) == 0) {
		r->fonte_ascolto = 0;
		return G_SOURCE_REMOVE;
	}

	const int c = accept(fd, NULL, NULL);
	if (c < 0)
		return G_SOURCE_CONTINUE;

	// ── Uno solo, e poi si chiude la porta ───────────────────────────
	//
	// Il socket sta in una cartella che solo noi possiamo aprire, ma
	// smettere di ascoltare appena la finestra è arrivata toglie anche il
	// caso in cui un secondo processo nostro si colleghi per sbaglio e
	// riceva il prompt.
	if (r->con >= 0) {
		close(c);
		return G_SOURCE_CONTINUE;
	}
	r->con = c;
	r->fonte_ascolto = 0;
	close(r->ascolto);
	r->ascolto = -1;
	unlink(r->percorso);

	gchar *fuga = g_strescape(r->messaggio != NULL ? r->messaggio : "", NULL);
	gchar *benvenuto = g_strdup_printf("richiesta \"%s\" \"%s\"",
		r->utente != NULL ? r->utente : "", fuga);
	alla_finestra(r, benvenuto);
	g_free(benvenuto);
	g_free(fuga);

	r->fonte_socket = g_unix_fd_add(r->con,
		G_IO_IN | G_IO_HUP | G_IO_ERR, dal_socket, r);

	// La sessione si avvia SOLO ADESSO, quando c'è una finestra a cui
	// girare il prompt. Avviarla prima vorrebbe dire ricevere `request` e
	// non avere nessuno a cui darlo — e `PolkitAgentSession` il prompt lo
	// manda una volta sola.
	polkit_agent_session_initiate(r->sessione);
	return G_SOURCE_REMOVE;
}

/// Apre il socket della finestra. Torna il percorso, o NULL.
static gchar *apri_socket(struct richiesta *r) {
	const char *dove = g_getenv("XDG_RUNTIME_DIR");
	if (dove == NULL || dove[0] == '\0') {
		g_warning("minerva-polkit: manca XDG_RUNTIME_DIR");
		return NULL;
	}

	static unsigned int contatore = 0;
	gchar *percorso = g_strdup_printf("%s/minerva-polkit-%d-%u.sock",
		dove, (int)getpid(), contatore++);

	r->ascolto = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (r->ascolto < 0) {
		g_free(percorso);
		return NULL;
	}

	struct sockaddr_un indirizzo = { 0 };
	indirizzo.sun_family = AF_UNIX;
	if (g_strlcpy(indirizzo.sun_path, percorso,
	              sizeof(indirizzo.sun_path)) >= sizeof(indirizzo.sun_path)) {
		g_warning("minerva-polkit: percorso del socket troppo lungo");
		close(r->ascolto);
		r->ascolto = -1;
		g_free(percorso);
		return NULL;
	}

	// Un socket avanzato da una volta precedente non si cancella alla cieca:
	// si prova a legare, e solo se il posto è occupato si guarda se è morto.
	// Vedi la stessa nota in `compositore/src/canale.c`.
	unlink(percorso);
	if (bind(r->ascolto, (struct sockaddr *)&indirizzo,
	         sizeof(indirizzo)) < 0 || listen(r->ascolto, 1) < 0) {
		g_warning("minerva-polkit: non riesco ad aprire %s: %s",
			percorso, g_strerror(errno));
		close(r->ascolto);
		r->ascolto = -1;
		g_free(percorso);
		return NULL;
	}
	// Solo noi. La cartella è già `0700`, ma i permessi si scrivono dove si
	// crea la cosa: chi legge questa riga non deve andare a controllare come
	// logind ha fatto la cartella.
	chmod(percorso, 0600);
	return percorso;
}

// ── L'agente vero e proprio ──────────────────────────────────────────────

#define MINERVA_TIPO_AGENTE (minerva_agente_get_type())
G_DECLARE_FINAL_TYPE(MinervaAgente, minerva_agente, MINERVA, AGENTE,
                     PolkitAgentListener)

struct _MinervaAgente {
	PolkitAgentListener genitore;
	/// Dove sta `permessi.qml`. Si calcola una volta all'avvio.
	gchar *finestra;
};

G_DEFINE_TYPE(MinervaAgente, minerva_agente, POLKIT_AGENT_TYPE_LISTENER)

/// Quale delle identità proposte usare.
///
/// polkit ne propone una lista: «per fare questo serve la password di uno di
/// questi». Si preferisce SEMPRE l'utente che sta davanti allo schermo, se è
/// fra quelli: chiedere la password di root a chi ha la propria è la
/// differenza fra una richiesta che si può soddisfare e una che manda a
/// cercare una password che magari non esiste (su molte macchine root non ne
/// ha una).
static PolkitIdentity *scegli_identita(GList *identita) {
	const gint io = (gint)getuid();
	for (GList *l = identita; l != NULL; l = l->next) {
		PolkitIdentity *id = l->data;
		if (POLKIT_IS_UNIX_USER(id)
		    && (gint)polkit_unix_user_get_uid(POLKIT_UNIX_USER(id)) == io)
			return id;
	}
	return identita != NULL ? identita->data : NULL;
}

static void minerva_agente_inizia(PolkitAgentListener *ascoltatore,
                                  const gchar *azione, const gchar *messaggio,
                                  const gchar *icona, PolkitDetails *dettagli,
                                  const gchar *biscotto, GList *identita,
                                  GCancellable *annullabile,
                                  GAsyncReadyCallback finito,
                                  gpointer dati_finito) {
	MinervaAgente *a = MINERVA_AGENTE(ascoltatore);
	(void)icona;
	(void)dettagli;

	GTask *compito = g_task_new(ascoltatore, annullabile, finito, dati_finito);

	PolkitIdentity *id = scegli_identita(identita);
	if (id == NULL) {
		g_task_return_new_error(compito, POLKIT_ERROR, POLKIT_ERROR_FAILED,
			"nessuna identità con cui autenticarsi");
		g_object_unref(compito);
		return;
	}

	struct richiesta *r = g_new0(struct richiesta, 1);
	r->ascolto = -1;
	r->con = -1;
	r->coda = g_string_new(NULL);
	r->compito = compito;
	r->messaggio = g_strdup(messaggio != NULL ? messaggio : "");
	if (POLKIT_IS_UNIX_USER(id)) {
		const gchar *nome =
			polkit_unix_user_get_name(POLKIT_UNIX_USER(id));
		r->utente = g_strdup(nome != NULL ? nome : "");
	} else {
		r->utente = polkit_identity_to_string(id);
	}

	r->percorso = apri_socket(r);
	if (r->percorso == NULL) {
		r->compito = NULL;
		g_task_return_new_error(compito, POLKIT_ERROR, POLKIT_ERROR_FAILED,
			"non riesco ad aprire il canale della finestra");
		g_object_unref(compito);
		richiesta_libera(r);
		return;
	}

	r->sessione = polkit_agent_session_new(id, biscotto);
	g_signal_connect(r->sessione, "request", G_CALLBACK(su_richiesta), r);
	g_signal_connect(r->sessione, "show-error", G_CALLBACK(su_errore), r);
	g_signal_connect(r->sessione, "show-info",
		G_CALLBACK(su_informazione), r);
	g_signal_connect(r->sessione, "completed", G_CALLBACK(su_completata), r);

	// ── La finestra ──────────────────────────────────────────────────
	//
	// Il percorso del socket va nell'AMBIENTE e non in `argv`: `argv` di un
	// processo lo legge chiunque, e anche se qui non passa il segreto, il
	// percorso del canale su cui viaggerà è la cosa che non si regala.
	gchar *argv[] = { (gchar *)"qs", (gchar *)"-p", a->finestra, NULL };
	gchar **ambiente = g_get_environ();
	ambiente = g_environ_setenv(ambiente, "MINERVA_POLKIT_CANALE",
		r->percorso, TRUE);
	ambiente = g_environ_setenv(ambiente, "MINERVA_POLKIT_AZIONE",
		azione != NULL ? azione : "", TRUE);

	GError *errore = NULL;
	if (!g_spawn_async(NULL, argv, ambiente,
	                   G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD,
	                   NULL, NULL, &r->figlio, &errore)) {
		g_warning("minerva-polkit: non riesco ad aprire la finestra: %s",
			errore != NULL ? errore->message : "?");
		g_clear_error(&errore);
		g_strfreev(ambiente);
		r->compito = NULL;
		g_task_return_new_error(compito, POLKIT_ERROR, POLKIT_ERROR_FAILED,
			"non riesco ad aprire la finestra della password");
		g_object_unref(compito);
		richiesta_libera(r);
		return;
	}
	g_strfreev(ambiente);
	r->fonte_figlio = g_child_watch_add(r->figlio, figlio_uscito, r);

	r->fonte_ascolto = g_unix_fd_add(r->ascolto, G_IO_IN,
		qualcuno_si_collega, r);

	// Per ultimo: se polkitd ha GIÀ annullato, `g_cancellable_connect`
	// chiama il gestore subito, qui dentro, e la richiesta deve essere già
	// tutta in piedi per potersi chiudere.
	if (annullabile != NULL) {
		r->annullabile = annullabile;
		r->aggancio_annullo = g_cancellable_connect(annullabile,
			G_CALLBACK(su_annullata), r, NULL);
	}
}

static gboolean minerva_agente_finisci(PolkitAgentListener *ascoltatore,
                                       GAsyncResult *risultato,
                                       GError **errore) {
	(void)ascoltatore;
	return g_task_propagate_boolean(G_TASK(risultato), errore);
}

static void minerva_agente_init(MinervaAgente *a) { (void)a; }

static void minerva_agente_finalize(GObject *o) {
	MinervaAgente *a = MINERVA_AGENTE(o);
	g_clear_pointer(&a->finestra, g_free);
	G_OBJECT_CLASS(minerva_agente_parent_class)->finalize(o);
}

static void minerva_agente_class_init(MinervaAgenteClass *c) {
	G_OBJECT_CLASS(c)->finalize = minerva_agente_finalize;
	PolkitAgentListenerClass *l = POLKIT_AGENT_LISTENER_CLASS(c);
	l->initiate_authentication = minerva_agente_inizia;
	l->initiate_authentication_finish = minerva_agente_finisci;
}

// ── L'avvio ──────────────────────────────────────────────────────────────

/// Dove sta `minerva-shell/permessi.qml`.
///
/// `MINERVA_ROOT` lo mette `scripts/start-minerva.sh` ed è la stessa variabile
/// che usano tutti gli altri script: un percorso scritto a mano qui dentro
/// sarebbe il quinto posto da cambiare quando la cartella si sposta, e
/// `scripts/prove.sh` ha una guardia apposta contro i percorsi a mano.
static gchar *dove_e_la_finestra(void) {
	const char *radice = g_getenv("MINERVA_ROOT");
	if (radice == NULL || radice[0] == '\0') {
		g_printerr("minerva-polkit: manca MINERVA_ROOT.\n");
		return NULL;
	}
	gchar *p = g_build_filename(radice, "minerva-shell", "permessi.qml",
		NULL);
	if (!g_file_test(p, G_FILE_TEST_EXISTS)) {
		g_printerr("minerva-polkit: non trovo %s\n", p);
		g_free(p);
		return NULL;
	}
	return p;
}

static gboolean esci_pulito(gpointer dati) {
	g_main_loop_quit(dati);
	return G_SOURCE_REMOVE;
}

int main(void) {
	gchar *finestra = dove_e_la_finestra();
	if (finestra == NULL)
		return 1;

	GError *errore = NULL;

	// Il soggetto è la SESSIONE, non il processo. Registrarsi per il
	// processo vorrebbe dire che l'agente vale solo per chi chiede il
	// permesso da questo stesso pid — cioè per nessuno.
	PolkitSubject *sessione =
		polkit_unix_session_new_for_process_sync(getpid(), NULL, &errore);
	if (sessione == NULL) {
		g_printerr("minerva-polkit: non trovo la sessione: %s\n",
			errore != NULL ? errore->message : "?");
		g_clear_error(&errore);
		g_free(finestra);
		return 1;
	}

	MinervaAgente *agente = g_object_new(MINERVA_TIPO_AGENTE, NULL);
	agente->finestra = finestra;

	gpointer maniglia = polkit_agent_listener_register(
		POLKIT_AGENT_LISTENER(agente),
		POLKIT_AGENT_REGISTER_FLAGS_NONE, sessione, NULL, NULL, &errore);
	if (maniglia == NULL) {
		// ── Il caso che capita davvero ───────────────────────────
		//
		// Ce n'è già uno registrato per questa sessione. Succede quando
		// resta acceso l'agente di un altro ambiente, o quando questo
		// programma viene avviato due volte. Non è un errore da
		// nascondere: senza di noi la finestra la fa qualcun altro, e
		// chi guarda lo schermo si chiede perché non somiglia a Minerva.
		g_printerr("minerva-polkit: non mi posso registrare: %s\n",
			errore != NULL ? errore->message : "?");
		g_clear_error(&errore);
		g_object_unref(agente);
		g_object_unref(sessione);
		return 1;
	}

	g_print("minerva-polkit: in ascolto per questa sessione.\n");

	GMainLoop *giro = g_main_loop_new(NULL, FALSE);
	g_unix_signal_add(SIGTERM, esci_pulito, giro);
	g_unix_signal_add(SIGINT, esci_pulito, giro);
	g_main_loop_run(giro);

	polkit_agent_listener_unregister(maniglia);
	g_main_loop_unref(giro);
	g_object_unref(agente);
	g_object_unref(sessione);
	return 0;
}
