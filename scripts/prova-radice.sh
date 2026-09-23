#!/bin/sh
# prova-radice.sh — Le prove di `scripts/minerva-radice`, l'aiutante di root.
#
#     scripts/prova-radice.sh [percorso dell'aiutante]
#
# ── Come si prova un programma che gira da root, senza essere root ─────────
#
# Se ne fa una copia in una cartella temporanea con i due controlli d'ingresso
# sostituiti da `:` — «sei root?» e «ti ha lanciato pkexec?». Tutto il resto è
# identico, riga per riga, e opera su una finta radice fatta di cartelle vere.
#
# È l'unico modo onesto: provare quello vero vorrebbe dire chiedere la password
# di amministratore a ogni giro di prove, e una prova che chiede una password è
# una prova che si smette di lanciare.
#
# ── Quello che conta sono i RIFIUTI ───────────────────────────────────────
#
# Che `elimina` cancelli si vede subito, e se si rompe si nota. Che `elimina`
# NON cancelli `/etc` non si vede mai — finché non si vede una volta sola, ed è
# tardi. Le prove che valgono qui dentro sono quelle sotto «deve rifiutare».
#
# E l'ultima, sotto «deve restare possibile», serve al contrario: un aiutante
# che rifiuta tutto è sicuro e inutile, e ci si accorge solo usandolo.
SORGENTE="${1:-$(dirname "$0")/minerva-radice}"
[ -r "$SORGENTE" ] || { echo "non trovo l'aiutante: $SORGENTE" >&2; exit 2; }
TANA=$(mktemp -d)
FINTO="$TANA/radice"
sed 's#^\[ "$(id -u)" -eq 0 \].*#:#; s#^\[ -n "${PKEXEC_UID:-}" \].*#:#; s#^REGISTRO=.*#REGISTRO='"$TANA"'/log#' \
    "$SORGENTE" > "$FINTO"
chmod +x "$FINTO"
export PKEXEC_UID=1000

ok=0; no=0
attesa() {  # descrizione, esito atteso (ok|rifiuto), comando…
    D="$1"; ATTESO="$2"; shift 2
    # L'uscita finisce in un file e non in una sostituzione di comando:
    # `elenca` separa le voci con un byte zero, e la sostituzione lo scarta
    # facendo stampare un avviso a ogni giro.
    if "$FINTO" "$@" > "$TANA/uscita" 2>&1; then E=ok; else E=rifiuto; fi
    OUT=$(tr -d '\000' < "$TANA/uscita" 2>/dev/null | head -1)
    if [ "$E" = "$ATTESO" ]; then ok=$((ok+1)); printf '  ok   %s\n' "$D"
    else no=$((no+1)); printf '  NO   %s  → %s (%s)\n' "$D" "$E" "$OUT"; fi
}

mkdir -p "$TANA/casa/sotto"
echo ciao > "$TANA/casa/file.txt"

echo "── Quello che deve funzionare"
attesa "elenca una cartella"            ok      elenca "$TANA/casa"
attesa "legge un file"                  ok      leggi "$TANA/casa/file.txt"
attesa "crea una cartella"              ok      crea-cartella "$TANA/casa/nuova"
attesa "cancella un file normale"       ok      elimina "$TANA/casa/file.txt"
attesa "cambia i permessi"              ok      permessi 640 "$TANA/casa/sotto"
# Il verbo che non fa niente: è quello che fa comparire la finestrella della
# password quando si ACCENDE la modalità amministratore. Deve riuscire senza
# argomenti — e non deve stampare niente, perché quello che stampa un processo
# di root lo legge chiunque.
attesa "chiede solo il permesso"        ok      permesso
if [ -s "$TANA/uscita" ]; then
    no=$((no+1)); printf '  NO   «permesso» non deve stampare niente\n'
else
    ok=$((ok+1)); printf '  ok   «permesso» non stampa niente\n'
fi

echo "── Quello che deve rifiutare"
attesa "percorso relativo"              rifiuto elimina "casa/file.txt"
attesa "percorso che comincia per -"    rifiuto elimina "-rf"
attesa "percorso vuoto"                 rifiuto elimina ""
attesa "risalita con .."                rifiuto elimina "/tmp/../etc/passwd"
attesa "la radice"                      rifiuto elimina "/"
attesa "/etc"                           rifiuto elimina "/etc"
attesa "/etc con barra in fondo"        rifiuto elimina "/etc/"
attesa "/home"                          rifiuto elimina "/home"
attesa "/usr/bin"                       rifiuto elimina "/usr/bin"
attesa "/var/lib"                       rifiuto elimina "/var/lib"
attesa "azione sconosciuta"             rifiuto disintegra "$TANA/casa"
attesa "permesso non ottale"            rifiuto permessi "u+s,go+w" "$TANA/casa"
attesa "permesso con 8 dentro"          rifiuto permessi 888 "$TANA/casa"
attesa "permesso troppo lungo"          rifiuto permessi 07777 "$TANA/casa"
attesa "spostare /etc"                  rifiuto sposta "/etc" "$TANA/casa/x"
attesa "cancellare quel che non c'è"    rifiuto elimina "$TANA/casa/fantasma"
attesa "creare quel che c'è già"        rifiuto crea-cartella "$TANA/casa/sotto"

echo "── Quello che DEVE restare possibile (non è una gabbia)"
mkdir -p "$TANA/finto-usr/bin/sotto"
attesa "un file dentro /usr/qualcosa/…"  ok     elimina "$TANA/finto-usr/bin/sotto"

printf '\n  %s passate, %s fallite\n' "$ok" "$no"
rm -rf "$TANA"
[ "$no" -eq 0 ]
