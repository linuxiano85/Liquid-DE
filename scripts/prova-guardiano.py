#!/usr/bin/env python3
"""Il guardiano del demone muore con la sessione che l'ha lanciato?

── Il difetto ────────────────────────────────────────────────────────────

Trovato il 7 settembre 2026 misurando altro: sulla macchina giravano DUE
`minervad`, quello della sessione in corso e quello di quella precedente, ognuno
col suo guardiano. Il padre di quello vecchio era `init`: era stato adottato,
cioè era uscito del tutto dall'albero della sessione.

La causa è `minerva-reload.sh`, che rilancia il guardiano con `nohup` per farlo
sopravvivere allo script — e da quel momento non è più figlio di nessuno, quindi
l'uscita dalla sessione non se lo porta via. Resta un demone che risponde su un
socket, per una scrivania che non esiste più, fino al riavvio del computer.

Non è solo memoria sprecata: un programma che si collegasse a quel canale
parlerebbe con un demone che comanda una sessione morta.

── Come si prova ─────────────────────────────────────────────────────────

Questa prova costruisce la stessa forma con un finto compositore — uno script
chiamato `minerva-wayland`, perché è dal nome che il guardiano lo riconosce — e
poi lo uccide.

I processi di prova NON si cercano nell'albero dei figli, ed è una lezione presa
scrivendola: con `nohup` in mezzo il guardiano viene adottato da `init` quasi
subito, quindi non è più discendente di nessuno. Si cercano invece per la
`MINERVA_SESSIONE` che porta in ambiente, che è unica di questa prova — ed è
anche l'unico modo di essere certi di non toccare la sessione vera.

Il guardiano e il suo demone devono sparire da soli. Con `nohup` in mezzo,
perché la prova sia quella vera: senza, si proverebbe solo che un figlio muore
col padre, che è già vero e non è il caso che ci interessa.

La sessione vera non si tocca: il finto guardiano ha una `MINERVA_SESSIONE`
tutta sua e un socket suo.
"""
import os
import shutil
import signal
import subprocess
import sys

import cartelle  # le cartelle di Liquid DE, accanto a questo file
import tempfile
import time

QUI = os.path.dirname(os.path.abspath(__file__))
GUARDIANO = os.path.join(QUI, "minerva-demone")

passate = 0
fallite = 0


def verifica(cosa, ok, dettaglio=""):
    global passate, fallite
    if ok:
        passate += 1
        print("  ok   %s" % cosa)
    else:
        fallite += 1
        print("  NO   %s%s" % (cosa, ("  → %s" % dettaglio) if dettaglio else ""))


def vivo(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    # Uno zombie risponde a `kill -0` ma non è vivo: lo si riconosce dallo stato.
    try:
        with open("/proc/%d/stat" % pid) as f:
            return f.read().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


def discendenti(radice):
    """Tutti i pid sotto `radice`, compresa lei."""
    figli = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open("/proc/%s/stat" % d) as f:
                ppid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, IndexError, ValueError):
            continue
        figli.setdefault(ppid, []).append(int(d))
    fuori, coda = [], [radice]
    while coda:
        p = coda.pop()
        fuori.append(p)
        coda.extend(figli.get(p, []))
    return fuori


def main():
    if not os.path.isfile(GUARDIANO):
        print("FERMO: non trovo %s" % GUARDIANO, file=sys.stderr)
        return 2

    marchio = "provaguardiano%d" % os.getpid()
    tmp = tempfile.mkdtemp(prefix="minerva-prova-guardiano-")
    finto = os.path.join(tmp, "minerva-wayland")
    # Il finto compositore lancia il guardiano con `nohup`, esattamente come fa
    # `minerva-reload.sh`, e poi aspetta.
    with open(finto, "w") as f:
        f.write("#!/bin/sh\n"
                "nohup '%s' >/dev/null 2>&1 &\n"
                "sleep 600\n" % GUARDIANO)
    os.chmod(finto, 0o755)

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["MINERVA_SESSIONE"] = marchio
    # NON si mette WAYLAND_DISPLAY, ed è il punto della prova: il compositore
    # vero quella variabile non ce l'ha — è lui a crearla. Il primo tentativo
    # gliela dava, la prova passava, e sulla sessione vera la sentinella non
    # partiva. Un'impalcatura più comoda della realtà non prova la realtà.
    amb.pop("WAYLAND_DISPLAY", None)
    amb["MINERVA_IPC_SOCKET"] = "/run/user/%d/minerva-pg-%d.sock" % (
        os.getuid(), os.getpid())
    amb["MINERVA_CONFIG_DIR"] = os.path.join(tmp, "conf")

    def nostri():
        """I processi che portano il marchio di QUESTA prova."""
        fuori = {}
        for d in os.listdir("/proc"):
            if not d.isdigit():
                continue
            try:
                with open("/proc/%s/environ" % d, "rb") as f:
                    if ("MINERVA_SESSIONE=" + marchio).encode() not in f.read().split(b"\0"):
                        continue
                fuori[int(d)] = open("/proc/%s/comm" % d).read().strip()
            except OSError:
                continue
        return fuori

    comp = subprocess.Popen([finto], env=amb)
    print("  ·    finto compositore pid %d, marchio %s" % (comp.pid, marchio))

    try:
        visti = {}
        for _ in range(60):
            time.sleep(0.5)
            visti = nostri()
            if any("minervad" in n for n in visti.values()):
                break
        verifica("il guardiano accende il demone",
                 any("minervad" in n for n in visti.values()),
                 "in trenta secondi non è nato nessun demone (visti: %s)" % visti)
        if not visti:
            return 1
        # Solo il guardiano e il demone: il `sleep 600` del finto compositore
        # porta lo stesso marchio ed è un pezzo dell'impalcatura, non della
        # scrivania. Contarlo faceva fallire la prova su una cosa vera.
        sorvegliati = [p for p, n in visti.items()
                       if p != comp.pid and ("minerva-demone" in n or "minervad" in n)]
        print("  ·    col marchio della prova: %s" %
              ", ".join("%d(%s)" % (p, visti[p]) for p in sorvegliati))

        # ── E adesso il compositore muore ─────────────────────────────────
        comp.send_signal(signal.SIGKILL)
        comp.wait(10)

        # Venti secondi sono larghi: la sentinella guarda ogni cinque.
        fine = time.monotonic() + 20
        rimasti = sorvegliati
        while time.monotonic() < fine:
            rimasti = [p for p in sorvegliati if vivo(p)]
            if not rimasti:
                break
            time.sleep(0.5)

        verifica("morto il compositore, il guardiano e il demone se ne vanno",
                 not rimasti,
                 "sono rimasti in piedi: %s — un demone orfano che risponde "
                 "per una scrivania che non c'è più"
                 % ", ".join("%d(%s)" % (p, visti.get(p, "?")) for p in rimasti))
    finally:
        for p in nostri():
            try:
                os.kill(p, signal.SIGKILL)
            except OSError:
                pass
        shutil.rmtree(tmp, ignore_errors=True)
        try:
            os.unlink(amb["MINERVA_IPC_SOCKET"])
        except OSError:
            pass
        shutil.rmtree(os.path.join(cartelle.runtime(), "sessioni", marchio),
                      ignore_errors=True)

    print()
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
