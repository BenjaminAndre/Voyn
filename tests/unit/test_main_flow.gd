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
	assert_eq(main.selected, -1, "no Creature is selected at the start of a window")
	assert_false(main.board._layers.has("reach"), "so no move range is shown yet")
	assert_eq(main.state.fighters.size(), 7)
	assert_eq(main.window_left, 16.0, "step_window_ms")


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
	main.click_cell(tank_cell + Vector2i(0, -6))
	assert_ne(main.last_message, "", "an unreachable cell says so")


func test_choosing_an_ability_then_a_target_makes_a_plan() -> void:
	var main: Control = await _main()
	main.select(0)
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
	main.select(0)
	main.state.fighters[0].ap = 1
	main.choose_ability("guard")
	assert_eq(str(main.builder.draft(0)["ability"]), "")


func test_ready_resolves_the_step_and_opens_the_next_window() -> void:
	var main: Control = await _main()
	main.select(0)
	main.choose_ability("guard")
	await main.resolve_step()
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_eq(main.state.step, 2)
	assert_gt(Statuses.shield_amount(main.state.fighters[0]), 0, "the Guard shield landed")
	assert_eq(main.builder.plans().size(), 0, "a fresh window has no plans")
	assert_eq(main.window_left, 16.0)


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


# --- T13b: fight end and restart ---


func _play_to_the_end(main: Control) -> void:
	var steps: int = 0
	while main.mode != main.Mode.ENDED and steps < 80:
		await main.resolve_step()
		steps += 1


func test_the_result_screen_shows_the_outcome_cleansed_and_board_karma() -> void:
	var main: Control = await _main()
	await _play_to_the_end(main)
	assert_eq(main.mode, main.Mode.ENDED)
	assert_true(main._end_panel.visible)
	assert_eq(main._end_title.text, "Defeat", "doing nothing loses")
	var details: String = main._end_details.text
	assert_string_contains(details, "Monsters Cleansed: 0/4")
	assert_string_contains(details, "Final board karma: %d" % main.state.board_karma())
	assert_string_contains(details, "Steps: %d" % main.state.step)


func test_result_details_count_the_cleansed_monsters() -> void:
	var main: Control = await _main()
	main.state.cleansed_count = 3
	assert_string_contains(main.result_details(), "Monsters Cleansed: 3/4")


func test_outcome_titles() -> void:
	var main: Control = await _main()
	assert_eq(main._outcome_title("victory"), "Victory")
	assert_eq(main._outcome_title("defeat"), "Defeat")
	assert_string_contains(main._outcome_title("bloom"), "Bloom")
	assert_string_contains(main._outcome_title("collapse"), "Collapse")


func test_restart_starts_a_fresh_fight() -> void:
	var main: Control = await _main()
	await _play_to_the_end(main)
	main.restart()
	main.board.animation_speed = 0.0
	assert_false(main._end_panel.visible)
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_eq(main.state.step, 1)
	assert_eq(main.state.status, FightState.STATUS_FIGHTING)
	assert_eq(main.state.cleansed_count, 0)
	for fighter: FighterState in main.state.fighters:
		assert_eq(fighter.hp, fighter.max_hp)
	assert_eq(main.state.board_karma(), -2, "the Arena starts unchanged")
	await main.resolve_step()
	assert_eq(main.state.step, 2, "and it plays")


func test_the_result_screen_is_hidden_while_playing() -> void:
	var main: Control = await _main()
	assert_false(main._end_panel.visible)


# --- Round 2, item 2.2: selection gives feedback ---


func test_selecting_a_creature_shows_its_move_range() -> void:
	var main: Control = await _main()
	assert_eq(main.selected, -1)
	main.select(1)
	assert_eq(main.selected, 1)
	assert_true(main.board._layers.has("reach"), "the blue cells appear when a Creature is selected")
	assert_eq((main.board._layers["reach"] as Node3D).get_child_count(), main.builder.reachable_cells(1).size())


func test_every_new_window_starts_with_nobody_selected() -> void:
	var main: Control = await _main()
	main.select(2)
	await main.resolve_step()
	assert_eq(main.selected, -1)
	assert_false(main.board._layers.has("reach"))


func test_nothing_can_be_planned_before_selecting() -> void:
	var main: Control = await _main()
	main.click_cell(main.state.cell_of(main.state.fighters[0]) + Vector2i(0, -1))
	assert_eq(main.builder.plans().size(), 0, "a click on an empty cell with nobody selected does nothing")
	main.choose_ability("bash")
	assert_eq(main.builder.plans().size(), 0)


# --- Round 2, item 2.4: never leave the UI stuck ---


func _hint(main: Control) -> String:
	return main._hint.text


func test_closing_the_window_while_aiming_cancels_the_aim() -> void:
	var main: Control = await _main()
	main.select(0)
	main.choose_ability("bash")
	assert_true(main.targeting)
	assert_string_contains(_hint(main), "aim at")
	await main.resolve_step()
	assert_false(main.targeting)
	assert_eq(main.selected, -1)
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_false(_hint(main).contains("aim at"), "no stale 'pick a cell to aim' in the next window")
	assert_eq(main.builder.plans().size(), 0)


func test_the_timer_closing_the_window_cancels_the_aim_too() -> void:
	var main: Control = await _main()
	main.untimed = false
	main.select(0)
	main.choose_ability("bash")
	main.window_left = 0.05
	main._process(0.2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(main.targeting)
	assert_false(_hint(main).contains("aim at"))


func test_pressing_ready_while_aiming_still_resolves_the_step() -> void:
	var main: Control = await _main()
	main.select(0)
	main.choose_ability("bash")
	await main.resolve_step()
	assert_eq(main.state.step, 2)


func test_an_error_message_does_not_survive_the_next_action_or_window() -> void:
	var main: Control = await _main()
	main.select(0)
	main.click_cell(main.state.cell_of(main.state.fighters[0]) + Vector2i(-3, -3))
	assert_ne(main.last_message, "", "an unreachable click explains itself")
	assert_eq(_hint(main), main.last_message)
	main.select(1)
	assert_eq(main.last_message, "")
	assert_false(_hint(main).contains("reach"))
	main.click_cell(main.state.cell_of(main.state.fighters[1]) + Vector2i(-4, -4))
	assert_ne(main.last_message, "")
	await main.resolve_step()
	assert_eq(main.last_message, "", "a new window starts clean")
	assert_false(_hint(main).contains("reach"))


func test_the_hint_follows_the_input_state() -> void:
	var main: Control = await _main()
	assert_string_contains(_hint(main), "Click a creature")
	main.select(0)
	assert_string_contains(_hint(main), "blue cell")
	main.choose_ability("bash")
	assert_string_contains(_hint(main), "aim at")
	main.clear_selected()
	assert_string_contains(_hint(main), "blue cell")
	main.choose_ability("guard")
	assert_false(main.targeting, "a self ability needs no aim")
	assert_string_contains(_hint(main), "blue cell")


func test_ending_the_fight_clears_aiming_and_the_hint() -> void:
	var main: Control = await _main()
	main.select(0)
	main.choose_ability("bash")
	main._end_fight()
	assert_false(main.targeting)
	assert_eq(main.selected, -1)
	assert_eq(_hint(main), "")


func _assert_input_invariants(main: Control, label: String) -> void:
	if main.targeting:
		assert_eq(main.mode, main.Mode.PLANNING, "%s: aiming only while planning" % label)
		assert_gte(main.selected, 0, "%s: aiming needs a selected Creature" % label)
		var entry: Dictionary = main.builder.drafts[main.selected]
		assert_ne(str(entry["ability"]), "", "%s: aiming needs a chosen ability" % label)
		assert_false(bool(entry["has_target"]), "%s: aiming means no target yet" % label)
	if main.mode != main.Mode.PLANNING:
		assert_false(main.targeting, "%s: no aiming outside a window" % label)
	if main.selected >= 0:
		assert_true(main.state.fighters[main.selected].on_board(), "%s: selected is on the board" % label)
	assert_false(main._hint.text.contains("aim at") and not main.targeting, "%s: no stale aiming hint" % label)


func test_input_state_invariants_hold_under_random_play() -> void:
	var main: Control = await _main()
	var prng: Prng = Prng.create(20261018)
	for i: int in 220:
		var label: String = "op %d" % i
		match prng.next_below(7):
			0:
				main.select(prng.next_below(3))
			1:
				if main.selected >= 0:
					var kit: PackedStringArray = main.state.fighters[main.selected].abilities
					main.choose_ability(kit[prng.next_below(kit.size())])
			2:
				main.click_cell(main.state.grid.cell_at(prng.next_below(main.state.grid.size())))
			3:
				main.set_order(prng.next_below(2) == 0)
			4:
				main.clear_selected()
			5:
				if prng.next_below(3) == 0:
					await main.resolve_step()
			6:
				if main.selected >= 0 and prng.next_below(2) == 0:
					main.click_cell(main.state.cell_of(main.state.fighters[prng.next_below(3)]))
		_assert_input_invariants(main, label)
		if main.mode == main.Mode.ENDED:
			break


# --- Round 2, item 2.5: the resolution log panel ---


func test_the_log_starts_empty_and_fills_as_a_step_plays() -> void:
	var main: Control = await _main()
	assert_string_contains(main._log_label.text, "appear here")
	await main.resolve_step()
	assert_string_contains(main._log_label.text, "Step 1")
	assert_string_contains(main._log_label.text, "Lead moves")
	assert_string_contains(main._log_label.text, "Upkeep")


func test_the_log_keeps_the_last_step_while_the_next_window_is_open() -> void:
	var main: Control = await _main()
	await main.resolve_step()
	assert_eq(main.mode, main.Mode.PLANNING)
	assert_string_contains(main._log_label.text, "Step 1", "still there in the next window")
	await main.resolve_step()
	assert_string_contains(main._log_label.text, "Step 2")
	assert_false(main._log_label.text.contains("Step 1"), "replaced when the next step plays")


func test_the_log_lists_what_the_monsters_did() -> void:
	var main: Control = await _main()
	await main.resolve_step()
	assert_string_contains(main._log_label.text, "moves", "the Monsters advanced")


func test_the_log_panel_can_be_collapsed_and_expanded() -> void:
	var main: Control = await _main()
	assert_true(main._log_label.visible)
	main._log_toggle.pressed.emit()
	assert_true(main.log_collapsed)
	assert_false(main._log_label.visible)
	assert_eq(main._log_toggle.text, "Log +")
	await main.resolve_step()
	assert_false(main._log_label.visible, "stays collapsed across steps")
	assert_string_contains(main.resolution_log.text(), "Step 1", "but it kept logging")
	main.set_log_collapsed(false)
	assert_true(main._log_label.visible)
	assert_eq(main._log_toggle.text, "Log -")


func test_restart_clears_the_log() -> void:
	var main: Control = await _main()
	await main.resolve_step()
	main.restart()
	main.board.animation_speed = 0.0
	assert_eq(main.resolution_log.entries.size(), 0)
	assert_string_contains(main._log_label.text, "appear here")


func test_the_log_is_built_from_the_event_stream_only() -> void:
	var main: Control = await _main()
	var events: Array = []
	main.board.event_played.connect(func(event: Dictionary) -> void: events.append(event))
	await main.resolve_step()
	var rebuilt: ResolutionLog = ResolutionLog.new()
	for event: Dictionary in events:
		rebuilt.add(event, main.state)
	assert_eq(main.resolution_log.text(), rebuilt.text())
