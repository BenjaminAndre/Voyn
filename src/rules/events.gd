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


## `cause`: "ability", "blight", "thrive", "collision", "crush" or "telegraph". `hp` is the HP left.
static func damaged(fighter: int, amount: int, cause: String, hp: int) -> Dictionary:
	return {"type": "damaged", "fighter": fighter, "amount": amount, "cause": cause, "hp": hp}


## `how`: "cleansed", "killed" (Monsters) or "downed" (Creatures).
static func defeated(fighter: int, how: String) -> Dictionary:
	return {"type": "defeated", "fighter": fighter, "how": how}


static func karma_changed(at: Vector2i, from: int, to: int) -> Dictionary:
	return {"type": "karma_changed", "cell": cell(at), "from": from, "to": to}


static func refilled(fighter: int, ap: int, mp: int) -> Dictionary:
	return {"type": "refilled", "fighter": fighter, "ap": ap, "mp": mp}


## `outcome`: "collapse", "bloom", "victory" or "defeat".
static func fight_ended(outcome: String) -> Dictionary:
	return {"type": "fight_ended", "outcome": outcome}
