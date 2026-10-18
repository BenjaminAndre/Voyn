class_name Defeat
extends RefCounted
## What happens when a fighter reaches 0 HP (GDD R7.4, R11.3).
##   Monster on a Pure or Thriving cell -> Cleansed: it leaves peacefully, and Renewal gives its
##     cell and each adjacent cell +1 karma.
##   Monster elsewhere -> Killed: its cell becomes Blighted.
##   Creature -> Downed: out for this fight, and its cell becomes Blighted too.
## The fighter leaves the board. The elimination check and Land check belong to the scheduler.


## Applies the defeat to `state` in place and appends events. Does nothing if already defeated.
static func apply(state: FightState, fighter: FighterState, events: Array[Dictionary]) -> void:
	if not fighter.alive:
		return
	var cell_index: int = fighter.cell
	var cell_karma: int = state.karma[cell_index]
	fighter.hp = 0
	fighter.alive = false
	state.remove_from_board(fighter)

	var how: String
	if fighter.is_creature():
		how = "downed"
	elif cell_karma >= Land.PURE:
		how = "cleansed"
	else:
		how = "killed"
	events.append(Events.defeated(fighter.id, how))

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
