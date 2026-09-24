#!/usr/bin/env python3
"""Gli angoli attivi: una sosta nell'angolo si annuncia, un passaggio no.

── Perché esiste ──────────────────────────────────────────────────────────

Liquid DE apre le cose dagli angoli dello schermo (il menù delle app in basso
a sinistra, il Centro di controllo in alto a destra). Il sensore sta nel
compositore (`angolo_guarda` in `src/main.c`), e la parte che conta non è
aprire: è NON aprire per sbaglio. Questa prova guarda che:

  1. una sosta in un angolo si annuncia UNA volta, col nome dell'angolo;
  2. andandosene si annuncia «via»;
  3. passarci attraverso più svelti della sosta non annuncia niente;
  4. i quattro angoli hanno i loro quattro nomi;
  5. il bordo destro NON si apre con una sosta ma con una SPINTA (è dove si
     prende la barra di scorrimento): una spinta piccola non annuncia
     niente, una vera annuncia `bordo` una volta sola, due spinte piccole
     separate da una pausa non si sommano, e negli angoli non c'è bordo.

Il puntatore lo muove `dito`, che esiste solo in prova. Si spinge oltre il
bordo (`dito -10 99999`) e il compositore lo ferma sull'angolo vero, quale che
sia la misura dello schermo.
"""
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

    def righe(self, secondi):
        out = []
        fine = time.monotonic() + secondi
        while time.monotonic() < fine:
            try:
                self.resto += self.s.recv(65536).decode()
            except socket.timeout:
                continue
            *intere, self.resto = self.resto.split("\n")
            out += [r for r in intere if r.startswith("evento ")]
        return out


def main():
    figli = []
    with tempfile.TemporaryDirectory(prefix="liquid-de-angoli-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "angoli.log"
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
                annunci = Ascolto(canale, "angolo bordo")
                annunci.righe(0.3)

                def dito(x, y):
                    r = chiedi(canale, f"dito {x} {y}")
                    assert r.startswith("ok"), r

                dito(400, 300)
                annunci.righe(0.3)

                # 1. La sosta.
                dito(-10, 99999)
                visti = annunci.righe(0.6)
                verifica("una sosta in basso a sinistra si annuncia una volta",
                         len(visti) == 1 and '"quale":"basso-sx"' in visti[0], visti)
                verifica("e dice su quale schermo", visti and '"schermo":"' in visti[0], visti)

                # 2. Andarsene.
                dito(400, 300)
                visti = annunci.righe(0.4)
                verifica("andandosene si annuncia «via»",
                         len(visti) == 1 and '"quale":"via"' in visti[0], visti)

                # 3. Passarci attraverso.
                dito(-10, 99999)
                time.sleep(0.05)
                dito(400, 300)
                visti = annunci.righe(0.5)
                verifica("passarci attraverso in fretta non annuncia niente", visti == [], visti)

                # 4. I quattro nomi.
                for x, y, nome in ((-10, -10, "alto-sx"), (99999, -10, "alto-dx"),
                                   (99999, 99999, "basso-dx"), (-10, 99999, "basso-sx")):
                    dito(400, 300)
                    annunci.righe(0.3)
                    dito(x, y)
                    visti = annunci.righe(0.5)
                    verifica(f"l'angolo {nome} si chiama «{nome}»",
                             len(visti) == 1 and f'"quale":"{nome}"' in visti[0], visti)

                # 5. La spinta sul bordo destro. `dito` oltre il bordo spinge
                # di quanto va oltre.
                dito(400, 300)
                annunci.righe(0.3)
                destra = int(chiedi(canale, "dito 99999 300").split()[1].rstrip(","))
                annunci.righe(0.3)
                dito(400, 300)
                annunci.righe(0.3)

                def bordi(righe):
                    return [r for r in righe if r.startswith("evento bordo ")]

                dito(destra + 30, 300)
                visti = bordi(annunci.righe(0.3))
                verifica("una spinta piccola sul bordo destro non annuncia niente", visti == [], visti)
                dito(destra + 80, 300)
                visti = bordi(annunci.righe(0.3))
                verifica("una spinta vera annuncia il bordo destro",
                         len(visti) == 1 and '"quale":"destra"' in visti[0]
                         and '"schermo":"' in visti[0], visti)
                dito(destra + 200, 300)
                visti = bordi(annunci.righe(0.3))
                verifica("e continuare a spingere non lo ripete", visti == [], visti)

                dito(400, 300)
                dito(destra + 50, 300)
                time.sleep(0.6)
                dito(destra + 50, 300)
                visti = bordi(annunci.righe(0.3))
                verifica("due spinte separate da una pausa non si sommano", visti == [], visti)

                dito(400, 300)
                dito(destra + 500, 300)
                visti = bordi(annunci.righe(0.3))
                verifica("lasciato il bordo, si ri-arma", len(visti) == 1, visti)

                dito(400, 300)
                dito(destra + 500, 5)
                visti = bordi(annunci.righe(0.4))
                verifica("nell'angolo non c'è bordo", visti == [], visti)
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
