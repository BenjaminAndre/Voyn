extends GutTest
## T6: movement (GDD R4): costs, Engagement, blight on entry, simultaneous lockstep resolution
## (R4.8: conflicts, swaps, cycles, follow-the-leader), and the `reachable` query with default paths.

const FAR: Array = [4, -4]  # a Monster spawn far from every scenario


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


## Creatures first (one per cell, player = index), then the given Monsters.
func _fight(creature_cells: Array[Vector2i], monsters: Array = [], arena: Dictionary = {}, overrides: Dictionary = {}) -> FightState:
	var roster: Array = []
	for i: int in creature_cells.size():
		# Slow recharge, so spent MP is still visible after the step's Upkeep (R3.5).
		var entry: Dictionary = {"player": i, "name": "c%d" % i, "recharge_steps": 10}
		entry.merge(overrides, true)
		roster.append(TestFixtures.creature(entry))
	if monsters.is_empty():
		roster.append(TestFixtures.monster(FAR))
	for monster: Dictionary in monsters:
		roster.append(monster)
	return TestFixtures.running(roster, creature_cells, arena)


func _step(state: FightState, plans: Array) -> Dictionary:
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_true(result["ok"], str(result["errors"]))
	return result


func _cell(state: FightState, id: int) -> Vector2i:
	return state.cell_of(state.fighters[id])


func _reasons(events: Array) -> Dictionary:
	var reasons: Dictionary = {}
	for event: Dictionary in TestFixtures.of_type(events, "move_blocked"):
		reasons[int(event["fighter"])] = str(event["reason"])
	return reasons


## An event without its `step` and `phase` stamps.
func _core(event: Dictionary) -> Dictionary:
	var copy: Dictionary = event.duplicate()
	copy.erase("step")
	copy.erase("phase")
	return copy


func _moved_ids(events: Array) -> Array[int]:
	var ids: Array[int] = []
	for event: Dictionary in TestFixtures.of_type(events, "moved"):
		ids.append(int(event["fighter"]))
	return ids


# --- Basic movement (R4.1) ---


func test_R4_1_a_move_costs_one_mp_per_cell() -> void:
	var state: FightState = _fight([_v(0, 0)])
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0], [2, 0]])])
	var moved: Array[Dictionary] = TestFixtures.of_type(result["events"], "moved")
	assert_eq(moved.size(), 2)
	assert_eq(_core(moved[0]), {"type": "moved", "fighter": 0, "from": [0, 0], "to": [1, 0], "mp_spent": 1, "mp_left": 2})
	assert_eq(_core(moved[1]), {"type": "moved", "fighter": 0, "from": [1, 0], "to": [2, 0], "mp_spent": 1, "mp_left": 1})
	assert_eq(moved[0]["step"], 1)
	assert_eq(moved[0]["phase"], "lead_move")
	var after: FightState = result["state"]
	assert_eq(_cell(after, 0), _v(2, 0))
	assert_eq(after.fighters[0].mp, 1)
	assert_eq(after.occupant[after.grid.index_of(_v(0, 0))], -1, "old cell freed")
	assert_eq(after.occupant[after.grid.index_of(_v(2, 0))], 0)


func test_R4_8_movers_advance_one_cell_per_sub_tick_in_lockstep() -> void:
	var state: FightState = _fight([_v(0, 0), _v(0, 2)])
	var plans: Array = [TestFixtures.move(0, [[0, -1], [0, -2]]), TestFixtures.move(1, [[0, 3], [0, 4]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_moved_ids(result["events"]), [0, 1, 0, 1], "A1 B1 A2 B2, not A1 A2 B1 B2")


func test_R4_1_a_fighter_that_stays_blocks_the_way() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([2, 0])])
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0], [2, 0]])])
	assert_eq(_cell(result["state"], 0), _v(1, 0), "stops before the Monster")
	assert_eq(result["state"].fighters[0].mp, 2, "keeps the unspent MP")
	var blocked: Array[Dictionary] = TestFixtures.of_type(result["events"], "move_blocked")
	assert_eq(blocked.size(), 1)
	assert_eq(_core(blocked[0]), {"type": "move_blocked", "fighter": 0, "at": [1, 0], "wanted": [2, 0], "reason": "occupied"})


func test_R4_1_a_move_into_an_obstacle_stops() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"obstacles": [[1, 0]]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0]])])
	assert_eq(_cell(result["state"], 0), _v(0, 0))
	assert_eq(_reasons(result["events"]), {0: "not_walkable"})


func test_R4_1_a_move_without_enough_mp_stops_and_keeps_mp() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {}, {"max_mp": 1})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0], [2, 0]])])
	assert_eq(_cell(result["state"], 0), _v(1, 0))
	assert_eq(result["state"].fighters[0].mp, 0)
	assert_eq(_reasons(result["events"]), {0: "no_mp"})


func test_R4_5_a_rooted_fighter_cannot_move() -> void:
	var state: FightState = _fight([_v(0, 0)])
	state.fighters[0].statuses.append({"name": "rooted"})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0]])])
	assert_eq(_cell(result["state"], 0), _v(0, 0))
	assert_eq(_reasons(result["events"]), {0: "rooted"})


func test_R2_3_a_stationary_fighter_never_moves() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {}, {"traits": ["stationary"]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0]])])
	assert_eq(_cell(result["state"], 0), _v(0, 0))
	assert_eq(_reasons(result["events"]), {0: "stationary"})


# --- Engagement (R4.2) ---


func test_R4_2_leaving_an_enemys_reach_costs_extra() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([1, 0])])
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[0, -1]])])
	var moved: Dictionary = TestFixtures.of_type(result["events"], "moved")[0]
	assert_eq(moved["mp_spent"], 2, "1 + engagement_mp_per_enemy")
	assert_eq(moved["mp_left"], 1)


func test_R4_2_only_the_cell_being_left_counts() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([1, 0])])
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[0, -1], [0, -2]])])
	var moved: Array[Dictionary] = TestFixtures.of_type(result["events"], "moved")
	assert_eq(moved[0]["mp_spent"], 2)
	assert_eq(moved[1]["mp_spent"], 1, "(0,-1) is not adjacent to the Monster")
	assert_eq(result["state"].fighters[0].mp, 0)


func test_R4_2_each_adjacent_enemy_adds_its_cost() -> void:
	var monsters: Array = [TestFixtures.monster([1, 0]), TestFixtures.monster([0, 1])]
	var state: FightState = _fight([_v(0, 0)], monsters)
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[-1, 0]])])
	assert_eq(TestFixtures.of_type(result["events"], "moved")[0]["mp_spent"], 3)


func test_R4_2_nimble_fighters_ignore_engagement() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([1, 0])], {}, {"traits": ["nimble"]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[0, -1]])])
	assert_eq(TestFixtures.of_type(result["events"], "moved")[0]["mp_spent"], 1)


func test_R4_2_an_unpayable_engaged_step_cannot_be_taken() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([1, 0])], {}, {"max_mp": 2})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[0, -1], [0, -2], [0, -3]])])
	assert_eq(_cell(result["state"], 0), _v(0, -1), "2 MP for the first step, none left")
	assert_eq(_reasons(result["events"]), {0: "no_mp"})


func test_R4_8_costs_use_positions_at_the_start_of_the_sub_tick() -> void:
	# The Monster walks away in the same phase, but the Creature still pays for the Engagement.
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([1, 0])])
	var plans: Array = [TestFixtures.move(0, [[0, -1]]), TestFixtures.move(1, [[2, 0]])]
	var result: Dictionary = _step(state, plans)
	var creature_move: Dictionary = TestFixtures.of_type(result["events"], "moved")[0]
	assert_eq(creature_move["fighter"], 0)
	assert_eq(creature_move["mp_spent"], 2)


# --- Blight (R4.3, R4.7) ---


func test_R4_3_entering_a_blighted_cell_deals_fixed_damage() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"karma": [[1, 0, -2], [2, 0, -2]]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0], [2, 0]])])
	var hits: Array[Dictionary] = TestFixtures.of_type(result["events"], "damaged")
	assert_eq(hits.size(), 2)
	assert_eq(_core(hits[0]), {"type": "damaged", "fighter": 0, "amount": 10, "cause": "blight", "hp": 90})
	assert_eq(hits[1]["hp"], 80)
	assert_eq(result["state"].fighters[0].hp, 80)


func test_R4_3_blightborn_ignore_blight() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"karma": [[1, 0, -2]]}, {"traits": ["blightborn"]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0]])])
	assert_eq(TestFixtures.of_type(result["events"], "damaged").size(), 0)
	assert_eq(result["state"].fighters[0].hp, 100)


func test_R4_3_corrupted_ground_is_harmless_to_walk_on() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"karma": [[1, 0, -1]]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0]])])
	assert_eq(TestFixtures.of_type(result["events"], "damaged").size(), 0)


func test_R4_7_a_mover_defeated_partway_stops_there() -> void:
	var roster: Array = [
		TestFixtures.creature({"name": "walker", "max_hp": 5}),
		TestFixtures.creature({"name": "bystander", "player": 1}),
		TestFixtures.monster(FAR),
	]
	var state: FightState = TestFixtures.running(roster, [_v(0, 0), _v(-3, 0)], {"karma": [[1, 0, -2]]})
	var result: Dictionary = _step(state, [TestFixtures.move(0, [[1, 0], [2, 0], [3, 0]])])
	var types: Array[String] = TestFixtures.event_types(TestFixtures.of_type(result["events"], "moved"))
	assert_eq(types.size(), 1, "never took the second cell")
	var after: FightState = result["state"]
	assert_false(after.fighters[0].alive)
	assert_eq(after.fighters[0].cell, -1)
	assert_eq(after.occupant[after.grid.index_of(_v(1, 0))], -1, "the defeated fighter left the board")
	var defeats: Array[Dictionary] = TestFixtures.of_type(result["events"], "defeated")
	assert_eq(defeats.size(), 1)
	assert_eq(_core(defeats[0]), {"type": "defeated", "fighter": 0, "how": "downed"})
	assert_eq(after.karma[after.grid.index_of(_v(1, 0))], Land.BLIGHTED)
	assert_eq(after.status, FightState.STATUS_FIGHTING, "the other Creature keeps the fight going")


# --- Simultaneous movement (R4.8) ---


func test_R4_8_follow_the_leader_chain_moves_in_one_sub_tick() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0), _v(2, 0)])
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]]),
		TestFixtures.move(1, [[2, 0]]),
		TestFixtures.move(2, [[3, 0]]),
	]
	var result: Dictionary = _step(state, plans)
	var after: FightState = result["state"]
	assert_eq(_cell(after, 0), _v(1, 0))
	assert_eq(_cell(after, 1), _v(2, 0))
	assert_eq(_cell(after, 2), _v(3, 0))
	assert_eq(TestFixtures.of_type(result["events"], "move_blocked").size(), 0)
	assert_eq(_moved_ids(result["events"]), [0, 1, 2])
	assert_eq(after.occupant[after.grid.index_of(_v(0, 0))], -1)


func test_R4_8_a_blocked_leader_stops_the_whole_chain() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0), _v(2, 0)], [], {"obstacles": [[3, 0]]})
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]]),
		TestFixtures.move(1, [[2, 0]]),
		TestFixtures.move(2, [[3, 0]]),
	]
	var result: Dictionary = _step(state, plans)
	assert_eq(_reasons(result["events"]), {0: "occupied", 1: "occupied", 2: "not_walkable"})
	assert_eq(_cell(result["state"], 0), _v(0, 0))
	assert_eq(_cell(result["state"], 2), _v(2, 0))


func test_R4_8_a_chain_follows_a_leader_that_turns_away() -> void:
	# The follower enters the cell the leader leaves in the same sub-tick, then both keep going.
	var state: FightState = _fight([_v(0, 0), _v(1, 0)])
	var plans: Array = [TestFixtures.move(0, [[1, 0], [2, 0]]), TestFixtures.move(1, [[2, 0], [2, -1]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_cell(result["state"], 0), _v(2, 0))
	assert_eq(_cell(result["state"], 1), _v(2, -1))


func test_R4_8_two_movers_for_one_cell_the_shorter_path_wins() -> void:
	var state: FightState = _fight([_v(0, 0), _v(2, 0)], [], {}, {"max_mp": 4})
	var plans: Array = [
		TestFixtures.move(0, [[1, 0], [2, -1], [3, -2]]),
		TestFixtures.move(1, [[1, 0], [1, -1]]),
	]
	var result: Dictionary = _step(state, plans)
	var after: FightState = result["state"]
	assert_eq(_reasons(result["events"]), {0: "conflict"})
	assert_eq(_cell(after, 1), _v(1, -1), "the shorter path kept going")
	assert_eq(_cell(after, 0), _v(0, 0), "the loser stops for good, even once the cell is free")
	assert_eq(after.fighters[0].mp, 4, "and keeps its MP")


func test_R4_8_a_conflict_tie_goes_to_creatures_before_monsters() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([2, 0])])
	var plans: Array = [TestFixtures.move(0, [[1, 0]]), TestFixtures.move(1, [[1, 0]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_cell(result["state"], 0), _v(1, 0))
	assert_eq(_cell(result["state"], 1), _v(2, 0))
	assert_eq(_reasons(result["events"]), {1: "conflict"})


func test_R4_8_a_conflict_tie_then_goes_to_roster_order() -> void:
	var state: FightState = _fight([_v(0, 0), _v(2, 0)])
	var plans: Array = [TestFixtures.move(1, [[1, 0]]), TestFixtures.move(0, [[1, 0]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_cell(result["state"], 0), _v(1, 0), "roster index 0 beats 1, whatever the plan order")
	assert_eq(_reasons(result["events"]), {1: "conflict"})


func test_R4_8_two_movers_swapping_cells_are_both_blocked() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0)])
	var plans: Array = [TestFixtures.move(0, [[1, 0]]), TestFixtures.move(1, [[0, 0]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_reasons(result["events"]), {0: "swap", 1: "swap"})
	assert_eq(_cell(result["state"], 0), _v(0, 0))
	assert_eq(_cell(result["state"], 1), _v(1, 0))
	assert_eq(result["state"].fighters[0].mp, 3)


func test_R4_8_a_three_cycle_is_blocked() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0), _v(0, 1)])
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]]),
		TestFixtures.move(1, [[0, 1]]),
		TestFixtures.move(2, [[0, 0]]),
	]
	var result: Dictionary = _step(state, plans)
	assert_eq(_reasons(result["events"]), {0: "cycle", 1: "cycle", 2: "cycle"})
	assert_eq(_cell(result["state"], 0), _v(0, 0))
	assert_eq(_cell(result["state"], 1), _v(1, 0))
	assert_eq(_cell(result["state"], 2), _v(0, 1))
	assert_eq(_moved_ids(result["events"]).size(), 0)


func test_R4_8_a_mover_cannot_slip_into_a_blocked_cycle() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0), _v(-1, 0)])
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]]),
		TestFixtures.move(1, [[0, 0]]),
		TestFixtures.move(2, [[0, 0]]),
	]
	var result: Dictionary = _step(state, plans)
	assert_eq(_moved_ids(result["events"]).size(), 0, "nobody moves")
	assert_eq(_reasons(result["events"]), {0: "swap", 1: "swap", 2: "conflict"})


func test_R4_8_a_longer_cycle_with_a_tail_blocks_only_the_cycle() -> void:
	# A->B->C->A is a cycle; D follows A out of (-1,0)... D wants A's cell, which stays: blocked.
	var state: FightState = _fight([_v(0, 0), _v(1, 0), _v(0, 1), _v(-1, 0)], [], {"creature_start_cells": [[0, 0], [1, 0], [0, 1], [-1, 0]]})
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]]),
		TestFixtures.move(1, [[0, 1]]),
		TestFixtures.move(2, [[0, 0]]),
		TestFixtures.move(3, [[0, 0]]),
	]
	var result: Dictionary = _step(state, plans)
	assert_eq(_moved_ids(result["events"]).size(), 0)
	assert_eq(_cell(result["state"], 3), _v(-1, 0))


func test_R4_8_a_free_chain_next_to_a_blocked_one_still_moves() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0), _v(-2, 2), _v(-1, 2)])
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]]),
		TestFixtures.move(1, [[0, 0]]),
		TestFixtures.move(2, [[-1, 2]]),
		TestFixtures.move(3, [[0, 2]]),
	]
	var result: Dictionary = _step(state, plans)
	assert_eq(_reasons(result["events"]), {0: "swap", 1: "swap"})
	assert_eq(_cell(result["state"], 2), _v(-1, 2))
	assert_eq(_cell(result["state"], 3), _v(0, 2))


# --- Lead and Trail moves (R3.6) ---


func test_R3_6_move_first_plans_move_in_lead_moves_and_ability_first_in_trail_moves() -> void:
	var state: FightState = _fight([_v(0, 0), _v(0, 2)])
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]], "move_first"),
		TestFixtures.move(1, [[0, 3]], "ability_first"),
	]
	var events: Array = _step(state, plans)["events"]
	var trail_start: int = -1
	var lead_move: int = -1
	var trail_move: int = -1
	for i: int in events.size():
		var event: Dictionary = events[i]
		if event["type"] == "phase_started" and event["name"] == "trail_move":
			trail_start = i
		if event["type"] == "moved":
			if event["fighter"] == 0:
				lead_move = i
			else:
				trail_move = i
	assert_lt(lead_move, trail_start)
	assert_gt(trail_move, trail_start)


func test_R3_6_trail_moves_see_the_board_after_lead_moves() -> void:
	var state: FightState = _fight([_v(0, 0), _v(-1, 0)])
	var plans: Array = [
		TestFixtures.move(0, [[1, 0]], "move_first"),
		TestFixtures.move(1, [[0, 0]], "ability_first"),
	]
	var result: Dictionary = _step(state, plans)
	assert_eq(_cell(result["state"], 0), _v(1, 0))
	assert_eq(_cell(result["state"], 1), _v(0, 0), "entered the cell the other vacated in Lead moves")
	assert_eq(TestFixtures.of_type(result["events"], "move_blocked").size(), 0)


func test_R4_8_a_move_without_an_ability_defaults_to_lead_moves() -> void:
	var state: FightState = _fight([_v(0, 0)])
	var result: Dictionary = _step(state, [{"fighter": 0, "move_path": [[1, 0]]}])
	assert_eq(_cell(result["state"], 0), _v(1, 0))


# --- The reachable query and default paths (R4.6) ---


func _reach(state: FightState, id: int = 0) -> Dictionary:
	return RulesEngine.reachable(state, id)


func _entry(state: FightState, reach: Dictionary, cell: Vector2i) -> Dictionary:
	return reach[state.grid.index_of(cell)]


func test_R4_6_reachable_covers_every_cell_within_mp_on_an_open_board() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {}, {"max_mp": 2})
	var reach: Dictionary = _reach(state)
	assert_eq(reach.size(), 19, "a radius-2 disk, own cell included")
	for index: int in reach.keys():
		var cell: Vector2i = state.grid.cell_at(index)
		assert_eq(reach[index]["mp"], Hex.distance(_v(0, 0), cell))
		assert_eq((reach[index]["path"] as Array).size(), Hex.distance(_v(0, 0), cell))
	assert_eq(_entry(state, reach, _v(0, 0))["mp"], 0)
	assert_true((_entry(state, reach, _v(0, 0))["path"] as Array).is_empty())


func test_R4_6_reachable_excludes_fighters_and_obstacles_and_routes_around() -> void:
	var state: FightState = _fight([_v(0, 0), _v(1, 0)], [], {"obstacles": [[1, 1]]})
	var reach: Dictionary = _reach(state)
	assert_false(reach.has(state.grid.index_of(_v(1, 0))), "an ally blocks")
	assert_false(reach.has(state.grid.index_of(_v(1, 1))), "an obstacle blocks")
	var to_far: Dictionary = _entry(state, reach, _v(2, 0))
	assert_eq(to_far["mp"], 3, "around the ally")
	var expected: Array[Vector2i] = [_v(1, -1), _v(2, -1), _v(2, 0)]
	assert_eq(to_far["path"], expected)


func test_R4_2_reachable_includes_engagement() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([1, 0])])
	var reach: Dictionary = _reach(state)
	assert_eq(_entry(state, reach, _v(0, -1))["mp"], 2)
	assert_eq(_entry(state, reach, _v(0, -2))["mp"], 3)
	assert_false(reach.has(state.grid.index_of(_v(0, -3))), "out of MP")


func test_R4_6_the_default_path_avoids_blight_before_saving_mp() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"karma": [[1, 0, -2]]})
	var reach: Dictionary = _reach(state)
	var entry: Dictionary = _entry(state, reach, _v(2, 0))
	assert_eq(entry["damage"], 0)
	assert_eq(entry["mp"], 3, "one cell longer to dodge the blight")
	var expected: Array[Vector2i] = [_v(1, -1), _v(2, -1), _v(2, 0)]
	assert_eq(entry["path"], expected, "tie between two detours: the lowest direction sequence")


func test_R4_6_blight_damage_is_reported_when_it_cannot_be_avoided() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"karma": [[1, 0, -2], [1, -1, -2], [0, 1, -2], [-1, 1, -2], [-1, 0, -2], [0, -1, -2]]})
	var entry: Dictionary = _entry(state, _reach(state), _v(1, 1))
	assert_eq(entry["damage"], 10, "one blighted cell on every route")


func test_R4_6_blightborn_walk_straight_through_blight() -> void:
	var state: FightState = _fight([_v(0, 0)], [], {"karma": [[1, 0, -2]]}, {"traits": ["blightborn"]})
	var entry: Dictionary = _entry(state, _reach(state), _v(2, 0))
	assert_eq(entry["mp"], 2)
	assert_eq(entry["damage"], 0)


func test_R4_6_equal_cost_paths_take_the_lowest_direction_sequence() -> void:
	var state: FightState = _fight([_v(0, 0)])
	var entry: Dictionary = _entry(state, _reach(state), _v(1, 1))
	var expected: Array[Vector2i] = [_v(1, 0), _v(1, 1)]
	assert_eq(entry["path"], expected, "D0 then D5 beats D5 then D0")


func test_R4_6_rooted_stationary_and_empty_pools_reach_only_their_own_cell() -> void:
	var rooted: FightState = _fight([_v(0, 0)])
	rooted.fighters[0].statuses.append({"name": "rooted"})
	assert_eq(_reach(rooted).size(), 1)
	var stationary: FightState = _fight([_v(0, 0)], [], {}, {"traits": ["stationary"]})
	assert_eq(_reach(stationary).size(), 1)
	var broke: FightState = _fight([_v(0, 0)])
	broke.fighters[0].mp = 0
	assert_eq(_reach(broke).size(), 1)


func test_R4_6_a_path_the_query_suggests_validates_and_resolves_to_the_same_place() -> void:
	var state: FightState = _fight([_v(0, 0)], [TestFixtures.monster([2, -1])], {"karma": [[1, 0, -2]]})
	var reach: Dictionary = _reach(state)
	var target: Vector2i = _v(1, 1)
	var entry: Dictionary = _entry(state, reach, target)
	var path: Array = []
	for cell: Vector2i in entry["path"]:
		path.append([cell.x, cell.y])
	var plan: Dictionary = TestFixtures.move(0, path)
	assert_true(RulesEngine.validate_plan(state, TestFixtures.with_from(state, plan))["ok"])
	var result: Dictionary = _step(state, [plan])
	assert_eq(_cell(result["state"], 0), target)
	assert_eq(result["state"].fighters[0].mp, 3 - int(entry["mp"]))
