#!/usr/bin/env python3
"""Generate procedural sound effects as WAVs (stdlib only, no numpy).

Same philosophy as gen_pixel_art.py: assets are code. Rerun after tweaking:
  python3 tools/gen_sfx.py
Output goes to assets/sfx/. Deterministic (seeded RNG) so rebuilds are
byte-identical.
"""
import math
import os
import random
import struct
import wave

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
RATE = 22050

rng = random.Random(1177)


def write_wav(name: str, samples: list[float]) -> None:
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000))
        f.writeframes(bytes(frames))


def env(i: int, n: int, attack: float = 0.01, curve: float = 2.0) -> float:
    """Attack + power-decay envelope, 0..1."""
    t = i / n
    a = min(1.0, t / max(attack, 1e-6))
    return a * (1.0 - t) ** curve


def sine_sweep(dur: float, f0: float, f1: float, curve: float = 2.0, vol: float = 0.8):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * env(i, n, curve=curve) * vol)
    return out


def square_sweep(dur: float, f0: float, f1: float, vol: float = 0.5):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        phase += f / RATE
        out.append((1.0 if (phase % 1.0) < 0.5 else -1.0) * env(i, n) * vol)
    return out


def noise_burst(dur: float, vol: float = 0.7, curve: float = 3.0, lowpass: float = 0.3):
    """Decaying filtered noise (one-pole lowpass, `lowpass` = smoothing 0..1)."""
    n = int(RATE * dur)
    out, prev = [], 0.0
    for i in range(n):
        prev += lowpass * (rng.uniform(-1, 1) - prev)
        out.append(prev * env(i, n, curve=curve) * vol)
    return out


def tone(dur: float, freq: float, vol: float = 0.6, harmonics=((1, 1.0),), curve: float = 2.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * freq * h * t) for h, a in harmonics)
        out.append(s * env(i, n, curve=curve) * vol)
    return out


def mix(*layers):
    n = max(len(x) for x in layers)
    return [sum(x[i] if i < len(x) else 0.0 for x in layers) for i in range(n)]


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)

    # Harpoon shot: short pressured "thunk" with a click
    write_wav("shoot.wav", mix(
        square_sweep(0.09, 340, 120, vol=0.35),
        noise_burst(0.05, vol=0.25, lowpass=0.6),
    ))

    # Flesh hit: dull thud
    write_wav("hit.wav", mix(
        noise_burst(0.07, vol=0.5, lowpass=0.25),
        sine_sweep(0.07, 210, 90, vol=0.4),
    ))

    # Kill pop: satisfying bloop
    write_wav("kill.wav", sine_sweep(0.14, 320, 55, curve=1.6, vol=0.75))

    # Gem pickup: bright rising chirp
    write_wav("pickup.wav", sine_sweep(0.09, 620, 1250, curve=1.2, vol=0.4))

    # Crate secured: metallic clank
    write_wav("crate.wav", mix(
        tone(0.28, 480, vol=0.45, harmonics=((1, 1.0), (2.76, 0.55), (5.4, 0.3)), curve=3.5),
        noise_burst(0.04, vol=0.3, lowpass=0.7),
    ))

    # Level up: two-note chime
    write_wav("levelup.wav", seq(
        tone(0.12, 660, vol=0.4, harmonics=((1, 1.0), (2, 0.3))),
        tone(0.22, 990, vol=0.45, harmonics=((1, 1.0), (2, 0.3))),
    ))

    # Depth charge: deep muffled boom
    write_wav("explosion.wav", mix(
        noise_burst(0.5, vol=0.8, lowpass=0.12, curve=2.2),
        sine_sweep(0.45, 110, 35, vol=0.9, curve=1.8),
    ))

    # Sonar: classic ping with a tail
    write_wav("sonar.wav", mix(
        sine_sweep(0.5, 1180, 1120, curve=4.0, vol=0.35),
        sine_sweep(0.5, 2360, 2240, curve=5.0, vol=0.12),
    ))

    # Diver down: urgent two-tone alarm
    write_wav("downed.wav", seq(
        tone(0.16, 520, vol=0.5, curve=1.0),
        tone(0.16, 392, vol=0.5, curve=1.0),
        tone(0.16, 520, vol=0.5, curve=1.0),
        tone(0.24, 392, vol=0.5, curve=1.5),
    ))

    # Revive: rising triad
    write_wav("revive.wav", seq(
        tone(0.1, 523, vol=0.4),
        tone(0.1, 659, vol=0.4),
        tone(0.26, 784, vol=0.45),
    ))

    # Dive bell arrival: big metallic ring
    write_wav("bell.wav", tone(
        0.9, 220, vol=0.6,
        harmonics=((1, 1.0), (2.4, 0.5), (4.2, 0.35), (6.8, 0.2)),
        curve=2.4,
    ))

    # Extraction: victory arp
    write_wav("extract.wav", seq(
        tone(0.11, 523, vol=0.42),
        tone(0.11, 659, vol=0.42),
        tone(0.11, 784, vol=0.42),
        tone(0.38, 1046, vol=0.48, harmonics=((1, 1.0), (2, 0.25))),
    ))

    # Defeat: low sagging drone
    write_wav("defeat.wav", mix(
        sine_sweep(1.0, 160, 55, curve=1.2, vol=0.5),
        sine_sweep(1.0, 80, 40, curve=1.2, vol=0.4),
    ))

    # Rock dig: short gravelly crunch
    write_wav("dig.wav", mix(
        noise_burst(0.08, vol=0.55, lowpass=0.18, curve=2.0),
        sine_sweep(0.08, 140, 70, vol=0.3),
    ))

    # Oxygen warning: sharp double beep
    write_wav("warning.wav", seq(
        tone(0.09, 880, vol=0.4, curve=1.0),
        [0.0] * int(RATE * 0.06),
        tone(0.09, 880, vol=0.4, curve=1.0),
    ))

    # Ambient bed: 4s loopable deep-water drone (brown-ish noise + slow swell)
    n = int(RATE * 4.0)
    amb, prev = [], 0.0
    for i in range(n):
        prev += 0.02 * (rng.uniform(-1, 1) - prev)
        swell = 0.6 + 0.4 * math.sin(2 * math.pi * i / n)  # period = loop length
        lfo = math.sin(2 * math.pi * 0.5 * i / RATE + math.sin(2 * math.pi * i / n))
        amb.append((prev * 2.2 + 0.05 * lfo) * swell * 0.5)
    write_wav("ambient.wav", amb)

    print(f"Wrote 16 sfx to {os.path.normpath(OUT_DIR)}")


if __name__ == "__main__":
    main()
