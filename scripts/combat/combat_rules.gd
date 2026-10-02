extends RefCounted
class_name CombatRules

## Authoritative rules for combat damage eligibility, friendly fire prevention,
## and faction/team resolution.

enum Team {
	NONE = 0,
	PLAYER = 1,
	ENEMY = 2,
	NEUTRAL = 3
}

## Resolves the team of a given node based on groups, classes, metadata, and hierarchy.
static func get_team(node: Variant) -> Team:
	if not is_instance_valid(node) or not (node is Node):
		return Team.NONE

	if (node as Node).has_meta("team"):
		var m = (node as Node).get_meta("team")
		if m is int:
			return m as Team

	# Resolve HitboxArea wrapper
	if node is HitboxArea:
		var hb: HitboxArea = node as HitboxArea
		if hb.source_team != Team.NONE:
			return hb.source_team
		if is_instance_valid(hb.owner_entity):
			return get_team(hb.owner_entity)

	# Resolve HurtboxArea wrapper
	if node is HurtboxArea:
		var target: Node = (node as HurtboxArea).get_target_node()
		if is_instance_valid(target) and target != node:
			return get_team(target)

	if node.is_in_group("player") or node.is_in_group("allies") or node.name == "Player":
		return Team.PLAYER

	if node is BuildingBase or node.is_in_group("buildings") or node.is_in_group("walls") or node.is_in_group("towers") or node.is_in_group("floor_spikes") or node.is_in_group("remote_mines") or node.is_in_group("decoy"):
		return Team.PLAYER

	if node.is_in_group("enemies") or node.is_in_group("enemy"):
		return Team.ENEMY
	if node.get_script() and "enemy" in node.get_script().resource_path.to_lower():
		return Team.ENEMY

	if node.is_in_group("resources") or node.is_in_group("resource_nodes"):
		return Team.NEUTRAL
	if node.get_script() and "resource_" in node.get_script().resource_path.to_lower():
		return Team.NEUTRAL

	# Check parent hierarchy as fallback
	var parent: Node = (node as Node).get_parent()
	if is_instance_valid(parent) and not (parent is Window or parent is Viewport):
		if parent.is_in_group("player") or parent.is_in_group("allies") or parent.name == "Player":
			return Team.PLAYER
		if parent is BuildingBase or parent.is_in_group("buildings") or parent.is_in_group("walls") or parent.is_in_group("towers"):
			return Team.PLAYER
		if parent.is_in_group("enemies") or parent.is_in_group("enemy"):
			return Team.ENEMY

	return Team.NONE

## Checks whether the target node is a friendly building, wall, tower, or trap.
static func is_friendly_building(node: Variant) -> bool:
	if not is_instance_valid(node) or not (node is Node):
		return false
	if node is BuildingBase:
		return true
	if (node as Node).is_in_group("buildings") or (node as Node).is_in_group("walls") or (node as Node).is_in_group("towers"):
		return true
	var parent: Node = (node as Node).get_parent()
	if is_instance_valid(parent) and (parent is BuildingBase or parent.is_in_group("buildings") or parent.is_in_group("walls") or parent.is_in_group("towers")):
		return true
	return false

## Evaluates whether attacker can deal combat damage to target.
## Prevents friendly fire:
## - Player attacks & abilities NEVER damage friendly buildings.
## - Friendly buildings/towers/traps NEVER damage themselves or other friendly buildings.
## - Enemies CAN damage player buildings and the player.
## - Player attacks CAN damage enemies and resource nodes.
static func can_damage(attacker: Variant, target: Node, attacker_team: Team = Team.NONE) -> bool:
	if not is_instance_valid(target):
		return false
	if target.get("is_dying") == true:
		return false

	var valid_attacker: Node = attacker as Node if (is_instance_valid(attacker) and attacker is Node) else null

	var resolved_target: Node = target
	if target is HurtboxArea:
		var candidate = (target as HurtboxArea).get_target_node()
		if is_instance_valid(candidate):
			resolved_target = candidate
		elif target.get_parent():
			resolved_target = target.get_parent()

	# Self-damage is forbidden (e.g. tower shooting itself or trap triggering on itself)
	if valid_attacker and (valid_attacker == resolved_target or valid_attacker == target):
		return false

	var eff_attacker_team: Team = attacker_team
	if valid_attacker:
		var t: Team = get_team(valid_attacker)
		if t != Team.NONE:
			eff_attacker_team = t

	# Target is a friendly building / wall / tower / trap
	if is_friendly_building(resolved_target):
		# Rejection: Player faction attacks cannot damage friendly buildings
		if eff_attacker_team == Team.PLAYER:
			return false
		if valid_attacker:
			if valid_attacker.is_in_group("player") or valid_attacker.name == "Player" or valid_attacker.is_in_group("allies"):
				return false
			if valid_attacker is BuildingBase or valid_attacker.is_in_group("buildings") or valid_attacker.is_in_group("walls") or valid_attacker.is_in_group("towers"):
				return false
			if valid_attacker.is_in_group("enemies") or valid_attacker.is_in_group("enemy"):
				return true
		if eff_attacker_team == Team.ENEMY:
			return true
		return eff_attacker_team != Team.PLAYER

	# Target is an enemy
	var target_team: Team = get_team(resolved_target)
	if target_team == Team.ENEMY or (is_instance_valid(resolved_target) and (resolved_target.is_in_group("enemies") or resolved_target.is_in_group("enemy"))):
		# Player faction can damage enemies
		if eff_attacker_team == Team.PLAYER:
			return true
		if valid_attacker and (valid_attacker.is_in_group("player") or valid_attacker.name == "Player" or valid_attacker is BuildingBase or valid_attacker.is_in_group("buildings") or valid_attacker.is_in_group("towers")):
			return true
		# Enemies do not friendly-fire each other
		if eff_attacker_team == Team.ENEMY:
			return false
		return true

	# Target belongs to Player faction (player character, decoy dummy, summons, allies)
	if target_team == Team.PLAYER:
		# Player faction cannot damage player faction entities
		if eff_attacker_team == Team.PLAYER:
			return false
		if valid_attacker:
			if valid_attacker.is_in_group("player") or valid_attacker.name == "Player" or valid_attacker is BuildingBase or valid_attacker.is_in_group("buildings") or valid_attacker.is_in_group("walls") or valid_attacker.is_in_group("towers") or valid_attacker.is_in_group("allies") or valid_attacker.is_in_group("decoy"):
				return false
			if valid_attacker.is_in_group("enemies") or valid_attacker.is_in_group("enemy"):
				return true
		# Enemy can damage player faction
		if eff_attacker_team == Team.ENEMY:
			return true
		# Scripted / environmental / neutral damage without player team provenance is allowed
		return eff_attacker_team != Team.PLAYER

	# Target is a resource node (rock, tree)
	if target_team == Team.NEUTRAL or (is_instance_valid(resolved_target) and (resolved_target.is_in_group("resources") or resolved_target.is_in_group("resource_nodes"))):
		return true

	return true
