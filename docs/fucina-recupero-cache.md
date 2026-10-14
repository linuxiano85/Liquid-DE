# Fucina: recuperare la cache dopo un'interruzione

Aggiornamento dell'8 ottobre 2026. Il recupero riapre l'accesso alla cache: non riprende né considera riuscita una compilazione interrotta e non ripara un'installazione amministrativa.

## Uso nell'app

1. Aprire **Kernel installati** e raggiungere **Sorgenti e archivi conservati**.
2. Premere **Verifica di nuovo**. Il daemon controlla il lock e i processi registrati.
3. Usare **Riapri cache** soltanto quando il controllo abilita il pulsante. Se un processo è ancora attivo, attendere e verificare di nuovo.

Il recupero conserva sorgenti, immagini, moduli, manifest e log. Rinomina soltanto `.lavoro-attivo.json` in una ricevuta `.lavoro-recuperato-<tempo>.json`. Non cancellare manualmente il segnale per aggirare un blocco: potrebbe esserci ancora un compilatore o un aiutante amministrativo al lavoro.

Se il registro è precedente a questo formato, corrotto o non verificabile, il recupero resta bloccato. Un'installazione interrotta va verificata separatamente, anche dopo un riavvio. Il pulsante non certifica l'integrità di `/boot`.

## Controlli del daemon

Il registro versione 2 include un identificatore casuale del lavoro, boot ID, namespace PID, PID e tempo iniziale del processo principale, tipo di lavoro, fase e gruppi dei processi avviati. Il tempo iniziale evita di scambiare un PID riutilizzato per il processo precedente.

Prima di avviare un comando, l'officina pubblica la fase `avvio-processo`; dopo lo spawn registra il gruppo isolato tramite `setsid`. Se il daemon termina nella finestra fra questi due passaggi, il recupero nello stesso boot rimane vietato. A conclusione di ogni comando, il gruppo viene tolto dal registro solo dopo averne verificato l'assenza.

Nello stesso avvio il recupero richiede:

- lo stesso namespace PID e un proprietario precedente terminato o che abbia rilasciato il lavoro;
- una compilazione con fase nota, senza spawn incerto o operazioni amministrative;
- gruppi registrati isolati e nessun processo ancora appartenente a quei gruppi;
- una verifica finale nativa `kill(-gruppo, 0)` che restituisca ESRCH per ogni gruppo. Il segnale zero non invia segnali ai processi. Errori di permessi e risultati incerti impediscono il recupero.

La scansione di `/proc` da sola non è atomica: un figlio può nascere mentre si leggono le directory. La verifica finale del gruppo evita di affidarsi a quella sola scansione. Anche i gruppi con zombie restano bloccati finché il kernel non ne conferma l'assenza. Le strutture di procfs e il significato del segnale zero sono descritti nella [documentazione procfs del kernel](https://www.kernel.org/doc/html/latest/filesystems/proc.html) e nel [manuale Linux di kill(2)](https://man7.org/linux/man-pages/man2/kill.2.html).

Un boot ID diverso consente di riaprire una cache con registro versione 2, perché quei processi non possono appartenere all'avvio corrente; resta obbligatoria la verifica separata di un'eventuale installazione interrotta. Registri legacy o illeggibili richiedono verifica manuale.

Diagnosi e recupero prendono lo stesso lock POSIX delle compilazioni. Il comando ricalcola i controlli sotto lock e confronta l'identificatore del lavoro: uno stato mostrato prima non autorizza a recuperare un lavoro successivo. La ricevuta viene pubblicata con rinomina senza sovrascrittura e fsync della directory.

L'IPC autenticato espone `fucina_cache_recupera` e risponde con `fucina_cache_recuperata`. Accetta soltanto il token: percorso della cache e controlli restano nel daemon. Non espone opzioni di forzatura o terminazione dei processi.

## Limiti

Il controllo copre i gruppi registrati dei comandi dell'officina. Non termina automaticamente processi e non può certificare comandi estranei che si siano deliberatamente staccati dal gruppo. Casi incerti restano bloccati. Il registro non rende le installazioni resistenti a perdita di alimentazione, SIGKILL o guasti del filesystem.

L'aiutante root aggiornato richiede ancora installazione con autenticazione sul sistema di prova. Il daemon rifiuta installazioni e rimozioni con la vecchia ABI; il recupero cache non aggira questo controllo. La prova del candidato sull'hardware, sospensione/ripresa, periferiche e confronto A/B delle prestazioni restano passaggi distinti.
