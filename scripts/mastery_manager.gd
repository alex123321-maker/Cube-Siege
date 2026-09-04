extends Node

const SAVE_PATH = "user://mastery_save.json"

var total_battle_xp: int = 0
var available_points: int = 5 # Start with 5 points to test right away!

var bloodlust: int = 0 # Max 25
var survival: int = 0  # Max 25
var agility: int = 0   # Max 25
var crafting: int = 0  # Max 25

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
		save_mgr.mastery = {
			"total_battle_xp": total_battle_xp,
			"available_points": available_points,
			"bloodlust": bloodlust,
			"survival": survival,
			"agility": agility,
			"crafting": crafting
		}
		save_mgr.save_to_disk()
		return

	# Fallback if SaveManager is not loaded
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return
	var data = {
		"total_battle_xp": total_battle_xp,
		"available_points": available_points,
		"bloodlust": bloodlust,
		"survival": survival,
		"agility": agility,
		"crafting": crafting
	}
	file.store_string(JSON.stringify(data))
	file.close()

func load_mastery() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and not save_mgr.mastery.is_empty():
		var m = save_mgr.mastery
		total_battle_xp = m.get("total_battle_xp", 0)
		available_points = m.get("available_points", 5)
		bloodlust = m.get("bloodlust", 0)
		survival = m.get("survival", 0)
		agility = m.get("agility", 0)
		crafting = m.get("crafting", 0)
		return

	# Fallback / migration from legacy file
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		total_battle_xp = parsed.get("total_battle_xp", 0)
		available_points = parsed.get("available_points", 5)
		bloodlust = parsed.get("bloodlust", 0)
		survival = parsed.get("survival", 0)
		agility = parsed.get("agility", 0)
		crafting = parsed.get("crafting", 0)
		if save_mgr:
			save_mgr.mastery = parsed
