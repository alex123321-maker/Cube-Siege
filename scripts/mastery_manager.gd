extends Node

var _local_mastery: Dictionary = {
	"total_battle_xp": 0,
	"available_points": 5,
	"bloodlust": 0,
	"survival": 0,
	"agility": 0,
	"crafting": 0
}

func _get_mastery_dict() -> Dictionary:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		if save_mgr.mastery.is_empty():
			var save_cls = load("res://scripts/save_manager.gd")
			if save_cls and save_cls.has_method("get_default_mastery"):
				save_mgr.mastery = save_cls.get_default_mastery()
		return save_mgr.mastery
	return _local_mastery

var total_battle_xp: int:
	get: return _get_mastery_dict().get("total_battle_xp", 0)
	set(val): _get_mastery_dict()["total_battle_xp"] = val

var available_points: int:
	get: return _get_mastery_dict().get("available_points", 5)
	set(val): _get_mastery_dict()["available_points"] = val

var bloodlust: int:
	get: return _get_mastery_dict().get("bloodlust", 0)
	set(val): _get_mastery_dict()["bloodlust"] = val

var survival: int:
	get: return _get_mastery_dict().get("survival", 0)
	set(val): _get_mastery_dict()["survival"] = val

var agility: int:
	get: return _get_mastery_dict().get("agility", 0)
	set(val): _get_mastery_dict()["agility"] = val

var crafting: int:
	get: return _get_mastery_dict().get("crafting", 0)
	set(val): _get_mastery_dict()["crafting"] = val

func _ready() -> void:
	load_mastery()

func add_battle_xp(amount: int) -> void:
	total_battle_xp += amount
	var new_points: int = int(amount / 50.0) # 1 point per 50 Battle XP
	available_points += new_points
	save_mastery()

func invest_point(branch: String) -> bool:
	if available_points <= 0:
		return false

	match branch:
		"bloodlust":
			if bloodlust >= 25: return false
			bloodlust += 1
		"survival":
			if survival >= 25: return false
			survival += 1
		"agility":
			if agility >= 25: return false
			agility += 1
		"crafting":
			if crafting >= 25: return false
			crafting += 1
		_:
			return false

	available_points -= 1
	save_mastery()
	return true

func reset_points() -> void:
	available_points += bloodlust + survival + agility + crafting
	bloodlust = 0
	survival = 0
	agility = 0
	crafting = 0
	save_mastery()

func get_stat_multipliers() -> Dictionary:
	return {
		"damage_mult": 1.0 + (bloodlust * 0.02),
		"max_hp_bonus": survival * 4.0,
		"resistance_mult": 1.0 - (survival * 0.01),
		"speed_mult": 1.0 + (agility * 0.015),
		"cooldown_mult": 1.0 - (agility * 0.015),
		"resource_mult": 1.0 + (crafting * 0.03),
		"building_hp_mult": 1.0 + (crafting * 0.04)
	}

func save_mastery() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		save_mgr.save_to_disk()

func load_mastery() -> void:
	# SaveManager is authoritative and loads during startup
	pass
