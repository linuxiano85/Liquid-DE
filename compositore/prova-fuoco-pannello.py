#!/usr/bin/env python3
"""Un pannello che chiede la tastiera se la prende, o bisogna cliccarci?

── Il difetto ────────────────────────────────────────────────────────────

Giacomo, 6 settembre 2026: «il nostro polkit o come si chiama, quando fa
apparire richiesta di password di root non prende il focus e quindi bisogna
spostare il mouse, cliccare sopra e inserire la password».

`permessi.qml` chiede già `WlrKeyboardFocus.Exclusive`, cioè «datemi la
tastiera appena compaio». Il compositore però dava la tastiera a una
superficie appoggiata **in un posto solo**: dentro `cursore_premuto`, cioè
quando ci si clicca sopra. Una superficie che nasce chiedendola non la
riceveva mai.

Non riguarda solo la password: la ricerca (`search/Palette.qml`) e la guardia
delle impostazioni (`settings/ChangeGuard.qml`) chiedono la stessa cosa.

── Come si prova ─────────────────────────────────────────────────────────

Un pannello minimo (`prova-pannello.qml`) che chiede `Exclusive` e scrive ogni
tasto che riceve. Si apre dentro un compositore annidato, si dà il fuoco alla
finestra dell'annidato e si scrive **senza cliccare niente**. Se il pannello
non riceve una lettera, la tastiera non gliel'ha data nessuno.

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
TASTI = os.path.join(QUI, "..", "scripts", "prova-tasti.py")
PANNELLO = os.path.join(QUI, "prova-pannello.qml")
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


def chiedi(comando):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"],
                           "minerva-wayland-%s.sock" % os.environ["WAYLAND_DISPLAY"]))
    s.sendall(comando.encode() + b"\n")
    r = s.recv(65536).decode()
    s.close()
    return r


def main():
    if shutil.which("qs") is None:
        print("SALTATA: serve quickshell per aprire il pannello di prova.")
        return 0

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(TMP, "minerva-fuoco.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([BIN], stdout=log, stderr=subprocess.STDOUT, env=amb)

    dentro = ""
    for _ in range(24):
        time.sleep(0.5)
        try:
            testo = open(registro, "r", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"^minerva-wayland: in ascolto su (\S+)", testo, re.M)
        if m:
            dentro = m.group(1)
            break
    if not dentro:
        print("il compositore annidato non è partito:", file=sys.stderr)
        print(open(registro, errors="replace").read()[-2000:], file=sys.stderr)
        chiudi(comp)
        return 1

    uscita = os.path.join(TMP, "minerva-pannello.log")
    fuori = open(uscita, "wb")
    pannello = None
    esito = 0
    try:
        amb_p = dict(amb)
        amb_p["WAYLAND_DISPLAY"] = dentro
        pannello = subprocess.Popen(["qs", "-p", PANNELLO], env=amb_p,
                                    stdout=fuori, stderr=subprocess.STDOUT)
        time.sleep(6)

        # Il fuoco alla finestra del compositore annidato, così la tastiera
        # finta ci arriva dentro. Da lì in poi decide lui a chi darla — ed è
        # esattamente la cosa in prova.
        for w in json.loads(chiedi("finestre")[3:]):
            if w["classe"] == "wlroots":
                chiedi("fuoco %s" % w["id"])
                break
        time.sleep(1.0)

        # Si scrive SENZA aver cliccato niente.
        subprocess.run(["python3", TASTI, "abc"], capture_output=True)
        time.sleep(2.0)

        fuori.flush()
        testo = open(uscita, errors="replace").read()
        tasti = re.findall(r"TASTO \d+ (\S)", testo)
        print("  ·  tasti arrivati al pannello: %s"
              % (", ".join(tasti) if tasti else "nessuno"))
        if not tasti:
            print("ROSSO: il pannello ha chiesto la tastiera e non gliel'ha "
                  "data nessuno — bisogna cliccarci sopra")
            esito = 1
        else:
            print("VERDE: un pannello che chiede la tastiera la riceve "
                  "appena compare")
    finally:
        if pannello is not None and pannello.poll() is None:
            pannello.terminate()
            try:
                pannello.wait(5)
            except subprocess.TimeoutExpired:
                pannello.kill()
        chiudi(comp)
        fuori.close()
    return esito


if __name__ == "__main__":
    sys.exit(main())
