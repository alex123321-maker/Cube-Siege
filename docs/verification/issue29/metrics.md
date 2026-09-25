# Issue #29 Scatter Runtime Profile

- Seed: `1337`; density: `Medium` production default; start window: 49 chunks (7×7).
- Internal density multipliers: Low `0.55`, Medium `0.80`, High `1.00`; cluster grid: `8m`, active clusters: `42%`.
- Per-biome prop rates and variants are authored in `assets/environment/scatter_profiles/{forest,plains,mountains}.tres`.
- Runtime: Godot 4.6.1-stable (official), Windows, Intel(R) Arc(TM) Graphics.
- Synchronous initial terrain + resource + scatter generation: **2420.40 ms** (whole 49-chunk startup, not scatter-only).
- Active terrain chunks: **49**; resource container nodes: **1610**.
- Batched scatter nodes: **13**; MultiMesh instances: **330**; scatter collision nodes: **0**.
- Mean wall-clock frame over 120 samples: **8.84 ms**; Godot process monitor: **8.286 ms**; mean draw calls: **3079**.
- Mean measured render CPU / GPU: **4.66 / 4.25 ms**.
