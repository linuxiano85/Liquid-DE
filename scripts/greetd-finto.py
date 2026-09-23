#!/usr/bin/env python3
"""Un greetd finto, per provare la schermata di accesso senza PAM.

Parla il protocollo vero — <lunghezza a 32 bit in ordine nativo><JSON UTF-8> —
e scrive su stdout ogni messaggio che riceve e ogni risposta che manda. È
quello che serve per rispondere alla domanda che le prove unitarie non possono
toccare: la schermata, il demone e il socket funzionano DAVVERO insieme?

La password buona è «apriti». Qualunque altra cosa torna auth_error, come fa
greetd vero.

── Una bugia che è costata cara ───────────────────────────────────────────

Fino al 10 agosto 2026 questo finto, dopo una password sbagliata, DIMENTICAVA
la sessione in configurazione. Il greetd vero non lo fa: la sessione resta lì,
e ogni `create_session` successivo riceve «a session is already being
configured». Risultato: tredici prove verdi e una schermata di accesso che, in
carne e ossa, non faceva più entrare dopo il primo errore.

Adesso si comporta come quello vero — la sessione si chiude solo con un
`cancel_session` esplicito. Un finto più gentile dell'originale non prova
niente: prova solo che saremmo bravi in un mondo più facile.
"""
import json
import os
import socket
import struct
import sys
import threading

# Di serie nella cartella di esecuzione dell'utente, che logind crea 0700:
# quello che c'è dentro lo vede solo lui. In `/tmp` — dov'era — il socket stava
# in una cartella scrivibile da chiunque, e per giunta a 0777.
_CASA = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
PERCORSO = sys.argv[1] if len(sys.argv) > 1 else _CASA + "/greetd-finto.sock"
GIUSTA = "apriti"

if os.path.exists(PERCORSO):
    os.unlink(PERCORSO)

srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(PERCORSO)
# 0600 e non 0777: a questo socket parla il demone, che gira come noi. Un
# permesso largo qui dentro vuol dire che ogni altro utente del computer può
# rispondere al posto di greetd durante le prove — e le prove esistono proprio
# per dimostrare che quel canale è chiuso.
os.chmod(PERCORSO, 0o600)
srv.listen(4)
print(f"[FINTO] in ascolto su {PERCORSO}", flush=True)


def leggi(conn, quanti):
    dati = b""
    while len(dati) < quanti:
        pezzo = conn.recv(quanti - len(dati))
        if not pezzo:
            return None
        dati += pezzo
    return dati


def manda(conn, msg):
    corpo = json.dumps(msg).encode()
    conn.sendall(struct.pack("=I", len(corpo)) + corpo)
    print(f"[FINTO] → {msg}", flush=True)


def servi(conn):
    # Lo stato che tiene greetd: una sola sessione in configurazione.
    sessione = None
    autenticato = False
    # E il suo processo aiutante, quello che parla con PAM: muore alla prima
    # password sbagliata. Vedi il commento dentro `post_auth_message_response`.
    aiutante_vivo = True
    while True:
        testa = leggi(conn, 4)
        if testa is None:
            print("[FINTO] connessione chiusa", flush=True)
            return
        (quanti,) = struct.unpack("=I", testa)
        corpo = leggi(conn, quanti)
        msg = json.loads(corpo.decode())
        print(f"[FINTO] ← {msg}", flush=True)

        tipo = msg.get("type")
        if tipo == "create_session":
            if sessione is not None:
                manda(conn, {"type": "error", "error_type": "error",
                             "description": "a session is already being configured"})
                continue
            sessione = msg.get("username")
            autenticato = False
            manda(conn, {
                "type": "auth_message",
                "auth_message_type": "secret",
                "auth_message": "Password: ",
            })
        elif tipo == "post_auth_message_response":
            if sessione is not None and not aiutante_vivo:
                manda(conn, {"type": "error", "error_type": "error",
                             "description": "unable to send message: "
                                            "Connection refused (os error 111)"})
            elif sessione is None:
                manda(conn, {"type": "error", "error_type": "error",
                             "description": "nessuna sessione in configurazione"})
            elif msg.get("response") == GIUSTA:
                autenticato = True
                manda(conn, {"type": "success"})
            else:
                # La sessione RESTA in configurazione: è ciò che fa greetd
                # vero. Per riprovare serve un cancel_session.
                #
                # Ma il suo AIUTANTE muore: greetd fa la conversazione con PAM
                # dentro un processo figlio, e quando `pam_authenticate`
                # fallisce quel figlio esce. Da lì in poi ogni messaggio su
                # quella sessione — `cancel_session` compreso — torna
                # «unable to send message: Connection refused», perché greetd
                # sta scrivendo a un morto.
                #
                # Visto sulla macchina vera il 16 agosto 2026, nel registro del
                # greeter:
                #     greetd risponde errore (auth_error): pam_authenticate
                #     greetd risponde errore (error): unable to send message
                # Un finto che risponde `success` all'annullamento non prova
                # niente: prova solo che saremmo bravi in un mondo più facile.
                autenticato = False
                aiutante_vivo = False
                manda(conn, {"type": "error", "error_type": "auth_error",
                             "description": "pam_authenticate: AUTH_ERR"})
        elif tipo == "start_session":
            if not autenticato:
                manda(conn, {"type": "error", "error_type": "error",
                             "description": "non autenticato"})
            else:
                print(f"[FINTO] AVVIO SESSIONE cmd={msg.get('cmd')} "
                      f"env={msg.get('env')}", flush=True)
                manda(conn, {"type": "success"})
        elif tipo == "cancel_session":
            morto = not aiutante_vivo
            sessione = None
            autenticato = False
            aiutante_vivo = True
            if morto:
                # La sessione è comunque finita — ma la risposta è un errore,
                # non un «sì». Chi si aspetta un `success` per andare avanti
                # resta fermo per sempre.
                manda(conn, {"type": "error", "error_type": "error",
                             "description": "unable to send message: "
                                            "Connection refused (os error 111)"})
            else:
                manda(conn, {"type": "success"})
        else:
            manda(conn, {"type": "error", "error_type": "error",
                         "description": f"non capisco {tipo}"})


while True:
    conn, _ = srv.accept()
    threading.Thread(target=servi, args=(conn,), daemon=True).start()
