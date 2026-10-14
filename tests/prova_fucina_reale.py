"""Osserva il daemon reale, oppure esegue una build con limite di tempo.

La compilazione parte solo con --compila. Non invia azioni di installazione,
rimozione o riavvio; --limite ferma soltanto la build avviata da questa prova.
"""

import argparse
import json
from pathlib import Path
import socket
import time


class Canale:
    def __init__(self, file):
        dati = dict(line.split("=", 1) for line in Path(file).read_text().splitlines() if "=" in line)
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.connect(dati["socket"])
        self.buffer = b""
        self.invia(dict(action="ciao", segreto=dati["segreto"]))

    def invia(self, dati):
        self.socket.sendall((json.dumps(dati) + "\n").encode())

    def aspetta(self, evento, timeout=30):
        scadenza = time.monotonic() + timeout
        while time.monotonic() < scadenza:
            if b"\n" not in self.buffer:
                self.socket.settimeout(max(0.01, scadenza - time.monotonic()))
                pezzo = self.socket.recv(65536)
                if not pezzo:
                    raise RuntimeError("Il daemon ha chiuso il canale")
                self.buffer += pezzo
                continue
            riga, self.buffer = self.buffer.split(b"\n", 1)
            dati = json.loads(riga)
            if dati.get("event") == evento:
                return dati["payload"]
            if dati.get("event") == "action_failed":
                raise RuntimeError(str(dati.get("payload")))
        raise TimeoutError(f"Risposta {evento} non arrivata")

    def stato(self):
        self.invia(dict(action="fucina_stato"))
        return self.aspetta("fucina_stato")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--canale", required=True, help="file canale della sessione, mai il suo contenuto")
    parser.add_argument("--compila", action="store_true")
    parser.add_argument("--versione")
    parser.add_argument("--nome", default="registro")
    parser.add_argument("--sorgente", choices=["vanilla", "cachyos"], default="cachyos")
    parser.add_argument("--limite", type=int, default=180)
    args = parser.parse_args()
    if args.compila and not args.versione:
        parser.error("--compila richiede --versione")
    if args.limite < 1:
        parser.error("--limite deve essere positivo")
    canale = Canale(args.canale)
    stato = canale.stato()
    if not args.compila:
        print(json.dumps(stato, ensure_ascii=False))
        return
    if stato.get("inCorso"):
        raise RuntimeError("Una compilazione è già in corso; la prova non la ferma né la sostituisce")
    canale.invia(dict(action="fucina_avvia", scelte=dict(versione=args.versione, nome=args.nome,
        sorgente=args.sorgente, base="in-uso", compilatore="gcc", nativo=True,
        scorte=["chiavette", "controller", "filesystem"], preset=[])))
    avvio = canale.aspetta("fucina_avviata", timeout=60)
    if avvio.get("ok") is not True:
        raise RuntimeError(str(avvio))
    rilascio = avvio["rilascio"]
    inizio = time.monotonic()
    fermata = False
    while True:
        stato = canale.stato()
        if stato.get("rilascio") != rilascio:
            raise RuntimeError("Il daemon sta osservando un altro rilascio: la prova non lo modifica")
        if avvio.get("ricetta") and stato.get("ricetta", {}).get("rilascio") != rilascio:
            raise AssertionError("La ricetta salvata non corrisponde al rilascio in compilazione")
        avanzamento = stato.get("avanzamento") or {}
        log = Path(stato["log"]) if stato.get("log") else None
        print(json.dumps(dict(secondi=stato.get("secondi"), passo=stato.get("passo"),
            inCorso=stato.get("inCorso"), fatti=avanzamento.get("fatti"),
            logBytes=log.stat().st_size if log and log.exists() else 0)), flush=True)
        if not stato.get("inCorso"):
            esito = stato.get("esito") or {}
            if not log or not log.exists():
                raise AssertionError("Manca il log della build reale")
            contenuto = log.read_text(errors="replace")
            raccolta = "] ricetta " in contenuto and "] comando " in contenuto and "] esito " in contenuto
            riepilogo = {k: v for k, v in esito.items() if k != "ricetta"}
            print(json.dumps(dict(esito=riepilogo, buildCompleta=esito.get("ok") is True,
                arrestoVoluto=fermata, raccoltaLogVerificata=raccolta,
                ricettaSalvata=bool(esito.get("ricetta")),
                righeLog=len(contenuto.splitlines())), ensure_ascii=False), flush=True)
            if not raccolta or not (esito.get("ok") is True or (fermata and esito.get("annullato") is True)):
                raise AssertionError("La prova reale non è riuscita; consultare il log")
            break
        if not fermata and time.monotonic() - inizio >= args.limite:
            canale.invia(dict(action="fucina_ferma"))
            fermata = True
        if fermata and time.monotonic() - inizio > args.limite + 30:
            raise TimeoutError("La build non si è fermata entro 30 secondi dalla richiesta")
        time.sleep(2 if fermata else 10)
    canale.socket.close()


if __name__ == "__main__":
    main()
