class_name PlanBuilder
extends RefCounted
## Builds the player's plans while a window is open (T13). Pure client logic with no nodes, so it
## is tested without a scene. It asks the rules engine for every fact (reachable cells, valid
## targets, Areas, validation, the preview) and decides none of them.
##
## A draft per Creature: {"path": Array[Vector2i], "ability": String, "target": Vector2i,
## "has_target": bool, "order": "move_first" | "ability_first"}.

var state: FightState
var drafts: Dictionary = {}


func reset(new_state: FightState) -> void:
	state = new_state
	drafts = {}


func draft(id: int) -> Dictionary:
	if not drafts.has(id):
		drafts[id] = {"path": [] as Array[Vector2i], "ability": "", "target": Vector2i.ZERO, "has_target": false, "order": Plans.ORDER_MOVE_FIRST}
	return drafts[id]


func clear(id: int) -> void:
	drafts.erase(id)


func clear_all() -> void:
	drafts = {}


## Sets the move to `cell` along the default path (R4.6). Returns false if it is out of reach.
## Choosing the fighter's own cell clears the move.
func set_path_to(id: int, cell: Vector2i) -> bool:
	var fighter: FighterState = state.fighters[id]
	var entry: Dictionary = draft(id)
	if cell == state.cell_of(fighter):
		entry["path"] = [] as Array[Vector2i]
		_forget_stale_target(id)
		return true
	var reach: Dictionary = Movement.reachable(state, fighter)
	var index: int = state.grid.index_of(cell)
	if not reach.has(index):
		return false
	entry["path"] = (reach[index]["path"] as Array[Vector2i]).duplicate()
	_forget_stale_target(id)
	return true


## Chooses an ability ("" for none). The target must be chosen again.
func set_ability(id: int, ability_id: String) -> void:
	var entry: Dictionary = draft(id)
	entry["ability"] = ability_id
	entry["has_target"] = false
	if ability_id != "" and str(state.abilities[ability_id]["target"]) == "self":
		entry["has_target"] = true
		entry["target"] = state.grid.cell_at(planned_cell(id))


func set_order(id: int, order: String) -> void:
	draft(id)["order"] = order
	_forget_stale_target(id)


## Aims the chosen ability at `cell`. Returns false if it is not a valid target from where the
## plan puts the Creature.
func set_target(id: int, cell: Vector2i) -> bool:
	var entry: Dictionary = draft(id)
	if str(entry["ability"]) == "":
		return false
	if not target_cells(id).has(state.grid.index_of(cell)):
		return false
	entry["target"] = cell
	entry["has_target"] = true
	return true


## The cell index the Creature will use its ability from: the end of its path if it moves first.
func planned_cell(id: int) -> int:
	var fighter: FighterState = state.fighters[id]
	var entry: Dictionary = draft(id)
	var path: Array = entry["path"]
	if not path.is_empty() and str(entry["order"]) == Plans.ORDER_MOVE_FIRST:
		return state.grid.index_of(path[path.size() - 1])
	return fighter.cell


## Cells the Creature could walk to with its current MP.
func reachable_cells(id: int) -> Array[int]:
	var cells: Array[int] = []
	var reach: Dictionary = Movement.reachable(state, state.fighters[id])
	for index: int in reach.keys():
		cells.append(index)
	cells.sort()
	return cells


## Valid targets of the chosen ability, from where the plan puts the Creature.
func target_cells(id: int) -> PackedInt32Array:
	var ability_id: String = str(draft(id)["ability"])
	if ability_id == "":
		return PackedInt32Array()
	return Abilities.targets(state, state.fighters[id], state.abilities[ability_id], planned_cell(id))


## The cells the chosen ability would affect if aimed at `target`.
func area_cells(id: int, target: Vector2i) -> Array[int]:
	var ability_id: String = str(draft(id)["ability"])
	if ability_id == "":
		return []
	return Abilities.area_cells(state, state.abilities[ability_id], planned_cell(id), target)


## Why an ability cannot be chosen right now ("" if it can): not enough AP, or on cooldown.
func unavailable_reason(id: int, ability_id: String) -> String:
	var fighter: FighterState = state.fighters[id]
	var ability: Dictionary = state.abilities[ability_id]
	if fighter.ap < int(ability["ap_cost"]):
		return "not enough AP"
	if state.step < int(fighter.cooldowns.get(ability_id, 0)):
		return "ready in step %d" % int(fighter.cooldowns[ability_id])
	return ""


## The plan dictionary for one Creature, or {} if the draft plans nothing. An ability with no
## target yet (and not `self`) is left out.
func plan_for(id: int) -> Dictionary:
	if not drafts.has(id):
		return {}
	var entry: Dictionary = drafts[id]
	var path: Array = entry["path"]
	var ability_id: String = str(entry["ability"])
	var has_ability: bool = ability_id != "" and bool(entry["has_target"])
	if path.is_empty() and not has_ability:
		return {}
	var from: Vector2i = state.cell_of(state.fighters[id])
	var plan: Dictionary = {"fighter": id, "from_cell": [from.x, from.y], "order": str(entry["order"])}
	if not path.is_empty():
		var cells: Array = []
		for cell: Vector2i in path:
			cells.append([cell.x, cell.y])
		plan["move_path"] = cells
	if has_ability:
		var target: Vector2i = entry["target"]
		plan["ability"] = ability_id
		plan["target_cell"] = [target.x, target.y]
	return plan


func validation(id: int) -> Dictionary:
	var plan: Dictionary = plan_for(id)
	if plan.is_empty():
		return {"ok": true, "errors": [] as Array[String]}
	return RulesEngine.validate_plan(state, plan)


## Every Creature's valid plan, in roster order. A plan that fails validation is left out.
func plans() -> Array:
	var result: Array = []
	var ids: Array[int] = []
	for id: int in drafts.keys():
		ids.append(id)
	ids.sort()
	for id: int in ids:
		var plan: Dictionary = plan_for(id)
		if not plan.is_empty() and RulesEngine.validate_plan(state, plan)["ok"]:
			result.append(plan)
	return result


## R9.2 The preview: the real resolution on a copy of the state with the players' plans and no
## Monster plans. Returns the resolve result ({} if there is nothing to resolve).
func preview() -> Dictionary:
	var mine: Array = plans()
	if mine.is_empty():
		return {}
	return RulesEngine.resolve_step(state, mine)


## What the preview says each fighter would lose or gain: {id: {"delta": int, "note": String}} with
## a note "Cleansed" or "Killed" or "Downed" for a defeat. Fighters unaffected are left out.
func preview_changes(result: Dictionary) -> Dictionary:
	var changes: Dictionary = {}
	if result.is_empty() or not result["ok"]:
		return changes
	var after: FightState = result["state"]
	var how: Dictionary = {}
	for event: Dictionary in result["events"]:
		if event["type"] == "defeated":
			how[int(event["fighter"])] = str(event["how"]).capitalize()
	for fighter: FighterState in state.fighters:
		var later: FighterState = after.fighters[fighter.id]
		var delta: int = later.hp - fighter.hp
		if delta != 0 or how.has(fighter.id):
			changes[fighter.id] = {"delta": delta, "note": str(how.get(fighter.id, ""))}
	return changes


## A one-line description of a Creature's plan for its card.
func summary(id: int) -> String:
	var entry: Dictionary = draft(id)
	var parts: Array[String] = []
	var path: Array = entry["path"]
	if not path.is_empty():
		parts.append("move %d" % path.size())
	var ability_id: String = str(entry["ability"])
	if ability_id != "":
		parts.append(str(state.abilities[ability_id].get("name", ability_id)) if bool(entry["has_target"]) else "pick a target for %s" % ability_id)
	if path.size() > 0 and ability_id != "" and bool(entry["has_target"]):
		parts.append("(" + ("move first" if str(entry["order"]) == Plans.ORDER_MOVE_FIRST else "ability first") + ")")
	return ", ".join(parts) if not parts.is_empty() else "waits"


func _forget_stale_target(id: int) -> void:
	var entry: Dictionary = draft(id)
	if str(entry["ability"]) == "" or not bool(entry["has_target"]):
		return
	if str(state.abilities[str(entry["ability"])]["target"]) == "self":
		entry["target"] = state.grid.cell_at(planned_cell(id))
		return
	if not target_cells(id).has(state.grid.index_of(entry["target"])):
		entry["has_target"] = false
