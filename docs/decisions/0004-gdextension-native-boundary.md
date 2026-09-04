# ADR 0004: GDExtension Boundary & Native Probe Architecture

## Status
Accepted

## Context
A graybox `PlayerController` class existed in C++ (`src/player_controller.cpp`), duplicating a small subset of player functionality while the actual game used GDScript (`scripts/player_prototype.gd`). GEMINI.md explicitly designates GDScript as the primary gameplay orchestration layer, reserving C++ GDExtension exclusively for hot paths (Flowfield navigation, swarm simulation, projectile pooling).

## Decision
1. Remove dead graybox `PlayerController` from `src/`.
2. Introduce lightweight `NativeProbe` class bound in `src/register_types.cpp`, exposing `is_native_loaded()` and `get_native_build_version()`.
3. Keep the SCons and GDExtension build pipelines fully active and verified in automated testing (`tools/verify.py` step 3 and GUT step 5).
4. Reserve future C++ additions strictly for performance-critical hot paths per GEMINI.md technological policy.

## Consequences
- **Positive**: Eliminates dead code and architectural ambiguity; preserves working C++ toolchain and CI build integrity; adheres strictly to the project GDExtension policy.
- **Negative**: None.
