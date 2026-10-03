extends RefCounted
class_name GameplaySandboxCatalog

class SpawnEntry extends RefCounted:
	var id: String
	var title: String
	var scene: PackedScene
	var boss_stage: int
	var elite_skill: String
	func _init(key: String, caption: String, prefab: PackedScene, stage: int = 0, skill: String = "") -> void:
		id = key
		title = caption
		scene = prefab
		boss_stage = stage
		elite_skill = skill

static func entries() -> Array[SpawnEntry]:
	var result: Array[SpawnEntry] = [
		SpawnEntry.new("zombie", "Зомби", WaveDirector.ENEMY_GRUNT),
		SpawnEntry.new("siege_breaker", "Таранщик", WaveDirector.ENEMY_SIEGE),
		SpawnEntry.new("ranged_skirmisher", "Стрелок", WaveDirector.ENEMY_RANGED),
		SpawnEntry.new("legacy_gorgon", "Горгон · прежняя версия", preload("res://scenes/enemies/boss_gorgon.tscn"))
	]
	var keys: Array[String] = ["boss_01_cairn", "boss_02_gorgon", "boss_03_ash_oracle", "boss_04_mortar", "boss_05_rift_warden", "boss_06_rift_harbinger"]
	for stage: int in range(1, 7):
		result.append(SpawnEntry.new(keys[stage - 1], "Босс %d · %s" % [stage, BossEncounterCatalog.build(stage).title], WarriorRunCoordinator.BOSS_SCENES[stage - 1], stage))
	for elite: EliteSkillCatalog.Entry in EliteSkillCatalog.entries():
		result.append(SpawnEntry.new(elite.id, "Элита · " + elite.title, load(elite.scene_path) as PackedScene, 0, elite.id))
	return result

static func find(id: String) -> SpawnEntry:
	for entry: SpawnEntry in entries():
		if entry.id == id:
			return entry
	return null
