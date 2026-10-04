#!/usr/bin/env python3
"""razza-finestre.py — Che «finestra» resti una finestra, di qualunque razza.

    ./scripts/razza-finestre.py

── Che cosa sorveglia ──────────────────────────────────────────────────────

Dentro `compositore/src/main.c` una finestra può essere di due razze: xdg
(i programmi Wayland) o X11 (Steam, i giochi, Wine). Le due parlano protocolli
diversi, e la differenza è tenuta dentro un gruppo ristretto di funzioni — gli
accessori `finestra_*` e i pochi gestori che per forza appartengono a una
razza sola.

Fuori da lì, `f->toplevel` e `f->xsup` non si scrivono. La regola sta scritta
nel file dal 25 agosto 2026:

    Da qui in poi la regola è: fuori dalle funzioni `finestra_*` non si scrive
    mai `f->toplevel`.

── Perché una guardia e non solo un commento ───────────────────────────────

Perché chi la infrange non se ne accorge. `f->toplevel` su una finestra X11 è
NULL: il compositore non dà nessun errore, non stampa niente, e cade — o
peggio, non cade e si comporta storto solo con Steam aperto. Un commento lo
legge chi lo cerca; questa riga lo dice a chi non lo sta cercando.

È la quarta guardia meccanica del progetto, dopo `verbi-compositore.py`,
`nomi-scorciatoie.py` e `azioni-scorciatoie.py`. Come le altre, ha trovato
qualcosa il giorno stesso in cui è stata scritta.
"""
import os
import re
import sys

QUI = os.path.dirname(os.path.abspath(__file__))
SORGENTE = os.path.join(QUI, "..", "compositore", "src", "main.c")

# ── Chi ha il diritto di sapere di che razza è una finestra ──────────────
#
# Gli accessori, cioè il confine stesso, e i gestori che vivono da una parte
# sola: un `commit` di xdg-shell non esiste in X11, e un `associate` di X11 non
# esiste in xdg-shell. Aggiungere un nome qui è una decisione, non una
# formalità: vuol dire dire «questa funzione sa di protocolli».
PERMESSE = {
    # Il confine.
    "finestra_superficie", "finestra_geometria", "finestra_titolo",
    "finestra_classe", "finestra_di_attiva", "finestra_di_geometria",
    "finestra_di_ingrandita", "finestra_di_ridotta",
    "finestra_di_schermo_intero", "finestra_di_chiuditi",
    "finestra_ha_genitore", "finestra_massimo", "finestra_pid",
    "finestra_pronta",
    # «Vuole nascere a schermo intero / ingrandita»: le due razze lo dicono in
    # due campi diversi. Erano due righe dentro `finestra_appare`, cioè fuori
    # dal confine, e questa guardia lo ha detto a ogni giro finché qualcuno non
    # l'ha letto — l'8 settembre 2026.
    "finestra_vuole_pieno", "finestra_vuole_ingrandita",
    # «Le si può scrivere?»: una xdg prima del primo commit, o smappata, no
    # (wlroots si ferma con un assert); una X11 sempre. Dalla revisione del
    # 30 settembre 2026, entrata con l'unione del 4 ottobre.
    "finestra_configurabile",
    # Il ciclo di vita xdg, che di xdg parla per forza.
    "decorazione_applica", "finestra_commit", "finestra_nuova",
    "finestra_distrutta", "decorazione_nuova",
    # Il ciclo di vita X11, idem.
    "le_spetta_x11", "x11_associa", "x11_dissocia", "x11_mappata",
    "x11_smappata", "x11_configura_chiesta", "x11_chiede_fuoco",
    "finestra_x11_nuova", "xwayland_superficie_nuova", "xwayland_pronto",
    # Le richieste, che leggono lo stato dalla parte giusta.
    "chiede_schermo", "chiede_riduci", "chiede_ridimensiona",
}

# ── Su CHI si cerca, e perché si ricava dal file ─────────────────────────
#
# `->toplevel` e `->xsup` compaiono anche su cose che non sono finestre
# nostre: la decorazione di xdg porta il proprio toplevel (`d->toplevel`), e
# le finestre «override redirect» hanno una struttura tutta loro
# (`s->xsup`) che è X11 per definizione — non c'è nessun confine da
# attraversare, perché non c'è nessuna seconda razza.
#
# Quindi non si cerca «qualunque cosa seguita da ->toplevel»: si cercano i
# nomi che in questo file sono davvero `struct finestra *`, e quei nomi si
# leggono dal file. Aggiungerne uno nuovo domani non richiede di ricordarsi
# di questa guardia — che è esattamente il modo in cui una guardia smette di
# guardare.
DICHIARA = re.compile(r"struct finestra \*(\w+)")
INIZIO = re.compile(r"^(?:static\s+)?[A-Za-z_][\w \t\*]*?\b(\w+)\s*\([^;]*$")


def funzioni(testo):
    """(nome, primo rigo, ultimo rigo) di ogni funzione di primo livello."""
    righe = testo.split("\n")
    fuori = []
    nome = None
    inizio = 0
    dentro = False
    for i, r in enumerate(righe):
        if not dentro:
            m = INIZIO.match(r)
            if m and not r.rstrip().endswith(";"):
                nome = m.group(1)
                inizio = i
            if r.startswith("{") or (r.rstrip().endswith("{") and nome):
                dentro = True
        elif r == "}":
            dentro = False
            if nome:
                fuori.append((nome, inizio, i))
            nome = None
    return fuori


def main():
    if not os.path.exists(SORGENTE):
        print("non trovo %s" % SORGENTE, file=sys.stderr)
        return 2
    testo = open(SORGENTE, encoding="utf-8").read()
    righe = testo.split("\n")
    mappa = funzioni(testo)

    nomi = set(DICHIARA.findall(testo))
    # I nomi di funzione che TORNANO una finestra non sono variabili.
    nomi -= {n for n, _, _ in mappa}
    if not nomi:
        print("nessuna variabile «struct finestra *»: la guardia non "
              "guarderebbe niente", file=sys.stderr)
        return 2
    cerca = re.compile(r"\b(?:%s)->(?:toplevel|xsup)\b"
                       % "|".join(sorted(nomi, key=len, reverse=True)))

    def chi(i):
        for nome, a, b in mappa:
            if a <= i <= b:
                return nome
        return None

    colpevoli = []
    for i, r in enumerate(righe):
        spoglia = r.split("//", 1)[0]
        if not cerca.search(spoglia):
            continue
        f = chi(i)
        if f is None or f in PERMESSE:
            continue
        colpevoli.append((i + 1, f, r.strip()))

    if colpevoli:
        print("── Il confine fra «finestra» e «protocollo» è stato "
              "attraversato ──")
        for n, f, r in colpevoli:
            print("  main.c:%d  dentro %s()" % (n, f))
            print("      %s" % r)
        print("")
        print("Una di queste due cose:")
        print("  · si usa un accessore `finestra_*` invece del campo diretto;")
        print("  · oppure la funzione appartiene DAVVERO a una razza sola, e")
        print("    allora il suo nome va aggiunto a PERMESSE in questo file —")
        print("    che è una decisione, non una formalità.")
        return 1

    print("ok: %d funzioni, %d nomi di finestra sorvegliati, e nessuno tocca "
          "un protocollo fuori dal confine" % (len(mappa), len(nomi)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
