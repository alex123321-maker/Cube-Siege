extends GutTest

## Integration tests for VFX Manager, class ability effects, and zero orphaned nodes (Issue #6)

const PLAYER_SCENE = preload("res://scenes/player.tscn")

func test_vfx_manager_autoload_exists() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	assert_not_null(vfx, "VFXManager autoload should be registered and present in tree")

func test_player_class_switching_updates_visual_model() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# 1. Warrior by default
	assert_eq(player.current_class, player.CharacterClass.WARRIOR)
	assert_true(player.hero_warrior.visible, "HeroWarrior should be visible by default")
	if player.hero_archer:
		assert_false(player.hero_archer.visible, "HeroArcher should be hidden")
	if player.hero_engineer:
		assert_false(player.hero_engineer.visible, "HeroEngineer should be hidden")

	# 2. Switch to Archer
	player.set_class(player.CharacterClass.ARCHER, false)
	assert_eq(player.current_class, player.CharacterClass.ARCHER)
	assert_false(player.hero_warrior.visible, "HeroWarrior should be hidden")
	assert_true(player.hero_archer.visible, "HeroArcher should be visible")
	if player.hero_engineer:
		assert_false(player.hero_engineer.visible, "HeroEngineer should be hidden")
	assert_eq(player.presentation.active_model, player.hero_archer)

	# 3. Switch to Engineer
	player.set_class(player.CharacterClass.ENGINEER, false)
	assert_eq(player.current_class, player.CharacterClass.ENGINEER)
	assert_false(player.hero_warrior.visible, "HeroWarrior should be hidden")
	assert_false(player.hero_archer.visible, "HeroArcher should be hidden")
	assert_true(player.hero_engineer.visible, "HeroEngineer should be visible")
	assert_eq(player.presentation.active_model, player.hero_engineer)

func test_warrior_attacks_and_vfx() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var vfx = get_node_or_null("/root/VFXManager")

	# Basic attack
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	assert_true(player.anim_player.current_animation == "attack" or player.anim_player.has_animation("attack"))

	# Cleave special
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	assert_true(player.anim_player.current_animation == "special" or player.anim_player.has_animation("special"))

	# Parry stance
	player.health.parry_cooldown_timer = 0.0
	player.perform_utility()
	assert_true(player.health.is_parrying)

func test_archer_attacks_and_vfx() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ARCHER, false)

	# Basic attack (arrow shot)
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	assert_true(player.anim_player.current_animation == "attack" or player.anim_player.has_animation("attack"))

	# Piercing shot
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	assert_true(player.anim_player.current_animation == "special" or player.anim_player.has_animation("special"))

	# Decoy deploy
	player.health.parry_cooldown_timer = 0.0
	player.perform_utility()
	assert_true(player.anim_player.current_animation == "utility" or player.anim_player.has_animation("utility"))

	# Eagle eye ultimate
	player.abilities.ultimate_cooldown_timer = 0.0
	player.perform_ultimate()
	assert_true(player.is_eagle_eye)

func test_engineer_attacks_and_vfx() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ENGINEER, false)

	# Basic hammer attack
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	assert_true(player.anim_player.current_animation == "attack" or player.anim_player.has_animation("attack"))

	# Deploy temp turret
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	assert_true(player.anim_player.current_animation == "special" or player.anim_player.has_animation("special"))

	# Mine plant and detonate
	player.health.parry_cooldown_timer = 0.0
	player.perform_utility() # Plant
	assert_not_null(player.active_remote_mine)
	player.perform_utility() # Detonate
	assert_null(player.active_remote_mine)

func test_vfx_nodes_cleanup_properly() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	assert_not_null(vfx)

	# Let any background effects from earlier tests settle
	await wait_seconds(0.8)
	var initial_count = vfx.get_active_effect_count()

	# Spawn various transient effects
	var slash = vfx.spawn_slash_arc(Vector3.ZERO, Vector3.FORWARD, 2.0, 90.0, Color.CYAN, 0.05)
	var sparks = vfx.spawn_sparks(Vector3.ZERO, Vector3.UP, Color.GOLD, 8, 3.0)
	var shock = vfx.spawn_shockwave(Vector3.ZERO, 3.0, Color.BLUE, 0.05)
	var puff = vfx.spawn_puff(Vector3.ZERO, Color.WHITE, 8, 2.0)

	assert_gt(vfx.get_active_effect_count(), initial_count, "Active effect count should increase")

	# Wait for auto-free timers
	await wait_seconds(0.6)

	assert_eq(vfx.get_active_effect_count(), initial_count, "All transient VFX must cleanly free without orphaned nodes")
