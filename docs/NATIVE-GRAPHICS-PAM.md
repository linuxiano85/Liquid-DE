# Prove grafiche e PAM della Shell

## Ultimo esito verificato — passata 4d, 3 ottobre 2026

Commit `fff4c054455885bf4a22e808ed129165e426b01d`,
[Actions 37124990189](https://github.com/linuxiano85/Liquid-DE/actions/runs/37124990189):
**cinque job riusciti, 129 regressioni, cinque scenari grafici/PAM e venti
ripetizioni aggiuntive**. Nessun fallimento ignorato o test saltato.
Le regressioni sono 59 JS, 22 Python greeter, 18 Dart launcher, 16 Dart
greetd, 2 nmcli e 12 nuove prove del helper PAM. Analisi Dart senza rilievi,
intero demone compilato; helper C compilato con `-Wall -Wextra -Werror`.
Anche la prima run della correzione, 37124839077, passa tutti i job,
quattro scenari nativi e venti ripetizioni.

## Ambiente e punto d'ingresso

Job `native-graphics-pam` di `.github/workflows/shell-regressions.yml`:
runner Ubuntu 24.04, contenitore Arch Linux usa e getta, Quickshell 0.3.1,
Qt 6.11.2, PAM 1.7.3, Mesa 26.2.4, Xvfb a 1360×768 con rendering OpenGL
software. Le versioni sono in `native-results/versions.txt`; font Adwaita
e Noto installati. Le schermate sono catture reali, non immagini generate.

Il comando è `LIQUID_NATIVE_CI=1 bash tests/native/run.sh`, esclusivamente
nel contenitore preparato dal job. Il runner rifiuta l'avvio senza questa
variabile e senza `/.dockerenv`. Crea l'account fittizio `liquidci` e servizi
PAM interni al contenitore. Non va eseguito su un sistema personale.
Il flag è un controllo contro errori d'uso, non una sandbox.

Il test copia il punto d'ingresso nella cartella `minerva-shell` per
rispettare il confine degli import Quickshell. Carica `Greeter.qml` e
`Blocco.qml` reali, inclusi shader e dipendenze QML. Quickshell e il helper
PAM girano come utente non root. Il servizio normale è una copia di
`config/pam/liquid-de`, con `pam_unix` e `pam_faillock` veri. I moduli
controllati servono soltanto a provocare errori, richieste aggiuntive e stalli.

## Stallo riprodotto e correzione

Le prime run 37101843474 e 37102153213 mostravano una verifica PAM che non
terminava. Il commit `360014c` ha esteso le ripetizioni: nella run fallita
[37123810816](https://github.com/linuxiano85/Liquid-DE/actions/runs/37123810816),
GDB ha acquisito due stack del figlio bloccato con questa catena:

```text
__lll_lock_wait_private (libc)
... (__syslog_chk)
pam_vsyslog / pam_syslog (libpam)
pam_sm_authenticate (pam_unix)
pam_authenticate
quickshell
```

L'attesa è quindi localizzata dentro libc durante il logging di pam_unix.
La traccia è coerente con mutex ereditati dal processo Qt multithread dopo
`fork()` senza `exec()`. Lo stesso meccanismo è segnalato nella issue
upstream [Quickshell #964](https://github.com/quickshell-mirror/quickshell/issues/964).
La traccia non identifica il mutex interno preciso; non si attribuisce il
problema a wlroots o alla GPU.

`Blocco.qml` ora usa `Quickshell.Io.Process` per eseguire il piccolo
`minerva-pam`, senza usare `PamContext`. L'esecuzione separata avvia PAM in
un processo nuovo, rimuovendo il percorso che ereditava i mutex grafici.
Non introduce un fork di Quickshell né cambia il fork wlroots.

Il helper:

- gira con UID/GID dell'utente, senza setuid; ricava il nome dall'UID reale,
  non dalle variabili USER/LOGNAME;
- riceve la password via stdin fino a EOF, con limite di 4096 byte;
  rifiuta input vuoto, NUL incorporati e dimensioni superiori;
- richiede un servizio PAM presente, regolare, root-owned e non scrivibile
  da gruppo/altri; rifiuta percorsi e non usa il fallback implicito `other`;
- risponde a una sola richiesta nascosta; richieste aggiuntive o visibili
  falliscono come metodo non supportato, senza reinviare la password;
- restituisce soltanto token fissi e codici di uscita: nessuna credenziale,
  nome account o messaggio PAM grezzo nell'output del helper;
- disabilita i core dump, pulisce il proprio buffer e termina alla morte
  del chiamante; ha inoltre una scadenza autonoma di 65 secondi.

Il QML accetta successo soltanto con uscita normale, codice 0 e token
esatto `ok\n`. La scadenza grafica resta di 60 secondi: uccide la verifica,
attende l'uscita e poi permette un nuovo tentativo. Una risposta tardiva
non sblocca e una verifica precedente non si sovrappone alla successiva.

## Installazione

Meson compila `compositore/src/minerva-pam.c` e il normale script di build
lo prepara insieme agli altri eseguibili. `scripts/install-minerva.sh`
include la dipendenza PAM e installa per rinomina il helper root-owned
in `/usr/local/bin/minerva-pam`, permessi 0755, senza setuid.
Dopo aggiornamento occorre eseguire l'installatore: la sola copia dei QML
non installa il nuovo eseguibile. `minerva-blocca` segnala l'assenza del
helper prima di richiedere il blocco dello schermo.

Il test CI compila e installa direttamente il helper nel contenitore.
Non equivale a una reinstallazione completa del desktop né a una nuova
build del compositore/wlroots sulla macchina di destinazione.

## Casi verificati

1. **Percorso normale:** rendering di greeter e blocco, campo mascherato;
   greeter in anteprima incapace di avviare una sessione; password vuota
   ignorata, password errata respinta, invio duplicato ignorato, password
   corretta dopo la pausa con un solo segnale di sblocco e campo pulito.
2. **Modulo PAM assente:** guasto distinto da password errata, nessuno
   sblocco e nessuna penalità del contatore password.
3. **Tastiera reale X11:** digitazione e Invio tramite xdotool, errore e
   retry senza ripristinare artificialmente il focus del campo.
4. **Modulo PAM bloccante:** verifica del timer di produzione a 60 secondi,
   poi accelerato a 1,2 secondi soltanto nel test. Nessuno sblocco; processo
   fermato, messaggio di retry, campo pulito e successiva autenticazione
   pam_unix riuscita sullo stesso componente.
5. **Helper non avviabile:** errore esplicito, nessuno sblocco o penalità;
   dopo ripristino del comando, autentica sullo stesso componente.

Il percorso normale viene ripetuto altre venti volte per run. Tutti i
marcatori sono obbligatori; timeout, errori QML e asserzioni fallite fanno
fallire il job. GDB raccoglie stack dopo 12 secondi nel solo contenitore
con capacità SYS_PTRACE, usando soltanto credenziali fittizie.

Le dodici prove dirette del helper verificano inoltre password reale,
identità da UID anche con USER/LOGNAME falsi, Unicode/newline/metacaratteri,
limiti di input, NUL, servizio mancante/traversal, proprietà e permessi dei
file PAM, modulo assente, prompt multipli/visibili, PAM_MAXTRIES, assenza
del segreto da argv/ambiente e terminazione alla morte del processo padre.

Restano valide le correzioni della passata 4c: campo cancellato prima dello
sblocco, distinzione tra guasto e password errata e recupero dopo timeout.
Svuotare il campo non garantisce azzeramento di tutte le copie in memoria
nel runtime Qt/QML.

## Limiti espliciti

La rimozione del percorso fork-only e due run verdi con venti ripetizioni
ciascuna sono evidenza della correzione, non una garanzia di assenza di
ogni possibile stallo in qualunque modulo PAM.

Il greeter è renderizzato in anteprima: non è una prova end-to-end di
minervad → greetd → PAM → apertura della sessione. Il blocco usa PAM vero
in una finestra X11 di test, non nel protocollo di blocco sicuro Wayland.
Restano da provare sul sistema di destinazione cambio VT, crash, chiusura
forzata del locker, più monitor, scaling, layout tastiera, sospensione e
ripresa, prestazioni e fluidità sulla GPU.

R-17 resta aperto: conversazioni MFA/impronta complete non implementate;
si mantiene la politica esistente `pam_authenticate`, senza aggiungere
`pam_acct_mgmt`. I prompt non supportati falliscono senza sbloccare.
Le Impostazioni e il resto della Shell non sono renderizzati da questo
harness. Nel contenitore manca PipeWire: il relativo errore di connessione
è un limite dell'ambiente e l'audio non viene dichiarato verificato.
