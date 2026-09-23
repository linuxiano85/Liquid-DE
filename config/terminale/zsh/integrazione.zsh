# integrazione.zsh — I marcatori dei blocchi (OSC 133) e la cartella (OSC 7)
# per zsh. Caricato da `.zshenv` al primo prompt, dopo `.zshrc`.
#
# I quattro marcatori, come li manda fish da solo e come li leggono kitty,
# WezTerm, foot e il nostro emulatore:
#
#     A   comincia il prompt          (precmd, prima di stamparlo)
#     B   comincia il comando         (in fondo al prompt: da qui si scrive)
#     C   comincia l'uscita           (preexec, il comando parte)
#     D;n il comando è finito con n   (precmd, prima di A)
#
# Con questi il Terminale sa dove finisce un comando e dove comincia
# l'altro senza indovinarlo dallo schermo, e può dire «questo blocco è
# finito male», offrirne la copia, e tenere la storia con l'esito.

typeset -g _minerva_dentro_comando=0
builtin source "$MINERVA_TERMINALE_INTEGRAZIONE/blocchi.sh"

_minerva_osc7() {
    # `file://host/percorso`, con i caratteri che in un URL non si possono
    # scrivere protetti in percentuale. Lo legge il Terminale per aprire la
    # scheda successiva nella stessa cartella.
    local p="$PWD" fuori="" c
    local i
    for (( i = 1; i <= ${#p}; i++ )); do
        c="${p[i]}"
        case "$c" in
            [A-Za-z0-9/._~-]) fuori+="$c" ;;
            *) fuori+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '\e]7;file://%s%s\a' "${HOST:-localhost}" "$fuori"
}

_minerva_precmd() {
    local codice=$?
    if (( _minerva_dentro_comando )); then
        _minerva_blocco D "$codice"
        printf '\e]133;D;%d\a' "$codice"
        _minerva_dentro_comando=0
    fi
    printf '\e]133;A\a'
    _minerva_blocco A
    _minerva_osc7
}

# Il marcatore B — «da qui comincia il comando» — NON sta in PS1: p10k si
# rimette in coda ai precmd a ogni giro e riscrive il prompt dopo tutti gli
# altri, e un marcatore appeso a PS1 spariva (visto il 15 settembre 2026).
# Sta in `zle-line-init`, che zsh chiama quando l'editor di riga comincia a
# leggere: cioè esattamente in fondo al prompt, qualunque cosa ci sia
# scritto. Il widget di prima, se c'era, si chiama dopo.
_minerva_zle_line_init() {
    printf '\e]133;B\a'
    if (( $+widgets[_minerva_zle_line_init_prima] )); then
        zle _minerva_zle_line_init_prima -- "$@"
    fi
}

_minerva_preexec() {
    _minerva_blocco C -1 "$1"
    printf '\e]133;C\a'
    _minerva_dentro_comando=1
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _minerva_precmd
add-zsh-hook preexec _minerva_preexec
if (( $+widgets[zle-line-init] )); then
    zle -A zle-line-init _minerva_zle_line_init_prima
fi
zle -N zle-line-init _minerva_zle_line_init
