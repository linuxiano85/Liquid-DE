#!/bin/bash
# prove-pannelli.sh — Apre tutti i pannelli della Spine e ascolta cosa dice.
#
# ── Perché questa prova esiste ─────────────────────────────────────────────
#
# I nove pannelli della barra erano l'unica parte grossa dell'interfaccia che
# NESSUNA prova apriva. Le prove di finestra aprono le app; le prove QML
# provano le funzioni; i pannelli si aprivano solo col dito di Giacomo.
#
# Il 24 agosto 2026 `prove.sh` ha trovato nel registro della shell viva:
#
#     WARN scene: QML Membrane at @spine/Spine.qml[332:5]:
#                 Binding loop detected for property "panelHeight"
#
# Un anello che girava sessanta volte al secondo, presente da chissà quando,
# visto solo perché per caso qualcuno aveva aperto un pannello prima che le
# prove leggessero il registro. Una prova che dipende da cosa ha toccato
# l'utente non è una prova.
#
# Qui si aprono tutti e nove, uno per uno, e si legge il pezzo di registro che
# ne è uscito. I nomi si prendono dal registro della Spine e non da un elenco
# scritto qui: un pannello nuovo entra nelle prove da solo.
#
# ── E si fanno DUE giri: barra in alto e barra in basso ────────────────────
#
# Dal 3 settembre 2026 la barra puo stare in fondo, e in quel caso la lingua
# dei pannelli non scende: sale. Sono le stesse misure con un segno davanti,
# ed e esattamente la forma di codice che si rompe in silenzio - perche il
# verso che nessuno usa non lo guarda nessuno.
#
# Il giro con la barra in basso costa dieci secondi e prova la meta della
# geometria che altrimenti nessuno vedrebbe fino al giorno in cui Giacomo la
# sposta.
#
# ── Sulla shell VIVA, e va bene così ───────────────────────────────────────
#
# Aprire e chiudere un pannello è ciò che fa un utente ogni minuto: non cambia
# niente sul disco e non tocca la sessione. Costa due secondi di lampeggio
# sullo schermo di chi lancia le prove, e in cambio prova la parte
# dell'interfaccia che nessun altro proverebbe.
set -u

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

PID=$(ps -eo pid,args --no-headers \
      | awk '$2 == "qs" && index($0, "minerva-shell/shell.qml") { print $1; exit }')
if [ -z "$PID" ]; then
    echo "SALTATE: nessuna shell di Minerva in esecuzione"
    exit 0
fi

# I nomi dei pannelli, dal registro vero.
NOMI=$(grep -oP '^\s{8}"\K[a-z]+(?=":\s*\{)' "$ROOT/minerva-shell/spine/Spine.qml")
if [ -z "$NOMI" ]; then
    echo "NO: non riesco a leggere il registro dei pannelli da Spine.qml"
    exit 1
fi

# Quante righe ha il registro ADESSO: si guarderà solo ciò che viene dopo.
PRIMA=$(qs log --pid "$PID" 2>/dev/null | wc -l)

# ── La barra si rimette dov'era, comunque vada ─────────────────────────────
#
# Questa prova gira sulla scrivania VERA, e sposta una preferenza di chi la sta
# usando. Il ripristino non puo dipendere dall'arrivare in fondo: un Ctrl-C, un
# pannello che non risponde, un `set -e` di domani - e Giacomo si ritroverebbe
# la barra dall'altra parte senza sapere perche.
IMPOSTAZIONI="${XDG_CONFIG_HOME:-$HOME/.config}/minerva/settings.json"
LEGGI="$ROOT/scripts/posizione-barra.py"

posizione_barra() { python3 "$LEGGI" "$IMPOSTAZIONI"; }
metti_barra() {
    python3 "$LEGGI" "$IMPOSTAZIONI" "$1"
    # Il demone se ne accorge sorvegliando il file e lo dice alla shell: il
    # tempo e per il giro completo, non per la scrittura.
    sleep 1.5
}

BARRA_ERA=$(posizione_barra)
ripristina() { [ -n "$BARRA_ERA" ] && python3 "$LEGGI" "$IMPOSTAZIONI" "$BARRA_ERA" >/dev/null 2>&1; }
trap ripristina EXIT INT TERM

giro() {
    for nome in $NOMI; do
        ESITO=$(qs ipc --pid "$PID" call minerva panel "$nome" 2>&1)
        if [ "$ESITO" != "ok" ]; then
            echo "NO: il pannello «$nome» non si e aperto ($1): $ESITO"
            exit 1
        fi
        # Abbastanza perche l'animazione della lingua finisca: un anello di
        # legami si vede DURANTE la discesa, e chiudendo subito non lo si
        # vedrebbe mai.
        sleep 0.7
        qs ipc --pid "$PID" call minerva panel "$nome" >/dev/null 2>&1
        sleep 0.2
    done
}

QUANTI=$(echo "$NOMI" | wc -w)

giro "barra in alto"
metti_barra basso
giro "barra in basso"
metti_barra "$BARRA_ERA"

DOPO=$(qs log --pid "$PID" 2>/dev/null | wc -l)
NUOVE=$((DOPO - PRIMA))
[ "$NUOVE" -lt 0 ] && NUOVE=0

RUMORE=$(qs log --pid "$PID" 2>/dev/null | tail -n "$NUOVE" \
         | grep -E "WARN|ERROR|error:" \
         | grep -v "Demone non raggiungibile" \
         | grep -v "host portal" \
         | grep -v "not previously tracked" \
         | grep -v "VDPAU")

if [ -n "$RUMORE" ]; then
    echo "NO: $QUANTI pannelli aperti nei due versi, e hanno detto:"
    echo "$RUMORE" | head -10
    exit 1
fi

echo "OK: $QUANTI pannelli aperti e chiusi nei due versi senza un solo avviso"
exit 0
