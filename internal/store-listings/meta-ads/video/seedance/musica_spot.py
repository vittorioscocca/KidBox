"""Colonna sonora dello spot Seedance, composta qui: nessun diritto di terzi.

La musica generata da Seedance è quasi solo ambiente (a tratti sotto i -30 dB),
quindi lo spot usa questa base continua, senza buchi. 90 BPM (una battuta =
2,67 s), Do maggiore, Do – Lam – Fa – Sol:

- 0 s     tappeto e piano elettrico in arpeggio, leggeri (la corsa del mattino);
- 3,6 s   entra il basso (il calendario: le cose si mettono a posto);
- 8,75 s  entra un ritmo morbido (lista, scuola, salute, assistente);
- 25,3 s  la cena: il ritmo si apre, il piano sale di ottava;
- chiusura: accordo di Do tenuto sotto logo e frase, sfuma negli ultimi 2,5 s.

Gli attacchi seguono gli stacchi dello spot: `--cuts` sono gli stessi di
finale.py, `--card` è l'istante in cui comincia la chiusura (finale.py la
chiama da sé con i valori giusti).

Uso: python3 musica_spot.py musica-spot.wav --dur 33.47 --card 28.44 \
         --cuts 0,3.58,8.75,12.375,17.29,19.625,25.29
"""
import argparse

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 48000
BEAT = 60 / 90
BAR = 4 * BEAT
rng = np.random.default_rng(11)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lowpass(x, hz):
    b, a = butter(2, hz / (SR / 2))
    return lfilter(b, a, x)


def highpass(x, hz):
    b, a = butter(2, hz / (SR / 2), btype="high")
    return lfilter(b, a, x)


def epiano(freq, dur):
    """Piano elettrico in FM: attacco morbido, coda che si spegne."""
    t = np.arange(int(dur * SR)) / SR
    idx = 1.6 * np.exp(-t * 3)
    tone = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * t))
    return tone * np.minimum(1, t / 0.004) * np.exp(-t * 1.8)


def pad(freqs, dur, attack=0.9, release=1.2):
    t = np.arange(int(dur * SR)) / SR
    x = np.zeros_like(t)
    for f in freqs:
        for det in (-0.12, 0.0, 0.12):
            ph = rng.uniform(0, 1)
            x += 2 * (((f * 2 ** (det / 12)) * t + ph) % 1) - 1
    x = lowpass(x, 1100) / (3 * len(freqs))
    e = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / release)
    return x * np.clip(e, 0, 1)


def bass(freq, dur):
    t = np.arange(int(dur * SR)) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.2 * np.sin(4 * np.pi * freq * t)
    return tone * np.minimum(1, t / 0.02) * np.exp(-t * 1.2) * np.minimum(1, (dur - t) / 0.08)


def kick():
    t = np.arange(int(0.35 * SR)) / SR
    f = 48 + 70 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)


def snap():
    t = np.arange(int(0.15 * SR)) / SR
    return highpass(rng.uniform(-1, 1, len(t)), 1500) * np.exp(-t * 35)


def shaker():
    t = np.arange(int(0.05 * SR)) / SR
    return highpass(rng.uniform(-1, 1, len(t)), 6000) * np.exp(-t * 80)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--dur", type=float, default=33.47)
    p.add_argument("--card", type=float, default=28.44)
    p.add_argument("--cuts", default="0,3.58,8.75,12.375,17.29,19.625,25.29")
    a = p.parse_args()
    cuts = [float(c) for c in a.cuts.split(",")]
    BASS_IN, BEAT_IN, DINNER, CARD = cuts[1], cuts[2], cuts[6], a.card
    total = int(a.dur * SR)
    L, R = np.zeros(total), np.zeros(total)

    def add(sig, at, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= total:
            return
        sig = sig[: total - i] * gain
        L[i:i + len(sig)] += sig * (1 - max(0, pan))
        R[i:i + len(sig)] += sig * (1 + min(0, pan))

    chords = [(60, 64, 67, 71), (57, 60, 64, 67), (53, 57, 60, 64), (55, 59, 62, 65)]
    roots = [36, 33, 29, 31]
    arp = [0, 2, 1, 3, 2, 1, 3, 2]

    n_bars = int(np.ceil(CARD / BAR))
    for b in range(n_bars):
        start = b * BAR
        if start >= CARD:
            break
        ch, root = chords[b % 4], roots[b % 4]
        # Il tappeto si sovrappone alla battuta dopo: nessun istante vuoto.
        add(pad([midi(n) for n in ch], BAR + 1.0), start, gain=0.20)
        up = 12 if start >= DINNER - 0.01 else 0
        for k, j in enumerate(arp):
            t0 = start + k * BEAT / 2
            if t0 >= CARD:
                break
            add(epiano(midi(ch[j] + 12 + up), 1.2), t0, gain=0.11 if k % 2 else 0.15, pan=-0.35 + 0.1 * j)
        if start + BAR > BASS_IN:
            for q in (0, 2):
                tq = start + q * BEAT
                if BASS_IN <= tq < CARD:
                    add(bass(midi(root + 12), 2 * BEAT), tq, gain=0.34)
        for q in range(4):
            tq = start + q * BEAT
            if BEAT_IN <= tq < CARD:
                add(kick(), tq, gain=0.42 if q % 2 == 0 else 0.22)
                if q % 2 == 1:
                    add(snap(), tq, gain=0.10, pan=0.15)
                for e in range(2):
                    add(shaker(), tq + e * BEAT / 2, gain=0.05 if tq < DINNER else 0.07, pan=-0.4)

    # Chiusura: Do tenuto sotto logo e frase.
    rest = a.dur - CARD
    add(pad([midi(n) for n in (48, 55, 60, 64, 67)], rest + 0.5, attack=0.3, release=0.1), CARD - 0.3, gain=0.55)
    for j, n in enumerate((60, 64, 67, 72, 76)):
        add(epiano(midi(n + 12), rest), CARD + j * 0.12, gain=0.2, pan=-0.3 + 0.15 * j)
    add(bass(midi(36), rest), CARD, gain=0.45)
    # Il piano continua ad arpeggiare piano sotto la chiusura, fino alla sfumata.
    t0, k = CARD + BEAT, 0
    while t0 < a.dur - 0.5:
        add(epiano(midi((72, 76, 79, 84, 79, 76)[k % 6]), 1.5), t0, gain=0.13, pan=-0.2 + 0.08 * (k % 6))
        t0, k = t0 + BEAT / 2, k + 1

    mix = np.stack([L, R], axis=1)
    mix /= np.max(np.abs(mix)) / 0.85
    fade = int(2.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 1.5
    mix[: int(0.3 * SR)] *= np.linspace(0, 1, int(0.3 * SR))[:, None]
    wavfile.write(a.out, SR, (mix * 32767).astype(np.int16))
    print(a.out)


if __name__ == "__main__":
    main()
