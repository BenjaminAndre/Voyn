class_name PlanBuilder
extends RefCounted
## Builds the player's plans while a window is open (T13, round 2 item 2.6). Pure client logic with
## no nodes, so it is tested without a scene. It asks the rules engine for every fact (reachable
## cells, valid targets, Areas, validation, the preview) and decides none of them.
##
## A plan has two slots, Move and Ability (GDD R9.4). The order they are filled in is the plan order
## (R3.4): Move then ability is "close in and strike" (move_first), ability then Move is "hit and run"
## (ability_first). Choosing a slot again replaces it and keeps its place in the order.
##
## A draft per Creature: {"path": Array[Vector2i], "ability": String, "target": Vector2i,
## "has_target": bool, "slots": Array[String] (filled slots in fill order: "move", "ability"),
## "order": "move_first" | "ability_first" (derived from slots)}.

const SLOT_MOVE: String = "move"
const SLOT_ABILITY: String = "ability"

var state: FightState
var drafts: Dictionary = {}


func reset(new_state: FightState) -> void:
	state = new_state
	drafts = {}


## Moves the drafts onto a new board (the next window's), keeping them as a safety net: a draft
## whose Creature is gone, or whose plan no longer validates, is dropped, and an aim that was never
## finished is cancelled. Plans made during the previous resolution carry over through this (R3.3).
func rebase(new_state: FightState) -> void:
	state = new_state
	var ids: Array[int] = []
	for id: int in drafts.keys():
		ids.append(id)
	for id: int in ids:
		if not state.fighters[id].on_board():
			drafts.erase(id)
			continue
		cancel_pending_ability(id)
		var plan: Dictionary = plan_for(id)
		if plan.is_empty():
			drafts.erase(id)
		elif not bool(RulesEngine.validate_plan(state, plan)["ok"]):
			drafts.erase(id)


func draft(id: int) -> Dictionary:
	if not drafts.has(id):
		drafts[id] = {
			"path": [] as Array[Vector2i], "ability": "", "target": Vector2i.ZERO, "has_target": false,
			"slots": [] as Array[String], "order": Plans.ORDER_MOVE_FIRST,
		}
	return drafts[id]


func clear(id: int) -> void:
	drafts.erase(id)


func clear_all() -> void:
	drafts = {}


func has_plan(id: int) -> bool:
	return not plan_for(id).is_empty()


## Sets the Move to `cell` along the default path (R4.6), replacing any earlier Move. Returns false
## if it is out of reach. Choosing the fighter's own cell clears the Move.
func set_path_to(id: int, cell: Vector2i) -> bool:
	var fighter: FighterState = state.fighters[id]
	var entry: Dictionary = draft(id)
	if cell == state.cell_of(fighter):
		entry["path"] = [] as Array[Vector2i]
		_unfill(id, SLOT_MOVE)
		_forget_stale_target(id)
		return true
	var reach: Dictionary = Movement.reachable(state, fighter)
	var index: int = state.grid.index_of(cell)
	if not reach.has(index):
		return false
	entry["path"] = (reach[index]["path"] as Array[Vector2i]).duplicate()
	_fill(id, SLOT_MOVE)
	_forget_stale_target(id)
	return true


## Chooses an ability ("" for none), replacing any earlier one, and waits for its target. A `self`
## ability is complete at once. A replaced ability keeps its place in the plan order.
func set_ability(id: int, ability_id: String) -> void:
	var entry: Dictionary = draft(id)
	entry["ability"] = ability_id
	entry["has_target"] = false
	if ability_id == "":
		_unfill(id, SLOT_ABILITY)
		return
	if str(state.abilities[ability_id]["target"]) == "self":
		entry["has_target"] = true
		_fill(id, SLOT_ABILITY)
		entry["target"] = state.grid.cell_at(planned_cell(id))


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
	_fill(id, SLOT_ABILITY)
	return true


## Drops an ability that was chosen but never aimed (cancelling the aim). Does nothing otherwise.
func cancel_pending_ability(id: int) -> void:
	if not drafts.has(id):
		return
	var entry: Dictionary = drafts[id]
	if str(entry["ability"]) != "" and not bool(entry["has_target"]):
		set_ability(id, "")


## The cell index the Creature will use its ability from: the end of its path if it moves first.
## While an ability is still being aimed after a Move is set, that Move comes first.
func planned_cell(id: int) -> int:
	var fighter: FighterState = state.fighters[id]
	var entry: Dictionary = draft(id)
	var path: Array = entry["path"]
	if not path.is_empty() and str(entry["order"]) == Plans.ORDER_MOVE_FIRST:
		return state.grid.index_of(path[path.size() - 1])
	return fighter.cell


## Cells the Creature could walk to with its current MP (always from where it stands now).
func reachable_cells(id: int) -> Array[int]:
	var cells: Array[int] = []
	var reach: Dictionary = Movement.reachable(state, state.fighters[id])
	for index: int in reach.keys():
		cells.append(index)
	cells.sort()
	return cells


## Why the Creature cannot choose Move right now ("" if it can).
func move_unavailable_reason(id: int) -> String:
	var fighter: FighterState = state.fighters[id]
	if fighter.has_status("rooted"):
		return "rooted"
	if fighter.has_trait("stationary"):
		return "cannot move"
	if fighter.mp <= 0:
		return "no MP"
	return ""


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
## target yet is left out.
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


## A one-line description of a Creature's plan for its card, in plan order.
func summary(id: int) -> String:
	var entry: Dictionary = draft(id)
	var parts: Array[String] = []
	var path: Array = entry["path"]
	var ability_id: String = str(entry["ability"])
	var ability_text: String = ""
	if ability_id != "":
		var label: String = str(state.abilities[ability_id].get("name", ability_id))
		ability_text = label if bool(entry["has_target"]) else "pick a target for %s" % label
	var move_text: String = "move %d" % path.size() if not path.is_empty() else ""
	var slots: Array = entry["slots"]
	if str(entry["order"]) == Plans.ORDER_ABILITY_FIRST and slots.has(SLOT_ABILITY):
		parts = [ability_text, move_text]
	else:
		parts = [move_text, ability_text]
	var kept: Array[String] = []
	for text: String in parts:
		if text != "":
			kept.append(text)
	return " then ".join(kept) if not kept.is_empty() else "waits"


func _fill(id: int, slot: String) -> void:
	var entry: Dictionary = draft(id)
	var slots: Array = entry["slots"]
	if not slots.has(slot):
		slots.append(slot)
	_update_order(id)


func _unfill(id: int, slot: String) -> void:
	var entry: Dictionary = draft(id)
	var slots: Array = entry["slots"]
	slots.erase(slot)
	_update_order(id)


## The plan order is the order the slots were filled in (ability first only if it came first).
func _update_order(id: int) -> void:
	var entry: Dictionary = draft(id)
	var slots: Array = entry["slots"]
	var ability_at: int = slots.find(SLOT_ABILITY)
	var move_at: int = slots.find(SLOT_MOVE)
	entry["order"] = Plans.ORDER_ABILITY_FIRST if (ability_at >= 0 and move_at >= 0 and ability_at < move_at) else Plans.ORDER_MOVE_FIRST


## After the Move changes, an aimed ability may no longer be valid from the new position.
func _forget_stale_target(id: int) -> void:
	var entry: Dictionary = draft(id)
	if str(entry["ability"]) == "" or not bool(entry["has_target"]):
		return
	if str(state.abilities[str(entry["ability"])]["target"]) == "self":
		entry["target"] = state.grid.cell_at(planned_cell(id))
		return
	if not target_cells(id).has(state.grid.index_of(entry["target"])):
		entry["has_target"] = false
