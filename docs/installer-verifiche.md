# Verifiche dell’installer

L’installer e `--scan` condividono i manifesti in
`config/liquid-install-{apps,required}.list`. Ogni applicazione del menu deve
avere script eseguibile, file `.desktop` e icona prima di richiedere privilegi.
Quando si aggiunge un componente obbligatorio, aggiungere anche i suoi ingressi
al manifesto e un caso di errore nella suite.

Le compilazioni obbligatorie, incluso Polkit, precedono la copia della radice e
la registrazione delle sessioni. Il file PAM e la preparazione di greetd sono
verificati prima di pubblicare una nuova voce di accesso. L’installazione non è
ancora una transazione atomica di tutti i file: un errore di copia successivo
può richiedere una nuova esecuzione dell’installer.

Gli avvisi non bloccanti producono un riepilogo nel terminale e nella GUI.
Se mpv non si ricompila ma esiste un modulo precedente, l’installer dichiara
esplicitamente che verrà mantenuto; non afferma che userà Qt Multimedia.

Eseguire le regressioni senza installare il desktop:

```sh
python3 -m unittest discover -s tests/installer -v
```

La suite esegue gli script reali su dati temporanei con sostituti per sudo,
pacman, compilatori e servizi. Non esegue i comandi amministrativi reali. Nei
contenitori che consentono solo UID 0, la guardia root viene disabilitata solo
nella copia di prova; il suo rifiuto originale è verificato separatamente.
Non sono prove di rendering QML, di autenticazione PAM o di registrazione
Polkit nella sessione grafica.

GitHub Actions esegue le regressioni su Ubuntu e una compilazione reale
dell’agente Polkit in un contenitore Arch. La build completa del desktop,
la finestra Posta e il primo accesso su hardware devono ancora essere provati.
In particolare, un agente KDE già registrato nella sessione richiede una
verifica dedicata: non va terminato dall’installer eseguito dentro Plasma.
