#!/usr/bin/env python3
"""Una tastiera finta su /dev/uinput, per provare Minerva senza mani.

Compagno di `prova-clic.py`: quello preme dove diciamo, questa scrive quello
che diciamo. Serve a provare le parti che si comandano scrivendo — il nome di
una cartella nuova, una rinomina, il campo del percorso — che finora si
potevano provare solo a mano, cioè quasi mai.

    prova-tasti.py "Documenti"        scrive il testo
    prova-tasti.py --tasto invio      preme un tasto per nome
    prova-tasti.py "prova" --tasto invio

I codici sono POSIZIONI sulla tastiera, non lettere: è il compositore ad
applicarci sopra la disposizione scelta. Per le lettere e i numeri italiano e
inglese coincidono; **per la punteggiatura no**, e non è un dettaglio.

Su una tastiera italiana la barra `/` è maiuscolo-7, e il tasto che in inglese
fa `-` fa un apostrofo. Finché la tabella era una sola, questo strumento non
sapeva scrivere un percorso — e i percorsi sono esattamente quello che si
scrive nelle caselle di Minerva. Da qui la tabella doppia, scelta leggendo la
disposizione vera della sessione.
"""
import fcntl
import struct
import os
import sys

import cartelle  # le cartelle di Liquid DE, accanto a questo file
import time

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY = 0, 1
SYN_REPORT = 0

KEY_LEFTSHIFT = 42

def disposizione():
    """Quale disposizione ha scelto chi usa questa sessione.

    La dicono le impostazioni di Liquid DE: sono quelle che il compositore
    applica all'avvio (`Compositore.applicaIngresso()`). Qui prima si
    chiedeva a `hyprctl`, che sotto il nostro compositore non esiste: la
    domanda falliva sempre e si ricadeva comunque sulle impostazioni.
    """
    import json
    import os
    try:
        with open(os.path.join(cartelle.config_di_partenza(), "settings.json"),
                  encoding="utf-8") as f:
            d = json.load(f)
        l = str(d.get("input", {}).get("layout", "")).split(",")[0].strip()
        if l:
            return l
    except Exception:
        pass
    return "us"


# Posizione sulla tastiera → carattere che ci si trova sopra, senza e con
# maiuscolo. Solo quello che serve a scrivere un nome di file.
ROWS = {
    2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9",
    11: "0", 12: "-", 13: "=",
    16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "y", 22: "u", 23: "i",
    24: "o", 25: "p",
    30: "a", 31: "s", 32: "d", 33: "f", 34: "g", 35: "h", 36: "j", 37: "k",
    38: "l",
    44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m",
    52: ".", 57: " ",
}

# ── La punteggiatura, che cambia con la disposizione ──────────────────────
#
# Carattere → (posizione, serve maiuscolo). Le posizioni sono le stesse, quello
# che ci si trova sopra no.
PUNTI = {
    "it": {
        "/": (8, True),   "!": (2, True),   '"': (3, True),
        "$": (5, True),   "%": (6, True),   "&": (7, True),
        "(": (9, True),   ")": (10, True),  "=": (11, True),
        "?": (12, True),  "'": (12, False),
        "+": (27, False), "*": (27, True),
        "-": (53, False), "_": (53, True),
        ",": (51, False), ";": (51, True),
        ".": (52, False), ":": (52, True),
        "\\": (41, False), "|": (41, True),
        "à": (40, False), "è": (26, False), "ì": (13, False),
        "ò": (39, False), "ù": (43, False),
    },
    "us": {
        "/": (53, False), "?": (53, True),
        "!": (2, True),   "@": (3, True),   "#": (4, True),
        "$": (5, True),   "%": (6, True),   "^": (7, True),
        "&": (8, True),   "*": (9, True),   "(": (10, True),
        ")": (11, True),
        "-": (12, False), "_": (12, True),
        "=": (13, False), "+": (13, True),
        ";": (39, False), ":": (39, True),
        "'": (40, False), '"': (40, True),
        ",": (51, False), "<": (51, True),
        ".": (52, False), ">": (52, True),
        "\\": (43, False), "|": (43, True),
    },
}

CHARS = {}
for code, ch in ROWS.items():
    CHARS[ch] = (code, False)
    if ch.isalpha():
        CHARS[ch.upper()] = (code, True)

# La punteggiatura sovrascrive: su italiano il tasto 12 fa un apostrofo, non
# un trattino, e la tabella generica qui sopra direbbe il falso.
_QUALE = disposizione()
for _c, _v in PUNTI.get(_QUALE, PUNTI["us"]).items():
    CHARS[_c] = _v

NAMED = {
    "invio": 28, "enter": 28, "return": 28,
    "esc": 1, "escape": 1,
    "tab": 15,
    "backspace": 14, "canc-indietro": 14,
    "canc": 111, "delete": 111,
    "su": 103, "giu": 108, "sinistra": 105, "destra": 106,
    "inizio": 102, "home": 102, "fine": 107, "end": 107,
    # I dodici funzione, per intero: F9 è servito la prima volta il 25
    # agosto 2026 per provare una scorciatoia DENTRO minerva-wayland — ci
    # voleva un tasto che Hyprland non si prende, o se lo mangiava lui
    # prima che arrivasse al compositore annidato.
    "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63, "f6": 64,
    "f7": 65, "f8": 66, "f9": 67, "f10": 68, "f11": 87, "f12": 88,
    "spazio": 57,
    # Le lettere per le combinazioni (ctrl+s, ctrl+n, …): le posizioni
    # coincidono su tastiere italiane e inglesi.
    "a": 30, "b": 48, "c": 46, "d": 32, "e": 18, "f": 33, "g": 34,
    "h": 35, "i": 23, "j": 36, "k": 37, "l": 38, "m": 50, "n": 49,
    "o": 24, "p": 25, "q": 16, "r": 19, "s": 31, "t": 20, "u": 22,
    "v": 47, "w": 17, "x": 45, "y": 21, "z": 44,
}

KEY_LEFTCTRL = 29
KEY_LEFTALT = 56
KEY_LEFTMETA = 125

MODS = {
    "ctrl": KEY_LEFTCTRL, "control": KEY_LEFTCTRL,
    "alt": KEY_LEFTALT,
    "super": KEY_LEFTMETA, "meta": KEY_LEFTMETA, "win": KEY_LEFTMETA,
    "shift": KEY_LEFTSHIFT, "maiusc": KEY_LEFTSHIFT,
}


def main():
    text = ""
    keys = []
    combos = []
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--tasto":
            i += 1
            if i < len(args):
                keys.append(args[i])
        elif args[i] == "--combo":
            # Una combinazione con un modificatore, come «super+m»: è il modo
            # di provare le scorciatoie di Minerva (Super+M ingrandisce) senza
            # mani. Si possono mettere più modificatori: «ctrl+super+m».
            i += 1
            if i < len(args):
                combos.append(args[i])
        else:
            text += args[i]
        i += 1

    unknown = [c for c in text if c not in CHARS]
    if unknown:
        print(f"prova-tasti: non so scrivere {unknown!r} "
              f"(disposizione «{_QUALE}»)", file=sys.stderr)
        return 1
    for k in keys:
        if k.lower() not in NAMED:
            print(f"prova-tasti: tasto sconosciuto «{k}»", file=sys.stderr)
            return 1
    for combo in combos:
        pezzi = [p.strip().lower() for p in combo.split("+")]
        if len(pezzi) < 2 or any(p not in MODS for p in pezzi[:-1]) \
                or pezzi[-1] not in NAMED:
            print(f"prova-tasti: combinazione sconosciuta «{combo}»",
                  file=sys.stderr)
            return 1

    fd = open("/dev/uinput", "wb", buffering=0)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    # Ogni codice che potremmo emettere va dichiarato PRIMA di creare il
    # dispositivo: quelli non dichiarati il kernel li scarta in silenzio, e la
    # prova sembra funzionare mentre non scrive niente. Si prendono da `CHARS`
    # e non da `ROWS`, perché la punteggiatura della disposizione usa tasti che
    # in `ROWS` non compaiono.
    codici = {c for c, _ in CHARS.values()}
    codici.update(NAMED.values())
    codici.update(MODS.values())
    codici.add(KEY_LEFTSHIFT)
    for code in sorted(codici):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)

    name = b"minerva-prova-tastiera".ljust(80, b"\0")
    fd.write(name + struct.pack("HHHH", 0x03, 0x1234, 0x5679, 1)
             + struct.pack("i", 0) + b"\0" * (4 * 64 * 4))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    # Il compositore impiega un attimo ad accorgersi della tastiera nuova: i
    # tasti premuti prima che se ne accorga non arrivano da nessuna parte.
    time.sleep(1.0)

    def ev(t, c, v):
        fd.write(struct.pack("qqHHi", 0, 0, t, c, v))

    def press(code, shift=False):
        if shift:
            ev(EV_KEY, KEY_LEFTSHIFT, 1)
            ev(EV_SYN, SYN_REPORT, 0)
        ev(EV_KEY, code, 1)
        ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.02)
        ev(EV_KEY, code, 0)
        ev(EV_SYN, SYN_REPORT, 0)
        if shift:
            ev(EV_KEY, KEY_LEFTSHIFT, 0)
            ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.05)

    for ch in text:
        code, shift = CHARS[ch]
        press(code, shift)

    for k in keys:
        press(NAMED[k.lower()])

    for combo in combos:
        pezzi = [p.strip().lower() for p in combo.split("+")]
        for mod in pezzi[:-1]:
            ev(EV_KEY, MODS[mod], 1)
            ev(EV_SYN, SYN_REPORT, 0)
        press(NAMED[pezzi[-1]])
        for mod in reversed(pezzi[:-1]):
            ev(EV_KEY, MODS[mod], 0)
            ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.08)

    time.sleep(0.4)
    fcntl.ioctl(fd, UI_DEV_DESTROY)
    fd.close()
    print(f"scritto {text!r}" + (f" + {keys}" if keys else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
