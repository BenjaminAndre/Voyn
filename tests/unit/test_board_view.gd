extends GutTest
## T12: the 3D board view. Layout and picking maths, the fighters on the board, overlays, forecast
## markers, and playing rules events (with animation off, and a short run with tweens on).


func _state() -> FightState:
	var roster: Array = [
		TestFixtures.creature({"abilities": ["bash"], "kind": "ph_tank", "name": "PH Tank"}),
		TestFixtures.monster([1, 0], {"abilities": ["bash"], "kind": "ph_brute", "name": "PH Brute"}),
		TestFixtures.monster([4, -4], {"name": "PH Flier", "kind": "ph_flier"}),
	]
	return TestFixtures.running(roster, [Vector2i(0, 0)], {"obstacles": [[-2, 0]], "karma": [[0, 2, -2], [1, 2, 1]]}, 1, {"land_phase_every_steps": 1})


func _board(state: FightState) -> BoardView:
	var board: BoardView = BoardView.new()
	add_child_autofree(board)
	board.setup(state)
	board.animation_speed = 0.0
	return board


# --- Layout ---


func test_cells_round_trip_through_world_positions() -> void:
	for cell: Vector2i in Hex.disk(Vector2i.ZERO, 6):
		assert_eq(HexLayout.from_world(HexLayout.to_world(cell, 1.0), 1.0), cell)
		assert_eq(HexLayout.from_world(HexLayout.to_world(cell, 2.5), 2.5), cell)


func test_neighbors_are_sqrt3_apart_and_tiles_share_edges() -> void:
	var center: Vector3 = HexLayout.to_world(Vector2i(2, -1), 1.0)
	for direction: Vector2i in Hex.DIRECTIONS:
		var other: Vector3 = HexLayout.to_world(Vector2i(2, -1) + direction, 1.0)
		assert_almost_eq(center.distance_to(other), HexLayout.SQRT3, 0.0001)
	# A corner of one hex is also a corner of two neighbors: the layout tiles the plane.
	var corners: Array[Vector3] = HexLayout.corners(1.0)
	var here: Vector3 = center + corners[0]
	var east: Vector3 = HexLayout.to_world(Vector2i(3, -2), 1.0) + corners[2]
	assert_almost_eq(here.distance_to(east), 0.0, 0.0001)


func test_points_near_a_center_belong_to_its_cell() -> void:
	var cell: Vector2i = Vector2i(-2, 3)
	var center: Vector3 = HexLayout.to_world(cell, 1.0)
	for offset: Vector3 in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0.2), Vector3(0.1, 0, -0.5)]:
		assert_eq(HexLayout.from_world(center + offset, 1.0), cell)


# --- The view ---


func test_setup_builds_one_tile_per_cell_and_a_view_per_fighter() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var tiles: int = 0
	for child: Node in board.get_children():
		if child is MeshInstance3D:
			tiles += 1
	assert_gte(tiles, state.grid.size() + 1, "tiles plus a pillar for the obstacle")
	for fighter: FighterState in state.fighters:
		assert_not_null(board.fighter_view(fighter.id))
	assert_not_null(board.camera())
	assert_eq(board.camera().projection, Camera3D.PROJECTION_ORTHOGONAL)


func test_fighters_stand_on_their_cells() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	for fighter: FighterState in state.fighters:
		var expected: Vector3 = board.world_of(state.cell_of(fighter)) + Vector3(0, BoardView.TILE_HEIGHT, 0)
		assert_eq(board.fighter_view(fighter.id).position, expected)


func test_tiles_are_tinted_by_karma() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var blighted: int = state.grid.index_of(Vector2i(0, 2))
	var pure: int = state.grid.index_of(Vector2i(1, 2))
	var neutral: int = state.grid.index_of(Vector2i(3, 0))
	assert_eq(board._tile_materials[blighted].albedo_color, BoardView.KARMA_COLORS[0])
	assert_eq(board._tile_materials[pure].albedo_color, BoardView.KARMA_COLORS[3])
	assert_eq(board._tile_materials[neutral].albedo_color, BoardView.KARMA_COLORS[2])


func test_a_defeated_fighter_is_hidden_after_sync() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var events: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[2], events)
	board.sync(state)
	assert_false(board.fighter_view(2).visible)
	assert_true(board.fighter_view(1).visible)


func test_overlays_can_be_set_and_cleared() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var cells: Array[int] = [0, 1, 2]
	board.set_overlay("reach", cells, Color(0, 0, 1, 0.3))
	assert_true(board._layers.has("reach"))
	assert_eq((board._layers["reach"] as Node3D).get_child_count(), 3)
	board.set_overlay("reach", [5] as Array[int], Color(0, 0, 1, 0.3))
	assert_eq((board._layers["reach"] as Node3D).get_child_count(), 1, "replaced")
	board.clear_overlay("reach")
	assert_false(board._layers.has("reach"))


func test_forecast_markers_follow_the_forecast() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var changed: PackedInt32Array = PackedInt32Array([3, 4])
	var next: PackedInt32Array = state.karma.duplicate()
	next[3] = state.karma[3] + 1
	next[4] = state.karma[4] - 1
	board.set_forecast(changed, next)
	assert_eq(board._forecast_root.get_child_count(), 2)


# --- Picking ---


func test_screen_picking_finds_the_cell_a_tile_is_drawn_at() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var camera: Camera3D = board.camera()
	await get_tree().process_frame
	var misses: int = 0
	for cell: Vector2i in Hex.disk(Vector2i.ZERO, 4):
		var top: Vector3 = board.world_of(cell) + Vector3(0, BoardView.TILE_HEIGHT, 0)
		var screen: Vector2 = camera.unproject_position(top)
		if board.cell_at_screen(screen) != cell:
			misses += 1
	assert_eq(misses, 0, "every tile center picks its own cell")


func test_clicking_emits_the_cell() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	await get_tree().process_frame
	var target: Vector2i = Vector2i(2, 1)
	var screen: Vector2 = board.camera().unproject_position(board.world_of(target) + Vector3(0, BoardView.TILE_HEIGHT, 0))
	watch_signals(board)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	board._unhandled_input(click)
	assert_signal_emitted_with_parameters(board, "cell_clicked", [target])


# --- Playing events ---


func test_playing_events_ends_with_the_view_in_the_final_state() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	var plans: Array = [
		{"fighter": 0, "ability": "bash", "target_cell": [1, 0]},
		TestFixtures.move(2, [[3, -3]]),
	]
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_true(result["ok"], str(result["errors"]))
	var banners: Array[String] = []
	board.banner.connect(func(text: String) -> void: banners.append(text))
	await board.play_events(result["events"], result["state"])
	var after: FightState = result["state"]
	assert_eq(board.fighter_view(2).position, board.world_of(after.cell_of(after.fighters[2])) + Vector3(0, BoardView.TILE_HEIGHT, 0))
	assert_eq(banners.size(), 7, "six phases and the Land phase")
	assert_eq(banners[0], "Lead Move")
	for index: int in after.grid.size():
		assert_eq(board._tile_materials[index].albedo_color, BoardView.KARMA_COLORS[after.karma[index] + 2])


func test_playing_events_with_animation_runs_without_errors() -> void:
	var state: FightState = _state()
	var board: BoardView = _board(state)
	board.animation_speed = 0.02
	var plans: Array = [
		{"fighter": 0, "ability": "bash", "target_cell": [1, 0]},
		TestFixtures.move(2, [[3, -3]]),
	]
	var result: Dictionary = TestFixtures.resolve(state, plans)
	var land: Array[int] = []
	board.land_changed.connect(func(value: int) -> void: land.append(value))
	await board.play_events(result["events"], result["state"])
	assert_eq(land.size(), 1)
	assert_eq(land[0], result["state"].board_karma())
	assert_eq(board.fighter_view(1).position, board.world_of(result["state"].cell_of(result["state"].fighters[1])) + Vector3(0, BoardView.TILE_HEIGHT, 0))
