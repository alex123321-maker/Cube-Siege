extends RefCounted
class_name AbilityLibrary

## Laboratory starting points, never replacements for approved class abilities.
static func examples() -> Array[AbilityDefinition]:
	var sector: AbilityDefinition = AbilityDefinition.new()
	sector.title = "01 · Сектор"
	sector.description = "Черновик на основе параметров Рассечения. Проверка центра цели; не точная копия текущего box-hitbox."
	var hit: AbilityStep = AbilityStep.new()
	hit.start = 0.15
	hit.damage = 60.0
	hit.arc_degrees = 180.0
	sector.steps.append(hit)
	var circle: AbilityModifier = AbilityModifier.new()
	circle.label = "Круговая область"
	circle.enabled = false
	sector.modifiers.append(circle)
	var motion: AbilityModifier = AbilityModifier.new()
	motion.label = "Движение во время удара"
	motion.enabled = false
	motion.operation = AbilityModifier.Operation.ADD_ACTION
	motion.action = AbilityStep.new()
	motion.action.slot = "advance"
	motion.action.kind = AbilityStep.Kind.MOVE
	motion.action.distance = 2.0
	motion.action.duration = hit.duration
	sector.modifiers.append(motion)
	var moving: AbilityDefinition = sector.duplicate(true) as AbilityDefinition
	moving.title = "02 · Движущаяся область"
	moving.modifiers[0].enabled = true
	moving.modifiers[1].enabled = true
	var pulse: AbilityDefinition = AbilityDefinition.new()
	pulse.title = "03 · Рецепт с импульсами"
	var recipe: AbilityStep = AbilityStep.new()
	recipe.kind = AbilityStep.Kind.RECIPE
	recipe.slot = "pulse_recipe"
	var area: AbilityStep = AbilityStep.new()
	area.slot = "pulse"
	area.arc_degrees = 360.0
	area.duration = 1.0
	area.repeat_interval = 0.25
	area.follow_actor = false
	recipe.children.append(area)
	pulse.steps.append(recipe)
	return [sector, moving, pulse]
