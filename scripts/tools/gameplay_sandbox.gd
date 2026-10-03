extends Node3D
class_name GameplaySandbox

signal configuration_changed()
signal encounter_changed()
signal message_changed(message: String)

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const PLAYER_SCRIPT: Script = preload("res://scripts/tools/gameplay_sandbox_player.gd")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const LEGACY_BOSS: Script = preload("res://scripts/boss_gorgon.gd")
const RESOURCE_SCENES: Array[PackedScene] = [preload("res://scenes/resource_tree.tscn"), preload("res://scenes/resource_stone.tscn"), preload("res://scenes/resource_iron.tscn")]
const FLOOR_HALF_SIZE: float = 100.0

@onready var camera: CameraFollow = $Camera3D as CameraFollow
@onready var sun: DirectionalLight3D = $SunLight as DirectionalLight3D
@onready var environment: WorldEnvironment = $WorldEnvironment as WorldEnvironment
var player: GameplaySandboxPlayer
var building_system: BuildingSystem
var enemies: Node3D
var hud: CanvasLayer
var editor: GameplaySandboxUI
var encounter: Node3D
var character_class: int = 0
var chosen_talents: Array[String] = []
var specialization_ranks: Dictionary = {}
var opening_bonuses: bool = false
var spawn_distance: float = 8.0
var _paused_before_editor: bool = false
var _editor_open: bool = false
var _resume_pending: bool = false
var _paused_on_entry: bool = false
var _night: bool = false
var _cycle: DayNightCycle

func _enter_tree() -> void:
	_paused_on_entry = get_tree().paused
	GameplaySandboxSession.begin(self)

func _ready() -> void:
	if not GameplaySandboxSession.is_active():
		return
	editor = GameplaySandboxUI.new()
	add_child(editor)
	editor.bind_sandbox(self)
	_build_grid_and_boundary()
	clear_encounter()
	print("GAMEPLAY_SANDBOX_READY")

func _exit_tree() -> void:
	get_tree().paused = _paused_on_entry
	var registry: Node = get_node_or_null("/root/EntityRegistry")
	if registry:
		registry.clear()
	GameplaySandboxSession.leave(self)

func _flat_height(_x: int, _z: int) -> int:
	return 0

func _flat_loaded(x: int, z: int) -> bool:
	return x >= -100 and x < 100 and z >= -100 and z < 100

func _configure_navigation() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	registry.clear()
	registry.monster_flowfield.set_height_lookup(_flat_height)
	registry.monster_flowfield.set_chunk_loaded_lookup(_flat_loaded)

func clear_encounter() -> void:
	if is_instance_valid(encounter):
		if is_instance_valid(player):
			chosen_talents = player.progression.run_build.selected_talents.duplicate()
			specialization_ranks = player.progression.run_build.specializations.duplicate()
		remove_child(encounter)
		encounter.queue_free()
	get_node("/root/VFXManager").clear_effects()
	_configure_navigation()
	encounter = Node3D.new()
	encounter.name = "Encounter"
	add_child(encounter)
	building_system = BuildingSystem.new()
	building_system.name = "BuildingSystem"
	encounter.add_child(building_system)
	_cycle = DayNightCycle.new()
	_cycle.name = "DayNightCycle"
	_cycle.running = false
	_cycle.sun_light_path = NodePath("../../SunLight")
	_cycle.world_env_path = NodePath("../../WorldEnvironment")
	encounter.add_child(_cycle)
	get_node("/root/RosterManager").selected_slot_index = character_class
	var instance: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	instance.set_script(PLAYER_SCRIPT)
	player = instance as GameplaySandboxPlayer
	player.name = "Player"
	player.opening_bonuses = opening_bonuses
	player.portal_path = NodePath()
	encounter.add_child(player)
	player.position = Vector3(0.0, 0.9, 0.0)
	player.portal_compass.hide()
	player.player_died.connect(_on_player_died)
	_apply_build()
	camera.set_target(player)
	enemies = Node3D.new()
	enemies.name = "Enemies"
	encounter.add_child(enemies)
	hud = HUD_SCENE.instantiate() as CanvasLayer
	hud.name = "HUD"
	hud.player_path = NodePath("../Player")
	hud.displayed_talent_capacity = WarriorTalentCatalog.TALENT_IDS.size()
	encounter.add_child(hud)
	var radial: Control = hud.get_node("Margin/RadialMenu") as Control
	radial.prefab_selected.connect(building_system.select_prefab)
	player.radial_menu = radial
	player.building_system = building_system
	editor.configure_native_hud(hud)
	set_night(_night)
	configuration_changed.emit()
	encounter_changed.emit()
	message_changed.emit("Бой сброшен. Управление обычное; F2 — настройка арены.")

func reset() -> void:
	clear_encounter()

func select_character(class_id: int) -> void:
	if class_id < 0 or class_id > 2:
		return
	character_class = class_id
	clear_encounter()

func configure_talents(ids: Array) -> void:
	if is_instance_valid(player):
		# Native HUD spending and editor changes share the same production build.
		specialization_ranks = player.progression.run_build.specializations.duplicate()
	chosen_talents = WarriorTalentCatalog.sanitize_ids(ids)
	_apply_build()
	configuration_changed.emit()

func _apply_build() -> void:
	if not is_instance_valid(player):
		return
	player.combat.cancel_pending_casts(player)
	var xp: float = player.current_xp
	var level: int = player.player_level
	var threshold: float = player.xp_to_next_level
	var resources: int = player.progression.collected_resources
	var points: int = player.progression.run_build.unspent_specialization_points
	var hp: float = player.current_health
	player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	var build: WarriorRunBuild = player.progression.run_build
	build.selected_talents = chosen_talents.duplicate()
	build.specializations = specialization_ranks.duplicate()
	build.unspent_specialization_points = points
	build._reveal_synergies()
	build.build_changed.emit()
	player.talents.refresh_meta()
	player.current_health = minf(hp, player.max_health)
	player.current_xp = xp
	player.player_level = level
	player.xp_to_next_level = threshold
	player.progression.collected_resources = resources
	player.progression._emit_xp(player)
	player.health.health_changed.emit(player.current_health, player.max_health)
	get_node("/root/EventBus").player_health_changed.emit(player.current_health, player.max_health)

func set_specialization(axis: String, rank: int) -> bool:
	if not is_instance_valid(player) or rank < 0 or not player.progression.run_build.get_available_axes().has(axis):
		return false
	specialization_ranks = player.progression.run_build.specializations.duplicate()
	if rank == 0:
		specialization_ranks.erase(axis)
	else:
		specialization_ranks[axis] = rank
	player.progression.run_build.specializations = specialization_ranks.duplicate()
	player.progression.run_build.build_changed.emit()
	configuration_changed.emit()
	return true

func clear_specializations() -> void:
	specialization_ranks.clear()
	player.progression.run_build.specializations.clear()
	player.progression.run_build.build_changed.emit()
	configuration_changed.emit()

func set_opening_bonuses(enabled: bool) -> void:
	opening_bonuses = enabled
	player.opening_bonuses = enabled
	player.talents.refresh_meta()
	configuration_changed.emit()

func set_night(enabled: bool) -> void:
	_night = enabled
	_cycle.is_night = enabled
	if enabled:
		_cycle.lighting_profile.apply_night_instant(sun, environment)
	else:
		_cycle.lighting_profile.apply_day_instant(sun, environment)

func spawn_monster(id: String, count: int = 1) -> int:
	var entry: GameplaySandboxCatalog.SpawnEntry = GameplaySandboxCatalog.find(id)
	if not entry or count <= 0 or not is_instance_valid(player) or player.current_health <= 0.0:
		return 0
	var created: int = 0
	var forward: Vector3 = player.orientation.aim_direction
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	var center: Vector3 = player.global_position + forward.normalized() * spawn_distance
	center.x = clampf(center.x, -90.0, 90.0)
	center.z = clampf(center.z, -90.0, 90.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for index: int in range(clampi(count, 1, 100)):
		var monster: CharacterBody3D = entry.scene.instantiate() as CharacterBody3D
		if monster is SiegeBoss:
			(monster as SiegeBoss).configure(entry.boss_stage, player)
		elif monster is EnemyBase:
			(monster as EnemyBase).target_player = player
		elif monster is LEGACY_BOSS:
			(monster as LEGACY_BOSS).target_player = player
		var placed: bool = false
		for attempt: int in range(24):
			var ring: float = 2.8 * float(1 + (index + attempt) / 8)
			var angle: float = float(index + attempt) * TAU / 8.0
			var position: Vector3 = center + Vector3(cos(angle), 0.0, sin(angle)) * ring
			position.y = MonsterLocomotion.calculate_spawn_y(0.0, monster)
			if absf(position.x) < 97.0 and absf(position.z) < 97.0 and MonsterLocomotion.validate_safe_spawn_point(space, monster, position):
				monster.position = position
				placed = true
				break
		if not placed:
			monster.free()
			continue
		enemies.add_child(monster)
		if not entry.elite_skill.is_empty() and monster is EnemyBase:
			EliteSkillController.attach(monster as EnemyBase, entry.elite_skill, _flat_height)
		if monster is SiegeBoss:
			(monster as SiegeBoss).defeated.connect(_on_boss_defeated)
			get_node("/root/EventBus").boss_spawned.emit(monster)
		created += 1
	message_changed.emit("Добавлено: %s ×%d" % [entry.title, created])
	encounter_changed.emit()
	return created

func _on_boss_defeated(_boss: SiegeBoss) -> void:
	if is_instance_valid(player) and player.current_health > 0.0:
		player.progression.grant_level(player)

func clear_monsters() -> void:
	if is_instance_valid(player) and player.is_dueling:
		player.end_duel()
	for child: Node in enemies.get_children():
		enemies.remove_child(child)
		child.queue_free()
	get_node("/root/VFXManager").clear_effects()
	editor.clear_boss_display(hud)
	encounter_changed.emit()
	message_changed.emit("Враги и их эффекты удалены.")

func add_resources() -> void:
	building_system.wallet.add_resource(1000, 1000, 1000)
	message_changed.emit("В кошелёк арены добавлено по 1000 ресурсов.")

func spawn_resource(kind: int) -> void:
	if kind < 0 or kind >= RESOURCE_SCENES.size():
		return
	var resource: Node3D = RESOURCE_SCENES[kind].instantiate() as Node3D
	resource.position = player.position + Vector3(4.0, 0.0, 4.0)
	resource.position.y = 0.0
	encounter.add_child(resource)

func toggle_editor(open: bool) -> void:
	if open == _editor_open:
		return
	_editor_open = open
	if open:
		# Transfer modal ownership before remembering the pause state. Otherwise
		# replacing the HUD can restore a pause whose native panel no longer exists.
		editor.set_native_editor_open(hud, true)
		if not _resume_pending:
			_paused_before_editor = get_tree().paused
		_resume_pending = false
		get_tree().paused = true
	else:
		_resume_pending = true
		editor.request_resume()
	editor.set_editor_open(open)

func resume_play() -> void:
	if not _editor_open:
		_resume_pending = false
		editor.set_native_editor_open(hud, false)
		get_tree().paused = _paused_before_editor

func _on_player_died() -> void:
	toggle_editor(true)
	message_changed.emit("Персонаж погиб только на арене. «Сбросить бой» вернёт его с выбранной сборкой.")

func return_to_menu() -> void:
	var paused_before_return: bool = get_tree().paused
	get_tree().paused = _paused_on_entry
	var result: Error = _change_scene_to_menu()
	if result != OK:
		get_tree().paused = paused_before_return
		message_changed.emit("Не удалось вернуться в меню: %s" % error_string(result))

func _change_scene_to_menu() -> Error:
	return get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _build_grid_and_boundary() -> void:
	var grid: ImmediateMesh = ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for cell: int in range(-100, 101, 2):
		grid.surface_add_vertex(Vector3(cell, 0.008, -100))
		grid.surface_add_vertex(Vector3(cell, 0.008, 100))
		grid.surface_add_vertex(Vector3(-100, 0.008, cell))
		grid.surface_add_vertex(Vector3(100, 0.008, cell))
	grid.surface_end()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.31, 0.22)
	var view: MeshInstance3D = MeshInstance3D.new()
	view.mesh = grid
	view.material_override = material
	add_child(view)
	for side: int in range(4):
		var wall: StaticBody3D = StaticBody3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(0.6, 4.0, 200.0) if side < 2 else Vector3(200.0, 4.0, 0.6)
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		wall.add_child(collision)
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = shape.size
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = mesh
		wall.add_child(visual)
		wall.position = Vector3(-100.0 if side == 0 else 100.0, 2.0, 0.0) if side < 2 else Vector3(0.0, 2.0, -100.0 if side == 2 else 100.0)
		add_child(wall)
