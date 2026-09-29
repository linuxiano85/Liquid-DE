#!/bin/bash
# minerva-reload.sh — Rimette in sesto la shell senza uscire dalla sessione.
#
#   minerva-reload.sh            ricarica la shell grafica
#   minerva-reload.sh tutto      ricarica la shell e riavvia il demone
#   minerva-reload.sh ambiente   dice con che ambiente ripartirebbero, e basta
#
# Il modo `hypr` — «ricarica la configurazione di Hyprland» — se n'è andato col
# distacco del 2 settembre 2026. Non era pericoloso, era peggio: rispondeva
# «hyprctl reload fallito» in rosso a chi non aveva sbagliato niente.
#
# Serve quando si modifica qualcosa e non si vuole chiudere e riaprire la
# sessione. Quickshell rilegge i file QML da solo a ogni salvataggio: questo
# script serve per i casi in cui NON basta — un errore che ha fermato la
# shell, un file nuovo, o una modifica al demone e alle scorciatoie.

SELF="$(readlink -f "$0")"
MINERVA_DIR="$(dirname "$(dirname "$SELF")")"
# I registri sono di questa sessione: vedi `scripts/minerva-posti.sh`.
. "$MINERVA_DIR/scripts/minerva-posti.sh"
SHELL_QML="$MINERVA_DIR/minerva-shell/shell.qml"
MODE="${1:-shell}"

say() { printf '\033[36m·\033[0m %s\n' "$1"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '\033[31m✗\033[0m %s\n' "$1"; }

# ── Le prove non si toccano ────────────────────────────────────────────────
#
# Una sessione di prova ha la stessa riga di comando di quella vera: la
# differenza sta solo nel suo ambiente (vedi la regola «mai pkill»).
di_prova() { tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | grep -qx 'MINERVA_PROVA=1'; }

# ── L'ambiente della SESSIONE, non quello di chi lancia ────────────────────
#
# Questo script si lancia da un terminale, e demone e shell ripartivano con
# l'ambiente del terminale. Il 29 settembre 2026 il suo PATH aveva davanti
# ~/.local/bin, dove `minerva-files` porta ancora a Minerva Shell: il demone
# riavviato apriva il gestore file dell'ALTRO progetto, che cercava un altro
# demone e restava vuoto. La sessione mette davanti la cartella di Liquid.
#
# Il modello è il compositore della sessione: lo lancia sempre il lanciatore
# della sessione, ed è il padre di tutto. A lui mancano solo le variabili
# che dà ai suoi figli — lo schermo, X, il suo canale — e si prendono da qui.
compositore_della_sessione() {
    for c in $(pgrep -x minerva-wayland); do
        di_prova "$c" && continue
        # Da un terminale che non sa la sua sessione: il primo vero.
        [ -z "${MINERVA_SESSIONE:-}" ] && { echo "$c"; return; }
        tr '\0' '\n' < "/proc/$c/environ" 2>/dev/null \
            | grep -qx "MINERVA_SESSIONE=${MINERVA_SESSIONE:-}" && { echo "$c"; return; }
    done
}
AMBIENTE=()
MODELLO=$(compositore_della_sessione)
if [ -n "$MODELLO" ]; then
    mapfile -d '' AMBIENTE < "/proc/$MODELLO/environ"
    for v in WAYLAND_DISPLAY DISPLAY MINERVA_CANALE WLR_RENDERER; do
        [ -n "${!v:-}" ] && AMBIENTE+=("$v=${!v}")
    done
fi
come_la_sessione() {
    if [ ${#AMBIENTE[@]} -gt 0 ]; then
        env -i "${AMBIENTE[@]}" "$@"
    else
        "$@"
    fi
}

if [ "$MODE" = "ambiente" ]; then
    [ -n "$MODELLO" ] && ok "ambiente dal compositore $MODELLO" \
                      || bad "nessun compositore della sessione ${MINERVA_SESSIONE:-?}: resta quello di qui"
    come_la_sessione sh -c 'echo "gestore file: $(command -v minerva-files)"'
    exit 0
fi

# ── Shell grafica ──────────────────────────────────────────────────────────
#
# Si sceglie l'istanza per PID e non con `qs ipc -p <percorso>`. Non è
# pedanteria: quickshell lascia in giro le schede delle istanze morte, e
# selezionando per percorso il comando finisce quasi sempre su una di quelle,
# rispondendo «Target not found» mentre la shell vera è lì che funziona.
# Si escludono i processi zombie: `pgrep -x qs` li conta come vivi, e chiamare
# l'IPC sul PID di un cadavere risponde «No instance found» facendo credere
# che la shell sia rotta quando invece sta funzionando benissimo.
#
# E si cerca `shell.qml`, non un `qs` qualunque: da quando il gestore file è un
# processo suo ci sono DUE quickshell in esecuzione, e ricaricare (o peggio,
# uccidere) quello sbagliato chiuderebbe la finestra di chi sta copiando file.
LIVE_PID=""
for p in $(ps -eo pid,stat,cmd --no-headers \
           | awk '$2 !~ /Z/ && /[q]s -p/ && /shell\.qml/ {print $1}'); do
    di_prova "$p" || { LIVE_PID=$p; break; }
done

# Prima si prova per le buone, con l'IPC: la shell si ricarica restando viva e
# barra e pannelli non spariscono mai. Solo se non risponde — perché è in
# errore o non è mai partita — la si riavvia da capo.
say "Ricarico la shell"

# L'esito del comando non dice nulla: ricaricandosi la shell chiude la
# connessione IPC prima di poter rispondere, quindi `qs ipc` riporta un errore
# anche quando ha funzionato. Ciò che conta è che il processo sia ancora vivo
# subito dopo — se il ricaricamento fosse fallito sarebbe morto.
if [ -n "$LIVE_PID" ]; then
    qs ipc --pid "$LIVE_PID" call minerva reload >/dev/null 2>&1
    sleep 2
fi

if [ -n "$LIVE_PID" ] && kill -0 "$LIVE_PID" 2>/dev/null; then
    ok "shell ricaricata (senza riavviarla)"
    # «Ricaricata» non vuol dire «senza errori»: davanti a un QML rotto
    # quickshell tiene la versione precedente e resta vivo. Chi guarda solo il
    # processo conclude che è andato tutto bene e continua a provare una
    # modifica che non è mai entrata in funzione.
    #
    # ── E due rumori che NON sono errori ──────────────────────────────────
    #
    # Questo controllo diceva «il registro riporta errori» a ogni ricarica
    # riuscita, per due righe che una ricarica produce sempre:
    #
    #  · «Failed to register with host portal … Connection already associated
    #    with an application ID» — la scrive Qt perché il processo si registra
    #    al portale una volta sola e alla seconda ricarica ci riprova. Non
    #    dipende dal nostro codice e non si può togliere dal nostro codice.
    #  · «Connessione persa, riprovo» — la scrive la shell quando il demone si
    #    riavvia, ed è seguita da «Connesso al demone». È il meccanismo che
    #    funziona, non il meccanismo che si rompe.
    #
    # Un controllo che grida al lupo a ogni ricarica smette di essere letto, e
    # allora il giorno che l'errore c'è davvero nessuno lo vede. Le due righe
    # si escludono per nome, e solo quelle.
    SHELL_LOG="$STATO/shell.log"
    if [ -f "$SHELL_LOG" ] \
       && tail -40 "$SHELL_LOG" \
          | grep -viE 'host portal|Connessione persa, riprovo' \
          | grep -qiE 'error|warning:.*qml|cannot assign'; then
        bad "ma il registro riporta errori — guarda $SHELL_LOG"
        tail -12 "$SHELL_LOG" | sed 's/^/    /'
    fi
else
    say "non risponde, la riavvio"
    for p in $(ps -eo pid,stat,cmd --no-headers | awk '$2 !~ /Z/ && /[q]s -p/ && /shell\.qml/ {print $1}'); do
        di_prova "$p" || kill "$p" 2>/dev/null
    done
    sleep 1
    LOG="$STATO/shell.log"
    come_la_sessione nohup qs -p "$SHELL_QML" >>"$LOG" 2>&1 &
    sleep 3
    if ps -eo pid,stat,cmd --no-headers | awk '$2 !~ /Z/ && /[q]s -p/ && /shell\.qml/' | grep -q .; then
        ok "shell riavviata"
    else
        bad "shell non partita — guarda $STATO/session.log"
    fi
fi

# ── Demone ─────────────────────────────────────────────────────────────────
#
# Il demone legge keybinds.conf UNA VOLTA all'avvio: dopo aver aggiunto o
# cambiato una scorciatoia va riavviato, altrimenti il pannello F1 continua a
# mostrare quelle vecchie.
if [ "$MODE" = "tutto" ]; then
    say "Riavvio il demone"
    # Si ferma il GUARDIANO, non il demone: il guardiano esiste per rimettere
    # in piedi un demone caduto, e ucciderlo da sotto vuol dire vederselo
    # tornare mentre se ne avvia un altro — due demoni per lo stesso socket.
    # Fermando il guardiano scende anche il figlio (`trap` in minerva-demone).
    for p in $(ps -eo pid,cmd | awk '/minerva-demone/ && !/awk/ {print $1}'); do
        di_prova "$p" || kill "$p" 2>/dev/null
    done
    # E poi ciò che fosse rimasto orfano, in tutte e due le forme che il
    # demone può avere: interpretato (`dart:minervad…`) e compilato
    # (`minervad`).
    for p in $(ps -eo pid,comm --no-headers \
               | awk '$2 ~ /^dart:minervad/ || $2 == "minervad" {print $1}'); do
        di_prova "$p" || kill "$p" 2>/dev/null
    done
    sleep 2

    # Se i sorgenti sono più recenti del compilato, si ricompila: altrimenti
    # il guardiano ripiega su `dart run` e il riavvio costa un secondo e mezzo
    # e duecento megabyte in più, senza che si capisca perché.
    ESE="$MINERVA_DIR/minervad/build/minervad"
    if [ -x "$ESE" ] && [ -n "$(find "$MINERVA_DIR/minervad/lib" \
            "$MINERVA_DIR/minervad/bin" -name '*.dart' -newer "$ESE" -print -quit 2>/dev/null)" ]; then
        say "sorgenti cambiati: ricompilo il demone"
        "$MINERVA_DIR/scripts/minerva-compila" >/dev/null 2>&1 \
            && ok "demone ricompilato" || bad "compilazione fallita: si userà dart run"
    fi
    # Si riparte dal guardiano e non dal demone: avviando il demone nudo si
    # resta senza guardiano per il resto della sessione, cioè senza la rete
    # che esiste apposta. È anche il guardiano a scegliere fra il compilato e
    # `dart run` (vedi `scripts/minerva-demone`).
    come_la_sessione nohup "$MINERVA_DIR/scripts/minerva-demone" >/dev/null 2>&1 &
    say "compilazione in corso, ~10 secondi"
    # Il socket lo scrive il demone stesso nel file del canale, e ci scrive
    # DOPO averlo preso: se la riga c'e', dall'altra parte c'e' qualcuno.
    # Cercare un percorso fisso vorrebbe dire indovinare la sessione.
    CANALE="$CARTELLA_RUNTIME/sessioni/${MINERVA_SESSIONE:-unica}/canale"
    SOCKET=""
    for _ in $(seq 1 20); do
        sleep 1
        SOCKET=$(sed -n 's/^socket=//p' "$CANALE" 2>/dev/null | head -1)
        if [ -n "$SOCKET" ] && [ -S "$SOCKET" ]; then
            ok "demone in ascolto su $SOCKET"
            break
        fi
    done
    [ -n "$SOCKET" ] && [ -S "$SOCKET" ] \
        || bad "il demone non ha aperto nessun socket (cercato in $CANALE)"
fi
