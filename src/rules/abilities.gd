class_name Abilities
extends RefCounted
## Abilities (GDD R6, R7.1-R7.3, R3.6-R3.7): validity, Areas, resolution by phase, the `targets` and
## `threat_zone` queries. Integers only. Every iteration runs in roster order or cell order.
##
## Resolution of one phase (Prep, Dash or Strike):
##   Prep and Dash resolve ability by ability in roster order: validity check, cost, effects,
##   defeats, footprint.
##   Strike resolves together (R3.6): every ability is checked and costed, all numbers are computed
##   from the state at the start of Strike, then everything is applied, then defeats are checked
##   (R11.3), then footprints apply (R11.2).
## A fizzled ability has no effect and no footprint, but its AP is still spent (R3.7).


## R6.1 Why an ability is not valid, as a stable code, or "" if it is. `user_cell` is the cell index
## the user stands on when the ability resolves (at plan time: the cell the plan puts it on).
## The order of the checks follows R6.1.
static func check(state: FightState, fighter: FighterState, ability: Dictionary, user_cell: int, target: Vector2i) -> String:
	if fighter.ap < int(ability["ap_cost"]):
		return "not_enough_ap"
	var target_index: int = state.grid.index_of(target)
	if target_index < 0:
		return "bad_target"
	var from: Vector2i = state.grid.cell_at(user_cell)
	var distance: int = Hex.distance(from, target)
	if distance < int(ability["min_range"]) or distance > int(ability["max_range"]):
		return "out_of_range"
	if bool(ability["needs_los"]) and not Los.has_los(from, target, _blocker(state, fighter)):
		return "no_los"
	if bool(ability["line_only"]) and not _on_axis(from, target):
		return "not_on_axis"
	if not _target_matches(state, fighter, str(ability["target"]), user_cell, target_index):
		return "bad_target"
	if state.step < int(fighter.cooldowns.get(str(ability["id"]), 0)):
		return "on_cooldown"
	return ""


## R6.2 The cells an ability affects: `single`, `burst(r)` or `line(n)` around the target cell,
## ignoring LoS and obstacles, kept inside the Arena. Cell indices in cell order.
static func area_cells(state: FightState, ability: Dictionary, user_cell: int, target: Vector2i) -> Array[int]:
	var area: Dictionary = ability["area"]
	var cells: Array[int] = []
	match str(area["shape"]):
		"single":
			cells.append(state.grid.index_of(target))
		"burst":
			for cell: Vector2i in Hex.disk(target, int(area["radius"])):
				var index: int = state.grid.index_of(cell)
				if index >= 0:
					cells.append(index)
		"line":
			var from: Vector2i = state.grid.cell_at(user_cell)
			var direction: int = Hex.push_direction(from, target)
			for i: int in int(area["length"]):
				var cell: Vector2i = target if direction < 0 else target + Hex.DIRECTIONS[direction] * i
				var index: int = state.grid.index_of(cell)
				if index >= 0:
					cells.append(index)
	cells.sort()
	return cells


## R6.2 The fighters an ability hits, by identity, in roster order: those standing in `area` that
## match `affects` (relative to the user's Side), plus the user itself if `include_user`.
static func affected_fighters(state: FightState, user: FighterState, ability: Dictionary, area: Array[int]) -> Array[int]:
	var ids: Array[int] = []
	for fighter: FighterState in state.fighters:
		if not fighter.on_board() or not area.has(fighter.cell):
			continue
		if fighter == user:
			if bool(ability["include_user"]):
				ids.append(fighter.id)
			continue
		match str(ability["affects"]):
			"enemies":
				if fighter.side != user.side:
					ids.append(fighter.id)
			"allies":
				if fighter.side == user.side:
					ids.append(fighter.id)
			"all":
				ids.append(fighter.id)
	return ids


## Query: every cell the fighter could target with an ability from `from_cell`, from the board as it
## stands (R6.1 checks 2-5: range, LoS, axis, target filter). Cell indices in cell order. AP and
## cooldown are not part of it: they say whether the ability can be used at all.
static func targets(state: FightState, fighter: FighterState, ability: Dictionary, from_cell: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var from: Vector2i = state.grid.cell_at(from_cell)
	var blocker: Callable = _blocker(state, fighter)
	for index: int in state.grid.size():
		var target: Vector2i = state.grid.cell_at(index)
		var distance: int = Hex.distance(from, target)
		if distance < int(ability["min_range"]) or distance > int(ability["max_range"]):
			continue
		if bool(ability["needs_los"]) and not Los.has_los(from, target, blocker):
			continue
		if bool(ability["line_only"]) and not _on_axis(from, target):
			continue
		if not _target_matches(state, fighter, str(ability["target"]), from_cell, index):
			continue
		result.append(index)
	return result


## Query (R9.1): the cells a fighter could reach and hit this step with its current AP and MP, from
## the board as it stands. It counts every hostile ability it can afford (damage, push or pull, not
## on cooldown), from every cell it can reach, aimed at any cell in range with LoS: whoever stands
## there would be hit, so the zone does not depend on who stands where now. Cell indices in cell order.
static func threat_zone(state: FightState, fighter: FighterState) -> PackedInt32Array:
	var zone: Dictionary = {}
	if not fighter.on_board():
		return PackedInt32Array()
	var reach: Dictionary = Movement.reachable(state, fighter)
	var origin_cells: Array[int] = []
	for index: int in reach.keys():
		origin_cells.append(index)
	origin_cells.sort()
	for ability_id: String in fighter.abilities:
		var ability: Dictionary = state.abilities[ability_id]
		if not _is_hostile(ability):
			continue
		if fighter.ap < int(ability["ap_cost"]) or state.step < int(fighter.cooldowns.get(ability_id, 0)):
			continue
		for from_cell: int in origin_cells:
			var from: Vector2i = state.grid.cell_at(from_cell)
			for index: int in state.grid.size():
				var target: Vector2i = state.grid.cell_at(index)
				var distance: int = Hex.distance(from, target)
				if distance < int(ability["min_range"]) or distance > int(ability["max_range"]):
					continue
				if bool(ability["line_only"]) and not _on_axis(from, target):
					continue
				if bool(ability["needs_los"]) and not Los.has_los(from, target, _blocker(state, fighter)):
					continue
				for hit: int in area_cells(state, ability, from_cell, target):
					zone[hit] = true
	var cells: Array[int] = []
	for index: int in zone.keys():
		cells.append(index)
	cells.sort()
	return PackedInt32Array(cells)


## Resolves the abilities of the plans whose `phase` tag is `phase`. Events are appended to `events`.
static func run_phase(state: FightState, plans: Array, phase: String, events: Array[Dictionary]) -> void:
	var entries: Array[Dictionary] = []
	for plan: Dictionary in plans:
		var ability_id: String = str(plan.get("ability", ""))
		if ability_id == "" or str(state.abilities[ability_id]["phase"]) != phase:
			continue
		entries.append({"fighter": int(plan["fighter"]), "ability": state.abilities[ability_id], "plan": plan})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["fighter"]) < int(b["fighter"]))

	if phase == Events.PHASE_STRIKE:
		_run_strike(state, entries, events)
		return
	for entry: Dictionary in entries:
		var fighter: FighterState = state.fighters[int(entry["fighter"])]
		if not fighter.alive:
			continue  # defeated earlier this step: its plan is dropped (R7.4)
		var prepared: Dictionary = _prepare(state, fighter, entry, events)
		if prepared.is_empty():
			continue
		_apply_ops(state, prepared, events)
		_defeat_the_fallen(state, events)
		_apply_footprint(state, prepared, events)


# --- Resolution ---


## Checks an ability at resolution time, pays for it, and returns what it will do, computed from the
## state as it stands: {"user", "ability", "area", "karma", "ops"}. Returns {} if it fizzled.
static func _prepare(state: FightState, fighter: FighterState, entry: Dictionary, events: Array[Dictionary]) -> Dictionary:
	var ability: Dictionary = entry["ability"]
	var plan: Dictionary = entry["plan"]
	var target: Vector2i = _plan_target(state, fighter, plan)
	var reason: String = check(state, fighter, ability, fighter.cell, target)
	_commit_cost(state, fighter, ability, events)
	if reason != "":
		events.append(Events.fizzled(fighter.id, str(ability["id"]), target, reason))
		return {}
	events.append(Events.ability_used(fighter.id, str(ability["id"]), target))

	var area: Array[int] = area_cells(state, ability, fighter.cell, target)
	var hit: Array[int] = affected_fighters(state, fighter, ability, area)
	var ops: Array[Dictionary] = []
	for effect: Dictionary in ability["effects"]:
		for id: int in hit:
			var victim: FighterState = state.fighters[id]
			match str(effect["type"]):
				"damage":
					ops.append({"kind": "damage", "fighter": id, "amount": Damage.compute(state, fighter, victim, int(effect["base"]))})
				"heal":
					ops.append({"kind": "heal", "fighter": id, "amount": int(effect["amount"])})
				"shield":
					ops.append({"kind": "shield", "fighter": id, "amount": int(effect["amount"]), "duration": int(effect["duration"]), "source": fighter.id})
				"apply_status":
					ops.append({"kind": "status", "fighter": id, "status": str(effect["status"]), "magnitude": int(effect["magnitude"]), "duration": int(effect["duration"]), "source": fighter.id})
	return {"user": fighter.id, "ability": str(ability["id"]), "area": area, "karma": int(ability["karma"]), "ops": ops}


## R3.7 AP is spent whether or not the ability fizzles, and the cooldown starts (R6.1): both happen
## here and nowhere else.
static func _commit_cost(state: FightState, fighter: FighterState, ability: Dictionary, events: Array[Dictionary]) -> void:
	var spent: int = mini(fighter.ap, int(ability["ap_cost"]))
	fighter.ap -= spent
	if spent > 0:
		events.append(Events.ap_spent(fighter.id, spent, fighter.ap))
	if int(ability["cooldown"]) > 0:
		fighter.cooldowns[str(ability["id"])] = state.step + int(ability["cooldown"])


static func _apply_ops(state: FightState, prepared: Dictionary, events: Array[Dictionary]) -> void:
	for op: Dictionary in prepared["ops"]:
		var victim: FighterState = state.fighters[int(op["fighter"])]
		if not victim.alive:
			continue
		match str(op["kind"]):
			"damage":
				Damage.apply(state, victim, int(op["amount"]), "ability", events)
			"heal":
				Damage.heal(victim, int(op["amount"]), "ability", events)
			"shield":
				Statuses.apply_shield(state, victim, int(op["amount"]), int(op["duration"]), int(op["source"]), events)
			"status":
				Statuses.apply(state, victim, str(op["status"]), int(op["magnitude"]), int(op["duration"]), int(op["source"]), events)


## R7.4, R11.3 Everyone at 0 HP is defeated now, in roster order.
static func _defeat_the_fallen(state: FightState, events: Array[Dictionary]) -> void:
	for fighter: FighterState in state.fighters:
		if fighter.alive and fighter.on_board() and fighter.hp <= 0:
			Defeat.apply(state, fighter, events)


## R11.2 Adds the footprint to every cell of the Area, clamped to the karma range.
static func _apply_footprint(state: FightState, prepared: Dictionary, events: Array[Dictionary]) -> void:
	var karma: int = int(prepared["karma"])
	if karma == 0:
		return
	for index: int in prepared["area"]:
		var old: int = state.karma[index]
		var value: int = clampi(old + karma, Land.BLIGHTED, Land.THRIVING)
		if value != old:
			state.karma[index] = value
			events.append(Events.karma_changed(state.grid.cell_at(index), old, value))


static func _run_strike(state: FightState, entries: Array[Dictionary], events: Array[Dictionary]) -> void:
	var prepared: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var fighter: FighterState = state.fighters[int(entry["fighter"])]
		if not fighter.alive:
			continue
		var one: Dictionary = _prepare(state, fighter, entry, events)
		if not one.is_empty():
			prepared.append(one)
	for one: Dictionary in prepared:
		_apply_ops(state, one, events)
	_defeat_the_fallen(state, events)
	for one: Dictionary in prepared:
		_apply_footprint(state, one, events)


# --- Helpers ---


## The target cell of a plan; for a `self` ability it may be left out.
static func _plan_target(state: FightState, fighter: FighterState, plan: Dictionary) -> Vector2i:
	if plan.has("target_cell"):
		var pair: Array = plan["target_cell"]
		return Vector2i(int(pair[0]), int(pair[1]))
	return state.cell_of(fighter)


static func _is_hostile(ability: Dictionary) -> bool:
	if str(ability["affects"]) == "allies":
		return false
	for effect: Dictionary in ability["effects"]:
		if ["damage", "push", "pull"].has(str(effect["type"])):
			return true
	return false


static func _on_axis(from: Vector2i, to: Vector2i) -> bool:
	var dq: int = to.x - from.x
	var dr: int = to.y - from.y
	return dq == 0 or dr == 0 or dq + dr == 0


## LoS blockers (R5.1): walls and fighters, except the user's own cell, which it leaves or is the
## origin of the line anyway.
static func _blocker(state: FightState, fighter: FighterState) -> Callable:
	var own: Vector2i = state.cell_of(fighter) if fighter.cell >= 0 else Vector2i(-9999, -9999)
	return func(cell: Vector2i) -> bool: return cell != own and state.blocks_sight(cell)


static func _target_matches(state: FightState, fighter: FighterState, filter: String, user_cell: int, target_index: int) -> bool:
	var occupant: FighterState = state.fighter_at(target_index)
	match filter:
		"any_cell":
			return true
		"empty_cell":
			return occupant == null and state.walkable[target_index] == 1
		"any_fighter":
			return occupant != null
		"enemy":
			return occupant != null and occupant.side != fighter.side
		"ally":
			return occupant != null and occupant != fighter and occupant.side == fighter.side
		"self":
			return target_index == user_cell
	return false
