#!/bin/bash
# start-minerva-wayland.sh — La sessione Liquid DE.
#
# Prepara l'identità della sessione, il registro e l'ambiente, e alla fine
# esegue `minerva-wayland`, il nostro compositore, che avvia
# `minerva-dentro-wayland` e da lì tutto il resto.
#
# ── Se qualcosa non va ────────────────────────────────────────────────────
#
# Alla schermata di accesso c'è anche la sessione di recupero
# (`minerva-dentro-recupero`: un terminale e nient'altro). E se non si
# arrivasse nemmeno lì: **Ctrl+Alt+Fn+F3** apre una console testuale. Su
# questa tastiera il tasto Fn è obbligatorio — vedi la memoria
# `minerva-console-fn`.

SELF="$(readlink -f "$0")"
MINERVA_DIR="$(dirname "$(dirname "$SELF")")"
# Le cartelle di Liquid DE e quella di questa sessione: servono da subito.
. "$MINERVA_DIR/scripts/minerva-posti.sh"

export MINERVA_ROOT="$MINERVA_DIR"

# ── E `~/.local/bin`, che non c'era ──────────────────────────────────────
#
# greetd non fa passare una shell di login: il PATH che arriva qui è quello
# scarno di systemd — `/usr/local/bin:/usr/bin` e poco altro. `~/.local/bin`,
# dove i programmi si installano quando non si è root, **non c'è**.
#
# Il costo, trovato il 3 settembre 2026 guardando la sessione vera di Giacomo:
# `minerva-polkit` era compilato e installato (`permessi/costruisci.sh` lo mette
# proprio lì), l'installatore diceva verde, e il compositore non lo trovava.
# Risultato: nessun agente dei permessi per due giorni, cioè **nessuna finestra
# della password** in tutta la scrivania — la modalità amministratore del
# gestore file che non chiede niente, e ogni `pkexec` che resta appeso.
#
# Il difetto non stava nell'agente, che era sano, e nemmeno
# nell'installatore, che aveva fatto il suo. Stava nel fatto che
# `command -v minerva-polkit` fa una domanda a cui il PATH risponde per lui, e
# il PATH era la cosa che nessuno aveva guardato.
#
# Prima i programmi di Liquid DE (`CARTELLA_BIN`, il suo prefisso), poi
# `~/.local/bin` per gli altri programmi dell'utente: lì ci sono anche quelli
# di Minerva, con gli stessi nomi, e in questa sessione devono perdere.
CASA_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
export PATH="$MINERVA_DIR/scripts:$CARTELLA_BIN:$CASA_BIN:$PATH"

# ── L'identità della sessione ─────────────────────────────────────────────
#
# XDG_CURRENT_DESKTOP non descrive quale compositore gira: sceglie quale file
# dei portali si legge. `xdg-desktop-portal` cerca un file per OGNI nome della
# lista, in ordine: `liquidde-portals.conf` (nostro: dice `wlr` e chi custodisce
# i segreti) vince. Cambiarlo vorrebbe dire non trovarlo, e con lui perdere le
# password di Chrome — in silenzio. `Minerva` resta dietro perché i programmi
# all'avvio dichiarati per Minerva (`OnlyShowIn=Minerva;`) partano anche qui.
export XDG_CURRENT_DESKTOP=LiquidDE:Minerva
export XDG_SESSION_DESKTOP=LiquidDE
export XDG_SESSION_TYPE=wayland
export QS_NO_RELOAD_POPUP=1

# ── L'ambiente dei programmi ──────────────────────────────────────────────
#
# Ce n'è una che si vede a occhio nudo — `QT_WAYLAND_DISABLE_WINDOWDECORATION`:
# senza, ogni programma Qt disegna la propria barra del titolo **sopra la
# nostra**, e ti ritrovi due barre sulla stessa finestra.
export QT_QPA_PLATFORM="wayland;xcb"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export GDK_BACKEND=wayland,x11
export MOZ_ENABLE_WAYLAND=1

# ── Il puntatore per CHI SE LO DISEGNA DA SÉ ─────────────────────────────
#
# Il compositore il puntatore lo disegna lui, e sulle finestre di Minerva si
# vede sempre. Ma sopra una PAGINA WEB non è così: Firefox e Chrome se lo
# disegnano da soli, e il tema se lo vanno a prendere da `XCURSOR_THEME` —
# oppure, se quella manca, dal nome scritto nelle impostazioni di GTK.
#
# Giacomo, 5 settembre 2026: «sono su google e nella lista dei risultati il
# mouse non compare sulla pagina web, probabilmente ci sarà lo stesso errore
# in molte altre app o pagine».
#
# Aveva ragione, ed era una cosa sola: in `~/.config/gtk-3.0/settings.ini`
# c'era scritto `breeze_cursors`, e quel tema **non è installato**. I browser
# lo cercavano, non lo trovavano, e sulla pagina non disegnavano niente. Sulle
# nostre finestre invece il puntatore c'era, perché lì lo disegna il
# compositore con un tema suo: è per questo che sembrava un difetto dei
# browser.
#
# Quindi il nome si dice noi, e si dice **dopo aver guardato se esiste**. È lo
# stesso controllo che `settings/MisuraPuntatore.qml` fa già prima di
# applicare un tema — un tema che non c'è fa sparire il puntatore, e sparito
# quello non lo si rimette col mouse.
#
# La MISURA viene dalle impostazioni: era scritta 24 a mano, e chi sceglieva
# «Grande» in Impostazioni vedeva crescere il puntatore solo sopra Minerva.
# Il nome CHIESTO si tiene da parte e non si tocca: la prima versione lo
# azzerava al primo posto in cui non lo trovava, e i due posti dopo cercavano
# una cartella senza nome. Trovato provandolo: `breeze_cursors` era installato
# e la sessione rispondeva «ripiego».
_chiesto_cursore=$(sed -n 's/^gtk-cursor-theme-name=//p' \
    "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | tr -d '"' | head -1)
_tema_cursore=""
for _c in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
    if [ -n "$_chiesto_cursore" ] && [ -d "$_c/$_chiesto_cursore/cursors" ]; then
        _tema_cursore=$_chiesto_cursore
        break
    fi
done
if [ -z "$_tema_cursore" ]; then
    # Il primo che esiste davvero. «default» è quello che c'è quasi sempre,
    # Adwaita quello che c'è su ogni installazione con GTK.
    for _t in default Adwaita capitaine-cursors Pop; do
        if [ -d "/usr/share/icons/$_t/cursors" ]; then
            _tema_cursore=$_t
            break
        fi
    done
fi
_misura_cursore=$(sed -n 's/.*"cursorSize"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' \
    "$CARTELLA_CONFIG/settings.json" 2>/dev/null | head -1)
case "$_misura_cursore" in
    ''|*[!0-9]*) _misura_cursore=24 ;;
esac
[ -n "$_tema_cursore" ] && export XCURSOR_THEME="$_tema_cursore"
export XCURSOR_SIZE="$_misura_cursore"
unset _tema_cursore _chiesto_cursore _misura_cursore _c _t

# Chi ci ospita, detto invece che lasciato indovinare. Lo leggono gli script
# e le prove; la shell invece si regola su `MINERVA_CANALE`, che lo scrive il
# compositore stesso quando apre il canale.
export MINERVA_COMPOSITORE=minerva-wayland

# ── XDG_DATA_DIRS per la sessione wayland ────────────────────────────────
#
# Il figlio (minerva-dentro-wayland) non la esportava a D-Bus, e AppScanner
# finiva a 71 app invece di 89. Se non è già impostata, la si
# recupera una volta sola.
if [ -z "${XDG_DATA_DIRS:-}" ]; then
    if command -v systemctl >/dev/null 2>&1; then
        _XDD=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^XDG_DATA_DIRS=//p')
        [ -n "$_XDD" ] && export XDG_DATA_DIRS="$_XDD"
        unset _XDD
    fi
    [ -z "${XDG_DATA_DIRS:-}" ] && export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
fi
[ -z "${XDG_DATA_HOME:-}" ] && export XDG_DATA_HOME="$HOME/.local/share"
# Garantisce che la shell trovi il portale corretto anche in wlroots
[ -z "${XDG_DATA_DIRS:-}" ] || export XDG_DATA_DIRS
# Le applicazioni e le icone di Liquid DE stanno nel suo prefisso.
export XDG_DATA_DIRS="$PREFISSO/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

# ── Un registro da leggere quando qualcosa non parte ──────────────────────
#
# Se la sessione muore all'avvio, il gestore di accesso ributta al login senza dire
# niente. Con questo file si può almeno sapere perché.
LOG="$STATO/session.log"

# ── Una PROVA non azzera il registro della sessione vera ─────────────────
#
# `: > "$LOG"` è giusto per una sessione che comincia: il registro deve
# parlare di questo avvio e non di quello di ieri. Ma lanciando questo script
# a mano per provare qualcosa — cosa che si fa, ed è come è nata la sessione
# di recupero — quella riga cancellava il registro della sessione **in corso**:
# il racconto di come Giacomo è entrato stamattina, sparito per una prova.
#
# È la stessa famiglia dei difetti raccolti in `minerva-trappole-prove`: una
# prova che tocca la sessione viva. `MINERVA_PROVA` è il contrassegno che le
# distingue, ed è già quello che protegge i processi dal `kill`.
if [ -n "${MINERVA_PROVA:-}" ]; then
    LOG="$STATO/session-prova.log"
fi
: > "$LOG"
exec >>"$LOG" 2>&1

echo "── Minerva (wlroots) $(date '+%F %T') ──────────────────"

BIN="$CARTELLA_BIN/minerva-wayland"
if [ ! -x "$BIN" ]; then
    BIN="$(command -v minerva-wayland 2>/dev/null)"
fi
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "ERRORE: minerva-wayland non trovato."
    echo "Costruiscilo con:  compositore/costruisci.sh"
    exit 1
fi
echo "compositore: $BIN"

# ── Gli schermi ───────────────────────────────────────────────────────────
#
# `~/.config/liquid-de/schermi.conf` lo scrive il pannello Schermi e lo legge il
# compositore all'avvio. Se non c'è, ogni schermo prende il modo che preferisce
# a scala 1 — che è la cosa giusta su un computer che non ha ancora scelto, ma
# su questo portatile vuol dire tutto piccolo di un quarto.
if [ ! -f "$CARTELLA_CONFIG/schermi.conf" ]; then
    echo "nota: nessun schermi.conf — scala 1 e modo preferito."
fi

# ── E si parte ────────────────────────────────────────────────────────────
#
# L'argomento è il programma da avviare dentro: da lì nascono il demone, la scrivania e i
# servizi di contorno.
#
# ── E si può chiedere di avviarne un ALTRO ───────────────────────────────
#
# `MINERVA_DENTRO` è la sola differenza fra la sessione vera e quella di
# recupero (`minerva-dentro-recupero`: un terminale e nient'altro). Tutto il
# resto di questo file — identità, ambiente, registro, schermi — resta lo
# stesso apposta, perché è la stessa sessione: duplicare lo script vorrebbe
# dire due vie che divergono su cose che col recupero non c'entrano, e allora
# non si saprebbe più quale differenza conta.
#
# Serve da quando Hyprland se n'è andato: era lui la via di ritorno, e una
# rete non si toglie senza metterne un'altra.
DENTRO="${MINERVA_DENTRO:-$MINERVA_DIR/scripts/minerva-dentro-wayland}"
if [ ! -x "$DENTRO" ]; then
    echo "ERRORE: «$DENTRO» non è eseguibile."
    exit 1
fi
echo "avvio: $BIN + $(basename "$DENTRO")"
exec "$BIN" "$DENTRO"
