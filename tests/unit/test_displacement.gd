extends GutTest
## T9: displacement (GDD R7.5-R7.7, R4.3, R4.4, R3.6): push, pull, Heavy, collisions, blight on entry,
## farthest-first order, Immovable/Stationary, and Trail moves cancelled after a push.

const FAR: Array = [4, -4]


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


func _setup(creatures: Array, monsters: Array, arena: Dictionary = {}) -> FightState:
	var roster: Array = []
	var cells: Array[Vector2i] = []
	for entry: Dictionary in creatures:
		var overrides: Dictionary = {"recharge_steps": 10}
		overrides.merge(entry, true)
		cells.append(overrides["cell"])
		overrides.erase("cell")
		overrides["player"] = roster.size()
		roster.append(TestFixtures.creature(overrides))
	for entry: Dictionary in monsters:
		var overrides: Dictionary = entry.duplicate()
		var spawn: Array = overrides["cell"]
		overrides.erase("cell")
		roster.append(TestFixtures.monster(spawn, overrides))
	return TestFixtures.running(roster, cells, arena, 1, {"land_phase_every_steps": 1000})


func _use(fighter: int, ability: String, target: Vector2i) -> Dictionary:
	return {"fighter": fighter, "ability": ability, "target_cell": [target.x, target.y]}


func _step(state: FightState, plans: Array) -> Dictionary:
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_true(result["ok"], str(result["errors"]))
	return result


func _types(events: Array, type: String) -> Array[Dictionary]:
	return TestFixtures.of_type(events, type)


func _cell(state: FightState, id: int) -> Vector2i:
	return state.cell_of(state.fighters[id])


func _op(state: FightState, origin: Vector2i, distance: int, pull: bool = false) -> Dictionary:
	return {"distance": distance, "origin": state.grid.index_of(origin), "pull": pull}


# --- Push (R7.5) ---


func test_R7_5_a_push_moves_the_target_away_from_the_user_and_costs_no_mp() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(_cell(after, 1), _v(3, 0))
	var moves: Array[Dictionary] = _types(result["events"], "displaced")
	assert_eq(moves.size(), 1)
	assert_eq([moves[0]["from"], moves[0]["to"], moves[0]["phase"]], [[1, 0], [3, 0], "dash"])
	assert_eq(after.fighters[1].mp, 3, "Displacement costs no MP (R4.4)")
	assert_eq(after.occupant[after.grid.index_of(_v(1, 0))], -1)
	assert_eq(after.occupant[after.grid.index_of(_v(3, 0))], 1)


func test_R6_3_effects_resolve_in_order_shove_pushes_then_damages() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_lt(types.find("displaced"), types.find("damaged"))
	assert_eq(result["state"].fighters[1].hp, 94)


func test_R7_5_the_direction_is_the_axis_closest_to_the_origin_to_target_vector() -> void:
	var state: FightState = _setup([{"cell": _v(-4, 0)}], [{"cell": [2, 1]}, {"cell": [1, 2]}])
	var events: Array[Dictionary] = []
	Displacement.apply(state, state.fighters[1], _op(state, _v(0, 0), 1), events)
	Displacement.apply(state, state.fighters[2], _op(state, _v(0, 0), 1), events)
	assert_eq(_cell(state, 1), _v(3, 1), "D0 is closest to (2,1)")
	assert_eq(_cell(state, 2), _v(1, 3), "D5 is closest to (1,2)")


func test_R7_5_a_fighter_on_the_origin_is_not_pushed() -> void:
	var state: FightState = _setup([{"cell": _v(-4, 0)}], [{"cell": [0, 0]}, {"cell": FAR}])
	var events: Array[Dictionary] = []
	Displacement.apply(state, state.fighters[1], _op(state, _v(0, 0), 2), events)
	assert_eq(_cell(state, 1), _v(0, 0))
	assert_eq(events.size(), 0)


func test_R7_5_push_origin_target_pushes_everyone_in_the_area_away_from_the_target_cell() -> void:
	var state: FightState = _setup(
		[{"cell": _v(-4, 0), "abilities": ["blast"]}],
		[{"cell": [1, 0]}, {"cell": [0, 1]}, {"cell": [-1, 1]}, {"cell": [0, 0]}])
	var result: Dictionary = _step(state, [_use(0, "blast", _v(0, 0))])
	var after: FightState = result["state"]
	assert_eq(_cell(after, 1), _v(2, 0))
	assert_eq(_cell(after, 2), _v(0, 2))
	assert_eq(_cell(after, 3), _v(-2, 2))
	assert_eq(_cell(after, 4), _v(0, 0), "the fighter on the origin stays")


func test_R6_3_displacement_goes_farthest_from_the_origin_first() -> void:
	# Nearest-first would make the near Monster hit the far one; farthest-first lets both slide.
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["gust"]}], [{"cell": [1, 0]}, {"cell": [2, 0]}])
	var result: Dictionary = _step(state, [{"fighter": 0, "ability": "gust"}])
	var after: FightState = result["state"]
	assert_eq(_cell(after, 1), _v(2, 0))
	assert_eq(_cell(after, 2), _v(3, 0))
	assert_eq(_types(result["events"], "collided").size(), 0)
	var order: Array[int] = []
	for event: Dictionary in _types(result["events"], "displaced"):
		order.append(int(event["fighter"]))
	assert_eq(order, [2, 1], "the far one first")


# --- Collisions (R7.6) ---


func test_R7_6_a_push_stopped_by_an_obstacle_deals_collision_damage() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}], {"obstacles": [[3, 0]]})
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(_cell(after, 1), _v(2, 0))
	var crash: Array[Dictionary] = _types(result["events"], "collided")
	assert_eq(crash.size(), 1)
	assert_eq([crash[0]["cells"], crash[0]["damage"]], [1, 8], "collision_damage_per_cell x cells not travelled")
	var hits: Array[Dictionary] = _types(result["events"], "damaged")
	assert_eq(hits[0]["cause"], "collision")
	assert_eq(hits[0]["amount"], 8)
	assert_eq(after.fighters[1].hp, 86, "8 collision + 6 from the shove")


func test_R7_1_collision_damage_is_fixed_and_ignores_modifiers() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"], "power": 100}], [{"cell": [1, 0]}, {"cell": FAR}], {"obstacles": [[3, 0]]})
	state.fighters[1].statuses.append(TestFixtures.status("vulnerable", 50))
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	assert_eq(_types(result["events"], "damaged")[0]["amount"], 8, "no power, no Vulnerable")


func test_R7_3_a_shield_absorbs_collision_damage() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}], {"obstacles": [[3, 0]]})
	var events: Array[Dictionary] = []
	Statuses.apply_shield(state, state.fighters[1], 10, 3, 0, events)
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	var hit: Dictionary = _types(result["events"], "damaged")[0]
	assert_eq([hit["amount"], hit["absorbed"]], [8, 8])


func test_R7_6_a_push_into_another_fighter_collides_and_the_other_takes_nothing() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": [2, 0]}])
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(_cell(after, 1), _v(1, 0), "did not move")
	assert_eq(_types(result["events"], "displaced").size(), 0, "no displaced event without movement")
	assert_eq(_types(result["events"], "collided")[0]["cells"], 2)
	assert_eq(after.fighters[1].hp, 100 - 16 - 6)
	assert_eq(after.fighters[2].hp, 100, "the fighter it hit takes nothing")


func test_R7_6_a_push_off_the_arena_edge_collides() -> void:
	var state: FightState = _setup([{"cell": _v(3, 0), "abilities": ["shove"]}], [{"cell": [4, 0]}, {"cell": [-4, 4]}])
	var result: Dictionary = _step(state, [_use(0, "shove", _v(4, 0))])
	assert_eq(_cell(result["state"], 1), _v(4, 0))
	assert_eq(_types(result["events"], "collided")[0]["damage"], 16)


func test_R7_6_a_pull_never_deals_collision_damage_and_stops_next_to_the_origin() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["hook", "yank"]}], [{"cell": [4, 0]}, {"cell": [-4, 4]}])
	var hooked: Dictionary = _step(state, [_use(0, "hook", _v(4, 0))])
	assert_eq(_cell(hooked["state"], 1), _v(1, 0), "3 cells in")
	var yanked: Dictionary = _step(state, [_use(0, "yank", _v(4, 0))])
	assert_eq(_cell(yanked["state"], 1), _v(1, 0), "stops once adjacent, though the pull was 6")
	assert_eq(_types(yanked["events"], "collided").size(), 0)


func test_R7_6_a_blocked_pull_just_stops() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0)}, {"cell": _v(1, 0)}], [{"cell": [3, 0]}, {"cell": FAR}])
	var events: Array[Dictionary] = []
	Displacement.apply(state, state.fighters[2], _op(state, _v(0, 0), 3, true), events)
	assert_eq(_cell(state, 2), _v(2, 0), "the ally at (1,0) is in the way")
	assert_eq(_types(events, "collided").size(), 0)
	assert_eq(state.fighters[2].hp, 100)


# --- Traits (R7.5, R7.7) ---


func test_R7_5_heavy_fighters_move_one_cell_less() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0], "traits": ["heavy", "blightborn"]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	assert_eq(_cell(result["state"], 1), _v(2, 0), "push 2 moves a Heavy fighter 1")


func test_R7_5_heavy_never_moves_less_than_one_cell() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["gust"]}], [{"cell": [1, 0], "traits": ["heavy"]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [{"fighter": 0, "ability": "gust"}])
	assert_eq(_cell(result["state"], 1), _v(2, 0), "push 1 still moves 1")


func test_R7_7_immovable_and_stationary_fighters_are_not_displaced_and_take_no_collision_damage() -> void:
	for trait_name: String in ["immovable", "stationary"]:
		var state: FightState = _setup(
			[{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0], "traits": [trait_name]}, {"cell": FAR}], {"obstacles": [[2, 0]]})
		var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
		assert_eq(_cell(result["state"], 1), _v(1, 0), trait_name)
		assert_eq(_types(result["events"], "collided").size(), 0)
		assert_eq(result["state"].fighters[1].hp, 94, "only the shove's own damage")


# --- Blight on entry (R4.3) and defeat mid-push ---


func test_R4_3_a_pushed_fighter_takes_blight_damage_for_each_blighted_cell_entered() -> void:
	var state: FightState = _setup(
		[{"cell": _v(1, 0)}], [{"cell": [0, 0], "abilities": ["shove"]}, {"cell": FAR}], {"karma": [[2, 0, -2]]})
	var result: Dictionary = _step(state, [_use(1, "shove", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(_cell(after, 0), _v(3, 0))
	var causes: Array[String] = []
	for hit: Dictionary in _types(result["events"], "damaged"):
		causes.append(str(hit["cause"]))
	assert_eq(causes, ["blight", "ability"], "the slide first, then the shove's damage")
	assert_eq(after.fighters[0].hp, 84, "10 blight + 6")
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_lt(types.find("displaced"), types.find("damaged"), "displaced before the hits")


func test_R4_3_blightborn_are_not_hurt_by_blight_when_pushed() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}], {"karma": [[2, 0, -2]]})
	var result: Dictionary = _step(state, [_use(0, "shove", _v(1, 0))])
	assert_eq(result["state"].fighters[1].hp, 94, "only the shove's damage")


func test_R7_6_a_fighter_defeated_mid_push_stops_there_with_no_collision_damage() -> void:
	var state: FightState = _setup(
		[{"cell": _v(1, 0), "max_hp": 5}, {"cell": _v(-4, 4)}],
		[{"cell": [0, 0], "abilities": ["shove"]}, {"cell": FAR}], {"karma": [[2, 0, -2]], "obstacles": [[3, 0]]})
	var result: Dictionary = _step(state, [_use(2, "shove", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(_types(result["events"], "collided").size(), 0, "no collision damage once defeated")
	assert_false(after.fighters[0].alive)
	assert_eq(_types(result["events"], "displaced")[0]["to"], [2, 0], "stopped on the Blighted cell")
	assert_eq(_types(result["events"], "defeated")[0]["how"], "downed")
	assert_eq(after.karma[after.grid.index_of(_v(2, 0))], Land.BLIGHTED)


# --- Phases and plans (R3.6) ---


func test_R3_6_a_displaced_fighters_trail_move_is_cancelled_and_keeps_its_mp() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}])
	var plans: Array = [_use(0, "shove", _v(1, 0)), TestFixtures.move(1, [[1, 1]], "ability_first")]
	var result: Dictionary = _step(state, plans)
	var after: FightState = result["state"]
	assert_eq(_cell(after, 1), _v(3, 0), "pushed, and it did not walk back")
	var blocked: Array[Dictionary] = _types(result["events"], "move_blocked")
	assert_eq(blocked.size(), 1)
	assert_eq([blocked[0]["reason"], blocked[0]["at"], blocked[0]["wanted"]], ["displaced", [3, 0], [1, 1]])
	assert_eq(after.fighters[1].mp, 3, "MP kept")


func test_R3_6_a_lead_move_happens_before_the_push_so_dodging_works() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["shove"]}], [{"cell": [1, 0]}, {"cell": FAR}])
	var plans: Array = [_use(0, "shove", _v(1, 0)), TestFixtures.move(1, [[1, 1]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_cell(result["state"], 1), _v(1, 1), "it left in Lead moves; the shove fizzled")
	assert_eq(_types(result["events"], "fizzled").size(), 1)


func test_R3_6_dash_comes_before_strike_so_allies_can_combo_across_players() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shove"]}, {"cell": _v(0, 1), "abilities": ["shot"]}],
		[{"cell": [1, 0]}, {"cell": FAR}])
	var plans: Array = [_use(0, "shove", _v(1, 0)), _use(1, "shot", _v(3, 0))]
	var result: Dictionary = _step(state, plans)
	assert_eq(_types(result["events"], "fizzled").size(), 0, "the archer aimed at where the push sends the Monster")
	assert_eq(result["state"].fighters[2].hp, 78, "6 from the shove, 16 from the shot")


func test_R6_3_a_displace_effect_is_part_of_the_ability_schema() -> void:
	var good: Dictionary = Defs.ability({
		"id": "x", "phase": "dash", "ap_cost": 1, "cooldown": 0, "target": "enemy", "min_range": 1, "max_range": 1,
		"needs_los": false, "line_only": false, "area": {"shape": "single"}, "affects": "enemies", "karma": 0,
		"effects": [{"type": "push", "distance": 2}, {"type": "pull", "distance": 1, "push_origin": "target"}],
	})
	assert_true(good["ok"], str(good["errors"]))
	assert_eq(good["value"]["effects"][0]["push_origin"], "user", "defaults to the user")
