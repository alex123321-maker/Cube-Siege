# ADR 0002: Player Controller Component Decomposition

## Status
Accepted

## Context
The initial `player_prototype.gd` combined movement, physics, aim projection, damage calculations, parry timing, XP progression, interaction polling, animations, floating text, and class-specific abilities in a single 600+ line monolith. This made unit testing impossible without instantiating full 3D node trees and caused tight coupling between presentation and gameplay rules.

## Decision
1. Decompose player mechanics into focused subsystem components:
   - `PlayerMovement`: WASD movement, speed scaling, dash velocity and cooldowns.
   - `PlayerAim`: Camera raycast plane projection, keyboard twin-stick aim fallback, duel target tracking.
   - `PlayerHealth`: Damage mitigation, parry invulnerability window, death signals.
   - `PlayerProgression`: XP accumulation, level progression thresholds, stats multipliers.
   - `PlayerInteraction`: Candidate tracking, proximity filtering, hold-to-interact execution.
   - `PlayerPresentation`: Blockbench animation playback, portal compass orientation, floating damage popups.
   - `PlayerCombat`: Attack and special attack timers, slash hitbox execution, arrow and piercing projectile spawning, hammer smash repair.
   - `PlayerAbilities`: Class utilities (parry, decoy dummy, remote mine, temp turret), class ultimates (duel tether, eagle eye, tactical nuke), and card upgrade mutations.
2. Maintain `player_prototype.gd` as a thin coordinator façade preserving 100% of the existing public API and exported properties for backward compatibility with scenes and tests.
3. Introduce `InteractableTarget` typed interaction contract with `can_interact`, `get_action_type`, and `execute_interaction`.
4. Ensure all core Player dependencies (`BuildingSystem`, `RadialMenu`, `Portal`) are wired via explicit exported NodePaths without runtime `find_child` fallbacks.

## Consequences
- **Positive**: Subsystems are independently unit-testable; clear division of concerns; reduces risk of regression when adding class abilities.
- **Negative**: Adds component indirection when accessing sub-properties from outside the player entity.
