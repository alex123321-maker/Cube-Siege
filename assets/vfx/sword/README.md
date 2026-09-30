# Steel sword VFX pilot

This is a candidate art direction for the warrior's normal attack. The first ribbon direction received positive visual feedback; the second pass refines contact and hit highlighting. It is not a new combat ability.

## Authoring boundary

- `steel_slash.tres` exposes ribbon/contact textures, body/edge/contact colors, duration, sweep time, ribbon width, emission, shard count, contact size, and contact lifetime.
- `sword_vfx.gd` and `sword_ribbon.gdshader` supply the reusable rendering and lifetime behavior.
- `sword_blade_trail.gd` samples the warrior's displayed guard and tip transforms into a short world-space ribbon. The existing painting is reused; no new raster asset is needed. One renderer is reused while the warrior model is bound, with at most 32 history samples.
- Damage, hitbox, cooldown, and the 60 ms attack event remain in the existing combat code.
- Contact accents require a confirmed target and use that target's position. At most three contact accents are emitted by one swing.
- The contact light is local and short. Camera shake, hit-stop, sound, and balance were not changed for this visual experiment.

For a future small-model trial, supply this directory, the capture harness, and the approved example recording. Restrict the trial to changing the `.tres` art controls, generate three candidates, and compare actual captures before allowing shader changes. This iteration was authored by the current assistant; no smaller model was evaluated yet.

## Texture provenance

`sword_ribbon.png` was generated for this prototype using the built-in Codex image generation tool on 2026-09-29. Original: `exec-a3e54c76-46d5-4743-b87b-6e15026c7bb7.png`. The generated RGBA file was copied without raster edits; its alpha is preserved. UV cropping and tinting happen in the shader. No texture was extracted from a reference game.

Exact generation prompt:

> Use case: stylized-concept. Asset type: production monochrome VFX texture for a 3D action game sword slash ribbon. Generate ONE single horizontal, uncurved, elongated brushstroke energy ribbon on a genuinely transparent background, isolated with generous transparent padding. It will be UV-mapped onto a curved 3D mesh, so the asset itself MUST be STRAIGHT LEFT TO RIGHT, not a crescent. High quality hand-painted fantasy action VFX, painterly and graphic, not photorealistic. Shape: sharp narrow entry at left, widening flowing main body through center-right, tapering to a needle sharp leading tip at the far right. About 5:1 aspect ratio of the painted stroke within the image. A crisp bright ivory-white cutting edge along the upper contour; layered silver-gray wisps peeling from lower contour; 3-5 graceful fine parallel internal streaks, large intentional dark/transparent negative-space splits through the body, controlled dry-brush breakup along trailing edge, very sparse tiny detached shards close to the stroke. Hierarchy of broad solid readable silhouette, medium sweeping torn shapes, fine elegant accents. Truly transparent holes in torn parts. White and neutral gray only so engine can tint the texture. No background glow or bloom baked into empty area, no colored hue, no scene, no character, no weapon, no words, no borders, no checkerboard, no grid, no multiple separate assets. The complete single stroke must be visible without clipping.

## Contact texture, refinement pass

`sword_contact.png` was generated with the built-in Codex image generation tool on 2026-09-29. Original: `exec-d5f10e70-fb64-4288-943b-a092f08ebca1.png`. The original RGBA image was copied unchanged. Tint, growth, and erosion run in `sword_contact.gdshader`; no game-reference texture was extracted.

Exact generation prompt:

> Use case: stylized-concept. Asset type: single monochrome hand-painted melee impact VFX sprite for a polished fantasy action game, to tint gold in engine. On a genuinely transparent background create ONE compact asymmetric burst centered in a square image, whole shape contained with 12 percent transparent margin. A small dense ivory-white sharp contact core, two dominant long tapered curved rays sweeping upper-right and lower-left, five shorter irregular blade-like rays, three thin hooked wisps curling around the core, and a few tiny detached slivers. The silhouette is energetic and angular but the individual streaks have graceful painterly curves. Strong visual hierarchy, crisp pointed tips, silver-gray thin translucent secondary strokes, carved transparent gaps and controlled dry brush breakup inside the larger rays. White and neutral gray only. Flat unlit grayscale VFX mask with actual alpha, no baked surrounding glow, no soft radial halo, no circular ring, no smoke cloud, no scene, no weapon, no character, no lettering, no watermark, no border, no checkerboard, no multiple variants or sprite sheet. It should read as an art-directed metal-on-armor contact flash, not a symmetric geometric star.

The contact root stays at the confirmed target; the visible burst and fragments are offset toward the incoming strike and camera to approximate its surface. This is a presentation offset, not a collision-derived surface normal. Occlusion remains depth-tested.

The shared hurtbox highlight now uses a short translucent overlay, preserving the actor's material and restoring its previous overlay. This visual change applies to all users of `HurtboxArea`, including non-sword hits. Other attack VFX, damage, animations, and cooldowns are unchanged.

## Review media

The third pass adds `blade_trail_start`, `blade_trail_end`, `blade_trail_lifetime`, `blade_trail_opacity`, and `arc_opacity` to the art profile. The start/end values select a visual portion of the authored attack animation and never change its clock or the damage window. Warrior anchor paths live in its animation profile. Other character profiles have no anchors and therefore no sword trail.

The trail uses displayed/interpolated transforms, following the [Godot Node3D guidance](https://docs.godotengine.org/en/4.6/classes/class_node3d.html#class-node3d-method-get-global-transform-interpolated). Old samples remain in world space while the character moves or turns. Teleports, new actions, hidden weapons, and model changes clear history; idle samples expire after 110 ms.

See `docs/verification/vfx_slash_pilot/` and its report. Judge the normal-speed recording and game camera as well as the detail frames. A close-up alone is insufficient evidence of readability.
