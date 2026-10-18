class_name Defeat
extends RefCounted
## What happens when a fighter reaches 0 HP (GDD R7.4, R11.3).
##   Monster on a Pure or Thriving cell -> Cleansed: it leaves peacefully, and Renewal gives its
##     cell and each adjacent cell +1 karma.
##   Monster elsewhere -> Killed: its cell becomes Blighted.
##   Creature -> Downed: out for this fight, and its cell becomes Blighted too.
## The fighter leaves the board, and its statuses and the statuses it applied end (R7.4).
## The elimination check and Land check belong to the scheduler.


## R7.4, R11.3 Everyone at 0 HP is defeated now, in roster order.
static func apply_fallen(state: FightState, events: Array[Dictionary]) -> void:
	for fighter: FighterState in state.fighters:
		if fighter.alive and fighter.on_board() and fighter.hp <= 0:
			apply(state, fighter, events)


## Applies the defeat to `state` in place and appends events. Does nothing if already defeated.
## `forced_how` ("cleansed") skips the karma check: Bloom cleanses every remaining Monster (R3.8).
static func apply(state: FightState, fighter: FighterState, events: Array[Dictionary], forced_how: String = "") -> void:
	if not fighter.alive:
		return
	var cell_index: int = fighter.cell
	var cell_karma: int = state.karma[cell_index]
	fighter.hp = 0
	fighter.alive = false
	state.remove_from_board(fighter)

	var how: String
	if forced_how != "":
		how = forced_how
	elif fighter.is_creature():
		how = "downed"
	elif cell_karma >= Land.PURE:
		how = "cleansed"
	else:
		how = "killed"
	events.append(Events.defeated(fighter.id, how))
	Statuses.clear_for_defeat(state, fighter, events)

	if how == "cleansed":
		state.cleansed_count += 1
		var renewed: Array[int] = [cell_index]
		for n: int in state.grid.neighbor_indices[cell_index]:
			renewed.append(n)
		renewed.sort()  # cell order: indices follow cell order
		for index: int in renewed:
			_set_karma(state, index, mini(state.karma[index] + 1, Land.THRIVING), events)
	else:
		_set_karma(state, cell_index, Land.BLIGHTED, events)


static func _set_karma(state: FightState, index: int, value: int, events: Array[Dictionary]) -> void:
	var old: int = state.karma[index]
	if old == value:
		return
	state.karma[index] = value
	events.append(Events.karma_changed(state.grid.cell_at(index), old, value))
