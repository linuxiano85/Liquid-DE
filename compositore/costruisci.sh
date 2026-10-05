#!/bin/sh
# Compila il fork privato; installa per rinomina solo dopo build e test riusciti.
set -eu
QUI="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD="${MINERVA_BUILD_DIR:-$QUI/build-native}"
. "$QUI/../scripts/minerva-cartelle.sh"
DOVE="$CARTELLA_BIN"
# Solo gles2 di serie: gli effetti (blur, angoli, anello) esistono solo lì,
# e aggiungere vulkan vuol dire ricompilare wlroots per un renderer che li
# perde in silenzio. Chi vuole provarlo lo chiede: MINERVA_RENDERERS=gles2,vulkan.
RENDERERS="${MINERVA_RENDERERS:-gles2}"
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
#
# ── Compilato per QUESTO processore ───────────────────────────────────────
#
# Fino al 29 settembre 2026 il compositore — fork di wlroots compreso — era
# compilato in DEBUG, cioè senza nessuna ottimizzazione (-O0): l'unico pezzo
# del sistema non ottimizzato, mentre Qt e il resto arrivano già dai
# repository cachyos-v4. Misurato trascinando una finestra (600 spostamenti,
# acquerello acceso): 1,45 → 1,38 ms di CPU per fotogramma, binario 3,75 →
# 1,6 MB. Poco, perché il profilo è piatto — metà del tempo è Mesa, un
# quinto pixman — ma gratis.
#
# `debugoptimized` e non `release`: tiene accesi gli assert di wlroots, che
# fermano un difetto dove nasce invece di lasciarlo correre (quello della
# barra del titolo nativa era uno di questi). LTO e `-march=native`: il
# compositore si compila sulla macchina dove girerà (install-minerva.sh).
# Per un binario da portare altrove: MINERVA_MARCH=x86-64-v3.
MARCH="${MINERVA_MARCH:-native}"
OTTIMIZZA="-Dbuildtype=debugoptimized -Db_lto=true -Dc_args=-march=$MARCH -Dc_link_args=-march=$MARCH"
# ── Una build fatta da un'altra cartella ─────────────────────────────────
#
# meson scrive nella build il percorso ASSOLUTO dei sorgenti. Spostato il
# progetto (il 4 ottobre 2026, da Scaricati a Documenti), `--reconfigure`
# moriva con un «Unhandled python OSError» su un file temporaneo nella
# cartella vecchia, e non diceva perché. Una build è tutta rigenerabile: se
# non è di QUESTI sorgenti si rifà da capo. Si cancella solo se è davvero
# una build di meson (`coredata.dat`), qualunque cosa dica MINERVA_BUILD_DIR.
if [ -f "$BUILD/meson-private/coredata.dat" ] && [ -f "$BUILD/build.ninja" ] \
   && ! grep -qF "$QUI/" "$BUILD/build.ninja"; then
    echo "La build in $BUILD era di un'altra cartella dei sorgenti: la rifaccio da capo."
    rm -rf -- "$BUILD"
fi
if [ -f "$BUILD/meson-private/coredata.dat" ]; then
    # shellcheck disable=SC2086
    meson setup --reconfigure "$BUILD" "$QUI" --wrap-mode=nofallback $OTTIMIZZA \
        -Dwlroots:renderers="$RENDERERS" -Dwlroots:backends=drm,libinput,x11 \
        -Dwlroots:session=enabled -Dwlroots:xwayland=enabled
else
    # shellcheck disable=SC2086
    meson setup "$BUILD" "$QUI" --wrap-mode=nofallback $OTTIMIZZA \
        -Dwlroots:renderers="$RENDERERS" -Dwlroots:backends=drm,libinput,x11 \
        -Dwlroots:session=enabled -Dwlroots:xwayland=enabled
fi
# Il riepilogo qui sopra scrive «vulkan-renderer : NO» in rosso, e sembra un
# guasto: il 29 settembre 2026 su un computer nuovo è stato letto come «manca
# vulkan-renderer». È voluto, e va detto subito sotto.
case ",$RENDERERS," in
    *,vulkan,*) ;;
    *) echo "Nota: «vulkan-renderer : NO» è voluto, non manca niente: gli effetti" \
            "esistono solo con gles2 (per provarlo: MINERVA_RENDERERS=gles2,vulkan)." ;;
esac
meson compile -C "$BUILD"
meson test -C "$BUILD" --print-errorlogs

for nome in minerva-wayland minerva-cattura minerva-pty minerva-pam; do
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
for nome in minerva-wayland minerva-cattura minerva-pty minerva-pam; do
    install -m755 "$BUILD/$nome" "$STAGING/$nome"
done
for nome in minerva-wayland minerva-cattura minerva-pty minerva-pam; do
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
