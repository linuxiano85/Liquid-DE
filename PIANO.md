# Liquid DE — il piano

> 23 settembre 2026, notte. Giacomo, davanti alla simulazione della Riva
> studiata: «è bellissimo». E prima: «riformuliamo tutto il piano e partiamo.
> Creeremo una cartella, la chiameremo Liquid DE, e lavoreremo lì senza
> toccare questo attuale progetto nel caso voglio continuare».
>
> La parola chiave, per tutto: **fluidità, desktop elastico, quasi senso di
> liquidità.** Solido ma liquido: il testo resta fermo e nitido, si muove la
> forma, con massa e tensione superficiale.

## Da dove parte

Liquid-DE è una **copia di Minerva Shell con tutta la sua storia**, sul ramo
`liquida`, fatta il 23 settembre da `rifiniture` (7c51dcc). Dal primo giorno
ha tutto quello che funziona oggi: il compositore `minerva-wayland` sul fork
di wlroots, il demone, la shell, il greeter, le prove.

**Minerva Shell non si tocca.** Il remoto `minerva` punta alla sua cartella
solo in lettura: la spinta è disattivata apposta (`git remote -v` lo mostra).
Se un giorno si vuole riprendere un pezzo di là, si fa `git fetch minerva`
e si sceglie; di qua verso là non passa niente.

Le simulazioni che fanno da disegno di riferimento:

| pagina | cosa decide |
|---|---|
| Finestre mai viste (4vVtCrfPstEV8o3VY8mjXS) | tavolo vivo, profondità, luce propria: scelte tutte e tre |
| Minerva Riva (AtxpNY6vtui1em3QtNCbbS) | bordi vivi + Isola + trascinare per spostare |
| **Riva studiata (FC5ZoJDw71YHB5NxQVQG29)** | il menù Sottomarino, il Centro di controllo, gli angoli, i tasti |

Il generatore delle simulazioni è in `disegno/` (`python3 disegno/genera.py`
rifà le pagine): è il riferimento con cui si confronta ogni tappa.

## Tappa 0 — Due desktop sulla stessa macchina

Oggi le due copie userebbero gli stessi posti: `~/.config/minerva`, lo stesso
socket in `$XDG_RUNTIME_DIR/minerva`, gli stessi binari in `~/.local/bin`,
la stessa voce di sessione e gli stessi file del greeter. Installare
Liquid DE vorrebbe dire rompere Minerva: esattamente quello che non si vuole.

Misurato: **~60 file** usano quei percorsi (22 `.config/minerva`, 8 la
cartella di runtime, 7 `/usr/local/lib/minerva`, 6 `.local/share/minerva`,
5 le sessioni Wayland, 5 greetd, 4 la cache, e 45 script che chiamano i
binari per nome).

1. **Un nome solo, in un posto solo.** Una variabile d'ambiente
   (`MINERVA_NOME`, di serie `minerva`; per noi `liquid`) letta da script,
   demone e shell, da cui discendono tutti i percorsi: configurazione, dati,
   cache, runtime, prefisso d'installazione. Niente più `minerva` scritto a
   mano nei percorsi: si cerca con `git grep`, e una prova lo vieta.
2. **Installazione in un prefisso suo**: `~/.local/opt/liquid-de/`, con
   `bin/`, `lib/`, `share/`. `costruisci.sh` e `minerva-compila` imparano il
   prefisso; `~/.local/bin` resta di Minerva.
3. **Una voce al login in più**: «Liquid DE» accanto a «Minerva» nel
   greeter di oggi, che non cambia. Il greeter nuovo arriva alla Tappa 6.
4. **Le impostazioni si importano una volta**: al primo avvio Liquid DE
   copia `~/.config/minerva/settings.json` nella sua cartella e da lì
   vive per conto suo.
5. **La prova che vale per tutto il piano**: prima e dopo ogni sessione di
   Liquid DE, l'impronta di `~/.config/minerva`, `~/.local/bin/minerva-*` e
   della cartella Minerva Shell deve restare identica.

## Tappa 0b — Via Hyprland dal codice

Liquid DE gira solo sul compositore nostro, ma il codice parla ancora anche
la lingua di Hyprland: **circa 400 punti** (72 in `core/Compositore.qml`, 54
in `prove.sh`, 41 in `main.c`, 31 in `core/Windows.qml`, e il resto sparso),
più la riserva del greeter e la sessione di recupero che lo avviano. Si
tolgono i rami Hyprland dalla shell, dal demone e dagli script; resta una sola
strada, la nostra. La sessione di recupero si rifà sul compositore nostro in
modalità minima, così la rete di sicurezza non sparisce.

## Tappa 1 — La Riva: la scrivania nuova

Quello che la simulazione mostra, fatto davvero. Tutto nella shell, tranne
due cose che solo il compositore può sapere.

**Nel compositore:**
- **Gli angoli attivi**: un evento `angolo <quale>` quando il puntatore resta
  in un angolo per 160 ms (la sosta che evita gli scatti per sbaglio), e
  `angolo via` quando se ne va. Oggi c'è solo il bordo alto per lo schermo
  intero (`bordo_alto_guarda`): si generalizza da lì. Spento in un gioco a
  schermo intero.
- **Super tenuto premuto**: il tocco esiste già (`tocco`, main.c:343); si
  aggiunge `tieni` (premuto oltre 400 ms, da solo), per mostrare i tasti.

**Nella shell** (le parti della simulazione, una per una):
- **L'Isola** al posto della barra: ora, segni di stato, trascinabile in
  alto o in basso; si allarga sulle notifiche e sulla musica.
- **I bordi vivi**: banchina in basso, stanze a sinistra, Cassetto a
  destra; si scambiano posto trascinandoli.
- **Il Sottomarino** (il menù delle app) dall'angolo in basso a sinistra:
  periscopio e poi scafo, quattro viste (Categorie, Cosa vuoi fare,
  Frequenti, A–Z), orizzontale o verticale, «scrivi e basta».
- **Il Centro di controllo** accanto all'Isola: le sei levette, volume e
  luminosità, il lettore, e i cinque pulsanti dell'energia (Esci, Riavvia,
  Spegni si tengono premuti; niente finestre «sei sicuro?»).
- **Gli altri angoli**: scrivania libera, panoramica (Tappa 4).
- **Il blocco** che sale come una marea (il blocco vero resta quello di
  oggi; cambia l'ingresso e l'uscita).

**Nel demone — la ricerca per funzione:**
- `app_scanner.dart` oggi legge `Name` e `Categories`. Legge anche
  `GenericName`, `Comment` e `Keywords`, con le versioni in italiano
  (`[it]`): **97 programmi su 147 installati le dichiarano**, quindi «navigare
  il web» trova Chrome coi dati di Chrome, non con una tabella nostra.
- Sopra, un **dizionario di sinonimi italiani** (quello della simulazione,
  allargato) e le **azioni** (blocca, notte, Wi-Fi…) nello stesso indice.
- «Frequenti» e «Cosa vuoi fare» dall'uso vero: quante volte e a che ora si
  apre ogni app, contate dal demone.

**I tasti nuovi** (da 95 a 30, le cinque regole della simulazione) in
`config/scorciatoie.minerva`, con Super+K che li mostra e Super tenuto che
li disegna sulla scrivania.

**Verifica**: prove annidate dal canale — l'angolo scatta dopo la sosta e
non prima, `tieni` e `tocco` non si confondono; prove QML sulla ricerca («navigare il web»
→ i browser e non il Wi-Fi); fotografie confrontate con la simulazione.

## Tappa 2 — Il materiale

Al posto del blur (che resta come opzione, com'è):
- **Acquerello**: dietro ogni superficie il colore di ciò che sta dietro, a
  1/32 della risoluzione, che insegue il nuovo con un ritardo morbido. Si
  ricalcola solo quando il fondo cambia.
- **Mercurio**: superfici vicine che si fondono ai bordi con un raccordo
  morbido (unione morbida di rettangoli arrotondati nello shader della
  cornice) e si staccano allontanandole.
- **Increspature**: lo sfondo è acqua. **Opzionale, spento di serie.**
  Costa solo finché l'acqua si muove; ferma, zero.

Nel fork: `render/gles2/pass.c` e `types/scene/wlr_scene.c`, dove oggi vive
il blur a fasce. Il verbo `effetto` impara `acquerello`.

## Tappa 3 — Le finestre liquide

1. **Il motore del movimento**: la molla (`molla.c`) diventa il corpo di
   ogni finestra (posizione, scala, inclinazione); la copia deformabile di
   `wobbly.c` si usa quando la finestra non è a riposo, e a riposo si torna al
   buffer diretto (costo zero, scanout possibile).
2. **Il tavolo vivo**: lancio con inerzia e rimbalzo, pile che si sfogliano,
   piega in una striscia viva.
3. **L'aggancio con la molla**: Super+frecce, e il trascinamento al bordo,
   ci arrivano superando di un soffio e posandosi.
4. **Profondità** e **luce propria** (colore dominante, bagliore, ombre vere
   con la direzione dell'ora).
5. **Apertura e chiusura** che gocciolano; «riduci» come un risucchio.

## Tappa 4 — Vedere le finestre

`ext-foreign-toplevel-list` e `ext-image-copy-capture`: anteprime vive che si
catturano solo mentre si guardano. Ne nascono la **panoramica** (angolo in
alto a sinistra, Super Tab) e Alt+Tab con le finestre vere. E i **gesti del
touchpad** (tre dita: stanze e panoramica), che oggi sono zero righe.

## Tappa 5 — L'accesso e il blocco liquidi

La colonna dell'accesso che respira, la password che si scrive in gocce, lo
sblocco che si apre come acqua. Il greeter di Liquid DE diventa quello di
serie solo quando Giacomo lo dice: fino ad allora il login resta quello di
Minerva, con «Liquid DE» fra le sessioni.

## Tappa 6 — Le app nuove

- **Il Fiume e il Cassetto** (gestore file): i file che scorrono per giorno,
  e la mensola sul bordo dove si posa qualunque cosa.
- **Minerva Web, «Il filo»**: su QtWebEngine; le pagine come fogli legati da
  un filo invece delle schede; Widevine dal CDM di Chrome, da provare.
- **Minerva Chiavi**: il portachiavi nostro su `org.freedesktop.secrets`,
  aperto dal login; «Chrome Safe Storage» si migra da ksecretd prima di
  spegnerlo.

## Regole per tutto il piano

- **Prestazioni estreme**: ogni effetto si misura col cronometro della
  scheda video (`gpu acceso`, `danno`) prima e dopo, scritto nel messaggio di
  salvataggio che lo introduce;
  a scrivania ferma zero fotogrammi; lo scanout a schermo intero resta
  diretto; il modo risparmio spegne tutto il liquido.
- **Ogni prova vista rossa prima.**
- **Solo annidato** finché una tappa non è verde; compilazioni solo in
  `build-native` e a bassa priorità (il portatile scalda).
- **Minerva Shell resta com'è**: la prova della Tappa 0 gira a ogni
  installazione.
- Il piano Rust/Smithay resta scritto e in pausa.

## Ordine

0 → 0b → 1 → 2 → 3 → 4 → 5 → 6. La Tappa 1 è quella che si vede tutti i giorni e
non chiede niente di pesante al compositore: si parte da lì, subito dopo la 0.

## Aperto, da decidere con Giacomo

- **Il nome del prodotto**: Liquid DE è il nome della cartella; dentro, le
  app si chiamano ancora «Minerva» (Minerva Web, Minerva Chiavi). Si tiene
  Minerva come marchio, o cambia?
- **GitHub**: oggi la copia non ha un remoto pubblico. Un repository nuovo
  si crea quando lo dice lui.
