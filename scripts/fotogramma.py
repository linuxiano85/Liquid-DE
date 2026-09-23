"""fotogramma.py — Leggere un PNG e dire quanto è cambiato, senza dipendenze.

Serve alle prove che guardano lo schermo. Non usa `numpy` né `PIL`: girano
anche su una macchina che non li ha, e una prova che non parte è una prova che
non prova niente.

── Perché non basta confrontare i byte ─────────────────────────────────────

Perché col blur acceso **nessun fotogramma è identico al precedente**: il
passaggio di sfocatura di SceneFX ci mette dentro un pizzico di rumore
(`blur_data.noise`, 0,02 di serie) e lo rigenera ogni volta. Misurato il 9
settembre 2026 dentro la sessione annidata: otto fotografie di una scrivania
ferma davano otto file diversi, e **zero pixel** con una differenza che
l'occhio possa vedere — il massimo era 5 su 765.

Un banco che confronta i byte, in quelle condizioni, dice «instabile» su
tutto. È esattamente quello che ha fatto la prima versione di
`prova-impostazioni.py`: 92 chiavi su 92.

Quindi si confronta con una TOLLERANZA, e su una griglia di punti invece che
su tutti: mezzo milione di pixel in Python puro sono secondi, cinquemila punti
sono millisecondi e dicono la stessa cosa.

`compositore/prova-effetto.py` ha una copia sua di `leggi_png`, più vecchia di
questo file. Non è stata tolta di lì mentre quella prova era verde: si unirà
la prossima volta che quel file si tocca per un'altra ragione.
"""
import struct
import zlib


def leggi_png(percorso):
    """(larghezza, altezza, byte per pixel, pixel) da un PNG."""
    with open(percorso, "rb") as f:
        d = f.read()
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
        filtro = raw[o]
        o += 1
        riga = bytearray(raw[o:o + stride])
        o += stride
        if filtro == 1:
            for x in range(bpp, stride):
                riga[x] = (riga[x] + riga[x - bpp]) & 0xFF
        elif filtro == 2:
            for x in range(stride):
                riga[x] = (riga[x] + prec[x]) & 0xFF
        elif filtro == 3:
            for x in range(stride):
                sx = riga[x - bpp] if x >= bpp else 0
                riga[x] = (riga[x] + ((sx + prec[x]) >> 1)) & 0xFF
        elif filtro == 4:
            for x in range(stride):
                a = riga[x - bpp] if x >= bpp else 0
                b = prec[x]
                c = prec[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                riga[x] = (riga[x] + pr) & 0xFF
        fuori += riga
        prec = riga
    return (larg, alt, bpp, bytes(fuori))


def punto(img, x, y):
    larg, _alt, bpp, dati = img
    o = y * larg * bpp + x * bpp
    return dati[o], dati[o + 1], dati[o + 2]


# Quanto deve essere grande la differenza di un punto perché conti come
# cambiato: la somma sui tre canali, su 765.
#
# Sei, e non dodici. Dodici sembrava prudente — sta sopra il rumore del blur,
# che arriva a cinque — ma taglia via cose vere: fra i due temi scuri «Notte»
# e «Carbone» il fondo cambia di **sei livelli**, e a dodici i due risultavano
# identici. Il modo giusto di stare sopra il rumore non è alzare la soglia: è
# togliere il rumore, cioè spegnere il blur mentre si misura. Con il blur
# spento il rumore è **0,0000 %**, misurato.
SOGLIA = 6


def diversi(a, b, passo=16):
    """Per cento dei punti campionati che sono cambiati fra due immagini.

    Restituisce None se le due immagini non hanno la stessa misura — cioè se
    è cambiata la risoluzione, e allora il confronto punto per punto non vuol
    dire niente.
    """
    if a is None or b is None:
        return None
    if a[0] != b[0] or a[1] != b[1]:
        return None
    larg, alt = a[0], a[1]
    guardati = cambiati = 0
    y = 0
    while y < alt:
        x = 0
        while x < larg:
            pa, pb = punto(a, x, y), punto(b, x, y)
            guardati += 1
            if abs(pa[0] - pb[0]) + abs(pa[1] - pb[1]) + abs(pa[2] - pb[2]) \
                    > SOGLIA:
                cambiati += 1
            x += passo
        y += passo
    return (100.0 * cambiati / guardati) if guardati else 0.0
