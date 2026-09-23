#!/usr/bin/env python3
"""prova-effetto.py — Il «corpo unico»: una trasparenza sola su tutta la finestra.

    ./prova-effetto.py

── Cosa prova, e perché così ──────────────────────────────────────────────

Giacomo, 2 settembre 2026: «in blur o vetro dovrebbero far vedere un solo corpo
trasparente o blur come un unico corpo la barra e la finestra senza stacchi di
blur o trasparenza».

Prima del 3 settembre 2026 la trasparenza era in tre posti che non si
parlavano: la barra se la disegnava (0,90 a fuoco), le finestre NOSTRE se la
mettevano in QML (0,88), quelle degli altri programmi erano opache. Tre
dialetti sulla stessa scrivania.

In modalità vetro il compositore mette **la stessa alfa su tutto l'albero** della finestra
— la barra che disegna lui e la superficie del programma — e la barra si
disegna opaca per non moltiplicarla.

── Perché si misurano i PIXEL, che di solito non si fa ────────────────────

Perché «senza stacchi» è una cosa che si vede e basta: due rettangoli attaccati
con alfa 0,90 e 1,00 non danno nessun errore, nessun avviso, e da fuori il
compositore risponde la stessa cosa in tutti e due i casi.

Non si confrontano fotografie fra loro — quella è la prova che diventa rossa il
giorno che cambia lo sfondo. Si fa una cosa più stretta: si fotografa PRIMA e
DOPO aver acceso il vetro, **nella stessa sessione e con la stessa finestra**,
e si guarda di quanto è cambiato ciascuno dei due. È un rapporto fra due
misure prese a un secondo di distanza, e non dipende da nessun colore.

── L'invariante giusto, che alla prima stesura NON era questo ─────────────

La prima versione guardava se la finestra «si scuriva» accendendo il vetro.
Passava, e poi dentro `prove.sh` diceva che il corpo si era SCHIARITO
(rapporto 1,24). Non era un difetto del vetro e non era il momento dello
scatto: era l'invariante a essere sbagliato.

Un pixel composito vale `a·finestra + (1-a)·sfondo`. Abbassando `a` il
risultato si muove VERSO LO SFONDO — che si scurisca o si schiarisca dipende
da cosa c'è dietro. La prima volta lo sfondo era nero (la scrivania non aveva
ancora disegnato niente) e veniva più scuro; con la fotografia al suo posto
viene più chiaro. Due misure vere, e una regola falsa che le legava.

Quello che si vuole sapere non è la direzione: è che **barra e corpo
rispondano alla stessa manopola nello stesso modo**. Quindi si scatta a tre
opacità — 0,90, 0,70, 0,50 — e per ciascuna delle due parti si guarda

    r = (p(0,50) - p(0,90)) / (p(0,70) - p(0,90))

Siccome `p` è lineare in `a`, quel rapporto vale (0,50-0,90)/(0,70-0,90) = 2,0
**per tutte e due**, qualunque sia il colore della finestra e qualunque sia lo
sfondo dietro. Le due incognite si semplificano da sole.

E se la barra continuasse a mettersi la propria alfa invece di ricevere quella
della scena, non cambierebbe affatto fra i tre scatti: il suo `r` sarebbe
indefinito. Quello è lo stacco, ed è ciò che questa prova prende.

── ANNIDATO, SEMPRE ───────────────────────────────────────────────────────

E il canale si legge dal REGISTRO del compositore annidato, mai da
`MINERVA_CANALE` nell'ambiente: lì c'è quello EREDITATO dalla sessione vera, e
chiedendo là si comanda il compositore di chi sta lavorando. Successo il
3 settembre 2026 mentre si scriveva questa prova.
"""
import os
import re
import socket
import struct
import subprocess
import sys
import time
import zlib

QUI = os.path.dirname(os.path.abspath(__file__))
# La stessa cartella che `prova-annidata.sh` prepara: la configurazione di
# prova, copiata da quella vera. Chi apre una finestra dentro la sessione
# annidata deve puntare LÌ, o parla col demone di Giacomo.
CONF_PROVA = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                          "minerva-prova-conf")
sys.path.insert(0, QUI)
from importlib import import_module

chiudi = import_module("prova-annunci").chiudi

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


def leggi_png(percorso):
    """Un PNG senza dipendenze: il compositore ne fa uno, e basta leggerlo."""
    d = open(percorso, "rb").read()
    i, larg, alt, idat, bit, col = 8, 0, 0, b"", 8, 6
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        tipo, dati = d[i + 4:i + 8], d[i + 8:i + 8 + ln]
        if tipo == b"IHDR":
            larg, alt, bit, col = struct.unpack(">IIBB", dati[:10])
        elif tipo == b"IDAT":
            idat += dati
        i += 12 + ln
    raw = zlib.decompress(idat)
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[col] * (bit // 8)
    stride = larg * bpp
    fuori, prec, o = bytearray(), bytearray(stride), 0
    for _ in range(alt):
        f = raw[o]
        o += 1
        riga = bytearray(raw[o:o + stride])
        o += stride
        for x in range(stride):
            a = riga[x - bpp] if x >= bpp else 0
            b = prec[x]
            c = prec[x - bpp] if x >= bpp else 0
            if f == 1:
                riga[x] = (riga[x] + a) & 255
            elif f == 2:
                riga[x] = (riga[x] + b) & 255
            elif f == 3:
                riga[x] = (riga[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                riga[x] = (riga[x] + pr) & 255
        fuori += riga
        prec = riga
    return larg, alt, bpp, bytes(fuori)


def punto(img, x, y):
    larg, _alt, bpp, dati = img
    o = y * larg * bpp + x * bpp
    return dati[o], dati[o + 1], dati[o + 2]


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("FERMO: non siamo in una sessione Wayland.", file=sys.stderr)
        return 2
    if not subprocess.run(["sh", "-c", "command -v grim"],
                          capture_output=True).returncode == 0:
        print("saltata: manca grim")
        return 0

    avvio = subprocess.Popen([os.path.join(QUI, "prova-annidata.sh"), "alacritty"],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, bufsize=1)
    dentro, canale = "", ""
    inizio = time.time()
    while time.time() - inizio < 60:
        r = avvio.stdout.readline()
        if not r:
            break
        m = re.search(r"compositore su (\S+)", r)
        if m:
            dentro = m.group(1)
        m = re.search(r"canale su (\S+)", r)
        if m:
            canale = m.group(1)
        if "shell dentro" in r:
            break

    print("── Il corpo unico ──")
    if not dentro:
        verifica("la sessione annidata parte", False)
        chiudi(avvio)
        return 1
    if not canale:
        canale = "%s/minerva-wayland-%s.sock" % (
            os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), dentro)
    # La riga che impedisce di comandare la sessione VERA.
    if dentro not in canale:
        verifica("il canale è quello annidato", False, canale)
        chiudi(avvio)
        return 1

    amb = dict(os.environ)
    amb["WAYLAND_DISPLAY"] = dentro
    time.sleep(24)

    def di(verbo):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(6)
        try:
            s.connect(canale)
            s.sendall((verbo + "\n").encode())
            return s.recv(65536).decode("utf-8", "replace").strip()
        except OSError:
            return "(niente)"
        finally:
            s.close()

    fuori = os.environ.get("TMPDIR", "/tmp")
    prima_f = os.path.join(fuori, "minerva-effetto-90.png")
    mezzo_f = os.path.join(fuori, "minerva-effetto-70.png")
    dopo_f = os.path.join(fuori, "minerva-effetto-50.png")
    try:
        # ── Non si prova più «nasce senza effetto», e va detto perché ────
        #
        # Perché questa prova non lancia il compositore nudo: lancia anche la
        # SHELL, che al collegamento applica le impostazioni di chi la usa. Da
        # quando Giacomo tiene il blur acceso, alla nascita l'effetto è il suo
        # — e la prova diventava rossa per una preferenza, cioè per il motivo
        # sbagliato. Si parte invece da un punto DICHIARATO.
        verifica("si parte da un punto noto",
                 di("effetto nessuno 0.50") == "ok nessuno 0.50",
                 di("stato"))
        # ── Il blur non è più un rifiuto ─────────────────────────────────
        #
        # Per settimane la riga qui sopra diceva «no il blur non c'è ancora», e
        # quel rifiuto valeva quanto una funzione: un verbo che si può scrivere
        # e non fa niente è il difetto che questo progetto si è messo per
        # iscritto di non commettere. Dal 9 settembre 2026 il blur c'è (SceneFX),
        # e la prova deve cambiare verso insieme al codice — o resta a
        # sorvegliare un mondo che non esiste più.
        verifica("«blur» si accende e lo dice",
                 di("effetto blur 0.73") == "ok blur 0.73",
                 di("effetto blur 0.73"))
        verifica("e «stato» lo ripete",
                 '"effetto":"blur"' in di("stato"), di("stato"))
        verifica("un'opacità impossibile è rifiutata",
                 di("effetto vetro 0.10").startswith("no l'opacità"),
                 di("effetto vetro 0.10"))

        # ── Dove sta la finestra, chiesto invece che indovinato ──────────
        #
        # La prima versione campionava a occhio — «venti pixel dall'alto, metà
        # schermo» — e dentro `prove.sh` è diventata rossa dicendo che il corpo
        # si era SCHIARITO (rapporto 1,23). Non era il vetro: erano due punti
        # che a macchina carica cadevano su cose diverse.
        #
        # Il compositore sa dove sta ogni finestra e con che misura. Chiederglielo
        # costa una riga e toglie di mezzo tutta la categoria.
        import json
        try:
            elenco = json.loads(di("finestre")[3:])
        except (ValueError, IndexError):
            elenco = []
        vere = [w for w in elenco if w.get("larghezza", 0) > 200
                and w.get("altezza", 0) > 200 and w.get("decorata")]
        if not vere:
            verifica("c'è una finestra decorata da guardare", False, di("finestre")[:200])
            return 1
        w = vere[0]
        alta_barra = 34   # `windows.titleHeight` di fabbrica
        px_barra = (w["x"] + w["larghezza"] // 2, w["y"] + alta_barra // 2)
        px_corpo = (w["x"] + w["larghezza"] // 2,
                    w["y"] + alta_barra + (w["altezza"] - alta_barra) // 2)

        # ── E si aspetta che lo schermo stia FERMO ───────────────────────
        #
        # Un terminale che sta ancora disegnando il prompt, un'animazione che
        # finisce, lo sfondo che sfuma: qualunque di queste cose cambia i pixel
        # fra le due fotografie, e il rapporto misura quella invece del vetro.
        # Si scatta finché due scatti di fila non sono identici.
        def fermo(dest, quanto=12.0):
            prec = None
            fine = time.time() + quanto
            while time.time() < fine:
                subprocess.run(["grim", dest], capture_output=True, env=amb)
                try:
                    d = open(dest, "rb").read()
                except OSError:
                    d = b""
                if prec is not None and d == prec and d:
                    return True
                prec = d
                time.sleep(1.0)
            return False

        verifica("il vetro si accende", di("effetto vetro 0.90") == "ok vetro 0.90")
        verifica("lo schermo si ferma prima di fotografarlo", fermo(prima_f))
        verifica("e lo si può interrogare da fuori",
                 '"effetto":"vetro"' in di("stato"), di("stato"))
        di("effetto vetro 0.70")
        fermo(mezzo_f)
        di("effetto vetro 0.50")
        fermo(dopo_f)
        if not (os.path.exists(prima_f) and os.path.exists(dopo_f)):
            verifica("le due fotografie ci sono", False)
        else:
            a, mez, b = leggi_png(prima_f), leggi_png(mezzo_f), leggi_png(dopo_f)
            larg, alt = a[0], a[1]

            # Non un punto solo: una crocetta di cinque, e si prende la
            # mediana. Un pixel può cadere su un carattere, su un cursore che
            # lampeggia o sul bordo di qualcosa; cinque no.
            def rapporto(cx, cy):
                # Non un punto solo: una crocetta di cinque, e si prende la
                # mediana. Un pixel può cadere su un carattere, su un cursore
                # che lampeggia o sul bordo di qualcosa; cinque no.
                valori = []
                for dx, dy in ((0, 0), (-30, 0), (30, 0), (0, -6), (0, 6)):
                    x, y = cx + dx, cy + dy
                    if not (0 <= x < larg and 0 <= y < alt):
                        continue
                    p90, p70, p50 = punto(a, x, y), punto(mez, x, y), punto(b, x, y)
                    for i in range(3):
                        denom = p70[i] - p90[i]
                        # Un canale che non si muove non dice niente: succede
                        # dove finestra e sfondo hanno lo stesso valore in quel
                        # canale, e lì il vetro è invisibile per costruzione.
                        if abs(denom) >= 3:
                            valori.append((p50[i] - p90[i]) / denom)
                if not valori:
                    return None
                valori.sort()
                return valori[len(valori) // 2]

            r_barra = rapporto(*px_barra)
            r_corpo = rapporto(*px_corpo)
            if os.environ.get("MINERVA_DIAGNOSI"):
                print("    finestra:", w)
                print("    immagine:", larg, "x", alt)
                print("    px_barra:", px_barra, punto(a,*px_barra),
                      punto(mez,*px_barra), punto(b,*px_barra))
                print("    px_corpo:", px_corpo, punto(a,*px_corpo),
                      punto(mez,*px_corpo), punto(b,*px_corpo))

            verifica("il corpo della finestra segue l'opacità",
                     r_corpo is not None and 1.7 <= r_corpo <= 2.3,
                     "r = %s, atteso 2,0" % r_corpo)
            # Ed è QUESTA la riga che prova il corpo unico: se la barra si
            # mettesse ancora la propria alfa, fra i tre scatti non cambierebbe
            # affatto e non ci sarebbe nessun rapporto da calcolare.
            verifica("e la barra la segue allo STESSO modo: un corpo solo",
                     r_barra is not None and 1.7 <= r_barra <= 2.3,
                     "r = %s, atteso 2,0 — se è None la barra non si muove "
                     "affatto, ed è lo stacco" % r_barra)
            verifica("il vetro si spegne", di("effetto nessuno") == "ok nessuno 0.50")

            # ── E il BLUR: non basta che risponda «ok» ───────────────────
            #
            # È la lezione della luce notturna, presa lo stesso giorno: il
            # verbo rispondeva «ok» da due settimane e lo schermo non cambiava
            # di un bit, perché nessuna prova guardava i pixel. Qui si guarda
            # il CORPO della finestra fra «vetro» e «blur». Dal 20 settembre
            # il blur non forza più l'opacità dei client: questo confronto
            # verifica il cambio di modalità, non dimostra la sfocatura.
            # Il filtro è verificato nella prova GPU; prova-blur-contenuto.py
            # verifica che i client opachi restino leggibili.
            vetro_f = os.path.join(fuori, "minerva-effetto-vetro.png")
            blur_f = os.path.join(fuori, "minerva-effetto-blur.png")
            di("effetto vetro 0.73")
            fermo(vetro_f)
            di("effetto blur 0.73")
            fermo(blur_f)
            if os.path.exists(vetro_f) and os.path.exists(blur_f):
                v, bl = leggi_png(vetro_f), leggi_png(blur_f)
                # Il corpo deve cambiare quando si rimuove la trasparenza
                # forzata dal vetro e si torna all'alfa nativa del client.
                x0 = w["x"] + 20
                y0 = w["y"] + alta_barra + 20
                x1 = w["x"] + w["larghezza"] - 20
                y1 = w["y"] + w["altezza"] - 20
                punti = diversi = 0
                yy = y0
                while yy < y1:
                    xx = x0
                    while xx < x1:
                        if 0 <= xx < v[0] and 0 <= yy < v[1]:
                            pv, pb = punto(v, xx, yy), punto(bl, xx, yy)
                            punti += 1
                            if sum(abs(pv[i] - pb[i]) for i in range(3)) > 6:
                                diversi += 1
                        xx += 7
                    yy += 7
                quota = (100.0 * diversi / punti) if punti else 0.0
                verifica("il passaggio da vetro a blur cambia il contenuto",
                         punti > 200 and quota >= 15.0,
                         "%d punti guardati, %.1f%% diversi fra vetro e blur "
                         "— atteso il ripristino dell'alfa del client" % (punti, quota))
            # ── E il vetro deve SOPRAVVIVERE a un cambio di misura ───────
            #
            # `aspetto` ridà la misura a ogni finestra, e la strada del
            # ridimensionamento aveva un `return` per le finestre che si
            # disegnano la barra da sole — Chrome, Firefox, e TUTTE quelle di
            # Minerva. Da quel `return` in poi nessuno rimetteva la
            # trasparenza sui buffer nuovi: la finestra tornava opaca e ci
            # restava.
            #
            # Si vedeva così: nelle Impostazioni si muove «Quanto si vede
            # attraverso», il compositore riceve il valore giusto — `stato` lo
            # conferma — e le finestre non cambiano. Il pannello manda
            # `aspetto` insieme a `effetto`, ed è quello che lo cancellava.
            #
            # Questa prova è il difetto in forma diretta: si accende il vetro,
            # si manda `aspetto`, e il vetro deve esserci ancora.
            # E si guarda una finestra SENZA la nostra barra, perché il
            # difetto era proprio lì: le decorate passano da `barra_aggiorna`,
            # che la trasparenza la rimetteva già. Provato: con la sola
            # alacritty, che è decorata, questa prova resta VERDE anche
            # togliendo la correzione — cioè non prova niente.
            #
            # Quindi si apre la Calcolatrice, che si disegna la barra da sé
            # come tutte le finestre di Minerva, come Chrome e come Firefox.
            # È l'unico caso in cui il difetto esisteva, ed è la maggioranza
            # delle finestre di questa scrivania.
            #
            # Vista rossa togliendo la correzione: **100,0 % dei punti
            # cambiati** su 2760. Con la sola alacritty restava verde.
            vetro_a = os.path.join(fuori, "minerva-effetto-prima-aspetto.png")
            vetro_b = os.path.join(fuori, "minerva-effetto-dopo-aspetto.png")
            amb_csd = dict(amb)
            amb_csd["MINERVA_PROVA"] = "1"
            amb_csd["MINERVA_CONFIG_DIR"] = CONF_PROVA
            amb_csd["MINERVA_IPC_SOCKET"] = os.path.join(CONF_PROVA, "canale.sock")
            amb_csd["MINERVA_TOKEN_FILE"] = os.path.join(CONF_PROVA, "canale")
            amb_csd["MINERVA_SESSIONE"] = "prova"
            amb_csd["MINERVA_CANALE"] = canale
            calc = subprocess.Popen(
                [os.path.join(os.path.dirname(QUI), "scripts",
                              "minerva-calcolatrice")],
                env=amb_csd, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL)
            time.sleep(9)
            senza = None
            try:
                for x in json.loads(di("finestre")[3:]):
                    if not x.get("decorata") and x.get("larghezza", 0) > 100:
                        senza = x
            except (ValueError, IndexError):
                pass
            if senza is None:
                verifica("c'è una finestra senza la nostra barra da guardare",
                         False, di("finestre")[:200])
                calc.terminate()
                raise SystemExit(1)
            w = senza
            di("effetto vetro 0.60")
            fermo(vetro_a)
            di("aspetto %d destra 22D3EE -" % alta_barra)
            fermo(vetro_b)
            if os.path.exists(vetro_a) and os.path.exists(vetro_b):
                pa, pb = leggi_png(vetro_a), leggi_png(vetro_b)
                uguali = diversi = 0
                yy = w["y"] + 20
                while yy < w["y"] + w["altezza"] - 20:
                    xx = w["x"] + 20
                    while xx < w["x"] + w["larghezza"] - 20:
                        if 0 <= xx < pa[0] and 0 <= yy < pa[1]:
                            va, vb = punto(pa, xx, yy), punto(pb, xx, yy)
                            uguali += 1
                            if sum(abs(va[i] - vb[i]) for i in range(3)) > 6:
                                diversi += 1
                        xx += 7
                    yy += 7
                quota = (100.0 * diversi / uguali) if uguali else 100.0
                calc.terminate()
                verifica("e «aspetto» non porta via il vetro",
                         uguali > 200 and quota < 2.0,
                         "%d punti, %.1f%% cambiati: dando la misura alla "
                         "finestra la trasparenza è sparita" % (uguali, quota))

            di("effetto nessuno 0.50")
    finally:
        chiudi(avvio)

    print("\n  %d passate, %d fallite" % (passate, fallite))
    return 1 if fallite else 0


sys.exit(main())
