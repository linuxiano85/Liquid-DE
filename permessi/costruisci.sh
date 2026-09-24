#!/bin/sh
# costruisci.sh — Compila minerva-polkit e lo installa senza fare danni.
#
# Stessa forma di `compositore/costruisci.sh`, e per la stessa ragione:
# si scrive di fianco e si RINOMINA. `cp` apre il file, lo TRONCA e lo riempie:
# se in quel momento l'agente sta girando, le sue pagine di codice diventano
# spazzatura mentre le esegue — e quel che si perde è la finestra della
# password, cioè il modo di montare un disco o cambiare l'ora.
#
# Qui il rischio è più piccolo che col compositore (cade una finestrella, non
# lo schermo), ma la regola non cambia per la dimensione del danno.
set -eu

QUI="$(cd "$(dirname "$0")" && pwd)"
. "$QUI/../scripts/minerva-cartelle.sh"
DOVE="$CARTELLA_BIN"

if ! pkg-config --exists polkit-agent-1; then
    echo "FERMO: mancano gli header di polkit." >&2
    echo "" >&2
    echo "Installali con:   sudo pacman -S polkit" >&2
    echo "" >&2
    echo "polkit c'è già su questa macchina — lo vuole systemd — ma su Arch" >&2
    echo "gli header stanno nello stesso pacchetto, quindi se manca qualcosa" >&2
    echo "manca il pacchetto intero." >&2
    exit 1
fi

[ -d "$QUI/build" ] || meson setup "$QUI/build" "$QUI"
ninja -C "$QUI/build"

BIN="$QUI/build/minerva-polkit"

MANCANTI=$(ldd "$BIN" 2>/dev/null | grep "not found" || true)
if [ -n "$MANCANTI" ]; then
    echo "" >&2
    echo "FERMO: mancano delle librerie a $BIN" >&2
    echo "$MANCANTI" >&2
    exit 1
fi

mkdir -p "$DOVE"
cp "$BIN" "$DOVE/.minerva-polkit.nuovo"
mv "$DOVE/.minerva-polkit.nuovo" "$DOVE/minerva-polkit"
echo "fatto: $DOVE/minerva-polkit"

# Se ne sta girando uno, il codice nuovo entra al prossimo accesso: si dice
# adesso, non fra mezz'ora.
if pgrep -x minerva-polkit >/dev/null 2>&1; then
    echo ""
    echo "NOTA: minerva-polkit sta già girando. Il binario è stato sostituito"
    echo "per rinomina, quindi quel processo continua col codice di prima:"
    echo "il nuovo entra al PROSSIMO ACCESSO."
fi
