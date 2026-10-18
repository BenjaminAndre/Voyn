class_name Statuses
extends RefCounted
## Statuses on fighters (GDD R6.6, R7.3). An instance is
## {"name": id, "effect": String, "sign": int, "magnitude": int, "ends_step": int, "source": int}.
## `effect` is one of Defs.STATUS_EFFECTS. Shield is built in: `magnitude` is the amount it still
## holds. A status with duration N ends in the Upkeep of step (applied step + N).

const SHIELD: String = "shield"


static func index_of(fighter: FighterState, status_id: String) -> int:
	for i: int in fighter.statuses.size():
		if fighter.statuses[i]["name"] == status_id:
			return i
	return -1


## Applies a status from its definition, replacing any status of the same name (newest wins).
static func apply(state: FightState, fighter: FighterState, status_id: String, magnitude: int, duration: int, source: int, events: Array[Dictionary]) -> void:
	var def: Dictionary = state.status_defs[status_id]
	_put(state, fighter, status_id, str(def["effect"]), int(def["sign"]), magnitude, duration, source, events)


## Applies or replaces a Shield holding `amount` (R7.3). Shield never stacks.
static func apply_shield(state: FightState, fighter: FighterState, amount: int, duration: int, source: int, events: Array[Dictionary]) -> void:
	_put(state, fighter, SHIELD, SHIELD, 1, amount, duration, source, events)
	events.append(Events.shield_changed(fighter.id, amount))


static func shield_amount(fighter: FighterState) -> int:
	var i: int = index_of(fighter, SHIELD)
	return 0 if i < 0 else int(fighter.statuses[i]["magnitude"])


## Sum of the signed magnitudes of every status of an effect (damage_taken_pct, damage_dealt_pct).
static func total(fighter: FighterState, effect: String) -> int:
	var sum: int = 0
	for status: Dictionary in fighter.statuses:
		if status["effect"] == effect:
			sum += int(status["sign"]) * int(status["magnitude"])
	return sum


## Removes a status and emits `status_ended`. No-op if absent.
static func remove(fighter: FighterState, status_id: String, events: Array[Dictionary]) -> void:
	var i: int = index_of(fighter, status_id)
	if i < 0:
		return
	fighter.statuses.remove_at(i)
	events.append(Events.status_ended(fighter.id, status_id))


## Upkeep (R3.6): ends every status due this step, in roster order then application order.
static func expire_due(state: FightState, events: Array[Dictionary]) -> void:
	for fighter: FighterState in state.fighters:
		if not fighter.alive:
			continue
		var kept: Array[Dictionary] = []
		for status: Dictionary in fighter.statuses:
			if int(status["ends_step"]) <= state.step:
				events.append(Events.status_ended(fighter.id, str(status["name"])))
			else:
				kept.append(status)
		fighter.statuses = kept


## R7.4 A defeated fighter loses its statuses, and the statuses it applied to others end too.
static func clear_for_defeat(state: FightState, defeated: FighterState, events: Array[Dictionary]) -> void:
	defeated.statuses = []
	for fighter: FighterState in state.fighters:
		if not fighter.alive:
			continue
		var kept: Array[Dictionary] = []
		for status: Dictionary in fighter.statuses:
			if int(status["source"]) == defeated.id:
				events.append(Events.status_ended(fighter.id, str(status["name"])))
			else:
				kept.append(status)
		fighter.statuses = kept


static func _put(state: FightState, fighter: FighterState, status_id: String, effect: String, sign: int, magnitude: int, duration: int, source: int, events: Array[Dictionary]) -> void:
	var instance: Dictionary = {
		"name": status_id, "effect": effect, "sign": sign, "magnitude": magnitude,
		"ends_step": state.step + duration, "source": source,
	}
	var i: int = index_of(fighter, status_id)
	if i >= 0:
		fighter.statuses[i] = instance
	else:
		fighter.statuses.append(instance)
	events.append(Events.status_applied(fighter.id, status_id, magnitude, int(instance["ends_step"])))
