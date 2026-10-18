extends GutTest
## Playtest round 2: real mouse events must reach the board through the GUI. The other client tests
## call click_cell directly, which skips input routing, so they could not catch a GUI layer that
## swallows clicks. These tests push events through a viewport, exactly like a player's mouse.


func _main_in_viewport() -> Array:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	add_child_autofree(viewport)
	var scene: Control = load("res://src/client/main.tscn").instantiate()
	viewport.add_child(scene)
	scene.untimed = true
	scene.board.animation_speed = 0.0
	await get_tree().process_frame
	return [viewport, scene]


func _push_click(viewport: SubViewport, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event, true)


func _push_motion(viewport: SubViewport, at: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	viewport.push_input(event, true)


func _tile_top_on_screen(scene: Control, cell: Vector2i) -> Vector2:
	var top: Vector3 = scene.board.world_of(cell) + Vector3(0, BoardView.TILE_HEIGHT, 0)
	return scene.board.camera().unproject_position(top)


func test_the_root_control_lets_board_clicks_through() -> void:
	var setup: Array = await _main_in_viewport()
	var scene: Control = setup[1]
	assert_eq(scene.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"a full-screen Control that stops the mouse swallows every click meant for the 3D board")


func test_a_real_click_on_an_empty_tile_reaches_the_board() -> void:
	var setup: Array = await _main_in_viewport()
	var viewport: SubViewport = setup[0]
	var scene: Control = setup[1]
	var cell: Vector2i = Vector2i(0, 0)  # the open center of PH Nave
	assert_null(scene.state.fighter_at(scene.state.grid.index_of(cell)), "precondition: the tile is empty")
	watch_signals(scene.board)
	_push_click(viewport, _tile_top_on_screen(scene, cell))
	assert_signal_emitted_with_parameters(scene.board, "cell_clicked", [cell])


func test_a_real_click_on_a_creature_figure_reaches_the_board_as_its_cell() -> void:
	var setup: Array = await _main_in_viewport()
	var viewport: SubViewport = setup[0]
	var scene: Control = setup[1]
	var creature: FighterState = scene.state.fighters[1]
	var cell: Vector2i = scene.state.cell_of(creature)
	var body: Vector3 = scene.board.fighter_view(creature.id).position + Vector3(0, 0.8, 0)
	watch_signals(scene.board)
	_push_click(viewport, scene.board.camera().unproject_position(body))
	assert_signal_emitted_with_parameters(scene.board, "cell_clicked", [cell])


func test_real_clicks_on_every_tile_name_that_tile() -> void:
	var setup: Array = await _main_in_viewport()
	var viewport: SubViewport = setup[0]
	var scene: Control = setup[1]
	watch_signals(scene.board)
	var checked: int = 0
	for index: int in scene.state.grid.size():
		var cell: Vector2i = scene.state.grid.cell_at(index)
		if _next_to_a_fighter(scene, cell):
			continue  # a figure stands over this tile or the one in front: figures win (round 2, 2.1)
		var at: Vector2 = _tile_top_on_screen(scene, cell)
		if not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(at):
			continue
		_push_click(viewport, at)
		assert_signal_emitted_with_parameters(scene.board, "cell_clicked", [cell], checked)
		checked += 1
	assert_gt(checked, 40, "most tiles away from fighters are on screen and were clicked")


func _next_to_a_fighter(scene: Control, cell: Vector2i) -> bool:
	for fighter: FighterState in scene.state.fighters:
		if fighter.on_board() and Hex.distance(scene.state.cell_of(fighter), cell) <= 1:
			return true
	return false


func test_real_mouse_motion_reaches_the_board_as_hover() -> void:
	var setup: Array = await _main_in_viewport()
	var viewport: SubViewport = setup[0]
	var scene: Control = setup[1]
	var cell: Vector2i = Vector2i(0, 0)
	watch_signals(scene.board)
	_push_motion(viewport, _tile_top_on_screen(scene, cell))
	assert_signal_emitted_with_parameters(scene.board, "cell_hovered", [cell])
