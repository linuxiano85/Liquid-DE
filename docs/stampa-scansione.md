# Stampa e scansione

Apri **Stampa e scansione** dal menu delle applicazioni oppure esegui
`minerva-documenti`. I due pulsanti in alto cambiano modalità conservando
le pagine del documento.

## Acquisire un documento

1. Seleziona lo scanner USB o di rete, l'origine e la risoluzione.
2. Premi **Scansiona**, poi **Prossimo foglio** per aggiungere altre pagine.
   Se lo scanner espone un alimentatore, puoi acquisirne tutti i fogli.
3. Seleziona una pagina per ruotarla, ritagliarla o aggiungere testo,
   note, evidenziazioni, frecce e forme colorate.
4. Usa **Salva PDF** per esportare tutte le pagine nello stesso documento,
   oppure passa a **Stampa**.

Le modifiche mantengono l'immagine acquisita originale. Puoi annullare le
ultime modifiche della pagina, cambiare l'ordine e ripristinare una pagina
rimossa. La chiusura richiede conferma quando ci sono scansioni non salvate.
L'interruzione conserva le pagine già acquisite completamente.

L'alimentatore ha un limite di 100 fogli per acquisizione: al raggiungimento
del limite l'app lo segnala; puoi continuare con **Prossimo foglio**.

## Stampare

Puoi aprire PDF, immagini o testo con **Apri documento**, oppure premere
**Ctrl+P** in Anteprima e File. Il dialogo mostra soltanto le opzioni
comunicate dalla stampante: carta, colore, copie e fronte-retro.
Un intervallo come `1,3-5` stampa solo le pagine indicate.

L'anteprima rappresenta il documento; l'adattamento al foglio e i margini
finali dipendono dal driver. Passare alla modalità Stampa non invia lavori:
occorre premere **Stampa**.

Per aggiungere stampanti, scegliere driver e leggere consumabili e stato,
apri **Impostazioni → Stampanti e scanner**.

## Supporto del sistema

La stampa usa CUPS e python-pycups. L'acquisizione usa SANE e, per gli
scanner di rete compatibili eSCL/WSD, sane-airscan. PDF e anteprime usano
Qt per Python. L'installer include queste dipendenze; il rilevamento non
richiede di esporre un servizio scanner sulla rete.

I documenti temporanei vengono creati nella cache privata dell'utente,
con permessi riservati, e rimossi alla chiusura normale. Un'interruzione
forzata del processo può lasciare file temporanei nella cache. I PDF
salvati dall'utente non vengono rimossi.
