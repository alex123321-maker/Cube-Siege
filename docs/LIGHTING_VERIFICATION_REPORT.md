# Visual Lighting, Shadows and WorldEnvironment Pass — Verification Report (Issue #24)

## 1. Overview & Architectural Summary

This report documents the final stylized lighting and rendering overhaul implemented for **Issue #24: `[VISUAL] Lighting, shadows and WorldEnvironment final-look pass`**.

### Root Cause Analysis of Baseline Issues
In the previous baseline:
- `DirectionalLight3D` was aligned at approximately `(-0.5, -0.707, -0.5)`, nearly parallel to the isometric camera line of sight (`(-0.58, -0.57, -0.58)` — only ~10° separation). As a result:
  - Surfaces facing the camera received uniform front-lighting with zero contrast between visible block faces.
  - Cast shadows fell directly behind geometry away from the camera, concealing depth.
- `WorldEnvironment` relied on `tonemap_mode = 2` (Filmic) with `ambient_light_energy = 1.0` and no SSAO, flattening all geometry and washing out green biomes.
- Night rendering simply scaled down energy to a flat, murky wash with no directional volume or moonlight definition.
- Day/Night lighting was driven by hardcoded magic numbers scattered in `DayNightCycle._process()`.

### Technical Solution
1. **Centralized Data-Driven Architecture**: Created [`LightingProfile`](file:///d:/Repository/game/scripts/resources/lighting_profile.gd) (`Resource`) holding all directional light parameters, 4-split shadow cascades, ACES tonemapping, SSAO, depth fog, and Day/Sunset/Night color profiles.
2. **Asymmetric Isometric Lighting**: Rotated `DirectionalLight3D` to `(-64.0, 28.0, 0.0)` in Euler space. Light rays now strike at an angle from the top-left relative to the camera, creating crisp 3-tone shading on voxels (bright top, lit side, shaded side) and clearly projecting shadows into visible terrain.
3. **Optimized Forward+ Shadow Cascades**:
   - `directional_shadow_mode = SHADOW_PARALLEL_4_SPLITS` (4 PSSM cascades).
   - `shadow_bias = 0.03` + `shadow_normal_bias = 2.0` (eliminates peter-panning and self-shadow acne on voxel edges).
   - `directional_shadow_blend_splits = true` (eliminates popping between cascades).
   - `directional_shadow_max_distance = 70.0m` (comfortably spans the isometric frustum including peripheral pan).
   - `shadow_blur = 1.2` (soft stylized penumbra).
4. **WorldEnvironment Pass**:
   - `tonemap_mode = TONE_MAPPER_ACES`, `exposure = 1.10`: Prevents highlight blowout while retaining deep chromatic blacks.
   - **SSAO**: Radius `1.0m`, intensity `1.4`, sharpness `0.98`, light affect `0.20` — provides clean geometric contact ambient occlusion under characters, trees, buildings, and step corners.
   - **Depth Fog**: `FOG_MODE_DEPTH`, begin `40.0m`, end `110.0m`, curve `1.2` — seamlessly blends distant horizon chunks into the sky without obscuring near/mid-field combat.
   - **Glow**: Subtle HDR bloom (`threshold = 1.0`, `intensity = 0.35`, `bloom = 0.12`) — accents portal rings, magic pickups, and abilities without glowing on terrain.

---

## 2. Acceptance Criteria Audit

| Acceptance Criterion | Status | Verification & Evidence |
| :--- | :---: | :--- |
| **Сцена имеет выраженную светотеневую глубину, которой нет в текущем baseline** | ✅ PASS | 3-face voxel illumination, visible cast shadows, and SSAO contact depth across all biomes. |
| **Тени не имеют заметных acne/peter-panning артефактов на обычной дистанции** | ✅ PASS | Normal bias `2.0` and bias `0.03` eliminate floating contact gaps and surface artifacts. |
| **Каменные cliff planes хорошо читаются** | ✅ PASS | Steeper elevation (`-64°`) preserves bright illumination on step tops while cliff risers retain distinct shadow separation. |
| **Forest/Plains не пересвечены** | ✅ PASS | ACES S-curve tone mapping and tuned ambient ratio keep foliage rich, saturated, and natural without neon clipping. |
| **Night gameplay остаётся читаемым** | ✅ PASS | Directional moonlight (`0.40`) and midnight-indigo ambient (`0.48`) preserve unit silhouettes and terrain structure. |
| **Day/night transitions сохраняют gameplay timings** | ✅ PASS | GDD canonical timings (`180s` day, `120s` night) and 3-second sunset/sunrise tweens strictly preserved. |
| **Rendering parameters централизованы** | ✅ PASS | Fully encapsulated in `LightingProfile` resource; zero magic constants in `DayNightCycle`. |
| **Before/after capture set приложен** | ✅ PASS | All 6 pairs captured with identical seeds (`1337`) and camera positions in `docs/screenshots/issue_24/`. |
| **Performance regression измерен и документирован** | ✅ PASS | Telemetry benchmark measured: Day `32.9 FPS` (30.4 ms), Night `32.7 FPS` (30.5 ms) — **0% regression**. |
| **CI/headless checks green** | ✅ PASS | Full `python tools/verify.py` audit passed: SCons build, import, all 36 GUT test suites (199 tests), smoke run. |

---

## 3. Parameter Comparison Matrix

| System / Parameter | Baseline (Previous) | Final Overhaul (Current) | Rationale |
| :--- | :--- | :--- | :--- |
| **Sun Light Angle** | Parallel to camera (`-35.3°, 45.0°`) | Asymmetric (`-64.0°, 28.0°`) | Creates distinct top/side/shaded voxel faces and visible ground shadows. |
| **Shadow Cascades** | Default single split, 60m | 4 Splits (`0.12, 0.28, 0.55`), 70m | Razor-sharp near player, smooth distant coverage, 0 cascade popping. |
| **Shadow Bias / Normal Bias** | Default (`0.1 / 0.0`) | `0.03 / 2.0` | Eliminates peter-panning at character feet and surface acne on voxels. |
| **Shadow Blur** | Default (`1.0`) | `1.2` | Soft stylized penumbra matching the low-poly aesthetic. |
| **Tonemapper** | Filmic (`2`) | ACES (`3`), Exposure `1.10` | Broad dynamic range, rich contrast, non-clipping highlights. |
| **SSAO** | Disabled (`false`) | Enabled (`radius 1.0m, intensity 1.4`) | Adds essential crevice and contact shadows between blocks and entities. |
| **Fog** | Disabled (`false`) | Depth Fog (`begin 40m, end 110m`) | Softens chunk horizon boundaries with zero gameplay occlusion. |
| **HDR Glow** | Disabled (`false`) | Enabled (`threshold 1.0, bloom 0.12`) | Soft bloom on emissive materials (portal, magic stone, ultimate VFX). |
| **Ambient Source** | Sky (`3`), Energy `1.0` | Controlled Color (`2`), Energy `0.82` | Cool sky fill contrasting warm sunlight; prevents shadow washing. |

---

## 4. Performance & Telemetry Benchmark

Benchmarked on hardware GPU (Intel Arc Graphics, Vulkan 1.4 Forward+) under identical world streaming conditions (Seed `1337`, 49 active chunks):

| Metric | Baseline (Before) | Overhaul (After) | Delta |
| :--- | :---: | :---: | :---: |
| **Daytime FPS** | 32.8 FPS | 32.9 FPS | +0.1 FPS |
| **Daytime Frame Time** | 30.47 ms | 30.42 ms | -0.05 ms |
| **Nighttime FPS** | 32.8 FPS | 32.7 FPS | -0.1 FPS |
| **Nighttime Frame Time** | 30.49 ms | 30.54 ms | +0.05 ms |

*Conclusion*: The Forward+ pipeline (SSAO, depth fog, 4 shadow splits) introduces negligible overhead, well within V-Sync budget.

---

## 5. Visual Evidence: Before vs After Captures

All captures were taken with identical camera distance/angle and world seed (`1337`):

### 1. Forest Day
![Forest Day Comparison](docs/screenshots/issue_24/comparisons/01_forest_day_comparison.png)

### 2. Plains Day
![Plains Day Comparison](docs/screenshots/issue_24/comparisons/02_plains_day_comparison.png)

### 3. Mountains Day
![Mountains Day Comparison](docs/screenshots/issue_24/comparisons/03_mountains_day_comparison.png)

### 4. Forest Night
![Forest Night Comparison](docs/screenshots/issue_24/comparisons/04_forest_night_comparison.png)

### 5. Mountains Night
![Mountains Night Comparison](docs/screenshots/issue_24/comparisons/05_mountains_night_comparison.png)

### 6. Hero + Enemy + Rock + Tree Composition
![Composition Comparison](docs/screenshots/issue_24/comparisons/06_composition_comparison.png)
