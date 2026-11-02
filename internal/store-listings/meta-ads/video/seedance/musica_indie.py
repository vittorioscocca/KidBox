"""Colonna sonora «indie pop solare», come gli spot Apple sulle funzioni:
battimani, chitarrina pizzicata, campanelle, un fischio che fa il motivo.
Composta qui, nessun diritto di terzi; stessi argomenti di musica_spot.py.

112 BPM, Sol maggiore (Sol – Re – Mim – Do):

- 0 s     chitarrina pizzicata e campanelle, leggere;
- 3,6 s   basso e battimani sul 2 e sul 4;
- 8,75 s  cassa in quattro e il fischio col motivo;
- cena    tutto aperto, il motivo all'ottava;
- chiusura: accordo di Sol tenuto, campanelle che scendono, sfuma.

Uso: python3 musica_indie.py musica.wav --dur 34.6 --card 29.6 \\
         --cuts 0,3.58,8.75,12.375,17.29,20.79,26.455
"""
import argparse

import numpy as np
from scipy.io import wavfile

from musica_jazz import SR, lowpass, highpass, room, midi

BEAT = 60 / 112
BAR = 4 * BEAT
rng = np.random.default_rng(9)


def pluck(freq, dur):
    """Chitarrina: dente di sega filtrato che si chiude in fretta."""
    t = np.arange(int(dur * SR)) / SR
    saw = 2 * ((freq * t) % 1) - 1
    bright = lowpass(saw, 2600) * np.exp(-t * 9) + lowpass(saw, 900) * np.exp(-t * 4) * 0.6
    return bright * np.minimum(1, t / 0.002)


def glock(freq, dur):
    t = np.arange(int(dur * SR)) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.4 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 9)
    return tone * np.exp(-t * 2.5) * np.minimum(1, t / 0.001)


def whistle(freq, dur):
    t = np.arange(int(dur * SR)) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.25)
    tone = np.sin(2 * np.pi * np.cumsum(np.full(len(t), freq) * vib) / SR)
    breath = highpass(rng.uniform(-1, 1, len(t)), 3000) * 0.04
    e = np.clip(np.minimum(t / 0.04, (dur - t) / 0.08), 0, 1)
    return (tone + breath) * e


def bass(freq, dur):
    t = np.arange(int(dur * SR)) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(4 * np.pi * freq * t)
    return tone * np.minimum(1, t / 0.005) * np.exp(-t * 3) * np.clip(np.minimum(1, (dur - t) / 0.03), 0, 1)


def kick():
    t = np.arange(int(0.3 * SR)) / SR
    f = 50 + 80 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11)


def clap():
    t = np.arange(int(0.2 * SR)) / SR
    n = highpass(rng.uniform(-1, 1, len(t)), 1000)
    bursts = sum(np.exp(-np.maximum(0, t - d) * 60) * (t >= d) for d in (0, 0.011, 0.023))
    return n * bursts * np.exp(-t * 18)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--dur", type=float, default=34.6)
    p.add_argument("--card", type=float, default=29.6)
    p.add_argument("--cuts", default="0,3.58,8.75,12.375,17.29,20.79,26.455")
    a = p.parse_args()
    cuts = [float(c) for c in a.cuts.split(",")]
    BASS_IN, BEAT_IN, DINNER, CARD = cuts[1], cuts[2], cuts[6], a.card
    total = int(a.dur * SR)
    L, R = np.zeros(total), np.zeros(total)

    def add(sig, at, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= total or at < 0:
            return
        sig = sig[: total - i] * gain
        L[i:i + len(sig)] += sig * (1 - max(0, pan))
        R[i:i + len(sig)] += sig * (1 + min(0, pan))

    chords = [(55, 59, 62), (50, 54, 57), (52, 55, 59), (48, 52, 55)]
    roots = [43, 38, 40, 36]
    strum = [0, 0.75, 1.5, 2, 2.75, 3.5]  # in quarti: il ritmo della chitarrina
    # Il motivo del fischio, su due battute.
    motif = [(0, 74, 0.5), (0.5, 76, 0.5), (1, 79, 1.0), (2.5, 76, 0.5), (3, 74, 1.0),
             (4.5, 71, 0.5), (5, 74, 1.0), (6, 76, 1.5)]

    n_bars = int(np.ceil(CARD / BAR))
    for b in range(n_bars):
        start = b * BAR
        ch, root = chords[b % 4], roots[b % 4]
        dinner = start >= DINNER - 0.01
        for k, q in enumerate(strum):
            t0 = start + q * BEAT
            if t0 < CARD:
                for j, n in enumerate(ch):
                    add(pluck(midi(n + 12), 0.4), t0 + j * 0.007, gain=0.09 if k % 3 else 0.12, pan=-0.35)
        if b % 2 == 1 and start < CARD:
            add(glock(midi(ch[2] + 24), 1.0), start + 3 * BEAT, gain=0.10, pan=0.4)
        for q in range(4):
            tq = start + q * BEAT
            if not (tq < CARD):
                continue
            if tq >= BASS_IN:
                add(bass(midi(root), BEAT * (1.5 if q == 0 else 0.9)), tq + (0 if q != 3 else BEAT / 2), gain=0.36)
                if q in (1, 3):
                    add(clap(), tq, gain=0.20, pan=0.1)
            if tq >= BEAT_IN:
                add(kick(), tq, gain=0.45 if q % 2 == 0 else 0.32)
        if start >= BEAT_IN - BAR and b % 2 == (int(BEAT_IN / BAR) % 2):
            for beat, n, d in motif:
                t0 = start + beat * BEAT
                if BEAT_IN <= t0 < CARD:
                    add(whistle(midi(n + (12 if dinner else 0)), d * BEAT * 0.95), t0, gain=0.11, pan=0.15)

    rest = a.dur - CARD
    for j, n in enumerate((43, 55, 59, 62, 67)):
        add(pluck(midi(n + 12), rest), CARD + j * 0.03, gain=0.18, pan=-0.3)
    add(bass(midi(31), rest), CARD, gain=0.4)
    for k, n in enumerate((91, 86, 83, 79, 74)):
        add(glock(midi(n), 2.0), CARD + 0.5 + k * BEAT, gain=0.16, pan=0.3)
    t0 = CARD
    while t0 < a.dur - 1.5:
        for j, n in enumerate((55, 59, 62)):
            add(pluck(midi(n + 12), 0.5), t0 + j * 0.007, gain=0.13, pan=-0.35)
        t0 += BEAT

    mix = np.stack([room(L), room(R)], axis=1)
    mix /= np.max(np.abs(mix)) / 0.85
    fade = int(2.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 1.5
    mix[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))[:, None]
    wavfile.write(a.out, SR, (mix * 32767).astype(np.int16))
    print(a.out)


if __name__ == "__main__":
    main()
