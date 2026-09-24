#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  Minerva Desktop — Installer delle dipendenze di sistema
#  Uso:  ./scripts/install-minerva.sh
#  Richiede la password di sudo (una sola volta).
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

MINERVA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$MINERVA_DIR/scripts/minerva-cartelle.sh"

c_ok()   { printf '\033[1;32m  ✔\033[0m %s\n' "$*"; }
c_info() { printf '\033[1;36m  ➜\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m  ⚠\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m  ✘\033[0m %s\n' "$*"; }
c_head() { printf '\n\033[1;35m━━ %s ━━\033[0m\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    c_err "Non eseguire questo script come root. Usa il tuo utente normale (chiederà sudo)."
    exit 1
fi

# ── 1. Pacchetti dai repository ufficiali ─────────────────────────────────
PKGS=(
    # Toolchain e dipendenze del fork privato: niente wlroots/SceneFX esterni.
    base-devel meson ninja pkgconf
    wayland wayland-protocols libdrm libinput libxkbcommon pixman
    mesa libglvnd seatd libdisplay-info libliftoff hwdata
    # vulkan-headers e glslang servivano solo al renderer Vulkan, che non si
    # compila più di serie (vedi compositore/costruisci.sh).
    vulkan-icd-loader
    libxcb xcb-util-wm xcb-util-errors xcb-util-renderutil xorg-xwayland
    cairo pango systemd glib2
    desktop-file-utils libpulse qt6-5compat
    # Custodia, dispositivi e strumenti invocati dai servizi/applicazioni.
    git rsync libsecret udisks2 upower python
    # ── I portali, e perché ce ne vogliono due ─────────────────────────
    #
    # `-wlr` è quello che serve DAVVERO sotto minerva-wayland: parla i
    # protocolli di wlroots (`wlr-screencopy`, `xdg-output`), che il nostro
    # compositore implementa. Senza, «condividi schermo» di Chrome è muto e
    # nessuno lo dice — il portale scende a `gtk`, che sotto wlroots non sa
    # fotografare lo schermo, e una richiesta senza risposta non è un errore
    # visibile: è un silenzio.
    #
    # `-hyprland` se n'è andato con la sessione che lo usava.
    xdg-desktop-portal xdg-desktop-portal-wlr
    # Shell QML
    quickshell qt6-wayland qt6-declarative qt6-base qt6-svg
    # ── E il multimediale, che era stato tolto per metà buona ragione ──
    #
    # Il 27 agosto 2026 `qt6-multimedia` è uscito dall'elenco di ciò che
    # serve per ENTRARE, e giustamente: i suoni erano finiti in una
    # sottocartella e non potevano più impedire l'accesso. Ma da lì è uscito
    # anche di qui, e senza di lui **Minerva Media non si apre affatto** —
    # `media/MediaWindow.qml` importa `QtMultimedia` alla prima riga.
    # Trovato dalle prove il 31 agosto: «il lettore multimediale non si è
    # aperto». Il `-ffmpeg` è il backend: senza, il lettore si apre e non
    # riproduce niente, che è peggio.
    qt6-multimedia qt6-multimedia-ffmpeg
    # Backend
    dart greetd
    # Servizi usati dai widget della barra
    cliphist wl-clipboard brightnessctl networkmanager
    pipewire pipewire-pulse wireplumber bluez bluez-utils
    # Terminale predefinito + utilità
    alacritty papirus-icon-theme
    # ── Chi apre la finestrella della password ─────────────────────────
    #
    # `polkit` e basta. La finestra è NOSTRA dal 1º settembre 2026
    # (`permessi/src/minerva-polkit.c` più `minerva-shell/permessi.qml`), e
    # `polkit-agent-1` — la libreria che parla con `polkit-agent-helper-1` —
    # arriva con questo pacchetto, che su questa macchina c'è comunque perché
    # lo vuole systemd.
    #
    # Qui prima c'era `hyprpolkitagent`, e prima ancora `polkit-kde-agent`:
    # cioè un pezzo di un altro ambiente in mezzo alla scrivania di Minerva,
    # con un altro carattere e un altro modo di dire «password sbagliata».
    polkit
    # Screenshot e selezione area
    grim slurp
    # Font di sistema di fallback
    ttf-dejavu noto-fonts noto-fonts-emoji
    # ── I due caratteri di Minerva ─────────────────────────────────────
    #
    # `adwaita-fonts` porta Adwaita Sans, che dal 3 settembre 2026 è la voce
    # dell'interfaccia; `noto-fonts` porta Noto Sans Mono, che è quello dei
    # numeri. Vengono dai repository e non da un `curl` a GitHub: un carattere
    # scaricato a mano è un pezzo di scrivania che dipende dalla rete il giorno
    # dell'installazione, e se quel giorno la rete non c'è la scrivania nasce
    # con un ripiego che nessuno ha scelto.
    adwaita-fonts
)

# Conservare il portachiavi già scelto; su una macchina nuova fornirne uno.
if ! command -v ksecretd >/dev/null 2>&1 &&
   ! command -v gnome-keyring-daemon >/dev/null 2>&1; then
    PKGS+=(gnome-keyring)
fi

c_head "Dipendenze"
# Si installa solo quello che MANCA, e senza aggiornare il sistema.
#
# Prima qui c'era `pacman -Syu`: installare una scrivania aggiornava tutto
# CachyOS, cosa che nessuno aveva chiesto e che, andando storta, trascinava
# con sé anche l'altra scrivania. Il timore che giustificava l'aggiornamento
# completo — un database appena scaricato con librerie vecchie — qui non
# c'è: `pacman -T` guarda cosa manca col database che c'è già, e se manca
# qualcosa lo si installa senza scaricarne uno nuovo (`-S`, non `-Sy`).
MANCANTI=$(pacman -T "${PKGS[@]}" 2>/dev/null || true)
if [ -z "$MANCANTI" ]; then
    c_ok "c'è già tutto: niente da installare"
elif sudo pacman -S --needed --noconfirm $MANCANTI; then
    c_ok "installati: $(printf '%s ' $MANCANTI)"
else
    c_err "Non riesco a installare: $(printf '%s ' $MANCANTI)"
    c_info "Probabilmente il database dei pacchetti è vecchio. Aggiorna il sistema"
    c_info "quando vuoi tu (sudo pacman -Syu) e rilancia questo installatore."
    exit 1
fi

# Compilare prima di configurare la sessione: gli errori devono essere visibili.
c_head "Compositore Minerva e prove automatiche"
"$MINERVA_DIR/compositore/costruisci.sh" || {
    c_err "Build/verifica del compositore fallita."
    exit 1
}
c_head "Dipendenze del backend"
(cd "$MINERVA_DIR/minervad" && dart pub get) || exit 1

# ── 2. I caratteri ────────────────────────────────────────────────────────
#
# Qui si scaricavano da GitHub le cinque varianti di Rajdhani e Share Tech
# Mono. Non si scaricano più, per due ragioni che si sommano:
#
#  1. dal 3 settembre 2026 i caratteri sono Adwaita Sans e Noto Sans Mono, che
#     stanno nei repository (`adwaita-fonts`, `noto-fonts`) — cioè
#     nell'elenco dei pacchetti qui sopra, dove si vedono;
#  2. un `curl` a GitHub dentro un installatore è una dipendenza dalla rete
#     nel momento peggiore: se quel giorno non risponde, la scrivania nasce
#     con un carattere di ripiego che nessuno ha scelto e nessuno saprà
#     perché.
#
# La verifica che ci siano davvero sta più sotto, insieme agli altri programmi:
# un carattere che manca non è un avviso da leggere di sfuggita, è metà
# dell'aspetto della scrivania.
c_head "Caratteri"
for f in "Adwaita Sans" "Noto Sans Mono"; do
    if fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/^ *//' \
       | grep -qix "$f"; then
        c_ok "$f"
    else
        c_warn "manca «$f»: Minerva userà un carattere di ripiego"
        c_warn "  → sudo pacman -S adwaita-fonts noto-fonts"
    fi
done

# ── 3. Sessione Wayland registrata in SDDM/GDM ────────────────────────────
c_head "Registrazione della sessione «Liquid DE» nel display manager"
# Il gestore di accessi non riesce a eseguire uno script il cui
# percorso contiene uno spazio. `/usr/share/plasmalogin/scripts/wayland-session`
# finisce con `exec $@` senza virgolette: la shell spezza il percorso sugli
# spazi, prova a eseguire «.../Progetti/Minerva» e la sessione muore prima di
# partire — si inserisce la password e si torna alla schermata di accesso senza
# nessun messaggio. Si installa quindi un ponte in un percorso senza spazi.
#
# Si SOSTITUISCE il segno `@MINERVA_DIR@` invece di copiare il file com'è: il
# ponte viene copiato e non collegato, quindi non può risalire da solo a dove
# sta Minerva, e l'unico che lo sa con certezza è questo script. È l'unico
# percorso assoluto che Minerva scrive da qualche parte, ed è scritto qui,
# adesso, sapendolo.
# ── E il ponte per la sessione sul NOSTRO compositore ────────────────────
#
# Si installa sempre, anche se `minerva-wayland` non è ancora costruito: la
# voce nella schermata di accesso c'è, e chi la sceglie senza aver costruito
# il compositore trova scritto nel registro della sessione cosa lanciare.
# Meglio una voce che spiega di una voce che non c'è.
sed "s|@MINERVA_DIR@|$MINERVA_DIR|g" \
    "$MINERVA_DIR/scripts/minerva-session-wayland" \
    | sudo install -Dm755 /dev/stdin /usr/local/bin/liquid-de-sessione
c_ok "/usr/local/bin/liquid-de-sessione installato ($MINERVA_DIR)"

# ── E il ponte del RECUPERO ──────────────────────────────────────────────
#
# Finché c'è stata la sessione Hyprland, la via di ritorno era quella. Dal
# 1 settembre 2026 Hyprland se ne va, e con lui quella rete: questa la
# sostituisce, ed è nostra — il nostro compositore con dentro un terminale e
# nient'altro.
#
# Si installa sempre e per prima, e non è un dettaglio d'ordine: una via di
# ritorno che si installa dopo la cosa da cui deve proteggere è una via di
# ritorno che manca proprio nel giro in cui serve.
sed "s|@MINERVA_DIR@|$MINERVA_DIR|g" \
    "$MINERVA_DIR/scripts/minerva-session-recupero" \
    | sudo install -Dm755 /dev/stdin /usr/local/bin/liquid-de-recupero
c_ok "/usr/local/bin/liquid-de-recupero installato ($MINERVA_DIR)"

# ── Il cambio password, e la sua regola ───────────────────────────────────
#
# `scripts/minerva-utente` gira come amministratore per una cosa sola:
# cambiare la password del proprio account. Si installa in un percorso FISSO
# perché la regola di polkit qui sotto deve nominarlo carattere per carattere,
# e la cartella del progetto cambia da un computer all'altro.
#
# La regola serve a chiedere MENO: senza, `pkexec` ricade sull'azione generica
# e domanda la password di un amministratore per cambiare la propria. Con lei
# domanda la tua, che è quello che ha sempre fatto `passwd`.
sudo install -Dm755 "$MINERVA_DIR/scripts/minerva-utente" /usr/local/bin/liquid-de-utente
sudo install -Dm644 "$MINERVA_DIR/config/polkit/org.liquidde.utente.policy" \
    /usr/share/polkit-1/actions/org.liquidde.utente.policy
c_ok "/usr/local/bin/liquid-de-utente e la sua regola polkit installati"

# ── La modalità amministratore del gestore file ───────────────────────────
#
# `scripts/minerva-radice` è l'unico pezzo di Minerva che gira da root su
# richiesta di una finestra. Vale la stessa regola di sopra, e qui pesa il
# doppio: il percorso è FISSO e la copia è di root, perché root non deve
# eseguire un file che l'utente può riscrivere. Chi gira come te — un pacchetto
# npm, un'estensione del browser — potrebbe altrimenti riscriverlo e aspettare
# che tu accenda la modalità amministratore.
sudo install -Dm755 "$MINERVA_DIR/scripts/minerva-radice" /usr/local/bin/liquid-de-radice
sudo install -Dm644 "$MINERVA_DIR/config/polkit/org.liquidde.radice.policy" \
    /usr/share/polkit-1/actions/org.liquidde.radice.policy
c_ok "/usr/local/bin/liquid-de-radice e la sua regola polkit installati"

# ── Qui si scriveva ~/.config/hypr/minerva-paths.conf ────────────────────
#
# Serviva a Hyprland per sapere dove sta Minerva: una riga `$minerva = …` che
# la sua configurazione leggeva all'avvio. Dal 2 settembre 2026 quel
# compositore non c'è più, e i percorsi li passa `start-minerva-wayland.sh`
# nell'ambiente della sessione — `MINERVA_ROOT`, che è la stessa cosa detta a
# chi la usa davvero.
#
# Scriverlo lo stesso «per sicurezza» sarebbe peggio che non scriverlo: un file
# che nessuno legge ma che sembra configurazione è il primo posto dove si va a
# cercare quando qualcosa non torna.

# ── E qualcuno che faccia DAVVERO il portachiavi ────────────────────────
#
# Il file qui sotto configura il PORTALE dei segreti
# (`org.freedesktop.impl.portal.Secret`), che è una cosa diversa dal servizio
# `org.freedesktop.secrets` sul bus — quello che cercano `secret-tool`, la
# Custodia e gli account online. Sono due nomi vicini per due cose diverse, ed
# è esattamente per questo che il difetto è sopravvissuto ad agosto: il portale
# era a posto e il portachiavi non c'era.
#
# Su Arch il servizio di KDE si chiama `ksecretd` e il suo file D-Bus dichiara
# solo `org.kde.secretservicecompat`: il nome standard lo prende a programma
# avviato. Sotto Plasma lo avvia Plasma; sotto Minerva lo avvia
# `scripts/minerva-dentro-wayland` — ma se sulla macchina non c'è NESSUN
# portachiavi installato, non c'è niente da avviare, e la Custodia non può
# tenere il permesso di GitHub né gli account una password.
#
# Le dipendenze includono un portachiavi se non ne esiste già uno.
# Verificare anche il comando disponibile nella sessione corrente.
if command -v ksecretd >/dev/null 2>&1 \
    || command -v gnome-keyring-daemon >/dev/null 2>&1; then
    c_ok "portachiavi presente: la sessione lo avvia da sola"
else
    c_warn "nessun portachiavi installato su questa macchina"
    c_info "senza, la Custodia non può tenere il permesso di GitHub e gli"
    c_info "account online non ricordano una password — e non lo dicono."
    c_info "Ne basta uno:  sudo pacman -S kwallet    (oppure gnome-keyring)"
fi

# Chi custodisce i segreti in Minerva. Senza questo file il portale non trova
# nessuno che risponda a `org.freedesktop.impl.portal.Secret`, e i programmi
# che ci tengono le password (Chrome per primo) ripiegano in silenzio su un
# archivio in chiaro con una chiave diversa: rientrando in un'altra scrivania
# vanno rifatti tutti gli accessi. Le ragioni per esteso stanno nel file.
#
# Il nome del file viene da XDG_CURRENT_DESKTOP (`LiquidDE`): è di Liquid DE
# e di nessun altro, così installarlo non tocca i portali di Minerva.
install -Dm644 "$MINERVA_DIR/config/xdg-desktop-portal/liquidde-portals.conf" \
    "$HOME/.config/xdg-desktop-portal/liquidde-portals.conf"
c_ok "~/.config/xdg-desktop-portal/liquidde-portals.conf creato"

# ── La voce al login: Liquid DE ──────────────────────────────────────────
#
# Accanto a quelle che ci sono già (Minerva compresa), mai al loro posto.
# Il documento-qui è QUOTATO (`<<'EOF'`) e dentro non ci sono segni gravi.
# Le due cose vanno insieme: in un documento-qui non quotato le righe che
# cominciano con `#` sono TESTO, non commenti, e quello che sta fra due segni
# gravi viene ESEGUITO — con `sudo` davanti. La guardia di `prove.sh` mi ha
# preso qui il 26 agosto 2026, e aveva ragione.
sudo install -Dm644 /dev/stdin \
    /usr/share/wayland-sessions/liquid-de.desktop <<'EOF'
[Desktop Entry]
Name=Liquid DE
Comment=La scrivania liquida, sul proprio compositore
Exec=/usr/local/bin/liquid-de-sessione
Type=Application
# L'ordine conta: da qui xdg-desktop-portal sceglie il file dei portali,
# provandoli uno per uno nell'ordine scritto.
#   · LiquidDE → liquidde-portals.conf, che dice «wlr» e chi custodisce i
#     segreti. Scriverci «wlroots» vorrebbe dire non trovarlo, e con lui
#     perdere le password di Chrome;
#   · Minerva resta dietro: i programmi all'avvio dichiarati per Minerva
#     partono anche qui.
DesktopNames=LiquidDE;Minerva;
EOF
c_ok "/usr/share/wayland-sessions/liquid-de.desktop creato"

# ── La terza voce: il recupero ───────────────────────────────────────────
#
# Il nostro compositore con dentro un terminale e nient'altro. Niente demone,
# niente scrivania, niente servizi: ogni pezzo in più è un pezzo che può
# impedirti di arrivare al terminale, che è esattamente ciò da cui questa
# sessione deve proteggere.
#
# Sostituisce la voce Hyprland come rete di sicurezza, e la sostituisce meglio:
# quella era un ambiente intero che poteva rompersi per conto suo, questa è
# venti righe.
#
# Il nome comincia con «Minerva» perché nell'elenco del login stia accanto
# alle altre due, e dice cos'è senza spaventare chi lo legge per sbaglio.
sudo install -Dm644 /dev/stdin \
    /usr/share/wayland-sessions/liquid-de-recupero.desktop <<'EOF'
[Desktop Entry]
Name=Liquid DE (recupero)
Comment=Il compositore di Liquid DE con un solo terminale — per riparare quando la scrivania non parte
Exec=/usr/local/bin/liquid-de-recupero
Type=Application
# Gli stessi nomi della sessione vera: da qui xdg-desktop-portal sceglie i
# file dei portali, e una sessione di recupero che non trova i nostri sarebbe
# una sessione in cui non si può nemmeno aprire un file per ripararlo.
DesktopNames=LiquidDE;Minerva;
EOF
c_ok "/usr/share/wayland-sessions/liquid-de-recupero.desktop creato"

# ── 3a. Le applicazioni di Minerva ────────────────────────────────────────
#
# Per il resto del sistema devono essere applicazioni come tutte le altre: un
# comando nel PATH e un file `.desktop` che lo descrive. Senza, non compaiono
# nel menu di nessun altro programma, non si possono scegliere come «apri
# con», e il nostro gestore file non è nemmeno candidato ad aprire le
# cartelle.
#
# Gestore file e Impostazioni sono anche due processi a sé
# (`minerva-shell/filemanager.qml` e `minerva-shell/settings.qml`), non più due
# finestre della shell: `minerva-files` e `minerva-settings` li avviano
# davvero. Un errore in uno dei due non tocca la barra.
#
# Il collegamento in ~/.local/bin non è una comodità: `minerva-files` scopre
# dov'è installata Minerva SEGUENDO quel collegamento. Copiare lo script
# invece di collegarlo lo lascerebbe senza radici.
# ── 3-zero. Il demone, compilato ──────────────────────────────────────────
#
# `dart run` compila ed esegue ogni volta, con la macchina virtuale e dentro
# il compilatore. Compilato una volta sola, il demone si accende cinque volte
# più in fretta e occupa undici volte meno memoria (1317 ms / 210 MB contro
# 261 ms / 19 MB, misurati). L’installazione richiede una build riuscita;
# il ripiego interpretato della sessione non nasconde errori di installazione.
c_head "Demone di Minerva"
if "$MINERVA_DIR/scripts/minerva-compila"; then
    c_ok "demone compilato in minervad/build/minervad"
else
    c_err "Compilazione del demone fallita."
    exit 1
fi

c_head "Applicazioni di Minerva"
# Tutto nel prefisso di Liquid DE: `~/.local/bin`, `~/.local/share/applications`
# e le icone in `~/.local/share/icons` sono di Minerva, con gli stessi nomi.
# La sessione di Liquid DE mette `$PREFISSO/bin` in testa al PATH e
# `$PREFISSO/share` in XDG_DATA_DIRS.
APPLICAZIONI="$PREFISSO/share/applications"
mkdir -p "$CARTELLA_BIN" "$APPLICAZIONI"

# Le icone stanno in `hicolor`, che per specifica è il tema dove ogni programma
# installa le PROPRIE: chi cambia tema di icone non deve perderle, e nessun
# tema di terze parti ne contiene una per noi.
#
# Il nome del file è anche il nome della classe della finestra (`//@ pragma
# AppId` in cima a ogni punto d'ingresso) ed è anche il nome del `.desktop`.
# I tre coincidono di proposito: è la catena con cui dock, barra del titolo e
# menu risalgono da una finestra aperta al programma che l'ha aperta.
ICONE="$PREFISSO/share/icons/hicolor/scalable/apps"
mkdir -p "$ICONE"

# `minerva-media` è entrato in questo elenco il 23 agosto 2026, e prima
# mancava: il lettore multimediale esisteva, funzionava, si poteva avviare da
# terminale — e non compariva nel menu di nessuno. Un programma che non è nel
# menu non esiste, e infatti l'MP3 continuava ad aprirlo un'altra cosa.
for app in minerva-files minerva-settings minerva-monitor minerva-viewer \
           minerva-editor minerva-calcolatrice minerva-media minerva-custodia \
           minerva-manutenzione minerva-terminale; do
    # Un collegamento e non una copia: il file nel progetto resta l'unico da
    # correggere, e una modifica vale subito senza reinstallare niente.
    ln -sf "$MINERVA_DIR/scripts/$app" "$CARTELLA_BIN/$app"
    install -Dm644 "$MINERVA_DIR/desktop/$app.desktop" "$APPLICAZIONI/$app.desktop"
    install -Dm644 "$MINERVA_DIR/assets/icons/$app.svg" "$ICONE/$app.svg"
    c_ok "$app installato"
done
# ── E le due che nel menu NON devono comparire ───────────────────────────
#
# Il blocco schermo e la finestra dei permessi non si avviano dal menu: li
# apre Minerva quando servono. Il file `.desktop` serve lo stesso, e per una
# ragione sola: senza, il portale xdg scrive «App info not found for
# 'minerva-blocco'» a ogni blocco schermo e «per 'minerva-permessi'» a ogni
# richiesta di password. Sono righe che finiscono nel registro esattamente nei
# momenti in cui il registro si va a leggere.
#
# `minerva-blocco.desktop` esisteva dal 10 agosto 2026 e non è mai stato
# installato da nessuno: l'avviso c'era ancora, e il file che doveva toglierlo
# stava lì da tre settimane.
for app in minerva-blocco minerva-permessi; do
    install -Dm644 "$MINERVA_DIR/desktop/$app.desktop" "$APPLICAZIONI/$app.desktop"
    c_ok "$app installato (nascosto dal menu)"
done

update-desktop-database "$APPLICAZIONI" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "$PREFISSO/share/icons/hicolor" >/dev/null 2>&1 || true

# ── Chi apre le immagini ──────────────────────────────────────────────────
#
# Dichiarare i tipi nel `.desktop` mette Anteprima fra le SCELTE POSSIBILI;
# essere quella predefinita è un'altra cosa e va detta, altrimenti in una
# sessione Minerva un doppio clic su una fotografia continua ad aprire il
# visualizzatore di un altro ambiente.
#
# Si scrive, e si dice ad alta voce che è stato scritto. Installare un ambiente
# desktop VUOL DIRE anche questo: chi resta il predefinito è una scelta
# dell'ambiente, non un dettaglio. Quasi sempre la riga che si sostituisce non
# l'ha scritta l'utente ma il gestore file di un altro ambiente, la prima volta
# che ci ha aperto una fotografia.
#
# Si toccano solo i formati che sappiamo davvero disegnare, e nessun formato
# vettoriale o di macchina fotografica: quelli restano a chi li faceva.
for tipo in image/png image/jpeg image/gif image/bmp image/webp image/tiff; do
    xdg-mime default minerva-viewer.desktop "$tipo" 2>/dev/null || true
done
c_ok "Anteprima è il visualizzatore predefinito delle immagini"
c_info "per tornare indietro: xdg-mime default <programma>.desktop image/jpeg"

# ── Chi apre audio e video ────────────────────────────────────────────────
#
# Stessa scelta e stessa ragione, con una storia in più che vale la pena
# ricordare. Fino al 23 agosto 2026 questi sette tipi audio li dichiaravano
# DUE programmi di Minerva: il lettore e «Suoneria», un editor di suonerie in
# PyQt6. Due programmi che dicono «apro io» vuol dire che a decidere è
# l'ordine dentro `mimeapps.list`, cioè il caso.
#
# E il caso aveva scelto la Suoneria, perché era l'unica delle due nel menu:
# il lettore vero non era in questo script e non veniva installato affatto.
# Suoneria è in `.attic/2026-08-23-suoneria/`, con il perché per esteso.
#
# Un tipo dichiarato da due nostri programmi è un difetto, non una comodità:
# quando succede se ne toglie uno.
for tipo in audio/mpeg audio/x-wav audio/wav audio/mp4 audio/aac audio/flac \
            audio/ogg video/mp4 video/webm video/x-matroska video/quicktime; do
    xdg-mime default minerva-media.desktop "$tipo" 2>/dev/null || true
done
c_ok "Media è il lettore predefinito di audio e video"
c_info "per tornare indietro: xdg-mime default <programma>.desktop audio/mpeg"

# Il PATH qui non conta: è la sessione di Liquid DE a mettere il prefisso in
# testa (`start-minerva-wayland.sh`), e fuori dalla sessione i comandi
# `minerva-*` devono restare quelli di Minerva.

# ── 3a-bis. Priorità di scheduling, dove c'è ananicy ──────────────────────
#
# Su CachyOS (e ovunque ci sia ananicy-cpp acceso) le regole di serie spingono
# `plasmashell` a nice -6 e `kwin_wayland` a -12, mentre mandano `qs` a +10 e
# qualunque cosa si chiami `dart` a +9. Senza questo file la nostra shell gira
# sedici punti di priorità dietro a quella di KDE, e la lentezza che si sente
# non viene dal nostro codice. Il commento dentro al file spiega i numeri.
if [ -d /etc/ananicy.d ]; then
    sudo install -Dm644 "$MINERVA_DIR/config/ananicy/zz-liquid-de.rules" \
        /etc/ananicy.d/zz-liquid-de.rules
    sudo systemctl try-restart ananicy-cpp >/dev/null 2>&1 || true
    c_ok "priorità di scheduling registrate in /etc/ananicy.d"
fi

# ── 3b. Configurazioni che devono stare in ~/.config/hypr ─────────────────
#
# Qui c'era `hypridle`, che non accettava il percorso della propria
# configurazione: l'opzione `-c` veniva ignorata e il programma moriva dicendo
# che non ne trovava nessuna. Leggeva solo da ~/.config/hypr, e quindi bisognava
# mettergliela lì. Non c'è più.
# ── Il file PAM del blocco schermo ─────────────────────────────────────────
#
# `scripts/minerva-blocca` chiede a PAM se la password è giusta, e PAM vuole
# sapere COME chiederlo: è il file `/etc/pam.d/liquid-de`. Senza, il blocco non
# parte proprio — di proposito, perché un blocco che non riesce a verificare
# niente è un computer perso, non un computer protetto.
#
# Il contenuto sta in `config/pam/liquid-de`, commentato riga per riga: niente
# `nullok`, `nodelay` (la pausa fra i tentativi la fa la schermata, meglio),
# e soglie di faillock generose perché quelle di sistema — 3 tentativi e 10
# minuti, con un contatore condiviso col login — chiudono fuori chi sbaglia a
# digitare e chi fa girare le prove automatiche.
#
# Si CONFRONTA e si aggiorna: prima bastava che il file esistesse, e chi aveva
# installato Minerva a luglio si teneva per sempre la versione di allora.
#
# Il servizio PAM è obbligatorio anche su una macchina senza altri desktop.
c_head "Blocco schermo"
if cmp -s "$MINERVA_DIR/config/pam/liquid-de" /etc/pam.d/liquid-de; then
    c_ok "/etc/pam.d/liquid-de gia aggiornato"
elif sudo install -Dm644 "$MINERVA_DIR/config/pam/liquid-de" /etc/pam.d/liquid-de \
        >/dev/null 2>&1; then
    c_ok "/etc/pam.d/liquid-de installato"
else
    c_err "Impossibile installare /etc/pam.d/liquid-de: blocco schermo non pronto."
    exit 1
fi

c_head "Configurazioni in ~/.config/hypr"
mkdir -p "$HOME/.config/hypr"
# Qui si collegava `hypridle.conf`. Dal 1º settembre 2026 l'inattività non ha
# più un programma: la conta il compositore, la politica sta nella shell, e le
# tre soglie stanno nelle impostazioni di Minerva e in nessun altro posto.

# ── L'agente delle password ───────────────────────────────────────────────
#
# È nostro: `permessi/`, in C, sopra `libpolkit-agent-1`. Si compila qui
# perché è l'unico pezzo compilato oltre al compositore, e chi installa
# Minerva non deve sapere che esiste una cartella in più da costruire a mano.
#
# La compilazione è obbligatoria: una macchina pulita potrebbe non avere
# nessun agente alternativo per le richieste di autorizzazione.
c_head "Agente delle password"
"$MINERVA_DIR/permessi/costruisci.sh" || {
    c_err "Compilazione dell'agente delle password fallita."
    exit 1
}
c_ok "minerva-polkit compilato e installato"

# ── 5. Verifica finale ────────────────────────────────────────────────────
c_head "Verifica"
ALL_OK=1
# `minerva-wayland` e `minerva-polkit` sono NOSTRI e si compilano: se mancano
# non è un pacchetto da installare ma una costruzione da rifare, e il messaggio
# deve poterlo dire. Per questo stanno in un elenco a parte.
# `Hyprland` stava in testa a questo elenco, e con `c_err` — cioè
# l'installazione si dichiarava FALLITA senza di lui. Dal 2 settembre 2026
# Minerva gira sul suo compositore e quel pacchetto va tolto: lasciarlo qui
# vorrebbe dire che il giorno del distacco l'installatore diventa rosso proprio
# perché il distacco è riuscito.
for bin in qs dart cliphist wl-copy brightnessctl nmcli pactl bluetoothctl alacritty; do
    if command -v "$bin" &>/dev/null; then
        c_ok "$bin"
    else
        c_err "$bin MANCANTE"
        ALL_OK=0
    fi
done

for bin in minerva-wayland minerva-cattura minerva-pty minerva-polkit; do
    if [ -x "$CARTELLA_BIN/$bin" ]; then
        c_ok "$bin"
    else
        c_err "$bin manca"
        ALL_OK=0
    fi
done

echo
if [[ $ALL_OK -eq 1 ]]; then
    c_ok "Installazione completata. Esci e scegli «Liquid DE» nel display manager,"
    c_ok "oppure prova la sessione annidata con: ./compositore/prova-annidata.sh"
else
    c_err "Installazione incompleta: alcuni componenti mancano."
    exit 1
fi
