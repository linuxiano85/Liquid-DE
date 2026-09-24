#!/usr/bin/env python3
"""prova-ingresso.py — Che le manopole di tastiera, mouse e colore arrivino.

    ./prova-ingresso.py

── Perché esiste ───────────────────────────────────────────────────────────

Perché fino al 26 agosto 2026 non arrivava nessuna. Il pannello «Tastiera e
mouse» mandava tutto con `hyprctl keyword`, che sotto il nostro compositore
non è nessuno, e il sintomo peggiore si vede subito e si spiega tardi: **la
tastiera resta americana.** Le accentate non si scrivono, la chiocciola è in
un altro posto, e non c'è nessun errore da nessuna parte.

── Che cosa guarda, e perché non basta la risposta «ok» ────────────────────

La disposizione non si verifica chiedendo al compositore che cosa gli abbiamo
detto: si chiede a **xkb** che cosa ha davvero la tastiera. Sono due cose
diverse ogni volta che una disposizione non esiste, ed è esattamente il caso
in cui una prova sulla nostra copia direbbe verde su una tastiera americana.

Per questo `dispositivi` manda due campi: `disposizione` in cima è quella
CHIESTA, e quella dentro ogni tastiera è quella VERA.

── ANNIDATA ───────────────────────────────────────────────────────────────

Come le altre — `WLR_BACKENDS=wayland`, `MINERVA_PROVA=1` — e per una ragione
in più: il backend annidato una tastiera ce l'ha (quella dell'ospite), mentre
quello headless no, e senza tastiera non c'è niente da provare.

Le manopole del touchpad qui si possono verificare solo fino a metà: il
puntatore annidato non passa da libinput, quindi non ha manopole. Si verifica
che il compositore le accetti e che rifiuti quelle assurde — il resto lo
verifica il touchpad vero, sotto le dita di chi lo usa.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import cartelle  # noqa: E402  le cartelle di Liquid DE
import time

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)
from importlib import import_module

_annunci = import_module("prova-annunci")
Canale = _annunci.Canale
chiudi = _annunci.chiudi

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


def _json_di(risposta):
    """Il corpo di una risposta «ok {...}», o None se non è quella forma."""
    if not risposta or not risposta.startswith("ok "):
        return None
    try:
        return json.loads(risposta[3:])
    except ValueError:
        return None


# ── Le fotografie, senza dipendere da niente che possa mancare ───────────
#
# `grim` è già quello che usano le altre prove del compositore. Se non c'è, la
# prova non fallisce e non finge: dice che non ha potuto guardare, e il
# controllo che dipende dai pixel si salta. Una prova che si dichiara saltata
# è onesta; una che passa senza aver guardato no.
def _foto(display):
    if display is None or not _c_e("grim"):
        return None
    fuori = "/tmp/minerva-prova-tinta-%d.png" % os.getpid()
    amb = dict(os.environ)
    amb["WAYLAND_DISPLAY"] = display
    try:
        r = subprocess.run(["grim", fuori], env=amb, timeout=15)
        if r.returncode != 0:
            return None
        with open(fuori, "rb") as f:
            dati = f.read()
        os.unlink(fuori)
        return dati
    except (OSError, subprocess.SubprocessError):
        return None


def _c_e(programma):
    """C'è, questo programma?"""
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if os.access(os.path.join(d, programma), os.X_OK):
            return True
    return False


def main():
    if not os.access(BIN, os.X_OK):
        print("manca %s — lancia prima ./costruisci.sh" % BIN, file=sys.stderr)
        return 2
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non sei in una sessione Wayland; wlroots prenderebbe "
              "lo schermo vero.", file=sys.stderr)
        return 2

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-ingresso.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([BIN], stdout=log, stderr=subprocess.STDOUT,
                            env=amb)

    canale = ""
    for _ in range(24):
        time.sleep(0.5)
        try:
            testo = open(registro, "r", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"^minerva-wayland: canale su (\S+)", testo, re.M)
        if m:
            canale = m.group(1)
            break
    dentro = ""
    try:
        d = re.search(r"^minerva-wayland: in ascolto su (\S+)",
                      open(registro, "r", errors="replace").read(), re.M)
        if d:
            dentro = d.group(1)
    except OSError:
        pass

    print("── Prove dell'ingresso (tastiera, puntatore, touchpad) ──")
    if not canale:
        print("il compositore non è partito. Registro:", file=sys.stderr)
        print(open(registro, errors="replace").read()[-2000:], file=sys.stderr)
        chiudi(comp)
        return 1

    c = None
    try:
        c = Canale(canale)

        def chiedi(riga, quanto=4.0):
            c.righe = []
            c.scrivi(riga)
            fine = time.time() + quanto
            while time.time() < fine:
                for r in c.righe:
                    if r.startswith("ok") or r.startswith("no"):
                        return r
                c.leggi(0.2)
            return None

        def stato():
            r = chiedi("dispositivi")
            if r is None or not r.startswith("ok {"):
                return None
            try:
                return json.loads(r[3:])
            except ValueError:
                return None

        def vera():
            s = stato()
            if not s or not s.get("tastiere"):
                return None
            return s["tastiere"][0].get("disposizione")

        s = stato()
        verifica("il compositore elenca i dispositivi", s is not None, s)
        if s is None:
            return 1
        verifica("e c'è almeno una tastiera",
                 len(s.get("tastiere") or []) > 0, s)
        verifica("con dentro la disposizione che ha DAVVERO",
                 bool(vera()), s.get("tastiere"))

        # ── La disposizione ─────────────────────────────────────────────
        verifica("la tastiera si mette in italiano",
                 chiedi("tastiera it") == "ok")
        verifica("e xkb dice che è italiana, non che gliel'abbiamo detto",
                 vera() == "Italian", vera())

        verifica("si cambia di nuovo", chiedi("tastiera de") == "ok")
        verifica("e diventa tedesca", vera() == "German", vera())

        # ── Il rifiuto che conta ────────────────────────────────────────
        #
        # Una disposizione che non esiste non deve lasciare senza tastiera —
        # `xkb` senza mappa non produce NESSUN simbolo, e non è «una tastiera
        # sbagliata», è una tastiera morta. E non deve nemmeno essere
        # accettata in silenzio: chi ha appena scelto una voce da un menu
        # deve sapere che quella voce non c'è.
        r = chiedi("tastiera zz-non-esiste")
        verifica("una disposizione inventata si rifiuta",
                 r is not None and r.startswith("no"), r)
        verifica("e quella di prima resta al suo posto",
                 vera() == "German", vera())

        verifica("«-» rimette quella di sistema",
                 chiedi("tastiera -") == "ok")
        verifica("e non è più tedesca", vera() != "German", vera())

        # ── La ripetizione ──────────────────────────────────────────────
        verifica("la ripetizione dei tasti si cambia",
                 chiedi("ripetizione 30 400") == "ok")
        s = stato()
        verifica("e il compositore la tiene",
                 s is not None and s.get("ripetizioni") == 30
                 and s.get("ritardo") == 400, s)
        for storta in ("ripetizione 0 600", "ripetizione 25 5",
                       "ripetizione 500 600"):
            r = chiedi(storta)
            verifica("«%s» si rifiuta" % storta,
                     r is not None and r.startswith("no"), r)

        # ── Il puntatore e il touchpad ──────────────────────────────────
        verifica("la sensibilità si accetta", chiedi("sensibilita 0.2") == "ok")
        verifica("e il neutro pure", chiedi("sensibilita 0") == "ok")
        for storta in ("sensibilita 9", "sensibilita -2"):
            r = chiedi(storta)
            verifica("«%s» si rifiuta" % storta,
                     r is not None and r.startswith("no"), r)

        verifica("le tre manopole del touchpad si accettano",
                 chiedi("touchpad si si no") == "ok")
        verifica("e «-» per quelle che non si stanno toccando",
                 chiedi("touchpad - - si") == "ok")

        r = chiedi("dispositivo no Non-Esiste")
        verifica("spegnere un dispositivo che non c'è si rifiuta",
                 r is not None and r.startswith("no"), r)

        # ── Gli appunti, e perché la prova sta QUI ──────────────────────
        #
        # 1º settembre 2026: **copiare non funzionava in nessun programma.**
        # Non c'era nessun errore — «Ctrl+C» sembrava fare il suo, e incollare
        # non dava niente. Giacomo se n'è accorto perché non riusciva a
        # incollare un comando nel terminale.
        #
        # Il motivo: `wlr_data_device_manager_create` apre il protocollo, ma
        # poi il seat CHIEDE il permesso a ogni copia, e nessuno rispondeva.
        # Una riga mancante — `request_set_selection` — e un compositore che
        # per il resto funziona benissimo.
        #
        # Stanno con l'ingresso perché sono la stessa cosa: il seat. E si
        # provano da FUORI, con `wl-copy`, perché quello che conta non è che
        # il compositore abbia il protocollo — è che un programma qualunque
        # riesca a copiare e un altro a incollare.
        if dentro and _c_e("wl-copy") and _c_e("wl-paste"):
            amb_c = dict(os.environ)
            amb_c["WAYLAND_DISPLAY"] = dentro
            for opzioni, come in (([], "gli appunti"),
                                  (["-p"], "la selezione primaria")):
                testo_p = "minerva-prova-appunti-%s" % ("p" if opzioni else "c")
                subprocess.run(["wl-copy"] + opzioni, input=testo_p.encode(),
                               env=amb_c, timeout=10)
                letto = ""
                try:
                    letto = subprocess.run(
                        ["wl-paste", "-n"] + opzioni, env=amb_c, timeout=10,
                        capture_output=True).stdout.decode(errors="replace")
                except subprocess.TimeoutExpired:
                    letto = "(nessuna risposta)"
                verifica("%s: quello che si copia si incolla" % come,
                         letto.strip() == testo_p,
                         "copiato «%s», riletto «%s»" % (testo_p,
                                                         letto.strip()))
        else:
            print("  --   niente wl-copy/wl-paste: appunti non provati")

        # ── Il nome con gli SPAZI, ed è la prova che mancava ─────────────
        #
        # 31 agosto 2026, sessione vera. Nel registro della shell:
        #
        #     no non c'è nessun dispositivo che si chiama ELAN0504:01
        #
        # Il touchpad di questo portatile si chiama
        # «ELAN0504:01 04F3:312A Touchpad» — tre parole — e il verbo leggeva
        # il nome con `parola()`, che si ferma al primo spazio. La levetta del
        # touchpad e il tasto Fn che lo spegne non facevano niente, e nessuna
        # prova se n'era accorta: quella nel banco QML controllava il testo
        # SPEDITO, non che il compositore lo capisse.
        #
        # Qui si guarda il rifiuto, non l'accettazione: se il nome torna
        # intero nel messaggio, allora è arrivato intero. Un dispositivo con
        # gli spazi non si può dare per scontato su ogni macchina — il rifiuto
        # invece si può provare ovunque.
        finto = "Nome Finto Con Spazi"
        r = chiedi("dispositivo no " + finto)
        verifica("un nome con gli spazi arriva INTERO",
                 r is not None and finto in r,
                 r)

        # ── E il giro completo, sul nome che dice lui stesso ─────────────
        #
        # I due verbi devono essere d'accordo fra loro: quello che `dispositivi`
        # ELENCA, `dispositivo` deve saperlo SPEGNERE. Non si scrive un nome a
        # mano — si prende il suo, così la prova vale su qualunque macchina.
        s_ora = stato()
        punt = (s_ora or {}).get("puntatori") or []
        if punt:
            suo = punt[0].get("nome", "")
            r = chiedi("dispositivo no " + suo)
            # L'asserzione NON è «ok», ed è voluto: nel backend annidato il
            # puntatore lo dà il compositore che ci ospita e non passa da
            # libinput, quindi non lo si può davvero spegnere. Pretendere «ok»
            # qui vorrebbe dire una prova che fallisce sempre annidata e non
            # gira mai altrove — cioè una prova che non gira.
            #
            # Quello che si pretende è che **non dica una bugia**: il
            # dispositivo che ha appena elencato non può risultare inesistente.
            # È l'asserzione che vale identica sull'hardware vero, dove la
            # risposta giusta è «ok».
            verifica("il nome che elenca lui, lui non lo dichiara inesistente",
                     r is not None and "non c'è nessun dispositivo" not in r,
                     "%s → %s" % (suo, r))
            # E si riaccende: una prova non lascia il puntatore spento.
            chiedi("dispositivo si " + suo)
        else:
            # Detto, non taciuto: una prova saltata in silenzio si confonde
            # con una passata.
            print("  --   nessun puntatore nel backend annidato: giro "
                  "completo non provato")

        # ── L'aspetto della barra del titolo ────────────────────────────
        #
        # Erano `#define`: il pannello «Finestre» mostrava l'altezza e il lato
        # dei pulsanti, li scriveva in `settings.json`, e sotto minerva-wayland
        # non succedeva niente. Un comando che si vede e non fa nulla è peggio
        # di un comando che non c'è.
        verifica("l'altezza della barra si cambia",
                 chiedi("aspetto 52 - - -") == "ok")
        verifica("i pulsanti si spostano a sinistra",
                 chiedi("aspetto - sinistra - -") == "ok")
        verifica("e tornano a destra",
                 chiedi("aspetto - destra - -") == "ok")
        verifica("il colore del fondo si cambia",
                 chiedi("aspetto - - 101820 -") == "ok")
        verifica("e quello del testo",
                 chiedi("aspetto - - - EEF4FF") == "ok")

        # I RIFIUTI, che qui contano più delle accettazioni: una barra alta 4
        # pixel non si prende col dito, e una alta 400 si mangia lo schermo.
        for storta, perche in (
                ("aspetto 4 - - -", "troppo bassa per prenderla col dito"),
                ("aspetto 400 - - -", "si mangerebbe lo schermo"),
                ("aspetto 0x2A - - -", "non è un numero"),
                ("aspetto - sopra - -", "i pulsanti stanno a destra o a sinistra"),
                ("aspetto - - ROSSO -", "non è un colore RRGGBB"),
                ("aspetto - - 12345 -", "cinque cifre non sono un colore")):
            r = chiedi(storta)
            verifica("«%s» si rifiuta (%s)" % (storta, perche),
                     r is not None and r.startswith("no"), r)

        # E si rimette com'era: una prova non lascia la scrivania diversa da
        # come l'ha trovata.
        verifica("l'aspetto torna a quello di fabbrica",
                 chiedi("aspetto 42 destra 0B0F1A EEF4FF") == "ok")

        # ── La lente di ingrandimento ───────────────────────────────────
        #
        # ATTENZIONE a cosa dicono questi verdi: qui si verifica che il verbo
        # arrivi, che i valori storti si rifiutino e che il compositore resti
        # VIVO — che non è poco, perché questa è l'unica cosa di tutto il
        # progetto che tocca il percorso del disegno.
        #
        # Che si veda ingrandito non si prova da qui: è un ritaglio dello
        # scanout, e sul backend annidato dipende dal compositore che ci
        # ospita. Si guarda a occhio, in una sessione annidata.
        verifica("la lente si accende", chiedi("lente 2") == "ok")
        verifica("e si può spingere", chiedi("lente 4") == "ok")
        verifica("e si spegne", chiedi("lente 1") == "ok")
        for storta, perche in (
                ("lente 0.5", "sotto 1 non è un ingrandimento"),
                ("lente 5", "sopra 4 sono francobolli, serve un carattere più grande"),
                ("lente due", "non è un numero"),
                ("lente", "manca la scala")):
            r = chiedi(storta)
            verifica("«%s» si rifiuta (%s)" % (storta, perche),
                     r is not None and r.startswith("no"), r)
        # E dopo tutto questo deve essere ancora in piedi: una lente che
        # spegne il compositore sarebbe molto peggio di una lente che manca.
        verifica("il compositore è vivo dopo la lente",
                 chiedi("stato") is not None)

        # ── La luce notturna ────────────────────────────────────────────
        #
        # Il commento che stava qui diceva «si verifica l'IMPIANTO, non i
        # pixel [...] che lo schermo diventi caldo non lo dice nessuno», e
        # aveva ragione: nessuno lo diceva, e infatti la luce notturna è stata
        # rotta per due settimane senza che una prova diventasse rossa.
        #
        # ── Cosa si era rotto, misurato il 9 settembre 2026 ─────────────
        #
        # Il compositore passava la tabella alla SCENA
        # (`wlr_scene_output_state_options.color_transform`), con scritto
        # accanto che «da qui la applica il renderer, e vale su ogni backend».
        # Non era vero. Stesso binario, stessa scena, due renderer:
        #
        #     GLES2 (il nostro)   0,0 % dei pixel cambia
        #     Vulkan              78,1 %
        #
        # Il renderer GLES2 di wlroots ignora la tabella dei colori, e per noi
        # è definitivo: il renderer di SceneFX è GLES2 e basta. Adesso la
        # tabella va sullo SCHERMO, che è la strada di `gammastep`.
        #
        # ── Cosa può provare una sessione ANNIDATA, e cosa no ───────────
        #
        # Non i pixel: qui la tabella la prenderebbe il monitor, e un monitor
        # qui non c'è. Ma può provare la cosa che era mancata davvero — che il
        # compositore **non menta sulla strada**. `stato` dice `tintaStrada`,
        # e le due risposte hanno conseguenze diverse e verificabili:
        #
        #     "nessuna"   e allora i pixel NON devono cambiare
        #     "schermo"   e allora la tabella è andata al monitor
        #
        # Una prova che guardasse solo «il verbo risponde ok» tornerebbe
        # esattamente al verde che ci ha ingannati.
        verifica("la tinta si accetta", chiedi("colore 1 0.86 0.71") == "ok")
        verifica("e il neutro pure", chiedi("colore 1 1 1") == "ok")
        for storta in ("colore 2 1 1", "colore 1 -1 1", "colore 1 1"):
            r = chiedi(storta)
            verifica("«%s» si rifiuta" % storta,
                     r is not None and r.startswith("no"), r)

        st = _json_di(chiedi("stato"))
        verifica("«stato» dice che tinta abbiamo addosso",
                 st is not None and st.get("tinta") == "1.0000 1.0000 1.0000",
                 st)
        verifica("e con la tinta spenta la strada è «spenta»",
                 st is not None and st.get("tintaStrada") == "spenta", st)

        # ── Prima si guarda se lo schermo sta FERMO ─────────────────────
        #
        # Due fotografie a tinta spenta. Se sono già diverse fra loro — un
        # puntatore che si muove, un programma che ridisegna — allora il
        # confronto dei pixel non può dire niente, e questa prova lo dichiara
        # invece di diventare rossa per il motivo sbagliato. È la trappola in
        # cui questo progetto è già caduto tre volte.
        ferma = _foto(dentro)
        time.sleep(1.0)
        ferma2 = _foto(dentro)
        schermo_immobile = (ferma is not None and ferma == ferma2)

        chiedi("colore 1 0.5 0.3")
        time.sleep(1.0)
        st = _json_di(chiedi("stato"))
        strada = (st or {}).get("tintaStrada")
        verifica("accesa, «stato» ripete i tre numeri",
                 st is not None and st.get("tinta") == "1.0000 0.5000 0.3000",
                 st)
        verifica("e dichiara una strada che esiste",
                 strada in ("schermo", "nessuna"), strada)
        dopo = _foto(dentro)
        if not schermo_immobile:
            print("  --  schermo non fermo (o niente grim): "
                  "il controllo sui pixel della tinta è saltato")
        elif strada == "nessuna":
            # Il caso del backend annidato. Se un giorno qui i pixel
            # cambiassero, vorrebbe dire che la tinta passa da un'altra parte
            # e che questo campo mente — che è il difetto da cui veniamo.
            verifica("dicendo «nessuna», i pixel infatti non cambiano",
                     dopo == ferma,
                     "lo schermo è cambiato pur dicendo di non poter tingere")
        elif strada == "schermo":
            # Qui la tabella l'ha presa il monitor, e `grim` fotografa la
            # scena PRIMA del monitor: non c'è niente da vedere, ed è giusto
            # così. Lo si dice, perché un silenzio si scambia per un verde.
            print("  --  strada «schermo»: la tinta la applica il monitor, "
                  "e una fotografia della scena non la vede")

        # E lo schermo continua a ricevere fotogrammi: rifiutare la tabella
        # non deve MAI voler dire smettere di disegnare. Una scrivania nera
        # perché la luce notturna non si può fare sarebbe una cura peggiore
        # della malattia.
        verifica("e lo schermo continua a consegnare fotogrammi",
                 _foto(dentro) is not None or not _c_e("grim"))
        chiedi("colore 1 1 1")

        # ── E dopo tutto questo il compositore è ancora vivo ────────────
        #
        # Non è una formalità: una mappa xkb sbagliata è il genere di cosa
        # che in wlroots finisce in un `assert`.
        verifica("e il compositore risponde ancora",
                 chiedi("ciao") == "ok minerva-wayland")
        verifica("ed è ancora vivo", comp.poll() is None, comp.poll())
    finally:
        if c is not None:
            c.chiudi()
        chiudi(comp)
        log.close()

    print("── %d passate, %d fallite ──" % (passate, fallite))
    if fallite:
        print("registro del compositore: %s" % registro)
    return 1 if fallite else 0


if __name__ == "__main__":
    sys.exit(main())
