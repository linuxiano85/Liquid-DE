# Condiviso da bash/zsh. Solo builtin, nessun processo per marcatore.
# La chiave viene rimossa dall'ambiente prima dei file utente: i normali
# processi figli non la ereditano. Non è isolamento da codice dello stesso UID.
_minerva_percentuale() {
    local LC_ALL=C p="$1" fuori="" c h i
    if (( ${#p} > 4096 )); then
        _minerva_encoded=''
        return 0
    fi
    for ((i=0; i<${#p} && i<4096; i++)); do
        c="${p:$i:1}"
        case "$c" in
            [a-zA-Z0-9/._~-]) fuori+="$c" ;;
            *) printf -v h '%%%02X' "'$c"; fuori+="$h" ;;
        esac
    done
    _minerva_encoded="$fuori"
}
_minerva_blocco() {
    [[ -n "${_minerva_chiave-}" ]] || return 0
    local _minerva_encoded comando cartella
    _minerva_percentuale "${3-}"
    comando="$_minerva_encoded"
    _minerva_percentuale "$PWD"
    cartella="$_minerva_encoded"
    printf '\e]777;minerva;%s;%s;%s;%s;%s\a' "$_minerva_chiave" "$1" "${2:--1}" "$comando" "$cartella"
}
