#!/usr/bin/env python3
"""I menù dei programmi: si vedono?

── Il difetto ────────────────────────────────────────────────────────────

Giacomo, 6 settembre 2026: «sui browser almeno, e non so se altrove, abbiamo
lo stesso problema: se clicco il tasto destro vale come sinistro. Ho testato
su chrome e firefox e confermo».

Il tasto NON è sbagliato: misurato col compositore che scrive quello che
riceve e quello che consegna, il destro arriva `0x111` e viene consegnato
`0x111`. Il difetto è a valle — il menù che il programma prova ad aprire non
si vede. Un tasto destro che non apre niente si comporta, agli occhi, come un
tasto sinistro.

In Wayland un menù è un `xdg_popup`: una superficie a sé, figlia della
finestra. Il compositore deve ascoltare `new_popup` e metterla nella scena.
Il nostro ascoltava solo `new_toplevel`, quindi ogni popup veniva creato dal
programma e non lo disegnava nessuno: menù contestuali, tendine, gli elenchi
`<select>` delle pagine web, i suggerimenti.

── Come si prova, e perché con la TASTIERA ───────────────────────────────

Chrome dentro un compositore annidato. Si fotografa, si apre un menù, si
rifotografa: un menù che compare cambia migliaia di pixel.

Il menù si apre con **F10**, non col tasto destro, e non per eleganza. Il clic
lo manda un mouse finto alle coordinate dello schermo VERO: se sopra la
finestra del compositore annidato c'è dell'altro — il browser o il gioco di
chi sta lavorando — il clic finisce là dentro. È successo il 6 settembre 2026:
zero pulsanti arrivati all'annidato, e la prova che si dichiarava rossa per il
motivo sbagliato dopo aver cliccato col destro dentro Steam.

La tastiera invece va **solo a chi ha il fuoco**, e il fuoco glielo diamo noi
dal canale. Nessun rischio di toccare la roba di qualcun altro.

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
import tempfile
import time

QUI = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.environ.get("MINERVA_BIN",
    os.path.join(QUI, "build-native")), "minerva-wayland")
TASTI = os.path.join(QUI, "..", "scripts", "prova-tasti.py")
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
    """Una domanda al compositore della sessione VERA, quello che ci ospita."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"],
                           "minerva-wayland-%s.sock" % os.environ["WAYLAND_DISPLAY"]))
    s.sendall(comando.encode() + b"\n")
    r = s.recv(65536).decode()
    s.close()
    return r


def finestra_annidata():
    for w in json.loads(chiedi("finestre")[3:]):
        if w["classe"] == "wlroots":
            return w
    return None


def scatta(nome, w):
    p = os.path.join(TMP, nome)
    subprocess.run(["grim", "-g", "%d,%d %dx%d"
                    % (w["x"], w["y"], w["larghezza"], w["altezza"]), p],
                   check=True)
    return p


def diversi(a, b):
    r = subprocess.run(["magick", "compare", "-metric", "AE", "-fuzz", "2%",
                        a, b, "null:"], capture_output=True)
    try:
        return float(r.stderr.decode().strip().split()[0])
    except Exception:
        return -1.0


def main():
    chrome = shutil.which("google-chrome-stable") or shutil.which("google-chrome")
    if chrome is None:
        print("SALTATA: serve Chrome, che apre il proprio menù con un xdg_popup.")
        return 0

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(TMP, "minerva-menu.log")
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

    profilo = tempfile.mkdtemp(prefix="minerva-menu-prova-")
    browser = None
    esito = 0
    try:
        amb_c = dict(amb)
        amb_c["WAYLAND_DISPLAY"] = dentro
        amb_c["XDG_SESSION_TYPE"] = "wayland"
        pagina = ("data:text/html,<body style='background:%23fff'>"
                  "<h1>menù</h1><p>tasto destro qui</p></body>")
        browser = subprocess.Popen(
            [chrome, "--ozone-platform=wayland", "--user-data-dir=" + profilo,
             "--no-first-run", "--no-default-browser-check", "--new-window",
             pagina],
            env=amb_c, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(13)

        w = finestra_annidata()
        if w is None:
            print("non trovo la finestra del compositore annidato",
                  file=sys.stderr)
            return 1
        print("  ·  annidato su %s, finestra a %d,%d %dx%d"
              % (dentro, w["x"], w["y"], w["larghezza"], w["altezza"]))

        # ── Davanti a tutto, prima di cliccare ───────────────────────────
        #
        # La finestra del compositore annidato può stare SOTTO un'altra della
        # sessione vera — il browser di chi sta lavorando, per esempio. I clic
        # finirebbero là, e la prova direbbe «nessun menù» dopo aver cliccato
        # col destro dentro il browser di qualcun altro.
        #
        # Successo davvero, il 6 settembre 2026: zero pulsanti arrivati al
        # compositore annidato, e la prova che si dichiarava rossa per il
        # motivo sbagliato.
        chiedi("fuoco %s" % w["id"])
        time.sleep(1.0)
        w = finestra_annidata()

        prima = scatta("menu-prima.png", w)
        subprocess.run(["python3", TASTI, "--tasto", "f10"],
                       capture_output=True)
        time.sleep(2.0)
        dopo = scatta("menu-dopo.png", w)

        d = diversi(prima, dopo)
        print("  ·  pixel cambiati aprendo il menù: %.0f" % d)
        # Millecinquecento pixel è più di qualunque tremolio e meno del più
        # piccolo dei menù di Chrome: misurato, un suggerimento ne cambia
        # duemilaseicento.
        if d < 1500:
            print("ROSSO: non compare nessun menù — il popup viene creato "
                  "e non lo disegna nessuno")
            esito = 1
        else:
            print("VERDE: i menù dei programmi si aprono e si vedono")
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
