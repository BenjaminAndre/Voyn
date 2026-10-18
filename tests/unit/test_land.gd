extends GutTest
## T4b: the Land phase automaton and forecast (GDD R11.4, R11.5, R11.6), with land_sum_threshold = 5.

const T: int = 5


func _grid(radius: int = 6) -> HexGrid:
	return HexGrid.hexagon(radius)


func _filled(grid: HexGrid, value: int) -> PackedInt32Array:
	var karma: PackedInt32Array = PackedInt32Array()
	karma.resize(grid.size())
	karma.fill(value)
	return karma


func _put(grid: HexGrid, karma: PackedInt32Array, cell: Vector2i, value: int) -> void:
	karma[grid.index_of(cell)] = value


func _at(grid: HexGrid, karma: PackedInt32Array, cell: Vector2i) -> int:
	return karma[grid.index_of(cell)]


func _run(grid: HexGrid, start: PackedInt32Array, phases: int) -> PackedInt32Array:
	var karma: PackedInt32Array = start
	for i: int in phases:
		karma = Land.next_karma(grid, karma, T)
	return karma


func _negated(karma: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = karma.duplicate()
	for i: int in result.size():
		result[i] = -result[i]
	return result


func test_R11_4_all_neutral_stays_neutral() -> void:
	var grid: HexGrid = _grid()
	var karma: PackedInt32Array = _filled(grid, 0)
	assert_eq(_run(grid, karma, 20), karma)
	assert_eq(Land.forecast(grid, karma, T)["changed"].size(), 0)


func test_R11_4_blight_pair_stays_bounded() -> void:
	var grid: HexGrid = _grid()
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, Vector2i(0, 0), Land.BLIGHTED)
	_put(grid, karma, Vector2i(1, 0), Land.BLIGHTED)
	for i: int in 20:
		karma = Land.next_karma(grid, karma, T)
		assert_eq(Land.board_karma(karma), -4, "phase %d" % (i + 1))


func test_R11_4_blight_triangle_stays_bounded() -> void:
	var grid: HexGrid = _grid()
	var start: PackedInt32Array = _filled(grid, 0)
	_put(grid, start, Vector2i(0, 0), Land.BLIGHTED)
	_put(grid, start, Vector2i(1, 0), Land.BLIGHTED)
	_put(grid, start, Vector2i(0, 1), Land.BLIGHTED)
	assert_eq(_run(grid, start, 20), start)


func test_R11_4_hexagonal_blob_stays_bounded() -> void:
	var grid: HexGrid = _grid()
	var start: PackedInt32Array = _filled(grid, 0)
	for cell: Vector2i in Hex.disk(Vector2i.ZERO, 1):
		_put(grid, start, cell, Land.BLIGHTED)
	assert_eq(_run(grid, start, 20), start)
	var big: PackedInt32Array = _filled(grid, 0)
	for cell: Vector2i in Hex.disk(Vector2i.ZERO, 3):
		_put(grid, big, cell, Land.BLIGHTED)
	assert_eq(_run(grid, big, 20), big, "a wider blob also stops at its edge")


func test_R11_4_a_blight_ring_fills_its_own_gap_then_stops() -> void:
	var grid: HexGrid = _grid()
	var start: PackedInt32Array = _filled(grid, 0)
	for cell: Vector2i in Hex.ring(Vector2i.ZERO, 1):
		_put(grid, start, cell, Land.BLIGHTED)
	var after_one: PackedInt32Array = Land.next_karma(grid, start, T)
	assert_eq(_at(grid, after_one, Vector2i.ZERO), Land.CORRUPTED, "gap loses 1 per phase")
	var after_two: PackedInt32Array = Land.next_karma(grid, after_one, T)
	assert_eq(_at(grid, after_two, Vector2i.ZERO), Land.BLIGHTED)
	assert_eq(Land.board_karma(after_two), -14, "7 blighted cells")
	assert_eq(_run(grid, after_two, 20), after_two, "then it stops")


func test_R11_4_corrupted_field_runs_away() -> void:
	var grid: HexGrid = _grid(4)
	var karma: PackedInt32Array = _filled(grid, Land.CORRUPTED)
	_put(grid, karma, Vector2i.ZERO, Land.BLIGHTED)
	var last: int = Land.board_karma(karma)
	for i: int in 20:
		karma = Land.next_karma(grid, karma, T)
		var now: int = Land.board_karma(karma)
		assert_lte(now, last, "never recovers")
		last = now
	assert_eq(Land.board_karma(karma), -2 * grid.size(), "the whole board ends up Blighted")


func test_R11_4_the_same_seed_on_neutral_ground_does_not_run_away() -> void:
	var grid: HexGrid = _grid(4)
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, Vector2i.ZERO, Land.BLIGHTED)
	assert_eq(Land.board_karma(_run(grid, karma, 20)), -2)


func test_R11_4_purity_runs_away_on_pure_ground() -> void:
	var grid: HexGrid = _grid(4)
	var karma: PackedInt32Array = _filled(grid, Land.PURE)
	_put(grid, karma, Vector2i.ZERO, Land.THRIVING)
	assert_eq(Land.board_karma(_run(grid, karma, 20)), 2 * grid.size())


func test_R11_4_purity_mirrors_corruption_on_fixed_patterns() -> void:
	var grid: HexGrid = _grid(4)
	var karma: PackedInt32Array = _filled(grid, Land.CORRUPTED)
	_put(grid, karma, Vector2i.ZERO, Land.BLIGHTED)
	_put(grid, karma, Vector2i(2, -1), Land.THRIVING)
	var mirrored_next: PackedInt32Array = Land.next_karma(grid, _negated(karma), T)
	assert_eq(mirrored_next, _negated(Land.next_karma(grid, karma, T)))


func test_R11_4_purity_mirrors_corruption_on_random_boards() -> void:
	var grid: HexGrid = _grid(5)
	var prng: Prng = Prng.create(31337)
	for round: int in 20:
		var karma: PackedInt32Array = PackedInt32Array()
		for i: int in grid.size():
			karma.append(prng.next_below(5) - 2)
		var forward: PackedInt32Array = karma
		var mirror: PackedInt32Array = _negated(karma)
		for phase: int in 5:
			forward = Land.next_karma(grid, forward, T)
			mirror = Land.next_karma(grid, mirror, T)
			assert_eq(mirror, _negated(forward), "round %d phase %d" % [round, phase])


func test_R11_4_contested_cell_does_not_change() -> void:
	# A Corrupted cell with a Blighted neighbor (corruption) and neighbors summing >= 5 (purity).
	var grid: HexGrid = _grid(3)
	var center: Vector2i = Vector2i.ZERO
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, center, Land.CORRUPTED)
	for n: Vector2i in Hex.neighbors(center):
		_put(grid, karma, n, Land.THRIVING)
	_put(grid, karma, Hex.neighbor(center, 0), Land.BLIGHTED)
	assert_eq(_at(grid, Land.next_karma(grid, karma, T), center), Land.CORRUPTED, "contested: holds")
	# Without the Blighted neighbor only purity applies, so the cell gains 1.
	_put(grid, karma, Hex.neighbor(center, 0), Land.THRIVING)
	assert_eq(_at(grid, Land.next_karma(grid, karma, T), center), Land.NEUTRAL)


func test_R11_4_contested_pure_cell_with_thriving_neighbor_holds() -> void:
	# A Pure cell with a Thriving neighbor (purity) and neighbors summing <= -5 (corruption).
	var grid: HexGrid = _grid(3)
	var center: Vector2i = Vector2i.ZERO
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, center, Land.PURE)
	for n: Vector2i in Hex.neighbors(center):
		_put(grid, karma, n, Land.BLIGHTED)
	_put(grid, karma, Hex.neighbor(center, 3), Land.THRIVING)
	assert_eq(_at(grid, Land.next_karma(grid, karma, T), center), Land.PURE)


func test_R11_4_edge_cells_count_missing_neighbors_as_zero() -> void:
	var grid: HexGrid = _grid(3)
	var corner: Vector2i = Vector2i(3, 0)
	var neighbor_cells: Array[Vector2i] = []
	for n: Vector2i in Hex.neighbors(corner):
		if grid.has_cell(n):
			neighbor_cells.append(n)
	assert_eq(neighbor_cells.size(), 3, "a corner has 3 neighbors")
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, neighbor_cells[0], Land.BLIGHTED)
	_put(grid, karma, neighbor_cells[1], Land.BLIGHTED)
	assert_eq(_at(grid, Land.next_karma(grid, karma, T), corner), 0, "sum -4: no change")
	_put(grid, karma, neighbor_cells[2], Land.BLIGHTED)
	assert_eq(_at(grid, Land.next_karma(grid, karma, T), corner), Land.CORRUPTED, "sum -6: loses 1")


func test_R11_4_threshold_comes_from_data() -> void:
	var grid: HexGrid = _grid()
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, Vector2i(0, 0), Land.BLIGHTED)
	_put(grid, karma, Vector2i(1, 0), Land.BLIGHTED)
	var common: Vector2i = Vector2i(0, 1)  # adjacent to both: sum -4
	assert_eq(_at(grid, Land.next_karma(grid, karma, 5), common), 0)
	assert_eq(_at(grid, Land.next_karma(grid, karma, 4), common), Land.CORRUPTED)


func test_R11_1_karma_is_clamped_to_the_range() -> void:
	var grid: HexGrid = _grid(3)
	assert_eq(_run(grid, _filled(grid, Land.BLIGHTED), 5), _filled(grid, Land.BLIGHTED))
	assert_eq(_run(grid, _filled(grid, Land.THRIVING), 5), _filled(grid, Land.THRIVING))


func test_R11_4_all_cells_update_from_the_old_state() -> void:
	# A Corrupted line next to a Blighted cell advances one cell per phase, not all at once.
	var grid: HexGrid = _grid(6)
	var karma: PackedInt32Array = _filled(grid, 0)
	_put(grid, karma, Vector2i(0, 0), Land.BLIGHTED)
	for q: int in range(1, 5):
		_put(grid, karma, Vector2i(q, 0), Land.CORRUPTED)
	var after_one: PackedInt32Array = Land.next_karma(grid, karma, T)
	assert_eq(_at(grid, after_one, Vector2i(1, 0)), Land.BLIGHTED)
	assert_eq(_at(grid, after_one, Vector2i(2, 0)), Land.CORRUPTED, "not yet: its neighbor was only Corrupted")
	var after_two: PackedInt32Array = Land.next_karma(grid, after_one, T)
	assert_eq(_at(grid, after_two, Vector2i(2, 0)), Land.BLIGHTED)
	assert_eq(_at(grid, after_two, Vector2i(3, 0)), Land.CORRUPTED)


func test_R11_4_input_is_not_modified() -> void:
	var grid: HexGrid = _grid(3)
	var karma: PackedInt32Array = _filled(grid, Land.CORRUPTED)
	_put(grid, karma, Vector2i.ZERO, Land.BLIGHTED)
	var before: PackedInt32Array = karma.duplicate()
	Land.next_karma(grid, karma, T)
	assert_eq(karma, before)


func test_R11_5_forecast_lists_changed_cells_in_cell_order() -> void:
	var grid: HexGrid = _grid(4)
	var karma: PackedInt32Array = _filled(grid, Land.CORRUPTED)
	_put(grid, karma, Vector2i.ZERO, Land.BLIGHTED)
	var result: Dictionary = Land.forecast(grid, karma, T)
	var changed: PackedInt32Array = result["changed"]
	var next: PackedInt32Array = result["next"]
	assert_gt(changed.size(), 0)
	var expected: PackedInt32Array = PackedInt32Array()
	for i: int in grid.size():
		if next[i] != karma[i]:
			expected.append(i)
	assert_eq(changed, expected)
	for i: int in range(1, changed.size()):
		assert_gt(changed[i], changed[i - 1])
	assert_eq(result["board_karma_after"], Land.board_karma(next))
	assert_lt(int(result["board_karma_after"]), Land.board_karma(karma))


func test_R11_6_board_karma_sums_every_cell() -> void:
	var grid: HexGrid = _grid(2)
	assert_eq(Land.board_karma(_filled(grid, 0)), 0)
	assert_eq(Land.board_karma(_filled(grid, Land.PURE)), grid.size())
	assert_eq(Land.board_karma(_filled(grid, Land.BLIGHTED)), -2 * grid.size())
