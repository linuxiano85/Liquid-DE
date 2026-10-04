# Fucina, manutenzione e apertura File

Fucina è integrata da `fucina-kernel` (e76a8f0) conservando le correzioni
Shell/PAM già presenti in `principale` (f8f5e2e).

## Correzioni

- Le patch Cachy vengono verificate in avanti prima di applicarle. Se fallisce,
  una verifica inversa senza inversione automatica distingue una patch già
  presente da una patch incompatibile o applicata solo in parte. Nessuna domanda
  interattiva può bloccare il processo. La preparazione continua a partire
  dall'archivio vanilla verificato; non è stata confermata una doppia applicazione
  sul PC dell'utente.
- modprobed-db: percorsi XDG attuali, percorsi precedenti e DBPATH personalizzato;
  nessuna esecuzione della configurazione shell. Un diario vuoto è distinto
  dall'assenza del programma.
- Manutenzione: rimozione orfani non ricorsiva, manifesto root-owned delle
  dipendenze Liquid obbligatorio, rifiuto di pacchetti contenenti kernel o file
  d'avvio. L'installatore marca le dipendenze dirette come esplicite. Prima di
  rimuovere orfani su installazioni precedenti occorre aggiornare l'installazione.
- La pulizia manuale non cancella più i temporanei di sistema: l'età della
  directory non prova che i suoi discendenti siano inattivi.
- File: avvii serializzati, IPC e avvio limitati nel tempo, consegna della
  richiesta dopo la disponibilità del processo, fallback se lo scope systemd
  fallisce. La risposta IPC deve confermare esplicitamente la richiesta, anche
  quando Quickshell restituisce successo con un target assente. Il precaricamento non apre finestre e non assorbe il primo clic.

## Verifica

La suite `tests/fucina_suite` incorpora gli otto test Fucina di Liquid_test
al commit 8b40658cf1bc28269f80ad78c2cbf5dcde9e8149, più nuove regressioni.
Eseguire `dart pub get` e `dart test` nella sua directory. Gli strumenti della
compilazione kernel sono simulati nei test dell'officina; le prove di patch
usano GNU patch e file reali. La prova del contenitore initramfs richiede cpio.

`python3 tests/test_recovery_scripts.py` verifica concorrenza, IPC bloccato e
protezione degli orfani con comandi isolati: non rimuove pacchetti reali.
La CI compila il demone completo e avvia Fucina e File in Quickshell su Wayland/Sway headless,
conservando immagini e registri. Il test di File richiede layer-shell: su X11
la creazione dei menu può restare incompleta e non costituisce una prova valida. Restano attive le prove native Shell/PAM.

Non equivalgono a una compilazione completa e avvio del kernel sul PC reale,
né dimostrano la causa del precedente schermo nero. Per quella diagnosi servono
il registro pacman della pulizia e il journal dell'avvio fallito. Il ramo
`perfezionamento` contiene ulteriori cambiamenti che richiedono una revisione
separata delle sovrapposizioni con le protezioni Shell/PAM attuali.
