extends PlayerPrototype
class_name GameplaySandboxPlayer

## The production player: input, camera aim, physics, abilities and XP are inherited.
## Only the optional permanent-opening bonus is isolated from normal progression.
var opening_bonuses: bool = false

func uses_meta_progression() -> bool:
	return opening_bonuses
