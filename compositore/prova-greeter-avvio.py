#!/usr/bin/env python3
"""Il lanciatore della schermata di accesso sceglie bene, e ripiega quando serve.

── Perché esiste ──────────────────────────────────────────────────────────

`scripts/minerva-greeter-avvio` è il comando FISSO che greetd lancia per la
schermata di accesso. Decide a ogni schermata: il nostro compositore, oppure
Hyprland. Sbagliare qui non è un difetto estetico — una schermata di accesso
che non parte, rilanciata all'infinito da greetd, è un computer in cui non si
entra più.

Si provano i quattro casi, col compositore vero senza schermo, una
«schermata» finta al posto di quella vera e una riserva finta al posto di
Hyprland (nessun Hyprland parte davvero):

  1. la schermata finisce bene (si è entrati): esce 0, niente riserva;
  2. la schermata cade subito: il compositore deve PASSARE quell'esito, e il
     lanciatore ripiega sulla riserva;
  3. il compositore non parte proprio: riserva;
  4. Hyprland forzato dall'installazione: riserva, senza nemmeno provare.

Il 2 è quello che chiede qualcosa di nuovo al compositore: prima usciva
sempre con 0 quando il suo programma finiva, e il lanciatore avrebbe creduto
che si fosse entrati.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

QUI = Path(__file__).resolve().parent
RADICE = QUI.parent
BUILD = Path(os.environ.get("MINERVA_BIN", QUI / "build-native")).resolve()
LANCIATORE = RADICE / "scripts" / "minerva-greeter-avvio"

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


def caso(base, nome, sessione, forza=False, backend="headless"):
    lib = base / nome / "lib"
    conf = base / nome / "conf"
    registri = base / nome / "registri"
    runtime = base / nome / "run"
    for d in (lib, conf, registri):
        d.mkdir(parents=True)
    runtime.mkdir(mode=0o700)
    shutil.copy(BUILD / "minerva-wayland", lib / "minerva-wayland")
    s = lib / "minerva-greeter-sessione"
    s.write_text("#!/bin/sh\n" + sessione + "\n")
    s.chmod(0o755)
    (conf / "minerva-greeter.env").write_text(
        f"LAYOUT=it\nFORZA_HYPRLAND={1 if forza else 0}\n")
    amb = {k: v for k, v in os.environ.items()
           if k not in ("WAYLAND_DISPLAY", "DISPLAY", "MINERVA_CANALE")}
    amb.update(MINERVA_PROVA="1", WLR_BACKENDS=backend, WLR_HEADLESS_OUTPUTS="1",
               WLR_RENDERER="gles2", XDG_RUNTIME_DIR=str(runtime),
               MINERVA_GREETER_LIB=str(lib), MINERVA_GREETER_CONF=str(conf),
               MINERVA_GREETER_REGISTRI=str(registri),
               MINERVA_GREETER_PROVA_RISERVA="exit 77")
    r = subprocess.run([str(LANCIATORE)], env=amb, timeout=60,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    registro = (registri / "compositore.log").read_text(errors="replace") \
        if (registri / "compositore.log").exists() else ""
    return r.returncode, registro


def main():
    with tempfile.TemporaryDirectory(prefix="mga-", dir="/tmp") as t:
        base = Path(t)

        esito, reg = caso(base, "a", "sleep 1; exit 0")
        verifica("la schermata finisce bene: esce 0", esito == 0, esito)
        verifica("e la riserva non parte", esito != 77, reg[-300:])
        verifica("e lo dice nel registro", "sul nostro compositore" in reg, reg[-300:])

        esito, reg = caso(base, "b", "exit 3")
        verifica("la schermata cade subito: si ripiega sulla riserva",
                 esito == 77, esito)
        verifica("e il registro dice con quale esito è caduto",
                 "NON è partito (esito 3" in reg, reg[-300:])

        esito, reg = caso(base, "c", "sleep 1; exit 0", backend="nessuno-cosi")
        verifica("il compositore non parte: riserva", esito == 77, esito)

        esito, reg = caso(base, "d", "sleep 1; exit 0", forza=True)
        verifica("Hyprland forzato: riserva senza provare il nostro",
                 esito == 77 and "sul nostro compositore" not in reg, reg[-300:])

    print("──")
    if fallite:
        print(f"FALLITE {fallite} su {passate + fallite}")
        return 1
    print(f"TUTTE PASSATE ({passate})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
