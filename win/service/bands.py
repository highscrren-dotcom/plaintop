#!/usr/bin/env python3
"""Spectrum bands from WASAPI loopback, in the frame the relay serves.

On Linux the visualizer's bands come from cava through spectrum/relay.py. The Windows
service keeps the relay's `/bands` protocol byte for byte (win/PROTOCOL.md) but has no
cava between the sound card and the HTTP server: this module captures the default
output's loopback stream and computes the bands itself, so the service stays one Python
process and `fold_mono` and `resample` from relay.py apply to its frames unchanged.

The frame keeps cava's stereo order — the left channel from its highest band down to its
lowest, then the right channel from lowest to highest — so drawn as it comes a ring shows
the same spectrum twice, mirrored about its middle, and relay.fold_mono (left reversed,
averaged with right) yields one run of bands from low to high. Mono input is written to
both halves.

Two parts, separated on purpose. A backend yields PCM blocks — soundcard or pyaudiowpatch
on Windows, silence when neither is installed, a synthetic generator for the stand — and
the Analyzer is pure numpy, so everything but the capture itself is verified by
tests/win_bands.py on a machine with no sound hardware. Nothing Windows-specific runs at
import time; the backends are imported when one is picked.

    python3 win/service/bands.py --self-test   # a tone and a sweep through the analyzer, and its cost
"""
import math
import os
import sys
import threading
import time

import numpy as np

BARS = int(os.environ.get("PLAINSPECTRUM_BARS", "256"))     # per channel: a frame is 2 × BARS
FPS = int(os.environ.get("PLAINSPECTRUM_FPS", "30"))
# 0–100 as cava's noise_reduction: the share of the previous frame kept in the next, so
# higher is smoother. cava's default is 77; the relay asks for 60.
NOISE = int(os.environ.get("PLAINSPECTRUM_NOISE", "60"))
LOW_HZ = int(os.environ.get("PLAINSPECTRUM_LOW_HZ", "40"))
HIGH_HZ = int(os.environ.get("PLAINSPECTRUM_HIGH_HZ", "16000"))
# Seconds of exact digital silence before the capture thread idles: the stream is closed,
# no FFT runs, no frame is written, and once a second it is opened for one block to see
# whether sound is back — relay.py's cava sleep_timer, which cut cava from 3.9% of a core
# to 0.35% in silence. The price is the same: the first frame comes up to a second after
# the sound returns. Three seconds keeps the pause between two tracks awake.
SLEEP = int(os.environ.get("PLAINSPECTRUM_SLEEP", "3"))
RANGE = 1000            # ascii_max_range: 1000 steps, or the bars visibly step

# The band magnitudes are lifted by 6 dB per octave before the compression, as cava's eq
# (proportional to the band's frequency to the 0.85, about 5 dB per octave, on its linear
# bars) lifts its treble: music falls towards the treble, and without the lift the right
# half of the ring barely moves. After the square root below that is 3 dB per octave on
# screen.
TILT_DB_PER_OCTAVE = 6.0
TILT_REF_HZ = 1000.0    # a full-scale 1 kHz sine reads 1.0 before the gain
# The dB-ish compression is a square root rather than a log. A log needs a floor, and
# everything above the floor is visible, so a ring on a log scale never rests on hiss; the
# root keeps zero at zero and still draws a band 20 dB under the peak at a third of the
# height, where cava's linear scale draws a tenth.
CURVE = 0.5
# autosens with cava's own rates (cavacore.c, 2% down and 0.1% up per frame at 66 fps, a
# further 10% up per frame until the first overshoot), written per second so the frame
# rate does not change them: the gain climbs fast from a cold start until something
# reaches the top, then creeps up while nothing does and drops as soon as something does,
# so music of any loudness fills the range without the picture pumping. The cap keeps the
# gain from hunting for a signal in the noise floor forever.
GAIN_RISE_DB_PER_S = 0.6
GAIN_RISE_INIT_DB_PER_S = 50.0
GAIN_FALL_DB_PER_S = 12.0
GAIN_MAX_DB = 60.0      # the quietest band peak the gain will bring to the top
# The FFT is four times the window, zero-padded. That sharpens nothing — the window sets
# how wide a tone smears — but it places a peak to within 6 Hz instead of 23, so two bass
# notes a few Hz apart land in different bands rather than in the same bin; with one bin
# per 23 Hz, E1 and A1 (41 and 55 Hz) would be the same band. Measured at 0.2 ms a frame
# against 0.08 without, on a 2.1 GHz Xeon core.
PAD = 4


def band_edges(bars, low_hz, high_hz):
    """The bars+1 frequencies bounding the bands: equal steps on a logarithmic scale from
    low to high, as cava lays them out, so every octave gets the same share of the ring."""
    return low_hz * (high_hz / low_hz) ** (np.arange(bars + 1) / bars)


def band_of(hz, bars, low_hz, high_hz):
    """Where a frequency falls on that scale, as a fractional band index: int() is the band."""
    return bars * math.log(hz / low_hz) / math.log(high_hz / low_hz)


class Analyzer:
    """PCM in, cava's frame out. Pure numpy, no clock, no thread: push() blocks as they
    come, frame() whenever a frame is due, and the stand drives it with synthetic signals."""

    def __init__(self, rate, channels=2, bars=BARS, low_hz=LOW_HZ, high_hz=HIGH_HZ, fps=FPS,
                 noise=NOISE):
        self.rate = int(rate)
        self.in_channels = int(channels)
        # The ring draws two channels; of a 5.1 loopback the first two are front left and
        # right, and the rest would only cost FFTs.
        self.channels = 2 if channels >= 2 else 1
        self.bars = int(bars)
        self.fps = fps
        self.low_hz = float(low_hz)
        self.high_hz = min(float(high_hz), self.rate / 2)
        # The power of two holding at least 30 ms: 2048 at 44.1 and 48 kHz (43–46 ms). A
        # shorter window puts the whole bass into a handful of bins; a longer one smears a
        # drum hit over several frames at 30 fps.
        self.size = 1 << max(8, math.ceil(math.log2(self.rate * 0.03)))
        self.nfft = PAD * self.size
        hann = np.hanning(self.size)
        # Scaled so a full-scale sine centred on a bin reads 1.0 there, which gives the
        # gain constants below a meaning in dBFS.
        self._window = (hann * 2.0 / hann.sum()).astype(np.float32)[:, None]
        self._ring = np.zeros((self.size, self.channels), np.float32)
        self._pos = 0
        self.edges = band_edges(self.bars, self.low_hz, self.high_hz)
        self._bin_idx, self._band_idx, self._weights = self._band_weights()
        self.gain = 1.0
        self.gain_init = True       # no overshoot yet: the fast ramp of a cold start
        self._rise = 10 ** (GAIN_RISE_DB_PER_S / 20 / fps)
        self._rise_init = 10 ** (GAIN_RISE_INIT_DB_PER_S / 20 / fps)
        self._fall = 10 ** (-GAIN_FALL_DB_PER_S / 20 / fps)
        self._gain_max = 10 ** (GAIN_MAX_DB / 20)
        # The smoothing is the share of the previous frame kept, noise/100 at 30 fps and
        # the same time constant at any other rate; 100 would freeze the ring, so it stops
        # at 97. cava's integrator has the same shape (y = y·nr + x) before its own gain.
        keep = min(max(noise, 0), 97) / 100.0
        self._keep = keep ** (30.0 / fps) if keep > 0 else 0.0
        self._levels = np.zeros((self.channels, self.bars), np.float32)

    def band_of(self, hz):
        return band_of(hz, self.bars, self.low_hz, self.high_hz)

    def _band_weights(self):
        """Bins → bands as a sparse weight list: band b is the mean of the spectrum, taken
        as a straight line between neighbouring bins, over the band's frequency range.

        A wide band (the treble, where a band spans many bins) averages its bins; a narrow
        one (the bass, where 256 log-spaced bands share a few dozen bins) interpolates
        between the two bins around its centre, as cava does when the exponential scale
        gets clumped in the bass — so every band owns at least one bin and neighbouring
        bands never repeat the same value in steps. Computed once; frame() pays one
        bincount per channel.
        """
        nbins = self.nfft // 2 + 1
        bin_hz = self.rate / self.nfft
        dense = np.zeros((self.bars, nbins), np.float64)
        tilt_exp = TILT_DB_PER_OCTAVE / (20.0 * math.log10(2.0))
        for b in range(self.bars):
            k0, k1 = self.edges[b] / bin_hz, self.edges[b + 1] / bin_hz
            n = max(8, int(4 * (k1 - k0)) + 1)
            pos = np.clip(k0 + (np.arange(n) + 0.5) * (k1 - k0) / n, 0, nbins - 1)
            lo = np.floor(pos).astype(int)
            hi = np.minimum(lo + 1, nbins - 1)
            frac = pos - lo
            centre = math.sqrt(self.edges[b] * self.edges[b + 1])
            tilt = (centre / TILT_REF_HZ) ** tilt_exp
            np.add.at(dense[b], lo, (1.0 - frac) * tilt / n)
            np.add.at(dense[b], hi, frac * tilt / n)
        band_idx, bin_idx = np.nonzero(dense)
        return bin_idx, band_idx, dense[band_idx, bin_idx].astype(np.float32)

    def push(self, block):
        """Append a block of float32 samples, shape (n, channels); only the last window
        is kept."""
        block = np.asarray(block, dtype=np.float32)
        if block.ndim == 1:
            block = block[:, None]
        if block.shape[1] < self.channels:
            block = np.repeat(block[:, :1], self.channels, axis=1)
        block = block[:, :self.channels]
        n = len(block)
        if n >= self.size:
            self._ring[:] = block[-self.size:]
            self._pos = 0
            return
        end = self._pos + n
        if end <= self.size:
            self._ring[self._pos:end] = block
        else:
            first = self.size - self._pos
            self._ring[self._pos:] = block[:first]
            self._ring[:end - self.size] = block[first:]
        self._pos = end % self.size

    def frame(self):
        """The stereo frame of 2 × bars integers 0–RANGE from the last window, in cava's
        order: the left channel from its highest band down to its lowest, then the right
        channel from lowest to highest."""
        buf = np.concatenate((self._ring[self._pos:], self._ring[:self._pos]))
        spec = np.abs(np.fft.rfft(buf * self._window, n=self.nfft, axis=0))
        bands = np.empty((self.channels, self.bars), np.float32)
        for c in range(self.channels):
            bands[c] = np.bincount(self._band_idx, spec[self._bin_idx, c] * self._weights,
                                   self.bars)
        # One gain for both channels, or a quiet channel would be drawn as loud as the other.
        peak = float(bands.max()) * self.gain
        if peak > 1.0:
            # A small overshoot lands exactly on the top instead of oscillating around it;
            # a big one comes down at the fall rate while the peak band clips.
            self.gain *= max(1.0 / peak, self._fall)
            self.gain_init = False
        elif peak > 0.0:
            # Exact silence leaves the gain alone, as cava's `if (!silence)` does: a gain
            # that climbed through a pause would clip the first beat after it.
            rise = self._rise * self._rise_init if self.gain_init else self._rise
            self.gain = min(self.gain * rise, self._gain_max)
        level = np.minimum(bands * self.gain, 1.0) ** CURVE
        self._levels += (1.0 - self._keep) * (level - self._levels)
        out = np.rint(self._levels * RANGE).astype(int)
        right = out[1] if self.channels == 2 else out[0]
        return np.concatenate((out[0][::-1], right)).tolist()


# ---------------------------------------------------------------------------------------
# Backends: open() -> (rate, channels), read() -> float32 (n, channels) within ~20 ms,
# close(). open() resolves the default output every time it is called, as relay.py
# resolves the default sink at every cava start: the user switches outputs and a stream
# stays bound to the device it was opened on.

class SoundcardBackend:
    """WASAPI loopback through the `soundcard` package (pip install soundcard)."""
    name = "soundcard"

    def __init__(self, rate=48000, block=None):
        self.rate = rate
        self.block = block or rate // 50
        self.source = ""
        self._rec = None
        self._channels = 2

    @staticmethod
    def probe():
        # Importing soundcard connects to the sound server of the platform at once, and
        # without one it raises whatever that failed with, not ImportError.
        import soundcard  # noqa: F401

    def open(self):
        import soundcard as sc
        speaker = sc.default_speaker()
        mic = sc.get_microphone(speaker.name, include_loopback=True)
        self._channels = 2 if mic.channels >= 2 else 1
        # The engine resamples to the asked rate, so the analyzer sees 48 kHz whatever the
        # device runs at; blocksize is the packet soundcard asks WASAPI for.
        rec = mic.recorder(samplerate=self.rate, channels=self._channels, blocksize=self.block)
        rec.__enter__()
        self._rec = rec
        self.source = speaker.name
        return self.rate, self._channels

    def read(self):
        # record(numframes) blocks until the frames are in; a device that delivers nothing
        # in silence is answered with zeros after a few periods (mediafoundation.py,
        # _record_chunk), so this returns within tens of milliseconds either way.
        data = self._rec.record(numframes=self.block)
        return np.asarray(data, dtype=np.float32).reshape(-1, self._channels)

    def close(self):
        rec, self._rec = self._rec, None
        if rec is not None:
            rec.__exit__(None, None, None)


class PyAudioBackend:
    """WASAPI loopback through `pyaudiowpatch` (pip install pyaudiowpatch), the PyAudio fork
    that lists loopback devices."""
    name = "pyaudiowpatch"

    def __init__(self, block=None):
        self.block = block
        self.source = ""
        self._pa = None
        self._stream = None
        self._channels = 2

    @staticmethod
    def probe():
        import pyaudiowpatch  # noqa: F401

    def open(self):
        import pyaudiowpatch as pyaudio
        pa = pyaudio.PyAudio()
        try:
            dev = pa.get_default_wasapi_loopback()
            rate = int(dev["defaultSampleRate"])
            # Opened with every channel the device has: PortAudio refuses fewer on some
            # WASAPI devices, and the analyzer takes the first two anyway.
            self._channels = max(1, int(dev["maxInputChannels"]))
            block = self.block or rate // 50
            self._stream = pa.open(format=pyaudio.paFloat32, channels=self._channels, rate=rate,
                                   input=True, input_device_index=dev["index"],
                                   frames_per_buffer=block)
        except Exception:
            pa.terminate()
            raise
        self._pa = pa
        self._block = block
        self.source = dev["name"]
        return rate, self._channels

    def read(self):
        # An overflow (we were late) loses samples but is no reason to restart the stream.
        data = self._stream.read(self._block, exception_on_overflow=False)
        return np.frombuffer(data, dtype=np.float32).reshape(-1, self._channels)

    def close(self):
        stream, self._stream = self._stream, None
        pa, self._pa = self._pa, None
        if stream is not None:
            try:
                stream.stop_stream()
            finally:
                stream.close()
        if pa is not None:
            pa.terminate()


class NullBackend:
    """Silence, when no capture library is installed: the service runs, /bands answers,
    the ring stays dark, and /state says `backend: "none"` so nobody has to guess."""
    name = "none"
    source = "(no capture)"

    def __init__(self, rate=48000, channels=2):
        self.rate = rate
        self.channels = channels
        self.block = rate // 50

    def open(self):
        return self.rate, self.channels

    def read(self):
        time.sleep(self.block / self.rate)
        return np.zeros((self.block, self.channels), np.float32)

    def close(self):
        pass


class SyntheticBackend:
    """Blocks from a callable, for the stand: generator(n) returns an (n, channels) array.
    Paced like a sound card by default, so Capture's timer and sleep logic run as they do
    live; realtime=False feeds the analyzer as fast as it will take."""
    name = "synthetic"
    source = "synthetic"

    def __init__(self, generator, rate=48000, channels=2, block=None, realtime=True):
        self.generator = generator
        self.rate = rate
        self.channels = channels
        self.block = block or rate // 50
        self.realtime = realtime
        self.opens = 0
        self.closes = 0

    def open(self):
        self.opens += 1
        return self.rate, self.channels

    def read(self):
        if self.realtime:
            time.sleep(self.block / self.rate)
        return np.asarray(self.generator(self.block), dtype=np.float32).reshape(-1, self.channels)

    def close(self):
        self.closes += 1


def pick_backend():
    """The first capture library that imports, soundcard then pyaudiowpatch; silence when
    neither does. Said once on stderr, as relay.py says "cava not found"."""
    for cls in (SoundcardBackend, PyAudioBackend):
        try:
            cls.probe()
        except Exception:
            continue
        return cls()
    print("no capture backend: pip install soundcard (or pyaudiowpatch) for WASAPI loopback; "
          "serving silence", file=sys.stderr, flush=True)
    return NullBackend()


class Capture:
    """The thread between a backend and the server: keeps the latest frame, supervises the
    backend as relay.py's pump() supervises cava, and idles on silence."""

    def __init__(self, backend=None, bars=BARS, fps=FPS, low_hz=LOW_HZ, high_hz=HIGH_HZ,
                 noise=NOISE, sleep=SLEEP):
        self.backend = backend if backend is not None else pick_backend()
        self.bars = bars
        self.fps = fps
        self.low_hz = low_hz
        self.high_hz = high_hz
        self.noise = noise
        self.sleep = sleep
        self.frames = 0
        self.restarts = 0
        self.stamp = 0.0
        self.source = ""
        self._frame = [0] * (2 * bars)
        self._analyzer = None
        self._stop = threading.Event()
        self._thread = None

    def start(self):
        self._thread = threading.Thread(target=self._run, name="bands-capture", daemon=True)
        self._thread.start()
        return self

    def stop(self, timeout=3.0):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout)

    def alive(self):
        return self._thread is not None and self._thread.is_alive()

    def frame(self):
        # The thread stops writing when it sleeps on silence or loses the device; serving
        # the last frame would leave the widget frozen mid-note, so after a second without
        # one silence is served, as the relay does for cava.
        if time.monotonic() - self.stamp < 1.0:
            return self._frame
        return [0] * (2 * self.bars)

    def state(self):
        age = time.monotonic() - self.stamp if self.stamp else -1
        return {"frames": self.frames, "restarts": self.restarts,
                "source": self.source or "(default)", "age": round(age, 2),
                "bars": self.bars, "fps": self.fps, "backend": self.backend.name}

    def _run(self):
        """Nothing inside the loop may end the thread (relay.py learnt that the hard way):
        an open or a read that raises is reported, and the backend is reopened after a
        backoff of 1 → 10 s, so a device that is not there yet costs a retry every 10 s
        rather than every second."""
        delay = 1
        while not self._stop.is_set():
            frames_before = self.frames
            try:
                self._open()
                self._pump()
            except Exception as e:
                self._close()
                if self._stop.is_set():
                    break
                self.restarts += 1
                delay = 1 if self.frames > frames_before else min(delay * 2, 10)
                print(f"capture ({self.backend.name}) failed: {e!r}, restarting in {delay} s",
                      file=sys.stderr, flush=True)
                self._stop.wait(delay)
        self._close()

    def _open(self):
        rate, channels = self.backend.open()
        self.source = getattr(self.backend, "source", "") or "(default)"
        a = self._analyzer
        if a is None or a.rate != rate or a.in_channels != channels:
            self._analyzer = Analyzer(rate, channels, self.bars, self.low_hz, self.high_hz,
                                      self.fps, self.noise)
            if a is not None:               # a new device keeps the loudness the ring settled on
                self._analyzer.gain, self._analyzer.gain_init = a.gain, a.gain_init

    def _close(self):
        try:
            self.backend.close()
        except Exception:
            pass

    def _pump(self):
        """Blocks in, a frame every 1/fps out — on a timer, not per block, so the frame
        rate is the same whatever packet size a backend delivers."""
        backend = self.backend
        period = 1.0 / self.fps
        next_frame = time.monotonic() + period
        quiet_since = None
        while not self._stop.is_set():
            block = backend.read()
            now = time.monotonic()
            if block is None or len(block) == 0:
                continue
            if block.any():
                quiet_since = None
            elif quiet_since is None:
                quiet_since = now
            elif now - quiet_since >= self.sleep:
                backend.close()
                self._doze()
                quiet_since = None
                next_frame = time.monotonic() + period
                continue
            self._analyzer.push(block)
            if now >= next_frame:
                self._frame = self._analyzer.frame()
                self.stamp = now
                self.frames += 1
                next_frame += period
                if next_frame < now:        # a long read: no burst of catch-up frames
                    next_frame = now + period

    def _doze(self):
        """Asleep on silence: the stream closed, one block a second to see whether sound is
        back. Returns with the backend open and the sounding block pushed, or when stopped.

        Closing rather than leaving the stream to overflow means waking does not start a
        second behind, and since open() resolves the default device anew, an output
        switched while the old one fell silent is picked up here — relay.py needs a
        watcher thread for that.
        """
        while not self._stop.wait(1.0):
            self._open()
            block = self.backend.read()
            if block is not None and len(block) and block.any():
                self._analyzer.push(block)
                return
            self.backend.close()


# ---------------------------------------------------------------------------------------

def self_test():
    """The analyzer's reaction to a tone and a sweep, and what a frame costs."""
    rate, channels = 48000, 2
    a = Analyzer(rate, channels)
    per_frame = rate // a.fps           # the samples one frame stands for
    print(f"analyzer: {rate} Hz, a {a.size}-sample window ({a.size / rate * 1000:.1f} ms) in a "
          f"{a.nfft}-point FFT ({rate / a.nfft:.1f} Hz per bin), {a.bars} bands "
          f"{a.low_hz:.0f}–{a.high_hz:.0f} Hz")

    def fold(frame):
        half = len(frame) // 2
        return [(frame[half - 1 - j] + frame[half + j]) // 2 for j in range(half)]

    pos = 0
    for _ in range(3 * a.fps):
        t = (pos + np.arange(per_frame)) / rate
        pos += per_frame
        s = (0.25 * np.sin(2 * np.pi * 440.0 * t)).astype(np.float32)
        a.push(np.stack([s, s], axis=1))
        frame = a.frame()
    folded = fold(frame)
    peak = int(np.argmax(folded))
    print(f"440 Hz tone at -12 dBFS, after 3 s: peak in band {peak} "
          f"(the log scale says {a.band_of(440):.1f}), level {folded[peak]}, "
          f"two octaves down {folded[int(a.band_of(110))]}, up {folded[int(a.band_of(1760))]}, "
          f"gain {20 * math.log10(a.gain):+.1f} dB")

    a = Analyzer(rate, channels)
    seconds = 8.0
    phase, pos = 0.0, 0
    print(f"sweep {a.low_hz:.0f} → {a.high_hz:.0f} Hz over {seconds:.0f} s "
          f"(the smoothing lags a sweep by a frame or two):")
    for n in range(int(seconds * a.fps)):
        t = (pos + np.arange(per_frame)) / rate
        hz = a.low_hz * (a.high_hz / a.low_hz) ** (t / seconds)
        ph = phase + np.cumsum(2 * np.pi * hz / rate)
        phase = ph[-1] % (2 * np.pi)
        pos += per_frame
        s = (0.3 * np.sin(ph)).astype(np.float32)
        a.push(np.stack([s, s], axis=1))
        frame = a.frame()
        if n % a.fps == a.fps - 1:
            folded = fold(frame)
            centre_hz = a.low_hz * (a.high_hz / a.low_hz) ** ((pos - a.size / 2) / rate / seconds)
            print(f"  {centre_hz:8.1f} Hz → peak band {int(np.argmax(folded)):3d}, "
                  f"the log scale says {a.band_of(centre_hz):6.1f}, level {max(folded)}")

    a = Analyzer(rate, channels)
    rng = np.random.default_rng(0)
    noise = (rng.standard_normal((per_frame, channels)) * 0.1).astype(np.float32)
    a.push(noise)
    a.frame()
    frames = 300
    t0 = time.perf_counter()
    for _ in range(frames):
        a.frame()
    frame_ms = (time.perf_counter() - t0) / frames * 1000
    t0 = time.perf_counter()
    for _ in range(frames):
        a.push(noise)
        a.frame()
    both_ms = (time.perf_counter() - t0) / frames * 1000
    print(f"cost at {rate} Hz, {a.bars} bands: frame() {frame_ms:.3f} ms, push() + frame() "
          f"{both_ms:.3f} ms — {both_ms * a.fps / 10:.2f}% of a core at {a.fps} fps")


def main(argv):
    if "--self-test" in argv:
        self_test()
        return 0
    print("bands.py serves nothing by itself: win/service/server.py imports Capture, BARS and "
          "FPS and serves /bands. Try --self-test.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
