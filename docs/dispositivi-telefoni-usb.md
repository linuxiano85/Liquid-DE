# Telefoni USB: componenti e integrazione Minerva

Piano registrato l'11 ottobre 2026 su richiesta dell'utente. Primo incremento
implementato, collaudato e installato nella stessa giornata. Su richiesta
successiva eliminati guida e pulsante fissi: il telefono compare solo se
rilevato. Prova fisica e monitoraggio a eventi ancora da completare.

## Problema osservato e verifiche

Al collegamento dello smartphone manca un percorso chiaro per capire lo stato
USB e accedere ai dati dal desktop.

Nella diagnosi iniziale, prima dell'intervento:

- `gio` e GVfs sono presenti; manca il backend `gvfs-mtp`.
- Manca anche il backend `gvfs-gphoto2`, necessario alla presentazione PTP.
- L'elenco `gio mount -l -i` non espone un telefono.
- Dopo che l'utente ha riferito di averlo collegato, `lsusb` non mostra un
  nuovo dispositivo telefonico. Questo non prova che il cavo sia difettoso:
  modalità del telefono, porta e cavo devono essere controllati con hardware
  reale. Non è stato possibile provare un trasferimento.
- L'installatore non include attualmente i backend telefonici nell'elenco
  `PKGS`. Il file manager segnalava MTP mancante insieme a Samba sotto
  «Connetti a un server», posizione poco comprensibile per chi collega un telefono.

## Vincolo Android

Android gestisce la funzione USB esposta: trasferimento file MTP, foto PTP,
ricarica e le altre modalità disponibili sul modello. La procedura ufficiale
richiede di sbloccare il telefono e scegliere **Trasferimento file** nella
notifica USB del telefono.

Minerva deve indicare questa procedura e agire sulle capacità effettivamente
esposte al PC. Un pulsante del desktop può aprire un telefono disponibile;
non può garantire il cambio di modalità sul telefono. Un dispositivo che non
si enumera sul bus USB non fornisce al PC un evento su cui mostrare un avviso.
Se non viene rilevato alcun telefono, il file manager non mostra una voce
telefonica vuota né una guida separata, come richiesto dall'utente.

Riferimento primario:
[Trasferire file con Android](https://support.google.com/android/answer/9064445).
Backend disponibili:
[GVfs MTP su Arch](https://archlinux.org/packages/extra/x86_64/gvfs-mtp/),
[GVfs PTP su Arch](https://archlinux.org/packages/extra/x86_64/gvfs-gphoto2/).

## Esperienza proposta

1. Quando un telefono è riconosciuto, voce nella barra laterale con nome e
   stato reale. Nessuna finestra aggiuntiva e nessuna apertura automatica.
   In assenza di telefoni non compare alcun elemento telefonico.
2. In modalità dati, azione **Apri file** o **Apri foto**, secondo la capacità
   esposta. Il montaggio parte dalla richiesta dell'utente.
3. Se il tentativo di apertura viene respinto dal telefono, indicare la causa
   effettiva e l'azione necessaria. Dopo il cambio di modalità aggiornare la
   voce; non dedurre il blocco dalla semplice assenza del dispositivo.
4. Lasciare il telefono in carica non richiede un'azione nel file manager.
5. Le dipendenze telefoniche fanno parte dell'installatore. Una dipendenza
   assente non crea una voce di telefono non rilevato.
6. Dopo lo scollegamento, rimuovere il dispositivo dalla barra laterale e
   dare un errore comprensibile alle operazioni interrotte. Le altre cartelle
   e gli altri dispositivi rimangono utilizzabili.

## Componenti del progetto

| Componente proposto | Responsabilità |
|---|---|
| `DispositiviUsbService` nel demone | Inventario iniziale, eventi di collegamento/scollegamento, correlazione dei dispositivi e dei volumi GIO, stato e capacità. |
| Adattatore eventi udev/GIO | Osservazione degli eventi di sistema; verificare l'accesso senza privilegi e la gestione della disconnessione. Aggiornamenti guidati dagli eventi, senza scansioni USB continue. |
| `Dispositivi.qml` nel core della shell | Modello condiviso tra shell e file manager; identificativi della connessione, aggiornamenti di stato, richieste di apertura. |
| Riga dispositivo (`SideEntry`) | Presentazione nativa nel file manager, coerente con il preset attivo, senza dialogo aggiuntivo. |
| Sezione dispositivi del file manager | Telefoni rilevati, stato, apertura e scollegamento logico. Nessuna voce telefonica fissa quando il dispositivo non compare. |
| Diagnostica USB | Riassunto di ciò che è rilevato e delle dipendenze mancanti; log tecnici esportabili senza numero seriale o contenuti del telefono. |

Il trasferimento usa il backend GVfs già integrato in `LuoghiRemoti` e le
operazioni di `FileService` sui percorsi locali esposti da GVfs. I componenti
Minerva possiedono presentazione, orchestrazione e diagnostica. Questa divisione
consente la stessa esperienza nei preset Liquid, Windows e negli altri temi.

## Modello di stato e identità

Stati da rappresentare separatamente:

- dispositivo riconosciuto, funzione dati non disponibile;
- backend assente;
- volume dati disponibile, ancora da aprire;
- apertura in corso;
- accesso non autorizzato / telefono bloccato, solo quando confermato;
- volume aperto;
- errore, con causa e azione ripetibile;
- scollegato.

Non dedurre lo stato «solo ricarica» o «bloccato» dalla sola assenza di un
volume MTP. Nomi commerciali e produttori non bastano per classificare un
dispositivo come smartphone. MTP comprende anche lettori multimediali.

Ogni collegamento ha una propria generazione. Cambiare modalità USB può
provocare rimozione e nuova enumerazione: le risposte di una generazione
precedente devono essere scartate. Un solo avviso per collegamento, con
aggiornamento dello stato, senza duplicazioni durante l'enumerazione.
Supportare contemporaneamente due telefoni dello stesso modello.

Le richieste di apertura riportano ora un identificativo della richiesta e
della scheda destinataria. Il vecchio `apriDopoCollega`, che conservava una
sola URI, è stato sostituito: le risposte concorrenti raggiungono la scheda
originaria; quelle relative a una scheda chiusa, a una navigazione successiva
o a una richiesta sostituita vengono scartate. La generazione del dispositivo
USB resta da integrare insieme al monitoraggio degli eventi.

## Ordine di realizzazione

1. **Prerequisiti e barra laterale:** distinguere le dipendenze dei telefoni
   da quelle della rete; aggiungere MTP/PTP all'installatore, con manifesti
   coerenti e messaggi in italiano/inglese. Verificare l'installazione sul PC
   con normale autenticazione di amministratore.
2. **Inventario ed eventi:** prova con telefono vero, verifica del passaggio
   tra modalità e della visibilità udev/GIO. Scegliere l'adattatore sulla base
   di questa prova; inventario coerente anche quando il demone viene riavviato.
3. **Interfaccia Minerva:** stato nella barra laterale e apertura indirizzata
   alla finestra corretta. Nessuna apertura automatica dei contenuti o di
   finestre di aiuto. Eventuali notifiche future richiedono una scelta di UX
   coerente con questa richiesta dell'utente.
4. **Operazioni e recupero:** copia, annullamento, scollegamento durante il
   trasferimento, due telefoni, riconnessione e diagnostica.

La scelta della modalità sul telefono non richiede ADB o l'attivazione delle
opzioni sviluppatore per il normale trasferimento MTP.

## Collaudo necessario prima dell'installazione

- Prove automatiche del modello: eventi duplicati, risposte tardive,
  disconnessione, riavvio, due dispositivi uguali, backend assente, errori di
  montaggio e richieste contemporanee da schede diverse.
- Prova grafica privata: avvisi e guida con ogni preset, mouse e tastiera,
  nessun furto di focus, Non disturbare, rimozione del dispositivo.
- Prova fisica: telefono bloccato/sbloccato, MTP, PTP se supportato, ritorno
  alla ricarica, cavo senza dati, scollegamento e riconnessione.
- Copia verso una directory temporanea e confronto dei byte; nessuna
  cancellazione dei contenuti personali come prova. Le modifiche sul telefono
  richiedono un percorso di test concordato.
- Misurare latenza dell'avviso, CPU a riposo e crescita della memoria; nessun
  processo di scansione lanciato periodicamente per tutta la sessione.
- Esaminare tutti i log e le schermate; documentare distintamente simulazioni
  e prove con hardware reale. Artefatti nel repository test adiacente.

## Stato corrente

### Primo incremento installato

- `gvfs-mtp` e `gvfs-gphoto2` installati con autenticazione amministrativa;
  aggiunti anche alle dipendenze del normale installatore Minerva.
- Nel file manager il telefono compare direttamente nella barra laterale
  quando GVfs lo rileva. Guida `TelefonoUsb.qml` e **Collega un telefono**
  eliminati dopo la richiesta dell'utente; resta l'apertura del volume.
- Le dipendenze della rete sono separate da quelle telefoniche. L'assenza
  di un dispositivo non viene presentata come prova di sola ricarica.
- Corretto il riconoscimento delle radici GVfs `mtp://[usb:002,015]/` e PTP:
  non sono normali host IPv6 e il precedente parser URI le rifiutava.
- Aperture concorrenti indirizzate alla scheda corretta, senza cambiare il
  focus. Anche il dialogo server distingue le proprie risposte.

Verifiche iniziali: **41** prove del file manager in sessione grafica privata,
**51** prove del servizio remoto, **50** regressioni file/socket,
**4** prove dell'installatore, **60** regressioni shell e **259** verifiche
Windows con **236** compilazioni QML. I dispositivi delle prove grafiche
sono simulati. Gli artefatti sono in
`../Liquid_test-principale/rapporti/telefoni-usb/`.

Dopo la rimozione della guida, **42/42** prove aggiornate: telefono assente,
due dispositivi nella barra laterale, apertura senza dialoghi, rimozione dei
telefoni che conserva il server e risposte concorrenti/tardive. Artefatti in
`../Liquid_test-principale/rapporti/telefoni-usb-sidebar/`. Copiati i nuovi
sorgenti nella radice; la finestra File già aperta ha `watchFiles = false`
e conserva il vecchio QML fino al riavvio del suo processo. Non è stata chiusa
automaticamente una finestra dell'utente per applicare il cambiamento.

Il gestore file installato è stato aperto nella sessione reale su una
cartella sintetica, verificato tramite IPC e immagine privata, poi chiuso
ripristinando il focus. Il demone installato conferma i backend MTP/PTP;
al controllo successivo all'installazione non espone ancora un telefono.
Il compositore non è stato riavviato.

### Passo successivo

Verificare sul telefono sbloccato la notifica USB e la modalità Trasferimento
file; attendere la conferma dell'utente prima di continuare con prove che
dipendono da questa azione. Non sono stati modificati contenuti del telefono
né eseguiti trasferimenti fisici. Inventario a eventi e recupero dei
trasferimenti restano i successivi incrementi.
Per ora il file manager conserva il proprio aggiornamento periodico già
esistente; non è stato aggiunto un monitor USB permanente.

## Confronto con altri desktop e nuova diagnosi USB

Controllati l'11 ottobre 2026 i pacchetti locali: presenti COSMIC Files e KDE
Plasma/Dolphin con KIO Extras, Solid e libmtp. Sono presenti librerie GNOME,
ma questo non equivale a un'installazione completa di GNOME Files.

| Desktop | Gestione verificata nei sorgenti ufficiali |
|---|---|
| GNOME | `Gio.VolumeMonitor` segnala aggiunta/rimozione dei volumi. La shell valuta sessione attiva, preferenza automount, `should_automount()` e `can_mount()` prima di montare. Il file manager espone i dispositivi nella barra laterale. |
| COSMIC | `src/mounter/gvfs.rs` costruisce l'elenco da volumi e mount GIO, evita il doppione di un volume già montato e ascolta aggiunta/rimozione/cambiamento. |
| KDE | `kmtpd.cpp` ascolta gli eventi di Solid, seleziona lettori con protocollo MTP e usa libmtp; il Device Notifier offre azioni sui dispositivi rilevati. |

Fonti primarie:
[GNOME AutomountManager](https://github.com/GNOME/gnome-shell/blob/main/js/ui/components/automountManager.js),
[GIO VolumeMonitor](https://docs.gtk.org/gio/class.VolumeMonitor.html),
[GNOME sidebar](https://help.gnome.org/gnome-help/files-removedrive.html),
[COSMIC GVfs](https://github.com/pop-os/cosmic-files/blob/master/src/mounter/gvfs.rs),
[KDE MTP](https://github.com/KDE/kio-extras/blob/master/mtp/kiod_module/kmtpd.cpp),
[KDE Device Notifier](https://userbase.kde.org/Plasma/DeviceNotifier).

La nuova lettura del journal rileva ripetuti `device descriptor read/64,
error -71`, `device not accepting address` e `unable to enumerate USB device`
sulle porte `2-1.5` e `2-1.6`. `lsusb` e GIO non espongono un telefono, mentre
i monitor GVfs MTP/PTP sono in esecuzione. Senza enumerazione non si arriva
al livello MTP gestito dal desktop. Non è ancora certa l'identità del
dispositivo che produce questi errori: manca un descrittore USB valido.

`-71` corrisponde a `EPROTO`; la
[documentazione del kernel](https://docs.kernel.org/driver-api/usb/error-codes.html)
indica che errori di questo tipo normalmente accompagnano problemi di
dispositivo/firmware o cavo e che il controller può non distinguere le cause.
Non prova da solo che il cavo sia guasto. La prossima verifica fisica deve
correlare il collegamento del telefono ai log, preferibilmente con un altro
cavo dati e una porta diretta, attendendo l'utente dopo averla richiesta.
