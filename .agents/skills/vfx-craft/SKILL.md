---
name: vfx-craft
description: Design, implement, and refine real-time gameplay VFX for abilities, attacks, impacts, and spell feedback, using in-engine recordings to balance visual quality, readability, timing, and performance. Use for game effects rather than cinematic compositing or standalone concept art.
---

# VFX Craft

Build a distinctive effect that feels native to the game and communicates the action from the player's actual camera. Treat "perfect" as the best demonstrated solution for the current brief and constraints, with honest remaining limitations.

If the active project provides `docs/vfx/START_HERE.md` and `tools/vfx_workbench.py`, read that entry point first. Use its known presets, bounded capture cases, rig report and asset-factory handoff instead of recreating the harness. An art-profile trial remains a proposal until it has current engine evidence and explicit observations; a file-integrity gate does not establish artistic quality.

## Establish the effect's job

Read the active project contract and inspect the actual ability, its basic-attack counterpart, animation, camera, lighting, and existing effects. Identify the source transform, cast and hit events, damage geometry, interruption rules, repetition rate, target hardware, and concurrent effect count. Separate an authorized gameplay change from a presentation change; this skill does not expand the user's scope or external-action permissions.

Express the art direction in a short working brief: intended sensation, signature shape, material language, palette roles, and the gameplay information the viewer must read. Use references for specific observations such as timing, shape breakup, or impact contrast. When reference research is needed, read the primary sources in [references/art-review.md](references/art-review.md); inspect available motion examples rather than assuming a screenshot describes movement. Record asset provenance and usage terms before integrating outside assets. A generated concept is an exploration, not proof of engine quality.

## Compose before decorating

- Establish one dominant silhouette readable at normal gameplay distance. Preserve a clear direction and center of action; use negative space to retain the actor, weapon, and target silhouettes.
- Give brightness and contrast a hierarchy: the decisive action owns the strongest accent; supporting trails, smoke, debris, and residue stay subordinate. Inspect grayscale and subdued bloom to expose a weak underlying shape.
- Assign colors a job: source identity, hot accent, body, or dissipation. Judge against the game's environments and other abilities. Avoid selecting a fixed palette merely because a reference uses it.
- Design anticipation, commitment, impact, and dissipation as a deliberate energy curve. Concentrate the peak at the meaningful event, then release energy with changing shape and motion; a uniform fade often feels inert. Derive durations from the actual action and viewing conditions.
- For a physical attack, make the body's anticipation, commitment, and recovery carry the action: stance, torso, arms, and weapon should express coordinated force from the actual camera. Inspect the pose without VFX, then preserve it with VFX enabled. A bigger trail cannot substitute for an indistinguishable attack animation.
- Make weapon effects follow the demonstrated blade path or another explicitly designed emission source. Align the source, sweep, damage event, target reaction, sound, and any camera impulse. A decorative arc centered near the player is not automatically a convincing sword trail.
- Keep the perceived threat consistent with actual hit geometry. Derive the damaging footprint's presentation from the gameplay geometry and transforms, including arc, reach, origin, and vertical limits, instead of maintaining a separate shape by eye. Distinguish a harmless flourish from a damaging boundary; correct a mismatch within the user's authorized scope.
- Give confirmed hits expressive feedback on the struck target: a local contact accent and appropriate visual reaction should convey the direction and force while retaining its silhouette. Use actual contacts or target geometry rather than a generic flash at the caster. Check multiple targets and a miss; shared cast spectacle must not hide which targets were hit or invent impact feedback.
- Give particles directional purpose and material behavior. Controlled asymmetry can add character; random omnidirectional glitter can erase force. Choose a few useful layers and remove any that do not strengthen the read.

Build the shape and timing first, then material breakup, particles, audio, and camera support. Tune each layer in context. Audio should reinforce the event and material; camera movement should reinforce force while preserving aiming, visibility, and the game's existing comfort settings.

## Iterate through evidence

Read [references/art-review.md](references/art-review.md) for repeatable comparison, recording coverage, performance checks, and the stopping criterion. For Godot implementation, also read [references/godot.md](references/godot.md).

Compare meaningful alternatives using the same scene and capture settings. For an ability meant to exceed or differ from a basic attack, record both in identical conditions and name the visible distinction in body action, footprint, and target response; increased brightness alone does not demonstrate it. Diagnose the weakest visible feature before each revision; change the variables needed to test that diagnosis. Revert changes that add spectacle while weakening the brief, readability, or budget. Prefer eliminating a poor layer to compensating with more layers.

Deliver a representative engine recording, concise changes and tradeoffs, actual validation results, and any unobserved conditions. Keep technical correctness separate from artistic judgment. Do not invent numeric quality thresholds, test passes, user approval, mentor approval, or a guarantee that no better effect can exist.
