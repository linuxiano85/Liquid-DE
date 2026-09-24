#!/bin/bash
# minerva-check.sh — Controllo di salute della sessione Minerva.
#
# Da lanciare DENTRO Minerva quando qualcosa non torna: dice in venti righe
# cos'è vivo e cosa no, invece di far cercare a mano in giro.

SELF="$(readlink -f "$0")"
MINERVA_DIR="$(dirname "$(dirname "$SELF")")"
# Le cose di sessione stanno in una cartella per sessione: vedi
# `scripts/minerva-posti.sh`.
. "$MINERVA_DIR/scripts/minerva-posti.sh"

ok()  { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad() { printf '\033[31m✗\033[0m %s\n' "$1"; }
inf() { printf '\033[36m·\033[0m %s\n' "$1"; }

echo "── Sessione ───────────────────────────────────────────"
# ── Due compositori, e nessuno dei due è «quello sbagliato» ───────────────
#
# Qui c'era una riga sola: se manca `HYPRLAND_INSTANCE_SIGNATURE`, «non sei
# dentro Hyprland», in rosso. Dentro minerva-wayland quella variabile non
# esiste e non esisterà mai — quindi questo strumento dichiarava guasta una
# sessione perfettamente sana, e mandava a cercare un difetto che non c'era.
#
# È lo stesso sbaglio, in tre posti diversi, nella stessa sera del 26 agosto:
# `polkit-kde-auth` cercato per nome, `prova-blocco.py` e `prova-xwayland.py`.
# La regola che ne è uscita: **uno strumento di diagnosi che dà per morto ciò
# che è vivo è peggio di nessuno strumento.**
#
# ── E dal 2 settembre 2026 il secondo compositore non c'è più ─────────────
#
# Qui c'era un ramo per Hyprland. Se ne va col distacco, e insieme a lui se ne
# vanno le due domande che faceva: «c'è «Hyprland» in XDG_CURRENT_DESKTOP?» e
# «esiste ~/.config/hypr/minerva-paths.conf?».
#
# Toglierle non è pulizia: erano diventate **domande che dicono rosso quando
# va tutto bene**, cioè lo stesso difetto che questo blocco di commento
# racconta d'aver riparato — solo dall'altra parte. Uno strumento di diagnosi
# ha una sola cosa da difendere: che quando dice rosso, sia rosso.
if [ -n "${MINERVA_CANALE:-}" ]; then
    ok "minerva-wayland attivo"
    COMPOSITORE=nostro
else
    bad "non sei dentro una sessione Minerva: MINERVA_CANALE non è impostata"
    COMPOSITORE=nessuno
fi
inf "scrivania: ${XDG_CURRENT_DESKTOP:-(vuota)}"

# ── E il portale, che deve corrispondere al compositore ───────────────────
#
# Non basta che ci sia un nome: deve essere quello del compositore che gira
# davvero. `xdg-desktop-portal-hyprland` cerca HYPRLAND_INSTANCE_SIGNATURE, e
# dentro minerva-wayland non la trova: la condivisione dello schermo e le
# finestre «apri file» cadono **senza dire niente**.
case "$COMPOSITORE" in
    nostro)
        case "${XDG_CURRENT_DESKTOP:-}" in
            LiquidDE*)
                ok "i portali useranno il backend di wlroots" ;;
            *)
                bad "manca «LiquidDE» in testa a XDG_CURRENT_DESKTOP:"
                bad "i portali cercherebbero quello di Hyprland, che qui dentro"
                bad "non risponde — e non lo direbbe" ;;
        esac
        if [ -r "$HOME/.config/xdg-desktop-portal/liquidde-portals.conf" ]; then
            ok "liquidde-portals.conf al suo posto"
        else
            bad "manca ~/.config/xdg-desktop-portal/liquidde-portals.conf"
            bad "  → scripts/install-minerva.sh"
        fi
        if [ -r /usr/share/xdg-desktop-portal/portals/wlr.portal ]; then
            ok "xdg-desktop-portal-wlr installato"
        else
            inf "xdg-desktop-portal-wlr non installato: le finestre «apri file»"
            inf "funzionano lo stesso (ci pensa gtk), la condivisione dello"
            inf "schermo no.  → pacman -S xdg-desktop-portal-wlr"
        fi
        ;;
esac

echo
echo "── Processi ───────────────────────────────────────────"
check_proc() {
    if ps -eo stat,cmd --no-headers | awk -v p="$2" '$1 !~ /Z/ && $0 ~ p' | grep -q .; then
        ok "$1"
    else
        bad "$1 non in esecuzione"
    fi
}
check_proc "shell grafica (qs)"      'shell[.]qml'
# ── Il demone ha DUE forme, e questo controllo ne conosceva una sola ────────
#
# Compilato (`minervad/build/minervad`, quello che si usa da settimane) oppure
# interpretato (`dart run bin/minervad.dart`, il ripiego del guardiano quando
# il compilato non c'e'). Qui si cercava solo la seconda: **col demone
# compilato e perfettamente vivo, questo controllo diceva «non in
# esecuzione»**.
#
# Uno strumento di diagnosi che dichiara morto cio' che e' vivo e' peggio di
# nessuno strumento: manda a cercare un guasto che non c'e', e la volta che
# dira' il vero non gli si credera'. `minerva-reload.sh` la forma giusta la
# conosceva gia'.
#
# Trovato il 12 agosto 2026 durante la prova generale dell'avvio — e per poco
# non me lo lasciavo smentire dalla trappola di sempre: lanciando il controllo
# da una riga di comando che CONTENEVA il testo cercato, il comando trovava se
# stesso e diceva di si'. Si prova da un file, sempre.
check_proc "demone (minervad)"       'minervad/build/minervad|minervad[.]dart'
# Il gestore file è un processo a sé e può benissimo non essere aperto: qui si
# dice se c'è, non si pretende che ci sia.
if ps -eo stat,cmd --no-headers | awk '$1 !~ /Z/ && /filemanager[.]qml/' | grep -q .; then
    ok "gestore file aperto"
else
    inf "gestore file chiuso (normale)"
fi
# ── L'inattività non è più un processo ────────────────────────────────────
#
# Qui si cercava `hypridle`. Dal 1º settembre 2026 il conto lo tiene il
# compositore e la politica sta nella shell: non c'è nessun processo da
# trovare, e cercarne uno direbbe rosso su una cosa che funziona.
#
# Quello che si può controllare è che la sorveglianza sia stata CHIESTA: la
# shell manda `inattivita …` al compositore all'apertura del canale.
if [ -n "${MINERVA_CANALE:-}" ] && [ -S "$MINERVA_CANALE" ]; then
    inf "inattività: sorvegliata dal compositore (nessun processo)"
else
    inf "inattività: canale del compositore non raggiungibile da qui"
fi
check_proc "appunti (cliphist)"      '[c]liphist store'
# ── L'agente di polkit non ha un nome solo ─────────────────────────────────
#
# Qui si cercava `polkit-kde-auth`, cioe' l'agente di KDE, per nome. Ma se ne
# provano diversi in fila e si prende il PRIMO che c'e': su una macchina senza
# KDE — cioe' esattamente dove Minerva vuole arrivare — l'agente c'e',
# funziona, e questo controllo lo dichiarava morto.
#
# Dal 1º settembre 2026 il primo della lista e' il NOSTRO, `minerva-polkit`.
# Gli altri restano perche' il ripiego resta: senza NESSUN agente ogni
# richiesta di permesso sparisce in silenzio, e meglio la finestra di qualcun
# altro che nessuna finestra.
check_proc "password (polkit)"       '[m]inerva-polkit|[h]yprpolkitagent|[p]olkit-kde-auth|[p]olkit-gnome-auth|[l]xqt-policykit|[p]olkit-mate-auth'

# ── Dove sta scritto l'indirizzo del canale ────────────────────────────────
#
# Dal 16 agosto 2026 la porta non è più la 11432 fissa: il demone prende la
# prima libera e la scrive nel file del canale, accanto alla parola d'ordine.
# Quindi qui si LEGGE, non si indovina. Cercare 11432 a mano diceva «demone non
# risponde» a una seconda Minerva perfettamente viva — e quello è esattamente
# il momento in cui si lancia questo controllo.
#
# La lista dei posti è la stessa del demone (`canale_segreto.dart`) e delle
# finestre (`core/Ipc.qml`), nello stesso ordine: qui sono tre, e devono
# restare tre.
CANALE=""
for c in "${MINERVA_TOKEN_FILE:-}" \
         "${XDG_RUNTIME_DIR:+$CARTELLA_RUNTIME/sessioni/$MINERVA_SESSIONE/canale}" \
         "$CARTELLA_CONFIG/sessioni/$MINERVA_SESSIONE/canale"; do
    [ -n "$c" ] && [ -f "$c" ] && { CANALE="$c"; break; }
done
# `MINERVA_IPC_SOCKET` vince sul file: e' un ordine, non un suggerimento, ed e'
# cosi' che la schermata di accesso resta sul socket suo.
SOCKET="${MINERVA_IPC_SOCKET:-}"
[ -z "$SOCKET" ] && [ -n "$CANALE" ] && SOCKET=$(sed -n 's/^socket=//p' "$CANALE" | head -1)

echo
echo "── Collegamenti ───────────────────────────────────────"
if [ -z "$SOCKET" ]; then
    bad "non si sa dove cercare il demone: nel file del canale non c'e' una riga «socket=»"
elif [ ! -S "$SOCKET" ]; then
    bad "il demone non ha aperto $SOCKET: menu app, impostazioni e gestore file non funzioneranno"
# ── Esserci non basta: un socket e' un file e resta per terra ─────────────
#
# Se il demone e' stato ucciso invece che chiuso, il file c'e' ancora e a
# guardarlo sembra tutto a posto. L'unico modo onesto di sapere se dall'altra
# parte c'e' qualcuno e' provare a collegarsi. Vedi `_ascolta` in
# `websocket_server.dart`, che fa la stessa domanda per la ragione opposta.
elif python3 -c "import socket,sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(2)
try: s.connect(sys.argv[1])
except OSError: sys.exit(1)
s.close()" "$SOCKET" 2>/dev/null; then
    ok "demone in ascolto su $SOCKET (sessione «$MINERVA_SESSIONE»)"
else
    bad "$SOCKET e' rimasto per terra da un demone morto: non risponde nessuno"
fi

PID=$(ps -eo pid,stat,cmd --no-headers | awk '$2 !~ /Z/ && /shell[.]qml/ {print $1; exit}')
if [ -n "$PID" ]; then
    S=$(qs ipc --pid "$PID" call minerva status 2>/dev/null)
    [ -n "$S" ] && ok "shell risponde — $S" || bad "shell viva ma non risponde all'IPC"
fi

echo
echo "── Configurazioni ─────────────────────────────────────"
# I percorsi li passa `start-minerva-wayland.sh` nell'ambiente della sessione:
# non c'è più nessun file di configurazione da cui vadano riletti.
if [ -n "${MINERVA_DIR:-}" ] && [ -d "$MINERVA_DIR/minerva-shell" ]; then
    ok "Minerva sta in $MINERVA_DIR"
else
    bad "MINERVA_DIR non punta a un albero di Minerva: «$MINERVA_DIR»"
fi

echo
echo "── Se qualcosa è rotto ────────────────────────────────"
echo "  $MINERVA_DIR/scripts/minerva-reload.sh        ricarica la shell"
echo "  $MINERVA_DIR/scripts/minerva-reload.sh tutto  ricarica tutto"
echo "  $STATO/session.log   registro dell'avvio"

# ── Il custode dei segreti ────────────────────────────────────────────────
#
# Se nessun backend offre `Secret` per questa scrivania, i programmi che
# tengono password (Chrome, Chromium, gli account online) ripiegano su un
# archivio in chiaro SENZA dirlo. Il sintomo arriva giorni dopo, altrove:
# «sincronizzazione sospesa» e tutti gli accessi da rifare.
sec_backend=""
for d in "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal" /usr/share/xdg-desktop-portal; do
    for nome in $(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr ':' ' ' | tr 'A-Z' 'a-z'); do
        f="$d/$nome-portals.conf"
        [ -f "$f" ] || continue
        riga=$(grep -E '^[[:space:]]*org\.freedesktop\.impl\.portal\.Secret[[:space:]]*=' "$f" | head -1)
        [ -n "$riga" ] && { sec_backend="${riga#*=}"; break 2; }
    done
done
if [ -n "$sec_backend" ]; then
    inf "custode dei segreti: ${sec_backend// /}"
else
    bad "nessun backend per org.freedesktop.impl.portal.Secret: Chrome e gli altri terranno le password in chiaro e chiederanno di rifare l'accesso"
fi

# ── La porta del canale, e chi ci può entrare ─────────────────────────────
#
# Il demone ascolta su una porta TCP di localhost. Fino al 16 agosto 2026
# rispondeva a chiunque riuscisse a collegarsi — cioè a ogni processo di ogni
# utente del computer. Adesso c'è una parola d'ordine in un file, e tutta la
# garanzia sta nei permessi di quel file: se un giorno nasce 0644, il canale
# torna aperto a tutti e non se ne accorge nessuno, perché continua a
# funzionare esattamente come prima.
echo
echo "── Il canale fra demone e finestre ────────────────────"
SEGRETO="$CANALE"
if [ -z "$SEGRETO" ]; then
    bad "nessuna parola d'ordine del canale: il demone non è mai partito, o è una versione vecchia che risponde a chiunque"
else
    MODO=$(stat -c '%a' "$SEGRETO")
    if [ "$MODO" = "600" ]; then
        ok "parola d'ordine del canale, leggibile solo da te ($SEGRETO)"
    else
        bad "la parola d'ordine del canale è $MODO invece di 600 ($SEGRETO): chiunque sul computer può comandare la scrivania"
    fi
fi

# ── La schermata di accesso ───────────────────────────────────────────────
#
# Il suo codice gira PRIMA che qualcuno abbia fatto l'accesso, e disegna la
# casella della password. Se è riscrivibile da un utente normale, quell'utente
# può farsi scrivere dentro le password di tutti quelli che entrano.
if [ -d /usr/local/share/minerva ]; then
    INTRUSI=$(find /usr/local/share/minerva /usr/local/lib/minerva \
                   \( ! -user root -o -perm -g+w -o -perm -o+w \) \
                   -print 2>/dev/null | head -3)
    if [ -z "$INTRUSI" ]; then
        ok "la schermata di accesso installata è solo di root"
    else
        bad "dentro /usr/local/share/minerva c'è roba scrivibile da chi non è root:"
        printf '%s\n' "$INTRUSI" | sed 's/^/      /'
        echo "      → sudo $MINERVA_DIR/scripts/minerva-greetd installa"
    fi
fi
