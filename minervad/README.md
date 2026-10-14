# minervad

Demone di Liquid DE. Gestisce impostazioni, informazioni di sistema,
applicazioni, file, periferiche e servizi della sessione. La shell comunica
attraverso un socket Unix con messaggi JSON delimitati da una nuova riga.

## Compilazione

Dalla radice del progetto, con l'SDK Dart e le dipendenze richieste dall'installer:

```sh
./scripts/minerva-compila
```

Lo script prepara i binari in `minervad/build/` e li sostituisce solo dopo
una compilazione riuscita. Per installare l'ambiente usare l'installer
dalla radice del progetto. Le prove e i rapporti sono conservati in Liquid_test.

## Struttura

- `bin/`: punti di ingresso.
- `lib/core/`: impostazioni e servizi condivisi.
- `lib/ipc/`: protocollo con la shell.
- `lib/services/`: integrazione con il sistema.
