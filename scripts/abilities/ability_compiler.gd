extends RefCounted
class_name AbilityCompiler

## Compile once per cast. Never edit authored Resources or running casts.
const MAX_ACTIONS: int = 128
const MAX_DEPTH: int = 8
const MAX_TIME: float = 60.0

static func compile(definition: AbilityDefinition) -> AbilityPlan:
	var plan: AbilityPlan = AbilityPlan.new()
	if definition == null:
		plan.errors.append("Определение отсутствует.")
		return plan
	plan.title = definition.title
	plan.cooldown = definition.cooldown
	plan.draft = definition.draft
	if definition.schema_version != AbilityDefinition.SCHEMA_VERSION:
		plan.errors.append("Неизвестная версия формата: %d." % definition.schema_version)
	if not is_finite(plan.cooldown) or plan.cooldown < 0.0 or plan.cooldown > MAX_TIME:
		plan.errors.append("Перезарядка должна быть в диапазоне 0–60 секунд.")
	var paths: Dictionary[String, bool] = {}
	_walk(definition.steps, "", 0.0, [], paths, plan)
	if plan.actions.is_empty():
		plan.errors.append("Добавьте хотя бы одно действие.")
	var replacements: Dictionary[String, String] = {}
	for modifier: AbilityModifier in definition.modifiers:
		if modifier == null:
			plan.errors.append("Пустой модификатор.")
			continue
		if not modifier.enabled:
			continue
		_apply_modifier(modifier, replacements, paths, plan)
	for action: AbilityPlan.Action in plan.actions:
		_validate_action(action, plan)
		plan.duration = maxf(plan.duration, action.start + action.step.duration)
	for i: int in range(plan.actions.size()):
		var first: AbilityPlan.Action = plan.actions[i]
		if first.step.kind != AbilityStep.Kind.MOVE:
			continue
		for j: int in range(i + 1, plan.actions.size()):
			var second: AbilityPlan.Action = plan.actions[j]
			if second.step.kind == AbilityStep.Kind.MOVE and first.start < second.start + second.step.duration and second.start < first.start + first.step.duration:
				plan.errors.append("Конфликт управления движением: %s / %s." % [first.path, second.path])
	return plan

static func _walk(steps: Array[Resource], prefix: String, offset: float, ancestors: Array[int], paths: Dictionary[String, bool], plan: AbilityPlan) -> void:
	if ancestors.size() > MAX_DEPTH:
		plan.errors.append("Глубина рецепта превышает %d." % MAX_DEPTH)
		return
	for resource: Resource in steps:
		var step: AbilityStep = resource as AbilityStep
		if paths.size() >= MAX_ACTIONS:
			plan.errors.append("Лимит: %d блоков в сборке." % MAX_ACTIONS)
			return
		if step == null:
			plan.errors.append("Пустой блок в %s." % prefix)
			continue
		var path: String = prefix + step.slot
		if step.slot.is_empty() or "/" in step.slot or step.slot.strip_edges() != step.slot:
			plan.errors.append("Некорректное имя слота: %s." % path)
		if paths.has(path):
			plan.errors.append("Повтор имени слота: %s." % path)
		paths[path] = true
		if not is_finite(step.start) or step.start < 0.0:
			plan.errors.append("%s: начало должно быть конечным и неотрицательным." % path)
			continue
		if step.kind == AbilityStep.Kind.RECIPE:
			if ancestors.has(step.get_instance_id()):
				plan.errors.append("Циклический рецепт: %s." % path)
				continue
			if step.children.is_empty():
				plan.errors.append("Пустой рецепт: %s." % path)
			var next: Array[int] = ancestors.duplicate()
			next.append(step.get_instance_id())
			_walk(step.children, path + "/", offset + step.start, next, paths, plan)
		else:
			if not step.children.is_empty():
				plan.errors.append("%s: дочерние блоки допустимы только у рецепта." % path)
			var action: AbilityPlan.Action = AbilityPlan.Action.new()
			action.path = path
			action.start = offset + step.start
			# Copy leaf fields, not potentially cyclic authored subresources.
			action.step = AbilityStep.new()
			action.step.kind = step.kind
			action.step.duration = step.duration
			action.step.damage = step.damage
			action.step.knockback = step.knockback
			action.step.radius = step.radius
			action.step.arc_degrees = step.arc_degrees
			action.step.follow_actor = step.follow_actor
			action.step.repeat_interval = step.repeat_interval
			action.step.terrain_mode = step.terrain_mode
			action.step.distance = step.distance
			plan.actions.append(action)

static func _apply_modifier(modifier: AbilityModifier, replacements: Dictionary[String, String], paths: Dictionary[String, bool], plan: AbilityPlan) -> void:
	var target: AbilityPlan.Action = null
	for action: AbilityPlan.Action in plan.actions:
		if action.path == modifier.target_slot:
			target = action
			break
	if target == null:
		plan.errors.append("%s: слот %s не найден среди действий." % [modifier.label, modifier.target_slot])
		return
	if not is_finite(modifier.value) or modifier.value < 0.0:
		plan.errors.append("%s: значение должно быть конечным и неотрицательным." % modifier.label)
		return
	if modifier.operation == AbilityModifier.Operation.ADD_ACTION:
		var additions: Array[Resource] = [modifier.action]
		var before: int = plan.actions.size()
		_walk(additions, "mod%d/" % plan.actions.size(), target.start, [], paths, plan)
		for i: int in range(before, plan.actions.size()):
			plan.actions[i].source = modifier.label
		return
	if target.step.kind != AbilityStep.Kind.AREA:
		plan.errors.append("%s: требуется блок области." % modifier.label)
		return
	var replacement_key: String = "%s:%d" % [target.path, modifier.operation]
	if modifier.operation in [AbilityModifier.Operation.SET_RADIUS, AbilityModifier.Operation.SET_ARC]:
		if replacements.has(replacement_key):
			plan.errors.append("Конфликт замен: %s / %s (%s)." % [replacements[replacement_key], modifier.label, target.path])
			return
		replacements[replacement_key] = modifier.label
	match modifier.operation:
		AbilityModifier.Operation.SET_RADIUS: target.step.radius = modifier.value
		AbilityModifier.Operation.SET_ARC: target.step.arc_degrees = modifier.value
		AbilityModifier.Operation.SCALE_DAMAGE: target.step.damage *= modifier.value
		AbilityModifier.Operation.ADD_KNOCKBACK: target.step.knockback += modifier.value
		_: plan.errors.append("Неизвестная операция модификатора.")
	target.source += " → " + modifier.label

static func _validate_action(action: AbilityPlan.Action, plan: AbilityPlan) -> void:
	var step: AbilityStep = action.step
	if step.kind < AbilityStep.Kind.AREA or step.kind > AbilityStep.Kind.WAIT:
		plan.errors.append("%s: неизвестный вид действия." % action.path)
	if not is_finite(step.duration) or step.duration < 0.001 or action.start + step.duration > MAX_TIME:
		plan.errors.append("%s: длительность ≥ 0.001 с, конец ≤ 60 секунд." % action.path)
	if step.kind == AbilityStep.Kind.AREA:
		if not is_finite(step.radius) or step.radius < 0.1 or step.radius > 30.0 or not is_finite(step.arc_degrees) or step.arc_degrees <= 0.0 or step.arc_degrees > 360.0:
			plan.errors.append("%s: радиус [0.1, 30] м, угол (0, 360]°." % action.path)
		if not is_finite(step.damage) or step.damage < 0.0 or not is_finite(step.knockback) or step.knockback < 0.0:
			plan.errors.append("%s: урон/отбрасывание должны быть конечными и ≥ 0." % action.path)
		if not is_finite(step.repeat_interval) or step.repeat_interval < 0.0 or (step.repeat_interval > 0.0 and step.repeat_interval < 0.05):
			plan.errors.append("%s: повтор = 0 (однократно) либо ≥ 0.05 с." % action.path)
		if step.terrain_mode not in [TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT, TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT]:
			plan.errors.append("%s: неизвестное правило рельефа." % action.path)
	if step.kind == AbilityStep.Kind.MOVE:
		if not is_finite(step.distance) or absf(step.distance) > 30.0 or absf(step.distance) / maxf(step.duration, 0.001) > 60.0:
			plan.errors.append("%s: перемещение ≤ 30 м, скорость ≤ 60 м/с." % action.path)
