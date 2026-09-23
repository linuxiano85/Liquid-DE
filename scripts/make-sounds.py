#!/usr/bin/env python3
"""make-sounds.py — Genera i suoni di Minerva.

I suoni sono FILE, ma non sono materiale d'archivio: sono generati da questo
programma, e questo programma sta nel deposito insieme a tutto il resto. Se un
giorno il timbro non convince, si cambia una riga qui e si rigenera tutto —
invece di ritoccare a orecchio undici file in un editor audio e ritrovarsi con
undici suoni che non sono più parenti fra loro.

── PERCHÉ UNDICI SUONI PER IL VOLUME ─────────────────────────────────────────

Perché il volume ha una posizione, e un suono solo non la racconta. Con un
click sempre uguale si sa che il tasto ha funzionato; con una nota che sale si
sa ANCHE dove si è arrivati, senza guardare lo schermo. È la stessa
informazione della barra a schermo, data all'orecchio invece che all'occhio —
e l'orecchio è già lì, visto che si sta regolando il volume.

Le undici note non sono una scala qualunque: sono una PENTATONICA MAGGIORE. In
una pentatonica non esistono due note che suonino male una dopo l'altra, in
nessun ordine. Vuol dire che tenendo premuto il tasto si sente una frase
musicale invece di una sirena, e che saltando da un valore all'altro col
cursore non si incappa mai in un intervallo stonato. È il motivo per cui questa
scala esiste in metà delle musiche del mondo, ed è esattamente la proprietà che
serve qui.

── LA FORMA DEL SUONO ────────────────────────────────────────────────────────

Fondamentale più due armoniche deboli: la sinusoide pura suona artificiale e
«medica», due armoniche appena accennate le danno un corpo di strumento senza
renderla squillante. Novanta millisecondi in tutto, con una salita di tre
millesimi — senza quella salita l'onda parte da zero di scatto e si sente un
«tac» che non c'entra niente con la nota.
"""

import math
import os
import struct
import wave

RATE = 48000
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "minerva-shell", "assets", "sounds")


def tone(freq, ms, peak=0.22, decay_ms=38, harmonics=(1.0, 0.26, 0.08), attack_ms=3.0):
    """Una nota: fondamentale più armoniche, che sale in fretta e svanisce."""
    n = int(RATE * ms / 1000)
    attack = max(1, int(RATE * attack_ms / 1000))
    tau = decay_ms / 1000.0
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for k, amp in enumerate(harmonics, start=1):
            s += amp * math.sin(2 * math.pi * freq * k * t)
        s /= sum(harmonics)
        s *= math.exp(-t / tau)
        if i < attack:
            s *= i / attack
        out.append(s * peak)
    return out


def mix(*parts):
    """Somma più pezzi allineati all'inizio, allungando il risultato."""
    length = max(len(p) for p in parts)
    out = [0.0] * length
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out


def delay(samples, ms):
    return [0.0] * int(RATE * ms / 1000) + samples


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    frames = bytearray()
    for v in samples:
        v = max(-1.0, min(1.0, v))
        frames += struct.pack("<h", int(v * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(f"  {name}  ({len(samples) / RATE * 1000:.0f} ms)")


def main():
    print("Suoni di Minerva →", OUT)

    # ── I passi del volume ────────────────────────────────────────────────
    # Pentatonica maggiore di Do, due ottave: 0%, 10%, … 100%.
    root = 523.25  # Do5
    degrees = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
    for i, semitones in enumerate(degrees):
        f = root * (2 ** (semitones / 12.0))
        # Le note acute si sentono di più a parità di ampiezza: si abbassano
        # un poco, altrimenti alzando il volume il suono di conferma cresce
        # due volte — una perché è più acuto e una perché il volume è salito.
        peak = 0.22 * (1.0 - 0.30 * (i / (len(degrees) - 1)))
        write(f"volume-{i:02d}.wav", tone(f, 90, peak=peak))

    # ── Sei arrivato in fondo ─────────────────────────────────────────────
    # Due tocchi bassi e sordi, ravvicinati. Non è un errore — non si è
    # sbagliato niente — quindi non deve suonare come un errore: suona come
    # una porta che non si apre oltre.
    low = tone(392.0, 70, peak=0.20, decay_ms=26, harmonics=(1.0, 0.12))
    write("volume-limit.wav", mix(low, delay(low, 78)))

    # ── Silenzio acceso e spento ──────────────────────────────────────────
    # Scende quando si toglie il suono, sale quando torna. È l'unica coppia
    # di suoni di Minerva che significa qualcosa per la sua DIREZIONE, e la
    # direzione si capisce senza spiegazioni.
    write("mute-on.wav", mix(
        tone(784.0, 70, peak=0.18, decay_ms=28),
        delay(tone(523.25, 90, peak=0.18, decay_ms=34), 60)))
    write("mute-off.wav", mix(
        tone(523.25, 70, peak=0.18, decay_ms=28),
        delay(tone(784.0, 90, peak=0.18, decay_ms=34), 60)))


if __name__ == "__main__":
    main()
