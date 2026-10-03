# Issue #56 B6.4: fair pending navigation requests

Actual Godot reproduction of the review corridor (height 0 only on row z=10, height 3 elsewhere; loaded cells; real wall at cell 10,10) confirmed starvation on `9bef64d9`: 16 player builds, 106 wall queries, zero wall builds in 240 public-clock steps. The actual Grunt remained at x=7.5 and the physical wall retained 250 HP. [Before log](before_9bef64d9.log).

The fix queues cold requests in FIFO order within the existing one-build/tick and 0.25-second/profile limits. Actual callers pass a stable target instance ID, so a moving player updates its pending coordinates without adding obsolete goal cells or moving ahead of an older wall. Cache keys still include exact goal cell and clearance profile. At capacity 256, existing requests retain their place and new callers can retry after service; queue records hold only numbers and vectors. World reset clears them, obstacle invalidation preserves fairness and the budget.

In the after public-clock reproduction the wall field became ready on step 16 (about 0.267 seconds): 101 wall queries, 94 positive directions, 16 total builds, at most 2 pending logical targets. The actual Grunt advanced to x=9.579998 and damaged the physical wall from 250 to 226 HP while the target kept moving. Build count is total, because any query may serve an older target from the queue. [After log](after.log), [reproduction harness](repro_after.gd), [source and evidence fingerprints](manifest.json).

Focused GUT: [45/45 monster unit tests, 5,335 assertions](unit.log), [9/9 physical stairs/crowd tests, 31 assertions](integration.log). The integration regression moves the target in its actual physics callback for 240 ticks, requires Grunt movement and wall damage, and bounds rebuilds using the public simulation clock. Unit regressions exercise the exact player-before-wall request order, per-tick/profile limits, latest-cell coalescing, and bounded FIFO capacity. Earlier full verification and paired timing in `../issue56_performance` belong to the preceding implementation and are not claimed as full verification of this fairness patch.

Run the focused regressions from a built/imported candidate checkout:

```powershell
Godot_v4.6.1-stable_win64_console.exe --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_monster_ -gexit
Godot_v4.6.1-stable_win64_console.exe --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -gselect=test_monster_stairs_and_crowd -gexit
Godot_v4.6.1-stable_win64_console.exe --headless --path . --script docs/verification/issue56_fairness/repro_after.gd
```

These finite commands must run under an external process timeout (120 seconds per focused GUT command; 60 seconds for the reproduction). The reproduction contains a controlled test arena and does not measure full-game rendering or performance.
