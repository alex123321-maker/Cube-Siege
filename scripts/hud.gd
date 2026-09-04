extends CanvasLayer

@export var player_path: NodePath
@export var day_night_cycle_path: NodePath = NodePath("../DayNightCycle")

@onready var top_xp_bar: ProgressBar = $TopXPBar
@onready var xp_label: Label = $TopXPBar/XPLabel
@onready var day_night_label: Label = $Margin/TopCenter/DayNightLabel
@onready var wood_label: Label = $Margin/TopLeft/Resources/WoodBox/WoodLabel
@onready var stone_label: Label = $Margin/TopLeft/Resources/StoneBox/StoneLabel
@onready var iron_label: Label = $Margin/TopLeft/Resources/IronBox/IronLabel
@onready var card_draft_popup: Control = $CardDraftPopup

@onready var player_floating_hp: Control = $PlayerFloatingHP
@onready var player_hp_bar: ProgressBar = $PlayerFloatingHP/Bar
@onready var player_hp_label: Label = $PlayerFloatingHP/Bar/Label

var player: Node3D = null
var day_night_cycle: DayNightCycle = null
var camera: Camera3D = null

func _ready() -> void:
	if has_node(player_path):
		player = get_node(player_path)
	if has_node(day_night_cycle_path):
		day_night_cycle = get_node(day_night_cycle_path) as DayNightCycle

	if has_node("Margin/TopCenter/BtnSkipNight"):
		$Margin/TopCenter/BtnSkipNight.pressed.connect(_on_skip_night_pressed)

	# EventBus listeners for decoupled architecture (single source of truth)
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.player_health_changed.connect(func(cur, mx): _on_health_changed(cur, mx))
		eb.player_xp_changed.connect(func(cur, mx, lvl): _on_xp_changed(cur, mx, lvl))
		eb.player_level_up.connect(func(lvl): _on_level_up_reached(lvl))
		eb.resources_changed.connect(func(w, s, i): _on_resources_changed(w, s, i))
		eb.cycle_time_updated.connect(func(tl, _tot, night, day_num): _update_day_night_label(tl, night, day_num))
		eb.boss_spawned.connect(func(boss): show_boss_bar(boss))
		eb.boss_defeated.connect(func(_b): _on_boss_defeated())
	else:
		# Fallback direct wiring for standalone testing without EventBus autoload
		if player:
			if player.has_signal("health_changed"):
				player.connect("health_changed", Callable(self, "_on_health_changed"))
			if player.has_signal("xp_changed"):
				player.connect("xp_changed", Callable(self, "_on_xp_changed"))
			if player.has_signal("level_up_reached"):
				player.connect("level_up_reached", Callable(self, "_on_level_up_reached"))
		if day_night_cycle:
			day_night_cycle.time_updated.connect(func(tl, _tot, night): _update_day_night_label(tl, night, day_night_cycle.current_day))

func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player) or not player_floating_hp:
		return
	if not camera or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
		if not camera:
			return

	var target_3d: Vector3 = player.global_position + Vector3(0, 2.2, 0)
	if camera.is_position_behind(target_3d):
		player_floating_hp.visible = false
	else:
		player_floating_hp.visible = true
		var screen_pos: Vector2 = camera.unproject_position(target_3d)
		player_floating_hp.global_position = screen_pos - (player_floating_hp.size * 0.5)

func _on_health_changed(current: float, max_hp: float) -> void:
	if player_hp_bar:
		player_hp_bar.max_value = max_hp
		player_hp_bar.value = current
	if player_hp_label:
		player_hp_label.text = "%d / %d HP" % [max(0, int(current)), int(max_hp)]

func _on_resources_changed(wood: int, stone: int, iron: int) -> void:
	if wood_label:
		wood_label.text = "WOOD: %d / 25" % wood
	if stone_label:
		stone_label.text = "STONE: %d / 25" % stone
	if iron_label:
		iron_label.text = "IRON: %d" % iron

func _on_skip_night_pressed() -> void:
	if day_night_cycle:
		day_night_cycle.skip_to_night()
	else:
		push_warning("HUD: Cannot skip to night - day_night_cycle is not configured")

func _update_day_night_label(seconds_left: float, is_night: bool, day_number: int) -> void:
	if not day_night_label:
		return
	var minutes: int = int(seconds_left) / 60
	var seconds: int = int(seconds_left) % 60
	if is_night:
		day_night_label.text = "NIGHT %d [SIEGE]  %02d:%02d" % [day_number, minutes, seconds]
		day_night_label.modulate = Color(1.0, 0.3, 0.3, 1.0)
	else:
		if seconds_left <= 30.0:
			day_night_label.text = "DAY %d [SUNSET]  %02d:%02d" % [day_number, minutes, seconds]
			day_night_label.modulate = Color(1.0, 0.6, 0.1, 1.0)
		else:
			day_night_label.text = "DAY %d  %02d:%02d" % [day_number, minutes, seconds]
			day_night_label.modulate = Color.WHITE

func _on_xp_changed(current: float, max_xp: float, level: int) -> void:
	if top_xp_bar:
		top_xp_bar.max_value = max_xp
		top_xp_bar.value = current
	if xp_label:
		var pct: int = int((current / max(1.0, max_xp)) * 100)
		xp_label.text = "LVL %d — [ %d / %d XP ] (%d%%)" % [level, int(current), int(max_xp), pct]

func _on_level_up_reached(new_level: int) -> void:
	if card_draft_popup and card_draft_popup.has_method("open_draft"):
		card_draft_popup.open_draft(player, new_level)

func show_boss_bar(boss: Node) -> void:
	var boss_container: Control = get_node_or_null("Margin/BossBarContainer") as Control
	if boss_container:
		boss_container.visible = true
	if boss.has_signal("boss_health_changed"):
		boss.connect("boss_health_changed", Callable(self, "_on_boss_health_changed"))
	if boss.has_signal("boss_defeated"):
		boss.connect("boss_defeated", Callable(self, "_on_boss_defeated"))
	if boss.get("max_health") != null:
		_on_boss_health_changed(boss.current_health, boss.max_health)

func _on_boss_health_changed(current: float, max_hp: float) -> void:
	var boss_hp_bar: ProgressBar = get_node_or_null("Margin/BossBarContainer/BossHPBar") as ProgressBar
	var boss_hp_label: Label = get_node_or_null("Margin/BossBarContainer/BossHPBar/BossHPLabel") as Label
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = current
	if boss_hp_label:
		boss_hp_label.text = "%d / %d HP" % [max(0, int(current)), int(max_hp)]

func _on_boss_defeated() -> void:
	var boss_container: Control = get_node_or_null("Margin/BossBarContainer") as Control
	if boss_container:
		boss_container.visible = false
