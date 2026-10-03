extends RefCounted
class_name BossEncounterCatalog

## Mechanics follow the nested Monster Pages; numeric values are starting balance.
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
			profile.attacks = [_attack(BossAttackSpec.Kind.BURST, 1.5, 1.9, 22.0, 4.8), _attack(BossAttackSpec.Kind.LOBBED, 1.7, 1.6, 24.0, 2.6)]
		1:
			profile.attacks = [_attack(BossAttackSpec.Kind.SWEEP, 1.25, 2.0, 30.0, 12.0), _attack(BossAttackSpec.Kind.BURST, 1.25, 1.5, 25.0, 5.0)]
		2:
			profile.attacks = [_attack(BossAttackSpec.Kind.LINE_BEAM, 1.4, 1.4, 24.0, 16.0), _radial(BossAttackSpec.RadialVariant.LEFT_TO_RIGHT, 65.0, 24.0), _attack(BossAttackSpec.Kind.CHAIN, 1.25, 1.5, 22.0, 1.7)]
		3:
			profile.attacks = [_attack(BossAttackSpec.Kind.LOBBED, 1.2, 1.3, 32.0, 3.0), _radial(BossAttackSpec.RadialVariant.RIGHT_TO_LEFT, 75.0, 30.0), _attack(BossAttackSpec.Kind.CHAIN, 1.1, 1.4, 28.0, 1.8)]
		4:
			profile.attacks = [_radial(BossAttackSpec.RadialVariant.CENTRE_TO_EDGES, 85.0, 34.0), _attack(BossAttackSpec.Kind.LINE_BEAM, 1.1, 1.4, 34.0, 18.0), _attack(BossAttackSpec.Kind.CHASE, 1.15, 1.3, 32.0, 1.8)]
			profile.phase_thresholds = PackedFloat32Array([0.5])
		5:
			profile.attacks = [_radial(BossAttackSpec.RadialVariant.EDGES_TO_CENTRE, 100.0, 38.0), _attack(BossAttackSpec.Kind.CHASE, 1.0, 1.15, 36.0, 1.9), _attack(BossAttackSpec.Kind.CHAIN, 1.0, 1.4, 40.0, 2.0)]
			profile.phase_thresholds = PackedFloat32Array([0.66, 0.33])
	return profile

static func _attack(kind: BossAttackSpec.Kind, windup: float, recovery: float, damage: float, reach: float) -> BossAttackSpec:
	var attack: BossAttackSpec = BossAttackSpec.new()
	attack.kind = kind
	attack.title = ["Взрыв вокруг", "Навесная атака", "Атака по линии", "Радиальная атака", "Подземная цепь взрывов", "Погоня за следами", "Сметающий рывок"][kind]
	attack.windup = windup
	attack.recovery = recovery
	attack.damage = damage
	attack.reach = reach
	attack.active = 0.30
	match kind:
		BossAttackSpec.Kind.LOBBED:
			attack.target_centered = true
			attack.terrain_mode = TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT
		BossAttackSpec.Kind.LINE_BEAM:
			attack.shape = BossAttackSpec.Shape.LINE
			attack.width = 2.4
		BossAttackSpec.Kind.CHAIN, BossAttackSpec.Kind.CHASE:
			attack.target_centered = true
			attack.terrain_mode = TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT
		BossAttackSpec.Kind.SWEEP:
			attack.shape = BossAttackSpec.Shape.LINE
			attack.charge = true
			attack.width = 3.4
			attack.active = 0.75
	attack.synchronise_duration()
	return attack

static func _radial(variant: BossAttackSpec.RadialVariant, speed: float, damage: float) -> BossAttackSpec:
	var attack: BossAttackSpec = _attack(BossAttackSpec.Kind.RADIAL_BEAM, 1.0, 1.4, damage, 10.0)
	attack.shape = BossAttackSpec.Shape.SECTOR
	attack.arc_degrees = 120.0
	attack.radial_variant = variant
	attack.angular_speed_degrees = speed
	attack.title += " · " + ["слева направо", "справа налево", "из центра к краям", "от краёв к центру"][variant]
	attack.synchronise_duration()
	return attack
