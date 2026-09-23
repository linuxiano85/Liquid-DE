#!/usr/bin/env python3
"""prova-contrasto.py — La barra si legge? Su sfondo chiaro, scuro e coi tre effetti.

    ./scripts/prova-contrasto.py

── Perché esiste ───────────────────────────────────────────────────────────

Giacomo, 9 settembre 2026: «verifica bene su vari colori chiaro e scuro».

Ha ragione a chiederlo, e c'è un motivo preciso: in `theme/Colors.qml` c'è
scritto che sotto 0,75 di opacità «il testo sopra una finestra di colore
opposto comincia a perdersi», e quel conto è stato fatto **su fondo scuro**.
Nessuno l'ha mai rifatto su un muro bianco. Il cursore si ferma lì per una
soglia che vale in metà dei casi.

E adesso ce n'è una seconda, nata oggi: col blur del compositore la membrana
scende a 0,68 di serie. Dietro c'è una macchia morbida invece di una
fotografia nitida — il che aiuta — ma non la schiarisce né la scurisce. Su uno
sfondo bianco quella macchia resta bianca.

── Che cosa misura ─────────────────────────────────────────────────────────

Il **rapporto di contrasto** (WCAG) fra il testo dell'orologio e il fondo su
cui sta, dentro la fascia della barra. La soglia sotto cui un testo piccolo
non si legge più senza sforzo è 4,5:1 — è lo stesso numero che le Impostazioni
usano già quando si sceglie un colore a mano.

Per ogni combinazione di sfondo (nero, bianco, e le due fotografie vere di
Giacomo), tema e effetto. Non decide niente da solo: stampa una tabella, e le
righe sotto 4,5 sono quelle su cui bisogna prendere una decisione.

── ANNIDATO ───────────────────────────────────────────────────────────────

Come tutto il resto: `compositore/prova-annidata.sh`, configurazione copiata
in `/tmp`. Cambia lo sfondo e il tema decine di volte — non è una cosa da fare
sulla scrivania di qualcuno.
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fotogramma import leggi_png, punto  # noqa: E402

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
CONF_PROVA = os.path.join(os.environ.get("TMPDIR", "/tmp"), "minerva-prova-conf")
FUORI = os.path.join(os.environ.get("TMPDIR", "/tmp"), "minerva-contrasto")

# La soglia. Non è nostra: è quella di WCAG per il testo piccolo, ed è già
# quella che le Impostazioni mostrano quando si sceglie un colore a mano.
SOGLIA_LEGGIBILE = 4.5


def luminanza(rgb):
    """La luminanza relativa di WCAG. Non è la media dei canali: il verde pesa
    sette volte il blu, ed è la ragione per cui un blu scuro e un verde scuro
    che «sembrano uguali» non lo sono affatto per la lettura."""
    c = []
    for v in rgb:
        x = v / 255.0
        c.append(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrasto(a, b):
    la, lb = luminanza(a), luminanza(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def testo_su_fondo(img, x0, y0, x1, y1):
    """Il contrasto fra il testo e il fondo dentro un riquadro.

    Non si sa dove cadano le lettere, e non serve saperlo: dentro la fascia di
    un orologio ci sono due popolazioni di pixel, il fondo (tanti, tutti simili)
    e il testo (pochi, lontani). Si prende la luminanza più comune come fondo e
    quella più lontana da lei come testo.

    È il **caso peggiore** e non la media, che è l'unico modo onesto di
    misurare la leggibilità: un testo si legge se si legge anche nel punto in
    cui va peggio.
    """
    conto = {}
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = punto(img, x, y)
            conto[p] = conto.get(p, 0) + 1
    if not conto:
        return None
    fondo = max(conto, key=lambda k: conto[k])
    # Il testo: il colore più lontano dal fondo, fra quelli che compaiono
    # abbastanza da non essere un pixel di bordo sfumato.
    almeno = max(2, (x1 - x0) * (y1 - y0) // 400)
    candidati = [k for k, n in conto.items() if n >= almeno]
    if not candidati:
        return None
    testo = max(candidati, key=lambda k: contrasto(k, fondo))
    return contrasto(testo, fondo)


class Demone:
    def __init__(self, cartella):
        conf = {}
        with open(os.path.join(cartella, "canale")) as f:
            for riga in f:
                if "=" in riga:
                    k, v = riga.strip().split("=", 1)
                    conf[k] = v
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.settimeout(20)
        self.s.connect(conf["socket"])
        self.f = self.s.makefile("rwb")
        self._manda({"action": "ciao", "segreto": conf["segreto"]})

    def _manda(self, d):
        self.f.write((json.dumps(d) + "\n").encode())
        self.f.flush()

    def scrivi(self, percorso, valore):
        self._manda({"action": "set_setting", "path": percorso, "value": valore})


def sfondi():
    """Le quattro scrivanie su cui si misura, o quelle che si riescono a fare.

    Nero e bianco pieni sono i due estremi, e servono perché una soglia si
    prova ai capi: un fondo medio non dice niente. Le due fotografie vere sono
    il caso di tutti i giorni.
    """
    os.makedirs(FUORI, exist_ok=True)
    fatti = []
    if subprocess.run(["sh", "-c", "command -v magick"],
                      capture_output=True).returncode == 0:
        for nome, colore in (("nero", "black"), ("bianco", "white")):
            dove = os.path.join(FUORI, "%s.png" % nome)
            subprocess.run(["magick", "-size", "1920x1080",
                            "xc:" + colore, dove], capture_output=True)
            fatti.append((nome, dove))
    else:
        print("  --  senza «magick» non si fanno il nero e il bianco pieni")
    # E le fotografie che ci sono davvero sulla macchina.
    casa = os.path.expanduser("~/.config/minerva/settings.json")
    try:
        with open(casa) as f:
            suo = json.load(f).get("desktop", {}).get("wallpaper", "")
        if suo and os.path.exists(suo):
            fatti.append(("la tua", suo))
    except (OSError, ValueError):
        pass
    return fatti


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland.", file=sys.stderr)
        return 1

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-prova-contrasto.log")
    log = open(registro, "w")
    avvio = subprocess.Popen(
        [os.path.join(RADICE, "compositore", "prova-annidata.sh")],
        stdout=log, stderr=subprocess.STDOUT)
    display = None
    for _ in range(40):
        time.sleep(0.5)
        try:
            m = re.search(r"compositore su (\S+)", open(registro).read())
        except OSError:
            continue
        if m:
            display = m.group(1)
            break
    if display is None:
        print("la sessione annidata non è partita — %s" % registro,
              file=sys.stderr)
        avvio.terminate()
        return 1
    print("sessione annidata su %s" % display)
    time.sleep(22)

    scatto = os.path.join(FUORI, "adesso.png")
    amb = dict(os.environ)
    amb["WAYLAND_DISPLAY"] = display
    peggiori = []
    try:
        d = Demone(CONF_PROVA)
        quadri = sfondi()
        if not quadri:
            print("nessuno sfondo su cui misurare", file=sys.stderr)
            return 1

        print("\n  %-10s %-10s %-9s  %s" % ("sfondo", "tema", "effetto",
                                            "contrasto della barra"))
        print("  " + "─" * 56)
        for nome_s, quadro in quadri:
            d.scrivi("desktop.wallpaper", quadro)
            for tema in ("carbone", "giorno"):
                d.scrivi("shell.scheme", tema)
                for effetto in ("nessuno", "vetro", "blur"):
                    d.scrivi("windows.effetto", effetto)
                    time.sleep(4.0)
                    subprocess.run(["grim", scatto], env=amb,
                                   capture_output=True, timeout=20)
                    try:
                        img = leggi_png(scatto)
                    except (OSError, ValueError, KeyError):
                        continue
                    larg = img[0]
                    # La fascia dell'orologio: in mezzo alla barra, dove il
                    # testo c'è sempre e non ci sono icone colorate.
                    c = testo_su_fondo(img, larg // 2 - 90, 6,
                                       larg // 2 + 90, 34)
                    if c is None:
                        continue
                    segno = "  " if c >= SOGLIA_LEGGIBILE else "  ← sotto 4,5"
                    print("  %-10s %-10s %-9s  %6.1f:1%s"
                          % (nome_s, tema, effetto, c, segno))
                    if c < SOGLIA_LEGGIBILE:
                        peggiori.append((nome_s, tema, effetto, c))
    finally:
        avvio.terminate()
        try:
            avvio.wait(timeout=15)
        except subprocess.TimeoutExpired:
            avvio.kill()
        log.close()

    print("")
    if peggiori:
        print("── %d combinazioni sotto la soglia ──" % len(peggiori))
        print("Non sono difetti da riparare a colpi di numero: sono le "
              "condizioni in cui\nla barra chiede più coprente di quanto le "
              "si stia dando. Il rimedio è un\nminimo che dipende dallo "
              "sfondo, non un minimo più alto per tutti.")
        return 1
    print("── tutte le combinazioni restano sopra 4,5:1 ──")
    return 0


if __name__ == "__main__":
    sys.exit(main())
