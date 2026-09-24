# minerva-posti.sh — Dove Liquid DE mette le cose, e quelle di QUESTA sessione.
#
# Non si esegue: si include.
#
#     . "$(dirname "$(readlink -f "$0")")/minerva-posti.sh"
#
# Dopo, si hanno `MINERVA_SESSIONE`, `STATO` e le cartelle di Liquid DE
# (vedi `minerva-cartelle.sh`).
#
# ── PERCHÉ ESISTE ──────────────────────────────────────────────────────────
#
# Perché Minerva dava per scontato di essere l'unica sessione dell'utente, e
# il 16 agosto 2026 quella supposizione è venuta a galla tutta insieme.
# Giacomo entra dalla schermata di accesso mentre la sua sessione è già viva,
# e non compare niente. Nei registri, tre righe:
#
#     unable to lock lockfile /run/user/1000/wayland-1.lock
#     [MINERVA][DEMONE] C'è già un guardiano (20252): questo esce.
#     [MINERVA][SHELL]  C'è già un guardiano (2463): questo esce.
#
# I guardiani decidono guardando `~/.local/state/liquid-de/demone.pid`, che è
# **per utente**: la seconda sessione trova il guardiano della prima, lo crede
# suo, e si fa da parte. Sopra il commento c'era scritto «Un guardiano per
# SESSIONE» — l'intenzione era giusta da sempre, il codice non la eseguiva.
#
# E non era solo quello. La stessa supposizione stava in altri tre posti:
#
#  · la porta del canale, 11432 fissa: il secondo demone non riesce ad
#    ascoltare e muore;
#  · i registri (`session.log`, `demone.log`, `shell.log`), che la sessione
#    nuova TRONCA sotto i piedi di quella vecchia — cioè cancella la prova
#    proprio mentre si sta cercando di capire;
#  · la parola d'ordine del canale, che è una per demone.
#
# Un rimedio solo per tutti: una cartella per sessione, e dentro tutto ciò che
# è di quella sessione.
#
# ── CHE COS'È «UNA SESSIONE» ───────────────────────────────────────────────
#
# `XDG_SESSION_ID`, che è il numero che logind dà a ogni accesso e che vale
# per tutto quello che nasce dentro. Lo mette `pam_systemd`, quindi c'è sia
# passando da greetd sia da qualunque altro gestore di accessi.
#
# I ripieghi, in ordine:
#
#  · `MINERVA_SESSIONE` già impostata — la mette `start-minerva.sh` per tutti
#    i suoi figli, e la schermata di accesso la impone a mano («greeter»),
#    perché lì logind può non aver aperto una sessione vera;
#  · il numero della console (`XDG_VTNR`), che distingue comunque due
#    accessi su console diverse;
#  · «unica», per chi lancia uno script a mano fuori da una sessione: torna
#    esattamente al comportamento di prima, cioè una cartella sola.
#
# Il nome si ripulisce: finisce in un percorso, e una variabile d'ambiente la
# può riempire chiunque.
if [ -z "${MINERVA_SESSIONE:-}" ]; then
    if [ -n "${XDG_SESSION_ID:-}" ]; then
        MINERVA_SESSIONE="$XDG_SESSION_ID"
    elif [ -n "${XDG_VTNR:-}" ]; then
        MINERVA_SESSIONE="vt$XDG_VTNR"
    else
        MINERVA_SESSIONE="unica"
    fi
fi
MINERVA_SESSIONE=$(printf '%s' "$MINERVA_SESSIONE" | tr -c 'A-Za-z0-9._-' '_')
[ -n "$MINERVA_SESSIONE" ] || MINERVA_SESSIONE="unica"

# Le cartelle di Liquid DE (il nome, le basi XDG): stanno in un file a sé,
# perché servono anche a chi non è una sessione.
# `$0` è lo script che include questo file, e vive accanto a lui. Il controllo
# prima del `.`: in `sh` un `.` su un file che non c'è interrompe lo script.
_cartelle="$(dirname "$(readlink -f "$0")")/minerva-cartelle.sh"
[ -f "$_cartelle" ] || _cartelle="${MINERVA_DIR:-${ROOT:-.}}/scripts/minerva-cartelle.sh"
. "$_cartelle"

# La cartella della sessione. Sotto `sessioni/` e non sparse nella cartella di
# stato, così guardandola si vede subito quante sessioni ci sono state e non
# un mucchio di file con dei numeri appiccicati al nome.
MINERVA_STATO_BASE="$CARTELLA_STATO"
STATO="$MINERVA_STATO_BASE/sessioni/$MINERVA_SESSIONE"
mkdir -p "$STATO" 2>/dev/null || true

export MINERVA_SESSIONE
