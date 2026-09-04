# ADR 0003: EventBus Single Source of Truth & EntityRegistry Policy

## Status
Accepted

## Context
High-frequency game logic (such as `SiegeBreaker` targeting and `WaveDirector` spawn validation) was performing costly `get_nodes_in_group()` traversals every physics frame. Furthermore, the HUD was subscribed to both direct Player signals and EventBus signals simultaneously, causing double-handling of events.

## Decision
1. **EventBus as Single Source of Truth for UI**:
   - HUD and UI widgets subscribe to `EventBus` signals rather than coupling directly to specific entities in the SceneTree.
   - Dual-connection patterns are removed; direct node signal subscription is retained only as a fallback when `EventBus` is unavailable.
   - Domain code (`DayNightCycle`, `PortalController`) publishes state changes via `EventBus` (`cycle_time_updated`, `portal_evacuated`) and never searches for HUD or UI Control nodes.
   - Presentation logic (e.g., `DayNightLabel` formatting) belongs strictly to the UI layer (`HUD`), which reacts to published time/phase events.
2. **EntityRegistry for High-Frequency Queries**:
   - Implement `EntityRegistry` singleton tracking active buildings, enemies, and bosses.
   - Automatically synchronize with `EventBus` events (`building_placed`, `building_destroyed`, `enemy_killed`, `boss_spawned`, `boss_defeated`).
   - SiegeBreakers and WaveDirector query `EntityRegistry` directly for $O(1)$ counts and squared-distance nearest queries, reducing frame overhead.
   - Retargeting in `SiegeBreaker` is throttled with an interval timer rather than evaluated on every physics frame.
3. **Strict Prohibition of Root `find_child` Fallbacks**:
   - Systems (`HUD`, `DayNightCycle`, `PortalController`, `WorkbenchModal`, `BossGorgon`) must resolve dependencies via explicit typed exported NodePaths or EventBus signals.
   - Dynamic global SceneTree searches (`get_tree().root.find_child(...)`) are completely forbidden in gameplay code.

## Consequences
- **Positive**: Clean UI/domain separation; eliminates redundant signal dispatches; eliminates per-frame SceneTree group scans; provides clean centralized mockability for tests.
- **Negative**: Entities must ensure proper registration/deregistration (handled automatically via EventBus integration).
