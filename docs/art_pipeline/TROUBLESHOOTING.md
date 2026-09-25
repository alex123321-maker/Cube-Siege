# Art pipeline troubleshooting

## Blender is not found

Run `.\tools\art_pipeline\setup_blender.ps1` or set `BLENDER_BIN` to `blender.exe`. The setup script downloads only the official 5.2.1 LTS portable archive and verifies its pinned SHA-256 before extraction.

## Blender exits zero after a Python traceback

Always include `--python-exit-code 1`. The repository verification wrapper already does this, so a script exception fails automation.

## Reference images are missing or selectable

Use absolute or repository-relative PNG/JPEG paths supported by Blender. Re-run `import_reference.py`; it replaces `REFERENCES`, sets a common scale, enables `hide_select`, and marks every reference `hide_render`.

## Render is empty or clipped

Ensure visible mesh objects exist and are not `hide_render`. The renderer derives framing from world-space mesh bounds. References, cameras, lights, and empties do not affect framing.

## GLB export reports unapplied scale

In Blender Object mode, apply Scale to mesh objects, then rerun export. Do not compensate with a Godot node scale. Keep the asset root at ground zero and front toward Blender `-Y`.

## Godot says “No loader found” for a new GLB

Force a headless editor import before loading it:

```powershell
& $env:GODOT_BIN --headless --editor --recovery-mode --import --path .
```

Art source files under `art/` are intentionally hidden from Godot by `art/.gdignore`; runtime GLB files belong under `assets/`.

## Godot scans `.blend` and asks for a Blender path

Keep `.blend` sources under `art/`, protected by `.gdignore`, rather than under runtime `assets/`. Only GLB outputs should be imported by Godot.

## Wrong scale or facing

Run the calibration pipeline. Expected report values are height `2.0`, front marker Z greater than zero, mesh materials present, at least two bones, and animation `calibration_idle`. In Blender use metres, Z-up, model front `-Y`, applied mesh scale, and GLB Y-up export.

## AI backend does not run

This revision intentionally approves only `blender-only`. Do not force CUDA packages onto unsupported Intel hardware or system Python. Re-run hardware discovery and perform a new license/security review before adding a pinned backend adapter.

## Disk/cache management

No AI checkpoints are installed by the current pipeline. Future approved backends must place caches on a volume with sufficient space and set explicit locations such as `HF_HOME` and `TORCH_HOME`. Typical upstream defaults are `%USERPROFILE%\.cache\huggingface` and `%USERPROFILE%\.cache\torch`; inspect the resolved path before deleting it. Checkpoints, `.vendor`, virtual environments, and `art/work/` are ignored by Git.

The verified C: drive had only about 2 GiB free, so portable Blender was placed on D:. Never commit `.ckpt`, `.safetensors`, AI cache directories, or downloaded repositories.
