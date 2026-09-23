#!/usr/bin/env python3
"""Che ogni azione mandata al compositore, il compositore sappia farla.

    azioni-scorciatoie.py <radice>

`services/scorciatoie.dart` decide quali azioni valgono per minerva-wayland
(`_sueDavvero`); `compositore/src/main.c` decide quali sa eseguire
(`scorciatoia_esegui`). I due elenchi devono coincidere.

── Perché, e cosa succede se non coincidono ──────────────────────────────

Nei due versi si rompono due cose diverse, e nessuna delle due dà errore:

 · un'azione **dichiarata e non eseguita** è una scorciatoia che si registra,
   si mangia il tasto, e poi non fa niente — il programma sotto non riceve
   nemmeno la pressione, quindi è peggio di un tasto libero;
 · un'azione **eseguita e non dichiarata** è codice del compositore che non può
   essere raggiunto, perché nessuno gli manderà mai quella riga.

È lo stesso controllo dei verbi (`verbi-compositore.py`), applicato all'altra
porta: quella dei tasti.
"""
import io
import os
import re
import sys

radice = sys.argv[1] if len(sys.argv) > 1 else "."

dart = io.open(os.path.join(radice, "minervad/lib/services/scorciatoie.dart"),
               encoding="utf-8").read()
m = re.search(r"_sueDavvero\s*=\s*\{(.*?)\}", dart, re.S)
dichiarate = set(re.findall(r"'([a-z-]+)'", m.group(1))) if m else set()

c = io.open(os.path.join(radice, "compositore/src/main.c"),
            encoding="utf-8").read()
corpo = c[c.index("static void scorciatoia_esegui("):] if \
    "static void scorciatoia_esegui(" in c else ""
corpo = corpo[:corpo.index("\n/// Cerca una scorciatoia")] if \
    "\n/// Cerca una scorciatoia" in corpo else corpo
eseguite = set(re.findall(r'strcmp\(a,\s*"([a-z-]+)"\)', corpo))

muti = sorted(dichiarate - eseguite)
morti = sorted(eseguite - dichiarate)
if muti:
    print("MANGIA-E-NON-FA " + " ".join(muti))
if morti:
    print("MAI-CHIESTE " + " ".join(morti))
if not muti and not morti:
    print("OK %d" % len(dichiarate))
