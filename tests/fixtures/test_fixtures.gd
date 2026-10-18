class_name TestFixtures
extends RefCounted
## Test-only builders for arenas, fighters and fights (never real content; see docs/tasks.md M1).


## The real rules.json values, with optional overrides for a test.
static func rules(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = DataFiles.load_rules()
	var values: Dictionary = (result["rules"] as Dictionary).duplicate()
	values.merge(overrides, true)
	return values


## A valid ability definition (Defs.ability) built from defaults plus overrides.
static func ability(id: String, overrides: Dictionary = {}) -> Dictionary:
	var raw: Dictionary = {
		"id": id, "phase": "strike", "ap_cost": 3, "cooldown": 0, "target": "enemy",
		"min_range": 1, "max_range": 1, "needs_los": false, "line_only": false,
		"area": {"shape": "single"}, "affects": "enemies", "include_user": false,
		"effects": [{"type": "damage", "base": 18}], "karma": 0,
	}
	raw.merge(overrides, true)
	var result: Dictionary = Defs.ability(raw)
	assert(result["ok"], "fixture ability %s must be valid: %s" % [id, str(result["errors"])])
	return result["value"]


## Definitions used by the tests: ID -> ability, and statuses.
static func defs() -> Dictionary:
	var list: Array[Dictionary] = [
		ability("bash", {"karma": -1}),
		ability("lunge", {"max_range": 2, "line_only": true, "effects": [{"type": "damage", "base": 22}], "karma": -1}),
		ability("whirl", {"target": "self", "min_range": 0, "max_range": 0, "area": {"shape": "burst", "radius": 1}, "ap_cost": 4, "cooldown": 2, "effects": [{"type": "damage", "base": 16}], "karma": -1}),
		ability("shot", {"min_range": 2, "max_range": 6, "needs_los": true, "effects": [{"type": "damage", "base": 16}]}),
		ability("guard", {"phase": "prep", "target": "self", "min_range": 0, "max_range": 0, "area": {"shape": "burst", "radius": 1}, "affects": "allies", "include_user": true, "cooldown": 2, "effects": [{"type": "shield", "amount": 20, "duration": 2}], "karma": 1}),
		ability("seed", {"phase": "prep", "target": "any_cell", "min_range": 1, "max_range": 5, "needs_los": true, "area": {"shape": "burst", "radius": 1}, "affects": "all", "cooldown": 2, "effects": [], "karma": 1}),
		ability("pin", {"min_range": 2, "max_range": 4, "needs_los": true, "ap_cost": 2, "cooldown": 2, "effects": [{"type": "damage", "base": 6}, {"type": "apply_status", "status": "rooted", "duration": 1, "magnitude": 0}]}),
		ability("curse", {"effects": [{"type": "apply_status", "status": "vulnerable", "duration": 2, "magnitude": 50}]}),
		ability("mend", {"phase": "prep", "target": "ally", "affects": "allies", "min_range": 1, "max_range": 3, "effects": [{"type": "heal", "amount": 20}]}),
		ability("sweep", {"max_range": 2, "line_only": true, "area": {"shape": "line", "length": 3}, "effects": [{"type": "damage", "base": 10}]}),
		ability("smash", {"effects": [{"type": "damage", "base": 500}]}),
		ability("shove", {"phase": "dash", "ap_cost": 2, "cooldown": 1, "effects": [{"type": "push", "distance": 2}, {"type": "damage", "base": 6}]}),
		ability("gust", {"phase": "dash", "target": "self", "min_range": 0, "max_range": 0, "area": {"shape": "burst", "radius": 2}, "effects": [{"type": "push", "distance": 1}]}),
		ability("blast", {"phase": "dash", "target": "any_cell", "min_range": 0, "max_range": 5, "affects": "all", "area": {"shape": "burst", "radius": 1}, "effects": [{"type": "push", "distance": 1, "push_origin": "target"}]}),
		ability("hook", {"phase": "dash", "min_range": 1, "max_range": 5, "needs_los": true, "effects": [{"type": "pull", "distance": 3}]}),
		ability("yank", {"phase": "dash", "min_range": 1, "max_range": 5, "needs_los": true, "effects": [{"type": "pull", "distance": 6}]}),
		ability("long_push", {"phase": "dash", "effects": [{"type": "push", "distance": 4}]}),
	]
	var abilities: Dictionary = {}
	for entry: Dictionary in list:
		abilities[entry["id"]] = entry
	var statuses: Dictionary = {
		"rooted": {"id": "rooted", "effect": "rooted", "sign": 1},
		"vulnerable": {"id": "vulnerable", "effect": "damage_taken_pct", "sign": 1},
		"guarded": {"id": "guarded", "effect": "damage_taken_pct", "sign": -1},
	}
	return {"abilities": abilities, "statuses": statuses}


## A status instance as Statuses stores it, for putting straight onto a fighter in a test.
static func status(id: String, magnitude: int = 0, ends_step: int = 999, source: int = 0) -> Dictionary:
	var def: Dictionary = (defs()["statuses"] as Dictionary)[id]
	return {"name": id, "effect": def["effect"], "sign": def["sign"], "magnitude": magnitude, "ends_step": ends_step, "source": source}


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
static func create(roster: Array, arena_overrides: Dictionary = {}, seed: int = 1, rules_overrides: Dictionary = {}) -> FightState:
	var result: Dictionary = RulesEngine.create(arena(arena_overrides), roster, rules(rules_overrides), seed, defs())
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
static func running(roster: Array, creature_cells: Array[Vector2i], arena_overrides: Dictionary = {}, seed: int = 1, rules_overrides: Dictionary = {}) -> FightState:
	var overrides: Dictionary = arena_overrides.duplicate()
	if not overrides.has("creature_start_cells"):
		var starts: Array = []
		for cell: Vector2i in creature_cells:
			starts.append([cell.x, cell.y])
		overrides["creature_start_cells"] = starts
	return start(create(roster, overrides, seed, rules_overrides), creature_cells)


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
