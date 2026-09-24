#!/bin/sh
# prova-riconnessione.sh — la shell torna da sola quando il demone riparte?
#
# ── Perché serve uno script e non basta una prova QML ─────────────────────
#
# Perché il guasto ha bisogno di un demone da UCCIDERE e da rimettere in piedi,
# e nessuna delle due cose si fa da dentro QML. Qui c'è l'orchestrazione; la
# parte che guarda è `minerva-shell/prove-riconnessione.qml`.
#
# ── E perché non tocca la sessione vera ───────────────────────────────────
#
# Tre recinti, e servono tutti e tre:
#
#   * `MINERVA_SESSIONE` — un nome tutto suo, quindi un file del canale tutto
#     suo. Senza, il demone di prova riscriverebbe l'indirizzo della sessione
#     VIVA, e la scrivania di chi sta lavorando si ritroverebbe a bussare a un
#     socket che sparisce a fine prova. È successo mentre si scriveva questa
#     riparazione: `--test-start` ha riscritto il canale della sessione in
#     corso, e la scrivania è rimasta appesa a un filo.
#   * `MINERVA_IPC_SOCKET` — un socket tutto suo. Corto, perché
#     `sockaddr_un.sun_path` sono 108 byte e un percorso lungo non dà un errore
#     chiaro.
#   * `MINERVA_CONFIG_DIR` — una cartella di configurazione copiata, così una
#     prova non riscrive le impostazioni vere.
#
# E il demone di prova si uccide per PID, quello che abbiamo lanciato noi: mai
# un `pkill minervad`, che prenderebbe anche quello di Giacomo.
set -eu

RADICE="$(cd "$(dirname "$0")/.." && pwd)"
. "$RADICE/scripts/minerva-cartelle.sh"
NOME="provaricon$$"
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mv-ricon-$$.sock"
CONF="$(mktemp -d)"
REG="$(mktemp)"
DEMONE=""

pulisci() {
    [ -n "$DEMONE" ] && kill "$DEMONE" 2>/dev/null || true
    rm -rf "$CONF" "$SOCKET" "$REG"
    rm -rf "$CARTELLA_RUNTIME/sessioni/$NOME"
}
trap pulisci EXIT INT TERM

[ -d "$CARTELLA_CONFIG_DI_PARTENZA" ] && cp -a "$CARTELLA_CONFIG_DI_PARTENZA/." "$CONF/" 2>/dev/null || true
rm -rf "$CONF/sessioni"

export MINERVA_PROVA=1
export MINERVA_SESSIONE="$NOME"
export MINERVA_IPC_SOCKET="$SOCKET"
export MINERVA_CONFIG_DIR="$CONF"

avvia_demone() {
    ( cd "$RADICE/minervad" && exec dart run bin/minervad.dart ) >> "$REG" 2>&1 &
    DEMONE=$!
    for _ in $(seq 40); do
        grep -q "Server in ascolto su $SOCKET" "$REG" && return 0
        sleep 0.5
    done
    echo "il demone di prova non è partito. Registro:" >&2
    tail -15 "$REG" >&2
    return 1
}

echo "· primo demone…"
avvia_demone || exit 1

# La shell finta parte adesso e si aggancia. Poi, mentre guarda, le si toglie
# il demone da sotto.
USCITA="$(mktemp)"
timeout 60 qs -p "$RADICE/minerva-shell/prove-riconnessione.qml" > "$USCITA" 2>&1 &
QS=$!

# Il tempo di agganciarsi la prima volta.
for _ in $(seq 40); do
    grep -q "aggancio n.1" "$USCITA" && break
    sleep 0.5
done

echo "· ora si toglie il demone da sotto"
kill "$DEMONE" 2>/dev/null || true
wait "$DEMONE" 2>/dev/null || true
DEMONE=""
sleep 1

echo "· e si rimette in piedi, come fa il guardiano"
avvia_demone || exit 1

wait "$QS" 2>/dev/null || true
sed 's/\x1b\[[0-9;]*m//g' "$USCITA"
if grep -q "TUTTE PASSATE" "$USCITA"; then
    rm -f "$USCITA"
    exit 0
fi
rm -f "$USCITA"
exit 1
