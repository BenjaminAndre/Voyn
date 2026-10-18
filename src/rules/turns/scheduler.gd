class_name Scheduler
extends RefCounted
## The only module that knows the step structure (GDD R3, docs/architecture.md): the phase order,
## recharge cadence and checkpoints. If D3 changes, only this file and its tests move.
##
## Phases of one step (R3.6): lead_move, prep, dash, strike, trail_move, upkeep. Upkeep holds the
## status expiries and the recharge refills so far; Telegraphs, Land effects and the Land phase slot
## in around them in T8-T10.

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
				Statuses.expire_due(next, events)
				_refill(next, events)
		var ended: bool = check_outcome(next, events)
		Events.stamp(events, from, next.step, phase)
		if ended:
			return _result(true, next, events, errors)
	next.step += 1
	return _result(true, next, events, errors)


## Elimination check (R3.8), run after every phase. Ends the fight, emits `fight_ended` and returns
## true if a Side is out of fighters. Collapse and Bloom (the Land check) join in T8.
## When both Sides are gone at once the first match wins: Victory comes before Defeat.
static func check_outcome(state: FightState, events: Array[Dictionary]) -> bool:
	if state.status == FightState.STATUS_ENDED:
		return true
	if state.living_count(FighterState.SIDE_MONSTERS) == 0:
		_end(state, "victory", events)
		return true
	if state.living_count(FighterState.SIDE_KEEPERS) == 0:
		_end(state, "defeat", events)
		return true
	return false


static func _end(state: FightState, outcome: String, events: Array[Dictionary]) -> void:
	state.status = FightState.STATUS_ENDED
	state.outcome = outcome
	events.append(Events.fight_ended(outcome))


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
