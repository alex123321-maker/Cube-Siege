"""Author Cube Siege's original demo score and foley with deterministic synthesis.

No downloaded samples. NumPy generates 44.1 kHz PCM; FFmpeg encodes the loops.
Day and night share a 16-bar D-minor theme, with different instrumentation/tempo.
Run: python tools/generate_demo_audio.py (finite, encoder timeout per file).
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/audio/demo"
RNG = np.random.default_rng(604102)
TAU = math.tau


def clock(seconds: float) -> np.ndarray:
    return np.arange(round(seconds * RATE), dtype=np.float64) / RATE


def hz(note: int) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def noise(seconds: float, low: float, high: float) -> np.ndarray:
    """Band-limited noise with soft spectral shoulders, no sample dependencies."""
    count = round(seconds * RATE)
    spectrum = np.fft.rfft(RNG.normal(size=count))
    frequencies = np.fft.rfftfreq(count, 1 / RATE)
    mask = np.exp(-(frequencies / high) ** 4)
    if low:
        mask *= 1 - np.exp(-(frequencies / low) ** 4)
    result = np.fft.irfft(spectrum * mask, count)
    return result / max(float(np.std(result)), 0.001)


def envelope(t: np.ndarray, attack: float, decay: float) -> np.ndarray:
    return (1 - np.exp(-t / attack)) * np.exp(-t / decay)


def pluck(note: int, seconds: float = 2.4) -> np.ndarray:
    t = clock(seconds)
    f = hz(note)
    out = np.zeros_like(t)
    for partial in range(1, 8):
        out += np.sin(TAU * f * partial * t + partial * 0.09) * np.exp(-t * (2.0 + partial * 1.2)) / partial ** 1.45
    return out * np.minimum(t / 0.004, 1) * 0.6


def flute(note: int, seconds: float) -> np.ndarray:
    t = clock(seconds)
    f = hz(note)
    phase = TAU * f * t + 0.16 * np.sin(TAU * 5.2 * t) * np.minimum(t / 0.25, 1)
    tone = np.sin(phase) + 0.15 * np.sin(phase * 2) + 0.06 * np.sin(phase * 3)
    fade = np.minimum(t / 0.1, 1) * np.minimum((seconds - t) / 0.22, 1)
    return (tone * 0.22 + noise(seconds, 1700, 3600) * 0.012) * np.maximum(fade, 0)


def string(note: int, seconds: float, pulse: bool = False) -> np.ndarray:
    t = clock(seconds)
    out = np.zeros_like(t)
    for partial in range(1, 9):
        for detune in [-0.002, 0.002]:
            out += np.sin(TAU * hz(note) * partial * (1 + detune) * t + partial * 0.5) / partial ** 1.65
    fade = np.minimum(t / (0.035 if pulse else 0.65), 1) * np.minimum((seconds - t) / 0.55, 1)
    return out * np.maximum(fade, 0) * (np.exp(-t * 3.0) if pulse else 0.12)


def drum(kind: str) -> np.ndarray:
    t = clock(0.65)
    if kind == "kick":
        return np.sin(TAU * (48 * t + 5 * (1 - np.exp(-t * 25)))) * np.exp(-t * 8) * 0.72
    if kind == "tom":
        return (np.sin(TAU * (95 * t + 3 * (1 - np.exp(-t * 20)))) * 0.48 + noise(0.65, 120, 2000) * 0.08) * np.exp(-t * 11)
    return noise(0.65, 3300, 11000) * np.exp(-t * (32 if kind == "shaker" else 17)) * 0.15


def add(target: np.ndarray, source: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0) -> None:
    """Circular placement retains reverb/note tails across the loop boundary."""
    indices = (round(at * RATE) + np.arange(len(source))) % len(target)
    stereo = np.column_stack([source * math.sqrt((1 - pan) / 2), source * math.sqrt((1 + pan) / 2)]) * gain
    np.add.at(target, indices, stereo)


def score(night: bool) -> np.ndarray:
    beat = 0.5 if night else 0.75
    seconds = 16 * 4 * beat
    out = np.zeros((round(seconds * RATE), 2))
    chords = [(50, 57, 62, 65, 69), (46, 53, 58, 62, 65), (53, 60, 65, 69, 72), (48, 55, 60, 64, 67)]
    melody = [[74, 77, 76, 72], [74, 70, 69, 65], [69, 72, 77, 76], [72, 67, 69, 72]]
    for bar in range(16):
        at = bar * 4 * beat
        chord = chords[bar % 4]
        for index, note in enumerate(chord[1:]):
            add(out, string(note, beat * 4 + 1.0), at, 0.33 if night else 0.45, (index - 1.5) * 0.27)
        for step in range(8 if night else 4):
            note = chord[(step + bar // 4) % len(chord)] + (12 if step % 3 == 2 else 0)
            add(out, pluck(note, 1.8), at + step * beat * (0.5 if night else 1.0), 0.24 if night else 0.35, (-0.35 if step % 2 else 0.35))
        if bar % 4 != 3 or bar >= 8:
            for step, note in enumerate(melody[bar % 4]):
                if step == 3 and bar % 2 == 0:
                    continue
                add(out, flute(note, beat * (1.7 if step == 3 else 0.85)), at + step * beat, 0.8 if night else 0.65, -0.12)
        if night:
            for step in range(8):
                bass = clock(beat * 0.7)
                low = np.sin(TAU * hz(chord[0] - 12) * bass) * envelope(bass, 0.007, 0.22)
                add(out, low, at + step * beat * 0.5, 0.35)
                add(out, string(chord[step % 3] + 12, beat * 0.8, True), at + step * beat * 0.5, 0.08, 0.2)
                add(out, drum("shaker"), at + (step + 0.5) * beat * 0.5, 0.42, 0.4)
            for step in [0, 2, 2.75]:
                add(out, drum("kick"), at + step * beat, 0.58)
            for step in [1, 3, 3.5 if bar % 4 == 3 else 3.75]:
                add(out, drum("tom"), at + step * beat, 0.45, -0.24)
        else:
            add(out, drum("shaker"), at + 1.5 * beat, 0.10, 0.5)
            add(out, pluck(chord[0] - 12), at, 0.5, -0.1)
    # Cross-channel room reflections; circular to remain seamless.
    dry = out.copy()
    for delay, gain in [(0.113, 0.15), (0.229, 0.12), (0.347, 0.09), (0.613, 0.07)]:
        out += np.roll(dry[:, ::-1], round(delay * RATE), axis=0) * gain
    return out / max(float(np.max(np.abs(out))), 0.001) * 0.76


def effect(name: str) -> np.ndarray:
    duration = 0.45
    if name in ["explosion", "nuke", "boss_roar", "rooster", "level_up", "portal_ready"]:
        duration = 2.1 if name == "nuke" else 1.5
    if name in ["leaves", "crickets", "campfire"]:
        duration = 8.0
    t = clock(duration)
    if name.startswith("footstep"):
        high = 2200 if name.endswith("grass") else 6200
        out = noise(duration, 250, high) * np.exp(-t * 35) * 0.28
        out += np.sin(TAU * 105 * t) * np.exp(-t * 55) * 0.4
    elif name in ["sword", "dash", "bow", "piercing"]:
        out = noise(duration, 600, 7200) * np.exp(-((t - 0.055) / 0.045) ** 2) * 0.25
        if name in ["bow", "piercing"]:
            out += np.sin(TAU * (650 * t - 240 * t * t)) * np.exp(-t * 22) * 0.32
    elif name in ["hit", "hammer", "stone", "wood", "build", "turret", "enemy_attack"]:
        frequency = {"wood": 180, "stone": 850, "hit": 260, "hammer": 80, "build": 160, "turret": 135, "enemy_attack": 110}[name]
        out = np.sin(TAU * frequency * t) * np.exp(-t * 20) * 0.6
        out += noise(duration, 100, 6000) * np.exp(-t * 36) * 0.18
        if name in ["stone", "hammer"]:
            for f in [1230, 2113, 3541]:
                out += np.sin(TAU * f * t) * np.exp(-t * 18) * 0.06
    elif name in ["explosion", "nuke"]:
        out = noise(duration, 0, 2600) * np.exp(-t * 4.5) * 0.21
        out += np.sin(TAU * (48 * t + 8 * (1 - np.exp(-t * 15)))) * np.exp(-t * 4) * 0.5
        out += noise(duration, 1200, 10000) * np.exp(-t * 27) * 0.08
    elif name in ["parry", "magic", "level_up", "portal_ready", "duel", "mine_arm"]:
        out = np.zeros_like(t)
        notes = [74, 77, 81, 86] if name in ["level_up", "portal_ready"] else [62, 69, 74]
        for index, note in enumerate(notes):
            phase_t = np.maximum(0, t - index * 0.10)
            out += np.sin(TAU * hz(note) * phase_t) * envelope(phase_t, 0.002, 0.3) * 0.22
        if name == "parry":
            out += noise(duration, 2000, 9500) * np.exp(-t * 30) * 0.18
    elif name in ["enemy_groan", "boss_roar", "hurt", "death", "boss_windup"]:
        frequency = 54 if name == "boss_roar" else 120
        phase = TAU * frequency * t + 3 * np.sin(TAU * 31 * t)
        out = (np.sin(phase) + 0.32 * np.sin(phase * 3)) * envelope(t, 0.04, duration * 0.35)
        out += noise(duration, 200, 1800) * envelope(t, 0.02, 0.2) * 0.12
    elif name in ["birds", "rooster"]:
        out = np.zeros_like(t)
        starts = [0, 0.19, 0.40, 0.62] if name == "rooster" else [0, 0.14, 0.27]
        for index, at in enumerate(starts):
            local = t - at
            active = (local >= 0) & (local <= (0.55 if index == len(starts) - 1 else 0.18))
            u = np.maximum(local, 0)
            f = 840 if name == "rooster" else 2350
            phase = TAU * (f * u + (220 if name == "rooster" else 1000) * u * u)
            vibrato = 1.8 * np.sin(TAU * 29 * u) if name == "rooster" else 0.2 * np.sin(TAU * 38 * u)
            out += active * np.sin(phase + vibrato) * envelope(u, 0.015, 0.14) * 0.7
    elif name == "leaves":
        # Slow continuous foliage with nonperiodic micro rustles.
        out = noise(duration, 300, 4500) * (0.08 + 0.035 * np.sin(TAU * t / 8) + 0.022 * np.sin(TAU * t * 3 / 8))
    elif name == "crickets":
        out = noise(duration, 3400, 6000) * np.maximum(0, np.sin(TAU * 14 * t)) ** 7 * (0.06 + 0.025 * np.sin(TAU * t / 8))
    elif name == "campfire":
        out = noise(duration, 50, 2000) * 0.06
        for at in RNG.uniform(0, duration, 55):
            u = t - at
            out += (u >= 0) * np.exp(-np.maximum(u, 0) * 130) * noise(duration, 2000, 8500) * 0.08
    else:
        raise ValueError(name)
    if name not in ["leaves", "crickets", "campfire"]:
        out *= np.minimum(t / 0.002, 1) * np.maximum(0, np.minimum((duration - t) / 0.04, 1))
    return np.tanh(out * 1.3) * 0.78


def write_pcm(path: Path, samples: np.ndarray) -> None:
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(2 if samples.ndim == 2 else 1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes((np.clip(samples, -0.98, 0.98) * 32767).astype("<i2").tobytes())


def generate() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {"author": "Cube Siege original procedural score / foley", "seed": 604102, "sample_rate": RATE, "files": {}}
    for name in ["day_theme", "night_theme", "leaves", "crickets", "campfire", "sword", "bow", "piercing", "dash", "hit", "hammer", "stone", "wood", "build", "turret", "enemy_attack", "explosion", "nuke", "parry", "magic", "level_up", "portal_ready", "duel", "mine_arm", "enemy_groan", "boss_roar", "boss_windup", "hurt", "death", "birds", "rooster", "footstep_grass", "footstep_stone"]:
        samples = score(name == "night_theme") if name.endswith("theme") else effect(name)
        loop = name.endswith("theme") or name in ["leaves", "crickets", "campfire"]
        path = OUTPUT / (name + (".ogg" if loop else ".wav"))
        if loop:
            with tempfile.TemporaryDirectory(prefix="cube_audio_") as directory:
                pcm = Path(directory) / "source.wav"
                write_pcm(pcm, samples)
                subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(pcm), "-c:a", "libvorbis", "-q:a", "5", str(path)], check=True, timeout=45)
        else:
            write_pcm(path, samples)
        manifest["files"][path.name] = {"duration": len(samples) / RATE, "loop": loop, "peak": round(float(np.max(np.abs(samples))), 4)}
    (OUTPUT / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Authored {len(manifest['files'])} original audio assets in {OUTPUT}")


if __name__ == "__main__":
    generate()
