#!/usr/bin/env python3
"""prova-xwayland.py — Che i programmi X11 dentro minerva-wayland si aprano
e si comandino come tutti gli altri.

    ./prova-xwayland.py

── Perché questa prova esiste ──────────────────────────────────────────────

Perché senza XWayland i programmi che non parlano Wayland — Steam, i giochi,
Wine — dentro il nostro compositore non si aprono **affatto**. Non partono
male, non si vedono storti: non compaiono, e non c'è nessun errore da nessuna
parte, perché senza un `DISPLAY` non c'è proprio niente a cui bussare.

E perché la parte X11 ha tre trappole che un compositore può prendere in
pieno senza che nulla segnali niente:

 1. **Il pid.** Dal lato Wayland il client è UNO SOLO — Xwayland — per tutti
    i programmi X11 insieme. Chi chiede il pid per quella strada dà lo stesso
    numero a Steam, al suo negozio e a ogni gioco, e la shell non li
    distingue più. Il pid vero lo dichiara la finestra (`_NET_WM_PID`), e
    questa prova ne apre DUE per vedere che i numeri siano diversi.

 2. **Le finestre che non compaiono mai.** Qt ne crea due per programma —
    una 1×1 e una 3×3, senza titolo e senza classe — per il copia-e-incolla e
    i metodi di input. Sono finestre a tutti gli effetti, e finivano
    nell'elenco: due voci fantasma nella dock per ogni programma X11.

 3. **La pigrizia.** Xwayland deve partire alla PRIMA finestra X11 e non
    all'avvio della sessione: su una scrivania senza programmi X11 — quella
    normale — non si devono pagare né i suoi processi né la sua memoria.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

`WLR_BACKENDS=wayland` e `MINERVA_PROVA=1`, come le altre. Nessun processo
viene ucciso senza aver prima letto `MINERVA_PROVA` nel suo
`/proc/PID/environ`.
"""
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

# ── Un menù X11, senza toolkit di mezzo ──────────────────────────────────
#
# In X11 un menù a tendina è una finestra come le altre, con un flag che dice
# «il gestore non mi tocchi»: `override_redirect`. Il compositore la deve
# disegnare dove il programma vuole, e NON metterla nell'elenco delle
# finestre — o nella dock compare una voce fantasma per ogni menù aperto.
#
# Si scrive qui invece di aprire il menù di un programma vero perché un menù
# vero dipende da come QUEL programma lo disegna: aprirlo con un clic vuol
# dire provare il toolkit, non noi. Così invece la finestra si dichiara per
# quello che è, e si colora di un magenta che in Minerva non esiste — così
# la si riconosce contando i pixel.
MENU_X11 = r"""
import sys, time
from Xlib import X, display
d = display.Display(sys.argv[1])
s = d.screen()
w = s.root.create_window(100, 100, 200, 150, 0, s.root_depth,
                         X.InputOutput, X.CopyFromParent,
                         background_pixel=0xFF00FF, override_redirect=1,
                         event_mask=X.ExposureMask)
w.map()
d.sync()
print("mappata", flush=True)
time.sleep(float(sys.argv[2]))
"""

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)
from importlib import import_module

_annunci = import_module("prova-annunci")
Canale = _annunci.Canale
carico = _annunci.carico
chiudi = _annunci.chiudi
e_una_prova = _annunci.e_una_prova

BIN = os.path.join(os.environ.get("MINERVA_BIN",
                                  os.path.expanduser("~/.local/bin")),
                   "minerva-wayland")

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


def xwayland_di_prova():
    """I pid degli Xwayland che appartengono a QUESTA prova.

    Non `pgrep -P` sul compositore, e la differenza è costata una riga rossa:
    wlroots avvia Xwayland con una doppia biforcazione — è il modo di non
    lasciarsi dietro processi zombie — e il risultato è che il suo genitore
    non è il compositore ma init. Cercarlo fra i figli vuol dire non trovarlo
    mai, e concludere che XWayland non è partito mentre il programma X11 è lì
    aperto sullo schermo.

    Si riconosce dall'ambiente: Xwayland eredita quello del compositore, e
    quello di una prova porta `MINERVA_PROVA=1`. È lo stesso contrassegno con
    cui si decide chi si può chiudere, ed è l'unico che distingue la prova
    dall'Xwayland della sessione vera.
    """
    trovati = []
    for voce in os.listdir("/proc"):
        if not voce.isdigit():
            continue
        pid = int(voce)
        try:
            if not open("/proc/%d/comm" % pid).read().strip().startswith("Xwayland"):
                continue
            with open("/proc/%d/environ" % pid, "rb") as f:
                if b"MINERVA_PROVA=1" in f.read().split(b"\0"):
                    trovati.append(pid)
        except OSError:
            continue
    return trovati


def prova_menu(canale, display, amb, ascoltatore, dentro):
    """Una finestra «override redirect»: si vede, e non è nell'elenco."""
    try:
        subprocess.run([sys.executable, "-c", "import Xlib"], check=True,
                       capture_output=True)
    except (subprocess.CalledProcessError, OSError):
        print("  ·    salto le prove dei menù: manca python-xlib")
        return
    if not shutil.which("grim"):
        print("  ·    salto le prove dei menù: manca grim")
        return

    amb_x = dict(amb)
    amb_x["DISPLAY"] = display
    amb_x.pop("WAYLAND_DISPLAY", None)

    # Si svuota la coda PRIMA: quello che si sta per verificare è che non
    # arrivi niente, e una coda piena di annunci di prima renderebbe la prova
    # rossa senza che ci sia niente di rotto.
    ascoltatore.leggi(0.3)
    ascoltatore.righe = []

    men = subprocess.Popen([sys.executable, "-c", MENU_X11, display, "25"],
                           env=amb_x, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, text=True)
    try:
        pronta = False
        for _ in range(60):
            if men.poll() is not None:
                break
            riga = men.stdout.readline()
            if riga.strip() == "mappata":
                pronta = True
                break
        verifica("un menù X11 si mappa", pronta, men.poll())
        if not pronta:
            return
        time.sleep(1.5)

        # ── Non deve annunciarsi, e non deve stare nell'elenco ───────────
        verifica("un menù non si annuncia come una finestra",
                 not any(r.startswith("evento aperta ")
                         for r in ascoltatore.leggi(1.5)),
                 ascoltatore.righe[-4:])

        d = Canale(canale)
        d.scrivi("finestre")
        e = d.aspetta("ok [", 4)
        try:
            lista = json.loads(e[3:]) if e else None
        except ValueError:
            lista = None
        verifica("e non compare nell'elenco delle finestre",
                 isinstance(lista, list)
                 and not any((x.get("larghezza"), x.get("altezza")) == (200, 150)
                             for x in lista), lista)
        d.chiudi()

        # ── Ma si VEDE, e esattamente dove l'ha messo il programma ───────
        #
        # La fotografia si scatta DENTRO il compositore annidato, non sullo
        # schermo vero: `grim` parla con lui attraverso `wlr-screencopy`, che
        # minerva-wayland implementa. Nessun clic sulla sessione di chi lancia
        # la prova, e nessuna coordinata da indovinare.
        scatto = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                              "minerva-xwayland-menu.png")
        amb_g = dict(os.environ)
        amb_g["WAYLAND_DISPLAY"] = dentro
        u = subprocess.run(["grim", scatto], env=amb_g, capture_output=True)
        verifica("si riesce a fotografare dentro il compositore",
                 u.returncode == 0 and os.path.exists(scatto), u.stderr[-200:])
        if u.returncode != 0:
            return
        try:
            from PIL import Image
        except ImportError:
            print("  ·    salto il conto dei pixel: manca Pillow")
            return
        im = Image.open(scatto).convert("RGB")
        magenta = (255, 0, 255)
        verifica("e il menù è disegnato dove l'ha chiesto il programma",
                 im.getpixel((105, 105)) == magenta
                 and im.getpixel((295, 245)) == magenta, im.getpixel((105, 105)))
        verifica("e non è né più grande né più piccolo",
                 sum(1 for p in im.get_flattened_data()
                     if p == magenta) == 200 * 150
                 if hasattr(im, "get_flattened_data")
                 else sum(1 for p in list(im.getdata()) if p == magenta)
                      == 200 * 150,
                 "cercavo 30000 pixel magenta")
    finally:
        if men.poll() is None:
            men.terminate()


def main():
    if not os.access(BIN, os.X_OK):
        print("manca %s — lancia prima ./costruisci.sh" % BIN, file=sys.stderr)
        return 2
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non sei in una sessione Wayland; wlroots prenderebbe "
              "lo schermo vero.", file=sys.stderr)
        return 2

    # ── Il cliente X11: un programma Qt costretto su xcb ─────────────────
    #
    # Non un programma X11 puro (xmessage, xclock) e la ragione è la prima
    # trappola: `_NET_WM_PID` lo scrivono i toolkit moderni — Qt, GTK — e non
    # le vecchie librerie Xt. Provare il pid con xmessage vorrebbe dire
    # provarlo dove non c'è, cioè non provarlo. E i programmi che a Giacomo
    # servono davvero — Steam, i giochi — sono Qt o GTK.
    # Qui c'erano `kcalc` e `kwrite`, cioè KDE — e il 26 agosto 2026 KDE è
    # stato disinstallato apposta, perché Minerva non deve dipenderne. Una
    # prova che si spegne quando togli l'ambiente desktop che stai cercando di
    # non usare più prova il contrario di quello che vuoi sapere.
    #
    # `zenity` è GTK3, pesa poco ed è quasi sempre in casa; `pavucontrol` è il
    # ripiego. Le due di KDE restano in fondo: se ci sono, vanno bene lo
    # stesso, ma non comandano più loro.
    # L'ordine conta, e la ragione è la barra del titolo. `zenity --info` apre
    # un DIALOGO, e a un dialogo Minerva non mette la barra: la prova
    # «e la barra del titolo gliela mette Minerva» falliva su una finestra che
    # non doveva averla. Serve una finestra applicativa normale.
    # L'ordine conta, e ognuno dei due criteri è costato un giro di prove.
    #
    # 1. **Finestra normale, non dialogo.** `zenity --info` apre un dialogo, e
    #    a un dialogo Minerva non mette la barra del titolo: la verifica
    #    «e la barra gliela mette Minerva» falliva su una finestra che non
    #    doveva averla.
    # 2. **Due istanze davvero distinte.** `pavucontrol` è a istanza singola:
    #    il secondo lancio rialza la prima finestra invece di aprirne un'altra,
    #    e la prova dei due pid diversi — che è il cuore di questo file —
    #    non aveva più due programmi da confrontare.
    #
    # `cmake-gui` è Qt6, apre una finestra vera, se ne possono aprire quante se
    # ne vuole, e `cmake` è già in casa perché lo chiede hyprpm. Gli altri
    # restano come ripiego, KDE compreso: se c'è va bene, ma non comanda più.
    candidati = (
        ("cmake-gui", []),
        ("kcalc", []),
        ("kwrite", []),
        ("pavucontrol", []),
        ("zenity", ["--info", "--no-wrap", "--text=Minerva prova XWayland"]),
    )
    cliente = None
    for nome, argomenti in candidati:
        if shutil.which(nome):
            cliente = [nome] + argomenti
            break
    if cliente is None:
        print("FERMO: non trovo un programma Qt o GTK da aprire su X "
              "(zenity, pavucontrol, kcalc, kwrite). Non serve un programma X11 "
              "puro come xmessage: quelli non scrivono _NET_WM_PID, e il pid è "
              "proprio la cosa che questa prova verifica.",
              file=sys.stderr)
        return 2

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    amb["MINERVA_COMPOSITORE"] = "minerva-wayland"

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-xwayland.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([BIN], stdout=log, stderr=subprocess.STDOUT,
                            env=amb)

    dentro, canale, display = "", "", ""
    for _ in range(24):
        time.sleep(0.5)
        try:
            testo = open(registro, "r", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"^minerva-wayland: in ascolto su (\S+)", testo, re.M)
        if m:
            dentro = m.group(1)
        m = re.search(r"^minerva-wayland: canale su (\S+)", testo, re.M)
        if m:
            canale = m.group(1)
        m = re.search(r"^minerva-wayland: XWayland su DISPLAY=(\S+)", testo, re.M)
        if m:
            display = m.group(1)
        if dentro and canale and display:
            break

    print("── Prove di XWayland ──")
    verifica("il compositore annuncia un DISPLAY", bool(display), display)
    if not (dentro and canale and display):
        print("il compositore non è partito come si deve. Registro:",
              file=sys.stderr)
        print(open(registro, errors="replace").read()[-2000:], file=sys.stderr)
        chiudi(comp)
        return 1
    print("  ·    display %s   canale %s   DISPLAY %s"
          % (dentro, canale, display))

    # ── La pigrizia, PRIMA di aprire qualunque cosa ──────────────────────
    prima = xwayland_di_prova()
    verifica("Xwayland non è partito finché nessuno lo chiede", not prima,
             prima)

    ascoltatore = None
    uno = due = None
    try:
        ascoltatore = Canale(canale)
        ascoltatore.scrivi("ascolta")
        ascoltatore.aspetta("ok ascolto", 3)

        amb_x = dict(amb)
        amb_x["DISPLAY"] = display
        amb_x["QT_QPA_PLATFORM"] = "xcb"
        # Lo stesso ordine per GTK: senza, `zenity` andrebbe su Wayland e la
        # prova aprirebbe una finestra che con XWayland non c'entra niente.
        amb_x["GDK_BACKEND"] = "x11"
        amb_x.pop("WAYLAND_DISPLAY", None)

        uno = subprocess.Popen(cliente, env=amb_x,
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)

        riga = ascoltatore.aspetta("evento aperta ", 25)
        verifica("un programma X11 si apre e si annuncia", riga is not None,
                 ascoltatore.righe[-6:])
        _, c1 = carico(riga) if riga else (None, None)

        dopo = xwayland_di_prova()
        verifica("e ADESSO Xwayland è partito", bool(dopo), dopo)

        if c1 is None:
            verifica("il carico è un oggetto JSON", False, riga)
        else:
            verifica("con il pid VERO del programma, non quello di Xwayland",
                     c1.get("pid") == uno.pid,
                     "%s vs %s" % (c1.get("pid"), uno.pid))
            verifica("con una classe non vuota",
                     bool(c1.get("classe")), c1.get("classe"))
            verifica("con un titolo non vuoto",
                     bool(c1.get("titolo")), c1.get("titolo"))
            verifica("con una misura che non è zero",
                     (c1.get("larghezza") or 0) > 60
                     and (c1.get("altezza") or 0) > 60, c1)
            verifica("e la barra del titolo gliela mette Minerva",
                     c1.get("decorata") is True, c1)

        # ── L'elenco: una finestra sola, non tre ─────────────────────────
        domande = Canale(canale)
        domande.scrivi("finestre")
        elenco = domande.aspetta("ok [", 4)
        try:
            lista = json.loads(elenco[3:]) if elenco else None
        except ValueError:
            lista = None
        verifica("l'elenco risponde con un JSON valido",
                 isinstance(lista, list), elenco)
        if isinstance(lista, list):
            verifica("e ha UNA finestra sola, non le finestre di servizio "
                     "che Qt non mappa mai",
                     len(lista) == 1, lista)
            verifica("e nessuna voce senza titolo né classe",
                     all(x.get("titolo") or x.get("classe") for x in lista),
                     lista)

        # ── Spostare e ridimensionare ────────────────────────────────────
        if c1 is not None:
            domande.righe = []
            domande.scrivi("sposta %s 120 200" % c1["id"])
            verifica("«sposta» risponde ok",
                     domande.aspetta("ok", 4) is not None, domande.righe)
            domande.righe = []
            domande.scrivi("ridimensiona %s 500 400" % c1["id"])
            domande.aspetta("ok", 4)
            time.sleep(1.0)
            domande.righe = []
            domande.scrivi("finestre")
            e2 = domande.aspetta("ok [", 4)
            try:
                l2 = json.loads(e2[3:]) if e2 else None
            except ValueError:
                l2 = None
            mia = next((x for x in (l2 or []) if x.get("id") == c1["id"]), None)
            verifica("e la finestra si è mossa davvero",
                     mia is not None and mia.get("x") == 120
                     and mia.get("y") == 200, mia)
            verifica("e ha preso la misura chiesta",
                     mia is not None and abs((mia.get("larghezza") or 0) - 500) <= 2
                     and abs((mia.get("altezza") or 0) - 400) <= 2, mia)

        # ── Due programmi X11, due pid diversi ───────────────────────────
        #
        # È la trappola numero uno vista dall'altro capo: se il pid venisse
        # dal lato Wayland, questi due numeri sarebbero identici — quello di
        # Xwayland — e la shell non saprebbe più che sono due programmi.
        ascoltatore.righe = []
        due = subprocess.Popen(cliente, env=amb_x,
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
        riga2 = ascoltatore.aspetta("evento aperta ", 25)
        _, c2 = carico(riga2) if riga2 else (None, None)
        verifica("un secondo programma X11 si apre", c2 is not None,
                 ascoltatore.righe[-6:])
        if c1 is not None and c2 is not None:
            verifica("e ha un pid DIVERSO dal primo",
                     c2.get("pid") == due.pid and c2.get("pid") != c1.get("pid"),
                     "%s / %s" % (c1.get("pid"), c2.get("pid")))
            verifica("e un indirizzo diverso",
                     c2.get("id") != c1.get("id"),
                     "%s / %s" % (c1.get("id"), c2.get("id")))

        # ── I menù: disegnati, e fuori dall'elenco ───────────────────────
        prova_menu(canale, display, amb, ascoltatore, dentro)

        # ── «Chiudi» chiude davvero ──────────────────────────────────────
        if c2 is not None:
            ascoltatore.righe = []
            domande.righe = []
            domande.scrivi("chiudi %s" % c2["id"])
            chiusa = ascoltatore.aspetta("evento chiusa ", 10)
            verifica("«chiudi» su una finestra X11 la chiude",
                     chiusa is not None, ascoltatore.righe[-6:])
            _, cc = carico(chiusa) if chiusa else (None, None)
            verifica("e l'annuncio parla di quella giusta",
                     cc is not None and cc.get("id") == c2.get("id"), cc)
            for _ in range(40):
                if due.poll() is not None:
                    break
                time.sleep(0.25)
            verifica("e il programma è uscito davvero",
                     due.poll() is not None, due.poll())

        domande.chiudi()
    finally:
        if ascoltatore is not None:
            ascoltatore.chiudi()
        for p in (uno, due):
            if p is not None and p.poll() is None:
                p.terminate()
        time.sleep(0.5)
        chiudi(comp)

    print("── %d passate, %d fallite ──" % (passate, fallite))
    return 1 if fallite else 0


if __name__ == "__main__":
    sys.exit(main())
