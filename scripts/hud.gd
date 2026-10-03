extends CanvasLayer

const DAY_ICON: Texture2D = preload("res://assets/ui/hud_visual_kit/icons/global_day.png")
const NIGHT_ICON: Texture2D = preload("res://assets/ui/hud_visual_kit/icons/global_night.png")

@export var player_path: NodePath
@export var displayed_talent_capacity: int = 6
@export var day_night_cycle_path: NodePath = NodePath("../DayNightCycle")
@export var building_system_path: NodePath = NodePath("../BuildingSystem")

@onready var day_night_icon: TextureRect = $Margin/TopCenter/DayNightRow/DayNightIcon
@onready var day_night_phase_label: Label = $Margin/TopCenter/DayNightRow/PhaseLabel
@onready var day_night_timer_label: Label = $Margin/TopCenter/DayNightRow/TimerLabel
@onready var wood_label: Label = $Margin/Resources/ResourceRows/WoodBox/WoodLabel
@onready var stone_label: Label = $Margin/Resources/ResourceRows/StoneBox/StoneLabel
@onready var iron_label: Label = $Margin/Resources/ResourceRows/IronBox/IronLabel
@onready var magic_label: Label = $Margin/Resources/ResourceRows/MagicBox/MagicLabel
@onready var hero_portrait: HUDHeroPortrait = $Margin/Resources/ResourceRows/HeroPortrait
@onready var card_draft_popup: Control = $Margin/CardDraftPopup
@onready var player_floating_hp: Control = $Margin/PlayerFloatingHP
@onready var player_hp_bar: ProgressBar = $Margin/PlayerFloatingHP/Bar
@onready var player_hp_label: Label = $Margin/PlayerFloatingHP/Bar/Label
@onready var player_xp_bar: ProgressBar = $Margin/PlayerFloatingHP/XPBar
@onready var player_xp_label: Label = $Margin/PlayerFloatingHP/XPLabel

var player: PlayerPrototype
var day_night_cycle: DayNightCycle
var camera: Camera3D
var _last_night_state: Variant = null
var _event_bus: Node
var build_panel: WarriorBuildPanel
var _build_button: Button

func _ready() -> void:
	if not player_path.is_empty() and has_node(player_path):
		player = get_node(player_path) as PlayerPrototype
	if not day_night_cycle_path.is_empty() and has_node(day_night_cycle_path):
		day_night_cycle = get_node(day_night_cycle_path) as DayNightCycle

	$Margin/TopCenter/DayNightRow/BtnSkipNight.pressed.connect(_on_skip_night_pressed)
	$Margin/TopCenter/DayNightRow/BtnSettings.pressed.connect(_on_settings_pressed)

	_event_bus = get_node_or_null("/root/EventBus")
	if _event_bus:
		_event_bus.player_health_changed.connect(_on_health_changed)
		_event_bus.player_xp_changed.connect(_on_xp_changed)
		_event_bus.player_level_up.connect(_on_level_up_reached)
		_event_bus.player_class_changed.connect(_on_player_class_changed)
		_event_bus.resources_changed.connect(_on_resources_changed)
		_event_bus.cycle_time_updated.connect(_on_cycle_time_updated)
		_event_bus.boss_spawned.connect(show_boss_bar)
		_event_bus.boss_defeated.connect(_on_boss_defeated_event)
	else:
		if player:
			player.health_changed.connect(_on_health_changed)
			player.xp_changed.connect(_on_xp_changed)
			player.level_up_reached.connect(_on_level_up_reached)
		if day_night_cycle:
			day_night_cycle.time_updated.connect(_on_cycle_time_updated_legacy)

	if player:
		build_panel = WarriorBuildPanel.new()
		$Margin.add_child(build_panel)
		build_panel.bind_player(player)
		_build_button = Button.new()
		_build_button.text = "Специализации · P"
		_build_button.position = Vector2(24, 180)
		_build_button.pressed.connect(build_panel.open_specializations)
		$Margin.add_child(_build_button)
		$Margin.move_child(build_panel, $Margin.get_child_count() - 1)
		player.progression.run_build.build_changed.connect(_update_build_button)
		_update_build_button()
		_on_health_changed(player.current_health, player.max_health)
		_on_xp_changed(player.current_xp, player.xp_to_next_level, player.player_level)
		hero_portrait.set_class(int(player.current_class))
	var building_system: BuildingSystem = get_node_or_null(building_system_path) as BuildingSystem
	if building_system:
		var wallet: ResourceWallet = building_system.wallet
		_on_resources_changed(wallet.get_wood(), wallet.get_stone(), wallet.get_iron(), wallet.get_magic_stone())
	if day_night_cycle:
		_update_day_night_label(day_night_cycle.time_left, day_night_cycle.is_night, day_night_cycle.current_day)

func _process(_delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(player_floating_hp):
		return
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
		if not camera:
			return
	var target_3d: Vector3 = player.global_position + Vector3(0.0, 2.2, 0.0)
	if camera.is_position_behind(target_3d):
		player_floating_hp.visible = false
		return
	player_floating_hp.visible = true
	var screen_pos: Vector2 = camera.unproject_position(target_3d)
	player_floating_hp.position = screen_pos - player_floating_hp.size * 0.5

func _on_health_changed(current: float, max_hp: float) -> void:
	if player_hp_bar:
		player_hp_bar.max_value = max_hp
		player_hp_bar.value = current
		player_hp_bar.theme_type_variation = "HealthProgressBar" if current <= max_hp * 0.3 else "HealthyProgressBar"
	if player_hp_label:
		player_hp_label.text = "%d / %d HP" % [max(0, int(current)), int(max_hp)]

func _on_xp_changed(current: float, max_xp: float, level: int) -> void:
	if player_xp_bar:
		player_xp_bar.max_value = max_xp
		player_xp_bar.value = current
	if player_xp_label:
		player_xp_label.text = "LV %d  ·  %d / %d XP" % [level, int(current), int(max_xp)]

func _on_resources_changed(wood: int, stone: int, iron: int, magic_stone: int = 0) -> void:
	_set_resource_count(wood_label, wood)
	_set_resource_count(stone_label, stone)
	_set_resource_count(iron_label, iron)
	_set_resource_count(magic_label, magic_stone)

func _set_resource_count(label: Label, count: int) -> void:
	label.tooltip_text = str(count)
	if count < 1000:
		label.text = str(count)
		return
	for unit: Array in [[1000000000, "B"], [1000000, "M"], [1000, "K"]]:
		if count >= unit[0]:
			var value: float = float(count) / float(unit[0])
			label.text = ("%.1f%s" if value < 10.0 else "%.0f%s") % [value, unit[1]]
			return

func _on_skip_night_pressed() -> void:
	if day_night_cycle:
		day_night_cycle.skip_to_night()
	else:
		push_warning("HUD: Cannot skip to night - day_night_cycle is not configured")

func _on_settings_pressed() -> void:
	var modal: SettingsModal = $Margin/SettingsModal
	modal.open_modal()

func _update_day_night_label(seconds_left: float, is_night: bool, day_number: int) -> void:
	if _last_night_state != is_night:
		day_night_icon.texture = NIGHT_ICON if is_night else DAY_ICON
		_last_night_state = is_night
	var minutes: int = int(seconds_left) / 60
	var seconds: int = int(seconds_left) % 60
	var tint: Color = Color.WHITE
	if is_night:
		day_night_phase_label.text = "NIGHT %d  ·  SIEGE" % day_number
		tint = Color(1.0, 0.3, 0.3, 1.0)
	elif seconds_left <= 30.0:
		day_night_phase_label.text = "DAY %d  ·  SUNSET" % day_number
		tint = Color(1.0, 0.6, 0.1, 1.0)
	else:
		day_night_phase_label.text = "DAY %d" % day_number
	day_night_phase_label.modulate = tint
	day_night_phase_label.tooltip_text = day_night_phase_label.text
	day_night_timer_label.text = "%02d:%02d" % [minutes, seconds]
	if is_night and day_night_cycle and day_night_cycle.boss_pending:
		day_night_timer_label.text = "ПОБЕДИТЕ БОССА"
	day_night_timer_label.modulate = tint

func _on_player_class_changed(new_class: int) -> void:
	hero_portrait.set_class(new_class)

func _on_level_up_reached(new_level: int) -> void:
	_update_build_button()
	if player:
		player.spawn_popup_text("УРОВЕНЬ %d · +1 СПЕЦИАЛИЗАЦИЯ [P]" % new_level, Color.GOLD)

func _update_build_button() -> void:
	if _build_button and player:
		_build_button.visible = player.progression.run_build.active
		_build_button.text = "Специализации · %d очков [P] · Таланты %d/%d" % [player.progression.run_build.unspent_specialization_points, player.progression.run_build.selected_talents.size(), displayed_talent_capacity]

func show_boss_bar(boss: Node) -> void:
	var boss_container: Control = $Margin/BossBarContainer
	boss_container.visible = true
	if boss is SiegeBoss:
		boss_container.tooltip_text = (boss as SiegeBoss).display_name
		$Margin/BossBarContainer/BossTitle.text = (boss as SiegeBoss).display_name
	if boss.has_signal("boss_health_changed"):
		boss.connect("boss_health_changed", Callable(self, "_on_boss_health_changed"))
	if boss.has_signal("boss_defeated"):
		boss.connect("boss_defeated", Callable(self, "_on_boss_defeated"))
	if boss.get("max_health") != null:
		_on_boss_health_changed(boss.current_health, boss.max_health)

func _on_boss_health_changed(current: float, max_hp: float) -> void:
	var boss_hp_bar: ProgressBar = $Margin/BossBarContainer/BossHPBar
	var boss_hp_label: Label = $Margin/BossBarContainer/BossHPBar/BossHPLabel
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current
	boss_hp_label.text = "%d / %d HP" % [max(0, int(current)), int(max_hp)]

func _on_boss_defeated() -> void:
	$Margin/BossBarContainer.visible = false

func _on_cycle_time_updated(seconds_left: float, _total: float, night: bool, day_number: int) -> void:
	_update_day_night_label(seconds_left, night, day_number)

func _on_cycle_time_updated_legacy(seconds_left: float, _total: float, night: bool) -> void:
	_update_day_night_label(seconds_left, night, day_night_cycle.current_day)

func _on_boss_defeated_event(_boss: Node = null) -> void:
	_on_boss_defeated()

func _exit_tree() -> void:
	if not is_instance_valid(_event_bus):
		return
	if _event_bus.player_health_changed.is_connected(_on_health_changed):
		_event_bus.player_health_changed.disconnect(_on_health_changed)
	if _event_bus.player_xp_changed.is_connected(_on_xp_changed):
		_event_bus.player_xp_changed.disconnect(_on_xp_changed)
	if _event_bus.player_level_up.is_connected(_on_level_up_reached):
		_event_bus.player_level_up.disconnect(_on_level_up_reached)
	if _event_bus.player_class_changed.is_connected(_on_player_class_changed):
		_event_bus.player_class_changed.disconnect(_on_player_class_changed)
	if _event_bus.resources_changed.is_connected(_on_resources_changed):
		_event_bus.resources_changed.disconnect(_on_resources_changed)
	if _event_bus.cycle_time_updated.is_connected(_on_cycle_time_updated):
		_event_bus.cycle_time_updated.disconnect(_on_cycle_time_updated)
	if _event_bus.boss_spawned.is_connected(show_boss_bar):
		_event_bus.boss_spawned.disconnect(show_boss_bar)
	if _event_bus.boss_defeated.is_connected(_on_boss_defeated_event):
		_event_bus.boss_defeated.disconnect(_on_boss_defeated_event)
