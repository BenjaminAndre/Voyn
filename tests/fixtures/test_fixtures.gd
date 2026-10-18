class_name TestFixtures
extends RefCounted
## Test-only builders for arenas, fighters and fights (never real content; see docs/tasks.md M1).


static func rules() -> Dictionary:
	var result: Dictionary = DataFiles.load_rules()
	return result["rules"]


## A creature entry for the roster. Overrides replace any default.
static func creature(overrides: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = {
		"side": "creature", "player": 0, "name": "creature", "max_hp": 100, "max_ap": 6, "max_mp": 3,
		"power": 0, "recharge_steps": 1, "traits": [],
	}
	entry.merge(overrides, true)
	return entry


## A Monster entry. Monsters are Blightborn by default.
static func monster(spawn: Array, overrides: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = {
		"side": "monster", "name": "monster", "max_hp": 100, "max_ap": 6, "max_mp": 3,
		"power": 0, "recharge_steps": 1, "traits": ["blightborn"], "cell": spawn,
	}
	entry.merge(overrides, true)
	return entry


## A hexagonal arena. Defaults: radius 4, no obstacles, all Neutral, start cells on the left.
static func arena(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"radius": 4, "obstacles": [], "karma": [],
		"creature_start_cells": [[-4, 0], [-3, 0], [-2, 0], [-4, 1], [-3, 1], [-4, 2], [-3, -1], [-4, 3]],
		"collapse_at": -100, "bloom_at": 100,
	}
	result.merge(overrides, true)
	return result


## Creates a fight in placement. Fails the calling test if the data is invalid.
static func create(roster: Array, arena_overrides: Dictionary = {}, seed: int = 1) -> FightState:
	var result: Dictionary = RulesEngine.create(arena(arena_overrides), roster, rules(), seed)
	assert(result["ok"], "fixture roster must be valid: %s" % str(result["errors"]))
	return result["state"]


## Places every Creature on the given cells (in roster order) and starts the fight.
static func start(state: FightState, cells: Array[Vector2i]) -> FightState:
	var current: FightState = state
	var next_cell: int = 0
	for fighter: FighterState in state.fighters:
		if fighter.is_creature():
			var placed: Dictionary = RulesEngine.place(current, fighter.id, cells[next_cell])
			assert(placed["ok"], "placement must succeed: %s" % str(placed["errors"]))
			current = placed["state"]
			next_cell += 1
	var started: Dictionary = RulesEngine.start_fight(current)
	assert(started["ok"], "start must succeed: %s" % str(started["errors"]))
	return started["state"]


## Shortcut: a running fight with Creatures at `creature_cells` and Monsters as given in the roster.
## Unless `arena_overrides` sets its own start cells, the Creatures' cells become the start cells.
static func running(roster: Array, creature_cells: Array[Vector2i], arena_overrides: Dictionary = {}, seed: int = 1) -> FightState:
	var overrides: Dictionary = arena_overrides.duplicate()
	if not overrides.has("creature_start_cells"):
		var starts: Array = []
		for cell: Vector2i in creature_cells:
			starts.append([cell.x, cell.y])
		overrides["creature_start_cells"] = starts
	return start(create(roster, overrides, seed), creature_cells)


## A move-only plan. `from_cell` is filled in by `with_from` / `resolve` from the state.
static func move(fighter: int, path: Array, order: String = "move_first") -> Dictionary:
	return {"fighter": fighter, "move_path": path, "order": order}


## Copy of a plan with `from_cell` set to where its fighter stands now, unless it already has one.
static func with_from(state: FightState, plan: Dictionary) -> Dictionary:
	var filled: Dictionary = plan.duplicate(true)
	var id: Variant = filled.get("fighter", null)
	if not filled.has("from_cell") and typeof(id) == TYPE_INT and int(id) >= 0 and int(id) < state.fighters.size():
		var fighter: FighterState = state.fighters[int(id)]
		if fighter.on_board():
			var cell: Vector2i = state.cell_of(fighter)
			filled["from_cell"] = [cell.x, cell.y]
	return filled


## RulesEngine.resolve_step with `from_cell` filled in on every plan that lacks it.
static func resolve(state: FightState, plans: Array) -> Dictionary:
	var filled: Array = []
	for plan: Variant in plans:
		filled.append(with_from(state, plan) if plan is Dictionary else plan)
	return RulesEngine.resolve_step(state, filled)


static func event_types(events: Array) -> Array[String]:
	var types: Array[String] = []
	for event: Dictionary in events:
		types.append(str(event["type"]))
	return types


## Events of one type, in order.
static func of_type(events: Array, type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in events:
		if event["type"] == type:
			found.append(event)
	return found
