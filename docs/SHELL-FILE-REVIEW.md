# Registro della revisione della Shell, file per file

Questo registro integra l'audit iniziale e il piano. Leggere un file non
equivale a verificarne il runtime. Ogni passata registra parti esaminate,
correzioni, prove e difetti residui. App autonome escluse; login, blocco,
Impostazioni e servizi necessari alla Shell inclusi. Stato della PR #2.

## Passata Wi-Fi: pezzo 3

| File | Esame in questa passata | Esito |
|---|---|---|
| `minerva-shell/settings/sections/Network.qml` | Lettura, scansione/parser, stato, avvio/disconnessione, radio, presentazione e dialogo password | R-03 corretto: processo dedicato, nessun segreto in argv/diagnostica/coda. Corretti campo persistente dopo Annulla, rivelazione al passaggio del mouse, richieste sovrapposte e completamenti tardivi; nomi/errori esterni PlainText. JS e nmcli passati in CI (89 test complessivi); QML/radio nativi aperti. |
| `minerva-shell/core/Exec.qml` | Comando conservato, coda, timeout, mancato avvio, completamento | La connessione Wi-Fi non lo usa più per i segreti. R-24 resta: esecuzioni fire sovrapposte, generazioni/timeout e contratto di completamento da trattare nel pezzo dei comandi. |
| `minervad/lib/services/system_state_service.dart` | Percorso `_leggiRete` e `setWifi`, non revisione integrale del file | Nomi nmcli non decodificati dagli escape e trim distruttivo dei bordi, confermati dal sorgente: residuo R-05. Stato radio ottimistico/riscontro del comando: pezzo 5. |
| `minervad/lib/ipc/websocket_server.dart` | Dispatch radio Wi-Fi, non revisione integrale del file | La credenziale della pagina non passa per IPC; revisione del replay delle altre conversazioni R-12 ancora aperta. |

Il caso dei profili con password già salvata usa ora l'UUID trovato tramite
confronto letterale dell'SSID, senza eliminare spazi o interpretare escape.
L'attivazione `connection up --ask` crea il SecretAgent anche con nmcli 1.46;
il test usa questo stesso percorso e sostituisce il valore precompilato.
La ricerca è di sola lettura, senza credenziali. Errori/UUID non validi e
risposte successive all'annullamento non avviano alcuna connessione.
La correzione Wi-Fi ha superato la CI sul commit 2b95c7f; QML e rete reali
restano da verificare.

Limiti residui di Network.qml: errori di scansione/disconnessione soppressi,
prima interfaccia selezionata senza scelta nel caso di più schede, SSID con
newline/byte arbitrari non rappresentabili dal parser a righe, WEP e 802.1X
da verificare sul sistema. La pagina non implementa configurazione completa
802.1X/certificati. I pulsanti fatti con Rectangle/MouseArea richiedono ancora
la passata di tastiera/focus R-32. Terminare nmcli cancella il client locale,
non garantisce annullamento di un'attivazione già accettata dal demone di rete.

Prove: corpi JS estratti dal QML; vero nmcli/readline e SecretAgent su bus
privato con NetworkManager simulato. Nessuna associazione radio o DHCP reale.
Password di prova fittizie; nessuna modifica a servizi/configurazioni di rete
del sistema. Vedere `tests/README-shell-regressions.md` per la matrice nativa.

La prossima passata segue `core/Ipc.qml` e i percorsi login/blocco/polkit:
coda offline, credenziali, cancellazione, riconnessione e risposte tardive.
Gli altri file restano nel piano: questo registro non dichiara completata la
revisione di tutta la Shell.

## Passata 4a: login offline e callback dei socket

- `core/Ipc.qml`: esaminati send, coda/svuotamento, rinnovo del socket,
  callback di stato/errore/lettura e metodi greeter. Risposte e comandi login
  rifiutati offline, vecchie voci login scartate, callback di socket ritirati
  ignorati. Non è una revisione integrale di tutte le API di questo file.
- `greeter/Greeter.qml`: esaminati creazione, risposta, avvio, retry,
  annullamento, selezione utente e handler IPC. Invio fallito/perdita del
  canale svuotano il campo e lo stato; retry esplicito, risposte tardive
  ignorate fino al nuovo tentativo. Il cambio selezione non riavvia da solo
  una conversazione interrotta. Grafica e login reale ancora da verificare.
- `minervad/lib/ipc/websocket_server.dart`: letto il dispatch greetd e
  l'inoltro delle risposte; nessuna modifica in questa passata. La proprietà
  della conversazione e la correlazione restano aperte: un nuovo client
  prende il posto del precedente senza identificatore di conversazione.

Dieci nuove regressioni JS esercitano i corpi del codice reale. Le prime
otto fallivano prima della patch, anche per funzioni nuove assenti: questo
non equivale a otto bug distinti. 57 test JS locali passati senza skip;
verifica complessiva della nuova revisione demandata alla CI della PR.
Il Wi-Fi precedente ha 89 test passati in Actions 37001460841 sul commit
2b95c7fdb71bc1b89a38a5f9db3ba2910a49ff68.

Prossimo pezzo: correlazione e proprietà delle conversazioni nel servizio
login, poi classificazione delle altre richieste accodabili. R-12 è parziale.

## Passata 4b: proprietario e richieste greetd

- `services/greetd_service.dart`: esaminato integralmente; il buffer è ora
  per socket, una sola richiesta resta in attesa, connect/flush/EOF/timeout
  e chiusura completano il chiamante senza riportare dati grezzi negli errori.
  Il protocollo ufficiale ha una risposta per richiesta: più domande PAM
  richiedono più scambi, non più risposte spontanee alla stessa richiesta.
- `services/greetd_conversation.dart`: nuovo coordinatore con proprietario
  della conversazione, stato di autenticazione e barriera di annullamento.
  Un altro client non può sostituire il proprietario né rispondere/avviare/
  annullare la sua sessione. La disconnessione sopprime le risposte e pulisce
  la sessione; dopo un guasto si richiede un reset confermato. Un avvio già
  riuscito non viene annullato all'uscita prevista del greeter.
- `ipc/websocket_server.dart`: dispatch e rimozione client delegano al
  coordinatore, senza assegnare la conversazione all'ultimo mittente.
- `greeter/Greeter.qml`: cambio utente attende l'annullamento; la risposta
  deve riferirsi a greeter_cancel per far ripartire la conversazione.
  Guasti di trasporto/rifiuti non valgono come conferme di annullamento.

59 regressioni JS locali passate. Aggiunti 16 test Dart: dieci sul coordinatore
con trasporto controllabile e sei sul trasporto reale tramite socket Unix
privati. Compilazione, analisi e test Dart sono richiesti dalla CI della PR.
PAM/greetd e QML nativi restano da verificare. Il proprietario è un confine
fra client della Shell, non una sandbox contro processi dello stesso UID.
Fonti del protocollo: kennylevinsen/greetd, greetd/src/server.rs e greetd_ipc.

Esito 4b: Actions 37047076712, commit b56aaf4, 117 test passati senza skip e
demone compilato. L'analisi ha segnalato sei rilievi informativi sulle graffe:
corretti nella revisione seguente; il controllo dei servizi greetd ora usa
--fatal-infos. L'esito dell'ultima revisione è registrato nella PR e nel rapporto.


## Passata 4c: QML e PAM nativi del blocco

Caricati Greeter e Blocco reali in Quickshell su Xvfb/Mesa, con account
usa e getta e lo stack PAM del progetto. Riprodotti e corretti password
rimasta nel campo dopo successo e diagnostica PAM sovrascritta da un errore
password. Aggiunta scadenza di 60 secondi con annullamento della sola
verifica e nuovo tentativo; il blocco resta attivo. Test dedicato con modulo
PAM bloccante, senza bypass di autenticazione.

Test tastiera con digitazione e Invio, errore e retry senza ripristino
artificiale del focus. Il greeter resta in modalità anteprima: nessuna
sessione greetd completa è stata avviata. R-17 (più credenziali/policy)
resta aperto. Resta da isolare uno stallo intermittente del subprocesso
PAM, osservato due volte; le ripetizioni e il recupero non equivalgono a
una sua correzione alla radice. Dettagli, comandi, run e limiti in
[NATIVE-GRAPHICS-PAM.md](NATIVE-GRAPHICS-PAM.md). Nessuna modifica a wlroots.


## Passata 4d: stallo PAM isolato e helper eseguito con exec

- compositore/src/minerva-pam.c: nuovo helper non privilegiato, buffer
  limitato su stdin, identità da UID, servizio PAM verificato, una sola
  risposta nascosta, token fissi e uscita alla morte del chiamante.
- minerva-shell/blocco/Blocco.qml: PamContext sostituito da Process;
  successo con codice/status/token concordi, errore di avvio gestito,
  timeout seguito da attesa dell'uscita prima del retry.
- compositore/meson.build e costruisci.sh: aggiunta soltanto compilazione,
  controllo dipendenze e preparazione del nuovo eseguibile; non riesaminati
  integralmente gli altri componenti del compositore.
- scripts/install-minerva.sh e minerva-blocca: dipendenza PAM esplicita,
  installazione root-owned senza setuid in /usr/local/bin e preflight.
- config/pam/liquid-de: aggiornati i commenti; politica auth invariata.
- tests/native: 12 prove dirette con libpam reale/moduli di guasto controllati,
  cinque scenari QML, venti ripetizioni, stack di processo su stallo.
- workflow Shell: trigger estesi ai nuovi sorgenti e alla configurazione PAM.

Prima della correzione, run 37123810816: due stack del figlio in attesa
libc durante syslog/pam_unix. Dopo, run 37124839077 e 37124990189 verdi.
Ultimo codice fff4c054455885bf4a22e808ed129165e426b01d: 129 regressioni
e cinque scenari nativi più venti ripetizioni. Nessuna modifica a wlroots.
MFA/policy account, sessione greetd completa, blocco sicuro Wayland e
matrice hardware restano aperti; nessuna promessa di zero errori.
