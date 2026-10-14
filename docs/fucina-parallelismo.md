# Compilare con un parallelismo adatto alla memoria

Aggiornamento dell'8 ottobre 2026.

## La scelta Auto

**Auto** sceglie i lavori di `make` considerando thread e memoria disponibile al momento. Il daemon rilegge questi dati per ogni anteprima e quando parte una compilazione: il numero finale può cambiare se altre applicazioni occupano RAM nel frattempo. La ricetta eseguita conserva il numero effettivamente usato.

Il calcolo usa:

1. `MemAvailable` da `/proc/meminfo`, limitato a `MemTotal`. Non sostituisce il dato mancante con memoria libera o swap. `MemAvailable` è una stima del kernel: [documentazione procfs](https://docs.kernel.org/filesystems/proc.html).
2. Per cgroup v2, il minimo margine `memory.max - memory.current` del gruppo del daemon e dei suoi antenati visibili. I mount vengono individuati da `mountinfo`; gli alias della stessa gerarchia, incluso quello di `bpftune`, non sono considerati gerarchie diverse. Viene scelto il mount che espone più antenati. Significato e gerarchia dei limiti: [cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html).
3. Un margine del 20%, con minimo 256 MiB e massimo 2 GiB, e una stima di 512 MiB per lavoro, aumentata a 768 MiB con ThinLTO. Il numero viene limitato ai thread rilevati, fra 1 e 512.

I valori del punto 3 sono un'**euristica dell'app**, non requisiti ufficiali di GCC/Clang o una misura del picco del kernel scelto. Con 2 GiB effettivamente disponibili, per esempio, propone tre lavori normali oppure due con ThinLTO; con 16 GiB e 12 thread può usarli tutti.

Se i dati non sono verificabili, Auto propone **un solo lavoro** e lo spiega. Questo vale anche per cgroup v1, mount ambigui, percorsi non validi, dati incompleti o contatori non interpretabili. Cgroup v1 non è ancora supportato dal rilevatore.

## Il limite manuale

I pulsanti `−` e `+` partono dal consiglio corrente. Il limite manuale viene rispettato entro i thread disponibili. Se supera il consiglio, Fucina mostra un avviso: il valore resta una scelta dell'utente. Tornando ad Auto, la UI attende una nuova ricetta prima di mostrare un numero verificato.

La compilazione non cambia sysctl, limiti cgroup, governor, SMT o mitigazioni. La lettura delle risorse non avvia programmi e non richiede root.

## Cosa non garantisce

- La memoria può cambiare durante una compilazione lunga; il numero di lavori non viene adattato in corsa.
- Una singola unità di compilazione può superare la stima. Anche un solo lavoro può esaurire la memoria.
- `memory.current` comprende memoria recuperabile: il margine calcolato può essere conservativo. `memory.high`, swap, quote CPU e antenati nascosti da un namespace non vengono modellati.
- **ThinLTO usa anche thread propri nel linker**, distinti dai lavori di `make`. Questo aggiornamento non imposta `--thinlto-jobs` e non sovrascrive i flag Kbuild. La distinzione è documentata da [Clang ThinLTO](https://clang.llvm.org/docs/ThinLTO.html#controlling-backend-parallelism).
- Non è un benchmark né una promessa di compilazione più veloce per ogni configurazione.

## Prove

- **330 test Dart passati**, inclusi MemAvailable mancante, limiti degli antenati, limite zero/esaurito, cgroup v1, mount con spazi, alias bind mount come sul PC reale, traversal, metadati corrotti, rilettura senza scritture, scelte manuali e ricette successive con memoria diversa.
- **20 prove grafiche passate**, compresa la guida al parallelismo nella viewport 780×560, incremento dal consiglio, avviso manuale e attesa del nuovo calcolo.
- Il daemon AOT reale e l'app installata sono verificati con `tests/prova_fucina_parallelismo.py`. Il dossier `Liquid_test-principale/rapporti/artefatti-2026-10/fucina2/parallelismo-reale/` conserva il risultato e il log della ripetizione incrementale del candidato non installato. Il cambio riguarda il parallelismo; l'hash dell'immagine viene confrontato prima e dopo.

Comandi ripetibili:

```sh
(cd tests/fucina_suite && dart test --reporter expanded)
FUCINA_GUI_ARTIFACT_DIR=/tmp/fucina2-gui python tests/test_fucina2_gui.py
python tests/prova_fucina_parallelismo.py \
  --canale /percorso/della/sessione/canale \
  --rilascio 7.2.9-fucina-opt-clang \
  --output /tmp/prova-parallelismo-nuova
```

Senza `--ripeti`, l'ultimo comando verifica soltanto l'anteprima e l'immagine invariata. Con `--ripeti`, ricompila lo stesso candidato non installato, conservando le scelte del manifest e passando il solo parallelismo ad Auto; sorveglia temperatura, memoria e durata. Non installa, rimuove o riavvia kernel. La directory di output deve essere nuova.
