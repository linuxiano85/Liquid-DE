#!/usr/bin/env python3
"""Super toccato, Super tenuto, Super+lettera: tre gesti sullo stesso tasto.

── Perché esiste ──────────────────────────────────────────────────────────

La prima regola dei tasti di Liquid DE: «Super da solo è la porta: lo tocchi
e trovi il menù; lo tieni premuto e i tasti compaiono sulla scrivania». Sono
tre gesti che cominciano tutti allo stesso modo (Super giù) e il compositore
li deve separare senza sbagliare mai:

  1. toccato e lasciato: il menù, e basta;
  2. tenuto da solo oltre 400 ms: «tasti», e al rilascio «tasti-via» — e il
     rilascio NON apre il menù, nemmeno se nel frattempo si è premuta una
     lettera;
  3. Super+E: la sua scorciatoia, e né menù né tasti;
  4. tenuto meno di 400 ms: è ancora un tocco;
  5. Super + clic (spostare una finestra): niente menù al rilascio.

I tasti li preme `tasto`, che esiste solo in prova: una tastiera finta DENTRO
il compositore, che passa dagli stessi gestori di quella vera.
"""
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

QUI = Path(__file__).resolve().parent
BUILD = Path(os.environ.get("MINERVA_BIN", QUI / "build-native")).resolve()

passate = 0
fallite = 0


def verifica(cosa, ok, dettaglio=None):
    global passate, fallite
    if ok:
        passate += 1
        print(f"  ok   {cosa}")
    else:
        fallite += 1
        print(f"  NO   {cosa}  → {dettaglio}")


def aspetta(f, quanto=20):
    scadenza = time.monotonic() + quanto
    while time.monotonic() < scadenza:
        v = f()
        if v:
            return v
        time.sleep(0.2)
    raise RuntimeError("non è successo in tempo")


def chiedi(canale, riga):
    with socket.socket(socket.AF_UNIX) as s:
        s.settimeout(5)
        s.connect(canale)
        s.sendall((riga + "\n").encode())
        return s.recv(65536).decode().strip()


class Ascolto:
    def __init__(self, canale, nomi):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(canale)
        self.s.settimeout(0.05)
        self.s.sendall(f"ascolta {nomi}\n".encode())
        self.resto = ""

    def azioni(self, secondi):
        out = []
        fine = time.monotonic() + secondi
        while time.monotonic() < fine:
            try:
                self.resto += self.s.recv(65536).decode()
            except socket.timeout:
                continue
            *intere, self.resto = self.resto.split("\n")
            for r in intere:
                a = re.search(r'"azione":"([^"]*)"', r)
                if r.startswith("evento scorciatoia") and a:
                    out.append(a[1])
        return out


def main():
    figli = []
    with tempfile.TemporaryDirectory(prefix="liquid-de-super-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "super.log"
        with registro.open("w") as log:
            try:
                comp = subprocess.Popen([str(BUILD / "minerva-wayland")], env=amb,
                                        stdout=log, stderr=log)
                figli.append(comp)

                def capi():
                    assert comp.poll() is None, "il compositore è morto"
                    t = registro.read_text(errors="replace")
                    c = re.search(r"^minerva-wayland: canale su (.+)$", t, re.M)
                    return c[1] if c else None

                canale = aspetta(capi)
                # Le stesse righe che manda il demone da config/scorciatoie.minerva.
                for riga in ("scorciatoia - Super_L tocco minerva:appmenu",
                             "scorciatoia - Super_L tieni minerva:tasti",
                             "scorciatoia SUPER e - minerva:files"):
                    r = chiedi(canale, riga)
                    assert r.startswith("ok"), (riga, r)
                ascolto = Ascolto(canale, "scorciatoia")
                ascolto.azioni(0.3)

                def tasto(nome, come):
                    r = chiedi(canale, f"tasto {nome} {come}")
                    assert r.startswith("ok"), r

                # 1. Il tocco.
                tasto("Super_L", "premi"); time.sleep(0.05); tasto("Super_L", "lascia")
                visti = ascolto.azioni(0.7)
                verifica("Super toccato apre il menù, e basta", visti == ["appmenu"], visti)

                # 2. Tenuto.
                tasto("Super_L", "premi"); time.sleep(0.7)
                visti = ascolto.azioni(0.1)
                verifica("Super tenuto 700 ms: compaiono i tasti", visti == ["tasti"], visti)
                tasto("Super_L", "lascia")
                visti = ascolto.azioni(0.5)
                verifica("lasciandolo i tasti se ne vanno e il menù NON si apre",
                         visti == ["tasti-via"], visti)

                # 2b. Tenuto, e poi una lettera: i tasti se ne vanno comunque
                # al rilascio di Super (restavano sullo schermo per sempre).
                tasto("Super_L", "premi"); time.sleep(0.7)
                tasto("e", "premi"); tasto("e", "lascia"); tasto("Super_L", "lascia")
                visti = ascolto.azioni(0.5)
                verifica("tenuto, poi Super+E: i tasti, i file, e i tasti se ne vanno",
                         visti == ["tasti", "files", "tasti-via"], visti)

                # 3. Super+E.
                tasto("Super_L", "premi"); tasto("e", "premi"); tasto("e", "lascia")
                time.sleep(0.6); tasto("Super_L", "lascia")
                visti = ascolto.azioni(0.5)
                verifica("Super+E (anche lento): i file, né menù né tasti", visti == ["files"], visti)

                # 4. Tenuto poco.
                tasto("Super_L", "premi"); time.sleep(0.2); tasto("Super_L", "lascia")
                visti = ascolto.azioni(0.7)
                verifica("tenuto 200 ms è ancora un tocco", visti == ["appmenu"], visti)

                # 5. Super + clic.
                chiedi(canale, "dito 400 300")
                tasto("Super_L", "premi"); time.sleep(0.1)
                chiedi(canale, "dito premi"); chiedi(canale, "dito lascia")
                time.sleep(0.6); tasto("Super_L", "lascia")
                visti = ascolto.azioni(0.6)
                verifica("Super + clic: niente menù e niente tasti al rilascio", visti == [], visti)

                # 7. Super+↓ su una finestra a schermo intero: ne esce e torna
                # com'era, senza ridurla (la riduceva restando a schermo
                # intero: tornava senza barra del titolo).
                for riga in ("scorciatoia SUPER f - schermo-intero:0",
                             "scorciatoia SUPER down - sposta-finestra:d"):
                    assert chiedi(canale, riga).startswith("ok")
                display = re.search(r"^minerva-wayland: in ascolto su (\S+)",
                                    registro.read_text(errors="replace"), re.M)[1]
                figli.append(subprocess.Popen(["alacritty"], env=dict(amb, WAYLAND_DISPLAY=display),
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))

                def alacritty():
                    for w in json.loads(chiedi(canale, "finestre")[3:]):
                        if w.get("classe") == "Alacritty":
                            return w
                prima = aspetta(alacritty, 20)
                time.sleep(0.5)
                tasto("Super_L", "premi"); tasto("f", "premi"); tasto("f", "lascia"); tasto("Super_L", "lascia")
                time.sleep(0.5)
                verifica("Super+F la mette a schermo intero", alacritty()["schermoIntero"] is True, alacritty())
                tasto("Super_L", "premi"); tasto("Down", "premi"); tasto("Down", "lascia"); tasto("Super_L", "lascia")
                time.sleep(0.5)
                dopo = alacritty()
                verifica("Super+↓ esce dallo schermo intero, senza ridurla",
                         dopo["schermoIntero"] is False and dopo["ridotta"] is False, dopo)
                verifica("e torna alla misura di prima",
                         (dopo["x"], dopo["y"], dopo["larghezza"], dopo["altezza"])
                         == (prima["x"], prima["y"], prima["larghezza"], prima["altezza"]),
                         (prima, dopo))

                # 6. Fuori prova il verbo non c'è: lo dice il codice, qui si
                # guarda che almeno risponda in prova e rifiuti l'assurdo.
                verifica("un tasto che non esiste si rifiuta",
                         chiedi(canale, "tasto NonEsiste premi").startswith("no"))
            finally:
                for f in figli:
                    f.terminate()
                    try:
                        f.wait(5)
                    except subprocess.TimeoutExpired:
                        f.kill()

    print(f"\n{passate} passate, {fallite} fallite")
    return 1 if fallite else 0


if __name__ == "__main__":
    sys.exit(main())
