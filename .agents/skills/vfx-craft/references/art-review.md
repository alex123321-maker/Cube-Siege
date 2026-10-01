# Art review and evidence

## Primary reference shelf

- [Riot: League's VFX Style Guide](https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/) organizes effects around gameplay, value, color, shape, and timing, with clarity and character identity alongside delight. Its principles are useful; its exact style is game-specific. The legacy article can redirect. If it does, use Riot's current [Visual Effects art education](https://www.riotgames.com/en/artedu/visual-effects) and [Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/) instead of treating the redirected home page as the guide.
- [Cyanilux: Sword Slash Shader Breakdown](https://www.cyanilux.com/tutorials/sword-slash-shader-breakdown/) demonstrates a masked texture moving over a prepared mesh with separate noise. It is a Unity implementation example, not a universal slash recipe or an animation integration guide. Evaluate mesh silhouette, UV flow, edge treatment, timing controls, and idle rendering cost before adapting the technique.

Take principles and inspect motion where available. Distinguish an observed reference property from your proposed interpretation. Do not copy a game's assets, proprietary shapes, or palette by default.

## Record the action the player will see

Create a reproducible setup with a known code version, ability parameters, input sequence, positions, deterministic seed when supported, frame rate, renderer, resolution, camera transform, environment settings, and concurrent actor count. Save the invocation and output path with the capture. Keep comparison setup constant except for the intended variation.

Start with normal camera and real-time playback, including sound. Use close views and slow motion to diagnose timing and attachment, then return to the player's view. A beauty camera or isolated black background is useful for inspection, but does not establish gameplay readability. Distinguish normal real-time capture from fixed-step/offline movie rendering; the latter does not establish frame-time performance.

Adapt the following coverage to the game, retaining the conditions that could expose a real failure:

| Context | What to inspect |
| --- | --- |
| Normal gameplay camera, repeated casts | Signature read, rhythm, residue buildup, camera recovery |
| Basic attack and ability in identical conditions | Observable distinction in body action, effect silhouette/reach, and target response |
| Bright/day and dark/night environments | Exposure, contrast, bloom, pale terrain and dark backgrounds |
| Miss, single hit, multiple hits, crowded combat | Truthful impact feedback, actor visibility, competing effects |
| Relevant facing angles and actor/camera rotation | Blade attachment, directional read, foreshortening, backfaces |
| Movement, interruption, rapid recast | Trails stretching, orphaned effects, duplicated sound, stale state |
| Slopes, elevation changes, walls, terrain transitions | Floating decals, intersection, clipping, misleading reach |
| Supported frame rates and representative hardware | Timing consistency, first-use hitch, sustained worst-case cost |

Inspect full-body anticipation, commitment, contact/peak, recovery, and effect dissipation as well as the full sequence. View the body action with VFX disabled diagnostically, then confirm the pose remains readable in the combined recording. Review miss footage for the cast's silhouette and hit footage for visible target-local response; do not let bright contacts conceal a weak ability shape. Include targets at relevant footprint boundaries and compare observed hits with the actual gameplay geometry. Keep geometry/debug overlays separate from the representative capture.

Note concrete observations: "the edge disappears against sand," "the body pose matches the basic attack," or "the blade arrives after the hit burst." A selected still cannot establish temporal quality. Label skipped coverage explicitly.

## Measure and compare

Obtain a baseline and worst-case concurrent cast estimate. Measure CPU/GPU frame time, allocation or spawn spikes, draw calls, transparent overdraw, dynamic lights, audio voice overlap, and cleanup where relevant. Use the project's existing targets; derive a budget from the scene and hardware if none is specified, and disclose that assumption. Particle count alone does not measure cost. Profile actual gameplay separately from offline captures.

Keep a lightweight comparison record: version/variant, intended improvement, representative clip, observed benefit, regression, cost, and retain/reject decision. Compare an alternative in the same conditions; avoid changing camera, exposure, playback speed, and background together. For open-ended polish, test a credible different solution to the weakest feature rather than only variations of brightness or particle count.

Stop when the selected solution satisfies the brief, meaningful coverage reveals no unresolved artistic or gameplay-readability defect, measured cost fits the budget, and the latest credible alternatives provide no clear overall improvement without sacrificing another requirement. This establishes a local optimum under stated conditions, not objective perfection. If every revision fails, change the approach or state the limiting constraint; repetition alone is not progress.

Present the selected result, comparison rationale, and any material limitations. Automated tests establish technical behavior; recordings and reasoned observations establish the current artistic judgment. Neither substitutes for the other's evidence.
