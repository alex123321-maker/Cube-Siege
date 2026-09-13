# Vertical Slice Baseline Profiling Report (Issue #22)

Authoritative baseline performance measurements for the Cube Siege vertical slice following stabilization.

## 1. Hardware & Execution Environment
- **Host OS**: Windows (Windows)
- **Engine**: Godot Engine 4.6.1-stable (official console binary)
- **GPU Adapter**: Intel(R) Arc(TM) Graphics
- **Driver / API**: 1.4.325
- **Display Server**: Windows (1280x720)
- **Scene Tested**: `res://scenes/main.tscn` (complete vertical slice with player, streaming terrain, buildings, AI, and HUD)
- **Launch Command**: `Godot_v4.6.1-stable_win64_console.exe --path . -s tools/profile_vertical_slice_baseline.gd`

## 2. Chunk Streaming & Physics Server 3D Baseline (49 Chunks Window)
Measured on a steady-state 7x7 chunk streaming perimeter (radius 3) centered on the player.

| Metric | Measured Value | Unit | Description |
|---|---|---|---|
| Active Streaming Chunks | 49 | chunks | 7x7 chunk grid centered around player |
| Active Resource Nodes | 1631 | nodes | Generated trees and rock deposits |
| Average `_spawn_chunk_resources` | 12262.30 | µs (12.262 ms) | CPU time per chunk generation step |
| Physics StaticBody3D Nodes | 1336 | bodies | Resource trunks and stone colliders |
| Physics Area3D Nodes | 2759 | areas | Resource canopy and interaction triggers |
| Physics CollisionShape3D Nodes | 4099 | shapes | Registered collision volumes |
| Physics Server Dynamic Active Bodies | 4 | bodies | Dynamic moving physics bodies (player + initial entities) |
| Physics Server 3D Collision Pairs | 10 | pairs | Broadphase active contact test pairs |
| Physics Server 3D Island Count | 8 | islands | Separate collision simulation islands |
| Render Total Draw Calls | 1467 | calls | GPU draw commands in steady state |
| Render Total Primitives | 101094 | primitives | Rendered triangle primitives in view |
| Render Total Objects | 2145 | objects | Visual mesh instances processed |

## 3. Mob Scaling Runtime Performance (0 to 100 Mobs)
Each step was warmed up for 20 frames for physics settlement, then measured over a 30-frame window.

| Mobs | Other CPU / Frame Remainder (ms) | Physics Tick (ms) | Render CPU (ms) | Render GPU (ms) | Total Frame (ms) | Est. FPS | Draw Calls | Active Dynamic Bodies | Collision Pairs |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 27.10 | 2.16 | 1.20 | 3.40 | 30.45 | 32.8 | 1467 | 4 | 14 |
| 10 | 26.28 | 2.87 | 1.23 | 3.66 | 30.38 | 32.9 | 1485 | 14 | 22 |
| 20 | 24.29 | 4.84 | 1.24 | 3.68 | 30.37 | 32.9 | 1487 | 24 | 24 |
| 50 | 22.05 | 6.80 | 1.35 | 3.64 | 30.19 | 33.1 | 1524 | 54 | 55 |
| 100 | 15.86 | 13.22 | 1.37 | 3.68 | 30.46 | 32.8 | 1584 | 104 | 130 |

*Note: 'Other CPU / Frame Remainder' represents CPU frame time outside physics tick and render dispatch (`Total - Physics Tick - Render CPU`), including game logic, scene traversal, and window/vsync frame synchronization.*

## 4. Verification & Bottleneck Analysis
- **Resource Bodies**: 49 chunks contain ~1336 `StaticBody3D` and ~2759 `Area3D` nodes (~4099 collision shapes). Physics Server collision pairs remain low (~10 pairs) in steady state because static bodies sleep effectively in the broadphase tree.
- **Chunk Generation**: Single chunk resource generation (`_spawn_chunk_resources`) averages ~12.262 ms. This isolated resource spawning overhead fits within a single frame slice, though complete chunk generation in practice also includes terrain mesh and collision generation which must remain distributed or threaded across frames.
- **Mob Scaling**: Moving dynamic entities scale cleanly from 0 to 100 mobs. Active dynamic bodies increase from 4 to 104, with collision pairs scaling from 14 to 130 without exponential blowup.
- **Render Breakdown**: In graphical runtime, Render CPU dispatch takes ~1.2-1.4 ms and GPU rendering takes ~3.4-3.7 ms for ~1460-1580 draw calls, confirming the GPU pipeline is stable within 60 Hz budget.

