#!/usr/bin/env python3
"""prova-specchio.py — Trasmettere lo SCHERMO: la conduttura, e cosa lascia.

    ./prova-specchio.py

── Cosa prova, e perché serve una prova viva ──────────────────────────────

«Trasmetti lo schermo» è una catena di quattro pezzi che si rompono in
silenzio:

    minerva-cattura → tubo → ffmpeg → segmenti HLS

Nessuno di loro dà errore quando sbaglia. Una geometria sbagliata dà un video
storto a diagonale; un formato di pixel sbagliato dà le facce blu; una GPU che
non risponde dà zero segmenti e nessuna riga rossa. Sono tutti difetti che si
vedono solo guardando la televisione — cioè tardi.

── Ma le due prove che contano davvero sono le ULTIME ─────────────────────

I segmenti che questa conduttura scrive **sono fotogrammi del tuo schermo**:
password, posta, conti. Due cose non devono succedere mai, e nessun'altra
prova le prende:

  1. **Niente orfani.** Il demone ferma la trasmissione uccidendo lo script.
     Se `minerva-cattura` e `ffmpeg` sopravvivessero, continuerebbero a
     leggere lo schermo per sempre, con la spia nel pannello che dice
     «spento». È la famiglia delle sessioni annidate rimaste in piedi il 30
     agosto 2026: 174 MB che nessuno vedeva.

  2. **Niente resti.** Dopo lo stop, in `$XDG_RUNTIME_DIR` non deve restare
     nemmeno un segmento. La prima stesura, il 3 settembre 2026, ne lasciava
     due: il `trap` cancellava i file mentre ffmpeg li stava ancora
     scrivendo, perché `kill` chiede e non impone. Serviva un `wait`.

E una terza, che è una difesa e non un difetto osservato: la cartella dei
segmenti deve stare dentro `$XDG_RUNTIME_DIR` — in RAM, 0700, via al
riavvio — e ogni altro percorso va rifiutato. È l'unica riga che impedisce a
un errore di battitura di lasciare il tuo schermo su un disco.

── Non serve una sessione annidata ────────────────────────────────────────

Al contrario di quasi tutte le prove del compositore. La cattura è in sola
lettura — è quello che fa `grim` a ogni schermata — e non tocca né le
finestre né la configurazione. Provarla nella sessione vera è più onesto:
è il compositore vero a rispondere.
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import time

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
SPECCHIO = os.path.join(RADICE, "scripts", "minerva-specchio")
CATTURA = os.environ.get("MINERVA_CATTURA") or os.path.join(
    QUI, "build-native", "minerva-cattura")

passate = 0
fallite = 0


def verifica(cosa, condizione, dettaglio=""):
    global passate, fallite
    if condizione:
        passate += 1
        print("  ok   %s" % cosa)
    else:
        fallite += 1
        print("  NO   %s%s" % (cosa, (" — " + dettaglio) if dettaglio else ""))


def vivi():
    """I processi della conduttura ancora in piedi.

    NON `pgrep -f`: quella trova sé stessa e trova questa prova, che ha i
    nomi nella riga di comando. È la trappola già pagata (vedi «Trappole
    delle prove»). Si guarda il nome dell'eseguibile, che è un'altra cosa.
    """
    fuori = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/comm" % pid) as f:
                nome = f.read().strip()
        except OSError:
            continue
        if nome in ("minerva-cattura", "ffmpeg"):
            fuori.append((pid, nome))
    return fuori


def main():
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("saltata: non siamo in una sessione Wayland")
        return 0
    if not os.path.exists(CATTURA):
        print("saltata: manca minerva-cattura (compila il compositore)")
        return 0
    if not shutil.which("ffmpeg"):
        print("saltata: manca ffmpeg")
        return 0

    ambiente = dict(os.environ, MINERVA_CATTURA=CATTURA)
    corsa = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()

    # ── 1. La forma dello schermo, chiesta e non indovinata ──────────────
    testa = subprocess.run([CATTURA, "--dimmi"], capture_output=True,
                           text=True, timeout=15)
    m = re.match(r"MINERVA_CATTURA (\d+) (\d+) (\w+)", testa.stdout.strip())
    verifica("il compositore dice la forma dello schermo",
             m is not None, testa.stdout.strip() or testa.stderr.strip())
    if not m:
        print("\n  %d passate, %d fallite" % (passate, fallite))
        return 1
    larg, alt, formato = int(m.group(1)), int(m.group(2)), m.group(3)
    verifica("ed è una geometria plausibile",
             320 <= larg <= 16384 and 240 <= alt <= 16384,
             "%dx%d" % (larg, alt))
    # Sbagliare qui non dà errore: dà le facce blu. `XRGB8888` di Wayland è
    # `bgr0` per ffmpeg, e `XBGR8888` è `rgb0` — al contrario di come si
    # leggono.
    verifica("e un formato che ffmpeg conosce",
             formato in ("bgr0", "rgb0", "bgra", "rgba"), formato)

    # ── 2. Il rifiuto: fuori da XDG_RUNTIME_DIR non si scrive ────────────
    fuori = subprocess.run([SPECCHIO, "avvia", "/tmp/minerva-specchio-vietata"],
                           capture_output=True, text=True, env=ambiente,
                           timeout=20)
    verifica("rifiuta una cartella fuori da XDG_RUNTIME_DIR",
             fuori.returncode != 0 and "deve stare dentro" in fuori.stderr,
             fuori.stderr.strip()[:120])
    verifica("e non la crea nemmeno",
             not os.path.exists("/tmp/minerva-specchio-vietata"))

    # ── 3. La conduttura vera ────────────────────────────────────────────
    dove = os.path.join(corsa, "minerva-specchio-prova")
    if os.path.isdir(dove):
        shutil.rmtree(dove, ignore_errors=True)
    prima = set(p for p, _ in vivi())

    p = subprocess.Popen([SPECCHIO, "avvia", dove, "--fps", "15"],
                         env=ambiente, stdout=subprocess.DEVNULL,
                         stderr=subprocess.PIPE, text=True)
    lista = os.path.join(dove, "schermo.m3u8")
    scaduto = time.time() + 25
    pronta = False
    while time.time() < scaduto:
        if p.poll() is not None:
            break
        if os.path.exists(lista):
            with open(lista) as f:
                if f.read().count("#EXTINF") >= 2:
                    pronta = True
                    break
        time.sleep(0.2)

    lamento = ""
    if not pronta and p.poll() is not None:
        lamento = (p.stderr.read() or "").strip()[:200]
    verifica("in venticinque secondi la lista ha almeno due segmenti",
             pronta, lamento or "niente lista")

    if pronta:
        segmenti = sorted(f for f in os.listdir(dove) if f.endswith(".ts"))
        verifica("e i segmenti esistono davvero", len(segmenti) >= 2,
                 str(segmenti))
        # Un segmento che non si decodifica è il difetto che si vede solo
        # sulla TV: la lista c'è, la trasmissione «riesce», lo schermo è nero.
        sonda = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries",
             "stream=codec_name,width,height", "-of", "default=nw=1",
             os.path.join(dove, segmenti[0])],
            capture_output=True, text=True, timeout=20)
        testo = sonda.stdout
        verifica("il segmento è H.264 vero", "codec_name=h264" in testo,
                 (sonda.stderr or testo).strip()[:120])
        verifica("della dimensione annunciata",
                 ("width=%d" % larg) in testo and ("height=%d" % alt) in testo,
                 testo.replace("\n", " ").strip()[:120])

    # ── 4. E adesso la parte che conta: si spegne e non lascia niente ────
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait(timeout=5)
    time.sleep(1.0)

    restati = [(q, n) for q, n in vivi() if q not in prima]
    verifica("dopo lo stop non resta nessun processo a leggere lo schermo",
             not restati, str(restati))
    verifica("e non resta nessun fotogramma dello schermo su disco",
             not os.path.exists(dove),
             str(os.listdir(dove)) if os.path.isdir(dove) else "")

    if os.path.isdir(dove):
        shutil.rmtree(dove, ignore_errors=True)

    print("\n  %d passate, %d fallite" % (passate, fallite))
    return 1 if fallite else 0


sys.exit(main())
