# integrazione.bash — I marcatori dei blocchi (OSC 133) e la cartella (OSC 7)
# per bash. Il Terminale avvia `bash --rcfile QUESTO_FILE`: si legge prima
# il `.bashrc` vero dell'utente, poi si mettono i ganci.
#
# I quattro marcatori sono gli stessi di `zsh/integrazione.zsh`; bash non ha
# `preexec`, e si usa la trappola DEBUG come fa bash-preexec.

_minerva_chiave="${MINERVA_BLOCCHI_CHIAVE-}"
export -n _minerva_chiave
unset MINERVA_BLOCCHI_CHIAVE
source "${BASH_SOURCE[0]%/bash/integrazione.bash}/blocchi.sh"

# Con `--rcfile` bash non legge né quello di sistema né quello di casa:
# si leggono qui, nello stesso ordine in cui li leggerebbe lui.
if [[ -r /etc/bash.bashrc ]]; then
    source /etc/bash.bashrc
fi
if [[ -r "$HOME/.bashrc" ]]; then
    source "$HOME/.bashrc"
fi

_minerva_dentro_comando=0
# «on» solo dal momento in cui il prompt è pronto al momento in cui parte il
# primo comando dell'utente: la trappola DEBUG scatta anche per ogni pezzo
# di PROMPT_COMMAND (il .bashrc di CachyOS ne mette dei suoi), e senza
# questo interruttore il marcatore C usciva PRIMA del prompt. È il metodo
# di bash-preexec.
_minerva_modo=off

_minerva_osc7() {
    local p="$PWD" fuori="" c i
    for (( i = 0; i < ${#p}; i++ )); do
        c="${p:i:1}"
        case "$c" in
            [A-Za-z0-9/._~-]) fuori+="$c" ;;
            *) fuori+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '\e]7;file://%s%s\a' "${HOSTNAME:-localhost}" "$fuori"
}

_minerva_precmd() {
    local codice=$?
    _minerva_modo=off
    if (( _minerva_dentro_comando )); then
        _minerva_blocco D "$codice"
        printf '\e]133;D;%d\a' "$codice"
        _minerva_dentro_comando=0
    fi
    printf '\e]133;A\a'
    _minerva_blocco A
    _minerva_osc7
    if [[ "$PS1" != *$'\e]133;B\a'* ]]; then
        PS1+=$'\[\e]133;B\a\]'
    fi
}

# L'ultimo pezzo di PROMPT_COMMAND: da qui il prossimo DEBUG è il comando.
_minerva_pronto() {
    _minerva_modo=on
}

_minerva_preexec() {
    [[ -n "$COMP_LINE" ]] && return
    [[ "$_minerva_modo" == on ]] || return
    _minerva_modo=off
    _minerva_blocco C -1 "$BASH_COMMAND"
    printf '\e]133;C\a'
    _minerva_dentro_comando=1
}

# Non sovrascrivere trappole DEBUG esistenti: in quel caso fallback classico.
if [[ -z "$(trap -p DEBUG)" ]]; then
    PROMPT_COMMAND=(_minerva_precmd "${PROMPT_COMMAND[@]}" _minerva_pronto)
    trap '_minerva_preexec' DEBUG
fi
