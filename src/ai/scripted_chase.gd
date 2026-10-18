class_name ScriptedChase
extends RefCounted
## The `scripted_chase` behavior (docs/gdd/90-placeholder-content.md), until the greedy AI (T14):
## deterministic and dumb on purpose. It aims at where Creatures stand now and never predicts
## movement, so dodging by moving works against it. Integers only; it plans from the visible board.
##
## For one Monster:
##   1. Target: the nearest Creature by hex distance (tie: roster order).
##   2. Strike from here: the first ability (in the Monster's list order) that can hit the target's
##      cell from where it stands (AP, range, LoS, axis, cooldown).
##   3. Otherwise close in: among the reachable cells from which some ability could hit the target's
##      cell, go to the cheapest by MP (tie: cell order) along the default path, and strike from there
##      (`move_first`). If there is none, move as far toward the target as MP allows, with no ability.
##   4. If it cannot afford any ability, it only moves.


## The plan for one Monster, or {} if it waits.
static func plan(state: FightState, fighter_id: int) -> Dictionary:
	var fighter: FighterState = state.fighters[fighter_id]
	if not fighter.on_board():
		return {}
	var target: FighterState = _nearest_creature(state, fighter)
	if target == null:
		return {}
	var target_cell: Vector2i = state.cell_of(target)
	var from_cell: Vector2i = state.cell_of(fighter)

	# 2. Strike from here.
	var here: String = _usable_ability(state, fighter, fighter.cell, target_cell)
	if here != "":
		return _plan(fighter, from_cell, [], here, target_cell)

	# 3. Close in. Reachable cells come with their default paths (R4.6).
	var reach: Dictionary = Movement.reachable(state, fighter)
	var indices: Array[int] = []
	for index: int in reach.keys():
		indices.append(index)
	indices.sort()  # cell order
	var best_index: int = -1
	var best_ability: String = ""
	var best_cost: int = 0
	for index: int in indices:
		if index == fighter.cell:
			continue
		var ability: String = _usable_ability(state, fighter, index, target_cell)
		if ability == "":
			continue
		var cost: int = int(reach[index]["mp"])
		if best_index < 0 or cost < best_cost:
			best_index = index
			best_ability = ability
			best_cost = cost
	if best_index >= 0:
		return _plan(fighter, from_cell, reach[best_index]["path"], best_ability, target_cell)

	# No ability can reach it this step (or it is low on AP): walk as close as MP allows. The cell
	# nearest the target wins, then the cheapest in MP, then cell order.
	var closest: int = -1
	var closest_distance: int = Hex.distance(from_cell, target_cell)
	var closest_cost: int = 0
	for index: int in indices:
		if index == fighter.cell:
			continue
		var distance: int = Hex.distance(state.grid.cell_at(index), target_cell)
		var cost: int = int(reach[index]["mp"])
		if distance < closest_distance or (closest >= 0 and distance == closest_distance and cost < closest_cost):
			closest = index
			closest_distance = distance
			closest_cost = cost
	if closest < 0:
		return {}
	return _plan(fighter, from_cell, reach[closest]["path"], "", target_cell)


## Plans for every Monster whose behavior is `scripted_chase`, in roster order. `behaviors` maps a
## behavior ID to its definition ({"kind": ...}).
static func plans(state: FightState, behaviors: Dictionary) -> Array:
	var result: Array = []
	for fighter: FighterState in state.living(FighterState.SIDE_MONSTERS):
		var definition: Dictionary = behaviors.get(fighter.behavior, {})
		if str(definition.get("kind", "")) != "scripted_chase":
			continue
		var one: Dictionary = plan(state, fighter.id)
		if not one.is_empty():
			result.append(one)
	return result


static func _nearest_creature(state: FightState, fighter: FighterState) -> FighterState:
	var best: FighterState = null
	var best_distance: int = 0
	for creature: FighterState in state.living(FighterState.SIDE_KEEPERS):
		if not creature.on_board():
			continue
		var distance: int = Hex.distance(state.cell_of(fighter), state.cell_of(creature))
		if best == null or distance < best_distance:
			best = creature
			best_distance = distance
	return best


## The first ability, in list order, that is valid from `from_cell` against `target_cell`; "" if none.
static func _usable_ability(state: FightState, fighter: FighterState, from_cell: int, target_cell: Vector2i) -> String:
	for ability_id: String in fighter.abilities:
		var ability: Dictionary = state.abilities[ability_id]
		if Abilities.check(state, fighter, ability, from_cell, target_cell) == "":
			return ability_id
	return ""


static func _plan(fighter: FighterState, from_cell: Vector2i, path: Array, ability: String, target_cell: Vector2i) -> Dictionary:
	var result: Dictionary = {"fighter": fighter.id, "from_cell": [from_cell.x, from_cell.y]}
	if not path.is_empty():
		var cells: Array = []
		for cell: Vector2i in path:
			cells.append([cell.x, cell.y])
		result["move_path"] = cells
		result["order"] = Plans.ORDER_MOVE_FIRST
	if ability != "":
		result["ability"] = ability
		result["target_cell"] = [target_cell.x, target_cell.y]
	return result
