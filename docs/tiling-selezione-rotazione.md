# Tiling, Stanze, selezione multipla e rotazione

## Finestre e desktop virtuali

La panoramica **Stanze** si apre con **Super+Tab**, dall’indicatore dei desktop
nell’isola o cliccando il desktop attivo nella barra. Mostra le finestre dei
desktop virtuali sul monitor corrente: un clic entra nella stanza, un clic
sulla miniatura raggiunge l’app e un trascinamento la invia a un’altra stanza
senza cambiare il desktop attuale.

Ogni stanza può avere un nome e una disposizione propria: **Predefinito**,
**Classico**, **Parti uguali**, **Maestro + pila**, **Griglia**, **Nuova stanza**.
I numeri restano stabili (1–10). La panoramica include una stanza vuota dopo
l’ultima occupata, finché non si raggiunge il limite di dieci.

In **Impostazioni → Finestre → Tiling**, nella sottosezione comprimibile, si scelgono il
comportamento predefinito, gli spazi, l’ordine Recenti/Manuale e le regole per
applicazione. Una regola può assegnare le nuove finestre a una stanza senza
portare lì l’utente (0 = stanza automatica). Le scelte vengono salvate.
L’icona del tiling accanto alla tray rimane facoltativa.

### Ordine del focus e Maestro

**Finestra attiva per prima**, attiva per impostazione predefinita con ordine
Recenti, porta ogni finestra che prende il focus al primo posto del layout:
a sinistra, oppure in alto a sinistra nella Griglia. In Maestro diventa il
riquadro principale; la pila a destra segue l’ultimo utilizzo, dalla più
recente in alto alla più vecchia in basso. Puoi disattivare l’opzione per
cambiare focus senza riordinare; l’ordine Manuale mantiene sempre le posizioni.
Il clic viene completato nella finestra originale prima dello spostamento,
per evitare che pressione e rilascio raggiungano app diverse.

Con il riordino attivo, **tieni Super premuto** mentre usi le frecce per
attraversare più finestre: la navigazione conserva la disposizione da cui sei
partito finché rilasci Super. In Maestro, ↓ passa dal Maestro alla cima della
pila e prosegue verso il basso; ↑ risale. Il focus aggiorna comunque il layout
ad ogni passo. Dopo il rilascio, la sequenza successiva parte dalla disposizione
attuale.

**Proporzioni automatiche del Maestro** usa tutto lo spazio con una finestra,
metà ciascuna con due, il 60% al Maestro con tre e il 65% con quattro o più.
I minimi delle app, le regole personali e il ridimensionamento con il mouse
hanno precedenza. Disattivando questa opzione puoi scegliere la percentuale
nel cursore Larghezza del maestro. Riattivandola si ripristinano le proporzioni
automatiche, cancellando la larghezza manuale del Maestro.
Cambiare esplicitamente la percentuale sostituisce anche un precedente
ridimensionamento con il mouse; il semplice cambio di focus conserva la
larghezza del ruolo Maestro.

| Tasti | Azione |
| --- | --- |
| Super + frecce, in tiling | Seleziona la finestra adiacente nel desktop e monitor attuali |
| Ctrl + ↑ / ↓, in tiling | Ingrandisce / ripristina il riquadro |
| Super + numero | Passa al desktop indicato; 0 indica il 10 |
| Super + Maiusc + numero | Invia la finestra a quel desktop, restando qui |
| Super + Ctrl + Maiusc + frecce | Scambia le posizioni mantenendo il focus sulla finestra spostata |
| Super + Ctrl + Alt + frecce | Scorre lo spazio del layout quando supera il monitor |
| Super + F | Alterna lo schermo intero |
| Super + K; Tab / Maiusc + Tab | Guida delle scorciatoie; alterna le schede Classico e Tiling |
| Super + L | Blocca lo schermo |

L’ingrandimento conserva l’appartenenza al tiling e il posto della finestra.
Il ripristino ricalcola la disposizione attuale; con due app in Parti uguali
si torna alle due metà. I limiti dimensionali delle app vengono rispettati:
se occorre, il layout espande lo spazio e la navigazione lo scorre. Dialoghi,
finestre fisse e client con vincoli incompatibili con il layout restano
flottanti. La modalità Classico ripristina le geometrie precedenti.
Una finestra esclusa per vincoli dimensionali viene riprovata quando cambiano
le condizioni: non diventa una scelta flottante permanente. I dialoghi seguono
il desktop della finestra principale, anche quando questa è nascosta.

**Super + trascinamento sinistro** riordina le finestre: nella griglia e nel
maestro scambia il riquadro sotto il puntatore; nelle parti uguali inserisce
prima o dopo la finestra di destinazione. **Super + trascinamento destro**
ridimensiona le colonne e, nel maestro o nella griglia, le righe. Lo spazio
residuo viene distribuito fra le altre finestre rispettando i limiti delle app.
Le righe della griglia rimangono allineate anche con applicazioni di altezza
limitata. Passare da un layout personale a Classico e tornare al tiling conserva
la disposizione scelta, anche al successivo accesso.

Le barre del titolo di Minerva spariscono dalle finestre tiled. Gli
[adattatori facoltativi COSMIC/Shelly](tiling-app-esterne.md) seguono lo stato
della singola finestra: rimuovono la decorazione nel Tiling e la ripristinano
in Classico. In COSMIC restano disponibili menu, ricerca e schede in una
barra compatta. Le altre applicazioni possono mantenere le proprie intestazioni.
Tenere Super non apre la guida nel tiling; conserva l’accesso alle isole a
schermo intero. In modalità Classico la guida mantiene il comportamento precedente.

## Anteprime e risorse

Le fotografie sono abilitate inizialmente e disattivabili nelle impostazioni.
Ogni finestra, anche coperta o minimizzata, ha una miniatura separata nella
griglia della propria stanza: tre finestre File producono tre miniature.
Le app assenti dal catalogo vengono incluse. L'associazione al monitor usa
l'output dichiarato dal compositore, anche se il layout scorre fuori schermo.

Le anteprime mostrano il contenuto disponibile delle singole finestre. Non sono video live.
Non si cambia desktop per catturarle e non si inviano frame callback per
risvegliare le app nascoste: il contenuto può quindi essere l’ultimo disegnato.

La cache viene preparata anche a panoramica chiusa quando una finestra cambia
contenuto, così la riapertura può mostrare fotografie già pronte. Le superfici
invariate riutilizzano l’immagine; quelle cambiate vengono catturate al massimo
ogni due secondi per finestra, distribuendo le acquisizioni nel tempo.
La cattura riduce sulla GPU a un massimo di 480×270 pixel prima della lettura.
La compressione PNG avviene su un thread dedicato; wlroots e la GPU restano
nel thread del compositore. La shell conserva l'immagine pronta finché la
sostituta non è caricata, evitando lampeggiamenti durante l'aggiornamento.
La cache contiene al massimo 64 finestre; per ciascuna viene conservata anche
la versione precedente durante la sostituzione. Per X11 nascosto si conserva
l’ultima fotografia completa: XWayland può ridisegnare solo una parte del
buffer durante una rotazione. Il contenuto viene aggiornato quando la finestra
è nuovamente visibile. I file sono nella directory privata
`minerva-anteprime-*` sotto `XDG_RUNTIME_DIR`, senza archivio permanente.
Disabilitare le fotografie o bloccare la sessione cancella la cache; le
acquisizioni ancora in corso non possono ripubblicare immagini eliminate.

Le app Minerva identificano la finestra tramite PID e ID della superficie
Wayland. Non scelgono una finestra usando solo PID o titolo. Il modulo Qt
`Minerva.WindowIdentity` si compila con `scripts/costruisci-window-identity.sh`
ed è incluso nell'installer. Usa gli header privati di Qt: dopo un aggiornamento
di Qt va ricompilato con la versione installata.
Il modello delle finestre conserva l'ultima risposta valida su errore IPC e
si sincronizza anche quando il ruolo della shell viene dichiarato dopo la connessione.

Una richiesta di attenzione da un’app in un’altra stanza viene indicata senza
spostare automaticamente l’utente. Raggiungere la finestra cancella l’indicatore.

## Selezionare file e cartelle

Trascinare sullo spazio vuoto della scrivania o del gestore file disegna un rettangolo di selezione. Nella vista elenco è disponibile anche il margine destro delle righe.

- Maiusc aggiunge alla selezione; Ctrl inverte gli elementi attraversati.
- Esc annulla il gesto e ripristina la selezione precedente.
- Il gestore file scorre quando si mantiene il puntatore vicino al bordo superiore o inferiore durante il gesto.
- Trascinare un elemento già selezionato mantiene il gruppo nel payload del trascinamento.
- Sul desktop il gruppo si sposta insieme e salva le posizioni con una sola richiesta. La disposizione automatica viene disattivata; con la griglia attiva si cerca la traslazione libera più vicina, senza spostare le icone escluse dal gruppo.

## Correzione della rotazione

La maschera del blur usava coordinate diverse da quelle della superficie quando l’output era ruotato. La trasformazione ora segue ritaglio e orientamento del client; angoli, foro e Mercurio seguono la trasformazione inversa dell’output. È stato corretto anche un problema di riposizionamento degli output automatici durante l’aggiornamento della disposizione dei monitor.

Il viewport delle colonne limita disegno, occlusione e input all’area utile del monitor. Il direct scanout viene escluso quando è attivo questo ritaglio; lo schermo intero rimuove il ritaglio. Il layout si aggiorna su eventi tramite un callback idle, senza polling periodico. Lo scorrimento della selezione usa un timer soltanto durante il gesto al bordo.

## Verifica ripetibile

Le prove sono nella cartella sorella **Liquid_test-principale**. Dalla radice:

```sh
LIQUID_DE="$PWD" python3 ../Liquid_test-principale/scripts/prova-tiling-stanze.py
```

La suite delle Stanze avvia un compositore privato con client reali Wayland e
XWayland. Verifica input, ingrandimento/ripristino, invio fra desktop, regole,
vincoli dimensionali dinamici, rotazioni, immagini reali dei desktop nascosti,
riuso della cache, caricamento QML e trascinamento delle miniature.
I log, le schermate di prova e il risultato con hash del binario sono in
`Liquid_test-principale/rapporti/stanze-tiling/`.
Il risultato dell’intera suite è in `rapporti/tiling-stanze-gate/result.json`.
Le prove delle modalità coprono da una a dodici finestre sia Wayland sia XWayland,
ordine manuale e recente, tutte le direzioni, ingrandimento, ripristino, riduzione,
spazi, vincoli e desktop automatici. Le prove delle interazioni usano input
reale del compositore, comprese inserzioni con chiavi d’ordine ravvicinate e
trasferimenti fra desktop; quelle dei monitor coprono scala frazionaria,
rotazione e scollegamento. Il test della shell carica il componente reale
con un modello di finestre di prova, evitando i servizi hardware del demone.
Il calcolo delle colonne include 2.000 casi generati e ripetibili; è stato
eseguito anche con AddressSanitizer e UndefinedBehaviorSanitizer.

Le prove aggiuntive avviano il vero gestore File: due, tre e quattro finestre
nello stesso processo, chiusura della terza, ripristino dalla dock e trascinamento
reale della miniatura fra stanze. Un ciclo prolungato ripete apertura, tre layout,
riduzione, ripristino e chiusura, misurando la memoria del gestore File. COSMIC
Files e Chrome vengono provati con dati sintetici in sessioni private.
Le fotografie sono controllate sui pixel con un client dai colori noti,
coperto, nascosto e minimizzato, comprese le quattro rotazioni e scale frazionarie.

Per una diagnosi, `traccia finestre si` sul canale privato abilita gli eventi
`MINERVA-WINDOW` nel log; `traccia finestre no` li disabilita. Il comando
`anteprime` restituisce contatori e durata massima della cattura. Queste tracce
possono contenere titoli delle finestre e vanno condivise dopo averli controllati.

I test di configurazione sono in `Liquid_test-principale/minervad`: eseguire
`dart test test/settings_api_test.dart test/scorciatoie_test.dart test/scorciatoie_sorgente_test.dart`.
Le prove isolate non sostituiscono la verifica prolungata sui monitor fisici e
su GPU diverse. Non interrompono la sessione dell’utente.

## Confronto con altri compositori

Il confronto è stato fatto sul codice di
[Niri, commit 2c82b77](https://github.com/niri-wm/niri/blob/2c82b77a7116a1241ea2fd41dd008ff00b609aae/src/layout/scrolling.rs)
e di [Hyprland, commit 663b29b](https://github.com/hyprwm/Hyprland/blob/663b29b846e4bad17cfa29941f6d2fbb6b61f139/src/layout/algorithm/tiled/master/MasterAlgorithm.cpp).
Niri distingue la selezione da spostamenti e stati di ingrandimento; Hyprland
ricalcola gli spazi interessati e adatta il ridimensionamento alla disposizione.
In Minerva l’ordine logico, il riquadro del layout e la geometria classica
sono separati. I quattro layout esistenti condividono questi stati, il controllo
dei vincoli e le regole di navigazione; un cambio di dimensione o uno scambio
non deve perdere la posizione che servirà al ripristino.

## Installazione locale

Compositore, daemon, shell e scorciatoie devono essere aggiornati insieme.
L’installazione locale conserva una copia dei file sostituiti e una ricevuta
con hash in `Liquid_test-principale/rapporti/artefatti-2026-10/stanze-tiling/installazione.json`.
Per caricare il nuovo compositore serve uscire e rientrare nella sessione:
sostituire il file su disco non aggiorna il processo già in esecuzione.

## Avvii nella stanza scelta e fotografie inattive

Il gestore File inoltra il token di avvio anche quando riusa un processo già
aperto o tenuto pronto. Il modulo nativo lo assegna alla singola finestra Qt;
un cambio di stanza durante l’avvio non modifica la destinazione e non riporta
l’utente sul desktop di quella finestra. La strada senza token mantiene il
richiamo normale. Il comportamento segue l’attivazione per superficie di
[Qt Wayland](https://github.com/qt/qtbase/blob/dev/src/plugins/platforms/wayland/plugins/shellintegration/xdg-shell/qwaylandxdgshell.cpp).

Nuova stanza cerca uno spazio libero dopo la stanza di destinazione, salta
quelle occupate e riparte dalla prima dopo la decima. Non cambia le regole
di Parti uguali, Maestro o Griglia.

Se un client non conferma la nuova geometria, le fotografie aspettano il
prossimo commit anziché riprovare indefinitamente. Il comando `anteprime`
include `warmTicks` e `warmTimerArmed` per verificare che il timer si arresti
a contenuto fermo e riparta quando il client invia un aggiornamento.

Per contenuti animati il timer attende la scadenza della fotografia precedente
(due secondi), anziché svegliarsi ogni 120 ms durante l'attesa. Un lavoro PNG
in corso riattiva la pianificazione quando termina. Disattivare le fotografie
arresta anche le richieste QML: richieste tardive e lavori già avviati non
possono ripubblicare immagini. La prova `prova-tiling-snapshot-scheduling.py`
verifica animazione reale, arresto del timer e disattivazione con viewer aperti.

Il verificatore controlla anche i risultati JSON dei singoli scenari: ogni
controllo deve essere riuscito, il rapporto deve essere fresco e l’impronta
del compositore deve coincidere. Registra gli hash dei sorgenti e dei binari;
l’installazione viene rifiutata se quei file cambiano dopo le prove.

Le prove dedicate sono `prova-tiling-file-launch-placement.py`,
`prova-tiling-snapshot-idle.py` e `prova-tiling-selection-current.py` nella
cartella `Liquid_test-principale/compositore`. La terza prova verifica i
componenti reali DesktopIcons e Pane con mouse, modificatori, annullamento,
scorrimento e persistenza delle posizioni sul demone isolato.
