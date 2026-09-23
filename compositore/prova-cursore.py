#!/usr/bin/env python3
"""Il puntatore chiesto per FORMA arriva davvero?

── Il difetto ────────────────────────────────────────────────────────────

Giacomo, 5 settembre 2026: «il puntatore quando sono su youtube non posso
vederlo se passo su un video, e anche su altre finestre come questo
terminale».

Nascondere e rimettere il puntatore sono due strade diverse. Si nasconde con
`wl_pointer.set_cursor` e una superficie vuota — e quella la ascoltavamo — e
si rimette col protocollo `cursor-shape-v1`, dicendo il NOME della forma. Quel
protocollo lo ANNUNCIAVAMO e non lo ascoltava nessuno: quindi YouTube
nascondeva il puntatore sopra il video e non lo rimetteva più.

Annunciare e non rispondere è peggio che non annunciare: il programma crede di
aver chiesto e non chiede più in nessun altro modo.

── Come si prova, e perché così ──────────────────────────────────────────

Serve un programma che usi DAVVERO `cursor-shape-v1`, e non tutti lo fanno:
il primo tentativo confrontava il puntatore sopra il testo e sopra il bordo
di un terminale, e restava verde anche con la correzione spenta — perché
quella differenza veniva da altro (il terminale chiede la barretta col
protocollo vecchio, e il bordo lo disegna il compositore da sé). Una prova che
non sa diventare rossa non prova niente.

Chrome invece lo usa. Si apre annidato, con un profilo suo in una cartella
temporanea per non toccare quello vero, si passa il puntatore sopra la sua
finestra, e si guarda se le richieste arrivano — `MINERVA_TRACCIA_FORMA=1` le
scrive nel registro.

Nessun processo viene ucciso senza aver prima letto `MINERVA_PROVA` nel suo
`/proc/PID/environ`.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

QUI = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.environ.get("MINERVA_BIN",
    os.path.join(QUI, "build-native")), "minerva-wayland")
CLIC = os.path.join(QUI, "..", "scripts", "prova-clic.py")
TMP = os.environ.get("TMPDIR", "/tmp")


def nostro(pid):
    """Vero solo se quel processo porta MINERVA_PROVA=1."""
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


def finestra_annidata():
    """Dov'è, sullo schermo vero, la finestra del compositore annidato.

    Si chiama «wlroots» e non «minerva-wayland»: la apre il backend, non noi.
    """
    import json
    import socket
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"],
                           "minerva-wayland-%s.sock" % os.environ["WAYLAND_DISPLAY"]))
    s.sendall(b"finestre\n")
    r = s.recv(65536).decode()
    s.close()
    for w in json.loads(r[3:]):
        if w["classe"] == "wlroots":
            return w
    return None


def main():
    chrome = shutil.which("google-chrome-stable") or shutil.which("google-chrome")
    if chrome is None:
        print("SALTATA: Chrome non c'è, e serve un programma che usi "
              "cursor-shape-v1 davvero.")
        return 0

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb["MINERVA_TRACCIA_FORMA"] = "1"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(TMP, "minerva-cursore.log")
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

    profilo = tempfile.mkdtemp(prefix="minerva-chrome-prova-")
    browser = None
    esito = 0
    try:
        amb_c = dict(amb)
        amb_c["WAYLAND_DISPLAY"] = dentro
        amb_c["XDG_SESSION_TYPE"] = "wayland"
        pagina = ("data:text/html,<h1>ciao</h1><p>testo "
                  "<a href='#'>collegamento</a></p><input>")
        browser = subprocess.Popen(
            [chrome, "--ozone-platform=wayland", "--user-data-dir=" + profilo,
             "--no-first-run", "--no-default-browser-check", "--new-window",
             pagina],
            env=amb_c, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(12)

        w = finestra_annidata()
        if w is None:
            print("non trovo la finestra del compositore annidato",
                  file=sys.stderr)
            return 1
        print("  ·  annidato su %s, finestra a %d,%d %dx%d"
              % (dentro, w["x"], w["y"], w["larghezza"], w["altezza"]))

        # Due passaggi dentro la finestra: uno in mezzo alla pagina, uno verso
        # il bordo. Serve solo che il puntatore ci cammini sopra.
        x0, y0 = w["x"] + 200, w["y"] + 300
        subprocess.run(["python3", CLIC, "muovi", str(x0), str(y0),
                        str(x0 + 200), str(y0 + 20)], capture_output=True)
        time.sleep(1.0)
        subprocess.run(["python3", CLIC, "muovi", str(x0 + 200), str(y0 + 20),
                        str(x0 + 380), str(y0 + 60)], capture_output=True)
        time.sleep(1.5)

        testo = open(registro, errors="replace").read()
        forme = re.findall(r"forma richiesta: (\S+)", testo)
        print("  ·  forme chieste: %s"
              % (", ".join(sorted(set(forme))) if forme else "nessuna"))
        if not forme:
            print("ROSSO: nessuna richiesta di forma è arrivata — il "
                  "protocollo è annunciato e non lo ascolta nessuno")
            esito = 1
        else:
            print("VERDE: le richieste di forma arrivano e vengono servite")
    finally:
        if browser is not None and browser.poll() is None:
            browser.terminate()
            try:
                browser.wait(5)
            except subprocess.TimeoutExpired:
                browser.kill()
        chiudi(comp)
        shutil.rmtree(profilo, ignore_errors=True)
    return esito


if __name__ == "__main__":
    sys.exit(main())
