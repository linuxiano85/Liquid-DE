#!/usr/bin/env bash
# memoria.sh — Quanto pesa DAVVERO questa sessione grafica.
#
# Nasce l'11 agosto 2026 da una domanda di Giacomo: «KDE arriva a 1,5 GB e noi
# siamo lì, è deludente». Il numero che si legge in un monitor di sistema
# comprende tutto ciò che gira sulla macchina — il browser, Docker, un
# assistente di programmazione da mezzo gigabyte — e non dice niente su quanto
# costa la scrivania. Questo script separa le tre cose e usa il PSS.
#
# PERCHÉ IL PSS E NON L'RSS. L'RSS di un processo comprende le librerie
# condivise (Qt, Mesa: un centinaio di megabyte) che stanno in memoria UNA
# volta sola ma vengono contate in OGNI processo che le usa. Sommare gli RSS
# di cinque processi Qt dà un numero che non esiste in nessuna parte del
# computer. Il PSS divide ogni pagina condivisa fra chi la usa: la somma dei
# PSS è un numero vero.
#
# ── E IL TRANELLO DEL PSS, che ho preso in pieno l'11 agosto 2026 ─────────
#
# «Dividere fra chi la usa» vuol dire che **il PSS di un processo cambia
# quando ne apri o ne chiudi un altro**, senza che quel processo abbia fatto
# niente. La shell misurata mentre girava anche un secondo Quickshell dava
# 43 MB di librerie; misurata da sola, 91 — le stesse identiche pagine.
#
# Quindi: la SOMMA dei PSS presi nello stesso istante è un numero vero, e i
# totali qui sotto si possono confrontare fra sessioni. Il PSS di una singola
# riga confrontato con quello di ieri NON si può, se nel frattempo è cambiato
# cosa gira accanto. Per «quanto costa DAVVERO questa finestra» il numero è
# la memoria PRIVATA, che non dipende da nessun altro.
#
# Si lancia identico dentro Minerva e dentro KDE, e i due numeri si possono
# confrontare:  ./scripts/memoria.sh
set -u

pss() {  # PSS in kB di un pid, 0 se non leggibile
    awk '/^Pss:/{s+=$2} END{print s+0}' "/proc/$1/smaps_rollup" 2>/dev/null || echo 0
}

# I processi che SONO la scrivania, per ciascuno dei due ambienti.
# `hypridle` e `hyprpolkitagent` sono usciti dall'elenco il 1º settembre
# 2026 insieme ai due pacchetti: l'inattività la conta il compositore e la
# finestra della password è `minerva-polkit`, che `minerva-.*` prende già.
scrivania_minerva='^(qs|dart:minervad|minerva-.*|Xwayland|xdg-desktop-por.*)$'
scrivania_kde='^(kwin_wayland|plasmashell|kded[0-9]*|kwalletd[0-9]*|ksmserver.*|kglobalaccel.*|xembedsniproxy|polkit-kde-au.*|kaccess|kactivitymanage.*|baloo_file.*|Xwayland|xdg-desktop-por.*|krunner|plasma-.*|gmenudbusmenu.*|DiscoverNotifie.*|kscreen_backend.*)$'

# ── Chi c'è: si cerca il COMPOSITORE ────────────────────────────────────
#
# Qui si cercava `Hyprland`. Il 2 settembre 2026 Hyprland è uscito da Minerva,
# e questa riga ha smesso di riconoscere la propria scrivania: la misura
# rispondeva «Ambiente: (sconosciuto)» e **zero megabyte di scrivania**, con
# tutti i processi buttati in «tutto il resto».
#
# Uno strumento di misura che dice zero è peggio di uno che non c'è: chi lo
# guarda ci crede. Ed è la ragione per cui il numero va confrontato con quello
# di agosto guardando che sia dello stesso ordine — vedi
# `minerva-confronto-kde-memoria`.
if pgrep -x minerva-wayland >/dev/null 2>&1; then
    AMBIENTE="Minerva"; FILTRO="$scrivania_minerva"
elif pgrep -x kwin_wayland >/dev/null 2>&1 || pgrep -x plasmashell >/dev/null 2>&1; then
    AMBIENTE="KDE Plasma"; FILTRO="$scrivania_kde"
else
    AMBIENTE="(sconosciuto)"; FILTRO='^$'
fi

# Le finestre di Minerva si chiamano tutte `qs`: shell, gestore file,
# impostazioni, anteprima. La shell E' la scrivania; le altre sono programmi
# aperti e vanno contate con i programmi, o la scrivania sembra il doppio.
etichetta() {  # nome leggibile di un pid, distinguendo shell e app di Minerva
    local pid=$1 c
    c=$(cat "/proc/$pid/comm" 2>/dev/null) || return 1
    if [ "$c" = qs ]; then
        local riga; riga=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
        case "$riga" in
            *shell.qml*) echo "shell di Minerva";      return 0;;
            *)           echo "app Minerva: $(basename "$(echo "$riga" | grep -oE '[^ ]+\.qml' | tail -1)" .qml)"; return 0;;
        esac
    fi
    echo "$c"
}

desktop=0; resto=0; tutto=0
declare -A dettaglio
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ -r "$p/smaps_rollup" ] || continue
    v=$(pss "$pid"); [ "$v" -gt 0 ] || continue
    c=$(cat "$p/comm" 2>/dev/null) || continue
    nome=$(etichetta "$pid") || continue
    tutto=$((tutto + v))
    if [[ "$c" =~ $FILTRO ]] && [[ "$nome" != "app Minerva:"* ]]; then
        desktop=$((desktop + v))
        dettaglio["$nome"]=$(( ${dettaglio["$nome"]:-0} + v ))
    else
        resto=$((resto + v))
    fi
done

mb() { printf "%'d MB" $(( $1 / 1024 )); }

echo "Ambiente: $AMBIENTE"
echo
echo "  LA SCRIVANIA (compositore, shell, demoni, portali)   $(mb $desktop)"
for k in "${!dettaglio[@]}"; do printf "%d|%s\n" "${dettaglio[$k]}" "$k"; done \
    | sort -rn -t'|' | while IFS='|' read v k; do printf "      %-22s %s\n" "$k" "$(mb $v)"; done
echo
echo "  TUTTO IL RESTO (programmi aperti, servizi, sviluppo) $(mb $resto)"
ps -eo comm= --sort=-rss | head -1 >/dev/null
echo "      i cinque piu grossi:"
for pid in $(ps -eo pid= --sort=-rss | head -40); do
    c=$(cat /proc/$pid/comm 2>/dev/null) || continue
    nome=$(etichetta "$pid") || continue
    [[ "$c" =~ $FILTRO ]] && [[ "$nome" != "app Minerva:"* ]] && continue
    echo "$(pss $pid)|$nome"
done | sort -rn -t'|' | head -5 | while IFS='|' read v c; do printf "      %-22s %s\n" "$c" "$(mb $v)"; done
echo
echo "  SOMMA DI TUTTI I PROCESSI                            $(mb $tutto)"
echo
awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^Shmem:/{s=$2} /^Slab:/{k=$2}
     END{printf "  Per confronto, quel che direbbe un monitor di sistema:\n"
         printf "      memoria occupata      %'"'"'d MB   (di cui %'"'"'d MB di grafica/tmpfs\n", (t-a)/1024, s/1024
         printf "                                          e %'"'"'d MB del kernel: non sono di nessun programma)\n", k/1024}' /proc/meminfo
