#!/usr/bin/env python3
"""Stand for spectrum/relay.py: the pure functions between cava and the widget — folding
the stereo frame into one spectrum, resampling the bands to the count the widget draws,
and the cava configuration the relay writes (the two gotchas of 2026-10-04: a mirrored
ring, and noise_reduction read from [smoothing] only).

    python3 tests/relay.py          # or ./install.sh --check-relay

No cava, no HTTP, no network: relay.py is imported and its functions are called.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("relay", ROOT / "spectrum/relay.py")
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)

passed = 0


def ok(cond, what):
    global passed
    if not cond:
        print("  ✗ " + what)
        sys.exit(1)
    passed += 1


def test_fold():
    # cava's frame: the left channel from its highest band down to its lowest, then the
    # right channel from lowest to highest. Band j is left[half-1-j] with right[half+j].
    ok(relay.fold_mono([3, 2, 1, 10, 20, 30]) == [5, 11, 16], "left reversed, averaged with right, low to high")
    ok(relay.fold_mono([7, 7]) == [7], "one band a channel")
    ok(relay.fold_mono([]) == [], "an empty frame")
    ok(relay.fold_mono([0, 0, 1000, 1000]) == [500, 500], "a full left, a silent right: half")
    # A tone in one band on the left and the same band on the right folds into one peak.
    frame = [0] * 8 + [0] * 8
    frame[8 - 1 - 2] = 600          # left, band 2
    frame[8 + 2] = 400              # right, band 2
    folded = relay.fold_mono(frame)
    ok(folded[2] == 500 and sum(folded) == 500, "the same band of both channels is one peak: " + repr(folded))
    print("  ✓ fold_mono: the stereo frame as one spectrum")


def test_resample():
    ok(relay.resample([0, 10, 20, 30], 2) == [5, 25], "down by two: averages")
    ok(relay.resample([1, 2, 3, 4, 5], 2) == [1, 4], "down unevenly: each chunk its own average")
    ok(relay.resample([0, 30], 4) == [0, 10, 20, 30], "up: linear interpolation, the ends kept")
    ok(relay.resample([5, 15, 25], 5) == [5, 10, 15, 20, 25], "up by a fraction")
    ok(relay.resample([7], 3) == [7, 7, 7], "one band repeated")
    ok(relay.resample([1, 2, 3], 3) == [1, 2, 3], "the same count: untouched")
    ok(relay.resample([1, 2, 3], 0) == [1, 2, 3] and relay.resample([1, 2, 3], -4) == [1, 2, 3], "a count of nothing: untouched")
    ok(relay.resample([], 4) == [], "nothing to resample")
    # A folded frame has half the bands: up-sampling it must not show pairs of equal ticks.
    up = relay.resample([0, 100, 0, 100], 8)
    ok(len(set(up)) > 4, "no runs of repeated values when interpolating: " + repr(up))
    print("  ✓ resample: the bands as the count the widget draws")


def test_cava_config():
    text = relay.cava_config("alsa_output.pci")
    sections = {}
    current = None
    for line in text.splitlines():
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections[current] = {}
        elif "=" in line and current:
            k, v = line.split("=", 1)
            sections[current][k] = v
    ok("noise_reduction" in sections.get("smoothing", {}), "noise_reduction sits under [smoothing]: " + repr(sections))
    ok("noise_reduction" not in sections.get("general", {}), "…and not under [general], where cava ignores it")
    ok(sections["general"].get("sleep_timer") == str(relay.SLEEP), "sleep_timer is set, so cava rests in silence")
    ok(sections["input"].get("method") == "pipewire" and sections["input"].get("source") == "alsa_output.pci", "the source goes to [input]")
    ok(sections["output"].get("data_format") == "ascii" and sections["output"].get("raw_target") == "/dev/stdout", "raw ascii to stdout")
    ok(sections["general"].get("bars") == str(relay.BARS), "the fixed, generous band count")
    ok("source=" not in relay.cava_config(""), "no source line when none is named")
    print("  ✓ cava_config: the sections cava actually reads")


if __name__ == "__main__":
    test_fold()
    test_resample()
    test_cava_config()
    print(f"  ✓ relay.py: {passed} checks passed")
