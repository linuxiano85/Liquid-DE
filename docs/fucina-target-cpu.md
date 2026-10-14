# Target CPU: una scelta spiegata e verificabile

Aggiornamento dell'8 ottobre 2026.

## Cosa mostra Fucina

La panoramica distingue due informazioni:

| Informazione | Significato |
| --- | --- |
| x86-64 v1–v4 | Livello ISA rilevato dai flag comuni delle CPU descritte in `/proc/cpuinfo` |
| Target native di GCC e Clang | Nome dichiarato da ciascun compilatore installato per il PC corrente, per esempio `haswell` |

Il livello ISA non è il nome di una microarchitettura. `-march=native` chiede al compilatore di rilevare la macchina locale; può produrre codice non utilizzabile su altre CPU. `-mtune` riguarda invece la scelta del tuning entro le istruzioni consentite. Queste distinzioni sono descritte nelle [opzioni x86 di GCC](https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html).

Per un kernel dedicato al PC corrente si può provare **Ottimizza questo PC**. Per un'immagine da usare su hardware diverso scegliere **Compatibilità più ampia**. Il pannello **Il target scelto dai tuoi compilatori** mostra l'evidenza e permette di aprire la configurazione con **Rivedi il target CPU**.

La sonda non sceglie GCC o Clang sulla base del nome restituito: due compilatori possono dichiarare lo stesso target e produrre risultati diversi. La presenza di `haswell`, per esempio, non dimostra un guadagno prestazionale. Il vantaggio va misurato sul kernel avviato, con carichi comparabili.

## CPU con capacità diverse o dati incompleti

Il rilevatore legge tutte le righe `flags`, anziché soltanto la prima CPU, e ne calcola l'intersezione. Confronta anche il numero delle righe con i processori descritti. Flag vuoti o mancanti non sono considerati un rilievo completo.

Se i flag non sono uniformi o completi, la UI propone generico e il daemon rifiuta una richiesta `nativo: true` prima di avviare la compilazione. È una scelta conservativa: non tenta di decidere quali differenze siano innocue per ogni versione del compilatore. Non applica pinning dei processi o modifiche all'hardware.

Il confronto riguarda le CPU descritte nel rilievo corrente; non certifica CPU future collegate a caldo, migrazioni di VM o hardware diverso. La documentazione delle informazioni esposte dal kernel è in [procfs](https://www.kernel.org/doc/html/latest/filesystems/proc.html).

La topologia NUMA assente viene ora mostrata come **non rilevata**, senza inventare un singolo nodo. Un kernel compilato senza NUMA può non esporre quella topologia.

## Come sono eseguite le sonde

Gli argomenti sono fissi nel daemon:

```sh
gcc -Q --help=target -march=native -mtune=native
clang -### -march=native -x c -c /dev/null -o /dev/null
```

GCC espone i valori delle opzioni con `-Q --help=target`: [documentazione GCC](https://gcc.gnu.org/onlinedocs/gcc/Overall-Options.html). Clang con `-###` stampa i comandi senza eseguirli: [opzioni del driver Clang](https://clang.llvm.org/docs/CommandGuide/clang.html#driver-options). Non vengono compilati sorgenti o eseguiti programmi generati dalle sonde.

Ogni processo ha un limite di tre secondi e un massimo di 64 KiB complessivi fra stdout/stderr. Errori, uscita non riuscita, timeout, diagnostica eccessiva e target non riconoscibile rimangono **non verificati**. Le richieste simultanee condividono le sonde in corso; un nuovo rilievo successivo può rileggerle dopo un aggiornamento dei compilatori. Le sonde non richiedono root.

Il payload contiene solo compilatore, target, tuning, esito e messaggio. Non pubblica gli argomenti interni completi di Clang, i percorsi personali o il suo output grezzo. L'IPC non permette al chiamante di scegliere un eseguibile o argomenti arbitrari.

## Limite rispetto a Kbuild

Questa è una verifica del driver del compilatore sul sistema corrente, non del comando effettivo di ogni oggetto del kernel. Kbuild imposta opzioni proprie e limita l'uso di alcune istruzioni. La ricetta continua a verificare `CONFIG_X86_NATIVE_CPU` dopo Kconfig e a fermarsi se il requisito esplicito non è attivo. Per Clang e gli altri strumenti LLVM vedere [Kbuild LLVM](https://docs.kernel.org/kbuild/llvm.html).

Le sonde non cambiano governor, SMT, mitigazioni, frequenze o sysctl. Non confrontano le prestazioni di GCC e Clang e non certificano stabilità del kernel futuro.
