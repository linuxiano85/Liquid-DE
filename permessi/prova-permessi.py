#!/usr/bin/env python3
"""prova-permessi.py — L'agente delle password, e la sua finestra.

    ./prova-permessi.py

── Cosa si può provare da qui, e cosa no ──────────────────────────────────

Non si può provare il giro completo. Un agente polkit si registra per una
SESSIONE — quella di logind — e di agenti per sessione ce n'è **uno solo**:
provare quello vero vorrebbe dire togliere di mezzo l'agente della sessione su
cui si sta lavorando, cioè lasciare senza finestra della password la macchina
di chi la sta usando. Non si fa, per la stessa ragione per cui non si prova
la sospensione.

E non si può nemmeno DIGITARE: dentro un compositore annidato non c'è una
tastiera finta, e i tasti veri se li prende la sessione ospite.

Quello che si prova è tutto il resto, che non è poco — ed è, guarda caso, dove
stanno i difetti che si vedono:

  1. **I rifiuti.** Un agente che non parte deve dirlo e uscire, non restare
     lì. Se resta lì, `minerva-dentro-wayland` crede che vada tutto bene e non
     avvia nessun ripiego: da quel momento ogni richiesta di permesso sparisce
     in silenzio, e il programma che l'ha chiesta sembra bloccato.
  2. **La finestra si carica senza un solo avviso.** È lo stesso controllo che
     `prove.sh` fa su tutte le app di Minerva, e qui vale doppio: questa
     finestra compare tre volte al giorno e in mezzo a un'operazione già
     cominciata.
  3. **La finestra parla il protocollo.** Si collega, aspetta, e non manda
     niente di sua iniziativa.
  4. **E se ne va quando la richiesta finisce.** Chiuso il socket, il processo
     deve uscire da sé. Una finestra della password che resta aperta dopo che
     il permesso è stato dato o negato chiede una password a nessuno.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

`WLR_BACKENDS=wayland` e `MINERVA_PROVA=1`. Nessun processo viene ucciso senza
aver prima letto `MINERVA_PROVA` nel suo `/proc/PID/environ`.
"""
import os
import re
import socket
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import cartelle  # noqa: E402  le cartelle di Liquid DE
import time

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
sys.path.insert(0, os.path.join(RADICE, "compositore"))
from importlib import import_module

_annunci = import_module("prova-annunci")
chiudi = _annunci.chiudi

DOVE = cartelle.cartella_bin()
AGENTE = os.path.join(DOVE, "minerva-polkit")
COMPOSITORE = os.path.join(DOVE, "minerva-wayland")

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


def esegui(amb, quanto=10):
    """Lancia l'agente e torna (uscita, testo). None se non è uscito."""
    p = subprocess.Popen([AGENTE], env=amb, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT)
    try:
        fuori, _ = p.communicate(timeout=quanto)
        return p.returncode, fuori.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        p.kill()
        p.communicate()
        return None, ""


def prove_dei_rifiuti():
    print("── I rifiuti dell'agente ──")

    amb = dict(os.environ)
    amb.pop("MINERVA_ROOT", None)
    codice, testo = esegui(amb)
    verifica("senza MINERVA_ROOT non parte, e lo dice",
             codice == 1 and "MINERVA_ROOT" in testo, (codice, testo.strip()))

    amb = dict(os.environ)
    amb["MINERVA_ROOT"] = "/non/esisto"
    codice, testo = esegui(amb)
    verifica("con una radice sbagliata dice quale file non trova",
             codice == 1 and "permessi.qml" in testo, (codice, testo.strip()))

    # ── Il caso che capita davvero ──────────────────────────────────────
    #
    # Un agente c'è già — è quello della sessione su cui gira questa prova.
    # Deve rifiutare SUBITO e uscire: se restasse in piedi senza essere
    # registrato, `minerva-dentro-wayland` non avvierebbe nessun ripiego e
    # ogni richiesta di permesso sparirebbe in silenzio.
    amb = dict(os.environ)
    amb["MINERVA_ROOT"] = RADICE
    codice, testo = esegui(amb)
    verifica("se un agente c'è già, si rifiuta invece di restare lì",
             codice == 1, (codice, testo.strip()))
    verifica("e dice perché", "registrare" in testo, testo.strip())


def apri_finestra(amb_base, dentro, coda):
    """Apre la finestra e le parla. Torna (processo, socket accettato)."""
    percorso = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                            "minerva-prova-permessi-%d-%s.sock"
                            % (os.getpid(), coda))
    try:
        os.unlink(percorso)
    except OSError:
        pass
    ascolto = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    ascolto.bind(percorso)
    os.chmod(percorso, 0o600)
    ascolto.listen(1)
    ascolto.settimeout(25)

    amb = dict(amb_base)
    amb["WAYLAND_DISPLAY"] = dentro
    amb["MINERVA_POLKIT_CANALE"] = percorso
    amb["MINERVA_POLKIT_AZIONE"] = "prova.minerva.permessi"

    p = subprocess.Popen(
        ["qs", "-p", os.path.join(RADICE, "minerva-shell", "permessi.qml")],
        env=amb, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        con, _ = ascolto.accept()
    except socket.timeout:
        con = None
    ascolto.close()
    try:
        os.unlink(percorso)
    except OSError:
        pass
    return p, con


# Le righe che NON sono difetti. È la stessa lista di `scripts/prove.sh`, e
# ognuna ha una ragione:
#
#  · «no receivers connected» la stampa Quickshell quando il programma esce da
#    sé chiamando `Qt.quit()` — cioè esattamente quello che questa prova gli
#    chiede di fare;
#  · «host portal» è xdg-desktop-portal che non riconosce l'identità dell'app.
#    Il file `desktop/minerva-permessi.desktop` esiste apposta, ma il portale
#    di questa macchina non lo vede da dentro una sessione annidata, e non
#    dipende dal nostro codice.
IGNORA = ("no receivers connected", "host portal")


def avvisi(testo):
    """Le righe di `qs` che sono difetti."""
    return [r for r in testo.splitlines()
            if re.search(r"\b(WARN|ERROR)\b", r)
            and not any(x in r for x in IGNORA)]


def prove_della_finestra():
    print("── La finestra della password ──")

    if not os.access(COMPOSITORE, os.X_OK):
        print("  ·    salto: manca %s" % COMPOSITORE)
        return
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("  ·    salto: non siamo in una sessione Wayland")
        return

    amb = dict(os.environ)
    amb["MINERVA_PROVA"] = "1"
    amb["WLR_BACKENDS"] = "wayland"
    amb.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

    registro = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                            "minerva-permessi.log")
    log = open(registro, "wb")
    comp = subprocess.Popen([COMPOSITORE], stdout=log,
                            stderr=subprocess.STDOUT, env=amb)

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
        verifica("il compositore annidato parte", False,
                 open(registro, errors="replace").read()[-800:])
        chiudi(comp)
        return

    try:
        # ── Il giro normale: si chiede, si risponde, si chiude ──────────
        #
        # Il socket lo fa la prova: qui si sta al posto di `minerva-polkit`, e
        # si parla lo stesso protocollo che parla lui.
        finestra, con = apri_finestra(amb, dentro, "pulito")
        verifica("la finestra si collega al canale dell'agente",
                 con is not None)
        uscita = ""
        if con is not None:
            con.settimeout(3)
            con.sendall(b'richiesta "giacomo" "Prova dei permessi di '
                        b'Minerva"\n')
            con.sendall(b'chiedi segreto "Password: "\n')
            time.sleep(1.5)

            # Non deve dire niente finché nessuno tocca niente: se mandasse
            # una `risposta` da sola, manderebbe una password vuota a PAM.
            spontanea = b""
            try:
                spontanea = con.recv(4096)
            except socket.timeout:
                pass
            verifica("e non manda niente di sua iniziativa",
                     spontanea == b"", spontanea)
            verifica("ed è ancora viva mentre aspetta",
                     finestra.poll() is None)

            # `fatto` è come finisce una richiesta andata a buon fine: la
            # finestra deve chiudersi da sé, senza che nessuno la uccida.
            con.sendall(b"fatto\n")
            try:
                finestra.wait(timeout=8)
                andata = True
            except subprocess.TimeoutExpired:
                andata = False
            verifica("con «fatto» la finestra si chiude da sé", andata)
            con.close()

        if finestra.poll() is None:
            finestra.kill()
        uscita = finestra.communicate()[0].decode("utf-8", "replace")

        # ── Nessun avviso ───────────────────────────────────────────────
        #
        # Lo stesso controllo che `prove.sh` fa su ogni app di Minerva. Le
        # righe di `qs` che cominciano per WARN o ERROR sono difetti: un
        # binding rotto, una proprietà che non esiste, un file che non si
        # carica. Si guarda il giro PULITO — quello sotto chiude il socket di
        # colpo apposta, e un avviso lì è la conseguenza voluta della prova.
        brutte = avvisi(uscita)
        verifica("la finestra si carica senza un solo avviso",
                 not brutte, "\n".join(brutte[:6]))

        # ── E se l'agente muore ─────────────────────────────────────────
        #
        # Una finestra della password che resta aperta quando dall'altra parte
        # non c'è più nessuno chiede una password a nessuno — e col fuoco
        # esclusivo sarebbe una tastiera che non serve più a niente.
        finestra2, con2 = apri_finestra(amb, dentro, "morto")
        verifica("si collega anche la seconda volta", con2 is not None)
        if con2 is not None:
            con2.sendall(b'richiesta "giacomo" "Prova"\n')
            con2.sendall(b'chiedi segreto "Password: "\n')
            time.sleep(1.5)
            con2.close()
            try:
                finestra2.wait(timeout=8)
                andata2 = True
            except subprocess.TimeoutExpired:
                andata2 = False
            verifica("se l'agente sparisce, la finestra si chiude da sé",
                     andata2)
        if finestra2.poll() is None:
            finestra2.kill()
        finestra2.communicate()
    finally:
        chiudi(comp)


def main():
    if not os.access(AGENTE, os.X_OK):
        print("manca %s — lancia prima ./costruisci.sh" % AGENTE,
              file=sys.stderr)
        return 2

    prove_dei_rifiuti()
    prove_della_finestra()

    print("──")
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
