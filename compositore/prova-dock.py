#!/usr/bin/env python3
"""prova-dock.py — I tre modi della dock, provati in una sessione vera.

    ./prova-dock.py

── Perché serve una sessione vera ─────────────────────────────────────────

Perché «la dock si è tolta di mezzo» non è un calcolo: è una superficie
layer-shell che scivola fuori dallo schermo. Da fuori non c'è niente da
interrogare, e l'unica alternativa sarebbe confrontare i pixel di una
fotografia — cioè una prova che diventa rossa il giorno che cambia lo sfondo.

Per questo la shell risponde a `qs ipc call minerva dock` con il modo e se si
vede. Stessa ragione per cui il compositore risponde con `"inattivita": N`:
una cosa che non si può guardare da fuori è una cosa che nessuno saprà se ha
smesso di funzionare.

── Cosa prova ─────────────────────────────────────────────────────────────

Il modo «elude», che è quello che non esisteva prima del 2 settembre 2026:
la dock c'è a schermo libero, si ritira quando una finestra le arriva sopra,
e torna quando la finestra se ne va. E che gli altri due modi restino quello
che erano.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

Le impostazioni che questa prova cambia sono quelle della COPIA in
`$TMPDIR/liquid-de-prova-conf`, mai quelle della sessione vera.
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


def demone(valori):
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
    d.sendall((json.dumps({"action": "ciao",
                           "segreto": conf["segreto"]}) + "\n").encode())
    time.sleep(1)
    try:
        d.recv(65536)
    except socket.timeout:
        pass
    d.sendall((json.dumps({"action": "set_settings",
                           "values": valori}) + "\n").encode())
    time.sleep(3)
    d.close()


def pid_shell(dentro):
    for p in subprocess.run(["pgrep", "-x", "qs"], capture_output=True,
                            text=True).stdout.split():
        try:
            amb = open("/proc/%s/environ" % p, "rb").read()
            cmd = open("/proc/%s/cmdline" % p, "rb").read()
        except OSError:
            continue
        if (("WAYLAND_DISPLAY=" + dentro).encode() + b"\0") in amb \
           and b"shell.qml" in cmd:
            return p
    return None


def stato(pid, amb):
    r = subprocess.run(["qs", "ipc", "--pid", pid, "call", "minerva", "dock"],
                       capture_output=True, text=True, env=amb)
    return (r.stdout or r.stderr).strip()


def attendi(pid, amb, atteso, quanto=8.0):
    """Lo stato ci mette un attimo: la dock ha un'animazione e un timer."""
    fine = time.time() + quanto
    ultimo = ""
    while time.time() < fine:
        ultimo = stato(pid, amb)
        if ultimo == atteso:
            return ultimo
        time.sleep(0.4)
    return ultimo


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland.", file=sys.stderr)
        return 2

    avvio = subprocess.Popen(
        [os.path.join(QUI, "prova-annidata.sh")],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    dentro = ""
    inizio = time.time()
    while time.time() - inizio < 60:
        r = avvio.stdout.readline()
        if not r:
            break
        m = re.search(r"compositore su (\S+)", r)
        if m:
            dentro = m.group(1)
        if "shell dentro" in r:
            break

    print("── I tre modi della dock ──")
    if not dentro:
        verifica("la sessione annidata parte", False)
        chiudi(avvio)
        return 1

    amb = dict(os.environ)
    amb["WAYLAND_DISPLAY"] = dentro
    time.sleep(20)

    pid = pid_shell(dentro)
    if pid is None:
        verifica("la shell è dentro la sessione", False)
        chiudi(avvio)
        return 1
    verifica("la shell è dentro la sessione", True)

    term = None
    try:
        # ── Sempre presente ─────────────────────────────────────────────
        demone({"dock.modo": "sempre"})
        verifica("«sempre»: la dock c'è",
                 attendi(pid, amb, "sempre presente") == "sempre presente",
                 stato(pid, amb))

        # ── Elude, a schermo libero ─────────────────────────────────────
        demone({"dock.modo": "elude"})
        verifica("«elude» a schermo libero: la dock c'è",
                 attendi(pid, amb, "elude presente") == "elude presente",
                 stato(pid, amb))

        # ── Elude, con una finestra sopra ───────────────────────────────
        #
        # È il pezzo che non esisteva. Un terminale nasce grande e arriva in
        # fondo allo schermo: la dock deve ritirarsi.
        cliente = None
        for c in ("alacritty", "foot", "kitty", "konsole"):
            if any(os.access(os.path.join(d, c), os.X_OK)
                   for d in os.environ.get("PATH", "").split(os.pathsep)):
                cliente = c
                break
        if cliente is None:
            print("  ·    salto la parte con la finestra: nessun terminale")
        else:
            term = subprocess.Popen([cliente], env=amb,
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
            verifica("«elude» con una finestra sopra: si ritira",
                     attendi(pid, amb, "elude ritirata") == "elude ritirata",
                     stato(pid, amb))

            term.kill()
            term.communicate()
            term = None
            verifica("e torna quando la finestra se ne va",
                     attendi(pid, amb, "elude presente") == "elude presente",
                     stato(pid, amb))

        # ── Si nasconde ─────────────────────────────────────────────────
        #
        # Senza puntatore sopra, si ritira e basta: è il modo di sempre.
        # ── E il puntatore, che non si può spostare da qui ──────────────
        #
        # Se il puntatore dell'ospite capita sopra la dock, la dock NON si
        # nasconde — ed è giusto così. Da dentro una prova annidata il
        # puntatore non si sposta, quindi la risposta viene accettata anche in
        # quella forma: è per questo che l'IPC dice pure il perché.
        #
        # Una prova che pretendesse «ritirata» e basta sarebbe rossa a seconda
        # di dove uno ha lasciato il mouse — cioè inaffidabile, che per una
        # guardia è peggio che non esserci.
        demone({"dock.modo": "nascondi"})
        finale = attendi(pid, amb, "nascondi ritirata")
        verifica("«nascondi»: si ritira, o dice che il puntatore la trattiene",
                 finale in ("nascondi ritirata",
                            "nascondi presente col-puntatore"), finale)
    finally:
        if term is not None:
            term.kill()
            term.communicate()
        chiudi(avvio)
        for q in subprocess.run(["pgrep", "-x", "minerva-wayland"],
                                capture_output=True,
                                text=True).stdout.split():
            try:
                if b"MINERVA_PROVA=1\x00" in open("/proc/%s/environ" % q,
                                                 "rb").read():
                    os.kill(int(q), 15)
            except OSError:
                pass
        time.sleep(2)

    print("──")
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
