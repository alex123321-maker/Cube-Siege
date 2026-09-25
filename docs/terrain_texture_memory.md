## Terrain Material Kit — Texture Memory Documentation

### Issue #26 Performance Requirement

Per Issue #26 Performance section: shared material resources, no material instances per cell.

### Texture Inventory

| Texture | Resolution | Format | VRAM (uncompressed) | Role |
|---|:---:|:---:|---:|---|
| `forest_grass_top.png` | 16×16 | RGBA8 | 1 024 B (1 KB) | Forest biome top face |
| `plains_meadow_top.png` | 16×16 | RGBA8 | 1 024 B (1 KB) | Plains biome top face |
| `mountain_stone_top.png` | 16×16 | RGBA8 | 1 024 B (1 KB) | Mountain biome top face |
| `cliff_side.png` | 16×16 | RGBA8 | 1 024 B (1 KB) | Cliff / rock side face |
| `dirt_soil.png` | 16×16 | RGBA8 | 1 024 B (1 KB) | Soil / dirt accent |
| `terrain_atlas.png` | 64×64 | RGBA8 | 16 384 B (16 KB) | Full 16-region atlas |
| **TOTAL** | | | **21 504 B (21 KB)** | |

### Runtime Sharing

- **4 active materials** at runtime: `mat_forest`, `mat_plains`, `mat_mountains`, `mat_cliff`.
- Each material is a **shared `StandardMaterial3D` resource** loaded once via `load()`.
- `ChunkBuilder` receives material references — **zero per-cell material instances**.
- Disk size of all 5 individual PNGs: **1 442 bytes** (heavily compressed PNG).
- `terrain_atlas.png` disk: **4 473 bytes**.
- **Total disk footprint: 5 915 bytes (~5.8 KB)**.

### Mipmaps

Mipmaps are **disabled** (`mipmaps/generate=false`) — correct for nearest-filtered voxel tiles where mipmaps would introduce unwanted blurring at distance. The full 21 KB is the complete VRAM cost with no mip chain overhead.

### Previous State (Prototype)

`_create_voxel_texture()` created a new `ImageTexture` per startup (not cached as a resource), consuming the same ~5 KB VRAM but losing shareability across reloads. Removed in this PR.
