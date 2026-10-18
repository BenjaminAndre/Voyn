extends GutTest
## T3: hex math (GDD R1.1-R1.3, R7.5) and HexGrid.


func test_R1_1_distance_known_values() -> void:
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(1, 0)), 1)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -1)), 2)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, -3)), 3)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, 2)), 4)
	assert_eq(Hex.distance(Vector2i(-2, 3), Vector2i(1, -1)), 4)


func test_R1_1_distance_is_symmetric_and_matches_cube_distance() -> void:
	var cells: Array[Vector2i] = Hex.disk(Vector2i.ZERO, 4)
	for a: Vector2i in cells:
		for b: Vector2i in cells:
			var d: int = Hex.distance(a, b)
			assert_eq(d, Hex.distance(b, a))
			var ca: Vector3i = Hex.to_cube(a)
			var cb: Vector3i = Hex.to_cube(b)
			var cube_d: int = maxi(absi(ca.x - cb.x), maxi(absi(ca.y - cb.y), absi(ca.z - cb.z)))
			assert_eq(d, cube_d)


func test_R1_1_cube_round_trip() -> void:
	for cell: Vector2i in Hex.disk(Vector2i.ZERO, 3):
		var cube: Vector3i = Hex.to_cube(cell)
		assert_eq(cube.x + cube.y + cube.z, 0)
		assert_eq(Hex.from_cube(cube), cell)


func test_R1_2_direction_order_and_neighbors() -> void:
	assert_eq(Hex.DIRECTIONS.size(), 6)
	assert_eq(Hex.DIRECTIONS[0], Vector2i(1, 0))
	assert_eq(Hex.DIRECTIONS[1], Vector2i(1, -1))
	assert_eq(Hex.DIRECTIONS[2], Vector2i(0, -1))
	assert_eq(Hex.DIRECTIONS[3], Vector2i(-1, 0))
	assert_eq(Hex.DIRECTIONS[4], Vector2i(-1, 1))
	assert_eq(Hex.DIRECTIONS[5], Vector2i(0, 1))
	var origin: Vector2i = Vector2i(2, -3)
	var around: Array[Vector2i] = Hex.neighbors(origin)
	var seen: Dictionary = {}
	for k: int in 6:
		assert_eq(around[k], origin + Hex.DIRECTIONS[k])
		assert_eq(around[k], Hex.neighbor(origin, k))
		assert_eq(Hex.distance(origin, around[k]), 1)
		seen[around[k]] = true
	assert_eq(seen.size(), 6, "six distinct neighbors")


func test_R1_2_opposite_directions_cancel() -> void:
	for k: int in 6:
		assert_eq(Hex.DIRECTIONS[k] + Hex.DIRECTIONS[Hex.opposite(k)], Vector2i.ZERO)


func test_R1_3_cell_order_sorts_by_q_then_r() -> void:
	var cells: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 2), Vector2i(0, -1), Vector2i(-1, 5), Vector2i(1, -4)]
	Hex.sort_cells(cells)
	var expected: Array[Vector2i] = [Vector2i(-1, 5), Vector2i(0, -1), Vector2i(0, 2), Vector2i(1, -4), Vector2i(1, 0)]
	assert_eq(cells, expected)
	assert_true(Hex.cell_less(Vector2i(0, 9), Vector2i(1, -9)))
	assert_false(Hex.cell_less(Vector2i(1, 1), Vector2i(1, 1)))


func test_disk_and_ring_sizes() -> void:
	for radius: int in 5:
		assert_eq(Hex.disk(Vector2i(3, -2), radius).size(), 1 + 3 * radius * (radius + 1))
		var expected_ring: int = 1 if radius == 0 else 6 * radius
		assert_eq(Hex.ring(Vector2i(3, -2), radius).size(), expected_ring)


func test_disk_is_in_cell_order_and_within_radius() -> void:
	var center: Vector2i = Vector2i(-1, 2)
	var cells: Array[Vector2i] = Hex.disk(center, 3)
	for i: int in cells.size():
		assert_lte(Hex.distance(center, cells[i]), 3)
		if i > 0:
			assert_true(Hex.cell_less(cells[i - 1], cells[i]))


func test_R7_5_push_direction_along_each_axis() -> void:
	var origin: Vector2i = Vector2i(1, 1)
	for k: int in 6:
		for n: int in range(1, 4):
			var target: Vector2i = origin + Hex.DIRECTIONS[k] * n
			assert_eq(Hex.push_direction(origin, target), k, "dir %d dist %d" % [k, n])
			assert_eq(Hex.pull_direction(origin, target), Hex.opposite(k))


func test_R7_5_push_direction_tie_goes_to_lowest_index() -> void:
	# (1, 1) is equally close to D0 and D5; (-1, -1) to D2 and D3; (2, -1) to D0 and D1.
	assert_eq(Hex.push_direction(Vector2i.ZERO, Vector2i(1, 1)), 0)
	assert_eq(Hex.push_direction(Vector2i.ZERO, Vector2i(-1, -1)), 2)
	assert_eq(Hex.push_direction(Vector2i.ZERO, Vector2i(2, -1)), 0)


func test_R7_5_push_direction_on_origin_is_none() -> void:
	assert_eq(Hex.push_direction(Vector2i(2, 2), Vector2i(2, 2)), -1)
	assert_eq(Hex.pull_direction(Vector2i(2, 2), Vector2i(2, 2)), -1)


func test_R7_5_push_direction_is_never_toward_the_origin() -> void:
	var origin: Vector2i = Vector2i.ZERO
	for cell: Vector2i in Hex.disk(origin, 4):
		if cell == origin:
			continue
		var k: int = Hex.push_direction(origin, cell)
		assert_gte(Hex.distance(origin, cell + Hex.DIRECTIONS[k]), Hex.distance(origin, cell), "never closer")


func test_floor_div_matches_float_floor() -> void:
	for n: int in range(-60, 61):
		for m: int in range(1, 9):
			assert_eq(Hex.floor_div(n, m), floori(float(n) / float(m)), "%d / %d" % [n, m])


func test_floor_div_known_values() -> void:
	assert_eq(Hex.floor_div(7, 2), 3)
	assert_eq(Hex.floor_div(-7, 2), -4)
	assert_eq(Hex.floor_div(-6, 3), -2)
	assert_eq(Hex.floor_div(-1, 3), -1)
	assert_eq(Hex.floor_div(0, 5), 0)


func test_grid_hexagon_cells_and_index() -> void:
	var grid: HexGrid = HexGrid.hexagon(3)
	assert_eq(grid.size(), 37)
	for i: int in grid.size():
		assert_eq(grid.index_of(grid.cell_at(i)), i)
		if i > 0:
			assert_true(Hex.cell_less(grid.cell_at(i - 1), grid.cell_at(i)))
	assert_eq(grid.index_of(Vector2i(4, 0)), -1)
	assert_false(grid.has_cell(Vector2i(4, 0)))
	assert_true(grid.has_cell(Vector2i(0, 0)))


func test_grid_neighbor_counts_center_edge_corner() -> void:
	var grid: HexGrid = HexGrid.hexagon(2)
	assert_eq(grid.neighbor_indices[grid.index_of(Vector2i(0, 0))].size(), 6)
	assert_eq(grid.neighbor_indices[grid.index_of(Vector2i(2, 0))].size(), 3, "corner")
	assert_eq(grid.neighbor_indices[grid.index_of(Vector2i(2, -1))].size(), 4, "edge")


func test_grid_neighbor_indices_are_symmetric_and_in_direction_order() -> void:
	var grid: HexGrid = HexGrid.hexagon(3)
	for i: int in grid.size():
		var last_direction: int = -1
		for j: int in grid.neighbor_indices[i]:
			assert_true(grid.neighbor_indices[j].has(i))
			var direction: int = Hex.DIRECTIONS.find(grid.cell_at(j) - grid.cell_at(i))
			assert_gt(direction, last_direction, "direction order")
			last_direction = direction


func test_grid_from_cells_sorts_and_rejects_duplicates() -> void:
	var cells: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1)]
	var grid: HexGrid = HexGrid.from_cells(cells)
	assert_eq(grid.cell_at(0), Vector2i(0, 0))
	assert_eq(grid.cell_at(1), Vector2i(0, 1))
	assert_eq(grid.cell_at(2), Vector2i(1, 0))
	var duplicated: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 0)]
	assert_null(HexGrid.from_cells(duplicated))
