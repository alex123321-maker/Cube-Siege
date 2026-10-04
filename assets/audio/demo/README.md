# Original demo audio

All 33 files are authored for Cube Siege by `tools/generate_demo_audio.py`;
there are no downloaded samples or third-party recordings. The seed and each
file's duration/peak are in `provenance.json`. Source synthesis uses NumPy,
44.1 kHz PCM and FFmpeg Vorbis encoding. The assets share the repository's license.

The 48-second daytime score uses a sparse plucked/flute melody; its 32-second
nighttime counterpart adds bass, strings and percussion at 120 BPM. Both share
a harmonic theme and retain note/reflection tails across their loop boundaries.
`RunAudio` crossfades between them. Leaves, crickets and hearth crackle are
separate ambience loops. Combat, construction, movement and wildlife use the
individual WAV cues.

`GameSettings` persists Master/Music/SFX/Ambience levels. Runtime sound voices
are spatial, range limited and capped at 24. Headless verification loads the
same assets and exercises state without requiring a playback device.

To regenerate, run `python tools/generate_demo_audio.py` with NumPy and FFmpeg
available, under a 300-second process timeout. Each encoder invocation has its
own 45-second timeout. PCM checks cover decoding, duration, non-silence and
clipping; they do not establish subjective musical quality.
