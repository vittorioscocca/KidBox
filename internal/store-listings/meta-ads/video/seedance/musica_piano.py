"""Colonna sonora «pianoforte intimo», come gli spot Apple più emotivi: poche
note di piano col feltro, spazio, poi gli archi che si aprono sulla cena.
Composta qui, nessun diritto di terzi; stessi argomenti di musica_spot.py.

70 BPM, La minore → Do maggiore (Lam – Fa – Do – Sol):

- 0 s     piano solo, una nota per volta (la corsa, il disordine);
- 3,6 s   la mano sinistra entra con gli accordi;
- 8,75 s  un tappeto d'archi lontano e un battito di cassa sordo;
- cena    gli archi si aprono, la melodia sale di ottava;
- chiusura: Do maggiore tenuto, una nota alta che risponde, sfuma.

Uso: python3 musica_piano.py musica.wav --dur 34.6 --card 29.6 \\
         --cuts 0,3.58,8.75,12.375,17.29,20.79,26.455
"""
import argparse

import numpy as np
from scipy.io import wavfile

from musica_jazz import SR, lowpass, room, midi

BEAT = 60 / 70
BAR = 4 * BEAT
rng = np.random.default_rng(5)


def piano(freq, dur, soft=1.0):
    """Piano col feltro: pochi armonici che si spengono in fretta, coda lunga."""
    t = np.arange(int(dur * SR)) / SR
    tone = sum(a * np.sin(2 * np.pi * freq * k * (1 + 0.0004 * k * k) * t) * np.exp(-t * (1.2 + 1.6 * k))
               for k, a in ((1, 1.0), (2, 0.45), (3, 0.2), (4, 0.08)))
    hammer = lowpass(rng.uniform(-1, 1, len(t)), 2500) * np.exp(-t * 90) * 0.15
    rel = np.clip(np.minimum(1, (dur - t) / 0.3), 0, 1)
    return lowpass((tone + hammer) * np.minimum(1, t / 0.004) * rel, 3000 * soft + 1500)


def strings(freqs, dur, attack=1.5, release=1.5):
    t = np.arange(int(dur * SR)) / SR
    x = np.zeros_like(t)
    for f in freqs:
        for det in (-0.08, 0.0, 0.08):
            vib = 1 + 0.003 * np.sin(2 * np.pi * 5 * t + rng.uniform(0, 6))
            x += 2 * ((f * 2 ** (det / 12) * vib * t + rng.uniform(0, 1)) % 1) - 1
    x = lowpass(lowpass(x, 1800), 1800) / (3 * len(freqs))
    e = np.clip(np.minimum(t / attack, (dur - t) / release), 0, 1)
    return x * e


def thump():
    t = np.arange(int(0.5 * SR)) / SR
    f = 42 + 30 * np.exp(-t * 20)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--dur", type=float, default=34.6)
    p.add_argument("--card", type=float, default=29.6)
    p.add_argument("--cuts", default="0,3.58,8.75,12.375,17.29,20.79,26.455")
    a = p.parse_args()
    cuts = [float(c) for c in a.cuts.split(",")]
    LEFT_IN, PULSE_IN, DINNER, CARD = cuts[1], cuts[2], cuts[6], a.card
    total = int(a.dur * SR)
    L, R = np.zeros(total), np.zeros(total)

    def add(sig, at, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= total or at < 0:
            return
        sig = sig[: total - i] * gain
        L[i:i + len(sig)] += sig * (1 - max(0, pan))
        R[i:i + len(sig)] += sig * (1 + min(0, pan))

    chords = [(45, 52, 57, 60), (41, 48, 53, 57), (36, 43, 48, 52), (43, 50, 55, 59)]
    pads = [(57, 60, 64), (57, 60, 65), (55, 60, 64), (55, 59, 62)]
    # Melodia di destra in ottavi lenti: una figura che si ripete e cambia di poco.
    figure = [(0, 76), (1, 72), (1.5, 69), (2, 72), (3, 74)]
    figure_b = [(0, 77), (1, 72), (1.5, 69), (2, 76), (3, 74)]

    n_bars = int(np.ceil(CARD / BAR))
    for b in range(n_bars):
        start = b * BAR
        ch = chords[b % 4]
        up = 12 if start >= DINNER - 0.01 else 0
        for beat, n in (figure if b % 2 == 0 else figure_b):
            t0 = start + beat * BEAT
            if t0 < CARD:
                add(piano(midi(n + up), 2.2), t0, gain=0.22 if beat == 0 else 0.16, pan=0.15)
        if start + BAR > LEFT_IN:
            for j, n in enumerate(ch):
                t0 = start + j * 0.06
                if LEFT_IN <= t0 < CARD:
                    add(piano(midi(n), BAR, soft=0.6), t0, gain=0.13, pan=-0.2)
        if PULSE_IN <= start + BAR and start < CARD:
            s0 = max(start, PULSE_IN)
            g = 0.16 if start >= DINNER - 0.01 else 0.09
            add(strings([midi(n) for n in pads[b % 4]], min(BAR + 1.5, CARD + 1.0 - s0)), s0 - 0.3, gain=g)
            for q in (0, 2):
                tq = start + q * BEAT
                if PULSE_IN <= tq < CARD:
                    add(thump(), tq, gain=0.30)

    rest = a.dur - CARD
    add(strings([midi(n) for n in (48, 55, 60, 64, 67)], rest + 0.5, attack=0.4, release=0.2), CARD - 0.3, gain=0.2)
    for j, n in enumerate((36, 48, 55, 60, 64)):
        add(piano(midi(n), rest, soft=0.7), CARD + j * 0.07, gain=0.2, pan=-0.2 + 0.1 * j)
    for k, n in enumerate((79, 76, 84)):
        add(piano(midi(n), 3.0), CARD + 1.2 + k * 1.3, gain=0.16, pan=0.2)

    mix = np.stack([room(room(L)), room(room(R))], axis=1)
    mix /= np.max(np.abs(mix)) / 0.85
    fade = int(2.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 1.5
    mix[: int(0.2 * SR)] *= np.linspace(0, 1, int(0.2 * SR))[:, None]
    wavfile.write(a.out, SR, (mix * 32767).astype(np.int16))
    print(a.out)


if __name__ == "__main__":
    main()
