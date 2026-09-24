#!/usr/bin/env python3
"""prova-impostazioni.py — Si gira ogni manopola e si guarda lo schermo.

    ./scripts/prova-impostazioni.py                tutte
    ./scripts/prova-impostazioni.py shell dock     solo alcuni gruppi
    ./scripts/prova-impostazioni.py --elenco       cosa proverebbe, senza provare

── Perché esiste ───────────────────────────────────────────────────────────

Perché in centotrentanove impostazioni non c'era **nessuna** prova che
collegasse un cursore a un pixel. Il 9 settembre 2026 ne sono saltate fuori
due nello stesso pomeriggio:

  * il cursore della trasparenza della barra, col blur acceso, girava da 0,75
    a 1,00 senza cambiare **nemmeno un pixel** — perché la shell teneva
    comunque il valore sotto 0,75;
  * la luce notturna rispondeva «ok» da due settimane e lo schermo non si
    scaldava, perché il renderer ignorava la tabella dei colori.

Tutte e due erano invisibili a chi guardava il codice, e ovvie a chi guardava
lo schermo. Questo banco guarda lo schermo.

── Come funziona, e perché in tre tempi e non in due ───────────────────────

Per ogni chiave:

    1. si aspetta che lo schermo stia FERMO (due fotografie identiche)
    2. si scrive un valore diverso, si aspetta che si fermi, si fotografa
    3. si RIMETTE il valore di prima, si aspetta, si fotografa

Il verdetto è «muove» solo se la fotografia 2 è diversa dalla 1 **e** la 3
torna uguale alla 1. Senza il terzo tempo, l'orologio della barra che scatta
di un minuto fra due scatti direbbe che una manopola qualunque funziona — ed
è esattamente il modo in cui una prova passa per il motivo sbagliato, che in
questo progetto è già successo tre volte.

Se la 3 non torna, il verdetto è «instabile»: qualcosa si muoveva da solo, e
di quella chiave questo giro non sa dire niente. Meglio un «non lo so» che un
verde.

── ANNIDATO, e non è una precauzione formale ───────────────────────────────

Gira dentro `compositore/prova-annidata.sh`: compositore, demone e shell tutti
suoi, con una COPIA della configurazione in `/tmp`. Un banco che gira ogni
manopola della scrivania vera la lascerebbe irriconoscibile — e una delle
manopole è «esci dalla sessione».
"""
import json
import os
import re
import socket
import subprocess
import sys

import cartelle  # le cartelle di Liquid DE, accanto a questo file
import time
from zlib import error as zlib_error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fotogramma import diversi, leggi_png  # noqa: E402

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
CONF_PROVA = os.path.join(os.environ.get("TMPDIR", "/tmp"), "liquid-de-prova-conf")


# ── I valori da provare ────────────────────────────────────────────────────
#
# Per una manopola a due posizioni non c'è niente da inventare: si prova
# l'altra. Per un numero si prende un valore lontano abbastanza da vedersi e
# vicino abbastanza da restare sensato — dimezzare, o salire al massimo se il
# numero sta fra zero e uno.
#
# Per le parole non si può indovinare, e non si finge di sapere: le famiglie
# di valori stanno qui sotto, dichiarate una per una. Una chiave di testo che
# non è in questa tabella esce come «non provabile», che è un TODO visibile —
# non un verde.
PAROLE = {
    "windows.effetto": ["nessuno", "vetro", "blur"],
    "windows.cornice": ["spento", "fisso", "gira"],
    "windows.buttonsSide": ["destra", "sinistra"],
    "windows.fullscreenBar": ["hover", "always", "off"],
    "icons.style": ["minerva", "classiche"],
    "bar.position": ["alto", "basso"],
    "dock.position": ["basso", "alto"],
    "dock.modo": ["sempre", "elude", "nascondi"],
    "shell.scheme": ["notte", "carbone", "ametista", "giorno"],
    "shell.accent": ["#22D3EE", "#F97316"],
    "shell.versoPersonale": ["scuro", "chiaro"],
    "shell.tintaPersonale": ["#101018", "#F0E8D8"],
    "general.language": ["auto", "it", "en"],
    "power.lidAction": ["suspend", "lock", "none"],
    "greeter.background": ["aurora", "immagine"],
    "desktop.iconSort": ["nome", "data"],
}

# ── Le chiavi che NON sono manopole ────────────────────────────────────────
#
# Sono STATO ricordato, non preferenze: dove eri rimasto, quanto era alto il
# volume, come avevi ordinato una cartella. Girarle non deve cambiare la
# scrivania, e pretenderlo renderebbe questo banco rosso per delle cose
# giuste.
#
# Ognuna sta qui con il suo motivo. Un elenco senza motivi diventa il posto
# dove si nascondono le manopole rotte.
STATO_RICORDATO = {
    "settings.lastSection": "dove eri rimasto nelle Impostazioni",
    "desktop.menuUsed": "se il menù della scrivania è già stato aperto una volta",
    "desktop.wallpaper": "quale sfondo: cambia lo schermo, ma il banco non ha "
                         "una seconda immagine da mettere",
    "desktop.wallpaperFolder": "la cartella da cui pescare gli sfondi",
    "desktop.iconPositions": "dove hai trascinato le icone",
    "files.desktopPositions": "dove hai trascinato le icone",
    # I widget della scrivania: quali, dove, e come. Girarla a caso vorrebbe
    # dire spostare (o cancellare) i widget di chi fa girare il banco — è la
    # stessa ragione delle posizioni delle icone qui sopra.
    "desktop.widgets": "quali widget hai messo sulla scrivania, e dove",
    "desktop.widgetBloccati": "se stavi personalizzando la scrivania: è un "
                              "modo, non una preferenza",
    "files.view": "griglia o elenco: te lo ricorda il gestore file",
    "files.zoom": "quanto avevi ingrandito",
    "files.sort": "come avevi ordinato",
    "files.sortDesc": "in che verso avevi ordinato",
    "files.pinned": "le tue cartelle fissate",
    "files.showHidden": "se mostravi i nascosti",
    "media.volume": "il volume di dov'eri rimasto",
    "media.muto": "se avevi tolto l'audio",
    "media.ripeti": "il modo di ripetizione",
    "media.casuale": "se avevi acceso il casuale",
    "media.disegno": "quale disegno dell'audio avevi scelto",
    "editor.bold": "com'era il testo che stavi scrivendo",
    "editor.italic": "com'era il testo che stavi scrivendo",
    "editor.font": "il carattere dell'editor",
    "editor.size": "la misura del carattere dell'editor",
    "editor.colore": "il colore del testo",
    "editor.fondoScuro": "il fondo dell'editor",
    "editor.piega": "se le righe andavano a capo",
    "launcher.fixedApps": "le app che hai fissato",
    "launcher.hiddenCategories": "le categorie che hai nascosto",
    "dock.pinned": "le app che hai fissato nella dock",
    "windows.csdApps": "l'elenco dei programmi che si disegnano la barra da soli",
    "shell.scavalca": "i colori messi a mano, uno per uno",
    "viewer.filmstrip": "se la striscia era aperta",
}

# ── E quelle che non si toccano nemmeno per sbaglio ────────────────────────
#
# Girare queste dentro il banco vorrebbe dire spegnere la prova mentre gira,
# o mettere il compositore in uno stato da cui non torna prima della fine.
MAI = {
    "general.beginnerMode": "cambia mezza interfaccia e lascia la prova a metà",
    "shell.hotReload": "ricarica la shell mentre il banco sta guardando",
    "greeter.background": "è la schermata di accesso: qui non c'è",
    # ── E le tre che spengono la scrivania mentre la si guarda ──────────
    #
    # Valgono zero, cioè «mai», e la regola dei numeri le porterebbe a uno:
    # un secondo. Il banco resta fermo per minuti — è il suo mestiere — e si
    # ritroverebbe la sessione sospesa o bloccata a metà giro, senza capire
    # perché. È la regola scritta in `minerva-non-toccare-in-prova`:
    # **una prova non deve poter spegnere niente.**
    "power.suspendAfter": "sospenderebbe la sessione di prova mentre gira",
    "power.lockAfter": "bloccherebbe lo schermo a metà giro",
    "power.dimAfter": "abbasserebbe la luce e falserebbe ogni fotografia",
    "power.lidAction": "l'azione del coperchio non si prova senza un coperchio",
    # E la disposizione della tastiera: cambiarla è il difetto che è costato
    # otto ore il 1º settembre 2026, e qui non si vedrebbe nemmeno.
    "input.layout": "cambiare disposizione lascerebbe la tastiera altrove",
}


def valore_diverso(percorso, v):
    """Un secondo valore da provare, o (None, motivo)."""
    if percorso in MAI:
        return None, MAI[percorso]
    if percorso in STATO_RICORDATO:
        return None, "stato ricordato: " + STATO_RICORDATO[percorso]
    if isinstance(v, bool):
        return (not v), None
    if isinstance(v, str):
        fam = PAROLE.get(percorso)
        if not fam:
            return None, "non so quali valori accetta: va dichiarato in PAROLE"
        for x in fam:
            if x != v:
                return x, None
        return None, "un solo valore possibile"
    if isinstance(v, float):
        if 0.0 <= v <= 1.0:
            # Una frazione: si va all'altro capo, restando dentro i limiti che
            # quasi tutti i cursori hanno (mezzo e uno).
            return (0.5 if v > 0.75 else 1.0), None
        return (v / 2 if v > 4 else v + 2), None
    if isinstance(v, int):
        # ── Un intero non è mai una frazione ────────────────────────────
        #
        # `windows.gap` vale 1 e sono PIXEL, non un novanta per cento: la
        # regola delle frazioni lo portava a 0,5, cioè a mezzo pixel. Peggio,
        # `power.suspendAfter` vale 0 — «mai» — e sarebbe diventato un secondo.
        return (int(v / 2) if v > 4 else v + 2), None
    return None, "non è un numero, una levetta né una parola"


# ── Il canale del demone di prova ──────────────────────────────────────────
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

    def impostazioni(self):
        """La mappa intera, dal saluto del demone."""
        fine = time.time() + 20
        while time.time() < fine:
            riga = self.f.readline()
            if not riga:
                break
            try:
                m = json.loads(riga)
            except ValueError:
                continue
            if m.get("event") == "init_state":
                return m["payload"]["settings"]
        return None

    def scrivi(self, percorso, valore):
        self._manda({"action": "set_setting", "path": percorso, "value": valore})


def foto(display, dest):
    amb = dict(os.environ)
    amb["WAYLAND_DISPLAY"] = display
    try:
        r = subprocess.run(["grim", dest], env=amb, capture_output=True,
                           timeout=20)
        if r.returncode != 0:
            return None
        return leggi_png(dest)
    except (OSError, subprocess.SubprocessError, KeyError, ValueError,
            zlib_error):
        return None


# ── «Ferma» non vuol dire IDENTICA, e il blur si spegne ────────────────────
#
# La prima versione aspettava due fotografie identiche byte per byte, e non
# arrivavano mai: col blur acceso SceneFX rimescola un pizzico di rumore a
# ogni fotogramma. Il banco ha detto «instabile» su **92 chiavi su 92** —
# cioè non ha provato niente, dichiarando di non poter provare. Onesto, e
# inutile.
#
# La seconda versione ha alzato la soglia sopra il rumore, e così ha perso le
# manopole piccole: l'accento tocca **tre punti su trentottomila** su una
# scrivania senza finestre, e finiva sotto il rumore insieme a loro.
#
# La terza toglie il rumore invece di alzarsi sopra: **il blur si spegne per
# tutto il giro** e si riaccende alla fine. Misurato:
#
#     col blur     rumore fra due scatti fermi   0,097 %
#     senza blur                                 0,0000 %
#
# Con lo zero sotto, mezzo punto su diecimila è già una differenza vera — e la
# prova in tre tempi (si rimette com'era e deve tornare) tiene fuori i casi.
#
# Le manopole che il blur lo VOGLIONO (sono la sua trasparenza) lo riaccendono
# solo per il loro giro: sono elencate in `VUOLE_IL_BLUR`.
FERMA_SOTTO = 0.005
MUOVE_SOPRA = 0.005

# ── E le stesse due, per le tre manopole che il blur lo ACCENDONO ─────────
#
# Per loro il rumore torna, e con lui la soglia. Con 0,005 non si posavano
# mai: il banco aspettava otto secondi, non trovava due scatti abbastanza
# uguali, e a seconda di come cadeva il tempo diceva «instabile» oppure — il
# caso peggiore — «non muove». È così che `windows.effettoOpacita` è risultata
# ferma pur essendo verificata a mano un minuto dopo.
#
# Non è un allentamento generale: vale solo per tre chiavi, e tutte e tre
# cambiano grandi superfici, dove un punto su cento è ancora un dettaglio.
FERMA_SOTTO_BLUR = 0.4
MUOVE_SOPRA_BLUR = 1.0

# Rimettendo il valore di prima, quanto si tollera che NON torni. Zero sarebbe
# giusto e non regge: col renderer software restano dei pixel di cose che non
# ci sono più (`minerva-residui-software`), e due punti su trentottomila non
# devono buttare via una misura buona. Sopra questo, invece, si muoveva
# qualcos'altro e il giro non vale.
TORNA_SOPRA = 0.05

# Un punto ogni sei pixel: circa trentottomila su 1280×720. Bastano a vedere
# l'accento, che su una scrivania senza finestre ne tocca tre.
PASSO = 6

# Le manopole che REGOLANO il blur: per loro si riaccende, o non regolano
# niente e il banco direbbe il falso al contrario.
VUOLE_IL_BLUR = {
    "shell.membraneOpacityBlur",
    "dock.opacityBlur",
    "windows.effettoOpacita",
}

# ── E quanto si aspetta PRIMA di guardare se si è fermato ──────────────────
#
# La strada da una manopola a un pixel è lunga: il demone scrive su disco,
# annuncia, la shell rifà la tavolozza, il compositore riceve i comandi
# (`WindowRules` li raccoglie per mezzo secondo prima di mandarli) e ridisegna.
#
# Con otto decimi di secondo il banco fotografava una scrivania ferma — ferma
# perché la manopola non era ancora arrivata — e scriveva «non muove». Ha
# detto «non muove» su `shell.scheme` e su `shell.accent`, che cambiano il
# colore di tutto: un verde al contrario, cioè il peggiore.
ATTESA = 2.6


def ferma(display, dest, sotto=FERMA_SOTTO, quanto=8.0):
    """Aspetta che lo schermo si posi, e restituisce l'ultima fotografia."""
    prec = None
    fine = time.time() + quanto
    while time.time() < fine:
        d = foto(display, dest)
        if prec is not None and d is not None:
            q = diversi(prec, d, PASSO)
            if q is not None and q < sotto:
                return d
        prec = d
        time.sleep(0.4)
    return None


def main():
    solo = [a for a in sys.argv[1:] if not a.startswith("-")]
    soloelenco = "--elenco" in sys.argv[1:]

    if not soloelenco and not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland.", file=sys.stderr)
        return 1

    if soloelenco:
        # Senza accendere niente: si legge la configurazione vera in sola
        # lettura e si dice cosa si proverebbe. Serve a vedere la copertura
        # senza aspettare un quarto d'ora.
        casa = os.environ.get("MINERVA_CONFIG_DIR", cartelle.config_di_partenza())
        with open(os.path.join(casa, "settings.json")) as f:
            impostazioni = json.load(f)
        return elenca(impostazioni, solo)

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-prova-impostazioni.log")
    log = open(registro, "w")
    # ── E una FINESTRA dentro, o un terzo delle manopole non si prova ────
    #
    # `windows.titleBars`, `titleHeight`, `buttonsSide`, `gap`, `cornice`,
    # `effettoOpacita`, `fullscreenBar`, `bar.listaFinestre`,
    # `shell.windowOpacity`: tutte agiscono su una finestra, e senza finestre
    # il banco diceva «non muove» su tutte e nove — la verità, e la verità
    # sbagliata.
    #
    # La Calcolatrice e non un terminale: è NOSTRA (quindi prova anche il
    # vetro delle finestre di Minerva) e soprattutto sta ferma. Un terminale
    # col cursore che lampeggia non fa mai posare lo schermo, e il banco
    # direbbe «instabile» su tutto.
    avvio = subprocess.Popen(
        [os.path.join(RADICE, "compositore", "prova-annidata.sh"),
         os.path.join(RADICE, "scripts", "minerva-calcolatrice")],
        stdout=log, stderr=subprocess.STDOUT)
    display = None
    for _ in range(40):
        time.sleep(0.5)
        try:
            testo = open(registro).read()
        except OSError:
            continue
        m = re.search(r"compositore su (\S+)", testo)
        if m:
            display = m.group(1)
            break
    if display is None:
        print("la sessione annidata non è partita — registro: %s" % registro,
              file=sys.stderr)
        avvio.terminate()
        return 1
    print("sessione annidata su %s   (registro: %s)" % (display, registro))

    # La shell ci mette un po' a disegnare barra, dock e sfondo: prima di
    # allora ogni fotografia è diversa dalla precedente e il banco direbbe
    # «instabile» su tutto.
    time.sleep(22)

    try:
        d = Demone(CONF_PROVA)
        impostazioni = d.impostazioni()
        if impostazioni is None:
            print("il demone di prova non manda le impostazioni",
                  file=sys.stderr)
            return 1
        return gira(d, display, impostazioni, solo)
    finally:
        avvio.terminate()
        try:
            avvio.wait(timeout=15)
        except subprocess.TimeoutExpired:
            avvio.kill()
        log.close()


def elenca(impostazioni, solo):
    quante = {"si": 0, "no": 0}
    for gruppo in sorted(impostazioni):
        v = impostazioni[gruppo]
        if not isinstance(v, dict) or (solo and gruppo not in solo):
            continue
        for chiave in sorted(v):
            percorso = "%s.%s" % (gruppo, chiave)
            nuovo, motivo = valore_diverso(percorso, v[chiave])
            if motivo is None:
                quante["si"] += 1
                print("  provabile     %-34s %r → %r"
                      % (percorso, v[chiave], nuovo))
            else:
                quante["no"] += 1
                print("  NON provabile %-34s %s" % (percorso, motivo))
    print("\n  %d provabili, %d no" % (quante["si"], quante["no"]))
    return 0


def gira(d, display, impostazioni, solo):
    scatto = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                          "minerva-manopola.png")
    mosse, ferme, instabili, saltate = [], [], [], []

    # ── Il blur si spegne, e si dice ────────────────────────────────────
    #
    # Il suo pizzico di rumore copre le manopole piccole. Vedi il blocco su
    # `FERMA_SOTTO` per i numeri. Si rimette com'era alla fine, comunque
    # vada — anche se il banco si interrompe a metà.
    effetto_prima = impostazioni.get("windows", {}).get("effetto", "nessuno")
    d.scrivi("windows.effetto", "nessuno")
    time.sleep(ATTESA)
    print("  ·  blur spento per la durata del giro (era «%s»): il suo "
          "rumore\n     coprirebbe le manopole che toccano pochi pixel"
          % effetto_prima)

    for gruppo in sorted(impostazioni):
        v = impostazioni[gruppo]
        if not isinstance(v, dict) or (solo and gruppo not in solo):
            continue
        for chiave in sorted(v):
            percorso = "%s.%s" % (gruppo, chiave)
            vecchio = v[chiave]
            nuovo, motivo = valore_diverso(percorso, vecchio)
            if motivo is not None:
                saltate.append((percorso, motivo))
                continue

            # ── La manopola che il banco stesso sta tenendo ferma ────────
            #
            # `windows.effetto` è spenta dal banco per tutta la durata del
            # giro. Il valore «di prima» non è quello scritto nel file: è
            # quello che c'è sullo schermo adesso, cioè «nessuno». Senza
            # questa riga il banco rimetteva «blur» alla fine del suo giro,
            # vedeva lo schermo cambiare del 12,6 % e dichiarava «instabile»
            # l'unica manopola su cui non poteva sbagliarsi.
            if percorso == "windows.effetto":
                vecchio = "nessuno"
                nuovo = "blur"

            vuole_blur = percorso in VUOLE_IL_BLUR
            if vuole_blur:
                d.scrivi("windows.effetto", "blur")
                time.sleep(ATTESA)

            sotto = FERMA_SOTTO_BLUR if vuole_blur else FERMA_SOTTO
            sopra = MUOVE_SOPRA_BLUR if vuole_blur else MUOVE_SOPRA
            prima = ferma(display, scatto, sotto)
            if prima is None:
                instabili.append((percorso, "lo schermo non si ferma mai"))
                if vuole_blur:
                    d.scrivi("windows.effetto", "nessuno")
                continue

            d.scrivi(percorso, nuovo)
            time.sleep(ATTESA)
            dopo = ferma(display, scatto, sotto)

            d.scrivi(percorso, vecchio)
            time.sleep(ATTESA)
            tornato = ferma(display, scatto, sotto)

            if vuole_blur:
                d.scrivi("windows.effetto", "nessuno")
                time.sleep(0.6)

            q_dopo = diversi(prima, dopo, PASSO)
            q_torna = diversi(prima, tornato, PASSO)
            if q_dopo is None or q_torna is None:
                instabili.append((percorso, "lo schermo non si ferma mai"))
            elif q_torna >= max(TORNA_SOPRA, sopra):
                # Qualcosa si muoveva da solo: di questa chiave, questo giro,
                # non si sa dire niente. È il caso in cui una prova onesta
                # tace invece di inventare un verde.
                instabili.append((percorso, "non torna com'era (%.3f%% diverso)"
                                  % q_torna))
            elif q_dopo >= sopra:
                mosse.append(percorso)
                # ── Il residuo, che è una notizia e non un disturbo ───────
                #
                # Rimettendo il valore di prima lo schermo deve tornare
                # identico. Quando restano due o tre punti diversi non è il
                # banco che sbaglia: sono pixel di una cosa che non c'è più,
                # la famiglia di difetti che questo progetto conosce col nome
                # di `minerva-residui-software`. Si dice, invece di buttarlo
                # in «instabile».
                res = "  ·residuo %.3f%%" % q_torna if q_torna > 0 else ""
                print("  muove         %-34s %r → %r   (%.2f%%)%s"
                      % (percorso, vecchio, nuovo, q_dopo, res))
            else:
                ferme.append((percorso, vecchio, nuovo))
                print("  NON MUOVE     %-34s %r → %r   (%.3f%%)"
                      % (percorso, vecchio, nuovo, q_dopo))

    d.scrivi("windows.effetto", effetto_prima)

    print("")
    print("── %d muovono, %d NON muovono, %d instabili, %d non provabili ──"
          % (len(mosse), len(ferme), len(instabili), len(saltate)))
    if ferme:
        print("\nLe manopole che non hanno cambiato niente sullo schermo:")
        for percorso, a, b in ferme:
            print("  %-34s %r → %r" % (percorso, a, b))
        print("\nNon sono tutte difetti: alcune agiscono su una finestra che "
              "qui non è aperta,\naltre su qualcosa che una fotografia non "
              "vede (un suono, una soglia di tempo).\nQuello che conta è che "
              "adesso sono un ELENCO, e non un dubbio.")
    if instabili:
        print("\nSu queste il banco non sa dire niente:")
        for percorso, perche in instabili:
            print("  %-34s %s" % (percorso, perche))
    return 0


if __name__ == "__main__":
    sys.exit(main())
