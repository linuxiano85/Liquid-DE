#!/usr/bin/env python3
"""prova-recupero.py — «Minerva (recupero)», provata annidata.

    ./prova-recupero.py

── Perché questa prova conta più di quanto sembri ─────────────────────────

Perché è la RETE. Finché c'è stata la sessione Hyprland, la via di ritorno era
quella: se la scrivania non partiva si sceglieva l'altra voce al login e si
riparava da lì. Col distacco totale (1º settembre 2026) Hyprland se ne va, e
con lui quella rete.

«Minerva (recupero)» la sostituisce: il nostro compositore con dentro un
terminale e nient'altro. Niente demone, niente scrivania, niente servizi —
ogni pezzo in più è un pezzo che può impedirti di arrivare al terminale, che è
esattamente ciò da cui questa sessione deve proteggere.

**Finché non funziona, non si toglie Hyprland.** Questo file è la guardia che
lo dice.

── Cosa NON prova, e va detto ─────────────────────────────────────────────

Non prova l'accesso vero. Quello vuole uscire dalla sessione, scegliere la
voce al login ed entrare: lo può fare solo chi sta davanti alla macchina, e
sta scritto nel piano che va fatto prima di andare avanti.

Prova le tre cose che possono rompersi PRIMA di arrivarci — e sono quelle che
si rompono in silenzio: che il compositore parta, che il terminale nasca
dentro, e che chiudendo l'ultima finestra si esca invece di restare su uno
schermo nero (che è il modo peggiore di fallire per una via di fuga).

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

`WLR_BACKENDS=wayland` e `MINERVA_PROVA=1`. Il contrassegno serve due volte:
per non poter chiudere la sessione vera, e perché `start-minerva-wayland.sh`
scriva in `session-prova.log` invece di azzerare il registro della sessione in
corso — il racconto di come Giacomo è entrato stamattina.
"""
import json
import os
import re
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
sys.path.insert(0, QUI)
from importlib import import_module

_annunci = import_module("prova-annunci")
Canale = _annunci.Canale
chiudi = _annunci.chiudi

passate = 0
fallite = 0


def verifica(nome, cond, dettaglio=""):
    global passate, fallite
    if cond:
        passate += 1
        print("  ok   " + nome)
    else:
        fallite += 1
        print("  NO   " + nome + ("  → " + str(dettaglio) if dettaglio else ""))


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland; wlroots prenderebbe "
              "lo schermo vero.", file=sys.stderr)
        return 2

    sessione = "recupero-prova"
    stato = os.path.join(
        os.environ.get("XDG_STATE_HOME",
                       os.path.expanduser("~/.local/state")),
        "minerva", "sessioni", sessione)
    registro = os.path.join(stato, "session-prova.log")

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    amb["MINERVA_SESSIONE"] = sessione
    # La sola differenza fra la sessione vera e quella di recupero.
    amb["MINERVA_DENTRO"] = os.path.join(RADICE, "scripts",
                                         "minerva-dentro-recupero")
    # Lo mette `scripts/minerva-session-recupero`, ed è la riga per cui
    # chiudendo il terminale non si resta su uno schermo nero.
    amb["MINERVA_ESCI_COL_FIGLIO"] = "1"

    try:
        os.remove(registro)
    except OSError:
        pass

    avvio = subprocess.Popen(
        [os.path.join(RADICE, "scripts", "start-minerva-wayland.sh")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=amb)

    print("── «Minerva (recupero)», annidata ──")

    canale = ""
    for _ in range(60):
        time.sleep(0.5)
        try:
            t = open(registro, errors="replace").read()
        except OSError:
            continue
        m = re.search(r"canale su (\S+)", t)
        if m:
            canale = m.group(1)
            break

    if not canale:
        verifica("il compositore parte", False,
                 "nessun canale in %s" % registro)
        chiudi(avvio)
        return 1
    verifica("il compositore parte", True)

    esito = 0
    c = None
    try:
        # ── Il terminale ────────────────────────────────────────────────
        #
        # Si aspetta invece di guardare subito: il compositore apre il canale
        # prima che il terminale abbia finito di nascere, e chiedere troppo
        # presto direbbe «nessuna finestra» su una sessione che sta bene.
        lista = []
        for _ in range(30):
            time.sleep(0.5)
            c = Canale(canale)
            c.scrivi("finestre")
            r = c.aspetta("ok [", 4)
            c.chiudi()
            c = None
            try:
                lista = json.loads(r[3:]) if r else []
            except ValueError:
                lista = []
            if lista:
                break

        verifica("e dentro c'è un terminale", bool(lista),
                 open(registro, errors="replace").read()[-600:])
        if lista:
            verifica("con una finestra vera, non vuota",
                     (lista[0].get("larghezza") or 0) > 0
                     and (lista[0].get("altezza") or 0) > 0, lista[0])

            # ── E si esce ───────────────────────────────────────────────
            #
            # Chiudendo l'ultima finestra la sessione deve finire e riportare
            # al login. Restare accesi su uno schermo nero è il modo peggiore
            # in cui una via di fuga può fallire: sembra che il computer sia
            # morto, e chi ci è arrivato ci è arrivato perché qualcosa era già
            # rotto.
            c = Canale(canale)
            c.scrivi("chiudi %s" % lista[0]["id"])
            c.aspetta("ok", 4)
            c.chiudi()
            c = None
            uscita = False
            for _ in range(20):
                time.sleep(0.5)
                if avvio.poll() is not None:
                    uscita = True
                    break
            verifica("chiusa l'ultima finestra, la sessione si chiude", uscita,
                     "resta accesa su uno schermo nero")
    finally:
        if c is not None:
            c.chiudi()
        chiudi(avvio)
        # `start-minerva-wayland.sh` esporta MINERVA_PROVA prima di partire, ma
        # il contrassegno lo eredita il COMPOSITORE, non lo script: si cerca
        # lui, che è quello che va spento davvero.
        for q in subprocess.run(["pgrep", "-x", "minerva-wayland"],
                                capture_output=True,
                                text=True).stdout.split():
            try:
                if b"MINERVA_PROVA=1\x00" in open("/proc/%s/environ" % q,
                                                 "rb").read():
                    os.kill(int(q), 15)
            except OSError:
                pass
        time.sleep(2)

    print("──")
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return esito


if __name__ == "__main__":
    sys.exit(main())
