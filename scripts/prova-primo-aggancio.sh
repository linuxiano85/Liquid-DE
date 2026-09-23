#!/bin/sh
# prova-primo-aggancio.sh — quanto ci mette la shell ad agganciare un demone
# che nasce DOPO di lei.
#
# ── Il difetto che ha fatto scrivere questa prova ─────────────────────────
#
# All'accesso shell e demone partono insieme, e la shell è più svelta: Qt più
# il nostro QML sono mezzo secondo, il demone ce ne mette due o tre. Quindi la
# shell bussa a un socket che non c'è ancora, e riprova con un'attesa che
# RADDOPPIA: 120, 240, 480, 960, 1920 ms.
#
# A tre secondi e sette decimi ha appena provato, e il tentativo dopo è a
# cinque e sette. Se il demone diventa pronto a due secondi e mezzo, la shell
# se ne accorge a tre e sette — un secondo e due decimi di attesa pura, con
# tutto già pronto da tutte e due le parti.
#
# Sul registro della sessione del 31 agosto 2026 si vede: la scrivania disegna
# sfondo e icone a 0,624 s, e la dock compare a **4,666**. Quel buco è metà
# «dieci secondi per avviarsi» che Giacomo ha segnalato; l'altra metà era il
# demone interpretato invece che compilato (1965 ms contro 162, misurati).
#
# ── Cosa misura ──────────────────────────────────────────────────────────
#
# Il tempo fra «il demone è in ascolto» e «la shell si è salutata con lui».
# Non l'avvio della shell, non l'avvio del demone: solo l'attesa in mezzo,
# che è l'unica cosa che questo codice controlla.
#
# ── E perché non tocca la sessione vera ───────────────────────────────────
#
# Gli stessi tre recinti di `prova-riconnessione.sh`: nome di sessione suo,
# socket suo, cartella di configurazione sua. Il demone di prova si uccide per
# PID — quello che abbiamo lanciato noi — mai con un `pkill minervad`, che
# prenderebbe anche quello di Giacomo.
set -eu

RADICE="$(cd "$(dirname "$0")/.." && pwd)"
NOME="provaggancio$$"
SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mv-agg-$$.sock"
CONF="$(mktemp -d)"
REG="$(mktemp)"
USCITA="$(mktemp)"
DEMONE=""
QS=""

# Quanto si concede fra «demone pronto» e «shell agganciata». Il ritmo minimo
# è 120 ms più un giro di andata e ritorno: mezzo secondo è largo il doppio, e
# stretto abbastanza da diventare rosso se il raddoppio torna.
TETTO_MS=600

# Quanto si aspetta prima di accendere il demone. Deve bastare perché la
# vecchia attesa arrivi al suo massimo — 120+240+480+960 = 1,8 s — o la prova
# sarebbe verde anche col difetto dentro.
ATTESA=4

pulisci() {
    [ -n "$DEMONE" ] && kill "$DEMONE" 2>/dev/null || true
    [ -n "$QS" ] && kill "$QS" 2>/dev/null || true
    rm -rf "$CONF" "$SOCKET" "$REG" "$USCITA"
    rm -rf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/minerva/sessioni/$NOME"
}
trap pulisci EXIT INT TERM

[ -d "$HOME/.config/minerva" ] && cp -a "$HOME/.config/minerva/." "$CONF/" 2>/dev/null || true
rm -rf "$CONF/sessioni"

export MINERVA_PROVA=1
export MINERVA_SESSIONE="$NOME"
export MINERVA_IPC_SOCKET="$SOCKET"
export MINERVA_CONFIG_DIR="$CONF"
# La shell non deve trovare il compositore della sessione vera e mandargli
# verbi: qui si prova il canale col DEMONE, non quello col compositore.
MINERVA_CANALE=/non/esisto
export MINERVA_CANALE

echo "── Il primo aggancio, con il demone che nasce dopo ──"

# ── Prima la shell, e senza nessun demone ────────────────────────────────
timeout 60 qs -p "$RADICE/minerva-shell/prove-riconnessione.qml" \
    > "$USCITA" 2>&1 &
QS=$!
sleep "$ATTESA"

if grep -q "aggancio n.1" "$USCITA"; then
    echo "  NO   si è agganciata a QUALCOSA senza nessun demone acceso" >&2
    exit 1
fi

# ── E adesso il demone ───────────────────────────────────────────────────
#
# Compilato se c'è: è quello che gira all'accesso vero, e con `dart run` il
# suo avvio (due secondi) coprirebbe la cosa che si sta misurando.
if [ -x "$RADICE/minervad/build/minervad" ]; then
    ( exec "$RADICE/minervad/build/minervad" ) >> "$REG" 2>&1 &
else
    ( cd "$RADICE/minervad" && exec dart run bin/minervad.dart ) >> "$REG" 2>&1 &
fi
DEMONE=$!

PRONTO=""
for _ in $(seq 60); do
    if grep -q "Server in ascolto su $SOCKET" "$REG"; then
        PRONTO=$(date +%s%3N)
        break
    fi
    sleep 0.1
done
if [ -z "$PRONTO" ]; then
    echo "  NO   il demone di prova non è partito. Registro:" >&2
    tail -15 "$REG" >&2
    exit 1
fi

AGGANCIO=""
for _ in $(seq 80); do
    if grep -q "aggancio n.1" "$USCITA"; then
        AGGANCIO=$(date +%s%3N)
        break
    fi
    sleep 0.05
done
if [ -z "$AGGANCIO" ]; then
    echo "  NO   la shell non si è agganciata affatto" >&2
    sed 's/\x1b\[[0-9;]*m//g' "$USCITA" | tail -10 >&2
    exit 1
fi

# ── Il conto ─────────────────────────────────────────────────────────────
#
# Il ciclo di sopra guarda ogni 50 ms, quindi la misura è arrotondata per
# eccesso di quel tanto. Va bene: il tetto è largo il doppio del vero, e un
# errore che spinge verso il rosso non può rendere verde una prova rotta.
DELTA=$((AGGANCIO - PRONTO))
if [ "$DELTA" -le "$TETTO_MS" ]; then
    echo "  ok   agganciata $DELTA ms dopo che il demone era pronto (tetto $TETTO_MS)"
    echo "TUTTE PASSATE (1)"
    exit 0
fi

echo "  NO   ci ha messo $DELTA ms (tetto $TETTO_MS)" >&2
echo "       È l'attesa che raddoppia: vedi «_senzaFrettaDopo» in" >&2
echo "       minerva-shell/core/Ipc.qml. Con tutto già pronto da tutte e due" >&2
echo "       le parti, questo tempo è scrivania che non compare." >&2
echo "FALLITE" >&2
exit 1
