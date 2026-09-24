#!/bin/sh
# Compila il fork privato; installa per rinomina solo dopo build e test riusciti.
set -eu
QUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD="${MINERVA_BUILD_DIR:-$QUI/build-native}"
. "$QUI/../scripts/minerva-cartelle.sh"
DOVE="$CARTELLA_BIN"
RENDERERS="${MINERVA_RENDERERS:-gles2,vulkan}"
INSTALLA=1
case "${1:-}" in
    --build-only) INSTALLA=0 ;;
    "") ;;
    *) echo "Uso: $0 [--build-only]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || exit 2
[ -f "$QUI/subprojects/wlroots/MINERVA.md" ] || {
    echo "Mancano i sorgenti del fork wlroots di Minerva." >&2; exit 1;
}
for cmd in meson ninja pkg-config cc ldd; do
    command -v "$cmd" >/dev/null || { echo "Manca $cmd" >&2; exit 1; }
done

# Richiedere i backend evita una build che riesce ma non gestisce DRM/input.
# Un profilo GLES soltanto deve essere scelto esplicitamente.
if [ -f "$BUILD/meson-private/coredata.dat" ]; then
    meson setup --reconfigure "$BUILD" "$QUI" --wrap-mode=nofallback \
        -Dwlroots:renderers="$RENDERERS" -Dwlroots:backends=drm,libinput,x11 \
        -Dwlroots:session=enabled -Dwlroots:xwayland=enabled
else
    meson setup "$BUILD" "$QUI" --wrap-mode=nofallback \
        -Dwlroots:renderers="$RENDERERS" -Dwlroots:backends=drm,libinput,x11 \
        -Dwlroots:session=enabled -Dwlroots:xwayland=enabled
fi
meson compile -C "$BUILD"
meson test -C "$BUILD" --print-errorlogs

for nome in minerva-wayland minerva-cattura minerva-pty; do
    [ -x "$BUILD/$nome" ] || { echo "Manca $nome nella build" >&2; exit 1; }
    LIBRERIE=$(ldd "$BUILD/$nome")
    if printf '%s\n' "$LIBRERIE" | grep -Eq 'not found|lib(wlroots|scenefx)'; then
        printf 'Dipendenze mancanti o libreria esterna vietata in %s:\n%s\n' "$nome" "$LIBRERIE" >&2
        exit 1
    fi
done
[ "$INSTALLA" -eq 1 ] || exit 0

SESSIONE_VIVA=""
for pid in $(pgrep -x minerva-wayland 2>/dev/null || true); do
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qx 'MINERVA_PROVA=1'; then
        echo "Prova annidata attiva ($pid): build verificata, installazione sospesa." >&2
        exit 1
    fi
    SESSIONE_VIVA="$pid"
done
mkdir -p "$DOVE"
STAGING=$(mktemp -d "$DOVE/.minerva-install.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT HUP INT TERM
for nome in minerva-wayland minerva-cattura minerva-pty; do
    install -m755 "$BUILD/$nome" "$STAGING/$nome"
done
for nome in minerva-wayland minerva-cattura minerva-pty; do
    if [ -f "$DOVE/$nome" ]; then
        cp "$DOVE/$nome" "$STAGING/$nome.precedente"
        mv -f "$STAGING/$nome.precedente" "$DOVE/$nome.precedente"
    fi
    mv -f "$STAGING/$nome" "$DOVE/$nome"
    echo "Installato: $DOVE/$nome"
done
if [ -n "$SESSIONE_VIVA" ]; then
    echo "La sessione attuale mantiene il vecchio binario; il nuovo sarà usato al prossimo accesso."
fi
