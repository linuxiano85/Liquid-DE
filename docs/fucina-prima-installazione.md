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

Per la cache interrotta, vedere la [guida al recupero](fucina-recupero-cache.md).
