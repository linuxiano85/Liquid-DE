#!/usr/bin/env python3
"""Legge o scrive `bar.position` nel file delle impostazioni.

    posizione-barra.py <file>            stampa la posizione ('alto' se manca)
    posizione-barra.py <file> basso      la scrive

Esiste per `prove-pannelli.sh`, che deve provare i pannelli in tutti e due i
versi e poi rimettere la barra dov'era. Sta in un file suo e non dentro lo
script perche un documento-qui Python dentro un documento-qui di shell e il
modo piu affidabile di scrivere un file che non si capisce piu.
"""
import io, json, sys

percorso = sys.argv[1]
try:
    d = json.load(open(percorso, encoding="utf-8"))
except Exception:
    d = {}

if len(sys.argv) < 3:
    print(d.get("bar", {}).get("position", "alto"))
else:
    d.setdefault("bar", {})["position"] = sys.argv[2]
    io.open(percorso, "w", encoding="utf-8").write(
        json.dumps(d, indent=2, ensure_ascii=False))
