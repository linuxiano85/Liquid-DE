# Il bus di Minerva

Un solo canale — un **socket Unix**, il cui percorso sta nel file del canale
insieme alla parola d'ordine — e sopra ci passa tutto quello che le finestre di
Minerva chiedono al sistema. JSON in tutte e due i versi, **un messaggio per
riga**: l'a-capo è il confine, e si può usare perché un JSON scritto da
`jsonEncode` non ne contiene mai uno.

Fino al 27 agosto 2026 era `ws://127.0.0.1:11432`. Il cambio ha tolto
`qt6-websockets` dalle dipendenze e chiuso il canale a chiunque non sia questo
utente: vedi `minervad/lib/ipc/canale_segreto.dart`.

    → richiesta   { "action": "fs_list", "path": "/home/tizio" }
    ← risposta    { "event":  "fs_listing", "payload": { … } }

## Perché questo file esiste

Perché il bus è il punto in cui **due programmi che non si conoscono devono
essere d'accordo**, e finora l'accordo non stava scritto da nessuna parte.

Il modo in cui si rompe non è un errore: è il silenzio. Un'azione scritta male
arriva al demone, non trova nessun `case`, e non succede niente — nessuna
eccezione, nessun messaggio, nessuna risposta. La shell resta ad aspettare per
sempre una cosa che non arriverà.

È già successo due volte, e tutte e due sono costate ore:

* `get_windows` e `get_monitors` li chiamava la shell e il demone non li
  conosceva: elenco delle finestre vuoto e spazio utile sconosciuto, senza un
  errore da nessuna parte;
* la shell chiedeva le impostazioni a un file che il demone non legge più.

Questo elenco è generato dal codice e c'è una prova che lo tiene allineato
(`minervad/test/bus_test.dart`): se si aggiunge un'azione e non la si scrive
qui, la suite non passa.


**164 azioni** che la shell può chiedere, **89 eventi** che il demone manda.

I due numeri li conta `minervad/test/bus_test.dart`: fino al 7 settembre 2026 dicevano 81 e 38 mentre le voci elencate qui sotto erano più del doppio. Un elenco che si aggiorna e un totale che no è peggio di nessun totale, perché chi legge si fida del numero e non conta le righe.


## Dire a quale domanda si risponde

Ogni richiesta può portare un campo **`id`**: una stringa qualunque, scelta da chi chiede. Se c'è, la risposta la riporta uguale; se non c'è, la risposta è identica a com'era prima.

Serve perché il protocollo riconosce le risposte dal **tipo** e da nient'altro. Due richieste dello stesso tipo in volo insieme sono indistinguibili, e chi aspetta prende la prima che passa: con una sola finestra si nota poco, con otto finestre di Minerva collegate allo stesso demone è una corsa che aspetta il suo giorno. È anche il motivo per cui `azione_fallita` da solo non bastava — per dire «questa richiesta non è andata» bisogna sapere **quale**.

Regole, e sono strette apposta:

- l'`id` torna **solo** a chi ha fatto quella richiesta. Mentre serviamo una domanda il demone può spedire qualcosa anche alle altre finestre, e quelle spedizioni non c'entrano niente con essa;
- gli **annunci non lo portano mai**. Un annuncio non è la risposta a nulla: attaccargli l'identificativo della richiesta che per caso era in corso vorrebbe dire dire il falso a tutte le finestre tranne una.

Dentro il demone viaggia in una *zona* e non in un campo della connessione: fra un `await` e il successivo il demone serve altri messaggi, e un campo verrebbe sovrascritto da chi arriva nel frattempo — cioè si romperebbe proprio nel caso per cui esiste.


## Manutenzione

`manutenzione_inventario` risponde con tutto quello che si può togliere da questo computer: una voce per famiglia, con `byte`, `dove` per esteso, e due campi che valgono quanto il numero — `torna` e `vuoleLaPassword`. `torna` ha **tre** valori e non due: `sola` (si rifà da sé quando serve), `mai` (tolta è tolta), `sempre` (torna anche se non vuoi — le lingue, che pacman rimette al primo aggiornamento). Erano due, e le lingue finivano fra le «non tornano», cioè il contrario della verità. Gli **orfani** stanno a parte e per nome, mai come numero: non si misurano in byte, e sommarli al totale direbbe il falso su tutti e due.

**Guarda e basta.** Non c'è nessuna azione che cancelli, e non deve entrarci: togliere è mestiere di `scripts/minerva-radice`, che ha un elenco chiuso di verbi. Una prova in `test/manutenzione/inventario_test.dart` pretende che l'inventario non chiami mai `rm`, `paccache` o `pacman -R`.

È **lento di proposito e non si ricorda**: `du` deve percorrere le cartelle vere, e un inventario vecchio di mezz'ora direbbe il falso proprio su quello che hai appena pulito.

E siccome è lento, **racconta mentre lavora**: `manutenzione_passo` arriva cinque volte per ogni scansione, con `{fase, testo, fatte, quante}`. `fatte`/`quante` fanno la barra, `testo` è la riga di registro che si legge. Va **solo a chi ha chiesto l'inventario** — con due finestre aperte, la seconda vedrebbe la barra dell'altra — e per questo l'inventario è un oggetto per richiesta e non un campo condiviso del demone.

Il fondoscala è `Inventario.passiInTutto` e sta nel demone: chi aggiunge una tappa senza toccare quel numero fa una barra che arriva al 120%.

### Togliere

`manutenzione_pulisci` prende **identificativi**, mai percorsi: `{"action": "manutenzione_pulisci", "ids": ["cache:mozilla", "cestino"]}`. I percorsi li ricava il demone rifacendo l'inventario un istante prima di cancellare, e per due ragioni: perché un verbo `pulisci <percorso>` sarebbe la stessa riga con dentro un buco — chiunque parli col canale potrebbe cancellare qualunque cosa passando da noi — e perché fra il momento in cui hai guardato l'elenco e il momento in cui premi possono essere passati minuti.

C'è un **secondo cancello**, di posto e non di nome: anche con l'identificativo giusto, si tocca solo quello che sta dentro `~/.cache/`, `~/.local/share/Trash/` o `/tmp/`. Fuori di lì il demone risponde di no e dice perché — e lo dice **voce per voce**, perché un «fatto» solo in fondo non permetterebbe di capire quali tre cartelle su ventidue non si sono potute togliere.

`/tmp` ha una regola in più: si toccano solo le cose più vecchie di un giorno, e mai prese o collegamenti. Un programma aperto da un'ora ci tiene dentro roba che gli serve, e quella cartella si svuota comunque al riavvio.

Quello che chiede la password — cache dei pacchetti, lingue, registro di sistema — passa da `scripts/minerva-radice`, che ha un elenco chiuso di verbi: `pulisci-cache-pacchetti` (via `paccache`, tenendo le ultime **due** versioni: l'ultima è quella installata, la penultima è quella a cui si torna), `pulisci-lingue` (che cancella **e** scrive `NoExtract` in `/etc/pacman.conf`, perché farne una sola è mezzo lavoro), `pulisci-registro` (potato con `journalctl --vacuum-size=50M`, non azzerato). Il pulitore non sa nemmeno cosa sia `pkexec`: gli arriva una funzione.

`pulisci-lingue` prende quelle da **tenere** e non quelle da togliere: se un domani quell'elenco arrivasse storto, il peggio che può succedere è che non si tolga niente.

`manutenzione_orfani` toglie i pacchetti rimasti soli, e **non prende nessun elenco**: lo rifà il demone un istante prima, e l'aiutante di root lo ricontrolla ancora chiedendo a pacman chi sono gli orfani adesso. Un elenco arrivato da fuori con dentro «linux» non deve poter disinstallare il kernel.

Dopo una pulizia la finestra **rimisura**: il numero che conta non è quello promesso prima, è quello che l'inventario trova dopo.

`manutenzione_inventario` e `manutenzione_pulito` portano anche `recuperato` — `{byte, volte, dal, ultima}` — cioè quanto Manutenzione ha tolto **da sempre**. È l'unica cosa che quel programma si ricorda: l'inventario si rimisura ogni volta apposta. Ci finiscono solo i byte usciti davvero, mai quelli promessi, e zero byte non conta come una pulizia.

- `manutenzione_inventario`
- `manutenzione_passo`
- `manutenzione_pulisci` → `manutenzione_pulito`
- `manutenzione_orfani` → `manutenzione_orfani`

### I file che ci sono due volte

`manutenzione_doppioni` percorre la cartella di casa e risponde con i gruppi di file identici, dal più sprecone. Il motore è quello delle fotografie (`foto/doppioni.dart`) — dimensione, poi le due estremità, poi il file intero — perché un secondo algoritmo di doppioni sarebbe un secondo posto dove sbagliarlo.

**Il codice non si guarda**: Progetti, le cartelle dei pacchetti e delle compilazioni, `.git` e le cartelle nascoste restano fuori. Là dentro i doppioni sono normali, e mostrarli vorrebbe dire annegare le tre copie del telefono in decine di migliaia di righe da non toccare.

Ogni gruppo porta `tieni` e `perche`: la copia proposta è quella **fuori dalle cartelle di passaggio** (Scaricati, Scrivania, tmp), poi la meno profonda, poi in ordine alfabetico. `percorsi` è riordinato con quella davanti — due modi di dire la stessa cosa sono due modi di dirla diversa. Resta una proposta: nella finestra si sceglie.

La risposta porta anche `cartelle`: per ogni cartella in cui vive almeno una copia, **quanto libererebbe se fosse lei il riferimento**. Serve al capovolgimento che rende usabile la pagina — la domanda non è «quali di questi settecento file butto?», a cui nessuno risponde davvero, ma «qual è la cartella buona?». Senza il numero accanto la scelta sarebbe alla cieca: due cartelle plausibili possono valere tre giga e trecento mega.

Prima di toccare qualcosa i due file si confrontano **byte per byte** con la copia che resta. L'impronta a tre livelli è quasi certezza — uno su diecimila miliardi — e per mostrare un elenco basta; per cancellare no, perché «quasi certo» moltiplicato per un tuo file fa una risposta sbagliata.

`manutenzione_doppioni_cestina` prende i percorsi e li mette **nel cestino**, mai cancellati: sono file tuoi, non cache. Prima rifà il giro e **rifiuta qualunque percorso che lascerebbe un gruppo senza copie** — basta aver aperto due volte la finestra perché un elenco vecchio chieda di buttare l'ultima rimasta.

### Le cartelle che non si guardano

`manutenzione_escluse` le legge, `manutenzione_escludi` e `manutenzione_includi` le cambiano. Sono **percorsi assoluti** e le conserva il demone (`~/.config/liquid-de/manutenzione-escluse.json`): una cartella si esclude perché è QUELLA, non perché si chiama così — `Documenti/foto` e `Scaricati/foto` sono due cose diverse, e un elenco di nomi le prenderebbe tutte e due.

Il setaccio ne salta già un elenco di serie (Progetti, le cartelle dei pacchetti e delle compilazioni, `Android`, `flutter`): roba **generata o scaricata**, dove i doppioni sono normali. Queste sono in più, e sono di chi usa il computer — nessun elenco scritto da noi può conoscere le sue cartelle.

- `manutenzione_doppioni`
- `manutenzione_doppioni_cestina` → `manutenzione_doppioni_tolti`
- `manutenzione_escluse` · `manutenzione_escludi` · `manutenzione_includi` → `manutenzione_escluse`


## Quando una richiesta non va

`azione_fallita` è l'unico evento che il demone manda **senza che nessuno l'abbia chiesto in quel momento**: è la risposta a una richiesta che non è andata.

Ne arriva uno quando l'azione non esiste (shell e demone non combaciano) e uno quando l'azione esiste ma è scoppiata a metà — per esempio perché un campo del messaggio è del tipo sbagliato. Dentro c'è `azione` (quale) e `perche` (il motivo per intero).

Fino al 7 settembre 2026 non esisteva, e i due casi finivano in una riga del registro del demone: chi aveva mandato il messaggio restava ad aspettare per sempre, e siccome il canale continuava a funzionare per tutto il resto, il difetto non si vedeva. Il ramo predefinito dello switch aveva scritto sopra, per un anno, la frase «il silenzio è la cosa peggiore che possa fare un confine fra due programmi» — e faceva esattamente quello.

**Non c'è un identificativo di richiesta**, quindi chi riceve `azione_fallita` sa QUALE azione è caduta ma non quale delle sue chiamate: con due richieste uguali in volo insieme non si distinguono. Per ora la shell lo scrive in `qs log` e basta.

- `azione_fallita`


## Impostazioni

Le preferenze. Vivono in `~/.config/liquid-de/settings.json` — NON in `config/` dentro il progetto, che è una copia vecchia rimasta lì.

- `set_setting`
- `set_settings`
- `reset_settings`


## Stato del sistema

Rete, Bluetooth, luminosità, batteria, spegnimento. Letti UNA volta dal demone per tutte le finestre: prima ogni processo se li interrogava da sé, ed erano i 5-6 secondi di ritardo all'avvio.

- `get_state`
- `wifi`
- `bluetooth`
- `brightness`
- `system_action`
- `machine_state`


## Finestre e monitor

Dove sono le finestre e quanto spazio c'è. Il demone **osserva** il compositore e spinge; `windows_follow` è l'unica cosa che deve dire la shell, perché il trascinamento col mouse il compositore non lo annuncia.

Qui c'erano anche quattro ORDINI — chiedi la finestra attiva, dàlle il fuoco, chiudila, cambia scrivania. Sono usciti il 23 agosto 2026 perché non li chiamava più nessuno da quando la shell ha la sua porta (`minerva-shell/core/Compositore.qml`), e perché la regola è più chiara senza — **il demone osserva il compositore, la shell lo comanda**. Vedi `minervad/lib/providers/compositor_provider.dart`.

- `get_windows`
- `get_monitors`
- `windows_follow`


## File

Tutto quello che tocca il disco passa da qui, e da nessun'altra parte: è l'unico modo di avere una copia che si può fermare, riprendere e raccontare mentre va.

- `fs_list`
- `fs_mkdir`
- `fs_rename`
- `fs_transfer`
- `fs_trash`
- `fs_trash_restore`
- `fs_trash_empty`
- `fs_info`
- `fs_measure`
- `fs_places`
- `fs_chmod`
- `fs_compress`
- `fs_extract`
- `fs_jobs`
- `fs_cancel`
- `fs_pause`
- `fs_resume`
- `fs_volumes`
- `fs_mount`
- `fs_unmount`
- `fs_format`
- `fs_formats`
- `fs_search`
- `fs_search_cancel`
- `fs_aspetto`
- `fs_touch`
- `fs_delete`
- `fs_conflitti`
- `fs_read`
- `fs_write`
- `font_list`


## Bluetooth: accoppiare

Accendere e spegnere il Bluetooth sta in `Stato del sistema`. Qui c'è solo
l'ACCOPPIAMENTO, che è l'unica cosa in Minerva in cui il demone deve fermarsi
ad aspettare una persona.

Un telefono non si accoppia senza confrontare un codice a sei cifre: BlueZ ne
mostra uno, il telefono un altro, e qualcuno deve dire se sono uguali. Quindi
tre azioni invece di una, e un evento che arriva da solo nel mezzo.

- `bt_pair` — comincia. `{mac}`
- `bt_pair_answer` — la risposta alla domanda. `{si: true|false}`
- `bt_pair_cancel` — ho cambiato idea

`bt_pairing` racconta i passaggi (`stato`: `avviato`, `chiede`, `fatto`,
`fallito`); quando `stato` è `chiede` porta `codice`. `bt_pair_result` è
soltanto la ricevuta della richiesta — «ho cominciato», non «è andata bene».

Vedi `minervad/lib/services/bluetooth_pairing_service.dart`.


## Set di icone installati da fuori

Un tema di icone è una cartella con dentro `index.theme` e delle immagini: uno
standard freedesktop, non roba nostra. Si spacchetta in
`~/.local/share/icons` e `get_icon_themes` lo trova da solo.

**Vale solo per le ICONE.** I temi di colore di Minerva vivono dentro
`theme/Colors.qml`, che è codice: installarne uno da un file non è una
funzione che manca, è un cambio di architettura.

L'archivio si apre in un posto temporaneo e si **guarda prima** di installarlo:
un `.desktop`, uno script o un file eseguibile fanno rifiutare tutto, col
motivo scritto. Lo zip slip lo ferma già `ArchiveService`.

- `icone_installa` — `{path}`, un archivio o una cartella
- `icone_disinstalla` — `{path}`, e solo dentro `~/.local/share/icons`

Vedi `minervad/lib/services/tema_icone_service.dart`.


## Condividere

Mandare uno o più file fuori da questo computer: Bluetooth, posta, e gli
schermi esterni. Vive fuori da `File` perché non tocca il disco — non crea, non
sposta, non cancella.

`condivisione_dove` torna SEMPRE tutte le destinazioni, comprese quelle spente,
ognuna col motivo scritto (`condivisione_service.dart`): una voce che sparisce
lascia chi la cercava a chiedersi se l'ha sognata.

**«Trasmetti a schermo» è spenta, e porta dentro i nomi veri dei televisori.**
La scoperta funziona — `schermi_esterni.dart` legge gli annunci mDNS con
`avahi-browse`, che è già installato, e ne ricava il nome che l'utente ha dato
col telecomando: «TV cameretta», «Cucina». Quello che manca è parlargli: il
protocollo CASTV2 è TLS con messaggi protobuf, e il televisore non riceve il
file — se lo va a prendere da un servizio HTTP che dobbiamo aprire noi.

Quindi `disponibile` è `false` e il motivo nomina i televisori TROVATI:
«Trovati Cucina e TV cameretta, ma non so ancora parlargli». Perché «non trovo
niente» e «ti ho trovato e non so ancora parlarti» sono due cose diverse, e chi
legge deve poter distinguere un televisore spento da una funzione non finita.

- `condivisione_dove`
- `condivisione_invia`


## Applicazioni

I programmi da lanciare: il menu li elenca, la dock li tiene. `launch_desktop` è per un file .desktop preso da un percorso qualsiasi — un launcher sulla scrivania.

L'elenco dei programmi installati e come si aprono i file.

- `get_all_apps`
- `launch_app`
- `launch_desktop`
- `rescan_apps`

- `app_seen`
  Richiede `id` (stringa): segna l'applicazione come vista. Se lo stato cambia,
  il demone invia `all_apps` a tutti i client per aggiornare l'indicatore di novità.
- `update_fixed_apps`
- `matrix_search`
- `open_with`
- `open_default`


## Suono

Lo studio delle suonerie: informazioni su un brano, la sua forma d'onda, e il taglio con le dissolvenze. Le risposte vanno a chi ha chiesto — due finestre di Suono aperte non si scambiano le onde.

- `audio_info`
- `audio_onda`
- `audio_taglia`
- `audio_formati`

L'audio del sistema — le uscite, gli ingressi, e i profili delle schede — lo
tiene `system_audio_service.dart`, che parla con PipeWire via `pactl` in JSON
e mai con una riga di shell. Serve alla pagina Audio e alla tendina del
volume, ed è quello che permette di scegliere l'uscita HDMI anche quando
PipeWire non ha ancora creato il dispositivo: la scelta cambia prima il
profilo della scheda, aspetta l'uscita, la imposta e ci sposta i flussi.

- `system_audio_state`
  Chiede lo stato: uscite, ingressi, predefiniti e le scelte HDMI/DisplayPort
  con la loro disponibilità. Risponde a chi ha chiesto con l'evento omonimo.
- `system_audio_select`
  Sceglie: `kind` (`sink`/`source`) e `name` per un'uscita o un ingresso, oppure
  una voce HDMI (`card`, `profile`, `port`). Attiva il profilo se serve, verifica
  rileggendo dal sistema, e in caso di errore rimette il profilo di prima.
  Risponde con `system_audio_select`, che porta l'esito e lo stato nuovo.
- `subscribe_audio`
  Da qui in poi questo client riceve `system_audio_state` a ogni cambiamento
  (cuffie, HDMI, profili): la pagina Audio si iscrive quando si apre e si
  disiscrive quando si chiude, così `pactl subscribe` non sveglia nessuno
  mentre nessuno guarda.
- `unsubscribe_audio`


## Tipi di file

Chi apre cosa.

- `mime_categories`
- `mime_defaults`
- `mime_describe`
- `mime_forget_default`
- `mime_set_category`
- `mime_set_default`


## Icone

La traduzione fra i nostri nomi e quelli dei temi freedesktop. La tabella sta nel demone perché si prova con `dart test`.

- `get_icon_themes`


## Processi

Il gestore attività. Si legge SOLO mentre qualcuno guarda: `subscribe`/`unsubscribe` accendono e spengono il campionamento.

- `get_processes`
- `subscribe_processes`
- `unsubscribe_processes`
- `kill_process`

E l'iscrizione **leggera**, per i widget della scrivania e della barra: gli stessi numeri senza l'elenco dei processi. Quattro file invece di `/proc` per ogni processo, e cinque secondi invece di due — i widget stanno accesi tutto il giorno, e dall'iscrizione pesante costerebbero il fermo di 22 ms misurato il 7 settembre 2026.

`machine_state` porta processore, core, memoria, scambio, rete, temperatura, GPU sveglia, carico, tempo acceso — e **il disco**, che è l'unico a costare un processo (`df`: lo spazio libero si chiede con `statvfs`, che Dart non ha). Per questo il disco si rilegge **una volta al minuto** e non a ogni giro: fra una lettura e l'altra si ripete l'ultimo valore, che non è una stima ma la misura di un minuto fa.

- `machine_state`
- `subscribe_machine`
- `unsubscribe_machine`


## Data, ora, lingua

Il fuso e la sincronizzazione appartengono al sistema: qui si passa da `timedatectl` e `localectl`.

- `time`
- `timezone`
- `ntp`
- `datetime_state`
- `datetime_set`
- `datetime_zones`
- `locale_state`
- `locale_set`


## Programmi all'avvio

`~/.config/autostart`.

- `autostart_list`
- `autostart_add`
- `autostart_remove`
- `autostart_set`


## Meteo

Open-Meteo, senza chiave. Le coordinate escono arrotondate a due decimali.

- `weather_search`
- `weather_state`


## Schermata di accesso

Il protocollo di greetd, che NON annulla la sessione da solo quando la password è sbagliata: va annullata a mano prima di ricominciare.

- `greeter_info`
- `greeter_create_session`
- `greeter_respond`
- `greeter_start`
- `greeter_cancel`
- `gestori_accesso`
- `trasmetti_schermi`
- `trasmetti_manda`
- `trasmetti_schermo`
- `trasmetti_ferma`
- `trasmetti_stato`
- `radice_stato`
- `radice_permesso`
- `radice_elenca`
- `radice_leggi`
- `radice_scrivi`
- `radice_azione`
- `custodia_panoramica`
- `custodia_dettaglio`
- `custodia_aggiungi`
- `custodia_togli`
- `custodia_punto`
- `custodia_salva`
- `custodia_inizia`
- `custodia_torna_salvataggio`
- `custodia_torna_punto`
- `custodia_destinazione_aggiungi`
- `custodia_destinazione_togli`
- `custodia_manda`
- `custodia_github_accedi`
- `custodia_github_attendi`
- `custodia_github_gettone`
- `custodia_github_chi`
- `custodia_github_dimentica`
- `custodia_github_crea`
- `account_elenco`
- `account_collega`
- `account_scollega`
- `account_guarda`
- `account_google_chiave`
- `account_google_dimentica`
- `account_google_collega`
- `scorciatoie_compositore`

### Le sessioni, e l'ambiente con cui partono

`greeter_info` risponde con l'elenco delle sessioni lette da
`/usr/share/wayland-sessions` e `/usr/share/xsessions`. Ogni sessione porta
`id`, `nome`, `descrizione`, `comando`, `tipo` (`wayland` o `x11`) e
**`nomiScrivania`**, che è il campo `DesktopNames` del file `.desktop`.

### Chi ti apre la porta

`gestori_accesso` risponde con l'elenco dei gestori di accessi installati —
riconosciuti da `Alias=display-manager.service` dentro l'unità systemd, non da
un elenco di nomi — e con quale è acceso, letto dal collegamento
`/etc/systemd/system/display-manager.service`.

Solo guardare. Accenderne uno richiede root e lo fa `minerva-greetd gestore`
dietro `pkexec`: il demone gira come te, e se potesse cambiare chi ti apre la
porta all'accensione basterebbe parlare col demone per prendersi la schermata
di accesso.

### La modalità amministratore

`radice_*` fa fare a `pkexec` una singola operazione su un percorso, tramite
`/usr/local/bin/liquid-de-radice`. **Il demone non ha nessun privilegio**: chi
decide se si può è polkit, che chiede la password di un amministratore.

`radice_azione` vuole `op` e `args`. Le operazioni sono un elenco chiuso —
`permesso`, `elenca`, `leggi`, `scrivi`, `elimina`, `crea-cartella`,
`rinomina`, `copia`, `sposta`, `permessi` — e l'aiutante le ricontrolla tutte
da capo, perché lo si può lanciare anche a mano.

### Trasmettere a un televisore

`trasmetti_schermi` risponde coi televisori accesi adesso, col loro nome vero.
`trasmetti_manda` vuole `file` e `schermo`, e `schermo` è l'**ID stabile** del
televisore, non il suo indirizzo: un IP cambia a ogni riaccensione del router,
e domani manderebbe altrove. `trasmetti_ferma` la interrompe,
`trasmetti_stato` dice se sta andando e verso chi.

Se ne trasmette **una sola per volta**: chiederne un'altra ferma la prima. Non
è un limite tecnico — due servizi effimeri vogliono due porte e il firewall ne
apre una (`trasmetti_permesso`), e la seconda finirebbe nello schermo nero
silenzioso che `foto/servizio_effimero.dart` racconta.

Si comincia sempre da un FILE, mai da una levetta: un televisore non riceve lo
schermo, riceve un indirizzo e si va a prendere una cosa.

#### `trasmetti_schermo` — lo schermo dal vivo

Vuole `schermo` (l'ID del televisore) e accetta `quale` (il nome dello schermo
da riprendere, `eDP-1`, `HDMI-A-1`; vuoto = il principale), `fps` (2–60, di
norma 30), `cursore` (di norma sì) e `muto` (di norma no: l'audio si prende dal
monitor dell'uscita, cioè da quello che stai già sentendo).

La strada è: `minerva-cattura` legge lo schermo con **wlr-screencopy** — lo
stesso protocollo di `grim`, che il compositore implementa già — e la GPU lo
comprime in H.264. La conduttura è `scripts/minerva-specchio`, ed è uno script
apposta: a 1920×1080 e 30 fps fra cattura e compressione passano **249 MB al
secondo**, e farli attraversare il demone vorrebbe dire inchiodarlo.

**Da lì in poi le strade sono due, e la sceglie il televisore.**

| | Chromecast | DLNA (Samsung e compagnia) |
|---|---|---|
| forma | lista **HLS** + pezzi da 1 s | flusso **MPEG-TS** continuo |
| ritardo | ~3 secondi | ~1–2 secondi |
| su disco | i segmenti, in `$XDG_RUNTIME_DIR` | **niente** |
| quando parte | subito | quando il televisore apre l'indirizzo |

Un Chromecast vuole una playlist: riceve l'indirizzo di una lista e va a
prendersi i pezzi. **Un Samsung un `.m3u8` non sa leggerlo**, e il modo in cui
lo dice è non dire niente — quindi a lui si dà un indirizzo che, aperto,
comincia a versare video.

La seconda forma è migliore dove si può usare, e non solo per il ritardo: la
conduttura si accende **quando il televisore apre l'indirizzo** e si spegne
quando chiude, quindi lo schermo si legge solo mentre qualcuno lo guarda, e
non se ne scrive un byte da nessuna parte.

Il ritardo comunque **c'è**: per guardare un film, delle foto o una
presentazione va benissimo; per *usare* il computer sullo schermo grande no.
Il rispecchiamento a bassa latenza dei Chromecast è un protocollo chiuso che
non implementa nessun ambiente desktop — KDE compreso — e Minerva lo dice
invece di lasciarlo scoprire.

I segmenti HLS sono fotogrammi del tuo schermo: stanno in `$XDG_RUNTIME_DIR`,
cioè in RAM e leggibili solo da te, l'indirizzo che li serve comincia con
ventiquattro byte casuali, e `trasmetti_ferma` li cancella. `trasmetti_stato`
dice `specchio: true` mentre va.

`radice_permesso` non prende argomenti e non fa niente: chiede a polkit di
identificarti, e serve a far comparire la finestrella della password quando si
**accende** la modalità amministratore invece che alla prima operazione. Fino
al 3 settembre 2026 la modalità si accendeva senza chiedere nulla — la scritta
«amministratore» compariva subito, e chi la leggeva credeva di esserlo già.
Risponde con l'evento omonimo: `ok` vero se la password è stata data,
`annullato` vero se la finestrella è stata chiusa (che non è un guasto).

`radice_elenco` separa le voci con un byte zero e non con un a capo: su Linux
un nome di file può contenere un a capo, e con le righe chi crea il file
deciderebbe cosa vede chi guarda la cartella.

### La Custodia

`custodia_*` è la storia e la sicurezza delle cartelle: **salvataggi** (git,
senza dire mai «git») e **punti di ritorno** (una copia dell'intera cartella,
`.git` e roba compilata comprese).

Sono due cose diverse e vanno tenute distinte anche nei nomi delle azioni, per
questo `custodia_torna_salvataggio` e `custodia_torna_punto` sono separati: un
salvataggio riporta indietro i file che git conosce, un punto di ritorno
riporta indietro la cartella intera. Confonderli è l'equivoco che la Custodia
esiste per togliere di mezzo.

**La regola che il demone garantisce alla shell:** nessuna operazione che può
perdere lavoro parte senza aver preso prima un punto di ritorno, e se il punto
non riesce l'operazione **non parte** e risponde `ok: false`. La shell non deve
implementarla né ricordarsene: può offrire «torna a ieri» come un pulsante
qualsiasi.

Ogni risposta ha la stessa forma — `{ok, errore?}` — e quando `ok` è falso
c'è **sempre** una frase in italiano da mostrare così com'è. `custodia_salva`
può rispondere anche `grossi`, l'elenco dei file oltre i 100 MB che l'hanno
fatta rifiutare: si rifiuta prima del salvataggio perché dopo sarebbe troppo
tardi — un file entrato nella storia ci resta anche se lo si cancella.

`custodia_manda` porta il progetto in una delle sue destinazioni, e il tipo
della destinazione sceglie la strada.

Con `cartella` — una cartella o un disco esterno, la sola strada per quello che
GitHub non prende (`Ruby`, 286 GB di immagini ROM) — la copia va **sempre
dentro una sottocartella nostra** che porta la chiave del progetto, mai nella
cartella scelta dall'utente: è quello che rende innocuo il `--delete` di rsync,
e non la prudenza di chi scrive.

Con `github` parte un `push`, e quindi esce solo quello che è **salvato**: se
restano modifiche non salvate la risposta lo dice in chiaro invece di lasciar
credere che sia andato via tutto. Prima di mandare si rifà il controllo dei
segreti su **tutti** i file che git conosce, e non solo sulle ultime modifiche:
un progetto può avere salvataggi più vecchi del controllo, e l'invio è l'ultimo
momento in cui si può ancora non farlo.

### Entrare in GitHub senza incollare niente

`custodia_github_accedi` e `custodia_github_attendi` sono i due passi del
**device flow**, che è il modo in cui GitHub fa entrare i programmi che girano
sul computer di qualcuno. Il primo torna **subito** con un codice di otto
caratteri da mostrare (`codice`), l'indirizzo dove confermarlo (`dove`) e un
codice che resta a noi (`nostro`). Il secondo **resta in attesa**, anche per
minuti, finché l'utente non ha confermato sul sito.

Due verbi e non uno per una ragione precisa: con un verbo solo la finestra
resterebbe muta per tutto il tempo dell'attesa, e una finestra muta è
indistinguibile da una rotta.

Perché questa strada e non il ritorno su `127.0.0.1` come per Google: il giro
web di GitHub pretende il *segreto* dell'applicazione per scambiare il codice,
e un segreto dentro un programma che si installa non è un segreto. VS Code e
simili ci riescono perché hanno un server loro dove quel segreto sta al sicuro;
noi non ce l'abbiamo, e il device flow è nato apposta per questo caso — è
quello che usa `gh` da riga di comando.

Il gettone che ne esce non passa mai per la shell: lo prende il demone e lo
mette nel portachiavi, come tutti gli altri.

### Il gettone di GitHub, incollato a mano

Resta per chi preferisce, ma è la strada vecchia — e l'8 settembre 2026 ha
mostrato perché: un gettone appena creato è finito dentro una conversazione,
cioè in un posto dove non doveva stare. Un gesto che si può sbagliare così è un
gesto da togliere, non da spiegare meglio.

`custodia_github_gettone` è l'unica azione di tutto il protocollo che porta un
segreto, e lo porta **in un verso solo**. Il demone lo mette nel portachiavi di
sistema (`secret-tool`, scritto sullo standard input e mai negli argomenti di
un processo) e da lì non torna più indietro: nessuna risposta lo contiene,
nemmeno accorciato. Se non vale niente viene **tolto** dal portachiavi invece
di restarci: ritrovarselo domani vorrebbe dire dare la colpa alla rete.

Da lì in poi il gettone arriva a git dentro l'ambiente di un processo che muore
subito dopo, tramite un `credential.helper` di una riga. **Non** finisce
nell'indirizzo del remote — da lì si propagherebbe in ogni copia del progetto —
né in `.git/config`, né in `/proc/<pid>/cmdline`, che legge chiunque giri come
te.

`custodia_github_chi` risponde `{ok: true, collegato, chi?}`: `chi` è il nome
dell'account su GitHub, ed è tutto quello che la shell può sapere del gettone.

`custodia_github_crea` fa due gesti in uno — crea l'archivio e lo aggiunge alle
destinazioni del progetto — perché un archivio creato e non collegato è uno
stato che non serve a nessuno. L'archivio nasce **vuoto** (`auto_init: false`):
con il README che GitHub aggiungerebbe di suo, il primo invio fallirebbe con
«fetch first», che è il messaggio che fa rinunciare la gente.

`custodia_panoramica` porta `progetti` (la griglia) e `proposte` (le cartelle
trovate in giro che non sono ancora nell'elenco: si mostrano, non si adottano).

Il percorso è la chiave con cui la shell nomina un progetto; i punti di ritorno
invece stanno sotto una **chiave stabile** che non cambia se si rinomina il
progetto. La shell non la vede e non le serve.

### Gli account online

`account_*` sono i servizi in rete a cui Minerva è collegata — oggi kDrive di
Infomaniak, Google Drive, e una cartella WebDAV qualsiasi.

**Il registro è uno solo**, e questa è la ragione per cui esiste il servizio:
le Impostazioni li mostrano, la Custodia li usa come destinazioni. Senza,
kDrive andrebbe collegato **due volte** — due password da tenere aggiornate e
due volte la stessa fatica per chi usa il computer.

`account_collega` è, con `custodia_github_gettone`, l'altra azione che porta un
segreto, e vale la stessa regola: **un verso solo**. La password va nel
portachiavi di sistema (`secret-tool`, scritta sullo standard input e mai negli
argomenti di un processo) e da lì non torna più indietro; nessuna risposta la
contiene. E **prima si prova, poi si scrive**: un account salvato che non
funziona è una riga che dice «collegato» e non lo è, e ci si accorgerebbe
dell'errore nel momento peggiore — quando ci si manda un backup.

`account_guarda` chiede l'accesso e lo spazio, ed è una richiesta in rete: si
fa quando qualcuno guarda quell'account, non all'apertura della finestra.
Aprire le Impostazioni non deve poter dipendere da un server lento.

Nella risposta, **`loDice` è più importante dei numeri**. Non tutti i server
WebDAV mandano `quota-used-bytes` e `quota-available-bytes` (RFC 4331), e un
`-1` vuol dire «non definito», non zero. Quando `loDice` è falso i campi non
ci sono affatto, e la finestra scrive che il server non lo dice: un numero
dedotto sullo spazio libero è quello che fa perdere dei file.

`account_elenco` porta anche `puo`, cioè cosa questa macchina sa fare
**adesso**: `montare` è falso se manca `rclone`, `google` è falso finché non
c'è una chiave dell'applicazione registrata. Si mostra invece di offrire cose
che finirebbero in un errore.

#### kDrive: il numero non si chiede

`account_collega` con `servizio: "kdrive"` accetta `numero`, ma **vuoto è la
strada normale**. Misurato con curl il 25 agosto 2026:
`https://connect.kdrive.infomaniak.com/` risponde a un PROPFIND con `401` e
`Www-Authenticate: Basic realm="kdrive/dav"` — è un server WebDAV vero, che
chiede solo di farsi riconoscere; un numero inventato risponde `404`. Quindi il
demone entra dalla radice con l'email e la password e si fa dire dal server
quali archivi ci sono.

Se ce n'è più d'uno, la risposta è `{ok: false, scegli: [...]}` con dentro
`{id, nome, url}`: non è un errore, è una domanda. La finestra rimanda la
stessa richiesta col `numero` scelto — e per questo, e solo per questo, la
password resta nel campo finché la risposta non arriva.

E se Infomaniak risponde `401`, la frase che torna indietro **nomina kAuth**:
col secondo passaggio attivo la password del sito non basta e non è colpa di
chi la scrive, perché a kAuth nessun programma può rispondere al posto suo.
Serve una password per le applicazioni.

#### Google: qui non passa nessuna password

`account_google_collega` è l'unica azione che risponde con **un indirizzo da
aprire** (`account_google_apri`), e non con un risultato: la pagina è quella di
Google, e lì ci vanno l'email, la password e il secondo passaggio. Minerva non
li vede. Il permesso torna su `http://127.0.0.1:<porta a caso>`, con PKCE e
uno `state` che deve tornare uguale a come è partito — senza quel controllo
un'altra pagina aperta nel browser potrebbe far collegare un account che non è
il tuo.

Si chiede un permesso solo, `drive.file`: **i file che Minerva crea**, non il
resto del Drive. Nel portachiavi finiscono due cose, e nessuna delle due esce
mai: la chiave dell'applicazione (`account_google_chiave`, che si dà una volta
sola) e la chiave di rinnovo dell'account. `account_scollega` su un account
Google revoca il permesso anche dal lato di Google: toglierlo solo da qui
lascerebbe scritto nel suo account che Minerva può entrare.

### Le scorciatoie per minerva-wayland

`scorciatoie_compositore` è **una cosa diversa da `keybindings`**, e non
viaggiano insieme apposta: `keybindings` è il promemoria di Super+K, fatto per
gli occhi di chi usa il computer, con le categorie e le descrizioni;
`scorciatoie_compositore` sono righe per un compositore, e le legge
`compositore/src/main.c`.

    scorciatoia SUPER K - minerva:cheatsheet
    scorciatoia - XF86AudioRaiseVolume bloccato minerva:volumeup

Escono tutte dalla stessa sorgente, `config/scorciatoie.minerva`, dalla stessa
classe che genera i tasti di Hyprland (`services/scorciatoie.dart`). **Sotto
Hyprland i tasti li registra Hyprland** leggendo il file che generiamo;
minerva-wayland non legge nessun file, di proposito: due parser per un formato
solo sono due parser che un giorno non sono più d'accordo.

**A portargliele è la shell**, non il demone — il demone osserva il
compositore, la shell lo comanda, ed è lei che ha il canale in mano. Le chiede
appena il canale si apre, e le rimanda tutte da capo ogni volta che il file
cambia: la prima riga è sempre `scorciatoie azzera`, perché aggiungere e basta
vorrebbe dire una tabella che cresce a ogni ricarica con dentro le regole di
ieri.

Ne partono **75 su 95**. Le altre venti sono di Hyprland e basta — i gruppi, il
fuoco e il ridimensionamento dentro la griglia, la scrivania speciale, i gesti
col mouse — e in minerva-wayland ogni finestra galleggia. Non si mandano
apposta: un tasto che il compositore si mangia e poi non usa è peggio di un
tasto libero, perché il programma sotto non lo riceve nemmeno. Il conto sta in
`saltatePerMinervaWayland`, e una prova lo controlla.

Le ventisei `minerva:` tornano indietro come `evento scorciatoia`, e le esegue
`core/Scorciatoia.qml` — lo stesso file, con lo stesso `name`, che sotto
Hyprland le riceve da `GlobalShortcut`.

### L'avvio della sessione

`greeter_start` vuole `cmd` ed `env`. **`cmd` è un elenco di UN elemento
solo**, la riga `Exec=` del `.desktop` così com'è. Non è un `argv`, per quanto
la pagina di manuale di greetd lo faccia sembrare: greetd unisce l'elenco con
degli spazi e lo dà a `/bin/sh -c`. Mettendoci davanti un secondo interprete
(`sh -lc …`) la riga si spezza, e le sessioni con due parole nell'`Exec` — su
questo computer solo Plasma — non partono affatto. Le
variabili sono quattro, e nessuna è cerimoniale:

    XDG_SESSION_DESKTOP=<id>              il nome del file
    XDG_CURRENT_DESKTOP=<nomiScrivania>   con cui la scrivania riconosce sé stessa
    XDG_SESSION_TYPE=wayland|x11          da cui Qt e GTK scelgono il backend
    XDG_SESSION_CLASS=user                per logind

Fino al 17 agosto 2026 c'era solo la prima, e `DesktopNames` non lo leggeva
nessuno: Plasma e Hyprland partivano senza sapere di essere KDE e Hyprland, e
`xdg-desktop-portal` non sapeva a chi chiedere per lo schermo condiviso, i
file e le password.


## La galleria

Le foto e i video di Anteprima. Il catalogo sta nella cache
(`~/.cache/liquid-de/foto/indice.json`), le cartelle scelte e le esclusioni
stanno nella configurazione (`~/.config/liquid-de/foto/cartelle.json`): si
possono buttare le miniature senza perdere le scelte.

Due cose non ovvie, e sono il motivo per cui queste azioni sono tante e non una.

**`foto_proposte` è separata da `foto_cartelle` perché costa.** Cercare dove
sono le foto nella home vuol dire camminarla: 0,4 secondi misurati. Leggere le
cartelle già scelte costa zero. Tenerle insieme avrebbe fatto pagare la
ricerca a ogni apertura di finestra.

### Lo sfondo sfocato — `sfondo_sfocato`

Il «vetro» dietro la barra e la dock **non è un effetto**: è un'immagine.

La shell gira con `QT_QUICK_BACKEND=software` — vale 38 MB — e col processore
un `layer.effect` non esiste. Verificato il 31 agosto 2026 anche la strada
nuova di Qt 6.8, `ShapePath.fillItem`: col renderer software la forma esce
**vuota**, mentre la stessa forma con un colore pieno si disegna
perfettamente. Misurato con una cattura, non supposto.

Quindi il demone prepara una copia già sfocata dello sfondo — ridotta a 320
pixel di larghezza e poi sfocata poco, perché la riduzione è già una media — e
la tiene in cache. La shell la disegna e basta: **costo a fotogramma zero**,
contro i due passaggi a schermo pieno che la sfocatura di Hyprland faceva
sessanta volte al secondo su una scheda video integrata.

Come `foto_miniatura`, la risposta porta un **percorso** e riporta il `sfondo`
di partenza, perché le richieste tornano fuori ordine.

Cosa si perde, detto subito: il vetro vero mostra le finestre che ci passano
sotto, questo mostra lo sfondo. La differenza è più piccola di quanto sembri —
la barra ha una zona riservata di layer-shell, quindi le finestre normali sotto
non ci passano. Si perde solo dietro le finestre a schermo intero, dove la
barra si nasconde comunque.

**`foto_miniatura` risponde con un PERCORSO, non con dei byte.** Una miniatura
in base64 sul canale sarebbe circa un megabyte per schermata di griglia. La
risposta riporta anche `percorsoFoto`, cioè il file di partenza, perché le
richieste tornano fuori ordine e chi ha chiesto deve poter riconoscere la
propria.

`foto_scansiona` è a flusso: manda `foto_scansione` a mazzetti mentre cammina,
e si ferma con `foto_scansiona_ferma`. Una scansione annullata **non** scrive
un indice a metà.

**`foto_doppioni` non cancella niente, e non lo farà mai.** Torna dei gruppi,
col primo di ognuno marcato come «quello da tenere» — il percorso più corto, che
è quello che qualcuno ha messo dove voleva invece di quello dove è caduto. A
buttare via è un'altra azione, e la separazione è voluta: qui si guarda, là si
decide.

Confronta a tre livelli, e ognuno serve a non fare il successivo: la
**dimensione** (sta già nell'indice, costa zero), i **primi e ultimi 64 KB**, e
solo se quelli non hanno deciso il **file intero**. L'ultimo livello non è una
precauzione teorica: due fotografie che differiscono solo nel mezzo hanno la
stessa testa e la stessa coda, e senza leggerle tutte verrebbero dichiarate
identiche — cioè una delle due finirebbe nel cestino. C'è una prova apposta, e
l'ho vista diventare rossa togliendo quel livello.

Misurato sulla libreria vera il 30 agosto 2026: **16 gruppi, 36 MB, in 0,7
secondi** su 525 fotografie.

**`foto_doppioni_scarta` è l'unica strada di Minerva verso la cancellazione di
una fotografia**, e i suoi rifiuti stanno nel demone e non nell'interfaccia —
perché un'interfaccia si può sbagliare. La regola è che **«butta tutte le
copie» non deve essere una cosa esprimibile**:

- senza dire quale copia TENERE, non butta niente;
- la copia da tenere non può stare anche fra quelle da buttare (è l'errore da
  un clic, ed è quello che perde la fotografia);
- si buttano solo file che stanno nell'indice: non è una via per cancellare
  `/etc/passwd` passando dal canale.

E poi non cancella: manda nel cestino, con `fs_trash`, che è recuperabile.


### Trasmettere a schermo

`trasmetti_permesso` apre — o richiude — **la sola porta 8010**, e **solo verso
la rete privata a cui questo computer è attaccato**. Passa dall'aiutante di
root (`scripts/minerva-radice`), quindi chiede la password una volta, e i due
verbi **non prendono argomenti**: un aiutante che gira da root e accetta «apri
la porta N verso la rete M» sarebbe la stessa riga con dentro un buco. La rete
non si riceve, si ricava — e se non è privata, non si apre niente.

**Perché serve.** Un Chromecast non riceve la fotografia: se la va a
**prendere** da un servizio che Minerva apre per il tempo della trasmissione.
Con un firewall acceso quel servizio è irraggiungibile, e il modo in cui si
rompe è il peggiore che ci sia: il televisore **accetta** il comando
(`MEDIA_STATUS`), la schermata di Chromecast sparisce, e resta **schermo nero**.
Il sì arriva subito, il no arriva dopo e in silenzio. Visto sulla «TV
cameretta» di Giacomo il 30 agosto 2026, ed è la ragione per cui il servizio
usa una porta fissa invece di una a caso: un firewall non sa permettere «la
porta che sceglierò fra un minuto».

La serratura resta comunque l'**indirizzo**, non la porta: ventiquattro byte da
`Random.secure()`, e qualunque richiesta che non abbia esattamente quello
riceve un no — anche a porta aperta.

- `foto_cartelle`
- `foto_proposte`
- `foto_cartella_aggiungi`
- `foto_cartella_togli`
- `foto_escludi`
- `foto_schermate`
- `foto_scansiona`
- `foto_scansiona_ferma`
- `foto_panoramica`
- `foto_giorno`
- `foto_miniatura`
- `foto_preferito`
- `foto_doppioni`
- `foto_doppioni_scarta`
- `trasmetti_permesso`
- `sfondo_sfocato`


## La parola d'ordine

Il primo messaggio di ogni connessione, prima di qualunque altro.

- `ciao`


## Scorciatoie

Lette da `config/hypr/keybinds.conf`, annotazione per annotazione.

- `get_keybindings`


## Servizio

Iscrizione al bus e ricarica.

- `subscribe`
- `refresh`


## Gli eventi che il demone manda

Alcuni sono risposte a una richiesta, altri arrivano da soli quando qualcosa cambia — lo stato delle finestre, la batteria, una copia che avanza.

- `ciao` — la risposta alla parola d'ordine, e il **primo** messaggio di ogni
  conversazione. `{ok: true}` apre il canale; `{ok: false}` lo chiude subito
  dopo. Finché non è arrivato con `ok: true`, il demone non manda nient'altro
  e non ascolta nient'altro: vedi `minervad/lib/ipc/canale_segreto.dart`.
- `all_apps`
- `autostart_list`
- `datetime_result`
- `datetime_state`
- `datetime_zones`
- `fs_formats`
- `fs_info`
- `fs_job`
- `fs_jobs`
- `fs_listing`
- `fs_measure`
- `fs_places`
- `fs_result`
- `fs_text`
- `fonts_list`
- `foto_cartelle`
- `foto_giorno`
- `foto_miniatura`
- `foto_panoramica`
- `foto_preferito`
- `foto_proposte`
- `foto_doppioni_scarta`
- `foto_scansione`
- `trasmetti_permesso`
- `sfondo_sfocato`
- `fs_conflitti`
- `fs_volumes`
- `gestori_accesso`
- `greeter_info`
- `greeter_message`
- `trasmetti_schermi`
- `trasmetti_esito`
- `trasmetti_stato`
- `radice_elenco`
- `radice_esito`
- `radice_permesso`
- `radice_stato`
- `radice_testo`
- `custodia_panoramica`
- `custodia_dettaglio`
- `custodia_esito`
- `custodia_github`
- `account`
- `account_esito`
- `account_dettaglio`
- `account_google_apri`
- `scorciatoie_compositore`
- `icon_themes`
- `icons`
- `init_state`
- `keybindings`
- `locale_result`
- `locale_state`
- `machine_state`
- `matrix_nodes`
- `matrix_results`
- `mime_categories`
- `mime_defaults`
- `mime_described`
- `monitors_state`
- `process_killed`
- `processes`
- `settings`
- `state_response`
- `system_state`
- `weather`
- `weather_places`
- `windows_state`
- `audio_info`
- `audio_onda`
- `audio_result`
- `audio_formati`
- `system_audio_state`
  Lo stato dell'audio di sistema. Risposta a `system_audio_state`, e anche
  annuncio a ogni cambiamento (`pactl subscribe`) per chi è iscritto a
  questo evento con `subscribe`.
- `system_audio_select`
- `condivisione_dove`
- `condivisione_esito`
- `bt_pairing`
- `bt_pair_result`
- `icone_esito`


## Le due regole del protocollo

1. **Chi aggiunge un'azione la scrive qui.** Non è burocrazia: è l'unico posto
   in cui l'altra metà del programma può venire a sapere che esiste.
2. **Un'azione che non si conosce si DICE.** Il demone scrive
   `[MINERVA][IPC][WARN] Azione sconosciuta`, perché il silenzio è il modo in
   cui questo genere di errore si nasconde per settimane.
