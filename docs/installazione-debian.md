# Installazione su Debian, Ubuntu e Mint

Il percorso Debian è **in preparazione, non ancora certificato per l’uso
quotidiano**. Riconoscimento, bootstrap APT, build del runtime privato e
packaging sono implementati; build completa e primo accesso su Mint devono
ancora essere validati. Il repository pubblico non è ancora configurato:
`packaging/repositories.json` non contiene origini abilitate.

Le basi previste sono Debian 13, Ubuntu 24.04/26.04 e Mint 22.x con base Ubuntu
noble, solo amd64/x86_64. Mint usa i pacchetti costruiti su Ubuntu 24.04.
LMDE, altre derivate non verificate e sistemi immutabili vengono rifiutati.
Arch mantiene l’installer esistente; Fedora sarà affrontata successivamente.

## Flusso dell’installer

```sh
./install.sh --plan
./install.sh --scan
```

Questi controlli non installano pacchetti e non richiedono privilegi.
`--scan` conserva il protocollo `total`/`missing` usato dall’installer.

Quando un repository firmato sarà configurato, `./install.sh`:

1. Riconosce sistema, versione e architettura e mostra i pacchetti mancanti.
2. Scarica la chiave registrata e verifica SHA-256 e fingerprint.
3. Installa una sorgente APT dedicata con `Signed-By`, senza cambiare le origini
   delle altre applicazioni.
4. Aggiorna gli indici e installa `liquid-de`. APT risolve le dipendenze; una
   soluzione che richiede rimozioni viene rifiutata con `--no-remove`.
5. Registra la sessione Wayland, conservando il gestore di accesso attuale.

Un PPA generico per Qt non basta: il fork wlroots richiede anche Wayland,
protocolli, libdrm, xkbcommon, pixman e libdisplay-info più recenti di quelli
disponibili su Mint 22. Il repository Liquid fornirà `liquid-de-runtime`
con quelle librerie private, senza sostituire glibc, Mesa o i driver.

Il runtime usa Qt 6.10.2 e il Quickshell fissato in
`native/quickshell/source.json`, ricompilati insieme ai moduli QML nativi.
Versioni, archivi e hash sono in `packaging/runtime-sources.json`. Le fonti
dei checksum sono le informazioni di download Qt e gli annunci di rilascio
dei rispettivi progetti. Il crash reporter cpptrace di Quickshell è
disabilitato nella build pacchettizzata; rimangono registri e core dump.

## Pacchetti candidati locali

Per costruire e installare direttamente sulla propria macchina, prima che
esista un repository pubblico:

```sh
./install.sh --build-local --plan
./install.sh --build-local
```

Eseguire da un terminale normale come utente: l’installer chiede `sudo` per
APT, mentre compila senza privilegi. Installa le dipendenze di sviluppo,
prepara Dart se necessario, costruisce il runtime privato e i `.deb`, poi
li installa. Servono almeno 24 GiB liberi; la compilazione completa è lunga.
`--jobs 2` limita il parallelismo; `--work-dir /percorso/privato` sceglie una
directory esterna ai sorgenti. Ripetendo il comando con la stessa directory
si riutilizzano i componenti completati e si conservano stato e registri.
Questo percorso è ancora da validare con una build e un accesso reali su Mint;
le regressioni automatiche verificano il flusso con sostituti dei compilatori.

Prima di pubblicare un repository, scaricare l’artefatto CI della propria
base e usare la cartella contenente i `.deb`:

```sh
./install.sh --packages-dir /percorso/packages
```

L’installer verifica nomi, versione comune, architettura e base ABI. Installa
desktop e runtime; i candidati locali devono provenire dalla propria build
verificata. Le dipendenze ordinarie arrivano dai repository di sistema.

Per includere anche il login facoltativo, senza attivarlo:

```sh
./install.sh --packages-dir /percorso/packages --with-login
```

`liquid-de-login` dipende da greetd. L’attivazione è esplicita:

```sh
sudo minerva-greetd attiva
```

Il cambiamento vale dal riavvio. `sudo minerva-greetd indietro` ripristina il
gestore precedente; la rimozione del pacchetto login ripristina la selezione
prima di eliminare i file. Non vengono fermati display manager attivi.
La personalizzazione del greeter del precedente installer da sorgenti non è
ancora trasferita al percorso pacchettizzato.

## Build e packaging

Usare una macchina o un contenitore della base scelta, con SDK Dart 3.12.0
disponibile. La toolchain serve solo per costruire i pacchetti. La build
scarica anche l’archivio Qt completo, circa 1,2 GB compressi; prevedere spazio
per sorgenti e oggetti.

```sh
python3 packaging/native.py build-dependencies --target ubuntu-24.04
python3 packaging/native.py prepare --target ubuntu-24.04 --output /tmp/liquid-build/source
python3 packaging/runtime.py --work-dir /tmp/liquid-build/runtime-build --prefix /tmp/liquid-build/runtime
python3 packaging/native.py build --target ubuntu-24.04 --source /tmp/liquid-build/source --runtime-prefix /tmp/liquid-build/runtime
python3 packaging/native.py stage --target ubuntu-24.04 --source /tmp/liquid-build/source --runtime-prefix /tmp/liquid-build/runtime --destdir /tmp/liquid-build/stage
python3 packaging/native.py package --target ubuntu-24.04 --destdir /tmp/liquid-build/stage --output /tmp/liquid-build/packages
```

Installare prima le dipendenze indicate dal primo comando. Gli altri comandi
si eseguono senza privilegi in directory nuove. Usare `debian-13` o
`ubuntu-26.04` per le altre basi, costruendo il runtime nella stessa base.
`DESTDIR` è supportato anche dai costruttori del compositore e dell’agente
Polkit e non attiva servizi durante lo staging.

`prepare` adatta i percorsi prima di compilare Dart, lasciando intatti i
sorgenti originali. I prodotti usano CPU baseline x86-64. Lo staging controlla
architettura, dipendenze ELF, symlink e permessi. I pacchetti dichiarano sia
le dipendenze calcolate da `dpkg-shlibdeps` sia i servizi invocati da Liquid.
La versione del pacchetto include la base ABI.

La workflow `.github/workflows/debian-packages.yml` esegue le regressioni;
con `workflow_dispatch` e `full_build=true` costruisce e prova l’installazione
su tutte e tre le basi. Produce candidati non firmati e sorgenti corrispondenti.
Non pubblica e non abilita servizi di accesso.

## Repository APT e aggiornamenti

`packaging/repository.py` genera `Packages`, `Release`, `InRelease` e firme
separate usando una chiave di rilascio già disponibile:

```sh
python3 packaging/repository.py --target ubuntu-24.04 --packages /percorso/packages --sources /percorso/sources --output /percorso/repository-nuovo --key FINGERPRINT_COMPLETO
```

Il comando non genera chiavi e non pubblica online. Pubblicare il risultato
su HTTPS mantenendo disponibili sorgenti corrispondenti e licenze.
Registrare in `packaging/repositories.json`, sotto `channels.ubuntu-24.04`,
i campi `url`, `keyUrl`, `keySha256` e `fingerprint`. `channel.json` contiene
fingerprint e checksum della chiave. Ogni base ha un repository separato;
Mint condivide quello Ubuntu 24.04.

La pagina aggiornamenti riconosce i pacchetti e apre l’aggiornamento APT in
un terminale invece di scaricare archivi sorgenti da GitHub. Desktop e runtime
restano vincolati alla stessa versione; se presente si aggiorna anche il login.

Al primo accesso, gli avviatori personali che puntano alla vecchia installazione
in `~/.local/opt/liquid-de` vengono conservati in una copia di recupero nello
stato XDG di Liquid. Configurazioni, dati e vecchia radice rimangono sul disco.
Il codice pacchettizzato usa `/usr/lib/liquid-de`; le altre applicazioni non
ereditano percorsi di caricamento delle librerie private.

## Criteri di rilascio

```sh
python3 -m unittest discover -s tests/packaging -v
python3 -m unittest discover -s tests/installer -v
```

Le regressioni costruiscono `.deb` reali con piccoli binari di prova e usano
sostituti per le azioni amministrative: non dimostrano l’avvio della shell
completa. La prova delle firme viene saltata dove il sandbox impedisce un
agente GPG isolato.

Il primo requisito è una build completa su Mint 22.3: accesso, recupero,
blocco/sblocco, Polkit, stampa, audio, rete, portali, aggiornamento e rimozione.
Ripetere poi su Debian 13 e Ubuntu 24.04/26.04. Le funzioni amministrative
legate a pacman, comprese parti della manutenzione e della Fucina, richiedono
verifica separata. Nessuna piattaforma è certificata soltanto perché viene
riconosciuta dall’installer.
