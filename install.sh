#!/usr/bin/env bash
# Punto d'ingresso grafico. Il piccolo bootstrap serve solo prima che esista qs.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/liquid-de/installer"
mkdir -p "$STATE"
chmod 700 "$STATE"
umask 077
LOG="$STATE/launch-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee -a "$LOG") 2>&1
printf '[%s] Avvio installer da %s\n' "$(date '+%F %T')" "$ROOT"
printf 'Registro di avvio: %s\n' "$LOG"
if (( EUID == 0 )); then
    echo 'Avvia l’installer come utente normale: chiederà i privilegi quando servono.' >&2
    exit 1
fi
if [[ -z ${WAYLAND_DISPLAY:-} && -z ${DISPLAY:-} ]]; then
    printf 'Serve una sessione grafica. Dal terminale puoi usare: %s/scripts/install-minerva.sh\n' "$ROOT" >&2
    exit 1
fi
command -v pacman >/dev/null || { echo 'Questa versione richiede Arch Linux o una derivata con pacman.' >&2; exit 1; }

BOOTSTRAP=(quickshell qt6-base qt6-declarative qt6-wayland qt6-svg zenity)
ESITO=0
MANCANTI=$(pacman -T "${BOOTSTRAP[@]}" 2>/dev/null) || ESITO=$?
if [[ ${ESITO:-0} != 0 && ${ESITO:-0} != 127 ]]; then
    echo 'Non riesco a controllare i componenti grafici.' >&2
    exit 1
fi
if [[ -n $MANCANTI ]]; then
    readarray -t PACCHETTI <<< "$MANCANTI"
    printf 'Preparo la finestra grafica: %s\n' "${PACCHETTI[*]}"
    if command -v pkexec >/dev/null; then
        if ! pkexec /usr/bin/pacman -S --needed --noconfirm -- "${PACCHETTI[@]}"; then
            echo 'Preparazione grafica non riuscita. Da terminale puoi installare i pacchetti indicati e rilanciare ./install.sh.' >&2
            exit 1
        fi
    elif [[ -t 0 ]]; then
        sudo pacman -S --needed --noconfirm -- "${PACCHETTI[@]}"
    else
        echo 'Autorizzazione non riuscita. Apri un terminale e rilancia ./install.sh.' >&2
        exit 1
    fi
fi

command -v qs >/dev/null || { echo 'Quickshell non è disponibile dopo il bootstrap.' >&2; exit 1; }
export MINERVA_INSTALL_ROOT="$ROOT"
printf '[%s] Avvio finestra Quickshell\n' "$(date '+%F %T')"
if qs -p "$ROOT/minerva-shell/installer.qml"; then
    ESITO=0
else
    ESITO=$?
fi
printf '[%s] Quickshell terminato con codice %s\n' "$(date '+%F %T')" "$ESITO"
exit "$ESITO"
