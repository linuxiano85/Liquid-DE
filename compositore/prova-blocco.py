#!/usr/bin/env python3
"""prova-blocco.py — Che il blocco schermo BLOCCHI.

    ./prova-blocco.py

── Perché una prova a sé ───────────────────────────────────────────────────

Perché è il pezzo in cui un errore non si vede. Un blocco che non blocca
sembra identico a uno che blocca, finché qualcuno non ci prova — e chi ci
prova, di solito, non sei tu.

Le tre cose che si provano sono le tre che rendono un blocco un blocco:

  1. quando la serratura arriva, la tastiera **non** è più di nessuna
     finestra;
  2. quando il programma del blocco **muore**, lo schermo resta bloccato. È la
     ragione per cui `ext-session-lock` esiste: con una finestra normale
     basterebbe ucciderne il processo da un'altra console per rientrare;
  3. solo `unlock_and_destroy` — cioè la password giusta — riporta indietro la
     scrivania.

── ANNIDATO, SEMPRE ────────────────────────────────────────────────────────

`WLR_BACKENDS=wayland` e `MINERVA_PROVA=1`, come `prova-annidata.sh`. Nessun
processo viene ucciso senza aver prima letto `MINERVA_PROVA` nel suo
`/proc/PID/environ`: un blocco schermo provato sulla sessione vera è un
computer che non si riapre.
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
    try:
        with open("/proc/%d/environ" % pid, "rb") as f:
            return b"MINERVA_PROVA=1" in f.read().split(b"\0")
    except OSError:
        return False


def chiudi(p, forte=False):
    if p is None or p.poll() is not None:
        return
    if not e_una_prova(p.pid):
        print("  ·    NON chiudo il pid %d: non porta MINERVA_PROVA" % p.pid)
        return
    p.send_signal(signal.SIGKILL if forte else signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()


class Canale:
    def __init__(self, percorso):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(percorso)
        self.resto = b""
        self.righe = []

    def scrivi(self, riga):
        self.s.sendall((riga + "\n").encode())

    def leggi(self, quanto=1.0):
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
        fine = time.time() + quanto
        while True:
            for r in self.righe:
                if r.startswith(prefisso):
                    return r
            if time.time() >= fine:
                return None
            self.leggi(0.3)

    def chiudi(self):
        try:
            self.s.close()
        except OSError:
            pass


def carico(riga):
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

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    amb["MINERVA_COMPOSITORE"] = "minerva-wayland"

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-blocco.log")
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

    print("── Prove del blocco schermo ──")
    print("  ·    display %s   canale %s" % (dentro, canale))

    ascolto = None
    blocco = None
    term = None
    try:
        ascolto = Canale(canale)
        ascolto.scrivi("ascolta")
        ascolto.aspetta("ok ascolto", 3)

        # ── Prima: il protocollo c'è ────────────────────────────────────
        #
        # `wayland-info` viene da `wayland-utils`, che NON è nostro: il 26
        # agosto 2026 se n'è andato insieme a KDE, e questa riga si è messa a
        # dire «il blocco schermo non blocca» su un blocco che bloccava
        # benissimo — le altre dodici verifiche qui sotto passavano tutte,
        # compresa «il compositore annuncia il blocco», che la stessa cosa la
        # chiede al nostro canale.
        #
        # Uno strumento di diagnosi che dichiara morto ciò che è vivo è peggio
        # di nessuno strumento: la stessa frase sta in `minerva-check.sh`, e la
        # stessa sera è toccato scriverla due volte. Se l'attrezzo non c'è si
        # SALTA e lo si dice — come fa già `prova-annunci.py` poche righe più
        # in là — perché il fatto che manchi un attrezzo non è una notizia sul
        # compositore.
        # Serve anche più in giù, per i programmi che la prova apre dentro il
        # compositore annidato: sta qui fuori e non dentro l'if.
        amb_c = dict(amb)
        amb_c["WAYLAND_DISPLAY"] = dentro

        if shutil.which("wayland-info"):
            try:
                info = subprocess.run(["wayland-info"], env=amb_c,
                                      capture_output=True, timeout=15,
                                      text=True).stdout
            except (OSError, subprocess.TimeoutExpired):
                info = ""
            verifica("annuncia ext_session_lock_manager_v1",
                     "ext_session_lock_manager_v1" in info,
                     "senza, «blocca schermo» non fa NIENTE")
        else:
            print("  ·    salto l'elenco dei protocolli: manca wayland-info "
                  "(pacchetto «wayland-utils»). Il blocco si prova lo stesso "
                  "qui sotto, dal vivo.")

        domande = Canale(canale)

        def stato():
            domande.righe = []
            domande.scrivi("stato")
            r = domande.aspetta("ok {", 4)
            try:
                return json.loads(r[3:]) if r else None
            except ValueError:
                return None

        # Una finestra vera da proteggere: il blocco deve toglierle la
        # tastiera, e una prova senza niente da bloccare non prova niente.
        term = None
        for c in ("alacritty", "foot", "kitty", "konsole"):
            if shutil.which(c):
                term = subprocess.Popen([c], env=amb_c,
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
                break
        if term is not None:
            ascolto.aspetta("evento fuoco ", 15)
        prima = stato()
        verifica("prima del blocco lo schermo è libero",
                 prima is not None and prima.get("bloccato") is False, prima)
        verifica("e la tastiera è di qualcuno",
                 prima is not None and prima.get("fuoco", "") != "",
                 "nessuna finestra a fuoco: la prova non proverebbe niente")

        # ── Il blocco VERO di Minerva ───────────────────────────────────
        #
        # Non un finto: quello di Minerva, che è il client che conta. Non
        # chiede la password a nessuno qui dentro — `MINERVA_BLOCCO_PROVA`
        # gli dice di sbloccarsi da solo dopo tot secondi, ed è l'uscita di
        # sicurezza scritta apposta in `blocco.qml`.
        radice = os.path.dirname(QUI)
        amb_b = dict(amb_c)
        amb_b["MINERVA_BLOCCO_PROVA"] = "10"
        ascolto.righe = []
        blocco = subprocess.Popen(
            ["qs", "-n", "-p", os.path.join(radice, "minerva-shell",
                                            "blocco.qml")],
            env=amb_b, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        riga = ascolto.aspetta("evento blocco ", 25)
        _, cb = carico(riga) if riga else (None, None)
        verifica("il compositore annuncia il blocco",
                 cb is not None and cb.get("bloccato") is True, riga)

        dentro_blocco = stato()
        verifica("da bloccati nessuna finestra ha la tastiera",
                 dentro_blocco is not None
                 and dentro_blocco.get("fuoco", "?") == "", dentro_blocco)

        # ── E nemmeno chiedendolo dal canale ────────────────────────────
        #
        # La tenda impedisce di VEDERE; questa prova riguarda l'altra metà:
        # che non si possa SCRIVERE. Senza il rifiuto in `fuoco_finestra`,
        # bastava una riga sul canale per mettere la tastiera dentro un
        # terminale coperto da uno schermo nero.
        if prima is not None and prima.get("fuoco"):
            domande.righe = []
            domande.scrivi("fuoco " + prima["fuoco"])
            domande.aspetta("ok", 3)
            dopo = stato()
            verifica("«fuoco» da bloccati non dà la tastiera a nessuno",
                     dopo is not None and dopo.get("fuoco", "?") == "", dopo)

        # ── La regola che rende un blocco un blocco ─────────────────────
        #
        # Il programma del blocco muore ammazzato — è quello che farebbe
        # chiunque volesse rientrare da un'altra console. Lo schermo deve
        # restare bloccato.
        ascolto.righe = []
        chiudi(blocco, forte=True)
        blocco.wait(timeout=5)
        time.sleep(1.5)
        ascolto.leggi(1.0)
        sbloccato = [r for r in ascolto.righe
                     if r.startswith("evento blocco ")
                     and '"bloccato":false' in r]
        verifica("ucciso il blocco, NON si sblocca", not sbloccato, sbloccato)
        morto = stato()
        verifica("e il compositore lo sa ancora",
                 morto is not None and morto.get("bloccato") is True, morto)
        verifica("e la tastiera resta di nessuno",
                 morto is not None and morto.get("fuoco", "?") == "", morto)
        verifica("il compositore è vivo", comp.poll() is None, comp.returncode)

        # ── E la strada per uscirne ─────────────────────────────────────
        #
        # Da qui non si esce più: è giusto così, ed è il punto. Si spegne il
        # compositore, si riaccende, e si prova l'altra metà — che con
        # `unlock_and_destroy` la scrivania torni.
        blocco = None
        chiudi(comp)
        comp.wait(timeout=6)
        ascolto.chiudi()
        ascolto = None
        domande.chiudi()

        log2 = open(registro + ".2", "wb")
        comp = subprocess.Popen([BIN], stdout=log2, stderr=subprocess.STDOUT,
                                env=amb)
        dentro2, canale2 = "", ""
        for _ in range(24):
            time.sleep(0.5)
            try:
                testo = open(registro + ".2", "r", errors="replace").read()
            except OSError:
                continue
            m1 = re.search(r"^minerva-wayland: in ascolto su (\S+)", testo, re.M)
            if m1:
                dentro2 = m1.group(1)
            m2 = re.search(r"^minerva-wayland: canale su (\S+)", testo, re.M)
            if m2:
                canale2 = m2.group(1)
            if dentro2 and canale2:
                break
        verifica("il compositore riparte", bool(dentro2 and canale2))

        if dentro2 and canale2:
            ascolto = Canale(canale2)
            ascolto.scrivi("ascolta")
            ascolto.aspetta("ok ascolto", 3)
            amb_b2 = dict(amb)
            amb_b2["WAYLAND_DISPLAY"] = dentro2
            amb_b2["MINERVA_BLOCCO_PROVA"] = "6"
            blocco = subprocess.Popen(
                ["qs", "-n", "-p", os.path.join(radice, "minerva-shell",
                                                "blocco.qml")],
                env=amb_b2, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL)
            r1 = ascolto.aspetta("evento blocco ", 25)
            _, c1 = carico(r1) if r1 else (None, None)
            verifica("si blocca di nuovo",
                     c1 is not None and c1.get("bloccato") is True, r1)
            ascolto.righe = []
            r2 = ascolto.aspetta("evento blocco ", 20)
            _, c2 = carico(r2) if r2 else (None, None)
            verifica("e sbloccandosi per bene la scrivania torna",
                     c2 is not None and c2.get("bloccato") is False, r2)

        print("──")
        if fallite == 0:
            print("TUTTE PASSATE (%d)" % passate)
            return 0
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        print("registro del compositore: %s" % registro)
        return 1
    finally:
        for x in (ascolto,):
            if x is not None:
                x.chiudi()
        chiudi(blocco)
        try:
            chiudi(term)
        except NameError:
            pass
        chiudi(comp)
        log.close()


if __name__ == "__main__":
    sys.exit(main())
