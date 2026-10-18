class_name Movement
extends RefCounted
## Movement rules (GDD R4): costs, Engagement, blight on entry, the default path, and the
## simultaneous lockstep resolution of a move phase (R4.8, algorithm in docs/architecture.md).
## Integers only. Every iteration runs in roster order (ascending fighter ID), never in
## Dictionary order.


## R4.2 Number of living enemies adjacent to a cell, from the point of view of `side`.
static func enemies_adjacent(state: FightState, cell_index: int, side: int) -> int:
	var count: int = 0
	for n: int in state.grid.neighbor_indices[cell_index]:
		var occupant_id: int = state.occupant[n]
		if occupant_id >= 0 and state.fighters[occupant_id].side != side:
			count += 1
	return count


## R4.1, R4.2 MP to leave `from_index` by one move: 1, plus `engagement_mp_per_enemy` per adjacent
## enemy unless Nimble. Computed against the positions in `state` as it stands.
static func step_cost(state: FightState, fighter: FighterState, from_index: int) -> int:
	var cost: int = 1
	if not fighter.has_trait("nimble"):
		cost += enemies_adjacent(state, from_index, fighter.side) * int(state.rules["engagement_mp_per_enemy"])
	return cost


## R4.3 Fixed blight damage for entering a Blighted cell; Blightborn ignore it.
static func blight_on_enter(state: FightState, fighter: FighterState, cell_index: int) -> int:
	if state.karma[cell_index] == Land.BLIGHTED and not fighter.has_trait("blightborn"):
		return int(state.rules["blight_damage"])
	return 0


## MP a path would cost against the current positions. `path` is a list of cell indices that does
## not include the fighter's own cell.
static func path_cost(state: FightState, fighter: FighterState, path: Array[int]) -> int:
	var total: int = 0
	var from_index: int = fighter.cell
	for to_index: int in path:
		total += step_cost(state, fighter, from_index)
		from_index = to_index
	return total


## Query: every cell a fighter could reach this step with its current MP, from the board as it
## stands (other fighters block). Returns {cell_index: {"mp": int, "damage": int, "path": Array[Vector2i]}}
## including the fighter's own cell (cost 0, empty path). The path is the default path (R4.6):
## least blight damage, then least MP, then the lowest sequence of direction indices.
static func reachable(state: FightState, fighter: FighterState) -> Dictionary:
	var result: Dictionary = {}
	if not fighter.on_board():
		return result
	var size: int = state.grid.size()
	var start: int = fighter.cell
	var best_damage: PackedInt32Array = PackedInt32Array()
	var best_mp: PackedInt32Array = PackedInt32Array()
	var reached: PackedInt32Array = PackedInt32Array()
	var visited: PackedInt32Array = PackedInt32Array()
	var best_dirs: Array[PackedInt32Array] = []
	best_damage.resize(size)
	best_mp.resize(size)
	reached.resize(size)
	visited.resize(size)
	for i: int in size:
		best_dirs.append(PackedInt32Array())
	reached[start] = 1

	var can_move: bool = not fighter.has_status("rooted") and not fighter.has_trait("stationary")
	while can_move:
		var u: int = -1
		for i: int in size:
			if reached[i] == 1 and visited[i] == 0:
				if u < 0 or _label_less(best_damage[i], best_mp[i], best_dirs[i], best_damage[u], best_mp[u], best_dirs[u]):
					u = i
		if u < 0:
			break
		visited[u] = 1
		var step: int = step_cost(state, fighter, u)
		var u_cell: Vector2i = state.grid.cell_at(u)
		for k: int in 6:
			var n: int = state.grid.index_of(u_cell + Hex.DIRECTIONS[k])
			if n < 0 or state.walkable[n] == 0 or state.occupant[n] >= 0 or visited[n] == 1:
				continue
			var new_mp: int = best_mp[u] + step
			if new_mp > fighter.mp:
				continue
			var new_damage: int = best_damage[u] + blight_on_enter(state, fighter, n)
			var new_dirs: PackedInt32Array = best_dirs[u].duplicate()
			new_dirs.append(k)
			if reached[n] == 0 or _label_less(new_damage, new_mp, new_dirs, best_damage[n], best_mp[n], best_dirs[n]):
				reached[n] = 1
				best_damage[n] = new_damage
				best_mp[n] = new_mp
				best_dirs[n] = new_dirs

	for i: int in size:
		if reached[i] == 0:
			continue
		var path: Array[Vector2i] = []
		var cursor: Vector2i = state.grid.cell_at(start)
		for k: int in best_dirs[i]:
			cursor = cursor + Hex.DIRECTIONS[k]
			path.append(cursor)
		result[i] = {"mp": best_mp[i], "damage": best_damage[i], "path": path}
	return result


## True if label A (damage, mp, direction sequence) is strictly better than label B.
static func _label_less(a_damage: int, a_mp: int, a_dirs: PackedInt32Array, b_damage: int, b_mp: int, b_dirs: PackedInt32Array) -> bool:
	if a_damage != b_damage:
		return a_damage < b_damage
	if a_mp != b_mp:
		return a_mp < b_mp
	var shared: int = mini(a_dirs.size(), b_dirs.size())
	for i: int in shared:
		if a_dirs[i] != b_dirs[i]:
			return a_dirs[i] < b_dirs[i]
	return a_dirs.size() < b_dirs.size()


## Resolves one move phase (Lead or Trail moves). `moves` is a list of
## {"fighter": int, "path": Array[int]} (path = cell indices, own cell excluded).
## Every mover advances one cell per sub-tick, in lockstep, until it has stopped or finished.
static func run_phase(state: FightState, moves: Array[Dictionary], events: Array[Dictionary]) -> void:
	var paths: Dictionary = {}
	var progress: Dictionary = {}
	var active: Array[int] = []
	for move: Dictionary in moves:
		var id: int = int(move["fighter"])
		paths[id] = move["path"]
		progress[id] = 0
		active.append(id)
	active.sort()
	while not active.is_empty():
		active = _sub_tick(state, active, paths, progress, events)


## One sub-tick (R4.8). Returns the movers that entered a cell and still have path left.
static func _sub_tick(state: FightState, active: Array[int], paths: Dictionary, progress: Dictionary, events: Array[Dictionary]) -> Array[int]:
	var want: Dictionary = {}
	var cost: Dictionary = {}
	var stops: Dictionary = {}
	var moving: Array[int] = []

	# 1. Wanted cell, and whether the mover can start at all. Costs use positions at the start of
	#    this sub-tick, since `state` is not touched until step 4.
	var alive_active: Array[int] = []
	for id: int in active:
		var fighter: FighterState = state.fighters[id]
		if not fighter.alive:
			continue
		alive_active.append(id)
		var path: Array = paths[id]
		var next: int = int(path[int(progress[id])])
		want[id] = next
		var reason: String = ""
		if fighter.has_status("rooted"):
			reason = "rooted"
		elif fighter.has_trait("stationary"):
			reason = "stationary"
		elif state.walkable[next] == 0:
			reason = "not_walkable"
		else:
			var step: int = step_cost(state, fighter, fighter.cell)
			if fighter.mp < step:
				reason = "no_mp"
			else:
				cost[id] = step
		if reason == "":
			moving.append(id)
		else:
			stops[id] = reason

	# 2. Fixed point. A cell is free if nobody stays on it; a mover leaving it frees it. Remove
	#    movers until nothing changes: blocked by a fighter that stays, beaten in a conflict, or
	#    part of a swap or longer cycle.
	var changed: bool = true
	while changed:
		changed = false

		var kept: Array[int] = []
		for id: int in moving:
			var occ: int = state.occupant[int(want[id])]
			if occ >= 0 and occ != id and not moving.has(occ):
				stops[id] = "occupied"
				changed = true
			else:
				kept.append(id)
		moving = kept

		var winner_of: Dictionary = {}
		for id: int in moving:
			var target: int = int(want[id])
			if not winner_of.has(target) or _beats(state, paths, progress, id, int(winner_of[target])):
				winner_of[target] = id
		kept = []
		for id: int in moving:
			if int(winner_of[int(want[id])]) == id:
				kept.append(id)
			else:
				stops[id] = "conflict"
				changed = true
		moving = kept

		var cycles: Array[Array] = _cycles(state, moving, want)
		if not cycles.is_empty():
			var in_cycle: Array[int] = []
			for members: Array in cycles:
				for id: int in members:
					in_cycle.append(id)
					stops[id] = "swap" if members.size() == 2 else "cycle"
			kept = []
			for id: int in moving:
				if not in_cycle.has(id):
					kept.append(id)
			moving = kept
			changed = true

	# 3. Report the movers that stopped.
	for id: int in alive_active:
		if stops.has(id):
			events.append(Events.move_blocked(id, state.grid.cell_at(state.fighters[id].cell), state.grid.cell_at(int(want[id])), str(stops[id])))

	# 4. Everyone who still moves enters its cell at once, and pays.
	var origin: Dictionary = {}
	for id: int in moving:
		origin[id] = state.fighters[id].cell
	for id: int in moving:
		state.occupant[int(origin[id])] = -1
	for id: int in moving:
		var fighter: FighterState = state.fighters[id]
		fighter.cell = int(want[id])
		state.occupant[fighter.cell] = id
		fighter.mp -= int(cost[id])
	for id: int in moving:
		var fighter: FighterState = state.fighters[id]
		events.append(Events.moved(id, state.grid.cell_at(int(origin[id])), state.grid.cell_at(fighter.cell), int(cost[id]), fighter.mp))

	# 5. Blight on entry (R4.3): all damage is computed first, then applied, then defeats (R4.7).
	var blight: Dictionary = {}
	for id: int in moving:
		var damage: int = blight_on_enter(state, state.fighters[id], state.fighters[id].cell)
		if damage > 0:
			blight[id] = damage
	for id: int in moving:
		if blight.has(id):
			var fighter: FighterState = state.fighters[id]
			fighter.hp = maxi(0, fighter.hp - int(blight[id]))
			events.append(Events.damaged(id, int(blight[id]), "blight", fighter.hp))
	for id: int in moving:
		if blight.has(id) and state.fighters[id].hp <= 0:
			Defeat.apply(state, state.fighters[id], events)

	var next_active: Array[int] = []
	for id: int in moving:
		progress[id] = int(progress[id]) + 1
		if state.fighters[id].alive and int(progress[id]) < (paths[id] as Array).size():
			next_active.append(id)
	return next_active


## R4.8 Conflict priority: shorter remaining path, then Creatures before Monsters, then roster order.
static func _beats(state: FightState, paths: Dictionary, progress: Dictionary, a: int, b: int) -> bool:
	var remaining_a: int = (paths[a] as Array).size() - int(progress[a])
	var remaining_b: int = (paths[b] as Array).size() - int(progress[b])
	if remaining_a != remaining_b:
		return remaining_a < remaining_b
	var a_creature: bool = state.fighters[a].is_creature()
	var b_creature: bool = state.fighters[b].is_creature()
	if a_creature != b_creature:
		return a_creature
	return a < b


## The swaps (2 movers) and longer cycles in the set of movers: each wants the cell of the next,
## around and around. A mover whose wanted cell is held by another mover points to it; chains that
## end at a free cell are not cycles. Each cycle is a list of fighter IDs; cycles are returned in
## order of their lowest ID.
static func _cycles(state: FightState, moving: Array[int], want: Dictionary) -> Array[Array]:
	var cycles: Array[Array] = []
	var covered: Array[int] = []
	for start: int in moving:
		if covered.has(start):
			continue
		var trail: Array[int] = []
		var cursor: int = start
		while cursor >= 0 and not trail.has(cursor):
			trail.append(cursor)
			var occ: int = state.occupant[int(want[cursor])]
			cursor = occ if (occ >= 0 and moving.has(occ)) else -1
		if cursor >= 0:
			var members: Array[int] = []
			for i: int in range(trail.find(cursor), trail.size()):
				members.append(trail[i])
			members.sort()
			for id: int in members:
				covered.append(id)
			cycles.append(members)
	return cycles
