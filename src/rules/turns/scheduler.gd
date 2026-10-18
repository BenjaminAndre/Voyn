class_name Scheduler
extends RefCounted
## The only module that knows the step structure (GDD R3, docs/architecture.md): the phase order,
## recharge cadence and checkpoints. If D3 changes, only this file and its tests move.
##
## Phases of one step (R3.6): lead_move, prep, dash, strike, trail_move, upkeep. Upkeep runs, in
## order: Land effects on occupants, status expiries, refills, the Land phase. Telegraphs slot in
## first with T10.

const PHASES: Array[String] = [
	Events.PHASE_LEAD_MOVE,
	Events.PHASE_PREP,
	Events.PHASE_DASH,
	Events.PHASE_STRIKE,
	Events.PHASE_TRAIL_MOVE,
	Events.PHASE_UPKEEP,
]


## Resolves the current step with every Side's plans (R3.6). `state` is not modified.
## Returns {"ok": bool, "state": FightState, "events": Array[Dictionary], "errors": Array[String]}.
## A malformed plan, a second plan for one fighter, or a fight that is not running is an error and
## changes nothing. Everything else that goes wrong (blocked moves, later: Fizzles) is an event.
static func resolve_step(state: FightState, plans: Array) -> Dictionary:
	var errors: Array[String] = []
	if state.status != FightState.STATUS_FIGHTING:
		errors.append("not_fighting")
		return _result(false, state, [], errors)
	for i: int in plans.size():
		for code: String in Plans.shape_errors(state, plans[i]):
			errors.append("plan %d: %s" % [i, code])
	if errors.is_empty():
		var seen: Array[int] = []
		for i: int in plans.size():
			var fighter_id: int = int((plans[i] as Dictionary)["fighter"])
			if seen.has(fighter_id):
				errors.append("plan %d: duplicate_plan" % i)
			seen.append(fighter_id)
	if not errors.is_empty():
		return _result(false, state, [], errors)

	var next: FightState = state.clone()
	var events: Array[Dictionary] = []
	events.append(Events.step_started())
	Events.stamp(events, 0, next.step, Events.PHASE_SETUP)
	for phase: String in PHASES:
		var from: int = events.size()
		events.append(Events.phase_started(phase))
		match phase:
			Events.PHASE_LEAD_MOVE:
				Movement.run_phase(next, phase_moves(next, plans, true, events), events)
			Events.PHASE_PREP, Events.PHASE_DASH, Events.PHASE_STRIKE:
				Abilities.run_phase(next, plans, phase, events)
			Events.PHASE_TRAIL_MOVE:
				Movement.run_phase(next, phase_moves(next, plans, false, events), events)
			Events.PHASE_UPKEEP:
				_upkeep(next, events)
		var ended: bool = check_outcome(next, events)
		Events.stamp(events, from, next.step, phase)
		if ended:
			return _result(true, next, events, errors)
	next.step += 1
	return _result(true, next, events, errors)


## The Land check (R11.6) and the elimination check (R3.8), run after every phase and sub-phase.
## Ends the fight, emits `fight_ended` and returns true if an outcome applies. The first match wins:
## Collapse, Bloom, Victory (no Monster left), Defeat (no Creature left). So Collapse beats a Victory
## won on the same blow, and when both Sides are gone at once it is a Victory.
static func check_outcome(state: FightState, events: Array[Dictionary]) -> bool:
	if state.status == FightState.STATUS_ENDED:
		return true
	var board: int = state.board_karma()
	if board <= state.collapse_at:
		_end(state, "collapse", events)
	elif board >= state.bloom_at:
		# Bloom: the Keepers' Side wins, and every remaining Monster is Cleansed (R3.8).
		for monster: FighterState in state.living(FighterState.SIDE_MONSTERS):
			Defeat.apply(state, monster, events, "cleansed")
		_end(state, "bloom", events)
	elif state.living_count(FighterState.SIDE_MONSTERS) == 0:
		_end(state, "victory", events)
	elif state.living_count(FighterState.SIDE_KEEPERS) == 0:
		_end(state, "defeat", events)
	else:
		return false
	return true


static func _end(state: FightState, outcome: String, events: Array[Dictionary]) -> void:
	state.status = FightState.STATUS_ENDED
	state.outcome = outcome
	events.append(Events.fight_ended(outcome))


## Upkeep (R3.6), in order: Land effects on occupants, due status expiries, due refills, the Land
## phase. The checks between the sub-steps stop it early if the fight ends.
static func _upkeep(state: FightState, events: Array[Dictionary]) -> void:
	_land_effects(state, events)
	Defeat.apply_fallen(state, events)
	if check_outcome(state, events):
		return
	Statuses.expire_due(state, events)
	_refill(state, events)
	_land_phase(state, events)


## R3.6 Blighted ground deals `blight_damage` (fixed; Blightborn ignore it) and Thriving ground
## heals `thrive_heal`, to everyone standing on it, in roster order.
static func _land_effects(state: FightState, events: Array[Dictionary]) -> void:
	for fighter: FighterState in state.fighters:
		if not fighter.on_board():
			continue
		var cell_karma: int = state.karma[fighter.cell]
		if cell_karma == Land.BLIGHTED and not fighter.has_trait("blightborn"):
			Damage.apply(state, fighter, int(state.rules["blight_damage"]), "blight", events)
		elif cell_karma == Land.THRIVING and fighter.hp < fighter.max_hp:
			Damage.heal(fighter, int(state.rules["thrive_heal"]), "thrive", events)


## R11.4 The Land phase, every `land_phase_every_steps` steps: `land_phase`, then one
## `karma_changed` per changed cell in cell order.
static func _land_phase(state: FightState, events: Array[Dictionary]) -> void:
	if state.step % int(state.rules["land_phase_every_steps"]) != 0:
		return
	var next: PackedInt32Array = Land.next_karma(state.grid, state.karma, int(state.rules["land_sum_threshold"]))
	events.append(Events.land_phase(Land.board_karma(next)))
	for index: int in state.grid.size():
		if next[index] != state.karma[index]:
			events.append(Events.karma_changed(state.grid.cell_at(index), state.karma[index], next[index]))
	state.karma = next


## R3.5 A fighter's pools refill to their max every `recharge_steps` steps, counted from fight
## start (steps 1-based), so a fighter with recharge 3 refills in Upkeep of steps 3, 6, 9...
## Unspent points are kept until then; a refill never overflows the max. An event is emitted
## only if a pool actually changed.
static func _refill(state: FightState, events: Array[Dictionary]) -> void:
	for fighter: FighterState in state.fighters:
		if not fighter.alive or state.step % fighter.recharge_steps != 0:
			continue
		if fighter.ap == fighter.max_ap and fighter.mp == fighter.max_mp:
			continue
		fighter.ap = fighter.max_ap
		fighter.mp = fighter.max_mp
		events.append(Events.refilled(fighter.id, fighter.ap, fighter.mp))


## The movement segments of the plans for Lead moves (`lead` true) or Trail moves, as
## {"fighter", "path"} entries for Movement.run_phase. A Trail move is cancelled, MP kept, if its
## fighter is no longer on the cell the path was planned from (displaced during the step, R3.6).
static func phase_moves(state: FightState, plans: Array, lead: bool, events: Array[Dictionary]) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for plan: Dictionary in plans:
		var path: Array[int] = Plans.path_indices(state, plan)
		if path.is_empty() or Plans.is_lead_move(plan) != lead:
			continue
		var fighter: FighterState = state.fighters[int(plan["fighter"])]
		if not fighter.alive:
			continue
		var from_cell: Array = plan["from_cell"]
		if fighter.cell != state.grid.index_of(Vector2i(int(from_cell[0]), int(from_cell[1]))):
			events.append(Events.move_blocked(fighter.id, state.cell_of(fighter), state.grid.cell_at(path[0]), "displaced"))
			continue
		moves.append({"fighter": fighter.id, "path": path})
	return moves


static func _result(ok: bool, state: FightState, events: Array[Dictionary], errors: Array[String]) -> Dictionary:
	return {"ok": ok, "state": state, "events": events, "errors": errors}
