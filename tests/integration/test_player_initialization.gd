extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CharacterDefinition = preload("res://scripts/resources/character_definition.gd")

func test_player_initialization_defaults_warrior() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	assert_not_null(player.movement)
	assert_not_null(player.health)
	assert_not_null(player.progression)
	assert_not_null(player.aim)
	assert_not_null(player.interaction)
	assert_not_null(player.presentation)
	
	var warrior_def = CharacterDefinition.get_definition(0)
	assert_eq(player.current_class, player.CharacterClass.WARRIOR)
	assert_eq(player.max_health, warrior_def.base_health)
	assert_eq(player.current_health, warrior_def.base_health)
	assert_eq(player.speed, warrior_def.base_speed)
	assert_eq(player.attack_damage, warrior_def.base_attack_damage)
	assert_eq(player.special_damage, warrior_def.base_special_damage)

func test_player_set_class_archer() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	player.set_class(player.CharacterClass.ARCHER, false)
	var archer_def = CharacterDefinition.get_definition(1)
	assert_eq(player.current_class, player.CharacterClass.ARCHER)
	assert_eq(player.max_health, archer_def.base_health)
	assert_eq(player.speed, archer_def.base_speed)
	assert_eq(player.attack_damage, archer_def.base_attack_damage)
	assert_eq(player.special_damage, archer_def.base_special_damage)

func test_player_set_class_engineer() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	player.set_class(player.CharacterClass.ENGINEER, false)
	var eng_def = CharacterDefinition.get_definition(2)
	assert_eq(player.current_class, player.CharacterClass.ENGINEER)
	assert_eq(player.max_health, eng_def.base_health)
	assert_eq(player.speed, eng_def.base_speed)
	assert_eq(player.attack_damage, eng_def.base_attack_damage)
	assert_eq(player.special_damage, eng_def.base_special_damage)
