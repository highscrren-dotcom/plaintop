#!/usr/bin/env python3
"""Stand for win/service/bands.py: the spectrum analyzer behind the Windows service's
`/bands`, driven with synthetic signals — a frame's shape, cava's stereo order, where a
tone lands on the log scale, autosens, smoothing, the capture thread's timer, its sleep on
silence and its supervisor — and the relay's fold_mono/resample applied to its frames.

    python3 tests/win_bands.py

No sound card, no Windows, no HTTP: bands.py is imported and fed from generators. The
WASAPI backends themselves (soundcard, pyaudiowpatch) are not exercised here; the stand
only checks that importing the module does not import them.
"""
import importlib.util
import math
import random
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bands = load("bands", "win/service/bands.py")
relay = load("relay", "spectrum/relay.py")

random.seed(0)
np.random.seed(0)

RATE = 48000
BLOCK = RATE // 50
passed = 0


def ok(cond, what):
    global passed
    if not cond:
        print("  ✗ " + what)
        sys.exit(1)
    passed += 1


def tone(hz, amp, left=True, right=True, channels=2):
    """Blocks of a sine with continuous phase; a channel left out is exact zeros."""
    pos = [0]

    def gen(n):
        t = (pos[0] + np.arange(n)) / RATE
        pos[0] += n
        s = (amp * np.sin(2 * np.pi * hz * t)).astype(np.float32)
        block = np.zeros((n, channels), np.float32)
        if left:
            block[:, 0] = s
        if right and channels > 1:
            block[:, 1] = s
        return block
    return gen


def run(analyzer, gen, frames, blocks_per_frame=2):
    """Push blocks and take frames as the capture thread would; the last frame comes back."""
    frame = None
    for _ in range(frames):
        for _ in range(blocks_per_frame):
            analyzer.push(gen(BLOCK))
        frame = analyzer.frame()
    return frame


def expected_band(hz):
    # The same log scale bands.py lays its bands on: equal steps from LOW_HZ to HIGH_HZ.
    return int(bands.BARS * math.log(hz / bands.LOW_HZ) / math.log(bands.HIGH_HZ / bands.LOW_HZ))


def test_import():
    ok("soundcard" not in sys.modules and "pyaudiowpatch" not in sys.modules,
       "importing bands.py imports no capture library")
    ok(bands.RANGE == 1000, "RANGE is cava's ascii_max_range")
    a = bands.Analyzer(RATE, 2)
    ok(20 <= a.size / RATE * 1000 <= 50, f"the FFT window is a few tens of ms: {a.size} samples")
    edges = bands.band_edges(bands.BARS, bands.LOW_HZ, bands.HIGH_HZ)
    ok(len(edges) == bands.BARS + 1 and abs(edges[0] - bands.LOW_HZ) < 1e-9
       and abs(edges[-1] - bands.HIGH_HZ) < 1e-6, "band edges run from low to high")
    ok(all(abs(a.band_of(edges[i]) - i) < 1e-6 for i in range(0, bands.BARS + 1, 17)),
       "band_of inverts the edges")
    owned = np.bincount(a._band_idx, minlength=a.bars)
    ok(owned.min() >= 1, "every band owns at least one bin: min " + str(owned.min()))
    print("  ✓ import: lazy backends, the log scale, every band with a bin")


def test_frame_shape():
    a = bands.Analyzer(RATE, 2)
    rng = np.random.default_rng(1)
    gen440 = tone(440.0, 0.3)

    def gen(n):
        return gen440(n) + (rng.standard_normal((n, 2)) * 0.01).astype(np.float32)
    frame = run(a, gen, 10)
    ok(isinstance(frame, list) and len(frame) == 2 * bands.BARS,
       f"a frame is 2 × BARS values: {len(frame)}")
    ok(all(type(v) is int for v in frame), "…all Python ints")
    ok(all(0 <= v <= 1000 for v in frame), "…each within 0..1000")
    ok(max(frame) > 0, "…and not all zero for a tone")
    print("  ✓ frame: 2 × BARS ints, 0..1000")


def test_silence():
    a = bands.Analyzer(RATE, 2)
    frame = run(a, lambda n: np.zeros((n, 2), np.float32), 5)
    ok(frame == [0] * (2 * bands.BARS), "digital silence is all zeros")
    ok(a.frame() == [0] * (2 * bands.BARS), "a frame before any sound is all zeros too")
    ok(a.gain == 1.0, "the gain holds in exact silence, as cava's does")
    mono = bands.Analyzer(RATE, 1)
    frame = run(mono, tone(1000.0, 0.3, channels=1), 10)
    half = len(frame) // 2
    ok(frame[:half] == frame[half:][::-1] and max(frame) > 0, "mono input is written to both halves")
    print("  ✓ silence: zeros; mono: both halves")


def test_tone_position():
    a = bands.Analyzer(RATE, 2)
    frame = run(a, tone(440.0, 0.3), 30)
    folded = relay.fold_mono(frame)
    ok(len(folded) == bands.BARS, "fold_mono halves the frame")
    peak = int(np.argmax(folded))
    want = expected_band(440.0)
    ok(abs(peak - want) <= 1, f"440 Hz peaks in band {peak}, the log scale says {want}")
    down, up = folded[expected_band(110.0)], folded[expected_band(1760.0)]
    ok(down < folded[peak] / 4 and up < folded[peak] / 4,
       f"two octaves away is under a quarter of the peak: {down}, {folded[peak]}, {up}")
    print(f"  ✓ 440 Hz: band {peak} of {bands.BARS}, two octaves away {down}/{up} against {folded[peak]}")


def test_cava_order():
    a = bands.Analyzer(RATE, 2)
    frame = run(a, tone(440.0, 0.3, left=True, right=False), 30)
    half = len(frame) // 2
    left, right = frame[:half], frame[half:]
    ok(max(left) > 100, "a tone on the left lands in the first half")
    ok(max(right) <= 10, "…and the right half is near zero: " + str(max(right)))
    folded_peak = int(np.argmax(relay.fold_mono(frame)))
    ok(half - 1 - int(np.argmax(left)) == folded_peak,
       "the first half is the left channel reversed: highest band first")
    ok(abs(folded_peak - expected_band(440.0)) <= 1, "…so folding puts the tone where it belongs")
    print("  ✓ cava's order: left from high to low, then right from low to high")


def test_levels_and_autosens():
    loud = bands.Analyzer(RATE, 2)
    quiet = bands.Analyzer(RATE, 2)
    loud_peak = max(run(loud, tone(1000.0, 0.5), 1))
    quiet_peak = max(run(quiet, tone(1000.0, 0.05), 1))
    ok(loud_peak > quiet_peak > 0, f"louder is higher at the same gain: {loud_peak} > {quiet_peak}")

    a = bands.Analyzer(RATE, 2)
    first = max(run(a, tone(1000.0, 0.1), 1))
    ok(first < 700, f"a -20 dBFS tone starts well under the top: {first}")
    gen = tone(1000.0, 0.1)
    for frames in range(1, 4 * bands.FPS + 1):
        peak = max(run(a, gen, 1))
        if peak >= 950:
            break
    ok(peak >= 950, f"autosens brings it near the top within a few seconds: {peak} after {frames} frames")
    ok(frames <= 3 * bands.FPS, f"…in {frames} frames, under three seconds' worth")
    steady = [max(run(a, gen, 1)) for _ in range(2 * bands.FPS)]
    ok(min(steady) >= 900, f"…and it stays there: min {min(steady)}")
    print(f"  ✓ autosens: {first} → {peak} in {frames} frames, steady above {min(steady)}")


def test_smoothing():
    # The mechanism, not the setting: with PLAINSPECTRUM_NOISE=0 in the environment a tone
    # switched off is meant to drop at once, so the check pins the relay's default of 60.
    a = bands.Analyzer(RATE, 2, noise=60)
    gen = tone(1000.0, 0.3)
    before = max(run(a, gen, 3 * bands.FPS))
    a.push(np.zeros((a.size, 2), np.float32))        # a whole window of silence at once
    decay = [max(a.frame()) for _ in range(6)]
    ok(0 < decay[0] < before, f"a tone switched off does not drop to zero at once: {before} → {decay[0]}")
    ok(all(decay[i] > decay[i + 1] for i in range(len(decay) - 1)), f"…it decays frame by frame: {decay}")
    for _ in range(3 * bands.FPS):
        last = a.frame()
    ok(last == [0] * (2 * bands.BARS), "…and reaches zero")
    print(f"  ✓ smoothing: {before} → {decay}")


def wait_for(cond, timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.05)
    return cond()


def test_capture_rate():
    backend = bands.SyntheticBackend(tone(1000.0, 0.3), rate=RATE)
    cap = bands.Capture(backend, sleep=5).start()
    try:
        ok(wait_for(lambda: cap.frames >= 3, 2.0), "the capture thread produces frames")
        start = cap.frames
        time.sleep(0.5)
        got = cap.frames - start
        low, high = int(bands.FPS * 0.5 * 0.5), int(bands.FPS * 0.5 * 1.7) + 1
        ok(low <= got <= high, f"about FPS frames a second: {got} in 0.5 s at {bands.FPS} fps")
        frame = cap.frame()
        ok(len(frame) == 2 * bands.BARS and max(frame) > 0, "frame() is the live frame")
        st = cap.state()
        ok(st["restarts"] == 0 and st["backend"] == "synthetic" and st["bars"] == bands.BARS
           and st["fps"] == bands.FPS and 0 <= st["age"] < 1 and st["frames"] == cap.frames,
           "state(): " + repr(st))
        ok(set(st) == {"frames", "restarts", "source", "age", "bars", "fps", "backend"},
           "state() has the relay's keys plus backend")
    finally:
        cap.stop()
    ok(not cap.alive(), "stop() ends the thread")
    print(f"  ✓ capture: {got} frames in 0.5 s, state {cap.state()}")


def test_capture_sleep():
    backend = bands.SyntheticBackend(lambda n: np.zeros((n, 2), np.float32), rate=RATE)
    cap = bands.Capture(backend, sleep=0.5).start()
    try:
        time.sleep(1.3)
        st1 = cap.state()
        ok(st1["frames"] > 0, "frames of zeros were computed before the silence timeout")
        ok(st1["age"] > 0.5, f"…then none: age {st1['age']}")
        ok(cap.frame() == [0] * (2 * bands.BARS), "frame() is zeros")
        time.sleep(1.2)
        st2 = cap.state()
        ok(st2["age"] > st1["age"] and st2["frames"] == st1["frames"], f"age keeps growing: {st2['age']}")
        ok(backend.opens >= 2 and backend.closes >= 1,
           f"asleep, the stream is closed and reopened once a second to listen: {backend.opens} opens")
        ok(cap.frame() == [0] * (2 * bands.BARS) and cap.alive(), "still zeros, thread alive")
    finally:
        cap.stop()
    print(f"  ✓ sleep on silence: age {st1['age']} → {st2['age']}, {backend.opens} probes")


def test_capture_restart():
    calls = [0]
    inner = tone(1000.0, 0.3)

    def flaky(n):
        calls[0] += 1
        if calls[0] == 1:
            raise RuntimeError("device gone")
        return inner(n)
    backend = bands.SyntheticBackend(flaky, rate=RATE)
    cap = bands.Capture(backend, sleep=5).start()
    try:
        ok(wait_for(lambda: cap.restarts >= 1, 1.0), "a backend that raises counts a restart")
        ok(cap.alive(), "…and the thread survives it")
        ok(wait_for(lambda: cap.frames >= 3, 3.0), "…and frames flow after the reopen")
        ok(backend.opens >= 2, f"the backend was reopened: {backend.opens} opens")
        ok(cap.state()["restarts"] >= 1, "state() reports the restart")
    finally:
        cap.stop()
    print(f"  ✓ supervisor: {cap.restarts} restart, {backend.opens} opens, {cap.frames} frames")


def test_null_backend():
    null = bands.NullBackend()
    rate, channels = null.open()
    block = null.read()
    ok(rate == 48000 and channels == 2 and block.shape == (rate // 50, 2) and not block.any(),
       "NullBackend yields silence in the right shape")
    cap = bands.Capture(null, sleep=0.3).start()
    try:
        time.sleep(0.8)
        ok(cap.frame() == [0] * (2 * bands.BARS) and cap.alive(), "a service without a capture library runs dark")
        ok(cap.state()["backend"] == "none", "…and says so in state()")
    finally:
        cap.stop()
    print("  ✓ no backend: silence, backend \"none\"")


def test_relay_functions():
    a = bands.Analyzer(RATE, 2)
    frame = run(a, tone(440.0, 0.3), 10)
    widget = relay.resample(relay.fold_mono(frame), 160)
    ok(len(widget) == 160, "resample(fold_mono(frame), 160) has the widget's 160 values")
    ok(max(widget) > 0 and all(0 <= v <= 1000 for v in widget), "…within 0..1000")
    print("  ✓ relay.py's fold_mono and resample apply unchanged")


if __name__ == "__main__":
    test_import()
    test_frame_shape()
    test_silence()
    test_tone_position()
    test_cava_order()
    test_levels_and_autosens()
    test_smoothing()
    test_capture_rate()
    test_capture_sleep()
    test_capture_restart()
    test_null_backend()
    test_relay_functions()
    print(f"  ✓ bands.py: {passed} checks passed")
