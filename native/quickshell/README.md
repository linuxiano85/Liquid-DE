# Runtime locale Quickshell

La patch a Quickshell 0.3.2 aggiorna l'ordine delle voci DBusMenu anche
quando il servizio mantiene gli stessi identificatori. Non modifica le
operazioni delle applicazioni né sostituisce il pacchetto di sistema.

`source.json` registra commit, origini HTTPS e SHA-256 dei due archivi e
della patch. Quickshell è disponibile con licenze LGPL-3.0/GPL-3.0 secondo
i rispettivi avvisi; CLI11 usa BSD-3-Clause. Le licenze originali vengono
copiate accanto al binario compilato.

```sh
python3 scripts/costruisci-quickshell.py --jobs 2
```

Servono CMake, Ninja, compilatore C++, patch, binutils e le dipendenze
di compilazione di Quickshell/Qt. Il primo avvio scarica i sorgenti;
le esecuzioni successive verificano e riusano la cache. Il risultato
è `libexec/quickshell/qs`, con manifesto della versione Qt e del binario.
I sorgenti e gli oggetti di compilazione rimangono nella cache locale.
