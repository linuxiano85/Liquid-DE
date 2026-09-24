#!/usr/bin/env python3
"""prova-schermi-vivi.py — Che la pagina Schermi cambi qualcosa DAVVERO.

    ./prova-schermi-vivi.py

── Che cosa prova ──────────────────────────────────────────────────────────

Il verbo `schermo`: risoluzione, scala, rotazione, posizione e spegnimento,
applicati **mentre la sessione gira**. Prima esisteva solo la lettura
all'avvio: la pagina Schermi scriveva `~/.config/liquid-de/schermi.conf` e la
modifica si vedeva al riavvio, che non è quello che chiede chi sta guardando
uno schermo storto.

── Perché sul backend HEADLESS e non annidata come le altre ────────────────

Perché questa è l'unica prova del compositore che deve poter **spegnere e
riaccendere** uno schermo, e sotto il backend Wayland — un compositore dentro
un altro, come girano tutte le altre prove — riaccendere **blocca il
processo**: `wlr_output_commit_state` non torna più, perché per riaccendere
deve parlare col compositore ospite e quel dialogo aspetta il ciclo di eventi
dentro cui sta girando. Misurato il 26 agosto 2026.

Il backend headless non ha nessun ospite con cui parlare, come il backend
vero (DRM) — quindi prova la stessa strada — e non tocca lo schermo di
nessuno: non apre nemmeno una finestra. È anche il motivo per cui il
compositore, dentro una prova annidata, **si rifiuta** di spegnere uno
schermo: uno schermo che non si riaccende è una trappola, non una funzione a
metà.

Attenzione a non confondere con `AQ_BACKENDS=headless`, che è di aquamarine e
che una volta ha aperto due finestre sullo schermo vero fingendo di
obbedire (vedi la memoria `minerva-trappole-prove`). `WLR_BACKENDS=headless` è
un'altra cosa, ed è verificata qui sotto: la prova controlla da sé che non sia
comparsa nessuna finestra.
"""
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.environ.get("MINERVA_BIN",
                                  os.path.join(QUI, "build-native")),
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

    La riga che permette di chiudere una prova senza rischiare di chiudere la
    sessione di chi la lancia. Vedi `minerva-trappole-prove`.
    """
    try:
        with open("/proc/%d/environ" % pid, "rb") as f:
            return b"MINERVA_PROVA=1" in f.read().split(b"\0")
    except OSError:
        return False


def chiudi(p):
    if p is None or p.poll() is not None:
        return
    if not e_una_prova(p.pid):
        print("  ·    NON chiudo il pid %d: non porta MINERVA_PROVA" % p.pid)
        return
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()


def chiedi(percorso, riga, pazienza=4.0):
    """Un comando, una risposta. `None` se il compositore non risponde.

    Ogni comando apre e chiude il proprio collegamento apposta: è il modo in
    cui si accorge se il compositore ha smesso di accettarne di nuovi — che è
    esattamente il sintomo di un ciclo di eventi bloccato.
    """
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(pazienza)
    try:
        s.connect(percorso)
        s.sendall((riga + "\n").encode())
        dati = b""
        while b"\n" not in dati:
            pezzo = s.recv(65536)
            if not pezzo:
                break
            dati += pezzo
        return dati.decode("utf-8", "replace").strip()
    except (OSError, socket.timeout):
        return None
    finally:
        s.close()


def elenco(percorso):
    r = chiedi(percorso, "schermi")
    if r is None or not r.startswith("ok ["):
        return None
    try:
        return json.loads(r[3:])
    except ValueError:
        return None


def trova(lista, nome):
    for s in lista or []:
        if s.get("nome") == nome:
            return s
    return None


def main():
    if not os.access(BIN, os.X_OK):
        print("manca %s — lancia prima ./costruisci.sh" % BIN, file=sys.stderr)
        return 2

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "headless"
    amb["WLR_HEADLESS_OUTPUTS"] = "2"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    # Senza questa, il compositore legge la configurazione VERA di Giacomo e
    # la prova dipende da come ha messo i suoi schermi.
    amb["MINERVA_CONFIG_DIR"] = os.path.join(
        os.environ.get("TMPDIR", "/tmp"), "minerva-schermi-prova")
    os.makedirs(amb["MINERVA_CONFIG_DIR"], exist_ok=True)

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-schermi-vivi.log")
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

    print("── Prove degli schermi, da vivi ──")
    if not canale:
        print("il compositore non è partito. Registro:", file=sys.stderr)
        print(open(registro, errors="replace").read()[-2000:], file=sys.stderr)
        chiudi(comp)
        return 1

    testo = open(registro, "r", errors="replace").read()
    verifica("il backend è headless, non quello vero",
             "Creating headless backend" in testo
             and "DRM backend" not in testo,
             "cerca «Creating headless backend» nel registro")

    try:
        lista = elenco(canale)
        verifica("i due schermi ci sono", lista is not None and len(lista) == 2,
                 lista)
        if lista is None or len(lista) != 2:
            return 1
        uno, due = "HEADLESS-1", "HEADLESS-2"
        verifica("e si chiamano come ci si aspetta",
                 trova(lista, uno) is not None and trova(lista, due) is not None,
                 [s.get("nome") for s in lista])
        verifica("l'elenco porta anche la descrizione del monitor",
                 all(isinstance(s.get("descrizione"), str) for s in lista),
                 lista[0])
        verifica("e i campi che servono alla pagina Schermi",
                 all(k in lista[0] for k in
                     ("hz", "rotazione", "modi", "scala", "acceso")),
                 sorted(lista[0].keys()))

        verifica("solo secondo monitor: transazione accettata",
                 chiedi(canale, "monitori-prova prova-solo solo " + due) == "ok")
        lista = elenco(canale)
        verifica("solo il secondo è acceso", not trova(lista, uno)["acceso"] and trova(lista, due)["acceso"])
        verifica("altre modifiche bloccate durante la conferma",
                 chiedi(canale, "schermo " + due + " preferito 2").startswith("no "))
        verifica("un token estraneo non conferma", chiedi(canale, "monitori-conferma estraneo").startswith("no "))
        verifica("annullamento configurazione", chiedi(canale, "monitori-annulla prova-solo") == "ok")
        verifica("annullamento riaccende entrambi", all(s["acceso"] for s in elenco(canale)))
        verifica("nuova transazione solo secondo", chiedi(canale, "monitori-prova prova-conferma solo " + due) == "ok")
        verifica("conferma configurazione", chiedi(canale, "monitori-conferma prova-conferma") == "ok")
        verifica("estendi riattiva entrambi", chiedi(canale, "monitori-prova prova-estendi estendi") == "ok"
                 and all(s["acceso"] for s in elenco(canale)))
        verifica("conferma estensione", chiedi(canale, "monitori-conferma prova-estendi") == "ok")
        lista = elenco(canale)
        verifica("estesi: il secondo sta a destra del primo",
                 trova(lista, due)["x"] > trova(lista, uno)["x"], [(s["nome"], s["x"]) for s in lista])

        # ── Duplica: stessa scena, stesso punto ─────────────────────────
        verifica("duplica: transazione accettata",
                 chiedi(canale, "monitori-prova prova-duplica duplica") == "ok")
        lista = elenco(canale)
        verifica("duplicati: tutti e due accesi", all(s["acceso"] for s in lista))
        verifica("duplicati: tutti e due nello stesso punto",
                 trova(lista, uno)["x"] == trova(lista, due)["x"] == 0
                 and trova(lista, uno)["y"] == trova(lista, due)["y"] == 0,
                 [(s["nome"], s["x"], s["y"]) for s in lista])
        verifica("duplica con un nome è rifiutato",
                 chiedi(canale, "monitori-prova prova-x duplica " + due).startswith("no "))
        verifica("conferma la duplicazione", chiedi(canale, "monitori-conferma prova-duplica") == "ok")
        lista = elenco(canale)
        verifica("confermata: restano nello stesso punto",
                 trova(lista, uno)["x"] == trova(lista, due)["x"] == 0,
                 [(s["nome"], s["x"], s["y"]) for s in lista])
        # Da qui in poi lo stato «di prima» È la duplicazione: annullare una
        # nuova duplica torna a duplicato, non a esteso. Sembra ovvio scritto,
        # e scritto male sarebbe una prova che accusa il compositore di un
        # difetto che non ha.
        verifica("di nuovo duplica, per provare l'annullamento",
                 chiedi(canale, "monitori-prova prova-duplica2 duplica") == "ok")
        verifica("annulla la duplicazione", chiedi(canale, "monitori-annulla prova-duplica2") == "ok")
        lista = elenco(canale)
        verifica("annullata: si torna a com'era, cioè duplicati",
                 trova(lista, uno)["x"] == trova(lista, due)["x"] == 0,
                 [(s["nome"], s["x"]) for s in lista])
        verifica("si torna a estendere", chiedi(canale, "monitori-prova prova-estendi2 estendi") == "ok")
        verifica("conferma l'estensione", chiedi(canale, "monitori-conferma prova-estendi2") == "ok")
        lista = elenco(canale)
        verifica("estesi di nuovo: il secondo è a destra",
                 trova(lista, due)["x"] > trova(lista, uno)["x"], [(s["nome"], s["x"]) for s in lista])
        verifica("timeout avviato", chiedi(canale, "monitori-prova prova-timeout solo " + due) == "ok")
        deadline = time.monotonic() + 18
        while time.monotonic() < deadline:
            if all(s["acceso"] for s in elenco(canale)): break
            time.sleep(.2)
        verifica("timeout ripristina senza intervento della UI", all(s["acceso"] for s in elenco(canale)))

        # ── La scala, che è la cosa che si cambia più spesso ─────────────
        verifica("la scala si cambia",
                 chiedi(canale, "schermo %s preferito 2" % due) == "ok")
        s2 = trova(elenco(canale), due)
        verifica("e vale davvero",
                 s2 is not None and abs((s2.get("scala") or 0) - 2.0) < 0.01, s2)
        verifica("e lo spazio logico si dimezza",
                 s2 is not None and s2.get("larghezza") == 640, s2)

        verifica("si torna indietro",
                 chiedi(canale, "schermo %s preferito 1" % due) == "ok")
        s2 = trova(elenco(canale), due)
        verifica("e la misura torna quella di prima",
                 s2 is not None and s2.get("larghezza") == 1280, s2)

        # ── La rotazione ────────────────────────────────────────────────
        verifica("si ruota di 90 gradi",
                 chiedi(canale, "schermo %s preferito 1 90" % due) == "ok")
        s2 = trova(elenco(canale), due)
        verifica("e lo schermo diventa alto invece che largo",
                 s2 is not None and s2.get("larghezza") == 720
                 and s2.get("altezza") == 1280, s2)
        verifica("e l'elenco lo dice in GRADI, non in numeri di Wayland",
                 s2 is not None and s2.get("rotazione") == 90, s2)
        chiedi(canale, "schermo %s preferito 1 0" % due)

        # ── La posizione ────────────────────────────────────────────────
        verifica("si sposta uno schermo rispetto all'altro",
                 chiedi(canale, "schermo %s preferito 1 0 100 50" % due) == "ok")
        s2 = trova(elenco(canale), due)
        verifica("e ci va davvero",
                 s2 is not None and s2.get("x") == 100 and s2.get("y") == 50, s2)

        # ── Spegnere e riaccendere ──────────────────────────────────────
        #
        # È il pezzo per cui questa prova gira sul backend headless: sotto
        # quello annidato riaccendere blocca il compositore.
        verifica("uno schermo si spegne",
                 chiedi(canale, "schermo %s spento" % due) == "ok")
        verifica("e il compositore risponde ancora",
                 chiedi(canale, "ciao") == "ok minerva-wayland")
        s2 = trova(elenco(canale), due)
        verifica("da spento resta nell'elenco, per poterlo riaccendere",
                 s2 is not None, elenco(canale))
        verifica("e si vede che è spento",
                 s2 is not None and s2.get("acceso") is False, s2)

        verifica("e si riaccende",
                 chiedi(canale, "schermo %s preferito 1 0 1280 0" % due) == "ok")
        verifica("senza che il compositore resti fermo",
                 chiedi(canale, "ciao") == "ok minerva-wayland")
        s2 = trova(elenco(canale), due)
        verifica("ed è tornato acceso e grande come prima",
                 s2 is not None and s2.get("acceso") is True
                 and s2.get("larghezza") == 1280, s2)

        # ── I rifiuti, che sono la parte che conta ──────────────────────
        r = chiedi(canale, "schermo NON-ESISTE preferito")
        verifica("uno schermo che non c'è si rifiuta",
                 r is not None and r.startswith("no"), r)
        r = chiedi(canale, "schermo %s ciao" % due)
        verifica("un modo scritto male si rifiuta, dicendo come si scrive",
                 r is not None and r.startswith("no") and "1920x1080" in r, r)
        r = chiedi(canale, "schermo %s preferito 9" % due)
        verifica("una scala assurda si rifiuta",
                 r is not None and r.startswith("no"), r)
        r = chiedi(canale, "schermo %s preferito 1 45" % due)
        verifica("una rotazione che non è un quarto di giro si rifiuta",
                 r is not None and r.startswith("no"), r)

        # ── E l'ultimo schermo acceso non si spegne ─────────────────────
        #
        # È il rifiuto più importante di tutti: spegnere l'ultimo vuol dire
        # restare senza niente su cui rimediare all'errore.
        verifica("si spegne il secondo",
                 chiedi(canale, "schermo %s spento" % due) == "ok")
        r = chiedi(canale, "schermo %s spento" % uno)
        verifica("ma NON l'ultimo che resta acceso",
                 r is not None and r.startswith("no") and "unico" in r, r)
        s1 = trova(elenco(canale), uno)
        verifica("e infatti è ancora acceso",
                 s1 is not None and s1.get("acceso") is True, s1)

        # ── Nessuna finestra sullo schermo vero ─────────────────────────
        verifica("riattivo il secondo per la prova di scollegamento", chiedi(canale, "schermo " + due + " preferito 1") == "ok")
        verifica("solo esterno prima di scollegarlo", chiedi(canale, "monitori-prova scollega solo " + due) == "ok")
        verifica("conferma solo esterno", chiedi(canale, "monitori-conferma scollega") == "ok")
        verifica("scollegamento simulato", chiedi(canale, "prova-monitor-rimuovi " + due) == "ok")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            lista = elenco(canale)
            if len(lista) == 1 and lista[0]["acceso"]: break
            time.sleep(.1)
        verifica("lo schermo rimasto si riaccende", len(lista) == 1 and lista[0]["nome"] == uno and lista[0]["acceso"])

        verifica("il compositore è ancora vivo alla fine",
                 comp.poll() is None, comp.poll())
    finally:
        chiudi(comp)
        log.close()

    print("── %d passate, %d fallite ──" % (passate, fallite))
    if fallite:
        print("registro del compositore: %s" % registro)
    return 1 if fallite else 0


if __name__ == "__main__":
    sys.exit(main())
