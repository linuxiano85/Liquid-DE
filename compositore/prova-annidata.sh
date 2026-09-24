#!/bin/sh
# prova-annidata.sh — minerva-wayland dentro la sessione vera, con la
# scrivania di Minerva dentro di lui.
#
#     ./prova-annidata.sh            compositore + shell di Minerva
#     ./prova-annidata.sh alacritty  compositore + shell + un terminale
#
# ── La regola che non si discute ──────────────────────────────────────────
#
# ANNIDATO, SEMPRE. Il plugin delle barre è caduto due volte portandosi via
# la sessione di lavoro, e lì cadeva un plugin: qui cadrebbe il compositore,
# cioè tutto lo schermo, con dentro il lavoro non salvato.
#
# `WLR_BACKENDS=wayland` è l'unica riga che lo garantisce: senza, in una
# sessione grafica wlroots sceglie da sé, e su una console libera sceglierebbe
# DRM — cioè prenderebbe lo schermo vero.
#
# ── E perché MINERVA_PROVA=1 ──────────────────────────────────────────────
#
# Perché è il contrassegno che permette di chiudere una prova senza rischiare
# di chiudere la sessione: si legge in `/proc/PID/environ` PRIMA di mandare
# un segnale, e senza non c'è modo sicuro di distinguere le due.
set -eu

QUI="$(cd "$(dirname "$0")" && pwd)"
RADICE="$(cd "$QUI/.." && pwd)"
. "$RADICE/scripts/minerva-cartelle.sh"
BIN="$CARTELLA_BIN/minerva-wayland"

[ -x "$BIN" ] || { echo "manca $BIN — lancia prima ./costruisci.sh" >&2; exit 1; }

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "FERMO: non sei in una sessione Wayland." >&2
    echo "Fuori da una, wlroots prenderebbe lo schermo vero." >&2
    exit 1
fi

export MINERVA_PROVA=1
# ── `wayland` di serie; `headless` quando si vuole fotografare da uno script ─
#
# Dentro la sessione viva il backend wayland apre una FINESTRA, e il
# compositore annidato disegna solo quando quella finestra è visibile: coperta
# da un terminale, `grim` resta appeso ad aspettare un fotogramma che non
# arriva mai. Con `WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1` non c'è
# nessuna finestra e nessun mouse — le fotografie escono sempre e il
# puntatore lo muove il verbo `dito` del canale (solo in prova).
#
# Tutti e due sono annidati e sicuri: né l'uno né l'altro può prendere lo
# schermo vero. Quello che NON si deve fare è lasciare che wlroots scelga da
# sé (`WLR_BACKENDS` vuota), perché su una console libera sceglierebbe DRM.
case "${WLR_BACKENDS:-}" in
    headless) export WLR_BACKENDS=headless ;;
    *)        export WLR_BACKENDS=wayland
              # In una finestra il bordo non ferma il puntatore: gli angoli
              # attivi si allargano, o prenderli sarebbe un tiro a segno.
              export MINERVA_ANGOLO_LATO="${MINERVA_ANGOLO_LATO:-16}" ;;
esac

# ── La riga che impedisce alla prova di toccare la sessione vera ──────────
#
# `Quickshell.Hyprland` non trova Hyprland guardandosi intorno: legge
# `HYPRLAND_INSTANCE_SIGNATURE` dall'ambiente. E qui l'ambiente è quello della
# sessione di Giacomo, che questa prova eredita per intero.
#
# Senza toglierla, la shell dentro minerva-wayland manderebbe i suoi comandi
# **al Hyprland vero**: regole delle finestre, `follow_mouse`, animazioni,
# scorciatoie — tutto applicato alla scrivania su cui stiamo lavorando, mentre
# crediamo di provarne un'altra. Un guasto della prova diventerebbe un guasto
# della sessione, che è esattamente ciò che l'annidamento deve escludere.
#
# `MINERVA_COMPOSITORE` è il verso positivo della stessa cosa: dice a chi sta
# dentro chi lo ospita, invece di lasciarglielo indovinare.
unset HYPRLAND_INSTANCE_SIGNATURE
export MINERVA_COMPOSITORE=minerva-wayland

REGISTRO="${TMPDIR:-/tmp}/liquid-de-wayland-prova.log"
: > "$REGISTRO"

"$BIN" > "$REGISTRO" 2>&1 &
COMPOSITORE=$!

# Il socket lo stampa lui: si aspetta di leggerlo invece di indovinarlo.
DENTRO=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    DENTRO=$(sed -n 's/^minerva-wayland: in ascolto su //p' "$REGISTRO" | head -1)
    [ -n "$DENTRO" ] && break
    sleep 0.5
done
if [ -z "$DENTRO" ]; then
    echo "il compositore non è partito. Registro:" >&2
    grep -v 'extensions:' "$REGISTRO" | tail -20 >&2
    kill "$COMPOSITORE" 2>/dev/null || true
    exit 1
fi
echo "compositore su $DENTRO   (registro: $REGISTRO)"

# ── E il canale, senza il quale la prova provava un'altra cosa ────────────
#
# `core/Compositore.qml` sceglie con chi parlare leggendo `MINERVA_CANALE`:
# senza quella variabile prende il ramo di Hyprland — e qui la firma di
# Hyprland è stata tolta apposta due righe più su. Il risultato era una shell
# che dentro il nostro compositore mandava comandi **a nessuno**: la scrivania
# si vedeva, e nessun clic sulle scrivanie o sulla dock arrivava da nessuna
# parte. Una prova che non prova quello che si crede.
#
# Il percorso non si indovina: lo stampa il compositore, e si aspetta di
# leggerlo come si aspetta il display.
CANALE=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    CANALE=$(sed -n 's/^minerva-wayland: canale su //p' "$REGISTRO" | head -1)
    [ -n "$CANALE" ] && break
    sleep 0.5
done
if [ -n "$CANALE" ]; then
    echo "canale su $CANALE"
else
    echo "ATTENZIONE: nessun canale. La shell non potrà comandare niente." >&2
fi

# ── E un DEMONE suo, che è la terza porta ────────────────────────────────
#
# Le altre due erano già chiuse: `HYPRLAND_INSTANCE_SIGNATURE` tolta, e
# `MINERVA_CANALE` puntato al nostro compositore. Restava aperta questa, ed è
# quella che si vede meno.
#
# La shell parla anche col DEMONE, sulla porta 11432, e senza dirle niente
# quella porta è quella della sessione VERA. Il risultato, visto a schermo il
# 26 agosto 2026: dentro il compositore annidato la scrivania di Minerva
# disegnava una barra del titolo per «wlroots - WL-1» — una finestra della
# sessione di fuori, che qui dentro non esiste. Il demone rispondeva con le
# finestre di Giacomo.
#
# Quella metà era solo confusa da guardare. L'altra no: **ogni impostazione
# cambiata durante una prova finiva nel `settings.json` vero.** Un giro di
# prove sulle Impostazioni si riscriveva la scrivania su cui si sta
# lavorando, che è esattamente ciò che l'annidamento deve escludere.
#
# Quindi la prova ha il suo demone, sulla sua porta, con la sua cartella di
# configurazione — **copiata** da quella vera, non vuota: una scrivania di
# prova che parte dai valori di fabbrica non somiglia a quella di nessuno, ed
# è il difetto che la memoria chiama «non si agisce sui valori di ripiego».
PORTA_PROVA="${MINERVA_IPC_PORT:-11433}"
# ── Il percorso è FISSO, e non per pigrizia ──────────────────────────────
#
# Il 13 settembre 2026 l'audit di Codex l'aveva reso unico (`mktemp -d`),
# con una ragione giusta: due prove insieme si pesterebbero i piedi. Ma sei
# prove — `prova-impostazioni.py`, `prova-dock.py`, `prova-effetto.py`,
# `prova-cornice.py`, `prova-inattivita.py`, `prova-contrasto.py` — leggono
# ESATTAMENTE questo percorso per trovare il canale del demone di prova, e con
# un nome casuale non lo trovavano più. Non si è visto perché `prove.sh` non
# era stato lanciato.
#
# Le prove girano una alla volta (`prove.sh` le mette in fila), quindi il
# nome fisso basta. Chi ne vuole due insieme lo dice: `MINERVA_CONF_PROVA`.
CONF_PROVA="${MINERVA_CONF_PROVA:-${TMPDIR:-/tmp}/liquid-de-prova-conf}"
rm -rf "$CONF_PROVA"
mkdir -p "$CONF_PROVA"
if [ -d "$CARTELLA_CONFIG_DI_PARTENZA" ]; then
    # Tutto TRANNE `sessioni/`, che contiene la chiave della sessione viva.
    # Copiarla vorrebbe dire portare un segreto dentro `/tmp` per niente: il
    # demone di prova la sua chiave se la genera da sé, e quella vera qui non
    # serve a nessuno. Un segreto che non si copia è un segreto che non si
    # può perdere.
    for voce in "$CARTELLA_CONFIG_DI_PARTENZA/"* "$CARTELLA_CONFIG_DI_PARTENZA/".[!.]*; do
        [ -e "$voce" ] || continue
        case "$(basename "$voce")" in sessioni) continue;; esac
        cp -a "$voce" "$CONF_PROVA/" 2>/dev/null || true
    done
fi

export MINERVA_IPC_PORT="$PORTA_PROVA"
export MINERVA_CONFIG_DIR="$CONF_PROVA"
# ── E la cartella di configurazione di TUTTO, non solo di Minerva ────────
#
# Sempre dall'audit del 13 settembre: `Input.qml` scrive in
# `$HOME/.config/hypr` e `Display.qml` in `$HOME/.config/minerva` passando da
# `$HOME`, cioè ignorando `MINERVA_CONFIG_DIR`. Una prova sulle Impostazioni
# riscriveva i file veri. Con `XDG_CONFIG_HOME` dentro la cartella di prova
# quelle scritture finiscono qui.
#
# Solo la configurazione, però. `XDG_DATA_HOME` e `XDG_CACHE_HOME` — che
# l'audit spostava pure — contengono le icone installate per utente e la
# cache di compilazione del QML: spostarle vorrebbe dire una scrivania di
# prova con le icone sbagliate e mezzo secondo più lenta a partire, cioè
# fotografie diverse per una ragione che non c'entra con la prova.
export XDG_CONFIG_HOME="$CONF_PROVA/xdg-config"
mkdir -p "$XDG_CONFIG_HOME"
# Isolamento socket Unix: senza, il demone di prova usa lo stesso
# /run/user/1000/minerva/canale-<sess>.sock del demone della sessione vera
# (stesso XDG_SESSION_ID) e fallisce con "già in ascolto".
export MINERVA_SESSIONE="prova"
export MINERVA_IPC_SOCKET="$CONF_PROVA/canale.sock"

# ── E il file del canale, o si rompe la sessione VERA ────────────────────
#
# Le due righe qui sopra non bastano, e la differenza è costata il 26 agosto
# 2026. Il demone scrive porta e chiave in un file, e i posti dove lo cerca
# sono in ordine: **`$XDG_RUNTIME_DIR/liquid-de/sessioni/<sessione>/canale`
# prima della cartella di configurazione.** La sessione è la stessa, la
# cartella di runtime è la stessa — quindi il demone di prova ha scritto la
# SUA porta (11433) e la SUA chiave sopra quelle del demone di Giacomo.
#
# Il sintomo: la scrivania continuava a funzionare, perché la shell era già
# collegata. Ma ogni finestra NUOVA leggeva quel file e cercava un demone che
# non c'era più — `minerva-check.sh` diceva «demone non risponde sulla
# 11433», e le prove della luce notturna sono diventate rosse mezz'ora dopo,
# lontanissime dalla causa.
#
# `MINERVA_TOKEN_FILE` vince su tutto ed esiste apposta: sta scritto in
# `canale_segreto.dart` che «serve alle prove, che non devono toccare il file
# vero di chi sta lavorando». Lo leggono tutti e due — il demone in Dart e
# la shell in `core/Ipc.qml`.
export MINERVA_TOKEN_FILE="$CONF_PROVA/canale"

DEMONE_LOG="${TMPDIR:-/tmp}/liquid-de-demone-prova.log"
(
    # Il demone di prova deve vedere le stesse variabili della shell di prova,
    # altrimenti usa il socket della sessione vera e collide.
    export MINERVA_SESSIONE="prova"
    export MINERVA_IPC_SOCKET="$CONF_PROVA/canale.sock"
    export MINERVA_TOKEN_FILE="$CONF_PROVA/canale"
    export MINERVA_CONFIG_DIR="$CONF_PROVA"
    export MINERVA_COMPOSITORE=minerva-wayland
    export MINERVA_CANALE="$CANALE"
    cd "$RADICE/minervad" || exit 1
    # `MINERVA_DA_SORGENTE=1` salta il compilato: serve quando si è appena
    # aggiunta una chiave ai valori di fabbrica e non si vuole ricompilare
    # il demone per provarla. Il compilato è più veloce a partire, e resta la
    # scelta di serie.
    if [ -x build/minervad ] && [ -z "${MINERVA_DA_SORGENTE:-}" ]; then
        exec ./build/minervad
    fi
    exec dart run bin/minervad.dart
) > "$DEMONE_LOG" 2>&1 &
DEMONE=$!

# Si aspetta che risponda: partire la shell prima vuol dire una scrivania che
# per due secondi mostra i valori di fabbrica, e li scrive se qualcuno tocca
# qualcosa.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if [ -S "$CONF_PROVA/canale.sock" ] || ss -ltn 2>/dev/null | grep -q ":$PORTA_PROVA "; then break; fi
    sleep 0.5
done
if [ -S "$CONF_PROVA/canale.sock" ] || ss -ltn 2>/dev/null | grep -q ":$PORTA_PROVA "; then
    echo "demone di prova su $CONF_PROVA/canale.sock (conf: $CONF_PROVA)"
else
    echo "ATTENZIONE: il demone di prova non risponde su $CONF_PROVA/canale.sock. Registro: $DEMONE_LOG" >&2
    tail -20 "$DEMONE_LOG" >&2 || true
fi

MINERVA_PROVA=1 WAYLAND_DISPLAY="$DENTRO" QT_QPA_PLATFORM=wayland \
    MINERVA_CANALE="$CANALE" MINERVA_SESSIONE=prova \
    MINERVA_IPC_SOCKET="$CONF_PROVA/canale.sock" MINERVA_TOKEN_FILE="$CONF_PROVA/canale" \
    MINERVA_CONFIG_DIR="$CONF_PROVA" \
    qs -p "$RADICE/minerva-shell/shell.qml" \
    > "${TMPDIR:-/tmp}/liquid-de-shell-prova.log" 2>&1 &
SHELL_PID=$!

if [ $# -gt 0 ]; then
    sleep 3
    MINERVA_PROVA=1 WAYLAND_DISPLAY="$DENTRO" QT_QPA_PLATFORM=wayland \
        MINERVA_CANALE="$CANALE" MINERVA_SESSIONE=prova \
        MINERVA_IPC_SOCKET="$CONF_PROVA/canale.sock" MINERVA_TOKEN_FILE="$CONF_PROVA/canale" \
        MINERVA_CONFIG_DIR="$CONF_PROVA" MINERVA_COMPOSITORE=minerva-wayland \
        "$@" &
fi

echo "shell dentro. Ctrl+C per chiudere tutto."
trap 'kill "$SHELL_PID" "$DEMONE" "$COMPOSITORE" 2>/dev/null || true' INT TERM
wait "$COMPOSITORE"
kill "$SHELL_PID" "$DEMONE" 2>/dev/null || true
