# Luna soft slash profile

This sibling profile reuses the production script and both existing textures. It keeps the slash lifetime at 0.32 s, sweep time at 0.065 s, and blade-trail timing at 0.055–0.22 s so the responsive reveal and visible emission window remain fixed.

Changed art controls from `steel_slash.tres`:

- `emission`: 1.6 → 1.25, lowering the glow shared by the ribbons, blade trail, and contact sprite.
- `shard_count`: 11 → 8, reducing the small fragments around the broad slash arc.
- `contact_size`: 1.65 → 1.35, reducing contact flash dominance.
- `contact_lifetime`: 0.16 → 0.12 s, shortening the contact sprite's visible fade.
- `arc_opacity`: 0.65 → 0.52, softening both broad arc ribbons.
- `blade_trail_opacity`: 0.9 → 0.72, easing the world-space trail's brightness.

Intent: retain the fast painted cut while softening its glow and reducing the arc/contact hierarchy competition. No render was made for this trial, so visual improvement and behavior at a 0.35 s attack interval are unverified.

Limitations: contact fragments are emitted as a fixed 12 and use fixed 0.24–0.36 s lifetimes in `sword_vfx.gd`; the profile cannot shorten or remove them. Contact light energy and its 0.10 s fade are also fixed there. The lower shared emission and smaller contact sprite cannot guarantee zero overlap clutter. The contact profile lifetime only controls the textured sprite's fade, not those fragments.

## Luna soft-tail follow-up profile

`luna_soft_tail.tres` keeps the responsive sweep and blade emission window fixed at `sweep_time` 0.065 s and `blade_trail_start`/`blade_trail_end` 0.055/0.22 s. Compared with `steel_slash.tres`, it changes:

- `lifetime`: 0.32 → 0.38 s, extending the painted arc's dim fade tail.
- `emission`: 1.6 → 1.05, lowering glow during the longer overlap window.
- `shard_count`: 11 → 8, reducing small arc fragments.
- `contact_size`: 1.65 → 1.30, reducing the contact flash footprint.
- `contact_lifetime`: 0.16 → 0.18 s, giving the contact painting a slightly longer, lower-intensity fade under the lower shared emission.
- `arc_opacity`: 0.65 → 0.48 and `blade_trail_opacity`: 0.9 → 0.66, keeping the arc and trail restrained.
- `blade_trail_lifetime`: 0.11 → 0.14 s, letting sampled trail marks fade more gradually.

The intent is a slightly longer, softer visual tail while retaining the original reveal timing. At a 0.35 s attack cadence the main arc's profile lifetime overlaps the next swing by 0.03 s; opacity/emission are reduced to limit interference, but cadence behavior remains unverified. Contact fragments retain their fixed 0.24–0.36 s lifetimes and count in code, and the contact light fade remains fixed, so the profile cannot ensure clutter-free overlap.

## Luna mine profiles

Both sibling profiles reuse all four existing texture references and preserve the reference warm orange/amber palette.

`luna_clear.tres` targets a crisp detonation with more visible painted flame folds and less lingering smoke in crowds. Compared with `ember_burst.tres`, changes are: `fire_lifetime` 0.42 → 0.36 s; `smoke_lifetime` 1.3 → 0.82 s; `smoke_opacity` 0.72 → 0.54; `fire_scale` 1.0 → 0.96; `smoke_scale` 1.0 → 0.92; `emission` 1.35 → 1.12; `ring_opacity` 0.38 → 0.29; `ember_count` 28 → 20; `ember_lifetime` 0.8 → 0.62 s; `light_energy` 1.8 → 1.45. Lower emission and a slightly reduced fire footprint should help separate the four flame lobes and preserve the texture's folds; reduced smoke duration/opacity/scale and fewer embers aim to keep targets visible.

`luna_weighty.tres` targets a broader, slower rolling fire mass with a gentle smoke tail and controlled occlusion. Compared with `ember_burst.tres`, changes are: `fire_lifetime` 0.42 → 0.58 s; `smoke_lifetime` 1.3 → 1.12 s; `smoke_opacity` 0.72 → 0.56; `fire_scale` 1.0 → 1.16; `smoke_scale` 1.0 → 0.96; `emission` 1.35 → 1.16; `ring_opacity` 0.38 → 0.32; `ember_count` 28 → 26; `ember_lifetime` 0.8 → 0.84 s; `light_energy` 1.8 → 1.55. The fire remains broader and longer while lower emission and opacity limit glare and smoke obstruction.

These are art-only parameter proposals, not evaluated results. No renders or runtime checks were performed. Mine lobe counts, flash duration, dust/ring duration, ember motion, and local light fade are fixed in reusable code; profiles cannot independently change their timing. A longer fire still overlaps more at repeated detonations, and crowd readability requires capture review.
