#!/usr/bin/env python3
"""Una finestra a schermo intero va allo schermo senza essere ricomposta.

── Perché esiste ──────────────────────────────────────────────────────────

Lo scanout diretto è il modo in cui un film a schermo intero costa quasi
niente: il buffer del programma va allo schermo così com'è, e la scheda video
non compone niente. wlroots lo tenta da solo, ma solo se nella lista di
disegno c'è UN elemento: basta una superficie qualunque sopra la finestra —
anche trasparente, anche di tre pixel — e ogni fotogramma si ricompone.

Il 23 settembre 2026 non riusciva mai: sopra ogni film c'erano due superfici
della shell sempre montate — la barra d'uscita, per accorgersi del puntatore
in cima, e il cartello del modo gioco, per reggere il freno dell'inattività.
Adesso quelle due cose le fa il compositore, e questa prova guarda le tre
metà del patto:

  1. a schermo intero la lista ha UN elemento, e i fotogrammi vanno diretti;
  2. il puntatore in cima si annuncia (`evento bordoalto`), una volta per
     arrivo, e si riarma scendendo: è così che la barra sa quando montarsi;
  3. il film FRENA l'inattività da solo, e ridotto smette di frenarla: è il
     freno che prima reggeva il cartello della shell.

La shell qui non c'è. Che lei non rimonti le sue superfici sopra il film lo
dice la misura nella sessione annidata con la shell.
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
    with tempfile.TemporaryDirectory(prefix="minerva-scanout-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "scanout.log"
        with registro.open("w") as log:
            try:
                comp = subprocess.Popen([str(BUILD / "minerva-wayland")], env=amb,
                                        stdout=log, stderr=log)
                figli.append(comp)

                def capi():
                    assert comp.poll() is None, "il compositore è morto"
                    t = registro.read_text(errors="replace")
                    d = re.search(r"^minerva-wayland: in ascolto su (.+)$", t, re.M)
                    c = re.search(r"^minerva-wayland: canale su (.+)$", t, re.M)
                    return (d[1], c[1]) if d and c else None

                display, canale = aspetta(capi)
                amb["WAYLAND_DISPLAY"] = display
                box = json.loads(chiedi(canale, "schermi")[3:])[0]
                w, h = box.get("larghezza", 1280), box.get("altezza", 720)

                # Il blur acceso: è l'effetto che più di tutti mette nodi in
                # lista, e a schermo intero deve sparire con gli altri.
                chiedi(canale, "effetto blur 0.88")
                film = subprocess.Popen(
                    [str(BUILD / "prova-danno-client"), str(w), str(h), "intero"],
                    env=amb, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                figli.append(film)
                aspetta(lambda: "prova-danno" in chiedi(canale, "finestre"))
                time.sleep(1.5)

                # ── 1. Diretto ───────────────────────────────────────────
                d0 = json.loads(chiedi(canale, "danno")[3:])
                time.sleep(2)
                d1 = json.loads(chiedi(canale, "danno")[3:])
                giri = d1["giri"] - d0["giri"]
                lista = (d1["lista"] - d0["lista"]) / max(giri, 1)
                candidati = d1["candidati"] - d0["candidati"]
                diretti = d1["diretti"] - d0["diretti"]
                print(f"  in due secondi: {giri} fotogrammi, lista media {lista:.1f}, "
                      f"candidati {candidati}, diretti {diretti}")
                verifica("a schermo intero la lista di disegno ha un elemento solo",
                         giri > 0 and lista == 1.0, chiedi(canale, "lista"))
                verifica("e ogni fotogramma è un candidato allo scanout",
                         giri > 0 and candidati == giri, (candidati, giri))
                # Sul backend senza schermo wlroots accetta il buffer: la
                # prova vera del piano hardware si fa sul portatile (DRM).
                verifica("e ci va davvero, senza ricomporre",
                         diretti == candidati, (diretti, candidati))

                # ── 2. Il bordo alto ─────────────────────────────────────
                bordo = Ascolto(canale, "bordoalto")
                bordo.righe(0.3)
                chiedi(canale, f"dito {w // 2} {h // 2}")
                chiedi(canale, f"dito {w // 2} 1")
                chiedi(canale, f"dito {w // 2 + 5} 0")
                ev = bordo.righe(1)
                verifica("il puntatore in cima si annuncia, una volta sola",
                         len(ev) == 1 and '"schermo"' in ev[0], ev)
                chiedi(canale, f"dito {w // 2} 40")
                chiedi(canale, f"dito {w // 2} 1")
                verifica("e non si riannuncia restando vicino al bordo",
                         bordo.righe(0.8) == [], None)
                chiedi(canale, f"dito {w // 2} {h // 2}")
                chiedi(canale, f"dito {w // 2} 1")
                verifica("ma sì dopo essere sceso davvero",
                         len(bordo.righe(1)) == 1, None)
                # Senza Super serve una sosta: un passaggio veloce sul bordo,
                # durante un gioco, non deve far scendere niente.
                chiedi(canale, f"dito {w // 2} {h // 2}")
                bordo.righe(0.3)
                chiedi(canale, f"dito {w // 2} 0")
                chiedi(canale, f"dito {w // 2} {h // 2}")
                verifica("un passaggio veloce sul bordo non si annuncia",
                         bordo.righe(0.9) == [], None)

                # ── 3. Il freno dell'inattività ─────────────────────────
                ozio = Ascolto(canale, "inattivo")
                ozio.righe(0.3)
                assert chiedi(canale, "inattivita 1").startswith("ok")
                ev = ozio.righe(2.5)
                verifica("col film visibile l'inattività non si annuncia",
                         ev == [], ev)
                fid = json.loads(chiedi(canale, "finestre")[3:])[0]["id"]
                chiedi(canale, f"riduci {fid} 1")
                ev = ozio.righe(2.5)
                verifica("ridotto, il film smette di frenare",
                         any(e.startswith("evento inattivo ") for e in ev), ev)
                chiedi(canale, f"riduci {fid} 0")
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
