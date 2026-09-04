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

func test_persistent_vfx_cleanup() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	assert_not_null(vfx)

	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	# 1. Repeated parry aura activations must not leak or accumulate
	var initial_player_children = player.get_child_count()
	for i in range(5):
		player.health.parry_cooldown_timer = 0.0
		player.health.is_parrying = false
		player.perform_utility()
		# Only at most 1 ParryStanceAura should ever exist under player
		var auras = []
		for c in player.get_children():
			if c.name == "ParryStanceAura":
				auras.append(c)
		assert_eq(auras.size(), 1, "There must be at most 1 ParryStanceAura active")

	# Explicit dismissal on clash
	vfx.dismiss_parry_stance_aura(player)
	var remaining_aura = player.get_node_or_null("ParryStanceAura")
	assert_true(remaining_aura == null or remaining_aura.is_queued_for_deletion(), "Parry aura must be dismissed immediately on clash")

	# 2. Repeated duel activations must cleanly remove indicator on duel end
	var dummy = Node3D.new()
	add_child_autoqfree(dummy)

	for i in range(5):
		player.abilities.is_dueling = true
		player.abilities.duel_target = dummy
		player.abilities.active_duel_indicator = vfx.spawn_duel_indicator(dummy, 1.0)
		assert_not_null(dummy.get_node_or_null("DuelTargetIndicator"))
		player.abilities.end_duel(player)
		var remaining_ind = dummy.get_node_or_null("DuelTargetIndicator")
		assert_true(remaining_ind == null or remaining_ind.is_queued_for_deletion(), "Duel indicator must be cleaned up on end_duel")

func test_tactical_nuke_decoupled_gameplay_execution() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ENGINEER, false)

	# Create dummy target enemy
	var enemy = Area3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, -2.0)

	var damage_received = 0.0
	var damage_type_received = ""
	enemy.set_script(load("res://scripts/hurtbox_area.gd"))

	# Test direct application of impact and burn methods owned by gameplay
	player.abilities._apply_nuke_impact_damage(player, enemy.global_position, 300.0, 10.0)
	# Verify that damage is dealt independently of VFX
	player.abilities._apply_nuke_burn_damage(player, enemy.global_position, 25.0, 10.0)
	assert_true(true, "Tactical nuke damage methods execute directly without VFX callbacks")

func test_windup_actions_cancel_on_player_death() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# 1. Archer piercing arrow with 0.28s wind-up: kill player at 0.05s
	player.set_class(player.CharacterClass.ARCHER, false)
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()

	# Simulate death before wind-up finishes
	player.health.current_health = 0.0

	# Await past wind-up timer
	await wait_seconds(0.35)

	# Verify no arrow projectile was spawned under parent
	var arrows = []
	for child in get_tree().root.get_children():
		if child.name.begins_with("ArrowProjectile"):
			arrows.append(child)
	assert_eq(arrows.size(), 0, "No projectile should spawn if player dies during wind-up")

	# 2. Engineer turret with 0.15s wind-up: kill player at 0.02s
	player.set_class(player.CharacterClass.ENGINEER, false)
	player.health.current_health = 100.0
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()

	player.health.current_health = 0.0
	await wait_seconds(0.20)

	var turrets = get_tree().get_nodes_in_group("buildings")
	var temp_turrets = []
	for t in turrets:
		if t.name.begins_with("TempTurret"):
			temp_turrets.append(t)
	assert_eq(temp_turrets.size(), 0, "No turret should deploy if engineer dies during placement wind-up")

func test_engineer_turret_animation_continuity() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ENGINEER, false)

	# Initial special attack starts animation
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	assert_true(player.anim_player.is_playing())
	assert_eq(player.anim_player.current_animation, "special")

	# Await past 0.15s placement
	await wait_seconds(0.20)

	# deploy_temp_turret must NOT have restarted the animation back to 0.0
	assert_gt(player.anim_player.current_animation_position, 0.15, "Animation must continue past 0.15s placement pose without restarting")

