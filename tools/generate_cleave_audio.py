"""Create the original layered steel cleave cue; no downloaded audio samples.

Deterministic mono PCM, filtered air rush + bass impact + damped metal partials.
Run: python tools/generate_cleave_audio.py
"""
import math
from pathlib import Path
import random
import struct
import wave


def generate() -> None:
    rate = 48000
    duration = 0.62
    rng = random.Random(83157)
    samples = []
    low = 0.0
    air = 0.0
    for index in range(int(rate * duration)):
        t = index / rate
        noise = rng.uniform(-1.0, 1.0)
        low += 0.045 * (noise - low)
        air += 0.40 * (noise - air)
        attack = min(t / 0.005, 1.0)
        impact = math.sin(math.tau * (76.0 * t - 34.0 * t * t)) * math.exp(-t * 28.0)
        rush = (air - low) * math.exp(-((t - 0.06) / 0.095) ** 2)
        metal = sum(
            math.sin(math.tau * frequency * t + phase) * math.exp(-t * decay) * weight
            for frequency, decay, weight, phase in (
                (693.0, 16.0, 0.09, 0.0),
                (1177.0, 21.0, 0.06, 0.3),
                (1931.0, 28.0, 0.035, 1.1),
                (3079.0, 36.0, 0.018, 2.3),
            )
        )
        sample = attack * (impact * 0.62 + rush * 0.8 + metal + low * math.exp(-t * 19.0) * 0.7)
        samples.append(sample * min((duration - t) / 0.04, 1.0))
    peak = max(abs(value) for value in samples)
    output = Path(__file__).resolve().parents[1] / "assets/vfx/cleave/cleave_release.wav"
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes(b"".join(struct.pack("<h", round(value / peak * 28500)) for value in samples))
    print(f"Generated {output} ({duration}s, {rate}Hz)")


if __name__ == "__main__":
    generate()
