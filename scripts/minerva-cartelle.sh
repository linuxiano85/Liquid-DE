# minerva-cartelle.sh — Le cartelle di Liquid DE. Non si esegue: si include.
#
#     . "$(dirname "$(readlink -f "$0")")/minerva-cartelle.sh"
#
# Definisce `LIQUID_NOME`, `CARTELLA_CONFIG`, `CARTELLA_DATI`,
# `CARTELLA_CACHE`, `CARTELLA_RUNTIME`, `CARTELLA_STATO`,
# `CARTELLA_CONFIG_DI_PARTENZA`, `PREFISSO` e `CARTELLA_BIN`, e non fa nient'altro:
# non esporta, non crea cartelle. È la parte di `minerva-posti.sh` che serve
# anche a chi non è una sessione (le prove, i controlli).
#
# ── IL NOME DELLE CARTELLE ─────────────────────────────────────────────────
#
# Lo stesso di `minervad/lib/core/minerva_paths.dart` e di `core/Ipc.qml`, in
# ogni base XDG. Liquid DE e Minerva convivono sullo stesso computer solo se
# non scrivono mai nella stessa cartella: con una cartella di stato comune, il
# guardiano di una scrivania si farebbe da parte davanti a quello dell'altra,
# esattamente come le due sessioni del 16 agosto.
LIQUID_NOME=liquid-de

_base_xdg() {  # variabile, posto di serie sotto la casa
    eval "_v=\${$1:-}"
    case "$_v" in /*) printf '%s' "${_v%/}" ;; *) printf '%s/%s' "$HOME" "$2" ;; esac
}
if [ -n "${MINERVA_CONFIG_DIR:-}" ]; then
    CARTELLA_CONFIG="${MINERVA_CONFIG_DIR%/}"
else
    CARTELLA_CONFIG="$(_base_xdg XDG_CONFIG_HOME .config)/$LIQUID_NOME"
fi
CARTELLA_DATI="$(_base_xdg XDG_DATA_HOME .local/share)/$LIQUID_NOME"
CARTELLA_CACHE="$(_base_xdg XDG_CACHE_HOME .cache)/$LIQUID_NOME"
case "${XDG_RUNTIME_DIR:-}" in
    /*) CARTELLA_RUNTIME="${XDG_RUNTIME_DIR%/}/$LIQUID_NOME" ;;
    *)  CARTELLA_RUNTIME="/tmp/$LIQUID_NOME-${USER:-utente}" ;;
esac
CARTELLA_STATO="$(_base_xdg XDG_STATE_HOME .local/state)/$LIQUID_NOME"

# Le impostazioni VERE da cui parte una prova: quelle di Liquid DE, o quelle di
# Minerva finché Liquid DE non ha ancora le sue. Si leggono e basta: una prova
# non scrive mai qui. (`MINERVA_CONFIG_DIR` non conta: è la cartella della
# prova, non quella da cui copiare.)
CARTELLA_CONFIG_DI_PARTENZA="$(_base_xdg XDG_CONFIG_HOME .config)/$LIQUID_NOME"
[ -f "$CARTELLA_CONFIG_DI_PARTENZA/settings.json" ] \
    || CARTELLA_CONFIG_DI_PARTENZA="$(_base_xdg XDG_CONFIG_HOME .config)/minerva"

# Dove si installano i programmi di Liquid DE: un prefisso suo, perché
# `~/.local/bin` è di Minerva. Lì dentro `bin/` e `share/` (applicazioni e
# icone). La sessione mette `bin/` in testa al PATH e `share/` in
# XDG_DATA_DIRS. `MINERVA_BIN` resta per le prove, che possono indicare una
# build da provare senza installarla.
PREFISSO="${LIQUID_PREFISSO:-$HOME/.local/opt/$LIQUID_NOME}"
CARTELLA_BIN="${MINERVA_BIN:-$PREFISSO/bin}"

# ── La radice installata ───────────────────────────────────────────────────
#
# Dove Liquid DE gira davvero: una COPIA della parte dei sorgenti che serve
# a runtime (script, shell, risorse, configurazioni, il demone compilato),
# fatta da `minerva-installa-radice`. Fino al 4 ottobre 2026 la sessione
# girava dalla cartella dei sorgenti stessa: spostata quella cartella da
# Scaricati a Documenti, nessuna app di Minerva si apriva più — nemmeno le
# Impostazioni — e al riavvio non sarebbe partita nemmeno la sessione. I
# sorgenti adesso sono solo il posto da cui si costruisce.
CARTELLA_RADICE="${LIQUID_RADICE:-$PREFISSO/radice}"
