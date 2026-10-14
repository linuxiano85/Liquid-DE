# Liquid Update — distribuzione selettiva

Stato del 13 ottobre 2026: formato, generatore, confronto e trasporto provati;
**non collegati ancora al pulsante Scarica**, che scarica lo ZIP dei sorgenti.
Non sono state pubblicate release né eseguiti aggiornamenti dell'installazione.

## Un numero di release, impronte automatiche per componenti e file

Una release ha versione, commit di provenienza, piattaforma e note leggibili.
Ogni componente ha un'impronta derivata dal proprio inventario. Ogni file ha
SHA-256, dimensione, tipo, permessi e componente. Non serve numerare i file
manualmente. Le patch e i commit restano nella pagina Cosa cambia; i binari
compilati non hanno una differenza testuale significativa.

Gli oggetti gzip sono identificati dallo SHA-256 del contenuto originale;
il manifesto contiene anche impronta e dimensione dei byte compressi. Un
oggetto condiviso da più file si trasferisce una sola volta. L'icona non è
impacchettata con tutti gli sfondi; una risorsa grande invariata non viene
scaricata perché cambia un altro file del medesimo componente.

`plan()` distingue file aggiunti, rimossi, modificati e componenti coinvolti.
Una rinomina o modifica dei permessi può riusare un contenuto dell'installazione,
indicato in `reuseInstalled`. **L'installatore futuro dovrà verificarne hash e
presenza reali prima del riuso**, perché il manifesto non prova che un file
locale non sia stato modificato o cancellato.

## Preparazione in locale

`scripts/liquid-update-packages.py build` riceve:

- `--root`: distribuzione assemblata, con i binari già compilati;
- `--inventory`: JSON contenente l'elenco esatto dei percorsi relativi;
- `--output`: cartella esterna alla distribuzione per manifesto e oggetti;
- `--version`, `--revision`, `--platform`: identità della release;
- `--notes`: file UTF-8 col changelog leggibile.

L'inventario è esplicito: non si pubblica automaticamente il checkout o la
radice personale. Chi prepara la release deve controllare provenienza e
licenze degli asset selezionati. Il generatore non sostituisce tale revisione.
Sono ammessi solo percorsi del runtime riconosciuti e file regolari/symlink
interni; genitori simbolici e destinazioni esterne sono rifiutati.

Per vedere il piano e il volume effettivo:

```sh
python3 scripts/liquid-update-packages.py plan vecchia/manifest.json nuova/manifest.json --cache cache-oggetti
```

La funzione `fetch()` scarica gli oggetti necessari, verifica lunghezza,
impronta dei byte compressi, espansione limitata, dimensione e impronta del
contenuto; poi li salva atomicamente nella cache. Non estrae in radice,
non esegue script e non riavvia servizi. Gli endpoint locali HTTP sono
consentiti solo nelle prove; la fonte di produzione prevista è GitHub HTTPS.

## Cosa manca per usarlo nel desktop

1. Inventario della distribuzione ufficiale e build riproducibili per piattaforma.
2. Release e autenticazione del manifesto: gli hash **non sono firme**.
3. Contratti di compatibilità e dipendenze tra componenti, soprattutto IPC e
   moduli Qt/wlroots. Il confronto non può determinarli da solo.
4. Collegamento del servizio Dart al manifesto e agli oggetti di release,
   progresso/cancellazione, visualizzazione byte/componenti prima del download.
5. Verifica della radice installata e delle modifiche locali, preparazione
   della transazione, attivazione coerente e rollback anche dopo un crash.
6. Test su aggiornamento di binari reali, biblioteche di sistema e sessione.

Limiti del prototipo: massimo 512 MiB per file e 20.000 percorsi; gli oggetti
sono attualmente letti/compressi in memoria dal generatore e dal trasporto
Python. La cache controlla integralmente l'oggetto per non fidarsi del nome.
Per grandi volumi il trasporto definitivo dovrà essere a flusso, con limiti
cumulativi e gestione dello spazio disponibile. Nessuna promessa di updater
pronto deriva dalle sole prove del formato.

## Prova ripetibile

```sh
python3 tests/test_liquid_update_packages.py
```

Trasferimento HTTP autentico locale: release circa 8 MiB, un file QML
modificato, solo 52 byte trasferiti con una richiesta. Una prova separata
simula un manifesto >1 GiB e verifica lo stesso piano selettivo: non è un
download reale da 1 GiB. Coperti cache corrotta, download corrotto, permessi,
rinomina/rimozione, deduplicazione, symlink, piattaforma e manifesto alterato.
