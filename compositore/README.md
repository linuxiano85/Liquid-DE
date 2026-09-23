# minerva-wayland

Il compositore di Minerva. Costruito su **wlroots 0.20**.

## Perché esiste

Giacomo, 19 agosto 2026: «voglio sradicare hyprland anche a costo di creare
tutti i suoi file da 0 [...] voglio solo minerva-wayland e non
minerva-hyprland-wayland. non voglio limiti imposti da hyprland».

Non è insofferenza: sono limiti che questo progetto ha **pagato**, uno per
uno, e che stanno scritti nella sua memoria.

- `transform()` ridisegna nella **stessa scatola** della finestra → le wobbly
  windows non possono strabordare, la gelatina viene tagliata;
- a una decorazione arrivano **solo pressione e rilascio**: niente movimento a
  tasto premuto, niente DRAG_START/END → il trascinamento della barra del
  titolo è passato per **quattro** tentativi;
- **il «riduci» non esiste**: Minerva lo finge con una scrivania di servizio, e
  Chrome si bloccava perché la sua richiesta `set_minimized` viene ignorata;
- l'ABI del plugin è legata al **commit hash** di Hyprland → a ogni
  aggiornamento le barre del titolo spariscono al login, in silenzio.

Ognuno di questi sparisce possedendo il compositore, e in nessun altro modo.

## Perché wlroots e non aquamarine

Sono due livelli diversi:

- **aquamarine** (quella che usa Hyprland) dà solo il **livello hardware**:
  DRM/KMS, sessione, input, GBM. Nessun protocollo — ed è il motivo per cui
  Hyprland ha **78 file** di soli protocolli;
- **wlroots** dà l'hardware **e i protocolli**: xdg-shell, seat, appunti,
  XWayland, session-lock, screencopy, e `wlr-layer-shell` — che è **suo**.

E qui sta il colpo di fortuna: la shell di Minerva usa `WlrLayershell` in **48
punti** e `wlr-screencopy` in uno. **Parla già la lingua di wlroots**, non
quella di Hyprland. L'unico pezzo davvero di Hyprland è `GlobalShortcut`, due
usi, già incartato in `core/Scorciatoia.qml`.

## Le due regole di questo cartello

Le stesse del plugin, e per la stessa ragione: sono già costate.

1. **Mai provarlo nella sessione vera.** Si prova annidato — un compositore
   dentro l'altro — che se cade porta con sé soltanto sé stesso. Il plugin è
   caduto due volte, e lì moriva un plugin; qui morirebbe lo schermo.
2. **Mai installare mentre una prova gira.** `cp` scrive sul posto: tronca e
   riempie, e il codice in esecuzione diventa spazzatura senza un messaggio.
   `costruisci.sh` scrive di fianco e **rinomina**, e si rifiuta di partire se
   trova un `minerva-wayland` vivo.

## Costruire e provare

    sudo pacman -S wlroots0.20   # una volta sola, l'unica dipendenza
    ./costruisci.sh              compila e installa in ~/.local/bin
    ./prova-annidata.sh      lo avvia con dentro la scrivania di Minerva

`prova-annidata.sh` forza `WLR_BACKENDS=wayland` e `MINERVA_PROVA=1`: la prima
riga è ciò che garantisce che resti annidato, la seconda è il contrassegno che
permette di chiuderlo senza rischiare di chiudere la sessione vera (si legge in
`/proc/PID/environ` prima di mandare un segnale).

Il socket si chiama **`minerva-N`**, non `wayland-N`. Non è civetteria:
`wl_display_add_socket_auto` prende il primo `wayland-N` libero, che in una
sessione Hyprland è `wayland-0` — cioè il nome a cui si collega qualunque
programma avviato senza `WAYLAND_DISPLAY`. Un compositore di prova che se lo
prende è una trappola che si paga dopo.

**L'XML del protocollo sta nel repository**, in `protocolli/`. wlroots
*implementa* layer-shell ma non ne installa la descrizione, e il suo header
comincia includendo un file che deve generare chi lo usa. Prenderlo da un
pacchetto esterno vorrebbe dire un compositore che si rifiuta di compilare
finché non installi qualcos'altro — cioè una dipendenza in più, per un file di
testo che non cambia mai. La copia è quella ufficiale di wlr-protocols.

## Stato

### Tappa 1 — Prima luce ✔ 19 agosto 2026

`minerva-wayland` parte annidato, accende lo schermo che trova e ci disegna
dentro una finestra vera.

**Le due trappole, tutte e due silenziose:**

**1. `wlr_backend_autocreate` vuole il CICLO DI EVENTI, non il display.**
Cambiato in wlroots 0.19; ogni esempio in circolazione è più vecchio e passa
il `wl_display`. È il motivo per cui le firme qui dentro sono state lette
dagli header installati, non ricordate.

**2. La configure iniziale la deve mandare il compositore, o non compare
niente.** In xdg-shell il programma non disegna finché non gli si dice «va
bene, e queste sono le tue misure». Da wlroots 0.18 c'è un campo apposta,
`initial_commit`, e chi non lo guarda lascia il programma ad aspettare per
sempre. Visto succedere: alacritty **vivo**, **collegato**, e la finestra non
c'era. Nessun errore, nessuna riga nel registro, solo uno schermo nero. Il
difetto peggiore non è quello che grida — è quello che aspetta.

### Tappa 2 — La scrivania di Minerva ci gira dentro ✔ 19 agosto 2026

**È il collaudo che decide tutto il resto, ed è passato.** La shell di Minerva,
**senza una riga cambiata**, dentro il nostro compositore: sfondo, barra in
cima con orologio e meteo, icone della scrivania, pannelli che si aprono.

    minerva: superficie appoggiata «minerva-wallpaper» sul piano 0
    minerva: superficie appoggiata «minerva-desktop»   sul piano 1
    minerva: superficie appoggiata «quickshell»        sul piano 2
    minerva: superficie appoggiata «minerva-gioco»     sul piano 3

Verificato a mano, non solo a registro: clic sull'orologio → si apre il
calendario, con la data giusta e i valori di memoria e temperatura letti dal
demone. E la tastiera: `touch prova-tastiera-arrivata` battuto in un alacritty
dentro il compositore, e il file è comparso.

**Che cosa c'è dentro adesso** — `wlr-layer-shell` (i quattro piani), il fuoco
(tastiera e puntatore, che in Wayland sono separati), `wlr_seat`, `wlr_cursor`
con il tema, XKB, e la richiesta di cursore dei clienti.

**L'ordine dei piani è la riga più delicata del file.** Nella scena chi nasce
dopo sta sopra, e l'ordine è: sfondo, dock, **finestre**, barra, blocco
schermo. Invertirne due vuol dire una barra che sparisce dietro le finestre —
difetto che in Minerva è già costato, ed è il motivo per cui la scrivania sta
su «Layer level 1». `scripts/prove.sh` adesso lo controlla, e la guardia è
stata provata su un file rotto apposta.

**Un difetto trovato per strada, che non è nostro:** le barre del titolo di
Minerva compaiono ma nel posto sbagliato, perché `TitleBars.qml` chiede le
misure delle finestre a Hyprland, che lì dentro non c'è. Risolto alla Tappa 4
qui sotto: adesso le barre le disegna il compositore.

**Una cosa che sembra un difetto e non lo è:** la dock non si vede perché è
impostata su `autoHide`.

### Tappe 3 e 4 — Le finestre, e la barra del titolo ✔ 23 agosto 2026

Giacomo, guardando la scrivania dentro il compositore: «non vedo la barra del
titolo o sbaglio?». Non sbagliava, e la risposta ha portato avanti la Tappa 4
insieme alla 3, perché erano lo stesso problema.

**La barra adesso è parte del compositore** (`src/barra.c`, disegnata con
cairo e pango). Non è un pannello appoggiato sopra la finestra che ne insegue
le misure: barra e finestra sono **lo stesso nodo della scena**, dentro un
albero che si chiama `cornice`. Quando la finestra si sposta, la barra non ha
niente da inseguire — si sposta perché è lei.

Misure e colori sono quelli del plugin, di proposito: 42 di altezza, 10 di
raggio, il fondo `#0B0F1A` della membrana, alfa 0,90 a fuoco e 0,70 spenta.
Un compositore diverso non deve sembrare una scrivania diversa.

**Provato a schermo**, non solo a registro: il titolo centrato, i quattro
pulsanti, la pastiglia che si accende sotto il puntatore (rossa su «chiudi»),
il trascinamento per la barra, il doppio clic che ingrandisce, «ingrandisci»
che ingrandisce **e torna indietro**, e il bordo che ridimensiona.

**Il bordo che ridimensiona era la domanda aperta**: è un `wlr_scene_rect`
completamente trasparente, sei pixel più grande della finestra, e non era
ovvio che `wlr_scene_node_at` lo considerasse cliccabile. Lo fa: la finestra
si è ristretta tirandola dal bordo destro.

#### I tre difetti trovati e sistemati

1. **Il compositore cadeva un secondo dopo l'avvio.**

       wlr_xdg_surface_schedule_configure: Assertion `surface->initialized'

   `xdg-decoration` è il protocollo con cui un programma chiede chi disegna la
   cornice, e rispondere «la disegno io» è **mandare una configure**. Ma il
   programma crea l'oggetto decorazione *prima* della prima commit della sua
   superficie: rispondere lì è scrivere a una superficie che non è ancora
   configurabile. Non è un avviso né un errore di ritorno — è un `assert`
   dentro wlroots, e si porta via tutto. La risposta ora passa sempre per
   `decorazione_applica`, che rimanda alla prima commit.

2. **Il titolo era centrato due volte** e usciva appiccicato ai pulsanti.
   `pango_layout_set_width` + `PANGO_ALIGN_CENTER` centrano già la riga;
   `pango_layout_get_pixel_size` però restituisce la larghezza del **testo**,
   non quella impostata, e lo scarto calcolato a mano si sommava a quello che
   Pango applicava per conto suo.

3. **La prova annidata poteva comandare la sessione vera.**
   `Quickshell.Hyprland` non cerca Hyprland: legge
   `HYPRLAND_INSTANCE_SIGNATURE` dall'ambiente, che la prova eredita per
   intero. La shell dentro minerva-wayland mandava i suoi comandi al **Hyprland
   di Giacomo** — regole delle finestre, `follow_mouse`, animazioni — mentre
   credevamo di provare un'altra scrivania. `prova-annidata.sh` adesso la
   toglie ed esporta `MINERVA_COMPOSITORE=minerva-wayland`. Senza la firma la
   shell parte lo stesso e si limita ad avvisare: conferma sul campo che
   l'unico pezzo davvero legato a Hyprland è `GlobalShortcut`.

#### Il freno: dove una finestra NON si può portare

Una finestra si sposta dove si vuole, tranne dove non si potrebbe più
riprendere. Sono due i modi di perderla, e Minerva li ha visti entrambi:
sotto il pannello della scrivania (il difetto per cui Giacomo scriveva «non
hanno la barra e devo chiuderle con super+C») e fuori dal bordo laterale. Il
tetto è quindi lo spazio **utile**, non lo schermo, e di lato devono restare
almeno 120 pixel. Il fondo invece resta libero: la barra è in cima, e da lì si
riprende comunque.

#### La via di ritorno, e quella che resta aperta

- **«riduci» torna indietro.** La dock manda `riduci <finestra> no` sul canale
  e la finestra riappare. Il pezzo che mancava non era nel compositore — lui il
  verbo lo sapeva già fare — ma nella shell, che per ridurre a icona mandava
  `movetoworkspacesilent`, cioè la strada di *Hyprland*: sotto questo
  compositore quella riga se ne andava in silenzio, e la finestra spariva senza
  modo di riportarla su. Adesso `Compositore.riduci()` è un verbo della porta
  come gli altri, e le due strade stanno una accanto all'altra.
- **«schermo intero»** nasconde la barra, e il compositore non intercetta
  ancora nessun tasto — per scelta: le novantacinque scorciatoie di Minerva
  vivono in `config/scorciatoie.minerva`, e averne anche una sola qui dentro
  vorrebbe dire due posti che decidono cosa fa un tasto. Per uscire si usa la
  scorciatoia di Minerva, che passa dalla shell.

### I protocolli che Minerva usa, e che ci sono

Ognuno di questi manca a un pezzo che sotto Hyprland funziona già, e senza
nessuno di loro c'è un errore da leggere: il programma non trova il
protocollo, si comporta come se la cosa non esistesse, e sembra Minerva a
essere rotta. Per questo `prova-annunci.py` non si fida del fatto che
compilino: chiede al compositore acceso chi è, e li conta.

| protocollo | cosa smette di funzionare senza |
|---|---|
| `ext-session-lock-v1` | **«blocca schermo» non fa niente** |
| `wlr-screencopy` | le schermate (`grim`, il pannello di Stamp) |
| `wlr-gamma-control` | la luce notturna |
| `ext-idle-notify` | il blocco automatico dello schermo, per chi lo chiede col protocollo standard |
| `idle-inhibit` | «non spegnere mentre guardo un film» — onorato davvero dal 1º settembre 2026 |
| `ext-data-control` | `wl-copy`, `wl-paste`, i gestori di appunti |
| `primary-selection` | incollare col tasto centrale |
| `cursor-shape` | il cursore chiesto per forma |
| `relative-pointer` | i giochi, e guardarsi intorno trascinando |
| `single-pixel-buffer` | gli sfondi pieni |

#### Il blocco schermo, che è quello che vale

La regola che rende un blocco un blocco: **se il programma del blocco muore,
lo schermo resta bloccato.** È la ragione per cui `ext-session-lock` esiste —
con una finestra normale basterebbe ucciderne il processo da un'altra console
per rientrare nella sessione.

Qui il compositore tiene una **tenda nera** sopra tutto (sopra anche a
«overlay», o basterebbe una notifica per disegnarci sopra) e toglie la
tastiera a chiunque. Le due metà vanno insieme e sono provate separatamente:
la tenda impedisce di *vedere*, il rifiuto dentro `fuoco_finestra()` impedisce
di *scrivere* — senza il secondo bastava una riga sul canale per mettere la
tastiera dentro un terminale coperto da uno schermo nero.

`prova-blocco.py` gira il blocco vero di Minerva dentro il compositore
annidato, lo **uccide** e verifica che non si sblocchi.

### Tappa 6 — Le scrivanie ✔ 25 agosto 2026

Minerva ne ha dieci, scritte in `config/scorciatoie.minerva` (`$mod 1…0`).
Fino a oggi, qui dentro, `workspace 3` **se ne andava nel vuoto**:
`minerva_comando()` rispondeva «verbo sconosciuto» a voce bassa e lo schermo
non cambiava. Lo stesso silenzio in cui era sparito il «riduci».

**Una scrivania non è una struttura: è un numero su ogni finestra**, più uno
sul compositore. Si accendono quelle che hanno il numero giusto e si spengono
le altre — nessun albero di scena per scrivania, perché l'ordine di
sovrapposizione è uno solo (`finestre_elenco`) ed è quello che decide chi
prende il fuoco quando una si chiude: dieci alberi vorrebbero dire dieci
ordini da tenere allineati a quell'unico elenco.

    scrivania 3        vai lì
    scrivania avanti   la vicina, saltando le vuote (la rotellina sulla barra)
    scrivanie          quali esistono            ← DOMANDA, col plurale
    portaascrivania <finestra> 3 si   mandala là senza seguirla

**Le tre cose che non sono ovvie:**

1. **Il fuoco è la metà che si dimentica.** Cambiare scrivania senza toccarlo
   lascia la tastiera alla finestra di prima, che adesso non si vede: si
   scrive in un posto invisibile. `fuoco_alla_prossima` guarda
   `finestra_visibile`, non `!ridotta`.
2. **Dare il fuoco a una finestra che sta altrove ci porta là.** La dock le
   elenca tutte: senza questo il clic «funziona» — la finestra prende davvero
   il fuoco — e sullo schermo non cambia niente.
3. **La shell si iscrive, e a una cosa sola.** `ascolta scrivanie` le fa
   arrivare il numero della scrivania e nient'altro. Le finestre continuano ad
   arrivarle dal demone; qui prende solo ciò che deve arrivare **subito**,
   perché da quel numero dipende quali barre del titolo si disegnano. Ascoltare
   tutto vorrebbe dire svegliare il processo che disegna a ogni tasto premuto
   in un terminale che cambia titolo.

**Una differenza da Hyprland, detta invece che scoperta:** la scrivania attiva
è **una per tutta la sessione**, non una per monitor. Su uno schermo solo le
due cose coincidono; il giorno che servirà, quel campo diventa un campo dello
schermo e il resto del file non cambia.

#### Il controllo che è nato da qui

`prove.sh` confronta i verbi che la shell manda con quelli che il compositore
conosce. Guardava **una porta sola**: non poteva accorgersi di un comando che
al nostro compositore non viene mandato affatto. Adesso c'è anche
`verbi-compositore.py --sordi`, che elenca le funzioni di `Compositore.qml` che
chiamano `_dispatch()` senza nominare da nessuna parte minerva-wayland.

La sera in cui è stato scritto ne ha trovate **tre**: `fuocoAlNostroProcesso`
(una finestra di Minerva tenuta pronta si apriva e restava dietro — da lì il
selettore `pid:` qui dentro), `libera` e `dilloAlProgramma` (che non hanno
niente da fare qui, e adesso lo dicono con un verbo vuoto invece di tacere).

E `prova-annidata.sh` **non passava `MINERVA_CANALE` alla shell**: dentro il
nostro compositore, la scrivania di Minerva mandava i suoi comandi a nessuno.
La prova mostrava una scrivania che sembrava viva e non rispondeva a niente.

### Tappa 6 — Le scorciatoie ✔ 25 agosto 2026

**Sono novantacinque, e qui dentro non ne funzionava nessuna.** Super+C non
chiudeva, Super+2 non cambiava scrivania, i tasti del volume non facevano
niente: il compositore non intercettava un tasto solo.

Adesso ne riceve **75**, e le riceve **già masticate**:

    scorciatoie azzera
    scorciatoia SUPER K - minerva:cheatsheet
    scorciatoia SUPER+SHIFT 1 - porta-a-scrivania:1
    scorciatoia - XF86AudioRaiseVolume bloccato minerva:volumeup

`config/scorciatoie.minerva` **non si legge qui dentro**, ed è la decisione che
conta: quel file ha le variabili, i flag e le annotazioni, e un parser in C
sarebbe un secondo posto che un giorno non è più d'accordo col primo. Lo legge
il demone — che già lo fa per il promemoria di Super+K e per i tasti di
Hyprland — e la shell porta le righe sul canale. `perMinervaWayland()` sta
accanto a `perHyprland()`, nella stessa classe: due prodotti, una sorgente.

**Le venti che restano fuori** sono di Hyprland e basta (i gruppi, il fuoco e
il ridimensionamento nella griglia, la scrivania speciale, i gesti col mouse).
Non si mandano apposta: un tasto che il compositore si mangia e poi non usa è
peggio di un tasto libero, perché il programma sotto non lo riceve nemmeno.

**Le tre cose che non sono ovvie:**

1. **Il tasto si riconosce senza i modificatori applicati.** Con SHIFT premuto
   la tastiera non produce più `1` ma `!`, e non più `k` ma `K`: confrontare il
   simbolo che esce vorrebbe dire che `SUPER+SHIFT 1` non scatta mai, perché
   quando arriva quel tasto non si chiama più «1». Si guarda il simbolo al
   **livello zero** e si confrontano a parte i modificatori. CAPS e BLOC NUM si
   tolgono dal confronto: sono stati della tastiera, non tasti tenuti premuti.
2. **Il rilascio di un tasto mangiato si mangia anche lui.** Se si inghiotte la
   pressione e si lascia passare il rilascio, il programma sotto vede un tasto
   che si alza senza essersi mai abbassato — e chi tiene il conto dei tasti
   premuti resta a credere che sia ancora giù.
3. **`avvia` lo esegue il compositore, non la shell.** È l'uscita di sicurezza:
   se la shell muore, le scorciatoie che passano da lei muoiono con lei, e
   senza questa non resterebbe modo di aprire un terminale. Doppia fork, così
   il nipote lo adotta init e non restano zombie da raccogliere.

**Provato a tastiera vera**, non solo a registro: dentro la sessione annidata,
`stato` diceva `"scrivania":1`; premuto Super+F9 (registrato a mano su
`scrivania:2`, perché ogni altra combinazione se la prende Hyprland prima che
arrivi qui dentro), `stato` diceva `"scrivania":2` — e il pallino sulla barra
di Minerva si era spostato da solo sul 2.

Restano fuori le due che aspettano il **rilascio** (l'Alt che conferma
l'Alt+Tab): il compositore annuncia la pressione e basta. E il flag `ripete`
(volume tenuto premuto) oggi vale una volta sola: la ripetizione la genera il
programma che riceve il tasto, e a una scorciatoia inghiottita non arriva.

### Tappa 7 — XWayland ✔ 26 agosto 2026

**Steam e i giochi si aprono.** Prima non si aprivano *male*: non si aprivano
affatto, e senza un errore da nessuna parte — senza un `DISPLAY` non c'è
niente a cui bussare.

Xwayland parte **pigro**: alla prima finestra X11, non all'avvio della
sessione. Su una scrivania in cui non si apre nessun programma X11 — quella
normale — non se ne pagano né i processi né la memoria.

**Le tre differenze che non danno errore:**

1. **Il pid sarebbe uno solo per tutti.** Dal lato Wayland il client è UNO —
   Xwayland — per ogni programma X11 insieme: `wl_client_get_credentials`
   darebbe lo stesso numero a Steam, al suo negozio e a ogni gioco, e la shell
   non li distinguerebbe più. Il pid vero lo dichiara la finestra
   (`_NET_WM_PID`). Lo scrivono i toolkit moderni e **non** le vecchie
   librerie Xt: provarlo con `xmessage` vuol dire provarlo dove non c'è.
2. **La superficie arriva dopo la finestra.** Una finestra X11 esiste dal lato
   del server X prima che ci sia qualcosa da disegnare, e può perdere la
   superficie e riprenderla senza morire. Quindi `finestra_superficie()` per
   una X11 **può essere NULL**, e l'albero di scena si costruisce alla
   mappatura — non alla nascita, come per le xdg.
3. **Le coordinate sono assolute, e il programma le vuole sapere.** Spostare
   una finestra X11 senza avvisarla dà i menù a tendina nell'angolo in alto a
   sinistra dello schermo. Per questo `finestra_di_misura` è diventata
   `finestra_di_geometria(f, x, y, w, h)` e il trascinamento passa da
   `finestra_muovi()`.

**I menù** — le finestre `override_redirect`, quelle che dicono «il gestore
non mi tocchi» — vivono in `struct sovrapposta` e non in `struct finestra`.
Non per eleganza: un flag avrebbe voluto dire un `if` in dodici posti
(elenco, annunci, fuoco, scrivanie, presa, barra), e un `if` dimenticato è un
menù di Steam che compare nella dock come se fosse un programma. Limite
dichiarato: `override_redirect` si legge alla nascita e non si riguarda più.

**Due difetti trovati provando, non leggendo:**

- **Qt crea due finestre per programma che non mappa mai** (una 1×1 e una
  3×3, senza titolo e senza classe, per appunti e metodi di input). Finivano
  nell'elenco: con KCalc, **tre finestre invece di una** — cioè due voci
  fantasma nella dock per ogni programma X11. Rimedio: il campo `comparsa`.
- **Tre `assert` di wlroots all'uscita, una nascosta dietro l'altra.**
  `wlr_xwayland_destroy` pretende che nessuno stia più ascoltando: con gli
  ascolti attaccati il processo **abortiva** prima di `canale_chiudi()` e
  lasciava il socket sul disco — la trappola per cui quel blocco di uscita
  esiste. Riparata quella sono uscite `gamma-control` e `session-lock`, che
  erano lì da prima. Adesso si staccano tutti gli ascolti sui protocolli.

**Le due guardie nuove:**

- `scripts/razza-finestre.py` — `f->toplevel` e `f->xsup` non si scrivono
  fuori dal confine. I nomi da sorvegliare li ricava dal file stesso, così
  una variabile nuova non le sfugge. Provata rompendo apposta.
- `compositore/prova-xwayland.py` — 27 verifiche con programmi X11 veri. La
  fotografia si scatta **dentro** il compositore annidato
  (`WAYLAND_DISPLAY=minerva-0 grim`, via `wlr-screencopy`): nessun clic sulla
  sessione di chi la lancia, nessuna coordinata da indovinare. Il menù è una
  finestra magenta 200×150 creata con `python-xlib` invece che aprendo quello
  di un programma — aprire un menù vero vuol dire provare il toolkit, non
  noi — e si contano i pixel: 30000 esatti.

### Tappa 8 — Gli schermi, da vivi ✔ 26 agosto 2026

**La pagina Schermi funziona.** Prima, sotto il nostro compositore, era
*vuota*: diceva «nessuno schermo rilevato» su un computer che lo schermo ce
l'ha davanti — perché chiedeva `hyprctl -j monitors`, che lì dentro non
risponde a nessuno, e perché leggeva a mano il vocabolario di Hyprland
(`width`, `refreshRate`, `availableModes`, `transform`, `disabled`).

Adesso c'è un verbo, `schermo`, e una traduzione sola:

    schermo eDP-1 1920x1080@60 1.25 0 0 0
    schermo HDMI-A-1 spento

Risoluzione, scala, rotazione, posizione e spegnimento si applicano **mentre
la sessione gira**. La rotazione si dice in **gradi** — 0, 90, 180, 270 — e
non nei numeri da 0 a 7 di Wayland: 45 gradi non è «quasi 90», è una cosa che
non si può fare, e diventa «dritto» invece di ruotare lo schermo di un valore
che nessuno ha chiesto.

**I rifiuti**, che sono la parte che conta:

- non si spegne **l'ultimo schermo acceso** — resterebbe niente su cui
  rimediare all'errore;
- non si mette un modo che il monitor non ha: qui si rifiuta, mentre
  all'avvio `schermi.conf` ripiega sul modo preferito. La differenza è che
  qui c'è qualcuno che sta guardando un pannello e ha appena scelto, e
  accettare per poi metterne un altro vuol dire una casella che dice
  1920×1080 e uno schermo che è a 1280×720;
- scale fuori da 0,5–4 e rotazioni che non sono un quarto di giro;
- e **dentro una prova annidata non si spegne affatto**. Vedi sotto.

**Il difetto che ha deciso come si prova questa cosa.** Sotto il backend
Wayland — un compositore dentro un altro, cioè come girano tutte le altre
prove — **riaccendere uno schermo blocca il processo**: non fallisce, non dà
errore, `wlr_output_commit_state` non torna più. Deve parlare col compositore
ospite, e quel dialogo aspetta il ciclo di eventi dentro cui sta girando.
Perciò `prova-schermi-vivi.py` gira sul backend **headless**, che come quello
vero non ha nessun ospite con cui parlare e non apre nemmeno una finestra —
e il compositore, dentro una prova annidata, si rifiuta di spegnere. Uno
schermo che non si riaccende è una trappola, non una funzione a metà.

**Due difetti gemelli trovati per strada:**

- `hyprctl -j monitors` **non elenca gli schermi spenti** — ci vuole
  `monitors all`. Uno schermo che non compare non si può riaccendere dal
  pannello, e lo stesso valeva dall'altra parte: il nostro compositore
  usciva di scena senza mettere in elenco uno schermo spento da
  `schermi.conf`. Due compositori, lo stesso buco.
- **Le finestre di Minerva avevano due barre del titolo.** `le_spetta` guarda
  la classe, e alla nascita di un `xdg_toplevel` la classe **non c'è
  ancora**: si decideva su una classe vuota, cioè si dava la barra a tutti.
  Adesso si decide alla prima commit e alla mappatura, con
  `finestra_decidi_barra`, che è la stessa per tutte e due le razze.

### La terza porta della prova annidata ✔ 26 agosto 2026

Le prime due erano già chiuse: `HYPRLAND_INSTANCE_SIGNATURE` tolta (o la
shell comanda la sessione di fuori) e `MINERVA_CANALE` puntato al nostro
compositore (o non comanda nessuno). Restava aperta la terza, ed è quella che
si vede meno: **la shell parla anche col demone**, e senza dirle niente quel
demone è quello della sessione vera.

Si è visto a schermo facendo girare Minerva intera qui dentro: la scrivania
di prova disegnava una barra del titolo per «wlroots - WL-1» — una finestra
della sessione di fuori, che qui dentro non esiste. Il demone rispondeva con
le finestre di Giacomo.

Quella metà era solo confusa da guardare. L'altra no: **ogni impostazione
cambiata durante una prova finiva nel `settings.json` vero.** Un giro di
prove sulle Impostazioni si riscriveva la scrivania su cui si sta lavorando.

`prova-annidata.sh` ha adesso il suo demone, sulla porta 11433, con la sua
cartella di configurazione — **copiata** da quella vera e non vuota: una
scrivania di prova che parte dai valori di fabbrica non somiglia a quella di
nessuno, ed è il difetto che la memoria chiama «non si agisce sui valori di
ripiego».

**E servono TRE variabili, non due.** La terza è quella che ho dimenticato al
primo tentativo, ed è la sola che abbia fatto danno vero. Il demone scrive
porta e chiave in un file, e lo cerca **in `$XDG_RUNTIME_DIR` prima che nella
cartella di configurazione**: stessa sessione, stessa cartella di runtime, e
il demone di prova ha scritto la sua porta (11433) e la sua chiave sopra
quelle del demone della sessione vera.

Il sintomo è arrivato mezz'ora dopo e da tutt'altra parte. La scrivania
continuava a funzionare — la shell era già collegata — ma ogni finestra NUOVA
leggeva quel file e cercava un demone che non c'era: `minerva-check.sh`
diceva «demone non risponde sulla 11433», e le prove della luce notturna sono
diventate rosse senza aver niente a che vedere con la luce notturna.

`MINERVA_TOKEN_FILE` vince su tutto ed esiste apposta — sta scritto in
`canale_segreto.dart`: «serve alle prove, che non devono toccare il file vero
di chi sta lavorando». Una riga di `prove.sh` controlla che ci siano tutte e
tre, e dice quale danno fa la mancanza di ognuna.

### Il rumore, che nascondeva i difetti ✔ 26 agosto 2026

Facendo girare Minerva intera qui dentro, il registro della shell aveva
**settantacinque righe di avviso**. Nessuna era un difetto; tutte insieme
erano peggio di un difetto, perché sotto quelle non se ne sarebbe visto
nessuno — e `prove.sh` ha una riga che si chiama «la shell gira senza un solo
avviso».

Settantadue venivano da `core/Scorciatoia.qml`, che dichiarava un
`GlobalShortcut` per ognuna delle trentasei scorciatoie:

    The active compositor does not support hyprland_global_shortcuts_v1
    GlobalShortcut will not work

Il commento lì sopra diceva «sotto minerva-wayland non fa niente e non dà
fastidio». La prima metà era vera, la seconda no. Adesso quel
`GlobalShortcut` sta dentro un `Loader` con `active: !Compositore.nostro`:
sotto Hyprland si crea come prima, sotto il nostro compositore non si crea
affatto — i tasti là dentro li porta il canale.

**Restano tre righe**, e sono tutte spiegate: due dicono che il server delle
notifiche è già registrato (lo tiene la sessione di fuori — in una sessione
vera la shell è una sola), e una dice che `HYPRLAND_INSTANCE_SIGNATURE` non
c'è, che è esattamente la verità.

### Tappa 9 — L'ingresso ✔ 26 agosto 2026

**Fino a oggi qui dentro la tastiera era americana.** Le accentate non si
scrivevano, la chiocciola era in un altro posto, e non c'era nessun errore da
nessuna parte: le manopole del pannello «Tastiera e mouse» passavano tutte da
`imposta()`, cioè da `hyprctl keyword`, che sotto il nostro compositore non è
nessuno. Era il punto cieco descritto qui sotto, visto dal lato che si sente.

Cinque verbi, e un elenco:

    tastiera it            (oppure «tastiera us intl», o «tastiera -»)
    ripetizione 25 600
    sensibilita 0.2
    touchpad si si no      (naturale, spento-mentre-scrivi, tocco-per-cliccare)
    dispositivo "ELAN Touchpad" no
    dispositivi            (la domanda: che c'è attaccato, e com'è regolato)

**Un trattino vuol dire «questa lasciala stare».** Serve al pannello per
cambiare UNA manopola senza rimandare anche le altre, e serve al compositore
per non dare un valore inventato a una manopola che nessuno ha mai scelto —
per questo i tre interruttori del touchpad nascono a −1 e non a zero: zero
vorrebbe dire «spento», che è una scelta, e nessuno l'ha fatta.

**Ogni manopola si applica due volte.** Quando arriva, a quello che è già
collegato; e alla nascita di ogni dispositivo nuovo. Senza la seconda metà,
una tastiera esterna infilata a sessione avviata nasce americana — e non
succede niente di visibile che lo spieghi.

**I rifiuti.** Una disposizione che non esiste **non** si accetta: `xkb`
risponde NULL, e una tastiera senza mappa non produce nessun simbolo — non è
«una disposizione sbagliata», è una tastiera morta. Si controlla prima di
applicare, si risponde `no`, e quella di prima resta al suo posto. Fuori
elenco anche una ripetizione fuori scala (un tasto che parte a raffica appena
lo si sfiora) e una sensibilità fuori da −1…+1.

**Come si verifica, e perché non basta il «ok».** La disposizione non si
chiede al compositore — che direbbe quello che gli abbiamo detto — ma a
**xkb**: `dispositivi` manda `disposizione` in cima (quella CHIESTA) e una
dentro ogni tastiera (quella VERA, letta da `xkb_keymap_layout_get_name`).
Sono due cose diverse ogni volta che si è ripiegato, ed è esattamente il caso
in cui una prova sulla nostra copia direbbe verde su una tastiera americana.
`prova-ingresso.py`, 25 verifiche, annidata perché il backend headless una
tastiera non ce l'ha.

**E il touchpad si riconosce chiedendo, non indovinando.** Hyprland manda un
elenco di `mice` e lascia riconoscere il touchpad **dal nome**; il nostro
chiede a libinput «questo dispositivo sa contare le dita?». Su questo
portatile l'ipotesi sul nome è già costata una volta.

### La luce notturna — impianto sì, pixel no ⚠ 26 agosto 2026

Sotto Hyprland la luce notturna è uno **shader su tutto lo schermo**
(`decoration:screen_shader`): `core/LuceNotturna.qml` calcola tre
moltiplicatori dai gradi Kelvin, li infila in un file `.frag` e dà il percorso
al compositore. Qui dentro quello shader non c'è, e non è una mancanza da
colmare: per scaldare i colori una **tabella** è la cosa giusta e costa meno —
è la strada di `gammastep`, ed è quella del pannello colori di un monitor da
vent'anni.

Quindi c'è un verbo, e i numeri sono gli stessi:

    colore 1 0.86 0.71      (rosso, verde, blu: 1 1 1 è il neutro)

Il conto **non si rifà** da questa parte: due conti per la stessa cosa sono
due tinte diverse il giorno che uno dei due cambia. Sotto Hyprland quei tre
numeri finiscono nello shader, sotto di noi in una tabella `lut_3x1d`.

**E qui va detta la cosa scomoda: i pixel non li ho visti cambiare.**

In wlroots 0.20 la tabella dei colori è una `wlr_color_transform`, e quella è
una strada dell'**hardware**: la applica il monitor, non il renderer. Sul
backend annidato non arriva ai pixel. Verificato il 26 agosto 2026
fotografando **da dentro** il compositore annidato e **da fuori** dalla
sessione vera, con il renderer GLES2 e con quello Vulkan, e forzando il
ridisegno di tutto lo schermo (`wlr_damage_ring_add_whole`): i pixel non
cambiano di un bit. Il verbo risponde `ok`, la tabella si costruisce, la
scena la riceve — e lo schermo resta bianco.

Sullo schermo vero (DRM) è la stessa strada che `gammastep` percorre da
sempre e che ogni compositore usa per la luce notturna, quindi c'è ogni
ragione di credere che funzioni. **Ma non l'ho visto**, e non posso vederlo
senza fare lo scambio — che è proibito finché la sessione di lavoro è questa.

Perciò `prova-ingresso.py` verifica l'IMPIANTO e lo dice a chiare lettere:
che il verbo esista, che i valori assurdi si rifiutino (sopra 1 non si
schiarisce, si satura), che il compositore non muoia. **Il giorno dello
scambio, la luce notturna è la prima cosa da guardare con i propri occhi.**

Una cosa buona è uscita dallo stesso giro: `wlr-gamma-control` — la gamma
chiesta da FUORI — non passa più da un gestore nostro ma da
`wlr_scene_set_gamma_control_manager_v1`. Il gestore che c'era metteva la
tabella sullo schermo e falliva allo stesso modo; la scena la combina anche
con la nostra, così `gammastep` e la luce notturna di Minerva insieme non si
cancellano. E toglie di mezzo un ascolto che all'uscita bisognava ricordarsi
di staccare.

### Tappa 10 — Lo scambio, pronto per essere provato ✔ 26 agosto 2026

Alla schermata di accesso c'è una **seconda voce**, accanto a «Minerva»:

    Minerva (compositore Minerva)

`start-minerva-wayland.sh` è il gemello di `start-minerva.sh`, e la differenza
è una riga in fondo: là si esegue Hyprland, qui `minerva-wayland`. Tutto
quello che sta in mezzo è identico **apposta** — identità della sessione,
registro, percorsi: due sessioni che si comportano diversamente su cose che
non c'entrano col compositore renderebbero impossibile capire quale
differenza conta.

`minerva-dentro-wayland` è il nostro equivalente degli `exec-once`: il nostro
compositore avvia UN programma, Hyprland ne avvia otto. **Se aggiungi un
`exec-once` in `config/hyprland.conf`, aggiungilo anche là** — non c'è ancora
una guardia che lo controlli.

**La sessione «Minerva» resta dov'era.** Questa si aggiunge accanto, non al
suo posto: se qualcosa non va si esce e si sceglie di nuovo l'altra. Niente
di quello che c'è qui può impedire di rientrare.

**E dentro una prova non si sospende.** `hypridle` non c'è più — dal
1º settembre 2026 l'inattività la conta il compositore (`inattivita 300 600
1800` sul canale) e la politica sta in `minerva-shell/shell.qml` — ma la
guardia si è spostata con la decisione, non è sparita: `onInattivo` legge
`MINERVA_PROVA` e non chiama `systemctl suspend`. Una prova che sospende la
macchina è la macchina che sparisce sotto le mani di chi la sta usando.
`minerva-dentro-wayland` salta comunque l'avvio automatico dei programmi:
dentro una prova sarebbero finestre che spuntano sulla scrivania di
qualcun altro.

**Verificato annidato**, con la catena d'avvio vera (registro, demone, shell,
scrivania, sfondo, dock, vassoio, batteria, wifi). Restava un difetto che
solo un occhio poteva vedere, e l'ha visto Giacomo alla prima prova: **il
puntatore spariva ovunque tranne che sulla barra.** In Wayland, entrando in
una superficie, che aspetto abbia il cursore lo decide il PROGRAMMA — e
finché non lo dice, non lo disegna nessuno. Sulla barra la shell lo imposta
(ci sono i pulsanti), sulla scrivania no; ma la scrivania è una superficie
anche lei, quella dello sfondo. Adesso il compositore rimette la freccia
entrando in ogni superficie nuova, e chi ne vuole un'altra la chiede subito
dopo.

### La guardia che non guardava ✔ 27 agosto 2026

Qui c'era scritto: «`verbi-compositore.py --sordi` cerca le funzioni che
chiamano `_dispatch(` senza una strada per il nostro compositore. Ma
`imposta()` — cioè `hyprctl keyword` — non passa da lì, e la guardia è cieca
su tutto quello che ci va dentro… è il prossimo pezzo di lavoro».

Fatto, e ha trovato più di quanto la nota prevedesse.

**Si esce da `Compositore.qml` per due porte, non una:** i VERBI
(`_dispatch`, cioè `movewindow`, `killactive`) e i SOSTANTIVI (`imposta`, cioè
`decoration:blur:size`, `animations:enabled`). La guardia guardava solo la
prima. Dalla seconda uscivano **dieci** funzioni senza nessuna strada verso
minerva-wayland.

**E il difetto vero non era la guardia cieca: era `imposta()`.** Non aveva
nessun ramo per il nostro compositore — lanciava `hyprctl keyword` comunque.
Sotto minerva-wayland finiva nel vuoto senza una riga da nessuna parte. E c'è
di peggio del vuoto: `hyprctl` non parla col compositore che ti sta disegnando
lo schermo, parla con quello che dice `HYPRLAND_INSTANCE_SIGNATURE`. In una
prova annidata fatta male quelle manopole andavano a cambiare la scrivania
**vera** di chi stava provando — lo stesso difetto già visto con i comandi
delle finestre, ed è il motivo per cui `prova-annidata.sh` cancella la firma.

**La decima l'ha trovata solo la versione severa.** Prima bastava che il corpo
della funzione contenesse la parola «nostro»: troppo poco, perché
`if (comp.nostro) return;` la contiene ed è esattamente il difetto travestito
da correzione. Adesso servono i fatti — `_nostro(`, `_due(` o
`_senzaStrada(` — e `filtroSchermo()` è saltata fuori subito: si nascondeva
dietro un «nostro» scritto in un commento.

**Ogni mancanza è adesso dichiarata, col perché**, in `senzaDestinazione`:

| funzione | perché non ha una strada |
|---|---|
| `animazioni`, `animazioneGruppo`, `animazioneAvanzata` | il motore delle animazioni è la Tappa 5 |
| `scia`, `sfocatura`, `ingrandimentoPuntatore` | sono effetti: Tappa 5 |
| `margini` | separano finestre affiancate, e il tiling in Minerva è stato tolto |
| `coloriBordo` | la cornice la disegna `src/barra.c` e i suoi colori sono ancora `#define` |
| `barraDelCompositore` | sono le manopole del plugin di Hyprland; da noi la barra è nativa |
| `filtroSchermo` | **non è un «non ancora»**: da noi la luce notturna passa dalla tabella dei colori (`coloreSchermo`), non da uno shader |

Detto **una volta sola** per manopola: un cursore nelle Impostazioni ne gira
decine, e una riga per scatto riempirebbe il registro di una notizia sola
ripetuta. E `imposta()` sotto il nostro compositore adesso **avvisa ogni
volta**: arrivarci vuol dire che qualcuno ha scritto una funzione nuova e si è
dimenticato di dichiararsi.

La guardia è stata provata su un file rotto apposta, e l'ha vista.

### L'inattività, contata qui ✔ 1º settembre 2026

Fino a oggi il conto lo teneva `hypridle`: un programma di un altro ambiente,
con un suo file di configurazione che il pannello Energia riscriveva e poi
riavviava a ogni pixel di cursore trascinato.

Adesso è un verbo, e la divisione è la stessa del coperchio del portatile — il
compositore CONTA, la shell DECIDE:

    inattivita 300 600 1800   →  ok 3     (soglie in secondi, crescenti)
    inattivita                →  ok 0     (spenta)

e a ogni soglia:

    evento inattivo {"secondi":300}

e al primo tocco dopo che una è scattata:

    evento attivo {}

**Il timer non si riarma a ogni movimento del mouse.** Riarmare vorrebbe dire
una `timerfd_settime` per movimento, e il puntatore si muove centinaia di volte
al secondo. L'attività scrive solo un numero (`ultima_attivita_ms`); il timer,
quando scatta, guarda da quanto davvero non si tocca niente, e se è troppo poco
si riarma per il resto senza annunciare.

**E il protocollo «non spegnere lo schermo» adesso lo onoriamo davvero.**
`wlr_idle_inhibit_v1_create` era chiamato dal primo giorno e i programmi ci si
appoggiavano — `minerva-shell/core/Gioco.qml` ha un `IdleInhibitor` — ma
nessuno contava gli inibitori vivi: lo schermo si sarebbe spento in mezzo a un
film lo stesso. Aprire un protocollo non è onorarlo, e un pezzo acceso che non
fa niente è peggio di uno che manca: chi legge il codice lo dà per fatto.

Due cose che mancavano anche prima, e che valevano pure per hypridle: **il clic
e la rotellina** non dichiaravano attività. Chi legge una pagina lunga
scorrendo, o guarda un video e clicca ogni tanto, non muove il puntatore di un
pixel — e lo schermo gli si abbassava sotto gli occhi.

`stato` risponde anche con `"inattivita": N`, il numero di soglie chieste. Serve
a separare due guasti che si vedono identici: la shell che non le ha chieste, e
il compositore che non conta.

### Che cosa manca (Tappe 5 e 11)

Gli effetti senza il limite del rettangolo (Tappa 5), e da lì in poi le cose
che si vedono soltanto usandolo tutti i giorni (Tappa 11).

La tabella qui sopra dice anche in che ordine conviene affrontare la Tappa 5:
sei delle dieci mancanze sono effetti, e due — i colori della cornice e le
manopole della barra — si chiudono il giorno in cui i `#define` di `barra.c`
diventano stato modificabile con un verbo.
