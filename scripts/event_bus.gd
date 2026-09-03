extends Node

# Resource events
signal resources_changed(wood: int, stone: int, iron: int)
signal resource_gathered(resource_type: String, amount: int, gatherer: Node)

# Combat events  
signal enemy_killed(enemy: Node, position: Vector3)
signal damage_dealt(source: Node, target: Node, amount: float, type: String)
signal player_died()

# Building events
signal building_placed(building_id: String, cell: Vector2i, building: Node)
signal building_destroyed(cell: Vector2i, building: Node)

# Game flow events
signal day_started(day_number: int)
signal night_started(night_number: int)
signal wave_started(wave_number: int, enemy_count: int)
signal wave_cleared(wave_number: int)

# Player events
signal player_health_changed(current: float, maximum: float)
signal player_xp_changed(current: float, max_xp: float, level: int)
signal player_level_up(new_level: int)
signal player_class_changed(new_class: int)

# Portal events
signal portal_repair_started()
signal portal_repair_complete()
signal portal_evacuation_started()

# Boss events
signal boss_spawned(boss: Node)
signal boss_defeated(boss: Node)
