#!/usr/bin/env python3
"""prova-inattivita.py — Che la catena dell'inattività sia INTERA.

    ./prova-inattivita.py

── Perché ci vuole una sessione vera ──────────────────────────────────────

Perché quello che si prova qui non è un pezzo: è una CATENA di quattro, e ogni
anello si rompe in silenzio.

    pannello Energia → demone → shell → compositore

Il pannello scrive un'impostazione; il demone la annuncia; la shell la legge,
la converte in secondi e la manda al compositore con `inattivita …`; il
compositore conta. Se un anello salta, lo schermo semplicemente non si blocca
più da solo — nessun errore, nessuna riga rossa, e non c'è niente da guardare
per sapere quale anello è.

La prima volta che questa prova è stata scritta, il 1º settembre 2026, ha
trovato subito un anello rotto: la shell mandava le soglie solo dentro due
gestori di segnale, e un segnale è un'occasione sola. Se il canale del
compositore era già aperto quando la shell è nata, e le impostazioni del demone
dicevano gli stessi numeri dei valori di ripiego, non scattava **niente**.

È lo stesso difetto che aveva lasciato il touchpad senza tap-to-click per otto
ore, ed è la ragione per cui una prova che parla al demone vero vale più di
dieci che leggono il codice.

── Come si guarda dall'altro capo ─────────────────────────────────────────

`stato` del compositore risponde col campo `inattivita`: quante soglie gli sono
state chieste. Serve esattamente a questo — separare «la shell non le ha
chieste» da «il compositore non conta», che dallo schermo si vedono identici.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

Si passa da `prova-annidata.sh`, che mette `WLR_BACKENDS=wayland` e
`MINERVA_PROVA=1` e si costruisce una cartella di configurazione tutta sua in
`$TMPDIR/liquid-de-prova-conf`. Le impostazioni che questa prova cambia sono
quelle della COPIA, mai quelle della sessione vera.
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
sys.path.insert(0, QUI)
from importlib import import_module

_annunci = import_module("prova-annunci")
Canale = _annunci.Canale
chiudi = _annunci.chiudi

CONF = os.path.join(os.environ.get("TMPDIR", "/tmp"), "liquid-de-prova-conf")

passate = 0
fallite = 0


def verifica(nome, cond, dettaglio=""):
    global passate, fallite
    if cond:
        passate += 1
        print("  ok   " + nome)
    else:
        fallite += 1
        print("  NO   " + nome + ("  → " + str(dettaglio) if dettaglio else ""))


def stato(canale):
    c = Canale(canale)
    c.scrivi("stato")
    r = c.aspetta("ok {", 6)
    c.chiudi()
    if r is None:
        return None
    try:
        return json.loads(r[3:])
    except ValueError:
        return None


def parla_al_demone(valori):
    """Cambia delle impostazioni come farebbe il pannello."""
    conf = {}
    with open(os.path.join(CONF, "canale")) as f:
        for riga in f:
            if "=" in riga:
                k, v = riga.strip().split("=", 1)
                conf[k] = v
    d = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    d.settimeout(8)
    d.connect(conf["socket"])
    # La parola d'ordine è la prima cosa, e senza il demone chiude e basta:
    # vedi `minervad/lib/ipc/canale_segreto.dart`.
    d.sendall((json.dumps({"action": "ciao",
                           "segreto": conf["segreto"]}) + "\n").encode())
    time.sleep(1)
    try:
        d.recv(65536)
    except socket.timeout:
        pass
    d.sendall((json.dumps({"action": "set_settings",
                           "values": valori}) + "\n").encode())
    time.sleep(4)
    d.close()


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland; wlroots prenderebbe "
              "lo schermo vero.", file=sys.stderr)
        return 2

    avvio = subprocess.Popen(
        [os.path.join(QUI, "prova-annidata.sh")],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        bufsize=1)

    canale, righe, inizio = "", [], time.time()
    while time.time() - inizio < 60:
        r = avvio.stdout.readline()
        if not r:
            break
        righe.append(r.rstrip())
        m = re.search(r"canale su (\S+)", r)
        if m:
            canale = m.group(1)
            break

    print("── Prove dell'inattività (catena intera) ──")
    if not canale:
        verifica("la sessione annidata parte", False, "\n".join(righe[-20:]))
        chiudi(avvio)
        return 1
    verifica("la sessione annidata parte", True)
    print("  ·    canale %s" % canale)

    try:
        # La shell ci mette qualche secondo a nascere e a ricevere le
        # impostazioni dal demone.
        time.sleep(16)

        # ── Tre soglie ───────────────────────────────────────────────────
        parla_al_demone({"power.dimAfter": 5, "power.lockAfter": 10,
                         "power.suspendAfter": 30})
        s = stato(canale)
        verifica("il compositore risponde a «stato»", s is not None)
        verifica("tre soglie chieste dal pannello arrivano al compositore",
                 s is not None and s.get("inattivita") == 3, s)

        # ── Zero vuol dire «mai», e «mai» si dice NON mandando ───────────
        #
        # Non mandando un numero enorme: un numero enorme prima o poi scatta.
        parla_al_demone({"power.dimAfter": 0, "power.lockAfter": 0,
                         "power.suspendAfter": 0})
        s = stato(canale)
        verifica("e «mai» su tutte e tre spegne la sorveglianza",
                 s is not None and s.get("inattivita") == 0, s)

        # ── Due uguali sono UNA ──────────────────────────────────────────
        #
        # Blocca e sospendi allo stesso minuto capita, e il compositore
        # rifiuta i doppioni: è la shell che deve sfoltire, non chi sposta il
        # cursore. Senza, la riga verrebbe rifiutata e la sorveglianza
        # resterebbe quella di prima — cioè spenta.
        parla_al_demone({"power.dimAfter": 0, "power.lockAfter": 10,
                         "power.suspendAfter": 10})
        s = stato(canale)
        verifica("due soglie uguali diventano una, e non un rifiuto",
                 s is not None and s.get("inattivita") == 1, s)
    finally:
        chiudi(avvio)
        # `prova-annidata.sh` esporta MINERVA_PROVA DOPO essere partito, quindi
        # nel suo `/proc/PID/environ` non c'è e `chiudi` non lo tocca — è la
        # regola che protegge la sessione vera, e qui va assecondata a mano:
        # si cerca il compositore, che invece il contrassegno ce l'ha perché è
        # stato avviato dopo l'export.
        for riga in subprocess.run(["pgrep", "-x", "minerva-wayland"],
                                   capture_output=True,
                                   text=True).stdout.split():
            try:
                amb = open("/proc/%s/environ" % riga, "rb").read()
            except OSError:
                continue
            if b"MINERVA_PROVA=1\x00" in amb:
                os.kill(int(riga), 15)
        time.sleep(2)

    print("──")
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
