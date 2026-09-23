# I moduli di Minerva

> Giacomo, 11 agosto 2026: «crealo in modo che sia modulare, in modo che se
> qualcosa non va o non ci piace sostituiamo il modulo con qualcosa di nuovo.
> Semplice, espandibile, e senza limiti di creatività: nel senso che non
> abbiamo vincoli su cosa possiamo fare e cosa no.»

Questo file esiste perché una decisione non scritta decade. Il 29 luglio 2026
avevamo deciso «una porta sola verso il compositore» e non l'avevamo scritta
da nessuna parte: il 11 agosto le chiamate dirette erano passate da 75 a 106.
Nessuno aveva disobbedito — semplicemente non c'era niente a cui obbedire.

---

## La regola, in una riga

**Un modulo è una cosa che si può buttare via senza riscrivere il resto.**

Se per sostituirlo bisogna toccare più di un file, non è un modulo: è
un'abitudine sparsa. E il modo per accorgersene prima che sia tardi non è la
buona volontà — è una prova che conta.

---

## Le due libertà, e perché non sono in conflitto

Un confine è per definizione un vincolo: dice cosa passa e cosa no. Sembra il
contrario di «nessun limite alla creatività». Non lo è, a una condizione:

> **Il confine si mette dove finisce il substrato, mai attraverso un'idea
> nostra.**

`Compositore` limita quello che possiamo chiedere a *Hyprland* — e va bene,
perché quel limite ce l'ha messo Hyprland, non noi: lo stiamo solo rendendo
visibile in un posto invece che in venticinque. Se domani un'idea non passa
dalla porta, la risposta non è «non si può fare»: è **allargare la porta**, e
se il substrato non ce la fa, è il substrato ad andare sostituito. È
esattamente per poterlo fare che la porta esiste.

Il vincolo che va evitato è l'altro: un modulo che decide al posto nostro
*cosa Minerva è*. Per questo la politica delle finestre non sta in
`Compositore` ma in `Windows`: cosa vuol dire «ingrandisci» lo decidiamo noi,
e nessun compositore ci può dire di no.

---

## La mappa, oggi

### 1. Il compositore — `minerva-shell/core/Compositore.qml`

**Cosa fa:** traduce. Sa come si dice in Hyprland «porta questa finestra
davanti», e non sa altro. Nessun elenco, nessuna memoria, nessun timer.

**Il contratto:** funzioni per intenzione (`fuoco`, `davanti`, `chiudi`,
`libera`, `sposta`, `ridimensiona`, `schermoIntero`, `portaAScrivania`,
`vaiAScrivania`, `imposta`, `ricarica`), più tre segnali
(`finestreCambiate`, `scrivanieCambiate`, `evento`).

**Sostituirlo costa:** un file. `core/Scorciatoia.qml` va con lui, perché
`GlobalShortcut` è un tipo dello stesso modulo.

**La prova che lo tiene:** `minervad/test/porta_compositore_test.dart` —
fallisce se un solo altro file nomina Hyprland.

**Fuori restano due**, e hanno una ragione che vale la regola di questo file:
caricano e scaricano il plugin, e stanno dentro uno `sh` che crea una
SENTINELLA prima e la toglie dopo — così una sessione che si spegne durante il
carico non riprova al riavvio. Il caricamento deve stare **in mezzo** a quelle
due cose: portarlo fuori taglierebbe attraverso un'idea nostra, non attraverso
il substrato.

**Il buco che la prova aveva**, e vale per chiunque ne scriva una: cercava
`"hyprctl"` — con le virgolette, cioè la forma `command: ["hyprctl", …]`.
Passava mentre ventidue chiamate vivevano nell'altra forma, dentro le righe di
shell (`fireSh("hyprctl keyword …")`). **Una guardia che guarda da una parte
sola è peggio di nessuna guardia**: dà per chiuso un confine aperto.

### 2. Il compositore, lato demone — `minervad/lib/providers/compositor_provider.dart`

`abstract class CompositorProvider`, con `HyprlandProvider` sotto. Nato
astratto, e il commento originale già diceva «si può scambiare con
NiriProvider, CosmicProvider». Ha una lista bianca chiusa dei comandi
ammessi: i messaggi arrivano da un socket, e un socket non deve poter
eseguire qualunque cosa.

### 3. Le applicazioni — un processo per gruppo

`filemanager.qml`, `settings.qml`, `app.qml`, `minervamedia.qml`,
`viewer.qml`, `greeter.qml`, `blocco.qml`. È la modularità più forte che
abbiamo, e la più costosa: **ogni processo paga il pavimento di Qt, 31 MB
disegnando col processore**. Il prezzo è deliberato — un errore QML in un
punto qualunque, in un processo solo, butterebbe giù l'ambiente intero.

Il prezzo però si paga **per processo e non per programma**, e questa è la
correzione del 18 agosto 2026: un'app in più nello stesso processo costa 5 MB,
un processo in più ne costa 70. Quindi Calcolatrice, Editor, Anteprima e
Attività stanno insieme dentro `app.qml` — quattro programmi che non si
parlano fra loro, in una casa sola: 108 MB invece di 315.

La linea di taglio non è «un file, un processo»: è **quanto fa male se cade**.
La scrivania sta da sola perché se cade lei non hai più niente. Il gestore file
sta da solo perché ci si copia dentro per minuti. Le quattro piccole stanno
insieme perché se cade quella casa hai perso una calcolatrice.

Sostituire un'applicazione vuol dire cancellare un file `.qml` e scriverne un
altro. Nessun altro pezzo se ne accorge.

### 4. I servizi del demone — `minervad/lib/services/` (ventuno)

Uno per argomento: rete, bluetooth, file, archivi, meteo, data e ora, lingua,
accesso, processi. Parlano solo attraverso il bus (vedi `EVENTS.md`).
Sostituirne uno vuol dire tenere le stesse azioni sul bus.

### 5. I plugin del demone — `minervad/lib/plugins/plugin_manager.dart`

Programmi esterni con un manifesto, avviati dal demone. Regola scritta nel
codice e provata: **un plugin rotto non può impedire l'accesso al computer.**
Manifesto illeggibile, cartella assente, permessi sbagliati: si tira dritto.

### 6. Il plugin del compositore — `plugins/minerva-bars/`

C++ dentro Hyprland: barre del titolo, aggancio, misura alla nascita.
È il modulo **più fragile che abbiamo**, e va detto: si rifiuta di partire se
l'hash del commit di Hyprland non coincide con quello di compilazione. Ogni
aggiornamento del compositore lo spegne finché non si ricompila.

Quando manca, la shell ridisegna le barre da sé (`spine/TitleBars.qml`): la
via di riserva esiste ed è provata.

### 7. Il tema — `minerva-shell/theme/`

`Colors.qml` tiene le tinte in `schemes`; `Typography`, `Effects`, `Motion` il
resto. Un tema nuovo è una voce in più in un oggetto. La regola che lo rende
vero: **nessun colore scritto a mano fuori da `theme/`** — e quando si viola,
succede quel che è successo alla dock, che restava nera mentre tutto il resto
si schiariva.

### 8. I servizi di sistema — `minervad/lib/services/dbus.dart`

**Cosa fa:** parla con BlueZ, e domani con NetworkManager e con
`systemd-logind`, attraverso D-Bus. `proprieta`, `oggetti`, `scrivi`,
`ceIlServizio`, con i valori già spacchettati dal loro involucro.

**Perché è un modulo:** sotto c'è ancora `busctl --json=short`, perché Dart
non ha un client D-Bus nella libreria standard e il demone ha **zero
dipendenze** — è ciò che lo tiene a 22 MB. Il giorno che ne scriveremo uno
vero, cambia solo quel file.

**Cosa ha già evitato:** il Bluetooth si leggeva con
`bluetoothctl show | grep 'Powered: yes'`, e quando BlueZ ha smesso di
stampare `Address:` Minerva dichiarava «nessun adattatore» su un computer col
Bluetooth acceso. `org.bluez.Adapter1.Powered` è un booleano oggi ed è un
booleano fra due anni.

**Cosa NON è stato spostato, e perché:** la rete. Usa già
`nmcli -t -f TYPE,NAME`, che è un formato per macchine, più letture di
`/proc` e `/sys`. Non è prosa: spostarla costerebbe due chiamate al posto di
una senza guadagnare niente. Lo stesso vale per `timedatectl show` (KEY=VALUE)
e `/etc/locale.conf`. **Il difetto era uno solo, e adesso è chiuso.**

### 9. Le scorciatoie — `config/scorciatoie.minerva`

**Cosa fa:** tiene le novantacinque scelte di Minerva («F1 apre il promemoria»)
nel vocabolario di Minerva, con le loro ragioni scritte accanto.

    Super K            -> minerva: cheatsheet
    Super 3            -> scrivania: 3
    Super Maiusc 3     -> porta-a-scrivania: 3
    XF86AudioMute [anche-bloccato] -> minerva: volumemute

**Il contratto:** `minervad/lib/services/scorciatoie.dart` legge la sorgente e
`perHyprland()` la traduce. È l'unico punto del progetto in cui «vai alla
scrivania 3» diventa `workspace, 3`. Un altro compositore vuole un'altra
funzione come quella, e nient'altro.

**Il prodotto** `config/hypr/keybinds.conf` sta sotto git perché Hyprland lo
legge all'avvio, **prima che il demone esista**: generarlo a caldo vorrebbe
dire una sessione che parte senza tasti. Si rigenera con
`./scripts/minerva-scorciatoie`.

**La prova che lo tiene:** `scorciatoie_sorgente_test.dart` rigenera e
confronta. Due file che dicono la stessa cosa vanno alla deriva — è la prova a
rendere vera la divisione, non il codice che genera.

**Cosa si è guadagnato oltre all'indipendenza:** il pannello F1 non fa più il
parsing della sintassi di Hyprland. Prima sì, e un cambiamento di quella
sintassi lo avrebbe svuotato **senza dare nessun errore**.

**La misura:** 48 scorciatoie su 95 erano già neutre (`minerva:` e `avvia:`),
47 usavano un dispatcher di Hyprland. Una prova impedisce che le neutre
scendano sotto 48.

---

## Come si aggiunge un modulo

1. **Scrivi il contratto prima dell'implementazione**, e scrivilo in
   intenzioni («porta questa finestra davanti»), non in comandi del substrato
   («alterzorder top»).
2. **Nessuno stato se non serve.** `Compositore` non ne ha, e per questo può
   essere usato dentro un'applicazione senza tirarsi dietro mezza shell.
3. **Una via di riserva quando il modulo può mancare.** Il plugin C++ può non
   caricarsi: la shell disegna le barre da sé. Un modulo che, mancando, lascia
   l'ambiente inutilizzabile non è un modulo: è una dipendenza travestita.
4. **Una prova che difende il confine.** Non «funziona», ma «nessun altro lo
   scavalca». È l'unica parte che non si può rimandare: senza, il confine
   dura fino alla prossima fretta.

---

## Quel che resta da fare

- Il comando che spegne il Wi-Fi è ancora `nmcli`: si può portare su D-Bus,
  ma non si può PROVARE senza staccare la rete a chi sta lavorando. Si farà
  quando la prova si potrà fare su una macchina che non è questa.
- Le 909 righe di `config/hypr/` sono il substrato che parla di sé: oggi non
  hanno un modulo, e sono la ragione per cui cambiare compositore costerebbe
  ancora più di un file.
