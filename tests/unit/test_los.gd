extends GutTest
## T4: line of sight (GDD R5). The golden table is part of the port contract.

const TABLE_PATH: String = "res://tests/golden/los_table.json"


func _blocker(blocked: Array[Vector2i]) -> Callable:
	return func(cell: Vector2i) -> bool: return blocked.has(cell)


func _no_blockers() -> Callable:
	return func(_cell: Vector2i) -> bool: return false


func test_R5_3_los_to_self_and_neighbors_ignores_blockers() -> void:
	var everything: Callable = func(_cell: Vector2i) -> bool: return true
	var origin: Vector2i = Vector2i(1, -2)
	assert_true(Los.has_los(origin, origin, everything))
	for n: Vector2i in Hex.neighbors(origin):
		assert_true(Los.has_los(origin, n, everything))


func test_R5_1_open_board_has_los_between_all_pairs() -> void:
	var cells: Array[Vector2i] = Hex.disk(Vector2i.ZERO, 4)
	var open: Callable = _no_blockers()
	for a: Vector2i in cells:
		for b: Vector2i in cells:
			assert_true(Los.has_los(a, b, open))


func test_R5_1_obstacle_on_a_straight_line_blocks() -> void:
	var a: Vector2i = Vector2i(0, 0)
	var b: Vector2i = Vector2i(4, 0)
	assert_false(Los.has_los(a, b, _blocker([Vector2i(2, 0)])))
	assert_false(Los.has_los(a, b, _blocker([Vector2i(1, 0)])))
	assert_false(Los.has_los(a, b, _blocker([Vector2i(3, 0)])))


func test_R5_1_obstacle_off_the_line_does_not_block() -> void:
	var a: Vector2i = Vector2i(0, 0)
	var b: Vector2i = Vector2i(4, 0)
	assert_true(Los.has_los(a, b, _blocker([Vector2i(2, 1), Vector2i(2, -1), Vector2i(0, 1)])))


func test_R5_1_endpoints_never_block_themselves() -> void:
	var a: Vector2i = Vector2i(0, 0)
	var b: Vector2i = Vector2i(3, 0)
	assert_true(Los.has_los(a, b, _blocker([a, b])))


func test_R5_1_a_fighter_blocks_like_an_obstacle() -> void:
	# The blocker callback covers both blocks_los cells and occupied cells.
	var fighters: Array[Vector2i] = [Vector2i(0, 2)]
	assert_false(Los.has_los(Vector2i(0, 0), Vector2i(0, 4), _blocker(fighters)))


func test_R5_2_either_nudged_line_may_be_clear() -> void:
	# (0,0) -> (2,-1) runs exactly between (1,0) and (1,-1): one blocker leaves the other line open.
	var a: Vector2i = Vector2i(0, 0)
	var b: Vector2i = Vector2i(2, -1)
	assert_true(Los.has_los(a, b, _blocker([Vector2i(1, 0)])))
	assert_true(Los.has_los(a, b, _blocker([Vector2i(1, -1)])))
	assert_false(Los.has_los(a, b, _blocker([Vector2i(1, 0), Vector2i(1, -1)])))


func test_R5_2_los_is_symmetric_on_an_arena_with_obstacles() -> void:
	var table: Dictionary = _load_table()
	var grid: HexGrid = HexGrid.hexagon(int(table["radius"]))
	var obstacles: Array[Vector2i] = _obstacles(table)
	var blocks: Callable = _blocker(obstacles)
	var asymmetric: int = 0
	for a: Vector2i in grid.cells:
		for b: Vector2i in grid.cells:
			if Los.has_los(a, b, blocks) != Los.has_los(b, a, blocks):
				asymmetric += 1
	assert_eq(asymmetric, 0, "LoS(A, B) == LoS(B, A) for every cell pair")


func test_R5_2_los_is_symmetric_with_random_obstacles() -> void:
	var prng: Prng = Prng.create(77)
	var grid: HexGrid = HexGrid.hexagon(5)
	for round: int in 5:
		var obstacles: Array[Vector2i] = []
		for cell: Vector2i in grid.cells:
			if prng.next_below(100) < 18:
				obstacles.append(cell)
		var blocks: Callable = _blocker(obstacles)
		var asymmetric: int = 0
		for a: Vector2i in grid.cells:
			for b: Vector2i in grid.cells:
				if Los.has_los(a, b, blocks) != Los.has_los(b, a, blocks):
					asymmetric += 1
		assert_eq(asymmetric, 0, "round %d" % round)


func test_R5_2_hand_checked_pairs_on_the_golden_arena() -> void:
	var table: Dictionary = _load_table()
	var blocks: Callable = _blocker(_obstacles(table))
	# Obstacles: (1,0), (-1,1), (0,-2), (2,-3).
	assert_false(Los.has_los(Vector2i(0, 0), Vector2i(2, 0), blocks), "through (1,0)")
	assert_false(Los.has_los(Vector2i(-1, 0), Vector2i(3, 0), blocks), "through (1,0)")
	assert_true(Los.has_los(Vector2i(0, 0), Vector2i(2, -1), blocks), "tie line has a free side")
	assert_true(Los.has_los(Vector2i(0, 0), Vector2i(0, 2), blocks), "(0,1) is free")
	assert_false(Los.has_los(Vector2i(0, 0), Vector2i(0, -3), blocks), "through (0,-2)")
	assert_true(Los.has_los(Vector2i(1, 0), Vector2i(2, 0), blocks), "neighbors, even from an obstacle")
	assert_false(Los.has_los(Vector2i(-2, 1), Vector2i(0, 1), blocks), "through (-1,1)")
	assert_true(Los.has_los(Vector2i(-3, 0), Vector2i(-3, 3), blocks), "edge line is free")


func test_R5_2_matches_golden_table() -> void:
	var table: Dictionary = _load_table()
	var grid: HexGrid = HexGrid.hexagon(int(table["radius"]))
	var blocks: Callable = _blocker(_obstacles(table))
	var rows: Array = table["rows"]
	assert_eq(rows.size(), grid.size())
	var mismatches: int = 0
	for i: int in grid.size():
		var row: String = rows[i]
		assert_eq(row.length(), grid.size())
		for j: int in grid.size():
			var expected: bool = row[j] == "1"
			if Los.has_los(grid.cell_at(i), grid.cell_at(j), blocks) != expected:
				mismatches += 1
	assert_eq(mismatches, 0, "every (from, to) pair matches the golden table")


func test_div_round_never_ties_and_rounds_to_nearest() -> void:
	assert_eq(Los._div_round(0, 12), 0)
	assert_eq(Los._div_round(5, 12), 0)
	assert_eq(Los._div_round(7, 12), 1)
	assert_eq(Los._div_round(-5, 12), 0)
	assert_eq(Los._div_round(-7, 12), -1)


func _load_table() -> Dictionary:
	var data: Variant = JSON.parse_string(DataFiles.read_text(TABLE_PATH))
	assert_true(data is Dictionary, "los_table.json loads")
	var table: Dictionary = data
	return table


func _obstacles(table: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pair: Array in table["obstacles"]:
		result.append(Vector2i(int(pair[0]), int(pair[1])))
	return result
