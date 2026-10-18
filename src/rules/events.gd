class_name Events
extends RefCounted
## Event constructors. An event is a Dictionary with a `type`, a `step`, a `phase` and a fixed set
## of int/string fields (schema in docs/architecture.md). Cells are [q, r]; fighters are roster IDs.
## The client animates events and nothing else, so every state change the rules make emits one.
##
## Constructors build the type-specific fields only. The caller that owns the step and the phase
## (RulesEngine for setup actions, Scheduler for the phases of a step) calls `stamp` afterwards.

const PHASE_SETUP: String = "setup"
const PHASE_LEAD_MOVE: String = "lead_move"
const PHASE_PREP: String = "prep"
const PHASE_DASH: String = "dash"
const PHASE_STRIKE: String = "strike"
const PHASE_TRAIL_MOVE: String = "trail_move"
const PHASE_UPKEEP: String = "upkeep"


static func cell(c: Vector2i) -> Array:
	return [c.x, c.y]


## Adds `step` and `phase` to every event from index `from` to the end of the list.
static func stamp(events: Array[Dictionary], from: int, step: int, phase: String) -> void:
	for i: int in range(from, events.size()):
		events[i]["step"] = step
		events[i]["phase"] = phase


static func placed(fighter: int, at: Vector2i) -> Dictionary:
	return {"type": "placed", "fighter": fighter, "cell": cell(at)}


static func fight_started() -> Dictionary:
	return {"type": "fight_started"}


static func step_started() -> Dictionary:
	return {"type": "step_started"}


## `name` is one of the six phase names (PHASE_LEAD_MOVE .. PHASE_UPKEEP). The event's own `phase`
## stamp is the same value.
static func phase_started(name: String) -> Dictionary:
	return {"type": "phase_started", "name": name}


static func moved(fighter: int, from: Vector2i, to: Vector2i, mp_spent: int, mp_left: int) -> Dictionary:
	return {"type": "moved", "fighter": fighter, "from": cell(from), "to": cell(to), "mp_spent": mp_spent, "mp_left": mp_left}


## `at` is where the fighter stands, `wanted` the cell it could not enter. `reason`: "conflict",
## "swap", "cycle", "occupied", "no_mp", "rooted", "displaced", "not_walkable" or "stationary".
static func move_blocked(fighter: int, at: Vector2i, wanted: Vector2i, reason: String) -> Dictionary:
	return {"type": "move_blocked", "fighter": fighter, "at": cell(at), "wanted": cell(wanted), "reason": reason}


## `amount` is the damage dealt, `absorbed` the part a Shield took, `hp` the HP left.
## `cause`: "ability", "blight", "thrive", "collision", "crush" or "telegraph".
static func damaged(fighter: int, amount: int, absorbed: int, cause: String, hp: int) -> Dictionary:
	return {"type": "damaged", "fighter": fighter, "amount": amount, "absorbed": absorbed, "cause": cause, "hp": hp}


static func healed(fighter: int, amount: int, cause: String, hp: int) -> Dictionary:
	return {"type": "healed", "fighter": fighter, "amount": amount, "cause": cause, "hp": hp}


## The Shield a fighter holds now (0 when it is gone).
static func shield_changed(fighter: int, shield: int) -> Dictionary:
	return {"type": "shield_changed", "fighter": fighter, "shield": shield}


static func status_applied(fighter: int, status: String, magnitude: int, ends_step: int) -> Dictionary:
	return {"type": "status_applied", "fighter": fighter, "status": status, "magnitude": magnitude, "ends_step": ends_step}


static func status_ended(fighter: int, status: String) -> Dictionary:
	return {"type": "status_ended", "fighter": fighter, "status": status}


## An ability starts resolving (it was valid). `cell` is its target cell.
static func ability_used(fighter: int, ability: String, target: Vector2i) -> Dictionary:
	return {"type": "ability_used", "fighter": fighter, "ability": ability, "cell": cell(target)}


## An ability whose conditions no longer held at resolution (R3.7). `reason` is the failed
## check's code: "not_enough_ap", "out_of_range", "no_los", "not_on_axis", "bad_target" or "on_cooldown".
static func fizzled(fighter: int, ability: String, target: Vector2i, reason: String) -> Dictionary:
	return {"type": "fizzled", "fighter": fighter, "ability": ability, "cell": cell(target), "reason": reason}


## AP paid for an ability, fizzled or not. `ap` is what the fighter has left.
static func ap_spent(fighter: int, amount: int, ap: int) -> Dictionary:
	return {"type": "ap_spent", "fighter": fighter, "amount": amount, "ap": ap}


## A fighter was pushed or pulled from `from` to `to` (R7.5).
static func displaced(fighter: int, from: Vector2i, to: Vector2i) -> Dictionary:
	return {"type": "displaced", "fighter": fighter, "from": cell(from), "to": cell(to)}


## A push was cut short (R7.6): `cells` = cells not travelled, `damage` = the fixed collision damage
## (dealt right after as a `damaged` event with cause "collision").
static func collided(fighter: int, cells: int, damage: int) -> Dictionary:
	return {"type": "collided", "fighter": fighter, "cells": cells, "damage": damage}


## `how`: "cleansed", "killed" (Monsters) or "downed" (Creatures).
static func defeated(fighter: int, how: String) -> Dictionary:
	return {"type": "defeated", "fighter": fighter, "how": how}


static func karma_changed(at: Vector2i, from: int, to: int) -> Dictionary:
	return {"type": "karma_changed", "cell": cell(at), "from": from, "to": to}


## The Land phase ran; one `karma_changed` per changed cell follows, in cell order.
## `board_karma` is the sum after it.
static func land_phase(board_karma: int) -> Dictionary:
	return {"type": "land_phase", "board_karma": board_karma}


static func refilled(fighter: int, ap: int, mp: int) -> Dictionary:
	return {"type": "refilled", "fighter": fighter, "ap": ap, "mp": mp}


## `outcome`: "collapse", "bloom", "victory" or "defeat".
static func fight_ended(outcome: String) -> Dictionary:
	return {"type": "fight_ended", "outcome": outcome}
