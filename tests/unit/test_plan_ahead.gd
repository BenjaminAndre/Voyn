extends GutTest
## Round 2, item 2.8 (GDD R3.3): plan at any time. While a step's resolution plays, the player can
## already plan the next step against the step's final state; those plans carry into the next
## window and are re-checked when it opens. The window still closes on time.


func _main() -> Control:
	var scene: Control = load("res://src/client/main.tscn").instantiate()
	add_child_autofree(scene)
	scene.untimed = true
	scene.board.animation_speed = 0.0
	await get_tree().process_frame
	return scene


## Runs `action` once, at the first event of the next resolution (the step is being played).
func _during_playback(main: Control, action: Callable) -> void:
	var done: Array[bool] = [false]
	main.board.event_played.connect(func(event: Dictionary) -> void:
		if not done[0] and event["type"] == "step_started":
			done[0] = true
			action.call())


func _tank_cell(main: Control) -> Vector2i:
	return main.state.cell_of(main.state.fighters[0])


func test_the_player_can_plan_while_the_step_plays_against_the_final_state() -> void:
	var main: Control = await _main()
	var seen: Dictionary = {}
	_during_playback(main, func() -> void:
		seen["mode"] = main.mode
		seen["step"] = main.state.step
		seen["builder_on_final"] = main.builder.state == main.state
		seen["board_on_final"] = main.board.state == main.state
		main.select(0)
		seen["selected"] = main.selected
		main.click_cell(_tank_cell(main) + Vector2i(0, -1))
		seen["plans"] = main.builder.plans().size())
	await main.resolve_step()
	assert_eq(seen["mode"], main.Mode.RESOLVING)
	assert_eq(seen["step"], 2, "the state already is the board of the next window")
	assert_true(seen["builder_on_final"])
	assert_true(seen["board_on_final"], "so clicking a figure picks its final cell")
	assert_eq(seen["selected"], 0)
	assert_eq(seen["plans"], 1)


func test_those_plans_carry_into_the_next_window_and_are_executed() -> void:
	var main: Control = await _main()
	var destination: Array[Vector2i] = [Vector2i.ZERO]
	_during_playback(main, func() -> void:
		destination[0] = _tank_cell(main) + Vector2i(0, -1)
		main.select(0)
		main.click_cell(destination[0]))
	await main.resolve_step()
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_eq(main.builder.plans().size(), 1, "the head start is still there")
	assert_eq(main.builder.plan_for(0)["move_path"], [[destination[0].x, destination[0].y]])
	assert_eq(main.selected, -1, "a new window still starts with nobody selected")
	assert_eq(main.window_left, 16.0, "and the window is not shortened by the head start")
	assert_eq(main.board._ghost_root.get_child_count(), 1, "the ghost is still shown")
	await main.resolve_step()
	assert_eq(_tank_cell(main), destination[0], "step 2 executed the plan made during step 1")


func test_an_ability_planned_during_playback_carries_over_too() -> void:
	var main: Control = await _main()
	_during_playback(main, func() -> void:
		main.select(0)
		main.choose_ability("guard"))
	await main.resolve_step()
	assert_eq(main.builder.plan_for(0)["ability"], "guard")
	await main.resolve_step()
	assert_gt(Statuses.shield_amount(main.state.fighters[0]), 0)


func test_the_plans_of_the_window_just_resolved_are_spent() -> void:
	var main: Control = await _main()
	main.select(0)
	main.click_cell(_tank_cell(main) + Vector2i(0, -1))
	await main.resolve_step()
	assert_eq(main.builder.plans().size(), 0, "not applied twice")


func test_nothing_can_be_planned_once_the_fight_has_ended() -> void:
	var main: Control = await _main()
	var tried_after_end: Array[bool] = [false]
	main.board.event_played.connect(func(_event: Dictionary) -> void:
		if main.state.status == FightState.STATUS_ENDED:
			tried_after_end[0] = true
			main.select(0)
			main.click_cell(Vector2i.ZERO)
			assert_eq(main.selected, -1, "no planning once the fight has ended")
			assert_eq(main.builder.plans().size(), 0))
	var steps: int = 0
	while main.mode != main.Mode.ENDED and steps < 80:
		await main.resolve_step()
		steps += 1
	assert_true(tried_after_end[0], "the last step's playback was checked")


func test_ready_and_space_do_nothing_while_the_step_plays() -> void:
	var main: Control = await _main()
	var seen: Dictionary = {}
	_during_playback(main, func() -> void:
		seen["ready_disabled"] = main._ready_button.disabled
		var space: InputEventKey = InputEventKey.new()
		space.keycode = KEY_SPACE
		space.pressed = true
		main._unhandled_input(space)
		seen["step_after_space"] = main.state.step
		main.resolve_step())
	await main.resolve_step()
	assert_true(seen["ready_disabled"])
	assert_eq(seen["step_after_space"], 2, "Space did not resolve another step")
	assert_eq(main.state.step, 2)


func test_escape_and_right_click_work_during_playback() -> void:
	var main: Control = await _main()
	var seen: Dictionary = {}
	_during_playback(main, func() -> void:
		main.select(0)
		main.choose_ability("bash")
		seen["aiming"] = main.targeting
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		main._unhandled_input(click)
		seen["after"] = main.targeting)
	await main.resolve_step()
	assert_true(seen["aiming"])
	assert_false(seen["after"])


func test_a_half_finished_aim_does_not_survive_into_the_next_window() -> void:
	var main: Control = await _main()
	_during_playback(main, func() -> void:
		main.select(0)
		main.choose_ability("bash"))
	await main.resolve_step()
	assert_false(main.targeting)
	assert_eq(main.selected, -1)
	assert_eq(main.builder.plans().size(), 0)
	assert_false(main._hint.text.contains("aim at"))


func test_a_plan_that_stopped_being_valid_is_dropped_when_the_window_opens() -> void:
	var main: Control = await _main()
	_during_playback(main, func() -> void:
		main.select(0)
		main.click_cell(_tank_cell(main) + Vector2i(0, -1))
		# Something changes the board before the window opens: the Creature is now rooted.
		main.state.fighters[0].statuses.append(TestFixtures.status("rooted")))
	await main.resolve_step()
	assert_eq(main.builder.plans().size(), 0, "re-validated and dropped, not carried into a plan that cannot run")


func test_the_window_still_closes_on_time_after_planning_ahead() -> void:
	var main: Control = await _main()
	var destination: Array[Vector2i] = [Vector2i.ZERO]
	_during_playback(main, func() -> void:
		destination[0] = _tank_cell(main) + Vector2i(0, -1)
		main.select(0)
		main.click_cell(destination[0]))
	await main.resolve_step()
	main.untimed = false
	main.window_left = 0.05
	main._process(0.2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gte(main.state.step, 3, "the timer resolved step 2")
	assert_eq(_tank_cell(main), destination[0])


func test_input_state_invariants_hold_for_random_actions_during_playback() -> void:
	var main: Control = await _main()
	var prng: Prng = Prng.create(77)
	var checked: Array[int] = [0]
	main.board.event_played.connect(func(_event: Dictionary) -> void:
		match prng.next_below(6):
			0:
				main.select(prng.next_below(3))
			1:
				if main.selected >= 0:
					var kit: PackedStringArray = main.state.fighters[main.selected].abilities
					main.choose_ability(kit[prng.next_below(kit.size())])
			2:
				main.click_cell(main.state.grid.cell_at(prng.next_below(main.state.grid.size())))
			3:
				main.choose_move()
			4:
				main.cancel_or_clear()
			5:
				main.clear_selected()
		checked[0] += 1
		assert_false(main.moving and main.targeting, "at most one aim")
		if main.targeting:
			assert_gte(main.selected, 0)
			var entry: Dictionary = main.builder.drafts[main.selected]
			assert_ne(str(entry["ability"]), "")
			assert_false(bool(entry["has_target"])))
	for i: int in 6:
		await main.resolve_step()
		if main.mode == main.Mode.ENDED:
			break
	assert_gt(checked[0], 40, "many events played with random planning going on")
