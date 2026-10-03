# Prove grafiche e PAM della Shell

## Ambiente e punto d'ingresso

Job `native-graphics-pam` di `.github/workflows/shell-regressions.yml`:
runner Ubuntu 24.04, contenitore Arch Linux usa e getta, Quickshell 0.3.1,
Qt 6, Xvfb a 1360×768 e Mesa con rendering OpenGL software. Le versioni
installate sono conservate in `native-results/versions.txt` e nel log dei
pacchetti. I font Adwaita e Noto sono installati per il test finale.

Il comando è `LIQUID_NATIVE_CI=1 bash tests/native/run.sh`, esclusivamente
nel contenitore preparato dal job. Il runner rifiuta l'avvio senza questa
variabile e senza `/.dockerenv`. Crea l'account fittizio `liquidci` e due
configurazioni PAM interne al contenitore. Non va eseguito su un sistema
personale. Il flag è un controllo contro errori d'uso, non una sandbox.

Il test copia il proprio punto d'ingresso nella cartella `minerva-shell`
per rispettare il confine degli import Quickshell. Carica i componenti reali
`Greeter.qml` e `Blocco.qml`, inclusi shader e dipendenze QML. Non sostituisce
il componente PAM con un mock. La configurazione normale è una copia di
`config/pam/liquid-de`, con `pam_unix` e `pam_faillock`; quella guasta fa
riferimento a un modulo inesistente. Quickshell gira come utente non root.

## Casi verificati

- Caricamento/rendering del greeter e del blocco, campo password mascherato.
- Greeter in anteprima: dati utente/sessione simulati, invio senza avvio
  di sessione e pulizia della risposta.
- Password vuota: nessuna autenticazione avviata.
- Password errata: rifiuto PAM reale, blocco mantenuto e campo pulito.
- Invio duplicato: una sola operazione e un solo errore conteggiato.
- Password corretta dopo la pausa: un solo segnale di sblocco, contatore
  azzerato e campo pulito prima di consegnare lo sblocco.
- Modulo PAM guasto: nessuno sblocco, diagnostica di sistema conservata,
  nessun incremento del contatore delle password errate.
- Percorso da tastiera: eventi X11 tramite xdotool, digitazione e Invio
  per password errata e corretta; il test non ripristina artificialmente
  il focus del campo fra i due tentativi.

I log devono contenere i quattro marcatori di successo; timeout, errori QML e
fallimenti delle asserzioni rendono il job fallito. Le schermate PNG e i log
sono scaricabili dall'artefatto `native-graphics-pam` della run Actions.
Contengono soltanto l'account e i dati fittizi del test.

## Difetti riprodotti e corretti

La run 37101542308 riproduce entrambi sul codice precedente alla correzione:

1. Il successo PAM emetteva `sbloccato` lasciando la password nel campo.
   Ora il campo viene svuotato su ogni completamento, prima del segnale,
   e anche quando `pam.start()` fallisce. Questo non promette azzeramento
   sicuro di tutte le copie della stringa nella memoria del runtime.
2. Quickshell emette `error` e poi `completed(PamResult.Error)`: il secondo
   handler sovrascriveva la diagnostica con “Password sbagliata” e applicava
   la penalità dei tentativi. Ora distingue il guasto e conserva il motivo.

3. La verifica non aveva una scadenza: uno stallo PAM lasciava il campo
   disabilitato indefinitamente. Un timer di 60 secondi ora annulla soltanto
   l'autenticazione, svuota il campo e rende possibile un nuovo tentativo.
   Il test carica un modulo PAM C che si ferma in `pause()` senza creare
   figli; accelera il timer a 1,2 secondi nel solo test, verifica l'assenza
   di sblocco e poi autentica davvero con pam_unix sullo stesso componente.

## Anomalia intermittente da seguire

Le run 37101843474 e 37102153213 hanno rilevato uno stallo del subprocesso
PAM. Nel secondo caso Quickshell registra l'invio della risposta; il
subprocesso non registra il suo consumo e, dopo 30 secondi, il contesto è
ancora `active=true, responseRequired=true`. Non è dimostrata la causa:
non si attribuisce il difetto a wlroots, alla GPU o a PAM senza prove.

La run successiva 37102325724 ha passato cinque ripetizioni consecutive
oltre ai tre scenari principali. Questo non chiude l'anomalia intermittente.
La CI mantiene cinque ripetizioni e non ignora un fallimento seguito da
successo. Dopo 12 secondi di attesa raccoglie stack tramite GDB nel solo
contenitore (capacità SYS_PTRACE); le credenziali sono tutte fittizie.
La nuova scadenza mitiga il blocco permanente, non dimostra la correzione
alla radice del subprocesso. Non introdurre un fork di Quickshell senza
aver isolato ulteriormente il problema.

## Limiti espliciti

Il greeter è renderizzato in anteprima: non è una prova end-to-end di
minervad → greetd → PAM → apertura della sessione. Il componente di blocco
usa PAM reale, ma è ospitato in una normale finestra di test X11, non nel
protocollo di blocco sicuro Wayland. Non dimostra resistenza alla chiusura
forzata del locker, cambio VT, crash del compositore o altri monitor.

Restano da provare sul sistema di destinazione: sessione greetd completa,
blocco Wayland sicuro, autenticazione multi-fattore/impronta, layout tastiera
multipli, scaling, più monitor, sospensione e ripresa, prestazioni e fluidità
sulla GPU. Le impostazioni e il resto della Shell non sono renderizzati da
questo test. Nel contenitore manca PipeWire: il relativo errore di connessione
è un limite dell'ambiente e l'audio non viene dichiarato verificato.


## Esito dell'ultima revisione verificata

Commit `bb0644c0372f66dcd610e98fd9a0fedc309fd576`,
[Actions 37102502767](https://github.com/linuxiano85/Liquid-DE/actions/runs/37102502767):
tutti e cinque i job riusciti. Le 117 regressioni esistenti restano verdi
(59 JS, 22 Python greeter, 18 Dart launcher, 16 Dart greetd, 2 nmcli),
oltre a quattro scenari nativi e cinque ripetizioni del caso password.
Analisi Dart senza rilievi e intero demone compilato. Le quattro schermate
finali sono state aperte e ispezionate a 1360×768. Nessuna misura di FPS.
La documentazione successiva non cambia i sorgenti verificati.
