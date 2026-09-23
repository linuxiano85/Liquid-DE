#!/usr/bin/env python3
# verbi-compositore.py — I verbi che la shell manda a minerva-wayland.
#
#     scripts/verbi-compositore.py minerva-shell/core/Compositore.qml
#
# Ne stampa uno per riga. Lo usa `prove.sh` per confrontarli con quelli che
# `compositore/src/main.c` sa ascoltare: sono due file in due linguaggi diversi
# che devono dire la stessa parola, ed è il posto in cui una differenza NON dà
# errore — il compositore risponde «no verbo sconosciuto» sul socket, la shell
# scrive un avviso che nessuno guarda, e la finestra non si muove.
#
# ── Perché un file e non un grep ───────────────────────────────────────────
#
# Perché il verbo è il SECONDO argomento di `_due(...)`, e le virgolette in un
# file QML sono dappertutto. Due tentativi col solo `grep` hanno dato:
#
#   · `"[a-z]+", \[`   perdeva `ridimensiona`, la cui chiamata va a capo;
#   · `"[a-z]+",`      prendeva ventotto parole, fra cui `hyprctl` e `windows`;
#   · «la seconda stringa fra virgolette» dava uno SPAZIO, perché il primo
#     argomento è una concatenazione: `"movewindowpixel exact " + x + " "`.
#
# Serve separare sulle virgole di primo livello, e per quello ci vuole un
# parser — piccolo, ma un parser.
#
# ── E le chiamate dirette ──────────────────────────────────────────────────
#
# Non tutti i verbi passano da `_due()`. Quelli che sotto Hyprland si fanno in
# un modo del tutto diverso — `riduci`, che là è «mandala nella scrivania di
# servizio» — chiamano `_nostro("verbo", …)` dentro un `if (comp.nostro)`, e
# lì il verbo è il PRIMO argomento e non c'è nessuna concatenazione davanti.
#
# Vanno raccolti anche quelli, o la guardia guarda solo metà porta: `riduci` è
# entrato così ed è passato inosservato al controllo che doveva prenderlo.

import re
import sys


# Il SECONDO argomento di ogni `_due(...)`, separando sulle virgole di PRIMO
# livello. Non basta prendere la seconda stringa fra virgolette: il primo
# argomento è spesso una concatenazione — `"movewindowpixel exact " + x + " "` —
# e la seconda stringa lì dentro è uno spazio.
testo = open(sys.argv[1], encoding="utf-8").read()
fuori = set()
for m in re.finditer(r"_due\(", testo):
    i = m.end()
    prof = 1
    virgolette = False
    pezzi = [""]
    while i < len(testo) and prof > 0:
        c = testo[i]
        if virgolette:
            if c == "\\":
                pezzi[-1] += testo[i:i + 2]; i += 2; continue
            if c == '"':
                virgolette = False
        elif c == '"':
            virgolette = True
        elif c in "([{":
            prof += 1
        elif c in ")]}":
            prof -= 1
            if prof == 0:
                break
        elif c == "," and prof == 1:
            pezzi.append("")
            i += 1
            continue
        pezzi[-1] += c
        i += 1
    if len(pezzi) >= 2:
        secondo = pezzi[1].strip()
        v = re.fullmatch(r'"([^"]*)"', secondo)
        if v is not None and v.group(1):
            fuori.add(v.group(1))
# Le chiamate dirette: `_nostro("verbo", [...])`. Qui il verbo è il primo
# argomento, quindi una espressione regolare basta e avanza.
for v in re.findall(r'_nostro\(\s*"([a-z_]+)"', testo):
    fuori.add(v)

# `--sordi` chiede un'altra cosa e non deve stampare questi.
if not (len(sys.argv) > 2 and sys.argv[2] == "--sordi"):
    for v in sorted(fuori):
        print(v)


# ── E il verso opposto: chi parla SOLO la lingua di Hyprland ───────────────
#
# `--sordi` elenca le funzioni di `core/Compositore.qml` che parlano al
# compositore senza avere una strada verso il nostro.
#
# ── Le DUE porte, e perché una era cieca ──────────────────────────────────
#
# Si esce da questo file in due modi, non uno:
#
#   · `_dispatch(...)`  — i VERBI di Hyprland (`movewindow`, `killactive`);
#   · `imposta(...)`    — i SOSTANTIVI, cioè `hyprctl keyword`
#                         (`decoration:blur:size`, `animations:enabled`).
#
# Fino al 27 agosto 2026 questa guardia guardava solo la prima, e il README del
# compositore lo diceva: «una guardia che non guarda ancora». Nove funzioni
# uscivano dalla seconda porta senza nessuna strada verso minerva-wayland, e
# nessuna riga rossa l'ha mai detto — a `schermo()`, `tastiera()`, `touchpad()`
# e `sensibilitaPuntatore()` ci si era arrivati guardando lo schermo.
#
# ── Non basta nominare `nostro` ───────────────────────────────────────────
#
# Prima bastava che il corpo contenesse la parola «nostro». Troppo poco: un
# `if (comp.nostro) return;` la contiene, e non fa niente — cioè è esattamente
# il difetto che questa guardia cerca, travestito da correzione.
#
# Adesso servono i fatti: `_nostro(` (c'è un verbo) oppure `_senzaStrada(` (la
# mancanza è dichiarata, col perché, in `senzaDestinazione`).
#
# ── Perché questo controllo esiste ────────────────────────────────────────
#
# Perché la guardia di sopra guarda una porta sola. Confronta i verbi che
# passano da `_due()` con quelli che il compositore conosce, e quindi non può
# accorgersi della cosa peggiore: un comando che a minerva-wayland **non viene
# mandato affatto**.
#
# Due volte è successo, e tutte e due le volte in silenzio:
#
#  · `minimize()` mandava `movetoworkspacesilent`, che sotto il nostro
#    compositore se ne andava nel vuoto: la finestra spariva dallo schermo e
#    non c'era modo di riportarla indietro;
#  · `vaiAScrivania()` mandava `workspace N` e basta — le scrivanie non
#    esistevano, e il comando non arrivava a nessuno.
#
# Nessuno dei due dava errore. Erano righe scritte in una lingua che
# dall'altra parte non c'era nessuno a parlare.
# ── Le TRE strade con cui è stata aggirata, il 30 agosto 2026 ─────────────
#
# La versione precedente considerava «parla al compositore» soltanto un corpo
# che contenesse `_dispatch(` o `imposta(`. Quattro punti uscivano per strade
# diverse, e nessuno di loro è mai comparso in una riga rossa:
#
#  1. `ricarica()` → `_accoda(["hyprctl", "reload"])` **diretto**, senza
#     passare da nessuna delle due porte. Sotto minerva-wayland non fa niente,
#     e con lui non fa niente l'azione del coperchio del portatile, che è la
#     sua unica chiamante;
#  2. `monitorAttivo` legge `Hyprland.focusedMonitor` ed è una **proprietà**,
#     non una funzione: il ciclo non la guardava proprio. Sotto di noi vale
#     sempre `""`, e con due schermi una scorciatoia colpisce quello sbagliato
#     **in silenzio**;
#  3. i `Process` di `chiedi()` hanno `command: ["hyprctl", …]` scritto
#     **fuori** da ogni funzione: solo `schermi` e `dispositivi` hanno un ramo
#     nostro, mentre `estensioni`, `puntatore` e `animazioni` lanciano hyprctl
#     comunque.
#
# La regola generale che ne esce, e che vale per la prossima volta: **non si
# cerca il nome della porta, si cerca la parola `hyprctl` e il singleton
# `Hyprland`**, ovunque stiano. Una guardia che conosce solo le strade che
# qualcuno ha già percorso non trova mai quella nuova.
def _corpo_da(testo, inizio):
    """Da un punto fino alla prossima dichiarazione allo stesso rientro."""
    resto = testo[inizio:]
    fine = re.search(r"\n    (?:function |readonly property |property )", resto)
    return resto[:fine.start()] if fine else resto


def _blocchi_nostro(corpo):
    """Il testo di ogni ramo `if (comp.nostro …) { … }` dentro un corpo.

    Serve a distinguere le due cose che si somigliano e sono opposte: un ramo
    che PORTA da qualche parte, e un `if (comp.nostro) return;` che nomina il
    nostro compositore e non fa niente.
    """
    fuori = []
    for m in re.finditer(r"if\s*\(\s*comp\.nostro\b", corpo):
        i = corpo.find("{", m.end())
        # Ramo senza graffe: `if (comp.nostro) return;` — fino al punto e virgola.
        if i < 0 or corpo[m.end():i].count(")") > 1:
            fine = corpo.find(";", m.end())
            fuori.append(corpo[m.end():fine + 1] if fine > 0 else "")
            continue
        prof, j = 1, i + 1
        while j < len(corpo) and prof > 0:
            if corpo[j] == "{":
                prof += 1
            elif corpo[j] == "}":
                prof -= 1
            j += 1
        fuori.append(corpo[i + 1:j - 1])
    return fuori


def _ramo_nostro_fa_qualcosa(corpo):
    """Vero se almeno un ramo `nostro` contiene una chiamata, non solo un
    `return`."""
    for b in _blocchi_nostro(corpo):
        senza_commenti = re.sub(r"//[^\n]*", "", b)
        if re.search(r"\b(?!return\b)\w+\s*\(", senza_commenti):
            return True
    return False


if len(sys.argv) > 2 and sys.argv[2] == "--sordi":
    sordi = []

    # ── a) Le funzioni ───────────────────────────────────────────────────
    for m in re.finditer(r"\n    function (\w+)\(", testo):
        nome = m.group(1)
        corpo = _corpo_da(testo, m.end())
        # `_accoda(["hyprctl"…])` è la terza porta, e non aveva guardiano.
        parla = ("_dispatch(" in corpo
                 or re.search(r"\bimposta\(", corpo)
                 or re.search(r'_accoda\(\s*\[\s*"hyprctl"', corpo)
                 or re.search(r"\bHyprland\.\w", corpo))
        if not parla:
            continue
        # Le porte stesse, e chi dichiara le mancanze: non si giudicano da sé.
        if nome in ("_dispatch", "_due", "_nostro", "imposta", "_senzaStrada",
                    "_accoda"):
            continue
        # `_due(...)` porta il verbo nostro dentro di sé: è già una strada.
        if "_due(" in corpo or "_nostro(" in corpo or "_senzaStrada(" in corpo:
            continue
        # ── E un ramo `nostro` che FA qualcosa ───────────────────────────
        #
        # Non basta nominare `nostro` — un `if (comp.nostro) return;` lo
        # nomina e non fa niente, ed è il difetto travestito da correzione che
        # questa guardia cerca. Ma un ramo che chiama altre funzioni della
        # porta è una strada vera: `ricarica()` sotto minerva-wayland rimanda
        # le scorciatoie e le manopole, che è precisamente ciò che «rileggi la
        # configurazione» vuol dire dove non c'è nessun file da rileggere.
        #
        # Quindi si guarda dentro il ramo: se contiene una chiamata — una
        # parola seguita da `(` che non sia `return` — è una strada.
        if _ramo_nostro_fa_qualcosa(corpo):
            continue
        sordi.append(nome)

    # ── b) Le proprietà che leggono il singleton di Hyprland ─────────────
    #
    # Una proprietà non «manda» niente, ma il valore che restituisce decide
    # cosa fa la shell — ed è per questo che `monitorAttivo` sbagliava schermo
    # senza che nessuno se ne accorgesse. Deve avere un ramo `nostro`, oppure
    # dichiararsi come le altre.
    for m in re.finditer(r"\n    (?:readonly )?property \w+ (\w+):", testo):
        nome = m.group(1)
        corpo = _corpo_da(testo, m.end())
        if not re.search(r"\bHyprland\.\w", corpo):
            continue
        if ("nostro" in corpo or "_nostro(" in corpo
                or "_senzaStrada(" in corpo):
            continue
        sordi.append(nome)

    # ── c) Le domande di `chiedi()` ──────────────────────────────────────
    #
    # Ogni `case "x":` di `chiedi()` fa partire un `Process` che esegue
    # hyprctl. Quelli che hanno una strada nostra si riconoscono da un
    # `comp.nostro && cosa === "x"` più su nella stessa funzione. Gli altri
    # sotto minerva-wayland chiedono a nessuno e non lo dicono.
    m = re.search(r"\n    function chiedi\(", testo)
    if m is not None:
        corpo = _corpo_da(testo, m.end())
        casi = set(re.findall(r'case\s+"(\w+)"\s*:', corpo))
        # Una domanda è coperta se il suo nome compare dentro una condizione
        # `comp.nostro && …`. Si prende TUTTA la condizione e non solo la forma
        # `cosa === "x"` subito dopo `&&`: due domande possono stare nello
        # stesso ramo — `(cosa === "estensioni" || cosa === "animazioni")` — e
        # la prima versione di questa riga ne vedeva zero delle due.
        coperti = set()
        for c in re.finditer(r"if\s*\(\s*comp\.nostro\b([^)]*(?:\)[^)]*)*?)\)\s*\{",
                             corpo):
            coperti.update(re.findall(r'cosa\s*===\s*"(\w+)"', c.group(1)))
        for cosa in sorted(casi - coperti):
            sordi.append("chiedi:" + cosa)

    print(" ".join(sordi))
    sys.exit(0)
