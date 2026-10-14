# Evoluzione del file manager e delle icone

Confronto iniziale del codice, 11 ottobre 2026. Richiesta: adottare le
funzioni utili di Esplora file nelle varianti Liquid, Windows e negli altri
preset. Il primo incremento implementa schede, affiancamento adattivo, caselle
di selezione e una famiglia originale di icone per Windows. Anteprima laterale,
Home aggregata e confronto dei singoli conflitti restano incrementi successivi.

## Base esistente

La lettura di `minerva-shell/files/` e dei servizi Dart mostra già:

- percorsi navigabili, cronologia, recenti e cartelle fissate;
- ricerca nelle sottocartelle, elenco/griglia, zoom, ordinamento e nascosti;
- selezione multipla, trascinamento, copia, spostamento e appunti di sistema;
- cestino, ripristino, annullamento e rinomina multipla;
- compressione/estrazione e scelta collettiva dei conflitti;
- avanzamento trasferimenti, pausa, ripresa e annullamento;
- proprietà in una finestra dedicata, miniature e apertura nel visualizzatore;
- dischi e collegamento a percorsi remoti, con dipendenze rilevate.

Questa è presenza nel codice, non una nuova verifica runtime. Le prove delle
operazioni sui file devono precedere la modifica della loro interfaccia.

Prima di questo intervento le «schede» erano riquadri sempre affiancati, fino a quattro:
`FileManager.qml`, `maxTabs`, `addTab()` e il contenitore dei `Pane`. Non sono
schede sovrapposte come quelle di un browser. Le miniature e il visualizzatore
non costituiscono un pannello laterale permanente di anteprima.

## Incrementi proposti

| Priorità | Funzione | Stato e intervento |
|---|---|---|
| 1 | Icone e comandi coerenti | Primo intervento implementato: 13 SVG originali per cartelle, famiglie di file, disco e cestino nel preset Windows; il tema esplicitamente scelto prevale. Rete e icone non coperte usano la risoluzione esistente. |
| 2 | Vere schede e modalità affiancata | Implementato: fino a 12 cartelle con identità stabile, una vista attiva o gruppi adattivi fino a quattro riquadri. Clic centrale, chiusura, riordino col mouse e scorciatoie verificati. |
| 3 | Caselle di selezione opzionali | Implementato: caselle nello stesso modello di selezione usato da mouse e tastiera, con preferenza separata per preset. |
| 4 | Anteprima e dettagli laterali | Implementato l'11 ottobre (Claude): vedi «Terzo incremento». La miniatura dei PDF nel riquadro usa quella del demone, se c'è. |
| 5 | Home operativa e ricerca filtrabile | Riunire accesso rapido, recenti e dischi in una vista; aggiungere filtri per tipo, data e dimensione alla ricerca esistente. Ogni risultato conserva il percorso reale. |
| 6 | Conflitti e trasferimenti più informativi | Mostrare sorgente/destinazione, dimensione e data per scegliere sui singoli conflitti. Migliorare i trasferimenti esistenti con velocità media e tempo stimato, soltanto quando i dati consentono una stima attendibile. |

La vista dettagli ora ha colonne Nome, Dimensione e Modificato. Dopo gli
incrementi iniziali, valutare colonne selezionabili e raggruppamento per tipo
o data. La memoria della vista per cartella va progettata separatamente dalla
preferenza generale del preset.

## Un motore, presentazioni per preset

Le operazioni restano nei servizi esistenti: `file_service.dart`,
`archive_service.dart`, `Files.qml` e IPC. Nessuna copia del motore per il tema
Windows. L'interfaccia sceglie disposizione, icone e comandi dal preset.

Le opzioni nuove di presentazione devono essere classificate in
`desktop_profiles.dart`: schede/affiancamento, caselle, pannello laterale,
densità e colonne. Cartelle fissate, file recenti e lavori in corso restano
legati ai dati dell'utente, con gli stessi percorsi nei diversi preset.

Ogni scheda aperta conserva il proprio riquadro, percorso, cronologia e selezione.
Solo la scheda attiva, o il suo gruppo in affiancamento, è visibile e abilitata.
Il gruppo dipende dallo spazio disponibile, con una larghezza minima desiderata
di 320 px per riquadro; se l'intera finestra è più stretta si mostra comunque
una cartella. Le schede nascoste non perdono il proprio stato. Il limite di
12 contiene il numero di riquadri caricati, senza precaricare quelli non aperti.

## Uso del primo incremento

- `Ctrl+T`: nuova scheda nella cartella corrente.
- `Ctrl+W`: chiudi la scheda attiva; l'ultima resta aperta.
- `Ctrl+Tab` / `Ctrl+Shift+Tab`: scheda successiva / precedente.
- `Ctrl+Shift+S`, oppure il pulsante a destra della barra delle schede:
  alterna schede e affiancamento.
- Clic centrale su una cartella: aprila in una nuova scheda; clic centrale
  sulla scheda: chiudila. Il trascinamento della scheda cambia l'ordine.
- Impostazioni del file manager → **Caselle di selezione**: selezione multipla
  senza tenere premuto Ctrl. Le caselle condividono la selezione con `Ctrl+A`.

`files.disposizione` accetta `auto`, `schede`, `affiancata`. Con `auto`, Windows
parte con le schede e gli altri preset conservano l'affiancamento.
`files.caselleSelezione` è disattivato di fabbrica. Entrambe le preferenze
appartengono al preset; cambiare tema non chiude le cartelle.
Il nuovo set vettoriale è descritto in `minerva-shell/files/artwork/LICENSE.md`.
Questo incremento non è un rifacimento visivo completo di Esplora file.

La gestione guidata dei telefoni USB è registrata separatamente in
[Telefoni USB e componenti Minerva](dispositivi-telefoni-usb.md): stati reali,
autorizzazione Android, dipendenze MTP/PTP, avvisi e collaudo con hardware.

## Prove del primo incremento

`python3 tests/prova_file_manager.py` crea un compositore Wayland privato,
due finestre reali, API file reali e directory temporanee. Verifica identità,
chiusura e riordino, risposte tardive, selezione, copia e annullamento, cambio
preset, tiling e percorsi lunghi senza sovrapposizioni. Mouse e tastiera sono
iniettati esclusivamente nella sessione `MINERVA_PROVA=1`.
Registri, esiti e schermate stanno in
`../Liquid_test-principale/rapporti/gestore-file-evoluzione/`.
Il test non collega dispositivi o server remoti e non copre ogni combinazione
di permessi/conflitti. La suite del servizio file copre separatamente le sue
operazioni; quella Windows controlla le regressioni della shell.

## Collaudo per incremento

1. File e directory sintetici in una cartella temporanea; registri e schermate
   in `../Liquid_test-principale/rapporti/gestore-file/`.
2. Verifica del contenuto prima/dopo copia, spostamento, pausa, annullamento,
   conflitti, cestino e ripristino. Errori di permessi e destinazioni occupate.
3. Più finestre, più schede, stesso percorso, cambio desktop e tiling: richieste,
   selezione e risposte di una finestra non devono modificare le altre.
4. Mouse e tastiera reali nel compositore privato, compresa selezione mista
   caselle/Ctrl/Shift e ricerca che si aggiorna mentre cambia il focus.
5. Passaggio fra preset e riapertura: preferenze visive isolate, operazioni
   conservate e nessuna richiesta di anteprima quando il pannello è chiuso.
6. Compilazione QML, lettura di tutti i log e ispezione delle immagini prima
   dell'installazione di ogni incremento.

## Secondo incremento: presentazione Windows e comandi reali

L'11 ottobre, dopo la richiesta di concentrarsi sul file manager, sono stati
implementati:

- schede sopra la barra dei comandi, pannello laterale piatto e corpo continuo;
- palette locale `FileStyle`, tema chiaro/scuro e accento del preset Windows,
  senza modificare la palette generale delle altre app;
- barra stabile Nuovo, Taglia, Copia, Incolla, Rinomina, Cestino, Ordina,
  Visualizza e altre opzioni; i comandi usano le operazioni già esistenti;
- menu navigabili con frecce, Home/End, Invio ed Escape, con scorrimento quando
  lo spazio è insufficiente;
- ricerca sempre visibile: accanto al percorso nelle viste larghe, su una riga
  separata in quelle strette. Invio cerca nelle sottocartelle; Liquid conserva
  il filtro e le proprie scorciatoie;
- icone vettoriali della famiglia Microsoft Fluent, con licenza MIT, commit,
  URL e SHA256 riportati in `files/command-SOURCE.json`;
- titolo leggibile anche in scuro e colore coerente della selezione col mouse.

La prova ha trovato e corretto due difetti funzionali: la preferenza dei file
nascosti veniva invertita due volte, rompendo il legame fra schede; la ricerca
attiva disabilitava tutta la barra perché lo stato che protegge le scorciatoie
del testo veniva riutilizzato per i pulsanti. Ora tutte le finestre aggiornano
i nascosti dalla stessa preferenza; solo i dialoghi bloccano le nuove
operazioni col mouse. Ctrl+C nel campo ricerca continua a copiare il testo.

Il collaudo usa API file reali, due finestre, input nel compositore privato e
file sintetici. Comprende rinomina con nome multilinea, contenuto prima/dopo
copia, annullamento, creazione, ricerca ricorsiva, menu, cambio preset, temi,
sincronizzazione dei nascosti e schede/affiancamento/tiling già verificati.
Esiti, hash e schermate:
`../Liquid_test-principale/rapporti/file-manager-windows/`.
La regressione generale della shell Windows si trova in
`../Liquid_test-principale/rapporti/windows11-file-manager/`.
Esito della revisione installata: **78/78** controlli file, **410/410**
regressioni Windows, **248 componenti QML compilati senza errori**.
I quindici componenti aggiornati sono installati nella radice locale;
riaprire il gestore file carica questa versione, senza riavviare la sessione.

Restano da implementare Home aggregata e confronto dei conflitti per singolo
file (il pannello laterale è il terzo incremento, qui sotto). Menu contestuali, proprietà e
trasferimenti conservano parte della presentazione Liquid: questo incremento
non certifica ancora una replica completa di Esplora file.

## Terzo incremento: riquadro dei dettagli e dell'anteprima

L'11 ottobre sera (Claude), come in Esplora file di Windows 11:

- **Si apre** da Visualizza → «Riquadro dettagli» (Alt+Maiusc+P) o «Riquadro
  di anteprima» (Alt+P); lo stesso tasto lo richiude. Le scorciatoie valgono
  in tutti i preset, le voci del menu stanno nella barra dei comandi Windows.
- **Dettagli:** icona, nome, tipo, dimensione, ultima modifica, misure di
  un'immagine, percorso. Con più elementi: quanti sono e quanto pesano i file
  (le cartelle non si misurano qui).
- **Anteprima:** l'immagine grande, decodificata alla misura del riquadro; le
  prime righe di un testo; la miniatura del demone per video e PDF;
  altrimenti «Nessuna anteprima disponibile».
- **Cosa legge.** Niente a riquadro chiuso: è un `Loader` spento. Aperto,
  una domanda `fs_anteprima` per il file su cui ci si ferma, dopo 120 ms, così
  scorrendo con le frecce non parte una lettura per file. Il demone legge al
  massimo 16 KB (`FileService.anteprima`) e decide dai byte se è testo. Ogni
  domanda ha un numero, e una risposta tardiva di una selezione vecchia si
  scarta.
- **Preferenza** `files.pannelloLaterale` (`niente`, `dettagli`,
  `anteprima`), una per preset, di serie spenta.

File: `files/PannelloLaterale.qml`, `files/FileManager.qml` (Loader,
scorciatoie), `files/WindowsCommands.qml` (voci del menu), `core/Ipc.qml`
(`anteprimaReceived`), `minervad/lib/services/file_service.dart`
(`anteprima`), `minervad/lib/ipc/websocket_server.dart` (`fs_anteprima`).

Prove:
- `tests/anteprima_file_test.dart`: 8 casi (testo breve, testo lungo
  troncato, carattere tagliato sul limite, binario con zeri, byte non UTF-8,
  immagine con misure, cartella, file sparito);
- `tests/prova_file_manager.py`, 13 controlli nuovi con clic veri: niente
  letture a riquadro chiuso, dettagli e misure, più elementi, selezione
  vuota, Alt+P col testo e con l'immagine, risposta tardiva scartata, una
  lettura sola scorrendo in fretta, preferenza per preset, chiusura che
  ridà la larghezza all'elenco.

Corretto anche il demone di prova: rispondeva sempre «nessun telefono» alla
domanda periodica di `Files.qml` (ogni 8 secondi), e cancellava a metà prova
i telefoni simulati. A seconda dei tempi, la prova dei telefoni passava o no.

## Riferimenti

Il 12 ottobre sono stati aggiunti menu contestuali personalizzabili secondo
il riferimento Insider del 17 agosto 2026: comandi in icone o testo, posizione
di Proprietà, azioni meno frequenti e visibilità delle voci. Le preferenze sono
per preset; le operazioni usano gli stessi servizi file. La selezione viene
fissata al clic destro e il menu segue l'output del puntatore.

Corrette anche corsia della scrollbar, ancoraggi al cambio preset e identità
delle richieste di anteprima alla riapertura dei pannelli. Collaudo finale:
108 controlli UI file, 14 operazioni reali sui contenuti, 424 regressioni
Windows e 35 controlli di sicurezza dei desktop. Dettagli e limiti nel diario
`audit/chatgpt/2026-10-12.md`; non è una certificazione di identità visiva 1:1.

La guida Microsoft documenta accesso rapido, vista compatta, menu comuni,
elementi nascosti e caselle di selezione:
[Esplora file in Windows](https://support.microsoft.com/it-it/windows/experience/fileexplorer/file-explorer-in-windows).

Il pannello di anteprima fa parte di Esplora file. Il supporto esteso a
Markdown, SVG, PDF e codice descritto qui è un'aggiunta PowerToys:
[File Explorer add-ons](https://learn.microsoft.com/en-us/windows/powertoys/file-explorer).
Questa distinzione evita di considerare ogni funzione PowerToys parte
dell'installazione standard di Windows. Le proposte Liquid sono scelte di
progetto, non una promessa di equivalenza già raggiunta.
