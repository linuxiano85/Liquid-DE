# Desktop Windows 11

In **Impostazioni → Aspetto → Stile della scrivania → Windows 11** si
attiva una shell dedicata, con la disposizione dello Start classico di Windows
11. Le applicazioni Liquid mantengono la propria interfaccia. Ogni preset
conserva separatamente le preferenze dell'aspetto e del comportamento, tiling compreso.

## Cosa comprende

- Barra inferiore da 48 pixel, pulsanti centrati, meteo a sinistra, stato del
  sistema e orologio a destra; una barra per ogni monitor.
- Start con applicazioni aggiunte, Tutte le app, ricerca locale e documenti
  recenti. Nelle impostazioni si può scegliere anche lo Start Liquid con le
  categorie Linux.
- Passaggio tra Aggiunte e Tutte le app con scorrimento e dissolvenza del
  contenuto; ricerca e barra dell'account mantengono la posizione. Esc torna
  indietro o cancella la ricerca prima di chiudere Start; Tab e frecce
  selezionano le applicazioni, Invio e Invio del tastierino le avviano.
- Applicazioni raggruppate nella barra e anteprime delle singole finestre.
  Clic centrale per aprire una nuova finestra; clic destro per aggiungere o
  togliere un'app dalla barra. Le finestre dello stesso processo restano distinte.
- Impostazioni rapide, volume, luminosità quando disponibile, Wi-Fi,
  Bluetooth, luce notturna, Non disturbare e accesso alle impostazioni audio,
  accessibilità e monitor. I controlli hardware seguono lo stato reale del sistema.
- Notifiche, calendario navigabile, widget meteo e calendario, menu della
  scrivania e del pulsante Start, icone della tray con menu D-Bus.
- Ombre morbide dei pannelli e dei menu, con intensità diversa nei temi
  chiaro e scuro. Le piccole immagini riutilizzabili sono generate dagli SVG
  originali: non richiedono una sfocatura continua durante l'uso.
- Pannelli con ingresso e uscita per scorrimento e dissolvenza. La chiusura
  restituisce subito tastiera e mouse alle applicazioni; il contenuto rimane
  visibile soltanto fino all'ultimo fotogramma, poi viene scaricato.
- Visualizzazione attività con anteprime salvate, navigazione con frecce e Tab,
  creazione e chiusura dei desktop e trascinamento delle singole finestre.
  Chiudere un desktop trasferisce le sue finestre a un altro desktop.

## Personalizzazione

La scheda Windows 11 sta nella pagina **Personalizzazione → Preset** (fino
all'11 ottobre 2026 era in Aspetto) e si vede solo col preset Windows. Permette
di scegliere Start, tema chiaro o scuro, colore d'accento, barra e pannelli di
vetro, documenti consigliati e visibilità del pulsante tiling. Il pulsante
tiling è inizialmente nascosto. Il tiling si configura nella sezione Finestre.

Nel tema scuro è possibile applicare l'accento anche a Start e barra. I colori
del testo e dei controlli vengono adattati per mantenere il contrasto leggibile.
Nel tema chiaro le superfici restano neutre; la preferenza viene conservata.

Lo sfondo può seguire il tema, usare Bloom Light o Bloom Dark oppure conservare
lo sfondo personale. Cambiando preset si recuperano le sue ultime preferenze,
senza riapplicare la disposizione di fabbrica. Liquid, Minerva, Mac, Windows e
Libero ricordano effetti, angoli attivi, barra, dock, colori, icone, sfondi,
animazioni, tiling e scorciatoie separatamente. Si può abilitare l'acquerello
in Liquid e disabilitarlo in Windows, oppure abilitarlo in entrambi.
Il funzionamento è descritto in [Preferenze separate per preset](preset-isolati.md).

I controlli hardware, la lingua, la località del meteo, i controller, le
credenziali e le impostazioni di sicurezza restano comuni. I file sulla
scrivania e le finestre aperte restano gli stessi; la disposizione delle icone
può cambiare tra i preset. La migrazione conserva il preset attivo e recupera
la vecchia disposizione Libero. Il meteo usa la località configurata in Data, ora e lingua: senza una
località non vengono richieste previsioni.

## Marchio e risorse

Il pulsante Start usa la nuova L fluida Liquid. Le tre proposte sono in
[assets/marchio/liquid](../assets/marchio/liquid/README.md).

Le icone di sistema sono tracciati Microsoft Fluent System Icons sotto licenza
MIT; Selawik è sotto SIL Open Font License. Quando è installato, viene preferito
Segoe UI. Provenienza e licenze sono incluse in
[windows11](../minerva-shell/windows11/).
Gli sfondi Bloom sono opere Microsoft / Six N. Five, con provenienza documentata;
non sono opere originali Liquid né rientrano nella licenza del codice del progetto.
Per questo i file `.jpg` restano fuori dal repository (`.gitignore`): chi li ha
sul disco li vede, gli altri hanno gli sfondi di Liquid.

Le schermate di questa pagina sono da rifare. Quelle dell'11 ottobre mattina
mostravano Bloom sullo sfondo, quindi ne ridistribuivano dei pezzi, e una barra
ormai cambiata: non sono entrate nel repository (Claude, 11 ottobre sera).

## Verifica

```sh
dart run tests/windows11_settings_probe.dart
dart run tests/desktop_profiles_probe.dart
python3 tests/prova_windows11.py
```

La prima prova verifica salvataggio, migrazione del vecchio preset e rifiuto
di valori non validi, senza collegarsi alla sessione desktop. La prova dei profili
controlla tutti i passaggi tra i cinque preset, la persistenza dopo riavvio,
le impostazioni comuni e il recupero di preferenze danneggiate. La prova grafica avvia
un compositore privato con due monitor, clienti Wayland e servizi tray reali;
invia input reali e acquisisce immagini del risultato. Copre finestre multiple,
riduzione e ripristino, desktop, trascinamento, scorciatoie, selettori nelle
Impostazioni, notifiche, tray, scollegamento di un monitor e risoluzioni fino
a 3840×2160 con scala 2. Nessun input viene inviato alla sessione dell'utente.

I rapporti JSON e i log si trovano in `Liquid_test-principale/rapporti/windows11`
accanto al progetto; `MINERVA_TEST_REPORT_DIR` permette di scegliere un'altra
cartella. Le immagini dimostrative usano un catalogo e documenti di prova.

La verifica delle ombre confronta immagini con lo stesso sfondo: controlla
la sfumatura all'esterno dei pannelli e l'assenza di residui dopo la chiusura,
nei due temi. Per rigenerare le risorse: `python3 scripts/costruisci-ombre-windows.py`
(richiede `rsvg-convert`).

La verifica delle transizioni registra i fotogrammi realmente presentati da Qt,
con avanzamento, opacità, contenuto caricato e stato del focus. Controlla Start,
ricerca, impostazioni rapide, calendario, alimentazione, meteo e panoramica;
include riapertura durante la chiusura, cambio pannello, clic ripetuti e
disattivazione delle animazioni. Il blocco dello schermo e la rimozione del
preset cancellano immediatamente anche l'immagine in uscita. Il movimento
dura al massimo 167 ms e non lascia animazioni attive a pannelli chiusi.
Durata e scorrimento seguono i criteri di
[movimento Fluent](https://learn.microsoft.com/en-us/windows/apps/design/motion/);
questo non certifica tempi di presentazione della GPU fisica né una replica
visiva completa di Windows. Le tracce sono in `motion.json` accanto al rapporto.

La navigazione interna dello Start mantiene distinti il catalogo delle app
aggiunte e quello completo anche durante la dissolvenza. Solo la vista
selezionata accetta input. La ricerca mostra subito i risultati; le animazioni
disabilitate producono un cambio immediato. La prova include inversione della
navigazione, chiusura a transizione avviata, riapertura, ripristino del focus e
avvio tramite tastierino. Le tracce dei fotogrammi sono in `start-views-motion.json`.
La direzione delle transizioni segue i criteri Microsoft per
[navigazione tra pagine](https://learn.microsoft.com/en-us/windows/apps/develop/motion/page-transitions).

## Come Windows 11: riferimenti e scelte (11 ottobre 2026, Claude)

- **Materiale.** Microsoft Learn,
  [Materials](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/materials):
  l'Acrylic (vetro smerigliato, traslucido) è per le superfici che compaiono
  e spariscono, come pannelli e menu; il Mica (opaco, appena tinto dallo
  sfondo) è per le finestre. Quindi:
  - barra, calendario, impostazioni rapide, Widget, Visualizzazione attività
    e notifiche usano un colore solo, `Style.barra` / `Style.pannello`, preso
    dal colore della barra (accento compreso);
  - col vetro acceso (`windows11.acrylic`, di serie sì) il compositore sfoca
    quello che sta dietro solo per il namespace `liquid-windows11` (verbo
    `vetrobarra`), anche se l'effetto delle finestre è spento;
  - la shell usa la trasparenza solo se il compositore ha risposto «ok si»:
    un compositore vecchio non conosce il verbo, e i pannelli restano pieni.
- **Alimentazione nello Start.** Il pulsante apre un menu subito sopra di sé
  con Opzioni di accesso, Sospendi, Arresta il sistema e Riavvia il sistema
  (fonti: Microsoft Q&A, Tom's Guide); un clic esegue. Il nome dell'account
  apre Cambia impostazioni account, Blocca e Disconnetti.
- **Menu «Liquid» al posto dello Start.** Si apre centrato sopra il pulsante
  Start, coi colori della barra (se chiaro/scuro coincidono con Liquid) e coi
  pulsanti di alimentazione.
- **Visualizzazione attività.** Oltre al trascinamento sulla miniatura di un
  desktop: tasto destro su una finestra → «Sposta in» → un desktop o «Nuovo
  desktop», senza seguire la finestra.
- **Misure della barra.** 48 px; Start, Ricerca, Visualizzazione attività e
  app con simboli da 24 px in pulsanti da 40 (Ricerca e Visualizzazione
  attività erano a 18 e sembravano più piccole).
- **Meteo sulla barra.** Il simbolo ha il colore del tempo (sole giallo,
  pioggia blu, nuvole grigie), sempre reso leggibile sul colore vero della
  barra; prima era del colore d'accento, che sulla barra colorata spariva.
- **Pulsanti della barra del titolo.** Fonti: Microsoft Learn, «Windows app
  title bar» (barra di 32 px, fondo pieno fino al bordo, segni
  ChromeMinimize/Maximize/Restore/Close, stati a riposo, sopra, premuto e
  inattivo), e le risorse della barra di WinUI (pulsanti di 46 px, «chiudi»
  `#C42B1C`). Col preset Windows:
  - tre rettangoli da 46 px alti quanto la barra, attaccati all'angolo
    destro: riduci, ingrandisci/ripristina, chiudi. Lo schermo intero non ha
    pulsante e resta su Super+F, come in Windows;
  - sopra un pulsante il fondo si riempie col colore del testo appena
    accennato; sopra «chiudi» diventa rosso col segno bianco, e il rosso
    segue l'angolo tondo;
  - sempre a destra, anche se in Liquid si sono scelti a sinistra: il lato
    resta salvato per gli altri preset;
  - segni sottili da 10 px disegnati da noi, uguali nel compositore
    (`compositore/src/barra.c`, verbo `stilebarra liquid|windows`, mandato da
    `core/WindowRules.qml`) e nelle nostre app (`ui/TitleBarContent.qml`).

  Un compositore che non conosce `stilebarra` lo rifiuta senza danni e tiene
  i pulsanti di Liquid. Prove: `compositore/prove/prova-barra.c` (geometria,
  clic, disegno), `tests/prova_barra_titolo.py` (Alacritty vero, rosso sotto il
  puntatore, un clic chiude) e `tests/prova_file_manager.py` (le nostre barre).

### Colori e materiali dai gettoni di Windows (fase A, 11 ottobre 2026 sera)

il manutentore: «i colori delle schede non sono coerenti, in Windows sono
leggermente in blur: cerca l'esatta combinazione che si adatti a tutte le
combinazioni di colori di Windows, anche per il colore manuale».

- **Fonte:** `microsoft/microsoft-ui-xaml` (MIT), commit
  `fe9d01273af3382ea570e203ab700772528d98df`:
  - `Common_themeresources_any.xaml` per i gettoni: testo, schede, bordi,
    controlli, fondi, colori di stato;
  - `AcrylicBrush_themeresources.xaml` per le ricette;
  - `AcrylicBrush.cpp/.h` per l'ordine delle fusioni, il raggio 30 e il
    rumore 0,02.

  Copia di lavoro in `../Liquid_test-principale/riferimenti/winui`, valori in
  `minerva-shell/windows11/Gettoni.js`.
- **Schede:** `CardBackgroundFillColorDefault` (bianco al 70 % in chiaro, al
  5 % in scuro) con `CardStrokeColorDefault`, trasparenti sopra il materiale.
  È il «leggermente in blur»: il vetro si vede attraverso la scheda.
- **Acrylic vero nel compositore.** Sullo sfondo sfocato:
  1. fusione di **luminosità** col colore della tinta all'opacità di
     luminosità (scuro `#2C2C2C` a 0,96, chiaro `#FCFCFC` a 0,85): passano
     tinta e saturazione dello sfondo, non i contrasti;
  2. fusione di **colore** con la tinta alla sua opacità (0,15 e 0);
  3. rumore al 2 %.

  Verbo `vetrobarra si <tinta> <op> <lum> <op>`, risposta `ok si acrylic`;
  `minerva_blur.frag` fa le fusioni W3C non separabili. Un compositore
  vecchio risponde «ok si»: allora la shell stende la tinta con l'opacità
  di luminosità.
- **Accento:** sei sfumature, Light1–3 e Dark1–3 (`ColorMath.palette`).
  - La formula di Windows non è pubblica. La luminosità OKLCH è tarata
    sulla tavolozza di serie che Windows scrive nel registro (`#99EBFF`
    `#4CC2FF` `#0091F8` `#0078D4` `#0067C0` `#003E92` `#001A68`), con
    scarto ≤ 0,002.
  - La tinta resta quella scelta (Windows la sposta un poco, in un modo non
    documentato).
  - Vale uguale per i 48 colori della griglia e per un colore manuale.
- **Uso dell'accento come Windows:**
  - riempimenti: Light2 in scuro, Dark1 in chiaro;
  - testo d'accento: Light3 e Dark2;
  - testo sull'accento: nero in scuro, bianco in chiaro, se si legge;
  - con «accento su Start e barra» (solo in scuro): Start e flyout Dark1, la
    barra Dark2, scendendo di una sfumatura se il bianco non si legge.
- **Prova:** `node --test tests/windows11-colori.test.mjs`.
  - Taratura sull'azzurro.
  - Ordine delle sfumature, testo, indicatori e superficie tinta per 48 + 200
    accenti.
  - Trasparenza delle schede e ricetta del vetro.

## Prossimi incrementi

### Isole Liquid disattivate in Windows

Per la richiesta dell'11 ottobre, il preset Windows e la barra Windows 11
disabilitano temporaneamente la Riva: nessuna Isola, Centro Liquid, Cassetto,
colonna Stanze o guida al mantenimento di Super. Non compaiono da bordi,
angoli attivi, cambio desktop o richieste IPC. Un'isola aperta viene chiusa
quando si passa a Windows e non riappare tornando a Liquid.

Start, notifiche, meteo, impostazioni rapide e Visualizzazione attività
continuano a usare i pannelli Windows; Ctrl+Maiusc+Esc apre il Monitor come
finestra. Il menu Liquid scelto esplicitamente come variante dello Start
rimane disponibile. Le preferenze della Riva sono conservate nei rispettivi
preset: passando a Liquid, Minerva o Mac tornano utilizzabili. Il Cassetto
Liquid con Super+V resta temporaneamente disabilitato in Windows, in attesa
di una presentazione coerente con questo stile.

La prova usa la shell completa su due monitor, stimola bordi e angoli,
aperture dirette e IPC, mantiene premuto Super, cambia desktop e passa fra
Liquid e Windows con ogni pannello aperto. Controlla visibilità, stato logico
e conservazione delle preferenze; risultati dell'incremento nel diario.

### Lavori successivi

La parte destra della taskbar usa ora componenti dedicati:
`SystemStatus.qml` mostra rete e volume per livello, batteria con riempimento
proporzionale e fulmine di carica; `ClockButton.qml` usa formato locale,
preferenza 12/24 ore e anno completo. La campanella distingue notifiche da
leggere e Non disturbare, anche quando il silenzio è automatico durante un
gioco. Il clic mantiene gli ingressi ai pannelli Windows già esistenti.

Il risparmio della batteria segue `profiloRisparmio` del compositore, che
riporta il profilo energetico effettivo; non basta spegnere gli effetti o
avere il 20% per dichiarare quel profilo attivo. Il simbolo è verde in carica,
rosso sotto o al 5%, ambra in risparmio e neutro altrimenti; carica prevalente
per non suggerire che una batteria collegata stia ancora scaricandosi.
Colori corretti per la leggibilità sul tema/accento. Nessuna batteria finta
sui desktop che non ne hanno una e nessuna nuova interrogazione periodica.

Riferimenti: [stati batteria Microsoft](https://blogs.windows.com/windows-insider/2025/01/24/announcing-windows-11-insider-preview-build-26120-3000-dev-channel/),
[notifiche e Non disturbare](https://support.microsoft.com/en-us/windows/experience/notifications-and-do-not-disturb-in-windows),
[taskbar e impostazioni rapide](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-taskbar-in-windows).
Le nuove icone Fluent sono MIT, dallo stesso commit delle precedenti;
provenienza in `windows11/fluent-SOURCE.md`. La batteria dinamica è disegnata
in QML. Le prove modificano gli ingressi dei componenti nella sessione privata,
senza cambiare volume PipeWire, connessioni o profilo energetico reali.

Ogni incremento viene verificato prima di aggiornare la sessione:

1. Transizioni durante il cambio desktop; apertura e chiusura dei pannelli
   e navigazione interna dello Start sono implementate e verificate.
2. Presentazione Windows delle Impostazioni: fatta il 12 ottobre, vedi
   «Impostazioni» qui sotto.
3. Tema di icone coerente: copertura di applicazioni, cartelle e tipi di file,
   risoluzione delle icone mancanti e provenienza documentata.
4. Adozione progressiva dello stile Windows nelle applicazioni Liquid e
   ombre delle finestre classiche gestite dal compositore.

La barra dei desktop è già collocata in basso nella Visualizzazione attività.

### Impostazioni

Dal 12 ottobre (Claude), nel preset Windows le Impostazioni si presentano come
Impostazioni di Windows 11. Le pagine, le funzioni e le chiavi sono le stesse
di Liquid: cambia solo come si presentano, e tornando a Liquid tutto torna
com'era.

- **Navigazione** (`settings/NavigazioneWindows.qml`):
  - in cima chi usa il computer, con nome e foto di AccountsService;
  - sotto la ricerca «Trova un'impostazione», che cerca anche dentro le
    pagine come la ricerca di Liquid;
  - poi otto categorie in un elenco piatto, con la barretta d'accento sulla
    categoria aperta.
- **Le categorie** di Windows, con dentro le pagine di Liquid:

  | Categoria | Pagine |
  | --- | --- |
  | Sistema | Schermo, Audio, Notifiche, Alimentazione, Scorciatoie, Informazioni |
  | Bluetooth e dispositivi | Bluetooth, Tastiera e mouse, Controller |
  | Rete e Internet | Rete |
  | Personalizzazione | Preset, Aspetto, Scrivania, Finestre, Barra e dock |
  | App | App predefinite, Avvio |
  | Account | Utente, Account online, Accesso |
  | Data/ora e lingua | Data, ora e lingua |
  | Accessibilità | Accessibilità |

  Ogni pagina sta in una categoria sola, e la prova lo controlla.
- **Pagina di categoria** (`settings/CategoriaWindows.qml`): una scheda per
  pagina, con icona, descrizione e freccia. Le categorie di una pagina sola
  la aprono direttamente.
- **Briciola.** «Sistema › Schermo» sopra la pagina, a 28 px; un clic sulla
  categoria riporta alla sua pagina di schede.
- **Colori, raggi e carattere** di Windows 11:
  - fondo #F3F3F3 e #202020, schede dai gettoni `CardBackground` e
    `ControlStroke`, testo e accento di `windows11/Style.qml`;
  - angoli da 4 e da 8, carattere di Windows (Segoe UI se c'è, altrimenti
    Selawik).

  Le 22 pagine non sono state riscritte. La finestra presta questi valori
  alla tavolozza del proprio processo (`presentazione` in
  `theme/Colors.qml` ed `Effects.qml`, `carattere` in `Typography.qml`), e
  le pagine li seguono. Le altre applicazioni hanno la loro copia della
  tavolozza e non cambiano.
- **Comandi.**
  - Le schede che si aprono e chiudono sono gli Expander di Windows: angoli
    da 4, filo di contorno, freccia in giù o in su.
  - L'interruttore è quello di Windows 11, con «Attivato»/«Disattivato» a
    sinistra.
  - Il cursore ha la maniglia tonda col punto d'accento.
  - Lo spazio del comando in una riga si allarga se il comando è più largo
    (`SettingRow.qml`), così l'interruttore con la scritta non esce dalla
    scheda.

**Prova:** `python3 tests/prova_impostazioni_windows.py`. Usa la finestra
vera, il compositore privato e il demone di prova.

- Controlla:
  - la colonna di Liquid e i suoi colori prima e dopo;
  - le otto categorie, la pagina di categoria, la briciola avanti e
    indietro, la categoria con una pagina sola;
  - un interruttore che scrive al demone, la ricerca;
  - chiaro e scuro, e una cattura per ognuna delle 22 pagine.
- Non tocca le impostazioni vere.

**Limiti.**

- I corpi del testo restano la scala di Liquid (16/14 px).
- Le pagine che disegnano a mano qualcosa di loro restano come sono, per
  esempio i valori in accento di Tastiera e mouse e le anteprime dei temi
  in Aspetto.
- Non ci sono le pagine «Home», «Giochi», «Privacy e sicurezza» e
  «Windows Update»: non hanno un servizio Liquid dietro, e non si aggiungono
  pagine vuote.

### Segnalazioni dell'11 ottobre: interazione e bacheca

Le anteprime della barra mantengono l'identità delle finestre anche quando
un terminale cambia titolo durante un clic. Le viste lunghe offrono barre
visibili e trascinabili; la componente condivisa è usata anche da File e
Impostazioni.

La bacheca segue il riferimento fornito dall'utente: testata, ricerca,
meteo compatto con previsioni espandibili, foto dello sfondo, calendario,
spazi di lavoro e notizie. Ricerca e Attività sulla barra hanno simboli
distinti; le illustrazioni meteo sono vettori QML originali e statici.

Se il compositore non supporta `vetrobarra`, i pannelli rimangono pieni.
Il binario aggiornato deve entrare in uso con un nuovo accesso prima di
valutare Acrylic. «Nessuno» rende opachi i fondi delle app Minerva;
«Vetro» usa l'opacità del compositore, con 100% corrispondente a opaco.

Per i feed senza foto si cercano i metadati dell'articolo sullo stesso sito,
con limiti di dimensione/tempo e cache. Nessuno script viene eseguito e non
vengono inviati cookie o Referer. La shell riceve solo percorsi locali;
le fotografie assenti non vengono inventate.

### Impostazioni rapide: scelta dell’uscita audio (12 ottobre)

La freccia accanto al volume apre l’elenco delle uscite nel pannello della
barra. I nomi provengono dal servizio audio; il segno di selezione viene
aggiornato solo dopo la conferma del sistema. Il servizio esistente sposta
anche i flussi già in riproduzione quando cambia uscita.

- **Tab**, **freccia su/giù** e **Invio** permettono di scegliere un’uscita.
- **Esc** torna al pannello principale; un secondo Esc lo chiude.
- Gli elenchi lunghi hanno una barra di scorrimento trascinabile.
- Errori e timeout lasciano visibile l’ultima uscita confermata e permettono
  di riprovare. Il pulsante Impostazioni apre la sezione Audio completa.

La pagina si iscrive agli eventi solo mentre è aperta: alla chiusura si
disiscrive, senza polling in background. Le prove usano un demone privato
che simula le uscite, senza cambiare l’audio dell’utente.

Il pannello interno Wi-Fi e il mixer per singola applicazione
restano incrementi successivi; i collegamenti alle sezioni complete rimangono
operativi.

Sopra l’icona dell’altoparlante nella barra si può usare la rotellina senza
aprire il pannello: una tacca varia il volume di due punti. Lo scorrimento
sopra rete o batteria non modifica l’audio. Il controllo usa il servizio
PipeWire comune e il suo limite di volume, senza comandi esterni.
Questa interazione è prevista anche da Windows 11:
[annuncio Microsoft della build 22478](https://blogs.windows.com/windows-insider/2021/10/14/announcing-windows-11-insider-preview-build-22478/).

Il cursore del volume nel pannello segue lo stesso massimo configurato dei
tasti e della rotellina. Quando è abilitata l’amplificazione, una tacca
segna il 100% e il tratto successivo è rosso tenue. Superando il 100%, la
parte extra utilizzata, il cursore e la percentuale diventano rossi. Tornando
sotto soglia il riempimento extra scompare. Anche il nome accessibile segnala
l’amplificazione, oltre al colore.

### Bluetooth nelle impostazioni rapide

La freccia sul riquadro Bluetooth apre la lista interna dei dispositivi già
associati, con stato e batteria quando disponibili. Un dispositivo sconosciuto
visto da una scansione precedente non viene mostrato come personale. Non si
avvia automaticamente alcuna ricerca radio.

Un clic su un dispositivo associato avvia la connessione. Su uno già connesso
apre la scheda con il pulsante **Disconnetti**: consultare un controller o un
mouse non deve interromperlo. Tab, frecce e Invio permettono di usare la lista;
Esc torna al pannello principale e restituisce il fuoco alla freccia Bluetooth.
Gli elenchi lunghi hanno una barra trascinabile.

La vista usa il [modulo Bluetooth nativo di Quickshell](https://quickshell.org/docs/v0.2.1/types/Quickshell.Bluetooth/BluetoothDevice/)
per gli aggiornamenti D-Bus di BlueZ e le connessioni. L’interruttore di
accensione passa dal servizio comune, che gestisce anche rfkill. Associazione
di nuovi dispositivi e funzioni avanzate rimangono nella sezione Bluetooth
completa, raggiungibile dal piede del pannello.

InputPlumber, profili dei controller, disposizione dei tasti e colori LED
restano nelle impostazioni Controller esistenti.

### Wi-Fi nelle impostazioni rapide

La freccia Wi-Fi apre la lista interna delle reti disponibili, leggendo
inizialmente la cache di NetworkManager senza avviare una scansione radio.
Selezionare una rete espande la scheda; **Connetti** avvia il collegamento.
Su una rete già attiva viene proposto **Disconnetti**. Il pulsante di
aggiornamento richiede una scansione esplicita.

La vista e la sezione Rete delle impostazioni usano lo stesso controller:
profili salvati cercati per SSID letterale, attivazione per UUID quando
disponibile, password mascherata e inviata a nmcli soltanto su stdin.
Password, errori e collegamento in attesa non sostituiscono il segno della
connessione confermata dal sistema. Esc annulla prima la richiesta della
password, poi torna al pannello principale. Gli elenchi hanno una barra
trascinabile.

Reti nascoste, autenticazione aziendale e scelta fra più adattatori non sono
coperti dal nuovo flusso rapido; non sono stati aggiunti controlli soltanto
decorativi per queste funzioni. La disconnessione eredita ancora dal
controller esistente la scelta della prima scheda Wi-Fi.

La provenienza delle risorse e i limiti della verifica giuridica sono
documentati in [provenienza-risorse-windows.md](provenienza-risorse-windows.md).

### Mixer per applicazione

La pagina **Uscita audio**, aperta dalla freccia del volume, contiene il
**Mixer volume** sotto l'elenco delle uscite. I flussi audio delle app hanno
volume e mute indipendenti; nome dell'app e descrizione del flusso permettono
di distinguere due riproduzioni della stessa applicazione. Tab porta ai
controlli e scorre la lista per renderli visibili; le frecce regolano il
volume di un punto. L'amplificazione segue il massimo scelto nelle impostazioni
e mantiene l'indicazione rossa oltre il 100%.

La vista usa i nodi di riproduzione del
[modulo PipeWire di Quickshell](https://quickshell.org/docs/v0.2.1/types/Quickshell.Services.Pipewire/PwNode/),
senza interrogazioni periodiche. Le iscrizioni ai nodi durano quanto la pagina.
I flussi di registrazione non entrano nel mixer; non vengono accesi microfoni.
Una modifica del volume non modifica il mute: il pulsante dedicato resta
esplicito. L'elenco riguarda i flussi esistenti, non tutte le app installate;
non salva ancora preferenze per applicazioni senza flussi attivi.

**Super+Ctrl+V** apre direttamente questa pagina sul monitor attivo, anche
con Start o altre impostazioni rapide aperte. Ripeterla mantiene l'audio
aperto. Esc torna alla pagina principale; un secondo Esc chiude il pannello.
Super+A continua ad aprire normalmente la pagina principale. Negli altri
preset Super+Ctrl+V apre la sezione Audio delle impostazioni.

Le opzioni audio spaziale non sono ancora implementate. La corrispondenza
complessiva del preset resta incompleta.

Il clic destro sull'altoparlante della barra offre **Apri mixer volume** e
**Impostazioni audio**. La prima apre la pagina rapida del mixer; la seconda
la sezione Audio completa. Il menu si usa anche con frecce e Invio e si
chiude con Esc. Il clic sinistro e la rotellina mantengono le loro azioni.
Non è ancora presente un servizio di diagnosi automatica dei problemi audio.

### Impostazioni: aggiornamento del 13 ottobre

La presentazione Windows ora usa le 12 categorie del riferimento nella VM,
con ricerca centrata nella barra, Indietro e le pagine Personalizzazione,
Sfondo, Colori e Temi. Le miniature dei temi si usano anche con Invio/Spazio.
Sfondo, adattamento, modalità delle app e temi salvati passano dal servizio
comune delle impostazioni; i preset conservano le proprie preferenze.

Questo blocco è installato localmente. Alcune sottopagine usano ancora la
vista Liquid equivalente e alcune funzioni Windows sono disabilitate:
la presentazione completa di tutte le pagine resta in lavorazione.
Dettagli e limiti delle verifiche nel
[registro del 13 ottobre](../audit/chatgpt/2026-10-13.md).


### Personalizzazione di Start e della barra

Le pagine **Start** e **Barra delle applicazioni** hanno ora controlli
propri. Start permette due, tre o quattro righe di app ancorate, rispettivamente
con più spazio per i consigliati, disposizione predefinita o più elementi
ancorati. La paginazione e le frecce seguono il numero di righe scelto.

Nella barra, Cerca può essere nascosto, mostrato come icona, icona con etichetta
o casella; Visualizzazione attività, Widget e Mostra desktop si possono
nascondere. L'allineamento può essere centrale o a sinistra; Start e Cerca
seguono questa scelta. Il pulsante tiling rimane opzionale. Queste preferenze
appartengono al preset; nascondere un pulsante non elimina la sua funzione.
Il menu del clic destro apre la pagina Barra dedicata.

Le pagine accompagnano con lo scorrimento il focus da tastiera. Le tendine
aperte si usano con frecce, Home/Fine, Invio/Spazio ed Esc.
Le miniature Start sono disegni originali in QML; le nuove icone sono Fluent
MIT, con provenienza registrata accanto ai tracciati.

Restano da implementare cartelle nello Start, app aggiunte di recente e più
usate, notifiche dell'account, menu penna, tastiera virtuale e i comportamenti
avanzati della barra. Le rispettive voci sono disabilitate. Nascondere i
consigliati riguarda Start, non la cronologia del gestore file.

Queste nuove pagine sono installate localmente dal 13 ottobre. Il giro
generale ha superato 570 controlli; le prove mirate e i limiti sono riportati
nel diario. Non occorre riavviare il desktop.


### Tastiera e paginazione di Start

Dalla ricerca vuota, il primo **Giù** entra nella griglia ed evidenzia l'app.
Le quattro frecce muovono la selezione; **Home/Fine** portano alla prima/ultima
app ancorata, e **Invio o Spazio** avviano quella evidenziata. Scrivere dalla
griglia torna subito alla ricerca; **Esc** cancella la ricerca prima di chiudere
Start. I pulsanti di pagina mantengono coerenti indice, pagina e focus.

Su schermi bassi, la griglia scorre per mostrare interamente la selezione.
Una griglia vuota conserva la ricerca e non avvia app con Invio.


### Scelta di immagini e album per lo sfondo

**Sfoglia le foto** apre una finestra **Apri** separata e modale, con la
presentazione del dialogo osservato nella VM Windows: navigazione,
indirizzo modificabile, ricerca nella cartella, luoghi reali del sistema,
elenco o miniature, anteprima, filtro, nome file e conferma/annullamento.
La cartella iniziale segue i percorsi XDG, anche quando Immagini è stata
spostata. **Nuova cartella** crea una cartella reale; **Organizza** consente
l'ordinamento per nome o data. Il selettore degli album usa la stessa
finestra limitando la scelta alle cartelle.

Invio conferma un'immagine valida o apre la cartella selezionata; Esc
annulla, Alt+Su sale, Alt+Sinistra/Destra segue lo storico, Ctrl+L modifica
l'indirizzo e F5 rilegge l'elenco. Un'immagine corrotta o inesistente non
cambia lo sfondo. I nomi con spazi, Unicode e `#` sono codificati negli URL
delle immagini, conservando il percorso originale nelle impostazioni.

Il selettore usa il servizio filesystem condiviso senza osservatori
persistenti; risposte vecchie o appartenenti ad altre richieste sono
ignorate. Miniature e anteprima sono decodificate a dimensione limitata;
chiudendo la finestra vengono liberati modello e immagini.
Il percorso grafico Liquid continua a usare il proprio selettore.

Il compositore gestisce ora `xdg-dialog-v1` per mantenere il focus sul
dialogo modale quando si clicca sulla madre. Il nuovo binario sarà attivo
al prossimo accesso; il selettore dispone di compatibilità con la sessione
precedente. Non sono simulate integrazioni cloud Microsoft; icone e risorse
rimangono quelle redistribuibili del progetto. Le schermate della VM sono
riferimenti privati e non vengono pubblicate.


### Catalogo delle applicazioni dopo un'installazione

Start e Cerca rileggono il catalogo all'apertura, come il menu Liquid.
Le app appena installate o rimosse compaiono correttamente senza uscire
dalla sessione. Il catalogo esistente resta visibile durante la rilettura;
il demone evita di riaprire i file `.desktop` se non sono cambiati.
Non è aggiunta una scansione periodica mentre i launcher sono chiusi.


### Liquid Update

La categoria **Liquid Update** è collegata al repository
[linuxiano85/Liquid-DE](https://github.com/linuxiano85/Liquid-DE).
**Verifica disponibilità aggiornamenti** legge il ramo predefinito del
repository; la verifica automatica avviene ogni sei ore. I risultati
restano disponibili riaprendo la pagina, anche dopo un riavvio del demone.
**Sospendi per 1 settimana** mette in pausa le verifiche automatiche;
**Riprendi aggiornamenti** le riattiva. La verifica manuale resta possibile.

**Scarica** recupera lo ZIP dei sorgenti del commit mostrato, ne verifica
struttura e CRC e ne registra SHA-256, dimensione e data. Il download è
salvato in `$XDG_CACHE_HOME/liquid-de/updates` (di serie
`~/.cache/liquid-de/updates`); dopo il completamento il pulsante apre quella
cartella. L'annullamento elimina il file parziale; un archivio già verificato
viene riutilizzato. La cronologia riguarda i download completati.

L'installatore registra revisione, versione e presenza di modifiche locali
in `liquid-build.json`. Una vecchia installazione senza manifesto non viene
presentata come aggiornata. Una build modificata viene indicata come locale.
Al 13 ottobre il repository non pubblica release: il canale usa quindi le
revisioni del ramo `principale`. Il download è un archivio sorgenti; la
procedura di installazione guidata e il canale di release versionate restano
lavori successivi. L'archivio non viene estratto né eseguito dal servizio.

La pagina riprende l'impaginazione della VM di riferimento, con variante
chiara/scura, inglese, navigazione e scrollbar. I controlli agiscono sul
servizio reale del demone. Quota GitHub, rete assente e archivi invalidi sono
stati d'errore, mai un risultato «nessun aggiornamento».

### Liquid Update: trasparenza del confronto (13 ottobre, seguito)

La pagina **Cosa cambia** confronta il commit registrato nell'installazione
con quello del ramo pubblico: commit completi, componenti interessati,
file aggiunti/modificati/rimossi/rinominati, conteggi di righe e patch
espandibili e copiabili. Le modifiche locali non sono incluse: la pagina
lo dichiara, senza presentare il confronto pubblico come inventario della
build di sviluppo. Un confronto non disponibile non significa zero modifiche.

Le categorie distinguono Shell, modulo nativo, demone, compositore, Fucina,
risorse/integrazione, documentazione/sviluppo e file ancora da classificare.
Le rinomine coinvolgono entrambi i componenti. Sul limite di 300 file o
quando mancano commit, il risultato è dichiarato parziale. Patch assenti
o oltre il budget di visualizzazione non vengono inventate.

**Non è ancora un piano di installazione:** non risolve dipendenze o
compatibilità IPC, non controlla le modifiche locali file per file e non
applica aggiornamenti. Il pulsante Scarica resta uno ZIP completo di sorgenti.
Il sistema definitivo deve distribuire artefatti compilati per componente,
manifesto con versioni/impronte/dipendenze/dimensioni/changelog, scaricare
solo gli artefatti cambiati, verificare integrità e provenienza, installare
con transazione e recupero. Le risorse grandi devono essere suddivise per
non riscaricare un intero pacchetto di sfondi per una singola icona. Non
occorrono versioni manuali di ciascun file: Git e le impronte le identificano.
Pubblicazione delle release non effettuata.

### Home delle Impostazioni (13 ottobre, seguito)

La categoria Home carica ora una pagina Windows dedicata, anziché una
categoria senza voci. Testata con anteprima e nome/modello del computer,
collegamento Liquid Update; schede consigliate, preferenze di accessibilità,
sei temi rapidi, tendina Chiara/Scura e informazioni sul dispositivo. Due
colonne sui pannelli larghi, una sui piccoli, barra di scorrimento e
navigazione alle pagine funzionali. Riepilogo CPU/RAM/sistema/kernel letto
una sola volta all'apertura: nessun timer o monitor dei processi.

Il confronto è `vm-windows11/foto/chiaro/categoria-home-01.png`. Nome macchina,
CPU e sistema mostrati sono quelli locali; nelle prove grafiche vengono
sostituiti da dati di fixture per non registrare il nome del PC. RAM indica
quella utilizzabile da Linux (`MemTotal`), non una stima della RAM fisica.

Parità ancora incompleta: accessibilità rimanda alla pagina reale di Liquid
anziché replicare le tessere della Home Windows; le raccomandazioni sono
fisse, non basate sullo storico di navigazione; App predefinite non è il
catalogo App installate; la testata non ha ancora il riepilogo Ethernet né
la rinomina del computer; i temi includono gli sfondi distribuibili di
Liquid e Bloom solo dove già presente localmente. Le sottopagine ancora
Liquid non sono diventate native per il solo cambio della Home. L'apertura
iniziale conserva per ora la logica della sezione ricordata.

### Sistema e navigazione (13 ottobre, seguito)

Sistema usa ora una pagina dedicata con testata del dispositivo, ordine e
misure delle schede dalla VM (`categoria-sistema-01/02.png`). Home e Sistema
condividono la stessa testata. Sono collegati Schermo, Audio, Notifiche,
energia, Multitasking, informazioni/licenza/ripristino e scorciatoie di Liquid.
Le voci senza implementazione sono esplicitamente disabilitate, anche per
l'accessibilità. Licenza sostituisce l'attivazione commerciale Windows:
Liquid è software libero e non richiede un Product Key.

Una pagina di finestre aperta da Multitasking conserva il contesto Sistema,
senza cambiare la categoria di appartenenza di Finestre quando la si apre
normalmente da Personalizzazione. La freccia Indietro risolve le briciole
reali; non manda più ogni pagina Windows a Personalizzazione. Dalla cronologia
Liquid Update torna alla pagina Liquid Update. Le radici non hanno un padre
fittizio. Lo storico completo di navigazione tra categorie resta da costruire.

Non basta questa pagina per ottenere parità funzionale: molte sottopagine
sono ancora quelle Liquid e le funzioni non disponibili restano da implementare.

### Storico e avvio delle Impostazioni (13 ottobre, seguito)

La freccia Indietro e Alt+Sinistra ripercorrono ora le visite effettive,
comprese le categorie principali. Lo storico conserva pagina, contesto,
sottopagina interna di Liquid Update e posizione di scorrimento; non conserva
una seconda copia dei valori delle impostazioni. Le briciole navigano al
padre e questa visita entra nello storico: Indietro può quindi riportare alla
sottopagina appena lasciata. Un ingresso diretto senza storico mantiene il
padre come destinazione di ripiego. Massimo 50 visite; cambio preset azzera
lo storico per non mescolare Liquid e Windows.

All'avvio nel preset Windows, senza una destinazione esplicita, la finestra
apre Home. Richieste esplicite come Audio o `w-barra` hanno precedenza. La
scelta iniziale viene applicata una volta dopo l'arrivo delle preferenze;
richiamare una finestra già aperta senza una destinazione conserva la pagina
corrente. In Liquid rimane la sezione ricordata e lo storico Windows non
modifica lo scorrimento quando si richiama la stessa pagina. Vecchi valori
`w-…` non vengono salvati come sezioni Liquid da ricordare.

Limiti: lo storico non è persistente dopo la chiusura del processo, non ha
un pulsante Avanti e non salva focus, testo di ricerca o campi dei dialoghi.
Il ripristino di scorrimento è provato sulle pagine del banco, non su ogni
sottopagina dinamica o su tutte le scale. Non sono implementate per questo
solo intervento le schede Sistema ancora grigie.

### Cartelle accanto all’alimentazione in Start (14 ottobre)

**Personalizzazione → Start → Cartelle** permette di mostrare Impostazioni,
Esplora file, Documenti, Download, Musica, Immagini, Video e Cartella personale
nel piede dello Start. I pulsanti seguono l’ordine del riferimento Windows,
anche quando attivati in ordine diverso; si possono nascondere tutti.
Il nome dell’account si abbrevia quando serve spazio, conservando il nome
completo nel suggerimento e nell’etichetta accessibile.

Le cartelle vengono lette attraverso QStandardPaths e la configurazione XDG:
non sono costruite aggiungendo nomi italiani alla home. Il percorso passa
come dato al servizio di apertura, senza interpolazione in comandi shell.
Le preferenze sono salvate per preset e validate dal demone. La voce Rete
resta disabilitata: manca ancora una vista delle risorse di rete equivalente.

Riferimenti: [personalizzazione di Start Microsoft](https://support.microsoft.com/it-it/windows/experience/personalization/customize-the-windows-start-menu),
[QML StandardPaths](https://doc.qt.io/qt-6/qml-qtcore-standardpaths.html);
misure e ordine confrontati con la pagina Cartelle della VM privata.

### Tray e menu delle applicazioni (14 ottobre)

Il pannello delle icone nascoste si naviga con le frecce e Home/Fine; Invio
e Spazio attivano l’icona. Menu o Maiusc+F10 aprono il menu accanto all’icona
con focus, anche quando il puntatore è altrove. Il clic centrale mantiene
l’attivazione secondaria dell’applicazione.

I menu D-Bus vengono letti tramite QsMenuOpener anche per le voci figlie:
sono mantenuti separatori, disponibilità, immagini fornite dall’app, spunte
e radio. Le mnemoniche & non vengono mostrate come caratteri letterali; &&
resta una e commerciale. Home/Fine, frecce, Invio e Spazio operano sulle voci
disponibili. La rimozione dell’app chiude il menu; chiuderlo libera il modello.
I menu della tray rispettano i 48 pixel della barra inferiore.

La prova privata usa nove StatusNotifierItem e un vero DBusMenu, con icona
PNG sintetica, una voce nascosta, una disabilitata, checkbox, radio e un
sottomenu. Non usa il bus delle applicazioni personali. Il modello limita
la lettura a sei livelli: la disposizione grafica condivisa mostra ancora
una sola colonna di sottomenu; le cascate più profonde richiedono un seguito.
Non è ancora implementata la scelta delle singole icone sempre visibili.

API verificate sulla [documentazione QsMenuEntry](https://quickshell.org/docs/v0.3.2/types/Quickshell/QsMenuEntry/)
e [QsMenuOpener](https://quickshell.org/docs/v0.3.2/types/Quickshell/QsMenuOpener/).
