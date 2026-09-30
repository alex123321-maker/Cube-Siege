# Consolidation into main — 2026-09-30

Starting main: `ab1cc4d6f3314bb177d0dad8d0957b97409924c3`.

## Included work

- Existing uncommitted Codex review-loop support, agent instructions, terrain import settings, and game launcher from the primary checkout. The launcher uses `GODOT_BIN`, `.godot_path`, or Godot on PATH instead of a machine-specific executable path.
- Sword trail/contact, mine blast/terrain imprint, arrow impact, and hit highlight from the uncommitted `codex/vfx-slash-pilot` worktree, including resources, textures, shaders, tests, capture scripts, reports, and their named review media.
- Documentation for registering the existing GPT bridge in Codex and selecting its local connection file.

The tree of `feat/6-production-character-models-vfx` exactly matches squash commit `ed8f905` from PR #7, already in main. Its original history is joined with an `ours` merge to retain the current hero models and later gameplay fixes. The final two documentation edits from `feat/20-vertical-slice-audit` are also already present; its history is joined the same way.

Other local and origin branch tips were already ancestors of the starting main. The old safety stash is preserved: its character scene, presentation code, and animation tests are present in consolidation commit `4d01af0`, also already in main. Later README and ignore-file changes are retained.

Before editing, all changed and untracked files were copied into local safety archives with SHA-256 manifests in `.review_loop/consolidation-20260930/`. The original VFX worktree is retained. Intermediate frame sequences and unreferenced capture logs remain in that archive and source worktree. They are not runtime assets. The archives contain no bridge connection configuration or key.

## Verification of the combined code

`python tools/verify.py` completed with exit code 0 using Godot 4.6.1:

- C++ GDExtension build and headless editor import: PASS.
- GUT: 290 tests across 49 scripts, PASS.
- Python: 135 tests across four test files, PASS.
- Procedural world/combat/streaming: 26 checks, PASS.
- Main menu smoke and gameplay harness: PASS; 24 gameplay checks across three classes.

Full output: [verify.log](verify.log).

A separate Forward+ Vulkan render on Intel Arc ran `capture_mine_pilot.gd` with fixed 60 FPS, label `consolidated`, and `--only-phase=0`. Its immediate radius/damage check passed for five targets: two internal targets ended at 9750 HP, the external target stayed at 10000 HP, and active effects returned to zero. The log contained the existing Godot 3.x SpatialMaterial/specular remapping warning; no runtime or shader error was observed.

The actual generated [burst frame](consolidated_0_012.png) was opened and inspected. The [ground imprint frame](consolidated_0_045.png) is retained for review. This check confirms the combined assets load and render; it does not approve a new art direction or establish a mass-combat performance benchmark.

## GPT bridge

The existing bridge was added to the user's global Codex MCP configuration with STDIO transport; its secret connection file was kept outside the repository. Existing MCP services remain configured. The real server completed initialization, advertised `ask_mentor`, `generate_image`, `get_job`, and `bridge_status`, and returned `connected: true` with the configured Mentor/Imgen projects. The diagnostic client then exited cleanly.

All 31 isolated bridge tests passed, including the real STDIO protocol, job queue, worker transport, browser adapter, and process-lock behavior: [bridge-tests.log](bridge-tests.log). These fixture tests do not demonstrate a newly generated ChatGPT image or mentor answer. Restart MCP in Codex to load the registration into the chat's tool catalog; only one client may own the existing bridge configuration at a time.
