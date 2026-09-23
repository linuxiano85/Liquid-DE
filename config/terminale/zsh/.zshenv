# .zshenv — Il primo file che zsh legge, messo qui da Minerva · Terminale.
#
# Il Terminale avvia zsh con `ZDOTDIR` puntato a questa cartella, così zsh
# legge QUESTO .zshenv per primo. Questo file fa tre cose, e poi sparisce:
#
#   1. rimette `ZDOTDIR` com'era, così `.zprofile`, `.zshrc` e `.zlogin`
#      si leggono dal posto vero (zsh guarda `$ZDOTDIR` a ogni file, non
#      una volta sola all'avvio);
#   2. legge lo `.zshenv` dell'utente, se c'è, perché non vada perso;
#   3. rimanda l'integrazione al PRIMO prompt, quando `.zshrc` ha già
#      finito: così i nostri ganci si mettono in coda DOPO quelli di
#      starship o di powerlevel10k, che riscrivono il prompt a ogni giro.
#
# È lo stesso metodo di kitty e di WezTerm, che è quello che funziona con
# le configurazioni che la gente ha davvero.
typeset -g _minerva_chiave="${MINERVA_BLOCCHI_CHIAVE-}"
typeset +x _minerva_chiave
unset MINERVA_BLOCCHI_CHIAVE
if [[ -n "${MINERVA_ZDOTDIR_ORIG-}" ]]; then
    export ZDOTDIR="$MINERVA_ZDOTDIR_ORIG"
else
    unset ZDOTDIR
fi
unset MINERVA_ZDOTDIR_ORIG

if [[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
    builtin source "${ZDOTDIR:-$HOME}/.zshenv"
fi

if [[ -o interactive && -n "${MINERVA_TERMINALE_INTEGRAZIONE-}" ]]; then
    _minerva_integra_al_primo_prompt() {
        # Una volta sola: si toglie, e mette i ganci veri.
        precmd_functions=(${precmd_functions:#_minerva_integra_al_primo_prompt})
        builtin source "$MINERVA_TERMINALE_INTEGRAZIONE/zsh/integrazione.zsh"
        _minerva_precmd
    }
    typeset -ga precmd_functions
    precmd_functions+=(_minerva_integra_al_primo_prompt)
fi
