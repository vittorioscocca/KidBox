"""Base musicale del video «Chi prende Marco giovedì?», composta qui: nessun
diritto di terzi. 15 s, 133 BPM (una battuta = 1,8 s), Do maggiore.

Le prime due battute (0–3,6 s) sono leggere, solo pizzicato e campanella; al
tap su «Ci penso io» (3,6 s) entrano basso e ritmo; da 12,6 s l'accordo finale
sfuma sotto la chiusura. Un «tic» marca il tap.

Uso: python3 music.py out/musica.wav
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 48000
DUR = 15.0
BEAT = 0.45
BAR = 4 * BEAT
TAP = 3.6
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, a=0.005, d=0.3, s=0.0, r=0.05, length=None):
    length = length or n
    t = np.arange(n) / SR
    e = np.minimum(1, t / a) * (s + (1 - s) * np.exp(-t / d))
    rel = int(r * SR)
    if rel and n > rel:
        e[-rel:] *= np.linspace(1, 0, rel)
    return e


def pluck(freq, dur, bright=0.5):
    """Karplus-Strong: corda pizzicata, suono da ukulele."""
    n = int(dur * SR)
    p = int(SR / freq)
    buf = rng.uniform(-1, 1, p)
    out = np.empty(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = 0.996 * (bright * buf[i % p] + (1 - bright) * buf[(i + 1) % p] + buf[i % p]) / 2
    return out * env(n, d=0.6)


def bell(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 6)
    return tone * env(n, a=0.002, d=0.45)


def bass(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * 2 * freq * t)
    return tone * env(n, a=0.01, d=0.35, s=0.25, r=0.04)


def kick():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 12)


def lowpass(x, hz):
    b, a = butter(2, hz / (SR / 2))
    return lfilter(b, a, x)


def highpass(x, hz):
    b, a = butter(2, hz / (SR / 2), btype="high")
    return lfilter(b, a, x)


def clap():
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    noise = highpass(rng.uniform(-1, 1, n), 900)
    return noise * np.exp(-t * 28)


def shaker():
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    return highpass(rng.uniform(-1, 1, n), 5000) * np.exp(-t * 70)


def tic():
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 1760 * t) + 0.5 * np.sin(2 * np.pi * 2640 * t)) * np.exp(-t * 45)


def main():
    out = sys.argv[1]
    total = int(DUR * SR)
    L = np.zeros(total)
    R = np.zeros(total)

    def add(sig, at, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= total:
            return
        sig = sig[: total - i] * gain
        L[i:i + len(sig)] += sig * (1 - max(0, pan))
        R[i:i + len(sig)] += sig * (1 + min(0, pan))

    # Do – Sol – Lam – Fa, una battuta ciascuno.
    chords = [(60, 64, 67), (55, 59, 62), (57, 60, 64), (53, 57, 60)]
    roots = [36, 43, 45, 41]
    # Campanella: un motivo pentatonico che risponde alla domanda.
    motif = [(0, 76), (1, 79), (2, 81), (3, 79), (6, 76), (7, 74)]

    n_bars = 7  # 0–12,6 s
    for b in range(n_bars):
        start = b * BAR
        ch, root = chords[b % 4], roots[b % 4]
        # Pizzicato in ottavi, accento sull'1 e sul 3.
        for k in range(8):
            t0 = start + k * BEAT / 2
            for j, note in enumerate(ch):
                add(pluck(midi(note + 12), 0.5, bright=0.6), t0 + j * 0.008,
                    gain=(0.16 if k % 4 == 0 else 0.10), pan=(-0.3 + 0.3 * j))
        if b in (0, 1, 4, 5):
            for beat8, note in motif:
                add(bell(midi(note), 0.6), start + beat8 * BEAT / 2, gain=0.12, pan=0.2)
        if start >= TAP - 0.01:
            for q in range(4):
                add(bass(midi(root), BEAT * 0.9), start + q * BEAT, gain=0.32)
                add(kick(), start + q * BEAT, gain=(0.55 if q % 2 == 0 else 0.35))
                if q % 2 == 1:
                    add(clap(), start + q * BEAT, gain=0.18, pan=0.1)
            for e8 in range(8):
                add(shaker(), start + e8 * BEAT / 2 + 0.01, gain=0.07, pan=-0.4)

    # Accordo finale sotto la chiusura.
    end = n_bars * BAR
    for j, note in enumerate((48, 60, 64, 67, 72)):
        add(pluck(midi(note), DUR - end, bright=0.4), end + j * 0.03, gain=0.18, pan=(-0.4 + 0.2 * j))
    add(bell(midi(84), 1.5), end + 0.2, gain=0.12)
    add(bass(midi(36), 1.6), end, gain=0.3)

    add(tic(), TAP, gain=0.35)

    mix = np.stack([L, R], axis=1)
    mix = lowpass(mix.T, 14000).T
    fade = int(1.2 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    mix[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))[:, None]
    mix /= np.max(np.abs(mix)) / 0.85
    wavfile.write(out, SR, (mix * 32767).astype(np.int16))
    print(out)


if __name__ == "__main__":
    main()
