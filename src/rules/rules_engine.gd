class_name RulesEngine
extends RefCounted
## The rules engine's public surface (docs/architecture.md). Every action takes a state and returns
## a result; the input state is never modified, so previews and the AI can call it on any copy.
##
## Action result: {"ok": bool, "state": FightState, "events": Array[Dictionary], "errors": Array[String]}.
## On failure `state` is the input state unchanged and `events` is empty.


## Builds a fight in its Placement phase. See FightState.create for the data shapes.
static func create(arena: Dictionary, roster: Array, rules: Dictionary, seed: int, defs: Dictionary = {}) -> Dictionary:
	return FightState.create(arena, roster, rules, seed, defs)


## R3.1 Puts a Creature on a free start cell. May be repeated to move it until `start_fight`.
static func place(state: FightState, fighter_id: int, cell: Vector2i) -> Dictionary:
	if state.status != FightState.STATUS_PLACEMENT:
		return _fail(state, "not_placing")
	if fighter_id < 0 or fighter_id >= state.fighters.size() or not state.fighters[fighter_id].is_creature():
		return _fail(state, "not_a_creature")
	var index: int = state.grid.index_of(cell)
	if index < 0 or not state.start_cells.has(index):
		return _fail(state, "not_a_start_cell")
	if state.occupant[index] >= 0 and state.occupant[index] != fighter_id:
		return _fail(state, "cell_occupied")
	var next: FightState = state.clone()
	next.set_position(next.fighters[fighter_id], index)
	return _ok(next, [Events.placed(fighter_id, cell)], state.step)


## R3.1 Ends placement; step 1 begins. Every Creature must be placed.
static func start_fight(state: FightState) -> Dictionary:
	if state.status != FightState.STATUS_PLACEMENT:
		return _fail(state, "not_placing")
	for fighter: FighterState in state.fighters:
		if fighter.is_creature() and fighter.cell < 0:
			return _fail(state, "creature_not_placed")
	var next: FightState = state.clone()
	next.status = FightState.STATUS_FIGHTING
	next.step = 1
	return _ok(next, [Events.fight_started()], state.step)


## R3.8 Ends the fight at once as a Defeat.
static func forfeit(state: FightState) -> Dictionary:
	if state.status == FightState.STATUS_ENDED:
		return _fail(state, "fight_over")
	var next: FightState = state.clone()
	var events: Array[Dictionary] = []
	next.status = FightState.STATUS_ENDED
	next.outcome = "defeat"
	events.append(Events.fight_ended("defeat"))
	return _ok(next, events, state.step)


## Plan-time validation (R3.4, R6.1): the plan against the board as it stands. Allies' plans never
## affect it. `player` >= 0 also checks that the fighter belongs to that player.
## Returns {"ok": bool, "errors": Array[String]}.
static func validate_plan(state: FightState, plan: Variant, player: int = -1) -> Dictionary:
	return Plans.validate(state, plan, player)


## Resolves one step with every Side's plans (R3.6). See Scheduler.resolve_step.
static func resolve_step(state: FightState, plans: Array) -> Dictionary:
	return Scheduler.resolve_step(state, plans)


## Query: the cells a fighter can reach this step. See Movement.reachable.
static func reachable(state: FightState, fighter_id: int) -> Dictionary:
	return Movement.reachable(state, state.fighters[fighter_id])


## Query: the cells (indices) a fighter could target with an ability from `from_cell`, on the board
## as it stands. See Abilities.targets.
static func targets(state: FightState, fighter_id: int, ability_id: String, from_cell: Vector2i) -> PackedInt32Array:
	return Abilities.targets(state, state.fighters[fighter_id], state.abilities[ability_id], state.grid.index_of(from_cell))


## Query (R11.5): what the next Land phase would change, from the board as it stands:
## {"changed": PackedInt32Array (cell indices in cell order), "next": PackedInt32Array (karma after),
## "board_karma_after": int, "steps_until": int (0 = in this step's Upkeep)}.
static func forecast(state: FightState) -> Dictionary:
	var every: int = int(state.rules["land_phase_every_steps"])
	var result: Dictionary = Land.forecast(state.grid, state.karma, int(state.rules["land_sum_threshold"]))
	result["steps_until"] = (every - state.step % every) % every
	return result


## Query: the cells (indices) a fighter could reach and hit this step. See Abilities.threat_zone.
static func threat_zone(state: FightState, fighter_id: int) -> PackedInt32Array:
	return Abilities.threat_zone(state, state.fighters[fighter_id])


## Setup events are stamped with the step the action was taken in and the phase "setup".
static func _ok(state: FightState, events: Array[Dictionary], step: int) -> Dictionary:
	var errors: Array[String] = []
	Events.stamp(events, 0, step, Events.PHASE_SETUP)
	return {"ok": true, "state": state, "events": events, "errors": errors}


static func _fail(state: FightState, code: String) -> Dictionary:
	var events: Array[Dictionary] = []
	var errors: Array[String] = [code]
	return {"ok": false, "state": state, "events": events, "errors": errors}
