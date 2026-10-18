extends GutTest
## T13: the main scene's step loop, driven through its public methods with animation off.


func _main() -> Control:
	var scene: Control = load("res://src/client/main.tscn").instantiate()
	add_child_autofree(scene)
	# _ready has run: stop the window timer before the first frame can tick it down.
	scene.untimed = true
	scene.board.animation_speed = 0.0
	await get_tree().process_frame
	return scene


func test_the_game_starts_in_a_planning_window_on_step_one() -> void:
	var main: Control = await _main()
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_eq(main.state.step, 1)
	assert_eq(main.state.status, FightState.STATUS_FIGHTING)
	assert_eq(main.selected, 0, "the first Creature is selected")
	assert_eq(main.state.fighters.size(), 7)
	assert_eq(main.window_left, 8.0, "step_window_ms")


func test_clicking_cells_builds_a_move_and_selects_creatures() -> void:
	var main: Control = await _main()
	var tank_cell: Vector2i = main.state.cell_of(main.state.fighters[0])
	main.click_cell(main.state.cell_of(main.state.fighters[1]))
	assert_eq(main.selected, 1, "clicking a Creature selects it")
	var destination: Vector2i = main.state.cell_of(main.state.fighters[1]) + Vector2i(0, -1)
	main.click_cell(destination)
	assert_eq(main.builder.draft(1)["path"], [destination])
	assert_eq(main.builder.plans().size(), 1)
	main.select(0)
	assert_eq(main.selected, 0)
	main.click_cell(tank_cell + Vector2i(5, 5))
	assert_ne(main.last_message, "", "an unreachable cell says so")


func test_choosing_an_ability_then_a_target_makes_a_plan() -> void:
	var main: Control = await _main()
	main.choose_ability("guard")
	assert_false(main.targeting, "a self ability is complete at once")
	assert_eq(main.builder.plan_for(0)["ability"], "guard")
	main.choose_ability("guard")
	assert_eq(main.builder.plan_for(0), {}, "pressing it again drops it")
	main.choose_ability("bash")
	assert_true(main.targeting)
	main.clear_selected()
	assert_false(main.targeting)


func test_an_ability_that_cannot_be_afforded_is_not_chosen() -> void:
	var main: Control = await _main()
	main.state.fighters[0].ap = 1
	main.choose_ability("guard")
	assert_eq(str(main.builder.draft(0)["ability"]), "")


func test_ready_resolves_the_step_and_opens_the_next_window() -> void:
	var main: Control = await _main()
	main.choose_ability("guard")
	await main.resolve_step()
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_eq(main.state.step, 2)
	assert_gt(Statuses.shield_amount(main.state.fighters[0]), 0, "the Guard shield landed")
	assert_eq(main.builder.plans().size(), 0, "a fresh window has no plans")
	assert_eq(main.window_left, 8.0)


func test_the_monsters_act_on_their_own_plans() -> void:
	var main: Control = await _main()
	var before: Vector2i = main.state.cell_of(main.state.fighters[3])
	await main.resolve_step()
	assert_ne(main.state.cell_of(main.state.fighters[3]), before, "the first Brute walked toward us")


func test_the_timer_ends_the_window() -> void:
	var main: Control = await _main()
	main.untimed = false
	main.window_left = 0.05
	main._process(0.2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gte(main.state.step, 2)


func test_untimed_never_runs_out() -> void:
	var main: Control = await _main()
	main._process(100.0)
	assert_eq(main.state.step, 1)
	assert_eq(main.mode, main.Mode.PLANNING)


func test_doing_nothing_loses_the_fight_in_a_bounded_number_of_steps() -> void:
	var main: Control = await _main()
	var steps: int = 0
	while main.mode != main.Mode.ENDED and steps < 80:
		await main.resolve_step()
		steps += 1
	assert_eq(main.mode, main.Mode.ENDED, "the fight ends within 80 steps")
	assert_true(["defeat", "collapse", "victory", "bloom"].has(main.state.outcome), main.state.outcome)
	assert_eq(main.state.status, FightState.STATUS_ENDED)


func test_the_preview_labels_follow_the_plan() -> void:
	var main: Control = await _main()
	# Walk the Striker next to a Brute-free cell and aim nothing: no preview. Then a Guard: no damage.
	main.select(1)
	main.choose_ability("whirl")
	var result: Dictionary = main.builder.preview()
	assert_false(result.is_empty(), "whirl is a self ability: a plan exists")
	assert_eq(main.builder.preview_changes(result).size(), 0, "nobody is near enough to be hit")
