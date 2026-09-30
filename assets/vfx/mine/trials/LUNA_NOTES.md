# Luna mine art profiles

Both profiles use `MineVFXProfile` and preserve the four texture references and warm engineer palette from `ember_burst.tres`.

## `luna_clear.tres`

Intent: crisp detonation, clearer painted flame folds, and less lingering smoke for crowd readability. Exact changes from `ember_burst.tres`:

- `fire_lifetime`: 0.42 → 0.36 s
- `smoke_lifetime`: 1.3 → 0.82 s
- `smoke_opacity`: 0.72 → 0.54
- `fire_scale`: 1.0 → 0.96
- `smoke_scale`: 1.0 → 0.92
- `emission`: 1.35 → 1.12
- `ring_opacity`: 0.38 → 0.29
- `ember_count`: 28 → 20
- `ember_lifetime`: 0.8 → 0.62 s
- `light_energy`: 1.8 → 1.45

Lower emission and slightly reduced fire size aim to make the source's painted folds easier to read. The shorter, lighter, smaller smoke and reduced ember tail aim to limit visual obstruction.

## `luna_weighty.tres`

Intent: a broader rolling fire mass with a gentle tail and limited smoke occlusion. Exact changes from `ember_burst.tres`:

- `fire_lifetime`: 0.42 → 0.58 s
- `smoke_lifetime`: 1.3 → 1.12 s
- `smoke_opacity`: 0.72 → 0.56
- `fire_scale`: 1.0 → 1.16
- `smoke_scale`: 1.0 → 0.96
- `emission`: 1.35 → 1.16
- `ring_opacity`: 0.38 → 0.32
- `ember_count`: 28 → 26
- `ember_lifetime`: 0.8 → 0.84 s
- `light_energy`: 1.8 → 1.55

The larger, longer-lived fire carries weight; reduced emission and smoke opacity keep the extended tail gentler and limit obstruction.

Neither profile has been rendered or validated. Counts/phases for smoke and fire lobes, the flash and ring timing, dust behavior, and the local light fade are fixed by the reusable effect code. Lower profile opacity cannot guarantee that targets stay visible in a crowd; compare day, night, and crowd captures before judging these goals.
