#!/usr/bin/env python3
"""Il modo risparmio abbassa gli effetti, e all'uscita li rimette com'erano.

── Perché esiste ──────────────────────────────────────────────────────────

A batteria bassa il compositore scende di un gradino da solo: niente blur né
trasparenza, la cornice che gira si ferma, l'elastico si spegne. La parte delicata
non è spegnere: è TORNARE. Se il gradino scrivesse sopra quello che era stato
chiesto, attaccando la corrente gli effetti resterebbero spenti — e chi ha
cambiato l'effetto a batteria bassa perderebbe la sua scelta.

Per questo il compositore tiene due valori per ogni effetto, il chiesto e il
disegnato, e questa prova guarda che:

  1. `risparmio sempre` abbassa quello che si disegna, e lo annuncia;
  2. un effetto chiesto DURANTE il risparmio si ricorda ma non si disegna;
  3. `risparmio mai` torna esattamente al chiesto — quello nuovo, non quello
     di prima;
  4. il verbo rifiuta quello che non è suo, e in prova «auto» non guarda la
     batteria vera (il portatile potrebbe essere al 15 %).

La batteria che scende e il profilo energetico sono provati con UPower finto
in `src/prova-energia.c`.
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


def stato(canale):
    return json.loads(chiedi(canale, "stato")[3:])


class Ascolto:
    def __init__(self, canale, nomi):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(canale)
        self.s.settimeout(0.3)
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
    with tempfile.TemporaryDirectory(prefix="minerva-risparmio-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "risparmio.log"
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
                annunci = Ascolto(canale, "risparmio")
                annunci.righe(0.3)

                # Quello che si chiede, prima di tutto.
                assert chiedi(canale, "effetto blur 0.88").startswith("ok")
                assert chiedi(canale, "cornice gira 4000").startswith("ok")
                assert chiedi(canale, "elastico 1").startswith("ok")
                s = stato(canale)
                verifica("di partenza il risparmio è spento, e gli effetti sono i chiesti",
                         s["risparmio"]["modo"] == "mai" and not s["risparmio"]["attivo"]
                         and s["effetto"] == "blur" and s["cornice"] == "gira"
                         and s["elastico"] == 1.0, s)

                # ── 1. Giù di un gradino ─────────────────────────────────
                r = chiedi(canale, "risparmio sempre")
                s = stato(canale)
                # «nessuno» e non «vetro»: una finestra trasparente senza la
                # sfocatura dietro non si legge (visto in fotografia).
                verifica("«risparmio sempre»: il blur non si disegna, e nemmeno la trasparenza",
                         s["effetto"] == "nessuno", s["effetto"])
                verifica("la cornice smette di girare e resta accesa",
                         s["cornice"] == "fisso", s["cornice"])
                verifica("l'elastico si spegne", s["elastico"] == 0.0, s["elastico"])
                verifica("e lo stato dice perché",
                         s["risparmio"]["attivo"] and s["risparmio"]["motivo"] == "chiesto",
                         s["risparmio"])
                ev = annunci.righe(1)
                verifica("e lo annuncia, una volta",
                         len(ev) == 1 and '"attivo":true' in ev[0], ev)

                # ── 2. Si cambia idea durante il risparmio ──────────────
                assert chiedi(canale, "effetto blur 0.70").startswith("ok")
                assert chiedi(canale, "elastico 2").startswith("ok")
                s = stato(canale)
                verifica("un blur chiesto durante il risparmio non si disegna",
                         s["effetto"] == "nessuno", s["effetto"])
                verifica("ma l'opacità nuova si prende subito",
                         abs(s["effettoAlfa"] - 0.70) < 0.001, s["effettoAlfa"])
                verifica("e l'elastico chiesto non si accende", s["elastico"] == 0.0,
                         s["elastico"])
                verifica("richiederlo uguale non annuncia niente",
                         chiedi(canale, "risparmio sempre").startswith("ok")
                         and annunci.righe(0.6) == [], None)

                # ── 3. Su ────────────────────────────────────────────────
                chiedi(canale, "risparmio mai")
                s = stato(canale)
                verifica("«risparmio mai»: torna il blur",
                         s["effetto"] == "blur", s["effetto"])
                verifica("torna la cornice che gira", s["cornice"] == "gira", s["cornice"])
                verifica("e l'elastico è quello chiesto DURANTE, non quello di prima",
                         s["elastico"] == 2.0, s["elastico"])
                ev = annunci.righe(1)
                verifica("annunciato anche il ritorno",
                         len(ev) == 1 and '"attivo":false' in ev[0], ev)

                # ── 4. Il verbo ──────────────────────────────────────────
                verifica("«risparmio forse» si rifiuta",
                         chiedi(canale, "risparmio forse").startswith("no "), None)
                verifica("una soglia del 3 % si rifiuta",
                         chiedi(canale, "risparmio auto 3").startswith("no "), None)
                r = chiedi(canale, "risparmio auto 30")
                d = json.loads(r[3:]) if r.startswith("ok ") else {}
                verifica("«auto» in prova non guarda la batteria vera",
                         d.get("modo") == "auto" and d.get("soglia") == 30
                         and d.get("attivo") is False and d.get("batteria") is False, r)
                verifica("e gli effetti restano i chiesti",
                         stato(canale)["effetto"] == "blur", None)
            finally:
                for p in reversed(figli):
                    p.terminate()
                for p in reversed(figli):
                    try:
                        p.wait(5)
                    except subprocess.TimeoutExpired:
                        p.kill()

    print("──")
    if fallite:
        print(f"FALLITE {fallite} su {passate + fallite}")
        return 1
    print(f"TUTTE PASSATE ({passate})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
