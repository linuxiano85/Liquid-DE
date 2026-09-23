#!/usr/bin/env python3
"""Trascinare un file: il gesto parte?

── Il difetto ────────────────────────────────────────────────────────────

Giacomo, 6 settembre 2026: «nel file manager non posso trascinare i file come
un qualsiasi file manager, ad esempio da cartella a sfondo o da sfondo a file
manager o da file manager in questa finestra per passarti un allegato».

Tutti i pezzi c'erano: il QML offre `text/uri-list`, il compositore risponde a
`request_start_drag`. E al compositore **non arrivava niente**: zero richieste,
contate.

Il motivo stava in due righe di `files/Pane.qml`:

    pane.trascinando = true;
    pane.trascinando = false;   // «tanto la riga sopra non torna»

Accanto c'era scritto che `Drag.active` fa partire un ciclo di eventi suo e
che la riga dopo si esegue a gesto finito. Non è vero — misurato col registro:
le due righe si eseguono nello stesso istante. Quello spegnimento **annullava
il trascinamento un battito dopo averlo acceso**.

── Come si prova ─────────────────────────────────────────────────────────

Un gestore file dentro un compositore annidato, un file trascinato, e si
guarda se al compositore arriva la richiesta — `MINERVA_TRACCIA_TRASCINA=1`
gliela fa scrivere. Non si guarda il risultato del rilascio: quello dipende da
dove si lascia. Si guarda che il gesto **parta**, che è la cosa che non
partiva.

Nessun processo viene ucciso senza aver prima letto `MINERVA_PROVA` nel suo
`/proc/PID/environ`.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.environ.get("MINERVA_BIN",
    os.path.join(QUI, "build-native")), "minerva-wayland")
CLIC = os.path.join(QUI, "..", "scripts", "prova-clic.py")
GESTORE = os.path.join(QUI, "..", "minerva-shell", "filemanager.qml")
TMP = os.environ.get("TMPDIR", "/tmp")


def nostro(pid):
    try:
        with open("/proc/%d/environ" % pid, "rb") as f:
            return b"MINERVA_PROVA=1" in f.read().split(b"\0")
    except OSError:
        return False


def chiudi(p):
    if p is None or p.poll() is not None:
        return
    if not nostro(p.pid):
        print("NON chiudo %d: non porta MINERVA_PROVA" % p.pid, file=sys.stderr)
        return
    p.terminate()
    try:
        p.wait(6)
    except subprocess.TimeoutExpired:
        p.kill()


def chiedi(comando):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"],
                           "minerva-wayland-%s.sock" % os.environ["WAYLAND_DISPLAY"]))
    s.sendall(comando.encode() + b"\n")
    r = s.recv(65536).decode()
    s.close()
    return r


def main():
    if shutil.which("qs") is None:
        print("SALTATA: serve quickshell.")
        return 0

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb["MINERVA_TRACCIA_TRASCINA"] = "1"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(TMP, "minerva-trascinamento.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([BIN], stdout=log, stderr=subprocess.STDOUT, env=amb)

    dentro = ""
    for _ in range(24):
        time.sleep(0.5)
        try:
            testo = open(registro, "r", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"^minerva-wayland: in ascolto su (\S+)", testo, re.M)
        if m:
            dentro = m.group(1)
            break
    if not dentro:
        print("il compositore annidato non è partito:", file=sys.stderr)
        chiudi(comp)
        return 1

    gestore = None
    esito = 0
    try:
        amb_g = dict(amb)
        amb_g["WAYLAND_DISPLAY"] = dentro
        # `qs` diretto e non `scripts/minerva-files`: quello vede il gestore
        # già aperto nella sessione VERA e gli passa la mano, lasciando
        # l'annidato vuoto. Costato mezz'ora di trascinamenti nel nulla.
        gestore = subprocess.Popen(["qs", "-n", "-p", GESTORE], env=amb_g,
                                   stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL)
        time.sleep(13)

        w = None
        for x in json.loads(chiedi("finestre")[3:]):
            if x["classe"] == "wlroots":
                w = x
        if w is None:
            print("non trovo la finestra dell'annidato", file=sys.stderr)
            return 1
        chiedi("fuoco %s" % w["id"])
        time.sleep(1.0)

        # Il primo elemento della griglia, e una trascinata lunga dentro la
        # stessa finestra: quello che conta è che il gesto PARTA.
        subprocess.run(["python3", CLIC, "trascina",
                        str(w["x"] + 364), str(w["y"] + 304),
                        str(w["x"] + 930), str(w["y"] + 617)],
                       capture_output=True)
        time.sleep(2.0)

        testo = open(registro, errors="replace").read()
        chieste = len(re.findall(r"trascinamento chiesto", testo))
        rifiutate = len(re.findall(r"serie RIFIUTATA", testo))
        print("  ·  richieste di trascinamento: %d   (rifiutate: %d)"
              % (chieste, rifiutate))
        if chieste == 0:
            print("ROSSO: il gesto non parte — al compositore non arriva "
                  "nessuna richiesta")
            esito = 1
        elif rifiutate > 0:
            print("ROSSO: il gesto parte e viene rifiutato — il numero di "
                  "serie del clic non regge")
            esito = 1
        else:
            print("VERDE: il trascinamento parte e il compositore lo prende "
                  "in carico")
    finally:
        if gestore is not None and gestore.poll() is None:
            gestore.terminate()
            try:
                gestore.wait(5)
            except subprocess.TimeoutExpired:
                gestore.kill()
        chiudi(comp)
    return esito


if __name__ == "__main__":
    sys.exit(main())
