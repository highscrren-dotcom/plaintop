#!/usr/bin/env python3
"""Reminder sounds for plaincalendar — the generator.

Writes package/contents/sounds/*.wav next to this file (the widget plays those files; they
are committed, not built at install time), so after an edit here run

    python3 calendar/sounds.py

from the repository root and commit the files. No dependencies beyond the standard
library; the output is deterministic, so a second run changes nothing. `--show` prints
each sound's length and peak.

The sounds are the plain kind the widgets look like: short synthetic tones, as a terminal
or a pager makes them — no samples, no music. Each tone has a few milliseconds of attack
and a smooth release so it never clicks, the square-ish ones are built from their first odd
harmonics only (no aliasing hiss), and the peak stays near -10 dBFS: a reminder should be
heard, not jump at you. 44.1 kHz, 16-bit, mono — pw-play and paplay both take WAV.
"""
import math
import os
import struct
import sys
import wave

RATE = 44100
PEAK = 0.32                 # of full scale, about -10 dBFS
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "package", "contents", "sounds")


def tone(freq, length, harmonics=(1,), attack=0.004, release=0.06, decay=None):
    """One tone as samples in -1..1: the sum of the given odd harmonics (1/n each), an
    attack and a release ramp, and an exponential decay with the given time constant."""
    n = int(RATE * length)
    weights = [1.0 / h for h in harmonics]
    norm = sum(weights)
    out = []
    for i in range(n):
        t = i / RATE
        v = sum(w * math.sin(2 * math.pi * freq * h * t) for h, w in zip(harmonics, weights)) / norm
        env = min(1.0, t / attack) if attack > 0 else 1.0
        left = length - t
        if left < release:
            env *= max(0.0, left / release) ** 2
        if decay:
            env *= math.exp(-t / decay)
        out.append(v * env)
    return out


def silence(length):
    return [0.0] * int(RATE * length)


def mix(*parts):
    """Lay (start, samples) parts over each other."""
    end = max(int(RATE * s) + len(p) for s, p in parts)
    out = [0.0] * end
    for s, p in parts:
        o = int(RATE * s)
        for i, v in enumerate(p):
            out[o + i] += v
    return out


SQUARE = (1, 3, 5)          # a soft square: the first three odd harmonics

SOUNDS = {
    # A terminal's BEL: one plain sine.
    "bell": lambda: tone(880, 0.22, release=0.12, decay=0.12),
    # Two short square-ish blips, as an old handheld beeps.
    "blip": lambda: tone(1320, 0.06, SQUARE, release=0.02) + silence(0.06) + tone(1320, 0.06, SQUARE, release=0.02),
    # Two tones down a fifth, ringing out.
    "chime": lambda: mix((0.0, tone(1046.5, 0.6, release=0.3, decay=0.25)),
                         (0.18, tone(784.0, 0.8, release=0.4, decay=0.3))),
    # A pager's three quick beeps.
    "pager": lambda: sum((tone(2000, 0.07, SQUARE, release=0.02) + silence(0.05) for _ in range(3)), []),
    # Two dry ticks, a clock's.
    "tick": lambda: tone(1500, 0.03, (1, 3), attack=0.001, release=0.025, decay=0.012) + silence(0.12)
                    + tone(1500, 0.03, (1, 3), attack=0.001, release=0.025, decay=0.012),
}


def write(name, samples):
    top = max(1e-9, max(abs(v) for v in samples))
    scale = PEAK / top
    frames = b"".join(struct.pack("<h", int(round(v * scale * 32767))) for v in samples)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    return path, len(samples) / RATE


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in SOUNDS.items():
        path, length = write(name, make())
        if "--show" in sys.argv:
            print(f"{name:6} {length:.2f} s  {os.path.getsize(path):6} bytes  peak {20 * math.log10(PEAK):.1f} dBFS")
    print(f"  ✓ {len(SOUNDS)} sounds → {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
