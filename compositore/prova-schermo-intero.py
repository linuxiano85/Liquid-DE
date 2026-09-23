#!/usr/bin/env python3
"""Una finestra che nasce a schermo intero, nasce a schermo intero?

── Il difetto ────────────────────────────────────────────────────────────

Giacomo, 5 settembre 2026: «tomb raider installato quando lo avvio non si
avvia a schermo intero ma ho la dock e la barra in alto».

Un programma che vuole nascere a schermo intero lo chiede **prima di
comparire**: una finestra xdg manda `set_fullscreen` prima del primo commit,
una X11 si mette `_NET_WM_STATE_FULLSCREEN` fra le proprietà iniziali. In
tutti e due i casi la richiesta arriva quando la finestra non c'è ancora, e
il compositore la lasciava cadere:

 · per una xdg, `chiede_schermo` usciva subito perché la superficie non è
   ancora inizializzata;
 · per una X11 lo stato è già scritto alla nascita, e il segnale di
   CAMBIAMENTO non scatta mai.

Nessuno lo riguardava alla comparsa. Il gioco si apriva grande quanto lo
schermo ma come finestra normale — con la barra e la dock sopra.

── Come si prova ─────────────────────────────────────────────────────────

Alacritty sa nascere a schermo intero (`window.startup_mode`). Si apre dentro
un compositore annidato e si chiede al canale come sta: deve dire
`schermoIntero: true` e occupare tutto lo schermo, non un pixel di meno.

Nessun processo viene ucciso senza aver prima letto `MINERVA_PROVA` nel suo
`/proc/PID/environ`.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.environ.get("MINERVA_BIN",
    os.path.join(QUI, "build-native")), "minerva-wayland")
TMP = os.environ.get("TMPDIR", "/tmp")


def nostro(pid):
    try:
        with open("/proc/%d/environ" % pid, "rb") as f:
            return b"MINERVA_PROVA=1" in f.read().split(b"\0")
    except OSError:
        return False


def chiudi(p):
    if p is None or p.poll() is not None:
        return
    if not nostro(p.pid):
        print("NON chiudo %d: non porta MINERVA_PROVA" % p.pid, file=sys.stderr)
        return
    p.terminate()
    try:
        p.wait(6)
    except subprocess.TimeoutExpired:
        p.kill()


def chiedi(canale, comando):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(canale)
    s.sendall(comando.encode() + b"\n")
    r = s.recv(1 << 16).decode()
    s.close()
    return r


def main():
    if shutil.which("alacritty") is None:
        print("SALTATA: serve alacritty, che sa nascere a schermo intero.")
        return 0

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(TMP, "minerva-schermo-intero.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([BIN], stdout=log, stderr=subprocess.STDOUT, env=amb)

    dentro = canale = ""
    for _ in range(24):
        time.sleep(0.5)
        try:
            testo = open(registro, "r", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"^minerva-wayland: in ascolto su (\S+)", testo, re.M)
        if m:
            dentro = m.group(1)
        m = re.search(r"^minerva-wayland: canale su (\S+)", testo, re.M)
        if m:
            canale = m.group(1)
        if dentro and canale:
            break
    if not (dentro and canale):
        print("il compositore annidato non è partito:", file=sys.stderr)
        print(open(registro, errors="replace").read()[-2000:], file=sys.stderr)
        chiudi(comp)
        return 1

    term = None
    esito = 0
    try:
        amb_c = dict(amb)
        amb_c["WAYLAND_DISPLAY"] = dentro
        term = subprocess.Popen(
            ["alacritty", "-o", 'window.startup_mode="Fullscreen"'],
            env=amb_c, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(5)

        r = chiedi(canale, "finestre")
        finestre = json.loads(r[3:]) if r.startswith("ok ") else []
        if not finestre:
            print("nessuna finestra dentro il compositore annidato",
                  file=sys.stderr)
            return 1
        f = finestre[0]
        print("  ·  «%s»  %dx%d a %d,%d   schermoIntero=%s"
              % (f["titolo"][:30], f["larghezza"], f["altezza"],
                 f["x"], f["y"], f["schermoIntero"]))

        if not f["schermoIntero"]:
            print("ROSSO: ha chiesto lo schermo intero prima di comparire e "
                  "nessuno l'ha ascoltata — si apre come finestra normale, "
                  "con la barra e la dock sopra")
            esito = 1
        else:
            print("VERDE: nasce a schermo intero, come aveva chiesto")
    finally:
        chiudi(term)
        chiudi(comp)
    return esito


if __name__ == "__main__":
    sys.exit(main())
