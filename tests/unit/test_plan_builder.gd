extends GutTest
## T13: PlanBuilder, the client logic that turns clicks into plans and previews them.

const FAR: Array = [4, -4]


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


## One Creature (id 0) with Tank-like abilities at (0,0), a Monster (id 1) at (3,0), another far.
func _setup(monster_cell: Array = [3, 0], monster_hp: int = 100) -> FightState:
	var roster: Array = [
		TestFixtures.creature({"abilities": ["bash", "shove", "guard", "shot", "seed"], "recharge_steps": 10, "name": "PH Tank"}),
		TestFixtures.monster(monster_cell, {"max_hp": monster_hp}),
		TestFixtures.monster(FAR),
	]
	return TestFixtures.running(roster, [_v(0, 0)], {}, 1, {"land_phase_every_steps": 1000})


func _builder(state: FightState) -> PlanBuilder:
	var builder: PlanBuilder = PlanBuilder.new()
	builder.reset(state)
	return builder


# --- Moving ---


func test_set_path_to_uses_the_default_path() -> void:
	var builder: PlanBuilder = _builder(_setup())
	assert_true(builder.set_path_to(0, _v(2, 0)))
	var path: Array = builder.draft(0)["path"]
	assert_eq(path, [_v(1, 0), _v(2, 0)])
	assert_eq(builder.plan_for(0)["move_path"], [[1, 0], [2, 0]])


func test_an_unreachable_cell_is_refused_and_the_own_cell_clears_the_move() -> void:
	var builder: PlanBuilder = _builder(_setup())
	assert_false(builder.set_path_to(0, _v(-4, 4)), "out of MP")
	assert_true(builder.set_path_to(0, _v(1, 0)))
	assert_true(builder.set_path_to(0, _v(0, 0)))
	assert_eq(builder.plan_for(0), {}, "nothing planned")


func test_reachable_cells_come_from_the_engine() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	assert_eq(builder.reachable_cells(0).size(), 36, "a radius-3 disk (37 cells) without the Monster's cell")


# --- Abilities and targets ---


func test_choosing_an_ability_needs_a_valid_target() -> void:
	var builder: PlanBuilder = _builder(_setup([1, 0]))
	builder.set_ability(0, "bash")
	assert_false(builder.draft(0)["has_target"])
	assert_eq(builder.plan_for(0), {}, "no target yet: nothing to plan")
	assert_false(builder.set_target(0, _v(0, 1)), "no enemy there")
	assert_true(builder.set_target(0, _v(1, 0)))
	var plan: Dictionary = builder.plan_for(0)
	assert_eq(plan["ability"], "bash")
	assert_eq(plan["target_cell"], [1, 0])
	assert_eq(plan["from_cell"], [0, 0])


func test_a_self_ability_needs_no_target() -> void:
	var builder: PlanBuilder = _builder(_setup())
	builder.set_ability(0, "guard")
	assert_true(builder.draft(0)["has_target"])
	assert_eq(builder.plan_for(0)["ability"], "guard")
	assert_true(builder.validation(0)["ok"])


func test_targets_are_checked_from_the_cell_the_plan_moves_to() -> void:
	var state: FightState = _setup([3, 0])
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "bash")
	assert_eq(builder.target_cells(0).size(), 0, "nothing adjacent to (0,0)")
	builder.set_path_to(0, _v(2, 0))
	assert_eq(builder.planned_cell(0), state.grid.index_of(_v(2, 0)), "the Move was set first, so the zone follows it")
	assert_eq(builder.target_cells(0), PackedInt32Array([state.grid.index_of(_v(3, 0))]))


func test_the_plan_order_is_the_order_the_slots_were_filled() -> void:
	var state: FightState = _setup([3, 0])
	var move_first: PlanBuilder = _builder(state)
	move_first.set_path_to(0, _v(2, 0))
	move_first.set_ability(0, "bash")
	assert_true(move_first.set_target(0, _v(3, 0)))
	assert_eq(move_first.plan_for(0)["order"], "move_first", "close in and strike")
	var ability_first: PlanBuilder = _builder(state)
	ability_first.set_ability(0, "shot")
	assert_true(ability_first.set_target(0, _v(3, 0)))
	ability_first.set_path_to(0, _v(-1, 0))
	assert_eq(ability_first.plan_for(0)["order"], "ability_first", "hit and run")
	assert_eq(ability_first.planned_cell(0), state.grid.index_of(_v(0, 0)), "the ability is used from where it stands now")
	assert_true(ability_first.validation(0)["ok"], str(ability_first.validation(0)["errors"]))


func test_the_zones_do_not_depend_on_the_order() -> void:
	var state: FightState = _setup([3, 0])
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "shot")
	builder.set_target(0, _v(3, 0))
	var before: Array[int] = builder.reachable_cells(0)
	builder.set_path_to(0, _v(-1, 0))
	assert_eq(builder.reachable_cells(0), before, "the Move zone is always from where it stands now")


func test_choosing_a_slot_again_replaces_it_and_keeps_its_place_in_the_order() -> void:
	var state: FightState = _setup([3, 0])
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "shot")
	builder.set_target(0, _v(3, 0))
	builder.set_path_to(0, _v(-1, 0))
	assert_eq(builder.draft(0)["order"], "ability_first")
	builder.set_path_to(0, _v(0, -1))
	assert_eq(builder.draft(0)["path"], [_v(0, -1)], "the Move was replaced")
	assert_eq(builder.draft(0)["order"], "ability_first", "and it kept its place")
	builder.set_ability(0, "shot")
	assert_eq(builder.draft(0)["order"], "ability_first", "re-picking the ability keeps its place too")
	builder.set_target(0, _v(3, 0))
	assert_eq(builder.draft(0)["slots"], ["ability", "move"])


func test_clearing_a_slot_removes_it_from_the_order() -> void:
	var builder: PlanBuilder = _builder(_setup([3, 0]))
	builder.set_ability(0, "shot")
	builder.set_target(0, _v(3, 0))
	builder.set_path_to(0, _v(-1, 0))
	builder.set_path_to(0, _v(0, 0))
	assert_eq(builder.draft(0)["path"], [], "choosing the own cell clears the Move")
	assert_eq(builder.draft(0)["slots"], ["ability"])
	assert_eq(builder.plan_for(0)["ability"], "shot")


func test_cancelling_an_unaimed_ability_drops_it() -> void:
	var builder: PlanBuilder = _builder(_setup([3, 0]))
	builder.set_ability(0, "bash")
	builder.cancel_pending_ability(0)
	assert_eq(str(builder.draft(0)["ability"]), "")
	builder.set_ability(0, "guard")
	builder.cancel_pending_ability(0)
	assert_eq(builder.plan_for(0)["ability"], "guard", "an aimed (self) ability stays")


func test_move_availability() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	assert_eq(builder.move_unavailable_reason(0), "")
	state.fighters[0].mp = 0
	assert_eq(builder.move_unavailable_reason(0), "no MP")
	state.fighters[0].mp = 3
	state.fighters[0].statuses.append(TestFixtures.status("rooted"))
	assert_eq(builder.move_unavailable_reason(0), "rooted")


func test_changing_the_move_forgets_a_target_that_is_no_longer_valid() -> void:
	var builder: PlanBuilder = _builder(_setup([3, 0]))
	builder.set_path_to(0, _v(2, 0))
	builder.set_ability(0, "bash")
	assert_true(builder.set_target(0, _v(3, 0)))
	builder.set_path_to(0, _v(1, 0))
	assert_false(builder.draft(0)["has_target"], "(3,0) is out of range from (1,0)")
	builder.set_path_to(0, _v(2, 0))
	assert_true(builder.set_target(0, _v(3, 0)))


func test_area_cells_show_what_an_ability_would_affect() -> void:
	var state: FightState = _setup([1, 0])
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "guard")
	assert_eq(builder.area_cells(0, _v(0, 0)).size(), 7, "burst(1)")
	builder.set_ability(0, "seed")
	assert_eq(builder.area_cells(0, _v(3, 0)).size(), 7)


func test_unavailable_reasons() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	assert_eq(builder.unavailable_reason(0, "bash"), "")
	state.fighters[0].ap = 2
	assert_eq(builder.unavailable_reason(0, "bash"), "not enough AP")
	state.fighters[0].ap = 6
	state.fighters[0].cooldowns["guard"] = 3
	assert_eq(builder.unavailable_reason(0, "guard"), "ready in step 3")


# --- Plans, validation and the preview ---


func test_plans_lists_valid_plans_in_roster_order() -> void:
	var roster: Array = [
		TestFixtures.creature({"abilities": ["bash"], "recharge_steps": 10}),
		TestFixtures.creature({"abilities": ["bash"], "recharge_steps": 10, "player": 1}),
		TestFixtures.monster([2, 2]),
	]
	var state: FightState = TestFixtures.running(roster, [_v(0, 0), _v(-1, 0)], {}, 1, {"land_phase_every_steps": 1000})
	var builder: PlanBuilder = _builder(state)
	builder.set_path_to(1, _v(-2, 0))
	builder.set_path_to(0, _v(1, 0))
	var ids: Array[int] = []
	for plan: Dictionary in builder.plans():
		ids.append(int(plan["fighter"]))
	assert_eq(ids, [0, 1])


func test_a_draft_that_became_invalid_is_dropped_from_plans() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	builder.set_path_to(0, _v(1, 0))
	assert_eq(builder.plans().size(), 1)
	state.fighters[0].statuses.append(TestFixtures.status("rooted"))
	assert_false(builder.validation(0)["ok"])
	assert_eq(builder.plans().size(), 0)


func test_the_preview_runs_the_real_resolution_with_only_our_plans() -> void:
	var state: FightState = _setup([1, 0])
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "bash")
	builder.set_target(0, _v(1, 0))
	var result: Dictionary = builder.preview()
	assert_true(result["ok"])
	var changes: Dictionary = builder.preview_changes(result)
	assert_eq(changes.keys(), [1], "only the Monster is hit")
	assert_eq(changes[1]["delta"], -18)
	assert_eq(changes[1]["note"], "")
	assert_eq(state.fighters[1].hp, 100, "the real state is untouched")


func test_the_preview_marks_a_final_blow() -> void:
	var state: FightState = _setup([1, 0], 10)
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "bash")
	builder.set_target(0, _v(1, 0))
	var changes: Dictionary = builder.preview_changes(builder.preview())
	assert_eq(changes[1]["note"], "Killed")
	var pure: FightState = TestFixtures.running(
		[TestFixtures.creature({"abilities": ["bash"], "recharge_steps": 10}), TestFixtures.monster([1, 0], {"max_hp": 10}), TestFixtures.monster(FAR)],
		[_v(0, 0)], {"karma": [[1, 0, 1]]}, 1, {"land_phase_every_steps": 1000})
	var cleanse: PlanBuilder = _builder(pure)
	cleanse.set_ability(0, "bash")
	cleanse.set_target(0, _v(1, 0))
	assert_eq(cleanse.preview_changes(cleanse.preview())[1]["note"], "Cleansed")


func test_an_empty_draft_has_no_preview() -> void:
	var builder: PlanBuilder = _builder(_setup())
	assert_eq(builder.preview(), {})
	assert_eq(builder.preview_changes({}), {})


func test_summaries_read_in_plain_words() -> void:
	var builder: PlanBuilder = _builder(_setup([3, 0]))
	assert_eq(builder.summary(0), "waits")
	builder.set_path_to(0, _v(2, 0))
	assert_eq(builder.summary(0), "move 2")
	builder.set_ability(0, "bash")
	assert_string_contains(builder.summary(0), "pick a target")
	builder.set_target(0, _v(3, 0))
	assert_eq(builder.summary(0), "move 2 then Bash".replace("Bash", "bash"))


func test_clear_removes_a_draft() -> void:
	var builder: PlanBuilder = _builder(_setup())
	builder.set_path_to(0, _v(1, 0))
	builder.clear(0)
	assert_eq(builder.plans().size(), 0)
	builder.set_path_to(0, _v(1, 0))
	builder.clear_all()
	assert_eq(builder.plans().size(), 0)


# --- Round 2, item 2.8: rebase onto the next window's board ---


func test_rebase_keeps_valid_drafts_and_points_at_the_new_state() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	builder.set_path_to(0, _v(1, 0))
	var next: FightState = state.clone()
	builder.rebase(next)
	assert_same(builder.state, next)
	assert_eq(builder.plans().size(), 1)


func test_rebase_drops_a_plan_that_no_longer_validates() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	builder.set_path_to(0, _v(1, 0))
	var next: FightState = state.clone()
	next.fighters[0].statuses.append(TestFixtures.status("rooted"))
	builder.rebase(next)
	assert_eq(builder.plans().size(), 0)
	assert_false(builder.drafts.has(0))


func test_rebase_drops_drafts_of_creatures_that_left_the_board_and_unfinished_aims() -> void:
	var state: FightState = _setup()
	var builder: PlanBuilder = _builder(state)
	builder.set_path_to(0, _v(1, 0))
	var next: FightState = state.clone()
	var scratch: Array[Dictionary] = []
	Defeat.apply(next, next.fighters[0], scratch)
	builder.rebase(next)
	assert_false(builder.drafts.has(0))
	var again: PlanBuilder = _builder(state)
	again.set_ability(0, "bash")
	again.rebase(state.clone())
	assert_false(again.drafts.has(0), "an unaimed ability is cancelled, leaving an empty draft that is dropped")


func test_rebase_drops_an_ability_target_that_is_no_longer_valid() -> void:
	var state: FightState = _setup([1, 0])
	var builder: PlanBuilder = _builder(state)
	builder.set_ability(0, "bash")
	builder.set_target(0, _v(1, 0))
	var next: FightState = state.clone()
	next.set_position(next.fighters[1], next.grid.index_of(_v(3, 0)))
	builder.rebase(next)
	assert_eq(builder.plans().size(), 0, "the Monster is no longer there to hit")
