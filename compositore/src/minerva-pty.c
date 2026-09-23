// minerva-pty — Apre uno pseudo-terminale, ci mette dentro la shell, e fa da
// tramite fra lei e chi lo ha lanciato.
//
// ── Perché esiste, in tre righe ────────────────────────────────────────────
//
// Il motore del Terminale di Minerva è in Dart, e Dart non può fare `fork`:
// la sua macchina virtuale è multithread, e un `fork` da FFI lascia il figlio
// con un solo filo e i lucchetti degli altri ancora chiusi. E Quickshell sa
// lanciare processi, ma su una pipe: un programma su una pipe non è «in un
// terminale» — `ls` non colora, `htop` si rifiuta, `sudo` non chiede.
//
// Quindi lo pseudo-terminale lo apre questo programmino, come `minerva-cattura`
// legge lo schermo: un mestiere solo, centoventi righe, e chi lo lancia parla
// con lui su stdin/stdout.
//
// ── Il protocollo ──────────────────────────────────────────────────────────
//
// Su **stdout** i byte che escono dal terminale, grezzi, senza cornice: è un
// flusso, e il motore lo dà all'emulatore com'è.
//
// Su **stdin** delle CORNICI, perché dentro ci passano due cose diverse:
//
//     [tipo: 1 byte][lunghezza: 2 byte, big-endian][dati]
//
//     tipo 0   tasti — i byte vanno al terminale così come sono
//     tipo 1   misura — dati = "colonne righe" in ASCII, e si fa TIOCSWINSZ
//
// Non un JSON: i tasti sono byte qualunque, compresi \0 e \n, e una cornice
// con la lunghezza davanti è l'unico modo di non doverli travestire.
//
// Su **stderr**, all'uscita, una riga: `uscita N` col codice del figlio (o
// `segnale N`). Chi legge sa distinguere «la shell ha detto exit» da «è
// caduta».
//
// ── Cosa NON fa ────────────────────────────────────────────────────────────
//
// Non aggiunge variabili d'ambiente oltre a TERM, COLORTERM e TERM_PROGRAM;
// non cambia utente; non tocca file. Gira come chi lo lancia e niente di più:
// è la riga che vale per «sicuro» nella richiesta di Giacomo.
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t figlio = -1;

static void uso(void) {
	fprintf(stderr, "uso: minerva-pty [--colonne N] [--righe N] "
		"[--cartella DIR] [--esegui COMANDO] [--shell PROG] [--arg X]... [--non-accesso]\n");
}

/// Scrive tutto, riprovando sugli scritti parziali. Torna falso se il
/// destinatario è sparito.
static int scrivi_tutto(int fd, const unsigned char *b, size_t n) {
	while (n > 0) {
		ssize_t w = write(fd, b, n);
		if (w < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			return 0;
		}
		b += (size_t)w;
		n -= (size_t)w;
	}
	return 1;
}

/// Legge esattamente `n` byte da stdin. Torna 0 alla fine del flusso.
static int leggi_esatto(unsigned char *b, size_t n) {
	while (n > 0) {
		ssize_t r = read(STDIN_FILENO, b, n);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			return 0;
		}
		if (r == 0)
			return 0;
		b += (size_t)r;
		n -= (size_t)r;
	}
	return 1;
}

int main(int argc, char **argv) {
	struct winsize misura = { .ws_row = 24, .ws_col = 80 };
	const char *cartella = NULL;
	const char *esegui = NULL;
	const char *shell = getenv("SHELL");
	if (shell == NULL || shell[0] == '\0')
		shell = "/bin/sh";
	// Gli argomenti in più per la shell (`bash --rcfile …`): pochi, e in
	// ordine. Zsh non ne ha bisogno, gli basta `ZDOTDIR` nell'ambiente.
	const char *arg_shell[16];
	int n_arg_shell = 0;
	// Di serie la shell è di ACCESSO («-zsh»). bash con `--rcfile` no: da
	// shell di accesso ignora quell'opzione e legge `.bash_profile`.
	int accesso = 1;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--colonne") == 0 && i + 1 < argc) {
			int v = atoi(argv[++i]);
			if (v > 0 && v < 10000) misura.ws_col = (unsigned short)v;
		} else if (strcmp(argv[i], "--righe") == 0 && i + 1 < argc) {
			int v = atoi(argv[++i]);
			if (v > 0 && v < 10000) misura.ws_row = (unsigned short)v;
		} else if (strcmp(argv[i], "--cartella") == 0 && i + 1 < argc) {
			cartella = argv[++i];
		} else if (strcmp(argv[i], "--esegui") == 0 && i + 1 < argc) {
			esegui = argv[++i];
		} else if (strcmp(argv[i], "--shell") == 0 && i + 1 < argc) {
			shell = argv[++i];
		} else if (strcmp(argv[i], "--non-accesso") == 0) {
			accesso = 0;
		} else if (strcmp(argv[i], "--arg") == 0 && i + 1 < argc) {
			if (n_arg_shell < 15)
				arg_shell[n_arg_shell++] = argv[++i];
			else
				i++;
		} else {
			uso();
			return 2;
		}
	}

	int padrone = -1;
	figlio = forkpty(&padrone, NULL, NULL, &misura);
	if (figlio < 0) {
		perror("minerva-pty: forkpty");
		return 1;
	}
	if (figlio == 0) {
		// ── Il figlio: la shell ────────────────────────────────────────
		setenv("TERM", "xterm-256color", 1);
		setenv("COLORTERM", "truecolor", 1);
		setenv("TERM_PROGRAM", "minerva", 1);
		if (cartella != NULL && chdir(cartella) != 0) {
			// Una cartella sparita non deve impedire di avere un terminale:
			// si parte da casa, e lo si dice.
			fprintf(stderr, "minerva-pty: «%s» non c'è, parto da casa\n", cartella);
			const char *casa = getenv("HOME");
			if (casa != NULL)
				(void)chdir(casa);
		}
		if (esegui != NULL) {
			execl("/bin/sh", "sh", "-c", esegui, (char *)NULL);
		} else {
			// Una shell di ACCESSO («-zsh»): legge i suoi file come farebbe
			// su una console, che è quello che uno si aspetta aprendo un
			// terminale.
			const char *base = strrchr(shell, '/');
			base = base != NULL ? base + 1 : shell;
			char argv0[256];
			snprintf(argv0, sizeof(argv0), "%s%s", accesso ? "-" : "", base);
			const char *ev[18];
			int n = 0;
			ev[n++] = argv0;
			for (int k = 0; k < n_arg_shell; k++)
				ev[n++] = arg_shell[k];
			ev[n] = NULL;
			execv(shell, (char *const *)ev);
		}
		perror("minerva-pty: exec");
		_exit(127);
	}

	// ── Il padre: il tramite ─────────────────────────────────────────────
	//
	// Due sorgenti: lo pseudo-terminale (verso stdout) e stdin (cornici verso
	// il terminale o la misura). `poll` su tutte e due; niente fili.
	unsigned char buf[65536];
	int vivo = 1;
	while (vivo) {
		struct pollfd pf[2] = {
			{ .fd = padrone, .events = POLLIN },
			{ .fd = STDIN_FILENO, .events = POLLIN },
		};
		int pronto = poll(pf, 2, -1);
		if (pronto < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		if (pf[0].revents & (POLLIN | POLLHUP | POLLERR)) {
			ssize_t r = read(padrone, buf, sizeof(buf));
			if (r <= 0) {
				// La shell ha chiuso: si esce, e si dice come.
				break;
			}
			if (!scrivi_tutto(STDOUT_FILENO, buf, (size_t)r))
				break;
		}
		if (pf[1].revents & (POLLIN | POLLHUP | POLLERR)) {
			unsigned char testa[3];
			if (!leggi_esatto(testa, 3)) {
				// Chi ci ha lanciato se n'è andato: la shell riceve la
				// fine del terminale e muore da sé.
				break;
			}
			size_t n = ((size_t)testa[1] << 8) | testa[2];
			if (n > sizeof(buf)) {
				fprintf(stderr, "minerva-pty: cornice troppo grande\n");
				break;
			}
			if (n > 0 && !leggi_esatto(buf, n))
				break;
			if (testa[0] == 0) {
				if (!scrivi_tutto(padrone, buf, n))
					break;
			} else if (testa[0] == 1) {
				buf[n < sizeof(buf) ? n : sizeof(buf) - 1] = '\0';
				int c = 0, rr = 0;
				if (sscanf((char *)buf, "%d %d", &c, &rr) == 2
						&& c > 0 && rr > 0 && c < 10000 && rr < 10000) {
					misura.ws_col = (unsigned short)c;
					misura.ws_row = (unsigned short)rr;
					(void)ioctl(padrone, TIOCSWINSZ, &misura);
				}
			}
			// Altri tipi: ignorati, per poter crescere senza rompere.
		}
	}

	close(padrone);
	int stato = 0;
	if (waitpid(figlio, &stato, WNOHANG) == 0) {
		// Ancora vivo: gli si chiede di andarsene, poi lo si aspetta.
		kill(figlio, SIGHUP);
		waitpid(figlio, &stato, 0);
	}
	if (WIFEXITED(stato))
		fprintf(stderr, "uscita %d\n", WEXITSTATUS(stato));
	else if (WIFSIGNALED(stato))
		fprintf(stderr, "segnale %d\n", WTERMSIG(stato));
	return 0;
}
