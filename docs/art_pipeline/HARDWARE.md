# Verified workstation hardware

Captured on 2026-09-05 with `python tools/art_pipeline/check_environment.py --format markdown`.

| Item | Observed value |
| --- | --- |
| OS | Microsoft Windows 11 Home, 64-bit, 10.0.26200 (build 26200) |
| CPU | Intel Core Ultra 9 185H, 16 cores / 22 logical processors |
| RAM | 31.43 GiB |
| GPU | Intel Arc Graphics (integrated) |
| GPU memory | Windows CIM reports 2.0 GiB adapter memory; this is not a supported dedicated-CUDA VRAM configuration |
| GPU driver | Intel 32.0.101.8132 |
| NVIDIA driver | Not installed / no NVIDIA GPU detected |
| CUDA toolkit | Not available (`nvcc` and `nvidia-smi` absent) |
| Repository volume | D:, approximately 539 GiB free at initial inspection |
| System volume | C:, approximately 2.06 GiB free at initial inspection |
| Python | CPython 3.13.5 |
| Git | 2.50.0.windows.2 |
| Blender before task | Not installed/discoverable |
| Blender after setup | 5.2.1 LTS portable, `D:\ProgramFiles\cube-siege-art-tools\blender-5.2.1-windows-x64\blender.exe` |
| Blender archive SHA-256 | `0e631dad7d0cad6d5d18abdd2e2550f6c0213215334eda00ddbd3d22b96ecb2c` |
| Godot | Existing 4.6.1 stable, `D:\ProgramFiles\godot\Godot_v4.6.1-stable_win64_console.exe` |

## Capability decision

| Candidate | Upstream requirement relevant here | Decision |
| --- | --- | --- |
| TRELLIS | Linux-tested, NVIDIA GPU with at least 16 GB VRAM, CUDA toolkit | Rejected on this workstation |
| InstantMesh | CUDA 12.1/PyTorch CUDA path in official setup | Rejected on this workstation |
| TripoSR | About 6 GB VRAM for default inference; CUDA-oriented mesh extraction | Rejected on this workstation; unofficial DirectML ports are not an approved dependency |
| Blender-only | CPU and supported graphics API | Selected and verified end-to-end |

The decision is hardware-based, not a claim that integrated GPU shared memory equals dedicated VRAM. Re-run the report after a hardware change and repeat license/security review before installing a backend.
