#!/usr/bin/env python3
"""prova-annunci.py — Che il compositore ANNUNCI, e non solo risponda.

    ./prova-annunci.py

Accende minerva-wayland annidato, si iscrive al canale con `ascolta`, apre e
chiude una finestra vera, e verifica che gli annunci arrivino nell'ordine
giusto e con dentro le cose giuste.

── Perché serve una finestra vera ─────────────────────────────────────────

Perché il pezzo che si sta provando è il legame fra il ciclo di eventi di
wlroots e il socket: un finto non lo tocca. Le prove del demone
(`minervad/test/minerva_provider_test.dart`) usano un compositore finto e
provano la lettura delle righe; questa prova gira dall'altro capo e prova che
quelle righe qualcuno le scriva davvero.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

`WLR_BACKENDS=wayland` e `MINERVA_PROVA=1`, come `prova-annidata.sh`. Nessun
processo viene ucciso senza aver prima letto `MINERVA_PROVA` nel suo
`/proc/PID/environ`.
"""
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import cartelle  # noqa: E402  le cartelle di Liquid DE
import time

QUI = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(cartelle.cartella_bin(),
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


def e_una_prova(pid):
    """Vero solo se quel processo porta MINERVA_PROVA=1.

    È la riga che permette di chiudere una prova senza rischiare di chiudere
    la sessione di chi la lancia: senza, `kill` su un pid trovato per nome è
    una scommessa. Vedi `minerva-trappole-prove`.
    """
    try:
        with open("/proc/%d/environ" % pid, "rb") as f:
            return b"MINERVA_PROVA=1" in f.read().split(b"\0")
    except OSError:
        return False


def _figli(pid):
    """I figli diretti di un processo, secondo il kernel."""
    try:
        with open("/proc/%d/task/%d/children" % (pid, pid)) as f:
            return [int(x) for x in f.read().split()]
    except OSError:
        return []


def _albero(pid):
    """`pid` e tutti i suoi discendenti, dal basso verso l'alto."""
    fuori = []
    for f in _figli(pid):
        fuori += _albero(f)
    fuori.append(pid)
    return fuori


def chiudi(p):
    """Chiude una sessione annidata: lo script che l'ha avviata e tutto ciò
    che ne è nato.

    ── Il difetto che questa funzione ha avuto fino al 3 settembre 2026 ─────

    Chiudeva soltanto `p`, e prima di farlo chiedeva `e_una_prova(p.pid)`.
    `p` è il processo di `prova-annidata.sh`, e quello script fa
    `export MINERVA_PROVA=1` DOPO essere partito.

    E qui sta la trappola: **`/proc/<pid>/environ` è un'istantanea presa
    all'exec**, non l'ambiente vivo. Una variabile esportata dopo non ci
    compare mai. Quindi la guardia rispondeva sempre di no, stampava
    «NON chiudo il pid N», e non chiudeva niente.

    Il costo, misurato lo stesso giorno nella sessione vera di Giacomo: sei
    compositori di prova ancora in piedi, **174 MB**, uno per ogni prova
    annidata girata quel pomeriggio. E cresceva a ogni giro, in silenzio,
    perché una prova che non chiude non fallisce.

    È la forma peggiore di questa famiglia: non una guardia mancante, ma una
    guardia **troppo stretta**, che non fira mai e quindi non protegge da
    niente mentre sembra proteggere.

    ── Come si ripara senza allentarla ──────────────────────────────────────

    La domanda giusta non è «questo processo è una prova?» ma «questo albero
    è un albero di prova?». Il compositore annidato, che è il figlio, il
    contrassegno ce l'ha davvero — l'ha ricevuto all'exec. Quindi si guarda
    l'albero, si chiude solo ciò che porta il contrassegno, e la sessione vera
    resta fuori esattamente come prima: il suo compositore ha
    `MINERVA_PROVA=0`, ed è la stessa riga a escluderlo.
    """
    if p is None:
        return
    # L'albero si legge PRIMA di mandare qualunque segnale: appena lo script
    # muore i figli vengono adottati da init e non sono più suoi.
    albero = _albero(p.pid) if p.poll() is None else []
    marcati = [q for q in albero if e_una_prova(q)]

    if p.poll() is None:
        if marcati:
            # Lo script che li ha avviati muore col suo albero: è nostro, l'
            # abbiamo lanciato noi in questo processo, e ciò che ne è nato
            # porta il contrassegno.
            p.send_signal(signal.SIGTERM)
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
        else:
            print("  ·    NON chiudo il pid %d: né lui né i suoi figli "
                  "portano MINERVA_PROVA" % p.pid)
            return

    # E poi quelli che il SIGTERM allo script non ha portato via: il
    # compositore annidato non muore col padre, e senza questo giro resta
    # in piedi per sempre.
    for q in marcati:
        try:
            os.kill(q, signal.SIGTERM)
        except OSError:
            pass
    time.sleep(1.5)
    for q in marcati:
        try:
            os.kill(q, signal.SIGKILL)
        except OSError:
            pass


class Canale:
    """Un collegamento al canale, con una coda di righe già lette."""

    def __init__(self, percorso):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(percorso)
        self.resto = b""
        self.righe = []

    def scrivi(self, riga):
        self.s.sendall((riga + "\n").encode())

    def leggi(self, quanto=1.0):
        """Legge quello che c'è entro `quanto` secondi, e lo accoda."""
        fine = time.time() + quanto
        while time.time() < fine:
            self.s.settimeout(max(0.05, fine - time.time()))
            try:
                d = self.s.recv(65536)
            except socket.timeout:
                break
            if not d:
                break
            self.resto += d
            while b"\n" in self.resto:
                r, self.resto = self.resto.split(b"\n", 1)
                self.righe.append(r.decode("utf-8", "replace"))
        return self.righe

    def aspetta(self, prefisso, quanto=6.0):
        """La prima riga che comincia con `prefisso`, o None."""
        fine = time.time() + quanto
        while True:
            for r in self.righe:
                if r.startswith(prefisso):
                    return r
            if time.time() >= fine:
                return None
            self.leggi(0.3)

    def aspetta_se(self, prefisso, giusto, quanto=6.0):
        """La prima riga col prefisso il cui carico soddisfa `giusto`.

        Serve dove `aspetta` non basta, e la differenza è costata una prova
        rossa: gli annunci sono tanti e dello stesso tipo — `evento stato`
        arriva per «ridotta», per «ingrandita» e per «cambiata scrivania» — e
        prendere il primo che capita vuol dire leggere la risposta a una
        domanda di prima. Il prefisso dice di che si parla; solo il carico
        dice se è QUESTO.
        """
        fine = time.time() + quanto
        while True:
            for r in self.righe:
                if r.startswith(prefisso):
                    _, c = carico(r)
                    if c is not None and giusto(c):
                        return r
            if time.time() >= fine:
                return None
            self.leggi(0.3)

    def chiudi(self):
        try:
            self.s.close()
        except OSError:
            pass


def tinte(dentro, regione):
    """Quanti colori diversi ci sono in quel rettangolo dello schermo.

    Si passa da `grim -t ppm`, che è un formato che si legge in venti righe:
    l'alternativa era una libreria di immagini, cioè una dipendenza in più
    perché una prova possa guardare quello che si vede.

    Torna None se non si è potuto guardare — che NON è «a posto»: chi chiama
    deve distinguere «ho guardato e va bene» da «non ho guardato».
    """
    amb = dict(os.environ)
    amb["WAYLAND_DISPLAY"] = dentro
    try:
        r = subprocess.run(["grim", "-g", regione, "-t", "ppm", "-"],
                           env=amb, capture_output=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    d = r.stdout
    if not d.startswith(b"P6"):
        return None
    # Intestazione PPM: P6, larghezza, altezza, massimo — separati da spazi
    # bianchi, con la possibilità di commenti che qui non capitano.
    campi, i = [], 2
    while len(campi) < 3 and i < len(d):
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        campi.append(d[i:j])
        i = j
    i += 1
    pixel = d[i:]
    return len({pixel[k:k + 3] for k in range(0, len(pixel) - 2, 3)})


def carico(riga):
    """Il JSON di `evento <che> {...}`."""
    m = re.match(r"^evento (\S+) (.*)$", riga)
    if m is None:
        return None, None
    try:
        return m.group(1), json.loads(m.group(2))
    except ValueError:
        return m.group(1), None


def main():
    if not os.access(BIN, os.X_OK):
        print("manca %s — lancia prima ./costruisci.sh" % BIN, file=sys.stderr)
        return 2
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non sei in una sessione Wayland; wlroots prenderebbe "
              "lo schermo vero.", file=sys.stderr)
        return 2

    # Un programma qualunque che apra una finestra xdg-shell. Si prende il
    # primo che c'è invece di pretenderne uno: la prova non deve dipendere da
    # quale terminale è installato su questa macchina.
    cliente = None
    for c in ("alacritty", "foot", "kitty", "konsole"):
        if shutil.which(c):
            cliente = c
            break
    if cliente is None:
        print("FERMO: non trovo un terminale da aprire (alacritty, foot, "
              "kitty, konsole).", file=sys.stderr)
        return 2

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    # La riga che impedisce alla prova di comandare la sessione vera.
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    amb["MINERVA_COMPOSITORE"] = "minerva-wayland"

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-annunci.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([BIN], stdout=log, stderr=subprocess.STDOUT,
                            env=amb)

    dentro, canale = "", ""
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
        if dentro and canale:
            break

    if not (dentro and canale):
        print("il compositore non è partito. Registro:", file=sys.stderr)
        print(open(registro, errors="replace").read()[-2000:], file=sys.stderr)
        chiudi(comp)
        return 1

    print("── Prove degli annunci del compositore ──")
    print("  ·    display %s   canale %s" % (dentro, canale))

    ascoltatore = None
    domande = None
    term = None
    try:
        ascoltatore = Canale(canale)
        ascoltatore.scrivi("ascolta")
        verifica("il canale accetta «ascolta»",
                 ascoltatore.aspetta("ok ascolto", 3) is not None,
                 ascoltatore.righe)

        # ── Chi NON ha chiesto di ascoltare non deve ricevere niente ─────
        domande = Canale(canale)
        domande.scrivi("ciao")
        verifica("e chi non l'ha chiesto riceve solo la sua risposta",
                 domande.aspetta("ok minerva-wayland", 3) is not None,
                 domande.righe)

        amb_cliente = dict(amb)
        amb_cliente["WAYLAND_DISPLAY"] = dentro
        term = subprocess.Popen([cliente], env=amb_cliente,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)

        riga = ascoltatore.aspetta("evento aperta ", 15)
        verifica("una finestra che si apre si annuncia", riga is not None,
                 ascoltatore.righe)

        che, c = carico(riga) if riga else (None, None)
        if c is None:
            verifica("e il carico è un oggetto JSON", False, riga)
        else:
            verifica("e il carico è un oggetto JSON", True)
            verifica("con dentro il pid vero del programma",
                     c.get("pid") == term.pid, "%s vs %s" % (c.get("pid"),
                                                             term.pid))
            verifica("con dentro la classe",
                     isinstance(c.get("classe"), str), c.get("classe"))
            verifica("con dentro una misura che non è zero",
                     (c.get("larghezza") or 0) > 0
                     and (c.get("altezza") or 0) > 0, c)
            verifica("e un indirizzo in esadecimale",
                     str(c.get("id", "")).startswith("0x"), c.get("id"))

        verifica("e subito dopo arriva il fuoco",
                 ascoltatore.aspetta("evento fuoco ", 6) is not None,
                 ascoltatore.righe[-4:])

        # Nessun annuncio deve essere finito sul collegamento che non ascolta.
        domande.leggi(0.4)
        verifica("nessun annuncio sul collegamento che non ascolta",
                 not any(r.startswith("evento ") for r in domande.righe),
                 domande.righe)

        # ── L'elenco dice le stesse cose dell'annuncio ───────────────────
        domande.righe = []
        domande.scrivi("finestre")
        elenco = domande.aspetta("ok [", 4)
        verifica("l'elenco risponde", elenco is not None, domande.righe)
        if elenco:
            try:
                lista = json.loads(elenco[3:])
            except ValueError:
                lista = None
            verifica("ed è un JSON valido", isinstance(lista, list), elenco)
            if isinstance(lista, list) and lista:
                verifica("con la stessa finestra dell'annuncio",
                         c is not None and lista[0].get("id") == c.get("id"),
                         lista[0])
                verifica("e «posto» 0 per quella davanti",
                         lista[0].get("posto") == 0, lista[0])

        # ── Ridurre a icona si annuncia ─────────────────────────────────
        if c is not None:
            ascoltatore.righe = []
            domande.righe = []
            domande.scrivi("riduci %s 1" % c["id"])
            stato = ascoltatore.aspetta("evento stato ", 5)
            verifica("«riduci» si annuncia", stato is not None,
                     ascoltatore.righe)
            _, sc = carico(stato) if stato else (None, None)
            verifica("e dice che è ridotta",
                     sc is not None and sc.get("ridotta") is True, sc)

            # ── E la strada del ritorno ─────────────────────────────────
            #
            # È la metà che per un pezzo non c'era: il compositore sapeva
            # nascondere una finestra e nessuno sapeva chiedergli di
            # riportarla su. Una finestra che sparisce senza modo di tornare
            # è peggio di un «riduci» che non funziona, perché sembra chiusa.
            #
            # Da ridotta deve restare NELL'ELENCO: è quello che permette alla
            # dock di mostrarla spenta e di riaccenderla con un clic.
            domande.righe = []
            domande.scrivi("finestre")
            e2 = domande.aspetta("ok [", 4)
            try:
                l2 = json.loads(e2[3:]) if e2 else None
            except ValueError:
                l2 = None
            verifica("da ridotta resta nell'elenco",
                     isinstance(l2, list)
                     and any(x.get("id") == c["id"] and x.get("ridotta") is True
                             for x in l2), l2)

            ascoltatore.righe = []
            domande.righe = []
            domande.scrivi("riduci %s 0" % c["id"])
            verifica("«riduci … 0» risponde ok",
                     domande.aspetta("ok", 4) is not None, domande.righe)
            stato2 = ascoltatore.aspetta("evento stato ", 5)
            _, sc2 = carico(stato2) if stato2 else (None, None)
            verifica("e la finestra torna su",
                     sc2 is not None and sc2.get("ridotta") is False, sc2)

        # ── Le scrivanie ────────────────────────────────────────────────
        #
        # Il pezzo che fino al 25 agosto 2026 non c'era: la shell mandava
        # `workspace 3` e quella riga se ne andava nel vuoto — `no verbo
        # sconosciuto`, a voce bassa, e lo schermo non cambiava. È lo stesso
        # modo in cui era sparito il «riduci».
        #
        # Si prova col compositore VERO e una finestra VERA perché è l'unico
        # modo di provare la cosa che conta: che una finestra nascosta resti
        # viva e torni indietro com'era. Un finto direbbe soltanto che i
        # campi JSON sono al posto giusto.
        if c is not None:
            domande.righe = []
            domande.scrivi("scrivanie")
            e3 = domande.aspetta("ok [", 4)
            try:
                l3 = json.loads(e3[3:]) if e3 else None
            except ValueError:
                l3 = None
            verifica("l'elenco delle scrivanie risponde",
                     isinstance(l3, list) and len(l3) == 1, l3)
            if isinstance(l3, list) and l3:
                verifica("si comincia dalla prima, e ha dentro la finestra",
                         l3[0].get("id") == 1 and l3[0].get("attiva") is True
                         and l3[0].get("finestre") == 1, l3)

            # ── Chi ascolta SOLO le scrivanie ───────────────────────────
            #
            # È l'abbonamento della shell. Serve perché un terminale che
            # cambia titolo a ogni tasto premuto annuncia a ogni tasto
            # premuto, e svegliare per quello il processo che DISEGNA è il
            # conto che questo progetto ha già pagato una volta.
            # I nomi sono quelli degli ANNUNCI — `scrivania`, non
            # «scrivanie» — perché chi si iscrive scrive la parola che poi
            # legge. Scriverne una che non esiste non dà errore: dà un
            # collegamento che non riceve niente, ed è come questa prova è
            # stata rossa per un minuto.
            sordo = Canale(canale)
            sordo.scrivi("ascolta scrivania")
            verifica("il canale accetta «ascolta scrivania»",
                     sordo.aspetta("ok ascolto", 3) is not None, sordo.righe)

            # ── Un'iscrizione lunga non si taglia ───────────────────────
            #
            # Fino al 23 settembre 2026 il canale teneva i primi QUATTRO
            # nomi e buttava gli altri senza dirlo. La shell ne chiedeva
            # sette: `attivo` e `schermi` non le sono mai arrivati. Qui il
            # nome che conta sta al settimo posto, come nella shell.
            lungo = Canale(canale)
            lungo.scrivi("ascolta scorciatoia coperchio inattivo attivo "
                         "schermi bordoalto scrivania")
            verifica("il canale accetta un'iscrizione da sette nomi",
                     lungo.aspetta("ok ascolto", 3) is not None, lungo.righe)
            troppi = Canale(canale)
            troppi.scrivi("ascolta " + " ".join("n%d" % i for i in range(17)))
            verifica("e ne rifiuta una da diciassette, dicendolo",
                     troppi.aspetta("no ", 3) is not None, troppi.righe)

            ascoltatore.righe = []
            sordo.righe = []
            domande.righe = []
            domande.scrivi("scrivania 2")
            verifica("«scrivania 2» risponde col numero nuovo",
                     domande.aspetta("ok 2", 4) is not None, domande.righe)
            ann = ascoltatore.aspetta("evento scrivania ", 5)
            _, sa = carico(ann) if ann else (None, None)
            verifica("e si annuncia",
                     sa is not None and sa.get("attiva") == 2, sa)
            verifica("anche a chi ascolta solo quelle",
                     sordo.aspetta("evento scrivania ", 3) is not None,
                     sordo.righe)
            verifica("e a chi l'ha chiesta come settimo nome",
                     lungo.aspetta("evento scrivania ", 3) is not None,
                     lungo.righe)

            # La finestra è ancora là, e sa dov'è: nascondere non è chiudere.
            domande.righe = []
            domande.scrivi("finestre")
            e4 = domande.aspetta("ok [", 4)
            try:
                l4 = json.loads(e4[3:]) if e4 else None
            except ValueError:
                l4 = None
            verifica("la finestra dell'altra scrivania resta nell'elenco",
                     isinstance(l4, list)
                     and any(x.get("id") == c["id"] and x.get("scrivania") == 1
                             for x in l4), l4)

            # ── Chi ascolta solo le scrivanie NON sente il resto ─────────
            sordo.righe = []
            ascoltatore.righe = []
            domande.scrivi("riduci %s 1" % c["id"])
            ascoltatore.aspetta_se("evento stato ",
                                   lambda x: x.get("ridotta") is True, 5)
            verifica("e non gli arriva nient'altro",
                     sordo.aspetta("evento stato ", 1.5) is None, sordo.righe)
            domande.scrivi("riduci %s 0" % c["id"])
            # Si aspetta l'annuncio CHE DICE QUELLO CHE ABBIAMO CHIESTO, non
            # il primo con lo stesso nome: quello di prima è ancora nella coda
            # letta, e prenderlo vorrebbe dire proseguire con una risposta
            # vecchia in mano — che è come questa prova era rossa.
            ascoltatore.aspetta_se("evento stato ",
                                   lambda x: x.get("ridotta") is False, 5)

            # ── Mandare una finestra altrove, senza seguirla ─────────────
            ascoltatore.righe = []
            domande.righe = []
            domande.scrivi("portaascrivania %s 3 si" % c["id"])
            verifica("«portaascrivania … si» risponde ok",
                     domande.aspetta("ok", 4) is not None, domande.righe)
            st = ascoltatore.aspetta_se("evento stato ",
                                        lambda x: x.get("id") == c["id"], 5)
            _, sp = carico(st) if st else (None, None)
            verifica("la finestra è sulla terza",
                     sp is not None and sp.get("scrivania") == 3,
                     sp if sp else ascoltatore.righe)

            domande.righe = []
            domande.scrivi("stato")
            stt = domande.aspetta("ok {", 4)
            try:
                so = json.loads(stt[3:]) if stt else None
            except ValueError:
                so = None
            verifica("e «silenzioso» vuol dire che non l'abbiamo seguita",
                     so is not None and so.get("scrivania") == 2, so)

            # ── Dare il fuoco a una finestra che sta altrove ci porta là ─
            #
            # La dock elenca tutte le finestre, non solo quelle di qui: un
            # clic su una che sta altrove deve portarci là. Senza, il clic
            # «funziona» e sullo schermo non cambia niente.
            ascoltatore.righe = []
            domande.righe = []
            domande.scrivi("fuoco %s" % c["id"])
            ann2 = ascoltatore.aspetta("evento scrivania ", 5)
            _, sf = carico(ann2) if ann2 else (None, None)
            verifica("il fuoco su una finestra di un'altra scrivania ci porta là",
                     sf is not None and sf.get("attiva") == 3, sf)

            # ── I rifiuti ───────────────────────────────────────────────
            domande.righe = []
            domande.scrivi("scrivania 99")
            verifica("una scrivania che non esiste si rifiuta",
                     domande.aspetta("no ", 3) is not None, domande.righe)
            domande.righe = []
            domande.scrivi("scrivania")
            verifica("e senza numero anche",
                     domande.aspetta("no ", 3) is not None, domande.righe)

            # Si torna dove si era, che è anche il modo di provare il giro.
            domande.scrivi("portaascrivania %s 1 no" % c["id"])
            time.sleep(0.4)
            sordo.chiudi()

        # ── Le scorciatoie ──────────────────────────────────────────────
        #
        # Qui si prova la REGISTRAZIONE: che il compositore capisca le righe
        # che gli manda la shell, e che rifiuti quelle storte. Che poi il tasto
        # premuto faccia davvero la cosa non si può provare da qui — servirebbe
        # una tastiera finta puntata dentro il compositore annidato, e i tasti
        # se li prenderebbe la sessione vera prima che arrivino.
        domande.righe = []
        domande.scrivi("scorciatoie azzera")
        verifica("le scorciatoie si azzerano",
                 domande.aspetta("ok", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("scorciatoia SUPER K - minerva:cheatsheet")
        verifica("una scorciatoia si registra",
                 domande.aspetta("ok 1", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("scorciatoia SUPER+SHIFT 1 - porta-a-scrivania:1")
        verifica("e una seconda si aggiunge alla prima",
                 domande.aspetta("ok 2", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("scorciatoia - XF86AudioRaiseVolume bloccato "
                       "minerva:volumeup")
        verifica("anche quelle che valgono a schermo bloccato",
                 domande.aspetta("ok 3", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("scorciatoia SUPER F9 - avvia:true # con spazi dentro")
        verifica("l'azione può contenere spazi: è una riga di comando",
                 domande.aspetta("ok 4", 3) is not None, domande.righe)

        # ── I rifiuti ───────────────────────────────────────────────────
        domande.righe = []
        domande.scrivi("scorciatoia SUPER nonesiste - minerva:x")
        verifica("un tasto che non esiste si rifiuta, invece di sparire",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("scorciatoia SUPER K -")
        verifica("e una riga senza azione anche",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        # `azzera` deve davvero azzerare: aggiungere e basta vorrebbe dire una
        # tabella che cresce a ogni ricarica, con dentro le regole di ieri.
        domande.righe = []
        domande.scrivi("scorciatoie azzera")
        domande.aspetta("ok", 3)
        domande.righe = []
        domande.scrivi("scorciatoie")
        verifica("e dopo «azzera» non ne resta nessuna",
                 domande.aspetta("ok 0", 3) is not None, domande.righe)

        # ── Il cartello ─────────────────────────────────────────────────
        #
        # È l'ultima cosa che si può ancora dire quando la scrivania non c'è
        # più: se la shell muore e il suo guardiano si arrende, non ci sono
        # avvisi, non c'è la barra, non c'è niente. L'unico rimasto in piedi è
        # il compositore.
        #
        # Fino al 1º settembre 2026 quel messaggio lo dava `hyprctl notify`, e
        # sotto di noi non lo dava nessuno: schermo nero e nessuna
        # spiegazione — cioè il silenzio proprio nel caso per cui l'avviso era
        # stato scritto.
        domande.righe = []
        domande.scrivi("messaggio 8000 Minerva: prova del cartello.")
        verifica("un messaggio a schermo si accetta",
                 domande.aspetta("ok", 4) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("messaggio 0")
        verifica("e si toglie con zero",
                 domande.aspetta("ok", 4) is not None, domande.righe)

        # ── I rifiuti ───────────────────────────────────────────────────
        domande.righe = []
        domande.scrivi("messaggio")
        verifica("senza millisecondi si rifiuta",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("messaggio subito ciao")
        verifica("e una parola al posto dei millisecondi anche",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("messaggio 9999999 troppo")
        verifica("e un tempo assurdo pure: un cartello per sempre è uno "
                 "schermo sporcato per sempre",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        # Un cartello nuovo sostituisce quello di prima: due messaggi
        # sovrapposti non si leggono né l'uno né l'altro.
        domande.righe = []
        domande.scrivi("messaggio 5000 primo")
        domande.aspetta("ok", 3)
        domande.righe = []
        domande.scrivi("messaggio 5000 secondo")
        verifica("un cartello nuovo prende il posto del vecchio",
                 domande.aspetta("ok", 3) is not None, domande.righe)
        domande.scrivi("messaggio 0")
        domande.aspetta("ok", 3)

        # E il compositore è ancora vivo dopo tutto questo.
        domande.righe = []
        domande.scrivi("ciao")
        verifica("e il compositore è vivo dopo i cartelli",
                 domande.aspetta("ok minerva-wayland", 3) is not None,
                 domande.righe)

        # ── L'inattività ────────────────────────────────────────────────
        #
        # Il compositore CONTA, la shell decide. Fino al 1º settembre 2026 il
        # conto lo teneva `hypridle`: un programma di un altro ambiente, con un
        # suo file di configurazione che il pannello Energia riscriveva e poi
        # riavviava. Adesso è un verbo, e la politica — spegni lo schermo,
        # blocca, sospendi — resta di chi disegna la scrivania.
        #
        # Le soglie qui sono di UN SECONDO perché la prova deve finire; in
        # sessione vera sono minuti.
        #
        # Quello che questa prova NON può provare è il ritorno: `evento attivo`
        # vuole che qualcuno tocchi qualcosa, e dentro un compositore annidato
        # senza tastiera finta non c'è niente da toccare. Sta scritto qui
        # invece che essere finto, perché una prova che finge di provarlo
        # sarebbe peggio di questa riga.
        domande.righe = []
        domande.scrivi("inattivita 1 2")
        verifica("le soglie di inattività si registrano",
                 domande.aspetta("ok 2", 3) is not None, domande.righe)

        ascoltatore.righe = []
        i1 = ascoltatore.aspetta_se("evento inattivo ",
                                    lambda x: x.get("secondi") == 1, 5)
        verifica("la prima soglia scatta e si annuncia", i1 is not None,
                 ascoltatore.righe)
        i2 = ascoltatore.aspetta_se("evento inattivo ",
                                    lambda x: x.get("secondi") == 2, 5)
        verifica("e poi la seconda, col suo numero", i2 is not None,
                 ascoltatore.righe)

        # ── I rifiuti ───────────────────────────────────────────────────
        #
        # In disordine il conto fra una soglia e la successiva verrebbe
        # negativo, e un timer con un tempo negativo non scatta mai: si
        # rifiuta la riga invece di accettarla e non fare niente.
        domande.righe = []
        domande.scrivi("inattivita 5 3")
        verifica("soglie in disordine si rifiutano",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("inattivita zero")
        verifica("e una parola al posto di un numero anche",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        domande.righe = []
        domande.scrivi("inattivita 0")
        verifica("e lo zero, che vorrebbe dire «subito e per sempre»",
                 domande.aspetta("no ", 3) is not None, domande.righe)

        # Una riga storta non deve spegnere una sorveglianza che funzionava:
        # dopo tre rifiuti le due soglie di prima devono essere ancora là.
        # È il campo `inattivita` di `stato` a dirlo, e sta lì apposta: una
        # sorveglianza che non è stata chiesta è indistinguibile da una che
        # non funziona — lo schermo non si blocca, e non c'è niente da
        # guardare per sapere di chi è la colpa.
        domande.righe = []
        domande.scrivi("stato")
        st_i = domande.aspetta("ok {", 3)
        try:
            so_i = json.loads(st_i[3:]) if st_i else None
        except ValueError:
            so_i = None
        verifica("dopo tre rifiuti le soglie di prima ci sono ancora",
                 so_i is not None and so_i.get("inattivita") == 2, so_i)

        # ── E si spegne ─────────────────────────────────────────────────
        domande.righe = []
        domande.scrivi("inattivita")
        verifica("senza numeri la sorveglianza si spegne",
                 domande.aspetta("ok 0", 3) is not None, domande.righe)
        ascoltatore.righe = []
        verifica("e da spenta non annuncia più niente",
                 ascoltatore.aspetta("evento inattivo ", 3) is None,
                 ascoltatore.righe)
        domande.righe = []
        domande.scrivi("stato")
        st_z = domande.aspetta("ok {", 3)
        try:
            so_z = json.loads(st_z[3:]) if st_z else None
        except ValueError:
            so_z = None
        verifica("e «stato» lo dice: zero soglie",
                 so_z is not None and so_z.get("inattivita") == 0, so_z)

        # ── I protocolli annunciati ─────────────────────────────────────
        #
        # Compilato non vuol dire annunciato: una riga di `wlr_..._create()`
        # dimenticata dentro un `#if`, o messa dopo il `wl_display_run()`, non
        # dà nessun errore — dà un protocollo che i client non trovano, e i
        # client che non lo trovano non si lamentano: fanno finta di niente.
        #
        # È il modo in cui si rompono TUTTI i pezzi di questa lista, ed è per
        # questo che si chiede al compositore chi è, invece di fidarsi del
        # fatto che compili. Ognuno è annotato con quello che si rompe senza.
        if shutil.which("wayland-info"):
            amb_info = dict(amb)
            amb_info["WAYLAND_DISPLAY"] = dentro
            try:
                testo = subprocess.run(["wayland-info"], env=amb_info,
                                       capture_output=True, timeout=15,
                                       text=True).stdout
            except (OSError, subprocess.TimeoutExpired):
                testo = ""
            attesi = [
                ("zwp_primary_selection_device_manager_v1",
                 "incollare col tasto centrale"),
                ("ext_data_control_manager_v1",
                 "wl-copy e i gestori di appunti"),
                ("zwlr_screencopy_manager_v1", "le schermate"),
                ("zwlr_gamma_control_manager_v1", "la luce notturna"),
                ("ext_idle_notifier_v1", "il blocco automatico dello schermo"),
                ("zwp_idle_inhibit_manager_v1",
                 "«non spegnere mentre guardo un film»"),
                ("wp_cursor_shape_manager_v1", "il cursore chiesto per forma"),
                ("zwp_relative_pointer_manager_v1",
                 "il movimento relativo del puntatore"),
                ("wp_single_pixel_buffer_manager_v1", "gli sfondi pieni"),
                # Quelli che c'erano già: se uno di questi sparisce, la shell
                # smette di disegnarsi e non si capisce perché.
                ("zwlr_layer_shell_v1", "la barra, la dock, i pannelli"),
                ("wp_fractional_scale_manager_v1", "la scala 1,25"),
                ("wp_viewporter", "la scala 1,25"),
                ("zxdg_output_manager_v1", "i nomi degli schermi"),
                ("xdg_wm_base", "qualunque finestra"),
            ]
            verifica("wayland-info risponde", testo.strip() != "")
            for nome, aCosaServe in attesi:
                verifica("annuncia %s → %s" % (nome, aCosaServe),
                         nome in testo,
                         "non annunciato")
        else:
            print("  ·    salto i protocolli: manca wayland-info")

        # ── Il puntatore ────────────────────────────────────────────────
        #
        # Tema e misura sono una cosa sola: il gestore dei cursori si
        # costruisce con tutti e due, e non c'è modo di cambiarne uno
        # lasciando l'altro. Un tema che non esiste NON deve far cadere il
        # compositore: si tiene quello di prima e si risponde di no.
        domande.righe = []
        domande.scrivi("cursore Adwaita 24")
        verifica("il puntatore si cambia", domande.aspetta("ok", 4) is not None,
                 domande.righe)
        domande.righe = []
        domande.scrivi("cursore Adwaita 999999")
        verifica("una misura assurda non lo fa cadere",
                 domande.aspetta("ok", 4) is not None, domande.righe)
        verifica("e il compositore è ancora vivo", comp.poll() is None,
                 comp.returncode)

        # ── Un titolo LUNGO non deve spezzare il canale ─────────────────
        #
        # `json_stringa` in `src/main.c` scrive un BYTE per giro e si ferma
        # quando non ci sta più. La fermata era cieca: con un titolo più lungo
        # del buffer (512 byte) si fermava a metà di una lettera accentata —
        # «è» sono due byte — e sul canale usciva UTF-8 non valido.
        #
        # Dall'altra parte il demone legge con `utf8.decoder`, che su un byte
        # malformato LANCIA: l'errore arriva a `onError`, che butta giù
        # l'abbonamento agli annunci e riconnette. Non muore niente e non si
        # vede niente — la scrivania perde per un istante le notizie sulle
        # finestre.
        #
        # Qui si legge STRETTO apposta: `Canale.leggi` decodifica con
        # `replace`, che trasforma un byte rotto in «�» e farebbe passare
        # la prova. Il carattere di sostituzione È il difetto.
        lungo = None
        if c is not None:
            # ── Perché SOLO accentate, e nessuno spazio ──────────────────
            #
            # Il taglio cieco si fermava al primo posto utile, e se lì c'era
            # un confine fra due caratteri non rompeva niente. Un testo misto
            # è una lotteria: il primo tentativo di questa prova usava «però
            # àèìòù » e cadeva sullo spazio finale — passava anche col difetto
            # dentro, cioè era una prova che non provava niente.
            #
            # Con soli caratteri da due byte e nessun ASCII, ogni posizione
            # dispari è in mezzo a una lettera. Il taglio cade a 509, che è
            # dispari: il difetto scatta sempre.
            titolo = "à" * 400                   # 800 byte in UTF-8
            amb_lungo = dict(amb)
            amb_lungo["WAYLAND_DISPLAY"] = dentro
            ascoltatore.righe = []
            lungo = subprocess.Popen(
                [cliente, "-e", "sh", "-c",
                 "printf '\033]0;%s\007' '%s'; sleep 300" % (titolo, titolo)],
                env=amb_lungo, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL)
            # Si aspetta l'annuncio del TITOLO, non quello dell'apertura:
            # una finestra si annuncia quando compare, e in quell'istante il
            # titolo è ancora quello di fabbrica — il programma dentro non ha
            # ancora stampato niente. Aspettando «aperta» arrivavano diciassette
            # byte, e la prova diceva verde senza aver provato niente.
            riga_l = ascoltatore.aspetta_se(
                "evento titolo ",
                lambda x: x.get("pid") == lungo.pid
                and len(str(x.get("titolo", "")).encode("utf-8")) > 400,
                15)
            verifica("una finestra con un titolo lunghissimo si annuncia",
                     riga_l is not None, ascoltatore.righe[-3:])
            if riga_l is not None:
                verifica("e la riga non ha caratteri rotti dentro",
                         "\ufffd" not in riga_l,
                         "c'è un carattere di sostituzione: il titolo è stato "
                         "tagliato in mezzo a una lettera")
                _, cl = carico(riga_l)
                verifica("e il JSON si legge ancora", cl is not None, riga_l)
                if cl is not None:
                    t = cl.get("titolo")
                    # Che sia arrivato LUNGO davvero. Senza questa riga, un
                    # terminale che butta via il titolo farebbe passare tutto
                    # il resto senza aver provato niente.
                    verifica("e il titolo è arrivato lungo davvero",
                             isinstance(t, str)
                             and len(t.encode("utf-8")) > 400,
                             "%s byte" % (len(t.encode("utf-8"))
                                          if isinstance(t, str) else "nessuno"))
                    verifica("col titolo accorciato, non storto",
                             isinstance(t, str) and "\ufffd" not in t, t)
            # ── E si aspetta che se ne sia ANDATA ────────────────────
            #
            # Senza queste tre righe questa prova ne rompe una che sta più
            # sotto: «e porta ancora il suo indirizzo» fa `aspetta("evento
            # chiusa ")`, che prende il PRIMO annuncio di chiusura in coda —
            # e da adesso il primo è questo, non quello della finestra di
            # cui si sta parlando. È la stessa trappola che ha fatto nascere
            # `aspetta_se`, presa dal verso opposto: qui non basta chiedere
            # meglio, bisogna proprio togliere di mezzo la notizia vecchia.
            chiudi(lungo)
            lungo = None
            if cl is not None:
                ascoltatore.aspetta_se(
                    "evento chiusa ", lambda x: x.get("id") == cl.get("id"), 8)
            ascoltatore.righe = []

        # ── L'altezza della barra e le finestre INGRANDITE ──────────────
        #
        # `aspetto` rifà tutte le finestre aperte, o sullo stesso schermo se
        # ne vedrebbero due di altezze diverse. Ma rifarle dal loro riquadro
        # di adesso è giusto solo per quelle normali: la misura di una
        # INGRANDITA non è una sua proprietà, è lo spazio utile meno la barra.
        # Tenendosi l'altezza vecchia restava ingrandita di nome e larga
        # quanto ieri.
        if c is not None:
            domande.righe = []
            domande.scrivi("schermi")
            e5 = domande.aspetta("ok [", 4)
            try:
                l5 = json.loads(e5[3:]) if e5 else None
            except ValueError:
                l5 = None
            schermo = l5[0] if isinstance(l5, list) and l5 else None

            domande.righe = []
            domande.scrivi("ingrandisci %s 1" % c["id"])
            domande.aspetta("ok", 4)
            time.sleep(0.4)

            domande.righe = []
            domande.scrivi("aspetto 60 destra")
            verifica("«aspetto 60 destra» risponde ok",
                     domande.aspetta("ok", 4) is not None, domande.righe)
            time.sleep(0.6)

            domande.righe = []
            domande.scrivi("finestre")
            e6 = domande.aspetta("ok [", 4)
            try:
                l6 = json.loads(e6[3:]) if e6 else None
            except ValueError:
                l6 = None
            mia = None
            if isinstance(l6, list):
                for x in l6:
                    if x.get("id") == c["id"]:
                        mia = x
                        break
            # Si confronta con lo spazio UTILE e non con lo schermo: è
            # quello che una finestra ingrandita ricopre, ed è quello che
            # `finestra_ingrandisci` le dà. Senza shell dentro i due
            # coincidono, ma scriverlo giusto vale anche il giorno in cui
            # questa prova avrà una barra sopra.
            if mia is not None and schermo is not None:
                verifica("una finestra ingrandita ricopre ancora lo spazio "
                         "utile dopo un cambio di altezza della barra",
                         mia.get("larghezza") == schermo.get("utileLarghezza")
                         and mia.get("altezza") == schermo.get("utileAltezza"),
                         "finestra %sx%s, utile %sx%s"
                         % (mia.get("larghezza"), mia.get("altezza"),
                            schermo.get("utileLarghezza"),
                            schermo.get("utileAltezza")))
            else:
                verifica("una finestra ingrandita ricopre ancora lo spazio "
                         "utile dopo un cambio di altezza della barra", False,
                         "non ho ritrovato la finestra o lo schermo")

            # Si rimette com'era: le prove che seguono contano sui 42 pixel.
            domande.scrivi("aspetto 42 destra")
            domande.aspetta("ok", 4)
            domande.righe = []
            domande.scrivi("ingrandisci %s 0" % c["id"])
            domande.aspetta("ok", 4)
            time.sleep(0.4)

        # ── E chiudere ──────────────────────────────────────────────────
        #
        # Prima la si porta DOVE SI GUARDA e in un punto noto. Non è pignoleria
        # di misura: senza, la prova qui sotto direbbe verde per caso. La
        # finestra a questo punto sta sulla prima scrivania mentre noi siamo
        # sulla terza, e un fantasma su una scrivania che non si guarda è
        # spento — cioè invisibile — anche quando c'è.
        # ── Un numero che non è un numero non è uno zero ─────────────────
        #
        # `atoi` risponde zero a «pippo» come a «0», e in una POSIZIONE lo zero
        # è un valore buono: `sposta <f> pippo pluto` portava la finestra
        # nell'angolo in alto a sinistra e rispondeva «ok». Un comando
        # eseguito al posto di un errore.
        #
        # Dove lo zero NON è buono il difetto non c'era: le scrivanie vanno da
        # uno, quindi «scrivania pippo» cadeva già nel controllo. Le due prove
        # qui sotto guardano tutti e due i casi, perché la seconda è la
        # controprova della prima.
        if c is not None:
            domande.righe = []
            domande.scrivi("sposta %s pippo pluto" % c["id"])
            verifica("«sposta» con due parole al posto dei numeri risponde no",
                     (domande.aspetta("no ", 3) or "").startswith("no"),
                     domande.righe)
            domande.righe = []
            domande.scrivi("sposta %s 12pippo 30" % c["id"])
            verifica("e nemmeno «12pippo» è dodici",
                     (domande.aspetta("no ", 3) or "").startswith("no"),
                     domande.righe)
            domande.righe = []
            domande.scrivi("sposta %s 0 0" % c["id"])
            verifica("mentre uno zero VERO passa",
                     domande.aspetta("ok", 3) is not None, domande.righe)
            domande.righe = []
            domande.scrivi("scrivania pippo")
            verifica("e «scrivania pippo» era già rifiutata da prima",
                     (domande.aspetta("no ", 3) or "").startswith("no"),
                     domande.righe)

        fantasma = None
        if c is not None and shutil.which("grim"):
            domande.scrivi("fuoco %s" % c["id"])
            time.sleep(0.5)
            domande.scrivi("sposta %s 100 300" % c["id"])
            time.sleep(0.5)
            fantasma = "100,300 400x42"
            verifica("prima di chiuderla, lì una barra del titolo c'è",
                     (tinte(dentro, fantasma) or 0) > 1,
                     "il punto scelto non mostra nessuna barra: la prova "
                     "che segue non proverebbe niente")

        ascoltatore.righe = []
        chiudi(term)
        term = None
        chiusa = ascoltatore.aspetta("evento chiusa ", 8)
        verifica("una finestra che si chiude si annuncia", chiusa is not None,
                 ascoltatore.righe)
        _, cc = carico(chiusa) if chiusa else (None, None)
        verifica("e porta ancora il suo indirizzo",
                 cc is not None and c is not None
                 and cc.get("id") == c.get("id"), cc)

        # ── E con lei se ne va la BARRA ─────────────────────────────────
        #
        # 31 agosto 2026, Giacomo: «quando apro una finestra che non è di
        # Minerva rimane sempre la barra del titolo quando la chiudo».
        #
        # Non si vedeva da nessuna parte se non guardando lo schermo: il
        # canale rispondeva giusto — una finestra sola nell'elenco — mentre
        # sulla scrivania ce n'erano quattro barre. Il compositore smontava
        # tutto TRANNE la cornice, che è l'unico nodo di scena creato da noi
        # e non appeso alla superficie.
        #
        # Per questo la prova è una FOTOGRAFIA e non una domanda: la cosa
        # rotta era proprio quella su cui il canale non ha niente da dire.
        if fantasma is not None:
            time.sleep(0.8)
            quante = tinte(dentro, fantasma)
            verifica("e con lei se ne va la barra del titolo",
                     quante == 1,
                     "%s colori dove la finestra non c'è più: è rimasta la "
                     "cornice" % quante)

        # ── Un cliente che se ne va non porta giù il compositore ─────────
        ascoltatore.chiudi()
        ascoltatore = None
        time.sleep(0.5)
        verifica("il compositore è ancora vivo dopo che l'ascoltatore se n'è "
                 "andato", comp.poll() is None, comp.returncode)

        # ── Uscire dalla sessione ───────────────────────────────────────
        #
        # «Esci» dal menu di Minerva passava solo da `hyprctl dispatch exit`:
        # sotto questo compositore non faceva niente, e non c'era nemmeno un
        # errore da leggere perché `hyprctl` non esiste. Una sessione da cui
        # non si esce si chiude col tasto di accensione.
        #
        # Si prova che finisca DA SÉ, senza segnali: è la stessa strada del
        # SIGTERM — si chiede al ciclo di eventi di finire — e quindi prova
        # anche che il socket venga tolto dal disco, che è il controllo qui
        # sotto.
        domande.scrivi("esci")
        for _ in range(40):
            if comp.poll() is not None:
                break
            time.sleep(0.15)
        verifica("«esci» chiude il compositore da sé", comp.poll() is not None,
                 "è ancora vivo dopo sei secondi")

    finally:
        for x in (ascoltatore, domande):
            if x is not None:
                x.chiudi()
        chiudi(term)
        chiudi(comp)
        log.close()

    # ── E il socket non deve restare sul disco ───────────────────────────
    #
    # Un socket Unix è un file, e un file avanzato da un compositore morto non
    # dà nessun errore a chi lo guarda: sembra un compositore acceso. Il 24
    # agosto 2026 è successo esattamente questo — finita una prova annidata, il
    # demone della sessione VERA ha visto quel file, ha concluso che girava
    # minerva-wayland, e ha chiesto le finestre a un compositore morto.
    # Hyprland aveva un terminale aperto, la shell diceva `finestre=0`, e non
    # c'era un errore da nessuna parte.
    #
    # Il demone si difende da sé guardando `/proc/net/unix`, che regge anche a
    # un SIGKILL. Questa è l'altra metà: non lasciare sporco quando si può
    # evitare.
    time.sleep(0.5)
    verifica("dopo SIGTERM il socket non resta sul disco",
             not os.path.exists(canale), canale)

    # ── E deve uscire, non ABORTIRE ─────────────────────────────────────
    #
    # Sono due cose diverse e la seconda si nasconde bene: un compositore che
    # aborta lascia il socket, sì, ma se aborta DOPO averlo tolto la riga qui
    # sopra resta verde e il crollo non lo vede nessuno. Lo si è visto il 26
    # agosto 2026 — tre `assert` di wlroots di fila all'uscita, ognuna
    # nascosta dietro la precedente, e nessuna che si vedesse dalle prove.
    #
    # `-6` è SIGABRT: un core dump a ogni chiusura. `0` o `-15` vanno bene.
    verifica("e non aborta uscendo",
             comp.returncode in (0, -signal.SIGTERM, -signal.SIGINT),
             "codice di uscita %s" % comp.returncode)
    if os.path.exists(canale):
        try:
            os.unlink(canale)
        except OSError:
            pass

    print("──")
    if fallite == 0:
        print("TUTTE PASSATE (%d)" % passate)
        return 0
    print("FALLITE %d su %d" % (fallite, passate + fallite))
    print("registro del compositore: %s" % registro)
    return 1


if __name__ == "__main__":
    sys.exit(main())
