class_name Plans
extends RefCounted
## Plan format and validation (GDD R3.4, docs/architecture.md).
##
## A plan is a Dictionary:
##   {"fighter": int, "from_cell": [q, r], "move_path": [[q, r], ...], "ability": "",
##    "target_cell": [q, r], "order": "move_first" | "ability_first"}
## Only "fighter" is required, and a plan with only a fighter means "wait". A plan that moves (or
## later, uses an ability) must carry `from_cell`, the cell the fighter stood on when it planned.
## `move_path` lists the cells entered, own cell excluded. A plan with no ability resolves its move
## in Lead moves. Abilities arrive with T7; keeper plans with T10b.
##
## Two layers. `shape_errors` finds malformed plans, which resolve_step refuses (nothing changes).
## `validate` adds the rules a player must respect while planning, against the board as it stands:
## allies' plans never affect it. Whatever still goes wrong at resolution is a stop or a Fizzle,
## never an error.

const ORDER_MOVE_FIRST: String = "move_first"
const ORDER_ABILITY_FIRST: String = "ability_first"
const KEYS: Array[String] = ["fighter", "from_cell", "move_path", "ability", "target_cell", "order"]


## Machine-readable error codes for a plan that cannot be read or is stale. Empty if well-formed.
static func shape_errors(state: FightState, plan: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (plan is Dictionary):
		errors.append("plan_not_object")
		return errors
	var dict: Dictionary = plan
	if dict.has("keeper"):
		errors.append("keeper_plans_unavailable")
		return errors
	for key: Variant in dict.keys():
		if not KEYS.has(str(key)):
			errors.append("unknown_key:%s" % str(key))
	if not dict.has("fighter") or typeof(dict["fighter"]) != TYPE_INT:
		errors.append("missing_fighter")
		return errors
	var id: int = int(dict["fighter"])
	if id < 0 or id >= state.fighters.size() or not state.fighters[id].on_board():
		errors.append("fighter_not_active")
		return errors
	var fighter: FighterState = state.fighters[id]
	if dict.has("order") and not [ORDER_MOVE_FIRST, ORDER_ABILITY_FIRST].has(dict["order"]):
		errors.append("bad_order")
	if dict.has("ability"):
		if typeof(dict["ability"]) != TYPE_STRING:
			errors.append("bad_ability")
		elif str(dict["ability"]) != "":
			errors.append("abilities_unavailable")
	if dict.has("target_cell") and not _is_cell(dict["target_cell"]):
		errors.append("bad_target_cell")

	var acts: bool = not (dict.get("move_path", []) is Array and (dict.get("move_path", []) as Array).is_empty())
	if dict.has("from_cell"):
		if not _is_cell(dict["from_cell"]):
			errors.append("bad_from_cell")
		elif _cell_of(dict["from_cell"]) != state.cell_of(fighter):
			errors.append("stale_from_cell")
	elif acts:
		errors.append("missing_from_cell")
	if dict.has("move_path"):
		errors.append_array(_path_errors(state, fighter, dict["move_path"]))
	return errors


## The plan's move path as cell indices (own cell excluded). Call only on a well-formed plan.
static func path_indices(state: FightState, plan: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for entry: Array in plan.get("move_path", []):
		result.append(state.grid.index_of(Vector2i(int(entry[0]), int(entry[1]))))
	return result


## "move_first" (default) plans resolve their move in Lead moves; "ability_first" plans in Trail moves.
static func is_lead_move(plan: Dictionary) -> bool:
	return str(plan.get("order", ORDER_MOVE_FIRST)) == ORDER_MOVE_FIRST


## Plan-time validation against the board as it stands (R3.4, R6.1). Allies' plans do not matter.
## The path may cross cells that are occupied now, because their occupants may leave; Engagement
## and blocking are settled at resolution (R4.8). `player` >= 0 also checks the fighter is theirs.
## Returns {"ok": bool, "errors": Array[String]}. Codes are stable strings.
static func validate(state: FightState, plan: Variant, player: int = -1) -> Dictionary:
	var errors: Array[String] = []
	if state.status != FightState.STATUS_FIGHTING:
		errors.append("not_fighting")
		return {"ok": false, "errors": errors}
	errors.append_array(shape_errors(state, plan))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var dict: Dictionary = plan
	var fighter: FighterState = state.fighters[int(dict["fighter"])]
	if player >= 0 and fighter.player != player:
		errors.append("not_your_fighter")
	var path: Array[int] = path_indices(state, dict)
	if not path.is_empty():
		if fighter.has_status("rooted") or fighter.has_trait("stationary"):
			errors.append("cannot_move")
		for cell_index: int in path:
			if state.walkable[cell_index] == 0:
				errors.append("cell_not_walkable")
				break
		if path.size() > fighter.mp:
			errors.append("path_too_long")
	return {"ok": errors.is_empty(), "errors": errors}


## True if the value is a [q, r] pair of ints.
static func _is_cell(value: Variant) -> bool:
	if value is Array:
		var pair: Array = value
		return pair.size() == 2 and typeof(pair[0]) == TYPE_INT and typeof(pair[1]) == TYPE_INT
	return false


static func _cell_of(value: Variant) -> Vector2i:
	var pair: Array = value
	return Vector2i(int(pair[0]), int(pair[1]))


static func _path_errors(state: FightState, fighter: FighterState, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (value is Array):
		errors.append("bad_move_path")
		return errors
	var cursor: Vector2i = state.cell_of(fighter)
	var visited: Array[Vector2i] = [cursor]
	for entry: Variant in (value as Array):
		if not _is_cell(entry):
			errors.append("bad_move_path")
			return errors
		var cell: Vector2i = _cell_of(entry)
		if not state.grid.has_cell(cell):
			errors.append("path_outside_arena")
			return errors
		if Hex.distance(cursor, cell) != 1:
			errors.append("path_not_contiguous")
			return errors
		if visited.has(cell):
			errors.append("path_repeats_cell")
			return errors
		visited.append(cell)
		cursor = cell
	return errors
