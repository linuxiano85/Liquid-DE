#!/usr/bin/env python3
"""La prova che mancava: l'accesso dall'inizio alla fine, senza schermo.

── Perché esiste ──────────────────────────────────────────────────────────

La schermata di accesso era provata a pezzi, e ogni pezzo passava:

    greetd_service_test.dart   il protocollo di greetd (inquadramento, guasti)
    accesso_service_test.dart  utenti e sessioni
    prove-greeter.qml          cosa fa l'interfaccia davanti a ogni messaggio
    socket_ipc_test.dart       su che socket si parlano demone e shell

E la schermata non faceva entrare. Il difetto stava esattamente dove non
guardava nessuna prova: **nel punto in cui i pezzi si toccano**. Il demone del
greeter non riusciva ad ascoltare (indirizzo occupato dal Minerva della sessione
già aperta), la schermata si connetteva al demone dell'ALTRO utente, quello
rispondeva che greetd non c'era, e la schermata si metteva in anteprima. Si
vedeva benissimo e non entrava nessuno.

Questa prova percorre la catena vera — un client vero, il demone vero, il
socket di greetd — con un solo pezzo finto: greetd, che non si può usare
davvero senza mettere in gioco l'accesso alla macchina. Non serve un
compositore, non serve uno schermo, non serve cambiare console.

    scripts/prova-accesso.py

── Il client, che il 27 agosto 2026 è diventato dieci righe ───────────────

Qui c'erano sessanta righe di WebSocket scritto a mano — apertura, maschera,
fotogrammi — perché su questa macchina non c'è né `websockets` né `websocat`, e
una prova che si può lanciare solo dopo aver installato qualcosa è una prova
che non si lancia.

Da quando il demone ascolta su un socket Unix non serve più niente di tutto
quello: si apre il socket, si scrive una riga di JSON, se ne legge una. Il
confine fra un messaggio e il prossimo è l'a-capo, e si può usare perché
`json.dumps` non ne produce mai uno dentro un messaggio.
"""
import json
import os
import socket
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMONE = os.path.join(QUI, "minervad", "build", "minervad")
FINTO = os.path.join(QUI, "scripts", "greetd-finto.py")

# Un socket nostro, non quello di chi sta lavorando: il demone della sessione è
# vivo e non lo si disturba. Dentro `XDG_RUNTIME_DIR` (0700) e non in `/tmp`,
# come il socket di greetd qui sotto, e per la stessa ragione.
CANALE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "minerva-prova-accesso-ipc.sock")
# Nella cartella di esecuzione dell'utente (0700), non in `/tmp`: un percorso
# fisso dentro una cartella scrivibile da tutti si può occupare in anticipo.
SOCKET_GREETD = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "minerva-prova-accesso.sock")
# Il segreto del canale, in un file nostro e non in quello di chi lavora.
#
# Nella cartella di esecuzione dell'utente e NON in `/tmp`, dal 13 settembre
# 2026: il demone rifiuta di scrivere una parola d'ordine in una cartella che
# non sia sua e chiusa agli altri (audit SEC01 — `/tmp` è di root e la può
# scrivere chiunque). Questa prova metteva il segreto proprio lì, e il demone
# moriva prima di ascoltare: era la prova a chiedere la cosa sbagliata.
SEGRETO = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "minerva-prova-accesso.segreto")
PASSWORD = "apriti"                # quella che il greetd finto accetta

passate, fallite = 0, 0


def verifica(nome, condizione, dettaglio=""):
    global passate, fallite
    if condizione:
        passate += 1
        print(f"  ok   {nome}")
    else:
        fallite += 1
        print(f"  NO   {nome}" + (f"  → {dettaglio}" if dettaglio else ""))


# ── Un client minimo ───────────────────────────────────────────────────────

class Ws:
    """Il capo di qua del canale. Il nome è rimasto `Ws` da quando sotto c'era
    una WebSocket: cambiarlo vorrebbe dire toccare venti richiami in questo
    file per guadagnare due lettere."""

    def __init__(self, percorso):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.settimeout(10)
        self.s.connect(percorso)
        self._resto = b""

    def manda(self, oggetto):
        self.s.sendall((json.dumps(oggetto) + "\n").encode())

    def ricevi(self, scadenza=6):
        self.s.settimeout(scadenza)
        while True:
            if b"\n" in self._resto:
                riga, self._resto = self._resto.split(b"\n", 1)
                if riga.strip():
                    return json.loads(riga.decode())
                continue
            pezzo = self.s.recv(65536)
            if not pezzo:
                raise EOFError("il demone ha chiuso")
            self._resto += pezzo

    def forse(self, scadenza=3):
        """Un messaggio, o `None` se non arriva niente e se il demone ha
        chiuso. Serve alle prove della parola d'ordine, dove «non arriva
        niente» e «ti ho chiuso la porta in faccia» sono esiti giusti e non
        errori."""
        try:
            return self.ricevi(scadenza)
        except (EOFError, OSError):
            return None

    def aspetta(self, evento, scadenza=8):
        """Il primo messaggio con questo `event`. Il demone ne manda molti
        altri — stato, finestre, icone — e cercare «la prossima risposta»
        invece di «la risposta giusta» è il modo classico di scrivere una
        prova che passa per caso."""
        fine = time.time() + scadenza
        while time.time() < fine:
            m = self.ricevi(max(0.5, fine - time.time()))
            if m.get("event") == evento:
                return m.get("payload")
        raise TimeoutError(f"nessun «{evento}» entro {scadenza}s")


def main():
    global fallite
    print("── Prova dell'accesso, dalla shell a greetd ──────────────────\n")

    if not os.path.exists(DEMONE):
        sys.exit("manca minervad/build/minervad — lancia scripts/minerva-compila")

    for avanzo in (SOCKET_GREETD,):
        if os.path.exists(avanzo):
            os.unlink(avanzo)

    finto = subprocess.Popen([sys.executable, FINTO, SOCKET_GREETD],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True)
    time.sleep(1)

    ambiente = dict(os.environ)
    ambiente["GREETD_SOCK"] = SOCKET_GREETD
    ambiente["MINERVA_IPC_SOCKET"] = CANALE
    ambiente["MINERVA_CONFIG_DIR"] = "/tmp/minerva-prova-accesso-conf"
    os.makedirs(ambiente["MINERVA_CONFIG_DIR"], exist_ok=True)
    # La parola d'ordine del canale, in un file nostro: senza, questa prova
    # userebbe quello della sessione vera di chi sta lavorando — e lo
    # riscriverebbe, buttando fuori la sua barra.
    ambiente["MINERVA_TOKEN_FILE"] = SEGRETO
    ambiente["MINERVA_SESSIONE"] = "prova-accesso"
    ambiente.pop("XDG_RUNTIME_DIR", None)
    if os.path.exists(SEGRETO):
        os.unlink(SEGRETO)

    demone = subprocess.Popen([DEMONE], env=ambiente,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True)

    ws = None
    try:
        for _ in range(40):
            time.sleep(0.5)
            if demone.poll() is not None:
                print(demone.stdout.read())
                sys.exit("il demone è morto prima di ascoltare")
            try:
                ws = Ws(CANALE)
                break
            except OSError:
                continue
        if ws is None:
            sys.exit(f"il demone non ha mai risposto su {CANALE}")

        verifica("il demone del greeter ascolta su un socket suo", True)

        # ── La parola d'ordine ────────────────────────────────────────────
        #
        # Prima di tutto il resto, perché è il primo messaggio che il demone
        # accetta: senza, la conversazione non comincia nemmeno.
        verifica("il segreto del canale è stato scritto",
                 os.path.exists(SEGRETO))
        modo = oct(os.stat(SEGRETO).st_mode & 0o777)
        verifica("e non lo può leggere nessun altro", modo == "0o600",
                 f"permessi {modo}, attesi 0o600 — con 0o644 chiunque sul "
                 "computer entra nel canale della schermata di accesso")

        # Dentro ci sono DUE cose, `chiave=valore` una per riga: l'indirizzo
        # e la parola d'ordine. L'indirizzo perché due sessioni possono stare
        # accese insieme, ognuna col suo socket, e chi legge non lo può
        # indovinare.
        canale = {}
        for riga in open(SEGRETO).read().splitlines():
            if "=" in riga:
                k, _, v = riga.partition("=")
                canale[k.strip()] = v.strip()
        segreto = canale.get("segreto", "")
        verifica("nel file c'è anche il socket su cui il demone ascolta",
                 canale.get("socket") == CANALE,
                 f"indirizzo nel file: {canale.get('socket')}, atteso {CANALE}")

        # Chi non la sa viene buttato fuori, e senza che il canale gli
        # risponda niente di utile.
        estraneo = Ws(CANALE)
        estraneo.manda({"action": "greeter_info"})
        rifiuto = estraneo.forse(3)
        verifica("un estraneo senza parola d'ordine viene respinto",
                 rifiuto is not None and rifiuto.get("event") == "ciao"
                 and rifiuto.get("payload", {}).get("ok") is False,
                 f"risposta ricevuta: {rifiuto}")
        dopo = estraneo.forse(2)
        verifica("e non riceve nient'altro", dopo is None,
                 f"invece è arrivato {dopo}")
        try:
            estraneo.s.close()
        except OSError:
            pass

        # Una parola d'ordine sbagliata non vale più di nessuna.
        bugiardo = Ws(CANALE)
        bugiardo.manda({"action": "ciao", "segreto": "a" * len(segreto)})
        r = bugiardo.forse(3)
        verifica("una parola d'ordine sbagliata viene respinta",
                 r is not None and r.get("payload", {}).get("ok") is False,
                 f"risposta ricevuta: {r}")
        try:
            bugiardo.s.close()
        except OSError:
            pass

        ws.manda({"action": "ciao", "segreto": segreto})
        saluto = ws.aspetta("ciao")
        verifica("con la parola d'ordine giusta il demone saluta",
                 saluto.get("ok") is True)

        # ── Chi c'è, e greetd c'è? ────────────────────────────────────────
        ws.manda({"action": "greeter_info"})
        info = ws.aspetta("greeter_info")

        verifica("greetd risulta presente",
                 info.get("greetd") is True,
                 "è QUESTO che era falso quando la password non entrava: "
                 "con greetd=false la schermata va in anteprima e non entra")
        verifica("l'elenco degli utenti non è vuoto",
                 len(info.get("utenti") or []) > 0)
        verifica("l'elenco delle sessioni non è vuoto",
                 len(info.get("sessioni") or []) > 0)

        utente = (info.get("utenti") or [{}])[0].get("nome")

        # ── Password sbagliata ────────────────────────────────────────────
        ws.manda({"action": "greeter_create_session", "username": utente})
        m = ws.aspetta("greeter_message")
        verifica("a create_session arriva una domanda di PAM",
                 m.get("type") == "auth_message", str(m))
        verifica("la domanda è segreta (la password non si mostra)",
                 m.get("auth_message_type") == "secret", str(m))

        ws.manda({"action": "greeter_respond", "response": "sbagliata"})
        m = ws.aspetta("greeter_message")
        verifica("una password sbagliata torna auth_error",
                 m.get("type") == "error" and m.get("error_type") == "auth_error",
                 str(m))

        # ── E dopo l'errore la sessione va ANNULLATA, poi ricominciata ────
        #
        # È la trappola numero tre del protocollo, e per un giro l'abbiamo
        # capita al contrario. Qui c'era scritto che dopo un errore greetd «la
        # sessione in configurazione l'ha già chiusa»: **non è vero**. La
        # tiene. Ricominciare senza annullare riceve «a session is already
        # being configured», e da lì non entra più nessuno — misurato sulla
        # macchina vera il 10 agosto 2026.
        #
        # E l'annullamento ha una risposta sua, che va consumata: è un
        # `success`, la stessa parola con cui greetd dice «password
        # accettata». Prenderla per quella fa chiedere l'apertura della
        # sessione a chi non è autenticato — e la schermata si chiude
        # portandosi dietro il compositore.
        ws.manda({"action": "greeter_cancel"})
        m = ws.aspetta("greeter_message")
        verifica("l'annullamento ha una risposta sua, da consumare",
                 m.get("type") in ("success", "error"), str(m))

        ws.manda({"action": "greeter_create_session", "username": utente})
        m = ws.aspetta("greeter_message")
        verifica("dopo l'errore si può ricominciare",
                 m.get("type") == "auth_message", str(m))

        ws.manda({"action": "greeter_respond", "response": PASSWORD})
        m = ws.aspetta("greeter_message")
        verifica("la password giusta torna success",
                 m.get("type") == "success", str(m))

        # ── L'avvio della sessione ────────────────────────────────────────
        ws.manda({
            "action": "greeter_start",
            "cmd": ["sh", "-lc", "/usr/local/bin/minerva-session"],
            "env": ["XDG_SESSION_DESKTOP=minerva"],
        })
        m = ws.aspetta("greeter_message")
        verifica("start_session torna il SECONDO success",
                 m.get("type") == "success", str(m))

        # ── Un comando vuoto non deve arrivare a greetd ───────────────────
        ws.manda({"action": "greeter_start", "cmd": [], "env": []})
        m = ws.aspetta("greeter_message")
        verifica("un comando di sessione vuoto viene rifiutato dal demone",
                 m.get("type") == "error" and "omando" in (m.get("description") or ""),
                 str(m))

        time.sleep(0.5)
    finally:
        if ws:
            try:
                ws.s.close()
            except OSError:
                pass
        demone.terminate()
        try:
            demone.wait(timeout=5)
        except subprocess.TimeoutExpired:
            demone.kill()
        finto.terminate()
        try:
            uscita = finto.communicate(timeout=5)[0] or ""
        except subprocess.TimeoutExpired:
            finto.kill()
            uscita = ""
        if os.path.exists(SOCKET_GREETD):
            os.unlink(SOCKET_GREETD)

    # Il greetd finto racconta cosa gli è arrivato davvero: è l'unico modo di
    # sapere che il demone non ha inventato le risposte.
    verifica("greetd ha ricevuto un start_session con un comando vero",
             "AVVIO SESSIONE" in uscita,
             "il greetd finto non ha mai visto la richiesta di avvio")
    verifica("la password non compare mai nei registri del demone",
             PASSWORD not in (demone.stdout.read() or ""),
             "una password scritta in un registro è una password persa")

    print()
    if fallite:
        print(f"FALLITE {fallite} su {passate + fallite}")
        if uscita:
            print("\n── dialogo con greetd ──")
            print(uscita)
        sys.exit(1)
    print(f"TUTTE PASSATE ({passate})")


if __name__ == "__main__":
    main()
