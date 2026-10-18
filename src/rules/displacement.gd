class_name Displacement
extends RefCounted
## Push and pull (GDD R7.5-R7.7, R4.3, R4.4). Displacement is not movement: it costs no MP and
## ignores Engagement. Integers only.


## Moves `fighter` for one `displace` op: {"distance": int, "origin": cell index, "pull": bool}.
## Emits `displaced` (if it moved), then the blight `damaged` events for each Blighted cell it
## entered, then `collided` and the collision damage if a push was cut short. Does not defeat
## anyone: a fighter at 0 HP is defeated by the caller at the end of the ability (R7.4).
static func apply(state: FightState, fighter: FighterState, op: Dictionary, events: Array[Dictionary]) -> void:
	if not fighter.on_board() or fighter.hp <= 0:
		return
	# R7.7 Immovable and Stationary fighters are never displaced, and take no collision damage.
	if fighter.has_trait("immovable") or fighter.has_trait("stationary"):
		return
	var origin: Vector2i = state.grid.cell_at(int(op["origin"]))
	var start: Vector2i = state.cell_of(fighter)
	var pull: bool = bool(op["pull"])
	# R7.5 The direction is computed once, before the first cell. A fighter on the origin stays.
	var direction: int = Hex.pull_direction(origin, start) if pull else Hex.push_direction(origin, start)
	if direction < 0:
		return
	# R7.5 Heavy fighters move 1 cell less, to a minimum of 1.
	var distance: int = int(op["distance"])
	if fighter.has_trait("heavy"):
		distance = maxi(1, distance - 1)

	var travelled: int = 0
	var blocked: bool = false
	var current: Vector2i = start
	# Blight hits are kept apart so the client sees the slide (`displaced`) before the damage.
	var blight_events: Array[Dictionary] = []
	while travelled < distance:
		# A pull stops once the target is next to the origin.
		if pull and Hex.distance(current, origin) <= 1:
			break
		var next: Vector2i = current + Hex.DIRECTIONS[direction]
		var next_index: int = state.grid.index_of(next)
		# R7.6 A push stops when the next cell is non-walkable, occupied or outside the Arena.
		if next_index < 0 or state.walkable[next_index] == 0 or state.occupant[next_index] >= 0:
			blocked = true
			break
		state.set_position(fighter, next_index)
		current = next
		travelled += 1
		# R4.3 Entering a Blighted cell by Displacement hurts too (unless Blightborn).
		var blight: int = Movement.blight_on_enter(state, fighter, next_index)
		if blight > 0:
			Damage.apply(state, fighter, blight, "blight", blight_events)
			if fighter.hp <= 0:
				break  # defeated mid-push: it stops here, with no collision damage

	if travelled > 0:
		events.append(Events.displaced(fighter.id, start, current))
	events.append_array(blight_events)
	if fighter.hp <= 0:
		return
	# R7.6 Collision damage: fixed, per cell not travelled; a pull never deals it.
	if blocked and not pull:
		var missing: int = distance - travelled
		var damage: int = missing * int(state.rules["collision_damage_per_cell"])
		events.append(Events.collided(fighter.id, missing, damage))
		Damage.apply(state, fighter, damage, "collision", events)
