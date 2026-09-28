// minerva-wayland — Il compositore di Minerva.
//
// Tappa 1: la prima luce. Un compositore che parte, accende gli schermi che
// trova, e disegna le finestre che gli arrivano.
//
// ── Le firme sono state LETTE, non ricordate ──────────────────────────────
//
// Ogni chiamata qui dentro viene dagli header di wlroots 0.20.2 installati su
// questa macchina, non da un esempio trovato online. È la lezione più costosa
// del plugin: l'API vera di Hyprland 0.56 non corrispondeva a quella che si
// trovava in giro, e ci è costato un pomeriggio.
//
// E in wlroots la differenza morde subito, perché la 0.20 ha cambiato proprio
// la prima riga che si scrive:
//
//     wlr_backend_autocreate(struct wl_event_loop *, struct wlr_session **)
//
// Vuole il CICLO DI EVENTI, non il `wl_display`. Ogni esempio anteriore alla
// 0.19 passa il display, compila con un avviso e poi non parte.
//
// ── Perché la «scena» e non un disegno nostro ─────────────────────────────
//
// `wlr_scene` è un albero di rettangoli che wlroots sa disegnare da sé, con
// il ritaglio, la trasformazione degli schermi e — soprattutto — il calcolo
// dei danni: ridisegna solo quello che è cambiato. Scriverlo a mano si può, ma
// è la parte che si paga in fotogrammi persi e in batteria, e non è quella che
// rende Minerva diversa.
//
// Quello che vogliamo possedere sono le REGOLE — dove nasce una finestra, cosa
// vuol dire ingrandirla, come si muove la gelatina — non il ciclo di disegno.

#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>

#include <libinput.h>

#include <linux/input-event-codes.h>
#include <time.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <wayland-server-core.h>

#include <wlr/backend.h>
#include <wlr/backend/libinput.h>
#include <wlr/backend/wayland.h>
#include <wlr/render/allocator.h>
#include <wlr/render/color.h>
#include <wlr/types/wlr_damage_ring.h>
#include <wlr/render/swapchain.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/interfaces/wlr_keyboard.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_switch.h>
// ── La scena viene da SceneFX, non da wlroots ────────────────────────────
//
// E non è un innesto: SceneFX espone **gli stessi identici nomi** —
// `wlr_scene_create`, `wlr_scene_node_set_position`, tutti i 136 usi di questo
// file — perché è una FORCELLA della scena di wlroots con dentro tre effetti
// in più: sfocatura, angoli arrotondati, ombre. Cambia l'include e cambia la
// libreria a cui ci si lega; nel codice non cambia una riga.
//
// È la stessa strada di SwayFX, che ci gira sopra in produzione. I suoi autori
// scrivono che non è pronta per altri compositori, ed è la ragione per cui
// questo lavoro si fa su un ramo e si prova solo annidato.
#include <wlr/types/wlr_scene.h>
#include <wlr/render/gles2.h>
#include <wlr/types/wlr_minerva_timing.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_linux_drm_syncobj_v1.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_viewporter.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_primary_selection_v1.h>
#include <wlr/types/wlr_ext_data_control_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/types/wlr_gamma_control_v1.h>
#include <wlr/types/wlr_idle_notify_v1.h>
#include <wlr/types/wlr_idle_inhibit_v1.h>
#include <wlr/types/wlr_single_pixel_buffer_v1.h>
#include <wlr/types/wlr_cursor_shape_v1.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/edges.h>

// ── XWayland: i programmi che non parlano Wayland ────────────────────────
//
// Steam, i giochi, Wine, e una lunga coda di programmi che non saranno mai
// portati. Senza questo blocco quei programmi dentro minerva-wayland non si
// aprono **affatto**: non partono male, non si vedono storti — proprio non
// compaiono, perché non trovano nessun DISPLAY a cui collegarsi.
//
// `WLR_HAS_XWAYLAND` sta in `wlr/config.h` ed è scritto quando wlroots viene
// compilata. Se è spento si ferma qui, con una frase, invece di lasciare un
// compositore che sembra a posto e non apre Steam.
#include <wlr/config.h>
#if !WLR_HAS_XWAYLAND
#error "Questa wlroots non ha XWayland: Steam e i giochi non si aprirebbero. Serve wlroots0.20 compilata col supporto XWayland."
#endif
#include <wlr/xwayland.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

#include "aggancio.h"
#include "anello.h"
#include "barra.h"
#include "lente.h"
#include "mercurio.h"
#include "molla.h"
#include "wobbly.h"
#include "sonno.h"
#include "energia.h"
#include "puntatore.h"
#include "schermi.h"
#include <wlr/backend/headless.h>
#include "canale.h"
#include "comandi.h"

/// Quante scrivanie. Dieci perché tante ne nomina
/// `config/scorciatoie.minerva` — `$mod 1…0` — ed è quel file la sorgente:
/// un numero diverso qui vorrebbe dire una scorciatoia che esiste nel
/// promemoria e non fa niente. Vedi `scripts/minerva-scorciatoie`.
#define SCRIVANIE 10

/// Quante scorciatoie ci stanno. Novantacinque ne ha Minerva oggi; il tetto è
/// alto il doppio, e non è un limite ma la garanzia che una riga in più non
/// scriva fuori dall'array.
#define SCORCIATOIE_MAX 192

/// Quante soglie di inattività la shell può chiedere in una volta.
///
/// Otto è largo: la politica di Minerva ne usa tre — schermo giù, blocco,
/// sospensione — e il tetto serve solo a garantire che una riga con
/// cinquanta numeri non scriva fuori dall'array.
#define MINERVA_SOGLIE_INATTIVITA 8

/// Una scorciatoia registrata: quali modificatori, quale tasto, cosa fare.
///
/// `azione` e `argomento` restano **parole di Minerva** — «scrivania»,
/// «avvia» — e non diventano numeri: il vocabolario è quello di
/// `config/scorciatoie.minerva`, e tradurlo qui vorrebbe dire un terzo posto
/// che deve sapere come si chiamano le cose.
struct scorciatoia {
	uint32_t modificatori;
	xkb_keysym_t tasto;
	char azione[32];
	char argomento[192];
	/// Funziona anche a schermo bloccato. Sono il volume, la luminosità e i
	/// tasti del lettore: le uniche cose che ha senso poter fare senza aver
	/// sbloccato, ed è il flag `anche-bloccato` della sorgente.
	bool anche_bloccato;
	/// Scatta quando il tasto si ALZA, non quando si abbassa.
	///
	/// Serve a una cosa sola, e senza di lei quella cosa è rotta a metà:
	/// l'Alt che conferma l'Alt+Tab. `ALT Tab` apre il selettore; a chiuderlo
	/// è il momento in cui si molla Alt, che non è una scorciatoia da
	/// imparare — è il seguito del gesto. Senza, il riquadro resta aperto
	/// sullo schermo e la finestra scelta non prende il fuoco.
	///
	/// È il flag `al-rilascio` della sorgente, ed è `bindr` in Hyprland.
	bool al_rilascio;
	/// Scatta solo se quel tasto è stato premuto e lasciato **da solo**.
	///
	/// È il gesto «premi Super e lascialo» che apre il menù delle
	/// applicazioni, come su Windows e su GNOME. Va insieme ad
	/// `al_rilascio`, e senza questa seconda condizione sarebbe un difetto e
	/// non una comodità: il menù si aprirebbe anche alla fine di Super+E,
	/// Super+1, Super+Invio — cioè **dopo ogni scorciatoia che comincia per
	/// Super**, che sono quarantatré.
	///
	/// E non si può accendere per tutte le scorciatoie del rilascio: l'Alt
	/// che conferma l'Alt+Tab DEVE scattare proprio quando in mezzo è stato
	/// premuto Tab. Sono due gesti opposti sullo stesso meccanismo, ed è il
	/// motivo per cui questo è un flag e non una regola.
	///
	/// È il flag `tocco` della sorgente. Hyprland non sa esprimerlo — `bindr`
	/// là scatta comunque — quindi quella riga non entra in `keybinds.conf`.
	bool da_solo;
	/// Scatta se quel tasto resta premuto DA SOLO per 400 ms, e al rilascio
	/// annuncia la stessa azione col suffisso `-via`.
	///
	/// È il flag `tieni` della sorgente: Super tenuto premuto disegna i tasti
	/// sulla scrivania finché non lo lasci. Il rilascio dopo un «tieni» non
	/// è un tocco — senza questa regola lasciando Super si aprirebbe anche il
	/// menù, cioè due cose per un gesto solo.
	bool tenuto;
};

struct minerva {
    struct monitor_transaction *monitor_transaction;
	struct wl_display *display;
	struct wl_event_loop *loop;
	struct sonno *sonno;
	struct puntatore *puntatore;
	bool sospendi_pendente;
	struct wl_event_source *sospendi_timer;

	struct wlr_backend *backend;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_scene *scena;
	struct wlr_scene_output_layout *scena_schermi;
	struct wlr_output_layout *schermi;

	struct wlr_xdg_shell *xdg_shell;
	struct wlr_layer_shell_v1 *layer_shell;

	/// XWayland, e le finestre «override redirect» che ne escono. Sta a
	/// parte da `finestre_elenco` apposta: quelle non sono finestre di
	/// Minerva, sono disegni che un programma X11 si mette sopra.
	struct wlr_xwayland *xwayland;
	struct wl_listener x_pronto;
	struct wl_listener x_superficie_nuova;
	struct wl_list sovrapposte;

	// Il canale di controllo, o NULL se non si è aperto. Serve per ANNUNCIARE:
	// i verbi in entrata arrivano già da soli, ma «questa finestra si è
	// aperta» lo sa solo chi sta qui dentro. Vedi `canale_annuncia()`.
	struct canale *canale;

	// Che schermi vuole Minerva. Si legge una volta all'avvio; quando ci sarà
	// il canale di controllo, di qui passerà anche il cambio a caldo.
	struct schermi_config schermi_conf;

	// ── I quattro piani, e perché esistono ───────────────────────────────
	//
	// layer-shell dice che una superficie appoggiata sta su uno di quattro
	// piani, e l'ordine NON è un dettaglio estetico: lo sfondo sta sotto le
	// finestre, la barra sopra, e il blocco schermo sopra tutto. Sbagliarlo
	// vuol dire una barra che sparisce dietro le finestre — difetto già visto
	// in Minerva, e per il quale la scrivania sta a «Layer level 1 (bottom)».
	struct wlr_scene_tree *piano[4];

	// E in mezzo ci stanno le finestre: sopra «bottom», sotto «top». Non è un
	// quinto piano di layer-shell — è il posto che il protocollo lascia
	// libero fra il secondo e il terzo, ed è dove vive tutto il resto.
	struct wlr_scene_tree *finestre;

	// ── Le scrivanie ─────────────────────────────────────────────────────
	//
	// Minerva ne ha dieci, scritte in `config/scorciatoie.minerva`
	// (`$mod 1…0 -> scrivania:`), e una scrivania qui dentro non è una
	// struttura: è un NUMERO su ogni finestra, più questo. Tutto il resto
	// segue — si vede chi ha il numero giusto, e basta.
	//
	// Perché non un albero di scena per scrivania, che sarebbe la strada
	// ovvia: perché l'ordine di sovrapposizione è UNO SOLO
	// (`finestre_elenco`, dalla più in alto), ed è quello che decide chi
	// prende il fuoco quando una si chiude. Dieci alberi vorrebbero dire
	// dieci ordini da tenere allineati a quell'unico elenco, cioè un secondo
	// posto dove la stessa verità può divergere.
	//
	// ── Una per tutta la sessione, non una per schermo ───────────────────
	//
	// Hyprland ne tiene una attiva PER MONITOR. Qui no, e va detto invece di
	// lasciarlo scoprire: cambiare scrivania cambia quello che si vede su
	// tutti gli schermi insieme. Su uno schermo solo le due cose coincidono;
	// il giorno che servirà, questo campo diventa un campo dello schermo e
	// il resto del file non cambia.
	int scrivania_attiva;

	// ── Le scorciatoie ───────────────────────────────────────────────────
	//
	// Novantacinque, e vivono in `config/scorciatoie.minerva` — che è la
	// sorgente unica: da lì escono i tasti di Hyprland, il promemoria di
	// Super+K, e adesso anche queste righe. **Qui dentro non si legge quel
	// file**: due parser per un formato solo sono due parser che un giorno
	// non sono più d'accordo. Il demone lo legge, la shell le manda su questo
	// canale (`scorciatoia …`), e qui restano dei numeri e delle parole.
	//
	// Il tetto è alto il doppio del bisogno: non è un limite, è la garanzia
	// che una riga in più non scriva fuori dall'array.
	struct scorciatoia scorciatoie[SCORCIATOIE_MAX];
	int quante_scorciatoie;

	// ── Come si comportano tastiera, puntatore e touchpad ────────────────
	//
	// Sono scelte dell'utente, e stanno nel pannello «Tastiera e mouse». Il
	// compositore non le legge da nessun file: le manda la shell sul canale,
	// come le scorciatoie e per la stessa ragione — il file delle
	// impostazioni lo legge il demone, e un secondo lettore in C sarebbe un
	// secondo posto che un giorno non è più d'accordo col primo.
	//
	// Si tengono qui perché servono DUE VOLTE: quando arrivano, per
	// applicarle a quello che è già collegato; e quando si collega qualcosa
	// di nuovo, che non c'era quando sono arrivate. Senza questa copia, una
	// tastiera esterna infilata a sessione avviata torna alla disposizione
	// americana — e a scoprirlo si perde molto tempo, perché non è successo
	// niente di visibile.
	struct ingresso {
		char disposizione[64];   // «it», «us»… vuota = quella di sistema
		char variante[64];
		int ritardo_ms;          // 0 = quello di serie
		int ripetizioni_s;
		/// Da −1 a +1, 0 è il neutro. Non è una percentuale.
		double sensibilita;
		bool sensibilita_detta;
		/// −1 = non detto, e allora non si tocca quello che c'è.
		int scorrimento_naturale;
		int tocco_e_clic;
		int spento_mentre_scrivi;
	} ingresso;

	// ── La tinta di tutto lo schermo — la luce notturna ──────────────────
	//
	// NULL vuol dire «nessuna», che è il neutro. Si costruisce una volta e si
	// tiene: la si passa alla scena a ogni fotogramma, e rifarla a ogni
	// fotogramma vorrebbe dire costruire una tabella di 768 numeri sessanta
	// volte al secondo per una tinta che non cambia mai.
	//
	// Vale da sé per gli schermi collegati DOPO, perché non sta sullo
	// schermo: sta sulla strada del disegno.
	struct wlr_color_transform *tinta;

	/// Gli stessi tre numeri, tenuti in chiaro per poterli DIRE. Senza,
	/// `stato` non sa rispondere «che tinta hai addosso», e una cosa che il
	/// compositore fa e non sa raccontare non si può provare da fuori.
	double tinta_rgb[3];

	// I tasti che una scorciatoia si è mangiata. Serve al RILASCIO: se si
	// inghiotte la pressione e si lascia passare il rilascio, il programma
	// sotto vede un tasto che si alza senza essersi mai abbassato — e chi
	// tiene il conto dei tasti premuti (i giochi, gli editor modali) resta a
	// credere che sia ancora giù.
	uint32_t inghiottiti[16];
	int quanti_inghiottiti;

	// ── L'ultimo tasto premuto, per riconoscere un TOCCO ─────────────────
	//
	// Un tocco è «premuto e lasciato da solo»: il gesto con cui Super apre il
	// menù delle applicazioni. Per saperlo al momento del rilascio basta
	// ricordare qual è stato l'ultimo tasto ad abbassarsi: se è ancora lui a
	// rialzarsi, in mezzo non è successo nient'altro.
	//
	// Due righe invece di un conteggio, e reggono i casi storti: Super giù,
	// E giù, E su, Super su — al rilascio di Super l'ultimo premuto è E, e il
	// tocco non scatta, che è precisamente quello che si vuole.
	uint32_t ultimo_premuto;

	/// La superficie su cui si è premuto un pulsante, e dove comincia in
	/// coordinate dello schermo (vedi «la presa implicita» in
	/// `cursore_aggiorna`).
	struct wlr_surface *tenuta;
	double tenuta_x, tenuta_y;

	/// Il «tieni» in corso (vedi `tenuto` in `struct scorciatoia`): quale
	/// tasto, quale scorciatoia, se è già scattato, e il timer dei 400 ms.
	uint32_t tieni_tasto;
	int tieni_quale;
	bool tieni_scattato;
	struct wl_event_source *tieni_timer;

	struct wlr_xdg_decoration_manager_v1 *decorazioni;

	// Le finestre, dalla più in alto alla più in basso. Serve per una cosa
	// che senza elenco non si può fare: quando si chiude quella attiva,
	// dare il fuoco alla successiva invece che al vuoto.
	struct wl_list finestre_elenco;
	struct wl_list appoggiate;
	struct wl_list schermi_elenco;

	struct wlr_seat *seat;
	struct wlr_cursor *cursore;

	/// ── L'ingrandimento sotto il puntatore ──────────────────────────────
	///
	/// 1.0 vuol dire spenta, ed è il valore di serie. Sopra 1, lo schermo
	/// mostra una finestra più piccola ingrandita fino a riempirlo, centrata
	/// dove sta il puntatore.
	///
	/// **Spenta non costa niente**: il disegno prende la strada di sempre,
	/// riga per riga la stessa di ieri. È la garanzia che rende accettabile
	/// una modifica dentro il percorso del disegno — dove uno sbaglio è uno
	/// schermo nero.
	double lente_scala;
	/// «Questo schermo non sa ingrandire» si dice UNA volta, non a sessanta
	/// fotogrammi al secondo.
	bool lente_avvisata;
	struct wlr_xcursor_manager *cursore_tema;

	/// Su quale superficie sta il puntatore ADESSO. Serve a sapere quando
	/// **entra** in una nuova, che è il momento in cui va rimessa la freccia:
	/// vedi `cursore_aggiorna`. NULL = sopra il vuoto o sopra roba nostra.
	struct wlr_surface *superficie_sotto;
	struct wl_list tastiere;
	struct wl_list puntatori;
	struct wl_list interruttori;

	// Chi tiene il conto di quanto tempo è che non tocchi niente. Non spegne
	// niente da sé: **annuncia**, e chi ascolta decide. Lo ascolta il blocco
	// schermo di Minerva.
	//
	// Questo è il protocollo standard (`ext_idle_notifier_v1`), quello che
	// serviva a `hypridle`. Resta acceso perché è roba che un programma
	// qualunque può chiedere — un lettore video, un gioco.
	struct wlr_idle_notifier_v1 *inattivita;

	// ── E la sorveglianza NOSTRA ─────────────────────────────────────
	//
	// Fino al 1º settembre 2026 il mestiere di «dopo tanti minuti spegni lo
	// schermo, dopo tanti altri sospendi» era di `hypridle`: un programma di
	// un altro ambiente, con un suo file di configurazione, che il pannello
	// Energia riscriveva e poi riavviava. Tre cose sbagliate in una: una
	// dipendenza esterna, una seconda sorgente di verità, e una politica
	// scritta in un file che non è nostro.
	//
	// Adesso il compositore fa quello che gli compete — CONTARE — e la
	// politica resta alla shell, esattamente come per il coperchio del
	// portatile. La shell dice quali soglie le interessano:
	//
	//     inattivita 300 600 900     →  ok
	//
	// e il compositore, a ognuna, annuncia:
	//
	//     evento inattivo {"secondi":300}
	//
	// Alla prima cosa toccata dopo che una soglia è scattata:
	//
	//     evento attivo {}
	//
	// ── Perché non si riarma il timer a ogni movimento ────────────────
	//
	// Perché il puntatore si muove centinaia di volte al secondo, e
	// riarmare vuol dire una `timerfd_settime` per movimento. Questo
	// progetto ha già pagato il conto dello svegliarsi per niente — la
	// scansione Wi-Fi ogni dodici secondi, il titolo animato che inchiodava
	// il demone. Perciò l'attività scrive solo un numero
	// (`ultima_attivita_ms`), e il timer, quando scatta, guarda da quanto è
	// che davvero non si tocca niente: se è troppo poco si riarma per il
	// resto e non annuncia niente. Costa un `clock_gettime` per evento —
	// che passa dalla vDSO e non è nemmeno una chiamata di sistema.
	/// Il programma avviato con `argv[1]`, se si è chiesto di uscire quando
	/// finisce (`MINERVA_ESCI_COL_FIGLIO=1`). Vedi il blocco in `main`.
	pid_t figlio_avvio;
	/// Come è finito il programma di avvio: il compositore esce con lo
	/// stesso esito. Chi lo lancia — lo script della schermata di accesso —
	/// deve poter distinguere «si è entrati» da «la schermata è caduta».
	int esito_figlio;

	// ── Il metro della scheda video ─────────────────────────────────────
	//
	// I pixel ridisegnati (`danno`) dicono QUANTO si ridisegna, non quanto
	// costa: un pixel sfocato vale due passate di filtro, uno pieno una
	// copia. Il tempo di disegno lo dà il cronometro di wlroots, che c'era e
	// non usava nessuno. Spento di serie: costa una domanda alla scheda video
	// per fotogramma, e serve solo a chi misura.
	bool metro_gpu;
	uint64_t gpu_ns, gpu_fotogrammi, gpu_persi;

	// ── Il cartello ──────────────────────────────────────────────────
	//
	// Una riga di testo dentro una pillola, in mezzo allo schermo, per un
	// tempo detto. Serve a dire una cosa quando NON C'È PIÙ NESSUNO che
	// possa dirla: se la scrivania muore e il suo guardiano si arrende, non
	// ci sono avvisi, non c'è la barra, non c'è niente — l'unico rimasto in
	// piedi è questo processo.
	//
	// Fino al 1º settembre 2026 quel messaggio lo dava `hyprctl notify`, ed
	// era l'ultimo pezzo della sessione su wlroots che chiamava un programma
	// di Hyprland: sotto di noi non lo dava nessuno, e restava uno schermo
	// nero senza spiegazione.
	struct wlr_scene_tree *piano_cartello;
	struct wlr_scene_buffer *cartello;
	struct wl_event_source *cartello_timer;

	struct wl_event_source *inattivo_timer;
	/// Le soglie chieste dalla shell, in secondi, in ordine crescente.
	int inattivo_soglie[MINERVA_SOGLIE_INATTIVITA];
	int inattivo_quante;
	/// L'indice della prossima soglia che deve scattare.
	int inattivo_prossima;
	/// Vero se almeno una soglia è scattata e non è ancora arrivato
	/// «attivo». Senza, il ritorno all'attività si annuncerebbe a ogni tasto
	/// premuto per tutta la sessione.
	bool inattivo_annunciato;
	/// Il momento dell'ultima cosa toccata, in millisecondi monotoni.
	uint64_t ultima_attivita_ms;
	/// Quanti programmi hanno chiesto «non spegnere lo schermo adesso».
	/// Un video a schermo intero è il caso per cui il protocollo esiste.
	int inibitori;
	struct wl_listener inibitore_nuovo;

	// ── Il blocco schermo ────────────────────────────────────────────
	//
	// `serratura` è il client che ha preso lo schermo, o NULL. `bloccato`
	// è un'altra cosa e va tenuta separata: resta VERO anche se il client
	// muore, ed è tutta la sicurezza del protocollo — se bastasse
	// uccidere il processo del blocco per rientrare, un blocco schermo non
	// servirebbe a niente.
	struct wlr_session_lock_v1 *serratura;
	bool bloccato;
	/// Il puntatore è al bordo alto di uno schermo con una finestra a schermo
	/// intero, ed è già stato detto. Vedi `bordo_alto_guarda`.
	bool bordo_alto_detto;
	/// La sosta sul bordo alto sopra uno schermo intero (vedi
	/// `bordo_alto_guarda`): il timer, e lo schermo su cui è cominciata.
	struct wl_event_source *bordo_alto_timer;
	char bordo_alto_schermo[64];
	/// Gli angoli attivi (vedi `angolo_guarda`): in quale angolo è il
	/// puntatore adesso (NULL se in nessuno), su quale schermo, se è già stato
	/// detto, e il timer della sosta.
	const char *angolo_ora;
	char angolo_schermo[64];
	bool angolo_detto;
	struct wl_event_source *angolo_timer;
	/// La spinta contro il bordo destro (vedi `bordo_spinto`): quanti pixel
	/// il puntatore ha provato ad andare oltre, e quando l'ultima volta.
	double spinta;
	uint32_t spinta_quando;
	bool spinta_detta;
	/// Da che parte si spinge: -1 a sinistra, +1 a destra, 0 nessuna.
	int spinta_lato;
	/// La riva riservata chiede Super (vero di serie). Il verbo `riva
	/// sempre` lo spegne: angoli e bordi rispondono anche sopra una finestra
	/// che riempie lo schermo. Lo sceglie Impostazioni › La Riva.
	bool riva_col_consenso;
	/// Se il «locked» è già partito. wlroots lo consente **una volta sola**
	/// per serratura, e chiamarlo due volte non è un errore da gestire: è un
	/// assert che porta giù il compositore, cioè tutto lo schermo. Preso
	/// così, alla prima prova: la seconda commit della superficie del blocco
	/// arrivava un istante dopo la prima e spegneva la sessione annidata.
	bool locked_inviato;
	struct wlr_scene_tree *piano_blocco;
	/// Il rettangolo nero sotto le superfici del blocco: si vede quando il
	/// client del blocco è morto e non c'è più niente da disegnare.
	struct wlr_scene_rect *tenda;
	struct wl_listener serratura_nuova;
	struct wl_listener serratura_superficie;
	struct wl_listener serratura_sblocca;
	struct wl_listener serratura_morta;

	struct wl_listener schermo_nuovo;
	struct wl_listener finestra_nuova;
	struct wl_listener menu_nuovo;
	struct wl_listener appoggiata_nuova;
	struct wl_listener dispositivo_nuovo;
	struct wl_listener cursore_mosso;
	struct wl_listener cursore_assoluto;
	struct wl_listener cursore_premuto;
	struct wl_listener cursore_rotella;
	struct wl_listener cursore_frame;
	struct wl_listener cursore_richiesto;
	struct wl_listener forma_richiesta;
	/// `MINERVA_TRACCIA_FORMA=1`: scrive nel registro ogni forma chiesta.
	bool traccia_forma;
	/// `MINERVA_TRACCIA_PULSANTI=1`: scrive ogni tasto del mouse, quello che
	/// arriva dal dispositivo e quello che si consegna al programma. Serve a
	/// dividere in due il campo quando un tasto «vale per un altro»: o lo
	/// sbagliamo noi, o lo interpreta male chi lo riceve.
	bool traccia_pulsanti;
	/// `MINERVA_TRACCIA_MENU=1`: dice quando arriva un menù e se si trova
	/// dove appenderlo. Un menù che non compare non lascia altra traccia.
	bool traccia_menu;
	/// `MINERVA_TRACCIA_TRASCINA=1`: dice se una richiesta di trascinamento
	/// arriva, e se il numero di serie del clic regge. Un trascinamento che
	/// non parte non lascia nessun'altra traccia — la sorgente viene
	/// distrutta e il programma non lo sa.
	bool traccia_trascina;
	struct wl_listener decorazione_nuova;

	// ── Gli appunti, la selezione primaria e il trascinamento ────────────
	//
	// `wlr_data_device_manager_create` da solo non copia niente: apre il
	// protocollo, e poi il seat CHIEDE il permesso a ogni copia. Senza questi
	// tre ascoltatori il compositore riceveva la domanda e non rispondeva —
	// «Ctrl+C» non dava nessun errore e non copiava nulla, in ogni programma,
	// e `wl-paste` diceva «Nothing is copied». Trovato il 1º settembre 2026
	// perché Giacomo non riusciva a incollare un comando nel terminale.
	struct wl_listener selezione_richiesta;
	struct wl_listener selezione_primaria_richiesta;
	struct wl_listener trascinamento_richiesto;
	struct wl_listener trascinamento_partito;
	struct wl_listener trascinamento_finito;
	/// Il piano su cui vive l'icona che segue il dito durante un
	/// trascinamento fra due finestre. Sopra tutto tranne il blocco schermo.
	struct wlr_scene_tree *piano_trascinamento;
	/// Le finestre a schermo intero: sopra i pannelli (TOP), sotto le
	/// notifiche e gli avvisi (OVERLAY). Vedi `finestra_schermo_intero`.
	struct wlr_scene_tree *piano_intero;
	/// L'icona in volo, se ce n'è una. NULL quando non si sta trascinando.
	struct wlr_scene_tree *icona_trascinata;

	// ── La presa in corso ────────────────────────────────────────────────
	//
	// Di mani ce n'è una: la presa è una sola per tutto il compositore, non
	// una per finestra. È la stessa conclusione a cui era arrivato il plugin
	// dopo quattro tentativi — con la differenza che lì il movimento del
	// puntatore a una decorazione non arrivava proprio, e qui arriva perché
	// il puntatore è nostro.
	enum {
		PRESA_NIENTE = 0,
		PRESA_SPOSTA,
		PRESA_RIDIMENSIONA,
	} presa;
	struct finestra *presa_di;
	/// Dove stava il puntatore quando si è premuto, e dov'era la finestra.
	double presa_x, presa_y;
	struct wlr_box presa_box;
	uint32_t presa_bordi;
	/// Il pulsante premuto (-1 nessuno) e se la mano si è mossa abbastanza
	/// perché sia un trascinamento e non un clic.
	int presa_pulsante;
	bool presa_mossa;
	/// Quando e dove si è concluso il clic precedente. «Doppio» non ce lo
	/// dice nessuno: è una cosa che si decide qui.
	uint32_t ultimo_clic;
	double ultimo_clic_x, ultimo_clic_y;

	// ── Le app che la barra se la disegnano da sé ────────────────────────
	//
	// Pezzi di nome cercati dentro la classe della finestra: `firefox`,
	// `org.gnome.`, `chromium`. La lista NON è cablata qui — la manda la shell
	// col verbo `csd`, perché la stessa lista sta in `settings.json` sotto
	// `windows.csdApps` ed è modificabile dal pannello Impostazioni.
	//
	// Prima era scritta in tutti e due i posti. Due copie della stessa lista
	// sono due liste che un giorno non sono più d'accordo: si aggiungeva un
	// programma dal pannello e non succedeva niente, senza nessun errore.
	//
	// Fino al primo `csd` che arriva vale quella di riserva, messa in
	// `main()`: una sessione che parte prima della shell non deve mettere due
	// barre a Firefox per i primi due secondi.
	char csd[32][64];
	int quanti_csd;

	/// Il rettangolo traslucido che mostra dove finirà la finestra agganciata,
	/// e la zona che sta indicando adesso. Spento quando non si trascina.
	struct wlr_scene_rect *aggancio_ombra;
	enum zona_aggancio aggancio_ora;

	/// Quanta rotellina si è girata con Super premuto, non ancora spesa.
	///
	/// Due contatori e non uno: i mouse mandano 120esimi di tacca
	/// (`delta_discrete`), i touchpad no e mandano solo `delta`. Mescolarli
	/// vorrebbe dire che lo stesso gesto conta il doppio su un dispositivo e
	/// la metà sull'altro.
	int32_t rotella_v120;
	double rotella_libera;

	// ── La cornice attorno alla finestra attiva ──────────────────────────
	//
	// Giacomo, 3 settembre 2026: «se voglio che il colore intorno diventi tipo
	// rgb e cambi colore costantemente oppure che giri sempre come una
	// striscia led?».
	//
	// Non serve disegnare niente di nuovo: attorno a ogni finestra c'è già un
	// anello di sei pixel, la `maniglia`, che esiste per poterla prendere e
	// ridimensionare. È un `wlr_scene_rect` trasparente sotto a tutto il
	// resto. Colorarlo è una chiamata, e cambiargli colore non ridisegna
	// nessun buffer: si sposta un colore e si sporca un anello sottile.
	//
	// Era l'alternativa a ricolorare la BARRA a ogni fotogramma, che vuol dire
	// rifare un buffer cairo per finestra venti volte al secondo. Su un
	// portatile la differenza non è di stile.
	//
	// Solo la finestra ATTIVA si accende. Un arcobaleno attorno a otto
	// finestre insieme non è un effetto, è una fiera — e sarebbero otto
	// rettangoli da sporcare invece di uno.
	enum { CORNICE_SPENTA, CORNICE_FISSA, CORNICE_GIRA,
	       CORNICE_STRISCIA } cornice_modo;
	float cornice_r, cornice_g, cornice_b;

	// ── I colori che si alternano ───────────────────────────────────────
	//
	// Giacomo, 9 settembre 2026: «vorrei anche l'effetto rgb come una strip
	// led e possibilità di scegliere i colori che si alterneranno».
	//
	// Zero colori vuol dire lo SPETTRO intero, che è come la cornice è nata e
	// resta il ripiego: chi non sceglie niente vede l'arcobaleno. Da uno in
	// su, il giro passa per quei colori e per nessun altro — con uno solo si
	// ottiene una striscia di un colore che scorre, che è una cosa che si può
	// volere.
	float cornice_tinte[8][3];
	int cornice_quante_tinte;

	/// Quanto è accesa la cornice sulle finestre che NON hanno il fuoco.
	///
	/// Zero — come nasce — vuol dire che si accende solo quella attiva, e c'è
	/// una ragione scritta: un arcobaleno attorno a otto finestre insieme non
	/// è un effetto, è una fiera, e soprattutto la cornice serve a dire
	/// «questa è quella attiva». Se sono accese tutte non dice più niente.
	///
	/// Giacomo l'ha chiesta lo stesso, e ha ragione a poterla volere: con una
	/// velatura bassa il bordo diventa il contorno di ogni finestra invece
	/// che un cartellino, ed è un altro modo di guardare la scrivania. Sopra
	/// 0,6 però la finestra attiva smette di distinguersi, e lì ci si ferma.
	double cornice_spente;
	/// Quanto è spesso l'anello, in pixel.
	///
	/// Era `BORDO_PRESA`, cioè lo stesso numero della presa per
	/// ridimensionare — che è una misura per le DITA e non per gli occhi.
	/// Legarli insieme voleva dire che ingrossare il bordo ingrossava anche
	/// la zona in cui il clic non arriva più al programma.
	///
	/// Adesso sono due cose: la presa resta sei pixel sempre, questo si
	/// sceglie. La zona presa segue il più grande dei due, o un anello grosso
	/// avrebbe una parte non afferrabile.
	int cornice_spessore;
	/// Millisecondi per un giro intero dello spettro.
	int cornice_periodo;
	/// Dove siamo del giro, da 0 a 1.
	double cornice_fase;
	struct wl_event_source *cornice_timer;

	// ── L'elastico delle finestre ────────────────────────────────────────
	//
	// `elastico` è la forza: 0 spento, 1 normale, fino a 3. Vale il
	// contrario di quel che sembra — più forza vuol dire molla più morbida,
	// quindi più ritardo e più rimbalzo — ed è così perché è quello che uno
	// si aspetta girando un cursore chiamato «quanto tremano le finestre».
	//
	// Il battito esiste solo mentre qualcosa si muove: parte con la presa e
	// si spegne da solo quando l'ultima finestra si è posata. A scrivania
	// ferma non c'è nessun timer in piedi, ed è la stessa disciplina della
	// cornice che gira.
	double elastico;
	double rigidita, smorzamento;
	unsigned molle_attive;

	// ── L'effetto sulle finestre: un corpo solo ─────────────────────────
	//
	// Giacomo, 2 settembre 2026: «non abbiamo il blur e ci vorrebbero delle
	// impostazioni per mettere nessun effetto o blur o vetro [...] e in blur
	// o vetro dovrebbero far vedere un solo corpo trasparente o blur come un
	// unico corpo la barra e la finestra senza stacchi».
	//
	// Prima di oggi la trasparenza era in tre posti che non si parlavano:
	// la barra se la disegnava (0,90 a fuoco), le finestre NOSTRE se la
	// mettevano in QML (`shell.windowOpacity`, 0,88), e quelle degli altri
	// programmi erano opache. Tre dialetti sulla stessa scrivania, ed è
	// quello che si vedeva.
	//
	/// `nessuno` — mantiene l'opacità fornita dai client.
	/// `vetro` — aggiunge trasparenza alla finestra, salvo a schermo intero.
	/// `blur` — sfoca dietro le zone trasparenti senza sbiadire il contenuto.
	/// Il blur gaussiano c'era fra VETRO e ACQUERELLO: tolto il 28 settembre
	/// 2026, l'acquerello è l'unico filtro.
	enum { EFFETTO_NESSUNO, EFFETTO_VETRO, EFFETTO_ACQUERELLO } effetto_modo;
	/// Quanto è opaca una finestra col vetro acceso, da 0 a 1.
	float effetto_alfa;

	// ── Il modo risparmio ────────────────────────────────────────────────
	//
	// A batteria bassa gli effetti scendono di un gradino e si rialzano da
	// soli quando torna la corrente: niente blur né trasparenza, la cornice
	// che gira si ferma, l'elastico si spegne. Lo decide il compositore (il
	// perché sta in `energia.h`).
	//
	// Per farlo senza perdere niente, di ogni effetto ce ne sono DUE:
	// quello CHIESTO (`voluto_*`, lo scrivono i verbi) e quello DISEGNATO
	// (`effetto_modo`, `cornice_modo`, `elastico`, che leggono tutti gli
	// altri). Fuori dal risparmio coincidono. Dentro, il disegnato scende e
	// il chiesto resta com'era — così all'uscita si torna esattamente lì, e
	// chi cambia un effetto a batteria bassa non scrive sopra il gradino.
	struct energia *energia;
	enum { RISPARMIO_MAI, RISPARMIO_AUTO, RISPARMIO_SEMPRE } risparmio_modo;
	/// La percentuale sotto cui «auto» comincia a risparmiare.
	int risparmio_soglia;
	bool risparmio_attivo;
	/// Il respiro delle finestre acceso (verbo `respiro si|no`), e quanti
	/// respiri sono in corso: a riposo nessun battito.
	bool respiro_acceso;
	int respiri_attivi;
	/// Quanti passi di respiro sono stati disegnati da quando è partito: dice
	/// alle prove se l'animazione avanza davvero fotogramma per fotogramma.
	unsigned respiro_passi;
	/// Mercurio (verbo `mercurio si|no`): le finestre vicine che si fondono
	/// come gocce. Due nodi per ponte — il filtro sotto e la tinta sopra — in
	/// un piano sotto tutte le finestre; `ponti` è quanti se ne disegnano
	/// adesso. Vedi `mercurio_aggiorna` e src/mercurio.h.
	bool mercurio_acceso;
	/// Le copie delle finestre appena chiuse, che si ritirano per un respiro
	/// (vedi `respiro_chiusura`). Vuota a riposo: nessun battito.
	struct wl_list fantasmi;
	int fantasmi_vivi;
	struct wlr_scene_tree *piano_mercurio;
	struct { struct wlr_scene_rect *filtro, *tinta; } ponte_nodi[12];
	int ponti;
	/// «batteria», «profilo», «chiesto», o NULL. Sempre una stringa fissa.
	const char *risparmio_motivo;
	int voluto_effetto, voluto_cornice;
	double voluto_elastico;
};

// Chi possiede un nodo della scena.
//
// Serve per una domanda sola, che però si fa a ogni clic: «sotto il puntatore
// c'è una finestra o un pannello di Minerva?». I due si trattano in modo
// diverso — una finestra si alza in cima e si accende, un pannello no — e
// senza un marchio l'unico modo di distinguerli sarebbe indovinare.
enum tipo_nodo {
	NODO_FINESTRA,
	NODO_APPOGGIATA,
	NODO_SOVRAPPOSTA,
};

struct tastiera {
	struct wl_list link;
	struct minerva *m;
	struct wlr_keyboard *kb;

	struct wl_listener tasto;
	struct wl_listener modificatori;
	struct wl_listener distrutta;
};

// ── E i puntatori, che prima non si tenevano ─────────────────────────────
//
// Il puntatore si attaccava al cursore e si lasciava andare: bastava, finché
// nessuno doveva RICONFIGURARLO. Adesso sì — scorrimento naturale, tocco per
// cliccare, velocità — e per riconfigurarli bisogna sapere quali sono.
//
// Il `dev` e non il `wlr_pointer`: le manopole stanno su libinput, e a
// libinput ci si arriva dal dispositivo.
struct puntatore {
	struct wl_list link;
	struct minerva *m;
	struct wlr_input_device *dev;

	struct wl_listener distrutto;
};

struct appoggiata {
	enum tipo_nodo tipo;
	struct wl_list link;
	struct minerva *m;
	struct wlr_layer_surface_v1 *ls;
	struct wlr_scene_layer_surface_v1 *scena;
	struct wlr_output *out;

	/// Il fondo sfocato di questo pannello. Vedi `appoggiata_sfocatura`.
	struct wlr_scene_rect *sfocatura;

	/// Se all'ultima commit era mostrata: quando cambia, cambia anche cosa c'è
	/// sotto il puntatore (vedi `puntatore_ricalcola`).
	bool mappata;

	struct wl_listener commit;
	struct wl_listener distrutta;
};

// ── Le finestre X11 che dicono «non toccarmi» ────────────────────────────
//
// In X11 un menù a tendina, un suggerimento, l'icona che segue il dito
// mentre si trascina sono FINESTRE come le altre, e si distinguono da una
// finestra vera per un flag solo: `override_redirect`. Vuol dire «il gestore
// non mi tocchi»: niente barra del titolo, niente posto nell'elenco, niente
// scrivania, niente giro del fuoco. Le mette il programma esattamente dove
// vuole lui, e il compositore le disegna e basta.
//
// ── Perché una struttura a parte e non un flag su «finestra» ─────────────
//
// Perché un flag avrebbe voluto dire un `if` in dodici posti — l'elenco, gli
// annunci, il fuoco, le scrivanie, la presa, la barra — e un `if` dimenticato
// è un menù di Steam che compare nella dock come se fosse un programma, o che
// si porta via il fuoco e non lo restituisce. Sessanta righe separate costano
// meno di dodici rami da ricordare.
struct sovrapposta {
	enum tipo_nodo tipo;
	struct wl_list link;
	struct minerva *m;
	struct wlr_xwayland_surface *xsup;
	/// Esiste solo da mappata a smappata: un menù che si chiude non muore,
	/// si smappa, e ricompare identico al clic dopo.
	struct wlr_scene_tree *albero;

	struct wl_listener associa;
	struct wl_listener dissocia;
	struct wl_listener mappata;
	struct wl_listener smappata;
	struct wl_listener distrutta;
	struct wl_listener spostata;
};

struct schermo {
	/// Il cronometro del disegno, acceso solo quando si misura (verbo
	/// `gpu`). Si legge al fotogramma DOPO: prima la scheda video non ha
	/// ancora finito, e wlroots lo segnala come errore.
	struct wlr_scene_timer cronometro;
	bool blocco_presentato, blocco_attesa;
	uint32_t blocco_seq;
	struct wl_listener present, output_commit;
	struct wl_list link;
	struct minerva *m;
	struct wlr_output *out;
	struct wl_event_source *prova_timer;
	struct wlr_output_state prima_prova;
	struct wlr_box prima_posizione;
	char prova_id[80];

	/// Lo spazio che resta tolte le barre e le dock. È il numero che decide
	/// dove può nascere una finestra e quanto è grande da ingrandita: la
	/// barra si prende quarantadue pixel in cima, e quelli non sono più
	/// spazio per nessun altro.
	struct wlr_box utile;

	struct wl_listener frame;
	struct wl_listener distrutto;

	/// Per che strada passa la luce notturna su QUESTO schermo.
	///
	///     0  non ancora provata
	///     1  la tabella la prende lo SCHERMO (la strada che funziona)
	///     2  questo schermo non la prende: la luce notturna non si vedrà
	///
	/// Si decide una volta sola, con un `wlr_output_test_state`: provarlo a
	/// ogni fotogramma vorrebbe dire chiedere al kernel sessanta volte al
	/// secondo una risposta che non cambia mai.
	int tinta_strada;
};

/// Di che razza è una finestra.
///
/// ── Perché esiste questo campo ───────────────────────────────────────────
///
/// Perché XWayland non parla xdg-shell. Un programma X11 — Steam, i giochi,
/// una parte di quelli vecchi — arriva come `wlr_xwayland_surface`, che ha i
/// suoi eventi, le sue misure e il suo modo di dire «chiuditi». Tutto il resto
/// di questo file però non deve saperlo: una finestra si sposta, prende il
/// fuoco, si riduce a icona e sta su una scrivania allo stesso modo.
///
/// Da qui in poi la regola è: **fuori dalle funzioni `finestra_*` non si
/// scrive mai `f->toplevel`**. Chi lo fa sta scrivendo codice che con Steam
/// non funzionerà, e non se ne accorgerà finché non lo prova.
enum razza_finestra {
	FINESTRA_XDG,
	FINESTRA_X11,
};

struct finestra {
	enum tipo_nodo tipo;
	struct wl_list link;
	struct minerva *m;
	enum razza_finestra razza;
	/// Uno dei due è NULL, sempre, e quale lo dice `razza`. Non si guarda mai
	/// il puntatore per indovinare la razza: si guarda `razza`.
	struct wlr_xdg_toplevel *toplevel;
	struct wlr_xwayland_surface *xsup;

	// ── Tre nodi, e perché non uno ───────────────────────────────────────
	//
	// `cornice` è la finestra INTERA, barra compresa: è questo che si sposta
	// quando si trascina, ed è il motivo per cui la barra non ha niente da
	// inseguire. Dentro ci sono la barra in cima e il programma sotto.
	struct wlr_scene_tree *cornice;
	/// Un rettangolo trasparente sei pixel più grande della finestra: è la
	/// presa per ridimensionarla. Invisibile ma cliccabile — senza un nodo
	/// non c'è niente su cui il puntatore possa cadere, e il bordo di una
	/// finestra è dove tutti provano a prenderla.
	struct wlr_scene_rect *maniglia;

	/// ── Il fondo sfocato ─────────────────────────────────────────────
	///
	/// Un nodo che sfoca quello che sta DIETRO, messo sotto la finestra e
	/// grande quanto lei. Non tocca la finestra: quella resta traslucida
	/// com'era, e cambia ciò che si vede attraverso.
	///
	/// È lo stesso mestiere del blur di COSMIC — un dual-kawase, non una
	/// gaussiana vera — e lo fa SceneFX con gli stessi shader di famiglia.
	struct wlr_scene_rect *sfocatura;

	/// L'anello che si VEDE: un rettangolo col BUCO, grande quanto la
	/// finestra più sei pixel per lato.
	///
	/// ── Tre versioni, e perché questa ─────────────────────────────────
	///
	/// 1. Fino al 7 settembre 2026 il colore lo portava la `maniglia`, che è
	///    un rettangolo PIENO grande quanto la finestra. Sotto una finestra
	///    opaca se ne vedono solo i bordi, ed era l'effetto voluto; sotto una
	///    TRASLUCIDA traspare da tutta la superficie. L'Alacritty di Giacomo
	///    sta a `opacity = 0.85`, e a ogni cambio di fuoco la finestra si
	///    tingeva per intero — misurato: da (54, 84, 98) a (50, 114, 131).
	/// 2. Allora quattro strisce sottili, una per lato. Ha retto finché gli
	///    angoli erano quadrati. Con gli angoli tondi no: la finestra si
	///    arrotonda e le strisce restano squadrate, e si vede. Giacomo, alla
	///    prima fotografia: «la vedo arrotondata sopra ma la linea celeste
	///    intorno no».
	/// 3. Adesso uno solo, con dentro un buco della forma esatta della
	///    finestra — `wlr_minerva_rect_set_hole`. Il buco è la
	///    ragione per cui questo non è un ritorno al punto 1: dentro non c'è
	///    colore, quindi non traspare niente.
	///
	/// La maniglia resta, e resta trasparente: il suo mestiere è ricevere i
	/// clic sul bordo, non dipingere.
	struct wlr_scene_rect *anello;
	struct wlr_scene_buffer *barra;
	struct wlr_scene_tree *albero;

	/// Falso per chi la barra se la disegna da solo (Chrome, Firefox) e per
	/// le finestre di Minerva, che ce l'hanno già nel QML.
	bool decorata;
	// ── «È mai comparsa?», e perché è una domanda che nasce con X11 ──────
	//
	// Una finestra Wayland esiste per essere mostrata. Una finestra X11 no:
	// Qt ne crea due per ogni programma — una 1×1 e una 3×3, senza titolo e
	// senza classe — che servono al copia-e-incolla e ai metodi di input, e
	// che non sono mappate mai. Sono finestre a tutti gli effetti, e senza
	// questo campo finivano nell'elenco: due voci fantasma nella dock per
	// ogni programma X11, e due annunci di chiusura per qualcosa che non si
	// era mai aperto.
	//
	// Misurato con KCalc su xcb il 26 agosto 2026: tre finestre nell'elenco,
	// una sola vera.
	bool comparsa;
	/// È mappata ADESSO? Diverso da `comparsa`, che dice «almeno una volta»
	/// e non torna mai indietro. Un programma può nascondere una finestra
	/// invece di chiuderla, e in quel momento della cornice resterebbe la
	/// sola BARRA: il fantasma di sempre, per l'altra strada.
	///
	/// Per le X11 la stessa cosa la diceva `albero == NULL`. Per una xdg no:
	/// lì l'albero è appeso alla superficie e non diventa mai nullo, quindi
	/// serviva dirlo esplicitamente.
	bool mappata_ora;
	bool ingrandita;
	/// Agganciata a una metà o a un quarto di schermo. Non è «ingrandita» —
	/// il pulsante direbbe il falso — ma si comporta come lei in una cosa:
	/// trascinandola deve tornare della misura di prima.
	bool agganciata;
	bool ridotta;
	bool schermo_intero;
	/// Su quale scrivania sta, da 1 a SCRIVANIE. Una finestra sta sempre su
	/// una sola: nasce su quella in uso quando è nata, e ci resta finché
	/// qualcuno non la manda altrove.
	int scrivania;
	/// Dov'era prima di ingrandirsi, per saperci tornare.
	struct wlr_box prima;

	// ── L'elastico ───────────────────────────────────────────────────────
	//
	// Dove sta la finestra e dove si sta DISEGNANDO sono due cose diverse
	// mentre la trascini: la seconda insegue la prima con una molla, resta
	// un po' indietro, e al rilascio supera e si posa. La fisica sta in
	// `src/molla.c`, fuori da wlroots perché si possa provare a numeri.
	//
	// `posto_x/y` rimane la geometria logica. Solo la superficie disegnata
	// si deforma: aggancio, coordinate dei client e disposizione non cambiano.
	struct molla molla;
	struct wobbly *wobbly;
	/// La copia fatta quando si è chiesto di chiuderla, che aspetta lo
	/// smappamento per ritirarsi (vedi `chiusura_chiesta`). NULL di solito.
	struct fantasma *fantasma_pronto;
	double wobbly_presa_x, wobbly_presa_y;
	struct timespec molla_ultimo;
	bool wobbly_fallita;
	int molla_dx, molla_dy;
	/// Il respiro (vedi `respiro_avvia`): la finestra che nasce, che viene
	/// risucchiata riducendola, che torna. RESPIRO_NIENTE a riposo.
	int respiro;
	struct timespec respiro_t0;
	int posto_x, posto_y;

	/// Quale pulsante sta sotto il puntatore adesso: -1 nessuno.
	int sotto_il_dito;
	/// Quello che la barra mostra ADESSO. Serve a non ridisegnarla uguale:
	/// un programma può cambiare titolo a ogni tasto premuto, e ogni
	/// ridisegno è una superficie cairo nuova.
	char *titolo_disegnato;
	int larghezza_disegnata;
	bool fuoco_disegnato;
	bool ingrandita_disegnata;
	int dito_disegnato;

	/// La richiesta «chi disegna la cornice?», se il programma l'ha fatta.
	/// Si tiene perché la risposta NON si può dare quando arriva: vedi
	/// `decorazione_applica`.
	struct wlr_xdg_toplevel_decoration_v1 *decorazione;

	struct wl_listener commit;
	struct wl_listener mappata;
	struct wl_listener smappata;
	struct wl_listener distrutta;
	struct wl_listener titolo_cambiato;
	struct wl_listener chiede_sposta;
	struct wl_listener chiede_ridimensiona;
	struct wl_listener chiede_ingrandisci;
	struct wl_listener chiede_schermo;
	struct wl_listener chiede_riduci;
	struct wl_listener decorazione_modo;
	struct wl_listener decorazione_via;

	// ── Solo X11 ─────────────────────────────────────────────────────────
	//
	// Una finestra X11 nasce SENZA superficie: esiste come finestra del
	// server X prima che ci sia qualcosa da disegnare, e la superficie
	// Wayland le viene «associata» dopo — e può andarsene e tornare senza
	// che la finestra muoia. È la differenza che rende impossibile fare
	// tutto alla nascita come per le xdg.
	/// Solo X11: il programma ha detto «non decorarmi» (gli splash, i giochi
	/// a schermo intero), oppure ha dichiarato di non essere una finestra
	/// normale. Vale più della classe.
	bool x11_senza_cornice;
	/// Il programma ha CHIESTO di disegnarsi la barra da sé, via
	/// `xdg-decoration`.
	///
	/// Vale più di qualunque lista di nomi, e per una ragione che le liste non
	/// possono avere: è il programma stesso a dirlo, quindi vale anche per
	/// quelli che non conosciamo e che non conosceremo mai. Senza questa riga,
	/// chi si disegna la sua barra e non è nell'elenco dei CSD **ne prendeva
	/// due** — è la segnalazione «finestre con barra del titolo doppiate» del
	/// 30 agosto 2026.
	bool csd_richiesto;

	struct wl_listener x_associa;
	struct wl_listener x_dissocia;
	struct wl_listener x_configura;
	struct wl_listener x_attiva;

	// ── I pezzi della striscia LED ──────────────────────────────────────
	//
	// L'anello normale è UN rettangolo tondo col buco, e un rettangolo ha un
	// colore solo: va benissimo per una cornice che sta ferma o che cambia
	// tinta tutta insieme, e non può fare una striscia in cui i colori si
	// rincorrono lungo il bordo.
	//
	// La striscia è fatta di pezzi, e la forma di ognuno è scelta perché gli
	// angoli restino TONDI:
	//
	//   · quattro GOMITI, uno per angolo. Ognuno è un rettangolo con il
	//     raggio solo sul suo angolo di fuori e un buco con il raggio solo
	//     sul suo angolo di dentro — cioè esattamente un quarto dell'anello.
	//   · sei SEGMENTI per lato, rettangoli lisci, sui tratti dritti.
	//
	// L'alternativa era ridisegnare un'immagine dell'anello a ogni battito
	// con cairo. Sarebbe stata più bella (un vero sfumato invece di
	// ventiquattro gradini) e avrebbe voluto dire ridipingere e ricaricare
	// una texture dodici volte al secondo, per sempre, su un portatile.
	// Ventotto rettangoli a cui si cambia il colore non costano niente.
	struct wlr_scene_buffer *led[ANELLO_PEZZI];
};

/// Quanto largo è il bordo con cui si prende una finestra per
/// ridimensionarla. Sei pixel: meno non si prende col mouse, di più si ruba il
/// clic al programma proprio sul bordo del suo contenuto.
#define BORDO_PRESA 6

// ── Il raggio degli angoli ───────────────────────────────────────────────
//
// Lo stesso di `Theme.Effects.radiusWindow` nella shell. Due numeri vicini
// sono peggio di due numeri diversi: se cambia là, cambia qui.
//
// Sta accanto a `BORDO_PRESA` perché i due si usano insieme: l'anello di sei
// pixel intorno alla finestra ha gli angoli più aperti di sei, o il bordo si
// assottiglierebbe proprio sulla curva.
#define ANGOLO_RAGGIO 10

static void fuoco_finestra(struct minerva *m, struct finestra *f);
static void barra_aggiorna(struct finestra *f);
/// La trasparenza del «corpo unico», su tutto l'albero della finestra.
/// Definita più sotto: la chiama anche `barra_aggiorna`, che le sta sopra.
static void finestra_effetto(struct finestra *f);
static void finestra_angoli(struct finestra *f);
static void appoggiata_sfocatura(struct appoggiata *a);
static void cornici_ridipingi(struct minerva *m);
static void finestra_posiziona(struct finestra *f, int x, int y, int w, int h);
static void molla_ferma_finestra(struct finestra *f);
static int effetto_disegnato(struct minerva *m);
static int cornice_disegnata(struct minerva *m);
static double elastico_disegnato(struct minerva *m);
static void effetto_imposta(struct minerva *m, int modo);
static void cornice_imposta(struct minerva *m, int modo);
static void elastico_imposta(struct minerva *m, double forza);
static void energia_cambiata(void *dati);
static int risparmio_json(struct minerva *m, char *buf, size_t n);
static void molla_avvia(struct finestra *f);
static void disponi(struct minerva *m, struct wlr_output *out);
static void annuncia(struct minerva *m, const char *che, struct finestra *f);
static bool finestra_visibile(struct finestra *f);
static void freno_aggiorna(struct minerva *m);
static bool schermo_intero_visibile(struct minerva *m);
static pid_t finestra_pid(struct finestra *f);
// Il confine fra «finestra» e «xdg-shell». Vedi il blocco che le definisce.
static struct wlr_surface *finestra_superficie(struct finestra *f);
static void finestra_geometria(struct finestra *f, int *w, int *h);
static const char *finestra_titolo(struct finestra *f);
static const char *finestra_classe(struct finestra *f);
static void finestra_di_attiva(struct finestra *f, bool si);
static void finestra_di_geometria(struct finestra *f, int x, int y, int w, int h);
static void finestra_di_ingrandita(struct finestra *f, bool si);
static void finestra_di_ridotta(struct finestra *f, bool si);
static bool finestra_ha_genitore(struct finestra *f);
static bool finestra_vuole_pieno(struct finestra *f);
static bool finestra_vuole_ingrandita(struct finestra *f);
static void finestra_massimo(struct finestra *f, int *w, int *h);
static void finestra_di_schermo_intero(struct finestra *f, bool si);
static void finestra_di_chiuditi(struct finestra *f);
static struct finestra *finestra_attiva(struct minerva *m);
static bool scrivania_vai_ex(struct minerva *m, int quale, bool prendi_il_fuoco);
static void annuncia_scrivania(struct minerva *m);
static void annuncia_schermi(struct minerva *m);
static void monitor_transaction_removed(struct minerva *, struct wlr_output *);
static void monitor_layout_refresh(struct minerva *);
static void monitor_recover(void *);
static void annuncia_blocco(struct minerva *m);
static void blocco_verifica_presentazione(struct minerva *m);
static int sospendi_scaduta(void *data);
enum { RESPIRO_NIENTE, RESPIRO_NASCITA, RESPIRO_RISUCCHIO, RESPIRO_RITORNO };
static void molla_fotogramma(struct minerva *m, struct wlr_output *out);
static void respiro_fotogramma(struct minerva *m, struct wlr_output *out);
static bool respiro_avvia(struct finestra *f, int tipo);
static void respiro_fine(struct finestra *f);
static void mercurio_aggiorna(struct minerva *m);
static void respiro_chiusura(struct finestra *f);
static void chiusura_chiesta(struct finestra *f);
struct fantasma;
static void fantasma_scarta(struct fantasma *g);
static void fantasmi_fotogramma(struct minerva *m);
static void proteggi_sonno(void *data);

// ── Il fuoco ──────────────────────────────────────────────────────────────
//
// «Fuoco» qui vuol dire una cosa sola e precisa: a chi arrivano i tasti. Non
// il bordo colorato, non l'ombra — quelli sono conseguenze che la shell
// disegna da sé. Wayland ne ha due separati, tastiera e puntatore, e vanno
// tenuti distinti: il puntatore segue la mano da solo, la tastiera no.

static void *nodo_proprietario(struct wlr_scene_node *n, enum tipo_nodo *fuori) {
	// I nodi di una superficie sono annidati (sottosuperfici, popup): il
	// proprietario sta più in alto nell'albero, e ci si arriva risalendo.
	while (n != NULL) {
		if (n->data != NULL) {
			*fuori = *(enum tipo_nodo *)n->data;
			return n->data;
		}
		n = n->parent == NULL ? NULL : &n->parent->node;
	}
	return NULL;
}

static void fuoco_tastiera(struct minerva *m, struct wlr_surface *s) {
	puntatore_consenti(m->puntatore, !m->bloccato && m->presa == PRESA_NIENTE);
	if (s == NULL) {
		wlr_seat_keyboard_notify_clear_focus(m->seat);
		return;
	}
	if (m->seat->keyboard_state.focused_surface == s)
		return;

	struct wlr_keyboard *kb = wlr_seat_get_keyboard(m->seat);
	if (kb != NULL)
		wlr_seat_keyboard_notify_enter(m->seat, s, kb->keycodes,
			kb->num_keycodes, &kb->modifiers);
	else
		// Senza tastiera collegata si manda il fuoco lo stesso: il programma
		// deve sapere di essere quello attivo anche se in quel momento non
		// c'è niente da premere.
		wlr_seat_keyboard_notify_enter(m->seat, s, NULL, 0, NULL);
}

static void fuoco_finestra(struct minerva *m, struct finestra *f) {
	if (f == NULL || f->albero == NULL)
		return;

	// ── Mentre lo schermo è bloccato, nessuno prende il fuoco ────────────
	//
	// Non è una cortesia: è la seconda metà del blocco. La tenda impedisce di
	// VEDERE, questa riga impedisce di SCRIVERE — e senza, basterebbe che la
	// shell mandasse `fuoco <finestra>` sul canale per mettere la tastiera
	// dentro un terminale coperto da uno schermo nero. Il canale non è
	// esposto a chiunque, ma un blocco che regge solo finché nessuno chiama
	// la funzione sbagliata non è un blocco.
	if (m->bloccato)
		return;

	// ── Già sua: non si rifà niente ─────────────────────────────────────
	//
	// Ogni clic su una finestra passa di qui, anche quando il fuoco ce l'ha
	// già. Rifare tutto voleva dire riattivarla, ridisegnare la barra del
	// titolo e la cornice e riannunciare «fuoco» alla shell a OGNI clic, e
	// Giacomo vedeva il titolo del terminale diventare grigio per un istante e
	// la finestra «perdere luce». Misurato il 24 settembre 2026 ascoltando il
	// canale: dieci «fuoco» in undici secondi, sempre la stessa finestra.
	if (f->scrivania == m->scrivania_attiva
	    && m->seat->keyboard_state.focused_surface == finestra_superficie(f)
	    && m->finestre_elenco.next == &f->link)
		return;

	// ── Se sta su un'altra scrivania, ci si va ───────────────────────────
	//
	// La dock elenca TUTTE le finestre, non solo quelle di qui: un clic su
	// una che sta altrove deve portarci là. Senza questa riga il clic
	// «funziona» — la finestra prende davvero il fuoco — e sullo schermo non
	// cambia niente, che è il modo peggiore di rispondere a un comando.
	// È anche quello che fa `focuswindow` di Hyprland.
	if (f->scrivania != m->scrivania_attiva)
		scrivania_vai_ex(m, f->scrivania, false);

	// Alzare in cima e accendere vanno insieme, e in quest'ordine: una
	// finestra attiva che resta sotto un'altra è il difetto che si vede
	// subito e non si sa spiegare.
	wlr_scene_node_raise_to_top(&f->cornice->node);
	// L'elenco tiene l'ordine di sovrapposizione, dalla più in alto: è così
	// che si sa a chi passare il fuoco quando questa si chiude.
	wl_list_remove(&f->link);
	wl_list_insert(&m->finestre_elenco, &f->link);

	// ── Spegnere quella di prima ─────────────────────────────────────────
	//
	// Si cerca per SUPERFICIE e non per toplevel: la superficie ce l'hanno
	// tutte, di qualunque razza siano. Cercare il `wlr_xdg_toplevel` vorrebbe
	// dire che una finestra X11 che perde il fuoco resta accesa — e la barra
	// del titolo di due finestre insieme accesa è il difetto per cui
	// «sembrano attive tutte».
	struct wlr_surface *prima = m->seat->keyboard_state.focused_surface;
	if (prima != NULL && prima != finestra_superficie(f)) {
		struct finestra *v;
		wl_list_for_each(v, &m->finestre_elenco, link) {
			if (finestra_superficie(v) != prima)
				continue;
			finestra_di_attiva(v, false);
			// La barra va ridisegnata subito, o resta accesa.
			barra_aggiorna(v);
			break;
		}
	}

	finestra_di_attiva(f, true);
	fuoco_tastiera(m, finestra_superficie(f));
	barra_aggiorna(f);
	// La cornice segue il fuoco: si accende su questa e si spegne su quella
	// di prima. Qui e non nel timer, o cambiando finestra a cornice FISSA non
	// succederebbe niente — il timer con quel modo non gira.
	cornici_ridipingi(m);
	annuncia(m, "fuoco", f);
}

/// A chi dare il fuoco quando quella attiva se ne va.
static void fuoco_alla_prossima(struct minerva *m) {
	// Da bloccati il fuoco è del blocco, e una finestra che si chiude non
	// deve poterselo riprendere.
	if (m->bloccato)
		return;
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		// `finestra_visibile` e non `!f->ridotta`: dare la tastiera a una
		// finestra che sta su un'altra scrivania vuol dire scrivere in un
		// posto che non si vede. È lo stesso difetto del blocco schermo —
		// coperta e comunque raggiungibile — su scala più piccola.
		struct wlr_surface *sup = finestra_superficie(f);
		if (finestra_visibile(f) && sup != NULL && sup->mapped) {
			fuoco_finestra(m, f);
			return;
		}
	}
	// Non è rimasto niente: il fuoco si toglie invece di restare appeso a una
	// superficie che non c'è più.
	fuoco_tastiera(m, NULL);
}

// ── Uno schermo ───────────────────────────────────────────────────────────

/// ── La lente: si ritaglia lo scanout, non si ridisegna la scena ─────────
///
/// La strada che sembra ovvia — catturare lo schermo in un buffer e
/// ridisegnarlo scalato — costa una cattura per fotogramma, ed è il motivo per
/// cui il README rimandava questa cosa alla sua Tappa 5.
///
/// Non serve. `wlr_output_state` ha già `buffer_src_box`: **la scena disegna
/// come sempre, e quello che cambia è quale fetta del buffer va sullo
/// schermo.** Nessun passaggio di disegno in più, nessuna cattura, nessuno
/// shader. È la stessa strada che i monitor usano da sempre per lo zoom.
///
/// Il prezzo è che dipende dal backend: su un piano hardware che non sa
/// scalare, il commit viene rifiutato. `wlr_output_commit_state` è **atomico**
/// — se fallisce non applica niente — quindi il caso peggiore non è uno
/// schermo rotto: è uno schermo che non ingrandisce, e lo si dice.
///
/// ── E perché il puntatore passa al software ─────────────────────────────
///
/// Perché un cursore hardware sta su un piano suo, che il ritaglio non tocca:
/// resterebbe della sua misura e nel posto sbagliato. E poi c'è una ragione
/// più sottile: un cursore hardware che si muove **non sporca la scena**, e
/// senza una scena sporca non c'è un fotogramma nuovo — la lente resterebbe
/// ferma mentre il puntatore cammina. Bloccandolo al software, ogni movimento
/// ridisegna, che è esattamente ciò che serve.
static bool lente_commit(struct schermo *s, struct wlr_scene_output *so,
		const struct wlr_scene_output_state_options *opzioni) {
	struct minerva *m = s->m;
	struct wlr_output *out = s->out;

	struct wlr_output_state stato;
	wlr_output_state_init(&stato);
	if (!wlr_scene_output_build_state(so, &stato, opzioni)) {
		wlr_output_state_finish(&stato);
		return false;
	}

	// Il ritaglio ha senso solo se la scena ha davvero messo un buffer: se
	// non c'era niente da ridisegnare non c'è su cosa agire, e il commit va
	// fatto lo stesso perché può portare altro (la tinta, il cursore).
	if (stato.buffer != NULL) {
		int lw = 0, lh = 0;
		wlr_output_transformed_resolution(out, &lw, &lh);
		struct wlr_box box;
		wlr_output_layout_get_box(m->schermi, out, &box);

		// ── Il conto sta in `src/lente.c`, e non è pignoleria ────────
		//
		// È l'unica cosa del compositore che NON si può fotografare: il
		// ritaglio agisce sullo scanout, e `grim` cattura la scena. Due
		// catture con lente spenta e accesa sono identiche al pixel.
		// Dove non si può guardare, l'unica prova possibile è sui numeri
		// — e per averla i numeri devono stare fuori da wlroots.
		//
		// Lì dentro c'è anche la riga che qui mancava: il ritaglio si
		// fa **solo sullo schermo dove sta il puntatore**. Gli altri
		// restavano ingranditi e fermi su un angolo.
		struct lente_box r;
		if (lente_ritaglio(m->lente_scala, box.x, box.y, box.width,
				box.height, lw, lh, m->cursore->x, m->cursore->y, &r)) {
			stato.buffer_src_box = (struct wlr_fbox){
				r.x, r.y, r.larghezza, r.altezza};
		}
	}

	if (wlr_output_commit_state(out, &stato)) {
		wlr_output_state_finish(&stato);
		return true;
	}

	// ── Rifiutato: si torna indietro invece di insistere ─────────────────
	//
	// Il commit è atomico, quindi qui non è stato applicato niente e lo
	// schermo mostra ancora il fotogramma di prima. Si riprova senza il
	// ritaglio: meglio uno schermo che non ingrandisce di uno che si ferma.
	stato.buffer_src_box = (struct wlr_fbox){0, 0, 0, 0};
	bool ok = wlr_output_commit_state(out, &stato);
	if (!ok && !m->lente_avvisata) {
		m->lente_avvisata = true;
		wlr_log(WLR_ERROR, "minerva: questo schermo non sa ingrandire "
			"(il commit col ritaglio è stato rifiutato)");
	}
	wlr_output_state_finish(&stato);
	return ok;
}

// ── La luce notturna, per la strada dello schermo ────────────────────────
//
// La tabella dei colori si mette sullo STATO DELLO SCHERMO e la applica il
// monitor (su DRM è la rampa di gamma della scheda video). Il perché sta in
// `schermo_frame`, in due parole: il renderer GLES2 la ignora, misurato.
//
// ── Si prova UNA volta, e se non si può si dice ──────────────────────────
//
// `wlr_output_test_state` chiede al backend «lo accetteresti?». La risposta
// non cambia per tutta la vita di uno schermo, quindi si chiede una volta e
// si ricorda in `s->tinta_strada`. Chiederlo a ogni fotogramma vorrebbe dire
// una chiamata al kernel sessanta volte al secondo per sapere una cosa già
// saputa.
//
// E quando la risposta è no, si scrive una riga di registro e si continua a
// disegnare senza tinta. Il peggio possibile qui sarebbe smettere di
// consegnare fotogrammi: uno schermo nero perché la luce notturna non si può
// fare è una cura peggiore della malattia.
static bool tinta_commit(struct schermo *s, struct wlr_scene_output *so,
		const struct wlr_scene_output_state_options *opzioni) {
	struct wlr_output_state stato;
	wlr_output_state_init(&stato);
	if (!wlr_scene_output_build_state(so, &stato, opzioni)) {
		wlr_output_state_finish(&stato);
		return false;
	}

	if (s->tinta_strada != 2) {
		wlr_output_state_set_color_transform(&stato, s->m->tinta);
		if (s->tinta_strada == 0) {
			s->tinta_strada = wlr_output_test_state(s->out, &stato) ? 1 : 2;
			if (s->tinta_strada == 2) {
				wlr_log(WLR_INFO, "minerva: «%s» non prende la tabella dei "
					"colori: la luce notturna non si vedrà su questo schermo",
					s->out->name);
				// Si rifà lo stato senza la tinta: uno stato che il backend
				// ha già rifiutato non si commette sperando.
				wlr_output_state_finish(&stato);
				wlr_output_state_init(&stato);
				if (!wlr_scene_output_build_state(so, &stato, opzioni)) {
					wlr_output_state_finish(&stato);
					return false;
				}
			}
		}
	}

	bool ok = wlr_output_commit_state(s->out, &stato);
	wlr_output_state_finish(&stato);
	return ok;
}

static void schermo_frame(struct wl_listener *l, void *dati) {
	(void)dati;
	struct schermo *s = wl_container_of(l, s, frame);
	molla_fotogramma(s->m, s->out);
	respiro_fotogramma(s->m, s->out);
	// Dopo la molla e il respiro, che spostano le finestre: i ponti seguono
	// le posizioni di QUESTO fotogramma. Se niente è cambiato, niente si
	// tocca (i nodi confrontano prima di sporcare).
	mercurio_aggiorna(s->m);
	fantasmi_fotogramma(s->m);

	// La scena sa cosa è cambiato e ridisegna solo quello. Chiedere il
	// disegno di tutto a ogni fotogramma funziona lo stesso e si paga in
	// batteria: su un portatile è la differenza fra una scrivania ferma che
	// consuma zero e una che scalda.
	struct wlr_scene_output *so =
		wlr_scene_get_scene_output(s->m->scena, s->out);
	if (so == NULL)
		return;

	// ── E qui passava la luce notturna, senza arrivare da nessuna parte ──
	//
	// Qui c'era `opzioni.color_transform = s->m->tinta`, con scritto accanto
	// che così «la applica il renderer, e vale su ogni backend». Non era
	// vero, e per due settimane nessuno se n'è accorto perché nessuna prova
	// guardava i pixel — lo dichiarava perfino `prova-ingresso.py`: «qui si
	// verifica l'IMPIANTO, non i pixel».
	//
	// Misurato il 9 settembre 2026, nel compositore annidato, con una
	// fotografia prima e una dopo `colore 1 0.5 0.3`:
	//
	//     renderer GLES2 (il nostro)     0,0 % dei pixel cambia
	//     renderer Vulkan, stesso codice 78,1 %
	//
	// Cioè: **il renderer GLES2 di wlroots ignora la tabella dei colori.**
	// Non è colpa di SceneFX — provato anche col compositore di prima dello
	// scambio, stesso zero — ed è definitivo per noi, perché il renderer di
	// SceneFX è GLES2 e basta.
	//
	// Resta una strada sola, ed è quella vera: la tabella la prende lo
	// SCHERMO. È quella di `gammastep` e del pannello colori di un monitor da
	// vent'anni, costa zero per fotogramma, e vale su ogni cosa a schermo.
	// Non c'è su ogni backend — il backend annidato non ha nessuna tabella —
	// e quando non c'è il compositore lo DICE, invece di far finta.
	struct wlr_scene_output_state_options opzioni = {0};
	bool accettato = false;
	if (s->m->metro_gpu) {
		// Il fotogramma di PRIMA: adesso la scheda video ha finito.
		if (s->cronometro.render_timer != NULL) {
			int64_t ns = wlr_render_timer_get_duration_ns(s->cronometro.render_timer);
			if (ns >= 0) {
				s->m->gpu_ns += (uint64_t)ns;
				s->m->gpu_fotogrammi++;
			} else {
				s->m->gpu_persi++;
			}
		}
		// build_state chiude il cronometro vecchio e ne apre uno nuovo.
		opzioni.timer = &s->cronometro;
	} else if (s->cronometro.render_timer != NULL) {
		wlr_scene_timer_finish(&s->cronometro);
		s->cronometro = (struct wlr_scene_timer){0};
	}
	if (s->m->bloccato && !s->blocco_presentato && s->blocco_attesa) {
		// Non sostituire la sequenza attesa prima del feedback del backend:
		// un feedback ritardato non deve affamare la conferma del blocco.
	} else if (s->m->bloccato && !s->blocco_presentato) {
		// La tenda deve diventare un buffer realmente presentato. Niente
		// lente/tinta in questo passaggio di sicurezza.
		wlr_damage_ring_add_whole(&so->damage_ring);
		struct wlr_output_state stato;
		wlr_output_state_init(&stato);
		bool ok = wlr_scene_output_build_state(so, &stato, &opzioni);
		if (ok && stato.buffer) {
			s->blocco_seq = s->out->commit_seq + 1;
			s->blocco_attesa = true;
			ok = wlr_output_commit_state(s->out, &stato);
		} else ok = false;
		wlr_output_state_finish(&stato);
		accettato = ok;
		if (!ok) {
			s->blocco_attesa = false;
			wlr_output_schedule_frame(s->out);
		}
	} else if (s->m->lente_scala > 1.0)
		accettato = lente_commit(s, so, &opzioni);
	else if (s->m->tinta != NULL)
		accettato = tinta_commit(s, so, &opzioni);
	else
		accettato = wlr_scene_output_commit(so, &opzioni);

	if (accettato)
		wlr_minerva_scene_output_latched(so);
	else if (!s->blocco_attesa)
		wlr_output_schedule_frame(s->out);

	// Frame callback: invito a produrre il prossimo frame. Il momento reale
	// di presentazione viene comunicato separatamente da presentation-time.
	struct timespec adesso;
	clock_gettime(CLOCK_MONOTONIC, &adesso);
	wlr_scene_output_send_frame_done(so, &adesso);
}

static void schermo_presentato(struct wl_listener *l, void *dati) {
	struct schermo *s = wl_container_of(l, s, present);
	struct wlr_output_event_present *e = dati;
	if (!s->m->bloccato || !s->blocco_attesa || e->commit_seq != s->blocco_seq) return;
	s->blocco_attesa = false;
	s->blocco_presentato = e->presented;
	// Recupera anche i danni arrivati mentre attendevamo il feedback.
	wlr_output_schedule_frame(s->out);
	blocco_verifica_presentazione(s->m);
}

static void schermo_commesso(struct wl_listener *l, void *dati) {
	struct schermo *s = wl_container_of(l, s, output_commit);
	struct wlr_output_event_commit *e = dati;
	if (e->state->committed & (WLR_OUTPUT_STATE_ENABLED | WLR_OUTPUT_STATE_MODE)) {
		s->blocco_presentato = false;
		// Un present tardivo del modo precedente non protegge quello nuovo.
		// Conserva soltanto l'attesa del buffer protetto di QUESTO commit.
		if (s->blocco_seq != s->out->commit_seq)
			s->blocco_attesa = false;
		if (s->m->bloccato && s->out->enabled) wlr_output_schedule_frame(s->out);
		blocco_verifica_presentazione(s->m);
	}
}

static void schermo_distrutto(struct wl_listener *l, void *dati) {
	(void)dati;
	struct schermo *s = wl_container_of(l, s, distrutto);
	struct minerva *m = s->m;
    monitor_transaction_removed(m, s->out);
	if (s->prova_timer) {
		wl_event_source_remove(s->prova_timer);
		wlr_output_state_finish(&s->prima_prova);
	}
	wlr_scene_timer_finish(&s->cronometro);
	wl_list_remove(&s->frame.link);
	wl_list_remove(&s->present.link);
	wl_list_remove(&s->output_commit.link);
	wl_list_remove(&s->distrutto.link);
	wl_list_remove(&s->link);
	free(s);
    if (m->canale) wl_event_loop_add_idle(m->loop, monitor_recover, m);
	blocco_verifica_presentazione(m);
	annuncia_schermi(m);
}

// ── Configurare uno schermo, in un posto solo ────────────────────────────
//
// Stava dentro `schermo_nuovo`, e ci starebbe ancora se la pagina Schermi
// delle Impostazioni non dovesse poter cambiare risoluzione **mentre la
// sessione gira**. Adesso lo stesso codice serve in due momenti: quando uno
// schermo compare, e quando qualcuno chiede di cambiarlo.
//
// Averne due copie sarebbe il difetto classico di questa pagina: la
// risoluzione che si applica al volo è giusta, quella che torna al riavvio è
// diversa — e la causa è lontana settimane dal sintomo.
//
// `v` può essere NULL: «il modo che preferisci, scala 1». È la risposta
// giusta su un computer che non ha ancora scelto niente.
static bool schermo_configura(struct wlr_output *out,
		const struct schermo_voluto *v) {
	// In 0.20 la configurazione di uno schermo si prepara in uno «stato» e si
	// consegna tutta insieme: acceso, modo, scala. Applicarla a pezzi è il
	// modo in cui si ottiene un frame nero in mezzo.
	struct wlr_output_state stato;
	wlr_output_state_init(&stato);

	if (v != NULL && !v->acceso) {
		// Uno schermo spento si spegne e basta: niente modo, niente scala,
		// niente scena. Restare a metà — acceso nella scena e spento
		// nell'hardware — vuol dire finestre che nascono dove non le vede
		// nessuno.
		wlr_output_state_set_enabled(&stato, false);
		const bool ok = wlr_output_commit_state(out, &stato);
		wlr_output_state_finish(&stato);
		wlr_log(WLR_INFO, "minerva: schermo %s spento su richiesta", out->name);
		return ok ? false : out->enabled;
	}

	wlr_output_state_set_enabled(&stato, true);

	struct wlr_output_mode *modo = NULL;
	if (v != NULL && v->larghezza > 0 && v->altezza > 0) {
		// Il modo chiesto, se esiste davvero. `wlr_output_preferred_mode` non
		// serve a cercarlo: bisogna scorrere la lista, perché un modo che il
		// monitor non ha si può chiedere e il commit fallisce — e uno schermo
		// nero per una riga di configurazione è il difetto peggiore che ci
		// sia, dato che per correggerla serve lo schermo.
		struct wlr_output_mode *cand;
		wl_list_for_each(cand, &out->modes, link) {
			if (cand->width != v->larghezza || cand->height != v->altezza)
				continue;
			if (v->millihz > 0 ? cand->refresh != v->millihz :
                    (v->hz > 0 && (cand->refresh + 500) / 1000 != v->hz))
				continue;
			modo = cand;
			break;
		}
		if (modo == NULL)
			wlr_log(WLR_ERROR, "minerva: lo schermo %s non ha il modo "
				"%dx%d@%d: tengo quello preferito", out->name,
				v->larghezza, v->altezza, v->hz);
	}
	if (modo == NULL)
		modo = wlr_output_preferred_mode(out);
	if (modo != NULL)
		wlr_output_state_set_mode(&stato, modo);

	// ── LA SCALA ────────────────────────────────────────────────────────
	//
	// Mancava, e non è un dettaglio estetico: senza, su questo portatile —
	// 1920×1080 a 1,25 — la scrivania nasce a 1920 punti logici invece che a
	// 1536, e tutto risulta piccolo di un quarto. Peggio, ogni misura presa a
	// schermo mente: si prova una barra alta 42 pixel e se ne vedono 33.
	double scala = (v != NULL && v->scala > 0) ? v->scala : 1.0;
	wlr_output_state_set_scale(&stato, (float)scala);

	if (v != NULL && v->rotazione >= 0) {
		enum wl_output_transform t = WL_OUTPUT_TRANSFORM_NORMAL;
		if (v->rotazione == 90)
			t = WL_OUTPUT_TRANSFORM_90;
		else if (v->rotazione == 180)
			t = WL_OUTPUT_TRANSFORM_180;
		else if (v->rotazione == 270)
			t = WL_OUTPUT_TRANSFORM_270;
		wlr_output_state_set_transform(&stato, t);
	}

	bool riuscito = wlr_output_commit_state(out, &stato);
	if (!riuscito) {
		wlr_log(WLR_ERROR, "minerva: lo schermo %s rifiuta la configurazione",
			out->name);
		// ── E allora si riprova NUDI ──────────────────────────────────
		//
		// Acceso, modo preferito, scala 1: quello che ogni schermo accetta.
		// Senza questo secondo tentativo una riga sbagliata in
		// `schermi.conf` darebbe uno schermo nero — e per correggere quella
		// riga serve lo schermo. È la stessa regola della schermata di
		// accesso: niente di quello che aggiungiamo può diventare un motivo
		// per non entrare.
		wlr_output_state_finish(&stato);
		wlr_output_state_init(&stato);
		wlr_output_state_set_enabled(&stato, true);
		struct wlr_output_mode *sicuro = wlr_output_preferred_mode(out);
		if (sicuro != NULL)
			wlr_output_state_set_mode(&stato, sicuro);
		wlr_output_state_set_scale(&stato, 1.0f);
		if (wlr_output_commit_state(out, &stato))
			wlr_log(WLR_INFO, "minerva: %s ripreso con i valori sicuri",
				out->name);
	}
	wlr_output_state_finish(&stato);

	wlr_log(WLR_INFO, "minerva: schermo %s %dx%d scala %.2f → %d×%d logici",
		out->name, out->width, out->height, (double)out->scale,
		(int)(out->width / out->scale), (int)(out->height / out->scale));
	return out->enabled;
}

// ── Mettere (o togliere) uno schermo dal disegno complessivo ─────────────
//
// Due cose insieme, e vanno insieme: il posto nel `wlr_output_layout` — cioè
// dove sta rispetto agli altri — e il nodo di scena che ci disegna sopra.
//
// Togliere solo il primo lascia una scena che disegna nel vuoto; togliere
// solo il secondo lascia nel disegno complessivo un rettangolo su cui le
// finestre possono nascere e nessuno le vede. Uno schermo spento deve
// **sparire dal disegno**, o si continua a poter perdere una finestra dentro.
static void schermo_nel_disegno(struct minerva *m, struct wlr_output *out,
		const struct schermo_voluto *v) {
	if (!out->enabled) {
		wlr_output_layout_remove(m->schermi, out);
		return;
	}

	// `add_auto` mette lo schermo a destra di quelli che ci sono già. Dove
	// vanno DAVVERO lo decidono le Impostazioni di Minerva, che sanno già
	// disporre due schermi (`settings/sections/Display.qml`): qui serve solo
	// che esistano da qualche parte.
	struct wlr_output_layout_output *lo =
		(v != NULL && v->posizione_detta)
		? wlr_output_layout_add(m->schermi, out, v->x, v->y)
		: wlr_output_layout_add_auto(m->schermi, out);
	if (lo == NULL)
		return;

	// Uno schermo riacceso il suo nodo di scena può averlo ancora — dipende
	// da chi l'ha portato via per primo — e crearne un secondo sullo stesso
	// schermo vorrebbe dire disegnarlo due volte. Si chiede, invece di dare
	// per buono: `wlr_scene_get_scene_output` risponde in tutti e due i casi.
	struct wlr_scene_output *so = wlr_scene_get_scene_output(m->scena, out);
	if (so == NULL) {
		so = wlr_scene_output_create(m->scena, out);
		if (so != NULL)
			wlr_scene_output_layout_add_output(m->scena_schermi, lo, so);
	}
}

static void schermo_nuovo(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, schermo_nuovo);
	struct wlr_output *out = dati;

	// Uno schermo non sa disegnare finché non gli si dice CON CHE COSA.
	// Saltando questa riga il compositore parte, non dà errore, e lo schermo
	// resta nero: uno dei modi più antipatici di sbagliare.
	if (!wlr_output_init_render(out, m->allocator, m->renderer)) {
		wlr_log(WLR_ERROR, "minerva: lo schermo %s non accetta il renderer",
			out->name);
		return;
	}

	// Che cosa vuole Minerva da QUESTO schermo. Il file può non esserci — e
	// allora è modo preferito e scala 1, che è la cosa giusta su un computer
	// che non ha ancora scelto niente.
	const struct schermo_voluto *voluto = schermi_per(&m->schermi_conf,
	                                                  out->name);
	schermo_configura(out, voluto);

	struct schermo *s = calloc(1, sizeof(*s));

	if (s == NULL)
		return;
	s->m = m;
	s->out = out;

	s->frame.notify = schermo_frame;
	s->present.notify = schermo_presentato;
	wl_signal_add(&out->events.present, &s->present);
	s->output_commit.notify = schermo_commesso;
	wl_signal_add(&out->events.commit, &s->output_commit);
	wl_signal_add(&out->events.frame, &s->frame);
	s->distrutto.notify = schermo_distrutto;
	wl_signal_add(&out->events.destroy, &s->distrutto);
	wl_list_insert(&m->schermi_elenco, &s->link);

	// ── Se la lente è accesa, questo schermo nasce già col cursore a
	//    software ───────────────────────────────────────────────────────
	//
	// `comando_lente` blocca il cursore sugli schermi che esistono in QUEL
	// momento, e uno attaccato dopo non ce l'ha. Non è un dettaglio: è la
	// riga che fa esistere la lente. Un cursore hardware che si muove non
	// sporca la scena, senza scena sporca non c'è fotogramma nuovo, e la
	// lente resterebbe ferma mentre il puntatore cammina — su quel monitor
	// e solo su quello, che è il modo peggiore di rompersi.
	if (m->lente_scala > 1.0)
		wlr_output_lock_software_cursors(out, true);

	schermo_nel_disegno(m, out, voluto);

	// Finché non arriva una superficie appoggiata, lo spazio utile è tutto lo
	// schermo. Lasciarlo a zero vorrebbe dire finestre nuove larghe zero.
	wlr_output_layout_get_box(m->schermi, out, &s->utile);
	disponi(m, out);

	// ── Anche da spento resta nell'elenco ────────────────────────────────
	//
	// Prima uno schermo spento da `schermi.conf` usciva di scena qui: niente
	// `struct schermo`, niente riga nell'elenco. E il risultato era che dalla
	// pagina Schermi **non si poteva più riaccendere**, perché non c'era.
	// Uno schermo spento è un pulsante da riaccendere, non un'assenza.
	wlr_log(WLR_INFO, "minerva: schermo %s %s (%dx%d)", out->name,
		out->enabled ? "acceso" : "spento", out->width, out->height);
	annuncia_schermi(m);
    wl_event_loop_add_idle(m->loop, monitor_recover, m);
}

// ── Le superfici APPOGGIATE: barra, dock, pannelli, sfondo ───────────────
//
// È il protocollo `wlr-layer-shell`, ed è la ragione per cui si è scelta
// wlroots: la shell di Minerva lo usa in **48 punti** (`WlrLayershell`,
// `PanelWindow`). È un protocollo di wlroots, non di Hyprland — quindi la
// nostra scrivania ci gira dentro senza cambiare una riga di QML.

// ── Disporre le superfici appoggiate, e ricavarne lo spazio utile ────────
//
// Non si può configurare una superficie per volta: la zona riservata è una
// SOTTRAZIONE progressiva, e il risultato dipende dall'ordine. La barra in
// cima si prende quarantadue pixel; la dock in basso si prende i suoi da
// quello che resta; e solo alla fine si sa quanto spazio ha davvero una
// finestra.
//
// Configurandone una sola alla volta — che è quello che facevo prima — ogni
// superficie ricalcola partendo dallo schermo intero, e lo spazio utile finale
// è quello dell'ultima che si è mossa. Il difetto si vede solo con due
// superfici che riservano spazio, cioè esattamente la barra e la dock.
static void disponi(struct minerva *m, struct wlr_output *out) {
	if (out == NULL)
		return;

	struct wlr_box tutto = {0};
	wlr_output_layout_get_box(m->schermi, out, &tutto);
	struct wlr_box utile = tutto;

	// Due passate: prima chi riserva spazio, poi chi si limita ad appoggiarsi.
	// Al contrario, un pannello che copre tutto lo schermo senza riservare
	// niente si mangerebbe l'area utile di quelli veri.
	for (int passata = 0; passata < 2; passata++) {
		struct appoggiata *a;
		wl_list_for_each(a, &m->appoggiate, link) {
			if (a->out != out || !a->ls->initialized)
				continue;
			const bool riserva = a->ls->current.exclusive_zone > 0;
			if (riserva != (passata == 0))
				continue;
			wlr_scene_layer_surface_v1_configure(a->scena, &tutto, &utile);
		}
	}

	struct schermo *sc;
	wl_list_for_each(sc, &m->schermi_elenco, link) {
		if (sc->out == out) {
			sc->utile = utile;
			return;
		}
	}
}

// ── La tastiera ai pannelli che l'hanno chiesta ──────────────────────────
//
// Giacomo, 6 settembre 2026: «il nostro polkit o come si chiama, quando fa
// apparire richiesta di password di root non prende il focus e quindi bisogna
// spostare il mouse, cliccare sopra e inserire la password».
//
// `permessi.qml` la tastiera la chiede — `keyboardFocus: Exclusive` — e il
// compositore la dava in UN posto solo: dentro `cursore_premuto`, cioè quando
// ci si clicca sopra. Una superficie che nasce chiedendola non la riceveva
// mai, e restava lì con il cursore che lampeggia in un campo sordo.
//
// Non era solo la password: la ricerca (`search/Palette.qml`) e la guardia
// delle impostazioni (`settings/ChangeGuard.qml`) chiedono la stessa cosa, e
// avevano lo stesso difetto.
//
// «Esclusivo» e non «a richiesta»: `ON_DEMAND` deve continuare a prendere il
// fuoco SOLO al clic, ed è la riga che impedisce alla barra in cima di rubare
// la tastiera a chi sta scrivendo. Le due cose si somigliano e vogliono dire
// l'opposto.
static void appoggiata_aggiorna_fuoco(struct minerva *m) {
	// Da bloccati il fuoco è della schermata di blocco, e nessun pannello se
	// lo riprende. È la stessa guardia di `fuoco_alla_prossima`.
	if (m->bloccato)
		return;

	struct appoggiata *scelta = NULL;
	struct appoggiata *a;
	wl_list_for_each(a, &m->appoggiate, link) {
		if (a->ls->surface == NULL || !a->ls->surface->mapped)
			continue;
		if (a->ls->current.keyboard_interactive
		    != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE)
			continue;
		// Se ce n'è più d'uno vince quello sul piano più alto: la finestra
		// della password sta sopra la ricerca, e deve prendersela lei.
		if (scelta == NULL
		    || a->ls->current.layer > scelta->ls->current.layer)
			scelta = a;
	}

	if (scelta != NULL) {
		fuoco_tastiera(m, scelta->ls->surface);
		return;
	}

	// Non ce n'è più nessuno: la tastiera torna a chi lavorava. Solo però se
	// ce l'aveva un pannello — se il fuoco è già di una finestra non glielo
	// si toglie di mano per poi ridarglielo.
	struct wlr_surface *ora = m->seat->keyboard_state.focused_surface;
	if (ora != NULL
	    && wlr_layer_surface_v1_try_from_wlr_surface(ora) != NULL)
		fuoco_alla_prossima(m);
}

// ── Il fondo sfocato dei pannelli ────────────────────────────────────────
//
// Barra, dock, menù: quello che la shell appoggia sopra la scrivania. Sono
// traslucidi da sempre, e da sempre sopra una fotografia non si leggono — è
// il difetto scritto in `minerva-vetro-leggibile`, dove si era scoperto che
// non era il blur a mancare ma un cursore al 55%. Mancava anche il blur.
//
// ── Due regole, e senza la seconda si sfoca lo sfondo intero ─────────────
//
// 1. **Solo i piani alti.** Lo SFONDO e le icone della scrivania sono
//    superfici appoggiate anche loro, sui piani bassi, e grandi quanto lo
//    schermo: mettere un fondo sfocato dietro di LORO vorrebbe dire sfocare
//    la fotografia dello sfondo per intero, sempre. Si sfoca solo ciò che sta
//    sopra le finestre.
// 2. **Solo dove il pannello dipinge davvero.** La dock è una superficie
//    larga quanto lo schermo con dentro una pillola in mezzo: sfocare tutta
//    la striscia mostrerebbe una banda sfocata dove non c'è niente.
//    `wlr_minerva_blur_set_mask` dice a SceneFX di sfocare
//    solo dove la maschera — cioè il pannello stesso — sta disegnando.
struct cerca_buffer {
	struct wlr_surface *superficie;
	struct wlr_scene_buffer *trovato;
};

static void cerca_il_buffer(struct wlr_scene_buffer *b, int sx, int sy,
		void *dati) {
	(void)sx; (void)sy;
	struct cerca_buffer *c = dati;
	if (c->trovato != NULL)
		return;
	struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(b);
	if (s != NULL && s->surface == c->superficie)
		c->trovato = b;
}

static void appoggiata_sfocatura(struct appoggiata *a) {
	if (a == NULL || a->scena == NULL || a->ls == NULL)
		return;

	// ── Tutti i piani tranne lo SFONDO ──────────────────────────────────
	//
	// Qui c'erano solo TOP e OVERLAY, con scritto accanto che sui piani bassi
	// «lo SFONDO e le icone della scrivania sono superfici anche loro, e
	// mettere un fondo sfocato dietro di LORO vorrebbe dire sfocare la
	// fotografia dello sfondo per intero, sempre».
	//
	// Vero per BACKGROUND, che è la fotografia. Non per BOTTOM, che è il
	// piano dove stanno le icone e — dal 9 settembre 2026 — i widget della
	// scrivania. Lì la maschera di trasparenza fa il suo mestiere: si sfoca
	// solo dove quella superficie dipinge davvero, cioè dietro il widget e
	// non dietro tutto lo schermo.
	//
	// È la cosa che su Linux non ha nessuno: i widget della scrivania — Conky,
	// Rainmeter, i plasmoidi — sono disegni piatti appoggiati sopra lo sfondo,
	// perché nessuno di loro possiede il compositore. E risolve gratis la
	// leggibilità: un numero bianco su una fotografia chiara non si legge,
	// dietro il vetro sì.
	const bool piano_giusto =
		a->ls->current.layer != ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND;
	const bool voglio = a->m->effetto_modo == EFFETTO_ACQUERELLO && piano_giusto;

	if (!voglio) {
		if (a->sfocatura != NULL)
			wlr_scene_node_set_enabled(&a->sfocatura->node, false);
		return;
	}

	const int w = a->ls->surface->current.width;
	const int h = a->ls->surface->current.height;
	if (w <= 0 || h <= 0)
		return;

	if (a->sfocatura == NULL) {
		a->sfocatura = wlr_minerva_blur_create(a->scena->tree, w, h);
		if (a->sfocatura == NULL)
			return;
		// Sotto la superficie: quello che si sfoca è ciò che sta dietro.
		wlr_scene_node_lower_to_bottom(&a->sfocatura->node);
	}

	struct cerca_buffer c = {.superficie = a->ls->surface, .trovato = NULL};
	wlr_scene_node_for_each_buffer(&a->scena->tree->node, cerca_il_buffer, &c);
	// ── La misura PRIMA della maschera, e non è indifferente ────────────
	//
	// All'incontrario non si vedeva niente: il nodo nasce 1×1, e dando la
	// maschera prima di dirgli quanto è grande, quello che si sfoca è un
	// pixel. Una fotografia con la dock ancora nitida, e nessun errore da
	// nessuna parte.
	wlr_scene_rect_set_size(a->sfocatura, w, h);
	if (c.trovato != NULL)
		wlr_minerva_blur_set_mask(a->sfocatura, c.trovato);
	wlr_scene_node_set_enabled(&a->sfocatura->node, true);
}

static void cursore_aggiorna(struct minerva *m, uint32_t tempo);

// ── Cosa c'è sotto il puntatore, quando non si muove ──────────────────────
//
// Il compositore decide chi riceve il puntatore solo quando il puntatore si
// MUOVE. Ma una superficie può comparire o sparire sotto un puntatore fermo:
// il Centro di controllo aperto dalla barra, un menù che si chiude. Giacomo,
// 24 settembre 2026: «se clicco tenendo il mouse fermo e poi rifaccio clic
// non succede nulla; devo muovere leggermente il mouse». Il clic andava alla
// superficie di prima, o a nessuna. Qui si rifà la scelta come se il
// puntatore si fosse mosso di zero.
static void puntatore_ricalcola(struct minerva *m) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	cursore_aggiorna(m, (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000));
	wlr_seat_pointer_notify_frame(m->seat);
}

static void appoggiata_commit(struct wl_listener *l, void *dati) {
	(void)dati;
	struct appoggiata *a = wl_container_of(l, a, commit);

	// Stessa regola delle finestre: alla PRIMA commit il compositore deve
	// rispondere, o il programma resta ad aspettare in silenzio. Qui è
	// costato uno schermo nero con alacritty vivo e collegato.
	if (a->ls->initial_commit) {
		disponi(a->m, a->out);
		return;
	}

	// Il fondo sfocato segue la misura del pannello, che cambia quando cambia
	// lo schermo o quando la shell si ridispone.
	appoggiata_sfocatura(a);

	// ── E POI solo quando cambia la DISPOSIZIONE, non il disegno ─────────
	//
	// Qui c'era `|| a->ls->surface->mapped`, cioè: **a ogni commit**. Ma una
	// commit è quasi sempre solo un fotogramma nuovo — la barra che ridisegna
	// l'orologio — e `disponi()` manda una configurazione a TUTTE le superfici
	// appoggiate dello schermo. Il giro che ne nasceva è chiuso:
	//
	//     la shell disegna → noi riconfiguriamo tutte le superfici
	//        → Qt riceve la configurazione, risponde e ridisegna
	//           → noi riconfiguriamo di nuovo → …
	//
	// Misurato il 30 agosto 2026 dentro la sessione annidata, a scrivania
	// FERMA: **tutte e cinque le superfici della shell a 57 fotogrammi al
	// secondo**, 340 risvegli al secondo, il 12% di un processore per non fare
	// niente. La stessa identica shell sotto COSMIC: **una o due volte al
	// secondo**. E il compositore da solo, senza shell dentro: 0%.
	//
	// Non era un difetto della shell: era il nostro compositore a tenerla
	// sveglia, ed è il costo che questo progetto ha già pagato una volta
	// dall'altra parte — il demone che svegliava la shell diciotto volte al
	// secondo.
	//
	// `current.committed` è la maschera di cosa è cambiato DAVVERO in questa
	// commit: ancoraggio, misura, zona riservata, margini, livello. Se è zero,
	// il programma ha solo disegnato, e la disposizione di ieri va ancora
	// bene.
	if (a->ls->surface->mapped && a->ls->current.committed != 0)
		disponi(a->m, a->out);

	// Il fuoco si guarda comunque: una superficie che si mappa non cambia
	// per forza la disposizione — la finestra della password è larga e alta
	// come le si è detto fin dall'inizio — ma è proprio il momento in cui
	// deve prendersi la tastiera.
	appoggiata_aggiorna_fuoco(a->m);

	// Comparsa o sparita: sotto il puntatore fermo c'è un'altra superficie.
	if (a->ls->surface->mapped != a->mappata) {
		a->mappata = a->ls->surface->mapped;
		puntatore_ricalcola(a->m);
	}
}

static void appoggiata_distrutta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct appoggiata *a = wl_container_of(l, a, distrutta);
	struct minerva *m = a->m;
	struct wlr_output *out = a->out;
	wl_list_remove(&a->commit.link);
	wl_list_remove(&a->distrutta.link);
	wl_list_remove(&a->link);
	free(a);
	// Lo spazio che teneva torna disponibile: senza questa riga, chiudere un
	// pannello lascia il buco riservato per sempre.
	disponi(m, out);
	// E la tastiera torna a chi lavorava: chiusa la finestra della password,
	// si riprende a scrivere dove si era.
	appoggiata_aggiorna_fuoco(m);
	// E il puntatore a chi c'è sotto adesso, anche se non si muove.
	puntatore_ricalcola(m);
}

static void appoggiata_nuova(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, appoggiata_nuova);
	struct wlr_layer_surface_v1 *ls = dati;

	// ── Uno schermo va scelto NOI se il programma non lo dice ────────────
	//
	// Il protocollo permette al cliente di lasciare `output` vuoto e di
	// affidarsi al compositore. Senza questa riga la superficie resta senza
	// schermo e non compare mai — un altro modo silenzioso di non funzionare.
	if (ls->output == NULL) {
		struct wlr_output *primo =
			wlr_output_layout_output_at(m->schermi, 0, 0);
		if (primo == NULL) {
			wlr_layer_surface_v1_destroy(ls);
			return;
		}
		ls->output = primo;
	}

	struct appoggiata *a = calloc(1, sizeof(*a));
	if (a == NULL)
		return;
	a->tipo = NODO_APPOGGIATA;
	a->m = m;
	a->ls = ls;
	a->out = ls->output;
	wl_list_insert(&m->appoggiate, &a->link);

	// Il piano lo dice il cliente, e va rispettato: la dock chiede «bottom»,
	// la barra «top», il blocco schermo «overlay». Metterli tutti insieme
	// vuol dire una scrivania in cui le cose si coprono a caso.
	struct wlr_scene_tree *piano = m->piano[ls->pending.layer];
	a->scena = wlr_scene_layer_surface_v1_create(piano, ls);
	if (a->scena == NULL) {
		free(a);
		return;
	}
	a->scena->tree->node.data = a;
	ls->data = a;

	a->commit.notify = appoggiata_commit;
	wl_signal_add(&ls->surface->events.commit, &a->commit);
	a->distrutta.notify = appoggiata_distrutta;
	wl_signal_add(&ls->events.destroy, &a->distrutta);

	wlr_log(WLR_INFO, "minerva: superficie appoggiata «%s» sul piano %d",
		ls->namespace ? ls->namespace : "?", ls->pending.layer);
}

// ── Una finestra, comunque sia fatta ──────────────────────────────────────
//
// Queste cinque funzioni sono il confine. Sotto ci sono due protocolli
// diversi — xdg-shell per i programmi Wayland, XWayland per quelli X11 — e
// sopra c'è un file che parla di finestre e basta.
//
// Prima esistevano soltanto le finestre xdg, e `f->toplevel->…` stava scritto
// in cinquantatré punti. Ognuno di quei punti era un posto dove aggiungere
// XWayland avrebbe voluto dire un `if` — e un `if` dimenticato è una finestra
// di Steam che non si sposta, o che non si chiude, senza nessun errore.

/// La superficie da disegnare e a cui dare la tastiera.
///
/// Per una finestra X11 può essere NULL, e non è un errore: esiste da quando
/// la superficie le viene «associata» a quando gliela tolgono. Chi la
/// dereferenzia deve controllare — è la differenza vera fra le due razze, e
/// l'unica che si paga con un crollo invece che con un difetto.
static struct wlr_surface *finestra_superficie(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return f->xsup->surface;
	return f->toplevel->base->surface;
}

/// Quanto è grande il PROGRAMMA (barra del titolo esclusa).
static void finestra_geometria(struct finestra *f, int *w, int *h) {
	if (f->razza == FINESTRA_X11) {
		// In X11 la misura della finestra È la misura della finestra: non
		// c'è nessuna «geometria della finestra dentro la superficie» come
		// in xdg-shell, perché non ci sono le ombre disegnate dal client.
		*w = f->xsup->width;
		*h = f->xsup->height;
		return;
	}
	*w = f->toplevel->base->geometry.width;
	*h = f->toplevel->base->geometry.height;
}

static const char *finestra_titolo(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return f->xsup->title != NULL ? f->xsup->title : "";
	return f->toplevel->title != NULL ? f->toplevel->title : "";
}

/// In X11 si chiama `WM_CLASS` e ha due metà: `instance` (il nome del
/// binario) e `class` (il nome del programma). Si dà la seconda, che è quella
/// che corrisponde all'`app_id` di Wayland — «Steam», non «steam».
static const char *finestra_classe(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return f->xsup->class != NULL ? f->xsup->class : "";
	return f->toplevel->app_id != NULL ? f->toplevel->app_id : "";
}

/// Il programma ha chiesto di nascere a schermo intero?
///
/// ── Perché un accessore e non due righe sul posto ──────────────────────
///
/// Perché le due razze lo dicono in due campi diversi, e il 5 settembre 2026
/// quelle due righe le avevo scritte dentro `finestra_appare` — attraversando
/// il confine che questo file si è dato il 25 agosto: fuori dagli accessori
/// `finestra_*` non si nomina né `f->toplevel` né `f->xsup`. Non me ne ero
/// accorto: `scripts/razza-finestre.py` lo diceva a ogni giro di `prove.sh`, e
/// la riga era in mezzo ad altre rosse per altri motivi.
static bool finestra_vuole_pieno(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return f->xsup->fullscreen;
	return f->toplevel->requested.fullscreen;
}

/// E ingrandita? In X11 non esiste una richiesta equivalente che valga alla
/// nascita — si passa da `_NET_WM_STATE`, che arriva dopo — quindi per quelle
/// la risposta è sempre no, ed è la stessa che dava il codice di prima.
static bool finestra_vuole_ingrandita(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return false;
	return f->toplevel->requested.maximized;
}

/// «Sei tu quella attiva»: è il segno che fa accendere il bordo ai programmi
/// che se lo disegnano da soli.
static void finestra_di_attiva(struct finestra *f, bool si) {
	if (f->razza == FINESTRA_X11) {
		wlr_xwayland_surface_activate(f->xsup, si);
		// ── E in più, l'ordine dentro X ──────────────────────────────────
		//
		// La pila che conta per noi è `finestre_elenco`, ma i programmi X11
		// hanno anche la LORO: se ne accorgono i menù, che si posizionano
		// rispetto alla finestra che X crede in cima. Senza questa riga il
		// menù di Steam compare dietro la finestra da cui è uscito.
		if (si)
			wlr_xwayland_surface_restack(f->xsup, NULL, XCB_STACK_MODE_ABOVE);
		return;
	}
	wlr_xdg_toplevel_set_activated(f->toplevel, si);
}

/// «Stai qui, e fatti grande così». Il programma può rispondere di no, ed è
/// un suo diritto: qui si chiede, non si impone.
///
/// ── Perché c'è anche la POSIZIONE, che a Wayland non serve ──────────────
///
/// Una finestra Wayland non sa dove sta, e va benissimo così. Una finestra
/// X11 invece **deve** saperlo: le sue coordinate sono assolute, e sono
/// quelle con cui calcola dove aprire i propri menù. Un compositore che la
/// muove senza dirglielo si ritrova i menù a tendina nell'angolo in alto a
/// sinistra dello schermo — difetto classico, e senza nessun errore.
///
/// `x, y` sono l'angolo del PROGRAMMA, barra del titolo esclusa.
static void finestra_di_geometria(struct finestra *f, int x, int y, int w, int h) {
	if (f->razza == FINESTRA_X11) {
		wlr_xwayland_surface_configure(f->xsup, (int16_t)x, (int16_t)y,
			(uint16_t)(w > 0 ? w : 0), (uint16_t)(h > 0 ? h : 0));
		return;
	}
	(void)x;
	(void)y;
	wlr_xdg_toplevel_set_size(f->toplevel, w, h);
}

static void finestra_di_ingrandita(struct finestra *f, bool si) {
	if (f->razza == FINESTRA_X11) {
		// X11 distingue «largo quanto lo schermo» da «alto quanto lo
		// schermo»: sono due stati separati, e ingrandito vuol dire tutti e
		// due insieme.
		wlr_xwayland_surface_set_maximized(f->xsup, si, si);
		return;
	}
	wlr_xdg_toplevel_set_maximized(f->toplevel, si);
}

/// ── Il «ridotta» che in xdg-shell non si può dire ───────────────────────
///
/// xdg-shell non ha nessun modo di dire a un programma «adesso sei ridotto»:
/// c'è `set_minimized` in una direzione sola, dal programma al compositore.
/// X11 invece ce l'ha, ed è quello che fa comparire la finestra spenta nelle
/// barre delle applicazioni che i programmi X11 si aspettano.
static void finestra_di_ridotta(struct finestra *f, bool si) {
	if (f->razza == FINESTRA_X11)
		wlr_xwayland_surface_set_minimized(f->xsup, si);
}

/// Ha una finestra madre? Un dialogo ce l'ha, una finestra principale no. È
/// il segno che distingue «piccola perché è un dialogo» da «piccola perché
/// non ha ancora deciso quanto è grande».
static bool finestra_ha_genitore(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return f->xsup->parent != NULL;
	return f->toplevel->parent != NULL;
}

/// La misura massima che il programma dichiara, o zero se non ne dichiara.
static void finestra_massimo(struct finestra *f, int *w, int *h) {
	*w = 0;
	*h = 0;
	if (f->razza == FINESTRA_X11) {
		// In X11 si chiamano «size hints» e possono non esserci affatto.
		if (f->xsup->size_hints != NULL) {
			*w = f->xsup->size_hints->max_width;
			*h = f->xsup->size_hints->max_height;
		}
		return;
	}
	*w = f->toplevel->current.max_width;
	*h = f->toplevel->current.max_height;
}

static void finestra_di_schermo_intero(struct finestra *f, bool si) {
	if (f->razza == FINESTRA_X11) {
		wlr_xwayland_surface_set_fullscreen(f->xsup, si);
		return;
	}
	wlr_xdg_toplevel_set_fullscreen(f->toplevel, si);
}

/// «Chiuditi, per favore». Non è un'uccisione: il programma può chiedere di
/// salvare, e deve poterlo fare.
static void finestra_di_chiuditi(struct finestra *f) {
	chiusura_chiesta(f);
	if (f->razza == FINESTRA_X11) {
		wlr_xwayland_surface_close(f->xsup);
		return;
	}
	wlr_xdg_toplevel_send_close(f->toplevel);
}

/// Lo spazio utile dello schermo su cui sta questa finestra.
static void finestra_utile(struct finestra *f, struct wlr_box *fuori) {
	struct wlr_box mia;
	wlr_scene_node_coords(&f->cornice->node, &mia.x, &mia.y);
	finestra_geometria(f, &mia.width, &mia.height);

	struct wlr_output *out = wlr_output_layout_output_at(f->m->schermi,
		mia.x + mia.width / 2.0, mia.y + mia.height / 2.0);
	if (out == NULL)
		out = wlr_output_layout_output_at(f->m->schermi, 0, 0);

	struct schermo *sc;
	wl_list_for_each(sc, &f->m->schermi_elenco, link) {
		if (sc->out == out) {
			*fuori = sc->utile;
			return;
		}
	}
	*fuori = (struct wlr_box){0, 0, 1280, 720};
}

// ══ L'aggancio ai bordi ══════════════════════════════════════════════════
//
// Trascini una finestra contro un bordo e lei ci si spalma: metà schermo di
// lato, tutto lo schermo in cima, un quarto negli angoli. È il gesto che tutti
// conoscono da Windows, e Minerva ce l'ha da luglio — **ma stava tutto in
// `minerva-shell/spine/TitleBars.qml`**, cioè nella barra del titolo disegnata
// dalla shell.
//
// Sotto minerva-wayland le barre sono native (`src/barra.c`), quindi quel file
// non è in funzione, e con lui non era in funzione l'aggancio: zero righe di
// snap in tutto il compositore. È la seconda delle tre cose che Giacomo ha
// chiesto il 30 agosto 2026, e non era «rotta»: non c'era.
//
// Il CONTO sta in `src/aggancio.c`, che non conosce wlroots e ha le sue prove
// (`meson test -C build aggancio`). Qui c'è solo il guscio: trovare lo schermo
// sotto il puntatore e passare i numeri.
//
// La divisione è la stessa di `schermi.c`, e per la stessa ragione: un difetto
// in quel conto si vede come una finestra nel posto sbagliato — tardi, a mano,
// e solo se qualcuno ci passa sopra. Con i numeri separati si prova in un
// decimo di secondo.
//
// ── I due rettangoli non sono lo stesso rettangolo ───────────────────────
//
// La ZONA si decide sul rettangolo FISICO (sopra c'è la barra, e il puntatore
// la può toccare: chiedere l'aggancio da lassù è il gesto naturale). Il
// BERSAGLIO si calcola nello spazio UTILE, o la finestra finisce sotto la
// barra con la maniglia nascosta — difetto già pagato una volta in
// `spine/TitleBars.qml`.
//
// La conversione fra `wlr_box` e `riquadro` è scritta a mano e non è un cast:
// i campi oggi coincidono, ma affidarsi a questo vorrebbe dire che il giorno in
// cui wlroots ne aggiunge uno le finestre vanno in un posto a caso.
static struct riquadro da_box(const struct wlr_box *b) {
	return (struct riquadro){b->x, b->y, b->width, b->height};
}

static struct wlr_box a_box(const struct riquadro *r) {
	return (struct wlr_box){r->x, r->y, r->larghezza, r->altezza};
}

/// In quale zona cade il puntatore, e qual è lo spazio utile di quello schermo.
static enum zona_aggancio aggancio_zona(struct minerva *m, double px, double py,
                                        struct wlr_box *utile_fuori) {
	struct wlr_output *out = wlr_output_layout_output_at(m->schermi, px, py);
	if (out == NULL)
		return ZONA_NIENTE;

	struct wlr_box fisico;
	wlr_output_layout_get_box(m->schermi, out, &fisico);

	struct schermo *sc;
	wl_list_for_each(sc, &m->schermi_elenco, link) {
		if (sc->out == out) {
			if (utile_fuori != NULL)
				*utile_fuori = sc->utile;
			break;
		}
	}

	const struct riquadro f = da_box(&fisico);
	return aggancio_zona_di(&f, px, py);
}

/// Quanto è alta la nostra barra su questa finestra: zero se non le spetta o
/// se è a schermo intero.
static int finestra_barra_alta(const struct finestra *f) {
	return (f->decorata && !f->schermo_intero) ? barra_alta() : 0;
}

// ── A chi spetta una barra ────────────────────────────────────────────────
//
// Portato tale e quale da `plugins/minerva-bars/src/main.cpp`, perché è
// conoscenza pagata e non una preferenza:
//
//  · le finestre di Minerva la barra ce l'hanno già nel QML. `minerva-` è il
//    prefisso di tutte le nostre classi; `org.quickshell` è il nome che
//    Quickshell dà a chi non ne ha uno, e appena le nostre app hanno preso un
//    nome proprio si sono ritrovate DUE barre;
//  · i programmi che se la disegnano da soli (i browser, la roba GNOME) non
//    smettono di farlo perché glielo chiediamo: `xdg-decoration` lo
//    implementano in pochi, e chi non lo implementa non lo sa nemmeno.
static bool le_spetta(const struct minerva *m, const char *classe) {
	if (classe == NULL)
		return true;

	if (strncmp(classe, "minerva-", 8) == 0)
		return false;
	if (strcmp(classe, "org.quickshell") == 0 || strcmp(classe, "quickshell") == 0)
		return false;

	char bassa[256];
	size_t n = 0;
	for (; classe[n] != '\0' && n + 1 < sizeof(bassa); n++)
		bassa[n] = (char)tolower((unsigned char)classe[n]);
	bassa[n] = '\0';

	for (int i = 0; i < m->quanti_csd; i++) {
		if (m->csd[i][0] != '\0' && strstr(bassa, m->csd[i]) != NULL)
			return false;
	}
	return true;
}

// ── Chi ha la barra si decide DOPO, e il perché è costato ────────────────
//
// `le_spetta` guarda la classe della finestra. Ma alla nascita — cioè quando
// il programma chiede un `xdg_toplevel` — **la classe non c'è ancora**: la
// scrive subito dopo, prima della prima commit. Deciderlo alla nascita vuol
// dire deciderlo su una classe vuota, cioè dare la barra a tutti.
//
// Il sintomo si vede solo a schermo, e per questo è rimasto nascosto: le
// Impostazioni di Minerva dentro minerva-wayland comparivano con DUE barre
// del titolo, la nostra sopra la loro. È lo stesso difetto che il plugin
// aveva già avuto il giorno che le nostre app hanno preso un nome proprio
// (vedi la memoria `minerva-nomi-icone-app`), ripetuto qui perché il momento
// in cui si guarda la classe è diverso.
//
// Si chiama alla prima commit — dove la classe c'è — e alla mappatura, dove
// c'è di sicuro. Chiamarla due volte non costa niente: se la risposta non
// cambia non tocca nulla.
static void finestra_decidi_barra(struct finestra *f, const char *classe) {
	const bool spetta = le_spetta(f->m, classe) && !f->x11_senza_cornice
		&& !f->csd_richiesto;
	if (spetta == f->decorata && (!spetta || f->barra != NULL))
		return;

	f->decorata = spetta;
	if (spetta && f->barra == NULL) {
		f->barra = wlr_scene_buffer_create(f->cornice, NULL);
		if (f->barra != NULL)
			f->barra->node.data = f;
	} else if (!spetta && f->barra != NULL) {
		wlr_scene_node_destroy(&f->barra->node);
		f->barra = NULL;
		free(f->titolo_disegnato);
		f->titolo_disegnato = NULL;
	}
	// L'albero del programma comincia sotto la barra: se la barra è appena
	// comparsa o sparita, quel numero è cambiato.
	if (f->albero != NULL)
		wlr_scene_node_set_position(&f->albero->node, 0,
			finestra_barra_alta(f));
}

// ── Ridisegnare la barra, ma solo quando serve ───────────────────────────
//
// Un programma può cambiare titolo a ogni tasto premuto (un editor lo fa: il
// nome del file più un asterisco), e ogni ridisegno è una superficie cairo
// nuova più un buffer nuovo. Quindi si confronta prima con quello che la barra
// mostra ADESSO, e nel caso normale non si fa niente.
static void barra_aggiorna(struct finestra *f) {
	int larghezza, altezza;
	finestra_geometria(f, &larghezza, &altezza);
	if (larghezza <= 0 || altezza <= 0)
		return;

	// La presa per ridimensionare la tiene anche chi la barra se la disegna da
	// sé: anzi, quelli ne hanno più bisogno, perché senza di lei un browser
	// non si potrebbe ridimensionare per niente.
	const int alta = altezza + finestra_barra_alta(f);
	// Lo spessore dell'anello si sceglie; la presa no. Ma dove l'anello è più
	// grosso della presa, la presa lo segue: un bordo che si vede e non si
	// afferra è peggio di uno che non si vede.
	const int spesso = f->m->cornice_spessore > 0
		? f->m->cornice_spessore : BORDO_PRESA;
	const int presa = spesso > BORDO_PRESA ? spesso : BORDO_PRESA;
	if (f->maniglia != NULL) {
		wlr_scene_node_set_position(&f->maniglia->node, -presa, -presa);
		wlr_scene_rect_set_size(f->maniglia,
			larghezza + 2 * presa, alta + 2 * presa);
	}

	// ── L'anello: un rettangolo col buco ────────────────────────────────
	//
	// Grande quanto la finestra più sei pixel per lato, con dentro ritagliata
	// la finestra stessa. Gli angoli di fuori sono più aperti di sei di
	// quelli di dentro, o il bordo si assottiglierebbe proprio sulla curva —
	// è la stessa ragione per cui la cornice di un quadro ha lo smusso
	// esterno più largo di quello interno.
	if (f->anello != NULL) {
		const int raggio = f->schermo_intero ? 0 : ANGOLO_RAGGIO;
		wlr_scene_node_set_position(&f->anello->node, -spesso, -spesso);
		wlr_scene_rect_set_size(f->anello,
			larghezza + 2 * spesso, alta + 2 * spesso);
		wlr_minerva_rect_set_corners(f->anello,
			wlr_minerva_radii_all(raggio > 0 ? raggio + spesso : 0));
		// Il buco, in coordinate del rettangolo: la finestra comincia
		// «spesso» pixel dentro per lato.
		const struct wlr_minerva_clip buco = {
			.area = {
				.x = spesso,
				.y = spesso,
				.width = larghezza,
				.height = alta,
			},
			.corners = wlr_minerva_radii_all(raggio),
		};
		wlr_minerva_rect_set_hole(f->anello, buco);
	}

	// Il fondo sfocato: esattamente la finestra, barra compresa, con gli
	// stessi angoli. Un pixel più grande e si vedrebbe un alone sfocato
	// spuntare da sotto il bordo.
	if (f->sfocatura != NULL) {
		wlr_scene_node_set_position(&f->sfocatura->node, 0, 0);
		wlr_scene_rect_set_size(f->sfocatura, larghezza, alta);
		wlr_minerva_rect_set_corners(f->sfocatura,
			wlr_minerva_radii_all(f->schermo_intero ? 0 : ANGOLO_RAGGIO));
	}

	// ── E la trasparenza e gli angoli, per TUTTE ────────────────────────
	//
	// Qui sotto c'è un `return` per le finestre che si disegnano la barra da
	// sole, e da quel `return` in poi non passava più niente. La trasparenza
	// e gli angoli sui buffer nuovi li rimetteva `barra_aggiorna`, che sta
	// dopo — cioè **solo per le decorate**. Ogni cambio di misura toglieva il
	// vetro a Chrome, a Firefox e a tutte le finestre di Minerva, e non lo
	// rimetteva nessuno.
	//
	// Si vedeva così, ed è come l'ha trovato il banco delle manopole il 9
	// settembre 2026: nelle Impostazioni si muove «Quanto si vede
	// attraverso», il compositore riceve il valore giusto — `stato` lo
	// conferma, 0.56 — e le finestre restano opache. Perché il pannello,
	// insieme all'effetto, manda anche `aspetto`, che ridà la misura a ogni
	// finestra. Misurato dentro la finestra: (16,20,23) col pannello,
	// (78,49,76) mandando lo STESSO comando a mano.
	//
	// Costa una discesa dell'albero per ridimensionamento, non per fotogramma:
	// è lo stesso conto che `barra_aggiorna` fa già dall'altra parte.
	finestra_effetto(f);
	finestra_angoli(f);

	if (!f->decorata || f->barra == NULL)
		return;

	if (f->schermo_intero) {
		wlr_scene_node_set_enabled(&f->barra->node, false);
		return;
	}
	wlr_scene_node_set_enabled(&f->barra->node, true);

	const char *titolo = finestra_titolo(f);
	const bool fuoco = f->m->seat->keyboard_state.focused_surface
		== finestra_superficie(f);

	if (larghezza == f->larghezza_disegnata
			&& fuoco == f->fuoco_disegnato
			&& f->ingrandita == f->ingrandita_disegnata
			&& f->sotto_il_dito == f->dito_disegnato
			&& f->titolo_disegnato != NULL
			&& strcmp(titolo, f->titolo_disegnato) == 0)
		return;

	struct barra_stato stato = {
		.titolo = titolo,
		.larghezza = larghezza,
		.fuoco = fuoco,
		.ingrandita = f->ingrandita,
		.sotto_il_dito = f->sotto_il_dito,
		.corpo_unico = f->m->effetto_modo != EFFETTO_NESSUNO,
	};
	struct wlr_buffer *b = barra_disegna(&stato);
	if (b == NULL)
		return;

	// ── Cambiando larghezza si ridipinge TUTTA la vecchia barra ──────────
	//
	// Il difetto, visto guardando: aprendo un dialogo GTK dentro il nostro
	// compositore, la sua barra mostrava **due file di pulsanti sovrapposte**,
	// sfalsate di un centinaio di pixel — una sbiadita e una piena. Le stesse
	// «barre del titolo doppiate» che Giacomo ha segnalato il 30 agosto 2026.
	//
	// Non era il disegno: `barra_disegna` parte da una superficie nuova e
	// azzerata, e i pulsanti li mette una volta sola. Ed era davvero sullo
	// schermo e non un artefatto della fotografia — due scatti a distanza
	// erano identici. Ma **spostando la finestra spariva**, e questo dice
	// tutto: erano pixel vecchi rimasti dove nessuno era passato a ridipingere.
	//
	// Succede quando la larghezza cambia subito dopo la comparsa, cioè quando
	// è il programma a decidere la propria misura — i dialoghi, e chi riapre
	// con la geometria dell'ultima volta. Spegnere e riaccendere il nodo
	// dichiara come «sporche» sia la zona vecchia sia la nuova, che è
	// esattamente ciò che serve. Costa niente: succede solo quando la
	// larghezza cambia davvero, non a ogni lettera del titolo.
	const bool cambia_larghezza = f->larghezza_disegnata != 0
		&& larghezza != f->larghezza_disegnata;
	if (cambia_larghezza)
		wlr_scene_node_set_enabled(&f->barra->node, false);

	wlr_scene_buffer_set_buffer(f->barra, b);

	if (cambia_larghezza)
		wlr_scene_node_set_enabled(&f->barra->node, true);
	// La scena ne prende un riferimento suo: il nostro va lasciato, o la
	// memoria cresce di una barra a ogni lettera digitata.
	wlr_buffer_drop(b);

	// Prima la copia, poi la liberazione: al contrario, se `strdup` fallisce
	// resta un puntatore a memoria liberata — e questo campo lo rilegge il
	// confronto che decide se ridisegnare la barra, cioè un uso-dopo-la-
	// liberazione a ogni carattere digitato nel titolo.
	char *copia = strdup(titolo);
	if (copia != NULL) {
		free(f->titolo_disegnato);
		f->titolo_disegnato = copia;
	}
	f->larghezza_disegnata = larghezza;
	f->fuoco_disegnato = fuoco;
	f->ingrandita_disegnata = f->ingrandita;
	f->dito_disegnato = f->sotto_il_dito;

	// Il buffer è nuovo, quindi nasce opaco: senza questa riga la barra
	// tornerebbe piena a ogni lettera del titolo dentro una finestra
	// trasparente — lo stacco, di nuovo, e stavolta lampeggiante.
	finestra_effetto(f);
	finestra_angoli(f);
}

// Il vetro richiede esplicitamente trasparenza sull'intera finestra.
// Il blur invece rispetta l'alfa dei pixel forniti dall'app: non deve
// sbiadire pagine web, testo o giochi opachi. La nostra barra può restare
// traslucida. A schermo intero nessun modo forza l'opacità del client.
// Riapplicare anche ai buffer nuovi e dopo i cambi di modalità.
static void applica_alfa(struct wlr_scene_buffer *b, int sx, int sy, void *dati) {
	(void)sx; (void)sy;
	// La NOSTRA opacità, che si moltiplica con quella del programma. Con
	// `wlr_scene_buffer_set_opacity` si litigava con wlroots, che a ogni
	// commit rimetteva quella del programma: la superficie intera si
	// sporcava a ogni fotogramma col vetro acceso (23 settembre 2026).
	wlr_minerva_buffer_set_alpha(b, *(const float *)dati);
}

static void finestra_effetto(struct finestra *f) {
	if (f == NULL || f->cornice == NULL)
		return;
	const bool vetro = f->m->effetto_modo == EFFETTO_VETRO && !f->schermo_intero;
	const float a = vetro ? f->m->effetto_alfa : 1.0f;
	if (f->wobbly) wobbly_visita(f->wobbly, applica_alfa, (void *)&a);
	else wlr_scene_node_for_each_buffer(&f->cornice->node, applica_alfa, (void *)&a);
	// L'acquerello si vede solo dove la superficie è trasparente: anche la
	// barra del titolo prende l'opacità, o sarebbe l'unico pezzo pieno della
	// finestra.
	const bool filtro = f->m->effetto_modo == EFFETTO_ACQUERELLO;
	if (f->barra != NULL && !f->schermo_intero && filtro)
		wlr_scene_buffer_set_opacity(f->barra, f->m->effetto_alfa);

	// Il filtro si accende solo col suo modo, e mai a schermo intero: lì
	// dietro la finestra non c'è niente, e sarebbe un passaggio di disegno
	// pagato per niente su ogni fotogramma di un video.
	if (f->sfocatura != NULL)
		wlr_scene_node_set_enabled(&f->sfocatura->node, filtro && !f->schermo_intero);
}

// ── Mercurio: i ponti fra le finestre vicine ─────────────────────────────
//
// Le forme sono le finestre visibili (barra compresa), i ponti li calcola
// src/mercurio.c, e qui si mettono in scena: per ogni ponte un rettangolo
// grande quanto il suo riquadro, che si disegna solo dove l'unione morbida
// esce dalle finestre. Sotto, lo stesso filtro delle finestre (acquerello o
// blur); sopra, la tinta della barra del titolo con la trasparenza delle
// finestre. Così il collo fra due finestre è della loro stessa materia.
//
// Non partecipa chi si sta deformando o respirando (la sua forma vera non è
// il suo rettangolo), e con una finestra a schermo intero non c'è nessun
// ponte: sotto non si vede, e un filtro in scena toglierebbe lo scanout.
static void mercurio_aggiorna(struct minerva *m) {
	if (m->piano_mercurio == NULL)
		return;
	struct mercurio_forma forme[32];
	int quante = 0;
	struct mercurio_ponte ponti[12];
	int n = 0;
	if (m->mercurio_acceso && !m->bloccato && !schermo_intero_visibile(m)) {
		struct finestra *f;
		wl_list_for_each(f, &m->finestre_elenco, link) {
			if (quante >= 32)
				break;
			if (!finestra_visibile(f) || f->schermo_intero || f->wobbly != NULL
			    || f->respiro != RESPIRO_NIENTE)
				continue;
			int w, h;
			finestra_geometria(f, &w, &h);
			h += finestra_barra_alta(f);
			if (w <= 0 || h <= 0)
				continue;
			forme[quante++] = (struct mercurio_forma){
				{f->cornice->node.x, f->cornice->node.y, w, h}, ANGOLO_RAGGIO};
		}
		n = mercurio_ponti(forme, quante, MERCURIO_K, ponti, 12);
		// Troppe forme in un ponte: niente piuttosto che un collo tagliato.
		if (n < 0)
			n = 0;
	}

	const struct barra_aspetto *asp = barra_aspetto_ora();
	const bool filtro = m->effetto_modo == EFFETTO_ACQUERELLO;
	const float alfa = m->effetto_modo == EFFETTO_NESSUNO ? 1.0f : m->effetto_alfa;
	const float tinta[4] = {(float)asp->fondo_r * alfa, (float)asp->fondo_g * alfa,
		(float)asp->fondo_b * alfa, alfa};
	for (int i = 0; i < 12; i++) {
		if (i >= n) {
			if (m->ponte_nodi[i].tinta != NULL) {
				wlr_scene_node_set_enabled(&m->ponte_nodi[i].tinta->node, false);
				wlr_scene_node_set_enabled(&m->ponte_nodi[i].filtro->node, false);
			}
			continue;
		}
		if (m->ponte_nodi[i].tinta == NULL) {
			m->ponte_nodi[i].filtro = wlr_minerva_blur_create(m->piano_mercurio, 1, 1);
			m->ponte_nodi[i].tinta = wlr_scene_rect_create(m->piano_mercurio, 1, 1, tinta);
			if (m->ponte_nodi[i].filtro == NULL || m->ponte_nodi[i].tinta == NULL)
				return;
		}
		const struct riquadro d = ponti[i].dove;
		struct wlr_minerva_mercurio mm = {.quante = ponti[i].quante,
			.k = MERCURIO_K, .raggio = ANGOLO_RAGGIO};
		for (int j = 0; j < ponti[i].quante; j++) {
			const struct riquadro r = forme[ponti[i].forme[j]].r;
			mm.forme[j] = (struct wlr_fbox){r.x - d.x, r.y - d.y, r.larghezza, r.altezza};
		}
		struct wlr_scene_rect *nodi[2] = {m->ponte_nodi[i].filtro, m->ponte_nodi[i].tinta};
		for (int k = 0; k < 2; k++) {
			wlr_scene_node_set_position(&nodi[k]->node, d.x, d.y);
			wlr_scene_rect_set_size(nodi[k], d.larghezza, d.altezza);
			wlr_minerva_rect_set_mercurio(nodi[k], &mm);
		}
		wlr_scene_rect_set_color(m->ponte_nodi[i].tinta, tinta);
		wlr_scene_node_set_enabled(&m->ponte_nodi[i].filtro->node, filtro);
		wlr_scene_node_set_enabled(&m->ponte_nodi[i].tinta->node, true);
	}
	m->ponti = n;
}

// ── Gli angoli, e la giunzione con la barra ──────────────────────────────
//
// Erano nostri, in QML, e costavano QUINDICI megabyte per applicazione —
// misurati: 55 MB senza, 69-72 con. Tolti il 2 settembre 2026 con scritto
// accanto «si faranno nel COMPOSITORE», dove si pagano una volta sola e
// valgono anche per i programmi degli altri.
//
// ── Perché non basta arrotondare «la finestra» ───────────────────────────
//
// Perché una finestra qui è DUE nodi dentro la stessa cornice: la barra che
// disegniamo noi, sopra, e il programma sotto. Arrotondarli tutti e due allo
// stesso modo farebbe due rettangoli tondi appoggiati, con in mezzo una
// strozzatura — l'esatto contrario di «combaciano perfettamente».
//
// Quindi: alla barra i due angoli DI SOPRA, al programma i due DI SOTTO. In
// mezzo il taglio resta dritto, e i due pezzi sono un corpo solo.
//
// Le sottosuperfici — i menù a tendina, i tooltip, il video dentro un lettore
// — non si toccano: stanno in mezzo alla finestra, e arrotondarle vorrebbe
// dire smangiarne gli angoli in un punto qualunque dello schermo.
//
struct angoli_da_mettere {
	struct wlr_scene_buffer *barra;
	struct wlr_surface *superficie;
	bool decorata;
	int raggio;
};

static void applica_angoli(struct wlr_scene_buffer *b, int sx, int sy,
		void *dati) {
	(void)sx; (void)sy;
	const struct angoli_da_mettere *a = dati;
	struct wlr_minerva_radii r = {0, 0, 0, 0};
	const uint16_t g = (uint16_t)a->raggio;

	if (b == a->barra) {
		r.top_left = g;
		r.top_right = g;
	} else {
		// La superficie principale del programma, e non una qualunque delle
		// sue: `wlr_scene_surface_try_from_buffer` dice a chi appartiene
		// questo buffer, e si confronta con quella della finestra.
		struct wlr_scene_surface *s = wlr_scene_surface_try_from_buffer(b);
		if (s == NULL || s->surface != a->superficie)
			return;
		r.bottom_left = g;
		r.bottom_right = g;
		if (!a->decorata) {
			// Nessuna barra nostra: la finestra è tutta lì, e gli angoli
			// sono quattro. È il caso delle app di Minerva, che gli angoli
			// li avevano in QML e li hanno persi aspettando questo.
			r.top_left = g;
			r.top_right = g;
		}
	}
	wlr_minerva_buffer_set_corners(b, r);
}

static void finestra_angoli(struct finestra *f) {
	if (f == NULL || f->cornice == NULL)
		return;
	struct angoli_da_mettere a = {
		.barra = f->barra,
		.superficie = finestra_superficie(f),
		.decorata = f->decorata,
		// A schermo intero gli angoli tondi lascerebbero quattro spicchi di
		// scrivania negli angoli dello schermo. Un video non si guarda con
		// gli angoli smussati.
		.raggio = f->schermo_intero ? 0 : ANGOLO_RAGGIO,
	};
	if (f->wobbly) wobbly_visita(f->wobbly, applica_angoli, &a);
	else wlr_scene_node_for_each_buffer(&f->cornice->node, applica_angoli, &a);
}

/// Mette la finestra qui, con questa misura. `x, y` sono l'angolo della
/// CORNICE, cioè della barra: il programma comincia più in basso.
static void finestra_posiziona(struct finestra *f, int x, int y, int w, int h) {
	const int alta = finestra_barra_alta(f);
	f->posto_x = x;
	f->posto_y = y;
	wlr_scene_node_set_position(&f->cornice->node,
		x, y);
	if (f->albero != NULL)
		wlr_scene_node_set_position(&f->albero->node, 0, alta);
	if (w > 0 && h > alta)
		finestra_di_geometria(f, x, y + alta, w, h - alta);
}

/// Spostarla soltanto, senza toccarne la misura. È il trascinamento, ed è
/// una funzione a sé per una ragione che si vede solo con X11: una finestra
/// Wayland si sposta muovendo il suo nodo e basta, una X11 va anche
/// AVVISATA, o continua a credere di stare dove stava e ci apre i menù.
static void finestra_muovi(struct finestra *f, int x, int y) {
	// Il programma riceve la geometria logica; il proxy Wobbly deforma solo
	// il contenuto disegnato, non la posizione comunicata al client.
	f->posto_x = x;
	f->posto_y = y;
	wlr_scene_node_set_position(&f->cornice->node,
		x, y);
	if (f->razza != FINESTRA_X11)
		return;
	int w, h;
	finestra_geometria(f, &w, &h);
	finestra_di_geometria(f, x, y + finestra_barra_alta(f), w, h);
}

/// Dove sta la cornice adesso, misure comprese.
static void finestra_box(struct finestra *f, struct wlr_box *fuori) {
	wlr_scene_node_coords(&f->cornice->node, &fuori->x, &fuori->y);
	// Il nodo cornice conserva sempre la geometria logica, anche con Wobbly.
	finestra_geometria(f, &fuori->width, &fuori->height);
	fuori->height += finestra_barra_alta(f);
}

static void finestra_ingrandisci(struct finestra *f, bool si) {
	if (f->ingrandita == si)
		return;

	// L'elastico racconta il TRASCINAMENTO, non i salti. Una finestra che si
	// ingrandisce attraversa mezzo schermo in un fotogramma: lasciandogliela
	// inseguire, per mezzo secondo sarebbe disegnata cento pixel fuori dal
	// suo posto — che non è un rimbalzo, è un errore che sembra un rimbalzo.
	// E `finestra_box` qui sotto verrebbe letta con lo scarto addosso.
	molla_ferma_finestra(f);

	if (si) {
		finestra_box(f, &f->prima);
		// Ingrandita e agganciata sono due stati, e uno solo per volta: la
		// misura di prima è una sola, e adesso è quella dell'ingrandimento.
		f->agganciata = false;
		struct wlr_box utile;
		finestra_utile(f, &utile);
		f->ingrandita = true;
		finestra_di_ingrandita(f, true);
		finestra_posiziona(f, utile.x, utile.y, utile.width, utile.height);
	} else {
		f->ingrandita = false;
		finestra_di_ingrandita(f, false);
		finestra_posiziona(f, f->prima.x, f->prima.y,
			f->prima.width, f->prima.height);
	}
	barra_aggiorna(f);
	annuncia(f->m, "stato", f);
}

static void finestra_schermo_intero(struct finestra *f, bool si) {
	if (f->schermo_intero == si)
		return;

	if (si && !f->ingrandita)
		finestra_box(f, &f->prima);

	f->schermo_intero = si;
	finestra_di_schermo_intero(f, si);

	if (si) {
		struct wlr_box tutto = {0};
		struct wlr_output *out = wlr_output_layout_output_at(f->m->schermi,
			f->prima.x + f->prima.width / 2.0,
			f->prima.y + f->prima.height / 2.0);
		if (out == NULL)
			out = wlr_output_layout_output_at(f->m->schermi, 0, 0);
		wlr_output_layout_get_box(f->m->schermi, out, &tutto);
		// A schermo intero la barra sparisce del tutto: un film con
		// quarantadue pixel di barra sopra non è a schermo intero.
		finestra_posiziona(f, tutto.x, tutto.y, tutto.width, tutto.height);
		// Sopra ogni pannello, compresa la barra di Minerva.
		wlr_scene_node_reparent(&f->cornice->node, f->m->piano_intero);
		freno_aggiorna(f->m);
	} else {
		wlr_scene_node_reparent(&f->cornice->node, f->m->finestre);
		freno_aggiorna(f->m);
		if (f->ingrandita) {
			struct wlr_box utile;
			finestra_utile(f, &utile);
			finestra_posiziona(f, utile.x, utile.y, utile.width, utile.height);
		} else {
			finestra_posiziona(f, f->prima.x, f->prima.y,
				f->prima.width, f->prima.height);
		}
	}
	barra_aggiorna(f);
}

// ── Il «riduci» VERO ──────────────────────────────────────────────────────
//
// In Hyprland non esiste: Minerva lo finge spostando la finestra su una
// scrivania di servizio, e Chrome si BLOCCA perché la sua richiesta
// `set_minimized` viene ignorata (hyprwm/Hyprland #995). Qui è uno stato della
// finestra come gli altri — si nasconde il nodo e si passa il fuoco.
//
// ── La strada del ritorno, che per un pezzo non c'era ────────────────────
//
// Finché il canale non esisteva, una finestra ridotta qui dentro restava
// ridotta: il compositore sapeva nasconderla e nessuno sapeva chiedergli di
// riportarla su. Adesso la dock manda `riduci <finestra> no` e la finestra
// torna — resta nell'elenco anche da ridotta, ed è quello che permette alla
// dock di mostrarla spenta e di riaccenderla con un clic.
//
// Il fuoco non lo ridà questa funzione: lo chiede subito dopo la shell
// (`Windows.restore` → `focus`), che sa anche portarla davanti. Una finestra
// che torna su e resta dietro a quella che c'era sembra non essere tornata.
/// Si vede? Due condizioni, e nessun'altra: non è ridotta, e sta sulla
/// scrivania in uso.
///
/// Sta qui, in una funzione, per una ragione che si paga cara altrove: se
/// «acceso o spento» lo decidono due punti diversi del file — uno che guarda
/// `ridotta`, uno che guarda la scrivania — il secondo che scrive vince, e
/// una finestra ridotta riappare cambiando scrivania. Un solo posto che
/// decide, e chiamarlo ogni volta che una delle due cose cambia.
static bool finestra_visibile(struct finestra *f) {
	// ── Tre condizioni, e la terza è nata con X11 ────────────────────────
	//
	// Senza albero non c'è niente da mostrare, e per una finestra Wayland la
	// cosa non capita mai. Per una X11 sì: può restare viva e smappata — un
	// programma che nasconde una finestra invece di chiuderla — e in quel
	// momento della cornice resta solo la BARRA. Senza questa riga bastava
	// cambiare scrivania e tornare indietro per far ricomparire una striscia
	// col titolo di una finestra che non c'è.
	if (f->albero == NULL || !f->mappata_ora)
		return false;
	return !f->ridotta && f->scrivania == f->m->scrivania_attiva;
}

static void finestra_mostra_o_nascondi(struct finestra *f) {
	wlr_scene_node_set_enabled(&f->cornice->node, finestra_visibile(f));
	// Un film ridotto, o lasciato su un'altra scrivania, non frena più.
	if (f->schermo_intero)
		freno_aggiorna(f->m);
}

static void finestra_riduci(struct finestra *f, bool si) {
	if (f->ridotta == si)
		return;
	f->ridotta = si;
	// Riducendo, prima il risucchio: la finestra si nasconde davvero alla
	// fine (`respiro_fine`). Riportandola, si accende e ne esce.
	if (!(si && respiro_avvia(f, RESPIRO_RISUCCHIO)))
		finestra_mostra_o_nascondi(f);
	if (!si)
		respiro_avvia(f, RESPIRO_RITORNO);
	finestra_di_ridotta(f, si);
	if (si) {
		finestra_di_attiva(f, false);
		if (f->m->seat->keyboard_state.focused_surface
				== finestra_superficie(f))
			fuoco_alla_prossima(f->m);
	}
	annuncia(f->m, "stato", f);
}

// ── Le scrivanie ──────────────────────────────────────────────────────────
//
// Sotto Hyprland la shell manda `workspace 3` e la cosa succede. Qui dentro,
// fino a oggi, quella riga se ne andava **in silenzio**: `minerva_comando`
// rispondeva «verbo sconosciuto» a voce bassa e lo schermo non cambiava. È lo
// stesso modo in cui era sparito il «riduci» — un verbo di Hyprland scritto
// nella shell, e nessuno dall'altra parte.
//
// Non c'è nessuna animazione e nessuno scorrimento: si accendono le finestre
// giuste e si spengono le altre. Un compositore che nasconde una finestra non
// la distrugge, non la smappa e non le dice niente — il programma continua a
// vivere e a disegnare per conto suo, e riappare com'era. È esattamente ciò
// che NON succede con la scrivania di servizio di Hyprland usata come
// «riduci», dove Chrome si blocca.

/// Quante finestre ha quella scrivania. Serve a saltare le vuote col gesto
/// della rotellina, che è quello che fa `workspace e+1` in Hyprland.
static int scrivania_quante(struct minerva *m, int quale) {
	int quante = 0;
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (f->scrivania == quale && !f->ridotta)
			quante++;
	}
	return quante;
}

/// Passa alla scrivania `quale`. Torna false se non c'era niente da fare.
///
/// `prendi_il_fuoco` è falso per una sola strada: quella che arriva da
/// `fuoco_finestra`, cioè «porta davanti QUESTA finestra, che sta là». Lì il
/// fuoco lo dà chi ha chiamato, e darlo anche qui vorrebbe dire annunciare un
/// «fuoco» sulla finestra sbagliata un istante prima di quello giusto — chi
/// ascolta lo vede, e disegna due volte.
static bool scrivania_vai_ex(struct minerva *m, int quale, bool prendi_il_fuoco) {
	if (quale < 1 || quale > SCRIVANIE || quale == m->scrivania_attiva)
		return false;

	m->scrivania_attiva = quale;

	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link)
		finestra_mostra_o_nascondi(f);

	// ── Il fuoco, che è la metà che si dimentica ──────────────────────────
	//
	// Cambiare scrivania senza toccare il fuoco lascia la tastiera alla
	// finestra di prima, che adesso non si vede: si scrive in un posto
	// invisibile. `fuoco_alla_prossima` guarda `finestra_visibile`, quindi
	// prende la prima di QUESTA scrivania — e se non ce n'è nessuna toglie il
	// fuoco invece di lasciarlo appeso.
	//
	// Da bloccati non si tocca niente: il fuoco è del blocco, e questa
	// funzione non deve poter diventare una scorciatoia per riprenderselo.
	if (prendi_il_fuoco && !m->bloccato)
		fuoco_alla_prossima(m);

	annuncia_scrivania(m);
	return true;
}

static bool scrivania_vai(struct minerva *m, int quale) {
	return scrivania_vai_ex(m, quale, true);
}

/// La scrivania vicina, saltando le vuote. È il gesto della rotellina sopra i
/// pallini della barra, e sotto Hyprland è `workspace e+1`.
static void scrivania_vicina(struct minerva *m, bool avanti) {
	for (int passo = 1; passo <= SCRIVANIE; passo++) {
		int quale = m->scrivania_attiva + (avanti ? passo : -passo);
		// Si gira in tondo: dalla decima si torna alla prima. Fermarsi al
		// bordo vorrebbe dire una rotellina che smette di funzionare e non si
		// capisce perché.
		while (quale > SCRIVANIE)
			quale -= SCRIVANIE;
		while (quale < 1)
			quale += SCRIVANIE;
		if (scrivania_quante(m, quale) > 0) {
			scrivania_vai(m, quale);
			return;
		}
	}
	// Nessun'altra scrivania ha finestre: si resta dove si è. Portare su una
	// scrivania vuota col gesto della rotellina è il modo di perdere tutto
	// quello che si stava guardando senza aver chiesto niente.
}

/// Manda una finestra su una scrivania. `seguila` la porta con sé.
static void scrivania_porta(struct finestra *f, int quale, bool seguila) {
	struct minerva *m = f->m;
	if (quale < 1 || quale > SCRIVANIE)
		return;
	if (f->scrivania != quale) {
		f->scrivania = quale;
		// Stessa ragione dell'ingrandimento: una finestra che cambia
		// scrivania non «viaggia», sparisce e ricompare. Un elastico ancora
		// in corsa la farebbe ricomparire storta.
		molla_ferma_finestra(f);
		// Una finestra ridotta che viene mandata altrove smette di essere
		// ridotta: sono due modi di dire «non qui», e tenerli tutti e due
		// insieme dà una finestra che arriva sulla scrivania nuova e non si
		// vede lo stesso.
		f->ridotta = false;
		finestra_mostra_o_nascondi(f);
		if (!finestra_visibile(f)
				&& m->seat->keyboard_state.focused_surface
					== finestra_superficie(f))
			fuoco_alla_prossima(m);
		annuncia(m, "stato", f);
	}
	if (seguila) {
		scrivania_vai(m, quale);
		fuoco_finestra(m, f);
	}
}

// ── «La barra la disegno io», ma non subito ────────────────────────
//
// `xdg-decoration` è il protocollo con cui un programma chiede chi deve
// disegnare la cornice. Rispondere SERVER_SIDE è ciò che fa smettere Qt e GTK
// di disegnarsi la propria: senza, le finestre Qt hanno la loro barra E la
// nostra, che è il difetto delle «due barre del titolo».
//
// ── E qui c'è la trappola che ha fatto cadere il compositore ───────────
//
// La prima prova con le barre native è morta così, un secondo dopo l'avvio:
//
//     wlr_xdg_surface_schedule_configure: Assertion `surface->initialized'
//
// Rispondere è mandare una configure, e una configure non si può mandare a una
// superficie che non è ancora pronta a riceverla. Il programma crea l'oggetto
// «decorazione» SUBITO DOPO il toplevel e PRIMA della sua prima commit: se si
// risponde lì, si scrive su una superficie che non esiste ancora davvero.
//
// Non è un avviso, non è un ritorno d'errore: è un `assert` dentro wlroots, e
// porta giù tutto lo schermo. La risposta si rimanda quindi alla prima commit,
// che è esattamente il posto in cui la finestra diventa configurabile.

// ── «csd»: chi la barra se la disegna da solo ─────────────────────────────
//
// `csd firefox chromium org.gnome.` — pezzi di nome separati da spazi, e
// sostituiscono l'elenco intero. Sostituire e non aggiungere è la stessa
// scelta di `scorciatoie azzera`: aggiungendo, un nome tolto dal pannello
// resterebbe in vita fino al riavvio della sessione.
//
// `csd` da solo svuota la lista: vuol dire «la barra mettila a tutti», ed è un
// modo legittimo di configurarla.
//
// Dopo si RIDECIDE per ogni finestra già aperta. Senza, il cambio varrebbe
// solo per quelle che nascono dopo — e chi toglie Firefox dalla lista si
// aspetta che la barra compaia su quello che ha già aperto, non al prossimo
// avvio.
static void comando_csd(struct minerva *m, char *resto) {
	m->quanti_csd = 0;
	char *salva = NULL;
	for (char *t = strtok_r(resto, " \t", &salva);
	     t != NULL && m->quanti_csd < (int)(sizeof(m->csd) / sizeof(m->csd[0]));
	     t = strtok_r(NULL, " \t", &salva)) {
		if (t[0] == '\0')
			continue;
		snprintf(m->csd[m->quanti_csd], sizeof(m->csd[0]), "%s", t);
		// Il confronto si fa in minuscolo: la classe di una finestra può
		// arrivare scritta come le pare al programma.
		for (char *c = m->csd[m->quanti_csd]; *c != '\0'; c++)
			*c = (char)tolower((unsigned char)*c);
		m->quanti_csd++;
	}

	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		// Chi l'ha chiesto lui con xdg-decoration resta com'è: quella è una
		// scelta del programma, non nostra, e una lista non la annulla.
		if (f->csd_richiesto)
			continue;
		finestra_decidi_barra(f, finestra_classe(f));
		barra_aggiorna(f);
	}
}

// ── Chi ha già la sua barra non ne prende una seconda ────────────────────
//
// `xdg-decoration` è una TRATTATIVA, non un ordine: il programma dice cosa
// preferisce (`requested_mode`) e il compositore decide. Qui si rispondeva
// sempre e solo in base a `f->decorata`, **ignorando del tutto quello che il
// programma aveva chiesto**.
//
// Il difetto che ne veniva è quello che Giacomo ha segnalato il 30 agosto 2026:
// «finestre con barra del titolo doppiate». Un programma che implementa il
// protocollo per bene e chiede CLIENT_SIDE — «la disegno io» — se la vedeva
// negare, disegnava la sua comunque, e sopra ci mettevamo la nostra. Due barre
// sulla stessa finestra.
//
// La lista dei nomi in `le_spetta()` copriva i soliti (Firefox, Chrome, le app
// GNOME) e non poteva coprire gli altri: un programma nuovo non è in nessuna
// lista, e nessuna lista lo sarà mai. Chiederglielo è l'unico modo che scala.
//
// L'ordine delle tre risposte non è indifferente:
//
//  1. se Minerva ha deciso di NON decorarla (le nostre app, la lista dei CSD),
//     è CLIENT_SIDE e non si discute: la nostra barra non c'è;
//  2. se il programma ha chiesto CLIENT_SIDE, si dice di sì. È la riga nuova;
//  3. altrimenti SERVER_SIDE, che è il caso normale — la maggioranza dei
//     programmi non chiede niente, e la barra gliela mettiamo noi.
//
// Il caso 2 NON deve spegnere `f->decorata` da sé: quella è la decisione di
// Minerva su chi merita la barra, e serve anche altrove (l'altezza da togliere,
// il disegno della cornice). Si cambia solo la risposta al programma... e
// invece no: se lui la disegna e noi pure, siamo al punto di partenza. Va
// spenta, ed è il motivo per cui questa funzione prende `f` e non una copia.
static void decorazione_applica(struct finestra *f) {
	if (f->decorazione == NULL)
		return;
	if (!f->toplevel->base->initialized)
		return;

	enum wlr_xdg_toplevel_decoration_v1_mode modo =
		WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
	if (!f->decorata) {
		modo = WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
	} else if (f->decorazione->requested_mode
			== WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE) {
		modo = WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
		// Ha detto che se la disegna lui: la nostra si toglie di mezzo, o
		// sono due. Si passa da `finestra_decidi_barra` e non si tocca
		// `f->decorata` a mano: là dentro c'è anche il nodo della barra da
		// distruggere e l'albero del programma da rialzare di 42 pixel.
		f->csd_richiesto = true;
		finestra_decidi_barra(f, finestra_classe(f));
	}
	wlr_xdg_toplevel_decoration_v1_set_mode(f->decorazione, modo);
}

// ── La configure iniziale, senza la quale non compare NIENTE ─────────────
//
// È il difetto che ha reso nera la prima prova, e vale la pena scriverlo
// perché non dà nessun errore da nessuna parte.
//
// In xdg-shell il programma non disegna finché il compositore non gli ha detto
// «va bene, e queste sono le tue misure». Da wlroots 0.18 quel primo messaggio
// **lo deve mandare il compositore**: c'è un campo apposta, `initial_commit`,
// e chi non lo guarda lascia il programma ad aspettare per sempre.
//
// Visto succedere: alacritty era vivo, collegato al nostro socket, e la
// finestra non compariva. Nessun errore nel registro, nessuna riga, solo uno
// schermo nero — e il programma pazientemente in attesa di una risposta che
// non sarebbe mai arrivata.
static void finestra_commit(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, commit);
	if (f->toplevel->base->initial_commit) {
		// Misura `0, 0` vuol dire «scegli tu»: la correzione vera arriva alla
		// mappatura, quando la misura scelta si può finalmente leggere.
		wlr_xdg_toplevel_set_size(f->toplevel, 0, 0);
		// La classe adesso c'è: è arrivata con questa stessa commit.
		finestra_decidi_barra(f, finestra_classe(f));
		// Adesso sì: la superficie è pronta a ricevere una configure.
		decorazione_applica(f);
		return;
	}
	// La barra è larga quanto la finestra: se il programma si ridimensiona da
	// sé (e lo fanno tutti, all'avvio) la barra deve seguirlo.
	barra_aggiorna(f);
}

// ── La misura alla nascita ────────────────────────────────────────────────
//
// Ci sono programmi che si mostrano prima di sapere quanto sono grandi.
// Konsole è il capofila: nasce 263×100 — tre righe di testo — e solo dopo si
// sistema. Hyprland gli dà esattamente quello che chiede; noi no.
//
// La regola è quella misurata per il plugin (`plugins/minerva-bars/misura.hpp`)
// e vale solo dove ha senso: non si tocca chi una misura sensata ce l'ha, né
// chi una misura piccola la vuole davvero — le finestre di dialogo, che si
// riconoscono dall'avere un genitore.
static void finestra_misura_alla_nascita(struct finestra *f, struct wlr_box *utile,
		int *w, int *h) {
	finestra_geometria(f, w, h);
	if (*w <= 0 || *h <= 0) {
		*w = 800;
		*h = 520;
	}

	if (finestra_ha_genitore(f))
		return;
	int max_w, max_h;
	finestra_massimo(f, &max_w, &max_h);
	// Chi dichiara una misura massima piccola la vuole piccola davvero.
	if (max_w > 0 && max_w < 300)
		return;
	if (*w >= 300 && *h >= 180)
		return;

	int nw = (int)(utile->width * 0.6);
	int nh = (int)(utile->height * 0.6);
	if (nw < 800) nw = 800;
	if (nh < 520) nh = 520;
	if (nw > utile->width) nw = utile->width;
	if (nh > utile->height) nh = utile->height;
	if (max_w > 0 && nw > max_w)
		nw = max_w;
	if (max_h > 0 && nh > max_h)
		nh = max_h;
	*w = nw;
	*h = nh;
}

/// Il corpo vero della mappatura, staccato dal listener perché lo chiamano in
/// due: le finestre Wayland dal segnale della loro superficie, e quelle X11
/// da `x11_mappata`, che prima deve costruirsi l'albero di scena.
static void finestra_appare(struct finestra *f) {
	// La PRIMA comparsa respira (vedi `respiro_avvia`); una finestra che si
	// rimappa — un programma che si nasconde e si rimostra — no.
	const bool prima_volta = !f->comparsa;
	f->comparsa = true;
	f->mappata_ora = true;
	// Ultima occasione, e per una finestra X11 è l'unica: `WM_CLASS` X la
	// scrive quando la finestra si prepara a comparire.
	finestra_decidi_barra(f, finestra_classe(f));

	struct wlr_box utile;
	finestra_utile(f, &utile);

	int w, h;
	finestra_misura_alla_nascita(f, &utile, &w, &h);
	const int alta = finestra_barra_alta(f);

	// ── Al centro dello spazio UTILE, non dello schermo ──────────────────
	//
	// È lo stesso conto che fa `core/Windows.qml`, e per la stessa ragione:
	// centrando sullo schermo intero, metà delle finestre nasce con la barra
	// del titolo sotto la barra di Minerva — cioè senza maniglia per
	// spostarle.
	int x = utile.x + (utile.width - w) / 2;
	int y = utile.y + (utile.height - h - alta) / 2;
	if (x < utile.x) x = utile.x;
	if (y < utile.y) y = utile.y;

	finestra_posiziona(f, x, y, w, h + alta);
	barra_aggiorna(f);

	wlr_log(WLR_INFO, "minerva: finestra «%s» (%s) %dx%d a %d,%d%s",
		finestra_titolo(f), finestra_classe(f),
		w, h, x, y, f->decorata ? "" : "  senza barra nostra");

	// Prima si annuncia che esiste, POI le si dà il fuoco: `fuoco_finestra`
	// annuncia a sua volta, e un «fuoco» su una finestra di cui non si è mai
	// sentito parlare obbliga chi ascolta a ricostruire l'elenco da capo.
	annuncia(f->m, "aperta", f);

	// Una finestra appena aperta prende il fuoco. È la regola di Minerva e
	// non quella di tutti: le sue eccezioni (una finestra che nasce dietro)
	// arriveranno con le regole vere, e staranno in un posto solo.
	fuoco_finestra(f->m, f);

	// Una finestra può tornare mentre si guarda un'altra scrivania, o
	// mentre lei stessa è ridotta: chi decide se si vede resta uno solo.
	finestra_mostra_o_nascondi(f);

	// ── Quello che aveva già chiesto prima di comparire ──────────────────
	//
	// Giacomo, 5 settembre 2026: «tomb raider installato quando lo avvio non
	// si avvia a schermo intero ma ho la dock e la barra in alto».
	//
	// Un programma che vuole nascere a schermo intero lo chiede **prima di
	// comparire**: una finestra xdg manda `set_fullscreen` prima del primo
	// commit, una X11 si mette `_NET_WM_STATE_FULLSCREEN` fra le proprietà
	// iniziali. In tutti e due i casi la richiesta arriva quando la finestra
	// non c'è ancora:
	//
	//  · per una xdg, `chiede_schermo` esce subito perché
	//    `finestra_pronta()` è falsa — la superficie non è inizializzata;
	//  · per una X11 lo stato è già scritto alla nascita, e il segnale di
	//    CAMBIAMENTO non scatta mai.
	//
	// E qui non lo guardava nessuno. Risultato: il gioco si apriva come una
	// finestra qualunque, grande quanto lo schermo ma con la barra e la dock
	// sopra — che è esattamente quello che si vedeva.
	//
	// Si guarda adesso, che è il primo momento in cui ha senso: la finestra
	// esiste, è posizionata, e `finestra_schermo_intero` può fare il suo
	// mestiere. Lo stesso vale per «ingrandita», che ha la stessa storia.
	if (finestra_vuole_pieno(f)) {
		finestra_schermo_intero(f, true);
	} else if (finestra_vuole_ingrandita(f)) {
		finestra_ingrandisci(f, true);
	}

	// Nasce come una goccia che si posa. Non a schermo intero: un gioco o un
	// film che parte non deve «crescere», deve esserci.
	if (prima_volta && !f->schermo_intero)
		respiro_avvia(f, RESPIRO_NASCITA);
}

static void finestra_mappata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, mappata);
	finestra_appare(f);
	// Una finestra che nasce mentre il vetro è acceso deve nascere di vetro.
	// Senza questa riga sarebbe l'unica opaca sulla scrivania, e lo sarebbe
	// finché qualcuno non cambia l'impostazione — cioè probabilmente mai.
	finestra_effetto(f);
	finestra_angoli(f);
}

static void finestra_sparisce(struct finestra *f) {
	molla_ferma_finestra(f);
	// Prima di tutto il resto: non è più sullo schermo. Senza questa riga
	// una finestra che si nasconde invece di chiudersi lascia la barra.
	f->mappata_ora = false;
	finestra_mostra_o_nascondi(f);

	// Se si stava trascinando proprio questa, la presa muore con lei: senza,
	// il puntatore resta agganciato a una finestra che non c'è più.
	if (f->m->presa_di == f) {
		f->m->presa = PRESA_NIENTE;
		f->m->presa_di = NULL;
	}

	// Senza questa, chiudendo una finestra il fuoco resta su una superficie
	// che non c'è più e la tastiera smette di andare da qualche parte: si
	// digita e non succede niente, senza nessun errore.
	if (f->m->seat->keyboard_state.focused_surface
			== finestra_superficie(f))
		fuoco_alla_prossima(f->m);
}

static void finestra_smappata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, smappata);
	// La copia fatta alla richiesta di chiudere, se c'è, si ritira adesso.
	respiro_chiusura(f);
	finestra_sparisce(f);
}

static void finestra_distrutta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, distrutta);
	molla_ferma_finestra(f);
	if (f->fantasma_pronto != NULL) {
		fantasma_scarta(f->fantasma_pronto);
		f->fantasma_pronto = NULL;
	}

	// Si annuncia PRIMA di smontare: qui il toplevel esiste ancora e il
	// titolo si legge. Annunciando dopo, chi ascolta riceverebbe un oggetto
	// con l'indirizzo giusto e tutto il resto sbagliato — che è peggio di non
	// riceverlo, perché sembra buono.
	annuncia(f->m, "chiusa", f);

	if (f->m->presa_di == f) {
		f->m->presa = PRESA_NIENTE;
		f->m->presa_di = NULL;
	}
	wl_list_remove(&f->commit.link);
	wl_list_remove(&f->mappata.link);
	wl_list_remove(&f->smappata.link);
	wl_list_remove(&f->distrutta.link);
	wl_list_remove(&f->titolo_cambiato.link);
	wl_list_remove(&f->chiede_sposta.link);
	wl_list_remove(&f->chiede_ridimensiona.link);
	wl_list_remove(&f->chiede_ingrandisci.link);
	wl_list_remove(&f->chiede_schermo.link);
	wl_list_remove(&f->chiede_riduci.link);
	// La decorazione può morire prima o dopo di noi: chi arriva secondo trova
	// il puntatore già a NULL e non stacca due volte lo stesso ascolto.
	if (f->decorazione != NULL) {
		wl_list_remove(&f->decorazione_modo.link);
		wl_list_remove(&f->decorazione_via.link);
		f->decorazione = NULL;
	}
	if (f->razza == FINESTRA_X11) {
		wl_list_remove(&f->x_associa.link);
		wl_list_remove(&f->x_dissocia.link);
		wl_list_remove(&f->x_configura.link);
		wl_list_remove(&f->x_attiva.link);
		f->xsup->data = NULL;
	} else {
		f->toplevel->base->data = NULL;
	}
	wl_list_remove(&f->link);
	if (f->schermo_intero)
		freno_aggiorna(f->m);

	// ── La cornice va distrutta a mano, e non lo era mai stata ───────────
	//
	// 31 agosto 2026, Giacomo: «quando apro una finestra che non è di
	// Minerva rimane sempre la barra del titolo quando la chiudo».
	//
	// L'albero del PROGRAMMA se ne va da solo: è appeso alla superficie, e
	// il compositore di scena lo smonta con lei. La CORNICE no. L'abbiamo
	// creata noi con `wlr_scene_tree_create`, e dentro ci stanno la barra e
	// la maniglia: nessuno la distruggeva. Restava sullo schermo una
	// striscia col titolo di una finestra che non esiste più, e se ne
	// accumulava una a ogni finestra chiusa.
	//
	// Non si vedeva con le finestre di Minerva, e per questo è durato tanto:
	// quelle la barra ce l'hanno nel QML (`decorata` falso), quindi della
	// cornice restava la sola maniglia, che è trasparente. Invisibile, ma
	// non innocua: è un nodo CLICCABILE il cui `node.data` punta a questa
	// `struct finestra` che due righe più sotto è memoria liberata. Il
	// fantasma che si vedeva era il sintomo gentile di un uso dopo la
	// liberazione.
	wlr_scene_node_destroy(&f->cornice->node);

	free(f->titolo_disegnato);
	free(f);
}

static void finestra_titolo_cambiato(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, titolo_cambiato);
	barra_aggiorna(f);
	annuncia(f->m, "titolo", f);
}

// ── Quello che il programma CHIEDE ───────────────────────────────────────
//
// Sono richieste, non ordini, e la differenza conta: un programma che chiede
// di ingrandirsi senza che nessuno gliel'abbia detto è la ragione per cui
// certe finestre si aprivano già grandi. Qui si accetta, perché è quello che
// l'utente si aspetta dal pulsante dentro il programma — ma la decisione è
// nostra e sta in un posto solo.

/// La finestra è pronta a ricevere ordini? Per una xdg è una domanda vera —
/// prima della prima configure non lo è — per una X11 no: esiste già dal lato
/// del server X, e la domanda non ha senso.
static bool finestra_pronta(struct finestra *f) {
	if (f->razza == FINESTRA_X11)
		return true;
	return f->toplevel->base->initialized;
}

static void chiede_ingrandisci(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, chiede_ingrandisci);
	if (!finestra_pronta(f))
		return;
	finestra_ingrandisci(f, !f->ingrandita);
}

static void chiede_schermo(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, chiede_schermo);
	if (!finestra_pronta(f))
		return;
	// Le due razze dicono la stessa cosa in due campi diversi: la xdg in una
	// richiesta in attesa, la X11 nel proprio stato, che X ha già cambiato.
	finestra_schermo_intero(f, f->razza == FINESTRA_X11
		? f->xsup->fullscreen : f->toplevel->requested.fullscreen);
}

static void chiede_riduci(struct wl_listener *l, void *dati) {
	struct finestra *f = wl_container_of(l, f, chiede_riduci);
	if (!finestra_pronta(f))
		return;
	if (f->razza == FINESTRA_X11) {
		// Qui il «cosa» viaggia nell'evento e non nello stato: X manda
		// «riducimi» e «riportami su» sullo stesso segnale.
		const struct wlr_xwayland_minimize_event *e = dati;
		finestra_riduci(f, e != NULL ? e->minimize : true);
		return;
	}
	(void)dati;
	// ── La richiesta che Hyprland butta via ──────────────────────────────
	//
	// Chrome la manda e poi ASPETTA la risposta: ignorarla lo blocca, ed è
	// un difetto vero con un numero (hyprwm/Hyprland #995). Qui si risponde.
	finestra_riduci(f, f->toplevel->requested.minimized);
}

static void presa_stacca(struct minerva *m, struct finestra *f);

static void presa_inizia(struct finestra *f, int come, uint32_t bordi) {
	struct minerva *m = f->m;
	if (f->schermo_intero)
		return;
	molla_ferma_finestra(f);
	f->wobbly_fallita = false;

	m->presa = come;
	puntatore_consenti(m->puntatore, false);
	m->presa_di = f;
	m->presa_x = m->cursore->x;
	m->presa_y = m->cursore->y;
	m->presa_mossa = false;
	m->presa_bordi = bordi;
	finestra_box(f, &m->presa_box);
	// Chi la ridimensiona a mano ha deciso lui la misura: da quel momento
	// non c'è più nessuna «misura di prima» a cui tornare.
	if (come == PRESA_RIDIMENSIONA)
		f->agganciata = false;
}

static void chiede_sposta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, chiede_sposta);
	fuoco_finestra(f->m, f);
	presa_inizia(f, PRESA_SPOSTA, 0);
	f->m->presa_mossa = true;
	presa_stacca(f->m, f);
	// ── Anche chi si disegna la barra da solo trema ──────────────────
	//
	// Qui `presa_mossa` nasce già vera: il programma chiede di essere
	// spostato quando l'utente sta GIÀ trascinando la sua barra, non alla
	// pressione. Ma l'elastico partiva solo nel passaggio falso→vero dentro
	// `presa_avanti`, che da questa strada non si attraversa mai — quindi le
	// app di Minerva, Chrome e Firefox non tremavano, e nessun errore lo
	// diceva. Visto il 13 settembre 2026 provando con la Calcolatrice.
	molla_avvia(f);
}

static void chiede_ridimensiona(struct wl_listener *l, void *dati) {
	struct finestra *f = wl_container_of(l, f, chiede_ridimensiona);
	// Due strutture diverse per lo stesso numero. Leggere l'una credendo
	// che sia l'altra non dà nessun errore: dà dei lati sbagliati, cioè una
	// finestra che si allunga dalla parte opposta a quella che si tira.
	uint32_t bordi;
	if (f->razza == FINESTRA_X11) {
		const struct wlr_xwayland_resize_event *e = dati;
		bordi = e->edges;
	} else {
		const struct wlr_xdg_toplevel_resize_event *e = dati;
		bordi = e->edges;
	}
	fuoco_finestra(f->m, f);
	presa_inizia(f, PRESA_RIDIMENSIONA, bordi);
	f->m->presa_mossa = true;
}

// ── I menù ────────────────────────────────────────────────────────────────
//
// Giacomo, 6 settembre 2026: «sui browser almeno, e non so se altrove, abbiamo
// lo stesso problema: se clicco il tasto destro vale come sinistro. Ho testato
// su chrome e firefox e confermo».
//
// Il tasto non era sbagliato — misurato: il destro arriva `0x111` e viene
// consegnato `0x111`. Mancava quello che il tasto destro DEVE far comparire.
//
// In Wayland un menù non è disegnato dentro la finestra: è una superficie a
// sé, un `xdg_popup`, che il programma crea e il compositore deve mettere
// nella scena. Il nostro ascoltava solo `new_toplevel`, cioè le finestre vere,
// e i popup li lasciava cadere: menù contestuali, tendine, gli elenchi
// `<select>` di una pagina web, i suggerimenti. Il programma li apriva e non
// li disegnava nessuno.
//
// Un tasto destro che non fa comparire niente, agli occhi, è un tasto
// sinistro. Ecco perché sembrava un difetto dei pulsanti.
//
// I menù dei programmi X11 invece si vedevano da sempre, perché in X un menù è
// una finestra `override-redirect` e quella strada c'era già
// (`sovrapposta_mappata`). Da qui il fatto che il difetto si notasse sui
// browser Wayland e non dappertutto.
struct menu {
	struct minerva *m;
	struct wlr_xdg_popup *popup;
	struct wlr_scene_tree *albero;
	struct wl_listener commit;
	struct wl_listener distrutto;
};

/// L'albero della scena a cui appendere un menù, dato il suo genitore.
///
/// Il genitore può essere di tre razze, e ognuna tiene il proprio ponte
/// all'indietro in un posto suo: una finestra (`base->data` è la `finestra`),
/// un altro menù (un sottomenù: `base->data` è il `menu`), o un pannello della
/// shell (`ls->data` è l'`appoggiata`).
static struct wlr_scene_tree *albero_del_genitore(struct wlr_surface *genitore) {
	struct wlr_xdg_surface *xs =
		wlr_xdg_surface_try_from_wlr_surface(genitore);
	if (xs != NULL) {
		if (xs->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
			struct finestra *f = xs->data;
			return f != NULL ? f->albero : NULL;
		}
		if (xs->role == WLR_XDG_SURFACE_ROLE_POPUP) {
			struct menu *mn = xs->data;
			return mn != NULL ? mn->albero : NULL;
		}
		return NULL;
	}
	struct wlr_layer_surface_v1 *ls =
		wlr_layer_surface_v1_try_from_wlr_surface(genitore);
	if (ls != NULL) {
		struct appoggiata *a = ls->data;
		return (a != NULL && a->scena != NULL) ? a->scena->tree : NULL;
	}
	return NULL;
}

/// Alla PRIMA commit si dice al menù dove ha diritto di stare.
///
/// Senza, un menù aperto vicino al bordo dello schermo esce di lato e metà
/// delle voci non si leggono. `wlr_xdg_popup_unconstrain_from_box` lo fa
/// ribaltare dall'altra parte, ed è il motivo per cui i menù dei programmi
/// «sanno» aprirsi verso l'alto quando sono in fondo.
///
/// Il riquadro va dato nelle coordinate del GENITORE, non dello schermo: da
/// qui la sottrazione. Darlo in coordinate assolute non dà errore — dà menù
/// che si ribaltano quando non serve e escono quando servirebbe.
static void menu_commit(struct wl_listener *l, void *dati) {
	(void)dati;
	struct menu *mn = wl_container_of(l, mn, commit);
	if (!mn->popup->base->initial_commit)
		return;

	int gx = 0, gy = 0;
	if (mn->albero->node.parent != NULL)
		wlr_scene_node_coords(&mn->albero->node.parent->node, &gx, &gy);

	struct wlr_output *out = wlr_output_layout_output_at(mn->m->schermi,
		gx, gy);
	if (out == NULL)
		return;
	struct wlr_box b;
	wlr_output_layout_get_box(mn->m->schermi, out, &b);
	b.x -= gx;
	b.y -= gy;
	wlr_xdg_popup_unconstrain_from_box(mn->popup, &b);
}

static void menu_distrutto(struct wl_listener *l, void *dati) {
	(void)dati;
	struct menu *mn = wl_container_of(l, mn, distrutto);
	wl_list_remove(&mn->commit.link);
	wl_list_remove(&mn->distrutto.link);
	// L'albero della scena lo distrugge wlroots insieme alla superficie.
	free(mn);
}

static void menu_nuovo(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, menu_nuovo);
	struct wlr_xdg_popup *popup = dati;

	struct wlr_scene_tree *genitore = albero_del_genitore(popup->parent);
	if (m->traccia_menu)
		fprintf(stderr, "minerva-wayland: menù nuovo, genitore %s\n",
			genitore != NULL ? "trovato" : "NON TROVATO");
	if (genitore == NULL)
		return;
	enum tipo_nodo proprietario_tipo;
	void *proprietario = nodo_proprietario(&genitore->node, &proprietario_tipo);
	if (proprietario && proprietario_tipo == NODO_FINESTRA) {
		struct finestra *f = proprietario;
		molla_ferma_finestra(f);
		f->wobbly_fallita = true;
	}

	struct menu *mn = calloc(1, sizeof(*mn));
	if (mn == NULL)
		return;
	mn->m = m;
	mn->popup = popup;
	mn->albero = wlr_scene_xdg_surface_create(genitore, popup->base);
	if (mn->albero == NULL) {
		free(mn);
		return;
	}
	// I nodi del menù NON portano un proprietario: `nodo_proprietario` risale
	// l'albero e trova quello della finestra sotto, che è la risposta giusta
	// — un clic su un menù riguarda la finestra a cui appartiene.
	popup->base->data = mn;

	mn->commit.notify = menu_commit;
	wl_signal_add(&popup->base->surface->events.commit, &mn->commit);
	mn->distrutto.notify = menu_distrutto;
	wl_signal_add(&popup->base->events.destroy, &mn->distrutto);
	if (m->traccia_menu)
		fprintf(stderr, "minerva-wayland: menù appeso alla scena\n");
}

static void finestra_nuova(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, finestra_nuova);
	struct wlr_xdg_toplevel *toplevel = dati;

	struct finestra *f = calloc(1, sizeof(*f));
	if (f == NULL)
		return;
	f->tipo = NODO_FINESTRA;
	f->m = m;
	// Scritta anche se `calloc` l'avrebbe già messa a zero: è il campo su cui
	// tutto il file decide di che protocollo parlare, e un campo così non si
	// lascia dedurre dal valore implicito di una calloc.
	f->razza = FINESTRA_XDG;
	f->toplevel = toplevel;
	f->sotto_il_dito = -1;
	f->dito_disegnato = -1;
	// Non si decide adesso: la classe non c'è ancora. Vedi
	// `finestra_decidi_barra`, che è chiamata alla prima commit.
	f->decorata = false;

	// ── La cornice ───────────────────────────────────────────────────────
	//
	// Un albero che contiene la barra e il programma. È questo che si sposta
	// quando si trascina, ed è il motivo per cui la barra non ha niente da
	// inseguire: non è una superficie appoggiata sopra la finestra, è la
	// finestra.
	f->cornice = wlr_scene_tree_create(m->finestre);
	if (f->cornice == NULL) {
		free(f);
		return;
	}
	f->cornice->node.data = f;
	// Il ponte all'indietro: da una superficie xdg alla nostra finestra. Serve
	// a `decorazione_nuova`, che riceve la decorazione e non la finestra.
	toplevel->base->data = f;

	// Sotto a tutto, così il programma e la barra le stanno sopra e solo
	// l'anello di sei pixel intorno resta cliccabile.
	static const float invisibile[4] = {0.0f, 0.0f, 0.0f, 0.0f};
	f->maniglia = wlr_scene_rect_create(f->cornice, 1, 1, invisibile);
	if (f->maniglia != NULL)
		f->maniglia->node.data = f;
	// L'anello, sopra la maniglia e sotto il programma.
	// `node.data` come la maniglia: è un nodo nostro, e chi cerca cosa c'è
	// sotto il puntatore deve riconoscerlo come «bordo».
	f->anello = wlr_scene_rect_create(f->cornice, 1, 1, invisibile);
	if (f->anello != NULL)
		f->anello->node.data = f;
	// I quattro pezzi della striscia, vuoti e spenti. Nascono qui e non alla
	// prima accensione perché la finestra attiva cambia in continuazione, e
	// creare dei nodi nel mezzo di un cambio di fuoco vorrebbe dire un
	// fotogramma in cui la striscia non c'è. Senza immagine dentro non
	// costano niente.
	for (int i = 0; i < ANELLO_PEZZI; i++) {
		f->led[i] = wlr_scene_buffer_create(f->cornice, NULL);
		if (f->led[i] == NULL)
			continue;
		f->led[i]->node.data = f;
		wlr_scene_node_set_enabled(&f->led[i]->node, false);
	}

	// ── Il fondo sfocato, e va SOTTO ANCHE ALL'ANELLO ────────────────────
	//
	// Quello che sfoca è ciò che sta DIETRO la finestra, quindi va disegnato
	// prima di lei. «Prima di lei» però non bastava: nasceva dopo l'anello,
	// e allora fra le cose che sfoca c'era anche **l'anello colorato**.
	//
	// Il sintomo, che è quello che Giacomo ha visto: con la cornice che gira,
	// a cambiare colore non era solo il bordo — la sfocatura ne pescava la
	// tinta e la spalmava dentro la finestra, dai bordi verso il centro.
	// Misurato nella sessione annidata, due fotografie a mezzo secondo di
	// distanza col blur acceso: **la barra del titolo cambiava nel 93,5 % dei
	// punti**, mentre a effetto spento non cambiava nemmeno un pixel.
	//
	// `lower_to_bottom` e non l'ordine di creazione: la maniglia e l'anello
	// nascono prima per una ragione loro (chi sta sotto il puntatore), e
	// legare due ordini diversi allo stesso elenco è il modo di romperne uno
	// aggiustando l'altro.
	//
	// Nasce spento — lo accende `finestra_effetto` se il modo lo chiede.
	f->sfocatura = wlr_minerva_blur_create(f->cornice, 1, 1);
	if (f->sfocatura != NULL) {
		wlr_scene_node_lower_to_bottom(&f->sfocatura->node);
		wlr_scene_node_set_enabled(&f->sfocatura->node, false);
	}

	// Nasce dove si sta guardando. Non c'è altra risposta sensata: una
	// finestra aperta adesso la si è chiesta adesso.
	f->scrivania = m->scrivania_attiva;

	f->albero = wlr_scene_xdg_surface_create(f->cornice, toplevel->base);
	if (f->albero != NULL) {
		f->albero->node.data = f;
		wlr_scene_node_set_position(&f->albero->node, 0,
			finestra_barra_alta(f));
	}

	wl_list_insert(&m->finestre_elenco, &f->link);

	f->commit.notify = finestra_commit;
	wl_signal_add(&toplevel->base->surface->events.commit, &f->commit);
	f->mappata.notify = finestra_mappata;
	wl_signal_add(&toplevel->base->surface->events.map, &f->mappata);
	f->smappata.notify = finestra_smappata;
	wl_signal_add(&toplevel->base->surface->events.unmap, &f->smappata);
	f->distrutta.notify = finestra_distrutta;
	wl_signal_add(&toplevel->events.destroy, &f->distrutta);
	f->titolo_cambiato.notify = finestra_titolo_cambiato;
	wl_signal_add(&toplevel->events.set_title, &f->titolo_cambiato);
	f->chiede_sposta.notify = chiede_sposta;
	wl_signal_add(&toplevel->events.request_move, &f->chiede_sposta);
	f->chiede_ridimensiona.notify = chiede_ridimensiona;
	wl_signal_add(&toplevel->events.request_resize, &f->chiede_ridimensiona);
	f->chiede_ingrandisci.notify = chiede_ingrandisci;
	wl_signal_add(&toplevel->events.request_maximize, &f->chiede_ingrandisci);
	f->chiede_schermo.notify = chiede_schermo;
	wl_signal_add(&toplevel->events.request_fullscreen, &f->chiede_schermo);
	f->chiede_riduci.notify = chiede_riduci;
	wl_signal_add(&toplevel->events.request_minimize, &f->chiede_riduci);
}

// Quando il programma cambia idea. Succede poco, ma succede: GTK chiede la
// modalità client subito dopo l'avvio se lo si lascia fare. La risposta è
// sempre la nostra — è il compositore a decidere, non lui.
static void decorazione_modo(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, decorazione_modo);
	decorazione_applica(f);
}

static void decorazione_via(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, decorazione_via);
	wl_list_remove(&f->decorazione_modo.link);
	wl_list_remove(&f->decorazione_via.link);
	f->decorazione = NULL;
}

// Non risolve tutto, e va detto: i browser non implementano questo protocollo
// e la barra se la disegnano comunque. Per quelli c'è `le_spetta`, che è un
// elenco — brutto, ma è la stessa lista che Minerva usa già.
static void decorazione_nuova(struct wl_listener *l, void *dati) {
	(void)l;
	struct wlr_xdg_toplevel_decoration_v1 *d = dati;
	struct finestra *f = d->toplevel->base->data;
	if (f == NULL)
		return;

	f->decorazione = d;
	f->decorazione_modo.notify = decorazione_modo;
	wl_signal_add(&d->events.request_mode, &f->decorazione_modo);
	f->decorazione_via.notify = decorazione_via;
	wl_signal_add(&d->events.destroy, &f->decorazione_via);

	// Se la superficie è già pronta si risponde adesso; altrimenti ci pensa
	// `finestra_commit` alla prima commit. Vedi `decorazione_applica`.
	decorazione_applica(f);
}

// ══ XWayland ══════════════════════════════════════════════════════════════
//
// Steam, i giochi, Wine, e la lunga coda di programmi che non saranno mai
// portati a Wayland. Fino a qui minerva-wayland li lasciava semplicemente
// fuori: non partivano male, non si vedevano storti — non comparivano, perché
// senza un `DISPLAY` a cui collegarsi non c'era proprio niente a cui parlare.
//
// ── Le tre differenze che contano, e nessuna dà errore ───────────────────
//
//  1. **La superficie arriva dopo.** Una finestra X11 esiste dal lato del
//     server X prima che ci sia qualcosa da disegnare, e la superficie
//     Wayland le viene «associata» in un secondo momento — e può andarsene e
//     tornare senza che la finestra muoia. Costruire l'albero di scena alla
//     nascita, come si fa per le xdg, vuol dire costruirlo sul nulla.
//
//  2. **Le coordinate sono assolute e il programma le vuole sapere.** Una
//     finestra Wayland non sa dove sta e non le serve; una X11 ci calcola
//     sopra la posizione dei propri menù. Spostarla senza dirglielo dà
//     menù nell'angolo in alto a sinistra, senza nessun errore.
//
//  3. **Il pid è uno solo per tutti.** Dal lato Wayland il client è uno —
//     Xwayland — quindi `wl_client_get_credentials` darebbe lo stesso numero
//     a Steam, al suo negozio e a ogni gioco. Il pid vero lo dichiara la
//     finestra con `_NET_WM_PID`. Vedi `finestra_pid`.
//
// ── E le finestre «override redirect», che non sono finestre ─────────────
//
// Un menù a tendina, un suggerimento, l'icona che segue il dito mentre si
// trascina: in X11 sono finestre come le altre, con un flag che dice «il
// gestore non mi tocchi». Vivono in `struct sovrapposta` e non in
// `struct finestra`, e la ragione sta scritta là.

/// A una finestra X11 la barra spetta con due condizioni in più rispetto a
/// una Wayland, e tutte e due vengono da vent'anni di convenzioni X.
static bool le_spetta_x11(struct wlr_xwayland_surface *x) {
	// «Niente cornice, grazie»: lo dicono gli splash screen all'avvio e i
	// giochi a schermo intero, con un'estensione di Motif che wlroots ha già
	// letto per noi. Metterci una barra sopra vuol dire una striscia grigia
	// in cima al gioco.
	if (x->decorations != WLR_XWAYLAND_SURFACE_DECORATIONS_ALL)
		return false;

	// E se dichiara di essere qualcosa che non è una finestra normale né un
	// dialogo — un menù, una notifica, una barra degli strumenti staccata —
	// non la si decora. Chi non dichiara niente è normale: è il valore
	// implicito di `_NET_WM_WINDOW_TYPE`.
	if (x->window_type_len > 0
			&& !wlr_xwayland_surface_has_window_type(x,
				WLR_XWAYLAND_NET_WM_WINDOW_TYPE_NORMAL)
			&& !wlr_xwayland_surface_has_window_type(x,
				WLR_XWAYLAND_NET_WM_WINDOW_TYPE_DIALOG))
		return false;

	// La classe non si guarda qui: la guarda `finestra_decidi_barra`, che è
	// la stessa per tutte e due le razze. Questa funzione risponde soltanto
	// alle due domande che in Wayland non esistono.
	return true;
}

static void x11_commit(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, commit);
	// L'equivalente X11 di `finestra_commit`, meno la parte che qui non
	// esiste: non c'è nessuna «prima configure» da mandare, perché la
	// finestra dal lato di X è già viva e già misurata.
	barra_aggiorna(f);
}

static void x11_mappata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, mappata);
	struct wlr_surface *s = f->xsup->surface;
	if (s == NULL)
		return;

	// ── Le due condizioni in più che valgono solo per X11 ────────────────
	//
	// «Niente cornice, grazie» e il tipo di finestra: le decide
	// `le_spetta_x11`, e se dice di no la barra non spetta comunque, quale
	// che sia la classe. Il resto — la classe — lo decide
	// `finestra_decidi_barra` da `finestra_appare`, qui sotto.
	f->x11_senza_cornice = !le_spetta_x11(f->xsup);

	f->albero = wlr_scene_subsurface_tree_create(f->cornice, s);
	if (f->albero != NULL) {
		f->albero->node.data = f;
		wlr_scene_node_set_position(&f->albero->node, 0,
			finestra_barra_alta(f));
	}

	f->commit.notify = x11_commit;
	wl_signal_add(&s->events.commit, &f->commit);

	finestra_appare(f);
	// Una finestra può tornare mentre si guarda un'altra scrivania, o
	// mentre lei stessa è ridotta: chi decide se si vede è uno solo.
	finestra_mostra_o_nascondi(f);
}

static void x11_smappata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, smappata);

	finestra_sparisce(f);

	wl_list_remove(&f->commit.link);
	wl_list_init(&f->commit.link);

	if (f->albero != NULL) {
		wlr_scene_node_destroy(&f->albero->node);
		f->albero = NULL;
	}
	// Senza questa riga sparisce il programma e resta la BARRA: una striscia
	// col titolo di una finestra che non c'è, e la maniglia intorno al
	// nulla. Si passa da `finestra_mostra_o_nascondi` e non si spegne il
	// nodo a mano perché chi decide se una finestra si vede deve restare
	// uno solo — è la stessa ragione per cui `finestra_visibile` esiste.
	finestra_mostra_o_nascondi(f);
}

static void x11_associa(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, x_associa);
	struct wlr_surface *s = f->xsup->surface;
	if (s == NULL)
		return;
	f->mappata.notify = x11_mappata;
	wl_signal_add(&s->events.map, &f->mappata);
	f->smappata.notify = x11_smappata;
	wl_signal_add(&s->events.unmap, &f->smappata);
}

static void x11_dissocia(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, x_dissocia);
	// Si stacca e si RIAZZERA: la finestra può vivere ancora a lungo senza
	// superficie, e la distruzione staccherà di nuovo. Un `wl_list_remove`
	// su un ascolto già staccato e non riazzerato è memoria altrui.
	wl_list_remove(&f->mappata.link);
	wl_list_init(&f->mappata.link);
	wl_list_remove(&f->smappata.link);
	wl_list_init(&f->smappata.link);

	// Di norma la smappatura arriva prima, e qui non c'è più niente da fare.
	// Ma «di norma» non è una garanzia, e un albero di scena appeso a una
	// superficie che sta per sparire è la definizione di memoria altrui.
	if (f->albero != NULL) {
		wlr_scene_node_destroy(&f->albero->node);
		f->albero = NULL;
		finestra_mostra_o_nascondi(f);
	}
}

// ── «Vorrei stare qui, ed essere grande così» ────────────────────────────
//
// In X11 il programma non chiede: agisce, e il gestore decide se
// assecondarlo. Prima della mappatura gli si dà quello che vuole — è così che
// impara le proprie misure mentre si prepara. Dopo, la posizione la decide
// Minerva (le finestre nascono al centro dello spazio utile, e ci restano
// finché non le si sposta), la misura invece gliela si concede: in una
// scrivania dove tutto è flottante, un programma che si ridimensiona da sé
// sta facendo una cosa legittima.
static void x11_configura_chiesta(struct wl_listener *l, void *dati) {
	struct finestra *f = wl_container_of(l, f, x_configura);
	struct wlr_xwayland_surface_configure_event *e = dati;

	if (f->xsup->surface == NULL || !f->xsup->surface->mapped) {
		wlr_xwayland_surface_configure(f->xsup, e->x, e->y, e->width, e->height);
		return;
	}

	struct wlr_box b;
	finestra_box(f, &b);
	const int alta = finestra_barra_alta(f);

	// Ingrandita o a schermo intero la misura è già decisa da noi: si
	// RICONFERMA quella vera invece di accettare. Senza, un programma che
	// insiste si ritrova convinto di una misura che non ha.
	if (f->ingrandita || f->schermo_intero) {
		finestra_di_geometria(f, b.x, b.y + alta, b.width, b.height - alta);
		return;
	}
	finestra_posiziona(f, b.x, b.y, e->width, e->height + alta);
	barra_aggiorna(f);
}

/// «Dammi il fuoco». Lo manda chi si è appena aperto in secondo piano e vuole
/// venire davanti: un aggiornamento di Steam, un dialogo di errore.
static void x11_chiede_fuoco(struct wl_listener *l, void *dati) {
	(void)dati;
	struct finestra *f = wl_container_of(l, f, x_attiva);
	if (f->xsup->surface == NULL || !f->xsup->surface->mapped)
		return;
	fuoco_finestra(f->m, f);
}

static void finestra_x11_nuova(struct minerva *m, struct wlr_xwayland_surface *x) {
	struct finestra *f = calloc(1, sizeof(*f));
	if (f == NULL)
		return;
	f->tipo = NODO_FINESTRA;
	f->m = m;
	f->razza = FINESTRA_X11;
	f->xsup = x;
	f->sotto_il_dito = -1;
	f->dito_disegnato = -1;
	// Si decide alla mappatura, quando `WM_CLASS` esiste. Vedi `x11_mappata`.
	f->decorata = false;

	f->cornice = wlr_scene_tree_create(m->finestre);
	if (f->cornice == NULL) {
		free(f);
		return;
	}
	f->cornice->node.data = f;
	x->data = f;

	static const float invisibile[4] = {0.0f, 0.0f, 0.0f, 0.0f};
	f->maniglia = wlr_scene_rect_create(f->cornice, 1, 1, invisibile);
	if (f->maniglia != NULL)
		f->maniglia->node.data = f;
	// L'anello, sopra la maniglia e sotto il programma.
	// `node.data` come la maniglia: è un nodo nostro, e chi cerca cosa c'è
	// sotto il puntatore deve riconoscerlo come «bordo».
	f->anello = wlr_scene_rect_create(f->cornice, 1, 1, invisibile);
	if (f->anello != NULL)
		f->anello->node.data = f;
	// I quattro pezzi della striscia, vuoti e spenti. Nascono qui e non alla
	// prima accensione perché la finestra attiva cambia in continuazione, e
	// creare dei nodi nel mezzo di un cambio di fuoco vorrebbe dire un
	// fotogramma in cui la striscia non c'è. Senza immagine dentro non
	// costano niente.
	for (int i = 0; i < ANELLO_PEZZI; i++) {
		f->led[i] = wlr_scene_buffer_create(f->cornice, NULL);
		if (f->led[i] == NULL)
			continue;
		f->led[i]->node.data = f;
		wlr_scene_node_set_enabled(&f->led[i]->node, false);
	}

	// ── Il fondo sfocato, e va SOTTO ANCHE ALL'ANELLO ────────────────────
	//
	// Quello che sfoca è ciò che sta DIETRO la finestra, quindi va disegnato
	// prima di lei. «Prima di lei» però non bastava: nasceva dopo l'anello,
	// e allora fra le cose che sfoca c'era anche **l'anello colorato**.
	//
	// Il sintomo, che è quello che Giacomo ha visto: con la cornice che gira,
	// a cambiare colore non era solo il bordo — la sfocatura ne pescava la
	// tinta e la spalmava dentro la finestra, dai bordi verso il centro.
	// Misurato nella sessione annidata, due fotografie a mezzo secondo di
	// distanza col blur acceso: **la barra del titolo cambiava nel 93,5 % dei
	// punti**, mentre a effetto spento non cambiava nemmeno un pixel.
	//
	// `lower_to_bottom` e non l'ordine di creazione: la maniglia e l'anello
	// nascono prima per una ragione loro (chi sta sotto il puntatore), e
	// legare due ordini diversi allo stesso elenco è il modo di romperne uno
	// aggiustando l'altro.
	//
	// Nasce spento — lo accende `finestra_effetto` se il modo lo chiede.
	f->sfocatura = wlr_minerva_blur_create(f->cornice, 1, 1);
	if (f->sfocatura != NULL) {
		wlr_scene_node_lower_to_bottom(&f->sfocatura->node);
		wlr_scene_node_set_enabled(&f->sfocatura->node, false);
	}

	f->scrivania = m->scrivania_attiva;

	// Spenta finché non si mappa: la cornice esiste da adesso, il programma
	// dentro no, e una maniglia intorno al vuoto si può afferrare. Va DOPO
	// `scrivania`, che è una delle tre cose che la decisione guarda.
	finestra_mostra_o_nascondi(f);

	wl_list_insert(&m->finestre_elenco, &f->link);

	// ── I tre ascolti che ancora non esistono ────────────────────────────
	//
	// `commit`, `mappata` e `smappata` vivono sulla SUPERFICIE, che qui non
	// c'è ancora. Si inizializzano vuoti perché `finestra_distrutta` li
	// stacca tutti e tre senza chiedersi di che razza sia la finestra — e
	// staccare un ascolto mai attaccato, su una lista non inizializzata, è
	// scrivere in memoria a caso.
	wl_list_init(&f->commit.link);
	wl_list_init(&f->mappata.link);
	wl_list_init(&f->smappata.link);

	f->x_associa.notify = x11_associa;
	wl_signal_add(&x->events.associate, &f->x_associa);
	f->x_dissocia.notify = x11_dissocia;
	wl_signal_add(&x->events.dissociate, &f->x_dissocia);
	f->distrutta.notify = finestra_distrutta;
	wl_signal_add(&x->events.destroy, &f->distrutta);
	f->titolo_cambiato.notify = finestra_titolo_cambiato;
	wl_signal_add(&x->events.set_title, &f->titolo_cambiato);
	f->x_configura.notify = x11_configura_chiesta;
	wl_signal_add(&x->events.request_configure, &f->x_configura);
	f->x_attiva.notify = x11_chiede_fuoco;
	wl_signal_add(&x->events.request_activate, &f->x_attiva);
	f->chiede_sposta.notify = chiede_sposta;
	wl_signal_add(&x->events.request_move, &f->chiede_sposta);
	f->chiede_ridimensiona.notify = chiede_ridimensiona;
	wl_signal_add(&x->events.request_resize, &f->chiede_ridimensiona);
	f->chiede_ingrandisci.notify = chiede_ingrandisci;
	wl_signal_add(&x->events.request_maximize, &f->chiede_ingrandisci);
	f->chiede_schermo.notify = chiede_schermo;
	wl_signal_add(&x->events.request_fullscreen, &f->chiede_schermo);
	f->chiede_riduci.notify = chiede_riduci;
	wl_signal_add(&x->events.request_minimize, &f->chiede_riduci);
}

// ── Le sovrapposte ───────────────────────────────────────────────────────

static void sovrapposta_mappata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct sovrapposta *s = wl_container_of(l, s, mappata);
	if (s->xsup->surface == NULL)
		return;

	// Dentro `m->finestre` e non in un piano suo: un menù di un programma
	// X11 deve stare sopra le finestre e SOTTO la barra di Minerva, che è
	// esattamente il posto in cui vivono le finestre.
	s->albero = wlr_scene_subsurface_tree_create(s->m->finestre,
		s->xsup->surface);
	if (s->albero == NULL)
		return;
	s->albero->node.data = s;
	wlr_scene_node_set_position(&s->albero->node, s->xsup->x, s->xsup->y);
	wlr_scene_node_raise_to_top(&s->albero->node);

	// ── Il fuoco che a certi menù serve davvero ──────────────────────────
	//
	// La regola X è «le override redirect non si toccano», ma alcune la
	// tastiera la vogliono: i lanciatori tipo rofi, le caselle di ricerca.
	// In X ci arrivano rubando l'input al server, una strada che sotto
	// Wayland non c'è. wlroots offre il criterio che usano tutti — è una
	// stima sul tipo di finestra, non una certezza, e va bene così.
	if (!s->m->bloccato
			&& wlr_xwayland_surface_override_redirect_wants_focus(s->xsup))
		fuoco_tastiera(s->m, s->xsup->surface);
}

static void sovrapposta_smappata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct sovrapposta *s = wl_container_of(l, s, smappata);

	if (s->xsup->surface != NULL
			&& s->m->seat->keyboard_state.focused_surface == s->xsup->surface)
		fuoco_alla_prossima(s->m);

	if (s->albero != NULL) {
		wlr_scene_node_destroy(&s->albero->node);
		s->albero = NULL;
	}
}

/// Un menù si sposta mentre è aperto — succede coi sottomenù, che scorrono
/// per restare dentro lo schermo. La posizione la decide il programma, e qui
/// si esegue e basta.
static void sovrapposta_spostata(struct wl_listener *l, void *dati) {
	(void)dati;
	struct sovrapposta *s = wl_container_of(l, s, spostata);
	if (s->albero != NULL)
		wlr_scene_node_set_position(&s->albero->node, s->xsup->x, s->xsup->y);
}

static void sovrapposta_associa(struct wl_listener *l, void *dati) {
	(void)dati;
	struct sovrapposta *s = wl_container_of(l, s, associa);
	if (s->xsup->surface == NULL)
		return;
	s->mappata.notify = sovrapposta_mappata;
	wl_signal_add(&s->xsup->surface->events.map, &s->mappata);
	s->smappata.notify = sovrapposta_smappata;
	wl_signal_add(&s->xsup->surface->events.unmap, &s->smappata);
}

static void sovrapposta_dissocia(struct wl_listener *l, void *dati) {
	(void)dati;
	struct sovrapposta *s = wl_container_of(l, s, dissocia);
	wl_list_remove(&s->mappata.link);
	wl_list_init(&s->mappata.link);
	wl_list_remove(&s->smappata.link);
	wl_list_init(&s->smappata.link);
}

static void sovrapposta_distrutta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct sovrapposta *s = wl_container_of(l, s, distrutta);
	if (s->albero != NULL) {
		wlr_scene_node_destroy(&s->albero->node);
		s->albero = NULL;
	}
	wl_list_remove(&s->associa.link);
	wl_list_remove(&s->dissocia.link);
	wl_list_remove(&s->mappata.link);
	wl_list_remove(&s->smappata.link);
	wl_list_remove(&s->distrutta.link);
	wl_list_remove(&s->spostata.link);
	wl_list_remove(&s->link);
	s->xsup->data = NULL;
	free(s);
}

static void sovrapposta_nuova(struct minerva *m, struct wlr_xwayland_surface *x) {
	struct sovrapposta *s = calloc(1, sizeof(*s));
	if (s == NULL)
		return;
	s->tipo = NODO_SOVRAPPOSTA;
	s->m = m;
	s->xsup = x;
	x->data = s;
	wl_list_insert(&m->sovrapposte, &s->link);

	wl_list_init(&s->mappata.link);
	wl_list_init(&s->smappata.link);

	s->associa.notify = sovrapposta_associa;
	wl_signal_add(&x->events.associate, &s->associa);
	s->dissocia.notify = sovrapposta_dissocia;
	wl_signal_add(&x->events.dissociate, &s->dissocia);
	s->distrutta.notify = sovrapposta_distrutta;
	wl_signal_add(&x->events.destroy, &s->distrutta);
	s->spostata.notify = sovrapposta_spostata;
	wl_signal_add(&x->events.set_geometry, &s->spostata);
}

// ── Il bivio, e il limite dichiarato ─────────────────────────────────────
//
// `override_redirect` si legge alla nascita — X lo porta nell'evento di
// creazione della finestra — e da lì non si guarda più. Un programma può
// cambiarlo dopo (`set_override_redirect`): succede raramente, e quando
// succede qui la finestra resta della forma con cui è nata. È un limite
// noto, scritto invece che nascosto: sistemarlo vuol dire smontare una
// rappresentazione e ricostruire l'altra a finestra viva, e non vale il
// rischio finché non si vede un programma vero che ne ha bisogno.
static void xwayland_superficie_nuova(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, x_superficie_nuova);
	struct wlr_xwayland_surface *x = dati;

	if (x->override_redirect)
		sovrapposta_nuova(m, x);
	else
		finestra_x11_nuova(m, x);
}

static void xwayland_pronto(struct wl_listener *l, void *dati) {
	(void)dati;
	struct minerva *m = wl_container_of(l, m, x_pronto);
	// Il posto glielo si ridà adesso: con l'avvio pigro, Xwayland parte molto
	// dopo di noi, e prima di partire non aveva nessuno a cui chiedere la
	// tastiera.
	wlr_xwayland_set_seat(m->xwayland, m->seat);
	wlr_log(WLR_INFO, "minerva: XWayland pronto su %s",
		m->xwayland->display_name != NULL ? m->xwayland->display_name : "?");
}

// ── Tastiera e puntatore ──────────────────────────────────────────────────
//
// Senza queste la scrivania si vede e non si tocca. Sono anche la parte in cui
// il compositore fa da tramite e basta: wlroots raccoglie dall'hardware, noi
// decidiamo A CHI mandare, e il `wlr_seat` lo consegna.

static void tastiera_modificatori(struct wl_listener *l, void *dati) {
	(void)dati;
	struct tastiera *t = wl_container_of(l, t, modificatori);
	// Il seat ha una tastiera attiva per volta: gliela si dice a ogni evento
	// perché con due tastiere collegate (quella del portatile e una esterna)
	// i modificatori devono venire da quella che si sta usando davvero.
	wlr_seat_set_keyboard(t->m->seat, t->kb);
	wlr_seat_keyboard_notify_modifiers(t->m->seat, &t->kb->modifiers);
}

// ── Le scorciatoie ────────────────────────────────────────────────────────
//
// Qui dentro non si legge `config/scorciatoie.minerva`, e non è pigrizia: quel
// file ha le variabili, i flag e le annotazioni, e un secondo parser sarebbe
// un secondo posto che un giorno non è più d'accordo col primo. Lo legge il
// demone — che già lo fa per il promemoria di Super+K e per i tasti di
// Hyprland — e la shell manda qui delle righe già masticate:
//
//     scorciatoie azzera
//     scorciatoia SUPER K minerva:cheatsheet
//     scorciatoia SUPER+SHIFT 1 porta-a-scrivania:1
//     scorciatoia - XF86AudioRaiseVolume minerva:volume-su bloccato
//
// ── Il tasto si riconosce SENZA i modificatori applicati ─────────────────
//
// È la parte che sbaglia chiunque la scriva la prima volta. Con SHIFT premuto
// la tastiera non produce più `1` ma `!`, e non più `k` ma `K`: confrontare il
// simbolo che esce vorrebbe dire che `SUPER+SHIFT 1` non scatta mai — perché
// quando arriva, quel tasto non si chiama più «1». Si guarda quindi il
// simbolo al **livello zero**, cioè quello che il tasto produrrebbe da solo, e
// si confrontano a parte i modificatori.
//
// CAPS LOCK e BLOC NUM si tolgono dal confronto: sono stati della tastiera,
// non tasti che qualcuno sta tenendo premuti, e lasciarli dentro vuol dire
// scorciatoie che smettono di funzionare quando è acceso il maiuscolo fisso.

static const uint32_t MODIFICATORI_CHE_CONTANO =
	WLR_MODIFIER_SHIFT | WLR_MODIFIER_CTRL | WLR_MODIFIER_ALT
	| WLR_MODIFIER_LOGO;

/// Il modificatore che un tasto È, se è un tasto modificatore.
///
/// wlroots aggiorna i modificatori DOPO aver annunciato il tasto: quando si
/// lascia Super, al momento del rilascio i modificatori dicono ancora «Super
/// premuto». Il tocco di Super (registrato senza modificatori) non combaciava
/// mai, e il menù non si apriva toccando Super; lo stesso per l'Alt che
/// chiude l'Alt+Tab. Visto il 24 settembre 2026 con `prova-super.py`: il
/// tasto stesso non conta come modificatore di sé.
static uint32_t modificatore_del_tasto(xkb_keysym_t sim) {
	switch (sim) {
	case XKB_KEY_Super_L: case XKB_KEY_Super_R:
	case XKB_KEY_Meta_L: case XKB_KEY_Meta_R:
		return WLR_MODIFIER_LOGO;
	case XKB_KEY_Shift_L: case XKB_KEY_Shift_R:
		return WLR_MODIFIER_SHIFT;
	case XKB_KEY_Control_L: case XKB_KEY_Control_R:
		return WLR_MODIFIER_CTRL;
	case XKB_KEY_Alt_L: case XKB_KEY_Alt_R:
		return WLR_MODIFIER_ALT;
	default:
		return 0;
	}
}

/// Avvia un programma, staccato da noi.
///
/// Doppia fork: il figlio fa un altro figlio e muore subito, così il nipote
/// viene adottato da init e non resta nessuno zombie da raccogliere. Un
/// compositore che accumula processi morti è un compositore che, dopo un
/// giorno di lavoro, non riesce più a lanciarne uno.
///
/// `setsid` stacca anche il terminale: senza, un Ctrl+C dato al compositore
/// se ne porta via i figli.
static pid_t figli_programmi[128];

static void avvia_programma(const char *comando) {
	if (comando == NULL || comando[0] == '\0')
		return;
	int posto = -1;
	for (int i = 0; i < 128; i++) {
		if (figli_programmi[i] > 0) {
			pid_t r = waitpid(figli_programmi[i], NULL, WNOHANG);
			if (r > 0 || (r < 0 && errno == ECHILD)) figli_programmi[i] = 0;
		}
		if (figli_programmi[i] == 0 && posto < 0) posto = i;
	}
	if (posto < 0) { wlr_log(WLR_ERROR, "minerva: troppi avvii pendenti"); return; }
	pid_t p = fork();
	if (p < 0)
		return;
	if (p == 0) {
		if (fork() == 0) {
			setsid();
			// I segnali gestiti dal ciclo Wayland sono bloccati nel padre.
			// Non trasferire questa maschera alla shell e ai suoi figli.
			sigset_t vuota;
			sigemptyset(&vuota);
			sigprocmask(SIG_SETMASK, &vuota, NULL);
			// Con la shell, perché le righe della sorgente sono comandi da
			// riga di comando — con le virgolette, le variabili e le pipe che
			// ci si aspetta da un `exec` di Hyprland.
			execl("/bin/sh", "sh", "-c", comando, (char *)NULL);
		}
		_exit(0);
	}
	// Il figlio intermedio viene raccolto da SIGCHLD, mai attendere qui.
	figli_programmi[posto] = p;
}

static void annuncia_scorciatoia(struct minerva *m, const struct scorciatoia *s);

/// Fa quello che dice la scorciatoia.
/// Il fuoco alla finestra in quella direzione: `l`, `r`, `u`, `d`.
///
/// Si sceglie per CENTRI, e la regola è: fra quelle che stanno davvero da
/// quella parte, la più vicina. «Davvero da quella parte» vuol dire che il suo
/// centro ha superato il nostro lungo l'asse giusto — non basta che sia un po'
/// più a sinistra, o due finestre quasi sovrapposte si scambierebbero il fuoco
/// avanti e indietro senza che si veda muovere niente.
///
/// La distanza pesa il traverso il doppio della direzione: fra una finestra
/// poco più a sinistra ma molto più in alto e una molto più a sinistra e in
/// linea, si vuole la seconda — è quella che l'occhio chiama «quella a
/// sinistra».
static void fuoco_in_direzione(struct minerva *m, const char *dove) {
	if (dove == NULL || dove[0] == '\0')
		return;
	struct finestra *attiva = finestra_attiva(m);
	if (attiva == NULL)
		return;

	struct wlr_box a;
	finestra_box(attiva, &a);
	const double ax = a.x + a.width / 2.0;
	const double ay = a.y + a.height / 2.0;

	struct finestra *scelta = NULL;
	double migliore = 0.0;
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (f == attiva || !finestra_visibile(f))
			continue;
		struct wlr_box b;
		finestra_box(f, &b);
		const double bx = b.x + b.width / 2.0;
		const double by = b.y + b.height / 2.0;
		const double dx = bx - ax;
		const double dy = by - ay;

		double avanti, traverso;
		switch (dove[0]) {
		case 'l': avanti = -dx; traverso = fabs(dy); break;
		case 'r': avanti =  dx; traverso = fabs(dy); break;
		case 'u': avanti = -dy; traverso = fabs(dx); break;
		case 'd': avanti =  dy; traverso = fabs(dx); break;
		default: return;
		}
		if (avanti <= 1.0)
			continue;
		const double costo = avanti + traverso * 2.0;
		if (scelta == NULL || costo < migliore) {
			scelta = f;
			migliore = costo;
		}
	}
	if (scelta != NULL)
		fuoco_finestra(m, scelta);
}

/// La finestra attiva agganciata a metà schermo: `l`, `r`, `u`, `d`.
///
/// `u` ingrandisce e `d` la rimette com'era: è quello che fa il trascinamento
/// contro il bordo di sopra, e la coppia su/giù come «ingrandisci / ripristina»
/// è il gesto che tutti conoscono da Windows.
///
/// Il conto lo fa `aggancio.c`, lo stesso file del trascinamento e delle sue
/// ventiquattro prove. Rifarlo qui vorrebbe dire due aggancî che col tempo
/// finiscono in due posti diversi per lo stesso bordo.
static void aggancia_attiva(struct minerva *m, const char *dove) {
	if (dove == NULL || dove[0] == '\0')
		return;
	struct finestra *f = finestra_attiva(m);
	if (f == NULL)
		return;

	// ── Dallo schermo intero, prima si esce ──────────────────────────────
	//
	// Giacomo, 25 settembre 2026: «quando passo una finestra a schermo
	// intero e premo poi Super+freccia giù la finestra perde la barra del
	// titolo». Super+↓ la RIDUCEVA restando a schermo intero: tornava senza
	// barra e senza un modo evidente di uscirne. Adesso Super+↓ esce dallo
	// schermo intero e basta — «torna com'era» — e le altre frecce prima ne
	// escono e poi fanno la loro.
	if (f->schermo_intero) {
		finestra_schermo_intero(f, false);
		annuncia(m, "stato", f);
		if (dove[0] == 'd')
			return;
	}

	if (dove[0] == 'u') {
		finestra_ingrandisci(f, true);
		return;
	}
	// Super+↓ è «torna com'era»: un'ingrandita si rimpicciolisce, una
	// agganciata torna alla misura di prima; e se era già com'era, la
	// seconda volta si riduce. Prima era solo «non ingrandita», e su una
	// finestra normale il tasto non faceva niente.
	if (dove[0] == 'd') {
		if (f->ingrandita) {
			finestra_ingrandisci(f, false);
		} else if (f->agganciata) {
			f->agganciata = false;
			if (f->prima.width > 0 && f->prima.height > 0)
				finestra_posiziona(f, f->prima.x, f->prima.y,
					f->prima.width, f->prima.height);
			barra_aggiorna(f);
			annuncia(m, "stato", f);
		} else {
			finestra_riduci(f, true);
		}
		return;
	}
	// ── Anche gli angoli, e non solo per completezza ────────────────────
	//
	// Da tastiera si arriva solo a `l` e `r`; i quarti di schermo li fa il
	// trascinamento. I nomi lunghi qui sotto non servono a una scorciatoia:
	// servono al verbo `aggancia` del canale, cioè a poter CHIEDERE un
	// aggancio da fuori e poi misurarne il risultato.
	//
	// Senza, lo snap era una cosa che si poteva solo fare col dito e guardare
	// a occhio — e Giacomo il 2 settembre 2026 l'ha descritta come «funziona
	// malissimo, posiziona male le finestre» senza che ci fosse un modo di
	// dargli torto o ragione con un numero.
	enum zona_aggancio zona;
	if (strcmp(dove, "l") == 0 || strcmp(dove, "sinistra") == 0)
		zona = ZONA_SINISTRA;
	else if (strcmp(dove, "r") == 0 || strcmp(dove, "destra") == 0)
		zona = ZONA_DESTRA;
	else if (strcmp(dove, "cima") == 0)
		zona = ZONA_CIMA;
	else if (strcmp(dove, "alto-sx") == 0)
		zona = ZONA_ALTO_SX;
	else if (strcmp(dove, "alto-dx") == 0)
		zona = ZONA_ALTO_DX;
	else if (strcmp(dove, "basso-sx") == 0)
		zona = ZONA_BASSO_SX;
	else if (strcmp(dove, "basso-dx") == 0)
		zona = ZONA_BASSO_DX;
	else
		return;

	struct wlr_box utile;
	finestra_utile(f, &utile);
	struct riquadro ru = da_box(&utile), rr;
	aggancio_riquadro(zona, &ru, &rr);
	const struct wlr_box r = a_box(&rr);
	// Un'agganciata non è ingrandita: se lo restasse, il pulsante
	// «ingrandisci» direbbe il falso e il doppio clic la rimetterebbe dove
	// non era mai stata.
	finestra_ingrandisci(f, false);
	// Ci si ricorda com'era, o staccandola non si saprebbe a che misura
	// tornare. Solo la PRIMA volta: agganciando due volte di fila, quella da
	// ricordare è la misura di prima del primo aggancio.
	if (!f->agganciata)
		finestra_box(f, &f->prima);
	f->agganciata = true;
	finestra_posiziona(f, r.x, r.y, r.width, r.height);
	barra_aggiorna(f);
	annuncia(m, "mossa", f);
}

/// La finestra attiva più larga o più stretta: `ridimensiona: <dx> <dy>`.
///
/// I due numeri sono in pixel e possono essere negativi, come li scrive
/// `config/scorciatoie.minerva` (`-60 0`, `0 60`). Si cresce verso destra e
/// verso il basso: l'angolo in alto a sinistra sta fermo, che è quello che ci
/// si aspetta quando non si sta trascinando niente.
static void ridimensiona_attiva(struct minerva *m, const char *arg) {
	if (arg == NULL)
		return;
	int dx = 0, dy = 0;
	if (sscanf(arg, "%d %d", &dx, &dy) != 2)
		return;
	if (dx == 0 && dy == 0)
		return;
	struct finestra *f = finestra_attiva(m);
	if (f == NULL)
		return;

	struct wlr_box b;
	finestra_box(f, &b);
	int w = b.width + dx;
	int h = b.height + dy;
	// Un minimo che non si discute: una finestra più piccola della sua barra
	// del titolo non si riprende più — non c'è dove cliccare per allargarla.
	const int minima = barra_alta() * 2;
	if (w < minima) w = minima;
	if (h < minima) h = minima;

	finestra_ingrandisci(f, false);
	finestra_posiziona(f, b.x, b.y, w, h);
	barra_aggiorna(f);
	annuncia(m, "mossa", f);
}

static void scorciatoia_esegui(struct minerva *m, const struct scorciatoia *s) {
	const char *a = s->azione;
	const char *arg = s->argomento;

	// ── Quelle che deve fare la SHELL ────────────────────────────────────
	//
	// Ventisei su novantacinque: il promemoria, le impostazioni, il pannello
	// di controllo, il lanciatore. Il compositore non sa cosa siano e non deve
	// saperlo — le annuncia, e chi disegna la scrivania fa il resto. È lo
	// stesso confine di `GlobalShortcut` sotto Hyprland.
	if (strcmp(a, "minerva") == 0) {
		annuncia_scorciatoia(m, s);
		return;
	}

	// ── E questa la fa il compositore, apposta ───────────────────────────
	//
	// `avvia` è l'uscita di sicurezza: se la shell muore o si impalla, le
	// scorciatoie che passano da lei muoiono con lei, e senza questa non
	// resterebbe modo di aprire un terminale per rimettere in piedi le cose.
	// È scritto anche nella sorgente, sopra `$mod SHIFT RETURN`.
	if (strcmp(a, "avvia") == 0) {
		avvia_programma(arg);
		return;
	}

	if (strcmp(a, "scrivania") == 0) {
		if (strcmp(arg, "prossima") == 0) {
			scrivania_vicina(m, true);
		} else if (strcmp(arg, "precedente") == 0) {
			scrivania_vicina(m, false);
		} else {
			scrivania_vai(m, atoi(arg));
		}
		return;
	}

	if (strcmp(a, "porta-a-scrivania") == 0) {
		struct finestra *f = finestra_attiva(m);
		if (f == NULL)
			return;
		// «Maiuscolo vuol dire portala con te»: Super+Maiusc+Ctrl+→ è la
		// stanza accanto, con la finestra. Oltre la prima e la decima non si
		// va: girare in tondo porterebbe la finestra dove non la si aspetta.
		int quale = atoi(arg);
		if (strcmp(arg, "prossima") == 0)
			quale = m->scrivania_attiva < 10 ? m->scrivania_attiva + 1 : 10;
		else if (strcmp(arg, "precedente") == 0)
			quale = m->scrivania_attiva > 1 ? m->scrivania_attiva - 1 : 1;
		scrivania_porta(f, quale, true);
		return;
	}

	if (strcmp(a, "chiudi-finestra") == 0) {
		struct finestra *f = finestra_attiva(m);
		if (f != NULL)
			finestra_di_chiuditi(f);
		return;
	}

	if (strcmp(a, "schermo-intero") == 0) {
		struct finestra *f = finestra_attiva(m);
		if (f != NULL)
			finestra_schermo_intero(f, !f->schermo_intero);
		return;
	}

	if (strcmp(a, "esci-dalla-sessione") == 0) {
		wl_display_terminate(m->display);
		return;
	}

	// ── Le frecce ────────────────────────────────────────────────────────
	//
	// Fino al 31 agosto 2026 queste tre azioni il demone le SALTAVA: erano
	// scritte in `config/scorciatoie.minerva`, comparivano nel promemoria F1,
	// e sotto minerva-wayland non arrivavano nemmeno al compositore. Il conto
	// era 67 registrate su 95 scritte.
	//
	// Erano state saltate con un ragionamento giusto e una conclusione
	// sbagliata: «sposta il fuoco a sinistra» e «allarga nella griglia»
	// vogliono dire qualcosa solo dove c'è una griglia. Vero per la seconda,
	// falso per la prima: il fuoco alla finestra a sinistra ha senso ovunque
	// ci siano due finestre, griglia o no. E «sposta la finestra a sinistra»,
	// senza griglia, ha una lettura ovvia che Minerva ha già — **l'aggancio a
	// metà schermo**, lo stesso di quando la trascini contro il bordo.
	if (strcmp(a, "fuoco") == 0) {
		fuoco_in_direzione(m, arg);
		return;
	}
	if (strcmp(a, "sposta-finestra") == 0) {
		aggancia_attiva(m, arg);
		return;
	}
	if (strcmp(a, "ridimensiona") == 0) {
		ridimensiona_attiva(m, arg);
		return;
	}

	// Un'azione che non conosciamo NON si annuncia e non fa niente: il tasto
	// però se l'è già mangiato chi ci ha portato qui. Per questo la shell non
	// deve mandarci le azioni che qui non hanno senso — le salta a monte, in
	// `minervad/lib/services/scorciatoie.dart`, dove il salto si vede e si
	// conta.
	wlr_log(WLR_INFO, "minerva: scorciatoia «%s» non so cosa sia", a);
}

// ── Il «tieni» ───────────────────────────────────────────────────────────
//
// Super premuto e tenuto da solo per 400 ms. Il timer lo conta, perché un
// tasto fermo non manda niente; qualunque altro tasto, o un clic, lo annulla
// azzerando `ultimo_premuto` — la stessa prova del «da solo» del tocco.
#define TIENI_MS 400

static void annuncia_scorciatoia_con(struct minerva *m, const char *nome);

static int tieni_scade(void *dati) {
	struct minerva *m = dati;
	if (m->tieni_quale < 0 || m->tieni_quale >= m->quante_scorciatoie)
		return 0;
	if (m->ultimo_premuto != m->tieni_tasto || m->bloccato)
		return 0;
	m->tieni_scattato = true;
	annuncia_scorciatoia_con(m, m->scorciatoie[m->tieni_quale].argomento);
	return 0;
}

/// Alla pressione: se questo tasto ha un «tieni», parte il conto.
static void tieni_premuto(struct minerva *m, struct wlr_keyboard *kb, uint32_t keycode) {
	// Già scattato e ora un altro tasto (Super tenuto, guardi i tasti, poi
	// premi A): il «tieni» resta vivo fino al rilascio di Super, che deve
	// ancora togliere i tasti dalla scrivania. Prima qui si azzerava tutto
	// e i tasti restavano sullo schermo per sempre.
	if (m->tieni_scattato && keycode != m->tieni_tasto)
		return;
	m->tieni_quale = -1;
	m->tieni_scattato = false;
	if (m->tieni_timer != NULL)
		wl_event_source_timer_update(m->tieni_timer, 0);
	struct xkb_keymap *mappa = kb->keymap;
	if (mappa == NULL || kb->xkb_state == NULL)
		return;
	xkb_keycode_t xkb = keycode + 8;
	xkb_layout_index_t disp = xkb_state_key_get_layout(kb->xkb_state, xkb);
	const xkb_keysym_t *simboli = NULL;
	int quanti = xkb_keymap_key_get_syms_by_level(mappa, xkb, disp, 0, &simboli);
	for (int i = 0; i < quanti; i++) {
		xkb_keysym_t sim = xkb_keysym_to_lower(simboli[i]);
		for (int j = 0; j < m->quante_scorciatoie; j++) {
			struct scorciatoia *s = &m->scorciatoie[j];
			if (!s->tenuto || s->tasto != sim)
				continue;
			if (strcmp(s->azione, "minerva") != 0)
				continue;
			if (m->tieni_timer == NULL)
				m->tieni_timer = wl_event_loop_add_timer(m->loop, tieni_scade, m);
			if (m->tieni_timer == NULL)
				return;
			m->tieni_tasto = keycode;
			m->tieni_quale = j;
			wl_event_source_timer_update(m->tieni_timer, TIENI_MS);
			return;
		}
	}
}

/// Al rilascio del tasto del «tieni»: se era scattato, si annuncia la fine,
/// e il rilascio NON è più un tocco.
static void tieni_lasciato(struct minerva *m, uint32_t keycode) {
	if (m->tieni_quale < 0 || keycode != m->tieni_tasto)
		return;
	if (m->tieni_timer != NULL)
		wl_event_source_timer_update(m->tieni_timer, 0);
	if (m->tieni_scattato && m->tieni_quale < m->quante_scorciatoie) {
		char nome[sizeof(m->scorciatoie[0].argomento) + 8];
		snprintf(nome, sizeof(nome), "%s-via", m->scorciatoie[m->tieni_quale].argomento);
		annuncia_scorciatoia_con(m, nome);
		m->ultimo_premuto = 0;
	}
	m->tieni_quale = -1;
	m->tieni_scattato = false;
}

/// Cerca una scorciatoia per questo tasto. Torna vero se l'ha eseguita.
static bool scorciatoia_prova(struct minerva *m, struct wlr_keyboard *kb,
                              uint32_t keycode, bool rilascio) {
	// Un TOCCO è un tasto premuto e lasciato da solo. Se dopo di lui se ne è
	// abbassato un altro, quello che stiamo vedendo è la fine di una
	// combinazione — Super+E — e non un tocco.
	const bool era_solo = (m->ultimo_premuto == keycode);
	if (m->quante_scorciatoie == 0)
		return false;

	uint32_t mods = wlr_keyboard_get_modifiers(kb) & MODIFICATORI_CHE_CONTANO;

	struct xkb_keymap *mappa = kb->keymap;
	if (mappa == NULL || kb->xkb_state == NULL)
		return false;
	xkb_keycode_t xkb = keycode + 8;
	xkb_layout_index_t disp = xkb_state_key_get_layout(kb->xkb_state, xkb);
	const xkb_keysym_t *simboli = NULL;
	int quanti = xkb_keymap_key_get_syms_by_level(mappa, xkb, disp, 0,
		&simboli);

	for (int i = 0; i < quanti; i++) {
		xkb_keysym_t sim = xkb_keysym_to_lower(simboli[i]);
		for (int j = 0; j < m->quante_scorciatoie; j++) {
			struct scorciatoia *s = &m->scorciatoie[j];
			// Una scorciatoia del rilascio non scatta alla pressione e
			// viceversa: sono due gesti diversi sullo stesso tasto, e
			// confonderli vuol dire che premere Alt confermerebbe un
			// selettore che non è ancora aperto.
			if (s->al_rilascio != rilascio)
				continue;
			// Il «tieni» ha la sua strada (`tieni_premuto`, il timer).
			if (s->tenuto)
				continue;
			// «Premuto e lasciato DA SOLO»: senza questa riga il menù delle
			// applicazioni si aprirebbe alla fine di ogni Super+qualcosa.
			if (s->da_solo && !era_solo)
				continue;
			if (s->tasto != sim
			    || s->modificatori != (mods & ~modificatore_del_tasto(sim)))
				continue;
			// Da bloccati passano solo quelle marcate: il volume, la
			// luminosità, il lettore. Tutto il resto sarebbe un modo di
			// comandare la sessione di qualcun altro senza sbloccarla.
			if (m->bloccato && !s->anche_bloccato)
				continue;
			scorciatoia_esegui(m, s);
			return true;
		}
	}
	return false;
}

// ── Da quanto non tocchi niente ──────────────────────────────────────────
//
// Vedi il blocco di commenti sui campi `inattivo_*` in `struct minerva`: qui
// c'è la meccanica, là c'è il perché.

// ── Il cartello ──────────────────────────────────────────────────────────
//
// Vedi i campi `cartello*` in `struct minerva` per il perché.

static void cartello_via(struct minerva *m) {
	if (m->cartello_timer != NULL) {
		wl_event_source_remove(m->cartello_timer);
		m->cartello_timer = NULL;
	}
	if (m->cartello != NULL) {
		wlr_scene_node_destroy(&m->cartello->node);
		m->cartello = NULL;
	}
}

static int cartello_scaduto(void *dati) {
	cartello_via(dati);
	return 0;
}

/// Mostra `testo` per `ms` millisecondi. Un cartello nuovo sostituisce quello
/// di prima: due messaggi sovrapposti non si leggono né l'uno né l'altro.
static bool cartello_mostra(struct minerva *m, const char *testo, int ms) {
	cartello_via(m);
	if (m->piano_cartello == NULL || testo == NULL || testo[0] == '\0')
		return false;

	// Lo schermo su cui sta il puntatore: è dove sta guardando chi legge.
	struct wlr_output *out = wlr_output_layout_output_at(m->schermi,
		m->cursore->x, m->cursore->y);
	if (out == NULL) {
		struct wlr_output_layout_output *primo;
		wl_list_for_each(primo, &m->schermi->outputs, link) {
			out = primo->output;
			break;
		}
	}
	if (out == NULL)
		return false;

	struct wlr_box box;
	wlr_output_layout_get_box(m->schermi, out, &box);

	int l = 0, h = 0;
	struct wlr_buffer *buf = barra_cartello(testo, box.width - 80, &l, &h);
	if (buf == NULL)
		return false;

	m->cartello = wlr_scene_buffer_create(m->piano_cartello, buf);
	// La scena ne ha preso il suo riferimento: il nostro si lascia andare.
	wlr_buffer_drop(buf);
	if (m->cartello == NULL)
		return false;

	// Un terzo dall'alto e non al centro: al centro finirebbe sopra la
	// finestra che si sta guardando, e questo cartello compare proprio quando
	// c'è dell'altro da leggere sullo schermo.
	wlr_scene_node_set_position(&m->cartello->node,
		box.x + (box.width - l) / 2, box.y + box.height / 6);

	if (ms > 0) {
		m->cartello_timer = wl_event_loop_add_timer(m->loop,
			cartello_scaduto, m);
		if (m->cartello_timer != NULL)
			wl_event_source_timer_update(m->cartello_timer, ms);
	}
	return true;
}

/// Il programma avviato all'inizio è finito: si esce.
///
/// Solo quando è stato chiesto — vedi `MINERVA_ESCI_COL_FIGLIO` in `main`.
/// `waitpid` con `WNOHANG` in un giro, perché un solo SIGCHLD può valere per
/// più figli finiti insieme e i segnali non si accodano.
static int figlio_finito(int segnale, void *dati) {
	(void)segnale;
	struct minerva *m = dati;
	for (int i = 0; i < 128; i++) {
		if (figli_programmi[i] <= 0) continue;
		pid_t p = waitpid(figli_programmi[i], NULL, WNOHANG);
		if (p > 0 || (p < 0 && errno == ECHILD)) figli_programmi[i] = 0;
	}
	if (m->figlio_avvio > 0) {
		int stato = 0;
		pid_t p = waitpid(m->figlio_avvio, &stato, WNOHANG);
		if (p == m->figlio_avvio) {
			m->esito_figlio = WIFEXITED(stato) ? WEXITSTATUS(stato)
				: WIFSIGNALED(stato) ? 128 + WTERMSIG(stato) : 1;
			wlr_log(WLR_INFO, "minerva: il programma di avvio è "
				"finito (esito %d), esco.", m->esito_figlio);
			wl_display_terminate(m->display);
			m->figlio_avvio = 0;
		}
	}
	return 0;
}

/// Adesso, in millisecondi monotoni.
///
/// Monotono e non «ora del giorno»: l'orologio di sistema può saltare
/// all'indietro — un aggiustamento NTP, il fuso che cambia — e un salto
/// all'indietro su questo conto vorrebbe dire una soglia che non scatta più
/// per ore.
static uint64_t ora_ms(void) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (uint64_t)t.tv_sec * 1000u + (uint64_t)(t.tv_nsec / 1000000);
}

static int inattivo_scatta(void *dati);

/// Riarma il timer perché scatti fra `fra_ms`. Zero soglie = spento.
static void inattivo_arma(struct minerva *m, uint64_t fra_ms) {
	if (m->inattivo_timer == NULL)
		return;
	if (m->inattivo_quante == 0 ||
	    m->inattivo_prossima >= m->inattivo_quante) {
		wl_event_source_timer_update(m->inattivo_timer, 0);
		return;
	}
	// `wl_event_source_timer_update` vuole un `int` di millisecondi, e con 0
	// SPEGNE il timer: una soglia che cade a zero millisecondi non
	// annuncerebbe mai invece di annunciare subito.
	if (fra_ms < 1)
		fra_ms = 1;
	if (fra_ms > (uint64_t)INT32_MAX)
		fra_ms = (uint64_t)INT32_MAX;
	wl_event_source_timer_update(m->inattivo_timer, (int)fra_ms);
}

/// Riparte da capo: la prossima soglia è la prima.
static void inattivo_riparti(struct minerva *m) {
	m->inattivo_prossima = 0;
	m->ultima_attivita_ms = ora_ms();
	if (m->inattivo_quante > 0)
		inattivo_arma(m, (uint64_t)m->inattivo_soglie[0] * 1000u);
	else
		inattivo_arma(m, 0);
}

/// «Qualcuno c'è.» Si chiama da OGNI evento di ingresso, e per questo non
/// deve fare niente di caro: vedi il commento sui campi.
static void attivita(struct minerva *m) {
	if (m->inattivita != NULL)
		wlr_idle_notifier_v1_notify_activity(m->inattivita, m->seat);

	m->ultima_attivita_ms = ora_ms();

	// L'annuncio del ritorno si fa una volta sola, e solo se qualcosa era
	// scattato. Senza questa guardia partirebbe a ogni tasto premuto per
	// tutta la sessione — cioè si sveglierebbe la shell per niente, che è
	// esattamente il difetto che questo progetto ha già pagato.
	if (!m->inattivo_annunciato)
		return;
	m->inattivo_annunciato = false;
	if (m->canale != NULL)
		canale_annuncia(m->canale, "attivo", "evento attivo {}");
	inattivo_riparti(m);
}

static int inattivo_scatta(void *dati) {
	struct minerva *m = dati;
	if (m->inattivo_quante == 0 ||
	    m->inattivo_prossima >= m->inattivo_quante)
		return 0;

	// ── Chi ha chiesto di non essere disturbato ──────────────────────
	//
	// Un video a schermo intero tiene un `idle_inhibitor`: finché c'è, non
	// si conta. Non si SOSPENDE il conto — lo si azzera: uscendo dal video
	// è giusto ripartire dai cinque minuti pieni, non dai trenta secondi
	// che restavano.
	if (m->inibitori > 0 || schermo_intero_visibile(m)) {
		inattivo_riparti(m);
		return 0;
	}

	const uint64_t soglia_ms =
		(uint64_t)m->inattivo_soglie[m->inattivo_prossima] * 1000u;
	const uint64_t adesso = ora_ms();
	const uint64_t fermi = adesso - m->ultima_attivita_ms;

	// Il timer non si riarma a ogni movimento del mouse: quando scatta può
	// quindi trovare che si è toccato qualcosa da poco. In quel caso non si
	// annuncia niente e si riprova fra il tempo che manca.
	if (fermi < soglia_ms) {
		inattivo_arma(m, soglia_ms - fermi);
		return 0;
	}

	char riga[64];
	snprintf(riga, sizeof(riga), "evento inattivo {\"secondi\":%d}",
		m->inattivo_soglie[m->inattivo_prossima]);
	if (m->canale != NULL)
		canale_annuncia(m->canale, "inattivo", riga);
	m->inattivo_annunciato = true;

	const int fatta = m->inattivo_soglie[m->inattivo_prossima];
	m->inattivo_prossima++;
	if (m->inattivo_prossima < m->inattivo_quante) {
		const int dopo = m->inattivo_soglie[m->inattivo_prossima];
		inattivo_arma(m, (uint64_t)(dopo - fatta) * 1000u);
	} else {
		inattivo_arma(m, 0);
	}
	return 0;
}

/// Legge le soglie chieste dalla shell. Torna `false` se la riga non va bene,
/// e in quel caso NON tocca quelle di prima: una richiesta storta non deve
/// spegnere una sorveglianza che funzionava.
static bool inattivo_imposta(struct minerva *m, const char *argomenti) {
	int nuove[MINERVA_SOGLIE_INATTIVITA];
	int quante = 0;
	const char *p = argomenti;

	while (p != NULL && *p != '\0') {
		while (*p == ' ' || *p == '\t')
			p++;
		if (*p == '\0')
			break;
		char *fine = NULL;
		const long v = strtol(p, &fine, 10);
		if (fine == p || v <= 0 || v > 86400)
			return false;
		if (quante >= MINERVA_SOGLIE_INATTIVITA)
			return false;
		// Devono arrivare in ordine crescente: il conto fra una soglia e la
		// successiva è una sottrazione, e con due numeri in disordine
		// verrebbe negativa.
		if (quante > 0 && (int)v <= nuove[quante - 1])
			return false;
		nuove[quante++] = (int)v;
		p = fine;
	}

	for (int i = 0; i < quante; i++)
		m->inattivo_soglie[i] = nuove[i];
	m->inattivo_quante = quante;
	m->inattivo_annunciato = false;
	inattivo_riparti(m);
	return true;
}

// ── «Non spegnere lo schermo adesso» ─────────────────────────────────────
//
// `wlr_idle_inhibit_v1_create` apre il protocollo e basta: onorarlo è
// mestiere del compositore. Fino al 1º settembre 2026 nessuno lo onorava —
// il protocollo era acceso, i programmi ci si appoggiavano, e lo schermo si
// sarebbe spento in mezzo a un film lo stesso. Un pezzo che c'è e non fa
// niente è peggio di uno che manca: chi guarda il codice lo dà per fatto.
struct inibitore {
	struct minerva *m;
	struct wl_listener distrutto;
};

// ── E lo schermo intero frena da solo ────────────────────────────────────
//
// Il freno dello schermo intero lo metteva la shell, appendendo un
// `IdleInhibitor` a una sua superficie — il cartello del modo gioco. Ma per
// reggere il freno quella superficie doveva restare MAPPATA per tutto il
// film, trasparente, sopra la finestra: e una superficie sopra basta a
// impedire lo scanout diretto (23 settembre 2026, misurato). Il compositore
// sa già se c'è una finestra a schermo intero visibile: frena lui. Alla shell
// resta il freno acceso a mano (il modo gioco «forzato»), che una finestra a
// schermo intero non ce l'ha e quindi non ha scanout da proteggere.
static bool schermo_intero_visibile(struct minerva *m) {
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (f->schermo_intero && finestra_visibile(f))
			return true;
	}
	return false;
}

/// Dice ai programmi che ascoltano l'inattività col protocollo standard se
/// adesso si è frenati. Il timer nostro (`inattivo_scatta`) lo ricontrolla da
/// sé a ogni scatto; questo serve a chi usa `ext-idle-notify`.
static void freno_aggiorna(struct minerva *m) {
	if (m->inattivita != NULL)
		wlr_idle_notifier_v1_set_inhibited(m->inattivita,
			m->inibitori > 0 || schermo_intero_visibile(m));
}

static void inibitore_distrutto(struct wl_listener *l, void *dati) {
	(void)dati;
	struct inibitore *i = wl_container_of(l, i, distrutto);
	struct minerva *m = i->m;
	if (m->inibitori > 0)
		m->inibitori--;
	freno_aggiorna(m);
	wl_list_remove(&i->distrutto.link);
	free(i);
	// Uscendo dal video il conto riparte da capo, non da dov'era.
	if (m->inibitori == 0)
		inattivo_riparti(m);
}

static void inibitore_nuovo(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, inibitore_nuovo);
	struct wlr_idle_inhibitor_v1 *inib = dati;

	struct inibitore *i = calloc(1, sizeof(*i));
	if (i == NULL)
		return;
	i->m = m;
	i->distrutto.notify = inibitore_distrutto;
	wl_signal_add(&inib->events.destroy, &i->distrutto);
	m->inibitori++;
	freno_aggiorna(m);
}

static void tastiera_tasto(struct wl_listener *l, void *dati) {
	struct tastiera *t = wl_container_of(l, t, tasto);
	struct minerva *m = t->m;
	struct wlr_keyboard_key_event *e = dati;

	attivita(m);

	// ── Il rilascio di un tasto già mangiato si mangia anche lui ─────────
	//
	// Se si inghiotte la pressione e si lascia passare il rilascio, il
	// programma sotto vede un tasto che si alza senza essersi mai abbassato.
	// Chi tiene il conto dei tasti premuti — i giochi, gli editor modali —
	// resta a credere che sia ancora giù, e da lì in poi risponde male a
	// tutto.
	if (e->state == WL_KEYBOARD_KEY_STATE_RELEASED) {
		for (int i = 0; i < m->quanti_inghiottiti; i++) {
			if (m->inghiottiti[i] != e->keycode)
				continue;
			m->inghiottiti[i] = m->inghiottiti[--m->quanti_inghiottiti];
			return;
		}

		// ── E qui le scorciatoie del RILASCIO ────────────────────────────
		//
		// Ce n'è una sola oggi, ed è quella che chiude l'Alt+Tab. Scatta e
		// **non si mangia il tasto**: la pressione di Alt è già passata al
		// programma sotto, e ingoiarne il rilascio lo lascerebbe a credere
		// che Alt sia ancora premuto per sempre. È la stessa ragione per cui
		// esiste l'elenco degli inghiottiti, vista dal verso opposto.
		tieni_lasciato(m, e->keycode);
		scorciatoia_prova(m, t->kb, e->keycode, true);
	} else {
		// Si segna PRIMA di provare le scorciatoie: `scorciatoia_prova` lo
		// legge per sapere se questo tasto è «da solo», e un tasto appena
		// premuto lo è sempre — è il prossimo che gli toglie il titolo.
		m->ultimo_premuto = e->keycode;
		tieni_premuto(m, t->kb, e->keycode);
		if (scorciatoia_prova(m, t->kb, e->keycode, false)) {
			if (m->quanti_inghiottiti
					< (int)(sizeof(m->inghiottiti) / sizeof(m->inghiottiti[0])))
				m->inghiottiti[m->quanti_inghiottiti++] = e->keycode;
			return;
		}
	}

	wlr_seat_set_keyboard(m->seat, t->kb);
	wlr_seat_keyboard_notify_key(m->seat, e->time_msec, e->keycode,
		e->state);
}

static void tastiera_distrutta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct tastiera *t = wl_container_of(l, t, distrutta);
	wl_list_remove(&t->tasto.link);
	wl_list_remove(&t->modificatori.link);
	wl_list_remove(&t->distrutta.link);
	wl_list_remove(&t->link);
	free(t);
}

// ══ L'ingresso: tastiera, puntatore, touchpad ═════════════════════════════
//
// Sono le manopole del pannello «Tastiera e mouse», e fino a oggi qui dentro
// non ne arrivava nessuna: la shell le mandava con `hyprctl keyword`, che
// sotto il nostro compositore non è nessuno. Il sintomo peggiore si vede
// subito e si capisce tardi — **la tastiera resta americana**: le accentate
// non si scrivono, e la chiocciola è in un altro posto.
//
// ── Applicare, e RIapplicare ─────────────────────────────────────────────
//
// Ogni manopola si applica due volte: quando arriva, a tutto ciò che è già
// collegato; e alla nascita di ogni dispositivo nuovo. Senza la seconda metà,
// una tastiera esterna infilata a sessione avviata nasce americana — e non
// succede niente di visibile che lo spieghi.

/// La disposizione dei tasti su UNA tastiera.
///
/// Campi vuoti vogliono dire «quello che dice il sistema»: `xkb` legge
/// allora `XKB_DEFAULT_LAYOUT` e la configurazione della macchina, che è la
/// cosa giusta finché nessuno ha scelto.
static void tastiera_applica(struct minerva *m, struct wlr_keyboard *kb) {
	struct xkb_rule_names nomi;
	memset(&nomi, 0, sizeof(nomi));
	if (m->ingresso.disposizione[0] != '\0')
		nomi.layout = m->ingresso.disposizione;
	if (m->ingresso.variante[0] != '\0')
		nomi.variant = m->ingresso.variante;

	struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (ctx == NULL)
		return;
	struct xkb_keymap *mappa = xkb_keymap_new_from_names(ctx, &nomi,
		XKB_KEYMAP_COMPILE_NO_FLAGS);
	// ── Una disposizione che non esiste non deve lasciare senza tastiera ──
	//
	// `xkb_keymap_new_from_names` con un nome inventato torna NULL, e senza
	// mappa quella tastiera non produce **nessun** simbolo: non è una
	// disposizione sbagliata, è una tastiera morta. Si ripiega su quella di
	// sistema, dicendolo.
	if (mappa == NULL && nomi.layout != NULL) {
		wlr_log(WLR_ERROR, "minerva: la disposizione «%s» non esiste: "
			"tengo quella di sistema", nomi.layout);
		memset(&nomi, 0, sizeof(nomi));
		mappa = xkb_keymap_new_from_names(ctx, &nomi,
			XKB_KEYMAP_COMPILE_NO_FLAGS);
	}
	if (mappa != NULL) {
		wlr_keyboard_set_keymap(kb, mappa);
		xkb_keymap_unref(mappa);
	}
	xkb_context_unref(ctx);

	const int ritmo = m->ingresso.ripetizioni_s > 0
		? m->ingresso.ripetizioni_s : 25;
	const int ritardo = m->ingresso.ritardo_ms > 0
		? m->ingresso.ritardo_ms : 600;
	wlr_keyboard_set_repeat_info(kb, ritmo, ritardo);
}

/// Le manopole di UN dispositivo di puntamento.
///
/// Passano da libinput, che è chi le sa fare davvero: wlroots ci dà solo la
/// maniglia. Un dispositivo che non viene da libinput — quello finto del
/// backend annidato, per esempio — non ha nessuna manopola, e non è un
/// errore: si lascia stare.
static void puntatore_applica(struct minerva *m, struct wlr_input_device *dev) {
	if (!wlr_input_device_is_libinput(dev))
		return;
	struct libinput_device *ld = wlr_libinput_get_device_handle(dev);
	if (ld == NULL)
		return;

	if (m->ingresso.sensibilita_detta
	    && libinput_device_config_accel_is_available(ld)) {
		double v = m->ingresso.sensibilita;
		if (v < -1.0) v = -1.0;
		if (v > 1.0) v = 1.0;
		libinput_device_config_accel_set_speed(ld, v);
	}

	// ── E queste solo dove ha senso chiederle ────────────────────────────
	//
	// `tap-to-click` su un mouse non esiste, e libinput risponde
	// «non disponibile». Chiederlo lo stesso non rompe niente, ma
	// controllare prima è il modo di non confondere «il dispositivo non ce
	// l'ha» con «la nostra riga non ha funzionato».
	//
	// Lo scorrimento naturale è nelle Impostazioni sotto **Touchpad**, e
	// deve valere solo lì. `libinput_device_config_scroll_has_natural_scroll`
	// dice sì anche per un mouse: con la levetta accesa — che è come sta
	// sul portatile di Giacomo — attaccando un mouse la rotellina andava al
	// contrario, per colpa di un interruttore che dice «touchpad».
	//
	// Un touchpad si riconosce dal fatto che sa scorrere con DUE DITA: è
	// una cosa che nessun mouse sa fare, e non dipende da come si chiama il
	// dispositivo.
	if (m->ingresso.scorrimento_naturale >= 0
	    && libinput_device_config_scroll_has_natural_scroll(ld)
	    && (libinput_device_config_scroll_get_methods(ld)
	        & LIBINPUT_CONFIG_SCROLL_2FG)) {
		libinput_device_config_scroll_set_natural_scroll_enabled(ld,
			m->ingresso.scorrimento_naturale ? 1 : 0);
	}
	if (m->ingresso.tocco_e_clic >= 0
	    && libinput_device_config_tap_get_finger_count(ld) > 0) {
		libinput_device_config_tap_set_enabled(ld,
			m->ingresso.tocco_e_clic ? LIBINPUT_CONFIG_TAP_ENABLED
			                         : LIBINPUT_CONFIG_TAP_DISABLED);
	}
	if (m->ingresso.spento_mentre_scrivi >= 0
	    && libinput_device_config_dwt_is_available(ld)) {
		libinput_device_config_dwt_set_enabled(ld,
			m->ingresso.spento_mentre_scrivi
			? LIBINPUT_CONFIG_DWT_ENABLED : LIBINPUT_CONFIG_DWT_DISABLED);
	}
}

/// Tutto a tutti: è quello che si fa quando una manopola cambia.
static void ingresso_riapplica(struct minerva *m) {
	struct tastiera *t;
	wl_list_for_each(t, &m->tastiere, link)
		tastiera_applica(m, t->kb);

	struct puntatore *p;
	wl_list_for_each(p, &m->puntatori, link)
		puntatore_applica(m, p->dev);
}

static void puntatore_distrutto(struct wl_listener *l, void *dati) {
	(void)dati;
	struct puntatore *p = wl_container_of(l, p, distrutto);
	// ── Staccarlo, non solo dimenticarlo ─────────────────────────────
	//
	// `puntatore_nuovo` fa `wlr_cursor_attach_input_device`, e qui non si
	// faceva il gesto contrario: si toglieva il puntatore dalla NOSTRA
	// lista e si lasciava attaccato a quello di wlroots, che continuava a
	// tenersene il conto.
	//
	// Il sintomo, visto il 4 settembre 2026 da Giacomo — «cosa sono tutti
	// quei segni + in impostazioni?» — è una **fila di cursori rimasti
	// impressi sullo schermo**, uno per ogni posto in cui il puntatore si
	// era fermato, disegnati sopra le finestre e immuni a qualunque
	// ridisegno. Si erano visti dopo `scripts/prova-clic.py`, che crea un
	// mouse finto e alla fine lo distrugge: è l'unico momento in cui un
	// dispositivo di puntamento sparisce mentre la sessione è viva, e
	// quindi l'unico in cui il difetto si vedeva.
	//
	// Si toglievano ricaricando il tema del puntatore (`cursore  24`), che
	// è il modo lungo per dire che erano roba del cursore e non delle
	// finestre sotto.
	wlr_cursor_detach_input_device(p->m->cursore, p->dev);
	wl_list_remove(&p->distrutto.link);
	wl_list_remove(&p->link);
	free(p);
}

static void puntatore_nuovo(struct minerva *m, struct wlr_input_device *dev) {
	wlr_cursor_attach_input_device(m->cursore, dev);

	struct puntatore *p = calloc(1, sizeof(*p));
	if (p == NULL)
		return;
	p->m = m;
	p->dev = dev;
	p->distrutto.notify = puntatore_distrutto;
	wl_signal_add(&dev->events.destroy, &p->distrutto);
	wl_list_insert(&m->puntatori, &p->link);

	// Le manopole scelte prima che questo esistesse valgono anche per lui.
	puntatore_applica(m, dev);
}

static void tastiera_nuova(struct minerva *m, struct wlr_input_device *dev) {
	struct wlr_keyboard *kb = wlr_keyboard_from_input_device(dev);

	struct tastiera *t = calloc(1, sizeof(*t));
	if (t == NULL)
		return;
	t->m = m;
	t->kb = kb;

	tastiera_applica(m, kb);

	t->modificatori.notify = tastiera_modificatori;
	wl_signal_add(&kb->events.modifiers, &t->modificatori);
	t->tasto.notify = tastiera_tasto;
	wl_signal_add(&kb->events.key, &t->tasto);
	t->distrutta.notify = tastiera_distrutta;
	wl_signal_add(&dev->events.destroy, &t->distrutta);

	wlr_seat_set_keyboard(m->seat, kb);
	wl_list_insert(&m->tastiere, &t->link);
}

/// ── Il coperchio del portatile, e perché il compositore non lo chiude ───
///
/// Un `switch` in libinput è un interruttore fisico: il coperchio del
/// portatile (`LID`) e il passaggio a tavoletta (`TABLET_MODE`). Fino al
/// 31 agosto 2026 il compositore non li guardava affatto — conosceva solo
/// tastiere e puntatori — e il pannello «Energia» scriveva una riga
/// `bindl = ,switch:on:Lid Switch,exec,…` che è sintassi di Hyprland e qui
/// dentro non la legge nessuno.
///
/// **Qui si annuncia e basta, e non è pigrizia: è la regola della casa.**
/// Chiudere il coperchio può voler dire sospendere, e una sospensione decisa
/// dal compositore è una macchina che sparisce senza che nessuno l'abbia
/// chiesto. Giacomo l'ha detto una volta e vale per sempre: «altrimenti ti
/// perdo». Il compositore riferisce il fatto — il coperchio è chiuso — e chi
/// ha la politica in mano (la shell, il pannello Energia) decide se spegnere
/// lo schermo, bloccare, o non fare niente.
///
/// È lo stesso confine del blocco schermo e delle scorciatoie `minerva:`.
struct interruttore {
	struct minerva *m;
	struct wlr_switch *sw;
	struct wl_listener commuta;
	struct wl_listener distrutto;
	struct wl_list link;
};

static void annuncia_coperchio(struct minerva *m, bool chiuso) {
	if (m->canale == NULL)
		return;
	char riga[64];
	snprintf(riga, sizeof(riga), "evento coperchio {\"chiuso\":%s}",
		chiuso ? "true" : "false");
	canale_annuncia(m->canale, "coperchio", riga);
}

static void interruttore_commuta(struct wl_listener *l, void *dati) {
	struct interruttore *i = wl_container_of(l, i, commuta);
	struct wlr_switch_toggle_event *e = dati;

	// La tavoletta non la gestiamo: su questa macchina non c'è, e fingere di
	// saperla trattare sarebbe peggio che dire che non la si tratta.
	if (e->switch_type != WLR_SWITCH_TYPE_LID) {
		wlr_log(WLR_INFO, "minerva: interruttore di tipo %d non gestito",
			(int)e->switch_type);
		return;
	}
	const bool chiuso = e->switch_state == WLR_SWITCH_STATE_ON;
	wlr_log(WLR_INFO, "minerva: coperchio %s", chiuso ? "chiuso" : "aperto");
	annuncia_coperchio(i->m, chiuso);
}

static void interruttore_distrutto(struct wl_listener *l, void *dati) {
	struct interruttore *i = wl_container_of(l, i, distrutto);
	(void)dati;
	wl_list_remove(&i->commuta.link);
	wl_list_remove(&i->distrutto.link);
	wl_list_remove(&i->link);
	free(i);
}

static void interruttore_nuovo(struct minerva *m,
		struct wlr_input_device *dev) {
	struct interruttore *i = calloc(1, sizeof(*i));
	if (i == NULL)
		return;
	i->m = m;
	i->sw = wlr_switch_from_input_device(dev);
	i->commuta.notify = interruttore_commuta;
	wl_signal_add(&i->sw->events.toggle, &i->commuta);
	i->distrutto.notify = interruttore_distrutto;
	wl_signal_add(&dev->events.destroy, &i->distrutto);
	wl_list_insert(&m->interruttori, &i->link);
}

static void dispositivo_nuovo(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, dispositivo_nuovo);
	struct wlr_input_device *dev = dati;

	switch (dev->type) {
	case WLR_INPUT_DEVICE_KEYBOARD:
		wlr_log(WLR_INFO, "minerva: tastiera «%s»", dev->name ? dev->name : "?");
		tastiera_nuova(m, dev);
		break;
	case WLR_INPUT_DEVICE_POINTER:
		wlr_log(WLR_INFO, "minerva: puntatore «%s»", dev->name ? dev->name : "?");
		puntatore_nuovo(m, dev);
		break;
	case WLR_INPUT_DEVICE_SWITCH:
		wlr_log(WLR_INFO, "minerva: interruttore «%s»",
			dev->name ? dev->name : "?");
		interruttore_nuovo(m, dev);
		break;
	default:
		// Tavolette e tocco arriveranno: dirlo nel registro è meglio che
		// ignorarli in silenzio e poi chiedersi perché non succede niente.
		wlr_log(WLR_INFO, "minerva: dispositivo di tipo %d non ancora gestito",
			dev->type);
		break;
	}

	// Le capacità si dichiarano SEMPRE con la tastiera dentro, anche senza
	// tastiere collegate: un cliente che vede un seat senza tastiera può
	// decidere di non chiedere mai il fuoco, e poi non riceve un tasto per
	// tutta la sessione.
	uint32_t capacita = WL_SEAT_CAPABILITY_POINTER;
	if (!wl_list_empty(&m->tastiere))
		capacita |= WL_SEAT_CAPABILITY_KEYBOARD;
	wlr_seat_set_capabilities(m->seat, capacita);
}

// ── Dove sta il puntatore, e chi lo riceve ───────────────────────────────

struct sotto {
	struct finestra *finestra;
	struct wlr_surface *superficie;
	double sx, sy;
	bool sulla_barra;
	bool sul_bordo;
};

static void cosa_c_e_sotto(struct minerva *m, struct sotto *fuori) {
	*fuori = (struct sotto){0};

	double sx, sy;
	struct wlr_scene_node *nodo = wlr_scene_node_at(&m->scena->tree.node,
		m->cursore->x, m->cursore->y, &sx, &sy);
	if (nodo == NULL)
		return;
	struct finestra *ondulante;
	wl_list_for_each(ondulante, &m->finestre_elenco, link) {
		if (wobbly_e_proxy(ondulante->wobbly, nodo)) {
			nodo = wobbly_nodo(ondulante->wobbly, sx, sy, &sx, &sy);
			if (!nodo) return;
			break;
		}
	}

	if (nodo->type == WLR_SCENE_NODE_BUFFER) {
		struct wlr_scene_buffer *b = wlr_scene_buffer_from_node(nodo);
		struct wlr_scene_surface *ss = wlr_scene_surface_try_from_buffer(b);
		if (ss != NULL) {
			fuori->superficie = ss->surface;
			fuori->sx = sx;
			fuori->sy = sy;
		}
	}

	enum tipo_nodo tipo;
	void *chi = nodo_proprietario(nodo, &tipo);
	if (chi == NULL || tipo != NODO_FINESTRA)
		return;

	struct finestra *f = chi;
	fuori->finestra = f;
	// Il nodo dice da solo su che cosa siamo: la barra e il bordo di presa
	// sono nodi nostri, tutto il resto è il programma.
	fuori->sulla_barra = (f->barra != NULL && nodo == &f->barra->node);
	fuori->sul_bordo = (f->maniglia != NULL && nodo == &f->maniglia->node);
	// L'anello sta SOPRA la maniglia e occupa la stessa banda: senza questa
	// riga, prendere una finestra esattamente sul bordo colorato smetterebbe
	// di ridimensionarla.
	if (!fuori->sul_bordo && f->anello != NULL
			&& nodo == &f->anello->node)
		fuori->sul_bordo = true;
}

/// Su quali lati si sta prendendo la finestra, per il ridimensionamento.
static uint32_t bordi_sotto(struct finestra *f, double x, double y) {
	struct wlr_box b;
	finestra_box(f, &b);

	// La stessa banda della maniglia: sei pixel, o lo spessore dell'anello se
	// è più grosso. Il conto sta in due posti e deve dare lo stesso numero, o
	// il puntatore cambia forma in un punto e la presa parte in un altro.
	const int presa = f->m->cornice_spessore > BORDO_PRESA
		? f->m->cornice_spessore : BORDO_PRESA;

	uint32_t bordi = 0;
	if (x < b.x + presa)
		bordi |= WLR_EDGE_LEFT;
	else if (x > b.x + b.width - presa)
		bordi |= WLR_EDGE_RIGHT;
	if (y < b.y + presa)
		bordi |= WLR_EDGE_TOP;
	else if (y > b.y + b.height - presa)
		bordi |= WLR_EDGE_BOTTOM;
	return bordi;
}

static const char *freccia_bordi(uint32_t bordi) {
	switch (bordi) {
	case WLR_EDGE_TOP:                     return "n-resize";
	case WLR_EDGE_BOTTOM:                  return "s-resize";
	case WLR_EDGE_LEFT:                    return "w-resize";
	case WLR_EDGE_RIGHT:                   return "e-resize";
	case WLR_EDGE_TOP | WLR_EDGE_LEFT:     return "nw-resize";
	case WLR_EDGE_TOP | WLR_EDGE_RIGHT:    return "ne-resize";
	case WLR_EDGE_BOTTOM | WLR_EDGE_LEFT:  return "sw-resize";
	case WLR_EDGE_BOTTOM | WLR_EDGE_RIGHT: return "se-resize";
	default:                               return "default";
	}
}

/// Il pulsante acceso passa da una finestra all'altra: chi lo aveva prima
/// deve spegnersi, o resta una pastiglia accesa su una barra che non si sta
/// più toccando.
static void dito_su(struct minerva *m, struct finestra *f, int quale) {
	struct finestra *altra;
	wl_list_for_each(altra, &m->finestre_elenco, link) {
		if (altra != f && altra->sotto_il_dito != -1) {
			altra->sotto_il_dito = -1;
			barra_aggiorna(altra);
		}
	}
	if (f != NULL && f->sotto_il_dito != quale) {
		f->sotto_il_dito = quale;
		barra_aggiorna(f);
	}
}

/// Porta avanti il trascinamento in corso. Torna vero se ha fatto qualcosa,
/// cioè se il puntatore appartiene alla presa e non a chi ci sta sotto.
// ── Dove NON si può trascinare una finestra ──────────────────────────────
//
// Una finestra si sposta dove si vuole, tranne dove non si potrebbe più
// riprendere. Sono due i modi di perderla, e Minerva li ha visti entrambi:
//
//  · **sopra**, sotto la barra della scrivania. È il difetto per cui Giacomo
//    scriveva «non hanno la barra e devo chiuderle con super+C»: se la barra
//    del titolo finisce dentro lo spazio riservato al pannello, non c'è più
//    niente da afferrare. Il tetto è quindi lo spazio UTILE, non lo schermo;
//  · **di lato**, fuori dal bordo. Trascinando in fretta si può buttare una
//    finestra quasi tutta fuori, e con lei la sua barra.
//
// Il fondo invece resta libero: una finestra bassa si può spingere giù quanto
// si vuole, perché la barra — che è in cima — rimane comunque a portata.
#define RESTA_DENTRO 120

static void trattieni(struct finestra *f, int *x, int *y) {
	struct wlr_box utile;
	finestra_utile(f, &utile);

	struct wlr_box b;
	finestra_box(f, &b);
	const int larga = b.width > 0 ? b.width : 1;

	int minimo = RESTA_DENTRO;
	if (larga < minimo)
		minimo = larga;

	if (*x + larga < utile.x + minimo)
		*x = utile.x + minimo - larga;
	if (*x > utile.x + utile.width - minimo)
		*x = utile.x + utile.width - minimo;
	if (*y < utile.y)
		*y = utile.y;
}

// ── L'elastico: il battito ───────────────────────────────────────────────
//
// Un giro per tutte le finestre vive, e il timer si riarma solo se ne resta
// almeno una. A scrivania ferma non c'è nessun battito in piedi: è la stessa
// disciplina della cornice che gira, e su un portatile è la differenza fra
// «costa quando lo usi» e «costa sempre».

/// Aggiorna il proxy deformato usando i buffer correnti del programma.
static bool molla_applica(struct finestra *f) {
	int dx = 0, dy = 0;
	molla_scarto(&f->molla, f->posto_x, f->posto_y, &dx, &dy);
	f->molla_dx = dx;
	f->molla_dy = dy;
	if (!f->wobbly || !f->molla.viva) return false;
	struct wlr_box box;
	finestra_box(f, &box);
	struct ondulazione forma = {
		.larghezza = box.width, .altezza = box.height,
		.presa_x = f->wobbly_presa_x, .presa_y = f->wobbly_presa_y,
		.dx = dx, .dy = dy,
	};
	double scala = 1.0;
	struct wlr_output *out = wlr_output_layout_output_at(f->m->schermi,
		f->m->cursore->x, f->m->cursore->y);
	if (out) scala = out->scale;
	if (!wobbly_disegna(f->wobbly, &forma, scala)) {
		wlr_log(WLR_ERROR, "minerva: wobbly non disponibile per questa finestra; scena normale");
		molla_ferma_finestra(f);
		f->wobbly_fallita = true;
		return false;
	}
	return true;
}

static struct wlr_output *molla_schermo(struct finestra *f) {
	struct wlr_box b;
	finestra_box(f, &b);
	struct wlr_output *out = wlr_output_layout_output_at(f->m->schermi,
		f->posto_x + b.width / 2.0, f->posto_y + b.height / 2.0);
	if (out && out->enabled) return out;
	struct schermo *s;
	wl_list_for_each(s, &f->m->schermi_elenco, link) if (s->out->enabled) return s->out;
	return NULL;
}

static void molla_fotogramma(struct minerva *m, struct wlr_output *out) {
	if (!m->molle_attive) return;
	bool viva = false;
	struct timespec ora;
	clock_gettime(CLOCK_MONOTONIC, &ora);
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (!f->molla.viva)
			continue;
		if (m->bloccato || !finestra_visibile(f)) { molla_ferma_finestra(f); continue; }
		if (molla_schermo(f) != out) continue;
		double dt = (ora.tv_sec - f->molla_ultimo.tv_sec)
			+ (ora.tv_nsec - f->molla_ultimo.tv_nsec) / 1e9;
		f->molla_ultimo = ora;
		molla_passo_regolato(&f->molla, f->posto_x, f->posto_y, dt, m->elastico, m->rigidita, m->smorzamento);
		molla_applica(f);
		if (f->molla.viva)
			viva = true;
		else
			molla_ferma_finestra(f);
	}
	if (viva)
		wlr_output_schedule_frame(out);
}

// ── Il respiro delle finestre ────────────────────────────────────────────
//
// La Tappa 3 del piano: «apertura e chiusura che gocciolano; "riduci" come
// un risucchio». Una finestra che nasce non compare a scatto: cresce da un
// soffio più piccola, supera di un niente e si posa, mentre prende colore.
// Riducendola viene risucchiata verso il fondo dello schermo, dove sta la
// dock, stringendosi più in altezza che in larghezza; riportata, ne esce
// all'incontrario.
//
// Si fa con la stessa copia dell'elastico (`wobbly`): per quei trecento
// millisecondi si disegna la copia invece della finestra, scalata e
// sfumata, e alla fine si torna alla finestra vera — a riposo costo zero,
// come l'elastico. Il battito c'è solo mentre un respiro è in corso.
//
// Non respira: col modo risparmio acceso, col respiro spento (`respiro no`),
// mentre la si trascina (c'è già l'elastico), o se la copia non si può fare.

static double respiro_durata(int tipo) {
	switch (tipo) {
	case RESPIRO_NASCITA: return 0.40;
	case RESPIRO_RISUCCHIO: return 0.30;
	case RESPIRO_RITORNO: return 0.32;
	}
	return 0;
}

/// Dove va a finire il risucchio, in coordinate della finestra: il fondo
/// dello schermo, in mezzo — dove sta la dock.
static void respiro_ancora(struct finestra *f, double *ax, double *ay) {
	struct wlr_box b;
	finestra_box(f, &b);
	struct wlr_output *out = wlr_output_layout_output_at(f->m->schermi,
		f->posto_x + b.width / 2.0, f->posto_y + b.height / 2.0);
	struct wlr_box sb = {0};
	if (out != NULL)
		wlr_output_layout_get_box(f->m->schermi, out, &sb);
	else
		sb = (struct wlr_box){f->posto_x, f->posto_y, b.width, b.height};
	*ax = sb.x + sb.width / 2.0 - f->posto_x;
	*ay = sb.y + sb.height - f->posto_y;
}

/// Disegna il respiro al punto `p` (0…1) del suo corso.
static void respiro_disegna(struct finestra *f, double p) {
	if (f->wobbly == NULL)
		return;
	struct wlr_box box;
	finestra_box(f, &box);
	struct ondulazione forma = {
		.larghezza = box.width, .altezza = box.height,
		.presa_x = box.width / 2.0, .presa_y = box.height / 2.0,
	};
	double scala = 1.0;
	struct wlr_output *out = molla_schermo(f);
	if (out) scala = out->scale;
	if (!wobbly_disegna(f->wobbly, &forma, scala)) {
		f->wobbly_fallita = true;
		respiro_fine(f);
		return;
	}
	if (p < 0) p = 0;
	if (p > 1) p = 1;
	double sx = 1, sy = 1, ax = box.width / 2.0, ay = box.height / 2.0, alfa = 1;
	switch (f->respiro) {
	case RESPIRO_NASCITA: {
		// Una goccia che si posa: cresce superando di un soffio (una curva
		// «ease out back») e l'altezza arriva un attimo dopo la larghezza,
		// come una goccia che si allarga e poi si alza. Prende colore
		// dolcemente, tutto nella prima metà.
		const double c1 = 1.4, c3 = c1 + 1;
		double q = p - 1;
		const double e = 1 + c3 * q * q * q + c1 * q * q;
		double p2 = (p - 0.08) / 0.92;
		if (p2 < 0) p2 = 0;
		q = p2 - 1;
		const double e2 = 1 + c3 * q * q * q + c1 * q * q;
		sx = 0.84 + 0.16 * e;
		sy = 0.80 + 0.20 * e2;
		const double a = p < 0.5 ? p / 0.5 : 1;
		alfa = a * a * (3 - 2 * a);
		break;
	}
	case RESPIRO_RISUCCHIO: {
		// Verso la dock, più stretta in altezza che in larghezza.
		const double e = p * p * p;
		respiro_ancora(f, &ax, &ay);
		sx = 1 - 0.82 * e;
		sy = 1 - 0.94 * e;
		alfa = 1 - e;
		break;
	}
	case RESPIRO_RITORNO: {
		const double q = 1 - p, e = 1 - q * q * q;
		respiro_ancora(f, &ax, &ay);
		sx = 0.18 + 0.82 * e;
		sy = 0.06 + 0.94 * e;
		alfa = e < 1 ? e : 1;
		break;
	}
	}
	wobbly_trasforma(f->wobbly, sx, sy, ax, ay, (float)alfa);
	f->m->respiro_passi++;
}

static bool respiro_avvia(struct finestra *f, int tipo) {
	struct minerva *m = f->m;
	if (!m->respiro_acceso || m->risparmio_attivo || f->wobbly_fallita
	    || f->molla.viva || m->bloccato)
		return false;
	if (f->respiro != RESPIRO_NIENTE)
		respiro_fine(f);
	if (f->wobbly == NULL) {
		f->wobbly = wobbly_crea(f->cornice, m->renderer, m->allocator, NULL);
		if (f->wobbly == NULL) {
			f->wobbly_fallita = true;
			return false;
		}
		m->molle_attive++;
	}
	f->respiro = tipo;
	clock_gettime(CLOCK_MONOTONIC, &f->respiro_t0);
	m->respiri_attivi++;
	// Il primo fotogramma subito: la finestra vera non deve vedersi per un
	// fotogramma prima della copia.
	respiro_disegna(f, 0);
	struct wlr_output *out = molla_schermo(f);
	if (out) wlr_output_schedule_frame(out);
	return true;
}

// ── Il respiro della chiusura ────────────────────────────────────────────
//
// Giacomo, 27 settembre 2026, vedendo il respiro: «l'animazione in apertura
// nelle app, ma in chiusura? nulla». Il perché: quando un programma chiude,
// la sua immagine se ne va con lui, e non c'è niente da animare.
//
// ── La copia si fa quando si CHIEDE di chiudere ──────────────────────────
//
// La prima versione la faceva allo smappamento, ed usciva vuota: a quel
// punto la scena di wlroots ha già spento (o svuotato) il contenuto del
// programma — con Alacritty restava solo la nostra barra del titolo, con una
// finestra Qt un rettangolo trasparente. Provato riaccendendo l'albero e
// prendendo la texture dal buffer del client: niente di affidabile.
//
// Quindi la copia si fa quando la chiusura si chiede (la X, Super+C,
// «chiudi» dalla dock: tutto passa da `finestra_di_chiuditi`), finché la
// finestra ha tutta la sua immagine. Resta nascosta; se la finestra si
// smappa entro tre secondi diventa il fantasma che si ritira e sfuma, se no
// — il programma ha chiesto «salvare?», o ha detto di no — si butta. Chi
// chiude da sé (Ctrl+Q, «Esci» nel suo menù) sparisce senza respiro.
//
// Il fantasma sta alla stessa altezza della finestra nella pila, e la
// finestra vera sparisce subito: chi la chiude non aspetta niente. Come una
// goccia che si ritira: si stringe un poco, più in altezza che in
// larghezza, e sfuma. Stesse regole del respiro: non col respiro spento, col
// risparmio, a schermo bloccato, a schermo intero (un film che si chiude
// sparisce e basta) o mentre la si trascina.
struct fantasma {
	struct wl_list link;
	struct wlr_scene_buffer *nodo;
	struct wlr_swapchain *catena;
	/// Dov'era la copia (angolo, in coordinate dello schermo) e quanto era
	/// grande, margine del wobbly compreso.
	int x, y, larga, alta;
	/// Quando è stata fatta (finché aspetta) e poi quando è partita.
	struct timespec t0;
};

#define CHIUSURA_DURATA 0.24
/// Quanto aspetta una copia fatta alla richiesta: oltre, il programma non
/// ha chiuso (o ha chiesto qualcosa) e la copia non è più la finestra.
#define CHIUSURA_ATTESA 3.0

static void fantasma_scarta(struct fantasma *g) {
	wlr_scene_node_destroy(&g->nodo->node);
	if (g->catena != NULL)
		wlr_swapchain_destroy(g->catena);
	free(g);
}

static void fantasma_via(struct minerva *m, struct fantasma *g) {
	wl_list_remove(&g->link);
	fantasma_scarta(g);
	m->fantasmi_vivi--;
}

static bool chiusura_puo_respirare(struct finestra *f) {
	struct minerva *m = f->m;
	return m->respiro_acceso && !m->risparmio_attivo && !m->bloccato
		&& !f->wobbly_fallita && !f->molla.viva && !f->schermo_intero
		&& finestra_visibile(f);
}

/// La richiesta di chiudere: si fa la copia, nascosta, finché l'immagine c'è.
static void chiusura_chiesta(struct finestra *f) {
	struct minerva *m = f->m;
	if (f->fantasma_pronto != NULL) {
		fantasma_scarta(f->fantasma_pronto);
		f->fantasma_pronto = NULL;
	}
	if (!chiusura_puo_respirare(f))
		return;
	// Un respiro a metà (la finestra chiusa appena nata) si chiude qui: la
	// copia parte da com'è adesso.
	if (f->respiro != RESPIRO_NIENTE)
		respiro_fine(f);
	if (f->wobbly != NULL)
		return;
	struct wobbly *w = wobbly_crea(f->cornice, m->renderer, m->allocator, NULL);
	if (w == NULL)
		return;
	struct wlr_box box;
	finestra_box(f, &box);
	struct ondulazione forma = {
		.larghezza = box.width, .altezza = box.height,
		.presa_x = box.width / 2.0, .presa_y = box.height / 2.0,
	};
	double scala = 1.0;
	struct wlr_output *out = molla_schermo(f);
	if (out) scala = out->scale;
	struct fantasma *g = NULL;
	if (box.width > 0 && box.height > 0 && wobbly_disegna(w, &forma, scala)
	    && (g = calloc(1, sizeof(*g))) != NULL) {
		g->nodo = wobbly_stacca(w, m->finestre, &g->catena);
		if (g->nodo == NULL) {
			free(g);
			g = NULL;
		}
	}
	wobbly_distruggi(w);
	if (g == NULL)
		return;
	g->x = f->cornice->node.x + g->nodo->node.x;
	g->y = f->cornice->node.y + g->nodo->node.y;
	g->larga = g->nodo->dst_width;
	g->alta = g->nodo->dst_height;
	wlr_scene_node_set_position(&g->nodo->node, g->x, g->y);
	wlr_scene_node_set_enabled(&g->nodo->node, false);
	clock_gettime(CLOCK_MONOTONIC, &g->t0);
	f->fantasma_pronto = g;
}

/// Allo smappamento: la copia fatta alla richiesta, se c'è ed è fresca,
/// prende il posto della finestra e si ritira.
static void respiro_chiusura(struct finestra *f) {
	struct minerva *m = f->m;
	struct fantasma *g = f->fantasma_pronto;
	if (g == NULL)
		return;
	f->fantasma_pronto = NULL;
	struct timespec ora;
	clock_gettime(CLOCK_MONOTONIC, &ora);
	const double eta = (ora.tv_sec - g->t0.tv_sec) + (ora.tv_nsec - g->t0.tv_nsec) / 1e9;
	if (eta > CHIUSURA_ATTESA || !chiusura_puo_respirare(f)) {
		fantasma_scarta(g);
		return;
	}
	wlr_scene_node_place_above(&g->nodo->node, &f->cornice->node);
	wlr_scene_node_set_enabled(&g->nodo->node, true);
	g->t0 = ora;
	wl_list_insert(&m->fantasmi, &g->link);
	m->fantasmi_vivi++;
	struct schermo *sc;
	wl_list_for_each(sc, &m->schermi_elenco, link)
		wlr_output_schedule_frame(sc->out);
}

static void fantasmi_fotogramma(struct minerva *m) {
	if (wl_list_empty(&m->fantasmi))
		return;
	struct timespec ora;
	clock_gettime(CLOCK_MONOTONIC, &ora);
	struct fantasma *g, *tmp;
	wl_list_for_each_safe(g, tmp, &m->fantasmi, link) {
		const double t = (ora.tv_sec - g->t0.tv_sec)
			+ (ora.tv_nsec - g->t0.tv_nsec) / 1e9;
		const double p = t / CHIUSURA_DURATA;
		if (p >= 1 || m->bloccato) {
			fantasma_via(m, g);
			continue;
		}
		// Parte piano e accelera: la goccia esita, poi si ritira.
		const double e = p * p;
		const double sx = 1 - 0.10 * e, sy = 1 - 0.16 * e;
		const double cx = g->x + g->larga / 2.0, cy = g->y + g->alta / 2.0;
		int dw = (int)lround(g->larga * sx), dh = (int)lround(g->alta * sy);
		if (dw < 1) dw = 1;
		if (dh < 1) dh = 1;
		wlr_scene_buffer_set_dest_size(g->nodo, dw, dh);
		wlr_scene_node_set_position(&g->nodo->node,
			(int)lround(cx - dw / 2.0), (int)lround(cy - dh / 2.0));
		const double a = 1 - p;
		wlr_scene_buffer_set_opacity(g->nodo, (float)(a * a * (3 - 2 * a)));
		m->respiro_passi++;
	}
	if (!wl_list_empty(&m->fantasmi)) {
		struct schermo *sc;
		wl_list_for_each(sc, &m->schermi_elenco, link)
			wlr_output_schedule_frame(sc->out);
	}
}

static void respiro_fine(struct finestra *f) {
	if (f->respiro == RESPIRO_NIENTE)
		return;
	const int era = f->respiro;
	f->respiro = RESPIRO_NIENTE;
	f->m->respiri_attivi--;
	if (!f->molla.viva && f->wobbly != NULL) {
		f->m->molle_attive--;
		wobbly_distruggi(f->wobbly);
		f->wobbly = NULL;
	}
	// Il risucchio finisce nascondendo davvero la finestra: fino a qui è
	// rimasta accesa perché si vedesse andare via.
	if (era == RESPIRO_RISUCCHIO)
		finestra_mostra_o_nascondi(f);
}

static void respiro_fotogramma(struct minerva *m, struct wlr_output *out) {
	if (m->respiri_attivi <= 0)
		return;
	struct timespec ora;
	clock_gettime(CLOCK_MONOTONIC, &ora);
	bool ancora = false;
	struct finestra *f, *tmp;
	wl_list_for_each_safe(f, tmp, &m->finestre_elenco, link) {
		if (f->respiro == RESPIRO_NIENTE)
			continue;
		if (molla_schermo(f) != out)
			continue;
		const double t = (ora.tv_sec - f->respiro_t0.tv_sec)
			+ (ora.tv_nsec - f->respiro_t0.tv_nsec) / 1e9;
		const double p = t / respiro_durata(f->respiro);
		if (p >= 1 || !f->cornice->node.enabled) {
			respiro_fine(f);
			continue;
		}

		respiro_disegna(f, p);
		ancora = true;
	}
	if (ancora)
		wlr_output_schedule_frame(out);
}

/// Accende l'elastico su una finestra e fa partire il battito.
static void molla_avvia(struct finestra *f) {
	struct minerva *m = f->m;
	if (m->elastico <= 0.0 || f->wobbly_fallita)
		return;
	if (f->molla.viva) return;
	// Un respiro in corso cede all'elastico: la mano ha la precedenza.
	if (f->respiro != RESPIRO_NIENTE)
		respiro_fine(f);
	f->wobbly = wobbly_crea(f->cornice, m->renderer, m->allocator,
		m->effetto_modo == EFFETTO_ACQUERELLO ? f->sfocatura : NULL);
	if (!f->wobbly) { f->wobbly_fallita = true; return; }
	m->molle_attive++;
	f->wobbly_presa_x = m->cursore->x - f->posto_x;
	f->wobbly_presa_y = m->cursore->y - f->posto_y;
	molla_accendi(&f->molla, f->posto_x, f->posto_y);
	clock_gettime(CLOCK_MONOTONIC, &f->molla_ultimo);
	struct wlr_output *out = molla_schermo(f);
	if (out) wlr_output_schedule_frame(out);
}

/// La spegne e rimette subito il disegno in pari.
///
/// Serve quando una finestra cambia stato in un modo che l'elastico non deve
/// raccontare — ingrandita, agganciata, mandata su un'altra scrivania — e
/// quando muore. Senza, resterebbe uno scarto congelato: una finestra ferma
/// e disegnata trenta pixel più in là, per sempre, con la maniglia del
/// ridimensionamento che non sta dove si vede il bordo.
static void molla_ferma_finestra(struct finestra *f) {
	// Anche il respiro usa la copia che qui si distrugge: si chiude prima lui,
	// per bene. Senza, una finestra chiusa mentre nasceva lasciava il conto
	// dei respiri in corso a uno per sempre, e il compositore li cercava a
	// ogni fotogramma; e un «riduci» interrotto a metà lasciava la finestra
	// accesa. `respiro_fine` la nasconde, se stava andando via.
	respiro_fine(f);
	if (f->wobbly) f->m->molle_attive--;
	wobbly_distruggi(f->wobbly);
	f->wobbly = NULL;
	if (!f->molla.viva && f->molla_dx == 0 && f->molla_dy == 0)
		return;
	molla_spegni(&f->molla, f->posto_x, f->posto_y);
	f->molla_dx = 0;
	f->molla_dy = 0;
	wlr_scene_node_set_position(&f->cornice->node, f->posto_x, f->posto_y);
}

/// Una finestra ingrandita o agganciata che si comincia a trascinare torna
/// alla sua misura sotto il puntatore. La chiamano le due strade della
/// presa: la nostra barra (`presa_avanti`, al primo movimento) e il
/// programma che chiede di essere spostato (`chiede_sposta`) — quella che
/// usano le app di Minerva e Chrome. Prima c'era solo la prima, e una
/// finestra ingrandita dal suo pulsante si trascinava grande com'era, fuori
/// dallo schermo (27 settembre 2026).
///
/// Vale anche per un'AGGANCIATA. Giacomo, 7 settembre 2026: «staccala e vedi
/// che si riaggancia da sola, e non riesco a ridimensionarla se non la voglio
/// più a metà schermo». Staccata dal bordo restava larga mezzo schermo: il
/// ritorno alla misura di prima c'era solo per le ingrandite.
///
/// Parte col MOVIMENTO e non con la pressione: un semplice clic sulla barra
/// di una finestra ingrandita non deve rimpicciolirla.
static void presa_stacca(struct minerva *m, struct finestra *f) {
	if (m->presa != PRESA_SPOSTA || !(f->ingrandita || f->agganciata))
		return;
	const double quota = m->presa_box.width > 0
		? (m->presa_x - m->presa_box.x) / m->presa_box.width : 0.5;
	// La misura a cui torna, presa PRIMA di chiederla: il programma
	// risponde a un «ridimensionati» solo al suo prossimo disegno, e fino ad
	// allora `finestra_box` dice ancora la misura grande. Coi conti su quella
	// la finestra restava attaccata al bordo sinistro e il puntatore, preso
	// dalla parte destra della barra, finiva fuori (27 settembre 2026).
	const int torna_l = f->prima.width;
	if (f->ingrandita) {
		finestra_ingrandisci(f, false);
	} else {
		f->agganciata = false;
		if (f->prima.width > 0 && f->prima.height > 0)
			finestra_posiziona(f, f->prima.x, f->prima.y,
				f->prima.width, f->prima.height);
		barra_aggiorna(f);
		annuncia(f->m, "stato", f);
	}
	// La si riaggancia al puntatore, o schizzerebbe via del suo scarto
	// rispetto all'angolo.
	struct wlr_box ora;
	finestra_box(f, &ora);
	if (torna_l > 0)
		ora.width = torna_l;
	m->presa_box = ora;
	m->presa_box.x = (int)(m->presa_x - quota * ora.width);
	m->presa_box.y = (int)(m->presa_y - barra_alta() / 2);
	m->presa_x = m->cursore->x;
	m->presa_y = m->cursore->y;
}

static bool presa_avanti(struct minerva *m) {
	if (m->presa == PRESA_NIENTE || m->presa_di == NULL)
		return false;

	struct finestra *f = m->presa_di;
	const double dx = m->cursore->x - m->presa_x;
	const double dy = m->cursore->y - m->presa_y;

	// ── Il trascinamento comincia col MOVIMENTO, non con la pressione ────
	//
	// Lezione del plugin, pagata: cominciare alla pressione vuol dire che un
	// semplice clic sulla barra di una finestra ingrandita la rimpicciolisce.
	// Tre pixel di soglia, ed è anche ciò che distingue un clic da un
	// trascinamento quando si lascia.
	if (!m->presa_mossa) {
		if (dx * dx + dy * dy < 9.0)
			return true;
		m->presa_mossa = true;
		// L'elastico parte col MOVIMENTO e non con la pressione, per la
		// stessa ragione della soglia qui sopra: alla pressione non si sa
		// ancora se sarà un clic, e una finestra che rimbalza a ogni clic
		// sulla propria barra sarebbe insopportabile.
		f->wobbly_fallita = false;
		// Trascinare una finestra ingrandita la fa tornare piccola sotto la
		// mano, come ovunque. La si riaggancia al puntatore, o schizzerebbe
		// via del suo scarto rispetto all'angolo.
		//
		// ── E lo stesso per una AGGANCIATA ───────────────────────────
		//
		// Giacomo, 7 settembre 2026: «staccala e vedi che si riaggancia da
		// sola, e non riesco a ridimensionarla se non la voglio più a metà
		// schermo: sono costretto a fare un altro snap per rimpicciolirla».
		//
		// Non si riagganciava: restava della misura dell'aggancio. Staccata
		// dal bordo era ancora larga mezzo schermo, e l'unico modo di
		// cambiarla era agganciarla di nuovo altrove. Il ritorno alla misura
		// di prima c'era solo per le ingrandite, e un'agganciata non è
		// ingrandita — è la riga qui accanto che le distingue, giustamente,
		// e le aveva distinte anche dove non serviva.
		presa_stacca(m, f);
	}

	if (m->presa == PRESA_SPOSTA) {
		molla_avvia(f);
		int x = (int)(m->presa_box.x + dx);
		int y = (int)(m->presa_box.y + dy);
		trattieni(f, &x, &y);
		finestra_muovi(f, x, y);

		// ── E l'ombra dell'aggancio, sotto il puntatore ──────────────
		//
		// Si guarda dove sta il DITO, non dove sta la finestra: è il dito
		// che indica il bordo, e una finestra larga può toccarne due
		// insieme. Stessa scelta della barra disegnata dalla shell.
		struct wlr_box utile = {0, 0, 0, 0};
		const enum zona_aggancio zona = aggancio_zona(m, m->cursore->x,
			m->cursore->y, &utile);
		if (zona != m->aggancio_ora) {
			m->aggancio_ora = zona;
			if (zona == ZONA_NIENTE) {
				wlr_scene_node_set_enabled(&m->aggancio_ombra->node, false);
			} else {
				struct riquadro ru = da_box(&utile), rr;
				aggancio_riquadro(zona, &ru, &rr);
				const struct wlr_box r = a_box(&rr);
				wlr_scene_rect_set_size(m->aggancio_ombra, r.width, r.height);
				wlr_scene_node_set_position(&m->aggancio_ombra->node, r.x, r.y);
				wlr_scene_node_set_enabled(&m->aggancio_ombra->node, true);
			}
		}
		return true;
	}

	// Ridimensionamento: si parte sempre dal rettangolo di quando si è preso,
	// non da quello di adesso. Sommando gli spostamenti a ogni evento gli
	// arrotondamenti si accumulano, e la finestra scivola.
	struct wlr_box n = m->presa_box;
	if (m->presa_bordi & WLR_EDGE_LEFT) {
		n.x = (int)(m->presa_box.x + dx);
		n.width = (int)(m->presa_box.width - dx);
	} else if (m->presa_bordi & WLR_EDGE_RIGHT) {
		n.width = (int)(m->presa_box.width + dx);
	}
	if (m->presa_bordi & WLR_EDGE_TOP) {
		n.y = (int)(m->presa_box.y + dy);
		n.height = (int)(m->presa_box.height - dy);
	} else if (m->presa_bordi & WLR_EDGE_BOTTOM) {
		n.height = (int)(m->presa_box.height + dy);
	}

	const int minimo_w = 200;
	const int minimo_h = finestra_barra_alta(f) + 80;
	if (n.width < minimo_w) {
		if (m->presa_bordi & WLR_EDGE_LEFT)
			n.x = m->presa_box.x + m->presa_box.width - minimo_w;
		n.width = minimo_w;
	}
	if (n.height < minimo_h) {
		if (m->presa_bordi & WLR_EDGE_TOP)
			n.y = m->presa_box.y + m->presa_box.height - minimo_h;
		n.height = minimo_h;
	}

	// Tirando il bordo di sopra si può infilare la barra del titolo sotto il
	// pannello della scrivania, che è lo stesso modo di perdere una finestra
	// del trascinamento. Qui il freno agisce sul bordo, non sulla posizione:
	// l'altezza si accorcia di quanto si è dovuto scendere.
	struct wlr_box utile;
	finestra_utile(f, &utile);
	if (n.y < utile.y) {
		n.height -= utile.y - n.y;
		n.y = utile.y;
		if (n.height < minimo_h)
			n.height = minimo_h;
	}

	finestra_posiziona(f, n.x, n.y, n.width, n.height);
	return true;
}

// ── La riva riservata ────────────────────────────────────────────────────
//
// Giacomo, 25 settembre 2026: «se ho una app a schermo intero compaiono le
// isole passandoci sopra». Con una finestra che riempie lo schermo —
// ingrandita o a schermo intero — la riva non si muove da sola: angoli,
// bordi e spinte rispondono solo mentre Super è tenuto giù. È la prima
// regola dei tasti («Super da solo è la porta») applicata al puntatore.
// Senza finestre che riempiono lo schermo tutto resta com'era.
static bool riva_riservata(struct minerva *m, struct wlr_output *out) {
	if (out == NULL)
		return false;
	struct wlr_box box;
	wlr_output_layout_get_box(m->schermi, out, &box);
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (!finestra_visibile(f) || (!f->ingrandita && !f->schermo_intero))
			continue;
		struct wlr_box fb;
		finestra_box(f, &fb);
		if (wlr_box_contains_point(&box, fb.x + fb.width / 2.0, fb.y + fb.height / 2.0))
			return true;
	}
	return false;
}

static bool super_giu(struct minerva *m) {
	struct wlr_keyboard *kb = wlr_seat_get_keyboard(m->seat);
	return kb != NULL && (wlr_keyboard_get_modifiers(kb) & WLR_MODIFIER_LOGO);
}

/// La riva di questo schermo si può muovere adesso?
static bool riva_libera(struct minerva *m, struct wlr_output *out) {
	return !m->riva_col_consenso || !riva_riservata(m, out) || super_giu(m);
}

// ── Il bordo alto sopra lo schermo intero ────────────────────────────────
//
// A schermo intero l'unica via d'uscita visibile è la barra che scende
// portando il puntatore in cima (`spine/FullscreenBar.qml`). Per SENTIRE il
// puntatore la shell teneva mappata una superficie trasparente sopra il
// gioco — e una superficie mappata sopra la finestra basta a impedire lo
// scanout diretto, cioè a far comporre dalla GPU ogni fotogramma di un film
// o di un gioco che potrebbe andare dritto allo schermo. Misurato il 23
// settembre 2026: tre elementi in lista invece di uno, zero fotogrammi
// candidati.
//
// Il compositore sa sempre dov'è il puntatore: il sensore sta qui. Quando
// tocca i due pixel in cima a uno schermo con sopra una finestra a schermo
// intero, si annuncia `bordoalto`; la shell mostra la barra solo allora.
// Si ri-arma quando il puntatore scende oltre gli ottanta pixel, cioè
// quando la barra non può più esserci sotto.
/// Mezzo secondo fermi sul bordo alto, sopra uno schermo intero, senza
/// Super: la via d'uscita per chi non conosce la scorciatoia.
#define BORDO_ALTO_SOSTA_MS 500

static void bordo_alto_annuncia(struct minerva *m, const char *schermo) {
	m->bordo_alto_detto = true;
	char riga[160];
	snprintf(riga, sizeof(riga), "evento bordoalto {\"schermo\":\"%s\"}", schermo);
	canale_annuncia(m->canale, "bordoalto", riga);
}

/// Vero se sotto il puntatore c'è una finestra a schermo intero.
static bool sopra_schermo_intero(struct minerva *m) {
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (!f->schermo_intero || !finestra_visibile(f))
			continue;
		struct wlr_box fb;
		finestra_box(f, &fb);
		if (wlr_box_contains_point(&fb, m->cursore->x, m->cursore->y))
			return true;
	}
	return false;
}

static int bordo_alto_scade(void *dati) {
	struct minerva *m = dati;
	if (m->bordo_alto_detto || m->canale == NULL || m->bordo_alto_schermo[0] == '\0')
		return 0;
	// Il puntatore deve essere ancora lassù: un timer non sa se nel
	// frattempo la mano è scesa.
	struct wlr_output *out = wlr_output_layout_output_at(m->schermi,
		m->cursore->x, m->cursore->y);
	if (out == NULL || strcmp(out->name, m->bordo_alto_schermo) != 0)
		return 0;
	struct wlr_box box;
	wlr_output_layout_get_box(m->schermi, out, &box);
	if (m->cursore->y - box.y > 2 || !sopra_schermo_intero(m))
		return 0;
	bordo_alto_annuncia(m, out->name);
	return 0;
}

static void bordo_alto_guarda(struct minerva *m) {
	if (m->canale == NULL)
		return;
	struct wlr_output *out = wlr_output_layout_output_at(m->schermi,
		m->cursore->x, m->cursore->y);
	if (out == NULL)
		return;
	struct wlr_box box;
	wlr_output_layout_get_box(m->schermi, out, &box);
	const double dentro = m->cursore->y - box.y;
	if (dentro > 80) {
		m->bordo_alto_detto = false;
		m->bordo_alto_schermo[0] = '\0';
		return;
	}
	if (dentro > 2) {
		// Sceso dal bordo prima della sosta: non si conta più.
		m->bordo_alto_schermo[0] = '\0';
		return;
	}
	if (m->bordo_alto_detto || !sopra_schermo_intero(m))
		return;
	// ── La via d'uscita dallo schermo intero ─────────────────────────
	//
	// Con Super giù la barra scende subito. Senza, dopo mezzo secondo
	// fermi sul bordo: un gioco o un film non la vedono scendere per un
	// passaggio del puntatore, ma chi la cerca la trova. Qui prima c'era
	// SOLO Super («la riva col consenso di Super», 24 settembre 2026), e
	// una finestra mandata a schermo intero dal suo pulsante restava senza
	// nessuna uscita visibile: la barra sparisce, e che servisse Super non
	// lo diceva niente. Giacomo, 27 settembre: «la finestra diventa
	// ingestibile».
	if (!m->riva_col_consenso || super_giu(m)) {
		bordo_alto_annuncia(m, out->name);
		return;
	}
	if (m->bordo_alto_schermo[0] != '\0')
		return;                 // la sosta è già in corso
	snprintf(m->bordo_alto_schermo, sizeof(m->bordo_alto_schermo), "%s", out->name);
	if (m->bordo_alto_timer == NULL)
		m->bordo_alto_timer = wl_event_loop_add_timer(m->loop, bordo_alto_scade, m);
	if (m->bordo_alto_timer != NULL)
		wl_event_source_timer_update(m->bordo_alto_timer, BORDO_ALTO_SOSTA_MS);
}

// ── Gli angoli attivi ────────────────────────────────────────────────────
//
// Liquid DE apre le cose dagli angoli dello schermo: in basso a sinistra il
// menù delle app, in alto a destra il Centro di controllo, e così via. Chi
// sa dov'è il puntatore è il compositore, e il sensore sta qui come quello
// del bordo alto; cosa si apre lo decide la shell.
//
// Tre regole, tutte contro l'apertura per sbaglio:
//
//  · una SOSTA di 160 ms: passarci attraverso andando altrove non apre
//    niente. La conta un timer, perché un puntatore fermo in un angolo non
//    manda più movimenti;
//  · solo gli angoli VERI: fra due schermi affiancati l'angolo interno non
//    è un angolo, il puntatore ci passa per andare di là;
//  · niente mentre si trascina una finestra o a schermo bloccato; e con una
//    finestra che riempie lo schermo (ingrandita o a schermo intero) solo
//    con Super giù (`riva_libera`): un gioco non deve aprire il menù perché
//    il mouse è finito in un angolo.
//
// Anche i bordi alto e basso, fuori dagli angoli, con la stessa sosta: si
// annunciano come `evento bordo {"quale":"alto"}` e servono all'Isola a
// scomparsa.
//
// Si annuncia `evento angolo {"quale":"basso-sx","schermo":"eDP-1"}` dopo la
// sosta, e `evento angolo {"quale":"via"}` quando il puntatore se ne va da un
// angolo già detto.
#define ANGOLO_SOSTA_MS 160

// Tre pixel sul bordo dello schermo vero, dove il puntatore si ferma da solo.
// In una prova annidata DENTRO UNA FINESTRA il bordo non ferma niente — oltre
// c'è l'altra scrivania — e un angolo di tre pixel è quasi impossibile da
// prendere: `MINERVA_ANGOLO_LATO` lo allarga (lo mette `prova-annidata.sh`).
static int angolo_lato(void) {
	static int lato = 0;
	if (lato == 0) {
		const char *detto = getenv("MINERVA_ANGOLO_LATO");
		lato = detto != NULL ? atoi(detto) : 3;
		if (lato < 1 || lato > 64)
			lato = 3;
	}
	return lato;
}

static int angolo_scade(void *dati) {
	struct minerva *m = dati;
	if (m->angolo_ora == NULL || m->angolo_detto || m->canale == NULL)
		return 0;
	m->angolo_detto = true;
	// Il bordo alto e quello basso (l'Isola a scomparsa) si annunciano come
	// bordi, gli angoli come angoli: sono due ascolti diversi nella shell.
	const bool bordo = strcmp(m->angolo_ora, "alto") == 0 || strcmp(m->angolo_ora, "basso") == 0;
	char riga[160];
	snprintf(riga, sizeof(riga), "evento %s {\"quale\":\"%s\",\"schermo\":\"%s\"}",
		bordo ? "bordo" : "angolo", m->angolo_ora, m->angolo_schermo);
	canale_annuncia(m->canale, bordo ? "bordo" : "angolo", riga);
	return 0;
}

static void angolo_guarda(struct minerva *m) {
	const char *quale = NULL;
	struct wlr_output *out = wlr_output_layout_output_at(m->schermi,
		m->cursore->x, m->cursore->y);
	if (out != NULL && !m->bloccato && m->presa == PRESA_NIENTE) {
		struct wlr_box box;
		wlr_output_layout_get_box(m->schermi, out, &box);
		const double cx = m->cursore->x, cy = m->cursore->y;
		const int lato = angolo_lato();
		const bool sx = cx < box.x + lato;
		const bool dx = cx > box.x + box.width - 1 - lato;
		const bool alto = cy < box.y + lato;
		const bool basso = cy > box.y + box.height - 1 - lato;
		if ((sx || dx) && (alto || basso)) {
			// Un angolo è vero se oltre i suoi due lati non c'è un altro
			// schermo.
			const double fuori_x = sx ? box.x - 4 : box.x + box.width + 4;
			const double fuori_y = alto ? box.y - 4 : box.y + box.height + 4;
			const bool vero =
				wlr_output_layout_output_at(m->schermi, fuori_x, cy) == NULL &&
				wlr_output_layout_output_at(m->schermi, cx, fuori_y) == NULL;
			if (vero && riva_libera(m, out))
				quale = alto ? (sx ? "alto-sx" : "alto-dx")
				             : (sx ? "basso-sx" : "basso-dx");
		} else if (alto || basso) {
			// Il bordo alto o basso, fuori dagli angoli: da lì ricompare
			// l'Isola a scomparsa. Vero se oltre non c'è un altro schermo.
			const double fuori_y = alto ? box.y - 4 : box.y + box.height + 4;
			if (wlr_output_layout_output_at(m->schermi, cx, fuori_y) == NULL
			    && riva_libera(m, out))
				quale = alto ? "alto" : "basso";
		}
	}

	// Confronto per contenuto: due letterali uguali non hanno per forza lo
	// stesso indirizzo.
	if ((quale == NULL && m->angolo_ora == NULL)
	    || (quale != NULL && m->angolo_ora != NULL && strcmp(quale, m->angolo_ora) == 0))
		return;

	// Cambiato angolo, o uscito: quello di prima si chiude. I bordi alto e
	// basso non hanno un «via»: l'Isola se ne va da sola quando il puntatore
	// la lascia.
	if (m->angolo_detto && m->canale != NULL && m->angolo_ora != NULL
	    && strcmp(m->angolo_ora, "alto") != 0 && strcmp(m->angolo_ora, "basso") != 0)
		canale_annuncia(m->canale, "angolo", "evento angolo {\"quale\":\"via\"}");
	m->angolo_detto = false;
	m->angolo_ora = quale;
	if (m->angolo_timer == NULL)
		m->angolo_timer = wl_event_loop_add_timer(m->loop, angolo_scade, m);
	if (m->angolo_timer == NULL)
		return;
	if (quale == NULL) {
		wl_event_source_timer_update(m->angolo_timer, 0);
		return;
	}
	snprintf(m->angolo_schermo, sizeof(m->angolo_schermo), "%s", out->name);
	wl_event_source_timer_update(m->angolo_timer, ANGOLO_SOSTA_MS);
}

// ── La spinta sui bordi di lato ──────────────────────────────────────────
//
// Dal bordo destro esce il Cassetto (gli appunti), dal sinistro le Stanze. Il bordo destro però è
// anche dove si va a prendere la barra di scorrimento di una finestra
// ingrandita: fermarcisi è una cosa che si fa di continuo, e una SOSTA come
// quella degli angoli aprirebbe il Cassetto ogni volta che si scorre una
// pagina. Qui serve un gesto che nessuno fa per caso: SPINGERE oltre il
// bordo. Il puntatore è fermo contro lo schermo e la mano continua ad andare
// a destra — ogni pixel che il compositore non ha potuto dare al puntatore
// si somma; 90 pixel di spinta aprono. La spinta si svuota se ci si ferma
// più di 400 ms, e si ri-arma solo lasciando il bordo.
//
// Solo nel tratto di mezzo (gli angoli sono degli angoli), solo su un bordo
// VERO (oltre non c'è un altro schermo), e non sopra lo schermo intero, a
// schermo bloccato o mentre si trascina una finestra: le stesse regole degli
// angoli.
//
// Si annuncia `evento bordo {"quale":"destra","schermo":"eDP-1"}` (o
// «sinistra»). `oltre` è quanto il puntatore ha provato ad andare oltre: in
// pixel, positivo verso destra.
#define SPINTA_SOGLIA 90.0
#define SPINTA_PAUSA_MS 400

static void bordo_spinto(struct minerva *m, double oltre, uint32_t tempo) {
	struct wlr_output *out = wlr_output_layout_output_at(m->schermi,
		m->cursore->x, m->cursore->y);
	int lato = 0;
	if (out != NULL && !m->bloccato && m->presa == PRESA_NIENTE) {
		struct wlr_box box;
		wlr_output_layout_get_box(m->schermi, out, &box);
		const double cx = m->cursore->x, cy = m->cursore->y;
		const double margine = box.height * 0.15;
		const bool mezzo = cy > box.y + margine && cy < box.y + box.height - margine;
		if (mezzo && cx >= box.x + box.width - 2
		    && wlr_output_layout_output_at(m->schermi, box.x + box.width + 4, cy) == NULL)
			lato = 1;
		else if (mezzo && cx <= box.x + 1
		    && wlr_output_layout_output_at(m->schermi, box.x - 4, cy) == NULL)
			lato = -1;
		if (lato != 0 && !riva_libera(m, out))
			lato = 0;
	}
	if (lato != m->spinta_lato) {
		m->spinta = 0;
		m->spinta_detta = false;
		m->spinta_lato = lato;
	}
	if (lato == 0)
		return;
	// Conta solo la spinta verso il bordo su cui si sta.
	const double verso = oltre * lato;
	if (verso <= 0 || m->spinta_detta)
		return;
	if (tempo - m->spinta_quando > SPINTA_PAUSA_MS)
		m->spinta = 0;
	m->spinta_quando = tempo;
	m->spinta += verso;
	if (m->spinta < SPINTA_SOGLIA || m->canale == NULL)
		return;
	m->spinta_detta = true;
	char riga[160];
	snprintf(riga, sizeof(riga), "evento bordo {\"quale\":\"%s\",\"schermo\":\"%s\"}",
		lato > 0 ? "destra" : "sinistra", out->name);
	canale_annuncia(m->canale, "bordo", riga);
}

static void cursore_aggiorna(struct minerva *m, uint32_t tempo) {
	bordo_alto_guarda(m);
	angolo_guarda(m);
	// ── «Qualcuno c'è» ───────────────────────────────────────────────
	//
	// Va detto PRIMA di ogni ritorno anticipato: durante una presa della
	// barra del titolo il puntatore si muove eccome, e uscire di qui senza
	// dirlo vorrebbe dire che lo schermo si blocca mentre si sta trascinando
	// una finestra. Un blocco che scatta mentre hai la mano sul mouse è la
	// cosa che fa spegnere il blocco automatico a tutti.
	attivita(m);

	// L'icona del trascinamento sta sotto il dito, e ci sta PRIMA di ogni
	// ritorno anticipato: durante una presa della barra il puntatore si muove,
	// e un'icona che si ferma mentre la mano no è peggio che non averla.
	if (m->icona_trascinata != NULL)
		wlr_scene_node_set_position(&m->icona_trascinata->node,
			(int)m->cursore->x, (int)m->cursore->y);

	if (presa_avanti(m))
		return;

	// ── La presa implicita ───────────────────────────────────────────────
	//
	// Wayland la dà per scontata: finché un pulsante è giù, il puntatore
	// resta alla superficie su cui è stato premuto, anche se esce dai suoi
	// bordi. Qui non c'era — il fuoco seguiva la superficie sotto il
	// puntatore anche col pulsante giù — e ogni trascinamento che usciva
	// dalla superficie si fermava a metà: la barra di scorrimento tirata
	// fuori dalla finestra, il testo selezionato oltre il bordo, le maniglie
	// del menù, l'Isola trascinata in basso. Visto il 24 settembre 2026
	// provando l'Isola: la capsula restava «premuta» e non si spostava.
	//
	// Non vale mentre si trascina un file (lì il bersaglio DEVE cambiare) né
	// mentre il compositore sposta una finestra (`presa_avanti`, sopra).
	if (m->tenuta != NULL) {
		if (m->seat->pointer_state.focused_surface == m->tenuta
		    && m->seat->drag == NULL) {
			wlr_seat_pointer_notify_motion(m->seat, tempo,
				m->cursore->x - m->tenuta_x, m->cursore->y - m->tenuta_y);
			return;
		}
		m->tenuta = NULL;
	}

	struct sotto s;
	cosa_c_e_sotto(m, &s);

	// ── Il pulsante che si accende al passaggio ──────────────────────────
	if (s.finestra != NULL && s.sulla_barra) {
		int nx = 0, ny = 0;
		wlr_scene_node_coords(&s.finestra->barra->node, &nx, &ny);
		int lw = 0, lh = 0;
		finestra_geometria(s.finestra, &lw, &lh);
		dito_su(m, s.finestra, barra_pulsante_a(m->cursore->x - nx,
			m->cursore->y - ny, lw));
	} else {
		dito_su(m, NULL, -1);
	}

	if (s.finestra != NULL && s.sul_bordo) {
		const uint32_t bordi = bordi_sotto(s.finestra, m->cursore->x,
			m->cursore->y);
		wlr_cursor_set_xcursor(m->cursore, m->cursore_tema,
			freccia_bordi(bordi));
		wlr_seat_pointer_notify_clear_focus(m->seat);
		m->superficie_sotto = NULL;
		return;
	}

	if (s.superficie == NULL) {
		// Sopra il vuoto — o sopra la nostra barra, che non è di nessun
		// programma — si rimette la freccia e si toglie il fuoco: senza, il
		// puntatore resta con l'aspetto che gli aveva dato l'ultima finestra
		// attraversata.
		wlr_cursor_set_xcursor(m->cursore, m->cursore_tema, "default");
		wlr_seat_pointer_notify_clear_focus(m->seat);
		m->superficie_sotto = NULL;
		return;
	}

	// ── La freccia, PRIMA di consegnare il puntatore ─────────────────────
	//
	// In Wayland, quando il puntatore entra in una superficie, che aspetto
	// abbia **non lo decide più il compositore**: lo decide il programma, con
	// `set_cursor`. E finché non lo dice — o se non lo dice mai — non lo
	// disegna nessuno.
	//
	// Il sintomo l'ha visto Giacomo il 26 agosto 2026, alla prima prova vera:
	// «non riesco a vedere il mouse oltre alla barra». Sopra la barra la
	// shell il cursore lo imposta (ci sono i pulsanti); sopra la SCRIVANIA no
	// — ma la scrivania è una superficie anche lei, quella dello sfondo, e il
	// puntatore ci entrava dentro sparendo.
	//
	// Si mette la freccia entrando in una superficie NUOVA. Se il programma
	// ne vuole un'altra la chiede subito dopo, e `cursore_richiesto` la
	// sostituisce prima che si veda niente. Rimetterla a ogni movimento
	// invece cancellerebbe la barretta del testo mentre si scrive.
	if (s.superficie != m->superficie_sotto) {
		m->superficie_sotto = s.superficie;
		wlr_cursor_set_xcursor(m->cursore, m->cursore_tema, "default");
	}

	wlr_seat_pointer_notify_enter(m->seat, s.superficie, s.sx, s.sy);
	wlr_seat_pointer_notify_motion(m->seat, tempo, s.sx, s.sy);
}

static void cursore_mosso(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, cursore_mosso);
	struct wlr_pointer_motion_event *e = dati;
	double dx = e->delta_x, dy = e->delta_y;
	puntatore_consenti(m->puntatore, !m->bloccato && m->presa == PRESA_NIENTE);
	puntatore_movimento(m->puntatore, (uint64_t)e->time_msec * 1000,
		&dx, &dy, e->unaccel_dx, e->unaccel_dy, true);
	const double voluta = m->cursore->x + dx;
	wlr_cursor_move(m->cursore, &e->pointer->base, dx, dy);
	bordo_spinto(m, voluta - m->cursore->x, e->time_msec);
	cursore_aggiorna(m, e->time_msec);
}

static void cursore_assoluto(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, cursore_assoluto);
	struct wlr_pointer_motion_absolute_event *e = dati;
	// Il movimento assoluto arriva dai touchscreen, dalle tavolette e — cosa
	// che ci riguarda da vicino — dal backend annidato, dove il puntatore è
	// quello del compositore che ci ospita.
	double x, y;
	wlr_cursor_absolute_to_layout_coords(m->cursore, &e->pointer->base, e->x, e->y, &x, &y);
	double dx = x - m->cursore->x, dy = y - m->cursore->y;
	puntatore_consenti(m->puntatore, !m->bloccato && m->presa == PRESA_NIENTE);
	// Applica i vincoli, ma non inventare delta relativi non accelerati:
	// con il cursore bloccato sarebbero distanze dal punto fermo, non moto.
	puntatore_movimento(m->puntatore, (uint64_t)e->time_msec * 1000,
		&dx, &dy, dx, dy, false);
	wlr_cursor_move(m->cursore, &e->pointer->base, dx, dy);
	cursore_aggiorna(m, e->time_msec);
}

/// Che cosa fa un pulsante della barra.
static void pulsante_premuto(struct finestra *f, int quale) {
	switch (quale) {
	case PULSANTE_RIDUCI:
		finestra_riduci(f, true);
		break;
	case PULSANTE_INGRANDISCI:
		finestra_ingrandisci(f, !f->ingrandita);
		break;
	case PULSANTE_SCHERMO:
		finestra_schermo_intero(f, !f->schermo_intero);
		break;
	case PULSANTE_CHIUDI:
		// `send_close` è una richiesta: un programma con del lavoro non
		// salvato può rispondere con una finestra di conferma, ed è giusto
		// così. Ucciderlo sarebbe più semplice e sbagliato.
		finestra_di_chiuditi(f);
		break;
	default:
		break;
	}
}

/// Il nome di un tasto del mouse, per il registro.
static const char *nome_pulsante(uint32_t b) {
	switch (b) {
	case BTN_LEFT:   return "sinistro";
	case BTN_RIGHT:  return "destro";
	case BTN_MIDDLE: return "centrale";
	case BTN_SIDE:   return "laterale";
	case BTN_EXTRA:  return "extra";
	default:         return "altro";
	}
}


// ── Il dito che si alza ───────────────────────────────────────────────────
//
/// Quello che succede quando un pulsante viene LASCIATO: si chiude la presa,
/// si compie l'aggancio, si preme il pulsante della barra del titolo su cui
/// il dito era sceso, e in mancanza d'altro il rilascio va al programma.
///
/// Sta in una funzione sua dall'8 settembre 2026. `cursore_premuto` era
/// centoquarantasette righe di codice contro le dieci della media del file, e
/// non era una questione di eleganza: è la funzione che riceve OGNI clic della
/// scrivania, ed è da qui che sono usciti i tre difetti di settembre — il
/// tasto destro, il trascinamento, e l'aggancio che arrivava mezzo secondo
/// dopo. Cercarli dentro un blocco lungo il doppio dello schermo è la ragione
/// per cui ci sono voluti tre giorni.
static void cursore_rilasciato(struct minerva *m,
		struct wlr_pointer_button_event *e) {
	const bool era_presa = m->presa != PRESA_NIENTE;
	struct finestra *f = m->presa_di;
	const int pulsante = m->presa_pulsante;
	const bool trascinata = m->presa_mossa;

	m->presa = PRESA_NIENTE;
	m->presa_di = NULL;
	m->presa_pulsante = -1;

	// ── L'aggancio si compie qui, al rilascio ────────────────────
	//
	// Durante il trascinamento si è solo MOSTRATO dove andrà: spostarla
	// prima vorrebbe dire una finestra che salta da metà schermo all'altra
	// mentre la mano passa sopra i bordi, e nessun modo di cambiare idea.
	//
	// L'ombra si spegne SEMPRE, anche quando non si aggancia niente —
	// altrimenti resta accesa sullo schermo, e un rettangolo azzurro che
	// non se ne va è il genere di difetto che si ripara riavviando.
	const enum zona_aggancio zona = m->aggancio_ora;
	m->aggancio_ora = ZONA_NIENTE;
	wlr_scene_node_set_enabled(&m->aggancio_ombra->node, false);
	if (era_presa && f != NULL && trascinata && zona != ZONA_NIENTE) {
		struct wlr_box utile = {0, 0, 0, 0};
		if (aggancio_zona(m, m->cursore->x, m->cursore->y, &utile)
				!= ZONA_NIENTE) {
			struct riquadro ru = da_box(&utile), rr;
			aggancio_riquadro(zona, &ru, &rr);
			const struct wlr_box r = a_box(&rr);
			// ── Si POSIZIONA, non si ridimensiona soltanto ──────
			//
			// Qui c'era `finestra_di_geometria`, che per una finestra
			// Wayland manda **solo la misura**: la posizione la butta via
			// (`(void)x; (void)y;`). La finestra restava dove l'aveva
			// lasciata la mano, e si spostava solo quando il programma
			// finiva di ridisegnarsi.
			//
			// Giacomo, 7 settembre 2026: «lo snap non è istantaneo, la
			// posizioni come vuoi e lasci e passa più di mezzo secondo e
			// poi si posiziona come voglio».
			//
			// Misurato: il compositore decideva nello STESSO millisecondo
			// del rilascio — rilascio e aggancio portano lo stesso
			// `time_msec` nel registro — e la finestra si vedeva arrivare
			// 0,34 s dopo la fine del gesto. Non era lentezza: era che
			// nessuno l'aveva spostata.
			//
			// `finestra_posiziona` fa tutte e due le cose ed è quella che
			// usano «aggancia», «ingrandisci» e la nascita di una
			// finestra. Il conto della barra del titolo lo fa lei — la
			// barra è NOSTRA e sta sopra il programma, quindi al programma
			// si chiede meno altezza — e farlo qui una seconda volta era
			// anche l'occasione perché i due conti divergessero.
			// Ci si ricorda com'era, o staccandola non si saprebbe a
			// che misura tornare. Vedi `aggancia_attiva`, che fa lo
			// stesso: le due strade dell'aggancio devono lasciare la
			// finestra nello stesso stato, o una delle due si stacca e
			// l'altra no.
			if (!f->agganciata)
				finestra_box(f, &f->prima);
			f->agganciata = true;
			finestra_posiziona(f, r.x, r.y, r.width, r.height);
			if (m->traccia_pulsanti)
				fprintf(stderr, "minerva-wayland: [%u] AGGANCIATA a "
					"%d,%d %dx%d\n", e->time_msec,
					r.x, r.y, r.width, r.height);
			annuncia(m, "mossa", f);
			return;
		}
	}

	// ── «Mossa» si annuncia alla FINE, non durante ───────────────
	//
	// Durante il trascinamento la finestra cambia posizione a ogni
	// fotogramma: annunciarla lì vorrebbe dire svegliare il demone
	// sessanta volte al secondo, cioè rifare esattamente il costo che
	// questo progetto ha passato settimane a togliere — vedi
	// `minerva-prestazioni-svegliarsi`. Chi ha bisogno della posizione
	// mentre la finestra si muove non deve chiederla a noi: se la
	// disegna il compositore (la barra del titolo è già nostra), o la
	// segue col puntatore.
	if (era_presa && f != NULL && trascinata)
		annuncia(m, "mossa", f);

	// Un pulsante si attiva al RILASCIO e solo se il dito è ancora sopra:
	// è quello che permette di premere per sbaglio e scappare via.
	if (era_presa && f != NULL && pulsante >= 0 && !trascinata) {
		int nx = 0, ny = 0;
		if (f->barra != NULL)
			wlr_scene_node_coords(&f->barra->node, &nx, &ny);
		int lw = 0, lh = 0;
		finestra_geometria(f, &lw, &lh);
		const int ancora = barra_pulsante_a(m->cursore->x - nx,
			m->cursore->y - ny, lw);
		if (ancora == pulsante)
			pulsante_premuto(f, pulsante);
		return;
	}
	// Il rilascio al programma lo consegna chi ci chiama, su OGNI strada:
	// vedi `cursore_premuto`.
}

static void cursore_premuto(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, cursore_premuto);
	struct wlr_pointer_button_event *e = dati;

	// Un clic mentre Super è giù fa di Super+clic una combinazione: né il
	// tocco (il menù al rilascio) né il «tieni» devono scattare dopo un
	// Super+trascina. Prima, lasciando Super dopo aver spostato una finestra,
	// si apriva il menù.
	if (e->state == WL_POINTER_BUTTON_STATE_PRESSED)
		m->ultimo_premuto = 0;

	if (m->traccia_pulsanti)
		fprintf(stderr, "minerva-wayland: [%u] pulsante ARRIVATO %s (0x%x) %s\n",
			e->time_msec, nome_pulsante(e->button), e->button,
			e->state == WL_POINTER_BUTTON_STATE_PRESSED ? "premuto" : "lasciato");

	// ── Cliccare è toccare qualcosa ──────────────────────────────────
	//
	// Fino al 1º settembre 2026 l'attività si dichiarava SOLO dal movimento
	// del puntatore e dalla tastiera. Chi legge una pagina lunga e scorre
	// con la rotellina, o chi guarda un video e clicca ogni tanto, non muove
	// il mouse di un pixel: per il conto dell'inattività era fermo, e lo
	// schermo gli si abbassava sotto gli occhi. Valeva anche per `hypridle`,
	// che leggeva lo stesso contatore.
	attivita(m);

	if (e->state == WL_POINTER_BUTTON_STATE_RELEASED) {
		cursore_rilasciato(m, e);
		// ── Il rilascio arriva SEMPRE ────────────────────────────────────
		//
		// Qui dentro c'erano tre `return` prima della consegna: dopo una
		// presa (la barra di un'app che si disegna da sé chiede di essere
		// spostata, Super+trascina), dopo un aggancio, dopo un pulsante della
		// nostra barra. Il programma aveva visto la PRESSIONE e non vedeva
		// mai il rilascio: per lui il tasto restava giù. E per wlroots
		// peggio: il sedile contava il pulsante ancora premuto, e alla
		// pressione dopo ne contava due e NON LA CONSEGNAVA (`n_pressed`, in
		// `wlr_seat_pointer_notify_button`). Da lì nessun clic arrivava più a
		// nessun programma, e restava solo la tastiera. Giacomo, 27 settembre
		// 2026: «le finestre una volta aperte non si possono spostare o
		// chiudere e sono obbligato a chiuderle con alt+f4».
		//
		// Consegnarlo sempre non costa niente: un rilascio di un pulsante
		// che il sedile non ha visto premere, wlroots lo scarta da sé.
		if (m->traccia_pulsanti)
			fprintf(stderr, "minerva-wayland: rilascio CONSEGNATO %s (0x%x)\n",
				nome_pulsante(e->button), e->button);
		wlr_seat_pointer_notify_button(m->seat, e->time_msec, e->button,
			e->state);
		// Finita la presa implicita, il puntatore torna a chi gli sta sotto.
		if (m->tenuta != NULL && m->seat->pointer_state.button_count == 0) {
			m->tenuta = NULL;
			cursore_aggiorna(m, e->time_msec);
		}
		return;
	}

	struct sotto s;
	cosa_c_e_sotto(m, &s);

	if (s.finestra != NULL)
		fuoco_finestra(m, s.finestra);

	// ── Super + trascina / Super + destro ────────────────────────────────
	//
	// Il gesto che uno prova per istinto quando la barra del titolo è sotto
	// un menu aperto, o quando la finestra è più grande dello schermo e la
	// maniglia non si vede: si tiene Super e si trascina da un punto
	// qualunque. Col tasto destro, si ridimensiona.
	//
	// Perché non è una scorciatoia: `config/scorciatoie.minerva` le scrive
	// come `$mod mouse_down`, e `mouse_down` **non è un tasto xkb** —
	// verificato, `xkb_keysym_from_name` risponde NO_SYMBOL. Quelle righe
	// venivano rifiutate in silenzio dal compositore. Il posto giusto è qui,
	// dove i tasti del mouse arrivano davvero.
	//
	// Il lato da cui ridimensionare non si chiede: lo dice il QUADRANTE in
	// cui si è preso. Prendere in basso a destra e vedersi muovere il bordo
	// in alto a sinistra è il modo classico di far sembrare rotto un gesto
	// che funziona.
	if (s.finestra != NULL && !m->bloccato
			&& (e->button == BTN_LEFT || e->button == BTN_RIGHT)) {
		uint32_t mods = 0;
		struct wlr_keyboard *kb = wlr_seat_get_keyboard(m->seat);
		if (kb != NULL)
			mods = wlr_keyboard_get_modifiers(kb) & MODIFICATORI_CHE_CONTANO;
		if (mods == WLR_MODIFIER_LOGO) {
			struct finestra *f = s.finestra;
			if (e->button == BTN_LEFT) {
				presa_inizia(f, PRESA_SPOSTA, 0);
			} else {
				struct wlr_box b;
				finestra_box(f, &b);
				uint32_t bordi = 0;
				bordi |= (m->cursore->x < b.x + b.width / 2)
					? WLR_EDGE_LEFT : WLR_EDGE_RIGHT;
				bordi |= (m->cursore->y < b.y + b.height / 2)
					? WLR_EDGE_TOP : WLR_EDGE_BOTTOM;
				presa_inizia(f, PRESA_RIDIMENSIONA, bordi);
			}
			m->presa_pulsante = -1;
			m->presa_mossa = true;
			return;
		}
	}

	// ── Il bordo: si prende e si ridimensiona ────────────────────────────
	if (s.finestra != NULL && s.sul_bordo
			&& e->button == BTN_LEFT) {
		const uint32_t bordi = bordi_sotto(s.finestra, m->cursore->x,
			m->cursore->y);
		if (bordi != 0) {
			presa_inizia(s.finestra, PRESA_RIDIMENSIONA, bordi);
			m->presa_pulsante = -1;
			m->presa_mossa = true;
			return;
		}
	}

	// ── La barra: pulsanti, trascinamento, doppio clic ───────────────────
	if (s.finestra != NULL && s.sulla_barra && e->button == BTN_LEFT) {
		struct finestra *f = s.finestra;
		int nx = 0, ny = 0;
		if (f->barra != NULL)
			wlr_scene_node_coords(&f->barra->node, &nx, &ny);
		int lw = 0, lh = 0;
		finestra_geometria(f, &lw, &lh);
		const int quale = barra_pulsante_a(m->cursore->x - nx,
			m->cursore->y - ny, lw);

		// Il doppio clic ingrandisce. «Doppio» non ce lo dice nessuno: sono
		// due clic vicini nel tempo E nello spazio, e senza il secondo
		// controllo due clic su due pulsanti diversi contano come doppio.
		const bool vicino_nel_tempo = e->time_msec - m->ultimo_clic < 400;
		const bool vicino_nel_posto =
			fabs(m->cursore->x - m->ultimo_clic_x) < 8 &&
			fabs(m->cursore->y - m->ultimo_clic_y) < 8;
		m->ultimo_clic = e->time_msec;
		m->ultimo_clic_x = m->cursore->x;
		m->ultimo_clic_y = m->cursore->y;

		if (quale < 0 && vicino_nel_tempo && vicino_nel_posto) {
			finestra_ingrandisci(f, !f->ingrandita);
			m->ultimo_clic = 0;
			return;
		}

		presa_inizia(f, PRESA_SPOSTA, 0);
		m->presa_pulsante = quale;
		if (quale >= 0) {
			// Su un pulsante non si trascina: si preme. Marcare la presa come
			// «già mossa» la escluderebbe dal conto del clic.
			m->presa_mossa = false;
		}
		return;
	}

	// Il clic si consegna al programma SEMPRE, anche quando sposta il fuoco.
	// Trattenerlo per «non far passare il clic che attiva la finestra» è una
	// scelta che alcuni compositori fanno e che qui non si fa: significa che
	// il primo clic su un pulsante non lo preme, e su una scrivania si nota
	// subito.
	if (m->traccia_pulsanti)
		fprintf(stderr, "minerva-wayland: pulsante CONSEGNATO %s (0x%x)\n",
			nome_pulsante(e->button), e->button);
	wlr_seat_pointer_notify_button(m->seat, e->time_msec, e->button, e->state);
	// La presa implicita comincia qui: vedi `cursore_aggiorna`.
	if (s.superficie != NULL
	    && m->seat->pointer_state.focused_surface == s.superficie) {
		m->tenuta = s.superficie;
		m->tenuta_x = m->cursore->x - s.sx;
		m->tenuta_y = m->cursore->y - s.sy;
	}

	if (s.finestra != NULL)
		return;

	enum tipo_nodo tipo;
	double sx, sy;
	struct wlr_scene_node *nodo = wlr_scene_node_at(&m->scena->tree.node,
		m->cursore->x, m->cursore->y, &sx, &sy);
	if (nodo == NULL)
		return;
	void *chi = nodo_proprietario(nodo, &tipo);
	if (chi == NULL || tipo != NODO_APPOGGIATA)
		return;

	// Un pannello di Minerva prende i tasti solo se li ha CHIESTI. È il
	// significato di `keyboardFocus: OnDemand` nel nostro QML: la barra in
	// cima non deve rubare la tastiera a chi sta scrivendo solo perché ci si
	// passa sopra con il mouse.
	struct appoggiata *ap = chi;
	if (ap->ls->current.keyboard_interactive
			!= ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE)
		fuoco_tastiera(m, ap->ls->surface);
}

// ── Super + rotellina = cambia scrivania ─────────────────────────────────
//
// Il gesto che Giacomo ha chiesto il 30 agosto 2026: «se clicco il tasto super
// e tenendo premuto giro la rotellina vorrei cambiare desktop».
//
// **Non può essere una scorciatoia**, e il motivo è netto: le scorciatoie si
// riconoscono da un simbolo xkb, e la rotellina non ne ha uno. Verificato
// chiamando xkb: `xkb_keysym_from_name("mouse_down")` risponde NoSymbol. Nella
// sorgente le due righe ci sono da sempre — `$mod mouse_down -> scrivania:
// prossima` — e il demone le scartava, giustamente, perché il compositore
// avrebbe risposto «il tasto non esiste». Il posto giusto è qui: chi riceve
// l'asse del puntatore.
//
// ── La rotellina di oggi non fa scatti, fa polvere ───────────────────────
//
// Un mouse vecchio manda una tacca per volta. Un touchpad e i mouse moderni
// mandano decine di micro-movimenti, e agire su ognuno vorrebbe dire saltare
// otto scrivanie con un dito che scorre di un centimetro. Si accumula finché
// non si è fatta una tacca intera, e solo allora si cambia.
//
// `delta_discrete` è in 120esimi di tacca (l'API «v120»): quando c'è, è la
// misura giusta perché la manda il dispositivo. Quando è zero — i touchpad —
// si accumula `delta`, che è in unità di scorrimento, e una tacca vale 15.
#define ROTELLA_TACCA_V120 120
#define ROTELLA_TACCA_LIBERA 15.0

static void cursore_rotella(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, cursore_rotella);
	struct wlr_pointer_axis_event *e = dati;

	// Anche la rotellina. Vedi la nota in `cursore_premuto`.
	attivita(m);

	// Solo la rotellina verticale, e solo col tasto Super premuto. Da
	// bloccati no: cambiare scrivania è comandare la sessione di qualcuno
	// senza averla sbloccata.
	uint32_t mods = 0;
	struct wlr_keyboard *kb = wlr_seat_get_keyboard(m->seat);
	if (kb != NULL)
		mods = wlr_keyboard_get_modifiers(kb) & MODIFICATORI_CHE_CONTANO;

	if (!m->bloccato && mods == WLR_MODIFIER_LOGO
			&& e->orientation == WL_POINTER_AXIS_VERTICAL_SCROLL) {
		int tacche = 0;
		if (e->delta_discrete != 0) {
			m->rotella_v120 += e->delta_discrete;
			while (m->rotella_v120 >= ROTELLA_TACCA_V120) {
				m->rotella_v120 -= ROTELLA_TACCA_V120;
				tacche++;
			}
			while (m->rotella_v120 <= -ROTELLA_TACCA_V120) {
				m->rotella_v120 += ROTELLA_TACCA_V120;
				tacche--;
			}
		} else {
			m->rotella_libera += e->delta;
			while (m->rotella_libera >= ROTELLA_TACCA_LIBERA) {
				m->rotella_libera -= ROTELLA_TACCA_LIBERA;
				tacche++;
			}
			while (m->rotella_libera <= -ROTELLA_TACCA_LIBERA) {
				m->rotella_libera += ROTELLA_TACCA_LIBERA;
				tacche--;
			}
		}
		// Giù = la scrivania dopo, come nella sorgente delle scorciatoie.
		for (int i = 0; i < (tacche < 0 ? -tacche : tacche); i++)
			scrivania_vicina(m, tacche > 0);
		// E l'evento NON passa al programma sotto: il gesto è nostro, e
		// lasciarlo passare vorrebbe dire cambiare scrivania **e** far
		// scorrere la pagina che si stava guardando.
		return;
	}

	// Mollato Super, l'accumulo si azzera: due mezze tacche prese a dieci
	// minuti di distanza non fanno una tacca.
	m->rotella_v120 = 0;
	m->rotella_libera = 0.0;

	wlr_seat_pointer_notify_axis(m->seat, e->time_msec, e->orientation,
		e->delta, e->delta_discrete, e->source, e->relative_direction);
}

// ── L'aspetto del puntatore lo decide chi ci sta sotto ───────────────────
//
// Senza questa, il puntatore resta una freccia dappertutto: niente barretta di
// testo sopra un campo da scrivere, niente mano sopra un collegamento, niente
// frecce ai bordi di una finestra da ridimensionare. Non dà nessun errore —
// dà una scrivania che sembra finta, e non si capisce perché.
static void cursore_richiesto(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, cursore_richiesto);
	struct wlr_seat_pointer_request_set_cursor_event *e = dati;

	// Si accetta solo dal cliente che ha il puntatore ADESSO. Al contrario,
	// una finestra in secondo piano potrebbe cambiare il cursore mentre si
	// lavora in un'altra: piccolo, ma è una finestra che agisce fuori dal
	// proprio turno, e quelle si chiudono subito.
	if (e->seat_client != m->seat->pointer_state.focused_client)
		return;

	wlr_cursor_set_surface(m->cursore, e->surface, e->hotspot_x, e->hotspot_y);
}

// ── La stessa cosa, detta con l'altro protocollo ─────────────────────────
//
// `cursor-shape-v1` è il modo moderno di chiedere un cursore: invece di
// mandarci un'immagine, il programma dice il NOME della forma («default»,
// «text», «pointer», «col-resize») e la disegna il compositore, col tema di
// chi usa il computer. Chrome e Alacritty lo usano quando c'è.
//
// E c'era: il protocollo lo annunciavamo (`wlr_cursor_shape_manager_v1_create`
// più sotto) e poi **non lo ascoltava nessuno**. Annunciare e non rispondere è
// peggio che non annunciare: il programma crede di aver chiesto e non chiede
// più in altro modo.
//
// ── Il sintomo, che sembrava tutt'altro ──────────────────────────────────
//
// Giacomo, 5 settembre 2026: «il puntatore quando sono su youtube non posso
// vederlo se passo su un video, e anche su altre finestre come questo
// terminale».
//
// Nasconderlo e rimetterlo sono due strade diverse: si nasconde con
// `wl_pointer.set_cursor` e una superficie vuota — e quella la ascoltavamo —
// e si rimette con `set_shape`, che invece buttavamo via. Quindi YouTube
// nascondeva il puntatore sopra il video, e non lo rimetteva più nessuno.
// Sul terminale è lo stesso: Alacritty lo nasconde mentre si scrive.
//
// È anche il motivo per cui il puntatore restava una freccia sopra un campo
// di testo: la barretta la chiedono di qui.
static void forma_cursore(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, forma_richiesta);
	struct wlr_cursor_shape_manager_v1_request_set_shape_event *e = dati;

	// Solo il puntatore: le tavolette grafiche hanno un cursore loro, e non
	// le gestiamo.
	if (e->device_type != WLR_CURSOR_SHAPE_MANAGER_V1_DEVICE_TYPE_POINTER)
		return;

	// La stessa guardia di `cursore_richiesto`: solo chi ha il puntatore
	// adesso può decidere che aspetto abbia.
	if (e->seat_client != m->seat->pointer_state.focused_client)
		return;

	const char *nome = wlr_cursor_shape_v1_name(e->shape);
	if (nome == NULL)
		nome = "default";
	// Con `MINERVA_TRACCIA_FORMA=1` si vede chi chiede cosa. Serve alla
	// prova annidata — che altrimenti non avrebbe modo di sapere se la
	// richiesta e' arrivata — e a capire, la prossima volta che un
	// programma si comporta in modo strano col puntatore, se sta chiedendo
	// e noi non rispondiamo o se non chiede affatto.
	if (m->traccia_forma)
		fprintf(stderr, "minerva-wayland: forma richiesta: %s\n", nome);
	wlr_cursor_set_xcursor(m->cursore, m->cursore_tema, nome);
}

// ── Gli appunti ──────────────────────────────────────────────────────────
//
// In Wayland la copia non è una scatola dove si mette la roba: è un cliente
// che dice «ce l'ho io, chiedimela quando serve». Il compositore fa da
// registro — segna CHI ce l'ha — e questa è la riga che lo segna. Senza,
// «copia» funziona dalla parte di chi copia e non esiste per chi incolla.
//
// Il `serial` non si inventa: è il numero dell'evento di ingresso che ha
// autorizzato la copia, e wlroots lo verifica. È quello che impedisce a un
// programma in secondo piano di prendersi gli appunti mentre lavori altrove.
static void selezione_richiesta(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, selezione_richiesta);
	struct wlr_seat_request_set_selection_event *e = dati;
	wlr_seat_set_selection(m->seat, e->source, e->serial);
}

// ── E la selezione primaria, che è l'altro paio di appunti ───────────────
//
// Quella che si riempie SELEZIONANDO del testo, senza copiare, e si incolla
// col tasto centrale. È una tradizione di X che Wayland ha ripreso, e chi la
// usa la usa continuamente: mancava per lo stesso motivo e con lo stesso
// silenzio.
static void selezione_primaria_richiesta(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, selezione_primaria_richiesta);
	struct wlr_seat_request_set_primary_selection_event *e = dati;
	wlr_seat_set_primary_selection(m->seat, e->source, e->serial);
}

// ── Trascinare qualcosa da una finestra a un'altra ───────────────────────
//
// Un file dal gestore file dentro una chat, un'immagine dentro un editor. È
// lo stesso meccanismo degli appunti — un cliente offre, un altro accetta —
// con in più un'icona che segue il dito.
//
// Il `serial` si verifica invece di fidarsi: senza, un programma potrebbe
// avviare un trascinamento senza che nessuno abbia premuto niente, e il
// puntatore resterebbe prigioniero di una presa che l'utente non ha
// cominciato. Se non è valido la sorgente si distrugge: rifiutare e basta
// lascerebbe il cliente ad aspettare per sempre.
static void trascinamento_richiesto(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, trascinamento_richiesto);
	struct wlr_seat_request_start_drag_event *e = dati;

	const bool buono = wlr_seat_validate_pointer_grab_serial(m->seat,
		e->origin, e->serial);
	if (m->traccia_trascina)
		fprintf(stderr, "minerva-wayland: trascinamento chiesto, serie %s\n",
			buono ? "valida" : "RIFIUTATA");
	if (buono) {
		wlr_seat_start_pointer_drag(m->seat, e->drag, e->serial);
		return;
	}
	wlr_data_source_destroy(e->drag->source);
}

/// Il trascinamento è finito: l'icona se n'è andata con lui.
static void icona_trascinata_distrutta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct minerva *m = wl_container_of(l, m, trascinamento_finito);
	m->icona_trascinata = NULL;
	wl_list_remove(&m->trascinamento_finito.link);
}

// ── L'icona che segue il dito ────────────────────────────────────────────
//
// `wlr_scene_drag_icon_create` disegna la superficie che il cliente offre;
// spostarla sotto il puntatore tocca a noi, a ogni movimento — vedi
// `cursore_aggiorna`. Senza quello l'icona resta inchiodata in alto a
// sinistra: si vede che qualcosa sta succedendo, e non si vede dove.
static void trascinamento_partito(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, trascinamento_partito);
	struct wlr_drag *d = dati;
	if (m->traccia_trascina)
		fprintf(stderr, "minerva-wayland: trascinamento partito, %s\n",
			d->icon != NULL ? "con l'icona" : "SENZA icona");
	if (d->icon == NULL)
		return;
	m->icona_trascinata =
		wlr_scene_drag_icon_create(m->piano_trascinamento, d->icon);
	if (m->icona_trascinata == NULL)
		return;
	m->trascinamento_finito.notify = icona_trascinata_distrutta;
	wl_signal_add(&d->icon->events.destroy, &m->trascinamento_finito);
}

static void cursore_frame(struct wl_listener *l, void *dati) {
	(void)dati;
	struct minerva *m = wl_container_of(l, m, cursore_frame);
	// Chiude il gruppo di eventi del puntatore. Dimenticarlo non dà errore:
	// dà clienti che reagiscono con un evento di ritardo, e si dà la colpa
	// alla loro lentezza.
	wlr_seat_pointer_notify_frame(m->seat);
}

// ── Il programma ──────────────────────────────────────────────────────────

// ══════════════════════════════════════════════════════════════════════════
// Il canale di controllo: i verbi
// ══════════════════════════════════════════════════════════════════════════
//
// Qui c'è la POLITICA — cosa vuol dire «ingrandisci», chi può avere il fuoco —
// mentre `canale.c` fa solo il trasporto. È la stessa divisione che la shell si
// è data fra `core/Compositore.qml` (traduce) e `core/Windows.qml` (decide), e
// serve alla stessa cosa: cambiare il trasporto senza toccare il significato.
//
// ── L'indirizzo di una finestra ───────────────────────────────────────────
//
// È il puntatore in esadecimale, come in Hyprland (`0x55f1c0…`). Non per
// imitazione: `core/Compositore.qml` lo tratta già così — `_selettore()`
// accetta `0x55…` e `address:0x55…` — e tenere lo stesso formato vuol dire che
// quel file cambia in un punto solo, `_dispatch`, invece che in quaranta.
//
// Un puntatore riciclato potrebbe far combaciare l'indirizzo di una finestra
// morta con quello di una viva. Non è un buco di sicurezza — chi parla su
// questo socket ha già la sessione — ma è un modo di chiudere la finestra
// sbagliata, e per questo si cerca sempre nell'elenco vivo invece di
// dereferenziare il numero ricevuto. **Non si scrive mai su un puntatore che
// arriva da fuori.**

static struct finestra *finestra_da_indirizzo(struct minerva *m,
                                              const char *testo) {
	if (testo == NULL || testo[0] == '\0')
		return NULL;

	// ── `pid:1234` ───────────────────────────────────────────────────────
	//
	// La shell lo usa per una cosa sola e importante: dare il fuoco a una
	// finestra PROPRIA appena aperta, quando ancora non ne conosce
	// l'indirizzo (`Compositore.fuocoAlNostroProcesso`). Senza, una finestra
	// di Minerva tenuta pronta si apre e resta dietro.
	//
	// Si prende la PIÙ IN ALTO fra quelle di quel processo, che è la stessa
	// convenzione di Hyprland. E c'è un motivo per cui non può essere più
	// precisa di così: cinque programmi di Minerva vivono in un processo
	// solo, quindi un pid può nominarne cinque. Quando la differenza conta,
	// chi chiama manda il titolo o l'indirizzo — vedi `ui/WindowTitleBar.qml`,
	// dove questo stesso equivoco ha già ridotto a icona la finestra
	// sbagliata.
	if (strncmp(testo, "pid:", 4) == 0) {
		pid_t voluto = (pid_t)atoi(testo + 4);
		if (voluto <= 0)
			return NULL;
		struct finestra *g;
		wl_list_for_each(g, &m->finestre_elenco, link) {
			if (finestra_pid(g) == voluto)
				return g;
		}
		return NULL;
	}

	// `address:0x…` oltre a `0x…`: la shell manda già tutte e due le forme.
	const char *p = strncmp(testo, "address:", 8) == 0 ? testo + 8 : testo;

	unsigned long long numero = strtoull(p, NULL, 0);
	if (numero == 0)
		return NULL;

	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if ((unsigned long long)(uintptr_t)f == numero)
			return f;
	}
	return NULL;
}

// La finestra che ha il fuoco adesso, o NULL.
static struct finestra *finestra_attiva(struct minerva *m) {
	struct wlr_surface *s = m->seat->keyboard_state.focused_surface;
	if (s == NULL)
		return NULL;
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (finestra_superficie(f) == s)
			return f;
	}
	return NULL;
}

// Un testo dentro una stringa JSON. Le virgolette e le barre rovesciate si
// scappano, e i caratteri di controllo si buttano: un titolo di finestra viene
// da un programma qualunque, e un a capo dentro il JSON darebbe a chi legge un
// oggetto spezzato in due.
//
// ── E se non ci sta, si taglia fra un carattere e l'altro ────────────────
//
// Questo ciclo scrive un BYTE per giro, e la fermata era «se non restano tre
// posti, basta». Con un titolo più lungo del buffer si fermava a metà di una
// lettera accentata — «è» sono due byte, un'emoji quattro — e sul canale
// usciva UTF-8 non valido.
//
// Dall'altra parte il demone legge con `.transform(utf8.decoder)`, che su un
// byte malformato LANCIA: l'errore arriva a `onError`, che butta giù
// l'abbonamento agli annunci e riconnette. Non muore niente, e non si vede
// niente — la scrivania perde per un istante le notizie sulle finestre, e
// nessuno sa perché. Un titolo da 509 byte non è teoria: è un percorso lungo
// nel titolo di un editor, o una scheda di browser.
//
// I byte di continuazione di UTF-8 cominciano tutti per `10`: si arretra
// finché non se ne trova uno che non è di continuazione, e si taglia lì.
static void json_stringa(char *fuori, size_t n, const char *dentro) {
	size_t o = 0;
	if (n == 0)
		return;
	for (const char *p = dentro != NULL ? dentro : ""; *p != '\0'; p++) {
		unsigned char c = (unsigned char)*p;
		if (o + 3 >= n) {
			// Non ci sta più: si torna indietro fino all'inizio
			// dell'ultimo carattere cominciato, e lo si butta intero.
			while (o > 0 && (((unsigned char)fuori[o - 1]) & 0xC0) == 0x80)
				o--;
			if (o > 0 && (((unsigned char)fuori[o - 1]) & 0x80) != 0)
				o--;
			break;
		}
		if (c == '"' || c == '\\') {
			fuori[o++] = '\\';
			fuori[o++] = (char)c;
		} else if (c < 0x20) {
			fuori[o++] = ' ';
		} else {
			fuori[o++] = (char)c;
		}
	}
	fuori[o] = '\0';
}

/// Il numero di processo che ha aperto questa finestra, o zero.
///
/// Serve alla shell per una cosa che senza non si può fare: riconoscere le
/// PROPRIE finestre. Una finestra di Minerva deve sapere che è sua — per non
/// disegnarsi sopra una seconda barra del titolo, per non finire nella dock
/// come se fosse un programma qualunque. L'indirizzo non basta: la shell il
/// proprio indirizzo non lo conosce, il proprio pid sì.
static pid_t finestra_pid(struct finestra *f) {
	pid_t pid = 0;
	// ── E per X11 è l'unica strada possibile ─────────────────────────────
	//
	// Una finestra X11 il pid lo dichiara da sé, con `_NET_WM_PID`. Non è
	// una comodità: chiederlo per la strada di Wayland darebbe LO STESSO
	// numero a tutti i programmi X11 insieme, perché dal lato Wayland il
	// client è uno solo — Xwayland. Steam, il suo negozio e ogni gioco
	// avrebbero un pid identico, e la shell non saprebbe più distinguerli.
	//
	// Zero se il programma non lo dichiara, e capita: è lecito.
	if (f->razza == FINESTRA_X11)
		return f->xsup->pid;

	struct wl_resource *r = f->toplevel->resource;
	if (r == NULL)
		return 0;
	struct wl_client *c = wl_resource_get_client(r);
	if (c == NULL)
		return 0;
	wl_client_get_credentials(c, &pid, NULL, NULL);
	return pid;
}

// ── Una finestra in JSON, scritta in un posto solo ────────────────────────
//
// La usano l'elenco (`finestre`) E gli annunci (`evento`). Erano due
// costruzioni separate nella prima stesura, e sarebbero divergute: si aggiunge
// un campo all'elenco, l'annuncio non ce l'ha, e chi legge vede una finestra
// che cambia forma a seconda di come l'ha saputa.
//
// `posto` è quanto è avanti nella pila: 0 la finestra attiva, 1 quella prima,
// e così via. È esattamente ciò che in Hyprland si chiama `focusHistoryID`, ed
// è l'unico modo di sapere chi copre chi — con la differenza che qui non è una
// deduzione: l'elenco È l'ordine di sovrapposizione, e lo tiene
// `fuoco_finestra()`.
static int finestra_json(struct finestra *f, int posto, char *fuori, size_t n) {
	struct wlr_box b;
	finestra_box(f, &b);

	char titolo[512];
	char classe[256];
	json_stringa(titolo, sizeof(titolo), finestra_titolo(f));
	json_stringa(classe, sizeof(classe), finestra_classe(f));

	return snprintf(fuori, n,
		"{\"id\":\"0x%llx\",\"pid\":%d,\"titolo\":\"%s\",\"classe\":\"%s\","
		"\"x\":%d,\"y\":%d,\"larghezza\":%d,\"altezza\":%d,"
		"\"ingrandita\":%s,\"ridotta\":%s,\"schermoIntero\":%s,"
		"\"scrivania\":%d,\"posto\":%d,\"decorata\":%s}",
		(unsigned long long)(uintptr_t)f, (int)finestra_pid(f), titolo, classe,
		b.x, b.y, b.width, b.height,
		f->ingrandita ? "true" : "false",
		f->ridotta ? "true" : "false",
		f->schermo_intero ? "true" : "false",
		f->scrivania, posto, f->decorata ? "true" : "false");
}

static void comando_finestre(struct minerva *m, char *risposta, size_t n) {
	size_t o = (size_t)snprintf(risposta, n, "ok [");
	bool prima = true;
	int posto = 0;

	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		if (!f->comparsa)
			continue;
		size_t spazio = n > o ? n - o : 0;
		if (!prima && spazio > 1) {
			risposta[o++] = ',';
			risposta[o] = '\0';
			spazio--;
		}
		int scritti = finestra_json(f, posto, risposta + o, spazio);
		if (scritti < 0 || (size_t)scritti >= spazio) {
			// Non ci sta: si chiude l'elenco a quello che c'è invece di
			// consegnare un JSON troncato, che chi legge non può distinguere
			// da uno completo. La virgola appena messa se ne va con lui.
			risposta[o] = '\0';
			if (o > 0 && risposta[o - 1] == ',')
				risposta[--o] = '\0';
			break;
		}
		o += (size_t)scritti;
		posto++;
		prima = false;
	}
	snprintf(risposta + o, n > o ? n - o : 0, "]");
}

// ── Gli annunci ───────────────────────────────────────────────────────────
//
// Un annuncio è una riga sola:
//
//     evento aperta {"id":"0x55f1c0","pid":4211,"titolo":"Konsole",…}
//     evento chiusa {"id":"0x55f1c0",…}
//     evento fuoco  {"id":"0x55f1c0",…}
//
// ── Perché il carico è JSON e non campi separati da virgole ──────────────
//
// Perché Hyprland fa così e ci è costato un difetto vero. `activewindow`
// manda `CLASSE,TITOLO` e `activewindowv2` manda `INDIRIZZO`: il demone
// leggeva il secondo come se fosse il primo, e il ramo «due campi» non
// scattava mai perché un indirizzo non ha virgole. Un titolo di finestra
// invece le virgole ce le ha quasi sempre.
//
// Un oggetto JSON non ha questo problema, e ha il vantaggio che conta: è LO
// STESSO oggetto che torna l'elenco, quindi chi legge scrive una lettura sola.
static void annuncia(struct minerva *m, const char *che, struct finestra *f) {
	if (m->canale == NULL)
		return;
	// Di una finestra che non è mai comparsa non si annuncia niente — nemmeno
	// la sua chiusura. Un «chiusa» senza un «aperta» prima obbliga chi
	// ascolta a cercare nel proprio elenco qualcosa che non c'è.
	if (!f->comparsa)
		return;

	char riga[1200];
	int testa = snprintf(riga, sizeof(riga), "evento %s ", che);
	if (testa < 0 || (size_t)testa >= sizeof(riga))
		return;

	// Il posto nella pila si conta adesso: un annuncio senza è mezzo annuncio,
	// e chi legge dovrebbe richiedere l'elenco solo per sapere chi è davanti.
	int posto = 0;
	struct finestra *g;
	wl_list_for_each(g, &m->finestre_elenco, link) {
		if (g == f)
			break;
		if (g->comparsa)
			posto++;
	}

	int coda = finestra_json(f, posto, riga + testa, sizeof(riga) - (size_t)testa);
	if (coda < 0 || (size_t)coda >= sizeof(riga) - (size_t)testa)
		return;
	canale_annuncia(m->canale, che, riga);
}

/// Gli schermi sono cambiati: uno acceso, uno spento, o una risoluzione
/// diversa. Non porta un carico — chi ascolta richiede `schermi`, che è una
/// domanda che si fa una volta ogni tanto e non sessanta volte al secondo.
static void annuncia_schermi(struct minerva *m) {
	if (m->canale == NULL)
		return;
	canale_annuncia(m->canale, "schermi", "evento schermi {}");
}

/// Lo schermo si è bloccato, o si è sbloccato.
///
/// Serve alla shell per non fare cose inutili mentre nessuno guarda: fermare
/// gli orologi, smettere di chiedere il meteo, spegnere le animazioni. E serve
/// a saperlo *senza* essere il programma del blocco — che è un processo a sé.
static void annuncia_blocco(struct minerva *m) {
	if (m->canale == NULL)
		return;
	char riga[64];
	snprintf(riga, sizeof(riga), "evento blocco {\"bloccato\":%s}",
		m->bloccato ? "true" : "false");
	canale_annuncia(m->canale, "blocco", riga);
}

/// Una scorciatoia che tocca alla shell.
///
/// Le ventisei `minerva:` — il promemoria, le impostazioni, il lanciatore — il
/// compositore non sa cosa siano, e non deve: le annuncia con lo stesso nome
/// che hanno nella sorgente, e chi disegna la scrivania fa il resto. È lo
/// stesso confine che sotto Hyprland passa per `GlobalShortcut`.
static void annuncia_scorciatoia(struct minerva *m,
                                 const struct scorciatoia *s) {
	annuncia_scorciatoia_con(m, s->argomento);
}

static void annuncia_scorciatoia_con(struct minerva *m, const char *argomento) {
	if (m->canale == NULL)
		return;
	char nome[256];
	json_stringa(nome, sizeof(nome), argomento);
	char riga[320];
	snprintf(riga, sizeof(riga), "evento scorciatoia {\"azione\":\"%s\"}",
		nome);
	canale_annuncia(m->canale, "scorciatoia", riga);
}

/// Si è cambiata scrivania.
///
/// Porta il numero, e non «richiedi l'elenco»: è l'informazione che serve alla
/// barra per accendere il pallino giusto, ed è una sola. Le finestre che si
/// sono nascoste o riviste non si riannunciano una per una — nessuna di loro è
/// cambiata, è cambiato quello che si guarda.
static void annuncia_scrivania(struct minerva *m) {
	if (m->canale == NULL)
		return;
	char riga[64];
	snprintf(riga, sizeof(riga), "evento scrivania {\"attiva\":%d}",
		m->scrivania_attiva);
	canale_annuncia(m->canale, "scrivania", riga);
}

/// Com'è messo il compositore adesso, in una riga.
///
/// Due cose che non si possono dedurre dall'elenco delle finestre:
///
///  · **se lo schermo è bloccato.** La shell deve saperlo senza essere il
///    programma del blocco — che è un processo a sé — per fermare gli
///    orologi, smettere di chiedere il meteo, spegnere le animazioni;
///  · **chi ha la tastiera.** Il posto 0 nell'elenco dice chi è davanti, che
///    è un'altra cosa: da bloccati nessuna finestra ha la tastiera e tutte
///    hanno il loro posto.
static void comando_stato(struct minerva *m, char *risposta, size_t n) {
	struct wlr_surface *sf = m->seat->keyboard_state.focused_surface;
	unsigned long long chi = 0;
	if (sf != NULL) {
		struct finestra *f;
		wl_list_for_each(f, &m->finestre_elenco, link) {
			if (finestra_superficie(f) == sf) {
				chi = (unsigned long long)(uintptr_t)f;
				break;
			}
		}
	}
	// La scrivania in uso sta qui e non solo negli annunci: chi si collega a
	// compositore già avviato — la shell che riparte, il demone che si
	// riprende — ha perso tutti gli annunci di prima, e senza questo campo
	// disegnerebbe il pallino della scrivania 1 fino al primo cambio.
	// ── E quante soglie di inattività ci hanno chiesto ───────────────
	//
	// Perché una sorveglianza che non è stata chiesta è indistinguibile da
	// una che non funziona: lo schermo non si blocca, e non c'è niente da
	// guardare per capire se il problema è la shell che non l'ha chiesta o
	// il compositore che non conta. Un numero qui separa le due cose.
	char code[64];
	if (chi != 0)
		snprintf(code, sizeof(code), "\"fuoco\":\"0x%llx\"", chi);
	else
		snprintf(code, sizeof(code), "\"fuoco\":\"\"");
	// ── E in che modo sta la cornice ─────────────────────────────────
	//
	// Stessa ragione delle soglie: una cornice che il pannello ha acceso e
	// che non si vede può essere il pannello che non l'ha chiesta o il
	// compositore che non la disegna, e da fuori le due cose sono identiche.
	const char *corn = m->cornice_modo == CORNICE_GIRA ? "gira"
		: (m->cornice_modo == CORNICE_STRISCIA ? "striscia"
		: (m->cornice_modo == CORNICE_FISSA ? "fisso" : "spento"));
	// E l'effetto, per la stessa ragione ancora: una finestra che sembra
	// opaca può essere il vetro spento o il vetro acceso al 100%, e da fuori
	// non si distinguono. Senza questo campo la prova dovrebbe confrontare
	// dei pixel — cioè diventare rossa il giorno che cambia lo sfondo.
	const char *eff = m->effetto_modo == EFFETTO_ACQUERELLO ? "acquerello"
		: (m->effetto_modo == EFFETTO_VETRO ? "vetro" : "nessuno");

	// ── E la luce notturna, con la sua STRADA ────────────────────────
	//
	// Non basta dire che tinta abbiamo addosso: una scrivania che non si
	// scalda può essere la tinta spenta o uno schermo che la tabella dei
	// colori non la prende, e da fuori sono identiche. È esattamente il
	// modo in cui la luce notturna è rimasta rotta per due settimane
	// senza che nessuno potesse accorgersene.
	//
	//     "schermo"   la tabella la prende il monitor: si vede
	//     "nessuna"   questo schermo non la prende: NON si vede
	//     "spenta"    non c'è nessuna tinta da applicare
	//
	// Su un backend annidato è sempre «nessuna», e va bene così: la prova
	// legge questo campo e sa se ha senso guardare i pixel.
	// Il risparmio, perché «effetto», «cornice» ed «elastico» qui sopra
	// dicono quello che si DISEGNA: a batteria bassa il blur chiesto è vetro
	// disegnato, e senza questo campo sembrerebbe un effetto che non ha
	// preso.
	char risp[256];
	risparmio_json(m, risp, sizeof(risp));

	// Quanti fotogrammi sono stati davvero mandati agli schermi: dice alle
	// prove se un'animazione si vede passo per passo o salta alla fine.
	unsigned presentati = 0;
	{
		struct schermo *sp;
		wl_list_for_each(sp, &m->schermi_elenco, link)
			presentati += (unsigned)sp->out->commit_seq;
	}
	const char *strada = "spenta";
	if (m->tinta != NULL) {
		strada = "schermo";
		struct schermo *sc;
		wl_list_for_each(sc, &m->schermi_elenco, link) {
			if (sc->tinta_strada == 2)
				strada = "nessuna";
		}
	}
	snprintf(risposta, n,
		"ok {\"bloccato\":%s,%s,\"scrivania\":%d,\"inattivita\":%d,"
		"\"cornice\":\"%s\",\"cornicePeriodo\":%d,"
		"\"corniceSpessore\":%d,\"corniceTinte\":%d,"
		"\"corniceSpente\":%.2f,"
		"\"effetto\":\"%s\",\"effettoAlfa\":%.2f,"
		"\"elastico\":%.2f,\"rigidita\":%.2f,\"smorzamento\":%.2f,"
		"\"tinta\":\"%.4f %.4f %.4f\",\"tintaStrada\":\"%s\","
		"\"respiro\":%s,\"respiri\":%d,\"respiroPassi\":%u,\"copie\":%u,"
		"\"presentati\":%u,\"mercurio\":%s,\"ponti\":%d,\"fantasmi\":%d,"
		"\"risparmio\":%s}",
		m->bloccato ? "true" : "false", code, m->scrivania_attiva,
		m->inattivo_quante, corn, m->cornice_periodo, m->cornice_spessore,
		m->cornice_quante_tinte, m->cornice_spente,
		eff, (double)m->effetto_alfa, m->elastico, m->rigidita, m->smorzamento,
		m->tinta_rgb[0], m->tinta_rgb[1], m->tinta_rgb[2], strada,
		m->respiro_acceso ? "true" : "false", m->respiri_attivi, m->respiro_passi,
		m->molle_attive, presentati,
		m->mercurio_acceso ? "true" : "false", m->ponti, m->fantasmi_vivi,
		risp);
}

/// Quali scrivanie esistono adesso.
///
/// Esiste una scrivania che ha almeno una finestra, più quella in uso — che
/// esiste anche vuota, perché ci si sta guardando dentro. È la stessa regola
/// di Hyprland, e non per imitazione: una scrivania vuota che non si guarda
/// non è una cosa, è un numero che non è stato ancora usato.
///
/// Le dieci ci sono sempre e comunque; questo elenco dice **quali contano**, e
/// serve alla barra per accendere il pallino pieno invece di quello vuoto.
static void comando_scrivanie(struct minerva *m, char *risposta, size_t n) {
	size_t o = (size_t)snprintf(risposta, n, "ok [");
	bool prima = true;
	for (int i = 1; i <= SCRIVANIE; i++) {
		int quante = scrivania_quante(m, i);
		if (quante == 0 && i != m->scrivania_attiva)
			continue;
		size_t spazio = n > o ? n - o : 0;
		int scritti = snprintf(risposta + o, spazio,
			"%s{\"id\":%d,\"nome\":\"%d\",\"finestre\":%d,\"attiva\":%s}",
			prima ? "" : ",", i, i, quante,
			i == m->scrivania_attiva ? "true" : "false");
		if (scritti < 0 || (size_t)scritti >= spazio)
			break;
		o += (size_t)scritti;
		prima = false;
	}
	if (o + 2 < n)
		snprintf(risposta + o, n - o, "]");
}

/// Da come wlroots chiama una rotazione ai gradi che dice Minerva.
///
/// Le trasformazioni da 4 in su sono le versioni SPECCHIATE, e non sono una
/// rotazione: darebbero 360 gradi e oltre. Si dice zero — «dritto» — perché
/// un numero senza senso in una casella di rotazione è peggio di un valore
/// che non si sa dire.
static int gradi_di(enum wl_output_transform t) {
	switch (t) {
	case WL_OUTPUT_TRANSFORM_90:  return 90;
	case WL_OUTPUT_TRANSFORM_180: return 180;
	case WL_OUTPUT_TRANSFORM_270: return 270;
	default:                      return 0;
	}
}

static void comando_schermi(struct minerva *m, char *risposta, size_t n) {
	size_t o = (size_t)snprintf(risposta, n, "ok [");
	bool prima = true;
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link) {
		char nome[128];
		json_stringa(nome, sizeof(nome), s->out->name);
		struct wlr_box b;
		wlr_output_layout_get_box(m->schermi, s->out, &b);
		// ── Si manda lo spazio UTILE, non le zone riservate ──────────
		//
		// Hyprland manda `reserved: [sinistra, alto, destra, basso]` e chi
		// legge deve sottrarlo da sé — un conto in quattro pezzi, rifatto
		// in ogni consumatore, con la scala di mezzo. Qui il rettangolo
		// utile il compositore ce l'ha già calcolato (`s->utile`, che è
		// quello con cui decide dove nasce una finestra): mandare il
		// risultato invece degli ingredienti toglie a chi legge un conto
		// che può sbagliare.
		//
		// E sono PIXEL LOGICI, già divisi per la scala: `wlr_output_layout`
		// ragiona in logici. In Hyprland `width`/`height` sono fisici e vanno
		// divisi, ed è una delle ragioni per cui la traduzione dei due
		// formati sta nella porta della shell e non qui.
		bool attivo = wlr_output_layout_output_at(m->schermi,
			m->cursore->x, m->cursore->y) == s->out;

		// ── I modi, e perché li deve mandare il compositore ───────────
		//
		// Perché è l'unico che sa davvero che cosa quel monitor regge. Un
		// elenco di risoluzioni scritto a mano prima o poi ne propone una
		// che lo schermo non accetta, e chi la sceglie resta al buio — e
		// per correggerla servirebbe lo schermo.
		//
		// Si mandano dalla più grande, che è l'ordine in cui li vuole
		// mostrare la pagina Schermi.
		char modi[2048];
		size_t mo = 0;
		modi[0] = '\0';
		bool primo_modo = true;
		struct wlr_output_mode *modo;
		wl_list_for_each(modo, &s->out->modes, link) {
			int q = snprintf(modi + mo, sizeof(modi) - mo, "%s\"%dx%d@%.3f\"",
				primo_modo ? "" : ",", modo->width, modo->height,
				modo->refresh / 1000.0);
			if (q < 0 || (size_t)q >= sizeof(modi) - mo)
				break;
			mo += (size_t)q;
			primo_modo = false;
		}

		// La descrizione è quella che il monitor dichiara di sé — marca e
		// modello — ed è l'unica cosa che distingue due schermi uguali
		// quando `DP-1` e `DP-2` non dicono niente a nessuno.
		char descr[256];
		json_stringa(descr, sizeof(descr),
			s->out->description != NULL ? s->out->description : "");

		int scritti = snprintf(risposta + o, n > o ? n - o : 0,
			"%s{\"nome\":\"%s\",\"descrizione\":\"%s\","
			"\"larghezza\":%d,\"altezza\":%d,"
			"\"modoLarghezza\":%d,\"modoAltezza\":%d,"
			"\"x\":%d,\"y\":%d,\"scala\":%.4f,\"hz\":%.3f,"
			"\"rotazione\":%d,\"acceso\":%s,"
			"\"attivo\":%s,\"utileX\":%d,\"utileY\":%d,"
			"\"utileLarghezza\":%d,\"utileAltezza\":%d,\"modi\":[%s]}",
			prima ? "" : ",", nome, descr, b.width, b.height,
			s->out->width, s->out->height, b.x, b.y,
			(double)s->out->scale,
			s->out->refresh / 1000.0,
			gradi_di(s->out->transform),
			s->out->enabled ? "true" : "false",
			attivo ? "true" : "false",
			s->utile.x, s->utile.y, s->utile.width, s->utile.height, modi);
		if (scritti < 0 || (size_t)scritti >= (n > o ? n - o : 0))
			break;
		o += (size_t)scritti;
		prima = false;
	}
	snprintf(risposta + o, n > o ? n - o : 0, "]");
}

// ── Un intero, davvero ────────────────────────────────────────────────────
//
// `atoi` risponde zero a «pippo» esattamente come a «0», e non c'è modo di
// distinguere i due casi. Dove lo zero non è un valore buono non fa danni — le
// scrivanie vanno da 1, quindi «scrivania pippo» cade già nel controllo e
// risponde `no`. Dove invece lo zero È buono, cioè in una POSIZIONE, quella
// risposta diventa un comando eseguito al posto di un errore: `sposta <f>
// pippo pluto` porta la finestra nell'angolo in alto a sinistra e dice «ok».
//
// Fatto il conto l'8 settembre 2026: quindici `atoi` in tutto, e solo quattro
// scoperti — i due della posizione di uno schermo e i due di «sposta». Gli
// altri undici sono già dietro un controllo che rifiuta lo zero.
static bool numero(const char *s, int *fuori) {
	if (s == NULL || *s == '\0')
		return false;
	errno = 0;
	char *fine = NULL;
	const long v = strtol(s, &fine, 10);
	// `fine == s` vuol dire che non ha letto nemmeno una cifra; `*fine` vuol
	// dire che dopo il numero c'era altro — «12pippo» non è dodici.
	if (errno != 0 || fine == s || *fine != '\0')
		return false;
	if (v < INT_MIN || v > INT_MAX)
		return false;
	*fuori = (int)v;
	return true;
}

// Una parola per volta dalla riga di comando.
static char *parola(char **resto) {
	char *p = *resto;
	while (*p == ' ' || *p == '\t')
		p++;
	if (*p == '\0') {
		*resto = p;
		return NULL;
	}
	char *inizio = p;
	while (*p != '\0' && *p != ' ' && *p != '\t')
		p++;
	if (*p != '\0')
		*p++ = '\0';
	*resto = p;
	return inizio;
}

// ── Cambiare uno schermo, adesso ─────────────────────────────────────────
//
//     schermo eDP-1 1920x1080@60 1.25 0 0 0
//     schermo eDP-1 preferito 1
//     schermo HDMI-A-1 spento
//
// Grammatica: `schermo <nome> <modo|preferito|spento> [scala] [rotazione]
// [x] [y]`. La rotazione è in GRADI — 0, 90, 180, 270 — come in
// `schermi.conf`, non nei numeri da 0 a 7 di Wayland: chi scrive «ruota di
// 90» non deve sapere che internamente si chiama `transform 1`.
//
// ── Perché questo verbo esiste ───────────────────────────────────────────
//
// Perché la pagina Schermi delle Impostazioni scriveva il file e basta: il
// compositore lo legge una volta sola, all'avvio. La risoluzione cambiava
// **al riavvio della sessione**, che non è quello che chiede chi sta
// guardando uno schermo storto. Sotto Hyprland la stessa pagina applica
// subito, con `hyprctl keyword monitor`; qui non arrivava a nessuno.
//
// ── E il rifiuto che conta ───────────────────────────────────────────────
//
// Non si spegne l'ultimo schermo acceso. È la stessa regola della schermata
// di accesso e del ripiego sicuro qui sopra: niente di quello che aggiungiamo
// può diventare un modo di restare al buio senza uno schermo per rimediare.
static struct schermo *schermo_da_nome(struct minerva *m, const char *nome) {
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link) {
		if (s->out->name != NULL && strcmp(s->out->name, nome) == 0)
			return s;
	}
	return NULL;
}

static int schermi_accesi(struct minerva *m) {
	int quanti = 0;
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link) {
		if (s->out->enabled)
			quanti++;
	}
	return quanti;
}

// Il nome qui si legge con `parola()`, e va bene — a differenza di
// `comando_dispositivo`, che per la stessa scelta non funzionava. La
// differenza non è di stile: un nome di schermo è un connettore DRM, e i
// connettori si chiamano `eDP-1`, `HDMI-A-1`, `DP-3`. **Non hanno spazi, per
// come sono fatti**, mentre i nomi di libinput ce li hanno quasi sempre.
// Scritto qui perché la prossima persona che confronta i due verbi non debba
// rifare il ragionamento, o peggio «uniformarli» spostando un difetto.
static void schermo_fine_prova(struct schermo *s) {
	if (!s->prova_timer) return;
	wl_event_source_remove(s->prova_timer);
	s->prova_timer = NULL;
	wlr_output_state_finish(&s->prima_prova);
	s->prova_id[0] = '\0';
}

static int schermo_ripristina(void *data) {
	struct schermo *s = data;
	if (!wlr_output_commit_state(s->out, &s->prima_prova)) {
		wlr_log(WLR_ERROR, "minerva: ripristino schermo %s fallito, riprovo", s->out->name);
		wl_event_source_timer_update(s->prova_timer, 1000);
		return 0;
	}
	if (s->out->enabled)
		wlr_output_layout_add(s->m->schermi, s->out, s->prima_posizione.x, s->prima_posizione.y);
	else
		wlr_output_layout_remove(s->m->schermi, s->out);
	struct schermo *g;
	wl_list_for_each(g, &s->m->schermi_elenco, link) {
		wlr_output_layout_get_box(s->m->schermi, g->out, &g->utile);
		disponi(s->m, g->out);
	}
	schermo_fine_prova(s);
	annuncia_schermi(s->m);
	return 0;
}

// Configurazione multipla: snapshot unico, commit backend e rollback a timer.
struct monitor_transaction {
    struct minerva *m;
    struct wlr_backend_output_state *before;
    struct wlr_box *positions;
    size_t count;
    struct wl_event_source *timer;
    char id[64];
};

static void monitor_transaction_free(struct minerva *m) {
    struct monitor_transaction *t = m->monitor_transaction;
    if (!t) return;
    if (t->timer) wl_event_source_remove(t->timer);
    for (size_t i = 0; i < t->count; i++) wlr_output_state_finish(&t->before[i].base);
    free(t->before); free(t->positions); free(t);
    m->monitor_transaction = NULL;
}

static void monitor_layout_refresh(struct minerva *m) {
    struct schermo *s;
    struct wlr_output *fallback = NULL;
    wl_list_for_each(s, &m->schermi_elenco, link) {
        if (!s->out->enabled) {
            wlr_output_layout_remove(m->schermi, s->out);
            continue;
        }
        if (!fallback) fallback = s->out;
        struct wlr_box position;
        wlr_output_layout_get_box(m->schermi, s->out, &position);
        struct schermo_voluto v = {.acceso = true, .posizione_detta = true,
            .x = position.x, .y = position.y};
        schermo_nel_disegno(m, s->out, &v);
        wlr_output_layout_get_box(m->schermi, s->out, &s->utile);
        disponi(m, s->out);
    }
    if (fallback) {
        struct wlr_box box;
        wlr_output_layout_get_box(m->schermi, fallback, &box);
        struct finestra *f;
        wl_list_for_each(f, &m->finestre_elenco, link) {
            if (!f->mappata_ora) continue;
            int w, h;
            finestra_geometria(f, &w, &h);
            if (!wlr_output_layout_output_at(m->schermi, f->posto_x + w / 2, f->posto_y + h / 2))
                finestra_posiziona(f, box.x, box.y, w, h);
        }
        if (!wlr_output_layout_output_at(m->schermi, m->cursore->x, m->cursore->y))
            wlr_cursor_warp_closest(m->cursore, NULL, box.x + box.width / 2, box.y + box.height / 2);
    }
    annuncia_schermi(m);
}

static void monitor_recover(void *data) {
    struct minerva *m = data;
    if (!m->canale) return;
    if (!schermi_accesi(m)) {
        struct schermo *s;
        // Preferire il pannello interno, altrimenti qualsiasi output rimasto.
        for (int pass = 0; pass < 2 && !schermi_accesi(m); pass++) {
            wl_list_for_each(s, &m->schermi_elenco, link) {
                const char *name = s->out->name ? s->out->name : "";
                if (!pass && strncmp(name, "eDP", 3) && strncmp(name, "LVDS", 4)) continue;
                if (schermo_configura(s->out, NULL)) break;
            }
        }
    }
    monitor_layout_refresh(m);
}

static int monitor_transaction_restore(void *data) {
    struct minerva *m = data;
    struct monitor_transaction *t = m->monitor_transaction;
    if (!t) return 0;
    // Output eventualmente scollegati sono rimossi dallo snapshot prima del destroy.
    bool ok = wlr_backend_commit(m->backend, t->before, t->count);
    for (size_t i = 0; i < t->count; i++) {
        struct wlr_output *out = t->before[i].output;
        if (out->enabled) wlr_output_layout_add(m->schermi, out, t->positions[i].x, t->positions[i].y);
    }
    monitor_layout_refresh(m);
    if (ok) monitor_transaction_free(m);
    else {
        wlr_log(WLR_ERROR, "minerva: ripristino monitor fallito, nuovo tentativo fra un secondo");
        wl_event_source_timer_update(t->timer, 1000);
    }
    return 0;
}

static void monitor_transaction_removed(struct minerva *m, struct wlr_output *out) {
    struct monitor_transaction *t = m->monitor_transaction;
    if (!t) return;
    for (size_t i = 0; i < t->count; i++) {
        if (t->before[i].output != out) continue;
        wlr_output_state_finish(&t->before[i].base);
        memmove(&t->before[i], &t->before[i + 1], (t->count - i - 1) * sizeof(*t->before));
        memmove(&t->positions[i], &t->positions[i + 1], (t->count - i - 1) * sizeof(*t->positions));
        t->count--;
        break;
    }
    if (m->canale) wl_event_source_timer_update(t->timer, 1);
    else monitor_transaction_free(m);
}

// ── I modi con più schermi: estendi, solo uno, duplica ───────────────────
//
// Una configurazione sola per tutti gli schermi, come TRANSAZIONE: si prova,
// si aspettano quindici secondi la conferma, e se non arriva si torna a
// com'era — una scelta sbagliata qui lascia senza schermo proprio chi deve
// annullarla. I tre modi:
//
//     estendi     tutti accesi, in fila da sinistra a destra
//     solo NOME   acceso solo quello, gli altri spenti
//     duplica     tutti accesi nello STESSO punto: la scena è una, e ogni
//                 schermo ne disegna il pezzo che gli sta sopra — cioè lo
//                 stesso. È la duplicazione di Wayland: niente copia, nessun
//                 costo in più. Con risoluzioni diverse si sceglie per ogni
//                 schermo il modo che ha esattamente la misura del più
//                 piccolo, se ce l'ha; altrimenti tiene il suo e il più
//                 grande mostra un bordo vuoto a destra e in basso.
//
// Giacomo, 22 settembre 2026: «sotto i monitor le opzioni duplica, solo
// monitor 1 o 2 o solo pc e estendi». Codex aveva lasciato fuori la
// duplicazione apposta; entra qui con la stessa transazione degli altri due.

/// Il modo di `o` con esattamente `w`×`h`, alla frequenza più alta, o NULL.
static struct wlr_output_mode *modo_con_misura(struct wlr_output *o, int w, int h) {
	struct wlr_output_mode *migliore = NULL, *mode;
	wl_list_for_each(mode, &o->modes, link) {
		if (mode->width != w || mode->height != h) continue;
		if (migliore == NULL || mode->refresh > migliore->refresh) migliore = mode;
	}
	return migliore;
}

static void comando_monitori(struct minerva *m, char *resto, char *reply, size_t len) {
    char *id = parola(&resto), *mode = parola(&resto), *target = parola(&resto);
    bool duplica = mode && strcmp(mode, "duplica") == 0;
    if (!id || strlen(id) >= 64 || !mode || parola(&resto) ||
            (strcmp(mode, "estendi") != 0 && strcmp(mode, "solo") != 0 && !duplica) ||
            (strcmp(mode, "solo") == 0 && (!target || !schermo_da_nome(m, target))) ||
            (strcmp(mode, "solo") != 0 && target)) {
        snprintf(reply, len, "no monitori-prova <id> estendi|duplica|solo [nome]"); return;
    }
    if (m->monitor_transaction) { snprintf(reply, len, "no configurazione monitor in attesa di conferma"); return; }
    size_t count = 0;
    struct schermo *s;
    wl_list_for_each(s, &m->schermi_elenco, link) {
        if (s->prova_timer || wlr_output_is_wl(s->out)) {
            snprintf(reply, len, "no monitor in prova o backend annidato non supportato"); return;
        }
        count++;
    }
    if (!count) { snprintf(reply, len, "no nessun monitor disponibile"); return; }
    struct monitor_transaction *t = calloc(1, sizeof(*t));
    struct wlr_backend_output_state *next = calloc(count, sizeof(*next));
    if (!t || !next) { free(t); free(next); snprintf(reply, len, "no memoria insufficiente"); return; }
    t->before = calloc(count, sizeof(*t->before));
    t->positions = calloc(count, sizeof(*t->positions));
    if (!t->before || !t->positions) {
        free(t->before); free(t->positions); free(t); free(next);
        snprintf(reply, len, "no memoria insufficiente"); return;
    }
    t->m = m; t->count = count;
    snprintf(t->id, sizeof(t->id), "%s", id);
    // Per «duplica»: la misura più piccola fra gli schermi, quella che tutti
    // proveranno a prendere.
    int min_w = 0, min_h = 0;
    if (duplica) {
        wl_list_for_each(s, &m->schermi_elenco, link) {
            struct wlr_output_mode *mode = s->out->current_mode ? s->out->current_mode : wlr_output_preferred_mode(s->out);
            int w = mode ? mode->width : s->out->width, h = mode ? mode->height : s->out->height;
            if (w <= 0 || h <= 0) continue;
            if (min_w == 0 || (long)w * h < (long)min_w * min_h) { min_w = w; min_h = h; }
        }
    }
    size_t i = 0;
    wl_list_for_each(s, &m->schermi_elenco, link) {
        struct wlr_output *o = s->out;
        t->before[i].output = next[i].output = o;
        wlr_output_state_init(&t->before[i].base);
        wlr_output_state_init(&next[i].base);
        wlr_output_state_set_enabled(&t->before[i].base, o->enabled);
        wlr_output_state_set_enabled(&next[i].base, !target || strcmp(target, o->name) == 0);
        // Conservare scala, rotazione e modo anche quando lo schermo era spento.
        for (int k = 0; k < 2; k++) {
            struct wlr_output_state *state = k ? &next[i].base : &t->before[i].base;
            wlr_output_state_set_scale(state, o->scale);
            wlr_output_state_set_transform(state, o->transform);
            struct wlr_output_mode *mode = o->current_mode ? o->current_mode : wlr_output_preferred_mode(o);
            if (k && duplica && min_w > 0) {
                struct wlr_output_mode *pari = modo_con_misura(o, min_w, min_h);
                if (pari) mode = pari;
            }
            if (!state->enabled) continue;
            if (mode) wlr_output_state_set_mode(state, mode);
            else if (o->width > 0 && o->height > 0) wlr_output_state_set_custom_mode(state, o->width, o->height, o->refresh);
        }
        wlr_output_layout_get_box(m->schermi, o, &t->positions[i]);
        i++;
    }
    m->monitor_transaction = t;
    t->timer = wl_event_loop_add_timer(m->loop, monitor_transaction_restore, m);
    bool ok = t->timer && wlr_backend_test(m->backend, next, count);
    if (ok) {
        // Il backend raggruppa le uscite DRM. Un fallimento ripristina lo snapshot.
        wl_event_source_timer_update(t->timer, 15000);
        ok = wlr_backend_commit(m->backend, next, count);
        if (ok) {
            int x = 0;
            for (i = 0; i < count; i++) {
                struct wlr_output *o = next[i].output;
                if (!o->enabled) continue;
                // Duplica: tutti a (0,0), cioè tutti sullo stesso pezzo di scena.
                wlr_output_layout_add(m->schermi, o, duplica ? 0 : x, 0);
                int w, h; wlr_output_effective_resolution(o, &w, &h); x += w;
            }
            monitor_layout_refresh(m);
        } else monitor_transaction_restore(m);
    } else monitor_transaction_free(m);
    for (i = 0; i < count; i++) wlr_output_state_finish(&next[i].base);
    free(next);
    snprintf(reply, len, ok ? "ok" : "no configurazione monitor rifiutata");
}

static void comando_schermo(struct minerva *m, char *resto, const char *prova,
		char *risposta, size_t n) {
	if (m->monitor_transaction) { snprintf(risposta, n, "no configurazione monitor in attesa di conferma"); return; }
	char *nome = parola(&resto);
	char *cosa = parola(&resto);
	if (nome == NULL || cosa == NULL) {
		snprintf(risposta, n, "no schermo vuole un nome e un modo "
			"(o «preferito», o «spento»)");
		return;
	}

	struct schermo *s = schermo_da_nome(m, nome);
	if (s == NULL) {
		snprintf(risposta, n, "no non c'è nessuno schermo che si chiama %s",
			nome);
		return;
	}
	if (s->prova_timer && (!prova || strcmp(prova, s->prova_id) != 0)) {
		snprintf(risposta, n, "no schermo in attesa di conferma");
		return;
	}

	struct schermo_voluto v;
	memset(&v, 0, sizeof(v));
	snprintf(v.nome, sizeof(v.nome), "%s", nome);
	v.rotazione = -1;
	v.acceso = strcmp(cosa, "spento") != 0;

	if (!v.acceso && s->out->enabled && schermi_accesi(m) <= 1) {
		snprintf(risposta, n, "no %s è l'unico schermo acceso: spegnendolo "
			"non resterebbe niente su cui rimediare", nome);
		return;
	}

	// ── E dentro una prova annidata non si spegne per niente ─────────────
	//
	// Misurato il 26 agosto 2026, ed è la ragione per cui questo rifiuto
	// esiste: sotto il backend Wayland — cioè un compositore dentro un altro
	// compositore, che è come si provano tutte le cose qui dentro —
	// **riaccendere uno schermo blocca il processo**. Non fallisce, non dà
	// errore: `wlr_output_commit_state` non torna più, e il compositore
	// resta fermo per sempre. Il motivo è che per riaccendere deve parlare
	// col compositore OSPITE, e quel dialogo aspetta un ciclo di eventi che
	// è proprio quello dentro cui stiamo girando.
	//
	// Uno schermo che si può spegnere e non si può riaccendere non è una
	// funzione a metà: è una trappola. Meglio dirlo prima.
	//
	// Sul vero backend — DRM, cioè lo schermo di questo portatile — non c'è
	// nessun ospite con cui parlare e la cosa funziona: provata sul backend
	// headless, che è l'altro senza ospite, dove spegnere e riaccendere va a
	// buon fine (`prova-schermi-vivi.py`).
	if (!v.acceso && wlr_output_is_wl(s->out)) {
		snprintf(risposta, n, "no dentro una prova annidata uno schermo "
			"spento non si riaccende: wlroots resta ferma nel dialogo col "
			"compositore ospite");
		return;
	}

	if (v.acceso && strcmp(cosa, "preferito") != 0) {
        if (!schermo_modo_parse(&v, cosa)) {
            snprintf(risposta, n, "no non capisco il modo «%s»: usa 1920x1080@59.940", cosa);
            return;
        }
        int w = v.larghezza, h = v.altezza, hz = v.hz;

		// ── Qui si RIFIUTA un modo che il monitor non ha ─────────────────
		//
		// All'avvio no: una riga sbagliata in `schermi.conf` non deve
		// lasciare uno schermo nero, e si ripiega sul modo preferito. Ma
		// qui c'è qualcuno che sta guardando un pannello e ha appena
		// scelto una risoluzione: accettare e metterne un'altra vuol dire
		// una casella che dice 1920×1080 e uno schermo che è a 1280×720.
		//
		// Uno schermo senza nessun modo dichiarato — headless, annidato —
		// non si può controllare, e allora si lascia passare: non si
		// rifiuta per un'informazione che non c'è.
		if (!wl_list_empty(&s->out->modes)) {
			bool c_e = false;
			struct wlr_output_mode *cand;
			wl_list_for_each(cand, &s->out->modes, link) {
				if (cand->width != w || cand->height != h)
					continue;
				if (v.millihz > 0 ? cand->refresh != v.millihz :
                        (hz > 0 && (cand->refresh + 500) / 1000 != hz))
					continue;
				c_e = true;
				break;
			}
			if (!c_e) {
				snprintf(risposta, n, "no lo schermo %s non ha il modo %s",
					nome, cosa);
				return;
			}
		}
	}

	char *sscala = parola(&resto);
	if (sscala != NULL) {
		double sc = atof(sscala);
		// Sotto 0,5 il testo diventa illeggibile, sopra 4 una finestra non
		// ci sta più sullo schermo. Sono i due estremi in cui il pannello
		// per rimediare non è più cliccabile.
		if (!isfinite(sc) || sc < 0.5 || sc > 4.0) {
			snprintf(risposta, n, "no la scala %s è fuori da quello che si "
				"può usare (da 0,5 a 4)", sscala);
			return;
		}
		v.scala = sc;
	}

	char *srot = parola(&resto);
	if (srot != NULL) {
		int g = atoi(srot);
		if (g != 0 && g != 90 && g != 180 && g != 270) {
			snprintf(risposta, n, "no la rotazione è in gradi: 0, 90, 180 "
				"o 270");
			return;
		}
		v.rotazione = g;
	}

	char *sx = parola(&resto);
	char *sy = parola(&resto);
	if (sx != NULL && sy != NULL) {
		if (!numero(sx, &v.x) || !numero(sy, &v.y)) {
			snprintf(risposta, n, "no la posizione di uno schermo sono due "
				"numeri interi, e «%s %s» non lo sono", sx, sy);
			return;
		}
		v.posizione_detta = true;
	}

	if (prova && !s->prova_timer) {
		s->prova_timer = wl_event_loop_add_timer(wl_display_get_event_loop(m->display), schermo_ripristina, s);
		if (!s->prova_timer) { snprintf(risposta, n, "no timer rollback non disponibile"); return; }
		wlr_output_state_init(&s->prima_prova);
		wlr_output_state_set_enabled(&s->prima_prova, s->out->enabled);
		wlr_output_state_set_scale(&s->prima_prova, s->out->scale);
		wlr_output_state_set_transform(&s->prima_prova, s->out->transform);
		if (s->out->current_mode)
			wlr_output_state_set_mode(&s->prima_prova, s->out->current_mode);
		else if (s->out->width > 0 && s->out->height > 0)
			wlr_output_state_set_custom_mode(&s->prima_prova, s->out->width, s->out->height, s->out->refresh);
		wlr_output_layout_get_box(m->schermi, s->out, &s->prima_posizione);
		snprintf(s->prova_id, sizeof(s->prova_id), "%s", prova);
	}
	if (s->prova_timer) wl_event_source_timer_update(s->prova_timer, 15000);
	schermo_configura(s->out, &v);
	schermo_nel_disegno(m, s->out, &v);

	// ── E adesso TUTTI gli altri ─────────────────────────────────────────
	//
	// Spostare o spegnere uno schermo cambia il disegno complessivo, quindi
	// cambia il rettangolo di ognuno: la barra e la dock vanno riconfigurate
	// su tutti, non solo su quello toccato. Ricalcolarne uno e basta lascia
	// gli altri con uno spazio utile di prima, e il sintomo è una barra che
	// sta larga quanto lo schermo che non c'è più.
	struct schermo *g;
	wl_list_for_each(g, &m->schermi_elenco, link) {
		wlr_output_layout_get_box(m->schermi, g->out, &g->utile);
		disponi(m, g->out);
	}

	annuncia_schermi(m);

	if (v.acceso && !s->out->enabled) {
		snprintf(risposta, n, "no lo schermo %s non ha accettato", nome);
		return;
	}
	snprintf(risposta, n, "ok");
}

// `1`, `si`, `true`, `on` → vero. Tutto il resto → falso.
static bool parola_vera(const char *p) {
	if (p == NULL)
		return false;
	return strcmp(p, "1") == 0 || strcasecmp(p, "si") == 0 ||
	       strcasecmp(p, "true") == 0 || strcasecmp(p, "on") == 0;
}


// ── Le manopole dell'ingresso, dal pannello «Tastiera e mouse» ───────────
//
//     tastiera it
//     tastiera us intl
//     ripetizione 25 600
//     sensibilita 0.2
//     touchpad si si no          (naturale, mentre-scrivi, tocco)
//     dispositivo "Elan Touchpad" no
//
// Un trattino al posto di un valore vuol dire «questa lasciala stare»: è
// quello che permette al pannello di cambiare UNA manopola senza dover
// rimandare anche le altre due, e senza che una manopola che non ha ancora
// un valore ne prenda uno inventato.
static int forse_bool(const char *p) {
	if (p == NULL || strcmp(p, "-") == 0)
		return -1;
	return parola_vera(p) ? 1 : 0;
}

/// Esiste, questa disposizione? Si chiede a xkb provando a costruirla.
///
/// Non c'è un elenco da consultare: `xkb` risponde NULL a una disposizione
/// che non conosce, e provare è l'unico modo di sapere.
static bool disposizione_esiste(const char *disp, const char *var) {
	struct xkb_rule_names nomi;
	memset(&nomi, 0, sizeof(nomi));
	if (disp != NULL && disp[0] != '\0')
		nomi.layout = disp;
	if (var != NULL && var[0] != '\0')
		nomi.variant = var;

	struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (ctx == NULL)
		return false;
	struct xkb_keymap *k = xkb_keymap_new_from_names(ctx, &nomi,
		XKB_KEYMAP_COMPILE_NO_FLAGS);
	const bool c_e = k != NULL;
	if (k != NULL)
		xkb_keymap_unref(k);
	xkb_context_unref(ctx);
	return c_e;
}

static void comando_tastiera(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *disp = parola(&resto);
	if (disp == NULL) {
		snprintf(risposta, n, "no tastiera vuole una disposizione (it, us…)");
		return;
	}
	char *var = parola(&resto);

	// ── Si rifiuta PRIMA di applicare ────────────────────────────────────
	//
	// `tastiera_applica` sa ripiegare su quella di sistema, e deve saperlo:
	// una disposizione che non esiste non deve lasciare senza tastiera. Ma
	// qui c'è qualcuno che ha appena scelto una voce da un menu, e accettare
	// per poi mettere un'altra disposizione vuol dire un pannello che dice
	// «italiano» e una tastiera che scrive in americano.
	//
	// E c'è un secondo motivo, meno ovvio: la scelta si TIENE, e vale per
	// ogni tastiera collegata dopo. Tenerne una che non funziona vuol dire
	// ripetere lo stesso ripiego, e lo stesso errore nel registro, a ogni
	// tastiera nuova per tutta la sessione.
	if (strcmp(disp, "-") != 0
	    && !disposizione_esiste(disp, (var != NULL && strcmp(var, "-") != 0)
	                                  ? var : NULL)) {
		snprintf(risposta, n, "no la disposizione «%s%s%s» non esiste", disp,
			(var != NULL && strcmp(var, "-") != 0) ? " " : "",
			(var != NULL && strcmp(var, "-") != 0) ? var : "");
		return;
	}

	// «-» vuol dire «quella di sistema»: è il modo di TOGLIERE una scelta,
	// che senza una parola apposta non si potrebbe dire.
	if (strcmp(disp, "-") == 0)
		m->ingresso.disposizione[0] = '\0';
	else
		snprintf(m->ingresso.disposizione, sizeof(m->ingresso.disposizione),
			"%s", disp);
	if (var == NULL || strcmp(var, "-") == 0)
		m->ingresso.variante[0] = '\0';
	else
		snprintf(m->ingresso.variante, sizeof(m->ingresso.variante), "%s", var);

	ingresso_riapplica(m);
	snprintf(risposta, n, "ok");
}

static void comando_ripetizione(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *sritmo = parola(&resto);
	char *sritardo = parola(&resto);
	if (sritmo == NULL || sritardo == NULL) {
		snprintf(risposta, n, "no ripetizione vuole quante al secondo e "
			"dopo quanti millisecondi");
		return;
	}
	const int ritmo = atoi(sritmo);
	const int ritardo = atoi(sritardo);
	// Zero ripetizioni al secondo è un tasto che non si ripete mai, e un
	// ritardo di zero è un tasto che parte a raffica appena lo si sfiora.
	// Nessuno dei due si sceglie apposta: si scrivono per sbaglio.
	if (ritmo < 1 || ritmo > 100 || ritardo < 100 || ritardo > 4000) {
		snprintf(risposta, n, "no fuori da quello che si può usare "
			"(da 1 a 100 al secondo, da 100 a 4000 millisecondi)");
		return;
	}
	m->ingresso.ripetizioni_s = ritmo;
	m->ingresso.ritardo_ms = ritardo;
	ingresso_riapplica(m);
	snprintf(risposta, n, "ok");
}

static void comando_sensibilita(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *sv = parola(&resto);
	if (sv == NULL) {
		snprintf(risposta, n, "no sensibilita vuole un numero da -1 a 1 "
			"(0 è il neutro)");
		return;
	}
	const double v = atof(sv);
	if (v < -1.0 || v > 1.0) {
		snprintf(risposta, n, "no la sensibilità va da -1 a 1, e 0 è il "
			"neutro: %s è fuori", sv);
		return;
	}
	m->ingresso.sensibilita = v;
	m->ingresso.sensibilita_detta = true;
	ingresso_riapplica(m);
	snprintf(risposta, n, "ok");
}

static void comando_touchpad(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *nat = parola(&resto);
	char *scrivi = parola(&resto);
	char *tocco = parola(&resto);
	if (nat == NULL) {
		snprintf(risposta, n, "no touchpad vuole scorrimento naturale, "
			"spento mentre scrivi, tocco per cliccare (si, no o «-»)");
		return;
	}
	m->ingresso.scorrimento_naturale = forse_bool(nat);
	if (scrivi != NULL)
		m->ingresso.spento_mentre_scrivi = forse_bool(scrivi);
	if (tocco != NULL)
		m->ingresso.tocco_e_clic = forse_bool(tocco);
	ingresso_riapplica(m);
	snprintf(risposta, n, "ok");
}

/// Accende o spegne UN dispositivo per nome. Serve al touchpad, che si spegne
/// tutto invece che a manopole — è la levetta «touchpad» del pannello.
///
/// ── La levetta PRIMA, il nome DOPO, e il perché è costato una funzione ───
///
/// Fino al 31 agosto 2026 questo verbo era `dispositivo <nome> <si|no>`, e
/// leggeva il nome con `parola()` — che si ferma al primo spazio. Ma i nomi di
/// libinput hanno gli spazi: su questa macchina il touchpad si chiama
///
///     ELAN0504:01 04F3:312A Touchpad
///
/// e quello che arrivava qui era `ELAN0504:01`, con `04F3:312A` al posto di
/// «acceso o spento». Il compositore rispondeva
/// «non c'è nessun dispositivo che si chiama ELAN0504:01» — cioè diceva la
/// verità, in un registro che nessuno guarda — e nella sessione vera la
/// levetta del touchpad e il tasto Fn che lo spegne non facevano **niente**.
///
/// Il nome è l'unica cosa qui dentro che può contenere spazi, quindi è
/// l'unica che può stare in fondo: prende **tutto il resto della riga**. Non è
/// una convenzione scelta a caso — è l'unica che non si può sbagliare.
static void comando_dispositivo(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *acceso = parola(&resto);
	// Il nome è quello che resta, spazi compresi, senza quelli davanti.
	while (*resto == ' ' || *resto == '\t')
		resto++;
	char *nome = resto;
	if (acceso == NULL || *nome == '\0') {
		snprintf(risposta, n, "no dispositivo vuole «si» o «no» e poi un nome "
			"(il nome sta in fondo perché è l'unico che può avere spazi)");
		return;
	}
	// E niente a-capo o spazi in coda: il nome arriva da una riga di testo.
	size_t l = strlen(nome);
	while (l > 0 && (nome[l - 1] == ' ' || nome[l - 1] == '\t'
			|| nome[l - 1] == '\r' || nome[l - 1] == '\n'))
		nome[--l] = '\0';
	const bool si = parola_vera(acceso);

	// ── Due «no» diversi, e confonderli manda a cercare altrove ──────────
	//
	// `trovati` conta chi porta quel nome; `regolati` conta quelli che si sono
	// potuti davvero accendere o spegnere. Non sono la stessa cosa: un
	// dispositivo che esiste ma non passa da libinput — è il caso del backend
	// annidato, dove il puntatore arriva dal compositore che ci ospita — c'è
	// eccome, e rispondere «non c'è nessun dispositivo che si chiama così»
	// manda a cercare un errore di nome che non esiste.
	//
	// Trovato il 31 agosto 2026 dalla prova che verifica il giro completo:
	// `dispositivi` elencava `wayland-pointer-seat0` e `dispositivo` diceva
	// che non c'era. Tutti e due i verbi «funzionavano»; era la frase a
	// mentire.
	int trovati = 0;
	int regolati = 0;
	struct puntatore *p;
	wl_list_for_each(p, &m->puntatori, link) {
		if (p->dev->name == NULL || strcmp(p->dev->name, nome) != 0)
			continue;
		trovati++;
		if (!wlr_input_device_is_libinput(p->dev))
			continue;
		struct libinput_device *ld = wlr_libinput_get_device_handle(p->dev);
		if (ld == NULL)
			continue;
		libinput_device_config_send_events_set_mode(ld, si
			? LIBINPUT_CONFIG_SEND_EVENTS_ENABLED
			: LIBINPUT_CONFIG_SEND_EVENTS_DISABLED);
		regolati++;
	}
	if (trovati == 0) {
		snprintf(risposta, n, "no non c'è nessun dispositivo che si chiama %s",
			nome);
		return;
	}
	if (regolati == 0) {
		snprintf(risposta, n, "no «%s» c'è ma non lo posso accendere o "
			"spegnere: non passa da libinput (è il caso del backend annidato, "
			"dove il puntatore lo dà il compositore che ci ospita)", nome);
		return;
	}
	snprintf(risposta, n, "ok");
}

/// Che cosa c'è attaccato, e come è regolato adesso.
///
/// Serve al pannello, che deve poter elencare i dispositivi per nome — la
/// levetta del touchpad ne ha bisogno — e serve alle prove, che altrimenti
/// non avrebbero modo di verificare che una manopola sia davvero arrivata.
static void comando_dispositivi(struct minerva *m, char *risposta, size_t n) {
	size_t o = (size_t)snprintf(risposta, n, "ok {\"disposizione\":\"%s\","
		"\"variante\":\"%s\",\"ripetizioni\":%d,\"ritardo\":%d,"
		"\"tastiere\":[",
		m->ingresso.disposizione, m->ingresso.variante,
		m->ingresso.ripetizioni_s > 0 ? m->ingresso.ripetizioni_s : 25,
		m->ingresso.ritardo_ms > 0 ? m->ingresso.ritardo_ms : 600);

	bool prima = true;
	struct tastiera *t;
	wl_list_for_each(t, &m->tastiere, link) {
		char nome[192];
		json_stringa(nome, sizeof(nome),
			t->kb->base.name != NULL ? t->kb->base.name : "");

		// ── E la disposizione VERA, chiesta a xkb ─────────────────────
		//
		// Non quella che abbiamo chiesto: quella che la tastiera ha
		// davvero. Sono due cose diverse ogni volta che una disposizione
		// non esiste e si è ripiegato — e senza questo campo, una prova
		// che verifica «la tastiera è italiana» verificherebbe solo che
		// gliel'abbiamo detto.
		char vera[64];
		vera[0] = '\0';
		struct xkb_keymap *mk = t->kb->keymap;
		if (mk != NULL && xkb_keymap_num_layouts(mk) > 0) {
			const char *l = xkb_keymap_layout_get_name(mk, 0);
			if (l != NULL)
				snprintf(vera, sizeof(vera), "%s", l);
		}
		char veraj[192];
		json_stringa(veraj, sizeof(veraj), vera);

		int q = snprintf(risposta + o, n > o ? n - o : 0,
			"%s{\"nome\":\"%s\",\"disposizione\":\"%s\"}",
			prima ? "" : ",", nome, veraj);
		if (q < 0 || (size_t)q >= (n > o ? n - o : 0))
			break;
		o += (size_t)q;
		prima = false;
	}

	o += (size_t)snprintf(risposta + o, n > o ? n - o : 0, "],\"puntatori\":[");
	prima = true;
	struct puntatore *p;
	wl_list_for_each(p, &m->puntatori, link) {
		char nome[192];
		json_stringa(nome, sizeof(nome),
			p->dev->name != NULL ? p->dev->name : "");
		// `touchpad` non è una supposizione sul nome: è libinput che dice se
		// quel dispositivo sa contare le dita. Indovinarlo dal nome è il modo
		// classico di sbagliare con un mouse che si chiama «Touch».
		bool e_touchpad = false;
		if (wlr_input_device_is_libinput(p->dev)) {
			struct libinput_device *ld =
				wlr_libinput_get_device_handle(p->dev);
			e_touchpad = ld != NULL
				&& libinput_device_config_tap_get_finger_count(ld) > 0;
		}
		int q = snprintf(risposta + o, n > o ? n - o : 0,
			"%s{\"nome\":\"%s\",\"touchpad\":%s}",
			prima ? "" : ",", nome, e_touchpad ? "true" : "false");
		if (q < 0 || (size_t)q >= (n > o ? n - o : 0))
			break;
		o += (size_t)q;
		prima = false;
	}
	snprintf(risposta + o, n > o ? n - o : 0, "]}");
}


/// ── L'aspetto della barra del titolo, dal pannello ──────────────────────
///
///     aspetto <alta|-> <destra|sinistra|-> <fondoRRGGBB|-> <testoRRGGBB|->
///
/// Il «-» vuol dire «questa non la sto toccando», come in `touchpad` e in
/// `tastiera`: è la stessa convenzione in tutto il canale, e averne una sola
/// vuol dire non doverla ricordare.
///
/// Fino al 31 agosto 2026 queste erano `#define` dentro `barra.h`. Il pannello
/// «Finestre» mostrava l'altezza e il lato dei pulsanti, li scriveva in
/// `settings.json`, e sotto minerva-wayland non succedeva niente — e
/// `coloriBordo` era dichiarato apertamente «senza strada». Tre manopole che
/// si vedono e non fanno nulla.
///
/// Cambiare l'altezza sposta le finestre: la barra sta SOPRA il contenuto e se
/// cresce di dieci pixel, o il contenuto scende o la finestra si allunga. Qui
/// si tiene fermo il rettangolo ESTERNO — quello che si vede — e si ridivide
/// dentro: una finestra al suo posto ci resta, e cambia solo lo spessore della
/// sua maniglia.
static bool colore_da_esadecimale(const char *t, double *r, double *g,
		double *b) {
	if (t == NULL || strlen(t) != 6)
		return false;
	unsigned int v = 0;
	for (int i = 0; i < 6; i++) {
		const char c = t[i];
		unsigned int d;
		if (c >= '0' && c <= '9') d = (unsigned int)(c - '0');
		else if (c >= 'a' && c <= 'f') d = (unsigned int)(c - 'a' + 10);
		else if (c >= 'A' && c <= 'F') d = (unsigned int)(c - 'A' + 10);
		else return false;
		v = (v << 4) | d;
	}
	*r = (double)((v >> 16) & 0xFF) / 255.0;
	*g = (double)((v >> 8) & 0xFF) / 255.0;
	*b = (double)(v & 0xFF) / 255.0;
	return true;
}

// ── Il bordo che gira ─────────────────────────────────────────────────────
//
// Il conto dei colori e il disegno stanno in `src/anello.c`. Qui c'è solo chi
// lo accende, su quali finestre, e con che stato.

/// Lo stato del bordo, pronto per `anello.c`.
static struct anello_stato cornice_stato(const struct minerva *m,
		const struct finestra *f, double alfa) {
	struct anello_stato s = {0};
	int w = 0, h = 0;
	finestra_geometria((struct finestra *)f, &w, &h);
	s.larghezza = w;
	s.altezza = h + finestra_barra_alta((struct finestra *)f);
	s.spessore = m->cornice_spessore > 0 ? m->cornice_spessore : BORDO_PRESA;
	s.raggio = f->schermo_intero ? 0 : ANGOLO_RAGGIO;
	s.fase = m->cornice_fase;
	s.quante_tinte = m->cornice_quante_tinte;
	for (int i = 0; i < m->cornice_quante_tinte && i < ANELLO_TINTE_MAX; i++)
		for (int c = 0; c < 3; c++)
			s.tinte[i][c] = m->cornice_tinte[i][c];
	s.alfa = alfa;
	return s;
}

/// Ridipinge i quattro pezzi della striscia di una finestra.
///
/// Quattro immagini nuove a ogni battito, e non è uno spreco: sono
/// centosessanta kilobyte in tutto (vedi il conto in cima ad `anello.c`), e
/// l'alternativa — dei rettangoli di colore pieno — è quella che ha lasciato
/// «le linee» che Giacomo ha visto subito.
static void finestra_striscia(struct minerva *m, struct finestra *f,
		bool accendi, double alfa) {
	if (f->led[0] == NULL)
		return;
	if (!accendi) {
		for (int i = 0; i < ANELLO_PEZZI; i++)
			if (f->led[i] != NULL) {
				wlr_scene_buffer_set_buffer(f->led[i], NULL);
				wlr_scene_node_set_enabled(&f->led[i]->node, false);
			}
		return;
	}
	struct anello_stato st = cornice_stato(m, f, alfa);
	for (int i = 0; i < ANELLO_PEZZI; i++) {
		if (f->led[i] == NULL)
			continue;
		int pl = 0, ph = 0, px = 0, py = 0;
		struct wlr_buffer *b = anello_disegna(&st, (enum anello_pezzo)i,
			&pl, &ph, &px, &py);
		if (b == NULL) {
			wlr_scene_buffer_set_buffer(f->led[i], NULL);
			wlr_scene_node_set_enabled(&f->led[i]->node, false);
			continue;
		}
		wlr_scene_buffer_set_buffer(f->led[i], b);
		wlr_scene_buffer_set_dest_size(f->led[i], pl, ph);
		wlr_scene_node_set_position(&f->led[i]->node, px, py);
		wlr_scene_node_set_enabled(&f->led[i]->node, true);
		// La scena ne prende una copia sua: la nostra si lascia andare, o
		// ogni battito lascerebbe indietro un'immagine che non muore più.
		wlr_buffer_drop(b);
	}
}

/// Ridipinge l'anello di ogni finestra: acceso su quella attiva, trasparente
/// su tutte le altre.
///
/// Si passano SEMPRE tutte, anche a cornice spenta: è il modo in cui una
/// finestra che perde il fuoco si spegne davvero. Spegnere solo «quella di
/// prima» vorrebbe dire tenersi un puntatore a chi era attivo, e quel
/// puntatore un giorno punta a una finestra chiusa.
static void cornici_ridipingi(struct minerva *m) {
	const float trasparente[4] = {0.0f, 0.0f, 0.0f, 0.0f};
	float acceso[4] = {m->cornice_r, m->cornice_g, m->cornice_b, 1.0f};
	if (m->cornice_modo == CORNICE_GIRA) {
		struct anello_stato s = {0};
		s.quante_tinte = m->cornice_quante_tinte;
		for (int i = 0; i < m->cornice_quante_tinte
				&& i < ANELLO_TINTE_MAX; i++)
			for (int c = 0; c < 3; c++)
				s.tinte[i][c] = m->cornice_tinte[i][c];
		anello_colore(&s, m->cornice_fase,
			&acceso[0], &acceso[1], &acceso[2]);
	}

	const bool striscia = m->cornice_modo == CORNICE_STRISCIA;
	struct finestra *attiva = finestra_attiva(m);
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		const bool viva = f == attiva;
		const double alfa = viva ? 1.0 : m->cornice_spente;
		const bool accendi = (m->cornice_modo != CORNICE_SPENTA)
			&& (viva || m->cornice_spente > 0.0);
		acceso[3] = (float)alfa;
		// Si colora l'ANELLO, non la maniglia: la maniglia è un rettangolo
		// pieno sotto tutta la finestra, e una finestra traslucida ne
		// lascerebbe vedere il colore per intero. Vedi il commento accanto a
		// `anello` in `struct finestra`.
		//
		// Con la striscia l'anello di tinta unica si spegne e al suo posto si
		// accendono i quattro pezzi disegnati: due bordi sovrapposti
		// vorrebbero dire il colore del più vecchio che traspare da sotto.
		if (f->anello != NULL)
			wlr_scene_rect_set_color(f->anello,
				(accendi && !striscia) ? acceso : trasparente);
		finestra_striscia(m, f, accendi && striscia, alfa);
	}
}

/// Ogni quanto si muove la tinta. Ottanta millisecondi, cioè dodici volte al
/// secondo: non è pigrizia. Il giro più veloce che si può chiedere è di due
/// secondi, e in due secondi dodici passi al secondo fanno ventiquattro
/// gradini di tinta — più di quanti l'occhio ne distingua su un anello di sei
/// pixel. Andare a sessanta vorrebbe dire cinque volte il lavoro per una
/// differenza che non c'è, su una macchina a batteria.
#define CORNICE_PASSO_MS 80

static int cornice_scatta(void *dato) {
	struct minerva *m = dato;
	if (m->cornice_modo != CORNICE_GIRA
			&& m->cornice_modo != CORNICE_STRISCIA)
		return 0;
	const double periodo = m->cornice_periodo > 0 ? m->cornice_periodo : 8000;
	m->cornice_fase += (double)CORNICE_PASSO_MS / periodo;
	if (m->cornice_fase >= 1.0)
		m->cornice_fase -= floor(m->cornice_fase);
	cornici_ridipingi(m);
	wl_event_source_timer_update(m->cornice_timer, CORNICE_PASSO_MS);
	return 0;
}

// ── «effetto»: nessuno, vetro o blur ─────────────────────────────────────
//
//     effetto nessuno
//     effetto vetro 0.88
//
// Il secondo argomento è l'opacità, da 0,50 a 1,00. Sotto 0,50 una finestra
// smette di essere una finestra: si legge lo sfondo attraverso il testo, e non
// si capisce più quale delle due cose sovrapposte si sta guardando. Il limite
// c'è per la stessa ragione per cui il giro della cornice non scende sotto i
// due secondi — certi valori non sono gusti, sono danni.
//
// In blur l'opacità regola la decorazione; il contenuto del client conserva
// la propria alfa. In vetro vale anche per il contenuto, fuori dal fullscreen.
static void comando_effetto(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *modo_t = parola(&resto);
	char *alfa_t = parola(&resto);
	if (modo_t == NULL) {
		snprintf(risposta, n, "no effetto vuole «nessuno|vetro|acquerello», e "
			"con un effetto acceso un'opacità fra 0.50 e 1.00");
		return;
	}

	int modo;
	if (strcmp(modo_t, "nessuno") == 0) {
		modo = EFFETTO_NESSUNO;
	} else if (strcmp(modo_t, "vetro") == 0) {
		modo = EFFETTO_VETRO;
	} else if (strcmp(modo_t, "acquerello") == 0 || strcmp(modo_t, "blur") == 0) {
		// «blur» è la parola di prima: il blur gaussiano è stato tolto il 28
		// settembre 2026 («a questo punto il blur lo eliminerei»), e chi lo
		// chiede ancora — un file di impostazioni vecchio, uno script —
		// riceve il filtro che c'è, invece di un rifiuto.
		// Il materiale della Tappa 2: il colore di quello che sta dietro, a
		// 1/32, invece della sua forma sfocata.
		modo = EFFETTO_ACQUERELLO;
	} else {
		snprintf(risposta, n, "no «%s» non è un effetto", modo_t);
		return;
	}

	float alfa = m->effetto_alfa;
	if (alfa_t != NULL && strcmp(alfa_t, "-") != 0) {
		char *fine = NULL;
		const double v = strtod(alfa_t, &fine);
		if (fine == alfa_t || *fine != '\0' || v < 0.50 || v > 1.00) {
			snprintf(risposta, n, "no l'opacità sta fra 0.50 e 1.00, "
				"non «%s»", alfa_t);
			return;
		}
		alfa = (float)v;
	}

	m->voluto_effetto = modo;
	m->effetto_alfa = alfa;
	effetto_imposta(m, effetto_disegnato(m));

	snprintf(risposta, n, "ok %s %.2f",
		modo == EFFETTO_ACQUERELLO ? "acquerello"
			: (modo == EFFETTO_VETRO ? "vetro" : "nessuno"),
		(double)alfa);
}

/// A risparmio l'effetto scende a «nessuno», dal blur E dal vetro.
///
/// La prima versione scendeva dal blur al vetro, «che costa solo un
/// moltiplicatore». Sbagliato due volte, e visto in fotografia il 23
/// settembre 2026: una finestra trasparente SENZA sfocatura dietro lascia
/// passare lo sfondo sotto il testo — il difetto di leggibilità già pagato
/// una volta (il vetro al 55 %) — e costa di più di quanto sembra, perché
/// una finestra trasparente non copre niente e tutto quello che le sta
/// dietro va disegnato lo stesso. «Nessuno» è il più leggero e il più
/// leggibile insieme.
static int effetto_disegnato(struct minerva *m) {
	return m->risparmio_attivo ? EFFETTO_NESSUNO : m->voluto_effetto;
}

/// La cornice che gira ridipinge l'anello dodici volte al secondo, per
/// sempre: a risparmio si ferma sul suo colore fisso.
static int cornice_disegnata(struct minerva *m) {
	if (m->risparmio_attivo && (m->voluto_cornice == CORNICE_GIRA
			|| m->voluto_cornice == CORNICE_STRISCIA))
		return CORNICE_FISSA;
	return m->voluto_cornice;
}

static double elastico_disegnato(struct minerva *m) {
	return m->risparmio_attivo ? 0.0 : m->voluto_elastico;
}

/// Mette in scena un effetto: il modo, e l'alfa che sta già in
/// `effetto_alfa`. Lo chiamano il verbo e il risparmio.
static void effetto_imposta(struct minerva *m, int modo) {
	const bool cambia_barra = (m->effetto_modo == EFFETTO_NESSUNO)
		!= (modo == EFFETTO_NESSUNO);
	m->effetto_modo = modo;

	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		// La barra porta la propria alfa DENTRO il buffer che disegna, quindi
		// passando da un modo all'altro va rifatta. `barra_aggiorna` non lo
		// farebbe: confronta titolo, larghezza e fuoco, e nessuno dei tre è
		// cambiato. Si azzera la larghezza disegnata, che è il modo che questo
		// file ha già di dire «quel che mostri adesso non vale più».
		if (cambia_barra) {
			f->larghezza_disegnata = 0;
			barra_aggiorna(f);
		}
		finestra_effetto(f);
		finestra_angoli(f);
	}

	// E i pannelli. Senza questo giro il fondo sfocato della barra e della
	// dock arriva solo alla loro prossima commit — cioè al minuto dopo per
	// l'orologio, e MAI per la dock, che se non cambia niente non ridisegna.
	// Visto in una fotografia: la finestra sfocata e la dock ancora nitida.
	struct appoggiata *a;
	wl_list_for_each(a, &m->appoggiate, link)
		appoggiata_sfocatura(a);
}

static void comando_cornice(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *modo_t = parola(&resto);
	char *periodo_t = parola(&resto);
	char *colore_t = parola(&resto);
	char *spesso_t = parola(&resto);
	if (modo_t == NULL) {
		snprintf(risposta, n, "no cornice vuole «spento|fisso|gira», poi i "
			"millisecondi di un giro, un colore RRGGBB e lo spessore");
		return;
	}

	// ── «cornice colori …»: i colori che si alternano ───────────────────
	//
	//     cornice colori 22D3EE,F97316,A855F7
	//     cornice colori -                     (torna allo spettro)
	//
	// Sta dentro lo stesso verbo e non in uno nuovo perché è la stessa cosa:
	// come si comporta il bordo. Un verbo `cornice-colori` sarebbe stato un
	// secondo posto da ricordare per la stessa manopola.
	// ── «cornice spente 0.35»: il bordo anche su chi non ha il fuoco ────
	//
	// Zero spegne tutte tranne l'attiva, che è come la cornice è nata.
	if (strcmp(modo_t, "spente") == 0) {
		if (periodo_t == NULL) {
			snprintf(risposta, n, "no «cornice spente» vuole una velatura da "
				"0 a 0.60, e 0 vuol dire solo la finestra attiva");
			return;
		}
		char *fine = NULL;
		const double v = strtod(periodo_t, &fine);
		if (fine == periodo_t || *fine != '\0' || v < 0.0 || v > 0.60) {
			snprintf(risposta, n, "no la velatura delle spente sta fra 0 e "
				"0.60: sopra, la finestra attiva non si distingue più");
			return;
		}
		m->cornice_spente = v;
		cornici_ridipingi(m);
		snprintf(risposta, n, "ok %.2f", v);
		return;
	}

	if (strcmp(modo_t, "colori") == 0) {
		if (periodo_t == NULL) {
			snprintf(risposta, n, "no «cornice colori» vuole un elenco "
				"RRGGBB,RRGGBB,… oppure «-» per lo spettro");
			return;
		}
		if (strcmp(periodo_t, "-") == 0) {
			m->cornice_quante_tinte = 0;
			cornici_ridipingi(m);
			snprintf(risposta, n, "ok spettro");
			return;
		}
		// Si legge TUTTO l'elenco prima di scriverne uno solo: un elenco per
		// metà buono lascerebbe la cornice con tre colori dei cinque chiesti,
		// e nessun modo di sapere quali.
		float tinte[8][3];
		int quante = 0;
		char copia[256];
		snprintf(copia, sizeof(copia), "%s", periodo_t);
		// A mano e non con `strsep`, che vuole `_GNU_SOURCE`: questo file
		// una funzione per spezzare una riga ce l'ha già (`parola`), e
		// aggiungere una macro di configurazione per sei righe non si fa.
		char *pezzo = copia;
		while (pezzo != NULL && *pezzo != '\0') {
			char *virgola = strchr(pezzo, ',');
			if (virgola != NULL)
				*virgola = '\0';
			char *prossimo = virgola != NULL ? virgola + 1 : NULL;
			if (*pezzo == '\0') {
				pezzo = prossimo;
				continue;
			}
			if (quante >= 8) {
				snprintf(risposta, n, "no più di otto colori non si "
					"distinguono girando");
				return;
			}
			double r, g, b;
			if (!colore_da_esadecimale(pezzo, &r, &g, &b)) {
				snprintf(risposta, n, "no «%s» non è un colore RRGGBB",
					pezzo);
				return;
			}
			tinte[quante][0] = (float)r;
			tinte[quante][1] = (float)g;
			tinte[quante][2] = (float)b;
			quante++;
			pezzo = prossimo;
		}
		if (quante == 0) {
			snprintf(risposta, n, "no l'elenco dei colori è vuoto");
			return;
		}
		for (int i = 0; i < quante; i++)
			for (int c = 0; c < 3; c++)
				m->cornice_tinte[i][c] = tinte[i][c];
		m->cornice_quante_tinte = quante;
		cornici_ridipingi(m);
		snprintf(risposta, n, "ok %d", quante);
		return;
	}

	int modo;
	if (strcmp(modo_t, "spento") == 0) {
		modo = CORNICE_SPENTA;
	} else if (strcmp(modo_t, "fisso") == 0) {
		modo = CORNICE_FISSA;
	} else if (strcmp(modo_t, "gira") == 0) {
		modo = CORNICE_GIRA;
	} else if (strcmp(modo_t, "striscia") == 0) {
		modo = CORNICE_STRISCIA;
	} else {
		snprintf(risposta, n, "no «%s» non è un modo della cornice", modo_t);
		return;
	}

	// Il periodo si accetta solo dentro limiti che vogliono dire qualcosa.
	// Sotto due secondi non è un colore che gira, è un lampeggio — e un
	// lampeggio davanti agli occhi tutto il giorno è una cosa che si fa a
	// qualcuno, non per qualcuno. Sopra i cinque minuti non si vede muovere.
	int periodo = m->cornice_periodo;
	if (periodo_t != NULL && strcmp(periodo_t, "-") != 0) {
		char *fine = NULL;
		const long v = strtol(periodo_t, &fine, 10);
		if (fine == periodo_t || *fine != '\0' || v < 2000 || v > 300000) {
			snprintf(risposta, n, "no il giro sta fra 2000 e 300000 "
				"millisecondi, non «%s»", periodo_t);
			return;
		}
		periodo = (int)v;
	}

	if (colore_t != NULL && strcmp(colore_t, "-") != 0) {
		double r, g, b;
		if (!colore_da_esadecimale(colore_t, &r, &g, &b)) {
			snprintf(risposta, n, "no «%s» non è un colore RRGGBB", colore_t);
			return;
		}
		m->cornice_r = (float)r;
		m->cornice_g = (float)g;
		m->cornice_b = (float)b;
	}

	// ── Lo spessore ─────────────────────────────────────────────────────
	//
	// Da uno a venti pixel. Sotto uno non c'è bordo; sopra venti non è più un
	// bordo, è una seconda finestra intorno alla finestra — e sarebbe anche
	// una banda in cui il clic non arriva più al programma, perché la presa
	// per ridimensionare segue lo spessore.
	int spesso = m->cornice_spessore;
	if (spesso_t != NULL && strcmp(spesso_t, "-") != 0) {
		char *fine = NULL;
		const long v = strtol(spesso_t, &fine, 10);
		if (fine == spesso_t || *fine != '\0' || v < 1 || v > 20) {
			snprintf(risposta, n, "no lo spessore sta fra 1 e 20 pixel, "
				"non «%s»", spesso_t);
			return;
		}
		spesso = (int)v;
	}

	const bool cambia_spessore = spesso != m->cornice_spessore;
	m->voluto_cornice = modo;
	m->cornice_periodo = periodo;
	m->cornice_spessore = spesso;

	// La geometria dell'anello si scrive nella strada del ridimensionamento,
	// che è l'unico posto che sa quanto è grande ogni finestra. Cambiando
	// spessore bisogna ripassare di là, o il numero nuovo si vedrebbe solo
	// alla prossima finestra spostata.
	if (cambia_spessore) {
		struct finestra *w;
		wl_list_for_each(w, &m->finestre_elenco, link) {
			struct wlr_box b;
			finestra_box(w, &b);
			finestra_posiziona(w, b.x, b.y, b.width, b.height);
		}
	}

	cornice_imposta(m, cornice_disegnata(m));
	snprintf(risposta, n, "ok");
}

static void elastico_imposta(struct minerva *m, double forza) {
	m->elastico = forza;
	// Spegnendo, chi stava rimbalzando torna subito in pari: un elastico
	// spento che lascia una finestra storta è peggio di uno acceso.
	if (forza == 0.0) {
		struct finestra *w;
		wl_list_for_each(w, &m->finestre_elenco, link)
			molla_ferma_finestra(w);
	}
}

// ── Il modo risparmio ────────────────────────────────────────────────────
//
//     risparmio                  com'è adesso, in JSON
//     risparmio mai              gli effetti restano quelli chiesti
//     risparmio auto [soglia]    a batteria sotto la soglia (20 di serie),
//                                o col profilo «risparmio energetico»
//     risparmio sempre           gradino giù, sempre
//
// Cambiando stato si annuncia `evento risparmio {…}`: la shell lo dice a
// chi guarda. Un effetto che si spegne da solo senza una parola sembra un
// guasto — ed è la prima cosa che uno va a «riparare» riaccendendolo.

static bool stessa_stringa(const char *a, const char *b) {
	return a == b || (a != NULL && b != NULL && strcmp(a, b) == 0);
}

static int risparmio_json(struct minerva *m, char *buf, size_t n) {
	const struct energia_stato e = energia_stato(m->energia);
	const char *modo = m->risparmio_modo == RISPARMIO_SEMPRE ? "sempre"
		: (m->risparmio_modo == RISPARMIO_AUTO ? "auto" : "mai");
	char motivo[24] = "null";
	if (m->risparmio_motivo != NULL)
		snprintf(motivo, sizeof(motivo), "\"%s\"", m->risparmio_motivo);
	return snprintf(buf, n, "{\"modo\":\"%s\",\"soglia\":%d,\"attivo\":%s,"
		"\"motivo\":%s,\"batteria\":%s,\"percento\":%d,\"scarica\":%s,"
		"\"profiloRisparmio\":%s}",
		modo, m->risparmio_soglia, m->risparmio_attivo ? "true" : "false",
		motivo, e.batteria ? "true" : "false", (int)e.percento,
		e.scarica ? "true" : "false", e.profilo_risparmio ? "true" : "false");
}

/// Decide, e mette in scena solo quello che cambia: una batteria che scende
/// dal 60 al 59 % non deve rifare tutte le finestre.
static void risparmio_ricalcola(struct minerva *m) {
	const char *motivo = NULL;
	bool attivo = false;
	if (m->risparmio_modo == RISPARMIO_SEMPRE) {
		attivo = true;
		motivo = "chiesto";
	} else if (m->risparmio_modo == RISPARMIO_AUTO) {
		attivo = energia_da_risparmiare(energia_stato(m->energia),
			m->risparmio_soglia, &motivo);
	}
	const bool cambiato = attivo != m->risparmio_attivo
		|| !stessa_stringa(motivo, m->risparmio_motivo);
	m->risparmio_attivo = attivo;
	m->risparmio_motivo = motivo;

	const int eff = effetto_disegnato(m);
	if (eff != (int)m->effetto_modo)
		effetto_imposta(m, eff);
	const int corn = cornice_disegnata(m);
	if (corn != (int)m->cornice_modo)
		cornice_imposta(m, corn);
	const double el = elastico_disegnato(m);
	if (el != m->elastico)
		elastico_imposta(m, el);

	if (cambiato) {
		wlr_log(WLR_INFO, "minerva: risparmio %s (%s)",
			attivo ? "acceso" : "spento", motivo != NULL ? motivo : "-");
		if (m->canale != NULL) {
			char json[256], riga[300];
			risparmio_json(m, json, sizeof(json));
			snprintf(riga, sizeof(riga), "evento risparmio %s", json);
			canale_annuncia(m->canale, "risparmio", riga);
		}
	}
}

static void energia_cambiata(void *dati) {
	risparmio_ricalcola(dati);
}

static void comando_risparmio(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *modo_t = parola(&resto);
	char *soglia_t = parola(&resto);
	if (modo_t != NULL) {
		int modo;
		if (strcmp(modo_t, "mai") == 0) {
			modo = RISPARMIO_MAI;
		} else if (strcmp(modo_t, "auto") == 0) {
			modo = RISPARMIO_AUTO;
		} else if (strcmp(modo_t, "sempre") == 0) {
			modo = RISPARMIO_SEMPRE;
		} else {
			snprintf(risposta, n, "no risparmio vuole «mai», «auto» o "
				"«sempre», non «%s»", modo_t);
			return;
		}
		int soglia = m->risparmio_soglia;
		if (soglia_t != NULL) {
			char *fine = NULL;
			const long v = strtol(soglia_t, &fine, 10);
			// Sotto il 5 % il gradino arriverebbe quando la macchina sta già
			// per spegnersi; sopra l'80 % sarebbe «sempre» con un altro nome.
			if (fine == soglia_t || *fine != '\0' || v < 5 || v > 80) {
				snprintf(risposta, n, "no la soglia sta fra 5 e 80 per "
					"cento, non «%s»", soglia_t);
				return;
			}
			soglia = (int)v;
		}
		if (parola(&resto) != NULL) {
			snprintf(risposta, n, "no risparmio: troppe parole");
			return;
		}
		m->risparmio_modo = modo;
		m->risparmio_soglia = soglia;
		risparmio_ricalcola(m);
	}
	const int scritti = snprintf(risposta, n, "ok ");
	if (scritti > 0 && (size_t)scritti < n)
		risparmio_json(m, risposta + scritti, n - (size_t)scritti);
}

/// Mette in scena il modo della cornice. Lo chiamano il verbo e il risparmio.
static void cornice_imposta(struct minerva *m, int modo) {
	m->cornice_modo = modo;
	cornici_ridipingi(m);

	// Il timer parte e si ferma col modo: a cornice ferma non deve restare in
	// piedi un battito che dodici volte al secondo scopre di non avere niente
	// da fare. È la stessa regola della scansione del Wi-Fi.
	if (m->cornice_timer != NULL) {
		wl_event_source_timer_update(m->cornice_timer,
			(modo == CORNICE_GIRA || modo == CORNICE_STRISCIA)
				? CORNICE_PASSO_MS : 0);
	}
}

static void comando_aspetto(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *alta_t = parola(&resto);
	char *lato_t = parola(&resto);
	char *fondo_t = parola(&resto);
	char *testo_t = parola(&resto);
	if (alta_t == NULL || lato_t == NULL) {
		snprintf(risposta, n, "no aspetto vuole «alta» e «destra|sinistra», "
			"poi facoltativi due colori RRGGBB. «-» per non toccarne una");
		return;
	}

	// Si parte da quello in vigore, così i campi «-» restano davvero fermi.
	struct barra_aspetto d = *barra_aspetto_ora();
	// «non detto» per i colori è la componente rossa negativa: vedi barra.h.
	d.fondo_r = -1.0;
	d.testo_r = -1.0;
	d.alta = 0;

	if (strcmp(alta_t, "-") != 0) {
		char *fine = NULL;
		const long v = strtol(alta_t, &fine, 10);
		if (fine == alta_t || *fine != '\0' || v <= 0 || v > 1000) {
			snprintf(risposta, n, "no «%s» non è un'altezza", alta_t);
			return;
		}
		d.alta = (int)v;
	}
	if (strcmp(lato_t, "-") == 0) {
		d.pulsanti_a_destra = barra_aspetto_ora()->pulsanti_a_destra;
	} else if (strcmp(lato_t, "destra") == 0) {
		d.pulsanti_a_destra = true;
	} else if (strcmp(lato_t, "sinistra") == 0) {
		d.pulsanti_a_destra = false;
	} else {
		snprintf(risposta, n, "no i pulsanti stanno «destra» o «sinistra», "
			"non «%s»", lato_t);
		return;
	}
	if (fondo_t != NULL && strcmp(fondo_t, "-") != 0
	    && !colore_da_esadecimale(fondo_t, &d.fondo_r, &d.fondo_g,
			&d.fondo_b)) {
		snprintf(risposta, n, "no «%s» non è un colore RRGGBB", fondo_t);
		return;
	}
	if (testo_t != NULL && strcmp(testo_t, "-") != 0
	    && !colore_da_esadecimale(testo_t, &d.testo_r, &d.testo_g,
			&d.testo_b)) {
		snprintf(risposta, n, "no «%s» non è un colore RRGGBB", testo_t);
		return;
	}

	if (!barra_aspetto_imposta(&d)) {
		snprintf(risposta, n, "no l'altezza sta fra 20 e 120 pixel: sotto non "
			"si prende col dito, sopra si mangia lo schermo");
		return;
	}

	// ── E adesso si rifà quello che si vede ─────────────────────────────
	//
	// Senza questo giro il valore nuovo varrebbe solo per le finestre che
	// nascono da adesso: le altre resterebbero con la barra di prima, e si
	// vedrebbero due altezze diverse sullo stesso schermo. È il tipo di
	// difetto che si scambia per «non ha funzionato».
	//
	// ── Ma una INGRANDITA non si rifà dal suo riquadro ───────────────────
	//
	// Per una finestra normale «tienti la misura che hai» è la risposta
	// giusta: cambia l'altezza della barra e il contenuto si stringe di
	// qualche pixel, la finestra resta dov'è e grande com'era.
	//
	// Per una ingrandita no. La sua misura NON è una sua proprietà: è lo
	// spazio utile meno la barra, ricalcolato ogni volta. Rifacendola dal
	// riquadro corrente si tiene l'altezza vecchia — cioè resta ingrandita
	// di nome e larga quanto ieri, con una striscia di sfondo sotto o un
	// pezzo che sborda. Si ricalcola dallo spazio utile, che è esattamente
	// quello che fa `finestra_ingrandisci`.
	struct finestra *f;
	wl_list_for_each(f, &m->finestre_elenco, link) {
		struct wlr_box b;
		finestra_box(f, &b);
		if (f->schermo_intero) {
			// A schermo intero la barra non c'è: la misura è lo schermo
			// FISICO, non lo spazio utile. Vedi `finestra_schermo_intero`.
			barra_aggiorna(f);
			continue;
		}
		if (f->ingrandita) {
			struct wlr_box utile;
			finestra_utile(f, &utile);
			b = utile;
		}
		finestra_posiziona(f, b.x, b.y, b.width, b.height);
		barra_aggiorna(f);
	}
	snprintf(risposta, n, "ok");
}

/// ── L'ingrandimento: `lente <scala>` ────────────────────────────────────
///
///     lente 1      spenta (di serie)
///     lente 2      lo schermo mostra metà larghezza e metà altezza
///     lente 4      il massimo
///
/// Sopra il quattro non si va: si vedrebbe una manciata di pixel grandi come
/// francobolli, e chi ha bisogno di più di così ha bisogno di un carattere più
/// grande, non di una lente.
static void comando_lente(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *t = parola(&resto);
	if (t == NULL) {
		snprintf(risposta, n, "no lente vuole una scala fra 1 e 4 "
			"(1 = spenta)");
		return;
	}
	char *fine = NULL;
	const double k = strtod(t, &fine);
	if (fine == t || *fine != '\0' || !(k >= 1.0) || k > 4.0) {
		snprintf(risposta, n, "no «%s» non è una scala fra 1 e 4", t);
		return;
	}

	const bool prima = m->lente_scala > 1.0;
	const bool adesso = k > 1.0;
	m->lente_scala = k;
	if (!adesso)
		m->lente_avvisata = false;

	// Il cursore passa al software solo quando serve, e torna all'hardware
	// appena si spegne: un cursore software costa un ridisegno a ogni
	// movimento del mouse, per sempre. Vedi `lente_commit`.
	if (prima != adesso) {
		struct schermo *s;
		wl_list_for_each(s, &m->schermi_elenco, link)
			wlr_output_lock_software_cursors(s->out, adesso);
	}

	// Si chiede un fotogramma: senza, con la scrivania ferma la lente non
	// comparirebbe finché non si muove qualcosa.
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link)
		wlr_output_schedule_frame(s->out);

	snprintf(risposta, n, "ok");
}

// ── Il colore di tutto lo schermo: la luce notturna ─────────────────────
//
//     colore 1 0.86 0.71      (rosso, verde, blu: 1 è il neutro)
//     colore 1 1 1            (spenta)
//
// Tre moltiplicatori, uno per canale, esattamente quelli che
// `core/LuceNotturna.qml` calcola già dai gradi Kelvin. Il conto non si rifà
// qui: è lo stesso numero che sotto Hyprland finisce dentro uno shader, e due
// conti per la stessa cosa sono due conti che un giorno danno due tinte.
//
// ── Perché una tabella di colore e non uno shader ───────────────────────
//
// Perché Hyprland ha `decoration:screen_shader` e noi no, e non è una
// mancanza da colmare: per scaldare i colori una tabella è la cosa giusta e
// costa meno. È la stessa strada di `gammastep` e `wlsunset`, ed è quella
// che il pannello dei colori del monitor usa da vent'anni.
//
// In wlroots 0.20 non si chiama più «gamma»: è un `wlr_color_transform`, e
// quello che serve è la variante a tre tabelle a una dimensione
// (`lut_3x1d`). Vale per OGNI cosa a schermo — giochi e filmati a schermo
// intero compresi — senza che nessun programma debba saperlo.

/// Quanti gradini ha la tabella. 256 è la misura di un canale a otto bit:
/// più fini non si vedrebbero, e la tabella la interpola comunque.
#define COLORE_GRADINI 256

static void comando_colore(struct minerva *m, char *resto,
		char *risposta, size_t n) {
	char *sr = parola(&resto);
	char *sg = parola(&resto);
	char *sb = parola(&resto);
	if (sr == NULL || sg == NULL || sb == NULL) {
		snprintf(risposta, n, "no colore vuole tre moltiplicatori da 0 a 1 "
			"(1 1 1 è il neutro)");
		return;
	}
	const double moltiplica[3] = {atof(sr), atof(sg), atof(sb)};
	// Sopra 1 non si schiarisce: si SATURA, e il risultato è uno schermo
	// slavato che sembra rotto. Sotto zero non vuol dire niente.
	for (int i = 0; i < 3; i++) {
		if (moltiplica[i] < 0.0 || moltiplica[i] > 1.0) {
			snprintf(risposta, n, "no i moltiplicatori vanno da 0 a 1, e 1 è "
				"il neutro: %s %s %s è fuori", sr, sg, sb);
			return;
		}
	}

	// Col neutro non si costruisce niente e si TOGLIE la tabella: lasciarne
	// una identità in mezzo vorrebbe dire far passare ogni fotogramma per una
	// trasformazione che non cambia niente.
	struct wlr_color_transform *nuova = NULL;
	const bool neutro = moltiplica[0] >= 0.999 && moltiplica[1] >= 0.999
	                    && moltiplica[2] >= 0.999;
	if (!neutro) {
		uint16_t tab[3][COLORE_GRADINI];
		for (int canale = 0; canale < 3; canale++) {
			for (int i = 0; i < COLORE_GRADINI; i++) {
				double v = (double)i / (COLORE_GRADINI - 1);
				v *= moltiplica[canale];
				if (v < 0.0) v = 0.0;
				if (v > 1.0) v = 1.0;
				tab[canale][i] = (uint16_t)(v * 65535.0 + 0.5);
			}
		}
		nuova = wlr_color_transform_init_lut_3x1d(COLORE_GRADINI,
			tab[0], tab[1], tab[2]);
		if (nuova == NULL) {
			snprintf(risposta, n, "no non riesco a costruire la tabella "
				"dei colori");
			return;
		}
	}

	// La vecchia si lascia DOPO aver preso la nuova: fra le due righe c'è un
	// fotogramma, e uno schermo che per un fotogramma non ha nessuna tinta
	// lampeggia.
	if (m->tinta != NULL)
		wlr_color_transform_unref(m->tinta);
	m->tinta = nuova;
	for (int i = 0; i < 3; i++)
		m->tinta_rgb[i] = moltiplica[i];

	// La strada si torna a chiedere: uno schermo collegato dopo, o rimesso
	// in piedi, può rispondere diversamente da quello di prima.
	{
		struct schermo *sc;
		wl_list_for_each(sc, &m->schermi_elenco, link)
			sc->tinta_strada = 0;
	}

	// ── Chiedere un fotogramma non basta: bisogna SPORCARE ───────────────
	//
	// La scena ridisegna solo quello che è cambiato, e cambiare la tabella
	// dei colori non cambia nessun pixel: il conto dei danni resta vuoto, la
	// scena consegna il fotogramma di prima, e la tinta non si vede mai.
	//
	// Costato un giro intero il 26 agosto 2026 — il verbo rispondeva «ok», e
	// tre fotografie di fila davano pixel identici byte per byte. Sembrava
	// che la trasformazione non funzionasse; funzionava, e non veniva
	// disegnata.
	//
	// `wlr_damage_ring_add_whole` dice «tutto lo schermo è da rifare», che è
	// la verità: una tabella di colore nuova cambia OGNI pixel.
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link) {
		if (!s->out->enabled)
			continue;
		struct wlr_scene_output *so =
			wlr_scene_get_scene_output(m->scena, s->out);
		if (so != NULL)
			wlr_damage_ring_add_whole(&so->damage_ring);
		wlr_output_schedule_frame(s->out);
	}

	snprintf(risposta, n, "ok");
}

void minerva_comando(struct minerva *m, const char *riga,
                     char *risposta, size_t n) {
	char copia[4096];
	snprintf(copia, sizeof(copia), "%s", riga);
	char *resto = copia;

	const char *verbo = parola(&resto);
	if (verbo == NULL) {
		snprintf(risposta, n, "no riga vuota");
		return;
	}
	if (strcmp(verbo, "sospendi") == 0) {
		if (getenv("MINERVA_PROVA") || !sonno_pronto(m->sonno)) {
			snprintf(risposta, n, "no sospensione non disponibile in prova o senza logind protetto");
			return;
		}
		if (access("/etc/pam.d/liquid-de", R_OK)) {
			snprintf(risposta, n, "no servizio PAM di blocco assente"); return;
		}
		if (!m->sospendi_timer) m->sospendi_timer =
			wl_event_loop_add_timer(m->loop, sospendi_scaduta, m);
		if (!m->sospendi_timer) { snprintf(risposta, n, "no timer sospensione non disponibile"); return; }
		wl_event_source_timer_update(m->sospendi_timer, 3000);
		m->sospendi_pendente = true;
		proteggi_sonno(m);
		snprintf(risposta, n, "ok");
		return;
	}

	// ── Le domande ────────────────────────────────────────────────────
	if (strcmp(verbo, "finestre") == 0) {
		comando_finestre(m, risposta, n);
		return;
	}
	if (strcmp(verbo, "schermi") == 0) {
		comando_schermi(m, risposta, n);
		return;
	}
	// Singolare e plurale, di nuovo: `schermi` è la domanda, `schermo` è
	// l'ordine. Vedi la nota su `scrivania`/`scrivanie` qui sotto.
	if (strcmp(verbo, "schermo") == 0) {
		comando_schermo(m, resto, NULL, risposta, n);
		return;
	}
    if (strcmp(verbo, "prova-monitor-rimuovi") == 0) {
        const char *test = getenv("MINERVA_PROVA");
        char *name = parola(&resto);
        struct schermo *s = name ? schermo_da_nome(m, name) : NULL;
        if (!test || strcmp(test, "1") || !s || !wlr_output_is_headless(s->out) || parola(&resto)) {
            snprintf(risposta, n, "no disponibile solo per output headless di prova"); return;
        }
        wlr_output_destroy(s->out);
        snprintf(risposta, n, "ok"); return;
    }
    if (strcmp(verbo, "monitori-prova") == 0) {
        comando_monitori(m, resto, risposta, n); return;
    }
    if (strcmp(verbo, "monitori-conferma") == 0 || strcmp(verbo, "monitori-annulla") == 0) {
        char *id = parola(&resto);
        if (!m->monitor_transaction || !id || strcmp(id, m->monitor_transaction->id) || parola(&resto)) {
            snprintf(risposta, n, "no configurazione monitor non trovata"); return;
        }
        if (strcmp(verbo, "monitori-conferma") == 0) monitor_transaction_free(m);
        else monitor_transaction_restore(m);
        snprintf(risposta, n, m->monitor_transaction ? "no ripristino in corso" : "ok"); return;
    }
	if (strcmp(verbo, "schermo-prova") == 0) {
		char *id = parola(&resto);
		if (!id || !id[0] || strlen(id) >= 80) { snprintf(risposta, n, "no identificativo prova non valido"); return; }
		comando_schermo(m, resto, id, risposta, n);
		return;
	}
	if (strcmp(verbo, "schermo-conferma") == 0 || strcmp(verbo, "schermo-annulla") == 0) {
		char *id = parola(&resto), *nome = parola(&resto);
		struct schermo *s = nome ? schermo_da_nome(m, nome) : NULL;
		if (!s || !id || !s->prova_timer || strcmp(id, s->prova_id)) {
			snprintf(risposta, n, "no prova scaduta o diversa"); return;
		}
		if (strcmp(verbo, "schermo-conferma") == 0) schermo_fine_prova(s);
		else schermo_ripristina(s);
		snprintf(risposta, n, "ok");
		return;
	}
	if (strcmp(verbo, "colore") == 0) {
		comando_colore(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "dispositivi") == 0) {
		comando_dispositivi(m, risposta, n);
		return;
	}
	if (strcmp(verbo, "tastiera") == 0) {
		comando_tastiera(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "ripetizione") == 0) {
		comando_ripetizione(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "sensibilita") == 0) {
		comando_sensibilita(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "touchpad") == 0) {
		comando_touchpad(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "dispositivo") == 0) {
		comando_dispositivo(m, resto, risposta, n);
		return;
	}
	// Attenzione al plurale: `scrivanie` è una DOMANDA (quali ci sono),
	// `scrivania` è un ORDINE (vai lì). Una lettera di differenza, e sono i
	// due versi opposti della stessa porta — per questo stanno lontane nel
	// file e vicine in questo commento.
	if (strcmp(verbo, "scrivanie") == 0) {
		comando_scrivanie(m, risposta, n);
		return;
	}
	// ── La sorveglianza dell'inattività ──────────────────────────────
	//
	//     inattivita 300 600 900   →  ok    (tre soglie, in secondi)
	//     inattivita               →  ok    (spenta: non si annuncia più)
	//
	// Chiederla è mestiere della shell, che è dove sta la politica: vedi il
	// blocco di commenti sui campi `inattivo_*` in `struct minerva`.
	if (strcmp(verbo, "inattivita") == 0) {
		if (inattivo_imposta(m, resto)) {
			snprintf(risposta, n, "ok %d", m->inattivo_quante);
		} else {
			snprintf(risposta, n, "no soglie: numeri di secondi "
				"positivi e in ordine crescente, al massimo %d",
				MINERVA_SOGLIE_INATTIVITA);
		}
		return;
	}
	// ── Dire una cosa a schermo ──────────────────────────────────────
	//
	//     messaggio 30000 Minerva: l'interfaccia non riparte.
	//     messaggio 0                          (toglie quello che c'è)
	//
	// Il tempo in millisecondi, poi il testo fino a fine riga. Serve a chi
	// deve parlare quando la scrivania non c'è più: vedi i campi `cartello*`
	// in `struct minerva`.
	if (strcmp(verbo, "messaggio") == 0) {
		char *quanto = parola(&resto);
		if (quanto == NULL) {
			snprintf(risposta, n, "no messaggio <millisecondi> <testo>");
			return;
		}
		char *fine = NULL;
		const long ms = strtol(quanto, &fine, 10);
		if (fine == quanto || ms < 0 || ms > 600000) {
			snprintf(risposta, n, "no i millisecondi vanno da 0 a 600000");
			return;
		}
		while (resto != NULL && (*resto == ' ' || *resto == '\t'))
			resto++;
		if (ms == 0 || resto == NULL || *resto == '\0') {
			cartello_via(m);
			snprintf(risposta, n, "ok");
			return;
		}
		if (cartello_mostra(m, resto, (int)ms))
			snprintf(risposta, n, "ok");
		else
			snprintf(risposta, n, "no non riesco a disegnare il cartello");
		return;
	}
	if (strcmp(verbo, "ciao") == 0) {
		snprintf(risposta, n, "ok minerva-wayland");
		return;
	}
	if (strcmp(verbo, "stato") == 0) {
		comando_stato(m, risposta, n);
		return;
	}
	// ── «danno»: il metro di quanto si ridipinge per niente ───────────
	//
	// Torna tre numeri: i pixel davvero ridipinti, quelli che sarebbero
	// stati ridipinti se ogni fotogramma sporcasse l'output intero, e i
	// fotogrammi. Il rapporto fra i primi due è la misura che conta:
	// col blur acceso oggi è 1,00 — cioè si ridipinge tutto lo schermo
	// per un orologio che cambia minuto — e il lavoro del danno
	// incrementale si giudica su questo numero, non a occhio.
	//
	// Un contatore e non una traccia sul registro: scrivere una riga per
	// fotogramma cambierebbe la cosa che si sta misurando.
	// «lista»: che cosa c'è nella lista da comporre del primo schermo.
	// Solo in prova — dice la geometria di tutte le finestre.
	if (strcmp(verbo, "lista") == 0) {
		if (getenv("MINERVA_PROVA") == NULL) {
			snprintf(risposta, n, "no «lista» esiste solo in prova (MINERVA_PROVA=1)");
			return;
		}
		struct schermo *s0 = wl_list_empty(&m->schermi_elenco) ? NULL
			: wl_container_of(m->schermi_elenco.next, s0, link);
		struct wlr_scene_output *so = s0 ? wlr_scene_get_scene_output(m->scena, s0->out) : NULL;
		if (so == NULL) {
			snprintf(risposta, n, "no nessuno schermo");
			return;
		}
		int k = snprintf(risposta, n, "ok ");
		if (k > 0 && (size_t)k < n)
			wlr_minerva_lista_descrivi(so, risposta + k, n - (size_t)k);
		return;
	}
	// ── «gpu acceso|spento»: il cronometro del disegno ─────────────────
	//
	// Il tempo totale finisce in `danno` (gpuNs, gpuFotogrammi): chi misura
	// ne fa la differenza fra due letture, come per i pixel.
	if (strcmp(verbo, "gpu") == 0) {
		char *v = parola(&resto);
		if (v == NULL || (strcmp(v, "acceso") != 0 && strcmp(v, "spento") != 0)) {
			snprintf(risposta, n, "no gpu vuole «acceso» o «spento»");
			return;
		}
		m->metro_gpu = strcmp(v, "acceso") == 0;
		snprintf(risposta, n, "ok %s", m->metro_gpu ? "acceso" : "spento");
		return;
	}
	if (strcmp(verbo, "danno") == 0) {
		uint64_t pixel = 0, schermo = 0, fotogrammi = 0;
		wlr_minerva_danno_conta(&pixel, &schermo, &fotogrammi);
		int x1, y1, x2, y2;
		wlr_minerva_danno_ultimo(&x1, &y1, &x2, &y2);
		uint64_t lista = 0, giri = 0, candidati = 0, diretti = 0;
		wlr_minerva_scanout_conta(&lista, &giri, &candidati, &diretti);
		snprintf(risposta, n,
			"ok {\"pixel\":%" PRIu64 ",\"schermo\":%" PRIu64
			",\"fotogrammi\":%" PRIu64 ",\"interi\":%" PRIu64 ",\"quota\":%.4f"
			",\"ultimo\":[%d,%d,%d,%d]"
			",\"lista\":%" PRIu64 ",\"giri\":%" PRIu64
			",\"candidati\":%" PRIu64 ",\"diretti\":%" PRIu64
			",\"fasce\":%" PRIu64
			",\"gpu\":%s,\"gpuNs\":%" PRIu64 ",\"gpuFotogrammi\":%" PRIu64
			",\"gpuPersi\":%" PRIu64 "}",
			pixel, schermo, fotogrammi, wlr_minerva_danno_interi(),
			schermo > 0 ? (double)pixel / (double)schermo : 0.0, x1, y1, x2, y2,
			lista, giri, candidati, diretti, wlr_minerva_danno_fasce(),
			m->metro_gpu ? "true" : "false", m->gpu_ns, m->gpu_fotogrammi,
			m->gpu_persi);
		return;
	}
	// ── Dov'è il puntatore ────────────────────────────────────────────
	//
	// Serve a una cosa sola, e si vede subito quando manca: il menù del
	// tasto destro si apre DOVE STA IL DITO, e per saperlo lo deve chiedere.
	// Sotto Hyprland lo faceva `hyprctl cursorpos`, che qui dentro non è
	// nessuno — quindi il menù cadeva sul suo ripiego e si apriva **in alto
	// a sinistra**, lontano dal punto in cui era stato chiesto.
	//
	// Il formato è quello di `hyprctl cursorpos` — «1211, 94» — di
	// proposito: chi legge la risposta è lo stesso pezzo di interfaccia per
	// tutti e due i compositori, e due formati vorrebbero dire due parser.
	// Sono PIXEL LOGICI, come tutto quello che esce da `wlr_cursor`: le
	// stesse coordinate in cui ragiona la superficie che disegna il menù.
	if (strcmp(verbo, "csd") == 0) {
		comando_csd(m, resto);
		snprintf(risposta, n, "ok %d", m->quanti_csd);
		return;
	}
	if (strcmp(verbo, "aspetto") == 0) {
		comando_aspetto(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "cornice") == 0) {
		comando_cornice(m, resto, risposta, n);
		return;
	}
	// ── «elastico»: quanto tremano le finestre ──────────────────────────
	//
	//     elastico 0        spento
	//     elastico 1        normale
	//     elastico 2.5      molto
	//
	// Il numero è una FORZA e vale il contrario di quel che sembra dentro:
	// più forza vuol dire molla più morbida, quindi più ritardo e più
	// rimbalzo. Fuori, sul cursore delle Impostazioni, è quello che uno si
	// aspetta — «quanto tremano» — e la traduzione sta in `src/molla.c`.
	//
	// Il tetto è tre, e non è timidezza: a forza tre il ritardo trascinando
	// arriva a ottanta pixel, cioè la finestra sembra staccata dal dito. Più
	// in là non è un effetto più forte, è un difetto.
	// `molla <rigidità> <smorzamento>`: il carattere dell'elastico. Qui c'era
	// anche `sfocatura <0-100>`, l'intensità del blur, tolto col blur.
	if (strcmp(verbo, "molla") == 0) {
		char *first = parola(&resto), *second = parola(&resto), *end = NULL;
		const double a = first ? strtod(first, &end) : NAN;
		if (!first || end == first || *end || !isfinite(a) || a < 0.5 || a > 2) {
			snprintf(risposta, n, "no parametro fuori intervallo");
			return;
		}
		const double b = second ? strtod(second, &end) : NAN;
		if (!second || end == second || *end || !isfinite(b) || b < 0.15 || b > 0.95
		    || parola(&resto)) {
			snprintf(risposta, n, "no parametri non validi");
			return;
		}
		m->rigidita = a;
		m->smorzamento = b;
		snprintf(risposta, n, "ok");
		return;
	}
    if (strcmp(verbo, "elastico") == 0) {
		char *quanto = parola(&resto);
		if (quanto == NULL) {
			snprintf(risposta, n, "no elastico vuole una forza da 0 a 3");
			return;
		}
		char *fine = NULL;
		const double v = strtod(quanto, &fine);
		if (fine == quanto || *fine != '\0' || !(v >= 0.0) || v > 3.0) {
			snprintf(risposta, n, "no la forza sta fra 0 e 3, non «%s»",
				quanto);
			return;
		}
		m->voluto_elastico = v;
		elastico_imposta(m, elastico_disegnato(m));
		snprintf(risposta, n, "ok %.2f", m->voluto_elastico);
		return;
	}
	if (strcmp(verbo, "effetto") == 0) {
		comando_effetto(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "risparmio") == 0) {
		comando_risparmio(m, resto, risposta, n);
		return;
	}
	// ── «aggancia»: lo stesso gesto del bordo, ma chiedibile ────────────
	//
	// Non è un comodo per le prove messo lì per fare prima. Lo snap era
	// raggiungibile **solo** premendo dei tasti o trascinando col mouse:
	// nessuno dei due si può fare da uno script, quindi «le finestre finiscono
	// nel posto giusto?» era una domanda senza risposta misurabile.
	//
	// Passa per `aggancia_attiva`, cioè per lo stesso codice della scorciatoia
	// e dello stesso `aggancio.c` del trascinamento: se questo verbo dice che
	// va bene, va bene anche col dito. Un verbo che facesse il conto per conto
	// suo proverebbe sé stesso e nient'altro.
	if (strcmp(verbo, "aggancia") == 0) {
		char *dove = parola(&resto);
		if (dove == NULL) {
			snprintf(risposta, n, "no aggancia vuole una zona: l, r, cima, "
				"alto-sx, alto-dx, basso-sx, basso-dx");
			return;
		}
		struct finestra *att = finestra_attiva(m);
		if (att == NULL) {
			snprintf(risposta, n, "no aggancia: nessuna finestra attiva");
			return;
		}
		aggancia_attiva(m, dove);
		struct wlr_box b;
		finestra_box(att, &b);
		snprintf(risposta, n, "ok %d %d %d %d", b.x, b.y, b.width, b.height);
		return;
	}
	if (strcmp(verbo, "lente") == 0) {
		comando_lente(m, resto, risposta, n);
		return;
	}
	if (strcmp(verbo, "puntatore") == 0) {
		snprintf(risposta, n, "ok %d, %d",
			(int)m->cursore->x, (int)m->cursore->y);
		return;
	}

	// ── «dito»: un puntatore finto, SOLO in prova ───────────────────────
	//
	//     dito 400 300          si sposta lì (coordinate della scrivania)
	//     dito premi            tasto sinistro giù
	//     dito lascia           tasto sinistro su
	//     dito premi destro     lo stesso col destro (e «lascia destro»)
	//
	// Una sessione senza schermo (`WLR_BACKENDS=headless`) non ha nessun
	// mouse, e un trascinamento — l'aggancio, l'elastico, il wobbly, il
	// trascinamento dei file — non si può provare in nessun altro modo che
	// guardando qualcuno farlo. È esattamente la mancanza che l'audit del 13
	// settembre 2026 segnalava: «manca una prova end-to-end del trascinamento
	// nella sessione completa».
	//
	// Passa dagli STESSI gestori del mouse vero (`cursore_aggiorna`,
	// `cursore_premuto`): se il verbo dice che funziona, funziona anche col
	// dito. Un verbo che rifacesse il conto per conto suo proverebbe sé
	// stesso e nient'altro — è la stessa regola di «aggancia», poco sopra.
	//
	// E fuori da una prova NON esiste: un canale che muove il mouse di chi
	// sta lavorando è una cosa che nessuno ha chiesto.
	// `respiro si|no`: le finestre nascono, si riducono e tornano col respiro
	// (vedi `respiro_avvia`), oppure a scatto.
	if (strcmp(verbo, "respiro") == 0) {
		char *come = parola(&resto);
		if (come != NULL && (strcmp(come, "si") == 0 || strcmp(come, "sì") == 0))
			m->respiro_acceso = true;
		else if (come != NULL && strcmp(come, "no") == 0)
			m->respiro_acceso = false;
		else {
			snprintf(risposta, n, "no respiro vuole «si» o «no»");
			return;
		}
		snprintf(risposta, n, "ok");
		return;
	}

	// `mercurio si|no`: le finestre vicine si fondono (vedi
	// `mercurio_aggiorna`), oppure restano forme separate.
	if (strcmp(verbo, "mercurio") == 0) {
		char *come = parola(&resto);
		if (come != NULL && (strcmp(come, "si") == 0 || strcmp(come, "sì") == 0))
			m->mercurio_acceso = true;
		else if (come != NULL && strcmp(come, "no") == 0)
			m->mercurio_acceso = false;
		else {
			snprintf(risposta, n, "no mercurio vuole «si» o «no»");
			return;
		}
		mercurio_aggiorna(m);
		snprintf(risposta, n, "ok");
		return;
	}

	// `riva super|sempre`: con una finestra che riempie lo schermo, la riva
	// (angoli, bordi, spinte, la barra dello schermo intero) risponde solo
	// con Super giù, oppure sempre. Vedi `riva_libera`.
	if (strcmp(verbo, "riva") == 0) {
		char *come = parola(&resto);
		if (come != NULL && strcmp(come, "super") == 0)
			m->riva_col_consenso = true;
		else if (come != NULL && strcmp(come, "sempre") == 0)
			m->riva_col_consenso = false;
		else {
			snprintf(risposta, n, "no riva vuole «super» o «sempre»");
			return;
		}
		snprintf(risposta, n, "ok");
		return;
	}

	// ── La tastiera finta, solo in prova ─────────────────────────────────
	//
	// `tasto <nome> premi|lascia`: come `dito` per il puntatore. Crea una
	// tastiera DENTRO il compositore e le fa premere il tasto; il tasto passa
	// da `tastiera_tasto`, cioè dagli stessi gestori della tastiera vera —
	// scorciatoie, tocco, «tieni», inghiottiti. Serve a provare Super tenuto
	// premuto senza toccare la tastiera di chi lavora (la tastiera finta di
	// `/dev/uinput` scriverebbe nella sessione vera).
	if (strcmp(verbo, "tasto") == 0) {
		if (getenv("MINERVA_PROVA") == NULL) {
			snprintf(risposta, n, "no «tasto» esiste solo in prova (MINERVA_PROVA=1)");
			return;
		}
		char *nome = parola(&resto);
		char *come = parola(&resto);
		if (nome == NULL || come == NULL
				|| (strcmp(come, "premi") != 0 && strcmp(come, "lascia") != 0)) {
			snprintf(risposta, n, "no tasto vuole «<nome> premi|lascia»");
			return;
		}
		static struct wlr_keyboard finta;
		static const struct wlr_keyboard_impl finta_impl = { .name = "minerva-prova" };
		static bool pronta = false;
		if (!pronta) {
			wlr_keyboard_init(&finta, &finta_impl, "minerva-prova");
			tastiera_nuova(m, &finta.base);
			// Senza dirlo al posto di lavoro, i programmi non sanno che c'è
			// una tastiera e non ne chiedono una: i tasti arrivavano alle
			// scorciatoie ma a nessun programma.
			wlr_seat_set_capabilities(m->seat,
				m->seat->capabilities | WL_SEAT_CAPABILITY_KEYBOARD);
			pronta = true;
		}
		xkb_keysym_t cercato = xkb_keysym_from_name(nome, XKB_KEYSYM_CASE_INSENSITIVE);
		if (cercato == XKB_KEY_NoSymbol || finta.keymap == NULL) {
			snprintf(risposta, n, "no il tasto «%s» non esiste", nome);
			return;
		}
		cercato = xkb_keysym_to_lower(cercato);
		uint32_t codice = 0;
		const xkb_keycode_t primo = xkb_keymap_min_keycode(finta.keymap);
		const xkb_keycode_t ultimo = xkb_keymap_max_keycode(finta.keymap);
		for (xkb_keycode_t k = primo; k <= ultimo && codice == 0; k++) {
			const xkb_keysym_t *sim = NULL;
			int q = xkb_keymap_key_get_syms_by_level(finta.keymap, k, 0, 0, &sim);
			for (int i = 0; i < q; i++)
				if (xkb_keysym_to_lower(sim[i]) == cercato)
					codice = k - 8;
		}
		if (codice == 0) {
			snprintf(risposta, n, "no «%s» non è su questa tastiera", nome);
			return;
		}
		struct timespec ts;
		clock_gettime(CLOCK_MONOTONIC, &ts);
		struct wlr_keyboard_key_event e = {
			.time_msec = (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000),
			.keycode = codice,
			.update_state = true,
			.state = strcmp(come, "premi") == 0
				? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED,
		};
		wlr_keyboard_notify_key(&finta, &e);
		snprintf(risposta, n, "ok %u", codice);
		return;
	}

	if (strcmp(verbo, "dito") == 0) {
		if (getenv("MINERVA_PROVA") == NULL) {
			snprintf(risposta, n, "no «dito» esiste solo in prova (MINERVA_PROVA=1)");
			return;
		}
		char *a = parola(&resto);
		if (a == NULL) {
			snprintf(risposta, n, "no dito vuole «x y», «premi» o «lascia»");
			return;
		}
		struct timespec ts;
		clock_gettime(CLOCK_MONOTONIC, &ts);
		const uint32_t tempo = (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
		if (strcmp(a, "premi") == 0 || strcmp(a, "lascia") == 0) {
			char *quale = parola(&resto);
			struct wlr_pointer_button_event e = {
				.pointer = NULL,
				.time_msec = tempo,
				.button = (quale != NULL && strcmp(quale, "destro") == 0)
					? BTN_RIGHT : BTN_LEFT,
				.state = strcmp(a, "premi") == 0
					? WL_POINTER_BUTTON_STATE_PRESSED
					: WL_POINTER_BUTTON_STATE_RELEASED,
			};
			cursore_premuto(&m->cursore_premuto, &e);
			wlr_seat_pointer_notify_frame(m->seat);
			snprintf(risposta, n, "ok");
			return;
		}
		char *b = parola(&resto);
		char *fa = NULL, *fb = NULL;
		const double x = strtod(a, &fa);
		const double y = b != NULL ? strtod(b, &fb) : 0;
		if (b == NULL || fa == a || *fa != '\0' || fb == b || *fb != '\0') {
			snprintf(risposta, n, "no dito vuole due numeri, non «%s %s»",
				a, b != NULL ? b : "");
			return;
		}
		wlr_cursor_warp_closest(m->cursore, NULL, x, y);
		// Oltre un bordo di lato è una spinta: quanto oltre, tanto spinge.
		bordo_spinto(m, x - m->cursore->x, tempo);
		cursore_aggiorna(m, tempo);
		wlr_seat_pointer_notify_frame(m->seat);
		snprintf(risposta, n, "ok %d, %d",
			(int)m->cursore->x, (int)m->cursore->y);
		return;
	}

	// ── I verbi che non riguardano una finestra sola ──────────────────

	// Il tema e la misura del puntatore sono UNA cosa sola: il gestore dei
	// cursori si crea con tutti e due insieme, e non c'è modo di cambiarne
	// uno lasciando l'altro. È la stessa ragione per cui in
	// `core/Compositore.qml` la funzione ne prende due.
	//
	// Il vecchio gestore si butta DOPO aver messo su il nuovo: buttarlo
	// prima vorrebbe dire un istante con il cursore che punta a un tema
	// distrutto, e quell'istante è quando si ridisegna.
	if (strcmp(verbo, "cursore") == 0) {
		char *tema = parola(&resto);
		char *mis = parola(&resto);
		int misura = mis != NULL ? atoi(mis) : 24;
		if (misura <= 0 || misura > 512)
			misura = 24;
		struct wlr_xcursor_manager *nuovo = wlr_xcursor_manager_create(
			(tema != NULL && strcmp(tema, "") != 0) ? tema : NULL,
			misura);
		if (nuovo == NULL) {
			snprintf(risposta, n, "no tema del puntatore non caricato");
			return;
		}
		struct wlr_xcursor_manager *vecchio = m->cursore_tema;
		m->cursore_tema = nuovo;
		wlr_cursor_set_xcursor(m->cursore, m->cursore_tema, "default");
		if (vecchio != NULL)
			wlr_xcursor_manager_destroy(vecchio);
		snprintf(risposta, n, "ok");
		return;
	}

	// ── Cambiare scrivania ────────────────────────────────────────────
	//
	// `scrivania 3`, `scrivania avanti`, `scrivania indietro`. I due nomi al
	// posto del numero sono il gesto della rotellina sopra i pallini della
	// barra, e saltano le scrivanie vuote — come `workspace e+1` di
	// Hyprland, che è la riga che la shell manda dall'altra parte.
	if (strcmp(verbo, "scrivania") == 0) {
		char *dove = parola(&resto);
		if (dove == NULL) {
			snprintf(risposta, n, "no manca il numero della scrivania");
			return;
		}
		if (strcmp(dove, "avanti") == 0 || strcmp(dove, "indietro") == 0) {
			scrivania_vicina(m, strcmp(dove, "avanti") == 0);
			snprintf(risposta, n, "ok %d", m->scrivania_attiva);
			return;
		}
		int quale = atoi(dove);
		if (quale < 1 || quale > SCRIVANIE) {
			snprintf(risposta, n, "no le scrivanie vanno da 1 a %d", SCRIVANIE);
			return;
		}
		scrivania_vai(m, quale);
		snprintf(risposta, n, "ok %d", m->scrivania_attiva);
		return;
	}

	// ── Registrare le scorciatoie ─────────────────────────────────────
	//
	//     scorciatoie azzera
	//     scorciatoia SUPER K - minerva:cheatsheet
	//     scorciatoia SUPER+SHIFT 1 - porta-a-scrivania:1
	//     scorciatoia - XF86AudioRaiseVolume bloccato minerva:volume-su
	//     scorciatoia SUPER+SHIFT RETURN - avvia:alacritty -e htop
	//
	// Quattro campi e poi **tutto il resto della riga è l'azione**. Il flag
	// sta in mezzo e non in fondo apposta: l'argomento di `avvia` è una riga
	// di comando intera, e un flag in coda sarebbe indistinguibile
	// dall'ultima parola del comando.
	//
	// `azzera` prima di rimandarle tutte: è l'unico modo per far sparire una
	// scorciatoia tolta dalla sorgente. Aggiungere e basta vorrebbe dire una
	// tabella che cresce a ogni ricarica, con dentro le regole di ieri.
	if (strcmp(verbo, "scorciatoie") == 0) {
		char *che = parola(&resto);
		if (che != NULL && strcmp(che, "azzera") == 0) {
			m->quante_scorciatoie = 0;
			snprintf(risposta, n, "ok");
		} else {
			snprintf(risposta, n, "ok %d", m->quante_scorciatoie);
		}
		return;
	}

	if (strcmp(verbo, "scorciatoia") == 0) {
		if (m->quante_scorciatoie >= SCORCIATOIE_MAX) {
			snprintf(risposta, n, "no non ci stanno più scorciatoie");
			return;
		}
		char *mods = parola(&resto);
		char *tasto = parola(&resto);
		char *flag = parola(&resto);
		char *azione = resto;
		while (*azione == ' ')
			azione++;
		if (mods == NULL || tasto == NULL || flag == NULL
				|| *azione == '\0') {
			snprintf(risposta, n,
				"no serve: scorciatoia <modificatori> <tasto> <flag> "
				"<azione>");
			return;
		}

		struct scorciatoia s = {0};
		// I modificatori: `SUPER+SHIFT`, oppure `-` per nessuno.
		for (const char *p = mods; *p != '\0';) {
			if (strncmp(p, "SUPER", 5) == 0) {
				s.modificatori |= WLR_MODIFIER_LOGO; p += 5;
			} else if (strncmp(p, "SHIFT", 5) == 0) {
				s.modificatori |= WLR_MODIFIER_SHIFT; p += 5;
			} else if (strncmp(p, "CTRL", 4) == 0) {
				s.modificatori |= WLR_MODIFIER_CTRL; p += 4;
			} else if (strncmp(p, "ALT", 3) == 0) {
				s.modificatori |= WLR_MODIFIER_ALT; p += 3;
			} else {
				p++;
			}
		}

		// Il nome del tasto è quello di XKB — `k`, `slash`, `F1`,
		// `XF86AudioRaiseVolume` — cioè lo stesso vocabolario della sorgente
		// di Minerva, che è nato per Hyprland e usa gli stessi nomi. Si
		// riduce a minuscolo perché il confronto avviene sul simbolo al
		// livello zero, che per le lettere è minuscolo.
		xkb_keysym_t sim = xkb_keysym_from_name(tasto,
			XKB_KEYSYM_CASE_INSENSITIVE);
		if (sim == XKB_KEY_NoSymbol) {
			snprintf(risposta, n, "no il tasto «%s» non esiste", tasto);
			return;
		}
		s.tasto = xkb_keysym_to_lower(sim);

		// I flag arrivano attaccati col `+`, come i modificatori:
		// `-`, `bloccato`, `rilascio`, `bloccato+rilascio`.
		s.anche_bloccato = strstr(flag, "bloccato") != NULL;
		s.al_rilascio = strstr(flag, "rilascio") != NULL;
		// `tocco` = premuto e lasciato DA SOLO. Tira dentro `rilascio`: un
		// tocco è per definizione una cosa che si riconosce quando il tasto
		// si rialza, e lasciarli separati vorrebbe dire che scrivendo solo
		// `tocco` la scorciatoia si registra, si mangia il tasto e non scatta
		// mai — cioè il difetto silenzioso che questo progetto ha già pagato
		// con `al-rilascio` mancante sull'Alt+Tab.
		s.da_solo = strstr(flag, "tocco") != NULL;
		if (s.da_solo)
			s.al_rilascio = true;
		s.tenuto = strstr(flag, "tieni") != NULL;

		// `azione:argomento`, e l'argomento è tutto quello che resta —
		// spazi compresi, perché per `avvia` è una riga di comando.
		char *duepunti = strchr(azione, ':');
		if (duepunti != NULL) {
			*duepunti = '\0';
			snprintf(s.argomento, sizeof(s.argomento), "%s", duepunti + 1);
		}
		snprintf(s.azione, sizeof(s.azione), "%s", azione);

		m->scorciatoie[m->quante_scorciatoie++] = s;
		snprintf(risposta, n, "ok %d", m->quante_scorciatoie);
		return;
	}

	// Chiudere la sessione. Si chiede al ciclo di eventi di finire — la
	// stessa strada del segnale di arresto — invece di uscire di qui: da
	// lì in poi si passa per l'uscita normale, `canale_chiudi()`
	// compreso, e il socket non resta a terra a far credere a chi arriva
	// dopo che ci sia ancora un compositore.
	if (strcmp(verbo, "esci") == 0) {
		snprintf(risposta, n, "ok");
		wl_display_terminate(m->display);
		return;
	}

	// ── I verbi sulle finestre ────────────────────────────────────────
	//
	// Tutti prendono un indirizzo, e per tutti «nessun indirizzo» vuol dire
	// «quella attiva» — che è la convenzione già usata da
	// `core/Compositore.qml`, dove `_bersaglio("")` non aggiunge niente.
	static const char *sulle_finestre[] = {
		"fuoco", "davanti", "chiudi", "sposta", "ridimensiona",
		"ingrandisci", "schermointero", "riduci", "portaascrivania", NULL
	};
	bool e_sulle_finestre = false;
	for (int i = 0; sulle_finestre[i] != NULL; i++) {
		if (strcmp(verbo, sulle_finestre[i]) == 0) {
			e_sulle_finestre = true;
			break;
		}
	}

	if (!e_sulle_finestre) {
		snprintf(risposta, n, "no verbo «%s» sconosciuto", verbo);
		return;
	}

	char *chi = parola(&resto);
	bool per_indirizzo = chi != NULL && strcmp(chi, "attiva") != 0;
	struct finestra *f = per_indirizzo ? finestra_da_indirizzo(m, chi)
	                                   : finestra_attiva(m);
	if (f == NULL) {
		// ── Il verbo si dice, e non è pignoleria ─────────────────────
		//
		// Il 1º settembre 2026, nel registro di una sessione vera, questa
		// riga compariva otto volte in una giornata — sempre uguale, e
		// senza il verbo. Vuol dire che qualcosa che la scrivania ha
		// chiesto **non è successo**, e non c'era modo di sapere cosa:
		// chiudere una finestra? metterla a fuoco da un clic sulla dock?
		// portarla su un'altra scrivania?
		//
		// Un rifiuto che non dice cosa è stato rifiutato è quasi un
		// silenzio, ed è la forma di guasto che questo progetto insegue
		// da mesi: l'azione parte, sparisce, e sullo schermo non cambia
		// niente.
		if (per_indirizzo)
			snprintf(risposta, n,
				"no «%s»: nessuna finestra con l'indirizzo %s",
				verbo, chi);
		else
			snprintf(risposta, n,
				"no «%s»: nessuna finestra attiva", verbo);
		return;
	}

	if (strcmp(verbo, "fuoco") == 0) {
		fuoco_finestra(m, f);
	} else if (strcmp(verbo, "davanti") == 0) {
		wlr_scene_node_raise_to_top(&f->cornice->node);
	} else if (strcmp(verbo, "chiudi") == 0) {
		finestra_di_chiuditi(f);
	} else if (strcmp(verbo, "sposta") == 0) {
		char *sx = parola(&resto);
		char *sy = parola(&resto);
		if (sx == NULL || sy == NULL) {
			snprintf(risposta, n, "no sposta vuole x e y");
			return;
		}
		// ── Spostare NON è ridimensionare ────────────────────────
		//
		// Qui c'era `finestra_box` + `finestra_posiziona`: si rileggeva
		// la misura di adesso e la si rimandava indietro insieme alla
		// posizione. Sembra innocuo e non lo è: fra il momento in cui si
		// CHIEDE una misura nuova e quello in cui il programma la
		// accetta passa del tempo, e in mezzo `finestra_box` risponde
		// ancora con quella vecchia. Rimandarla indietro **annulla il
		// ridimensionamento appena chiesto**.
		//
		// La shell ingrandisce così, in due comandi attaccati:
		//
		//     ridimensiona <finestra> 1916 952
		//     sposta       <finestra> 2 46
		//
		// e il secondo cancellava il primo. Risultato: «ingrandisci»
		// spostava la finestra nell'angolo in alto a sinistra e la
		// lasciava della misura di prima. Giacomo, 5 settembre 2026:
		// «poi impostazioni non si può massimizzare la finestra».
		//
		// `finestra_muovi` esiste apposta — «spostarla soltanto, senza
		// toccarne la misura» — ed è quello che questo verbo ha sempre
		// voluto dire.
		int mx = 0, my = 0;
		if (!numero(sx, &mx) || !numero(sy, &my)) {
			snprintf(risposta, n, "no sposta vuole due numeri, e «%s %s» non "
				"lo sono", sx, sy);
			return;
		}
		finestra_muovi(f, mx, my);
	} else if (strcmp(verbo, "ridimensiona") == 0) {
		char *sw = parola(&resto);
		char *sh = parola(&resto);
		if (sw == NULL || sh == NULL) {
			snprintf(risposta, n, "no ridimensiona vuole larghezza e altezza");
			return;
		}
		int w = atoi(sw), h = atoi(sh);
		// Una finestra di larghezza zero o negativa non è piccola: è una
		// finestra che sparisce senza modo di riprenderla, perché non c'è più
		// niente su cui cliccare.
		if (w < 60 || h < 40) {
			snprintf(risposta, n, "no misura troppo piccola (minimo 60x40)");
			return;
		}
		struct wlr_box b;
		finestra_box(f, &b);
		finestra_posiziona(f, b.x, b.y, w, h);
	} else if (strcmp(verbo, "ingrandisci") == 0) {
		char *v = parola(&resto);
		finestra_ingrandisci(f, v == NULL ? !f->ingrandita : parola_vera(v));
	} else if (strcmp(verbo, "schermointero") == 0) {
		char *v = parola(&resto);
		finestra_schermo_intero(f, v == NULL ? !f->schermo_intero : parola_vera(v));
	} else if (strcmp(verbo, "portaascrivania") == 0) {
		// `portaascrivania <finestra> <numero> [silenzioso]`. «Silenzioso»
		// vuol dire mandarla là senza andarci dietro — è la stessa parola
		// che usa `core/Compositore.qml`, e la stessa distinzione che fa
		// Hyprland fra `movetoworkspace` e `movetoworkspacesilent`.
		char *dove = parola(&resto);
		char *zitto = parola(&resto);
		int quale = dove != NULL ? atoi(dove) : 0;
		if (quale < 1 || quale > SCRIVANIE) {
			snprintf(risposta, n, "no le scrivanie vanno da 1 a %d", SCRIVANIE);
			return;
		}
		scrivania_porta(f, quale, !(zitto != NULL && parola_vera(zitto)));
	} else if (strcmp(verbo, "riduci") == 0) {
		char *v = parola(&resto);
		finestra_riduci(f, v == NULL ? !f->ridotta : parola_vera(v));
	}

	snprintf(risposta, n, "ok");
}

// ══════════════════════════════════════════════════════════════════════════
// Il blocco schermo
// ══════════════════════════════════════════════════════════════════════════
//
// `ext-session-lock-v1`. È il pezzo in cui un errore non si vede: un blocco
// che non blocca sembra identico a uno che blocca, finché qualcuno non ci
// prova.
//
// ── La regola che rende un blocco un blocco ──────────────────────────────
//
// **Se il programma del blocco muore, lo schermo resta bloccato.** Non è un
// caso limite: è la ragione per cui il protocollo esiste. Con un blocco fatto
// di una finestra normale basta ucciderne il processo da un'altra console per
// rientrare nella sessione; qui il compositore tiene la tenda anche quando
// dall'altra parte non c'è più nessuno, e l'unica strada per uscire è che il
// client mandi `unlock_and_destroy` — cioè che qualcuno abbia digitato la
// password giusta.
//
// Lo dice anche `scripts/minerva-blocca`, che per questo si rifiuta di
// bloccare se non trova un file PAM: meglio uno schermo non bloccato di uno
// bloccato per sempre.
//
// ── Perché una tenda nera ────────────────────────────────────────────────
//
// Perché se il client muore mentre lo schermo è bloccato non resta nessuna
// superficie da disegnare, e senza la tenda si vedrebbe la scrivania sotto —
// bloccata all'ingresso ma leggibile. Una posta elettronica aperta si legge
// benissimo anche senza poterla toccare.
//
// ── Perché non basta disegnare sopra ─────────────────────────────────────
//
// Perché l'ingresso non passa dal disegno. Si spengono gli altri piani della
// scena: la scena è anche ciò su cui si cerca «che cosa c'è sotto il
// puntatore», quindi un piano spento non riceve nemmeno i clic. E il fuoco
// della tastiera si porta a mano sulla superficie del blocco, perché la
// tastiera non guarda la scena.

/// Una superficie del blocco, con il suo pezzo di scena e i suoi ascolti.
///
/// Una per schermo: il protocollo vuole che il client ne crei una per ogni
/// monitor, e uno schermo senza la sua superficie resterebbe scoperto.
struct blocco_superficie {
	struct minerva *m;
	struct wlr_session_lock_surface_v1 *sup;
	struct wlr_scene_tree *albero;
	struct wl_listener distrutta;
	struct wl_listener commessa;
};

/// Accende o spegne tutto quello che NON è il blocco.
static void blocco_mostra_tenda(struct minerva *m, bool bloccato) {
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link) {
		s->blocco_presentato = false;
		s->blocco_attesa = false;
		if (bloccato && s->out->enabled) wlr_output_schedule_frame(s->out);
	}
	wlr_scene_node_set_enabled(&m->piano[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND]->node, !bloccato);
	wlr_scene_node_set_enabled(&m->piano[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM]->node, !bloccato);
	wlr_scene_node_set_enabled(&m->finestre->node, !bloccato);
	wlr_scene_node_set_enabled(&m->piano[ZWLR_LAYER_SHELL_V1_LAYER_TOP]->node, !bloccato);
	wlr_scene_node_set_enabled(&m->piano_intero->node, !bloccato);
	wlr_scene_node_set_enabled(&m->piano[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY]->node, !bloccato);
	wlr_scene_node_set_enabled(&m->piano_blocco->node, bloccato);
}

/// La tenda grande quanto tutti gli schermi messi insieme.
static void blocco_ridimensiona_tenda(struct minerva *m) {
	if (m->tenda == NULL)
		return;
	struct wlr_box tutto;
	wlr_output_layout_get_box(m->schermi, NULL, &tutto);
	// Senza schermi il rettangolo torna vuoto: si tiene comunque una tenda
	// non nulla, o al primo schermo che si riaccende ci sarebbe un istante
	// di scrivania visibile.
	if (tutto.width <= 0 || tutto.height <= 0) {
		tutto.width = 1920;
		tutto.height = 1080;
	}
	wlr_scene_node_set_position(&m->tenda->node, tutto.x, tutto.y);
	wlr_scene_rect_set_size(m->tenda, tutto.width, tutto.height);
}

static void proteggi_sonno(void *data) {
	struct minerva *m = data;
	if (!m->bloccato) {
		m->bloccato = true;
		blocco_ridimensiona_tenda(m);
		blocco_mostra_tenda(m, true);
		fuoco_tastiera(m, NULL);
		wlr_seat_pointer_notify_clear_focus(m->seat);
		annuncia_blocco(m);
	}
	if (!m->serratura) avvia_programma("minerva-blocca");
	blocco_verifica_presentazione(m);
}

static int sospendi_scaduta(void *data) {
	struct minerva *m = data;
	if (m->sospendi_pendente) {
		m->sospendi_pendente = false;
		wlr_log(WLR_ERROR, "minerva: sospensione annullata, protezione degli output non confermata");
	}
	return 0;
}

static void blocco_verifica_presentazione(struct minerva *m) {
	if (!m->bloccato) return;
	struct schermo *s;
	wl_list_for_each(s, &m->schermi_elenco, link) {
		if (s->out->enabled && !s->blocco_presentato) return;
	}
	if (m->serratura && !m->locked_inviato) {
		m->locked_inviato = true;
		wlr_session_lock_v1_send_locked(m->serratura);
	}
	sonno_protetto(m->sonno);
	if (m->sospendi_pendente) {
		m->sospendi_pendente = false;
		wl_event_source_timer_update(m->sospendi_timer, 0);
		if (sonno_pronto(m->sonno)) avvia_programma("systemctl suspend");
	}
}

/// Il fuoco alla prima superficie del blocco che ci sia.
static void blocco_dai_il_fuoco(struct minerva *m) {
	if (m->serratura == NULL)
		return;
	struct wlr_session_lock_surface_v1 *sup;
	wl_list_for_each(sup, &m->serratura->surfaces, link) {
		if (sup->surface->mapped) {
			fuoco_tastiera(m, sup->surface);
			return;
		}
	}
}

static void serratura_superficie_distrutta(struct wl_listener *l, void *dati) {
	(void)dati;
struct blocco_superficie *bs = wl_container_of(l, bs, distrutta);
	wl_list_remove(&bs->distrutta.link);
	wl_list_remove(&bs->commessa.link);
	// L'albero della scena lo distrugge wlroots insieme alla superficie.
	free(bs);
}

static void serratura_superficie_commessa(struct wl_listener *l, void *dati) {
	(void)dati;
struct blocco_superficie *bs = wl_container_of(l, bs, commessa);

	// ── «locked» si manda DOPO, e non prima ─────────────────────────
	//
	// Mandarlo all'arrivo della serratura vorrebbe dire dire al client «ci
	// penso io» quando sullo schermo non c'è ancora niente: fra quel
	// momento e la prima superficie disegnata resterebbe un lampo di
	// scrivania, ed è esattamente il lampo in cui si legge quello che c'era
	// aperto.
	if (bs->m->serratura == NULL || !bs->sup->surface->mapped)
		return;
	blocco_verifica_presentazione(bs->m);
	// Il fuoco invece si ridà a ogni commit utile: la prima superficie che
	// si mappa può non essere quella che resta, e una tastiera appesa a una
	// superficie sparita è uno schermo bloccato che non accetta la password.
	blocco_dai_il_fuoco(bs->m);
}

static void serratura_superficie(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, serratura_superficie);
	struct wlr_session_lock_surface_v1 *sup = dati;

struct blocco_superficie *bs = calloc(1, sizeof(*bs));
	if (bs == NULL)
		return;
	bs->m = m;
	bs->sup = sup;
	bs->albero = wlr_scene_subsurface_tree_create(m->piano_blocco,
	                                             sup->surface);

	// Ogni superficie sta sul SUO schermo, e ci sta esatta: una superficie
	// di blocco più piccola dello schermo lascia una striscia di scrivania
	// scoperta, e una più grande nasconde l'altro monitor.
	struct wlr_box b = {0};
	wlr_output_layout_get_box(m->schermi, sup->output, &b);
	if (bs->albero != NULL)
		wlr_scene_node_set_position(&bs->albero->node, b.x, b.y);
	wlr_session_lock_surface_v1_configure(sup, b.width > 0 ? b.width : 1920,
	                                      b.height > 0 ? b.height : 1080);

	bs->distrutta.notify = serratura_superficie_distrutta;
	wl_signal_add(&sup->events.destroy, &bs->distrutta);
	bs->commessa.notify = serratura_superficie_commessa;
	wl_signal_add(&sup->surface->events.commit, &bs->commessa);
}

static void serratura_sblocca(struct wl_listener *l, void *dati) {
	(void)dati;
	struct minerva *m = wl_container_of(l, m, serratura_sblocca);

	// Qui, e SOLO qui, si torna a vedere la scrivania: `unlock` lo manda il
	// client dopo che la password è stata verificata. Non lo manda la morte
	// del client, non lo manda un segnale.
	m->bloccato = false;
	m->sospendi_pendente = false;
	blocco_mostra_tenda(m, false);
	annuncia_blocco(m);
	fuoco_alla_prossima(m);
}

static void serratura_morta(struct wl_listener *l, void *dati) {
	(void)dati;
	struct minerva *m = wl_container_of(l, m, serratura_morta);
	wl_list_remove(&m->serratura_superficie.link);
	wl_list_remove(&m->serratura_sblocca.link);
	wl_list_remove(&m->serratura_morta.link);
	m->serratura = NULL;

	// Se `bloccato` è ancora vero il client è MORTO senza sbloccare — un
	// guasto, o qualcuno che ha provato a uccidere il blocco per rientrare.
	// La tenda resta, e il fuoco resta tolto: da qui si esce solo da un'altra
	// console.
	if (m->bloccato) {
		wlr_log(WLR_ERROR, "minerva: il blocco schermo è morto senza "
			"sbloccare. Lo schermo RESTA bloccato.");
		fuoco_tastiera(m, NULL);
		blocco_mostra_tenda(m, true);
	}
}

static void serratura_nuova(struct wl_listener *l, void *dati) {
	struct minerva *m = wl_container_of(l, m, serratura_nuova);
	struct wlr_session_lock_v1 *serratura = dati;

	// Uno solo alla volta. Un secondo blocco sopra il primo darebbe due
	// superfici sullo stesso schermo e nessuna delle due saprebbe di essere
	// coperta: `scripts/minerva-blocca` lo evita già con `--no-duplicate`,
	// ma quello vale per i NOSTRI blocchi. Questa riga vale per tutti.
	if (m->serratura != NULL) {
		wlr_log(WLR_ERROR, "minerva: c'è già un blocco schermo: rifiuto "
			"il secondo");
		wlr_session_lock_v1_destroy(serratura);
		return;
	}

	m->serratura = serratura;
	m->bloccato = true;
	m->locked_inviato = false;
	blocco_ridimensiona_tenda(m);
	blocco_mostra_tenda(m, true);
	// Il fuoco si toglie SUBITO, prima ancora che il blocco disegni: fra
	// l'arrivo della serratura e la sua prima superficie passano dei
	// millisecondi, e in quei millisecondi la tastiera non deve poter
	// scrivere in quello che c'era aperto.
	fuoco_tastiera(m, NULL);
	annuncia_blocco(m);

	m->serratura_superficie.notify = serratura_superficie;
	wl_signal_add(&serratura->events.new_surface, &m->serratura_superficie);
	m->serratura_sblocca.notify = serratura_sblocca;
	wl_signal_add(&serratura->events.unlock, &m->serratura_sblocca);
	m->serratura_morta.notify = serratura_morta;
	wl_signal_add(&serratura->events.destroy, &m->serratura_morta);
	blocco_verifica_presentazione(m);
}

// ── La luce notturna, e chi la chiede da fuori ────────────────────────────
//
// `wlr-gamma-control` è il protocollo con cui un programma (gammastep,
// wlsunset) chiede di scaldare i colori dello schermo. Minerva la sua luce
// notturna non la chiede da fuori — se la fa da sé, col verbo `colore` — ma
// il protocollo resta, perché un programma che lo usa ha ragione di
// aspettarselo.
//
// Qui non c'è nessun gestore, ed è una correzione del 26 agosto 2026:
// `wlr_scene_set_gamma_control_manager_v1` lo fa applicare alla SCENA, cioè
// al renderer. Il gestore che c'era prima metteva la tabella sullo SCHERMO —
// la strada dell'hardware — e sul backend annidato il commit la rifiutava
// senza che nessuna prova potesse accorgersene. Dalla scena funziona su ogni
// backend, e la scena sa anche COMBINARLA con la nostra: gammastep e la luce
// notturna di Minerva insieme non si cancellano.
//
// Vedi `wlr_scene_set_gamma_control_manager_v1` in `main()`.

/// Un segnale di arresto: si chiede al ciclo di eventi di finire, invece di
/// morire dentro il gestore. Da lì in poi la strada è quella dell'uscita
/// normale — `canale_chiudi()` compreso, che è il punto.
static int esci_pulito(int segnale, void *dati) {
	(void)segnale;
	wl_display_terminate(dati);
	return 0;
}

/// ── Le pagine enormi, spente per tutta la sessione ────────────────────────
///
/// Giacomo, 28 settembre 2026: «esiste un modo per comprimere quei 69 MB
/// fissi ad app? […] andiamo alla radice del problema». La radice non era
/// Quickshell né Qt: era il kernel. Su CachyOS le pagine enormi trasparenti
/// stanno su `always`, e allora ogni area di memoria di ogni thread — il
/// malloc del filo di Wayland, quello di D-Bus, quello dei registri — prende
/// pagine da 2 MB appena ci si scrive un byte. Letto dentro una finestra
/// Quickshell vuota: quattro blocchi da 4 e 8 MB, zeri al 100 %, 1988 pagine
/// da 4 KB vuote su 2048, e tutte contate come occupate.
///
/// Misurato nella sessione di prova, con e senza:
///
///     finestra Quickshell vuota     46,3 → 23,8 MB
///     la shell                     144,9 → 99,6 MB
///     compositore + shell + demone 203,6 → 155,3 MB
///
/// `PR_SET_THP_DISABLE` vale per questo processo e per TUTTI quelli che
/// nascono da lui: la shell, il demone, le app, e i programmi che si aprono
/// dalla sessione. È per questo che sta qui, prima di lanciare chiunque. Chi
/// vuole le pagine enormi (un gioco che ne guadagna, da misurare) avvia la
/// sessione con MINERVA_PAGINE_ENORMI=1.
static void pagine_enormi_spente(void) {
	const char *detto = getenv("MINERVA_PAGINE_ENORMI");
	if (detto != NULL && strcmp(detto, "1") == 0) {
		fprintf(stderr, "minerva-wayland: pagine enormi LASCIATE ACCESE (MINERVA_PAGINE_ENORMI=1)\n");
		return;
	}
	if (prctl(PR_SET_THP_DISABLE, 1, 0, 0, 0) != 0)
		fprintf(stderr, "minerva-wayland: non riesco a spegnere le pagine enormi: %s\n",
			strerror(errno));
}

int main(int argc, char *argv[]) {
	pagine_enormi_spente();
	wlr_log_init(WLR_INFO, NULL);

	struct minerva m = {0};

	// La prima scrivania è la 1 e non la 0: `{0}` qui vorrebbe dire una
	// sessione che parte su una scrivania che non esiste, con ogni finestra
	// nuova su un numero e la barra che ne accende un altro. Le scrivanie di
	// Minerva si contano da uno perché così le nomina chi le usa — `$mod 1`.
	m.scrivania_attiva = 1;

	m.display = wl_display_create();
	if (m.display == NULL) {
		fprintf(stderr, "minerva: non riesco a creare il display Wayland\n");
		return 1;
	}
	m.loop = wl_display_get_event_loop(m.display);

	// Gli elenchi si preparano PRIMA di qualunque cosa possa aggiungerci
	// dentro. Una `wl_list` non inizializzata non dà errore: dà un puntatore
	// a caso seguito alla prima iterazione.
	wl_list_init(&m.finestre_elenco);
	wl_list_init(&m.fantasmi);
	wl_list_init(&m.sovrapposte);
	wl_list_init(&m.appoggiate);
	wl_list_init(&m.schermi_elenco);
	wl_list_init(&m.tastiere);
	wl_list_init(&m.puntatori);
	wl_list_init(&m.interruttori);

	// ── «Non detto» è -1, non zero ───────────────────────────────────────
	//
	// `calloc` mette a zero, e zero qui vorrebbe dire «spento»: il touchpad
	// nascerebbe senza tocco per cliccare e senza scorrimento naturale, cioè
	// con delle scelte che nessuno ha fatto. Finché la shell non parla, non
	// si tocca niente di quello che libinput ha deciso da sé.
	m.ingresso.scorrimento_naturale = -1;
	m.ingresso.tocco_e_clic = -1;
	m.tieni_quale = -1;
	m.respiro_acceso = true;
	m.mercurio_acceso = true;
	m.riva_col_consenso = true;
	m.ingresso.spento_mentre_scrivi = -1;

	// ── La lista di riserva di chi si disegna la barra da sé ─────────────
	//
	// Quella vera la manda la shell col verbo `csd`, letta da `settings.json`.
	// Ma fra l'accensione del compositore e la prima parola della shell passa
	// un secondo abbondante, e in quel secondo può già essersi aperto un
	// programma — la sessione riapre quello che c'era. Senza una riserva,
	// Chrome nascerebbe con DUE barre e se le terrebbe.
	//
	// Sono gli stessi nomi che stanno in `windows.csdApps`. Averli in due
	// posti qui è accettabile perché uno dei due è un ripiego di un secondo,
	// non una seconda verità: appena la shell parla, questa sparisce.
	{
		static const char *riserva[] = {
			"firefox", "chromium", "google-chrome", "brave-browser",
			"microsoft-edge", "thunderbird", "antigravity", "org.gnome.",
			"nautilus", "gnome-",
		};
		for (size_t i = 0; i < sizeof(riserva) / sizeof(riserva[0]); i++) {
			snprintf(m.csd[m.quanti_csd], sizeof(m.csd[0]), "%s", riserva[i]);
			m.quanti_csd++;
		}
	}
	// La tinta parte a NULL, che è il neutro: `calloc` ci pensa, ma dirlo
	// qui è dire che il neutro è «nessuna tabella» e non «una tabella che
	// non cambia niente».
	m.tinta = NULL;
	// E i tre moltiplicatori partono dal neutro, o `stato` direbbe «0 0 0»
	// — cioè uno schermo nero — a chi non ha ancora acceso niente.
	m.tinta_rgb[0] = m.tinta_rgb[1] = m.tinta_rgb[2] = 1.0;
	// La lente parte SPENTA, e va detto: è la riga che garantisce che il
	// percorso del disegno resti quello di sempre finché nessuno chiede
	// altro.
	m.lente_scala = 1.0;
	m.lente_avvisata = false;
	m.presa_pulsante = -1;

	// ── Il cambio che rompe ogni esempio vecchio ─────────────────────────
	//
	// In wlroots 0.20 questa vuole il CICLO DI EVENTI. Fino alla 0.18 voleva
	// il `wl_display`, e tutti gli esempi in circolazione fanno così.
	struct wlr_session *sessione = NULL;
	m.backend = wlr_backend_autocreate(m.loop, &sessione);
	if (m.backend == NULL) {
		fprintf(stderr, "minerva: nessun backend disponibile.\n"
			"Fuori da una sessione grafica serve WLR_BACKENDS=headless.\n");
		return 1;
	}

	// Il renderer del nostro wlroots: GLES2 di serie, perché è lì che ci
	// sono blur e angoli nativi. Chi mette WLR_RENDERER (vulkan, pixman)
	// viene rispettato — e perde gli effetti, come dice il registro sotto.
	if (!getenv("WLR_RENDERER")) setenv("WLR_RENDERER", "gles2", 0);
	m.renderer = wlr_renderer_autocreate(m.backend);
	if (m.renderer == NULL) {
		fprintf(stderr, "minerva: non riesco a preparare il disegno "
			"(controllare il renderer selezionato)\n");
		return 1;
	}
	m.allocator = wlr_allocator_autocreate(m.backend, m.renderer);
	if (m.allocator == NULL) {
		fprintf(stderr, "minerva: non riesco a preparare il disegno\n");
		return 1;
	}
	if (!wlr_renderer_init_wl_display(m.renderer, m.display)) {
		wlr_log(WLR_ERROR, "minerva: impossibile inizializzare i buffer Wayland del renderer");
		return 1;
	}
	if (!wlr_renderer_is_gles2(m.renderer)) {
		wlr_log(WLR_INFO, "minerva: renderer alternativo: blur e angoli nativi "
			"non ancora disponibili su questo percorso");
	}
	if (!wlr_presentation_create(m.display, m.backend, 2) || !wlr_minerva_timing_create(m.display)) {
		wlr_log(WLR_ERROR, "minerva: impossibile creare i protocolli di presentazione");
		return 1;
	}
	if (m.renderer->features.timeline && m.backend->features.timeline) {
		int drm_fd = wlr_renderer_get_drm_fd(m.renderer);
		if (drm_fd >= 0 && !wlr_linux_drm_syncobj_manager_v1_create(m.display, 1, drm_fd)) {
			wlr_log(WLR_ERROR, "minerva: impossibile attivare explicit sync");
			return 1;
		}
	}

	if (!wobbly_prepara(m.renderer, m.allocator))
		wlr_log(WLR_INFO, "minerva: precompilazione wobbly non disponibile");

	// ── Il minimo perché un programma possa disegnare qualcosa ───────────
	//
	// `wlr_compositor` porta `wl_surface`, che è il fondamento di tutto: senza
	// non esiste nessuna finestra. Le altre due sono altrettanto obbligatorie
	// e si dimenticano facilmente, perché il loro difetto non è un errore —
	// è un programma che si comporta male: senza `subcompositor` i menu di
	// GTK finiscono nel posto sbagliato, senza `data_device` non funziona
	// copia-e-incolla né il trascinamento (cioè metà del gestore file).
	// Il puntatore si tiene: XWayland lo vuole, perché è a lui che deve
	// consegnare le superfici che i programmi X11 disegnano.
	struct wlr_compositor *compositore =
		wlr_compositor_create(m.display, 5, m.renderer);
	wlr_subcompositor_create(m.display);
	wlr_data_device_manager_create(m.display);

	// ── I protocolli che Minerva USA GIÀ, e che senza non danno errore ───
	//
	// Ognuno di questi manca a un pezzo di Minerva che oggi funziona sotto
	// Hyprland. Il modo in cui si rompono è sempre lo stesso, ed è il
	// peggiore: **niente**. Nessun messaggio, nessun errore in giornale — il
	// programma non trova il protocollo, si comporta come se la cosa non
	// esistesse, e chi guarda pensa che sia Minerva a essere rotta.
	//
	// Li elenco con quello che si rompe, perché fra un mese la riga da sola
	// non dirà più niente a nessuno.

	// Incollare col tasto centrale. È il gesto di chi lavora in un terminale
	// e non passa dagli appunti: selezioni e incolli, senza copiare.
	wlr_primary_selection_v1_device_manager_create(m.display);

	// Leggere e scrivere gli appunti da FUORI, senza avere una finestra a
	// fuoco. Lo usano `wl-copy`/`wl-paste` e ogni gestore di appunti: senza,
	// `wl-paste` resta muto e chi ci conta non capisce perché.
	wlr_ext_data_control_manager_v1_create(m.display, 1);

	// Le schermate. Minerva ha il suo pannello di Stamp (vedi la memoria
	// `minerva-schermate`) e sotto usa `grim`, che parla questo protocollo:
	// senza, «Stamp» non fotografa niente.
	wlr_screencopy_manager_v1_create(m.display);

	// Il cursore chiesto per FORMA e non per immagine («io qui voglio la
	// manina»). È come lo chiedono i programmi moderni; senza, restano col
	// cursore di prima e sembra che i collegamenti non siano cliccabili.
	//
	// E va ASCOLTATO: fino al 5 settembre 2026 lo annunciavamo e basta, e chi
	// nascondeva il puntatore non riusciva più a rimetterlo — vedi
	// `forma_cursore`.
	m.traccia_forma = getenv("MINERVA_TRACCIA_FORMA") != NULL;
	m.traccia_pulsanti = getenv("MINERVA_TRACCIA_PULSANTI") != NULL;
	m.traccia_menu = getenv("MINERVA_TRACCIA_MENU") != NULL;
	m.traccia_trascina = getenv("MINERVA_TRACCIA_TRASCINA") != NULL;
	struct wlr_cursor_shape_manager_v1 *forme =
		wlr_cursor_shape_manager_v1_create(m.display, 1);
	if (forme != NULL) {
		m.forma_richiesta.notify = forma_cursore;
		wl_signal_add(&forme->events.request_set_shape, &m.forma_richiesta);
	}

	// Il movimento RELATIVO del puntatore, senza posizione assoluta. Lo
	// vogliono i giochi e ogni cosa che guarda in giro trascinando.

	// Un buffer di un pixel di un colore solo. Sembra una curiosità ed è il
	// modo con cui i programmi disegnano gli sfondi pieni senza allocare
	// un'immagine intera.
	wlr_single_pixel_buffer_manager_v1_create(m.display);

	// «Non spegnere lo schermo mentre guardo un film». Aprire il protocollo
	// non basta: onorarlo è mestiere nostro, e si onora contando gli
	// inibitori vivi. Vedi `inibitore_nuovo`.
	struct wlr_idle_inhibit_manager_v1 *inibizione =
		wlr_idle_inhibit_v1_create(m.display);
	if (inibizione != NULL) {
		m.inibitore_nuovo.notify = inibitore_nuovo;
		wl_signal_add(&inibizione->events.new_inhibitor, &m.inibitore_nuovo);
	}

	// Da quanto non tocchi niente. Non spegne niente da sé: annuncia, e chi
	// ascolta decide — è il blocco schermo di Minerva che ascolta. Senza,
	// lo schermo non si blocca MAI da solo, che è un buco di sicurezza e non
	// una scomodità.
	m.inattivita = wlr_idle_notifier_v1_create(m.display);

	// Il timer della sorveglianza nostra. Nasce spento: finché la shell non
	// chiede delle soglie con `inattivita …`, qui non scatta niente. Un
	// compositore che decide da sé quando spegnere lo schermo è la stessa
	// cosa che si è rifiutata per il coperchio del portatile.
	m.ultima_attivita_ms = ora_ms();
	m.inattivo_timer = wl_event_loop_add_timer(m.loop, inattivo_scatta, &m);

	// La cornice attorno alla finestra attiva. Nasce SPENTA, come è nata
	// finora: chi non la chiede non deve accorgersi che esiste, e soprattutto
	// non deve pagarne il battito. Anche questo timer nasce fermo.
	m.cornice_modo = CORNICE_SPENTA;
	// Sei come la presa: è la misura con cui la cornice è nata, e cambiarla
	// di nascosto vorrebbe dire una scrivania diversa senza che nessuno
	// l'abbia chiesto.
	m.cornice_spessore = BORDO_PRESA;
	m.cornice_periodo = 8000;
	m.cornice_r = 0.13f;
	m.cornice_g = 0.83f;
	m.cornice_b = 0.93f;
	m.cornice_timer = wl_event_loop_add_timer(m.loop, cornice_scatta, &m);

	// ── L'elastico nasce SPENTO ─────────────────────────────────────────
	//
	// Come l'effetto vetro poche righe più sotto, e per la stessa ragione:
	// una scrivania che parte con le finestre che rimbalzano prima che
	// qualcuno l'abbia chiesto è una scrivania che ha deciso al posto tuo.
	// Lo accende la shell leggendo `windows.elastico`.
	//
	// Il timer si crea comunque, spento: crearlo alla prima presa vorrebbe
	// dire un `if` in mezzo al trascinamento, e un timer fermo non costa
	// niente — `wl_event_loop_add_timer` non lo arma.
	m.elastico = 0.0;
	m.rigidita = 1; m.smorzamento = 0.42;

	// L'effetto nasce SPENTO. Non è timidezza: una scrivania che parte con le
	// finestre trasparenti prima che qualcuno lo abbia chiesto è una scrivania
	// che sembra rotta, e chi non sa che l'impostazione esiste non sa nemmeno
	// dove spegnerla. Lo accende la shell, leggendo `windows.effetto`.
	//
	// 0,88 è lo stesso numero che le nostre finestre QML usavano già per conto
	// loro (`shell.windowOpacity` in `theme/Colors.qml`): partire da un valore
	// diverso vorrebbe dire che accendendo il vetro le finestre di Minerva
	// cambiano opacità e quelle degli altri no — cioè il difetto al contrario.
	m.effetto_modo = EFFETTO_NESSUNO;
	m.effetto_alfa = 0.88f;

	// Il risparmio nasce SPENTO, per la stessa ragione dell'effetto: lo
	// accende la shell leggendo `power.risparmioEffetti`. Una prova che non
	// lo chiede non se lo trova addosso perché il portatile è al 15 %.
	m.risparmio_modo = RISPARMIO_MAI;
	m.risparmio_soglia = 20;
	m.voluto_effetto = m.effetto_modo;
	m.voluto_cornice = m.cornice_modo;
	m.voluto_elastico = m.elastico;

	// La luce notturna che arriva da FUORI. Vedi il blocco «La luce
	// notturna, e chi la chiede da fuori» qui sopra.
	struct wlr_gamma_control_manager_v1 *gamma =
		wlr_gamma_control_manager_v1_create(m.display);

	// Il blocco schermo. Vedi il blocco di commenti sopra `serratura_nuova`:
	// è il pezzo in cui un errore non si vede, perché un blocco che non
	// blocca sembra identico a uno che blocca.
	struct wlr_session_lock_manager_v1 *serrature =
		wlr_session_lock_manager_v1_create(m.display);
	m.serratura_nuova.notify = serratura_nuova;
	wl_signal_add(&serrature->events.new_lock, &m.serratura_nuova);

	// ── I due protocolli senza cui la scala frazionaria non arriva ───────
	//
	// `wl_output.scale` è un INTERO: 1, 2, 3. Annunciando 1,25 wlroots
	// arrotonda a 2 per i client che non sanno fare di meglio, e succede
	// esattamente quello che si è misurato il 24 agosto 2026 con la shell
	// dentro il compositore:
	//
	//     schermo 1280x720 scala 1.25  →  la shell vede 640x360 (rapporto 2)
	//
	// cioè metà scrivania. Non è un difetto di arrotondamento: è che senza
	// `wp_fractional_scale_v1` la frazione non ha proprio un modo di passare.
	// Con lui il client riceve 1,25 e disegna 1024×576.
	//
	// `wp_viewporter` va insieme e non è facoltativo: è il protocollo con cui
	// il client dice «questo buffer va mostrato a QUESTA dimensione». Senza,
	// un client che disegna a 1,25 avrebbe un buffer di dimensioni non intere
	// da mostrare a dimensioni intere, e non c'è modo di dire come.
	//
	// Non c'è altro da scrivere: `wlr_scene_surface_create` implementa tutti e
	// due per conto nostro, manda la scala preferita a ogni superficie e
	// aggiorna quando la finestra passa su uno schermo con scala diversa. Al
	// compositore tocca soltanto ACCENDERLI — che è la ragione per cui questo
	// commento è più lungo delle due righe che spiega.
	wlr_viewporter_create(m.display);
	wlr_fractional_scale_manager_v1_create(m.display, 1);

	m.schermi = wlr_output_layout_create(m.display);
	m.scena = wlr_scene_create();
	m.scena_schermi = wlr_scene_attach_output_layout(m.scena, m.schermi);

	// ── E la gamma chiesta da fuori la fa applicare la SCENA ─────────────
	//
	// Prima c'era un nostro gestore che rispondeva a `set_gamma` mettendo la
	// tabella sullo SCHERMO. Funziona sul backend vero e **fallisce
	// sull'annidato**, per la stessa ragione della luce notturna: quella è la
	// strada dell'hardware. Da qui la applica il renderer, e la scena sa
	// anche combinarla con la nostra — così `gammastep` e la luce notturna
	// di Minerva insieme non si cancellano.
	//
	// **Qui e non dove si crea il manager**, che è quaranta righe più su: là
	// `m.scena` non esiste ancora, ed è NULL. Costato un segmentation fault
	// il 26 agosto 2026 — nessun avviso in compilazione, e il compositore
	// moriva subito dopo aver creato il renderer.
	wlr_scene_set_gamma_control_manager_v1(m.scena, gamma);

	// ── L'ordine dei piani si decide QUI, una volta ──────────────────────
	//
	// Nella scena chi nasce dopo sta sopra. Queste cinque righe sono, in
	// ordine, quello che si vede guardando lo schermo di taglio: lo sfondo,
	// la dock, le finestre, la barra, il blocco schermo.
	//
	// È il difetto che in Minerva è già costato: la scrivania con le icone
	// stava su «Layer level 1 (bottom)», e un rettangolo a tutto schermo lì
	// dentro finiva DIETRO ogni finestra senza dire niente.
	m.piano[ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND] =
		wlr_scene_tree_create(&m.scena->tree);
	m.piano[ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM] =
		wlr_scene_tree_create(&m.scena->tree);
	// I ponti di Mercurio: sotto TUTTE le finestre, sopra la scrivania.
	m.piano_mercurio = wlr_scene_tree_create(&m.scena->tree);
	m.finestre = wlr_scene_tree_create(&m.scena->tree);

	// ── L'ombra dell'aggancio ────────────────────────────────────────────
	//
	// Il rettangolo che si accende mentre trascini una finestra contro un
	// bordo, per dire dove andrà a finire. Sta SOPRA le finestre e non sotto:
	// sotto sarebbe coperto dalla finestra che stai trascinando e da tutte
	// quelle in mezzo, cioè invisibile proprio quando serve. È traslucido
	// apposta — deve indicare, non nascondere.
	//
	// ── Il colore va PREMOLTIPLICATO ─────────────────────────────────────
	//
	// Giacomo, 7 settembre 2026: «quel blu che compare come dimostrazione è
	// troppo forte e lo vorrei un pochino più trasparente e meno forte come
	// intensità».
	//
	// Non era una questione di gusto: era un difetto. `wlr_scene_rect_create`
	// vuole un colore **premoltiplicato per l'alfa** — sta scritto in una riga
	// dentro `wlr_scene.h`, «The color argument must be a premultiplied color
	// value» — e noi gli passavamo il colore pieno con l'alfa a fianco.
	// Risultato: disegnato quattro volte più intenso di quanto dicesse il
	// numero, e l'alfa scritta qui non voleva dire niente.
	//
	// Adesso la moltiplicazione è scritta, così cambiare `alfa` cambia davvero
	// quello che si vede — e 0,20 è 0,20.
	{
		static const float alfa = 0.20f;
		m.aggancio_ombra = wlr_scene_rect_create(&m.scena->tree, 1, 1,
			(float[4]){0.13f * alfa, 0.83f * alfa, 0.93f * alfa, alfa});
	}
	wlr_scene_node_set_enabled(&m.aggancio_ombra->node, false);

	m.piano[ZWLR_LAYER_SHELL_V1_LAYER_TOP] =
		wlr_scene_tree_create(&m.scena->tree);
	// ── Il piano dello schermo intero ────────────────────────────────────
	//
	// Fino al 23 settembre 2026 una finestra a schermo intero veniva
	// spostata DENTRO il piano dei pannelli (TOP), in cima. Ma i pannelli
	// si ridispongono, e la barra e la dock finivano di nuovo sopra di lei:
	// trasparenti, quindi non si vedevano — e bastavano a impedire lo
	// scanout diretto, che vuole UN elemento solo da mostrare. Col blur
	// peggio: i loro filtri, visibili, accendevano la lista completa, dodici
	// elementi per un film a schermo intero. Un piano suo, fra i pannelli e
	// gli avvisi, e la domanda «chi sta sopra» non ha più due risposte.
	m.piano_intero = wlr_scene_tree_create(&m.scena->tree);
	m.piano[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY] =
		wlr_scene_tree_create(&m.scena->tree);

	// ── L'icona che si trascina, sopra ogni finestra ─────────────────────
	//
	// Sopra «overlay», che è il piano più alto di layer-shell, perché durante
	// un trascinamento la cosa che conta è dove sta il dito: un'icona che
	// finisce sotto la barra mentre la si porta lassù è un'icona che sparisce
	// nel momento in cui serve. Sotto il blocco schermo, però — a schermo
	// bloccato non deve restare in volo niente.
	m.piano_trascinamento = wlr_scene_tree_create(&m.scena->tree);
	// Il cartello sta SOPRA le finestre e sotto il blocco schermo: è l'ultima
	// cosa che si può ancora dire, e finire dietro una finestra vorrebbe dire
	// non dirla. Sotto il blocco perché a schermo bloccato non si mostra
	// niente a chi non ha ancora messo la password.
	m.piano_cartello = wlr_scene_tree_create(&m.scena->tree);

	// ── E sopra tutto, il blocco schermo ─────────────────────────────────
	//
	// Sopra anche a «overlay», che è il piano più alto di layer-shell: se il
	// blocco stesse allo stesso livello della barra, basterebbe una notifica
	// per disegnarci sopra. Dentro c'è per prima la tenda nera, e sopra di lei
	// le superfici del blocco. Spento finché non serve.
	m.piano_blocco = wlr_scene_tree_create(&m.scena->tree);
	static const float nero[4] = {0.0f, 0.0f, 0.0f, 1.0f};
	m.tenda = wlr_scene_rect_create(m.piano_blocco, 1, 1, nero);
	wlr_scene_node_set_enabled(&m.piano_blocco->node, false);

	// ── Prima degli schermi, la configurazione degli schermi ─────────────
	//
	// Va letta QUI e non dentro `schermo_nuovo`: il backend annuncia gli
	// schermi nell'istante in cui parte, e leggere il file una volta per ogni
	// monitor vorrebbe dire aprirlo due volte su un computer con due schermi —
	// e, peggio, poter leggere due versioni diverse se qualcuno lo salva in
	// mezzo.
	schermi_leggi(&m.schermi_conf, NULL);
	if (m.schermi_conf.quanti > 0)
		wlr_log(WLR_INFO, "minerva: %d schermi configurati",
			m.schermi_conf.quanti);

	// ── E il protocollo che porta la DIMENSIONE LOGICA ──────────────────
	//
	// `wp_fractional_scale_v1` da solo non basta, e la misura del 24 agosto
	// 2026 lo dice senza margini: accesi viewporter e scala frazionaria, la
	// shell dentro il compositore continuava a vedere 640×360 su uno schermo
	// 1280×720 a 1,25.
	//
	// Il motivo è che la scala frazionaria è **per superficie**: dice a una
	// finestra a che risoluzione disegnare i propri pixel. Non dice a nessuno
	// quanto è grande la SCRIVANIA. Quella la porta `xdg-output-unstable-v1`,
	// e senza di lui un client la calcola da sé come «modo diviso la scala
	// intera di wl_output» — cioè 1280/2, perché `wl_output.scale` è un intero
	// e 1,25 arrotondato per eccesso fa 2.
	//
	// Tre protocolli quindi, e servono tutti e tre insieme: uno per la
	// dimensione della scrivania, uno per la nitidezza delle finestre, uno per
	// mostrare un buffer non intero. Ne manca uno e il sintomo è lo stesso —
	// tutto grande il doppio o piccolo di un quarto — il che rende difficile
	// capire quale.
	wlr_xdg_output_manager_v1_create(m.display, m.schermi);

	m.schermo_nuovo.notify = schermo_nuovo;
	wl_signal_add(&m.backend->events.new_output, &m.schermo_nuovo);

	// La versione 6 di xdg-shell è quella che porta i suggerimenti di
	// ridimensionamento: chiederne una più alta di quella che wlroots
	// implementa fa fallire la creazione, non degradare.
	m.xdg_shell = wlr_xdg_shell_create(m.display, 6);
	m.finestra_nuova.notify = finestra_nuova;
	wl_signal_add(&m.xdg_shell->events.new_toplevel, &m.finestra_nuova);
	// I menù. Senza questa riga il tasto destro non apre niente: vedi
	// `menu_nuovo`.
	m.menu_nuovo.notify = menu_nuovo;
	wl_signal_add(&m.xdg_shell->events.new_popup, &m.menu_nuovo);

	// ── Il protocollo per cui abbiamo scelto wlroots ─────────────────────
	//
	// ── Perché proprio la 4, letto dall'XML e non a memoria ──────────────
	//
	// Alla versione 4 arriva `keyboard_interactivity = on_demand`
	// (`protocolli/wlr-layer-shell-unstable-v1.xml`, riga 246), ed è
	// esattamente quello che i pannelli di Minerva chiedono: prendono i tasti
	// quando ci si clicca sopra, non appena compaiono. Dichiarare la 3 vuol
	// dire pannelli che non ricevono mai una lettera.
	//
	// La 5 aggiunge `set_exclusive_edge`, che non usiamo: chiederla vorrebbe
	// dire promettere qualcosa che non serve a nessuno.
	m.layer_shell = wlr_layer_shell_v1_create(m.display, 4);
	m.appoggiata_nuova.notify = appoggiata_nuova;
	wl_signal_add(&m.layer_shell->events.new_surface, &m.appoggiata_nuova);

	// ── Chi disegna la cornice ───────────────────────────────────────────
	//
	// Senza questo protocollo, Qt e GTK disegnano la loro barra del titolo e
	// si ritrovano sotto anche la nostra: è il difetto delle «due barre».
	m.decorazioni = wlr_xdg_decoration_manager_v1_create(m.display);
	m.decorazione_nuova.notify = decorazione_nuova;
	wl_signal_add(&m.decorazioni->events.new_toplevel_decoration,
		&m.decorazione_nuova);

	// ── Il posto: tastiera, puntatore, appunti ───────────────────────────
	//
	// Il nome «seat» è di Wayland e vuol dire una persona seduta davanti al
	// computer: una tastiera, un puntatore, un blocco appunti. Le capacità si
	// dichiarano quando arrivano i dispositivi, non adesso.
	m.seat = wlr_seat_create(m.display, "seat0");
	// ── Il puntatore si dichiara SUBITO, non al primo mouse ──────────────
	//
	// Le capacità del seat si aggiornavano solo in `dispositivo_nuovo`: senza
	// nessun dispositivo — cioè in una sessione `headless` — restavano a
	// ZERO, i programmi non chiedevano mai un `wl_pointer`, e nessun clic
	// finto del verbo `dito` poteva arrivare a nessuno. Il compositore
	// diceva «CONSEGNATO» e la shell non riceveva niente: trovato il 13
	// settembre 2026 con `WAYLAND_DEBUG=1` sulla shell, che mostrava
	// `wl_seat.capabilities(0)`. Il puntatore c'è sempre: è il cursore di
	// wlroots, con o senza un mouse dietro.
	wlr_seat_set_capabilities(m.seat, WL_SEAT_CAPABILITY_POINTER);

	// ── XWayland, e perché PIGRO ─────────────────────────────────────────
	//
	// `lazy = true` vuol dire che il server X non parte adesso: parte la
	// prima volta che un programma X11 prova a collegarsi. Su una sessione
	// in cui non si apre nessun programma X11 — che è la sessione normale di
	// Minerva — non si pagano né i suoi processi né la sua memoria.
	//
	// Va creato DOPO il posto (`m.seat`) o non avrebbe a chi dare la
	// tastiera, e il `DISPLAY` si scrive subito: il nome ce l'ha da adesso,
	// anche se il server dorme, ed è quello che un programma legge per
	// sapere dove bussare.
	m.xwayland = wlr_xwayland_create(m.display, compositore, true);
	if (m.xwayland == NULL) {
		// Non è fatale: si perde Steam, non la scrivania. Uno schermo nero
		// sarebbe peggio di una funzione in meno.
		fprintf(stderr, "minerva-wayland: XWayland NON avviato — "
			"i programmi X11 (Steam, i giochi, Wine) non si apriranno\n");
	} else {
		m.x_pronto.notify = xwayland_pronto;
		wl_signal_add(&m.xwayland->events.ready, &m.x_pronto);
		m.x_superficie_nuova.notify = xwayland_superficie_nuova;
		wl_signal_add(&m.xwayland->events.new_surface, &m.x_superficie_nuova);
		wlr_xwayland_set_seat(m.xwayland, m.seat);
		if (m.xwayland->display_name != NULL) {
			setenv("DISPLAY", m.xwayland->display_name, true);
			printf("minerva-wayland: XWayland su DISPLAY=%s\n",
				m.xwayland->display_name);
		}
	}

	m.cursore = wlr_cursor_create();
	m.puntatore = puntatore_crea(m.display, m.seat, m.cursore);
	if (!m.puntatore) {
		wlr_log(WLR_ERROR, "minerva: inizializzazione del puntatore fallita");
		return 1;
	}
	wlr_cursor_attach_output_layout(m.cursore, m.schermi);

	// 24 pixel è la misura di base; a schermo scalato 1,25 — come quello di
	// questo portatile — wlroots carica da sé la variante più grande, purché
	// il tema sappia di doverlo fare.
	m.cursore_tema = wlr_xcursor_manager_create(NULL, 24);

	m.dispositivo_nuovo.notify = dispositivo_nuovo;
	wl_signal_add(&m.backend->events.new_input, &m.dispositivo_nuovo);

	m.cursore_mosso.notify = cursore_mosso;
	wl_signal_add(&m.cursore->events.motion, &m.cursore_mosso);
	m.cursore_assoluto.notify = cursore_assoluto;
	wl_signal_add(&m.cursore->events.motion_absolute, &m.cursore_assoluto);
	m.cursore_premuto.notify = cursore_premuto;
	wl_signal_add(&m.cursore->events.button, &m.cursore_premuto);
	m.cursore_rotella.notify = cursore_rotella;
	wl_signal_add(&m.cursore->events.axis, &m.cursore_rotella);
	m.cursore_frame.notify = cursore_frame;
	wl_signal_add(&m.cursore->events.frame, &m.cursore_frame);
	m.cursore_richiesto.notify = cursore_richiesto;
	wl_signal_add(&m.seat->events.request_set_cursor, &m.cursore_richiesto);

	// Gli appunti, la selezione primaria e il trascinamento: vedi i gestori.
	m.selezione_richiesta.notify = selezione_richiesta;
	wl_signal_add(&m.seat->events.request_set_selection,
		&m.selezione_richiesta);
	m.selezione_primaria_richiesta.notify = selezione_primaria_richiesta;
	wl_signal_add(&m.seat->events.request_set_primary_selection,
		&m.selezione_primaria_richiesta);
	m.trascinamento_richiesto.notify = trascinamento_richiesto;
	wl_signal_add(&m.seat->events.request_start_drag,
		&m.trascinamento_richiesto);
	m.trascinamento_partito.notify = trascinamento_partito;
	wl_signal_add(&m.seat->events.start_drag, &m.trascinamento_partito);

	// ── Il socket si chiama «minerva-N», e non è civetteria ──────────────
	//
	// `wl_display_add_socket_auto` prende il primo `wayland-N` libero, e in
	// una sessione Hyprland il primo libero è `wayland-0` — cioè il nome a cui
	// si collega qualunque programma avviato senza `WAYLAND_DISPLAY`. Un
	// compositore di PROVA che si prende quel nome è una trappola: un giorno
	// una finestra qualsiasi si apre dentro la prova invece che nella
	// sessione vera, e la si cerca a lungo.
	//
	// Con un nome nostro chi ci vuole entrare deve dirlo:
	//
	//     WAYLAND_DISPLAY=minerva-0 alacritty
	char nome[32];
	const char *socket = NULL;
	for (int i = 0; i < 32 && socket == NULL; i++) {
		snprintf(nome, sizeof(nome), "minerva-%d", i);
		if (wl_display_add_socket(m.display, nome) == 0)
			socket = nome;
	}
	if (socket == NULL) {
		fprintf(stderr, "minerva: non riesco ad aprire il socket\n");
		wlr_backend_destroy(m.backend);
		return 1;
	}

	if (!wlr_backend_start(m.backend)) {
		fprintf(stderr, "minerva: il backend non parte\n");
		wlr_backend_destroy(m.backend);
		wl_display_destroy(m.display);
		return 1;
	}

	// Si stampa il socket e non lo si mette solo nell'ambiente: chi avvia
	// minerva-wayland da un terminale deve poterlo leggere per lanciarci
	// dentro un programma, e le prove ci si appoggiano.
	setenv("WAYLAND_DISPLAY", socket, true);
	printf("minerva-wayland: in ascolto su %s\n", socket);

	// ── Il canale di controllo ──────────────────────────────────────────
	//
	// Da qui la shell comanda: fuoco, chiudi, sposta, ingrandisci. Senza,
	// minerva-wayland disegna ma non si guida — è la metà che l'audit del 23
	// agosto 2026 aveva contato come mancante: «i 45 verbi di
	// core/Compositore.qml: nessuno arriva».
	//
	// Se non si apre, si va avanti lo stesso e si dice. Un compositore che si
	// rifiuta di partire perché non ha potuto creare un socket è uno schermo
	// nero, e uno schermo nero è sempre peggio di una funzione in meno.
	struct canale *canale = canale_apri(&m, m.loop, socket);
	m.canale = canale;
	if (canale != NULL) {
		setenv("MINERVA_CANALE", canale_percorso(canale), true);
		printf("minerva-wayland: canale su %s\n", canale_percorso(canale));
	} else {
		fprintf(stderr, "minerva-wayland: canale di controllo NON aperto — "
			"la shell disegnerà ma non potrà comandare le finestre\n");
	}
	fflush(stdout);
	// ── Il blocco prima del sonno ───────────────────────────────────────
	//
	// Solo su una sessione vera: le prove annidate non parlano con logind, e
	// non devono — una prova che prende un inibitore sul portatile di Giacomo
	// è una prova che gli impedisce di chiudere il coperchio.
	//
	// Se logind non c'è si avvisa e basta. La prima versione qui bloccava lo
	// schermo «per prudenza», cioè metteva la schermata di blocco davanti a
	// una sessione appena aperta perché un bus non aveva risposto: il perché
	// non si fa più sta in cima a `sonno.h`.
	//
	// ── E nemmeno sotto la schermata di accesso ──────────────────────────
	//
	// Dal 23 settembre 2026 questo compositore disegna anche il greeter
	// (`MINERVA_GREETER=1`, lo mette `scripts/minerva-greeter-sessione`). Lì
	// non c'è una sessione da proteggere — nessuno ha ancora fatto l'accesso
	// — e soprattutto non c'è nessuno che disegni la schermata di blocco:
	// la tenda calerebbe prima del sonno e al risveglio resterebbe il NERO,
	// davanti alla casella della password. Stessa cosa per la batteria: il
	// greeter non manda nessuna regola di risparmio, e ascoltarla sarebbe
	// un bus aperto per niente.
	const bool nel_greeter = getenv("MINERVA_GREETER") != NULL;
	if (nel_greeter)
		wlr_log(WLR_INFO, "minerva: sotto la schermata di accesso: "
			"niente blocco prima del sonno, niente batteria");

	if (sessione && !getenv("MINERVA_PROVA") && !nel_greeter) {
		m.sonno = sonno_crea(m.loop, proteggi_sonno, &m);
		if (!m.sonno)
			wlr_log(WLR_ERROR, "minerva: logind non raggiungibile: la "
				"sospensione da Minerva resta rifiutata");
	}

	// La batteria: stessa regola delle prove, una prova non guarda quella
	// vera. Senza bus si va avanti lo stesso — il modo «auto» non scatterà
	// mai per la batteria, e «sempre» funziona comunque.
	if (!getenv("MINERVA_PROVA") && !nel_greeter)
		m.energia = energia_crea(m.loop, energia_cambiata, &m);

	// Un programma da avviare subito, come fa `Hyprland -c` con `exec-once`:
	// serve alle prove per non dover aprire un terminale a mano.
	pid_t figlio_avvio = -1;
	if (argc > 1) {
		figlio_avvio = fork();
		if (figlio_avvio == 0) {
			execvp(argv[1], argv + 1);
			_exit(1);
		}
	}

	// ── E se quel programma finisce? ─────────────────────────────────────
	//
	// Di norma non ci si pensa: `minerva-dentro-wayland` finisce con `wait` e
	// resta vivo per tutta la sessione, quindi la domanda non si pone.
	//
	// Se la pone la **sessione di recupero**, che è tutta un'altra cosa: il
	// nostro compositore con dentro un terminale e nient'altro. Lì il figlio
	// È il terminale, e chiudendolo restava uno schermo nero. Trovato
	// dalla prova annidata il 1º settembre 2026, ed è il modo peggiore in cui
	// una via di fuga può fallire: ci si arriva perché qualcosa è già rotto,
	// si chiude la finestra, e si è bloccati davanti al nero senza sapere se
	// il computer è morto.
	//
	// ── Perché SU RICHIESTA e non sempre ─────────────────────────────────
	//
	// Perché nella sessione vera quel `wait` torna anche in un caso: se **sia**
	// il guardiano del demone **sia** quello della shell si arrendono (cinque
	// morti in due minuti, e allora smettono). Uscire lì vorrebbe dire portare
	// via anche le finestre di chi stava lavorando — un editor con del testo
	// non salvato — per un guasto che riguarda la scrivania, non loro.
	//
	// Quindi lo chiede chi sa di volerlo: `minerva-session-recupero` mette
	// `MINERVA_ESCI_COL_FIGLIO=1`, la sessione normale no.
	const char *esci_col_figlio = getenv("MINERVA_ESCI_COL_FIGLIO");
	struct wl_event_source *sig_chld = wl_event_loop_add_signal(m.loop,
		SIGCHLD, figlio_finito, &m);
	if (!sig_chld) {
		wlr_log(WLR_ERROR, "minerva: impossibile monitorare i processi figli");
		return 1;
	}
	if (figlio_avvio > 0 && esci_col_figlio != NULL
	    && strcmp(esci_col_figlio, "1") == 0) {
		m.figlio_avvio = figlio_avvio;
	} else if (figlio_avvio > 0) {
		figli_programmi[127] = figlio_avvio;
	}
	figlio_finito(0, &m);

	// ── Fermarsi bene, e perché è un requisito e non un vezzo ───────────
	//
	// Senza questi, un SIGTERM ferma il processo all'istante: `wl_display_run`
	// non torna, `canale_chiudi()` non viene chiamato, e **il file del socket
	// resta sul disco**. Un socket Unix è un file, e un file avanzato non dà
	// nessun errore a chi lo guarda: sembra un compositore acceso.
	//
	// Costato il 24 agosto 2026. Finita una prova annidata, il socket è
	// rimasto lì; il demone della sessione VERA l'ha visto, ha concluso che
	// girava minerva-wayland, e ha chiesto le finestre a un compositore morto.
	// Hyprland aveva un terminale aperto e la shell diceva `finestre=0`:
	// nessun errore, da nessuna parte, e una scrivania senza finestre.
	//
	// Il demone adesso controlla se qualcuno ASCOLTA davvero
	// (`/proc/net/unix`), che è la difesa giusta perché regge anche a un
	// SIGKILL. Questa è l'altra metà: non lasciare sporco quando si può
	// evitare.
	struct wl_event_source *sig_term =
		wl_event_loop_add_signal(m.loop, SIGTERM, esci_pulito, m.display);
	struct wl_event_source *sig_int =
		wl_event_loop_add_signal(m.loop, SIGINT, esci_pulito, m.display);
	struct wl_event_source *sig_hup =
		wl_event_loop_add_signal(m.loop, SIGHUP, esci_pulito, m.display);

	wl_display_run(m.display);
	energia_distruggi(m.energia);
	m.energia = NULL;
	sonno_distruggi(m.sonno);
	m.sonno = NULL;
	m.sospendi_pendente = false;
	if (m.sospendi_timer) wl_event_source_remove(m.sospendi_timer);

	if (sig_term != NULL)
		wl_event_source_remove(sig_term);
	if (sig_int != NULL)
		wl_event_source_remove(sig_int);
	if (sig_hup != NULL)
		wl_event_source_remove(sig_hup);

	// ── Staccare gli ascolti PRIMA di distruggere ────────────────────────
	//
	// Costato il 26 agosto 2026, e nel modo peggiore: `wlr_xwayland_destroy`
	// comincia con
	//
	//     assert(wl_list_empty(&xwayland->events.new_surface.listener_list));
	//
	// cioè pretende che chi lo distrugge si sia già tolto di mezzo. Con gli
	// ascolti ancora attaccati il processo **aborta qui**, e abortendo non
	// arriva a `canale_chiudi()`: il socket resta sul disco, e un socket
	// avanzato è un compositore che sembra acceso. È esattamente la trappola
	// per cui esiste tutto questo blocco di uscita pulita.
	//
	// L'ha trovata `prova-annunci.py`, con la riga «dopo SIGTERM il socket
	// non resta sul disco» — scritta mesi fa per un difetto diverso.
	//
	// E prima dei client, perché Xwayland È un client: distruggerlo dopo
	// vorrebbe dire smontarlo quando il display sotto di lui non c'è più.
	if (m.xwayland != NULL) {
		wl_list_remove(&m.x_pronto.link);
		wl_list_remove(&m.x_superficie_nuova.link);
		wlr_xwayland_destroy(m.xwayland);
		m.xwayland = NULL;
	}
	wl_display_destroy_clients(m.display);
	puntatore_distruggi(m.puntatore);
	m.puntatore = NULL;
	canale_chiudi(canale);
	// ── E il puntatore si azzera, o si annuncia a memoria liberata ──────
	//
	// `wl_display_destroy`, più sotto, distrugge gli schermi, e ogni schermo
	// che muore chiama `schermo_distrutto` → `annuncia_schermi` →
	// `canale_annuncia(m->canale, …)`: cioè legge dentro il canale appena
	// liberato. Con i clienti piccoli il blocco liberato restava
	// leggibile e nessuno se ne accorgeva; il 13 settembre 2026, con la coda
	// di uscita da 16 KB per cliente, il blocco è diventato grande abbastanza
	// da venire restituito al sistema — e ogni uscita del compositore
	// lasciava un coredump. Due su tre di quelli trovati quella sera erano
	// questo.
	m.canale = NULL;

	// ── E tutti gli altri ascolti sui protocolli ─────────────────────────
	//
	// Stessa assert di XWayland, e non è un caso: è una convenzione di
	// wlroots. Un manager creato sul display si smonta quando il display
	// muore, e comincia col controllare che nessuno stia più ascoltando —
	// perché un ascolto rimasto attaccato a un segnale che sta per sparire
	// è memoria altrui la prossima volta che qualcuno lo tocca.
	//
	// Non tutti i protocolli lo controllano, ma quelli che lo fanno lo fanno
	// con una `assert`, cioè con un core dump. Trovati uno alla volta il 26
	// agosto 2026 — luce notturna, poi blocco schermo — perché ognuno
	// abortiva prima di lasciar vedere il successivo. Si staccano tutti,
	// anche quelli che oggi non protestano: costa una riga e toglie una
	// classe intera di crolli all'uscita.
	//
	// Quello della luce notturna non è più in questo elenco perché non c'è
	// più un gestore nostro: se lo tiene la scena, e se lo stacca da sé.
	wl_list_remove(&m.serratura_nuova.link);
	wl_list_remove(&m.finestra_nuova.link);
	wl_list_remove(&m.menu_nuovo.link);
	wl_list_remove(&m.appoggiata_nuova.link);
	wl_list_remove(&m.decorazione_nuova.link);
	wl_list_remove(&m.cursore_richiesto.link);
	if (m.forma_richiesta.link.next != NULL)
		wl_list_remove(&m.forma_richiesta.link);
	wl_list_remove(&m.selezione_richiesta.link);
	wl_list_remove(&m.selezione_primaria_richiesta.link);
	wl_list_remove(&m.trascinamento_richiesto.link);
	wl_list_remove(&m.trascinamento_partito.link);
	wl_list_remove(&m.schermo_nuovo.link);
	wl_list_remove(&m.dispositivo_nuovo.link);
	if (m.inibitore_nuovo.notify != NULL)
		wl_list_remove(&m.inibitore_nuovo.link);
	if (m.inattivo_timer != NULL)
		wl_event_source_remove(m.inattivo_timer);
	if (m.angolo_timer)
		wl_event_source_remove(m.angolo_timer);
	if (m.bordo_alto_timer)
		wl_event_source_remove(m.bordo_alto_timer);
	if (m.cartello_timer != NULL)
		wl_event_source_remove(m.cartello_timer);
	if (sig_chld != NULL)
		wl_event_source_remove(sig_chld);

	wl_display_destroy(m.display);
	// Con `MINERVA_ESCI_COL_FIGLIO` si esce con l'esito del programma di
	// avvio: 0 se la schermata di accesso ha finito perché si è entrati.
	return m.esito_figlio;
}
