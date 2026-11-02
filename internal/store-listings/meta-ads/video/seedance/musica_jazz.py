"""Colonna sonora lounge jazz dello spot, alternativa a musica_spot.py, composta
qui: nessun diritto di terzi. Stessi argomenti, stessi attacchi sugli stacchi.

80 BPM in swing (una battuta = 3 s), Fa maggiore, Fa maj9 – Re m9 – Sol m9 – Do13:

- 0 s     piano elettrico da solo, accordi sincopati;
- 3,6 s   entra il contrabbasso che cammina;
- 8,75 s  spazzole e piatto ride in swing;
- cena    il vibrafono accenna una melodia;
- chiusura: Fa maj9 tenuto sotto logo e frase, sfuma negli ultimi 2,5 s.

Uso: python3 musica_jazz.py musica.wav --dur 34.6 --card 29.6 \\
         --cuts 0,3.58,8.75,12.375,17.29,20.79,26.455
"""
import argparse

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 48000
BEAT = 60 / 80
BAR = 4 * BEAT
SWING = BEAT * 2 / 3  # l'«e» in swing cade a due terzi del quarto
rng = np.random.default_rng(23)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lowpass(x, hz):
    b, a = butter(2, hz / (SR / 2))
    return lfilter(b, a, x)


def highpass(x, hz):
    b, a = butter(2, hz / (SR / 2), btype="high")
    return lfilter(b, a, x)


def bandpass(x, lo, hi):
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def rhodes(freq, dur):
    """Piano elettrico: FM morbida con tremolo leggero."""
    t = np.arange(int(dur * SR)) / SR
    idx = 1.1 * np.exp(-t * 4)
    tone = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * t))
    tone += 0.15 * np.sin(2 * np.pi * 2 * freq * t) * np.exp(-t * 6)
    trem = 1 + 0.12 * np.sin(2 * np.pi * 4.5 * t)
    rel = np.minimum(1, (dur - t) / 0.12)
    return tone * trem * np.minimum(1, t / 0.006) * np.exp(-t * 1.1) * np.clip(rel, 0, 1)


def vibes(freq, dur):
    t = np.arange(int(dur * SR)) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * 4 * freq * t) * np.exp(-t * 8)
    trem = 1 + 0.25 * np.sin(2 * np.pi * 5.5 * t)
    return tone * trem * np.minimum(1, t / 0.003) * np.exp(-t * 1.6)


def upright(freq, dur):
    """Contrabbasso pizzicato: attacco col «tump», coda breve."""
    t = np.arange(int(dur * SR)) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.45 * np.sin(4 * np.pi * freq * t) + 0.15 * np.sin(6 * np.pi * freq * t)
    thump = np.sin(2 * np.pi * freq * 0.5 * t) * np.exp(-t * 40)
    env = np.minimum(1, t / 0.008) * np.exp(-t * 2.2) * np.clip(np.minimum(1, (dur - t) / 0.05), 0, 1)
    return lowpass(tone * env + 0.4 * thump, 1200)


def ride():
    t = np.arange(int(0.9 * SR)) / SR
    metal = sum(np.sin(2 * np.pi * f * t) for f in (3150, 4270, 5340, 6890)) / 4
    noise = highpass(rng.uniform(-1, 1, len(t)), 5000)
    return (0.5 * metal + noise) * np.exp(-t * 5) * np.minimum(1, t / 0.002)


def brush():
    """Colpo di spazzola sul rullante: rumore morbido con un attacco lento."""
    t = np.arange(int(0.28 * SR)) / SR
    noise = bandpass(rng.uniform(-1, 1, len(t)), 1500, 7000)
    return noise * np.minimum(1, t / 0.03) * np.exp(-t * 14)


def feather():
    t = np.arange(int(0.3 * SR)) / SR
    f = 45 + 40 * np.exp(-t * 25)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 12)


def room(x):
    """Un po' d'ambiente: tre echi corti e smorzati, come una sala piccola."""
    out = x.copy()
    for ms, g in ((23, 0.35), (37, 0.28), (61, 0.2), (89, 0.14)):
        d = int(ms * SR / 1000)
        out[d:] += g * lowpass(x[:-d], 4000)
    return out


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

    # Voci senza fondamentale (la fa il contrabbasso), come in un trio.
    chords = [(57, 60, 64, 67), (53, 57, 60, 64), (58, 62, 65, 69), (58, 62, 64, 69)]
    roots = [41, 38, 43, 36]
    # Camminata: fondamentale, terza o quinta, poi avvicinamento cromatico.
    walks = [(41, 45, 48, 39), (38, 41, 45, 42), (43, 46, 50, 37), (36, 40, 43, 40)]
    # Ritmo del piano per battuta: (quarto, in levare?, durata in quarti).
    comp = [(0, False, 1.6), (1, True, 0.5), (3, True, 1.2)]
    melody = [(0, 72), (1, 74), (1.67, 77), (3, 76), (5, 74), (6, 72), (6.67, 69)]

    n_bars = int(np.ceil(CARD / BAR))
    for b in range(n_bars):
        start = b * BAR
        ch, walk = chords[b % 4], walks[b % 4]
        for q, off, d in comp:
            t0 = start + q * BEAT + (SWING if off else 0)
            if t0 >= CARD:
                continue
            for j, n in enumerate(ch):
                add(rhodes(midi(n), d * BEAT), t0 + j * 0.012, gain=0.11, pan=-0.25 + 0.12 * j)
        for q in range(4):
            tq = start + q * BEAT
            if BASS_IN <= tq < CARD:
                add(upright(midi(walk[q]), BEAT * 0.95), tq, gain=0.42 if q == 0 else 0.34)
            if BEAT_IN <= tq < CARD:
                add(ride(), tq, gain=0.07, pan=0.35)
                if q in (1, 3):
                    add(ride(), tq + SWING, gain=0.045, pan=0.35)
                    add(brush(), tq, gain=0.16, pan=-0.1)
                if q in (0, 2):
                    add(feather(), tq, gain=0.22)
        if start >= DINNER - BAR and b % 2 == 0:
            for beat, n in melody:
                t0 = start + beat * BEAT
                if DINNER <= t0 < CARD:
                    add(vibes(midi(n), 1.4), t0, gain=0.10, pan=0.25)

    # Chiusura: Fa maj9 tenuto, il contrabbasso sul Fa, il vibrafono che sale.
    rest = a.dur - CARD
    for j, n in enumerate((57, 60, 64, 67, 72)):
        add(rhodes(midi(n), rest + 0.5), CARD + j * 0.05, gain=0.22, pan=-0.3 + 0.15 * j)
    add(upright(midi(29), 2.5), CARD, gain=0.5)
    t0, k = CARD + BEAT, 0
    while t0 < a.dur - 0.8:
        add(vibes(midi((69, 72, 76, 79, 81, 79)[k % 6]), 1.8), t0, gain=0.14, pan=0.2)
        t0, k = t0 + BEAT, k + 1
    t0 = CARD
    while t0 < a.dur - 1.5:
        add(ride(), t0, gain=0.04, pan=0.35)
        t0 += BEAT

    mix = np.stack([room(L), room(R)], axis=1)
    mix = lowpass(mix.T, 12000).T
    mix /= np.max(np.abs(mix)) / 0.85
    fade = int(2.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 1.5
    mix[: int(0.3 * SR)] *= np.linspace(0, 1, int(0.3 * SR))[:, None]
    wavfile.write(a.out, SR, (mix * 32767).astype(np.int16))
    print(a.out)


if __name__ == "__main__":
    main()
