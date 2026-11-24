#!/usr/bin/env python3
"""Generate a synthetic rehearsal WAV file for App Store review.

This script creates a short, deterministic RIFF/WAVE file that exercises
BandCut's track-detection pipeline:

- A 5 s false start that should be ignored (under the 40 s minimum).
- Three "song" segments above the -22 dBFS threshold, separated by gaps
  longer than the 8 s bridge window.
- Low-level inter-song "chatter" that tests the chatter filter.

Output is a standard PCM 16-bit stereo 44.1 kHz WAV.
"""

import math
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44100
CHANNELS = 2
BIT_DEPTH = 16
DURATION_SECONDS = 270  # 4 min 30 s
OUTPUT_PATH = Path(__file__).parent.parent / "_tmp" / "bandcut_review_sample.wav"


def db_to_linear(db: float) -> float:
    """Convert dBFS to linear amplitude."""
    return 10 ** (db / 20)


def generate_song_segment(
    duration: float,
    base_freq: float,
    amplitude_db: float = -12.0,
) -> np.ndarray:
    """Return a stereo "song" segment with a few mixed sine tones."""
    samples = int(duration * SAMPLE_RATE)
    t = np.linspace(0, duration, samples, endpoint=False)
    amplitude = db_to_linear(amplitude_db)

    # Mix a few harmonically related tones to simulate a band signal.
    tone = (
        np.sin(2 * math.pi * base_freq * t)
        + 0.5 * np.sin(2 * math.pi * base_freq * 2 * t)
        + 0.3 * np.sin(2 * math.pi * (base_freq * 1.5) * t)
    )

    # Add slow amplitude envelope so it sounds more like a real take.
    envelope = 0.7 + 0.3 * np.sin(2 * math.pi * 0.2 * t)
    tone = tone * envelope

    # Normalize and scale.
    tone = tone / np.max(np.abs(tone)) * amplitude

    # Stereo: slight left/right variation.
    left = tone
    right = tone * 0.85
    return np.column_stack((left, right))


def generate_chatter(duration: float, amplitude_db: float = -35.0) -> np.ndarray:
    """Return quiet inter-song "chatter" that should stay below the gate."""
    samples = int(duration * SAMPLE_RATE)
    amplitude = db_to_linear(amplitude_db)
    noise = np.random.default_rng(seed=42).normal(0, 1, samples)
    # Apply a low-pass-ish shape by smoothing.
    kernel = np.ones(64) / 64
    noise = np.convolve(noise, kernel, mode="same")
    noise = noise / np.max(np.abs(noise)) * amplitude
    return np.column_stack((noise, noise * 0.9))


def generate_silence(duration: float) -> np.ndarray:
    """Return digital silence."""
    samples = int(duration * SAMPLE_RATE)
    return np.zeros((samples, CHANNELS))


def to_16bit_pcm(audio: np.ndarray) -> np.ndarray:
    """Normalize and convert float audio to 16-bit signed integers."""
    peak = np.max(np.abs(audio))
    if peak > 1.0:
        audio = audio / peak
    return (audio * (2 ** 15 - 1)).astype(np.int16)


def main() -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    segments = [
        # A short false start that the app should ignore (< 40 s).
        generate_song_segment(5.0, base_freq=220.0, amplitude_db=-10.0),
        # Silence.
        generate_silence(10.0),
        # Take 1.
        generate_song_segment(75.0, base_freq=196.0, amplitude_db=-12.0),
        # Chatter / tuning gap.
        generate_chatter(15.0, amplitude_db=-36.0),
        # Take 2.
        generate_song_segment(75.0, base_freq=261.6, amplitude_db=-12.0),
        # Silence gap.
        generate_silence(12.0),
        # Take 3.
        generate_song_segment(60.0, base_freq=329.6, amplitude_db=-12.0),
        # Tail silence.
        generate_silence(18.0),
    ]

    audio = np.concatenate(segments, axis=0)
    pcm = to_16bit_pcm(audio)

    with wave.open(str(OUTPUT_PATH), "wb") as wav_file:
        wav_file.setnchannels(CHANNELS)
        wav_file.setsampwidth(BIT_DEPTH // 8)
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(pcm.tobytes())

    print(f"Generated review sample: {OUTPUT_PATH}")
    print(f"Duration: {len(pcm) / SAMPLE_RATE:.1f} s")
    print(f"Size: {OUTPUT_PATH.stat().st_size / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
