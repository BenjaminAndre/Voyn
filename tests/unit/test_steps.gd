extends GutTest
## T5: fight state, setup actions, the step scheduler, recharge, outcomes (GDD R2, R3), plan
## validation (R3.4) and defeats (R11.3).

const C0: Vector2i = Vector2i(-2, 0)
const C1: Vector2i = Vector2i(-1, 0)


func _duel(creature_overrides: Dictionary = {}, monster_overrides: Dictionary = {}) -> FightState:
	var roster: Array = [TestFixtures.creature(creature_overrides), TestFixtures.monster([3, 0], monster_overrides)]
	return TestFixtures.running(roster, [C0])


func _cell(state: FightState, id: int) -> Vector2i:
	return state.cell_of(state.fighters[id])


# --- Fight creation (R2, R3.1) ---


func test_R3_1_create_builds_a_fight_in_placement() -> void:
	var roster: Array = [
		TestFixtures.creature({"name": "a"}),
		TestFixtures.creature({"name": "b", "player": 1}),
		TestFixtures.monster([3, 0], {"name": "m"}),
	]
	var state: FightState = TestFixtures.create(roster)
	assert_eq(state.status, FightState.STATUS_PLACEMENT)
	assert_eq(state.step, 0)
	assert_eq(state.outcome, "")
	assert_eq(state.fighters.size(), 3)
	for i: int in 3:
		assert_eq(state.fighters[i].id, i, "fighter ID = roster index")
	assert_eq(state.fighters[0].cell, -1, "Creatures start unplaced")
	assert_eq(_cell(state, 2), Vector2i(3, 0), "Monsters spawn on their Encounter cell")
	assert_eq(state.occupant[state.grid.index_of(Vector2i(3, 0))], 2)
	assert_eq(state.fighters[0].ap, 6, "pools start full")
	assert_eq(state.fighters[0].mp, 3)
	assert_eq(state.fighters[0].hp, 100)


func test_R3_1_create_rejects_bad_data() -> void:
	var rules: Dictionary = TestFixtures.rules()
	var good: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0])]
	assert_false(RulesEngine.create({"radius": 0}, good, rules, 1)["ok"], "radius")
	var monster_first: Array = [TestFixtures.monster([3, 0]), TestFixtures.creature()]
	assert_false(RulesEngine.create(TestFixtures.arena(), monster_first, rules, 1)["ok"], "roster order")
	var no_recharge: Array = [TestFixtures.creature({"recharge_steps": 0}), TestFixtures.monster([3, 0])]
	assert_false(RulesEngine.create(TestFixtures.arena(), no_recharge, rules, 1)["ok"], "recharge_steps")
	var no_monster: Array = [TestFixtures.creature()]
	assert_false(RulesEngine.create(TestFixtures.arena(), no_monster, rules, 1)["ok"], "no monsters")
	var on_obstacle: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0])]
	assert_false(RulesEngine.create(TestFixtures.arena({"obstacles": [[3, 0]]}), on_obstacle, rules, 1)["ok"], "spawn on obstacle")
	var too_many: Array = [TestFixtures.creature(), TestFixtures.creature(), TestFixtures.monster([3, 0])]
	assert_false(RulesEngine.create(TestFixtures.arena({"creature_start_cells": [[-2, 0]]}), too_many, rules, 1)["ok"], "start cells")
	var stacked: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0]), TestFixtures.monster([3, 0])]
	assert_false(RulesEngine.create(TestFixtures.arena(), stacked, rules, 1)["ok"], "two monsters on a cell")


func test_R1_6_obstacles_and_karma_come_from_the_arena() -> void:
	var roster: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0])]
	var state: FightState = TestFixtures.create(roster, {"obstacles": [[1, 1]], "karma": [[0, 2, -2], [2, 0, 1]]})
	var obstacle: int = state.grid.index_of(Vector2i(1, 1))
	assert_eq(state.walkable[obstacle], 0)
	assert_eq(state.blocks_los[obstacle], 1)
	assert_eq(state.karma[state.grid.index_of(Vector2i(0, 2))], Land.BLIGHTED)
	assert_eq(state.karma[state.grid.index_of(Vector2i(2, 0))], Land.PURE)
	assert_eq(state.karma[state.grid.index_of(Vector2i(0, 0))], 0)


func test_clone_is_independent_and_shares_the_grid() -> void:
	var state: FightState = _duel()
	var copy: FightState = state.clone()
	assert_same(copy.grid, state.grid)
	copy.karma[0] = -2
	copy.fighters[0].hp = 1
	copy.set_position(copy.fighters[0], state.grid.index_of(Vector2i(0, 0)))
	copy.step = 9
	copy.prng.next_u32()
	assert_eq(state.karma[0], 0)
	assert_eq(state.fighters[0].hp, 100)
	assert_eq(_cell(state, 0), C0)
	assert_eq(state.occupant[state.grid.index_of(Vector2i(0, 0))], -1)
	assert_eq(state.step, 1)
	assert_ne(copy.prng.state, state.prng.state)


# --- Setup actions (R3.1) ---


func test_R3_1_place_puts_a_creature_on_a_start_cell() -> void:
	var state: FightState = TestFixtures.create([TestFixtures.creature(), TestFixtures.monster([3, 0])])
	var result: Dictionary = RulesEngine.place(state, 0, Vector2i(-3, 0))
	assert_true(result["ok"])
	var placed: FightState = result["state"]
	assert_eq(_cell(placed, 0), Vector2i(-3, 0))
	assert_eq(state.fighters[0].cell, -1, "input state unchanged")
	assert_eq(TestFixtures.event_types(result["events"]), ["placed"])
	assert_eq(result["events"][0]["phase"], "setup")
	assert_eq(result["events"][0]["step"], 0)
	var moved: Dictionary = RulesEngine.place(placed, 0, Vector2i(-2, 0))
	assert_true(moved["ok"], "can re-place before the fight")
	assert_eq(moved["state"].occupant[placed.grid.index_of(Vector2i(-3, 0))], -1)


func test_R3_1_place_rejects_bad_requests() -> void:
	var roster: Array = [TestFixtures.creature(), TestFixtures.creature({"player": 1}), TestFixtures.monster([3, 0])]
	var state: FightState = TestFixtures.create(roster)
	assert_false(RulesEngine.place(state, 0, Vector2i(0, 0))["ok"], "not a start cell")
	assert_false(RulesEngine.place(state, 2, Vector2i(-3, 0))["ok"], "Monsters are not placed")
	assert_false(RulesEngine.place(state, 7, Vector2i(-3, 0))["ok"], "unknown fighter")
	var first: FightState = RulesEngine.place(state, 0, Vector2i(-3, 0))["state"]
	assert_false(RulesEngine.place(first, 1, Vector2i(-3, 0))["ok"], "cell taken")
	var started: FightState = TestFixtures.start(first, [Vector2i(-3, 0), Vector2i(-2, 0)])
	assert_false(RulesEngine.place(started, 0, Vector2i(-2, 0))["ok"], "placement is over")


func test_R3_1_start_fight_needs_every_creature_placed() -> void:
	var state: FightState = TestFixtures.create([TestFixtures.creature(), TestFixtures.monster([3, 0])])
	var early: Dictionary = RulesEngine.start_fight(state)
	assert_false(early["ok"])
	assert_eq(early["errors"], ["creature_not_placed"])
	var placed: FightState = RulesEngine.place(state, 0, C0)["state"]
	var result: Dictionary = RulesEngine.start_fight(placed)
	assert_true(result["ok"])
	var running: FightState = result["state"]
	assert_eq(running.status, FightState.STATUS_FIGHTING)
	assert_eq(running.step, 1, "step 1 begins")
	assert_eq(TestFixtures.event_types(result["events"]), ["fight_started"])
	assert_eq(placed.status, FightState.STATUS_PLACEMENT, "input state unchanged")
	assert_false(RulesEngine.start_fight(running)["ok"], "cannot start twice")


# --- The step (R3.2, R3.6) ---


func test_R3_6_a_step_runs_the_phases_in_order() -> void:
	var result: Dictionary = TestFixtures.resolve(_duel(), [])
	assert_true(result["ok"])
	var expected: Array[String] = [
		"step_started", "phase_started", "phase_started", "phase_started",
		"phase_started", "phase_started", "phase_started", "land_phase",
	]
	assert_eq(TestFixtures.event_types(result["events"]), expected)
	var phases: Array[String] = []
	for event: Dictionary in TestFixtures.of_type(result["events"], "phase_started"):
		phases.append(str(event["name"]))
		assert_eq(event["phase"], event["name"], "stamped with its own phase")
		assert_eq(event["step"], 1)
	assert_eq(phases, ["lead_move", "prep", "dash", "strike", "trail_move", "upkeep"])
	assert_eq(result["events"][0]["step"], 1)


func test_R3_2_the_step_counter_advances_and_the_input_is_untouched() -> void:
	var state: FightState = _duel()
	var after: FightState = TestFixtures.resolve(state, [])["state"]
	assert_eq(after.step, 2)
	assert_eq(state.step, 1)
	var third: FightState = TestFixtures.resolve(after, [])["state"]
	assert_eq(third.step, 3)


func test_resolve_step_is_deterministic() -> void:
	var plans: Array = [TestFixtures.move(0, [[-1, 0], [0, 0]])]
	var a: Dictionary = TestFixtures.resolve(_duel(), plans)
	var b: Dictionary = TestFixtures.resolve(_duel(), plans)
	assert_eq(a["events"], b["events"])


func test_resolve_step_refuses_a_fight_that_is_not_running() -> void:
	var placing: FightState = TestFixtures.create([TestFixtures.creature(), TestFixtures.monster([3, 0])])
	var result: Dictionary = TestFixtures.resolve(placing, [])
	assert_false(result["ok"])
	assert_eq(result["errors"], ["not_fighting"])
	var ended: FightState = RulesEngine.forfeit(_duel())["state"]
	assert_false(TestFixtures.resolve(ended, [])["ok"])


func test_malformed_plans_are_errors_and_change_nothing() -> void:
	var state: FightState = _duel()
	var bad_plans: Array = [
		"nope",
		{},
		{"fighter": "0"},
		{"fighter": 9},
		{"fighter": 0, "order": "sideways"},
		{"fighter": 0, "ability": 5},
		{"fighter": 0, "ability": "smash"},
		{"fighter": 0, "target_cell": [1]},
		{"fighter": 0, "move_path": [[9, 9]]},
		{"fighter": 0, "move_path": [[-2, 2]]},
		{"fighter": 0, "move_path": [[-1, 0], [-2, 0]]},
		{"fighter": 0, "move_path": [[-1, 0], [-1, 0]]},
		{"fighter": 0, "move_path": "east"},
		{"fighter": 0, "colour": "red"},
		{"keeper": 0, "interaction": "purify"},
	]
	for plan: Variant in bad_plans:
		var result: Dictionary = RulesEngine.resolve_step(state, [plan])
		assert_false(result["ok"], "rejects %s" % str(plan))
		assert_same(result["state"], state, "state unchanged")
		assert_true((result["events"] as Array).is_empty())
		assert_false((result["errors"] as Array).is_empty())


func test_two_plans_for_one_fighter_are_an_error() -> void:
	var plans: Array = [TestFixtures.move(0, [[-1, 0]]), TestFixtures.move(0, [[-2, 1]])]
	var result: Dictionary = TestFixtures.resolve(_duel(), plans)
	assert_false(result["ok"])
	assert_string_contains(str(result["errors"]), "duplicate_plan")


func test_a_defeated_fighter_cannot_be_planned() -> void:
	var state: FightState = _duel()
	var events: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[0], events)
	var result: Dictionary = TestFixtures.resolve(state, [{"fighter": 0}])
	assert_false(result["ok"])
	assert_string_contains(str(result["errors"]), "fighter_not_active")


func test_a_fighter_with_no_plan_waits() -> void:
	var state: FightState = _duel()
	var after: FightState = TestFixtures.resolve(state, [])["state"]
	assert_eq(_cell(after, 0), C0)
	assert_eq(after.fighters[0].mp, 3)


# --- Recharge (R3.5) ---


func test_R3_5_a_pool_refills_every_recharge_steps_from_fight_start() -> void:
	var state: FightState = _duel({"recharge_steps": 3, "max_mp": 3})
	var result: Dictionary = TestFixtures.resolve(state, [TestFixtures.move(0, [[-1, 0], [0, 0], [1, 0]])])
	var s2: FightState = result["state"]
	assert_eq(s2.fighters[0].mp, 0, "step 1 spent every MP")
	assert_eq(TestFixtures.of_type(result["events"], "refilled").size(), 0)
	var r2: Dictionary = TestFixtures.resolve(s2, [])
	assert_eq(r2["state"].fighters[0].mp, 0, "step 2: no refill")
	assert_eq(TestFixtures.of_type(r2["events"], "refilled").size(), 0)
	var r3: Dictionary = TestFixtures.resolve(r2["state"], [])
	var refills: Array[Dictionary] = TestFixtures.of_type(r3["events"], "refilled")
	assert_eq(refills.size(), 1, "step 3: refill (the Monster, at recharge 1, was already full)")
	assert_eq(refills[0]["fighter"], 0)
	assert_eq(refills[0]["mp"], 3)
	assert_eq(r3["state"].fighters[0].mp, 3)


func test_R3_5_recharge_counts_from_fight_start_every_n_steps() -> void:
	var state: FightState = _duel({"recharge_steps": 2, "max_ap": 4})
	state.fighters[0].ap = 1
	var refilled_at: Array[int] = []
	var current: FightState = state
	for i: int in 6:
		var result: Dictionary = TestFixtures.resolve(current, [])
		current = result["state"]
		for event: Dictionary in TestFixtures.of_type(result["events"], "refilled"):
			if event["fighter"] == 0:
				refilled_at.append(i + 1)
		current.fighters[0].ap = 1  # spend again so the next refill is visible
	assert_eq(refilled_at, [2, 4, 6])


func test_R3_5_a_refill_never_overflows_and_a_full_pool_emits_nothing() -> void:
	var state: FightState = _duel({"max_ap": 5, "max_mp": 3})
	for i: int in 3:
		var result: Dictionary = TestFixtures.resolve(state, [])
		state = result["state"]
		assert_eq(TestFixtures.of_type(result["events"], "refilled").size(), 0)
		assert_eq(state.fighters[0].ap, 5)
		assert_eq(state.fighters[0].mp, 3)


func test_R3_5_unspent_points_carry_over_until_the_refill() -> void:
	var state: FightState = _duel({"recharge_steps": 4, "max_mp": 3})
	state = TestFixtures.resolve(state, [TestFixtures.move(0, [[-1, 0]])])["state"]
	assert_eq(state.fighters[0].mp, 2)
	state = TestFixtures.resolve(state, [])["state"]
	assert_eq(state.fighters[0].mp, 2, "kept, not lost")


# --- Outcomes (R3.8) ---


func test_R3_8_no_monster_left_is_victory_and_skips_the_rest_of_the_step() -> void:
	var state: FightState = _duel()
	var scratch: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[1], scratch)
	var result: Dictionary = TestFixtures.resolve(state, [])
	assert_true(result["ok"])
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_eq(types, ["step_started", "phase_started", "fight_ended"])
	assert_eq(result["events"][2]["outcome"], "victory")
	assert_eq(result["state"].status, FightState.STATUS_ENDED)
	assert_eq(result["state"].outcome, "victory")
	assert_eq(result["state"].step, 1, "the step did not finish")


func test_R3_8_no_creature_left_is_defeat() -> void:
	var state: FightState = _duel()
	var scratch: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[0], scratch)
	var result: Dictionary = TestFixtures.resolve(state, [])
	assert_eq(result["state"].outcome, "defeat")


func test_R3_8_both_sides_gone_at_once_is_victory_first() -> void:
	var state: FightState = _duel()
	var scratch: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[0], scratch)
	Defeat.apply(state, state.fighters[1], scratch)
	var events: Array[Dictionary] = []
	assert_true(Scheduler.check_outcome(state, events))
	assert_eq(state.outcome, "victory", "'no Monster left' is listed before 'no Creature left'")


func test_R3_8_the_fight_goes_on_while_both_sides_have_fighters() -> void:
	var events: Array[Dictionary] = []
	assert_false(Scheduler.check_outcome(_duel(), events))
	assert_true(events.is_empty())


func test_R3_8_forfeit_ends_the_fight_as_a_defeat() -> void:
	var state: FightState = _duel()
	var result: Dictionary = RulesEngine.forfeit(state)
	assert_true(result["ok"])
	assert_eq(result["state"].status, FightState.STATUS_ENDED)
	assert_eq(result["state"].outcome, "defeat")
	assert_eq(result["events"], [{"type": "fight_ended", "outcome": "defeat", "step": 1, "phase": "setup"}])
	assert_eq(state.status, FightState.STATUS_FIGHTING, "input state unchanged")
	assert_false(RulesEngine.forfeit(result["state"])["ok"], "already over")
	var placing: FightState = TestFixtures.create([TestFixtures.creature(), TestFixtures.monster([3, 0])])
	assert_true(RulesEngine.forfeit(placing)["ok"], "can forfeit during placement")


# --- Defeats (R7.4, R11.3) ---


func test_R11_3_a_downed_creature_blights_its_cell_and_leaves_the_board() -> void:
	var state: FightState = _duel()
	var events: Array[Dictionary] = []
	var home: int = state.fighters[0].cell
	Defeat.apply(state, state.fighters[0], events)
	assert_false(state.fighters[0].alive)
	assert_eq(state.fighters[0].hp, 0)
	assert_eq(state.fighters[0].cell, -1)
	assert_eq(state.occupant[home], -1)
	assert_eq(state.karma[home], Land.BLIGHTED)
	assert_eq(events, [
		{"type": "defeated", "fighter": 0, "how": "downed"},
		{"type": "karma_changed", "cell": [-2, 0], "from": 0, "to": -2},
	])


func test_R11_3_a_monster_on_neutral_ground_is_killed() -> void:
	var state: FightState = _duel()
	var events: Array[Dictionary] = []
	var home: int = state.fighters[1].cell
	Defeat.apply(state, state.fighters[1], events)
	assert_eq(events[0], {"type": "defeated", "fighter": 1, "how": "killed"})
	assert_eq(state.karma[home], Land.BLIGHTED)
	assert_eq(state.cleansed_count, 0)


func test_R11_3_a_monster_on_pure_ground_is_cleansed_and_renewal_spreads() -> void:
	var roster: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0])]
	var state: FightState = TestFixtures.running(roster, [C0], {"karma": [[3, 0, 1], [2, 0, 2], [3, -1, -2]]})
	var events: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[1], events)
	assert_eq(events[0], {"type": "defeated", "fighter": 1, "how": "cleansed"})
	assert_eq(state.cleansed_count, 1)
	assert_eq(state.karma[state.grid.index_of(Vector2i(3, 0))], Land.THRIVING, "its cell +1")
	assert_eq(state.karma[state.grid.index_of(Vector2i(2, 0))], Land.THRIVING, "clamped at +2")
	assert_eq(state.karma[state.grid.index_of(Vector2i(3, -1))], Land.CORRUPTED, "neighbors +1")
	assert_eq(state.karma[state.grid.index_of(Vector2i(4, -1))], Land.PURE, "neutral neighbor +1")
	var cells: Array[Vector2i] = []
	for event: Dictionary in TestFixtures.of_type(events, "karma_changed"):
		cells.append(Vector2i(int(event["cell"][0]), int(event["cell"][1])))
	for i: int in range(1, cells.size()):
		assert_true(Hex.cell_less(cells[i - 1], cells[i]), "karma_changed events follow cell order")


func test_R11_3_defeat_is_applied_once() -> void:
	var state: FightState = _duel()
	var events: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[1], events)
	var count: int = events.size()
	Defeat.apply(state, state.fighters[1], events)
	assert_eq(events.size(), count)


# --- Plan validation (R3.4) ---


func _valid(state: FightState, plan: Dictionary, player: int = -1) -> Dictionary:
	return RulesEngine.validate_plan(state, TestFixtures.with_from(state, plan), player)


func test_R3_4_a_good_move_plan_validates() -> void:
	var result: Dictionary = _valid(_duel(), TestFixtures.move(0, [[-1, 0], [0, 0]]))
	assert_true(result["ok"], str(result["errors"]))
	assert_true(_valid(_duel(), {"fighter": 0})["ok"], "waiting is a plan")


func test_R3_4_validate_plan_needs_a_running_fight() -> void:
	var placing: FightState = TestFixtures.create([TestFixtures.creature(), TestFixtures.monster([3, 0])])
	assert_eq(RulesEngine.validate_plan(placing, {"fighter": 0})["errors"], ["not_fighting"])


func test_R3_4_validate_plan_reports_path_problems_with_stable_codes() -> void:
	var state: FightState = _duel({"max_mp": 2})
	assert_true((_valid(state, TestFixtures.move(0, [[-1, 0], [0, 0], [1, 0]]))["errors"] as Array).has("path_too_long"))
	var gap: Dictionary = _valid(state, TestFixtures.move(0, [[0, 0]]))
	assert_true((gap["errors"] as Array).has("path_not_contiguous"), "must start next to the fighter")
	var stationary: FightState = _duel({"traits": ["stationary"]})
	assert_true((_valid(stationary, TestFixtures.move(0, [[-1, 0]]))["errors"] as Array).has("cannot_move"))
	var rooted: FightState = _duel()
	rooted.fighters[0].statuses.append(TestFixtures.status("rooted"))
	assert_true((_valid(rooted, TestFixtures.move(0, [[-1, 0]]))["errors"] as Array).has("cannot_move"))
	var walled: FightState = TestFixtures.running(
		[TestFixtures.creature(), TestFixtures.monster([3, 0])], [C0], {"obstacles": [[-1, 0]]})
	assert_true((_valid(walled, TestFixtures.move(0, [[-1, 0]]))["errors"] as Array).has("cell_not_walkable"))


func test_R3_4_the_path_may_cross_cells_occupied_now() -> void:
	# Occupants may leave; Engagement and blocking are settled at resolution (R4.8).
	var roster: Array = [
		TestFixtures.creature({"name": "mover"}),
		TestFixtures.creature({"name": "ally", "player": 1}),
		TestFixtures.monster([0, 0]),
	]
	var state: FightState = TestFixtures.running(roster, [C0, C1])
	var through: Dictionary = TestFixtures.move(0, [[-1, 0], [0, 0]])
	assert_true(_valid(state, through)["ok"], "through an ally and an enemy")


func test_R3_4_the_path_costs_one_mp_per_cell_whatever_the_engagement() -> void:
	var state: FightState = TestFixtures.running(
		[TestFixtures.creature({"max_mp": 2}), TestFixtures.monster([-1, 0])], [C0])
	var plan: Dictionary = TestFixtures.move(0, [[-2, 1], [-2, 2]])
	assert_true(_valid(state, plan)["ok"], "engaged, but 2 cells <= 2 MP")


func test_R3_4_validate_plan_can_check_whose_fighter_it_is() -> void:
	var state: FightState = _duel()
	assert_true(_valid(state, {"fighter": 0}, 0)["ok"])
	assert_true((_valid(state, {"fighter": 0}, 1)["errors"] as Array).has("not_your_fighter"))


func test_R3_4_a_plan_that_moves_needs_a_current_from_cell() -> void:
	var state: FightState = _duel()
	var missing: Dictionary = RulesEngine.validate_plan(state, TestFixtures.move(0, [[-1, 0]]))
	assert_true((missing["errors"] as Array).has("missing_from_cell"))
	var stale: Dictionary = TestFixtures.move(0, [[-1, 0]])
	stale["from_cell"] = [0, 0]
	assert_true((RulesEngine.validate_plan(state, stale)["errors"] as Array).has("stale_from_cell"))
	var bad: Dictionary = TestFixtures.move(0, [[-1, 0]])
	bad["from_cell"] = "here"
	assert_true((RulesEngine.validate_plan(state, bad)["errors"] as Array).has("bad_from_cell"))
	assert_false(RulesEngine.resolve_step(state, [stale])["ok"], "resolve_step refuses a stale plan too")


func test_R3_6_a_trail_move_is_cancelled_if_the_fighter_left_its_planned_cell() -> void:
	# Displacement (T9) moves fighters in Dash; simulate it by moving the fighter after planning.
	var state: FightState = _duel()
	var plan: Dictionary = TestFixtures.with_from(state, TestFixtures.move(0, [[-1, 0]], "ability_first"))
	var moved_by_dash: FightState = state.clone()
	moved_by_dash.set_position(moved_by_dash.fighters[0], moved_by_dash.grid.index_of(Vector2i(-2, 1)))
	var events: Array[Dictionary] = []
	var moves: Array[Dictionary] = Scheduler.phase_moves(moved_by_dash, [plan], false, events)
	assert_true(moves.is_empty())
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "move_blocked")
	assert_eq(events[0]["reason"], "displaced")
	assert_eq(events[0]["at"], [-2, 1])
	assert_eq(events[0]["wanted"], [-1, 0])
	var untouched: Array[Dictionary] = []
	assert_eq(Scheduler.phase_moves(state, [plan], false, untouched).size(), 1, "still on its cell: it moves")
