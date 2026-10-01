extends GutTest

func test_examples_compile_without_mutating_the_source() -> void:
	for definition: AbilityDefinition in AbilityLibrary.examples():
		var plan: AbilityPlan = AbilityCompiler.compile(definition)
		assert_true(plan.valid(), plan.describe())
		assert_true(definition.draft)
	var moving: AbilityDefinition = AbilityLibrary.examples()[1]
	var compiled: AbilityPlan = AbilityCompiler.compile(moving)
	assert_eq(compiled.actions[0].step.arc_degrees, 360.0)
	assert_eq(moving.steps[0].arc_degrees, 180.0)
	assert_eq(compiled.actions.size(), 2)
	assert_almost_eq(compiled.actions[1].start, 0.15, 0.0001)

func test_conflicting_replacements_fail_instead_of_using_last_writer() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[0]
	definition.modifiers[0].enabled = true
	definition.modifiers.append(definition.modifiers[0].duplicate(true) as AbilityModifier)
	var plan: AbilityPlan = AbilityCompiler.compile(definition)
	assert_false(plan.valid())
	assert_string_contains(plan.describe(), "Конфликт замен")

func test_unknown_slot_and_invalid_numbers_are_rejected() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[0]
	definition.modifiers[0].enabled = true
	definition.modifiers[0].target_slot = "deleted/hit"
	definition.steps[0].duration = NAN
	var plan: AbilityPlan = AbilityCompiler.compile(definition)
	assert_false(plan.valid())
	assert_gte(plan.errors.size(), 2)

func test_recipe_offsets_and_semantic_paths() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[2]
	definition.steps[0].start = 0.3
	definition.steps[0].children[0].start = 0.2
	var plan: AbilityPlan = AbilityCompiler.compile(definition)
	assert_eq(plan.actions[0].path, "pulse_recipe/pulse")
	assert_almost_eq(plan.actions[0].start, 0.5, 0.00001)
	assert_almost_eq(plan.duration, 1.5, 0.00001)

func test_recipe_cycles_fail_without_recursing_forever() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[2]
	var recipe: AbilityStep = definition.steps[0]
	recipe.children.append(recipe)
	var plan: AbilityPlan = AbilityCompiler.compile(definition)
	assert_false(plan.valid())
	assert_string_contains(plan.describe(), "Циклический")
	recipe.children.pop_back()

func test_overlapping_motion_owners_fail() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[1]
	var move: AbilityStep = definition.modifiers[1].action.duplicate(true) as AbilityStep
	move.slot = "conflicting_motion"
	move.start = 0.15
	definition.steps.append(move)
	assert_string_contains(AbilityCompiler.compile(definition).describe(), "Конфликт управления")

func test_duplicate_slots_and_unknown_schema_fail() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[0]
	definition.steps.append(definition.steps[0].duplicate(true) as AbilityStep)
	definition.schema_version = 99
	var plan: AbilityPlan = AbilityCompiler.compile(definition)
	assert_false(plan.valid())
	assert_string_contains(plan.describe(), "Повтор имени")
	assert_string_contains(plan.describe(), "версия")

func test_document_roundtrip_and_undo_keep_nested_actions() -> void:
	var document: AbilityLabDocument = AbilityLabDocument.new()
	document.open_definition(AbilityLibrary.examples()[2])
	document.checkpoint()
	document.definition.steps[0].children[0].damage = 77.0
	document.undo()
	assert_eq(document.definition.steps[0].children[0].damage, 25.0)
	document.redo()
	assert_eq(document.definition.steps[0].children[0].damage, 77.0)
	var path: String = "user://test_profile/ability_roundtrip.tres"
	DirAccess.make_dir_recursive_absolute("user://test_profile")
	assert_eq(document.save_to(path), OK)
	var restored: AbilityLabDocument = AbilityLabDocument.new()
	assert_eq(restored.load_from(path), OK)
	assert_eq(restored.definition.steps[0].children[0].damage, 77.0)
	assert_true(AbilityCompiler.compile(restored.definition).valid())
	DirAccess.remove_absolute(path)
