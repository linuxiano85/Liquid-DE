#!/usr/bin/env python3
"""make-wallpapers.py — Disegna gli sfondi di Minerva.

Perché generarli invece di scaricarli: uno sfondo preso da un archivio di
fotografie è una bella immagine appoggiata sopra un ambiente. Uno sfondo
generato dalla stessa tavolozza dell'interfaccia è PARTE dell'ambiente — la
barra ci si appoggia sopra senza litigare, il vetro sfocato trova dietro di sé
colori che già conosce, e l'accento non stona mai perché è lo stesso accento.

Tutti nascono dallo stesso fondo (#070A12, il blu quasi nero di Minerva) e
dalla stessa coppia di accenti, ciano e viola. Cambiano per forma, non per
colore: messi uno dopo l'altro si riconoscono come una famiglia.

── LA COSA MENO OVVIA: IL DISTURBO ──────────────────────────────────────────

Ogni immagine finisce con un velo di rumore da mezzo livello. Sembra un
controsenso — si è appena disegnata una sfumatura perfetta e ci si butta sopra
del disturbo — ma senza, una sfumatura scura su schermo a 8 bit per canale si
vede A STRISCE: i salti fra un livello e l'altro sono più grandi della
differenza che si vorrebbe mostrare, e appaiono bande larghe e visibilissime,
soprattutto nei blu profondi. Il rumore rompe l'allineamento delle bande e
l'occhio ricompone una sfumatura continua. È lo stesso motivo per cui si usa il
retino in tipografia.
"""

import math
import os

import numpy as np
from PIL import Image

W, H = 2560, 1440
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "minerva-shell", "assets", "wallpapers")

# La tavolozza è quella di `theme/Colors.qml`, non una scelta a parte.
BASE = np.array([0x07, 0x0A, 0x12], dtype=float)
DEEP = np.array([0x0B, 0x14, 0x28], dtype=float)
CYAN = np.array([0x22, 0xD3, 0xEE], dtype=float)
BLUE = np.array([0x0E, 0xA5, 0xE9], dtype=float)
VIOLET = np.array([0x8B, 0x5C, 0xF6], dtype=float)


def canvas():
    """Un campo vuoto del colore di fondo, in virgola mobile."""
    return np.tile(BASE, (H, W, 1))


def grid():
    """Coordinate normalizzate: x e y da 0 a 1, e il rapporto dello schermo."""
    x = np.linspace(0.0, 1.0, W)[None, :]
    y = np.linspace(0.0, 1.0, H)[:, None]
    return x, y


def add(img, mask, colour, strength=1.0):
    """Somma un colore secondo una maschera 0–1, senza mai spegnere il fondo."""
    m = np.clip(mask, 0.0, 1.0)[:, :, None] * strength
    img += m * colour
    return img


def finish(img, name, dither=0.5):
    """Disturbo, taglio e salvataggio. Vedi la nota in cima al file."""
    noise = np.random.default_rng(7).normal(0.0, dither, img.shape)
    out = np.clip(img + noise, 0, 255).astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    Image.fromarray(out, "RGB").save(path, optimize=True)
    print(f"  {name}")


def smoothstep(edge0, edge1, v):
    t = np.clip((v - edge0) / max(1e-6, (edge1 - edge0)), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ── Gli sfondi ───────────────────────────────────────────────────────────────

def continuum():
    """La firma di Minerva: la lingua che scende dalla barra.

    È la stessa forma della superficie continua della shell — un corpo che
    scende dal bordo alto, con gli angoli bassi tondi e, dove tocca il bordo,
    due raccordi CONCAVI che lo allargano invece di staccarlo.

    Il raccordo concavo non si ottiene aggiungendo un pezzo di cerchio a lato:
    così spuntano due orecchie, e infatti al primo tentativo sembrava un
    divano. Si ottiene facendo dipendere il BORDO dalla quota: vicino alla cima
    il fianco si sposta in fuori seguendo un arco, e alla fine del raccordo
    torna dritto. La sagoma è una sola curva continua, che è tutto il punto.
    """
    img = canvas()
    x, y = grid()
    px, py = x * W, y * H

    left, right = W * 0.20, W * 0.80
    bottom = H * 0.66
    rf = H * 0.22          # raccordo concavo in alto
    rb = W * 0.09          # angoli tondi in basso

    # Il fianco in funzione della quota: in cima è più in fuori di `rf`, e
    # rientra seguendo l'arco fino a diventare verticale.
    t = np.clip(1.0 - py / rf, 0.0, 1.0)
    flare = rf * (1.0 - np.sqrt(np.clip(1.0 - (1.0 - t) ** 2, 0.0, 1.0)))
    flare = np.where(py < rf, rf - np.sqrt(np.clip(rf ** 2 - (rf - py) ** 2, 0, None)), 0.0)
    lx = left - flare
    rx = right + flare

    # Distanza con segno dal bordo della sagoma: positiva dentro.
    inner = np.minimum(px - lx, rx - px)
    inner = np.minimum(inner, bottom - py)

    # Angoli bassi tondi: dentro il rettangolo ridotto, oppure entro `rb` dal
    # centro dell'arco d'angolo.
    corner = np.full_like(px, 1e9)
    for cx in (left + rb, right - rb):
        d = np.sqrt((px - cx) ** 2 + (py - (bottom - rb)) ** 2)
        near = ((px < left + rb) if cx < W / 2 else (px > right - rb)) & (py > bottom - rb)
        corner = np.where(near, rb - d, corner)
    signed = np.where(corner < 1e8, corner, inner)

    body = smoothstep(-W * 0.004, W * 0.004, signed)

    # Il corpo è un vetro appena più chiaro del fondo, più luminoso in cima:
    # la luce entra dalla barra, come nell'interfaccia vera.
    depth = 1.0 - smoothstep(0.0, bottom, py)
    img = add(img, body * (0.30 + 0.55 * depth), DEEP - BASE)

    # Il filo di luce sul bordo, che segue tutta la sagoma.
    rim = np.exp(-(signed ** 2) / (2 * (W * 0.0016) ** 2))
    img = add(img, rim * 0.55, CYAN)
    img = add(img, rim * 0.20 * smoothstep(bottom * 0.4, bottom, py), VIOLET)

    # Alone diffuso attorno, così la sagoma non è ritagliata nel vuoto.
    halo = np.exp(-np.clip(-signed, 0, None) ** 2 / (2 * (W * 0.045) ** 2))
    img = add(img, halo * 0.10 * depth, BLUE)
    finish(img, "continuum.png")


def aurora():
    """Bande morbide in diagonale: la sfumatura più semplice che si possa fare
    senza che sembri il modello vuoto di un programma di grafica."""
    img = canvas()
    x, y = grid()
    d = (x * 0.75 + y * 0.55)          # direzione della diagonale
    img = add(img, smoothstep(0.1, 1.1, d) * 0.85, DEEP - BASE)
    for centre, width, colour, amount in (
        (0.34, 0.20, BLUE, 0.16),
        (0.58, 0.16, CYAN, 0.11),
        (0.80, 0.24, VIOLET, 0.13),
    ):
        band = np.exp(-((d - centre) ** 2) / (2 * width ** 2))
        img = add(img, band, colour, amount)
    finish(img, "aurora.png")


def orbite():
    """Archi concentrici che escono dall'angolo. Righe sottili su fondo scuro:
    si vedono da vicino e spariscono da lontano, che è quello che deve fare uno
    sfondo dietro delle finestre."""
    img = canvas()
    x, y = grid()
    cx, cy = 0.86, 1.06
    ratio = W / H
    d = np.sqrt(((x - cx) * ratio) ** 2 + (y - cy) ** 2)

    img = add(img, np.exp(-(d ** 2) / (2 * 0.75 ** 2)) * 0.75, DEEP - BASE)
    img = add(img, np.exp(-(d ** 2) / (2 * 0.22 ** 2)) * 0.20, BLUE)
    # Diciotto archi invece di undici, e più marcati: al primo tentativo si
    # vedevano solo di striscio in un angolo, e uno sfondo che non si vede non
    # è uno sfondo discreto — è una superficie vuota.
    for i in range(18):
        r = 0.07 + i * 0.098
        ring = np.exp(-((d - r) ** 2) / (2 * 0.0026 ** 2))
        colour = VIOLET if i % 4 == 3 else CYAN
        img = add(img, ring, colour, 0.55 * math.exp(-i / 9.0))
    finish(img, "orbite.png")


def reticolo():
    """Una griglia in prospettiva che si perde nel nero. È l'unico sfondo con
    un orizzonte, e serve proprio per quello: dà una direzione allo schermo."""
    img = canvas()
    x, y = grid()
    horizon = 0.46

    below = y > horizon
    depth = np.clip((y - horizon) / (1.0 - horizon), 1e-4, 1.0)

    # Righe orizzontali sempre più fitte verso l'orizzonte.
    u = 1.0 / depth
    lines_h = np.exp(-((u % 1.0 - 0.5) ** 2) / (2 * 0.030 ** 2)) * below
    # Righe che convergono nel punto di fuga.
    v = (x - 0.5) / depth
    lines_v = np.exp(-((v % 0.24 - 0.12) ** 2) / (2 * 0.010 ** 2)) * below

    strength = (depth ** 0.7) * 0.5
    img = add(img, lines_h * strength, CYAN, 0.55)
    img = add(img, lines_v * strength, BLUE, 0.40)

    glow = np.exp(-((y - horizon) ** 2) / (2 * 0.055 ** 2))
    img = add(img, glow * 0.30, BLUE)

    # Sopra l'orizzonte non c'era niente, e metà schermo vuoto è metà schermo
    # sprecato: una velatura larga e due lame di luce verticali, appena
    # accennate, danno un cielo senza rubare l'attenzione alle finestre.
    sky = smoothstep(horizon, 0.02, y)
    img = add(img, sky * 0.40, DEEP - BASE)
    for cx, width, amount in ((0.28, 0.055, 0.10), (0.62, 0.085, 0.07), (0.86, 0.040, 0.06)):
        beam = np.exp(-((x - cx) ** 2) / (2 * width ** 2)) * sky
        img = add(img, beam, CYAN if cx < 0.7 else VIOLET, amount)
    finish(img, "reticolo.png")


def onda():
    """Creste sovrapposte, come colline in controluce. Il taglio più basso è
    il più chiaro: è dove di solito sta la dock, e le dà un appoggio."""
    img = canvas()
    x, y = grid()
    layers = [
        (0.52, 0.045, 2.1, 0.20, 0.30),
        (0.63, 0.038, 3.3, 0.62, 0.45),
        (0.74, 0.030, 1.7, 1.15, 0.62),
        (0.86, 0.022, 4.5, 2.05, 0.85),
    ]
    for base, amp, freq, phase, lum in layers:
        ridge = base + amp * np.sin(2 * math.pi * freq * x + phase)
        mask = smoothstep(0.0, 0.006, y - ridge)
        img = add(img, mask * lum * 0.40, DEEP - BASE)
        crest = np.exp(-((y - ridge) ** 2) / (2 * 0.0035 ** 2))
        img = add(img, crest, CYAN, 0.20 * lum)
    glow = np.exp(-((y - 0.44) ** 2) / (2 * 0.16 ** 2))
    img = add(img, glow * 0.14, BLUE)
    finish(img, "onda.png")


def quiete():
    """Quasi nero e una sola luce. Per chi vuole vedere le finestre e nient'altro,
    e per gli schermi che il nero lo spengono davvero."""
    img = canvas() * 0.55
    x, y = grid()
    ratio = W / H
    d = np.sqrt(((x - 0.32) * ratio) ** 2 + (y - 0.28) ** 2)
    img = add(img, np.exp(-(d ** 2) / (2 * 0.52 ** 2)) * 0.80, DEEP - BASE * 0.55)
    img = add(img, np.exp(-(d ** 2) / (2 * 0.17 ** 2)) * 0.16, BLUE)
    # Una seconda luce piccolissima dalla parte opposta: senza, l'immagine è
    # simmetrica attorno a un punto solo e sembra un difetto dello schermo.
    d2 = np.sqrt(((x - 0.88) * ratio) ** 2 + (y - 0.84) ** 2)
    img = add(img, np.exp(-(d2 ** 2) / (2 * 0.24 ** 2)) * 0.10, VIOLET)
    finish(img, "quiete.png", dither=0.7)


def main():
    print("Sfondi di Minerva →", OUT)
    continuum()
    aurora()
    orbite()
    reticolo()
    onda()
    quiete()


if __name__ == "__main__":
    main()
