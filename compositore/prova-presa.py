#!/usr/bin/env python3
"""La presa implicita: col pulsante giù il puntatore resta a chi è stato premuto.

── Il difetto ────────────────────────────────────────────────────────────

Il 24 settembre 2026, provando a trascinare l'Isola in basso, la capsula
restava «premuta» e non si spostava. Il compositore dava il puntatore alla
superficie SOTTO di lui anche col pulsante giù: appena si usciva dai bordi di
quella premuta, lei smetteva di sentire i movimenti e non riceveva più il
rilascio. Wayland la dà per scontata (è la «presa implicita»), e senza ogni
trascinamento che esce dalla superficie si ferma a metà: la barra di
scorrimento tirata fuori dalla finestra, il testo selezionato oltre il bordo,
le maniglie del menù.

── Come si prova ─────────────────────────────────────────────────────────

Un pannello minimo (`prova-presa.qml`, 400×120 in alto a sinistra) che
scrive dove riceve il puntatore. Dentro un compositore senza schermo il
`dito` preme in (100, 60), scende a (100, 500) — fuori dal pannello — e
lascia. Il pannello deve aver sentito il movimento a y=500 e il rilascio
lì; e dopo il rilascio, un movimento fuori non gli arriva più.
"""
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
PANNELLO = QUI / "prova-presa.qml"

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
        print("SALTATA: serve quickshell per aprire il pannello di prova.")
        return 0
    figli = []
    with tempfile.TemporaryDirectory(prefix="liquid-de-presa-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "presa.log"
        uscita = base / "pannello.log"
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
                figli.append(subprocess.Popen(["qs", "-p", str(PANNELLO)], env=amb_p,
                                              stdout=fuori, stderr=subprocess.STDOUT))

                def c_e_il_pannello():
                    chiedi(canale, "dito 100 60")
                    chiedi(canale, "dito 101 60")
                    return "MOSSO" in uscita.read_text(errors="replace")

                try:
                    aspetta(c_e_il_pannello, 30)
                except RuntimeError:
                    print(uscita.read_text(errors="replace")[-1500:])
                    raise
                inizio = len(uscita.read_text(errors="replace"))

                chiedi(canale, "dito 100 60"); time.sleep(0.2)
                chiedi(canale, "dito premi"); time.sleep(0.2)
                for y in (90, 130, 250, 500):
                    chiedi(canale, f"dito 100 {y}"); time.sleep(0.1)
                chiedi(canale, "dito lascia"); time.sleep(0.4)
                chiedi(canale, "dito 100 600"); time.sleep(0.4)
                righe = uscita.read_text(errors="replace")[inizio:].splitlines()
                eventi = [r[r.index(p):] for r in righe for p in ("PREMUTO", "MOSSO", "LASCIATO", "ANNULLATO") if p in r]

                verifica("il pannello sente la pressione dentro",
                         "PREMUTO 100 60" in eventi, eventi)
                verifica("e il movimento fuori dai suoi bordi, col pulsante giù",
                         "MOSSO 100 500" in eventi, eventi)
                verifica("e il rilascio là fuori",
                         "LASCIATO 100 500" in eventi, eventi)
                verifica("dopo il rilascio il puntatore fuori non è più suo",
                         not any(e.startswith("MOSSO 100 600") for e in eventi), eventi)
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
