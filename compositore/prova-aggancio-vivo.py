#!/usr/bin/env python3
"""prova-aggancio-vivo.py — Lo snap misurato in una sessione vera.

    ./prova-aggancio-vivo.py

── Perché esiste ──────────────────────────────────────────────────────────

Giacomo, 2 settembre 2026: «bisogna sistemare lo snap perché funziona malissimo
perché posiziona male le finestre».

Il conto puro è già provato — `prova-aggancio.c`, ventiquattro casi con dei
numeri — e passa. Quindi il difetto, se c'è, non sta lì: sta in quello che gli
si dà in pasto (lo spazio UTILE) o in come si applica il risultato (la barra
del titolo, la cornice, la scala 1,25 di questo portatile).

Nessuna di quelle tre cose si vede da un conto isolato. Questa prova le prende
tutte e tre insieme: chiede al compositore lo spazio utile che LUI crede di
avere, aggancia una finestra vera in tutte e sette le zone, e per ognuna
confronta la geometria ottenuta con quella attesa.

── Un pixel di tolleranza, e non di più ───────────────────────────────────

Metà di una larghezza dispari si prende per difetto e l'altra è «quello che
resta» (vedi `aggancio.c`), quindi le due metà possono differire di uno. Tutto
il resto deve tornare esatto: una tolleranza larga è il modo in cui una prova
smette di trovare i difetti che è stata scritta per trovare.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

E il canale si legge dal registro del compositore annidato, mai da
`MINERVA_CANALE` nell'ambiente: lì c'è quello EREDITATO dalla sessione vera.
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)
from importlib import import_module

chiudi = import_module("prova-annunci").chiudi

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


def atteso(u, zona):
    """Lo stesso conto di `aggancio.c`, riscritto qui apposta.

    Riscriverlo è il punto: se questa prova chiamasse la funzione vera,
    proverebbe che la funzione è uguale a sé stessa. Qui c'è la REGOLA — metà,
    metà, un quarto — e dall'altra parte la sua attuazione.
    """
    x, y, w, h = u["x"], u["y"], u["larghezza"], u["altezza"]
    mw, mh = w // 2, h // 2
    rw, rh = w - mw, h - mh
    return {
        "l":         (x,      y,      mw, h),
        "r":         (x + mw, y,      rw, h),
        "cima":      (x,      y,      w,  h),
        "alto-sx":   (x,      y,      mw, mh),
        "alto-dx":   (x + mw, y,      rw, mh),
        "basso-sx":  (x,      y + mh, mw, rh),
        "basso-dx":  (x + mw, y + mh, rw, rh),
    }[zona]


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland.", file=sys.stderr)
        return 2

    avvio = subprocess.Popen([os.path.join(QUI, "prova-annidata.sh"), "alacritty"],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, bufsize=1)
    dentro, canale = "", ""
    inizio = time.time()
    while time.time() - inizio < 60:
        r = avvio.stdout.readline()
        if not r:
            break
        m = re.search(r"compositore su (\S+)", r)
        if m:
            dentro = m.group(1)
        m = re.search(r"canale su (\S+)", r)
        if m:
            canale = m.group(1)
        if "shell dentro" in r:
            break

    print("── L'aggancio, misurato ──")
    if not dentro:
        verifica("la sessione annidata parte", False)
        chiudi(avvio)
        return 1
    if not canale or dentro not in canale:
        verifica("il canale è quello annidato", False, canale)
        chiudi(avvio)
        return 1

    time.sleep(24)

    def di(verbo):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(6)
        try:
            s.connect(canale)
            s.sendall((verbo + "\n").encode())
            return s.recv(65536).decode("utf-8", "replace").strip()
        except OSError:
            return "(niente)"
        finally:
            s.close()

    try:
        # ── Lo spazio utile, chiesto a chi lo calcola ────────────────────
        #
        # È il primo dei tre sospetti: se `utile` è vecchio o è lo schermo
        # intero invece di quello sotto la barra, ogni aggancio è sbagliato
        # dello stesso numero di pixel — e si vede subito, perché sono tutti
        # sbagliati allo stesso modo.
        try:
            schermi = json.loads(di("schermi")[3:])
        except (ValueError, IndexError):
            schermi = []
        vivi = [s for s in schermi if s.get("attivo") or s.get("acceso")]
        if not vivi:
            verifica("c'è uno schermo", False, di("schermi")[:200])
            return 1
        sc = vivi[0]
        u = {"x": sc["utileX"], "y": sc["utileY"],
             "larghezza": sc["utileLarghezza"], "altezza": sc["utileAltezza"]}
        print("     schermo %dx%d, utile %dx%d a %d,%d, scala %s"
              % (sc["larghezza"], sc["altezza"], u["larghezza"], u["altezza"],
                 u["x"], u["y"], sc.get("scala")))

        verifica("lo spazio utile non è lo schermo intero",
                 u["altezza"] < sc["altezza"] or u["y"] > 0,
                 "utile %dx%d a %d,%d — se è tutto lo schermo, la barra di "
                 "sistema non è nel conto e ogni aggancio finisce sotto di lei"
                 % (u["larghezza"], u["altezza"], u["x"], u["y"]))
        verifica("e non è vuoto",
                 u["larghezza"] > 200 and u["altezza"] > 200, u)

        # ── E poi le sette zone, una per una ─────────────────────────────
        for zona in ("l", "r", "cima", "alto-sx", "alto-dx",
                     "basso-sx", "basso-dx"):
            r = di("aggancia " + zona)
            if not r.startswith("ok "):
                verifica("«%s» si aggancia" % zona, False, r)
                continue
            subito = r
            time.sleep(1.5)
            # La risposta del verbo dice dove il compositore CREDE di averla
            # messa; `finestre` dice dov'è davvero. Si guarda la seconda: fra
            # le due può esserci un ridimensionamento rifiutato dal programma.
            try:
                elenco = json.loads(di("finestre")[3:])
            except (ValueError, IndexError):
                elenco = []
            nostre = [w for w in elenco if w.get("decorata")]
            if not nostre:
                verifica("«%s» si aggancia" % zona, False, "nessuna finestra")
                continue
            w = nostre[0]
            ax, ay, aw, ah = atteso(u, zona)
            dx = abs(w["x"] - ax); dy = abs(w["y"] - ay)
            dw = abs(w["larghezza"] - aw); dh = abs(w["altezza"] - ah)
            if os.environ.get("MINERVA_DIAGNOSI"):
                print("     %-9s verbo=%-22s finestre=%d,%d %dx%d  atteso=%d,%d %dx%d"
                      % (zona, subito, w["x"], w["y"], w["larghezza"],
                         w["altezza"], ax, ay, aw, ah))
            verifica("«%s» finisce dove deve" % zona,
                     dx <= 1 and dy <= 1 and dw <= 1 and dh <= 1,
                     "ottenuto %d,%d %dx%d — atteso %d,%d %dx%d "
                     "(scarto %d,%d %dx%d)"
                     % (w["x"], w["y"], w["larghezza"], w["altezza"],
                        ax, ay, aw, ah, dx, dy, dw, dh))
        # ── «sposta» non deve annullare «ridimensiona» ──────────────────
        #
        # La shell ingrandisce una finestra così, in due comandi attaccati:
        #
        #     ridimensiona <finestra> 1916 952
        #     sposta       <finestra> 2 46
        #
        # e fino al 5 settembre 2026 il secondo cancellava il primo: `sposta`
        # rileggeva la misura di ADESSO — che fra il momento in cui si chiede
        # una misura nuova e quello in cui il programma la accetta è ancora
        # quella vecchia — e la rimandava indietro insieme alla posizione.
        #
        # Sullo schermo: «ingrandisci» spostava la finestra nell'angolo in
        # alto a sinistra e la lasciava della misura di prima. Giacomo: «poi
        # impostazioni non si può massimizzare la finestra».
        try:
            elenco = json.loads(di("finestre")[3:])
        except (ValueError, IndexError):
            elenco = []
        nostre = [w for w in elenco if w.get("decorata")]
        if nostre:
            chi = "address:" + nostre[0]["id"]
            # Misure che CI STANNO nello spazio utile: il compositore non
            # lascia sporgere una finestra sotto la barra, quindi una misura
            # troppo grande viene limitata — e la prova fallirebbe per il
            # limite, non per il difetto.
            larg = min(900, u["larghezza"] - 120)
            alt = min(500, u["altezza"] - 120)
            px = u["x"] + 40
            py = u["y"] + 30
            di("ridimensiona %s 700 400" % chi)
            time.sleep(1.2)
            di("sposta %s 300 200" % chi)
            time.sleep(1.2)

            # I due attaccati, sulla STESSA connessione e senza pause: è
            # esattamente come li manda la shell.
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(6)
            try:
                s.connect(canale)
                s.sendall(("ridimensiona %s %d %d\n"
                           "sposta %s %d %d\n"
                           % (chi, larg, alt, chi, px, py)).encode())
                # Si ASPETTANO le due risposte prima di chiudere: chiudendo
                # subito il compositore può trovarsi la connessione morta a
                # metà lettura, e allora la prova non prova niente.
                letto = b""
                while letto.count(b"\n") < 2:
                    pezzo = s.recv(4096)
                    if not pezzo:
                        break
                    letto += pezzo
            except OSError:
                pass
            finally:
                s.close()
            time.sleep(2)

            try:
                elenco = json.loads(di("finestre")[3:])
            except (ValueError, IndexError):
                elenco = []
            nostre = [w for w in elenco if w.get("decorata")]
            if not nostre:
                verifica("spostare non annulla il ridimensionamento", False,
                         "finestra sparita")
            else:
                w = nostre[0]
                verifica("spostare non annulla il ridimensionamento",
                         abs(w["larghezza"] - larg) <= 1
                         and abs(w["altezza"] - alt) <= 1
                         and abs(w["x"] - px) <= 1 and abs(w["y"] - py) <= 1,
                         "ottenuto %d,%d %dx%d — atteso %d,%d %dx%d"
                         % (w["x"], w["y"], w["larghezza"], w["altezza"],
                            px, py, larg, alt))
    finally:
        chiudi(avvio)

    print("\n  %d passate, %d fallite" % (passate, fallite))
    return 1 if fallite else 0


sys.exit(main())
