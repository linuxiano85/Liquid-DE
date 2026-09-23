#!/usr/bin/env python3
"""Che ogni scorciatoia «minerva:» abbia qualcuno che risponde.

    nomi-scorciatoie.py <radice>

`config/scorciatoie.minerva` dice `-> minerva: launcher`; da qualche parte
nella shell deve esserci un `Core.Scorciatoia { name: "launcher" }`. I due
elenchi devono coincidere, nei due versi.

── Perché questo controllo, e perché adesso ──────────────────────────────

Perché il nome è l'unica cosa che tiene insieme le due metà, e nessuna delle
due si accorge se l'altra cambia. Una scorciatoia senza risposta è un tasto che
si preme e non fa niente — nessun errore, da nessuna parte. Una risposta senza
scorciatoia è codice che non può essere raggiunto.

E adesso perché i compositori sono due: sotto Hyprland il nome viaggia in
`global, quickshell:<nome>`, sotto minerva-wayland in
`evento scorciatoia {"azione":"<nome>"}`. Stesso nome, due strade — e un errore
di battitura le spegne tutte e due insieme.
"""
import glob
import io
import os
import re
import sys

radice = sys.argv[1] if len(sys.argv) > 1 else "."

sorgente = io.open(os.path.join(radice, "config/scorciatoie.minerva"),
                   encoding="utf-8").read()
nomi = set(re.findall(r"->\s*minerva:\s*(\S+)", sorgente))

risposte = set()
for f in glob.glob(os.path.join(radice, "minerva-shell/**/*.qml"),
                   recursive=True):
    testo = io.open(f, encoding="utf-8").read()
    # `Scorciatoia { … name: "x" … }`: il name può non essere la prima riga.
    for m in re.finditer(r'Scorciatoia\s*\{[^}]*?name:\s*"([^"]+)"', testo,
                         re.S):
        risposte.add(m.group(1))

senza = sorted(nomi - risposte)
mai = sorted(risposte - nomi)
if senza:
    print("SENZA-RISPOSTA " + " ".join(senza))
if mai:
    print("MAI-NOMINATE " + " ".join(mai))
if not senza and not mai:
    print("OK %d" % len(nomi))
