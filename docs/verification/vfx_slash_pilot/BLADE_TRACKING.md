# Sword VFX — blade tracking pass

The warrior now has a short painted trail sampled from the actual guard and tip of the animated sword. It follows the displayed, interpolated transforms instead of assuming a fixed swing plane. The wider art-directed arc remains, with opacity reduced to 0.65; the warm contact effect is unchanged.

## Behavior and ownership

`PlayerPresentation` binds two explicit anchor paths from the warrior animation profile, creates one reusable `SwordBladeTrail`, and enables emission during 55–220 ms of the normal attack animation. Samples live for 110 ms. These are visual controls; authored clips, hit timing, damage, reach, and cooldowns are unchanged.

Historical endpoints remain in world space during turns and movement. New actions, hidden weapons, teleports larger than two world units between samples, and model replacement clear the history. The mesh holds at most 32 pairs of endpoints. The node is freed when the character model is replaced; ordinary attacks reuse it. Profiles without blade anchors do not create this effect.

The renderer reuses `sword_ribbon.png` from the first pass. No new generated image or extracted game asset was needed. Art parameters live in `assets/vfx/sword/steel_slash.tres`; full texture provenance remains in that directory's README.

Implementation reference: Godot's [displayed-transform API](https://docs.godotengine.org/en/4.6/classes/class_node3d.html#class-node3d-method-get-global-transform-interpolated). The renderer uses these transforms in its render update, with automatic interpolation disabled on the already sampled world-space mesh.

## Actual render evidence

Final recording: `tracked-render.log`, Forward+, Godot 4.6.1, Intel Arc, fixed 60 FPS. The harness locks its internal viewport to 1280×720 even if the desktop window is resized. Early `tracking_*.png` images came from an unlocked viewport and are exploratory; **`tracked_*.png` and the final MP4s are the fixed-size deliverables**.

There are five three-second views: detail/day, game camera/day, game camera/night, stationary crowd/night, and a closer alternate angle with three misses and a slow actor turn. The last view moves the targets away so the sword trail can be judged separately from contact flashes. AI and ordinary player movement remain disabled, as in previous captures; the turn is harness-controlled.

The final sequence records 15 swings: **12 hits, 3 misses, 12 contacts, 300 total damage, zero remaining active effects, and zero remaining trail surfaces**. Fifteen sampled rendered frames check the trail tip against the displayed sword tip. Maximum endpoint error: **0.00000035762787 world units**. Peak sampled history: seven endpoint pairs at 60 FPS.

The bound trail is best visible near the sword in the closer miss view. At game-camera distance it is a small motion cue; the wider arc and gold contact still carry most readability. The wide arc is an exaggerated presentation shape and has not become a physically sampled weapon trail. Performance at many simultaneous attackers or other render rates is not established by this recording.

## Deliverables

- `slash-blade-tracking.mp4`: 18 seconds, 1280×720, 60 FPS. First three seconds are the preserved preceding contact-refinement pass; the remaining fifteen show this implementation in the five views above.
- `blade-tracking-slow.mp4`: 3.12 seconds at quarter speed, showing the miss view and the short trail's decay. Frames are repeated, not synthesized.
- `tracked_4_020.png`, `tracked_4_023.png`, `tracked_4_027.png`, `tracked_4_033.png`: the inspected weapon-motion sequence. Other `tracked_*.png` images cover daylight, night, and crowd.

## Verification

- New focused tests verify real warrior anchor binding, world-space history under translation/rotation, both newest mesh endpoints matching the weapon, complete expiration, teleport breaks, hidden weapons, bounded sample count, new-action reset, and class-switch cleanup.
- Focused tests passed: six tests, 24 assertions, including the existing sword/contact regressions.
- Full GUT suite: **282/282 tests passed, 9,291 assertions**, 47 scripts. Existing teardown warnings remain (13 warnings and one retained resource at shutdown). See `tracked-tests.log`.
- Headless import passed with the previously observed ten-resource editor shutdown warning. Render completed without script or shader errors; existing material-remapping and low-disk-space warnings remain in the log.
- Full `tools/verify.py` was attempted again and stopped at the absent `godot-cpp/SConstruct` in the isolated worktree. This is **not a passing native/build audit**. The existing native debug library was reused, with no C++ changes. See `tracked-audit.log`.
- Import, render, tests, and encoding used bounded subprocess deadlines of 180, 240, 300, and 90 seconds respectively.

The reusable art profile and capture checks can support a later small-model trial. This pass does not claim such a model trial was run.
