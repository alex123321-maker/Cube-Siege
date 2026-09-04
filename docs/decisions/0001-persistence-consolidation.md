# ADR 0001: Consolidated Single-File Persistence & Schema Migration

## Status
Accepted

## Context
Previously, run progress, meta-progression, character rosters, and talent masteries were scattered across three uncoordinated JSON files (`cube_siege_save.json`, `character_roster.json`, and `mastery_save.json`), each maintained by independent managers (`SaveManager`, `RosterManager`, `MasteryManager`). This caused state desynchronization, duplicate schema versions, and divergent permadeath handling on run end.

## Decision
1. Consolidate all persistence under `SaveManager` as the authoritative single source of truth (`user://cube_siege_save.json`).
2. Implement schema versioning with `SAVE_VERSION = 2` and automatic migration from legacy schema v1 and legacy sidecar files.
3. Repurpose `RosterManager` and `MasteryManager` as domain facades delegating storage directly to `SaveManager`.
4. Add `auto_load` configuration flag to allow hermetic unit test isolation without file side-effects.

## Consequences
- **Positive**: Atomic save/load round-trips; eliminates race conditions and inconsistent death/victory records; fully backwards-compatible with v1 save files.
- **Negative**: Domain managers depend on `SaveManager` availability in the scene tree.
