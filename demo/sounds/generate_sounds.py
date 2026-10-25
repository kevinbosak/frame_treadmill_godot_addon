#!/usr/bin/env python3
"""Generates the demo's forest sounds (no recordings needed).

Run from this folder:  python3 generate_sounds.py   (needs numpy and scipy)
Every sound is synthesised, so you can replace any .wav here with a real
recording of the same name later. Looping files carry WAV loop points that
Godot picks up on import.
"""
import struct
import wave

import numpy as np
from scipy import signal

RNG = np.random.default_rng(7)
SR = 44100


# --- helpers -------------------------------------------------------------------

def write_wav(path, x, sr=SR, loop=False, peak_db=-3.0):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)
    channels = 1 if x.ndim == 1 else x.shape[1]
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    if loop:
        frames = len(x)
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
            size = f.tell() - 8
            f.seek(4)
            f.write(struct.pack("<I", size))
    print(f"wrote {path}: {len(x) / sr:.2f} s, {channels} ch, {sr} Hz{', loop' if loop else ''}")


def env(n, attack, release, sr=SR):
    e = np.ones(n)
    a = min(int(attack * sr), n)
    r = min(int(release * sr), n - a)
    if a:
        e[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if r:
        e[n - r:] = np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return e


def tone(freq_curve, amp_curve, harmonics=((1, 1.0),), sr=SR):
    phase = 2 * np.pi * np.cumsum(freq_curve) / sr
    out = sum(a * np.sin(h * phase) for h, a in harmonics)
    return out * amp_curve


def silence(sec, sr=SR):
    return np.zeros(int(sec * sr))


def bandpass(x, lo, hi, sr=SR, order=4):
    return signal.sosfilt(signal.butter(order, [lo, hi], "bandpass", fs=sr, output="sos"), x, axis=0)


def lowpass(x, cutoff, sr=SR, order=4):
    return signal.sosfilt(signal.butter(order, cutoff, "lowpass", fs=sr, output="sos"), x, axis=0)


def highpass(x, cutoff, sr=SR, order=2):
    return signal.sosfilt(signal.butter(order, cutoff, "highpass", fs=sr, output="sos"), x, axis=0)


def make_loop(x, sr, fade_sec=1.0):
    """Crossfades the end into the start so the file loops without a seam."""
    n = int(fade_sec * sr)
    body, tail = x[:-n].copy(), x[-n:]
    ramp = np.linspace(0, 1, n)
    if x.ndim == 2:
        ramp = ramp[:, None]
    body[:n] = body[:n] * ramp + tail * (1 - ramp)
    return body


def periodic_noise_curve(seconds, sr, components=6, lo_cycles=1, hi_cycles=12):
    """A smooth random curve in 0..1 that repeats exactly every `seconds`."""
    t = np.arange(int(seconds * sr)) / sr
    curve = np.zeros_like(t)
    for _ in range(components):
        cycles = RNG.integers(lo_cycles, hi_cycles + 1)
        curve += RNG.uniform(0.3, 1.0) * np.sin(2 * np.pi * cycles * t / seconds + RNG.uniform(0, 2 * np.pi))
    curve -= curve.min()
    return curve / curve.max()


# --- birds ------------------------------------------------------------------------

def chirp(dur, f0, f1, vib_hz=0.0, vib_depth=0.0, amp=1.0, curve=2.0):
    n = int(dur * SR)
    s = np.linspace(0, 1, n)
    f = f0 + (f1 - f0) * s ** curve
    if vib_hz:
        f = f + vib_depth * np.sin(2 * np.pi * vib_hz * s * dur)
    return tone(f, env(n, dur * 0.25, dur * 0.4) * amp, ((1, 1.0), (2, 0.12)))


def warbler():
    parts = []
    for i in range(10):
        parts += [chirp(0.055, 6200 - i * 120, 4000, 60, 150, 0.8 + 0.2 * RNG.random()), silence(0.025)]
    parts += [chirp(0.28, 3800, 6500, 45, 300, 1.0, curve=1.0)]
    return np.concatenate(parts)


def robin():
    parts = []
    for _ in range(4):
        dur = RNG.uniform(0.18, 0.26)
        n = int(dur * SR)
        s = np.linspace(0, 1, n)
        lo, hi = RNG.uniform(2000, 2500), RNG.uniform(2900, 3400)
        f = lo + (hi - lo) * np.sin(np.pi * s) ** 0.8
        am = 0.8 + 0.2 * np.sin(2 * np.pi * 30 * s * dur)
        parts += [tone(f, env(n, 0.03, 0.06) * am, ((1, 1.0), (2, 0.08))), silence(RNG.uniform(0.06, 0.12))]
    return np.concatenate(parts)


def chickadee():
    n1, n2 = int(0.28 * SR), int(0.33 * SR)
    a = tone(np.linspace(4000, 3900, n1), env(n1, 0.04, 0.08))
    b = tone(np.linspace(3420, 3380, n2), env(n2, 0.04, 0.12))
    return np.concatenate([a, silence(0.04), b])


def finch():
    parts = []
    for _ in range(15):
        d = RNG.uniform(0.03, 0.06)
        f0 = RNG.uniform(3000, 5500)
        parts += [chirp(d, f0, f0 + RNG.uniform(500, 1800), amp=RNG.uniform(0.6, 1.0), curve=1.0),
                  silence(RNG.uniform(0.02, 0.05))]
    return np.concatenate(parts)


# --- other creatures -----------------------------------------------------------

def bee_loop(seconds=2.0, f0=190.0):
    """Bumblebee buzz: a wingbeat-rate tone with rich harmonics and a little wobble."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.025 * np.sin(2 * np.pi * 1.5 * t) + 0.012 * np.sin(2 * np.pi * 7.0 * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    phase *= np.round(phase[-1] / (2 * np.pi)) * 2 * np.pi / phase[-1]   # whole cycles: seamless loop
    x = sum((1.0 / h ** 0.9) * np.sin(h * phase + 0.3 * h) for h in range(1, 22))
    x = x * (1 + 0.15 * np.sin(phase * 0.5) ** 2)
    noise = bandpass(RNG.normal(size=n), 300, 3000) * 0.08
    x = bandpass(x + noise, 120, 5000, order=2)
    return x


def owl():
    parts = []
    for dur, gap, f in [(0.22, 0.12, 390), (0.14, 0.05, 400), (0.5, 0.35, 410), (0.32, 0.3, 385), (0.32, 0.0, 375)]:
        n = int(dur * SR)
        freq = np.linspace(f, f * 0.94, n)
        voice = tone(freq, env(n, 0.05, 0.12), ((1, 1.0), (2, 0.18), (3, 0.05)))
        breath = lowpass(RNG.normal(size=n), 900) * env(n, 0.05, 0.12) * 0.06
        parts += [voice + breath, silence(gap)]
    return np.concatenate(parts)


def woodpecker():
    out = np.zeros(int(1.3 * SR))
    times = np.cumsum(np.linspace(0.07, 0.05, 18))
    for i, t0 in enumerate(times):
        n = int(0.03 * SR)
        k = RNG.normal(size=n) * np.exp(-np.arange(n) / (0.004 * SR))
        knock = bandpass(k, 700, 2200, order=2) + 0.6 * bandpass(k, 250, 450, order=2)
        start = int(t0 * SR)
        out[start:start + n] += knock * (1.0 - 0.3 * i / len(times))
    return out


def cricket_loop(period=0.6, count=7, carrier=4600.0):
    seconds = period * count
    n = int(seconds * SR)
    t = np.arange(n) / SR
    gate = np.zeros(n)
    for c in range(count):
        level = RNG.uniform(0.7, 1.0)
        for p in range(3):
            start = int((c * period + p * 0.025) * SR)
            m = int(0.015 * SR)
            gate[start:start + m] = env(m, 0.003, 0.006) * level
    return np.sin(2 * np.pi * carrier * t) * gate


# --- ambience ---------------------------------------------------------------------

def forest_ambience(seconds=30.0, sr=24000):
    """Stereo dusk forest bed: wind in the trees, leaves, distant crickets and birds."""
    total = seconds + 1.0      # one extra second for the loop crossfade
    n = int(total * sr)
    gust = np.concatenate([periodic_noise_curve(seconds, sr, 7, 1, 9)] * 2)[:n]
    common = np.cumsum(RNG.normal(size=n))
    out = np.zeros((n, 2))
    for ch in range(2):
        brown = 0.7 * common + 0.3 * np.cumsum(RNG.normal(size=n))
        brown = highpass(brown, 40, sr)
        # Wind: lowpass whose cutoff rises with each gust, processed in blocks.
        block = 1024
        wind = np.zeros(n)
        zi = None
        for start in range(0, n, block):
            g = gust[start]
            sos = signal.butter(2, 250 + 900 * g, "lowpass", fs=sr, output="sos")
            if zi is None:
                zi = signal.sosfilt_zi(sos) * 0
            wind[start:start + block], zi = signal.sosfilt(sos, brown[start:start + block], zi=zi)
        wind *= 0.25 + 0.75 * gust
        leaves = bandpass(RNG.normal(size=n), 2000, 8000, sr) * (0.05 + 0.5 * gust ** 2)
        out[:, ch] = wind / (np.std(wind) + 1e-9) * 0.35 + leaves / (np.std(leaves) + 1e-9) * 0.06
    # A distant cricket chorus, spread across both ears.
    chorus = np.zeros((n, 2))
    one = cricket_loop(period=0.55, count=4)
    one = signal.resample(one, int(len(one) * sr / SR))
    for _ in range(14):
        pan = RNG.uniform(0, 1)
        offset = RNG.integers(0, n)
        rate = RNG.uniform(0.9, 1.1)
        c = signal.resample(one, int(len(one) / rate))
        rep = np.tile(c, 2 * n // len(c) + 2)[offset:offset + n] * RNG.uniform(0.3, 1.0)
        chorus[:, 0] += rep * (1 - pan)
        chorus[:, 1] += rep * pan
    chorus = lowpass(chorus, 7000, sr)
    out += chorus / (np.std(chorus) + 1e-9) * 0.05
    # A few far-off birds, soft and reverberant.
    ir_n = int(0.9 * sr)
    for maker, when in [(robin, 4.0), (chickadee, 13.0), (warbler, 21.0), (finch, 27.0)]:
        call = signal.resample(maker(), int(len(maker()) * sr / SR))
        call = lowpass(call, 3000, sr)
        ir = RNG.normal(size=ir_n) * np.exp(-np.arange(ir_n) / (0.25 * sr))
        wet = signal.fftconvolve(call, ir)[: len(call) + ir_n]
        wet = wet / (np.max(np.abs(wet)) + 1e-9) * 0.06
        pan = RNG.uniform(0.15, 0.85)
        start = int(when * sr)
        end = min(start + len(wet), n)
        out[start:end, 0] += wet[: end - start] * (1 - pan)
        out[start:end, 1] += wet[: end - start] * pan
    return make_loop(out, sr)


if __name__ == "__main__":
    write_wav("bird_warbler.wav", warbler())
    write_wav("bird_robin.wav", robin())
    write_wav("bird_chickadee.wav", chickadee())
    write_wav("bird_finch.wav", finch())
    write_wav("bee_buzz.wav", bee_loop(), loop=True, peak_db=-4.0)
    write_wav("owl_hoot.wav", owl())
    write_wav("woodpecker.wav", woodpecker())
    write_wav("cricket.wav", cricket_loop(), loop=True, peak_db=-6.0)
    write_wav("forest_ambience.wav", forest_ambience(), sr=24000, loop=True, peak_db=-6.0)
