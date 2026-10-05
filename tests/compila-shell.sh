#!/bin/sh
# compila-shell.sh — Compila OGNI file QML della shell col motore vero.
#
# `qmllint` non conosce i tipi di Quickshell e vede errori che non ci sono;
# la shell avviata compila solo quello che apre, e una pagina delle
# Impostazioni rotta si scopre solo aprendola. Qui ogni file passa da
# `Qt.createComponent` dentro Quickshell, senza crearne nessuno: un import
# tolto di troppo, un tipo che non esiste, un errore di sintassi escono
# tutti, con nome e riga.
#
#     tests/compila-shell.sh        → «compilati=203 rotti=0», uscita 0
#
# Non tocca la sessione: nessuna finestra viene creata.
set -eu

QUI="$(cd "$(dirname "$0")/.." && pwd)"
SHELL_DIR="$QUI/minerva-shell"
PROVA="$SHELL_DIR/_prova_compila.qml"
trap 'rm -f "$PROVA"' EXIT INT TERM

ELENCO=$(cd "$SHELL_DIR" && find . -name '*.qml' ! -name '_prova_*' | sed 's|^\./||' | sort \
         | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')

cat > "$PROVA" <<FINE
import QtQuick
import Quickshell
ShellRoot {
    Timer {
        interval: 200; running: true
        onTriggered: {
            var elenco = $ELENCO;
            var rotti = 0;
            for (var i = 0; i < elenco.length; i++) {
                var c = Qt.createComponent(Qt.resolvedUrl(elenco[i]), Component.PreferSynchronous);
                if (c.status === Component.Error) {
                    rotti++;
                    console.log("ROTTO " + elenco[i] + " :: " + c.errorString().replace(/\n/g, " | "));
                }
            }
            console.log("FINE compilati=" + elenco.length + " rotti=" + rotti);
            Qt.quit();
        }
    }
}
FINE

USCITA=$(timeout 180 qs -p "$PROVA" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'ROTTO|FINE' || true)
printf '%s\n' "$USCITA" | sed 's/^ *DEBUG qml: //'
printf '%s\n' "$USCITA" | grep -q 'FINE .* rotti=0$'
