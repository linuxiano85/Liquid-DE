# Intestazioni delle app esterne in Tiling

Minerva nasconde le proprie decorazioni in Tiling. Le intestazioni disegnate
dentro un'app richiedono la collaborazione del client: non vengono ritagliati
pixel e non vengono alterate le coordinate dei clic.

## COSMIC Terminal e COSMIC Files

Gli adattatori facoltativi sono costruiti dalle versioni 1.9.0 originali con
una patch MPL-2.0 di libcosmic. Revisioni e licenze sono in
`patches/apps-tiling/versions.json`; la ricetta rifiuta modifiche alle altre
dipendenze già fissate nei lockfile.

Ogni finestra segue gli stati TILED ricevuti da Wayland. In Tiling rimane
una barra compatta con i comandi dell'app: menu, ricerca, pannello laterale
e nuova scheda. Non contiene titolo, trascinamento, riduzione, ingrandimento
o chiusura. In Classico torna l'intestazione originale. La preferenza
`show_headerbar` dell'app non viene riscritta.

Le build per Minerva usano il monitoraggio dei file di configurazione previsto
da libcosmic. Non cercano `cosmic-settings-daemon`, che Minerva non avvia.
Le altre funzionalità predefinite delle due app restano abilitate.

```sh
python3 scripts/costruisci-app-tiling.py --jobs 4
```

Servono Cargo/Rust compatibili con i sorgenti (almeno Rust 1.93), Git e le
dipendenze di compilazione delle app COSMIC. Sorgenti e cache Cargo rimangono
in `$XDG_CACHE_HOME/liquid-de/apps-tiling`, oppure in `~/.cache/liquid-de/apps-tiling`.
Si possono scegliere con `--cache`. Le build usano priorità ridotta quando
`nice` e `ionice` sono disponibili. I binari vanno in `libexec/tiling`.
Pacchetti di sistema e configurazioni personali non vengono sostituiti.

Le licenze e la patch vengono conservate accanto ai binari. Per distribuire
gli adattatori modificati conservare anche questa ricetta, le revisioni
originali e i sorgenti della patch, rispettando le licenze delle app.

## Shelly / GTK4

Il piccolo modulo `libminervatiledheaders.so` usa gli eventi GDK, senza
polling. Nasconde soltanto la decorazione predefinita GTK4 quando la finestra
è tiled e ripristina la sua scelta originale tornando in Classico. Le
intestazioni personalizzate con comandi dell'app restano disponibili.

```sh
sh scripts/costruisci-tiled-headers.sh
```

Il modulo si attiva soltanto nel launcher Shelly di Minerva. Non collega GTK
alle app Qt o COSMIC. Il descrittore e il preload usati per caricarlo vengono
rimossi prima dell'avvio dei processi figli. Shelly continua a gestire una
sola istanza: l'adattatore non aggiunge capacità multi-finestra all'app.

## Installazione e ripristino

L'installer di Minerva costruisce il modulo GTK e copia gli adattatori COSMIC
se sono già stati compilati. Al nuovo accesso, prima della scansione del
catalogo, prepara i launcher delle app disponibili. Le sessioni di prova
non modificano i launcher dell'utente.

Per una verifica manuale dalla radice **installata**:

```sh
python3 scripts/minerva-installa-app-tiling.py --dry-run
python3 scripts/minerva-installa-app-tiling.py
```

Gli ID desktop e le azioni delle app restano quelli originali. I launcher
personali precedenti vengono salvati in
`$XDG_STATE_HOME/liquid-de/app-tiling` (di serie `~/.local/state/liquid-de/app-tiling`).
La ricevuta conserva l'impronta precedente fino all'attivazione della nuova
copia: un'interruzione durante una prima installazione o un aggiornamento
può essere ripresa o ripristinata.

```sh
python3 scripts/minerva-installa-app-tiling.py --remove
```

Il ripristino rifiuta di sovrascrivere modifiche successive dell'utente.
Fuori da Minerva i launcher usano i programmi originali in `/usr/bin`.
`MINERVA_TILED_HEADERS=0` permette di avviare la versione originale anche
dentro Minerva.

## Prove

Nel repository Liquid_test sono incluse prove reali di GTK4, Shelly, COSMIC
Terminal e COSMIC Files in un compositore privato: cambi Classico/Tiling,
finestre in stanze con layout diversi, ingrandimento, minimizzazione,
scorciatoie, menu con il mouse e schermate delle due modalità. Le prove dei
launcher usano directory XDG temporanee e verificano installazione,
reinstallazione, interruzione e ripristino.

Sono adattatori per le versioni elencate, non un metodo universale per
nascondere le intestazioni di tutte le applicazioni Linux.

La prova XWayland ritarda soltanto quattro messaggi reali di associazione,
nel compositore privato, per riprodurre il caso in cui il primo buffer arriva
prima della finestra. Gli altri cicli usano il normale ordine degli eventi.
Una build separata priva della correzione fallisce già al primo ciclo;
la build candidata supera 60 cicli, con 240 finestre effettive.
