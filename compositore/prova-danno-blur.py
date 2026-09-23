#!/usr/bin/env python3
"""Il danno incrementale del blur non lascia scie.

── Perché esiste ──────────────────────────────────────────────────────────

Fino al 22 settembre 2026 bastava un nodo di sfocatura in scena perché il
compositore sporcasse TUTTO l'output a ogni fotogramma. Costava otto volte il
lavoro — misurato: 12,3 % dei pixel senza blur, 100 % con — e su un portatile
quello è ventola. Adesso si ridipinge solo il pezzo cambiato, allargato del
raggio del filtro.

Un danno incrementale sbagliato non dà nessun errore: lascia **scie**. Il
pannello continua a mostrare il fondo sfocato di dieci secondi fa, e chi
guarda pensa che sia il blur a essere fatto male.

── Come si prova ──────────────────────────────────────────────────────────

Due finestre. Sotto, un quadrato bianco che salta trenta volte al secondo.
Sopra, un terminale TRASPARENTE e ingrandito, col blur del compositore dietro: quello che si vede attraverso è
il quadrato di sotto, sfocato. Ogni salto del quadrato cambia ciò che il
filtro di sopra deve mostrare — ed è esattamente il caso che il danno
incrementale deve seguire.

Dopo qualche secondo di raffica si FERMA tutto (SIGSTOP), così fra i due
scatti non cambia più niente di vero:

  1. si fotografa: questo è il risultato del disegno incrementale;
  2. si fa ridisegnare tutto da capo — spegnendo e riaccendendo l'effetto —
     e si fotografa di nuovo;
  3. le due fotografie devono combaciare.

Se il danno incrementale ha saltato un pezzo, quel pezzo mostra ancora il
fondo sfocato di prima, e la seconda fotografia è diversa proprio lì. La
prima versione di questa prova metteva il terminale a schermo intero: ma a
schermo intero il blur si spegne apposta, e il terminale copriva la barra —
confrontava cifre che cambiavano, non scie. Rossa per la ragione sbagliata.

Si guarda tutto lo schermo sotto la fascia della barra: la barra ha
l'orologio, che può cambiare minuto fra uno scatto e l'altro.
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageChops

QUI = Path(__file__).resolve().parent
RADICE = QUI.parent
BUILD = Path(os.environ.get("MINERVA_BIN", QUI / "build-native")).resolve()
ALTEZZA_BARRA = 64          # la fascia in cima, con margine
# Nessuna differenza ammessa, nemmeno di un livello. Fino al 23 settembre
# 2026 qui c'erano una soglia di 8 livelli e una tolleranza dello 0,1 %, e
# la prova è rimasta verde con le cuciture vere: linee sottili, da 1 a 12
# livelli, che Giacomo vedeva nel terminale a ogni tasto. Il ridisegno a
# pezzi e quello completo fanno gli stessi conti sugli stessi pixel: devono
# dare la stessa immagine, bit per bit.
SOGLIA = 0                  # un pixel conta se differisce di più di questo
TOLLERANZA = 0.0            # frazione di pixel diversi ammessa


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
    figli = []
    with tempfile.TemporaryDirectory(prefix="minerva-danno-blur-") as tmp:
        base = Path(tmp)
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)
        amb = dict(os.environ)
        for k in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE"):
            amb.pop(k, None)
        amb.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(base / "config"),
                   MINERVA_PROVA="1", WLR_BACKENDS="headless", WLR_HEADLESS_OUTPUTS="1",
                   WLR_RENDERER="gles2")
        registro = BUILD / "danno-blur.log"
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

                # Niente shell. La prima versione la lanciava per avere la barra
                # sfocata — ma senza demone qualcosa lì dentro si ridisegna di
                # continuo, e durante la raffica si ridipingeva l'87,8 % dello
                # schermo: con un danno così grande nessun errore del danno si
                # vede. Il filtro che si prova è quello della finestra
                # trasparente di sopra, e per quello basta il compositore.
                assert chiedi(canale, "effetto blur 0.88").startswith("ok"), "blur rifiutato"
                # Il raggio più grande: è quello che fa sbordare di più la
                # sfumatura fuori dal danno del client.
                assert chiedi(canale, "sfocatura 100").startswith("ok"), "sfocatura rifiutata"

                # Sotto: un quadrato che salta, dichiarando danneggiato SOLO il
                # quadrato (`src/prova-danno-client.c`). Le versioni prima usavano
                # alacritty e poi una finestra Qt: tutte e due dichiarano la
                # finestra intera a ogni fotogramma, il danno copriva sempre il
                # filtro, e la prova è rimasta verde col filtro rotto apposta.
                sotto = subprocess.Popen(
                    [str(BUILD / "prova-danno-client"), "800", "500"],
                    env=amb, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                figli.append(sotto)
                time.sleep(3)
                sopra = subprocess.Popen(
                    ["alacritty", "-o", "window.opacity=0.15",
                     "-o", "cursor.style.blinking=\"Never\"",
                     "-e", "sh", "-c", "sleep 600"],
                    env=amb, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                figli.append(sopra)
                time.sleep(3)
                assert chiedi(canale, "ingrandisci").startswith("ok"), "ingrandisci rifiutato"

                # La raffica: il quadrato salta e il filtro di sopra
                # deve seguirlo, fotogramma dopo fotogramma, col danno piccolo.
                # E si legge il metro: quanto dello schermo si ridipinge. Se
                # fosse il cento per cento, la prova non potrebbe distinguere
                # un danno giusto da uno sbagliato — e deve dirlo.
                import json

                def quota(secondi):
                    d0 = json.loads(chiedi(canale, "danno")[3:])
                    time.sleep(secondi)
                    d1 = json.loads(chiedi(canale, "danno")[3:])
                    return ((d1["pixel"] - d0["pixel"]) / max(1, d1["schermo"] - d0["schermo"]),
                            f'{d1["fotogrammi"] - d0["fotogrammi"]}, di cui interi '
                            f'{d1["interi"] - d0["interi"]}; fasce '
                            f'{100 * (d1.get("fasce", 0) - d0.get("fasce", 0)) / max(1, d1["schermo"] - d0["schermo"]):.1f} %; '
                            f'disegno {(d1.get("gpuNs", 0) - d0.get("gpuNs", 0)) / max(1, d1.get("gpuFotogrammi", 0) - d0.get("gpuFotogrammi", 0)) / 1e6:.2f} ms')

                # Il cronometro del disegno: i pixel dicono quanto si
                # ridipinge, questo quanto costa (vedi `gpu` in main.c).
                chiedi(canale, "gpu acceso")
                chiedi(canale, "effetto nessuno")
                time.sleep(0.5)
                base, fb = quota(4)
                chiedi(canale, "effetto blur 0.88")
                chiedi(canale, "sfocatura 100")
                time.sleep(0.5)
                col_blur, fc = quota(5)
                print(f"durante la raffica si ridipinge: {100 * base:.1f} % senza blur "
                      f"({fb} fotogrammi), {100 * col_blur:.1f} % col blur ({fc} fotogrammi)")
                # Fermi tutti e due: da qui fra gli scatti non cambia niente.
                for p in (sotto, sopra):
                    os.kill(p.pid, 19)          # SIGSTOP
                time.sleep(1.0)

                def scatta(nome):
                    p = BUILD / nome
                    subprocess.run(["grim", str(p)], env=amb, check=True,
                                   capture_output=True)
                    im = Image.open(p).convert("RGB")
                    return im.crop((0, ALTEZZA_BARRA, im.width, im.height))

                prima = scatta("danno-blur-1.png")
                chiedi(canale, "effetto nessuno")
                time.sleep(0.6)
                chiedi(canale, "effetto blur 0.88")
                chiedi(canale, "sfocatura 100")
                time.sleep(1.2)
                dopo = scatta("danno-blur-2.png")
                for p in (sotto, sopra):
                    os.kill(p.pid, 18)          # SIGCONT, per chiuderli bene

                assert prima.size == dopo.size, "le due fotografie non combaciano di misura"
                diff = ImageChops.difference(prima, dopo).convert("L")
                diversi = sum(1 for v in diff.get_flattened_data() if v > SOGLIA)
                totale = prima.size[0] * prima.size[1]
                quota = diversi / totale
                print(f"sotto la barra: {diversi} pixel diversi su {totale} "
                      f"({100 * quota:.2f} %)")
                if quota > TOLLERANZA:
                    diff.save(BUILD / "danno-blur-differenza.png")
                    raise AssertionError(
                        f"il danno incrementale lascia scie: {100 * quota:.2f} % dello "
                        f"schermo cambia quando si ridisegna tutto da capo "
                        f"(vedi {BUILD / 'danno-blur-differenza.png'})")
                print("ok: nessuna scia — quello che si vede è quello che si vedrebbe "
                      "ridisegnando tutto")
            finally:
                for p in reversed(figli):
                    p.terminate()
                for p in reversed(figli):
                    try:
                        p.wait(5)
                    except subprocess.TimeoutExpired:
                        p.kill()


if __name__ == "__main__":
    sys.exit(main())
