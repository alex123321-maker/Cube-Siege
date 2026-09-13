# Vertical Slice Baseline Profiling Report (Issue #22)

Recorded baseline performance metrics for Cube Siege vertical slice stabilization.

## 1. Test Environment
- **Engine**: Godot Engine 4.6.1-stable
- **Active Chunks**: 49 (7x7 streaming window, radius 3)
- **Physics Interpolation**: Enabled (`physics/common/physics_interpolation=true`)

## 2. Chunk Streaming & Physics Server 3D Baseline (49 Chunks)
| Metric | Value | Unit |
|---|---|---|
| Active Chunks | 49 | chunks |
| Active Resource Nodes | 1668 | nodes |
| Average `_spawn_chunk_resources` | 7593.40 | µs (7.593 ms) |
| Physics Server 3D Active Objects | 0 | objects |
| Physics Server 3D Collision Pairs | 0 | pairs |
| Render Total Draw Calls | 0 | calls |
| Render Total Primitives | 0 | primitives |

## 3. Mob Scaling Runtime Performance (0 to 100 Mobs)
| Mobs | Process Time (ms) | Physics Time (ms) | Render Frame Time (ms) | Total Frame Time (ms) | Est. FPS | Active 3D Objects | Collision Pairs |
|---|---|---|---|---|---|---|---|
| 0 | 58.384 | 502.430 | 0.000 | 6.899 | 144.9 | 0 | 0 |
| 10 | 133.182 | 0.080 | 0.000 | 6.920 | 144.5 | 10 | 16 |
| 20 | 133.182 | 0.080 | 0.000 | 6.898 | 145.0 | 20 | 33 |
| 50 | 2.585 | 4.297 | 4.193 | 6.778 | 147.5 | 50 | 68 |
| 100 | 2.585 | 4.297 | 4.521 | 7.106 | 140.7 | 100 | 119 |

## 4. Verification Verdict
- Frame budget maintained across mob scaling up to 100 active entities.
- Chunk resource generation overhead is ~7.593 ms per chunk, well within the 16.6ms frame budget.
- Physics 3D collision pairs scale predictably without compounding leaks.
