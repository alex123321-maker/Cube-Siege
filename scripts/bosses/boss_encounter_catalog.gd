extends RefCounted
class_name BossEncounterCatalog

## First-version starting balance. Every action is avoidable with ordinary movement.
const TITLES: PackedStringArray = ["Страж кургана", "Горгон-Топтатель", "Пепельный оракул", "Мортирный колосс", "Страж Разлома", "Вестник Разлома"]
const HEALTH: PackedFloat32Array = [900.0, 1600.0, 2300.0, 3200.0, 4300.0, 5800.0]
const COLORS: Array[Color] = [Color(1.0, 0.65, 0.20), Color(1.0, 0.34, 0.25), Color(1.0, 0.48, 0.16), Color(1.0, 0.74, 0.24), Color(0.76, 0.45, 1.0), Color(0.96, 0.32, 0.8)]

static func build(stage: int) -> BossEncounterProfile:
	var index: int = clampi(stage, 1, 6) - 1
	var profile: BossEncounterProfile = BossEncounterProfile.new()
	profile.title = TITLES[index]
	profile.health = HEALTH[index]
	profile.speed = 2.3 + float(index) * 0.15
	profile.color = COLORS[index]
	match index:
		0:
			profile.attacks = [_attack("Удар каменных кулаков", BossAttackSpec.Shape.SECTOR, 1.4, 1.9, 22.0, 4.8), _attack("Обвал", BossAttackSpec.Shape.CIRCLE, 1.7, 1.6, 24.0, 2.6, true)]
		1:
			var charge: BossAttackSpec = _attack("Топот Горгона", BossAttackSpec.Shape.LINE, 1.25, 2.0, 30.0, 12.0)
			charge.charge = true
			charge.width = 2.4
			charge.active = 0.75
			profile.attacks = [charge, _attack("Каменный веер", BossAttackSpec.Shape.SECTOR, 1.1, 1.5, 25.0, 6.0)]
		2:
			var fan: BossAttackSpec = _attack("Пепельные копья", BossAttackSpec.Shape.FAN, 1.0, 1.3, 24.0, 22.0)
			fan.arc_degrees = 65.0
			fan.projectile_speed = 11.0
			var ember: BossAttackSpec = _attack("Тлеющая печать", BossAttackSpec.Shape.CIRCLE, 1.25, 1.1, 18.0, 3.0, true)
			ember.slowing = 0.25
			profile.attacks = [fan, _attack("Пепельный выброс", BossAttackSpec.Shape.CROSS, 1.2, 1.5, 28.0, 6.5, true), ember]
		3:
			var mortar: BossAttackSpec = _attack("Мортирный залп", BossAttackSpec.Shape.CIRCLE, 1.2, 1.3, 32.0, 3.4, true)
			var barrage: BossAttackSpec = _attack("Артиллерийская полоса", BossAttackSpec.Shape.LINE, 1.1, 1.4, 35.0, 18.0)
			barrage.width = 3.0
			profile.attacks = [mortar, barrage, _attack("Удар опор", BossAttackSpec.Shape.CIRCLE, 1.0, 1.6, 30.0, 5.0)]
		4:
			var spear: BossAttackSpec = _attack("Кристальные пики", BossAttackSpec.Shape.FAN, 0.9, 1.15, 30.0, 24.0)
			spear.projectile_count = 5
			spear.projectile_speed = 14.0
			spear.arc_degrees = 90.0
			var ring: BossAttackSpec = _attack("Раскол земли", BossAttackSpec.Shape.SECTOR, 1.0, 1.3, 36.0, 7.0)
			ring.arc_degrees = 250.0
			profile.attacks = [_attack("Клинок Разлома", BossAttackSpec.Shape.SECTOR, 0.95, 1.4, 34.0, 5.8), spear, ring]
			profile.phase_thresholds = PackedFloat32Array([0.5])
		5:
			var well: BossAttackSpec = _attack("Гравитационная печать", BossAttackSpec.Shape.CIRCLE, 1.05, 1.1, 36.0, 3.8, true)
			well.slowing = 0.35
			var beam: BossAttackSpec = _attack("Лучевой веер", BossAttackSpec.Shape.FAN, 0.85, 1.15, 38.0, 26.0)
			beam.projectile_count = 7
			beam.projectile_speed = 16.0
			beam.arc_degrees = 110.0
			var cross: BossAttackSpec = _attack("Крест Разлома", BossAttackSpec.Shape.CROSS, 1.15, 1.6, 42.0, 8.0, true)
			cross.width = 2.4
			cross.teleport = true
			profile.attacks = [well, beam, cross]
			profile.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	return profile

static func _attack(title: String, shape: BossAttackSpec.Shape, windup: float, recovery: float, damage: float, reach: float, target_centered: bool = false) -> BossAttackSpec:
	var attack: BossAttackSpec = BossAttackSpec.new()
	attack.title = title
	attack.shape = shape
	attack.windup = windup
	attack.recovery = recovery
	attack.damage = damage
	attack.reach = reach
	attack.target_centered = target_centered
	if target_centered:
		attack.terrain_mode = TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT
	return attack
