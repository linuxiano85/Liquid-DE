#!/usr/bin/env python3
"""La cornice colorata è un ANELLO, o una macchia sotto tutta la finestra?

── Il difetto ────────────────────────────────────────────────────────────

Giacomo, 7 settembre 2026: «quando clicco su uno dei controlli sulla barra il
terminale cambia colore, tutta la finestra compresa la barra del titolo e i
pulsanti. Torna com'è quando chiudo». E poi, che è la prova decisiva:
«quando disattivo l'accento cioè la cornice colorata il problema sparisce».

Attorno a ogni finestra c'è la `maniglia`: il rettangolo che serve ad
afferrarne i bordi per ridimensionarla. Dal 3 settembre 2026 quel rettangolo
viene COLORATO, per fare l'anello luminoso che Giacomo aveva chiesto («che il
colore intorno diventi tipo rgb e giri come una striscia led»). Il commento
accanto spiegava perché sembrava gratis: «è un `wlr_scene_rect` sotto a tutto
il resto, colorarlo è una chiamata».

Solo che non è un anello: è un rettangolo PIENO grande quanto la finestra più
sei pixel per lato, e sta SOTTO la superficie del programma. Con una finestra
opaca se ne vedono solo i bordi — ed era l'effetto voluto. Con una finestra
TRASLUCIDA (Alacritty di Giacomo ha `opacity = 0.85`) il colore traspare da
tutta la finestra, e ogni volta che il fuoco si sposta la finestra si tinge e
si stinge per intero.

Misurato sulla sessione vera prima della correzione: sul testo del terminale
il colore passava da (54, 84, 98) a (50, 114, 131), cioè esattamente una
velatura ciano al 20 % — che è il 15 % di trasparenza di Alacritty più il
resto. La barra del titolo invece cambiava di tre punti soli, perché quella la
disegna cairo ed è opaca: il rettangolo non ci traspare attraverso. È il
dettaglio che ha chiuso la diagnosi.

── Come si prova ─────────────────────────────────────────────────────────

Dentro un compositore annidato, con la cornice accesa di ROSSO PIENO e una
finestra mezza trasparente sopra uno sfondo nero:

  · al CENTRO della finestra non ci deve essere rosso — o l'anello sta
    dipingendo sotto al programma;
  · sul BORDO il rosso ci deve essere — o non si sta provando niente,
    perché la cornice potrebbe essere semplicemente spenta.

La seconda verifica conta quanto la prima. Senza, basterebbe spegnere la
cornice per far passare la prova, che è il modo più tranquillo di cancellare
un difetto invece di ripararlo.
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

# Rosso pieno: lontanissimo da qualunque colore della scrivania, e su un fondo
# nero un eventuale trasudamento si vede al primo pixel.
CORNICE = "FF0000"

passate = 0
fallite = 0


def verifica(cosa, ok, dettaglio=""):
    global passate, fallite
    if ok:
        passate += 1
        print("  SI   %s" % cosa)
    else:
        fallite += 1
        print("  NO   %s%s" % (cosa, ("  → %s" % dettaglio) if dettaglio else ""))


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


def comanda(display, riga):
    """Una riga sul canale di controllo del compositore annidato."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(4)
    s.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"],
                           "minerva-wayland-%s.sock" % display))
    s.sendall(riga.encode() + b"\n")
    r = s.recv(1 << 16).decode(errors="replace")
    s.close()
    return r


def ppm(dati):
    """Legge un PPM binario (P6). Restituisce (larghezza, altezza, pixel)."""
    campi = []
    i = 0
    while len(campi) < 4:
        while dati[i:i + 1].isspace():
            i += 1
        if dati[i:i + 1] == b"#":
            while dati[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while not dati[j:j + 1].isspace():
            j += 1
        campi.append(dati[i:j])
        i = j
    i += 1
    w, h = int(campi[1]), int(campi[2])
    return w, h, dati[i:i + w * h * 3]


def pixel(dati, w, x, y):
    o = (y * w + x) * 3
    return dati[o], dati[o + 1], dati[o + 2]


def main():
    if shutil.which("grim") is None:
        print("SALTATA: serve grim per guardare dentro il compositore.")
        return 0
    if shutil.which("alacritty") is None:
        print("SALTATA: serve una finestra traslucida, e uso alacritty.")
        return 0
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SALTATA: non siamo in una sessione Wayland.")
        return 0

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(TMP, "minerva-cornice.log")
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

    term = None
    try:
        # Cornice FISSA e rossa: fissa e non «gira», o il colore cambierebbe
        # fra la fotografia e il conto.
        r = comanda(dentro, "cornice fisso 4000 " + CORNICE)
        if not r.startswith("ok"):
            print("il compositore non ha accettato la cornice: %s" % r.strip(),
                  file=sys.stderr)
            return 1

        amb_t = dict(amb)
        amb_t["WAYLAND_DISPLAY"] = dentro
        term = subprocess.Popen(
            ["alacritty",
             "-o", "window.opacity=0.5",
             "-o", "colors.primary.background=#000000",
             "-e", "sleep", "90"],
            env=amb_t, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        box = None
        for _ in range(30):
            time.sleep(0.4)
            try:
                risposta = comanda(dentro, "finestre")
            except OSError:
                continue
            try:
                elenco = json.loads(risposta[3:])
            except ValueError:
                continue
            for w in elenco:
                if "alacritty" in (w.get("classe") or "").lower():
                    box = w
                    break
            if box:
                break
        if box is None:
            print("la finestra traslucida non è comparsa dentro l'annidato",
                  file=sys.stderr)
            return 1
        # Un respiro perché il primo fotogramma sia disegnato per intero.
        time.sleep(1.2)

        foto = subprocess.run(["grim", "-t", "ppm", "-"],
                              env={**os.environ, "WAYLAND_DISPLAY": dentro},
                              capture_output=True)
        if foto.returncode != 0:
            print("grim non ha fotografato: %s" % foto.stderr[:200],
                  file=sys.stderr)
            return 1
        w, h, px = ppm(foto.stdout)

        cx = box["x"] + box["larghezza"] // 2
        cy = box["y"] + box["altezza"] // 2
        centro = pixel(px, w, cx, cy)

        # Il bordo: tre pixel FUORI dal lato sinistro, dentro l'anello di sei.
        bx = max(0, box["x"] - 3)
        by = box["y"] + box["altezza"] // 2
        bordo = pixel(px, w, bx, by)

        print("  fotogramma %dx%d · finestra a (%d,%d) %dx%d"
              % (w, h, box["x"], box["y"], box["larghezza"], box["altezza"]))
        print("  centro %s · bordo %s" % (centro, bordo))

        # Prima la guardia: se l'anello non si vede, la prova non prova niente.
        verifica("l'anello colorato si vede sul bordo",
                 bordo[0] > 90 and bordo[1] < 90 and bordo[2] < 90,
                 "sul bordo c'è %s, mi aspettavo del rosso: la cornice è "
                 "spenta e questa prova non sta guardando niente" % (bordo,))

        # E poi il difetto.
        verifica("e NON traspare dal centro di una finestra traslucida",
                 centro[0] < 60,
                 "al centro c'è %s: il rosso della cornice sta dipingendo "
                 "SOTTO il programma, e una finestra traslucida lo lascia "
                 "vedere tutto" % (centro,))
    finally:
        chiudi(term)
        chiudi(comp)
        log.close()

    print()
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
