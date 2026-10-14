# Prima di installare un kernel Fucina

Aggiornamento dell'8 ottobre 2026.

## Cosa controllare nell'app

Aprire **Kernel installati**. Il riquadro **Prima di installare: completa i prerequisiti** indica gli strumenti mancanti o l'aiutante amministrativo da aggiornare. **Aggiorna controlli** rilegge lo stato senza chiedere password o modificare il sistema.

L'installazione richiede l'aiutante compatibile con ABI 2, `pkexec`, `flock`, `depmod` e un generatore initramfs (`mkinitcpio` oppure `dracut`). La rimozione richiede aiutante, `pkexec` e `flock`. La presenza dei programmi viene controllata nei percorsi di sistema: non vengono eseguiti durante la diagnosi. Questo controllo non sostituisce la configurazione degli strumenti della distribuzione.

Se l'aiutante è obsoleto, dalla cartella del progetto aggiornare la copia amministrativa:

```sh
sudo install -m 755 scripts/minerva-radice /usr/local/bin/liquid-de-radice
```

Poi premere **Aggiorna controlli**. Il comando richiede autenticazione; l'app non lo esegue automaticamente. Se mancano programmi, installare i pacchetti previsti dalla propria distribuzione e configurare il generatore initramfs prima di procedere.

## Cosa significa «Preparato per l'installazione»

Il daemon controlla che:

- il manifest `fucina.json` sia un file regolare, leggibile e contenga il rilascio corrispondente;
- immagine e configurazione siano file regolari, presenti e non vuoti;
- le cartelle boot e moduli siano directory reali nei componenti controllati;
- non sia registrata una prova QEMU fallita.

I problemi compaiono nella scheda e impediscono l'installazione prima della richiesta di autorizzazione. I file vengono conservati. Una prova QEMU non registrata è indicata come verifica mancante, non come successo; rimane possibile installare un kernel preparato senza QEMU, come nelle versioni precedenti.

Questi controlli non calcolano un hash di ogni modulo, non ne verificano il funzionamento e non certificano firma Secure Boot, firmware, spazio libero, configurazione initramfs o correttezza del menu di avvio. L'aiutante amministrativo ricontrolla i vincoli dell'operazione, prepara moduli e initramfs e gestisce i guasti verificati. L'avvio reale e le prove sulle periferiche restano necessari.

Il kernel in uso non può essere reinstallato o rimosso. Durante un lavoro, con cache da recuperare o prerequisiti non verificati, l'interfaccia blocca l'azione pertinente. I controlli vengono rivalutati anche prima dell'invio dalla conferma e nel daemon: una schermata aperta prima di un cambiamento non autorizza una mutazione successiva.

Al termine della compilazione il riepilogo distingue la build completata dall'installazione. Se mancano i controlli, propone **Vedi controlli** e apre la pagina Kernel installati. Il kernel della distribuzione resta escluso dalle rimozioni gestibili da Fucina.

## Evidenze

- **304 test Dart passati**, inclusi manifest corrotto, rilascio diverso, file vuoti/mancanti, symlink, helper assente/non eseguibile, ABI vecchia/futura, programmi mancanti, diagnosi in errore e rifiuti senza chiamate root.
- **16 prove grafiche passate**: azioni disabilitate con helper obsoleto, prerequisiti cambiati durante la conferma, materiali incompleti e QEMU fallito.
- **9 prove mirate passate dopo l'ultima revisione ABI**: un aiutante con marcatori di versione duplicati viene rifiutato come ambiguo.
- **Daemon AOT e finestra realmente installati**: l'aiutante vecchio è riconosciuto prima dell'installazione; gli strumenti presenti sono indicati separatamente. Nessuna azione kernel amministrativa inviata dalla sonda reale.
- Immagine del candidato `7.2.9-fucina-opt-clang` invariata: SHA256 `12f65192e69504d9cb0900bd620189f5fa8c970c089d0cda9b378cca0e98e711`.

Artefatti: `Liquid_test-principale/rapporti/artefatti-2026-10/fucina2/test-dart-304.log`, `test-prerequisiti-abi-9.log`, `test-gui-16.log`, `gui-prerequisiti/`, `prova-prerequisiti-reale-finale.json`, `prova-prerequisiti-abi-univoca.json` e `runtime-prerequisiti.json`. I conteggi precedenti restano nei rapporti storici.

Per ripetere la sonda in sola lettura, usando il file canale della propria sessione:

```sh
python tests/prova_fucina_prerequisiti.py \
  --canale /percorso/della/sessione/canale \
  --rilascio 7.2.9-fucina-opt-clang \
  --output /tmp/prova-prerequisiti-nuova.json
```

`--rilascio` è facoltativo. Se presente, la sonda confronta l'immagine nella cache dichiarata dal daemon prima e dopo la lettura. Il file di output deve essere nuovo. La sonda invia soltanto richieste di stato ed elenco; non compila, installa, rimuove o recupera lavori.

Per la cache interrotta, vedere la [guida al recupero](fucina-recupero-cache.md). Per compilazione, KVM, test del kernel e limiti del confronto prestazionale, vedere il [rapporto di ottimizzazione](../audit/chatgpt/FUCINA2-AUDIT-OTTIMIZZAZIONE.md).
