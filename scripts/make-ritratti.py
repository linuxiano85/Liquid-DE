#!/usr/bin/env python3
"""make-ritratti.py — Disegna i ritratti di serie di Minerva.

Sono le immagini che si scelgono in Impostazioni → Utente quando non si ha una
foto propria, e che si vedono nella schermata di accesso. Giacomo li ha chiesti
così: «tipo la paperella, il gattino e tante di tanti tipi, un controller RGB,
in base ai gusti».

── Perché disegnati e non scaricati ─────────────────────────────────────────

La stessa ragione degli sfondi (`make-wallpapers.py`), più una: un ritratto
preso da un archivio di icone porta con sé una licenza da rispettare e un
autore da citare, e fra un anno nessuno si ricorda quale file veniva da dove.
Questi nascono da questo file: si ridisegnano tutti cambiando una riga, e non
c'è niente da tenere aggiornato.

── LA COSA MENO OVVIA: SI DISEGNA IN GRANDE ─────────────────────────────────

Pillow non fa antialiasing sui poligoni. Un becco disegnato dritto a 512 pixel
ha il bordo a scaletta, e a schermo si vede benissimo — sono forme piatte a
tinta unita, quindi ogni gradino è un salto di colore netto.

Si disegna quindi a 2048 e si riduce a 512 con LANCZOS: la riduzione media i
pixel e i bordi vengono morbidi. Costa quattro volte la memoria per un decimo
di secondo, ed è l'unica differenza fra «disegnato» e «disegnato male».

── LA SECONDA: LA MISURA VERA È 48 PIXEL ────────────────────────────────────

Nella schermata di accesso questi ritratti sono tondi di poche decine di pixel.
Tutto quello che si vede solo a 512 è tempo buttato, e peggio: un dettaglio
sottile a 48 pixel diventa una macchia sporca. Quindi forme grandi, poche, e
contrasto forte contro il fondo.

Per guardarli a quella misura senza indovinare c'è `--tavola`, che ne stampa
una tavola unica con ogni ritratto anche a 48.

── LE TINTE ─────────────────────────────────────────────────────────────────

Il fondo tondo viene dalla tavolozza di Minerva (`theme/Colors.qml`): è quello
che li fa sembrare una famiglia messi uno accanto all'altro.

Il SOGGETTO no. Una paperella è gialla, un panda è bianco e nero, e tingerli
d'azzurro per coerenza li renderebbe irriconoscibili — che è l'unica cosa che
un ritratto non si può permettere. La coerenza la porta il fondo.
"""
import argparse
import math
import os

from PIL import Image, ImageDraw

# Si disegna qui e si consegna là: vedi la nota in cima.
GRANDE = 2048
LATO = 512

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "minerva-shell", "assets", "ritratti")

# ── I fondi, dalla tavolozza di Minerva ──────────────────────────────────────
#
# Non uno solo: con diciassette tondi identici l'elenco sembra una tabella.
# Sono varianti dello stesso blu profondo verso il ciano, il viola e il verde
# acqua — abbastanza diverse da distinguersi, abbastanza vicine da stare
# insieme.
FONDI = {
    "notte": ("#0B1428", "#132A4A"),
    "ciano": ("#0A1F2B", "#11455C"),
    "viola": ("#150F2E", "#2E1F5C"),
    "alga": ("#0A2320", "#12483F"),
    "brace": ("#241009", "#4A2113"),
    "prugna": ("#220F1C", "#4A1F3A"),
}


def scala(v):
    """Da coordinate 0–1 al foglio grande."""
    return v * GRANDE


def E(d, cx, cy, rx, ry, fill, outline=None, width=0):
    """Ellisse per centro e raggi, che è come si pensa una forma tonda."""
    d.ellipse([scala(cx - rx), scala(cy - ry), scala(cx + rx), scala(cy + ry)],
              fill=fill, outline=outline, width=int(scala(width)))


def C(d, cx, cy, r, fill, outline=None, width=0):
    E(d, cx, cy, r, r, fill, outline, width)


def P(d, punti, fill):
    d.polygon([(scala(x), scala(y)) for x, y in punti], fill=fill)


def R(d, x0, y0, x1, y1, r, fill):
    d.rounded_rectangle([scala(x0), scala(y0), scala(x1), scala(y1)],
                        radius=scala(r), fill=fill)


def L(d, punti, fill, larghezza):
    d.line([(scala(x), scala(y)) for x, y in punti], fill=fill,
           width=int(scala(larghezza)), joint="curve")


def arco(d, cx, cy, r, da, a, fill, larghezza):
    d.arc([scala(cx - r), scala(cy - r), scala(cx + r), scala(cy + r)],
          da, a, fill=fill, width=int(scala(larghezza)))


def foglio(fondo):
    """Il tondo di partenza: una sfumatura verticale dentro un cerchio.

    La sfumatura è verticale e non radiale perché un fondo radiale con sopra
    una figura centrata fa da alone e le toglie il contorno; una sfumatura
    dall'alto lascia la figura staccata.
    """
    cima, fondale = (Image.new("RGB", (1, 1), c).getpixel((0, 0)) for c in fondo)
    grad = Image.new("RGB", (1, GRANDE))
    for y in range(GRANDE):
        t = y / (GRANDE - 1)
        grad.putpixel((0, y), tuple(int(cima[i] + (fondale[i] - cima[i]) * t)
                                    for i in range(3)))
    img = grad.resize((GRANDE, GRANDE))

    tondo = Image.new("L", (GRANDE, GRANDE), 0)
    ImageDraw.Draw(tondo).ellipse([0, 0, GRANDE - 1, GRANDE - 1], fill=255)
    fuori = Image.new("RGBA", (GRANDE, GRANDE), (0, 0, 0, 0))
    fuori.paste(img, (0, 0), tondo)
    return fuori


def consegna(img, nome):
    os.makedirs(OUT, exist_ok=True)
    piccolo = img.resize((LATO, LATO), Image.LANCZOS)
    piccolo.save(os.path.join(OUT, nome + ".png"), optimize=True)
    return piccolo


# ── Gli occhi, che sono di tutti ─────────────────────────────────────────────
#
# Una funzione sola perché due occhi disegnati a mano due volte non vengono mai
# uguali, e su una faccia lo si vede subito.

def occhi(d, cx, cy, dist, r, colore="#101820", luce=True):
    for lato in (-1, 1):
        C(d, cx + lato * dist, cy, r, colore)
        if luce:
            C(d, cx + lato * dist + r * 0.32, cy - r * 0.34, r * 0.30, "#FFFFFF")


# ── I ritratti ───────────────────────────────────────────────────────────────
#
# Ognuno prende `(d, img)`: la matita e il foglio. Quasi tutti usano solo la
# matita, ma la luna ha bisogno del foglio per posarci sopra una figura già
# bucata — vedi lì — e due protocolli diversi per diciassette funzioni sono
# un modo di sbagliarsi.

def paperella(d, img):
    C(d, 0.50, 0.62, 0.245, "#FBBF24")            # corpo
    P(d, [(0.30, 0.60), (0.24, 0.72), (0.36, 0.70)], "#F59E0B")  # ala
    C(d, 0.58, 0.38, 0.155, "#FCD34D")            # testa
    P(d, [(0.70, 0.37), (0.83, 0.41), (0.70, 0.45)], "#F97316")  # becco
    C(d, 0.60, 0.345, 0.026, "#101820")
    C(d, 0.607, 0.337, 0.009, "#FFFFFF")


def gattino(d, img):
    P(d, [(0.28, 0.36), (0.33, 0.15), (0.45, 0.28)], "#F59E0B")   # orecchie
    P(d, [(0.72, 0.36), (0.67, 0.15), (0.55, 0.28)], "#F59E0B")
    P(d, [(0.32, 0.33), (0.35, 0.21), (0.42, 0.29)], "#FCA5A5")
    P(d, [(0.68, 0.33), (0.65, 0.21), (0.58, 0.29)], "#FCA5A5")
    C(d, 0.50, 0.47, 0.255, "#FBBF24")                            # testa
    E(d, 0.50, 0.575, 0.145, 0.105, "#FEF3C7")                    # muso
    occhi(d, 0.50, 0.44, 0.105, 0.043)
    P(d, [(0.465, 0.535), (0.535, 0.535), (0.50, 0.575)], "#F472B6")  # naso
    for lato in (-1, 1):
        for k, dy in enumerate((-0.035, 0.0, 0.035)):
            L(d, [(0.50 + lato * 0.14, 0.575 + dy * 0.6),
                  (0.50 + lato * 0.30, 0.575 + dy)], "#FDE68A", 0.012)


def volpe(d, img):
    P(d, [(0.26, 0.40), (0.28, 0.14), (0.46, 0.28)], "#EA580C")
    P(d, [(0.74, 0.40), (0.72, 0.14), (0.54, 0.28)], "#EA580C")
    P(d, [(0.30, 0.36), (0.31, 0.21), (0.42, 0.29)], "#1F2937")
    P(d, [(0.70, 0.36), (0.69, 0.21), (0.58, 0.29)], "#1F2937")
    P(d, [(0.22, 0.42), (0.78, 0.42), (0.50, 0.84)], "#F97316")   # muso a cuneo
    P(d, [(0.34, 0.56), (0.66, 0.56), (0.50, 0.84)], "#FFF7ED")   # guance
    occhi(d, 0.50, 0.50, 0.115, 0.040)
    C(d, 0.50, 0.775, 0.038, "#101820")


def panda(d, img):
    C(d, 0.28, 0.28, 0.105, "#111827")
    C(d, 0.72, 0.28, 0.105, "#111827")
    C(d, 0.50, 0.50, 0.285, "#F8FAFC")
    E(d, 0.385, 0.465, 0.082, 0.098, "#111827")
    E(d, 0.615, 0.465, 0.082, 0.098, "#111827")
    C(d, 0.385, 0.475, 0.030, "#F8FAFC")
    C(d, 0.615, 0.475, 0.030, "#F8FAFC")
    E(d, 0.50, 0.615, 0.052, 0.038, "#111827")
    arco(d, 0.50, 0.60, 0.085, 20, 160, "#111827", 0.016)


def gufo(d, img):
    P(d, [(0.28, 0.32), (0.34, 0.13), (0.46, 0.26)], "#92400E")
    P(d, [(0.72, 0.32), (0.66, 0.13), (0.54, 0.26)], "#92400E")
    E(d, 0.50, 0.55, 0.275, 0.305, "#B45309")
    E(d, 0.50, 0.66, 0.165, 0.175, "#D97706")
    C(d, 0.385, 0.44, 0.105, "#FFFBEB")
    C(d, 0.615, 0.44, 0.105, "#FFFBEB")
    occhi(d, 0.50, 0.44, 0.115, 0.052)
    P(d, [(0.455, 0.525), (0.545, 0.525), (0.50, 0.60)], "#F59E0B")


def pinguino(d, img):
    E(d, 0.50, 0.585, 0.275, 0.325, "#111827")
    E(d, 0.50, 0.635, 0.175, 0.245, "#F8FAFC")
    C(d, 0.50, 0.34, 0.185, "#111827")
    E(d, 0.50, 0.375, 0.115, 0.105, "#F8FAFC")
    occhi(d, 0.50, 0.335, 0.072, 0.032)
    P(d, [(0.44, 0.415), (0.56, 0.415), (0.50, 0.475)], "#F97316")
    P(d, [(0.30, 0.87), (0.46, 0.87), (0.38, 0.92)], "#F97316")
    P(d, [(0.54, 0.87), (0.70, 0.87), (0.62, 0.92)], "#F97316")


def riccio(d, img):
    for i in range(13):
        a = math.pi * (0.06 + 0.88 * i / 12)
        P(d, [(0.50 - 0.30 * math.cos(a), 0.62 - 0.26 * math.sin(a)),
              (0.50 - 0.46 * math.cos(a), 0.62 - 0.42 * math.sin(a)),
              (0.50 - 0.20 * math.cos(a + 0.22), 0.62 - 0.18 * math.sin(a + 0.22))],
          "#78350F")
    E(d, 0.50, 0.66, 0.285, 0.235, "#A16207")
    E(d, 0.62, 0.62, 0.175, 0.155, "#FDE68A")
    occhi(d, 0.635, 0.585, 0.062, 0.030)
    C(d, 0.775, 0.645, 0.036, "#101820")


def controller(d, img):
    """Il controller con le luci RGB, chiesto per nome."""
    R(d, 0.13, 0.36, 0.87, 0.70, 0.16, "#1F2937")
    E(d, 0.22, 0.62, 0.135, 0.145, "#1F2937")
    E(d, 0.78, 0.62, 0.135, 0.145, "#1F2937")
    # La striscia RGB: sei tacche di tinte diverse. È la cosa che si riconosce
    # a 48 pixel — la forma del controller da sola diventa un fagiolo scuro.
    tinte = ["#F43F5E", "#F59E0B", "#FACC15", "#22C55E", "#22D3EE", "#8B5CF6"]
    for i, t in enumerate(tinte):
        R(d, 0.235 + i * 0.092, 0.395, 0.305 + i * 0.092, 0.425, 0.015, t)
    R(d, 0.245, 0.485, 0.285, 0.605, 0.014, "#94A3B8")   # croce direzionale
    R(d, 0.205, 0.525, 0.325, 0.565, 0.014, "#94A3B8")
    C(d, 0.705, 0.505, 0.036, "#22D3EE")                 # tasti
    C(d, 0.795, 0.545, 0.036, "#F43F5E")
    C(d, 0.705, 0.585, 0.036, "#FACC15")
    C(d, 0.615, 0.545, 0.036, "#22C55E")


def chitarra(d, img):
    # Schiarita e ingrossata dopo la tavola dei 48 pixel: col legno scuro di
    # prima, alla misura della schermata di accesso, era una macchia marrone
    # su un fondo prugna. Il manico sottile spariva del tutto.
    E(d, 0.45, 0.69, 0.235, 0.225, "#D97706")
    E(d, 0.45, 0.48, 0.170, 0.175, "#D97706")
    E(d, 0.45, 0.69, 0.180, 0.170, "#F59E0B")
    C(d, 0.45, 0.63, 0.080, "#3A2410")
    L(d, [(0.50, 0.40), (0.75, 0.17)], "#A16207", 0.095)
    R(d, 0.705, 0.09, 0.845, 0.215, 0.025, "#111827")
    for i in range(3):
        L(d, [(0.40 + i * 0.045, 0.86), (0.62 + i * 0.045, 0.20)], "#FEF3C7", 0.010)


def fotocamera(d, img):
    R(d, 0.14, 0.36, 0.86, 0.76, 0.10, "#1F2937")
    R(d, 0.36, 0.28, 0.58, 0.38, 0.03, "#374151")
    C(d, 0.50, 0.56, 0.165, "#0F172A")
    C(d, 0.50, 0.56, 0.115, "#22D3EE")
    C(d, 0.50, 0.56, 0.062, "#0B1220")
    C(d, 0.455, 0.515, 0.028, "#E0F2FE")
    C(d, 0.755, 0.425, 0.030, "#F43F5E")


def tazza(d, img):
    # ── Il manico era staccato, e il vapore era da un'altra parte ───────────
    #
    # L'arco del manico stava centrato in 0.735 e apriva a ±70°: i suoi due
    # capi cadevano a x = 0.774, cioè NOVE CENTESIMI oltre il fianco della
    # tazza, che finisce a 0.68. Da lontano sembrava una parentesi appoggiata
    # accanto. Adesso il centro è sul fianco e l'apertura è ±110°, così i capi
    # rientrano DENTRO la tazza (x = 0.641) e la giuntura non si vede.
    #
    # Il vapore partiva da y ≈ 0.16, con la tazza che comincia a 0.44: in mezzo
    # c'erano tre decimi di tondo vuoto e i riccioli sembravano nuvole di
    # passaggio. Ora stanno appena sopra il bordo.
    R(d, 0.24, 0.44, 0.68, 0.82, 0.09, "#F8FAFC")
    R(d, 0.24, 0.44, 0.68, 0.53, 0.03, "#E2E8F0")
    arco(d, 0.68, 0.615, 0.115, 250, 110, "#F8FAFC", 0.045)
    R(d, 0.28, 0.82, 0.64, 0.855, 0.017, "#CBD5E1")
    for x, dy in ((0.34, 0.02), (0.45, -0.03), (0.56, 0.02)):
        arco(d, x, 0.35 + dy, 0.048, 200, 340, "#94A3B8", 0.019)


def libro(d, img):
    P(d, [(0.50, 0.32), (0.14, 0.38), (0.14, 0.80), (0.50, 0.74)], "#F8FAFC")
    P(d, [(0.50, 0.32), (0.86, 0.38), (0.86, 0.80), (0.50, 0.74)], "#E2E8F0")
    R(d, 0.485, 0.32, 0.515, 0.78, 0.008, "#7C3AED")
    for i in range(4):
        y = 0.44 + i * 0.085
        L(d, [(0.20, y + 0.012), (0.44, y - 0.006)], "#94A3B8", 0.016)
        L(d, [(0.56, y - 0.006), (0.80, y + 0.012)], "#94A3B8", 0.016)


def razzo(d, img):
    P(d, [(0.50, 0.10), (0.66, 0.44), (0.66, 0.70), (0.34, 0.70), (0.34, 0.44)],
      "#E2E8F0")
    P(d, [(0.50, 0.10), (0.62, 0.38), (0.38, 0.38)], "#F43F5E")
    P(d, [(0.34, 0.52), (0.18, 0.76), (0.34, 0.72)], "#F43F5E")
    P(d, [(0.66, 0.52), (0.82, 0.76), (0.66, 0.72)], "#F43F5E")
    C(d, 0.50, 0.50, 0.082, "#0B1220")
    C(d, 0.50, 0.50, 0.058, "#22D3EE")
    P(d, [(0.40, 0.70), (0.60, 0.70), (0.50, 0.92)], "#F59E0B")
    P(d, [(0.445, 0.70), (0.555, 0.70), (0.50, 0.84)], "#FDE68A")


def pianeta(d, img):
    C(d, 0.50, 0.48, 0.245, "#8B5CF6")
    C(d, 0.415, 0.40, 0.062, "#A78BFA")
    C(d, 0.585, 0.545, 0.042, "#A78BFA")
    C(d, 0.475, 0.585, 0.030, "#A78BFA")
    # L'anello passa DIETRO in alto e DAVANTI in basso: senza, sembra un
    # piatto appoggiato e il pianeta perde la sua forma.
    d.arc([scala(0.13), scala(0.40), scala(0.87), scala(0.60)], 180, 360,
          fill="#F59E0B", width=int(scala(0.030)))
    d.arc([scala(0.13), scala(0.40), scala(0.87), scala(0.60)], 0, 180,
          fill="#FBBF24", width=int(scala(0.034)))


def luna(d, img):
    # ── Una falce, e perché serve il foglio e non solo la matita ────────────
    #
    # Prima era un disco pieno: la riga che avrebbe dovuto dargli il morso era
    # `C(d, 0.63, 0.40, 0.245, None)`, e `fill=None` in Pillow non toglie
    # niente — non disegna e basta. Restava un tondo chiaro, che a 48 pixel è
    # un tondo chiaro e nient'altro.
    #
    # Il morso non si può dare qui: `d` fonde quello che disegna (è una matita
    # `"RGBA"`), e anche potendo cancellare bucherebbe pure il fondo, lasciando
    # vedere la pagina attraverso. Quindi la luna si disegna su un foglio a
    # parte, le si toglie il morso mentre è sola, e si posa dopo.
    falce = Image.new("RGBA", img.size, (0, 0, 0, 0))
    # Matita SENZA `"RGBA"`: scrive i valori invece di fonderli, quindi un
    # riempimento trasparente cancella davvero.
    f = ImageDraw.Draw(falce)
    C(f, 0.50, 0.50, 0.275, "#FDE68A")
    C(f, 0.37, 0.55, 0.050, "#FCD34D")
    C(f, 0.44, 0.68, 0.035, "#FCD34D")
    C(f, 0.33, 0.40, 0.030, "#FCD34D")
    C(f, 0.655, 0.38, 0.255, (0, 0, 0, 0))
    img.alpha_composite(falce)


def cactus(d, img):
    R(d, 0.42, 0.20, 0.58, 0.74, 0.08, "#16A34A")
    R(d, 0.20, 0.40, 0.34, 0.62, 0.07, "#16A34A")
    R(d, 0.20, 0.55, 0.46, 0.62, 0.035, "#16A34A")
    R(d, 0.66, 0.32, 0.80, 0.56, 0.07, "#16A34A")
    R(d, 0.54, 0.49, 0.80, 0.56, 0.035, "#16A34A")
    R(d, 0.30, 0.72, 0.70, 0.90, 0.04, "#EA580C")
    R(d, 0.26, 0.68, 0.74, 0.76, 0.03, "#F97316")
    C(d, 0.50, 0.235, 0.055, "#F43F5E")


def fungo(d, img):
    d.pieslice([scala(0.16), scala(0.20), scala(0.84), scala(0.76)], 180, 360,
               fill="#EF4444")
    C(d, 0.36, 0.36, 0.055, "#FFF7ED")
    C(d, 0.60, 0.32, 0.042, "#FFF7ED")
    C(d, 0.52, 0.44, 0.032, "#FFF7ED")
    R(d, 0.40, 0.47, 0.60, 0.84, 0.06, "#FEF3C7")
    arco(d, 0.50, 0.50, 0.115, 20, 160, "#FDE68A", 0.020)


RITRATTI = [
    ("paperella", "ciano", paperella),
    ("gattino", "notte", gattino),
    ("volpe", "alga", volpe),
    ("panda", "viola", panda),
    ("gufo", "notte", gufo),
    ("pinguino", "ciano", pinguino),
    ("riccio", "alga", riccio),
    ("controller", "notte", controller),
    ("chitarra", "prugna", chitarra),
    ("fotocamera", "viola", fotocamera),
    ("tazza", "brace", tazza),
    ("libro", "notte", libro),
    ("razzo", "notte", razzo),
    ("pianeta", "viola", pianeta),
    ("luna", "notte", luna),
    ("cactus", "alga", cactus),
    ("fungo", "prugna", fungo),
]


def tavola(piccoli):
    """Tutti insieme, e ognuno anche a 48 pixel.

    Serve a guardarli alla misura vera invece di indovinarla: nella schermata
    di accesso sono tondi piccoli, ed è lì che si scopre quale non si capisce.
    """
    colonne = 6
    cella, mini = 160, 48
    righe = (len(piccoli) + colonne - 1) // colonne
    alto = righe * (cella + mini + 24) + 24
    tela = Image.new("RGB", (colonne * cella + 24, alto), "#0B1220")
    for i, (nome, img) in enumerate(piccoli):
        cx = (i % colonne) * cella + 12
        cy = (i // colonne) * (cella + mini + 24) + 12
        tela.paste(img.resize((cella - 16, cella - 16), Image.LANCZOS), (cx + 8, cy))
        tela.paste(img.resize((mini, mini), Image.LANCZOS),
                   (cx + (cella - mini) // 2, cy + cella))
    percorso = os.path.join(OUT, "_tavola.png")
    tela.save(percorso)
    print("  tavola →", percorso)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tavola", action="store_true",
                    help="stampa anche una tavola con tutti, e ognuno a 48 pixel")
    args = ap.parse_args()

    print("Ritratti di Minerva →", OUT)
    piccoli = []
    for nome, fondo, disegna in RITRATTI:
        img = foglio(FONDI[fondo])
        disegna(ImageDraw.Draw(img, "RGBA"), img)
        piccoli.append((nome, consegna(img, nome)))
        print(f"  {nome}")
    if args.tavola:
        tavola(piccoli)


if __name__ == "__main__":
    main()
