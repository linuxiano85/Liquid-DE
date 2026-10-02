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
