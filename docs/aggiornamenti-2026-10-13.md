# Aggiornamento del desktop — 13 ottobre 2026

Questa è una fotografia di sviluppo, **non la dichiarazione di una versione
1.0 definitiva o di parità completa con Windows**.

## Interfaccia Windows

- Barra, Start, ricerca, impostazioni rapide, audio fino al limite configurato
  e indicazione del volume oltre il 100%, Wi-Fi/Bluetooth e panoramica desktop.
- Pagine dedicate Personalizzazione, Sfondo, Colori, Temi, Start, Barra, Home
  e Sistema; selettore di immagini con finestra modale e filtro.
- Storico delle Impostazioni, Indietro e Alt+Sinistra, ritorno alle sottopagine
  e allo scorrimento; apertura generale sulla Home, destinazioni esplicite
  rispettate, comportamento Liquid mantenuto.
- Temi e preferenze del preset separati. Asset Microsoft non redistribuiti:
  senza immagini locali il preset usa gli sfondi originali di Liquid.

## Funzionamento e trasparenza

- Liquid Update legge il repository e mostra commit, componenti, file e
  differenze. Download sorgenti con verifica e cronologia.
- Formato preparatorio per futuri aggiornamenti selettivi: oggetti per file,
  hash, cache e calcolo dei byte necessari. Il pulsante attuale scarica ancora
  lo ZIP completo; installazione selettiva e rollback non sono implementati.
- Catalogo delle applicazioni aggiornato all'apertura dei menu, senza riavvio.
- Evoluzione di tiling, gestione finestre/desktop, file manager e Fucina 2;
  dettagli tecnici nelle rispettive pagine di documentazione e nelle prove.

## Verifica e parti ancora aperte

Le prove GUI usano compositori e preferenze isolati, non la sessione personale.
Le pagine Sistema non ancora implementate sono esplicitamente disabilitate;
alcune sottopagine aprono ancora l'interfaccia Liquid. Restano lavoro di
finitura, corrispondenza delle icone, funzioni aggiuntive e parità complessiva.
Il banco Qt WebEngine richiede un host Qt dedicato; il fixture incluso è
una verifica tecnica con HTML fittizio, non una nuova applicazione pronta.
