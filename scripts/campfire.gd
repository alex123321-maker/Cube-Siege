extends BuildingBase
class_name Campfire

## Refresh one timed regeneration contribution per hearth; distinct hearths stack.
@export var aura_radius: float = 5.0
@export var heal_per_second: float = 3.0
@export var aura_half_height: float = 2.5
@export var refresh_interval: float = 0.25
@export var effect_refresh_duration: float = 0.6

@onready var aura_area: Area3D = $RegenerationArea
@onready var aura_shape: CollisionShape3D = $RegenerationArea/CollisionShape3D
@onready var fire_visual: CampfireVisual = $FireVisual

var _players: Array[PlayerPrototype] = []
var _refresh_timer: float = 0.0
var _extinguished: bool = false
var _focused: bool = false

func _ready() -> void:
	super._ready()
	add_to_group("campfires")
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = aura_radius
	cylinder.height = aura_half_height * 2.0
	aura_shape.shape = cylinder
	aura_area.body_entered.connect(_on_body_entered)
	aura_area.body_exited.connect(_on_body_exited)
	fire_visual.setup(aura_radius, $Model/Flames as Node3D)

func _physics_process(delta: float) -> void:
	if _extinguished:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = refresh_interval
	var in_range: bool = false
	for player: PlayerPrototype in _players:
		if not is_instance_valid(player) or not is_instance_valid(player.status_effects):
			continue
		if contains_player(player.global_position) and player.current_health > 0.0:
			player.status_effects.refresh_regeneration(get_instance_id(), heal_per_second, effect_refresh_duration, aura_radius)
			in_range = true
		else:
			player.status_effects.remove_source(get_instance_id())
	fire_visual.set_aura_visible(_focused or in_range)

func contains_player(world_position: Vector3) -> bool:
	var offset: Vector3 = world_position - global_position
	return Vector2(offset.x, offset.z).length_squared() <= aura_radius * aura_radius \
		and absf(offset.y) <= aura_half_height

func _on_body_entered(body: Node3D) -> void:
	var player: PlayerPrototype = body as PlayerPrototype
	if player and not _players.has(player):
		_players.append(player)
		_refresh_timer = 0.0

func _on_body_exited(body: Node3D) -> void:
	var player: PlayerPrototype = body as PlayerPrototype
	if player:
		if is_instance_valid(player.status_effects):
			player.status_effects.remove_source(get_instance_id())
		_players.erase(player)

func set_focused(focused: bool) -> void:
	super.set_focused(focused)
	_focused = focused
	if is_instance_valid(fire_visual):
		fire_visual.set_aura_visible(focused or not _players.is_empty())

func destroy_building() -> void:
	if _extinguished:
		return
	_extinguished = true
	_remove_regeneration()
	fire_visual.extinguish()
	super.destroy_building()

func _exit_tree() -> void:
	_remove_regeneration()
	super._exit_tree()

func _remove_regeneration() -> void:
	for player: PlayerPrototype in _players:
		if is_instance_valid(player) and is_instance_valid(player.status_effects):
			player.status_effects.remove_source(get_instance_id())
	_players.clear()
