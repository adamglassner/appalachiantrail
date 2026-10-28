#!/usr/bin/env python3
"""Synthesizes all music, ambience and sound effects for The Appalachian Trail.

Everything is original and generated from code: plucked guitar and banjo, fiddle,
harmonica and pads are additive-synthesis instruments; ambience and effects are
shaped noise. Output: ../audio/{music,amb,sfx}/*.ogg  (requires numpy, scipy, ffmpeg)

    python3 tools/gen_audio.py
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(1923)  # year the first AT section opened

NOTE_IDX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    n, o = name[:-1], int(name[-1])
    return 12 * (o + 1) + NOTE_IDX[n]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ============================================================ instruments

def env_adsr(n, a, d, s, r, sr=SR):
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1), endpoint=False),
        np.linspace(1, s, max(d_n, 1), endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    return e[:n] if len(e) >= n else np.pad(e, (0, n - len(e)))


def pluck(f, dur, bright=0.5, decay=1.6, pos=0.18, inharm=0.0004, body=True):
    """Plucked string (guitar / banjo) by additive synthesis with per-partial decay."""
    length = dur + decay * 1.2
    n = int(length * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    kmax = int(min(28, (SR * 0.45) / f))
    for k in range(1, kmax + 1):
        fk = f * k * np.sqrt(1 + inharm * k * k)
        amp = abs(np.sin(np.pi * k * pos)) / (k ** (1.6 - bright))
        tau = decay / (1 + 0.22 * (k - 1) ** 1.25 * (1.3 - bright))
        out += amp * np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    # pick noise
    nn = int(0.012 * SR)
    click = rng.normal(0, 1, nn) * np.linspace(1, 0, nn) ** 2
    click = signal.lfilter(*signal.butter(2, min(0.99, 3000 * (0.6 + bright) / (SR / 2)), "high"), click)
    out[:nn] += click * 0.08 * (0.5 + bright)
    # damp after the note's written length (player lifts finger)
    stop = int(dur * SR)
    if stop < n:
        rel = np.exp(-np.arange(n - stop) / (0.12 * SR))
        out[stop:] *= rel
    att = np.minimum(1, np.arange(n) / (0.002 * SR))
    out *= att
    if body:
        b, a = signal.butter(2, [90 / (SR / 2), 5000 / (SR / 2)], "band")
        out = 0.6 * out + 0.4 * signal.lfilter(b, a, out)
    return out / (np.max(np.abs(out)) + 1e-9)


def bowed(f, dur, vib=0.006, attack=0.07, bright=0.55, noise=0.02):
    """Fiddle: band-limited sawtooth with delayed vibrato, bow noise and a body filter."""
    n = int((dur + 0.15) * SR)
    t = np.arange(n) / SR
    vib_amt = vib * np.clip((t - 0.12) / 0.25, 0, 1)
    inst_f = f * (1 + vib_amt * np.sin(2 * np.pi * 5.6 * t))
    phase = 2 * np.pi * np.cumsum(inst_f) / SR
    out = np.zeros(n)
    kmax = int(min(24, (SR * 0.45) / f))
    for k in range(1, kmax + 1):
        out += np.sin(k * phase) / (k ** (1.25 - bright * 0.5))
    out += rng.normal(0, noise, n) * (1 + 0.3 * np.sin(2 * np.pi * 7 * t))
    b, a = signal.butter(2, [200 / (SR / 2), 4200 / (SR / 2)], "band")
    out = 0.5 * out + 0.7 * signal.lfilter(b, a, out)
    e = env_adsr(n, attack, 0.1, 0.85, 0.14)
    swell = 1 + 0.08 * np.sin(np.pi * np.clip(t / max(dur, 0.1), 0, 1))
    out *= e * swell
    return out / (np.max(np.abs(out)) + 1e-9)


def reed(f, dur, attack=0.05):
    """Harmonica: reedy additive tone with gentle tremolo and breath."""
    n = int((dur + 0.12) * SR)
    t = np.arange(n) / SR
    bend = 1 - 0.012 * np.exp(-t / 0.05)
    phase = 2 * np.pi * np.cumsum(f * bend * (1 + 0.003 * np.sin(2 * np.pi * 5 * t))) / SR
    amps = [1.0, 0.75, 0.55, 0.42, 0.3, 0.2, 0.14, 0.1, 0.07, 0.05]
    out = np.zeros(n)
    for k, a in enumerate(amps, 1):
        if f * k < SR * 0.45:
            out += a * np.sin(k * phase)
    out += rng.normal(0, 0.03, n)
    out = signal.lfilter(*signal.butter(2, 3500 / (SR / 2)), out)
    out *= env_adsr(n, attack, 0.08, 0.8, 0.1) * (1 + 0.12 * np.sin(2 * np.pi * 5.2 * t))
    return out / (np.max(np.abs(out)) + 1e-9)


def pad(freqs, dur, attack=1.2, release=1.5, cutoff=1400):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for det in (-0.004, 0.0, 0.0045):
            ph = 2 * np.pi * f * (1 + det) * t + rng.uniform(0, 6.28)
            for k in range(1, 7):
                out += np.sin(k * ph) / k * 0.4
    out = signal.lfilter(*signal.butter(2, cutoff / (SR / 2)), out)
    out *= env_adsr(n, attack, 0.5, 0.9, release)
    return out / (np.max(np.abs(out)) + 1e-9)


def bass(f, dur):
    n = int((dur + 0.3) * SR)
    t = np.arange(n) / SR
    out = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.12 * np.sin(6 * np.pi * f * t)
    out *= np.exp(-t / 0.9) * np.minimum(1, t / 0.004)
    stop = int(dur * SR)
    if stop < n:
        out[stop:] *= np.exp(-np.arange(n - stop) / (0.08 * SR))
    return out / (np.max(np.abs(out)) + 1e-9)


def bell(f, dur=2.0, partials=((1, 1.0, 1.0), (2.76, 0.5, 0.6), (5.4, 0.3, 0.35), (8.93, 0.15, 0.2))):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, dec in partials:
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (dur * dec * 0.45))
    out *= np.minimum(1, t / 0.002)
    return out / (np.max(np.abs(out)) + 1e-9)


def kick(dur=0.35):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 50 + 70 * np.exp(-t / 0.03)
    out = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12)
    return out


def shaker(dur=0.09):
    n = int(dur * SR)
    out = rng.normal(0, 1, n) * np.exp(-np.arange(n) / (0.025 * SR))
    return signal.lfilter(*signal.butter(2, 6000 / (SR / 2), "high"), out)


# ============================================================ mixing helpers

class Track:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.L = np.zeros(self.n + SR * 6)
        self.R = np.zeros(self.n + SR * 6)

    def add(self, sig, at, gain=1.0, pan=0.0):
        i = int(at * SR)
        if i >= len(self.L):
            return
        sig = sig[: len(self.L) - i]
        lg = gain * np.cos((pan + 1) * np.pi / 4)
        rg = gain * np.sin((pan + 1) * np.pi / 4)
        self.L[i:i + len(sig)] += sig * lg
        self.R[i:i + len(sig)] += sig * rg


def reverb(x, mix=0.25, size=1.0, seed=0):
    out = np.zeros_like(x)
    combs = [1557, 1617, 1491, 1422, 1277, 1356]
    for j, d in enumerate(combs):
        d = int(d * size) + seed * 23 + j
        g = 0.82
        a = np.zeros(d + 1)
        a[0] = 1
        a[d] = -g
        lp = signal.lfilter([1 - 0.3], [1, -0.3], x)
        out += signal.lfilter([1], a, lp)
    out /= len(combs)
    for d in (225 + seed * 7, 556 + seed * 11, 441):
        g = 0.5
        b = np.zeros(d + 1)
        b[0] = -g
        b[d] = 1
        a = np.zeros(d + 1)
        a[0] = 1
        a[d] = -g
        out = signal.lfilter(b, a, out)
    return x * (1 - mix) + out * mix * 1.4


def finish_stereo(tr, loop_seconds=None, rev=0.22, size=1.0, gain_db=-1.0):
    L = reverb(tr.L, rev, size, 0)
    R = reverb(tr.R, rev, size, 1)
    if loop_seconds:
        n = int(loop_seconds * SR)
        tail_L, tail_R = L[n:], R[n:]
        L, R = L[:n].copy(), R[:n].copy()
        m = min(len(tail_L), n)
        L[:m] += tail_L[:m]
        R[:m] += tail_R[:m]
    else:
        # trim trailing silence
        e = np.abs(L) + np.abs(R)
        nz = np.nonzero(e > 1e-4)[0]
        end = nz[-1] + 1 if len(nz) else len(L)
        L, R = L[:end], R[:end]
    st = np.stack([L, R], axis=1)
    peak = np.max(np.abs(st)) + 1e-9
    st = st / peak * (10 ** (gain_db / 20))
    # gentle soft clip / glue
    st = np.tanh(st * 1.15) / np.tanh(1.15)
    return st


def write_ogg(path, data, quality=5):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if data.ndim == 1:
        data = data[:, None]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (np.clip(data, -1, 1) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
        os.unlink(tmp.name)
    print("wrote", os.path.relpath(path, ROOT), f"{data.shape[0] / SR:.1f}s")


# ============================================================ composition helpers

def parse_melody(s):
    """'B4:2 D5:1 | ...' -> list of bars, each [(midi|None, beats)]"""
    bars = []
    for bar in s.split("|"):
        bar = bar.strip()
        if not bar:
            continue
        notes = []
        for tok in bar.split():
            nm, d = tok.split(":")
            notes.append((None if nm == "r" else midi(nm), float(d)))
        bars.append(notes)
    return bars


CHORD_TYPES = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10]}


def chord_notes(name):
    root = name[0] + ("#" if len(name) > 1 and name[1] in "#b" else "")
    if len(name) > 1 and name[1] == "b":
        root = name[:2]
    qual = name[len(root):]
    r = NOTE_IDX[root]
    return r, CHORD_TYPES[qual]


def voicing(name, low=52, count=4):
    """chord tones at or above `low` (midi), ascending"""
    r, iv = chord_notes(name)
    tones = []
    m = low - (low % 12) + r
    if m < low:
        m += 12
    base = m - 12
    for octave in range(0, 4):
        for i in iv:
            n = base + 12 * octave + i
            if n >= low:
                tones.append(n)
    tones = sorted(set(tones))
    return tones[:count]


def bass_root(name, low=40):
    r, iv = chord_notes(name)
    m = low - (low % 12) + r
    if m < low:
        m += 12
    return m, m + iv[2] - (12 if m + iv[2] - 12 >= low - 2 else 0)


def check_bars(bars, beats, label):
    for i, b in enumerate(bars):
        s = sum(d for _, d in b)
        if abs(s - beats) > 1e-6:
            sys.exit(f"{label}: bar {i + 1} has {s} beats, expected {beats}")


def place_melody(tr, bars, start, spb, inst, gain, pan, legato=0.95, octave=0):
    t = start
    for bar in bars:
        for m, d in bar:
            if m is not None:
                f = hz(m + octave)
                dur = d * spb * legato
                if inst == "fiddle":
                    s = bowed(f, dur)
                elif inst == "harp":
                    s = reed(f, dur)
                elif inst == "banjo":
                    s = pluck(f, dur, bright=0.95, decay=0.55, pos=0.1)
                else:
                    s = pluck(f, dur, bright=0.6, decay=1.2)
                tr.add(s, t, gain, pan)
            t += d * spb
    return t


# ============================================================ music pieces

def guitar_part(tr, chords, start, spb, beats_per_bar, style, gain=0.32, pan=-0.25):
    t = start
    for ch in chords:
        halves = ch.split(",")
        sub_beats = beats_per_bar / len(halves)
        for h in halves:
            v = voicing(h, 55, 4)
            r, fifth = bass_root(h, 40)
            if style == "waltz":
                tr.add(pluck(hz(r), spb * 1.0, 0.45, 1.8), t, gain * 1.1, pan)
                for b in (1, 2):
                    for j, n in enumerate(v[:3]):
                        tr.add(pluck(hz(n), spb * 0.9, 0.5, 1.2), t + b * spb + j * 0.012, gain * 0.45, pan + 0.1)
            elif style == "travis":
                steps = int(sub_beats * 2)
                for s_i in range(steps):
                    tt = t + s_i * spb / 2
                    if s_i % 2 == 0:
                        bn = r if (s_i // 2) % 2 == 0 else fifth
                        tr.add(pluck(hz(bn), spb, 0.4, 1.4), tt, gain, pan)
                    else:
                        tr.add(pluck(hz(v[(s_i // 2) % len(v) + (1 if len(v) > 2 else 0) - 1]), spb * 0.6, 0.55, 1.0), tt, gain * 0.55, pan + 0.15)
            elif style == "arp":
                seq = [r] + v + v[-2:0:-1]
                steps = int(sub_beats * 2)
                for s_i in range(steps):
                    n = seq[s_i % len(seq)]
                    tr.add(pluck(hz(n), spb * 1.2, 0.35, 2.0), t + s_i * spb / 2, gain * (0.9 if s_i == 0 else 0.55), pan)
            elif style == "boomchuck":
                for b in range(int(sub_beats)):
                    tt = t + b * spb
                    if b % 2 == 0:
                        bn = r if (b // 2) % 2 == 0 else fifth
                        tr.add(pluck(hz(bn), spb * 0.9, 0.4, 1.2), tt, gain, pan)
                    else:
                        for j, n in enumerate(v):
                            tr.add(pluck(hz(n), spb * 0.45, 0.6, 0.6), tt + j * 0.01, gain * 0.38, pan + 0.12)
            t += sub_beats * spb


def banjo_rolls(tr, chords, start, spb, beats_per_bar, gain=0.2, pan=0.35):
    pattern = [0, 1, 2, 0, 1, 2, 0, 2]  # forward roll over 3 strings
    t = start
    for ch in chords:
        for h in ch.split(","):
            v = voicing(h, 62, 3)
            sub = beats_per_bar / len(ch.split(","))
            for s_i in range(int(sub * 2)):
                n = v[pattern[s_i % 8] % len(v)]
                accent = 1.0 if s_i % 3 == 0 else 0.7
                tr.add(pluck(hz(n), spb * 0.5, 0.95, 0.45, 0.1), t + s_i * spb / 2, gain * accent, pan)
            t += sub * spb


def bass_part(tr, chords, start, spb, beats_per_bar, gain=0.35, every=2):
    t = start
    for ch in chords:
        for h in ch.split(","):
            sub = beats_per_bar / len(ch.split(","))
            r, fifth = bass_root(h, 33)
            for b in range(0, int(sub), every):
                n = r if (b // every) % 2 == 0 else fifth
                tr.add(bass(hz(n), spb * every * 0.9), t + b * spb, gain, 0)
            t += sub * spb


def pad_part(tr, chords, start, spb, beats_per_bar, gain=0.12):
    t = start
    for ch in chords:
        for h in ch.split(","):
            sub = beats_per_bar / len(ch.split(","))
            v = voicing(h, 52, 3)
            tr.add(pad([hz(n) for n in v], sub * spb, 0.6, 0.8), t, gain, 0)
            t += sub * spb


def perc_part(tr, bars, start, spb, beats_per_bar, kick_gain=0.25, shake_gain=0.05):
    for bar in range(bars):
        t0 = start + bar * beats_per_bar * spb
        for b in range(beats_per_bar):
            if b % 2 == 0:
                tr.add(kick(), t0 + b * spb, kick_gain)
            for h in range(2):
                tr.add(shaker(), t0 + (b + h * 0.5) * spb, shake_gain * (1.0 if h == 1 else 0.6), 0.3)


def song_title():
    bpm, bpb = 84, 3
    spb = 60 / bpm
    A1 = parse_melody("B4:2 D5:1 | D5:2 B4:1 | C5:2 E5:1 | D5:3 | B4:2 G4:1 | E4:2 G4:1 | A4:3 | r:1 B4:1 C5:1 |")
    A2 = parse_melody("D5:2 B4:1 | G5:2 F#5:1 | E5:2 C5:1 | D5:2 B4:1 | C5:1 B4:1 A4:1 | B4:1 A4:1 G4:1 | A4:2 F#4:1 | G4:3 |")
    B1 = parse_melody("E5:2 G5:1 | E5:2 D5:1 | D5:2 B4:1 | G4:3 | A4:2 C5:1 | E5:2 D5:1 | D5:3 | r:1 D5:1 E5:1 |")
    B2 = parse_melody("G5:2 E5:1 | D5:2 B4:1 | C5:1 B4:1 A4:1 | B4:2 G4:1 | A4:2 B4:1 | C5:2 A4:1 | G4:3 | G4:3 |")
    cA1 = "G G C G Em C D D".split()
    cA2 = "G G C G C G D G".split()
    cB1 = "C C G G Am Am D D".split()
    cB2 = "C G Am G Am D7 G G".split()
    for b, l in ((A1, "A1"), (A2, "A2"), (B1, "B1"), (B2, "B2")):
        check_bars(b, bpb, "title " + l)
    form = [(A1, cA1, False), (A2, cA2, False), (A1, cA1, True), (A2, cA2, True), (B1, cB1, True), (B2, cB2, True), (A1, cA1, True), (A2, cA2, True)]
    total_bars = 8 * len(form)
    secs = total_bars * bpb * spb
    tr = Track(secs)
    t = 0.0
    for mel, ch, play in form:
        guitar_part(tr, ch, t, spb, bpb, "waltz", 0.3)
        bass_part(tr, ch, t, spb, bpb, 0.2, 3)
        pad_part(tr, ch, t, spb, bpb, 0.07)
        if play:
            place_melody(tr, mel, t, spb, "fiddle", 0.3, 0.2, 0.98)
        else:
            place_melody(tr, mel, t, spb, "guitar", 0.28, 0.15, 0.9, 12)
        t += 8 * bpb * spb
    return finish_stereo(tr, secs, rev=0.3, size=1.2)


TRAIL_A1 = "F#4:0.5 A4:0.5 D5:0.5 A4:0.5 F#5:1 E5:0.5 D5:0.5 | E5:0.5 F#5:0.5 E5:0.5 D5:0.5 B4:1 A4:1 | B4:0.5 D5:0.5 G5:0.5 D5:0.5 B4:1 G4:1 | A4:0.5 B4:0.5 A4:0.5 F#4:0.5 D4:2 | F#4:0.5 A4:0.5 D5:0.5 E5:0.5 F#5:0.5 A5:0.5 F#5:0.5 D5:0.5 | E5:1 D5:0.5 B4:0.5 A4:2 | C#5:0.5 E5:0.5 A5:0.5 E5:0.5 C#5:0.5 B4:0.5 A4:1 | B4:0.5 C#5:0.5 D5:0.5 E5:0.5 E5:2 |"
TRAIL_A2 = "F#4:0.5 A4:0.5 D5:0.5 A4:0.5 F#5:1 E5:0.5 D5:0.5 | E5:0.5 F#5:0.5 E5:0.5 D5:0.5 B4:1 A4:1 | B4:0.5 D5:0.5 G5:0.5 D5:0.5 B4:1 G4:1 | A4:0.5 B4:0.5 A4:0.5 F#4:0.5 D4:2 | E4:0.5 A4:0.5 C#5:0.5 E5:0.5 A5:1 G5:0.5 E5:0.5 | C#5:0.5 B4:0.5 A4:0.5 G4:0.5 E4:2 | F#4:0.5 A4:0.5 D5:0.5 F#5:0.5 E5:0.5 C#5:0.5 A4:1 | D5:2 r:2 |"
TRAIL_B1 = "G5:1 B5:0.5 G5:0.5 D5:1 B4:1 | G4:0.5 B4:0.5 D5:0.5 G5:0.5 F#5:1 E5:1 | F#5:1 A5:0.5 F#5:0.5 D5:1 A4:1 | F#4:0.5 A4:0.5 D5:0.5 F#5:0.5 E5:2 | G5:1 B5:0.5 G5:0.5 D5:1 B4:1 | C5:0.5 B4:0.5 A4:0.5 G4:0.5 B4:2 | A4:0.5 C#5:0.5 E5:0.5 A5:0.5 G5:0.5 E5:0.5 C#5:0.5 B4:0.5 | A4:2 r:1 A4:0.5 B4:0.5 |"
TRAIL_B2 = "G5:1 B5:0.5 G5:0.5 D5:1 B4:1 | G4:0.5 B4:0.5 D5:0.5 G5:0.5 F#5:1 E5:1 | F#5:1 E5:0.5 D5:0.5 A4:1 F#4:1 | B4:0.5 C#5:0.5 D5:0.5 F#5:0.5 B5:2 | A5:0.5 G5:0.5 E5:0.5 C#5:0.5 A4:1 C#5:1 | E5:0.5 D5:0.5 C#5:0.5 B4:0.5 A4:2 | D5:0.5 F#5:0.5 A5:0.5 F#5:0.5 E5:0.5 C#5:0.5 A4:0.5 C#5:0.5 | D5:2 D4:2 |"


def song_trail():
    bpm, bpb = 108, 4
    spb = 60 / bpm
    parts = [parse_melody(x) for x in (TRAIL_A1, TRAIL_A2, TRAIL_B1, TRAIL_B2)]
    chords = ["D D G D D D A A".split(), "D D G D A A D D".split(), "G G D D G G A A".split(), "G G D Bm A A D D".split()]
    for i, p in enumerate(parts):
        check_bars(p, bpb, f"trail {i}")
    # form: banjo-led pass (melody on banjo, quieter), then fiddle pass
    form = [(0, "banjo"), (1, "banjo"), (2, "banjo"), (3, "banjo"), (0, "fiddle"), (1, "fiddle"), (2, "fiddle"), (3, "fiddle")]
    secs = len(form) * 8 * bpb * spb
    tr = Track(secs)
    t = 0.0
    for idx, inst in form:
        ch = chords[idx]
        guitar_part(tr, ch, t, spb, bpb, "boomchuck", 0.26, -0.3)
        bass_part(tr, ch, t, spb, bpb, 0.28, 2)
        if inst == "fiddle":
            banjo_rolls(tr, ch, t, spb, bpb, 0.11, 0.4)
            place_melody(tr, parts[idx], t, spb, "fiddle", 0.27, 0.12, 0.92)
        else:
            place_melody(tr, parts[idx], t, spb, "banjo", 0.33, 0.3, 0.95)
        perc_part(tr, 8, t, spb, bpb, 0.14, 0.035)
        t += 8 * bpb * spb
    return finish_stereo(tr, secs, rev=0.2, size=1.0)


def song_night():
    bpm, bpb = 64, 4
    spb = 60 / bpm
    mel = parse_melody("E5:2 C5:1 B4:1 | A4:3 r:1 | B4:2 D5:1 B4:1 | G4:3 r:1 | A4:2 C5:1 A4:1 | F4:2 G4:2 | E4:2 G4:1 C5:1 | B4:3 G#4:1 | A4:2 C5:1 E5:1 | E5:2 D5:1 C5:1 | D5:2 B4:1 G4:1 | G4:4 | A4:2 F4:1 A4:1 | B4:2 D5:2 | C5:1 B4:1 A4:2 | A4:4 |")
    check_bars(mel, bpb, "night")
    ch = "Am Am G G F F C E Am Am G G F G Am Am".split()
    secs = 32 * bpb * spb
    tr = Track(secs)
    for half in range(2):
        t = half * 16 * bpb * spb
        guitar_part(tr, ch, t, spb, bpb, "arp", 0.3, -0.2)
        pad_part(tr, ch, t, spb, bpb, 0.1)
        bass_part(tr, ch, t, spb, bpb, 0.18, 4)
        if half == 1:
            place_melody(tr, mel, t, spb, "harp", 0.24, 0.2, 0.96)
    return finish_stereo(tr, secs, rev=0.35, size=1.3)


def song_town():
    bpm, bpb = 126, 4
    spb = 60 / bpm
    A = parse_melody("D5:0.5 E5:0.5 D5:0.5 B4:0.5 G4:1 B4:1 | D5:1 G5:1 F#5:0.5 E5:0.5 D5:1 | E5:0.5 F#5:0.5 G5:0.5 E5:0.5 C5:1 E5:1 | D5:0.5 B4:0.5 A4:0.5 B4:0.5 G4:2 | D5:0.5 E5:0.5 D5:0.5 B4:0.5 G4:1 B4:1 | D5:1 G5:1 B5:1 G5:1 | A5:0.5 G5:0.5 F#5:0.5 E5:0.5 D5:1 C5:1 | A4:1 B4:0.5 C5:0.5 D5:2 | D5:0.5 E5:0.5 D5:0.5 B4:0.5 G4:1 B4:1 | D5:1 G5:1 F#5:0.5 E5:0.5 D5:1 | E5:0.5 F#5:0.5 G5:0.5 E5:0.5 C5:1 E5:1 | D5:0.5 B4:0.5 A4:0.5 B4:0.5 G4:2 | F#4:0.5 A4:0.5 D5:0.5 F#5:0.5 A5:1 F#5:1 | E5:0.5 D5:0.5 C5:0.5 A4:0.5 F#4:2 | G4:0.5 B4:0.5 D5:0.5 G5:0.5 F#5:0.5 D5:0.5 B4:0.5 A4:0.5 | G4:2 r:2 |")
    B = parse_melody("E5:1 G5:1 E5:1 C5:1 | E5:0.5 F5:0.5 E5:0.5 D5:0.5 C5:2 | B4:1 D5:1 G5:1 D5:1 | B4:0.5 C5:0.5 B4:0.5 A4:0.5 G4:2 | E5:1 G5:1 E5:1 C5:1 | E5:0.5 F#5:0.5 G5:0.5 E5:0.5 C5:2 | A4:0.5 B4:0.5 C5:0.5 D5:0.5 E5:1 F#5:1 | A5:2 F#5:2 | G5:1 E5:1 C5:1 E5:1 | G5:0.5 F#5:0.5 E5:0.5 D5:0.5 C5:2 | D5:1 B4:1 G4:1 B4:1 | E5:0.5 D5:0.5 B4:0.5 G4:0.5 E4:2 | F#4:0.5 A4:0.5 D5:0.5 F#5:0.5 A5:1 F#5:1 | E5:0.5 D5:0.5 C5:0.5 A4:0.5 F#4:2 | G4:0.5 B4:0.5 D5:0.5 G5:0.5 F#5:0.5 D5:0.5 A4:0.5 F#4:0.5 | G4:2 r:2 |")
    check_bars(A, bpb, "town A")
    check_bars(B, bpb, "town B")
    cA = "G G C G G G D D G G C G D D G G".split()
    cB = "C C G G C C D D C C G Em D D G G".split()
    secs = 32 * bpb * spb
    tr = Track(secs)
    for i, (mel, ch) in enumerate(((A, cA), (B, cB))):
        t = i * 16 * bpb * spb
        guitar_part(tr, ch, t, spb, bpb, "boomchuck", 0.28, -0.3)
        banjo_rolls(tr, ch, t, spb, bpb, 0.1, 0.45)
        bass_part(tr, ch, t, spb, bpb, 0.3, 2)
        perc_part(tr, 16, t, spb, bpb, 0.16, 0.04)
        place_melody(tr, mel, t, spb, "fiddle", 0.28, 0.1, 0.9)
    return finish_stereo(tr, secs, rev=0.18, size=0.9)


def song_forage():
    bpm, bpb = 116, 4
    spb = 60 / bpm
    mel = parse_melody("E5:0.5 r:0.5 G5:0.5 r:0.5 E5:0.5 D5:0.5 C5:1 | D5:0.5 E5:0.5 D5:0.5 C5:0.5 G4:2 | A4:0.5 r:0.5 C5:0.5 r:0.5 F5:1 E5:0.5 D5:0.5 | E5:0.5 D5:0.5 C5:0.5 D5:0.5 E5:2 | E5:0.5 r:0.5 G5:0.5 r:0.5 C6:1 B5:0.5 A5:0.5 | G5:0.5 E5:0.5 C5:0.5 E5:0.5 G5:2 | G4:0.5 B4:0.5 D5:0.5 F5:0.5 E5:0.5 D5:0.5 B4:0.5 G4:0.5 | D5:2 r:2 | E5:0.5 r:0.5 G5:0.5 r:0.5 E5:0.5 D5:0.5 C5:1 | D5:0.5 E5:0.5 D5:0.5 C5:0.5 G4:2 | A4:0.5 r:0.5 C5:0.5 r:0.5 F5:1 E5:0.5 D5:0.5 | E5:0.5 D5:0.5 C5:0.5 D5:0.5 E5:2 | F5:0.5 E5:0.5 D5:0.5 C5:0.5 A4:1 C5:1 | B4:0.5 C5:0.5 D5:0.5 F5:0.5 G5:2 | E5:0.5 G5:0.5 C6:0.5 G5:0.5 E5:0.5 D5:0.5 C5:1 | C5:2 r:2 |")
    check_bars(mel, bpb, "forage")
    ch = "C C F C C C G G C C F C F G C C".split()
    secs = 16 * bpb * spb
    tr = Track(secs)
    guitar_part(tr, ch, 0, spb, bpb, "boomchuck", 0.22, -0.3)
    bass_part(tr, ch, 0, spb, bpb, 0.3, 2)
    perc_part(tr, 16, 0, spb, bpb, 0.12, 0.05)
    place_melody(tr, mel, 0, spb, "banjo", 0.3, 0.25, 0.6)
    return finish_stereo(tr, secs, rev=0.15)


def song_victory():
    bpm, bpb = 72, 4
    spb = 60 / bpm
    mel = parse_melody("F#5:2 A5:2 | E5:3 C#5:1 | D5:2 F#5:1 B5:1 | B5:3 A5:1 | A5:2 F#5:1 D5:1 | E5:4 | D5:1 E5:1 F#5:1 G5:0.5 E5:0.5 | D5:4 | D5:4 |")
    check_bars(mel, bpb, "victory")
    ch = ["D", "A", "Bm", "G", "D", "A", "G,A", "D", "D"]
    secs = len(ch) * bpb * spb
    tr = Track(secs + 3)
    guitar_part(tr, ch, 0, spb, bpb, "arp", 0.3)
    pad_part(tr, ch, 0, spb, bpb, 0.16)
    bass_part(tr, ch, 0, spb, bpb, 0.25, 4)
    place_melody(tr, mel, 0, spb, "fiddle", 0.34, 0.1, 0.98)
    place_melody(tr, mel, 0, spb, "fiddle", 0.12, -0.3, 0.98, -12)
    tr.add(bell(hz(midi("D5")), 4.0), (len(ch) - 2) * bpb * spb, 0.15, 0.2)
    return finish_stereo(tr, None, rev=0.35, size=1.3)


def song_gameover():
    bpm, bpb = 60, 4
    spb = 60 / bpm
    mel = parse_melody("B4:2 G4:2 | E4:3 G4:1 | A4:2 C5:1 B4:1 | F#4:4 | E4:4 | r:4 |")
    check_bars(mel, bpb, "gameover")
    ch = ["Em", "C", "Am", "B7", "Em", "Em"]
    tr = Track(len(ch) * bpb * spb + 3)
    guitar_part(tr, ch[:5], 0, spb, bpb, "arp", 0.28)
    pad_part(tr, ch[:5], 0, spb, bpb, 0.12)
    place_melody(tr, mel, 0, spb, "harp", 0.3, 0.15, 0.97)
    return finish_stereo(tr, None, rev=0.4, size=1.3)


# ============================================================ ambience

def noise(n, color="white"):
    w = rng.normal(0, 1, n)
    if color == "pink":
        b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
        a = [1, -2.494956002, 2.017265875, -0.522189400]
        w = signal.lfilter(b, a, w)
    elif color == "brown":
        w = np.cumsum(w)
        w = signal.lfilter([1, -1], [1, -0.995], w)
    return w / (np.max(np.abs(w)) + 1e-9)


def lp(x, f, order=2):
    return signal.lfilter(*signal.butter(order, f / (SR / 2)), x)


def hp(x, f, order=2):
    return signal.lfilter(*signal.butter(order, f / (SR / 2), "high"), x)


def bp(x, lo, hi, order=2):
    return signal.lfilter(*signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band"), x)


def slow_lfo(n, rate, depth, base=1.0):
    t = np.arange(n) / SR
    ph = rng.uniform(0, 6.28)
    return base + depth * (0.6 * np.sin(2 * np.pi * rate * t + ph) + 0.4 * np.sin(2 * np.pi * rate * 2.7 * t + ph * 1.7))


def wind_bed(n, level=1.0, cutoff=700):
    w = lp(noise(n, "pink"), cutoff) * slow_lfo(n, 0.07, 0.45)
    return w * level


def birdsong(seconds, density=1.0):
    tr = Track(seconds)
    t = 0.5
    while t < seconds - 2:
        kind = rng.integers(0, 4)
        pan = rng.uniform(-0.8, 0.8)
        gain = rng.uniform(0.05, 0.16)
        if kind == 0:   # warbler: fast descending trill
            for i in range(rng.integers(5, 10)):
                f0 = 5200 - i * 180 + rng.uniform(-100, 100)
                tr.add(chirp(f0, f0 * 0.82, 0.05), t + i * 0.065, gain, pan)
        elif kind == 1:  # chickadee-like two-note whistle
            tr.add(tone_glide(3900, 3850, 0.32), t, gain, pan)
            tr.add(tone_glide(3300, 3250, 0.4), t + 0.38, gain, pan)
        elif kind == 2:  # thrush-ish flute phrase
            base = rng.uniform(1800, 2600)
            for i, r_ in enumerate([1.0, 1.26, 1.5, 1.33, 1.68]):
                tr.add(tone_glide(base * r_, base * r_ * 1.02, 0.14, vib=40), t + i * 0.12, gain * 0.9, pan)
        else:  # simple chips
            for i in range(rng.integers(2, 5)):
                tr.add(chirp(6500, 4000, 0.03), t + i * 0.18, gain * 0.7, pan)
        t += rng.uniform(1.2, 4.5) / density
    return tr


def chirp(f0, f1, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / dur) ** 2


def tone_glide(f0, f1, dur, vib=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.linspace(f0, f1, n) + vib * np.sin(2 * np.pi * 30 * t)
    e = np.minimum(1, t / 0.02) * np.minimum(1, (dur - t) / 0.06)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * e


def loopify(st, fade=2.0):
    """Crossfade the last `fade` seconds into the start for a seamless loop."""
    f = int(fade * SR)
    body = st[:-f].copy()
    tail = st[-f:]
    ramp = np.linspace(0, 1, f)[:, None]
    body[:f] = body[:f] * ramp + tail * (1 - ramp)
    return body


def stereo_from_track(tr, extra_L=None, extra_R=None, rev=0.3):
    L, R = tr.L[:tr.n], tr.R[:tr.n]
    if extra_L is not None:
        L = L + extra_L
        R = R + extra_R
    L = reverb(L, rev, 1.4, 0)
    R = reverb(R, rev, 1.4, 1)
    st = np.stack([L, R], axis=1)
    return st / (np.max(np.abs(st)) + 1e-9)


def amb_forest(seconds=42):
    tr = birdsong(seconds + 2, 1.0)
    n = tr.n
    wl, wr = wind_bed(n, 0.35), wind_bed(n, 0.35)
    leaves = hp(noise(n), 2500) * slow_lfo(n, 0.11, 0.6) * 0.04
    st = stereo_from_track(tr, wl + leaves, wr + np.roll(leaves, 5000), 0.35)
    return loopify(st * 0.8)


def crickets(seconds):
    tr = Track(seconds)
    for c in range(5):
        f = rng.uniform(3800, 5200)
        rate = rng.uniform(0.45, 0.8)
        pulses = rng.integers(2, 5)
        pan = rng.uniform(-0.9, 0.9)
        g = rng.uniform(0.04, 0.09)
        t = rng.uniform(0, 1)
        while t < seconds:
            for p in range(pulses):
                n = int(0.018 * SR)
                tt = np.arange(n) / SR
                s = np.sin(2 * np.pi * f * tt) * np.sin(np.pi * tt / 0.018)
                tr.add(s, t + p * 0.032, g, pan)
            t += rate * rng.uniform(0.9, 1.1)
    return tr


def crackles(n, density=6.0, level=0.3):
    out = np.zeros(n)
    k = int(n / SR * density)
    for _ in range(k):
        i = rng.integers(0, n - 2000)
        ln = rng.integers(40, 400)
        burst = rng.normal(0, 1, ln) * np.exp(-np.arange(ln) / (ln * 0.25))
        out[i:i + ln] += burst * rng.uniform(0.2, 1.0)
    hiss = lp(noise(n, "brown"), 400) * 0.25
    return (hp(out, 900) * level + hiss * level * 0.6)


def amb_night(seconds=40):
    tr = crickets(seconds + 2)
    n = tr.n
    w = wind_bed(n, 0.18, 400)
    fire = crackles(n, 5, 0.35)
    # a distant owl, once
    owl = Track(seconds + 2)
    t0 = seconds * 0.55
    for i, (dt, d) in enumerate(((0, 0.35), (0.55, 0.22), (0.85, 0.5))):
        s = tone_glide(390, 360, d) * 0.7
        s = lp(s + 0.3 * np.sin(2 * np.pi * 780 * np.arange(len(s)) / SR) * np.abs(s), 1200)
        owl.add(s, t0 + dt, 0.12, -0.5)
    st = stereo_from_track(tr, w + fire + owl.L[:n], w + fire * 0.9 + owl.R[:n], 0.3)
    return loopify(st * 0.8)


def amb_rain(seconds=36, heavy=False):
    n = int((seconds + 2) * SR)
    def layer():
        base = bp(noise(n), 400, 9000) * (0.5 if heavy else 0.32)
        hiss = hp(noise(n), 4000) * 0.18
        drops = np.zeros(n)
        k = int((seconds + 2) * (90 if heavy else 45))
        for _ in range(k):
            i = rng.integers(0, n - 800)
            ln = rng.integers(60, 500)
            f = rng.uniform(1500, 5000)
            tt = np.arange(ln) / SR
            drops[i:i + ln] += np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.004) * rng.uniform(0.1, 0.5)
        return (base + hiss) * slow_lfo(n, 0.05, 0.2) + drops * 0.5
    L, R = layer(), layer()
    if heavy:
        rumble = lp(noise(n, "brown"), 120) * slow_lfo(n, 0.03, 0.8) * 0.9
        L, R = L + rumble, R + rumble
    st = np.stack([reverb(L, 0.2, 1.3, 0), reverb(R, 0.2, 1.3, 1)], axis=1)
    st /= np.max(np.abs(st)) + 1e-9
    return loopify(st * 0.8)


def amb_wind(seconds=40):
    n = int((seconds + 2) * SR)
    def layer():
        g = slow_lfo(n, 0.09, 0.7, 1.0).clip(0.15, None)
        howl = np.zeros(n)
        for f in (300, 520, 900):
            howl += bp(noise(n), f * 0.9, f * 1.1, 2) * slow_lfo(n, 0.05, 0.9).clip(0, None)
        return (lp(noise(n, "pink"), 1500) * 0.7 + howl * 0.8) * g
    st = np.stack([layer(), layer()], axis=1)
    st /= np.max(np.abs(st)) + 1e-9
    return loopify(st * 0.8)


def amb_river(seconds=30):
    n = int((seconds + 2) * SR)
    def layer():
        flow = bp(noise(n, "pink"), 150, 2500) * 0.8
        bub = np.zeros(n)
        for _ in range(int(seconds * 25)):
            i = rng.integers(0, n - 3000)
            d = rng.uniform(0.01, 0.04)
            f0 = rng.uniform(400, 1400)
            s = chirp(f0, f0 * 1.6, d)
            bub[i:i + len(s)] += s * rng.uniform(0.05, 0.25)
        return flow * slow_lfo(n, 0.2, 0.2) + bub
    st = np.stack([layer(), layer()], axis=1)
    st = np.stack([reverb(st[:, 0], 0.25, 1, 0), reverb(st[:, 1], 0.25, 1, 1)], axis=1)
    st /= np.max(np.abs(st)) + 1e-9
    return loopify(st * 0.75)


def amb_town(seconds=36):
    tr = birdsong(seconds + 2, 0.5)
    n = tr.n
    # distant murmur: band-limited noise with syllable-like modulation
    murmur = bp(noise(n), 250, 1100) * np.abs(lp(noise(n), 6)) * 4.0
    murmur = murmur * 0.25
    car = np.zeros(n)
    for start in (seconds * 0.3, seconds * 0.75):
        i = int(start * SR)
        ln = int(4 * SR)
        env = np.sin(np.linspace(0, np.pi, ln)) ** 2
        car[i:i + ln] += lp(noise(ln, "brown"), 300) * env * 0.5
    st = stereo_from_track(tr, murmur + car, murmur * 0.9 + np.roll(car, 2000), 0.25)
    return loopify(st * 0.7)


# ============================================================ sound effects

def fx_norm(x, g=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * g


def fx_click():
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * 1800 * t) * np.exp(-t / 0.006) + 0.4 * rng.normal(0, 1, n) * np.exp(-t / 0.002)
    return fx_norm(bp(s, 600, 6000), 0.5)


def fx_coin():
    s = np.zeros(int(0.9 * SR))
    s[:len(b := bell(1568, 0.6))] += b * 0.6
    b2 = bell(2093, 0.8)
    s[int(0.07 * SR):int(0.07 * SR) + len(b2)] += b2 * 0.7
    n = int(0.05 * SR)
    s[:n] += hp(rng.normal(0, 1, n), 3000) * np.exp(-np.arange(n) / (0.01 * SR)) * 0.3
    return fx_norm(s, 0.7)


def fx_arpeggio(notes, step=0.09, dur=1.4, g=0.7):
    s = np.zeros(int((len(notes) * step + dur) * SR))
    for i, nm in enumerate(notes):
        b = bell(hz(midi(nm)), dur)
        i0 = int(i * step * SR)
        s[i0:i0 + len(b)] += b * (0.8 - i * 0.05)
    return fx_norm(reverb(s, 0.25), g)


def fx_bad():
    s = np.zeros(int(2.0 * SR))
    a = reed(hz(midi("E4")), 0.45)
    b = reed(hz(midi("D#4")), 0.9)
    s[:len(a)] += a
    s[int(0.42 * SR):int(0.42 * SR) + len(b)] += b
    p = pad([hz(midi("E3")), hz(midi("G3"))], 1.2, 0.05, 0.6)
    s[:len(p)] += p * 0.4
    return fx_norm(reverb(s, 0.3), 0.6)


def fx_thunder(seed, dist=1.0):
    r = np.random.default_rng(seed)
    dur = 6.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    crack = hp(r.normal(0, 1, n), 1500) * np.exp(-t / 0.05) * (1.0 / dist)
    rumble = lp(noise(n, "brown"), 180) * 1.4
    env = np.exp(-t / 2.0) * (1 - np.exp(-t / 0.15))
    # rolling bumps
    bumps = np.ones(n)
    for _ in range(6):
        c = r.uniform(0.2, 4.0)
        bumps += 0.8 * np.exp(-((t - c) / r.uniform(0.15, 0.5)) ** 2)
    mid = bp(noise(n), 80, 600) * env * bumps * 0.6
    s = crack * 0.5 + rumble * env * bumps + mid
    st = np.stack([reverb(s, 0.3, 1.5, 0), reverb(s, 0.3, 1.5, 1)], axis=1)
    return fx_norm(st, 0.95)


def fx_bear():
    dur = 1.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 95 + 25 * np.sin(np.pi * t / dur) - 20 * (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin(k * ph) / k for k in range(1, 30))
    rough = 1 + 0.7 * np.sin(2 * np.pi * 28 * t) * (0.5 + 0.5 * rng.normal(0, 1, n).clip(-1, 1))
    s = saw * rough + noise(n) * 0.6
    s = 0.6 * bp(s, 200, 700) + 0.5 * bp(s, 900, 1600) + 0.4 * lp(s, 250)
    env = np.minimum(1, t / 0.12) * np.minimum(1, (dur - t) / 0.4)
    return fx_norm(reverb(s * env, 0.15), 0.85)


def fx_splash():
    dur = 1.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = hp(noise(n), 800) * np.exp(-t / 0.18)
    for _ in range(25):
        i = rng.integers(int(0.1 * SR), n - 3000)
        f0 = rng.uniform(500, 1500)
        c = chirp(f0, f0 * 1.8, rng.uniform(0.01, 0.03))
        s[i:i + len(c)] += c * rng.uniform(0.1, 0.4) * np.exp(-i / SR / 0.6)
    return fx_norm(reverb(s, 0.2), 0.8)


def fx_pickup():
    a = pluck(hz(midi("A5")), 0.1, 0.9, 0.4, 0.1)
    b = pluck(hz(midi("E6")), 0.15, 0.9, 0.5, 0.1)
    s = np.zeros(int(0.7 * SR))
    s[:len(a)] += a[:len(s)]
    i = int(0.06 * SR)
    s[i:i + len(b)] += b[:len(s) - i]
    return fx_norm(s, 0.6)


def fx_toxic():
    dur = 0.8
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 500 * np.exp(-t * 1.2) * (1 + 0.05 * np.sin(2 * np.pi * 9 * t))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR))
    s = lp(s, 2000) * np.minimum(1, (dur - t) / 0.2)
    return fx_norm(s, 0.5)


def fx_whistle():
    s = np.zeros(int(1.3 * SR))
    for k, start in enumerate((0.0, 0.45)):
        d = 0.35
        n = int(d * SR)
        t = np.arange(n) / SR
        f = 2900 + 150 * np.sin(2 * np.pi * 38 * t) + 120 * t / d
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.25 * rng.normal(0, 1, n)
        w = bp(w, 2000, 5000) * np.minimum(1, t / 0.02) * np.minimum(1, (d - t) / 0.04)
        i = int(start * SR)
        s[i:i + n] += w
    return fx_norm(reverb(s, 0.25), 0.6)


def fx_steps():
    """Looping trail footsteps with trekking-pole taps (two hikers, slightly out of step)."""
    secs = 3.6
    n = int(secs * SR)
    s = np.zeros(n + SR)
    for hiker, offset in enumerate((0.0, 0.27)):
        for k in range(8):
            t0 = offset + k * 0.45
            ln = int(0.16 * SR)
            tt = np.arange(ln) / SR
            crunch = bp(rng.normal(0, 1, ln), 300, 3500) * np.exp(-tt / 0.04)
            crunch += lp(rng.normal(0, 1, ln), 200) * np.exp(-tt / 0.02) * 1.5
            gain = (0.8 if k % 2 == 0 else 0.6) * (1.0 if hiker == 0 else 0.7)
            i = int(t0 * SR)
            s[i:i + ln] += crunch * gain
            if k % 2 == 0:
                pl = int(0.03 * SR)
                tp = np.arange(pl) / SR
                tap = np.sin(2 * np.pi * 2400 * tp) * np.exp(-tp / 0.006) * 0.25
                j = int((t0 + 0.2) * SR)
                s[j:j + pl] += tap
    s[:SR] += s[n:n + SR]
    return fx_norm(s[:n], 0.6)


def fx_page():
    dur = 0.45
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = bp(noise(n), 1500, 8000) * np.abs(np.sin(np.pi * t / dur)) ** 0.5 * slow_lfo(n, 14, 0.6)
    return fx_norm(s, 0.4)


def fx_rattle():
    dur = 1.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = hp(noise(n), 3500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 48 * t))) * np.minimum(1, t / 0.05) * np.minimum(1, (dur - t) / 0.3)
    return fx_norm(s, 0.5)


def fx_camera():
    s = np.zeros(int(0.4 * SR))
    for k, t0 in enumerate((0.0, 0.09)):
        ln = int(0.03 * SR)
        c = hp(rng.normal(0, 1, ln), 2000) * np.exp(-np.arange(ln) / (0.005 * SR))
        s[int(t0 * SR):int(t0 * SR) + ln] += c
    return fx_norm(s, 0.5)


# ============================================================ main

def main():
    jobs = {
        "music/title.ogg": song_title,
        "music/trail.ogg": song_trail,
        "music/night.ogg": song_night,
        "music/town.ogg": song_town,
        "music/forage.ogg": song_forage,
        "music/victory.ogg": song_victory,
        "music/gameover.ogg": song_gameover,
        "amb/forest.ogg": amb_forest,
        "amb/night.ogg": amb_night,
        "amb/rain.ogg": lambda: amb_rain(36, False),
        "amb/storm.ogg": lambda: amb_rain(36, True),
        "amb/wind.ogg": amb_wind,
        "amb/river.ogg": amb_river,
        "amb/town.ogg": amb_town,
        "sfx/click.ogg": fx_click,
        "sfx/coin.ogg": fx_coin,
        "sfx/good.ogg": lambda: fx_arpeggio(["G5", "B5", "D6", "G6"]),
        "sfx/event.ogg": lambda: fx_arpeggio(["D5", "A5"], 0.14, 1.6, 0.55),
        "sfx/arrive.ogg": lambda: fx_arpeggio(["G4", "D5", "G5"], 0.16, 2.2, 0.6),
        "sfx/bad.ogg": fx_bad,
        "sfx/thunder1.ogg": lambda: fx_thunder(1, 1.0),
        "sfx/thunder2.ogg": lambda: fx_thunder(2, 1.6),
        "sfx/thunder3.ogg": lambda: fx_thunder(3, 2.5),
        "sfx/bear.ogg": fx_bear,
        "sfx/splash.ogg": fx_splash,
        "sfx/pickup.ogg": fx_pickup,
        "sfx/toxic.ogg": fx_toxic,
        "sfx/whistle.ogg": fx_whistle,
        "sfx/steps.ogg": fx_steps,
        "sfx/page.ogg": fx_page,
        "sfx/rattle.ogg": fx_rattle,
        "sfx/camera.ogg": fx_camera,
    }
    only = sys.argv[1:]
    for path, fn in jobs.items():
        if only and not any(o in path for o in only):
            continue
        data = fn()
        q = 5 if path.startswith("music") else 4
        write_ogg(os.path.join(ROOT, path), data, q)


if __name__ == "__main__":
    main()
