#!/usr/bin/env python3
"""prova-cornice.py — Il colore intorno alla finestra attiva, catena intera.

    ./prova-cornice.py

── Cosa si prova, e perché non basta guardare ─────────────────────────────

Giacomo, 3 settembre 2026: «se voglio che il colore intorno diventi tipo rgb e
cambi colore costantemente oppure che giri sempre come una striscia led?».

La catena è di quattro anelli, come quella dell'inattività:

    pannello Aspetto → demone → shell (WindowRules) → compositore

e si rompe negli stessi modi silenziosi. Il caso peggiore non è «non si vede»:
è che il compositore RIFIUTI la riga — un periodo fuori misura, un colore
storto — e risponda `no …` su un socket che nessuno sta leggendo. Sullo schermo
non succede niente, e non succede niente anche quando la cornice è spenta.

Per questo `stato` riporta `cornice` e `cornicePeriodo`: separa «la shell non
l'ha chiesta» da «il compositore non la disegna», che a occhio sono identici.

── E i rifiuti, che sono metà della prova ─────────────────────────────────

Un periodo di mezzo secondo non è un colore che gira: è un lampeggio davanti
agli occhi tutto il giorno. Il compositore lo rifiuta, e questa prova pretende
che lo rifiuti — perché il modo in cui una guardia sparisce è che qualcuno
allarghi i limiti «tanto è solo un numero».

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

Si passa da `prova-annidata.sh`: `WLR_BACKENDS=wayland`, `MINERVA_PROVA=1` e
una cartella di configurazione tutta sua. La sessione vera non si tocca.
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)
from importlib import import_module

_annunci = import_module("prova-annunci")
Canale = _annunci.Canale
chiudi = _annunci.chiudi

CONF = os.path.join(os.environ.get("TMPDIR", "/tmp"), "minerva-prova-conf")

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


def dico(canale, riga, attesa="ok", quanto=6):
    """Manda una riga al compositore e torna la risposta."""
    c = Canale(canale)
    c.scrivi(riga)
    r = c.aspetta(attesa, quanto)
    c.chiudi()
    return r


def stato(canale):
    r = dico(canale, "stato", "ok {")
    if r is None:
        return None
    try:
        return json.loads(r[3:])
    except ValueError:
        return None


def parla_al_demone(valori):
    """Cambia delle impostazioni come farebbe il pannello Aspetto."""
    conf = {}
    with open(os.path.join(CONF, "canale")) as f:
        for riga in f:
            if "=" in riga:
                k, v = riga.strip().split("=", 1)
                conf[k] = v
    d = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    d.settimeout(8)
    d.connect(conf["socket"])
    d.sendall((json.dumps({"action": "ciao",
                           "segreto": conf["segreto"]}) + "\n").encode())
    time.sleep(1)
    try:
        d.recv(65536)
    except socket.timeout:
        pass
    d.sendall((json.dumps({"action": "set_settings",
                           "values": valori}) + "\n").encode())
    # `WindowRules` aspetta mezzo secondo prima di scrivere — le impostazioni
    # arrivano una alla volta e riscriverle a ogni valore sarebbe uno spreco.
    time.sleep(5)
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

    print("── Prove della cornice ──")
    if not canale:
        verifica("la sessione annidata parte", False, "\n".join(righe[-20:]))
        chiudi(avvio)
        return 1
    verifica("la sessione annidata parte", True)
    print("  ·    canale %s" % canale)

    try:
        time.sleep(16)

        # ── Nasce spenta DENTRO IL COMPOSITORE, non nella sessione ───────
        #
        # Un effetto che si muove tutto il giorno è una cosa che si sceglie,
        # non che si subisce — e il compositore infatti nasce senza. Ma questa
        # prova lancia anche la SHELL, che al collegamento applica le
        # impostazioni di chi la usa: se lì la cornice è accesa, alla prima
        # domanda risulta accesa. La prova diventava rossa per una preferenza,
        # cioè per il motivo sbagliato — la stessa correzione fatta lo stesso
        # giorno in `prova-effetto.py`.
        #
        # Che il COMPOSITORE nasca spento lo sorveglia il suo codice
        # (`m.cornice_modo = CORNICE_SPENTA` in `main`), non una prova che ha
        # una shell in mezzo.
        s = stato(canale)
        verifica("il compositore risponde a «stato»", s is not None)
        verifica("si parte da un punto noto",
                 dico(canale, "cornice spento - -") == "ok")
        s = stato(canale)
        verifica("e da lì la cornice è spenta",
                 s is not None and s.get("cornice") == "spento", s)

        # ── I tre modi arrivano ──────────────────────────────────────────
        verifica("«fisso» si accetta",
                 dico(canale, "cornice fisso - 22D3EE") == "ok")
        verifica("«gira» si accetta",
                 dico(canale, "cornice gira 12000 -") == "ok")
        s = stato(canale)
        verifica("e il compositore dice di girare",
                 s is not None and s.get("cornice") == "gira", s)
        verifica("col periodo che gli è stato chiesto",
                 s is not None and s.get("cornicePeriodo") == 12000, s)

        # ── I rifiuti, che sono metà della prova ─────────────────────────
        r = dico(canale, "cornice gira 500 -", "no")
        verifica("un giro di mezzo secondo si rifiuta: è un lampeggio",
                 r is not None and r.startswith("no"), r)
        r = dico(canale, "cornice arcobaleno - -", "no")
        verifica("un modo che non esiste si rifiuta",
                 r is not None and r.startswith("no"), r)
        r = dico(canale, "cornice fisso - ZZZZZZ", "no")
        verifica("un colore storto si rifiuta",
                 r is not None and r.startswith("no"), r)

        # E dopo tre rifiuti lo stato è ancora quello di prima: un comando
        # rifiutato non deve lasciare le cose a metà.
        s = stato(canale)
        verifica("dopo i rifiuti la cornice è rimasta com'era",
                 s is not None and s.get("cornice") == "gira"
                 and s.get("cornicePeriodo") == 12000, s)

        # ── La catena intera, dal pannello ───────────────────────────────
        dico(canale, "cornice spento - -")
        parla_al_demone({"windows.cornice": "gira",
                         "windows.cornicePeriodo": 20000})
        s = stato(canale)
        verifica("il pannello accende la cornice e il compositore lo sa",
                 s is not None and s.get("cornice") == "gira", s)
        verifica("e il periodo del pannello arriva fino in fondo",
                 s is not None and s.get("cornicePeriodo") == 20000, s)

        parla_al_demone({"windows.cornice": "spento"})
        s = stato(canale)
        verifica("e si spegne dallo stesso posto",
                 s is not None and s.get("cornice") == "spento", s)
    finally:
        chiudi(avvio)
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
