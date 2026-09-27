#!/usr/bin/env python3
"""Il rilascio del pulsante arriva al programma anche dopo un trascinamento.

── Il difetto ────────────────────────────────────────────────────────────

27 settembre 2026, Giacomo: «le finestre una volta aperte non si possono
spostare o chiudere e sono obbligato a chiuderle con alt+f4». Il compositore,
finita una presa (una finestra che si disegna la barra da sé e chiede di
essere spostata, o un aggancio a un bordo), usciva senza consegnare il
rilascio. Il programma aveva visto la pressione e mai il rilascio, e il sedile
di wlroots contava il pulsante ancora giù: alla pressione seguente ne contava
due e non la consegnava. Da lì nessun clic arrivava più a nessuno.

── Come si prova ─────────────────────────────────────────────────────────

Una finestra (`prova-rilascio.qml`) che si sposta da sé con
`startSystemMove`, come la barra delle app di Minerva. Si trascina, poi la si
aggancia al bordo sinistro trascinandola, e dopo ognuno dei due gesti un clic
semplice dentro deve arrivarle intero: pressione, rilascio, clic.
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
from pathlib import Path

QUI = Path(__file__).resolve().parent
BUILD = Path(os.environ.get("MINERVA_BIN", QUI / "build-native")).resolve()
FINESTRA = QUI / "prova-rilascio.qml"

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


def main():
    if shutil.which("qs") is None:
        print("SALTATA: serve quickshell per aprire la finestra di prova.")
        return 0
    figli = []
    with tempfile.TemporaryDirectory(prefix="liquid-de-rilascio-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "rilascio.log"
        uscita = base / "finestra.log"
        with registro.open("w") as log, uscita.open("w") as fuori:
            try:
                comp = subprocess.Popen([str(BUILD / "minerva-wayland")], env=amb,
                                        stdout=log, stderr=log)
                figli.append(comp)

                def capi():
                    assert comp.poll() is None, "il compositore è morto"
                    t = registro.read_text(errors="replace")
                    c = re.search(r"^minerva-wayland: canale su (.+)$", t, re.M)
                    d = re.search(r"^minerva-wayland: in ascolto su (\S+)", t, re.M)
                    return (c[1], d[1]) if c and d else None

                canale, display = aspetta(capi)
                amb_p = dict(amb, WAYLAND_DISPLAY=display, QT_QPA_PLATFORM="wayland")
                figli.append(subprocess.Popen(["qs", "-p", str(FINESTRA)], env=amb_p,
                                              stdout=fuori, stderr=subprocess.STDOUT))

                def dove():
                    r = chiedi(canale, "finestre")
                    if not r.startswith("ok "):
                        return None
                    elenco = [f for f in json.loads(r[3:]) if f["titolo"] == "prova-rilascio"]
                    return elenco[0] if elenco else None

                f = aspetta(dove, 30)
                time.sleep(0.8)
                chiedi(canale, f"sposta {f['id']} 300 200")
                time.sleep(0.4)

                def eventi_da(inizio):
                    righe = uscita.read_text(errors="replace")[inizio:].splitlines()
                    return [r[r.index(p):].split()[0] for r in righe
                            for p in ("PREMUTO", "LASCIATO", "CLIC", "SPOSTAMI") if p in r]

                def clic_dentro(nome):
                    g = dove()
                    inizio = len(uscita.read_text(errors="replace"))
                    x, y = g["x"] + 250, g["y"] + 150
                    chiedi(canale, f"dito {x} {y}"); time.sleep(0.2)
                    chiedi(canale, "dito premi"); time.sleep(0.1)
                    chiedi(canale, "dito lascia"); time.sleep(0.5)
                    ev = eventi_da(inizio)
                    verifica(f"{nome}: un clic dentro arriva intero",
                             ev[:3] == ["PREMUTO", "LASCIATO", "CLIC"], ev)

                def trascina(da, a):
                    chiedi(canale, f"dito {da[0]} {da[1]}"); time.sleep(0.2)
                    chiedi(canale, "dito premi"); time.sleep(0.1)
                    for i in range(1, 11):
                        x = da[0] + (a[0] - da[0]) * i // 10
                        y = da[1] + (a[1] - da[1]) * i // 10
                        chiedi(canale, f"dito {x} {y}"); time.sleep(0.04)
                    time.sleep(0.2)
                    chiedi(canale, "dito lascia"); time.sleep(0.6)

                clic_dentro("prima di tutto")

                # 1. Un trascinamento chiesto dal programma.
                g = dove()
                inizio = len(uscita.read_text(errors="replace"))
                trascina((g["x"] + 100, g["y"] + 50), (g["x"] + 250, g["y"] + 150))
                h = dove()
                verifica("la finestra chiede di essere spostata",
                         "SPOSTAMI" in eventi_da(inizio), eventi_da(inizio))
                verifica("e si sposta", (h["x"], h["y"]) != (g["x"], g["y"]),
                         (g["x"], g["y"], h["x"], h["y"]))
                clic_dentro("dopo un trascinamento")

                # 2. Un trascinamento che finisce agganciato al bordo sinistro.
                g = dove()
                trascina((g["x"] + 100, g["y"] + 50), (0, g["y"] + 50))
                h = dove()
                verifica("trascinata al bordo sinistro si aggancia",
                         h["x"] <= 10 and h["altezza"] > g["altezza"], h)
                clic_dentro("dopo un aggancio")
            finally:
                for f in reversed(figli):
                    f.terminate()
                    try:
                        f.wait(5)
                    except subprocess.TimeoutExpired:
                        f.kill()

    print(f"\n{passate} passate, {fallite} fallite")
    return 1 if fallite else 0


if __name__ == "__main__":
    sys.exit(main())
