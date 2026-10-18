extends GutTest
## Round 2, item 2.7 (GDD R9.3): the plan preview in four shades of blue, light to dark: 1 the zone
## you can use, 2 the chosen path, 3 the predicted position with a ghost, 4 the ability's target and
## Area, with damage numbers on the fighters it hits.


func _main() -> Control:
	var scene: Control = load("res://src/client/main.tscn").instantiate()
	add_child_autofree(scene)
	scene.untimed = true
	scene.board.animation_speed = 0.0
	await get_tree().process_frame
	return scene


func _slab_colors(board: BoardView, layer: String) -> Array[Color]:
	var colors: Array[Color] = []
	if not board._layers.has(layer):
		return colors
	for slab: Node in (board._layers[layer] as Node3D).get_children():
		colors.append(((slab as MeshInstance3D).material_override as StandardMaterial3D).albedo_color)
	return colors


func _slab_count(board: BoardView, layer: String) -> int:
	return (board._layers[layer] as Node3D).get_child_count() if board._layers.has(layer) else 0


func _slab_y(board: BoardView, layer: String) -> float:
	return ((board._layers[layer] as Node3D).get_child(0) as Node3D).position.y


## A scene where the Striker (id 1) stands next to the Brute, so a Lunge has a target.
func _setup_close_fight(main: Control) -> void:
	# Move the first Brute next to the Striker, so abilities have targets.
	var striker_cell: Vector2i = main.state.cell_of(main.state.fighters[1])
	var brute: FighterState = main.state.fighters[3]
	main.state.set_position(brute, main.state.grid.index_of(striker_cell + Vector2i(0, -2)))
	main.board.sync(main.state)
	main.builder.reset(main.state)


func test_the_zone_being_aimed_is_shade_1() -> void:
	var main: Control = await _main()
	main.select(0)
	assert_eq(_slab_colors(main.board, "reach")[0], Palette.US_SHADES[0], "the move zone")
	main.choose_ability("bash")
	assert_eq(_slab_colors(main.board, "target").size(), 0, "no enemy within reach of Bash yet")
	main.cancel_or_clear()


func test_the_chosen_path_is_shade_2() -> void:
	var main: Control = await _main()
	main.select(0)
	var start: Vector2i = main.state.cell_of(main.state.fighters[0])
	main.click_cell(start + Vector2i(0, -1))
	assert_eq(_slab_count(main.board, "path"), 1)
	main.choose_move()
	main.click_cell(start + Vector2i(-1, -1))
	assert_eq(_slab_count(main.board, "path"), 2, "replaced by a longer path")
	for color: Color in _slab_colors(main.board, "path"):
		assert_eq(color, Palette.US_SHADES[1])


func test_the_predicted_position_is_shade_3_with_a_ghost_of_the_creature() -> void:
	var main: Control = await _main()
	main.select(0)
	var start: Vector2i = main.state.cell_of(main.state.fighters[0])
	var destination: Vector2i = start + Vector2i(-1, -1)
	main.click_cell(destination)
	assert_eq(_slab_count(main.board, "predicted"), 1)
	assert_eq(_slab_colors(main.board, "predicted")[0], Palette.US_SHADES[2])
	var ghosts: Array[Node] = main.board._ghost_root.get_children()
	assert_eq(ghosts.size(), 1, "one ghost for one planned Move")
	var ghost: MeshInstance3D = ghosts[0]
	var expected: Vector3 = main.board.world_of(destination) + Vector3(0, BoardView.TILE_HEIGHT + 0.45, 0)
	assert_eq(ghost.position, expected, "the ghost stands on the predicted cell")
	assert_eq(ghost.mesh, main.board.fighter_view(0).body_mesh(), "and has the creature's shape")
	assert_lt(((ghost.material_override as StandardMaterial3D).albedo_color).a, 1.0, "translucent")
	assert_eq(main.board.fighter_view(0).position, main.board.world_of(start) + Vector3(0, BoardView.TILE_HEIGHT, 0), "the real figure has not moved")


func test_the_ability_target_and_area_are_shade_4_with_damage_numbers_on_who_it_hits() -> void:
	var main: Control = await _main()
	_setup_close_fight(main)
	main.select(1)
	main.choose_ability("lunge")
	var striker_cell: Vector2i = main.state.cell_of(main.state.fighters[1])
	var target: Vector2i = striker_cell + Vector2i(0, -2)
	assert_true(main.builder.target_cells(1).has(main.state.grid.index_of(target)), "precondition: Lunge reaches the Brute")
	assert_gt(_slab_count(main.board, "target"), 0)
	main.click_cell(target)
	assert_eq(_slab_count(main.board, "plan_area"), 1, "Lunge hits a single cell")
	assert_eq(_slab_colors(main.board, "plan_area")[0], Palette.US_SHADES[3])
	var preview: Label3D = main.board.fighter_view(3)._preview
	assert_true(preview.visible, "damage number on the Brute")
	assert_string_contains(preview.text, "-")
	assert_false(main.board.fighter_view(4)._preview.visible, "not on the one it does not hit")


func test_the_shades_do_not_depend_on_the_plan_order() -> void:
	var main: Control = await _main()
	_setup_close_fight(main)
	var start: Vector2i = main.state.cell_of(main.state.fighters[1])
	main.select(1)
	# Move first, then the ability.
	main.click_cell(start + Vector2i(0, -1))
	main.choose_ability("lunge")
	main.click_cell(start + Vector2i(0, -2))
	var move_first: Dictionary = {
		"path": _slab_colors(main.board, "path"), "predicted": _slab_colors(main.board, "predicted"), "area": _slab_colors(main.board, "plan_area"),
	}
	assert_eq(main.builder.plan_for(1)["order"], "move_first")
	main.clear_selected()
	# Ability first, then the Move: same shades.
	main.choose_ability("lunge")
	main.click_cell(start + Vector2i(0, -2))
	main.choose_move()
	main.click_cell(start + Vector2i(0, -1))
	assert_eq(main.builder.plan_for(1)["order"], "ability_first")
	assert_eq(_slab_colors(main.board, "path"), move_first["path"])
	assert_eq(_slab_colors(main.board, "predicted"), move_first["predicted"])
	assert_eq(_slab_colors(main.board, "plan_area"), move_first["area"])
	assert_eq(main.board._ghost_root.get_child_count(), 1)


func test_layers_stack_light_to_dark() -> void:
	var main: Control = await _main()
	_setup_close_fight(main)
	var start: Vector2i = main.state.cell_of(main.state.fighters[1])
	main.select(1)
	main.click_cell(start + Vector2i(0, -1))
	main.choose_ability("lunge")
	main.click_cell(start + Vector2i(0, -2))
	main.choose_move()
	var zone_y: float = _slab_y(main.board, "reach")
	var path_y: float = _slab_y(main.board, "path")
	var predicted_y: float = _slab_y(main.board, "predicted")
	var area_y: float = _slab_y(main.board, "plan_area")
	assert_lt(zone_y, path_y)
	assert_lt(path_y, predicted_y)
	assert_lt(predicted_y, area_y)


func test_hovering_a_target_shows_its_area_in_the_darkest_shade() -> void:
	var main: Control = await _main()
	_setup_close_fight(main)
	var start: Vector2i = main.state.cell_of(main.state.fighters[1])
	main.select(1)
	main.choose_ability("whirl")
	assert_false(main.targeting, "Whirl is self-targeted: nothing to hover")
	main.clear_selected()
	main.choose_ability("lunge")
	main._on_cell_hovered(start + Vector2i(0, -2))
	assert_eq(_slab_colors(main.board, "area")[0], Palette.US_SHADES[3])


func test_ghosts_and_overlays_disappear_with_the_plan() -> void:
	var main: Control = await _main()
	main.select(0)
	main.click_cell(main.state.cell_of(main.state.fighters[0]) + Vector2i(0, -1))
	assert_eq(main.board._ghost_root.get_child_count(), 1)
	main.clear_selected()
	assert_eq(main.board._ghost_root.get_child_count(), 0)
	assert_eq(_slab_count(main.board, "path"), 0)
	main.select(0)
	main.click_cell(main.state.cell_of(main.state.fighters[0]) + Vector2i(0, -1))
	assert_eq(main.board._ghost_root.get_child_count(), 1)
	await main.resolve_step()
	assert_eq(main.board._ghost_root.get_child_count(), 0, "a new window starts with no ghosts")


func test_every_creature_with_a_move_gets_its_own_ghost() -> void:
	var main: Control = await _main()
	for id: int in [0, 1, 2]:
		main.select(id)
		main.click_cell(main.state.cell_of(main.state.fighters[id]) + Vector2i(0, -1 - id))
	assert_eq(main.board._ghost_root.get_child_count(), 3)
	assert_eq(_slab_count(main.board, "predicted"), 3)
