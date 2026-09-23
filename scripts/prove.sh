#!/bin/bash
# prove.sh — Tutte le prove automatiche di Minerva, in un comando.
#
#     scripts/prove.sh          tutto quello che si può provare
#     scripts/prove.sh veloce   salta le prove che aprono finestre
#
# Era il terzo dei tre problemi strutturali del progetto: «non c'è una sola
# prova automatica». Tutto veniva verificato guardando fotografie dello
# schermo, una volta, e la modifica successiva poteva rompere il tasto destro
# sulla scrivania senza che nessuno se ne accorgesse per settimane.
#
# Qui dentro non c'è niente di sofisticato. Ci sono cinque domande a cui una
# macchina può rispondere in venti secondi, e che nessuno si ricorda di farsi:
#
#   1. il codice del demone sta in piedi?              (dart analyze)
#   2. quello che fa, lo fa giusto?                    (dart test)
#   3. la configurazione di Hyprland si legge?         (--verify-config)
#   4. gli script sono scritti in shell valida?        (sh -n)
#   5. l'interfaccia si apre senza lamentarsi?         (quickshell + log)
#
# La quinta si può fare da quando il gestore file è un processo suo: prima
# avrebbe voluto dire riavviare la shell di chi stava lavorando.

SELF="$(readlink -f "$0")"
ROOT="$(dirname "$(dirname "$SELF")")"
MODE="${1:-tutto}"

ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; FAILED=$((FAILED + 1)); }
skip() { printf '\033[33m–\033[0m %s\n' "$1"; }
nota() { printf '       \033[36m·\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m── %s\033[0m\n' "$1"; }

FAILED=0

# ── 1 e 2. Il demone ───────────────────────────────────────────────────────
head_ "Demone (Dart)"
if command -v dart >/dev/null 2>&1; then
    cd "$ROOT/minervad" || exit 1

    # `dart analyze` segnala anche i suggerimenti di stile, che non sono
    # guasti: si guarda solo se ci sono errori veri.
    OUT=$(dart analyze 2>&1)
    if echo "$OUT" | grep -q "^ *error"; then
        bad "dart analyze ha trovato errori"
        echo "$OUT" | grep "^ *error" | head -10
    else
        ok "dart analyze: nessun errore"
    fi

    if dart test --reporter compact > /tmp/minerva-prove-test.log 2>&1; then
        ok "$(grep -o '+[0-9]*' /tmp/minerva-prove-test.log | tail -1) prove del demone passate"
    else
        bad "prove del demone fallite"
        tail -20 /tmp/minerva-prove-test.log
    fi
    cd "$ROOT" || exit 1
else
    skip "dart non installato: prove del demone saltate"
fi

# ── 3. La sorgente delle scorciatoie ───────────────────────────────────────
#
# Qui si verificava `config/hyprland.conf` con `Hyprland --verify-config`.
# Quel file è sparito il 2 settembre 2026 con la sessione Hyprland.
#
# Al suo posto NON si rimette un secondo controllo: che
# `config/scorciatoie.minerva` si legga lo verifica già
# `minervad/test/scorciatoie_sorgente_test.dart`, che gira nelle prove del
# demone qui sopra e dice riga e motivo quando la sorgente è storta.
#
# Quello che qui non c'era e serve è più semplice: **che il file ci sia**. È
# l'unico file di configurazione rimasto a Minerva, e senza di lui la scrivania
# parte senza nessun tasto — novantacinque scorciatoie mute, e nessun errore da
# nessuna parte, perché un file che non c'è non dà errore di sintassi.
head_ "Configurazione"
SORGENTE="$ROOT/config/scorciatoie.minerva"
if [ ! -f "$SORGENTE" ]; then
    bad "manca config/scorciatoie.minerva: la scrivania parte senza tasti"
elif [ ! -s "$SORGENTE" ]; then
    bad "config/scorciatoie.minerva è vuoto"
else
    QUANTE=$(grep -cE '^[^#]*->' "$SORGENTE" 2>/dev/null || true)
    if [ "${QUANTE:-0}" -gt 50 ]; then
        ok "config/scorciatoie.minerva: $QUANTE scorciatoie"
    else
        bad "config/scorciatoie.minerva ne dichiara solo ${QUANTE:-0}: ne mancano"
    fi
fi

# ── 3-ter. La schermata di accesso non gira dal progetto ───────────────────
#
# Gira da una COPIA in /usr/local, e deve essere così: il greeter è l'utente
# `greeter`, e in una cartella personale — `drwx------` — non entra. Ma quella
# copia si aggiorna solo quando qualcuno lancia `sudo minerva-greetd installa`,
# e **niente lo ricorda**.
#
# Quanto è costato, per esteso. Il 17 agosto 2026 Giacomo scriveva: «mi fa
# entrare solo con cosmic e minerva, hyprland e kde mi portano sempre su
# minerva». La correzione — le quattro variabili `XDG_*` che ogni scrivania si
# aspetta — è stata scritta lo stesso giorno. **Il 23 agosto il difetto era
# ancora lì**, identico, perché la copia installata era rimasta a prima. Sei
# giorni a girare col codice vecchio, e nessun modo di accorgersene: la
# schermata funzionava, si apriva, chiedeva la password. Semplicemente non era
# quella che avevamo corretto.
#
# Si confrontano solo le cartelle che la schermata legge davvero, e il demone.
# Confrontare tutto darebbe rosso per il gestore file — che nel greeter non si
# apre mai — e un rosso che non conta insegna a ignorare il rosso.
head_ "Schermata di accesso"
INST=/usr/local/share/minerva/minerva-shell
if [ ! -d "$INST" ]; then
    skip "greeter non installato: niente da confrontare"
else
    INDIETRO=""
    for c in greeter core theme ui; do
        if ! diff -rq "$ROOT/minerva-shell/$c" "$INST/$c" >/dev/null 2>&1; then
            INDIETRO="${INDIETRO:+$INDIETRO }$c"
        fi
    done
    for f in greeter.qml; do
        if ! cmp -s "$ROOT/minerva-shell/$f" "$INST/$f"; then
            INDIETRO="${INDIETRO:+$INDIETRO }$f"
        fi
    done
    if [ -x /usr/local/lib/minerva/minervad ] \
       && ! cmp -s "$ROOT/minervad/build/minervad" /usr/local/lib/minerva/minervad; then
        INDIETRO="${INDIETRO:+$INDIETRO }il-demone"
    fi
    if [ ! -x /usr/local/lib/minerva/minerva-avvia-sessione ]; then
        INDIETRO="${INDIETRO:+$INDIETRO }l-avviatore"
    fi

    if [ -z "$INDIETRO" ]; then
        ok "la copia installata è quella del progetto"
    else
        bad "la schermata di accesso gira con codice vecchio: $INDIETRO"
        nota "quello che correggi qui NON arriva all'accesso finché non lanci:"
        nota "    scripts/minerva-compila && sudo scripts/minerva-greetd installa"
    fi
fi

# ── 3-quater-bis. Il compositore in esecuzione è quello compilato? ─────────
#
# Stessa storia della schermata di accesso, e stesso modo di costare giorni.
# `compositore/costruisci.sh` installa per RINOMINA, apposta: sostituire il
# binario sotto la sessione che ci sta girando dentro vuol dire pagine di
# codice che diventano spazzatura mentre le si esegue. Il prezzo è che il
# codice nuovo entra al **prossimo accesso**.
#
# Nel frattempo la scrivania gira col compositore di prima, e un verbo appena
# aggiunto non lo conosce nessuno: la shell scrive «no verbo «…» sconosciuto» e
# il pannello che l'ha chiesto non fa niente. È già successo con `aspetto`, ed
# è il modo in cui quel difetto si è visto.
#
# Qui non si dice «rotto»: si dice quale delle due cose sta succedendo.
COMP_VECCHIO=0
COMP_PID=$(pgrep -x minerva-wayland 2>/dev/null | head -1)
COMP_BIN="${MINERVA_BIN:-$HOME/.local/bin}/minerva-wayland"
if [ -n "$COMP_PID" ] && [ -x "$COMP_BIN" ]; then
    if cmp -s "/proc/$COMP_PID/exe" "$COMP_BIN" 2>/dev/null; then
        ok "il compositore in esecuzione è quello compilato"
    else
        COMP_VECCHIO=1
        nota "il compositore in esecuzione è più VECCHIO di quello compilato:"
        nota "    il binario nuovo c'è, ma entra al prossimo accesso."
        nota "    Fino ad allora un verbo nuovo risulta «sconosciuto»."
    fi
fi

# ── 3-quater. L'avviatore rimette insieme quello che greetd spezza ─────────
#
# greetd non esegue l'array `cmd` come un `argv`, per quanto la sua pagina di
# manuale dica «command line»: lo unisce con degli spazi e lo passa a
# `/bin/sh -c`. Delle quattro sessioni installate su questo computer, Plasma è
# l'unica con due parole nella riga `Exec=`, e arrivava spezzata in due: partiva
# solo la prima, che esce subito e in silenzio. Uscita 0, zero secondi — da
# fuori identico a una password sbagliata, e per questo è durato giorni.
#
# La prova avvia davvero l'avviatore, con un comando innocuo di due parole
# consegnato in due pezzi, e guarda cosa ha scritto nel registro.
head_ "Avvio delle sessioni"
AVV="$ROOT/scripts/minerva-avvia-sessione"
STATO_FINTO="$(mktemp -d)"
if XDG_STATE_HOME="$STATO_FINTO" "$AVV" /bin/echo ciao mondo >/dev/null 2>&1; then :; fi
REG_FINTO="$STATO_FINTO/minerva/sessione.log"
if [ ! -f "$REG_FINTO" ]; then
    bad "l'avviatore non ha scritto nessun registro"
elif grep -q "avvio: /bin/echo ciao mondo" "$REG_FINTO"; then
    ok "una riga di comando spezzata da greetd viene rimessa insieme"
else
    bad "l'avviatore ha perso dei pezzi del comando"
    nota "ha scritto: $(grep -m1 'avvio:' "$REG_FINTO" 2>/dev/null)"
fi
if grep -q "^ciao mondo$" "$REG_FINTO" 2>/dev/null; then
    ok "e il comando è stato eseguito per intero"
else
    bad "il comando non è arrivato intero al programma"
fi
rm -rf "$STATO_FINTO"

# La schermata non deve rimettere una shell davanti al comando: quella ce la
# mette già greetd, e due interpreti in fila spezzano le righe di due parole.
if grep -q '"sh", "-lc", greeter.sessione.comando' "$ROOT/minerva-shell/greeter/Greeter.qml" 2>/dev/null; then
    bad "la schermata rimette un «sh -lc» davanti al comando di sessione"
    nota "greetd unisce cmd con degli spazi e lo dà già a /bin/sh -c:"
    nota "un secondo interprete rispezza le righe Exec= di due parole (KDE)."
else
    ok "la schermata non aggiunge una seconda shell"
fi

# ── 3-sexies. L'aiutante di root ───────────────────────────────────────────
#
# `minerva-radice` è l'unico pezzo di Minerva che gira come amministratore su
# richiesta di una finestra. Le sue prove stanno in un file a parte perché
# funzionano in modo diverso: si fanno una copia dell'aiutante con i controlli
# d'ingresso tolti, e la lanciano su una finta radice.
head_ "Modalità amministratore"
if [ ! -r "$ROOT/scripts/minerva-radice" ]; then
    skip "aiutante non trovato"
else
    USCITA_RADICE=$(sh "$ROOT/scripts/prova-radice.sh" 2>&1) && ESITO=0 || ESITO=1
    CONTO=$(printf '%s' "$USCITA_RADICE" | sed -n 's/.*  \([0-9]*\) passate.*/\1/p')
    if [ "$ESITO" -eq 0 ]; then
        ok "${CONTO:-?} prove dell'aiutante di root passate (accetta e rifiuta)"
    else
        bad "l'aiutante di root non si comporta come deve:"
        printf '%s\n' "$USCITA_RADICE" | grep '  NO   ' | while IFS= read -r R; do
            nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
        done
    fi
fi

# ── 3-quinquies. I permessi che tengono chiuso il canale ───────────────────
#
# Non si controlla il codice, si controlla il COMPUTER. Ogni riga qui sotto è
# un buco che è stato aperto per davvero almeno una volta, e che si richiude da
# solo alla prossima installazione fatta male:
#
#  · `/usr/local/share/minerva` restava di Giacomo perché `rsync -a` conserva
#    il proprietario. Lì dentro c'è `greeter.qml`, cioè il programma che
#    disegna la casella della password: un processo qualunque che gira come lui
#    poteva riscriverlo e farsi consegnare le password di tutti.
#  · La parola d'ordine del canale in un file leggibile da altri vuol dire dare
#    a un altro utente il comando della scrivania — e nella schermata di
#    accesso, la possibilità di avviare una sessione a nome tuo.
#  · I registri del greeter a 0755 raccontano a chiunque i tentativi falliti.
head_ "Permessi"
PERM_MALE=""
guarda_modo() {   # percorso, modo atteso, proprietario atteso
    [ -e "$1" ] || return 0
    M=$(stat -c '%a' "$1" 2>/dev/null)
    U=$(stat -c '%U' "$1" 2>/dev/null)
    [ "$M" = "$2" ] && [ -z "$3" -o "$U" = "$3" ] && return 0
    PERM_MALE="${PERM_MALE}$1 — modo $M (atteso $2), di $U${3:+ (atteso $3)}
"
}

guarda_modo /var/lib/minerva-greeter 700 greeter
guarda_modo /var/log/minerva-greeter 750 greeter

# L'installazione: di root, e non scrivibile da nessun altro.
for D in /usr/local/share/minerva /usr/local/lib/minerva \
         /usr/local/bin/minerva-greetd /usr/local/bin/minerva-radice \
         /usr/local/bin/minerva-utente; do
    [ -e "$D" ] || continue
    SCRIVIBILI=$(find "$D" \( ! -user root -o -perm -g+w -o -perm -o+w \) \
                 -print 2>/dev/null | head -3)
    [ -z "$SCRIVIBILI" ] || PERM_MALE="${PERM_MALE}$SCRIVIBILI
"
done

# La parola d'ordine di ogni sessione viva: sua e di nessun altro.
for C in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/minerva/sessioni/*/canale; do
    [ -f "$C" ] || continue
    guarda_modo "$C" 600 "$(id -un)"
done

if [ -z "$PERM_MALE" ]; then
    ok "quello che tiene chiuso il canale è chiuso davvero"
else
    bad "permessi troppo larghi:"
    printf '%s' "$PERM_MALE" | while IFS= read -r X; do
        [ -n "$X" ] && nota "$X"
    done
    nota "si rimettono a posto con: sudo scripts/minerva-greetd installa"
fi

# ── 3-bis. Il nostro compositore ───────────────────────────────────────────
#
# minerva-wayland è C, e il C non ha un `dart analyze`: quello che si può
# provare a macchina è che **compili senza un solo avviso** (il progetto è a
# `werror=true`) e che le quattro righe che già ci sono costate non tornino
# indietro. Sono tutte righe il cui difetto NON dà errore: dà uno schermo nero,
# o una barra dietro le finestre, e si passa un pomeriggio a cercarle.
head_ "Compositore (C)"
SORGENTE="$ROOT/compositore/src/main.c"
if [ ! -f "$SORGENTE" ]; then
    skip "compositore non presente"
elif ! pkg-config --exists wlroots-0.20 2>/dev/null; then
    skip "wlroots 0.20 non installata: compositore non provato"
else
    if [ -d "$ROOT/compositore/build" ]; then
        if ninja -C "$ROOT/compositore/build" > /tmp/minerva-compositore.log 2>&1; then
            ok "minerva-wayland compila senza avvisi"
        else
            bad "minerva-wayland non compila"
            tail -15 /tmp/minerva-compositore.log
        fi
    else
        skip "compositore mai configurato: lancia compositore/costruisci.sh"
    fi

    # ── Il ciclo di eventi, non il display ───────────────────────────────
    #
    # In wlroots 0.20 `wlr_backend_autocreate` vuole il `wl_event_loop`.
    # Fino alla 0.18 voleva il `wl_display`, e ogni esempio in circolazione
    # fa così: compila con un avviso e poi non parte.
    if grep -q "wlr_backend_autocreate(m.loop" "$SORGENTE"; then
        ok "il backend si crea sul ciclo di eventi"
    else
        bad "wlr_backend_autocreate non riceve più m.loop"
        nota "in wlroots 0.20 vuole il wl_event_loop, non il wl_display"
    fi

    # ── La prima configure, senza la quale non compare NIENTE ────────────
    #
    # Da wlroots 0.18 il compositore deve rispondere alla prima commit. Chi
    # non lo fa lascia il programma ad aspettare per sempre: nessun errore,
    # nessuna riga nel registro, solo uno schermo nero.
    #
    # Si cercano le due righe PRECISE e non il numero di volte che la parola
    # compare: contando, il commento che la spiega vale come una delle due, e
    # la prova resta verde anche togliendo quella vera. Provato: succede.
    MANCA=""
    grep -q "f->toplevel->base->initial_commit" "$SORGENTE" || MANCA="finestre"
    grep -q "a->ls->initial_commit" "$SORGENTE" \
        || MANCA="${MANCA:+$MANCA e }pannelli"
    if [ -z "$MANCA" ]; then
        ok "la prima configure c'è per le finestre E per i pannelli"
    else
        bad "manca la risposta alla prima commit: $MANCA"
        nota "senza, il programma aspetta per sempre e lo schermo resta nero"
    fi

    # ── La scala, e i tre protocolli che la portano ──────────────────────
    #
    # Ognuna di queste righe, se sparisce, dà lo STESSO sintomo: la scrivania
    # esce grande il doppio o piccola di un quarto. Ed è il motivo per cui
    # stanno tutte e quattro qui: col sintomo identico non si riesce a
    # indovinare quale manca, e le si cerca a una a una.
    #
    # Misurato il 24 agosto 2026, schermo annidato 1280×720 a scala 1,25:
    #
    #   niente `set_scale`            la shell vede 1280×720   (scala ignorata)
    #   solo `set_scale`              la shell vede  640×360   (1280 / 2)
    #   + viewporter + frazionaria    la shell vede  640×360   (ancora!)
    #   + xdg-output                  la shell vede 1024×576   ✓
    #
    # La terza riga è quella che sorprende: la scala frazionaria è **per
    # superficie** — dice a una finestra a che risoluzione disegnare — e non
    # dice a nessuno quanto è grande la scrivania. Quella la porta xdg-output.
    MANCA=""
    grep -q "wlr_output_state_set_scale" "$SORGENTE" || MANCA="la scala"
    grep -q "wlr_viewporter_create" "$SORGENTE" \
        || MANCA="${MANCA:+$MANCA, }viewporter"
    grep -q "wlr_fractional_scale_manager_v1_create" "$SORGENTE" \
        || MANCA="${MANCA:+$MANCA, }la scala frazionaria"
    grep -q "wlr_xdg_output_manager_v1_create" "$SORGENTE" \
        || MANCA="${MANCA:+$MANCA, }xdg-output"
    if [ -z "$MANCA" ]; then
        ok "la scala arriva ai client: scala, viewporter, frazionaria, xdg-output"
    else
        bad "manca quello che porta la scala ai client: $MANCA"
        nota "il sintomo è sempre lo stesso — tutto grande il doppio o piccolo"
        nota "di un quarto — quindi non si indovina quale manca: si legge qui."
    fi

    # ── E la rete sotto la configurazione degli schermi ───────────────────
    #
    # Una riga sbagliata in `schermi.conf` è l'unico difetto del compositore
    # che si porta via il modo di ripararlo: dà uno schermo nero, e per
    # correggere quella riga serve lo schermo.
    # Si cerca la RIGA DEL REGISTRO del secondo tentativo, non il numero di
    # volte che compare una chiamata: contare vuol dire che un commento in più
    # tiene la prova verde. È lo stesso errore già evitato per la prima
    # configure, qualche riga più in su.
    if grep -q "ripreso con i valori sicuri" "$SORGENTE"; then
        ok "una configurazione degli schermi sbagliata non lascia lo schermo nero"
    else
        bad "manca il secondo tentativo coi valori sicuri in schermo_nuovo"
        nota "senza, una riga storta in schermi.conf spegne lo schermo — e per"
        nota "correggerla servirebbe lo schermo."
    fi

    # ── I verbi devono esistere in tutti e due i file ─────────────────────
    #
    # `core/Compositore.qml` manda dei verbi; `compositore/src/main.c` li
    # ascolta. Sono due file in due linguaggi diversi che devono dire la stessa
    # parola, ed è il posto classico in cui una differenza NON dà errore: il
    # compositore risponde «no verbo sconosciuto» sul socket, la shell scrive
    # un avviso che nessuno guarda, e la finestra semplicemente non si muove.
    #
    # È la stessa guardia che già confronta le azioni della shell con quelle
    # del demone (`bus_coerenza_test.dart`), e nasce dallo stesso incidente:
    # nove azioni gestite dal demone e nominate da nessuno.
    QML_COMP="$ROOT/minerva-shell/core/Compositore.qml"
    if [ -f "$QML_COMP" ]; then
        SCONOSCIUTI=""
        # ── Come si estraggono i verbi ────────────────────────────────────
        #
        # Il SECONDO argomento di ogni `_due(...)`. Non il primo, che è la riga
        # per Hyprland: in `_due("killactive", "chiudi", …)` il primo è pure
        # una parola sola fra virgolette, e prendere «la prima che capita»
        # farebbe cercare `killactive` dentro il compositore. Ed è per questo
        # che non basta un `grep`: la chiamata va spesso a capo, e le
        # virgolette in un file QML sono dappertutto.
        VERBI=$(python3 "$ROOT/scripts/verbi-compositore.py" "$QML_COMP")
        for V in $VERBI; do
            grep -q "\"$V\"" "$SORGENTE" || SCONOSCIUTI="${SCONOSCIUTI:+$SCONOSCIUTI }$V"
        done
        if [ -z "$SCONOSCIUTI" ]; then
            ok "ogni verbo che la shell manda, il compositore lo conosce"
        else
            bad "verbi che il compositore non conosce: $SCONOSCIUTI"
            nota "la shell li manderebbe e lui risponderebbe «no verbo"
            nota "sconosciuto» — a voce bassa, e la finestra non si muove."
        fi
    fi

    # ── Ogni scorciatoia «minerva:» ha qualcuno che risponde ──────────────
    #
    # Il nome è l'unica cosa che tiene insieme le due metà — la sorgente dei
    # tasti e il pezzo di shell che fa la cosa — e nessuna delle due si accorge
    # se l'altra cambia. Una scorciatoia senza risposta è un tasto che si preme
    # e non fa niente, senza nessun errore da nessuna parte.
    #
    # Conta doppio da quando i compositori sono due: sotto Hyprland il nome
    # viaggia in `global, quickshell:<nome>`, sotto minerva-wayland in
    # `evento scorciatoia`. Stesso nome, due strade, e un errore di battitura
    # le spegne tutte e due insieme.
    NOMI=$(python3 "$ROOT/scripts/nomi-scorciatoie.py" "$ROOT")
    case "$NOMI" in
        OK*) ok "ogni scorciatoia «minerva:» ha chi le risponde (${NOMI#OK })" ;;
        *)   bad "scorciatoie e risposte non combaciano: $NOMI" ;;
    esac

    # ── Ogni azione mandata al compositore, lui sa farla ──────────────────
    #
    # Il Dart decide quali azioni valgono per minerva-wayland; il C decide
    # quali sa eseguire. Se i due elenchi divergono non lo dice nessuno:
    # un'azione dichiarata e non eseguita è una scorciatoia che si registra, si
    # mangia il tasto e non fa niente — e il programma sotto non riceve nemmeno
    # la pressione, quindi è peggio di un tasto libero.
    #
    # Provata su una copia rotta apposta prima di essere messa qui.
    AZIONI=$(python3 "$ROOT/scripts/azioni-scorciatoie.py" "$ROOT")
    case "$AZIONI" in
        OK*) ok "ogni azione delle scorciatoie, il compositore sa farla (${AZIONI#OK })" ;;
        *)   bad "azioni e compositore non combaciano: $AZIONI" ;;
    esac

    # ── E i comandi che a minerva-wayland non arrivano affatto ────────────
    #
    # La guardia di sopra guarda una porta sola: confronta i verbi che passano
    # da `_due()` con quelli che il compositore conosce. Non può quindi
    # accorgersi della cosa peggiore — un comando che al nostro compositore
    # **non viene mandato**, perché quella funzione parla solo la lingua di
    # Hyprland.
    #
    # È successo due volte, tutte e due in silenzio: `minimize()` mandava
    # `movetoworkspacesilent` (la finestra spariva e non tornava) e
    # `vaiAScrivania()` mandava `workspace N` (non arrivava a nessuno). Questa
    # riga è nata dalla seconda, il 25 agosto 2026, e la stessa sera ne ha
    # trovate altre tre.
    if [ -f "$QML_COMP" ]; then
        SORDE=$(python3 "$ROOT/scripts/verbi-compositore.py" "$QML_COMP" --sordi)
        if [ -z "$SORDE" ]; then
            ok "ogni comando della shell ha una strada anche per minerva-wayland"
        else
            bad "funzioni che parlano solo a Hyprland: $SORDE"
            nota "sotto minerva-wayland quella riga se ne va nel vuoto, senza"
            nota "errore. O le dai un verbo nostro, o la dichiari: aggiungi la"
            nota "riga in «senzaDestinazione» e chiama _senzaStrada(\"nome\")."
        fi
    fi

    # ── «Finestra» resta una finestra, di qualunque razza ────────────────
    #
    # Dentro il compositore una finestra può essere Wayland o X11, e la
    # differenza sta chiusa dentro un gruppo ristretto di funzioni. Fuori da
    # lì, `f->toplevel` su una finestra di Steam è NULL — e non dà nessun
    # errore: il compositore cade, oppure (peggio) non cade e si comporta
    # storto solo con Steam aperto.
    #
    # Provata su una copia rotta apposta prima di essere messa qui.
    RAZZA=$(python3 "$ROOT/scripts/razza-finestre.py" 2>&1) && ESI=0 || ESI=1
    if [ "$ESI" -eq 0 ]; then
        ok "$(printf '%s' "$RAZZA" | sed 's/^ok: //')"
    else
        bad "il confine fra «finestra» e «protocollo» è stato attraversato:"
        printf '%s\n' "$RAZZA" | grep 'main.c:' | while IFS= read -r R; do
            nota "$(printf '%s' "$R" | sed 's/^ *//')"
        done
    fi

    # ── Una finestra si descrive in un posto solo ─────────────────────────
    #
    # L'elenco (`finestre`) e gli annunci (`evento aperta …`) mandano lo STESSO
    # oggetto, e devono mandarlo con la stessa funzione. Erano due costruzioni
    # separate nella prima stesura: si aggiunge un campo all'elenco, l'annuncio
    # non ce l'ha, e chi legge vede una finestra che cambia forma a seconda di
    # come l'ha saputa — un difetto che si manifesta solo quando due strade
    # portano allo stesso dato, cioè quasi mai, cioè tardi.
    if grep -q "static int finestra_json(" "$SORGENTE"; then
        COSTRUZIONI=$(grep -c 'id..:..0x%llx' "$SORGENTE" || true)
        if [ "$COSTRUZIONI" -le 1 ]; then
            ok "una finestra si descrive in un posto solo"
        else
            bad "l'oggetto finestra è costruito in $COSTRUZIONI posti"
            nota "elenco e annunci divergeranno: usa finestra_json()"
        fi
    fi

    # ── Un cliente lento non deve poter fermare lo schermo ────────────────
    #
    # Il socket del canale è non bloccante. Un cliente che smette di leggere
    # riempie il proprio buffer e `write` risponde EAGAIN per sempre: un ciclo
    # che riprova senza una fine gira DENTRO il ciclo di eventi del
    # compositore, e ferma il mouse e lo schermo di tutti perché un programma
    # qualunque — anche solo fermo su un punto di interruzione — non sta
    # leggendo. C'era, ed è uscito il 24 agosto 2026.
    #
    # ── E il 13 settembre 2026 è uscita anche l'attesa ───────────────────
    #
    # La cura del 24 agosto era un `poll` con una pazienza di 200 ms: un
    # ciclo con una fine, ma sempre un ciclo DENTRO il compositore. L'audit
    # di Codex l'ha misurato (C02): un cliente fermo costava a tutti gli
    # altri 203 ms di attesa — mouse e schermo compresi. Adesso la risposta
    # va in una coda per cliente e il socket si svuota quando il ciclo di
    # eventi dice che è scrivibile (`WL_EVENT_WRITABLE`); chi non legge
    # riempie la sua coda e viene chiuso, senza che nessuno aspetti.
    #
    # Quindi la guardia cerca la coda e NON deve trovare il `poll`: se
    # qualcuno lo rimette, questa riga torna rossa.
    CANALE_C="$ROOT/compositore/src/canale.c"
    if [ -f "$CANALE_C" ]; then
        if grep -q "WL_EVENT_WRITABLE" "$CANALE_C" && ! grep -q "poll(&pf" "$CANALE_C"; then
            ok "un cliente che non legge si stacca, e nessuno lo aspetta"
        else
            bad "canale.c aspetta un cliente lento dentro il ciclo di eventi"
            nota "un cliente fermo costerebbe a tutti gli altri un'attesa (misurata: 203 ms)"
        fi
    fi

    # ── Un compositore fermato non deve lasciare sporco ───────────────────
    #
    # Senza un gestore per SIGTERM, `wl_display_run` non torna e
    # `canale_chiudi()` non viene chiamato: il file del socket resta sul disco.
    # E un socket avanzato non dà nessun errore a chi lo guarda — sembra un
    # compositore acceso. Il 24 agosto 2026 il demone della sessione VERA ci è
    # cascato: ha chiesto le finestre a un compositore morto, e la scrivania è
    # rimasta senza finestre senza un errore da nessuna parte.
    if grep -q "wl_event_loop_add_signal(m.loop, SIGTERM" "$SORGENTE"; then
        ok "un compositore fermato toglie il proprio socket"
    else
        bad "minerva-wayland non ascolta SIGTERM"
        nota "il socket resterebbe sul disco, e sembrerebbe un compositore vivo"
    fi

    # ── Le prove del lettore di schermi ───────────────────────────────────
    if [ -x "$ROOT/compositore/build/prova-schermi" ]; then
        USCITA_SCH=$("$ROOT/compositore/build/prova-schermi" 2>&1) && ESI=0 || ESI=1
        CONTO_SCH=$(printf '%s' "$USCITA_SCH" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_SCH:-?} prove degli schermi passate"
        else
            bad "il lettore di schermi non si comporta come deve:"
            printf '%s\n' "$USCITA_SCH" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    else
        skip "prova-schermi non costruito"
    fi

    # ── Le prove dell'aggancio ai bordi ───────────────────────────────────
    #
    # Stessa forma delle precedenti, e per la stessa ragione: `src/aggancio.c`
    # è conto puro, e il suo difetto si vedrebbe come una finestra nel posto
    # sbagliato — cioè tardi e solo guardando. Il caso che conta di più è
    # «agganciata in alto finisce sotto la barra di sistema»: è già successo
    # una volta in `spine/TitleBars.qml`, dove il conto partiva dallo schermo
    # intero invece che dallo spazio utile.
    if [ -x "$ROOT/compositore/build/prova-aggancio" ]; then
        USCITA_AGG=$("$ROOT/compositore/build/prova-aggancio" 2>&1) && ESI=0 || ESI=1
        CONTO_AGG=$(printf '%s' "$USCITA_AGG" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_AGG:-?} prove dell'aggancio ai bordi passate"
        else
            bad "l'aggancio ai bordi non manda le finestre dove deve:"
            printf '%s\n' "$USCITA_AGG" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    else
        skip "prova-aggancio non costruito"
    fi

    # ── Le prove del ritaglio della lente ─────────────────────────────────
    #
    # Stessa forma, con una ragione in più che vale solo per questa: la lente
    # è l'unica cosa del compositore che NON si può fotografare. Agisce sullo
    # scanout, e `grim` cattura la scena — due catture con lente spenta e
    # accesa sono identiche al pixel. Per le barre del titolo fantasma la
    # fotografia è stata la sola strada; qui quella strada non c'è.
    if [ -x "$ROOT/compositore/build/prova-lente" ]; then
        USCITA_LEN=$("$ROOT/compositore/build/prova-lente" 2>&1) && ESI=0 || ESI=1
        CONTO_LEN=$(printf '%s' "$USCITA_LEN" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_LEN:-?} prove del ritaglio della lente passate"
        else
            bad "la lente ingrandisce il pezzo sbagliato:"
            printf '%s\n' "$USCITA_LEN" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    else
        skip "prova-lente non costruita"
    fi

    # ── Gli annunci: il compositore vero, con dentro una finestra vera ───
    #
    # È l'unica prova del compositore che accende wlroots, e c'è una ragione
    # per cui vale il suo mezzo minuto: il pezzo che prova — il legame fra il
    # ciclo di eventi di wlroots e il socket — un finto non lo tocca. Dal capo
    # opposto ci sono le prove del demone, che leggono le righe con un
    # compositore finto; senza questa, nessuno verificherebbe che quelle righe
    # qualcuno le scriva davvero.
    #
    # Si salta senza sessione Wayland (fuori da una, wlroots prenderebbe lo
    # schermo VERO) e con MINERVA_SENZA_ANNIDATE=1, per chi lancia le prove su
    # una macchina senza schermo.
    ANNUNCI="$ROOT/compositore/prova-annunci.py"
    if [ ! -x "$ANNUNCI" ]; then
        skip "prova-annunci.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "annunci: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "annunci: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_ANN=$(python3 "$ANNUNCI" 2>&1) && ESI=0 || ESI=1
        CONTO_ANN=$(printf '%s' "$USCITA_ANN" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_ANN:-?} prove degli annunci passate (compositore vero)"
        else
            bad "il compositore non annuncia come deve:"
            printf '%s\n' "$USCITA_ANN" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Che il blocco schermo BLOCCHI ────────────────────────────────────
    #
    # È il pezzo in cui un errore non si vede: un blocco che non blocca sembra
    # identico a uno che blocca, finché qualcuno non ci prova — e chi ci prova,
    # di solito, non sei tu.
    #
    # La prova gira il blocco VERO di Minerva dentro il compositore annidato, e
    # la cosa che verifica è quella per cui `ext-session-lock` esiste: **ucciso
    # il programma del blocco, lo schermo resta bloccato.**
    BLOCCO="$ROOT/compositore/prova-blocco.py"
    if [ ! -x "$BLOCCO" ]; then
        skip "prova-blocco.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "blocco: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "blocco: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_BL=$(python3 "$BLOCCO" 2>&1) && ESI=0 || ESI=1
        CONTO_BL=$(printf '%s' "$USCITA_BL" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_BL:-?} prove del blocco schermo passate (compositore vero)"
        else
            bad "il blocco schermo non blocca come deve:"
            printf '%s\n' "$USCITA_BL" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── La via di fuga ───────────────────────────────────────────────────
    #
    # «Minerva (recupero)» è la RETE: quando Hyprland se ne va, è l'unica
    # strada che resta se la scrivania non parte. Una rete che non si prova è
    # una rete che si scopre rotta il giorno in cui serve — e quel giorno, per
    # definizione, qualcos'altro è già rotto.
    #
    # Alla prima passata, il 1º settembre 2026, ha trovato subito il difetto
    # peggiore possibile per una via di fuga: chiudendo il terminale la
    # sessione restava accesa su uno schermo nero.
    #
    # Quello che questa prova NON può fare è entrarci dal login: va fatto a
    # mano, ed è scritto nel piano che va fatto **prima** di togliere Hyprland.
    RECUPERO="$ROOT/compositore/prova-recupero.py"
    if [ ! -x "$RECUPERO" ]; then
        skip "prova-recupero.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "recupero: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "recupero: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_RE=$(python3 "$RECUPERO" 2>&1) && ESI=0 || ESI=1
        CONTO_RE=$(printf '%s' "$USCITA_RE" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_RE:-?} prove della sessione di recupero passate"
        else
            bad "la via di fuga non regge:"
            printf '%s\n' "$USCITA_RE" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── I tre modi della dock ────────────────────────────────────────────
    #
    # «Elude le finestre» è il modo che il 2 settembre 2026 non esisteva, e
    # Giacomo lo chiedeva da tempo. Non si prova leggendo il codice: la dock è
    # una superficie layer-shell che scivola fuori dallo schermo, e da fuori
    # non c'è niente da interrogare — per questo la shell risponde a
    # `qs ipc call minerva dock`.
    #
    # Alla prima passata ha trovato subito un difetto nel codice appena
    # scritto: passando a «si nasconde» la dock restava lì, perché dentro
    # `onModoChanged` le proprietà derivate valevano ancora quelle di prima.
    DOCK="$ROOT/compositore/prova-dock.py"
    if [ ! -x "$DOCK" ]; then
        skip "prova-dock.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "dock: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "dock: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_DK=$(python3 "$DOCK" 2>&1) && ESI=0 || ESI=1
        CONTO_DK=$(printf '%s' "$USCITA_DK" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_DK:-?} prove dei modi della dock passate"
        else
            bad "la dock non si comporta come deve:"
            printf '%s\n' "$USCITA_DK" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Lo snap, misurato in una sessione vera ───────────────────────────
    #
    # Giacomo, 2 settembre 2026: «bisogna sistemare lo snap perché funziona
    # malissimo perché posiziona male le finestre».
    #
    # Il conto puro era già provato (`prova-aggancio.c`, ventiquattro casi) e
    # passava: il difetto non stava lì. Stava fra il conto e lo schermo — nello
    # spazio utile, nella barra del titolo, nella cornice. Nessuna di quelle
    # tre cose si vede da un conto isolato, e per questo il difetto è
    # sopravvissuto a una prova verde.
    #
    # Trovato il 3 settembre 2026 proprio con questa prova: il compositore
    # agganciava giusto e la SHELL, trecento millisecondi dopo, rimetteva la
    # finestra 42 pixel più in basso senza accorciarla — una compensazione di
    # Hyprland (`barSopra`) sopravvissuta al distacco.
    AGG="$ROOT/compositore/prova-aggancio-vivo.py"
    if [ ! -x "$AGG" ]; then
        skip "prova-aggancio-vivo.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "aggancio: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "aggancio: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_AG=$(python3 "$AGG" 2>&1) && ESI=0 || ESI=1
        CONTO_AG=$(printf '%s' "$USCITA_AG" | sed -n 's/^  \([0-9]*\) passate.*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_AG:-?} prove dell'aggancio passate (tutte e sette le zone)"
        else
            bad "l'aggancio posiziona male le finestre:"
            printf '%s\n' "$USCITA_AG" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Il portachiavi c'è ───────────────────────────────────────────────
    #
    # Senza `org.freedesktop.secrets` sul bus, la Custodia non può tenere un
    # gettone di GitHub e gli account online non possono ricordare una
    # password. Nessuno dei due lo dice: è la «sincronizzazione sospesa».
    #
    # Su Arch il servizio di KDE dichiara solo `org.kde.secretservicecompat`, e
    # il nome standard lo prende soltanto a programma avviato — sotto Plasma lo
    # avvia Plasma, sotto Minerva lo avvia `minerva-dentro-wayland`.
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "portachiavi: fuori da una sessione"
    elif busctl --user status org.freedesktop.secrets >/dev/null 2>&1; then
        ok "il portachiavi risponde (org.freedesktop.secrets)"
    else
        bad "nessun portachiavi sul bus:"
        nota "la Custodia non può tenere un gettone e gli account non possono"
        nota "ricordare una password — e non lo dicono. Lo avvia"
        nota "scripts/minerva-dentro-wayland; se manca, la sessione è vecchia."
    fi

    # ── Il guardiano muore con la sua sessione ───────────────────────────
    #
    # Il 7 settembre 2026 sulla macchina giravano due `minervad`: quello della
    # sessione in corso e quello di quella prima, adottato da `init`. Un demone
    # che risponde per una scrivania che non esiste più, fino al riavvio.
    GUARD="$ROOT/scripts/prova-guardiano.py"
    if [ ! -x "$GUARD" ]; then
        skip "prova-guardiano.py non trovata"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "guardiano: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_GU=$(python3 "$GUARD" 2>&1) && ESI=0 || ESI=1
        CONTO_GU=$(printf '%s' "$USCITA_GU" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_GU:-?} prove del guardiano passate (muore con la sessione)"
        else
            bad "il guardiano del demone sopravvive alla sessione:"
            printf '%s\n' "$USCITA_GU" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── La cornice colorata è un ANELLO, non una macchia ─────────────────
    #
    # Giacomo, 7 settembre 2026: «quando clicco su uno dei controlli sulla
    # barra il terminale cambia colore, tutta la finestra». E poi la frase che
    # ha chiuso la diagnosi: «quando disattivo l'accento cioè la cornice
    # colorata il problema sparisce».
    #
    # Il colore lo portava la `maniglia`, che è un rettangolo PIENO sotto tutta
    # la finestra: invisibile sotto una finestra opaca, ben visibile sotto una
    # traslucida. Questa prova guarda i pixel dentro un compositore annidato,
    # e guarda anche il BORDO — se l'anello non si vede, spegnere la cornice
    # farebbe passare la prova senza aver riparato niente.
    CORN_ANELLO="$ROOT/compositore/prova-cornice-anello.py"
    if [ ! -x "$CORN_ANELLO" ]; then
        skip "prova-cornice-anello.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "cornice: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "cornice: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_AN=$(python3 "$CORN_ANELLO" 2>&1) && ESI=0 || ESI=1
        CONTO_AN=$(printf '%s' "$USCITA_AN" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_AN:-?} prove della cornice passate (anello, non macchia)"
        else
            bad "la cornice colorata dipinge dove non deve:"
            printf '%s\n' "$USCITA_AN" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Il corpo unico: una trasparenza sola su tutta la finestra ────────
    #
    # Giacomo, 2 settembre 2026: «in blur o vetro dovrebbero far vedere un solo
    # corpo trasparente [...] la barra e la finestra senza stacchi».
    #
    # È l'unica prova del progetto che misura dei PIXEL, e la ragione è che
    # «senza stacchi» non ha nessun'altra faccia: due rettangoli attaccati con
    # alfa 0,90 e 1,00 non danno nessun errore e da fuori il compositore
    # risponde uguale nei due casi.
    #
    # Non confronta fotografie fra loro — quella è la prova che diventa rossa
    # il giorno che cambia lo sfondo. Confronta la STESSA finestra con sé
    # stessa a un secondo di distanza, prima e dopo aver acceso il vetro, e
    # guarda di quanto è cambiata ciascuna delle due parti.
    EFF="$ROOT/compositore/prova-effetto.py"
    if [ ! -x "$EFF" ]; then
        skip "prova-effetto.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "effetto: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "effetto: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_EF=$(python3 "$EFF" 2>&1) && ESI=0 || ESI=1
        CONTO_EF=$(printf '%s' "$USCITA_EF" | sed -n 's/^  \([0-9]*\) passate.*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_EF:-?} prove del corpo unico passate"
        else
            bad "barra e finestra non sono un corpo solo:"
            printf '%s\n' "$USCITA_EF" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Gli effetti costano quello che mostrano, e non lasciano scie ─────
    #
    # Due prove sugli effetti nativi del fork, che fino al 23 settembre 2026
    # giravano a mano e basta.
    #
    # `prova-blur-contenuto.py` (di Codex): il blur non sbiadisce le app
    # opache e a schermo intero nessun effetto forza la trasparenza — dodici
    # confronti a pixel.
    #
    # `prova-danno-blur.py`: il danno incrementale. Fino al 23 settembre si
    # ridipingeva tutto lo schermo con un filtro in scena (100 % dei pixel per
    # un puntino che lampeggia) e tutta la finestra di un programma a ogni suo
    # fotogramma — per l'anello e per l'opacità del vetro che si litigavano.
    # Un danno sbagliato non dà errori: lascia scie. La prova ferma tutto,
    # fotografa, fa ridisegnare da capo e confronta — ed è stata vista ROSSA
    # col filtro rotto apposta (5.653 pixel di scia, un anello attorno al
    # quadrato), dopo tre versioni verdi che non provavano niente.
    #
    # `prova-scanout.py`: a schermo intero la lista di disegno ha un elemento
    # e i fotogrammi vanno allo schermo senza ricomporre; il bordo alto si
    # annuncia; il film frena l'inattività da solo. Vista ROSSA col freno
    # tolto dal compositore.
    #
    # `prova-risparmio.py`: il modo risparmio abbassa quello che si DISEGNA
    # e ricorda quello che si è CHIESTO — anche durante — e all'uscita torna
    # lì. Vista ROSSA col verbo `elastico` che scriveva sopra il gradino.
    #
    # `prova-greeter-avvio.py`: il comando fisso della schermata di accesso
    # sceglie il nostro compositore, e ripiega su Hyprland quando non parte.
    # Vista ROSSA col compositore di prima, che usciva sempre con 0.
    for PROVA_EFF in prova-blur-contenuto.py prova-danno-blur.py prova-scanout.py prova-risparmio.py prova-greeter-avvio.py; do
        PE="$ROOT/compositore/$PROVA_EFF"
        if [ ! -x "$PE" ]; then
            skip "$PROVA_EFF non trovata"
        elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
            skip "$PROVA_EFF: saltata da MINERVA_SENZA_ANNIDATE"
        elif [ ! -x "$ROOT/compositore/build-native/minerva-wayland" ]; then
            skip "$PROVA_EFF: manca la build del fork (compositore/costruisci.sh --build-only)"
        else
            USCITA_PE=$(python3 "$PE" 2>&1) && ESI=0 || ESI=1
            if [ "$ESI" -eq 0 ]; then
                ok "$PROVA_EFF: $(printf '%s' "$USCITA_PE" | grep -E '^(ok|durante|TUTTE)' | tail -1 | cut -c1-110)"
            else
                bad "$PROVA_EFF è rossa:"
                printf '%s\n' "$USCITA_PE" | grep -E 'Error|NO |scie' | tail -3 | while IFS= read -r R; do
                    nota "$R"
                done
            fi
        fi
    done

    # ── Trasmettere lo schermo: la conduttura, e cosa lascia ─────────────
    #
    # Le due verifiche che contano non sono «funziona»: sono **niente orfani**
    # e **niente resti**. I segmenti che la conduttura scrive sono fotogrammi
    # dello schermo — password, posta, conti — e due processi rimasti a
    # leggerlo, o due segmenti rimasti su disco, sono un difetto di un'altra
    # gravità rispetto a una trasmissione che non parte.
    #
    # Non costa una sessione annidata: la cattura è in sola lettura (è quello
    # che fa `grim` a ogni schermata), quindi si prova nella sessione vera, ed
    # è più onesto — risponde il compositore vero.
    SPE="$ROOT/compositore/prova-specchio.py"
    if [ ! -x "$SPE" ]; then
        skip "prova-specchio.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "specchio: non siamo in una sessione Wayland"
    else
        USCITA_SP=$(python3 "$SPE" 2>&1) && ESI=0 || ESI=1
        CONTO_SP=$(printf '%s' "$USCITA_SP" | sed -n 's/^  \([0-9]*\) passate.*/\1/p')
        if printf '%s' "$USCITA_SP" | grep -q '^saltata:'; then
            skip "specchio: $(printf '%s' "$USCITA_SP" | sed -n 's/^saltata: //p')"
        elif [ "$ESI" -eq 0 ]; then
            ok "${CONTO_SP:-?} prove della trasmissione dello schermo passate"
        else
            bad "trasmettere lo schermo non è a posto:"
            printf '%s\n' "$USCITA_SP" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── L'inattività: la catena intera ───────────────────────────────────
    #
    # Non un pezzo — quattro, e ognuno si rompe in silenzio:
    #
    #     pannello Energia → demone → shell → compositore
    #
    # Se un anello salta, lo schermo non si blocca più da solo e non c'è
    # nessuna riga rossa da nessuna parte. La prima volta che questa prova è
    # girata, il 1º settembre 2026, ha trovato subito l'anello rotto: la shell
    # mandava le soglie solo dentro due gestori di segnale, e un segnale è
    # un'occasione sola.
    #
    # Costa una sessione annidata intera (circa mezzo minuto), ed è la ragione
    # per cui sta qui in fondo alle prove del compositore e non fra quelle
    # veloci.
    INATT="$ROOT/compositore/prova-inattivita.py"
    if [ ! -x "$INATT" ]; then
        skip "prova-inattivita.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "inattività: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "inattività: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_IN=$(python3 "$INATT" 2>&1) && ESI=0 || ESI=1
        CONTO_IN=$(printf '%s' "$USCITA_IN" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_IN:-?} prove dell'inattività passate (pannello → compositore)"
        else
            bad "la catena dell'inattività è rotta:"
            printf '%s\n' "$USCITA_IN" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── La cornice attorno alla finestra attiva ──────────────────────────
    #
    # Stessa catena a quattro anelli dell'inattività, e gli stessi modi di
    # rompersi in silenzio: il compositore RIFIUTA una riga storta e risponde
    # `no …` su un socket che nessuno legge. Sullo schermo non succede niente,
    # e non succede niente nemmeno quando la cornice è spenta.
    #
    # Metà delle prove sono sui RIFIUTI: un giro di mezzo secondo è un
    # lampeggio davanti agli occhi tutto il giorno, e il modo in cui una
    # guardia sparisce è che qualcuno allarghi i limiti «tanto è un numero».
    # ── I quattro verbi di root della manutenzione ───────────────────────
    #
    # Cancellano roba di sistema: è il posto del progetto dove un difetto costa
    # di più, ed è anche l'unico che una prova normale non può eseguire —
    # l'aiutante si rifiuta di partire se non è root. La prova prende il file
    # VERO, gli sposta le tre cartelle di sistema dentro una temporanea e lo
    # lancia sotto `fakeroot`. Niente tocca la macchina di chi la lancia.
    RADM="$ROOT/scripts/prova-radice-manutenzione.py"
    if [ ! -x "$RADM" ]; then
        skip "prova-radice-manutenzione.py non trovata"
    else
        USCITA_RM=$(python3 "$RADM" 2>&1) && ESI=0 || ESI=1
        CONTO_RM=$(printf '%s' "$USCITA_RM" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_RM:-?} prove dei verbi di root della manutenzione passate"
        else
            bad "i verbi di root della manutenzione non fanno quel che dicono:"
            printf '%s\n' "$USCITA_RM" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    CORN="$ROOT/compositore/prova-cornice.py"
    if [ ! -x "$CORN" ]; then
        skip "prova-cornice.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "cornice: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "cornice: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_CO=$(python3 "$CORN" 2>&1) && ESI=0 || ESI=1
        CONTO_CO=$(printf '%s' "$USCITA_CO" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_CO:-?} prove della cornice passate (pannello → compositore)"
        else
            bad "la catena della cornice è rotta:"
            printf '%s\n' "$USCITA_CO" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Il puntatore, e le finestre che nascono a schermo intero ─────────
    #
    # Due difetti trovati il 5 settembre 2026, tutti e due da Giacomo usando
    # il computer e nessuno dei due preso dalle prove che c'erano:
    #
    #  · il puntatore spariva sulle pagine web e nel terminale — annunciavamo
    #    `cursor-shape-v1` e non lo ascoltava nessuno;
    #  · un gioco non nasceva a schermo intero — la richiesta arriva PRIMA che
    #    la finestra compaia, e alla comparsa non la riguardava nessuno.
    #
    # Sono due prove di REALTÀ: aprono un programma vero dentro un compositore
    # annidato e guardano cosa succede. È il tipo di prova che mancava.
    #  · il tasto destro che «valeva come sinistro» — il compositore non
    #    disegnava i menù dei programmi, e un menù che non compare, agli
    #    occhi, è un tasto che non fa niente;
    #  · la finestra della password che non prendeva la tastiera.
    for NOME in cursore schermo-intero menu fuoco-pannello trascinamento; do
        PRV="$ROOT/compositore/prova-$NOME.py"
        if [ ! -x "$PRV" ]; then
            skip "prova-$NOME.py non trovata"
        elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
            skip "$NOME: non siamo in una sessione Wayland"
        elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
            skip "$NOME: saltata da MINERVA_SENZA_ANNIDATE"
        else
            USCITA_PV=$(python3 "$PRV" 2>&1) && ESI=0 || ESI=1
            if [ "$ESI" -eq 0 ]; then
                ok "$(printf '%s' "$USCITA_PV" | grep -m1 -E 'VERDE|SALTATA' \
                     | sed 's/^VERDE: //')"
            else
                bad "prova-$NOME: rossa"
                printf '%s\n' "$USCITA_PV" | grep -m2 -E 'ROSSO|·' \
                    | while IFS= read -r R; do nota "$R"; done
            fi
        fi
    done

    # ── L'agente delle password, e la sua finestra ───────────────────────
    #
    # Il giro completo non si può provare: di agenti polkit per sessione ce
    # n'è **uno solo**, e provare il nostro vorrebbe dire togliere di mezzo
    # quello della sessione su cui si sta lavorando — cioè lasciare senza
    # finestra della password la macchina di chi la sta usando.
    #
    # Si prova quello che si può, che è dove stanno i difetti che si vedono:
    # che l'agente RIFIUTI e ESCA quando non può registrarsi (se restasse lì,
    # `minerva-dentro-wayland` non avvierebbe nessun ripiego e ogni richiesta
    # di permesso sparirebbe in silenzio), e che la finestra si carichi,
    # parli il protocollo, e se ne vada quando la richiesta finisce.
    # ── Che esista non basta: la sessione deve poterlo TROVARE ──────────
    #
    # Il 3 settembre 2026 questa prova era verde e l'agente non partiva da due
    # giorni. Il file c'era — `permessi/costruisci.sh` lo mette in
    # `~/.local/bin` — ma `start-minerva-wayland.sh` non metteva quella
    # cartella nel PATH, e `minerva-dentro-wayland` lo cerca con `command -v`.
    #
    # Fra «il file esiste» e «il programma parte» c'era il PATH, e la prova
    # guardava solo il primo dei due. È la forma generale del difetto che
    # Giacomo aveva già nominato: dare per buono il pezzo che non si è
    # guardato.
    DOVE_BIN="${MINERVA_BIN:-$HOME/.local/bin}"
    if grep -q 'XDG_BIN_HOME:-\$HOME/\.local/bin' "$ROOT/scripts/start-minerva-wayland.sh" 2>/dev/null; then
        ok "la sessione ha ~/.local/bin nel PATH: minerva-polkit si trova"
    else
        bad "start-minerva-wayland.sh non mette ~/.local/bin nel PATH"
        nota "minerva-polkit sta lì: senza, NESSUNA finestra della password"
    fi

    PERMESSI="$ROOT/permessi/prova-permessi.py"
    if [ ! -x "$PERMESSI" ]; then
        skip "prova-permessi.py non trovata"
    elif [ ! -x "${MINERVA_BIN:-$HOME/.local/bin}/minerva-polkit" ]; then
        skip "permessi: minerva-polkit non installato (permessi/costruisci.sh)"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "permessi: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "permessi: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_PE=$(python3 "$PERMESSI" 2>&1) && ESI=0 || ESI=1
        CONTO_PE=$(printf '%s' "$USCITA_PE" | sed -n 's/^TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_PE:-?} prove dei permessi passate (agente e finestra)"
        else
            bad "l'agente delle password non si comporta come deve:"
            printf '%s\n' "$USCITA_PE" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── XWayland: che Steam e i giochi si aprano davvero ─────────────────
    #
    # Senza XWayland dentro minerva-wayland i programmi che non parlano
    # Wayland non si aprono **affatto** — non male, proprio non compaiono, e
    # senza nessun errore da nessuna parte, perché senza un DISPLAY non c'è
    # niente a cui bussare.
    #
    # La prova apre programmi X11 VERI dentro il compositore annidato, perché
    # le tre trappole di quel pezzo non si vedono altrimenti: il pid che
    # sarebbe lo stesso per tutti, le finestre di servizio che Qt non mappa
    # mai e che finivano nella dock, e la pigrizia — Xwayland deve partire
    # alla prima finestra X11, non all'avvio della sessione.
    XW="$ROOT/compositore/prova-xwayland.py"
    if [ ! -x "$XW" ]; then
        skip "prova-xwayland.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "xwayland: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "xwayland: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_XW=$(python3 "$XW" 2>&1) && ESI=0 || ESI=1
        CONTO_XW=$(printf '%s' "$USCITA_XW" | sed -n 's/^── \([0-9]*\) passate.*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_XW:-?} prove di XWayland passate (programmi X11 veri)"
        else
            bad "i programmi X11 dentro minerva-wayland non vanno come devono:"
            printf '%s\n' "$USCITA_XW" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Gli schermi si cambiano DA VIVI ──────────────────────────────────
    #
    # Prima la pagina Schermi scriveva il file e basta: il compositore lo
    # legge una volta sola, all'avvio, e la risoluzione cambiava al riavvio
    # della sessione. Che non è quello che chiede chi sta guardando uno
    # schermo storto.
    #
    # ── Perché questa gira sul backend HEADLESS ──────────────────────────
    #
    # Perché è l'unica prova che deve poter SPEGNERE e RIACCENDERE uno
    # schermo, e sotto il backend annidato riaccendere blocca il compositore:
    # `wlr_output_commit_state` non torna più, perché deve parlare col
    # compositore ospite e quel dialogo aspetta il ciclo di eventi dentro cui
    # sta girando. Il backend headless non ha nessun ospite — come quello
    # vero — e non tocca lo schermo di nessuno.
    SCH="$ROOT/compositore/prova-schermi-vivi.py"
    if [ ! -x "$SCH" ]; then
        skip "prova-schermi-vivi.py non trovata"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "schermi: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_SCH=$(python3 "$SCH" 2>&1) && ESI=0 || ESI=1
        CONTO_SCH=$(printf '%s' "$USCITA_SCH" | sed -n 's/^── \([0-9]*\) passate.*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_SCH:-?} prove degli schermi da vivi passate"
        else
            bad "gli schermi non si cambiano come devono:"
            printf '%s\n' "$USCITA_SCH" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Le manopole di tastiera e mouse arrivano davvero ─────────────────
    #
    # Il sintomo peggiore di questo pezzo si vede subito e si spiega tardi:
    # **la tastiera dentro il nostro compositore resta americana**. Le
    # accentate non si scrivono, la chiocciola è in un altro posto, e non c'è
    # nessun errore da nessuna parte.
    #
    # La prova non si accontenta della risposta «ok»: chiede a xkb che
    # disposizione ha DAVVERO la tastiera. Sono due cose diverse ogni volta
    # che una disposizione non esiste — ed è proprio il caso in cui una prova
    # sulla nostra copia direbbe verde su una tastiera americana.
    ING="$ROOT/compositore/prova-ingresso.py"
    if [ ! -x "$ING" ]; then
        skip "prova-ingresso.py non trovata"
    elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
        skip "ingresso: non siamo in una sessione Wayland"
    elif [ -n "${MINERVA_SENZA_ANNIDATE:-}" ]; then
        skip "ingresso: saltata da MINERVA_SENZA_ANNIDATE"
    else
        USCITA_ING=$(python3 "$ING" 2>&1) && ESI=0 || ESI=1
        CONTO_ING=$(printf '%s' "$USCITA_ING" | sed -n 's/^── \([0-9]*\) passate.*/\1/p')
        if [ "$ESI" -eq 0 ]; then
            ok "${CONTO_ING:-?} prove dell'ingresso passate (tastiera vera)"
        else
            bad "le manopole di tastiera e mouse non arrivano come devono:"
            printf '%s\n' "$USCITA_ING" | grep '  NO   ' | while IFS= read -r R; do
                nota "$(printf '%s' "$R" | sed 's/^  NO   //')"
            done
        fi
    fi

    # ── Le finestre dell'ospite sono TUTTE nell'elenco che lo tiene vivo ──
    #
    # `app.qml::_valutaSeRestare()` fa uscire il processo quando nessuna delle
    # sue finestre è più costruita. L'elenco che guarda è scritto a mano, e una
    # finestra nuova dimenticata lì dentro fa uscire il processo **mentre quella
    # finestra è aperta sotto le mani di chi la usa**.
    #
    # Si contano i `Loader` e si verifica che ognuno sia nominato.
    APPQML="$ROOT/minerva-shell/app.qml"
    CARICATORI=$(grep -oE '^        id: [a-zA-Z]+' "$APPQML" \
                 | sed 's/.*id: //' | sort -u)
    # Il file si legge tutto su una riga sola (`tr`) prima di cercare: l'elenco
    # cresce di una finestra alla volta e prima o poi va a capo — è successo
    # con la sesta, Manutenzione, e questa guardia si è messa a dire che
    # mancavano TUTTE. Rossa e non cieca, quindi ha fatto il suo mestiere; ma
    # una guardia che accusa sei innocenti la si smette di leggere.
    ELENCO=$(tr '\n' ' ' < "$APPQML" \
             | grep -oE 'var caricatori = \[[^]]*\]' | head -1)
    MANCANTI=""
    for L in $CARICATORI; do
        # Solo gli id che sono davvero dei Loader di finestra: quelli citati
        # dentro un `laFinestra:`.
        if grep -q "laFinestra: $L\.item" "$APPQML"; then
            case "$ELENCO" in
                *"$L"*) ;;
                *) MANCANTI="$MANCANTI $L" ;;
            esac
        fi
    done
    if [ -z "$MANCANTI" ]; then
        ok "ogni finestra dell'ospite è nell'elenco che lo tiene vivo"
    else
        bad "finestre non nominate in _valutaSeRestare():$MANCANTI"
        nota "il processo uscirebbe con quella finestra ancora aperta"
    fi

    # ── Ogni nostra finestra ha una barra del titolo ─────────────────────
    #
    # Hyprland non disegna decorazioni: la barra di una finestra di Minerva sta
    # DENTRO la finestra (`ui/WindowTitleBar.qml`), e chi non la mette non ce
    # l'ha. Non è un difetto grafico — senza barra la finestra non si chiude
    # col mouse, non si trascina per la cima e non si ingrandisce col doppio
    # clic: si chiude solo con Super+C.
    #
    # È successo due volte, alla Custodia e al lettore multimediale, e in tutti
    # e due i casi se n'è accorto Giacomo guardando lo schermo.
    # I nomi si passano separati da NUL e non da spazi: il percorso del
    # progetto contiene uno spazio, e «Minerva Shell» diventerebbe due file
    # inesistenti — che è esattamente come questa guardia si è rotta appena
    # scritta, dicendo che TUTTE le finestre erano senza barra.
    SENZABARRA=$(grep -rlZ '^FloatingWindow {' "$ROOT/minerva-shell" \
                      --include='*.qml' 2>/dev/null \
                 | xargs -0 -r grep -LZ 'Ui.WindowTitleBar' 2>/dev/null \
                 | tr '\0' '\n' | grep -v '/prova-' | sed "s|^$ROOT/||")
    if [ -z "$SENZABARRA" ]; then
        ok "ogni finestra di Minerva ha la sua barra del titolo"
    else
        bad "finestre senza barra del titolo:"
        printf '%s\n' "$SENZABARRA" | while IFS= read -r R; do nota "$R"; done
        nota "si chiuderebbero solo con Super+C"
    fi

    # ── Ogni nostra applicazione ha un nome suo nella dock ────────────────
    #
    # Le applicazioni che vivono dentro `app.qml` dichiarano tutte la stessa
    # classe (`minerva-app`), perché `AppId` è del PROCESSO e non della
    # finestra. L'unica cosa che le distingue è il TITOLO, e la tabella che li
    # traduce sta in `core/Apps.qml::ownApps`.
    #
    # Chi non ha la sua riga lì dentro cade nel prefisso «Minerva · »
    # dell'editor e nella dock si chiama «Editor di testi», con la sua icona.
    # È successo alla Custodia. Non si vede leggendo il codice: si vede
    # guardando la dock.
    APPSQML="$ROOT/minerva-shell/core/Apps.qml"
    SENZANOME=""
    for D in "$ROOT"/desktop/minerva-*.desktop; do
        N=$(basename "$D" .desktop)
        # Due che non sono applicazioni: il blocco schermo e la finestra dei
        # permessi. Non hanno né finestra né posto nella dock — sono superfici
        # layer-shell, che nella dock non compaiono affatto — e il loro
        # `.desktop` esiste per una ragione sola: senza, il portale xdg scrive
        # «App info not found for …» a ogni blocco e a ogni password.
        #
        # `NoDisplay=true` lo dice già nei due file, ed è quello che si
        # potrebbe controllare invece di elencarli qui. Si elencano: `NoDisplay`
        # vuol dire «non nel menu», e ci sono programmi veri che lo mettono.
        [ "$N" = "minerva-blocco" ] && continue
        [ "$N" = "minerva-permessi" ] && continue
        CLS=$(sed -n 's/^StartupWMClass=//p' "$D")
        # Se la classe che dichiara esiste davvero come processo a sé, la
        # strada della classe basta e la tabella non le serve.
        if grep -rqs "pragma AppId $CLS\$" "$ROOT/minerva-shell"/*.qml; then
            continue
        fi
        grep -q "\"$N.desktop\"" "$APPSQML" || SENZANOME="$SENZANOME $N"
    done
    if [ -z "$SENZANOME" ]; then
        ok "ogni applicazione di Minerva si riconosce dal titolo"
    else
        bad "applicazioni senza riga in Apps.qml::ownApps:$SENZANOME"
        nota "nella dock prenderebbero nome e icona dell'editor"
    fi

    # ── Niente ancore dentro il contenuto di uno SpineButton ─────────────
    #
    # `holder`, dentro `ui/SpineButton.qml`, si dimensiona su `childrenRect` e
    # centra già lui il contenuto. Un figlio che si ancora al padre chiude un
    # anello di legami: Qt lo dice in un avviso e poi disegna qualcosa che
    # sembra giusto, quindi non lo si scopre guardando.
    ANELLI=$(grep -rn -A1 'content: ' "$ROOT/minerva-shell" --include='*.qml' \
             | grep 'anchors.centerIn: parent' | head -5)
    if [ -z "$ANELLI" ]; then
        ok "nessuna ancora dentro il contenuto di uno SpineButton"
    else
        bad "anelli di legami in SpineButton:"
        printf '%s\n' "$ANELLI" | while IFS= read -r R; do nota "$R"; done
    fi

    # ── Nessun byte di controllo nei sorgenti ────────────────────────────
    #
    # Un NUL o un 0x1F scritto alla lettera dentro un `.dart` è legale per il
    # compilatore e rende il file **binario** per tutto il resto: `file` dice
    # «data», `grep` non trova più niente, e una modifica cieca col `sed` lo
    # rovina in silenzio. Vanno scritti come sequenze di fuga.
    SPORCHI=$(find "$ROOT/minervad/lib" "$ROOT/minerva-shell" \
                   \( -name '*.dart' -o -name '*.qml' \) -type f \
                   -exec grep -lIP '[\x00-\x08\x0b-\x1f]' {} + 2>/dev/null \
              | head -5)
    if [ -z "$SPORCHI" ]; then
        ok "nessun byte di controllo scritto alla lettera nei sorgenti"
    else
        bad "sorgenti con byte di controllo crudi:"
        printf '%s\n' "$SPORCHI" | while IFS= read -r R; do
            nota "${R#$ROOT/}"
        done
    fi

    # ── Ogni verbo della Custodia che la shell manda, il demone lo conosce ─
    #
    # Due file in due linguaggi che devono dire la stessa parola: se non
    # combaciano il demone non risponde e la finestra resta ferma senza un
    # errore. È lo stesso controllo che si fa già sui verbi del compositore.
    VERBI_SHELL=$(grep -oE '"action": "custodia_[a-z_]+"' \
                       "$ROOT/minerva-shell/core/Ipc.qml" \
                  | sed 's/.*"custodia_/custodia_/; s/"$//' | sort -u)
    ORFANI=""
    for V in $VERBI_SHELL; do
        grep -q "case '$V':" "$ROOT/minervad/lib/ipc/websocket_server.dart" \
            || ORFANI="$ORFANI $V"
    done
    if [ -z "$ORFANI" ]; then
        ok "ogni verbo della Custodia che la shell manda, il demone lo conosce"
    else
        bad "verbi della Custodia che il demone non gestisce:$ORFANI"
    fi

    # ── La prova annidata non deve toccare la sessione vera ──────────────
    #
    # `Quickshell.Hyprland` non cerca Hyprland: legge
    # `HYPRLAND_INSTANCE_SIGNATURE` dall'ambiente, che la prova eredita dalla
    # sessione di Giacomo. Senza toglierla, la shell dentro minerva-wayland
    # manda i suoi comandi al Hyprland VERO — e si crede di provare una
    # scrivania mentre se ne riconfigura un'altra.
    ANNIDATA="$ROOT/compositore/prova-annidata.sh"
    if [ -f "$ANNIDATA" ] \
       && grep -q "^unset HYPRLAND_INSTANCE_SIGNATURE" "$ANNIDATA"; then
        ok "la prova annidata è cieca al Hyprland vero"
    else
        bad "prova-annidata.sh non toglie HYPRLAND_INSTANCE_SIGNATURE"
        nota "la shell della prova comanderebbe la sessione di lavoro"
    fi

    # ── E nemmeno al DEMONE vero, che è la terza porta ────────────────────
    #
    # La più difficile da vedere delle tre, perché non fa niente di
    # spettacolare: la shell dentro il compositore annidato parla col demone
    # sulla porta 11432, che è quello della sessione di fuori. Il 26 agosto
    # 2026 si vedeva a schermo — la scrivania di prova disegnava una barra
    # del titolo per una finestra della sessione VERA — ma la metà che conta
    # è invisibile: **ogni impostazione cambiata durante una prova finiva nel
    # `settings.json` di Giacomo.**
    #
    # Due variabili, e servono tutte e due: la porta perché il demone sia un
    # altro, la cartella perché scriva altrove.
    # E TRE variabili, non due. La terza è quella che ho dimenticato la prima
    # volta, ed è la sola che facesse danno vero: il demone scrive porta e
    # chiave in un file, e lo cerca **in `$XDG_RUNTIME_DIR` prima che nella
    # cartella di configurazione**. Stessa sessione, stessa cartella di
    # runtime: il demone di prova ha scritto la sua porta e la sua chiave
    # sopra quelle del demone di Giacomo, e ogni finestra NUOVA della
    # sessione vera è andata a bussare a un demone che non c'era.
    #
    # `MINERVA_TOKEN_FILE` vince su tutto ed esiste apposta — sta scritto in
    # `canale_segreto.dart`: «serve alle prove, che non devono toccare il
    # file vero di chi sta lavorando».
    MANCA_ISOLAMENTO=""
    if [ -f "$ANNIDATA" ]; then
        grep -q "MINERVA_IPC_PORT" "$ANNIDATA" \
            || MANCA_ISOLAMENTO="$MANCA_ISOLAMENTO MINERVA_IPC_PORT"
        grep -q "MINERVA_CONFIG_DIR" "$ANNIDATA" \
            || MANCA_ISOLAMENTO="$MANCA_ISOLAMENTO MINERVA_CONFIG_DIR"
        grep -q "MINERVA_TOKEN_FILE" "$ANNIDATA" \
            || MANCA_ISOLAMENTO="$MANCA_ISOLAMENTO MINERVA_TOKEN_FILE"
    fi
    if [ -z "$MANCA_ISOLAMENTO" ]; then
        ok "e ha un demone suo, con la sua cartella e il suo file del canale"
    else
        bad "prova-annidata.sh non isola il demone:$MANCA_ISOLAMENTO"
        nota "senza IPC_PORT e CONFIG_DIR, le impostazioni cambiate in una"
        nota "prova finiscono in quelle vere; senza TOKEN_FILE, la prova"
        nota "riscrive porta e chiave della SESSIONE di chi la lancia."
    fi

    # ── La decorazione non si risponde quando arriva ─────────────────────
    #
    # Il programma crea l'oggetto «decorazione» PRIMA della prima commit della
    # sua superficie. Rispondere lì dentro è mandare una configure a una
    # superficie non ancora configurabile, e wlroots non lo segnala: fa
    # `assert`. La prima prova con le barre native è morta così, un secondo
    # dopo l'avvio:
    #
    #     wlr_xdg_surface_schedule_configure: Assertion `surface->initialized'
    #
    # Non basta cercare `initialized`: si controlla che la risposta passi
    # SEMPRE per `decorazione_applica`, cioè che `set_mode` non compaia da
    # nessun'altra parte.
    QUANTE=$(grep -c "wlr_xdg_toplevel_decoration_v1_set_mode" "$SORGENTE")
    if [ "$QUANTE" = "1" ] \
       && grep -q "if (!f->toplevel->base->initialized)" "$SORGENTE" \
       && grep -q "decorazione_applica(f);" "$SORGENTE"; then
        ok "alla decorazione si risponde solo a superficie pronta"
    else
        bad "set_mode fuori da decorazione_applica, o senza il controllo"
        nota "wlroots fa assert e si porta giù tutto lo schermo"
    fi

    # ── Il freno al trascinamento ────────────────────────────────────────
    #
    # Una finestra trascinata sotto il pannello non si riprende più: è il
    # difetto «non hanno la barra e devo chiuderle con super+C», che in Minerva
    # è già costato una volta.
    if grep -q "trattieni(f, &x, &y);" "$SORGENTE"; then
        ok "una finestra non si può trascinare dove non si riprende"
    else
        bad "manca il freno al trascinamento"
        nota "senza, la barra del titolo finisce sotto il pannello"
    fi

    # ── L'ordine dei piani ───────────────────────────────────────────────
    #
    # Sfondo, dock, finestre, barra, blocco schermo. Nella scena chi nasce
    # dopo sta sopra: invertirne due vuol dire una barra che sparisce dietro
    # le finestre, che è un difetto già visto in Minerva.
    # Si guardano solo le righe che CREANO un piano, non ogni volta che il nome
    # di un piano compare. La prima versione cercava il nome dell'enum ovunque,
    # e si è tinta di rosso il giorno in cui una finestra a schermo intero ha
    # cominciato a farsi riadottare dal piano TOP: codice giusto, guardia che
    # contava una cosa diversa da quella che diceva di controllare.
    ORDINE=$(grep -o "m\.piano\[ZWLR_LAYER_SHELL_V1_LAYER_[A-Z]*\] =\|m\.finestre = wlr_scene_tree_create" "$SORGENTE" \
             | sed 's/m\.piano\[ZWLR_LAYER_SHELL_V1_LAYER_//; s/\] =//; s/m\.finestre = .*/FINESTRE/' | tr '\n' ' ')
    if [ "$ORDINE" = "BACKGROUND BOTTOM FINESTRE TOP OVERLAY " ]; then
        ok "i piani nascono nell'ordine giusto (sfondo → blocco schermo)"
    else
        bad "l'ordine dei piani è cambiato: $ORDINE"
        nota "atteso: BACKGROUND BOTTOM FINESTRE TOP OVERLAY"
    fi

    # ── Il socket non si chiama wayland-0 ────────────────────────────────
    #
    # `wl_display_add_socket_auto` prende il primo `wayland-N` libero, che in
    # una sessione Hyprland è `wayland-0`: cioè il nome a cui si collega
    # qualunque programma avviato senza `WAYLAND_DISPLAY`. Un compositore di
    # prova che se lo prende è una trappola.
    #
    # Si escludono i commenti, o questa prova fallirebbe per il commento che
    # spiega perché non la si usa — che è il modo più stupido di avere una
    # prova rossa, e ci è successo scrivendola.
    if grep -vE '^[[:space:]]*(//|\*)' "$SORGENTE" \
            | grep -q "wl_display_add_socket_auto"; then
        bad "il compositore prende il primo wayland-N libero"
        nota "una prova non deve poter rubare wayland-0 alla sessione vera"
    elif grep -q '"minerva-%d"' "$SORGENTE"; then
        ok "il socket si chiama minerva-N, non wayland-N"
    else
        bad "non trovo il nome del socket"
    fi

    # ── Si installa per rinomina, mai `cp` sul posto ─────────────────────
    #
    # `cp` TRONCA il file e lo riempie: se qualcuno sta eseguendo quel
    # binario, le sue pagine di codice diventano spazzatura mentre le esegue.
    COSTRUISCI="$ROOT/compositore/costruisci.sh"
    if grep -qE '^[[:space:]]*cp[[:space:]]+"\$BIN"[[:space:]]+"\$DOVE/minerva-wayland"' "$COSTRUISCI"; then
        bad "costruisci.sh copia il binario SUL POSTO"
        nota "si scrive di fianco e si rinomina, o si tronca il codice in esecuzione"
    elif grep -q 'mv "\$DOVE/.minerva-wayland.nuovo" "\$DOVE/minerva-wayland"' "$COSTRUISCI" ||
         grep -Fq 'mv -f "$STAGING/$nome" "$DOVE/$nome"' "$COSTRUISCI"; then
        ok "il compositore si installa per rinomina"
    else
        bad "costruisci.sh non installa più per rinomina"
    fi
fi

# ── 4. Gli script ──────────────────────────────────────────────────────────
head_ "Script"
BAD_SCRIPTS=0
# Tutti gli script, non un elenco scritto a mano. L'elenco a mano c'era, e il
# difetto dell'elenco a mano è che uno script nuovo non ci finisce mai: è
# rimasto fuori `minerva-demone`, che è il guardiano, cioè il pezzo che se si
# rompe porta giù tutto. Ora si guarda dentro: se la prima riga dichiara una
# shell, si controlla.
for f in "$ROOT"/scripts/*; do
    [ -f "$f" ] || continue
    head -1 "$f" | grep -q '^#!.*\(sh\|bash\)$' || continue
    if head -1 "$f" | grep -q bash; then
        bash -n "$f" 2>/dev/null || { bad "$(basename "$f"): sintassi"; BAD_SCRIPTS=1; }
    else
        sh -n "$f" 2>/dev/null || { bad "$(basename "$f"): sintassi"; BAD_SCRIPTS=1; }
    fi
done
[ "$BAD_SCRIPTS" -eq 0 ] && ok "tutti gli script sono sintatticamente validi"

# ── La sessione su wlroots non chiama niente di Hyprland ──────────────────
#
# È il cuore del distacco, e va verificato invece che sperato. La catena di
# avvio è: `start-minerva-wayland.sh` → `minerva-dentro-wayland` → i due
# guardiani, i posti, l'autostart. Se una di quelle righe chiama un `hypr*`
# senza rete, la sessione «indipendente» dipende.
#
# Il 2 settembre 2026, dopo che Giacomo ha provato «Minerva (recupero)» dal
# login, sono andati via anche i tre ripieghi che restavano:
#
#   · l'agente polkit degli altri ambienti (il nostro c'è ed è provato);
#   · `hyprctl notify` in `minerva-interfaccia` (il compositore ha il suo
#     verbo `messaggio`);
#   · la voce di sessione e la configurazione di Hyprland.
#
# Resta UNA riga in tutta la catena, e non è una dipendenza: il NOME
# «hyprland» nell'elenco degli ambienti di `minerva-autostart`, che serve a
# far partire i programmi il cui `.desktop` dice `OnlyShowIn=Hyprland`. È una
# stringa da confrontare, non un programma da eseguire, e toglierla vorrebbe
# dire che quei programmi smettono di partire senza dirlo.
#
# Il conto è per file: se cresce, qualcuno ne ha aggiunta una.
CATENA_ATTESA="scripts/minerva-dentro-wayland=0
scripts/minerva-interfaccia=0
scripts/minerva-autostart=1
scripts/start-minerva-wayland.sh=0
scripts/minerva-demone=0
scripts/minerva-posti.sh=0"
CATENA_ROTTA=""
# `grep -c` stampa il conto ED ESCE CON 1 quando è zero. Scritto
# `$(grep -c … || echo 0)` il risultato diventa «0\n0» — due righe — e il
# confronto fallisce su ogni file pulito: la guardia diceva rosso proprio sui
# file che stava certificando. Preso da sé stessa il 2 settembre 2026.
printf '%s\n' "$CATENA_ATTESA" | while IFS== read -r F ATTESI; do
    VERI=$(grep -cE "^[^#]*hypr" "$ROOT/$F" 2>/dev/null) || VERI="$VERI"
    [ -n "$VERI" ] || VERI=0
    [ "$VERI" = "$ATTESI" ] || printf '%s: %s righe invece di %s\n' "$F" "$VERI" "$ATTESI"
done > /tmp/minerva-catena.txt
if [ -s /tmp/minerva-catena.txt ]; then
    bad "la sessione su wlroots ha righe di Hyprland che non ci aspettavamo:"
    while IFS= read -r R; do nota "$R"; done < /tmp/minerva-catena.txt
    nota "ogni riga che resta deve essere un RIPIEGO dietro un «command -v»"
    nota "o un controllo di esistenza, mai una chiamata secca."
else
    ok "la catena di avvio su wlroots non chiama niente di Hyprland"
fi
rm -f /tmp/minerva-catena.txt

# ── Sostituzioni di comando dentro i documenti-qui ─────────────────────────
#
# Un documento-qui col delimitatore SENZA virgolette espande tutto: le
# variabili — che spesso è il motivo per cui lo si vuole così — ma anche le
# sostituzioni di comando. E un documento-qui **non ha commenti**: una riga che
# comincia con «#» è testo per il file che si sta scrivendo, non per la shell.
#
# Quindi un nome citato fra backtick dentro uno di quei commenti è un comando,
# eseguito mentre si scrive il file. In `minerva-greetd` succedeva durante
# «sudo minerva-greetd installa», cioè **da root**: quattro «comando non
# trovato» in mezzo a un'installazione riuscita, e quattro buchi nel file
# scritto al posto dei nomi citati. Il 23 agosto 2026, e li avevo scritti io.
#
# Non è solo sporcizia: è una sostituzione di comando che nasce da testo, ed è
# la stessa forma del difetto dei nomi di file coi backtick nella shell.
GUARDIA_QUI=$(for f in "$ROOT"/scripts/*; do
    [ -f "$f" ] || continue
    head -1 "$f" | grep -q '^#!.*\(sh\|bash\)$' || continue
    awk '
    {
        if (dentro) {
            if ($0 == fine) { dentro = 0; next }
            if (index($0, "\140") > 0)
                printf "%s:%d\n", FILENAME, NR
            next
        }
        if (match($0, /<<-?[A-Za-z_][A-Za-z0-9_]*/)) {
            e = substr($0, RSTART, RLENGTH); sub(/<<-?/, "", e)
            dentro = 1; fine = e
        }
    }' "$f"
done)
if [ -z "$GUARDIA_QUI" ]; then
    ok "nessun comando si esegue di nascosto dentro un documento-qui"
else
    bad "sostituzione di comando dentro un documento-qui non quotato:"
    printf '%s\n' "$GUARDIA_QUI" | while read -r r; do nota "$r"; done
    nota "in un documento-qui le righe con # sono TESTO, non commenti:"
    nota "quello che sta fra i due segni gravi viene eseguito."
    BAD_SCRIPTS=1
fi

# Nessun percorso assoluto negli script: lo stesso controllo che le prove del
# demone fanno sul codice Dart. L'unica eccezione è il modello della sessione,
# che ha un segno da sostituire e non un percorso.
#
# Si cerca «/home/» e non un nome preciso: un percorso assoluto dentro la
# cartella di casa di CHIUNQUE è un percorso che funziona su un computer solo.
# Si escludono le prove stesse (che quel testo lo devono nominare per cercarlo)
# e i due strumenti di prova, che non finiscono in mano a nessuno.
#
# I commenti sono esclusi: un esempio scritto in un commento
# («MINERVA_FILES_PATH=/home/tizio/Immagini») spiega, non esegue.
STRAY=$(grep -rn "/home/" "$ROOT/scripts" "$ROOT/minerva-shell" 2>/dev/null \
        | grep -v "prove.sh\|prova-clic.py\|prova-tasti.py" \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//|\*)' || true)
if [ -z "$STRAY" ]; then
    ok "nessun percorso scritto a mano in script e shell"
else
    bad "percorsi assoluti rimasti:"
    echo "$STRAY" | sed "s|$ROOT/||" | head -10
fi

# ── 4-bis. Le traduzioni ───────────────────────────────────────────────────
#
# `Strings.t(chiave)` non fallisce mai: se la chiave non c'è ripiega
# sull'inglese, e se non c'è nemmeno lì **restituisce la chiave**. Vuol dire
# che una traduzione dimenticata non dà nessun errore: mostra `showCheatsheet`
# a schermo, e ce ne si accorge guardando. Due domande che una macchina sa
# fare e nessuno si ricorda di farsi.
head_ "Traduzioni"
if command -v python3 >/dev/null 2>&1; then
    OUT=$(python3 - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
s = open(os.path.join(root, 'minerva-shell/core/Strings.qml'),
         encoding='utf-8').read()
b = re.search(r'readonly property var _ui:\s*\(\{(.*?)\n    \}\)', s, re.S).group(1)
def rami(nome):
    m = re.search(r'"%s":\s*\{(.*?)\n\s{8}\}' % nome, b, re.S)
    return set(re.findall(r'"(\w+)"\s*:', m.group(1)))
it, en = rami('it'), rami('en')
guai = []
for solo, dove in ((it - en, 'inglese'), (en - it, 'italiano')):
    for k in sorted(solo):
        guai.append(f"manca in {dove}: {k}")

usate = set()
for d, _, fs in os.walk(os.path.join(root, 'minerva-shell')):
    for f in fs:
        if f.endswith(('.qml', '.js')):
            t = open(os.path.join(d, f), encoding='utf-8', errors='ignore').read()
            usate |= set(re.findall(r'\.t\(\s*"(\w+)"', t))
for k in sorted(usate - it - en):
    guai.append(f"chiesta dal codice ma inesistente: {k}")
print('\n'.join(guai))
PY
)
    if [ -z "$OUT" ]; then
        ok "italiano e inglese dicono le stesse cose, e il codice non chiede chiavi che non esistono"
    else
        bad "traduzioni:"
        echo "$OUT" | head -10
    fi
else
    skip "python3 non installato"
fi

# ── 5. L'interfaccia ───────────────────────────────────────────────────────
head_ "Interfaccia (QML)"
if [ "$MODE" = "veloce" ]; then
    skip "modalità veloce: la prova che apre finestre è saltata"
elif [ -z "${WAYLAND_DISPLAY:-}" ]; then
    skip "fuori da una sessione Wayland: non c'è dove disegnare"
elif ! command -v qs >/dev/null 2>&1; then
    skip "quickshell non installato"
else
    # Si provano i due programmi STACCATI e non la shell: sono processi a sé,
    # si aprono e si chiudono senza disturbare la barra di chi sta lavorando.
    # È esattamente il motivo per cui sono stati staccati — prima una prova
    # come questa avrebbe voluto dire riavviare l'ambiente.
    # ── Trovare LA finestra giusta, e nessun'altra ───────────────────────
    #
    # Due errori, tutti e due già costati una finestra chiusa sotto le mani di
    # chi stava lavorando.
    #
    # 1. `pgrep -f "$SEGNO" | head -1` prende il processo PIÙ VECCHIO. Se il
    #    gestore file era già aperto — cosa normale, ci si lavora dentro — la
    #    prova leggeva i log della SUA finestra invece di quella appena
    #    lanciata (quindi diceva «a posto» senza provare niente) e alla fine
    #    gliela chiudeva.
    #
    # 2. `pgrep -f` corrisponde anche ai COMANDI CHE STANNO CERCANDO: la
    #    sottoshell che esegue `pgrep -f filemanager[.]qml` ha quel testo nella
    #    propria riga di comando. Sono processi effimeri, con pid diverso a
    #    ogni chiamata, e chi li scambia per «la finestra nuova» finisce per
    #    uccidere qualcos'altro.
    #
    # Quindi niente `pgrep`: si richiede che la riga di comando COMINCI con
    # `qs`, cosa che una grep o una sottoshell non fanno mai. Poi si segna chi
    # c'era prima e si tiene solo chi è comparso dopo.
    # ── Solo le finestre che ho aperto IO ──────────────────────────────────
    #
    # Le prove aprono il gestore file, le Impostazioni, Anteprima — e poi le
    # chiudono. Finché la macchina era libera bastava distinguerle per
    # percorso; ma queste prove girano mentre Giacomo lavora, e il gestore
    # file che ha aperto lui gira dallo stesso percorso.
    #
    # Riconoscerle per «chi c'era prima» non basta: è un confronto che si può
    # sbagliare in silenzio, e sbagliarlo vuol dire chiudere in faccia a
    # qualcuno la finestra che stava usando — senza salvargli niente.
    #
    # Quindi le mie le MARCHIO alla nascita, e prima di chiuderne una vado a
    # rileggere la marca in `/proc/<pid>/environ`. Una finestra non marcata non
    # si tocca, qualunque cosa dica il resto della prova.
    finestre_qs() {
        ps -eo pid,args --no-headers \
            | awk -v f="$1" '$2 == "qs" && index($0, f) { print $1 }'
    }

    e_mia() {
        tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null \
            | grep -q '^MINERVA_PROVA=1$'
    }

    chiudi_se_mia() {
        if e_mia "$1"; then
            kill "$1" 2>/dev/null
        else
            bad "mi stavo per prendere una finestra non mia (pid $1): lasciata stare"
        fi
    }

    # Le sei app si aprono con L'AMBIENTE VERO, quello che usano gli script in
    # `scripts/minerva-*`: disegnano col processore e non con la scheda video.
    # Aprirle qui in un modo e nella vita in un altro vorrebbe dire provare una
    # cosa e consegnarne un'altra — e la differenza non è teorica: senza scheda
    # video `layer.enabled` e `QtQuick.Effects` non danno errore, fanno SPARIRE
    # l'oggetto. Il ritratto tondo delle Impostazioni è sparito così, e nessuna
    # di queste prove se ne sarebbe accorta.
    #
    # Shell, blocco schermo e schermata di accesso NON passano di qui e restano
    # sulla scheda video: per questo l'ambiente si include dentro una
    # SOTTOSHELL, e non qui in mezzo. Incluso qui esporterebbe la variabile a
    # tutto il resto del file — le prove della shell, quelle del greeter,
    # quelle del blocco — e le proverebbe tutte in un modo in cui non girano
    # mai.
    # ── E quanto pesa ────────────────────────────────────────────────────
    #
    # Il terzo argomento è il TETTO in megabyte di memoria privata. Non è un
    # numero a caso: è quello misurato il 18 agosto 2026 più un quinto di
    # margine, e serve a prendere le ricadute grosse, non a inseguire i tre
    # megabyte di rumore.
    #
    # La ricaduta grossa che questa prova esiste per prendere è una sola e
    # concreta: se un giorno una app torna a disegnare con la scheda video
    # — perché qualcuno ha tolto una riga da uno script, o ne ha aggiunto uno
    # nuovo dimenticandola — si porta dietro 38 MB e nessuno se ne accorge.
    # Trentotto megabyte non danno errore, non si vedono, e non li nota
    # nessuno finché non li nota Giacomo.
    #
    # Si misura la PRIVATA e non l'RSS né il PSS: l'RSS conta anche le
    # librerie condivise, che stanno in memoria una volta sola per tutta la
    # macchina, e il PSS di una riga cambia quando apri un'altra finestra.
    # Trappola già presa in questo progetto, l'11 agosto.
    privata_mb() {
        awk '/^Private_(Clean|Dirty):/ {s+=$2} END {printf "%d", s/1024}' \
            "/proc/$1/smaps_rollup" 2>/dev/null || echo 0
    }

    # ── Siamo dentro una sessione Minerva, o fuori? ──────────────────────
    #
    # Non è una curiosità: cambia quali righe hanno un significato.
    #
    # Lanciando `prove.sh` da un'altra scrivania — COSMIC, GNOME, un terminale
    # su un'altra sessione — succedono due cose, e nessuna delle due è un
    # difetto di Minerva:
    #
    #  · ogni app scrive «$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot
    #    connect to hyprland», perché lì Hyprland non c'è. Misurato il 30
    #    agosto 2026: SEI righe rosse, tutte per questo;
    #  · i tetti di memoria saltano di dieci-quindici MB, perché sono stati
    #    misurati DENTRO una sessione Minerva e fuori cambiano il tema delle
    #    icone, il portale e il compositore che tiene le superfici.
    #
    # Tredici righe rosse su una scrivania sana. È esattamente ciò che questo
    # progetto ha già pagato tre volte in una sera — `polkit-kde-auth` cercato
    # per nome, `prova-blocco.py`, `prova-xwayland.py` — e la regola scritta
    # allora vale qui: **se una cosa non si può provare, si SALTA dicendolo,
    # mai rosso.** Uno strumento che dà per morto ciò che è vivo manda a
    # cercare un guasto che non esiste.
    # ── E una seconda domanda, che fino a stasera era la stessa ──────────
    #
    # «Sono dentro Minerva?» e «c'è Hyprland?» erano una domanda sola, perché
    # l'unica sessione Minerva era Hyprland. Da quando Giacomo lavora dentro
    # minerva-wayland non lo sono più: `Quickshell.Hyprland` avvisa
    # «$HYPRLAND_INSTANCE_SIGNATURE is unset» in OGNI app, per sempre, e non
    # è un difetto — è la verità, detta da quickshell e non da noi.
    #
    # Tenerle unite costava caro in un modo preciso: sette app rosse per la
    # stessa riga innocua, cioè il controllo «si apre senza un solo avviso»
    # ridotto a rumore che nessuno guarda più. Un avviso che c'è sempre non
    # avvisa di niente.
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        HYPRLAND_CE=1
    else
        HYPRLAND_CE=0
    fi

    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ -n "${MINERVA_CANALE:-}" ]; then
        DENTRO_MINERVA=1
    else
        DENTRO_MINERVA=0
        skip "non sei dentro una sessione Minerva: gli avvisi su Hyprland e i"
        nota "tetti di memoria si saltano — sarebbero rossi per l'ambiente,"
        nota "non per il codice. Per il conto vero, lancia queste prove"
        nota "dentro Minerva."
    fi

    prova_finestra() {
        NOME="$1"; FILE="$2"; TETTO="${3:-0}"
        PERCORSO="$ROOT/minerva-shell/$FILE"
        PRIMA=" $(finestre_qs "$PERCORSO" | tr '\n' ' ')"
        (
            . "$ROOT/scripts/minerva-ambiente-app"
            MINERVA_PROVA=1 qs -d -p "$PERCORSO"
        ) >/dev/null 2>&1
        sleep 6
        PID=""
        for p in $(finestre_qs "$PERCORSO"); do
            case "$PRIMA" in
                *" $p "*) ;;
                *) PID="$p"; break ;;
            esac
        done
        if [ -z "$PID" ]; then
            # ── E si dice PERCHÉ ────────────────────────────────────────
            #
            # «Non si è aperto» manda a cercare un difetto nel QML. Il 31
            # agosto 2026 la causa era `module "QtMultimedia" is not
            # installed` — un pacchetto mancante, che dal messaggio non si
            # poteva nemmeno sospettare. Il lancio di sopra è `-d`, cioè
            # staccato, e la sua uscita se ne va nel nulla: si rilancia
            # attaccati giusto il tempo di raccogliere l'errore.
            PERCHE=$( ( . "$ROOT/scripts/minerva-ambiente-app"
                        MINERVA_PROVA=1 timeout 10 qs -p "$PERCORSO" 2>&1 ) \
                      | grep -E "ERROR|error:" | head -3)
            bad "$NOME non si è aperto"
            if [ -n "$PERCHE" ]; then
                printf '%s\n' "$PERCHE" | while IFS= read -r R; do
                    nota "$(printf '%s' "$R" | sed 's/^[[:space:]]*//')"
                done
            fi
            return
        fi
        # Gli avvisi «Demone non raggiungibile» all'avvio sono attesi: le
        # prime richieste partono prima che il collegamento sia in piedi, e
        # vengono rifatte appena c'è. Il resto sono difetti.
        # «Got openwindow for workspace … which was not previously tracked»
        # lo dice quickshell, non noi: la sua copia delle scrivanie di
        # Hyprland è ancora vuota quando la finestra di prova si apre. Non
        # dipende dal nostro codice e non si può togliere dal nostro codice.
        NOISE=$(qs log --pid "$PID" 2>/dev/null \
                | grep -E "WARN|ERROR|error:" \
                | grep -v "Demone non raggiungibile" \
                | grep -v "host portal" \
                | grep -v "not previously tracked" \
                | grep -v "VDPAU")
        # «Non trovo Hyprland» è la verità e non un difetto ogni volta che
        # Hyprland davvero non c'è — fuori da Minerva, e dentro
        # minerva-wayland. La condizione guarda HYPRLAND, non Minerva: era la
        # stessa domanda finché l'unica sessione Minerva era Hyprland, e ha
        # smesso di esserlo il 31 agosto 2026.
        if [ "$HYPRLAND_CE" = "0" ]; then
            NOISE=$(printf '%s\n' "$NOISE" \
                    | grep -v "HYPRLAND_INSTANCE_SIGNATURE is unset" \
                    | grep -v "quickshell.hyprland.ipc" \
                    | grep -v "quickshell.io.socket" \
                    | sed '/^$/d')
        fi
        if [ -z "$NOISE" ]; then
            ok "$NOME si apre senza un solo avviso"
        else
            bad "avvisi QML all'apertura di $NOME:"
            echo "$NOISE" | head -10
        fi
        if [ "$TETTO" -gt 0 ]; then
            PESO=$(privata_mb "$PID")
            if [ "$DENTRO_MINERVA" = "0" ]; then
                skip "$NOME pesa $PESO MB (tetto $TETTO) — non confrontabile"
                nota "fuori da una sessione Minerva: tema delle icone, portale"
                nota "e compositore sono altri, e il numero cambia da solo."
            elif [ "$PESO" -le "$TETTO" ]; then
                ok "$NOME pesa $PESO MB (tetto $TETTO)"
            else
                bad "$NOME pesa $PESO MB, oltre il tetto di $TETTO"
                echo "    Se sono una quarantina in più, quasi certamente"
                echo "    quella app è tornata a disegnare con la scheda video:"
                echo "    controlla che scripts/minerva-* includa"
                echo "    scripts/minerva-ambiente-app."
            fi
        fi
        chiudi_se_mia "$PID"
        sleep 1
    }

    MINERVA_FILES_PATH="$HOME" prova_finestra "il gestore file" filemanager.qml 110
    MINERVA_SETTINGS_SECTION=appearance prova_finestra "le Impostazioni" settings.qml 120

    # ── Le tre che vivono dentro l'ospite ────────────────────────────────
    #
    # Si aprono da `app.qml` e NON da `monitor.qml`, `editor.qml`,
    # `calcolatrice.qml`. Da quando le quattro app stanno in un processo solo,
    # gli script spediti passano tutti per l'ospite; quei tre file sono in
    # `.attic/2026-08-23-ingressi-vecchi/`.
    #
    # Puntare qui era il difetto: queste prove erano verdi su una strada che
    # non prende nessuno, e la strada vera — quella che apre le finestre a
    # Giacomo — non era provata da niente. È lo stesso inganno delle guardie
    # che contano una cosa diversa da quella che dicono di controllare.
    #
    # I tetti sono rimisurati sull'ospite (23 agosto 2026) e non ereditati:
    # dentro l'ospite ogni app porta con sé il pavimento di Qt, quindi i
    # numeri vecchi non valevano più nemmeno come ordine di grandezza.
    # Misurati oggi: Attività 78, Editor 89, Calcolatrice 67.
    MINERVA_APP_APRI=attivita     prova_finestra "il gestore attività" app.qml 95
    MINERVA_APP_APRI=editor       prova_finestra "l'editor di testi"   app.qml 108
    MINERVA_APP_APRI=calcolatrice prova_finestra "la calcolatrice"     app.qml 82
    MINERVA_APP_APRI=custodia     prova_finestra "la Custodia"         app.qml 95
    # Manutenzione apre e SUBITO chiede l'inventario, che sono decine di
    # migliaia di file letti da `du`: se questa prova diventa lenta è quello,
    # non la finestra. Tetto misurato il 9 settembre 2026.
    MINERVA_APP_APRI=manutenzione prova_finestra "Manutenzione"         app.qml 100
    # Il Terminale porta con sé una shell VERA (`minerva-pty` → zsh) e il
    # motore in un processo suo: qui si pesa la finestra; il motore fa 6 MB
    # a parte. Misurato il 15 settembre 2026 con `vim` aperto: 85 MB.
    MINERVA_APP_APRI=terminale    prova_finestra "il Terminale"         app.qml 104

    # Il lettore multimediale è l'app più recente ed era l'unica senza prova.
    # Misurato oggi: 112 MB — il più pesante di tutti, ed è la ragione in più
    # per averlo sotto controllo. Il grosso sono i decodificatori, che si
    # aprono al primo file e non si contano nella finestra vuota: se un giorno
    # questo numero cresce di colpo, è quello il posto dove guardare.
    prova_finestra "il lettore multimediale" minervamedia.qml 134
    # Anteprima si apre CON un'immagine: aperta vuota mostrerebbe il cartello
    # «nessuna immagine» e non proverebbe niente di quello che fa davvero —
    # caricare un file, misurarlo, chiedere la cartella al demone.
    PROVINO=$(ls "$ROOT/minerva-shell/assets/wallpapers"/*.png 2>/dev/null | head -1)
    MINERVA_VIEWER_PATHS="$PROVINO" prova_finestra "Anteprima" viewer.qml 110

    # ── Prove unitarie dell'interfaccia ──────────────────────────────────
    #
    # Le prove qui sopra guardano solo che una finestra si apra senza avvisi:
    # è poco, ed era tutto quello che c'era per 29.000 righe di QML. Questa
    # invece prova COSA FA un pezzo di interfaccia — la schermata di accesso
    # davanti ai messaggi di greetd — emettendo i messaggi a mano.
    #
    # Non usa `Qt.exit`, che in Quickshell non chiude il processo: si legge
    # l'esito dall'uscita e si spegne col timeout. Vale la pena saperlo prima
    # di scriverne un'altra.
    prove_qml() {
        NOME="$1"; FILE="$2"
        USCITA=$(timeout 40 qs -p "$ROOT/minerva-shell/$FILE" 2>&1 \
                 | sed 's/\x1b\[[0-9;]*m//g')
        if echo "$USCITA" | grep -q "TUTTE PASSATE"; then
            QUANTE=$(echo "$USCITA" | sed -n 's/.*TUTTE PASSATE (\([0-9]*\)).*/\1/p')
            ok "$QUANTE prove $NOME passate"
            # Le prove che si saltano da sole vanno DETTE, o una prova che non
            # ha provato niente si confonde con una che ha provato tutto.
            echo "$USCITA" | grep -- "  --   " | sed 's/^.*--   /       · saltata: /'
        else
            bad "prove $NOME fallite:"
            echo "$USCITA" | grep -E "NO |FALLITE|ERROR" | head -10
        fi
    }

    prove_qml "della schermata di accesso" prove-greeter.qml
    # Col nome di sessione suo: il file delle notifiche del blocco non deve
    # poter finire nella cartella della sessione VERA (la prova lo spegne
    # comunque per prima cosa, ma una rete in più qui costa una parola).
    MINERVA_SESSIONE=prove-notifiche prove_qml "delle notifiche sul blocco" prove-notifiche-blocco.qml
    # ── E queste si lanciano con MINERVA_CANALE ──────────────────────────
    #
    # Senza, `Compositore._due()` prenderebbe il ramo di Hyprland e ogni
    # comando della prova finirebbe alla scrivania VERA di chi le sta
    # lanciando. Il percorso non deve esistere: serve solo la variabile.
    MINERVA_CANALE=/non/esisto prove_qml "del canale col compositore" prove-canale.qml
    prove_qml "del lettore multimediale"   prove-media.qml
    prove_qml "del volume"                 prove-audio.qml
    prove_qml "delle finestre"             prove-finestre.qml
    prove_qml "della calcolatrice"         prove-calcolatrice.qml
    # Il servizio PAM lo sceglie `minerva-blocca`, non questa riga: così la
    # prova prova quello che il blocco userebbe davvero.
    MINERVA_PAM="$("$ROOT/scripts/minerva-blocca" --quale-pam 2>/dev/null)" \
        prove_qml "del blocco schermo"         prove-blocco.qml

    # ── E ora si rimette a posto il contatore di faillock ──────────────────
    #
    # La prova qui sopra manda a PAM una password inventata: è l'unico modo di
    # verificare che la catena arrivi fino in fondo senza conoscere quella
    # vera. Ma PAM non sa che è una prova, e la conta come tentativo fallito.
    #
    # Il contatore è UNO PER UTENTE e condiviso fra tutti i servizi: quel
    # tentativo si somma verso `sudo` e verso il login, che su Arch bloccano a
    # TRE. Cioè: tre `prove.sh` di fila e la macchina smette di accettare la
    # tua password — non nel blocco schermo, che ha soglie sue, ma nel
    # terminale. È successo il 17 agosto 2026, e non si capisce guardando:
    # sembra che la password sia sbagliata.
    #
    # Non serve root: il file del contatore è dell'utente.
    if command -v faillock >/dev/null 2>&1; then
        faillock --user "$USER" --reset >/dev/null 2>&1 \
            && ok "contatore di faillock rimesso a zero dopo la prova"
    fi
    # Prova la luce notturna FINO AL COMPOSITORE, che è l'unico anello che si
    # era rotto: il file dello shader nasceva lo stesso, e guardando la
    # cartella sembrava tutto a posto.
    # ── E questa vuole un compositore vero, non solo il demone ───────────
    #
    # `prove-luce.qml` verifica l'anello FINO AL COMPOSITORE, ed è il punto
    # del suo valore: il 17 agosto 2026 il file dello shader nasceva
    # regolarmente e nessuno lo diceva a Hyprland, quindi guardando la
    # cartella sembrava tutto a posto. Per verificarlo chiede
    # `hyprctl getoption`, e fuori da una sessione Minerva quella domanda non
    # ha nessuno a cui essere fatta: due righe rosse che non parlano del
    # codice.
    #
    # Si salta DICENDOLO, e a voce alta: un banco che smette di provare in
    # silenzio è il modo in cui una prova muore senza che nessuno se ne
    # accorga — è scritto nel banco stesso, ed è giusto.
    if [ "$DENTRO_MINERVA" = "1" ]; then
        prove_qml "della luce notturna"        prove-luce.qml
    else
        skip "prove della luce notturna SALTATE: chiedono al compositore"
        nota "(«hyprctl getoption»), e qui fuori non risponde nessuno."
        nota "Sono l'unico anello che si era davvero rotto: rilanciale"
        nota "dentro una sessione Minerva prima di fidarti di questo verde."
    fi
    prove_qml "delle animazioni"          prove-animazioni.qml
    prove_qml "della scrivania"            prove-scrivania.qml

    # ── La shell torna quando il demone riparte ───────────────────────────
    #
    # Il guasto del 31 agosto 2026, e non si prova con un `prove_qml` perché
    # ha bisogno di un demone da UCCIDERE e da rimettere in piedi.
    #
    # Cosa proteggeva, in una riga: se questa prova fallisce, la scrivania
    # resta senza dock e senza menù delle applicazioni la prossima volta che
    # il demone cade — e non lo dice nessuno.
    #
    # Le due cause erano una per parte: nel demone un errore di scrittura che
    # non tornava a chi aveva scritto e usciva con 255; nella shell un `Socket`
    # di Quickshell che, fallito una volta, non si riusa più — e la
    # riconnessione era costruita tutta sul riusarne uno solo.
    printf '\n'
    if "$ROOT/scripts/prova-riconnessione.sh" > /tmp/minerva-ricon.log 2>&1; then
        ok "la shell torna da sola quando il demone riparte"
    else
        bad "la shell NON torna quando il demone riparte:"
        grep -E "NO |aggancio|non è partito" /tmp/minerva-ricon.log | head -6
    fi

    # ── E quanto ci mette ad agganciarlo la PRIMA volta ───────────────────
    #
    # È la stessa coppia shell/demone, guardata dall'altro capo: non «torna
    # dopo che è caduto» ma «quanto aspetta quello che non è ancora nato».
    # All'accesso partono insieme e la shell è più svelta, quindi bussa a un
    # socket che non c'è; con l'attesa che raddoppia (120, 240, 480, 960,
    # 1920 ms) può restare ferma più di un secondo con tutto già pronto da
    # tutte e due le parti.
    #
    # Misurato: 1476 ms col difetto, 56 ms senza. Sul registro della sessione
    # del 31 agosto 2026 questo è metà del buco fra la scrivania disegnata
    # (0,624 s) e la dock comparsa (4,666 s) — cioè metà dei «dieci secondi
    # per avviarsi» segnalati da Giacomo.
    if "$ROOT/scripts/prova-primo-aggancio.sh" > /tmp/minerva-aggancio.log 2>&1; then
        ok "$(grep -o 'agganciata [0-9]* ms.*' /tmp/minerva-aggancio.log | head -1)"
    else
        bad "la shell aspetta troppo il demone che sta nascendo:"
        grep -E "NO  |ms |È l'attesa" /tmp/minerva-aggancio.log | head -6
    fi

    # ── Due Minerva accese insieme ────────────────────────────────────────
    #
    # Il 16 agosto 2026 Giacomo è entrato dalla schermata di accesso mentre la
    # sua sessione era viva, e non è comparso niente. Tre righe nei registri,
    # una causa sola: Minerva dava per scontato di essere l'unica sessione
    # dell'utente — stessi PID dei guardiani, stessa porta, stessi registri.
    #
    # Qui si prova la cosa che lo impedisce, e si prova sul serio: due demoni
    # con due nomi di sessione, e due shell che devono trovare OGNUNA IL SUO.
    # Se un giorno il nome della sessione sparisse da uno dei tre posti che lo
    # calcolano (`minerva-posti.sh`, `canale_segreto.dart`, `core/Ipc.qml`), le
    # due si troverebbero sullo stesso canale e questa prova diventerebbe rossa
    # invece di lasciarlo scoprire a un accesso mancato.
    due_sessioni() {
        DUE=/tmp/minerva-prova-due
        rm -rf "$DUE"; mkdir -p "$DUE"
        # Si tiene il PID di QUESTI due.
        #
        # Prima si lanciavano staccati (`( nohup … & )`) e alla fine si
        # cercavano per nome. Due difetti in una riga sola, e il secondo è
        # grave: il filtro era `$2 == "<radice>/minervad/build/minervad"`, ma
        # la radice di questo progetto contiene uno spazio — «Minerva Shell» —
        # e `awk` spezza sugli spazi, quindi `$2` si fermava a
        # «…/Progetti/Minerva» e non combaciava mai. Risultato: due demoni
        # lasciati accesi a ogni giro delle prove, che tenevano una porta e
        # facevano sembrare occupata mezza scansione al giro dopo.
        #
        # E se avesse combaciato sarebbe stato peggio: sulla macchina di chi
        # sviluppa gira già un minervad avviato dallo STESSO eseguibile — la
        # sua sessione — e quel `kill` gliel'avrebbe spenta nel mezzo del
        # lavoro. Un PID preso al volo non ha nessuno dei due problemi.
        PIDS=""
        for N in A B; do
            MINERVA_SESSIONE="$N" MINERVA_CONFIG_DIR="$DUE/conf-$N" \
                "$ROOT/minervad/build/minervad" > "$DUE/$N.log" 2>&1 &
            PIDS="$PIDS $!"
            sleep 2
        done
        PORTE=$(sed -n 's|.*in ascolto su \(/.*\.sock\).*|\1|p' \
                "$DUE/A.log" "$DUE/B.log" | sort -u | tr '\n' ' ')
        ESITO=""
        for N in A B; do
            R=$(MINERVA_SESSIONE="$N" MINERVA_CONFIG_DIR="$DUE/conf-$N" \
                timeout 25 qs -p "$ROOT/minerva-shell/prove-due-sessioni.qml" 2>&1 \
                | sed 's/\x1b\[[0-9;]*m//g' \
                | sed -n 's|.*\[DUE\] \(.*\)|\1|p' | head -1)
            ESITO="$ESITO|$R"
        done
        for P in $PIDS; do
            kill "$P" 2>/dev/null || true
        done
        # Aspettarli davvero: senza, `rm -rf` porta via la cartella delle
        # impostazioni mentre stanno ancora chiudendo, e ogni tanto lasciano
        # un errore nel registro per una cosa che non è un errore.
        wait $PIDS 2>/dev/null || true
        rm -rf "$DUE"
        printf '%s %s\n' "$PORTE" "$ESITO"
    }
    RIS=$(due_sessioni)
    QUANTE=$(printf '%s' "$RIS" | awk '{print NF - 1}')
    if printf '%s' "$RIS" | grep -q "|A ok" && printf '%s' "$RIS" | grep -q "|B ok" \
       && [ "$QUANTE" -ge 2 ]; then
        ok "due sessioni Minerva insieme: due socket, e ognuna trova il suo"
    else
        bad "due sessioni Minerva insieme non si separano: $RIS"
    fi

    # ── L'indirizzo del canale ────────────────────────────────────────────
    #
    # Dentro la schermata di accesso girano DUE Minerva insieme: quello del
    # greeter e quello della sessione già aperta. Se parlano sullo stesso
    # indirizzo, il demone del greeter non riesce ad ascoltare e la schermata
    # finisce a chiedere le cose al demone dell'ALTRO utente — che non sa
    # niente di greetd e le risponde che è un'anteprima. Si vede benissimo e
    # non fa entrare nessuno. È successo il 5 agosto 2026.
    #
    # Qui si prova la sola cosa che lo impedisce: che la shell dia retta a
    # MINERVA_IPC_SOCKET, e che davanti a un valore scritto male torni al
    # predefinito invece di non partire. Il demone ha la sua prova gemella in
    # `socket_ipc_test.dart`: devono restare d'accordo sulla regola.
    socket_letto() {
        MINERVA_IPC_SOCKET="$1" timeout 20 qs -p "$ROOT/minerva-shell/prove-greeter.qml" 2>&1 \
            | sed -n 's|.*Canale su \([^ ]*\).*|\1|p' | head -1
    }
    ATTESO="${XDG_RUNTIME_DIR:-/tmp}/minerva/canale-${MINERVA_SESSIONE:-unica}.sock"
    VUOTO=$(socket_letto "")
    SCELTO=$(socket_letto /tmp/minerva-prova-scelto.sock)
    # Non un percorso: relativo, quindi non è un ordine e si torna al proprio.
    ROTTO=$(socket_letto pippo)
    if [ "$SCELTO" = /tmp/minerva-prova-scelto.sock ] \
       && [ "$VUOTO" = "$ROTTO" ] && [ -n "$VUOTO" ] \
       && [ "${VUOTO%.sock}" != "$VUOTO" ]; then
        ok "la shell segue MINERVA_IPC_SOCKET (e ignora i valori sbagliati)"
    else
        bad "indirizzo del canale: senza=$VUOTO scelto=$SCELTO sbagliato=$ROTTO (atteso di ripiego: $ATTESO)"
    fi

    # ── L'accesso, dall'inizio alla fine ──────────────────────────────────
    #
    # Tutte le prove qui sopra guardano UN pezzo per volta, e il 5 agosto 2026
    # passavano tutte mentre la schermata di accesso non faceva entrare
    # nessuno. Il difetto stava nel punto in cui i pezzi si toccano — il
    # demone del greeter che non riusciva ad ascoltare — e nessuna prova di un
    # pezzo solo poteva vederlo.
    #
    # Questa percorre la catena vera: client vero → demone vero → socket
    # di greetd. L'unico pezzo finto è greetd, perché usare quello vero
    # significherebbe mettere in gioco l'accesso alla macchina. Non serve un
    # compositore né uno schermo: si può lanciare sempre.
    USCITA=$(timeout 90 python3 "$ROOT/scripts/prova-accesso.py" 2>&1)
    if echo "$USCITA" | grep -q "TUTTE PASSATE"; then
        QUANTE=$(echo "$USCITA" | sed -n 's/.*TUTTE PASSATE (\([0-9]*\)).*/\1/p')
        ok "$QUANTE prove dell'accesso completo (shell → demone → greetd) passate"
    else
        bad "prove dell'accesso completo fallite:"
        echo "$USCITA" | grep -E "NO |FALLITE|manca|morto|mai" | head -10
    fi
fi

# ── 6. La shell che sta girando ────────────────────────────────────────────
#
# Era il buco più grosso della rete: le quattro finestre staccate si provano
# tutte, e `shell.qml` — che è la superficie QML PIÙ GRANDE (novanta file) e
# l'unica che resta accesa tutto il giorno — non si provava mai. Un ciclo di
# legami o un avviso lì dentro non lo vedeva nessuno.
#
# Non se ne apre una seconda: due shell si contenderebbero la barra e i
# pannelli. Si guarda QUELLA CHE STA GIRANDO, che è anche l'unico modo di
# accorgersi di un avviso che compare solo dopo ore di uso.
head_ "Shell in esecuzione"
SHELL_PID=$(ps -eo pid,args --no-headers \
            | awk '$2 == "qs" && index($0, "minerva-shell/shell.qml") { print $1; exit }')
if ! command -v qs >/dev/null 2>&1; then
    skip "quickshell non installato"
elif [ -z "$SHELL_PID" ]; then
    skip "nessuna shell di Minerva in esecuzione"
else
    # ── I nove pannelli della barra ──────────────────────────────────────
    #
    # Si aprono PRIMA di leggere il registro, cosi' che cio' che dicono finisca
    # nella lettura qui sotto. Erano l'unico pezzo grosso dell'interfaccia che
    # nessuna prova apriva, e il 24 agosto 2026 e' saltato fuori il perche':
    # un anello di legami in `Spine.qml` che girava da chissa' quando, visto
    # solo perche' per caso qualcuno aveva aperto un pannello a mano prima
    # delle prove. Vedi `scripts/prove-pannelli.sh`.
    USCITA_PAN=$(bash "$ROOT/scripts/prove-pannelli.sh" 2>&1) && ESITO=0 || ESITO=1
    if [ "$ESITO" -eq 0 ]; then
        ok "$(printf '%s' "$USCITA_PAN" | sed -n 's/^OK: //p' | head -1)"
    else
        bad "i pannelli della barra non si aprono in silenzio:"
        printf '%s\n' "$USCITA_PAN" | sed 's/^NO: //' | head -6 \
            | while IFS= read -r R; do nota "$R"; done
    fi

    # Stessi due rumori attesi della prova qui sopra, più il portale: lo dice
    # Qt quando un secondo processo si presenta allo stesso servizio del
    # desktop, e non dipende da noi.
    #
    # ── Una connessione persa e RIPRESA non è un difetto ─────────────────
    #
    # Il demone si riavvia legittimamente: ricompilarlo e rimetterlo in moto è
    # il gesto più comune di tutta la giornata di lavoro. Ogni volta la shell
    # scrive «Connessione persa», e quella riga resta nel registro per tutta la
    # vita del processo — quindi da lì in poi questa prova era rossa fino al
    # riavvio della shell, e diceva rosso su una cosa che aveva funzionato.
    #
    # Una prova che si può far tornare verde solo riavviando qualcosa insegna a
    # riavviare, non a correggere. Quindi: si contano le perdite e i ritorni.
    # Se ogni perdita ha avuto il suo ritorno, il canale ha fatto esattamente
    # ciò per cui è stato scritto. Se ne resta una scoperta, quella si vede.
    REG=$(qs log --pid "$SHELL_PID" 2>/dev/null)
    PERSE=$(printf '%s\n' "$REG" | grep -c "Connessione persa")
    RIPRESE=$(printf '%s\n' "$REG" | grep -c "Connesso al demone")

    SHELL_NOISE=$(printf '%s\n' "$REG" \
                  | grep -E "WARN|ERROR|error:" \
                  | grep -v "Demone non raggiungibile" \
                  | grep -v "host portal" \
                  | grep -v "not previously tracked" \
                  | grep -v "VDPAU")

    # ── E «non trovo Hyprland», quando Hyprland davvero non c'è ─────────
    #
    # Stessa ragione della stessa riga in `prova_finestra`: sotto
    # minerva-wayland `Quickshell.Hyprland` avvisa una volta all'avvio, per
    # sempre, e non è un difetto nostro. Un avviso che c'è sempre non avvisa
    # di niente — e teneva rosso il controllo che serve a vedere quelli veri.
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        SHELL_NOISE=$(printf '%s\n' "$SHELL_NOISE" \
                      | grep -v "HYPRLAND_INSTANCE_SIGNATURE is unset" \
                      | grep -v "quickshell.hyprland.ipc" \
                      | sed '/^$/d')
    fi

    if [ "$PERSE" -gt 0 ] && [ "$RIPRESE" -ge "$PERSE" ]; then
        SHELL_NOISE=$(printf '%s\n' "$SHELL_NOISE" | grep -v "Connessione persa")
        # ── Lo stesso evento, visto dall'altra parte ─────────────────────
        #
        # «Connessione persa» la scrive il nostro QML; queste due righe le
        # scrive quickshell in C++ per lo STESSO distacco, e dal 27 agosto 2026
        # ci sono perché il canale è un socket Unix e non più una WebSocket:
        #
        #   · PeerClosedError      — il demone se n'è andato;
        #   · ServerNotFoundError  — si è ribussato prima che il nuovo fosse
        #                            in piedi.
        #
        # Si perdonano SOLO qui dentro, cioè solo quando ogni perdita ha avuto
        # il suo ritorno. Fuori da questo ramo restano rosse, ed è giusto: un
        # socket che non si trova e non torna è un demone che non c'è.
        SHELL_NOISE=$(printf '%s\n' "$SHELL_NOISE" \
                      | grep -v "quickshell.io.socket")
        if [ "$PERSE" -eq 1 ]; then
            nota "il demone si è fermato una volta, e la shell l'ha ripreso"
        else
            nota "il demone si è fermato $PERSE volte, e la shell l'ha ripreso ogni volta"
        fi
    fi
    # ── I verbi che il compositore VECCHIO non conosce ────────────────────
    #
    # Si perdonano SOLO se il controllo 3-quater-bis ha già detto che il
    # compositore in esecuzione è più vecchio del binario compilato. Fuori da
    # quel caso restano rossi, ed è giusto: un verbo che il compositore
    # AGGIORNATO non conosce è un pannello che scrive nel vuoto.
    if [ "${COMP_VECCHIO:-0}" -eq 1 ]; then
        VERBI_IGNOTI=$(printf '%s\n' "$SHELL_NOISE" \
                       | grep -c 'verbo .* sconosciuto' || true)
        if [ "${VERBI_IGNOTI:-0}" -gt 0 ]; then
            SHELL_NOISE=$(printf '%s\n' "$SHELL_NOISE" \
                          | grep -v 'verbo .* sconosciuto')
            nota "perdonati $VERBI_IGNOTI «verbo sconosciuto»: li conosce il"
            nota "compositore compilato, non quello che sta girando adesso"
        fi
    fi

    if [ -z "$SHELL_NOISE" ]; then
        ok "la shell gira senza un solo avviso"
    else
        # Il registro copre TUTTA la vita del PROCESSO, e una ricarica non è
        # un processo nuovo: `minerva-reload.sh` passa dall'IPC e la shell
        # sopravvive, quindi gli avvisi di prima della correzione restano lì a
        # dire rosso su una cosa già riparata. (Qui c'era scritto che la
        # ricarica riazzera il registro. Non è vero, e l'ho creduto.)
        #
        # Per azzerarlo davvero bisogna che la shell RIPARTA:
        #
        #     pkill -f 'qs -p .*shell.qml'   # e riavviarla
        #
        # La riga qui sopra — i nove pannelli — invece guarda solo il pezzo di
        # registro nato durante la prova, e quella dice sempre la verità di
        # adesso.
        bad "avvisi nella shell in esecuzione (da quando è partita):"
        echo "$SHELL_NOISE" | head -10
    fi
fi

# ── Quanto pesa la scrivania ───────────────────────────────────────────────
#
# Giacomo, 2 settembre 2026: «uno dei nostri obiettivi deve essere un desktop
# leggerissimo e scattante [...] che senso ha un desktop nuovo ma più pesante
# di altri?». È un requisito di architettura, non una rifinitura, e un
# requisito che nessuno misura è un'opinione.
#
# Le singole app hanno già i loro tetti qui sopra. Mancava quello che conta di
# più: **la scrivania intera** — compositore, shell, demone, portali — che è il
# prezzo che si paga sempre, anche senza aprire niente.
#
# La misura è `scripts/memoria.sh`, la stessa del confronto con KDE del
# 12 agosto 2026, e conta la memoria PSS: è l'unico numero che si può sommare
# fra processi senza contare due volte le librerie condivise.
#
#   12 agosto 2026    436 MB   (shell 165 · Hyprland 126 · minervad 52 · … )
#    2 settembre      261 MB   (shell 150 · minerva-wayland 57 · minervad 44)
#
# Centosettantacinque megabyte in meno, e la fetta più grossa è il compositore
# nostro al posto di Hyprland: 126 → 57.
#
# ── Il tetto si ABBASSA quando si guadagna ────────────────────────────────
#
# Un tetto lasciato largo smette di sorvegliare: fra sei mesi la scrivania pesa
# 299 e nessuno se n'è accorto. Quando una misura scende in modo stabile, si
# scende anche qui — è l'unico modo perché «leggerissimo» resti un numero.
head_ "Peso della scrivania"
if [ ! -x "$ROOT/scripts/memoria.sh" ]; then
    skip "memoria.sh non trovata"
elif ! pgrep -x minerva-wayland >/dev/null 2>&1; then
    skip "peso: nessuna sessione Minerva in corso"
elif pgrep -af 'dartvm.*bin/minervad\.dart' >/dev/null 2>&1; then
    # ── Un rosso che non è un difetto insegna a ignorare i rossi ───────────
    #
    # Il guardiano del demone, quando i sorgenti `.dart` sono più recenti del
    # compilato, ripiega su `dart run` apposta: meglio una scrivania pesante di
    # una scrivania col demone di ieri. Ma quel ripiego si porta dietro la
    # macchina virtuale con dentro il compilatore — misurato il 3 settembre
    # 2026 nella sessione vera di Giacomo: **231 MB invece di 19**.
    #
    # Con quel demone la scrivania pesa duecento megabyte di troppo e questa
    # prova diventa rossa. Il numero è vero, ma non dice quello che sembra
    # dire: non c'è nessuna regressione, c'è un file toccato mezz'ora fa.
    #
    # Una prova che dice rosso quando va tutto bene è peggio di una prova che
    # non c'è: la prima volta la si guarda, la terza la si salta — e il giorno
    # che il rosso è vero si salta anche quello. Quindi qui si SALTA, dicendo
    # perché e cosa fare.
    skip "peso: il demone gira interpretato (sorgenti più recenti del compilato)"
    nota "sono ~210 MB in più che spariscono da soli: la ricompilazione parte"
    nota "da sola in sottofondo, e il prossimo accesso userà il compilato."
    nota "per misurare adesso: cd minervad && dart compile exe bin/minervad.dart -o build/minervad"
else
    # ── Il tetto non è un numero: è una somma dichiarata ──────────────────
    #
    # Giacomo, 9 settembre 2026: «se dobbiamo superare un po' i 290 MB va bene
    # tanto già me lo aspettavo». Alzare il numero e basta però lo spegnerebbe
    # — questo file lo dice per iscritto poco più su: «un tetto lasciato largo
    # smette di sorvegliare».
    #
    # Quindi il tetto resta 290 per la scrivania NUDA, e cresce **solo di
    # quanto costa quello che hai acceso tu**. Il supplemento dei widget è
    # MISURATO e non stimato, dentro la sessione annidata del 10 settembre
    # 2026, leggendo `Private_Clean+Private_Dirty` del processo della shell:
    #
    #     nessun widget                         99 MB
    #     5 sulla scrivania + 3 nella barra    102 MB
    #     10 sulla scrivania + 6 nella barra   105 MB
    #
    # Cioè circa mezzo megabyte l'uno, e non è un caso: la sorgente è una sola
    # (`core/Macchina.qml`), la cadenza è una sola, e un widget in più è un
    # rettangolo con dentro due `Text` e un `Canvas` da 48 numeri.
    #
    # Mezzo per widget, arrotondato a UNO: se domani un widget nuovo ne
    # prendesse tre, la prova diventa rossa lo stesso. È l'unico modo di
    # alzare un tetto senza spegnerlo.
    TETTO_BASE=290
    COSTO_WIDGET=1
    IMPO="${MINERVA_CONFIG_DIR:-$HOME/.config/minerva}/settings.json"
    QUANTI_WIDGET=$(python3 - "$IMPO" <<'PYCONTA' 2>/dev/null || echo 0
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0); raise SystemExit
n = len((d.get('desktop') or {}).get('widgets') or [])
n += len((d.get('bar') or {}).get('widgets') or [])
print(n)
PYCONTA
)
    [ -z "$QUANTI_WIDGET" ] && QUANTI_WIDGET=0
    TETTO_SCRIVANIA=$((TETTO_BASE + QUANTI_WIDGET * COSTO_WIDGET))
    PESO=$("$ROOT/scripts/memoria.sh" 2>/dev/null \
           | sed -n 's/.*LA SCRIVANIA[^0-9]*\([0-9]\+\) MB.*/\1/p' | head -1)
    if [ "$QUANTI_WIDGET" -gt 0 ]; then
        nota "tetto $TETTO_BASE + $QUANTI_WIDGET widget × $COSTO_WIDGET MB = $TETTO_SCRIVANIA"
    fi
    if [ -z "$PESO" ]; then
        bad "non riesco a leggere il peso della scrivania da memoria.sh"
    elif [ "$PESO" -le "$TETTO_SCRIVANIA" ]; then
        ok "la scrivania pesa $PESO MB (tetto $TETTO_SCRIVANIA, era 436 il 12 agosto)"
        # Se è scesa parecchio sotto il tetto, il tetto va abbassato: lo dice
        # invece di lasciarlo largo in silenzio.
        if [ "$PESO" -lt $((TETTO_SCRIVANIA - 40)) ]; then
            nota "è scesa a $PESO: abbassa TETTO_BASE in prove.sh, o smette di sorvegliare"
        fi
    else
        bad "la scrivania pesa $PESO MB (tetto $TETTO_SCRIVANIA)"
        nota "guarda chi è cresciuto con: ./scripts/memoria.sh"
    fi
fi

# ── Esito ──────────────────────────────────────────────────────────────────
echo
if [ "$FAILED" -eq 0 ]; then
    printf '\033[32m✓ tutto a posto\033[0m\n'
    exit 0
fi
printf '\033[31m✗ %d controlli falliti\033[0m\n' "$FAILED"
exit 1
