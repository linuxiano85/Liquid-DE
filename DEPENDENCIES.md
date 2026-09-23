# Le dipendenze di Minerva

Questo elenco è servito una volta sola, ed è stato sbagliato.

Il 26 agosto 2026 un `pacman -Rns plasma kde-applications` ha portato via 211
pacchetti. Fra questi c'erano due moduli QML che Minerva usa: `qt6-websockets`
e `qt6-multimedia`. Questo file ne nominava **uno**. Giacomo ha reinstallato
esattamente quello che c'era scritto qui, e il computer non è arrivato lo stesso
alla schermata di accesso: cinque tentativi di greetd e schermo nero.

Quindi l'elenco non basta che sia lungo. Deve dire **cosa si rompe**, perché è
l'unica informazione che serve a chi legge di corsa da un terminale
d'emergenza. E deve distinguere ciò che impedisce di entrare nel computer da
ciò che toglie una comodità.

> **Se sei qui da un terminale d'emergenza:** la sezione «Senza queste non si
> entra» è quella che ti serve, ed è la prima. Il terminale, su questa
> tastiera, si raggiunge con **Ctrl+Alt+Fn+F3** — senza `Fn` i tasti funzione
> non sono tasti funzione, e sembra che il computer non risponda.

---

## Senza queste non si entra

Se manca una di queste, quickshell non parte. E siccome la schermata di accesso
**è** quickshell, non parte nemmeno quella: greetd riprova cinque volte, poi si
arrende e lo schermo resta nero.

| pacchetto | chi lo usa | cosa succede se manca |
|---|---|---|
| `quickshell` | è la shell | niente |
| `qt6-base`, `qt6-declarative` | il motore QML | niente |
| `qt6-wayland` | le superfici Wayland | niente |
| `qt6-svg` | lo vuole `quickshell` stesso | niente |
| ~~`qt6-multimedia`~~ | **per entrare non serve più** — vedi sotto. Ma serve a [Minerva Media](#minerva-media-e-qt6-multimedia) | si entra, e il lettore multimediale non si apre affatto |
| `dart` | compila ed esegue `minervad` | il demone non c'è, la shell mostra i valori di fabbrica |
| `pam` | l'autenticazione della schermata di accesso e del blocco | non si può entrare |
| `greetd` | avvia la schermata di accesso | si arriva al terminale e basta |
| `ttf-rajdhani`, `ttf-share-tech-mono` | tutte le scritte | si vede, ma con i caratteri di ripiego |

Il compositore, e ce n'è uno:

| pacchetto | note |
|---|---|
| `wlroots0.20` | la libreria su cui è costruito il nostro |
| `minerva-wayland` | **il nostro**, si compila da `compositore/` — dal 2 settembre 2026 è l'unico |

> **Le due righe qui sopra sono cambiate il 27 agosto 2026, e vale la pena
> dire come.**
>
> `qt6-multimedia` era in questa tabella per un difetto nostro: `greeter.qml`
> importa la cartella `"core"`, e importare una cartella obbliga a compilare
> tutti i venti tipi del suo `qmldir` — suoni compresi. Undici note
> pentatoniche per il volume avevano il potere di impedirti di entrare nel
> computer. Adesso stanno in `core/suoni/Campioni.qml`, che è in una
> sottocartella e si carica per indirizzo: se il pacchetto manca, tacciono.
>
> `qt6-websockets` non è più nell'elenco affatto. Il canale col demone è
> passato da `ws://127.0.0.1:11432` a un **socket Unix**, che
> `Quickshell.Io/Socket` sa fare da solo. Una dipendenza in meno, e la porta
> TCP che rispondeva a chiunque sulla macchina non c'è più.
>
> Le sorveglia `minervad/test/moduli_fragili_test.dart`, che oggi non ha
> nessuna eccezione.

---

## Senza queste manca un pezzo, e si vede

Il resto della sessione funziona.

| pacchetto | dà | se manca |
|---|---|---|
| `pipewire`, `pipewire-pulse`, `libpulse` | `pactl` | niente audio, niente cursore del volume |
| `networkmanager` | `nmcli` | niente rete nella barra |
| `bluez`, `bluez-utils` | `bluetoothctl` | niente Bluetooth |
| `polkit` | `pkexec`, e `libpolkit-agent-1` per il nostro agente | la modalità amministratore e il cambio password non possono chiedere niente |
| `libsecret` + un servizio Secret (`gnome-keyring`) | `secret-tool` | account, kDrive e GitHub falliscono — **in silenzio**, ed è il caso peggiore |
| `wl-clipboard`, `cliphist` | appunti e loro storico | niente copia-incolla fra programmi, niente storico |
| `brightnessctl` | luminosità | i tasti della luminosità non fanno niente |
| `grim`, `slurp` | schermate | il pannello di Stamp non cattura |
| `xdg-utils` | `xdg-open`, `xdg-email` | «apri con» e «manda per posta» non partono |
| `udisks2` | `udisksctl` | le chiavette non si montano |
| `avahi` | `avahi-browse` | non si trovano i televisori (Trasmetti a schermo) |
| `libarchive` | `bsdtar` | niente comprimi/estrai |
| `rsync` | la Custodia | niente copie di sicurezza |
| `libnotify` | `notify-send` | gli avvisi degli script non arrivano |
| `xdg-desktop-portal` | il centralino delle domande dei programmi | niente «apri file», niente condivisione schermo, niente segreti |
| `xdg-desktop-portal-gtk` | chi risponde a «apri un file» | i programmi non riescono a farti scegliere un file |
| `xdg-desktop-portal-wlr` | il backend della sessione **minerva-wayland** | là: niente condivisione dello schermo (le finestre «apri file» reggono, ci pensa gtk) |

**Sbagliare backend non dà errore, e questa è la cosa da ricordare.**
`xdg-desktop-portal-hyprland` — che è stato disinstallato il 2 settembre 2026 —
per lavorare cercava `HYPRLAND_INSTANCE_SIGNATURE`: dentro minerva-wayland
quella variabile non esiste, quindi non rispondeva a nessuno. E «nessuno
risponde» non è un errore visibile: è un silenzio. È lo stesso modo in cui si
era rotto il portachiavi di Chrome l'11 agosto 2026.

Chi sceglie il backend è `XDG_CURRENT_DESKTOP`, e la sessione dichiara
`MinervaWayland:Minerva:Hyprland` — tre nomi, in quest'ordine. Il primo trova
`minervawayland-portals.conf`, che dice `default=wlr;gtk`; gli altri due
restano dietro perché chiunque altro guardi quella variabile continui a
riconoscerci, segreti compresi. Lo sorveglia
`minervad/test/due_sessioni_test.dart`.

**L'agente di polkit è nostro** dal 1º settembre 2026: `permessi/`, in C sopra
`libpolkit-agent-1`, con la finestra in `minerva-shell/permessi.qml`. La
password non la verifica lui e non potrebbe — lo fa `polkit-agent-helper-1`,
che è setuid e parla PAM, e a decidere è `polkitd`, che gira come root. Quello
che era di un altro ambiente non era il permesso: era la FINESTRA, e si vedeva.

Il ripiego sugli agenti degli altri ambienti è sparito il 2 settembre 2026
insieme ai pacchetti: su una macchina senza Hyprland e senza KDE quella lista
non trovava comunque niente, e una rete che non c'è è peggio di nessuna rete —
si smette di guardare. `minerva-dentro-wayland` controlla che `minerva-polkit`
sia ancora vivo mezzo secondo dopo averlo avviato, e se non lo è **lo scrive**:
le richieste di permesso riceveranno un errore invece di restare appese.

**`hyprlock` non è più fra le dipendenze** (2 settembre 2026). Non è mai stato
la nostra schermata di blocco — quella è `minerva-shell/blocco/` — e serviva
solo perché installava `/etc/pam.d/hyprlock`, che `scripts/minerva-blocca`
usava come ripiego se `/etc/pam.d/minerva` non si era
potuto creare.

---

## Minerva Media e `qt6-multimedia`

Il 31 agosto 2026 `./scripts/prove.sh` ha detto «il lettore multimediale non
si è aperto». Non era un difetto del codice: **`qt6-multimedia` non è
installato**, e `media/MediaWindow.qml` lo importa alla prima riga.

Come ci si è arrivati vale più della riparazione. Il 27 agosto quel pacchetto
è uscito dalla tabella di sopra, e giustamente: i suoni erano finiti in una
sottocartella e non impedivano più di entrare nel computer. Ma nel toglierlo si
è scritto «**non serve più**», che era vero per l'avvio e falso per il lettore
— e da quel momento questo file diceva a chi lo leggeva di corsa che poteva
farne a meno.

| pacchetto | chi lo usa | cosa succede se manca |
|---|---|---|
| `qt6-multimedia` | `media/MediaWindow.qml`, `media/PiPWindow.qml`, `core/suoni/Campioni.qml` | **Minerva Media non si apre**: «module "QtMultimedia" is not installed». I suoni tacciono |
| `qt6-multimedia-ffmpeg` | il backend che decodifica | il lettore si apre e non riproduce niente |

Non c'è ripiego da costruire, e non è una rinuncia: un lettore multimediale
senza il modulo che legge i video non è una versione ridotta di sé stesso — è
una finestra vuota. Il ripiego onesto qui è `mpv`, che c'è già in tabella più
sotto.

```sh
sudo pacman -S --needed qt6-multimedia qt6-multimedia-ffmpeg
```

---

## Le foto e i video

La galleria di Anteprima legge l'EXIF da sé, in Dart puro: `exiftool` non serve
e non è installato. Ma per i formati che Qt non decodifica serve qualcuno.

| pacchetto | dà | se manca |
|---|---|---|
| `imagemagick` | `magick` | niente miniature di HEIC, AVIF, TIFF, grezzi |
| `libraw` | i delegati dei grezzi di `magick` | i RAW delle macchine fotografiche restano senza miniatura |
| `kimageformats` | i plugin Qt per HEIC/AVIF/JXL | quelle immagini non si aprono nella shell |
| `ffmpeg` | `ffprobe` | i video restano senza data di scatto e senza durata |
| `ffmpegthumbnailer` | il fotogramma | i video restano senza miniatura |
| `mpv` | il ripiego onesto | quando il nostro motore non regge un formato, non c'è dove passare |

Nessuno di questi deve poter spegnere niente: un formato senza miniatura è una
miniatura mancante, non una finestra che non si apre.

---

## Quello che NON serve, anche se sembra

Verificato uno per uno il 26 agosto, dopo che togliere KDE ha rotto tutto.

- **`konsole`, `dolphin`, `kcalc`, `gwenview` e le altre di KDE.** Sono soltanto
  *nominate* — `minervad/lib/services/processi_umani.dart` e
  `minerva-shell/core/Apps.qml` le riconoscono per dare un nome umano a una
  finestra che ne ha una. Non vengono mai eseguite.
- **`polkit-kde-agent`, `hyprpolkitagent`.** L'agente è nostro (sopra), e dal 2 settembre 2026 non c'è più nemmeno il ripiego: nessuno dei due serve.
- **`breeze-cursors`.** Non impostiamo un tema di puntatore per nome.
- **`playerctl`.** I tasti multimediali passano da MPRIS via D-Bus, non da lui.
- **`qtkeychain-qt6`, `kdnssd`, `wayland-utils`, `ttf-hack`.** Nessun uso.

---

## Le prove — e perché hanno una sezione loro

Questa categoria non esisteva, ed è la seconda cosa che il 26 agosto ha
insegnato. Tolto KDE, `./scripts/prove.sh` è diventato rosso su due righe:

```
✗ il blocco schermo non blocca come deve
✗ i programmi X11 dentro minerva-wayland non vanno come devono
```

Nessuna delle due era vera. Il blocco bloccava — le altre dodici verifiche
dello stesso file passavano tutte — e mancava soltanto `wayland-info`, che sta
in `wayland-utils` e se n'era andato con KDE. La prova di XWayland apriva
`kcalc` per avere una finestra X11, cioè **dipendeva dall'ambiente desktop che
stavamo togliendo apposta**.

Una prova che si spegne quando togli KDE non sta provando Minerva.

| pacchetto | dà | serve a | se manca |
|---|---|---|---|
| `python3` | | tutte le prove del compositore | non si prova niente di minerva-wayland |
| `wayland-utils` | `wayland-info` | l'elenco dei protocolli annunciati | quelle verifiche si **saltano** dicendolo, e il resto si prova lo stesso |
| `cmake` | `cmake-gui` | una finestra X11 vera, Qt e multi-istanza | si scende ai ripieghi: `kcalc`, `kwrite`, `pavucontrol`, `zenity` |

**La regola, e vale per ogni prova che si scriverà:** se manca l'attrezzo, si
**salta dicendolo**; non si dichiara rotta la cosa che non si è potuta
guardare. Uno strumento di diagnosi che dichiara morto ciò che è vivo è peggio
di nessuno strumento — sta scritto anche in `scripts/minerva-check.sh`, e la
stessa sera è toccato scriverlo tre volte.

## Se devi togliere un ambiente desktop

`pacman -Rns` non guarda cosa usi: guarda chi ha chiesto cosa. Un pacchetto che
serve a Minerva ma che è entrato come dipendenza di KDE se ne va insieme a KDE,
senza una domanda.

Il gesto che lo impedisce è dire a pacman che quei pacchetti li vogliamo noi:

```sh
sudo pacman -D --asexplicit qt6-multimedia qt6-multimedia-ffmpeg \
                            qt6-svg gnome-keyring gcr libsecret libraw kimageformats \
                            imagemagick ffmpeg ffmpegthumbnailer mpv \
                            libarchive rsync avahi grim slurp libnotify
```

(`qt6-websockets` non c'è più: dal 27 agosto 2026 non lo usa nessuno. Se è
rimasto marcato come voluto da un giro precedente non fa danno — occupa due
megabyte e basta.)

Poi si toglie, si **legge l'elenco che pacman propone** confrontandolo con le
tabelle qui sopra, e — questa è la regola che il 26 agosto ha scritto col
sangue — **prima di riavviare si apre la schermata di accesso finta**:

```sh
MINERVA_PROVA=1 qs -p minerva-shell/prove-greeter.qml
```

Costa dieci secondi. È la differenza fra una riga rossa e un'ora di terminale
d'emergenza.
