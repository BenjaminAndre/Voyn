extends GutTest
## T13: the `scripted_chase` Monster behavior (docs/gdd/90-placeholder-content.md).

const BEHAVIORS: Dictionary = {"chase": {"id": "chase", "kind": "scripted_chase"}, "idle": {"id": "idle", "kind": "greedy"}}


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


## creatures: cells; monsters: [{"cell": [q, r], ...overrides}]. Monsters default to bash and chase.
func _setup(creature_cells: Array[Vector2i], monsters: Array, creature_overrides: Dictionary = {}) -> FightState:
	var roster: Array = []
	for i: int in creature_cells.size():
		var entry: Dictionary = {"player": i, "recharge_steps": 10, "name": "c%d" % i}
		entry.merge(creature_overrides, true)
		roster.append(TestFixtures.creature(entry))
	for entry: Dictionary in monsters:
		var overrides: Dictionary = {"abilities": ["bash"], "behavior": "chase", "recharge_steps": 10}
		overrides.merge(entry, true)
		var spawn: Array = overrides["cell"]
		overrides.erase("cell")
		roster.append(TestFixtures.monster(spawn, overrides))
	return TestFixtures.running(roster, creature_cells, {}, 1, {"land_phase_every_steps": 1000})


func _monster(state: FightState) -> int:
	return state.living(FighterState.SIDE_MONSTERS)[0].id


func test_it_targets_the_nearest_creature_and_breaks_ties_by_roster_order() -> void:
	var state: FightState = _setup([_v(0, 0), _v(2, 0)], [{"cell": [1, 0]}])
	var plan: Dictionary = ScriptedChase.plan(state, 2)
	assert_eq(plan["target_cell"], [0, 0], "both creatures are adjacent: roster order")
	var nearer: FightState = _setup([_v(-3, 0), _v(2, 0)], [{"cell": [1, 0]}])
	assert_eq(ScriptedChase.plan(nearer, 2)["target_cell"], [2, 0], "the nearer one wins")


func test_it_strikes_from_where_it_stands_with_no_move() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [1, 0]}])
	var plan: Dictionary = ScriptedChase.plan(state, 1)
	assert_eq(plan["ability"], "bash")
	assert_eq(plan["target_cell"], [0, 0])
	assert_false(plan.has("move_path"))
	assert_eq(plan["from_cell"], [1, 0])


func test_it_closes_in_by_the_cheapest_cell_that_lets_it_strike() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [3, 0]}])
	var plan: Dictionary = ScriptedChase.plan(state, 1)
	assert_eq(plan["order"], "move_first")
	assert_eq(plan["move_path"], [[2, 0], [1, 0]], "2 MP to a cell next to the target")
	assert_eq(plan["ability"], "bash")
	assert_eq(plan["target_cell"], [0, 0])


func test_cheapest_cell_ties_go_to_cell_order() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [2, -1]}])
	var plan: Dictionary = ScriptedChase.plan(state, 1)
	assert_eq(plan["move_path"], [[1, -1]], "(1,-1) and (1,0) both cost 1; cell order picks (1,-1)")


func test_when_no_ability_can_reach_it_walks_as_close_as_mp_allows_and_does_not_strike() -> void:
	var state: FightState = _setup([_v(-4, 0)], [{"cell": [4, -2], "max_mp": 2}])
	var plan: Dictionary = ScriptedChase.plan(state, 1)
	assert_false(plan.has("ability"))
	var path: Array = plan["move_path"]
	assert_eq(path.size(), 2, "all its MP")
	var end: Vector2i = Vector2i(int(path[1][0]), int(path[1][1]))
	assert_eq(Hex.distance(end, _v(-4, 0)), Hex.distance(_v(4, -2), _v(-4, 0)) - 2, "two cells closer")


func test_low_on_ap_it_only_moves() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [3, 0]}])
	state.fighters[1].ap = 2
	var plan: Dictionary = ScriptedChase.plan(state, 1)
	assert_false(plan.has("ability"))
	assert_true(plan.has("move_path"))
	var adjacent: FightState = _setup([_v(0, 0)], [{"cell": [1, 0]}])
	adjacent.fighters[1].ap = 0
	assert_eq(ScriptedChase.plan(adjacent, 1), {}, "already next to it, and cannot afford to strike: it waits")


func test_a_rooted_monster_still_strikes_but_does_not_move() -> void:
	var near: FightState = _setup([_v(0, 0)], [{"cell": [1, 0]}])
	near.fighters[1].statuses.append(TestFixtures.status("rooted"))
	assert_eq(ScriptedChase.plan(near, 1)["ability"], "bash")
	var far: FightState = _setup([_v(0, 0)], [{"cell": [3, 0]}])
	far.fighters[1].statuses.append(TestFixtures.status("rooted"))
	assert_eq(ScriptedChase.plan(far, 1), {})


func test_it_skips_abilities_on_cooldown() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [1, 0], "abilities": ["bash", "smash"]}])
	state.fighters[1].cooldowns["bash"] = 9
	assert_eq(ScriptedChase.plan(state, 1)["ability"], "smash")


func test_it_aims_at_where_creatures_stand_now_so_dodging_works() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [1, 0]}])
	var plans: Array = [ScriptedChase.plan(state, 1), TestFixtures.move(0, [[-1, 0]])]
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_eq(result["state"].fighters[0].hp, 100, "the creature stepped away first")
	assert_eq(TestFixtures.of_type(result["events"], "fizzled").size(), 1)


func test_it_waits_with_no_creature_on_the_board() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [1, 0]}, {"cell": [4, -4]}])
	var events: Array[Dictionary] = []
	Defeat.apply(state, state.fighters[0], events)
	assert_eq(ScriptedChase.plan(state, 1), {})


func test_plans_cover_scripted_chase_monsters_in_roster_order_and_skip_other_behaviors() -> void:
	var state: FightState = _setup([_v(0, 0)], [{"cell": [1, 0]}, {"cell": [4, -4], "behavior": "idle"}, {"cell": [-1, 0]}])
	var plans: Array = ScriptedChase.plans(state, BEHAVIORS)
	var ids: Array[int] = []
	for plan: Dictionary in plans:
		ids.append(int(plan["fighter"]))
	assert_eq(ids, [1, 3])


func test_every_plan_it_makes_passes_plan_validation() -> void:
	for monster_cell: Array in [[1, 0], [3, 0], [2, -1], [4, -2], [-3, 3], [0, -4]]:
		var state: FightState = _setup([_v(0, 0), _v(-2, 2)], [{"cell": monster_cell}])
		var plan: Dictionary = ScriptedChase.plan(state, 2)
		if plan.is_empty():
			continue
		var check: Dictionary = RulesEngine.validate_plan(state, plan)
		assert_true(check["ok"], "%s: %s" % [str(monster_cell), str(check["errors"])])


func test_it_is_deterministic() -> void:
	var state: FightState = _setup([_v(0, 0), _v(-2, 2)], [{"cell": [3, -1]}, {"cell": [2, 1]}])
	assert_eq(ScriptedChase.plans(state, BEHAVIORS), ScriptedChase.plans(state.clone(), BEHAVIORS))


func test_the_real_placeholder_encounter_gets_four_monster_plans() -> void:
	var content: Dictionary = ContentLoader.load_all()["content"]
	var built: Dictionary = ContentLoader.fight_from(content, TestFixtures.rules(), "ph_encounter_1", 1)
	var cells: Array[Vector2i] = [_v(-1, 4), _v(0, 4), _v(1, 3)]
	var state: FightState = TestFixtures.start(built["state"], cells)
	var plans: Array = ScriptedChase.plans(state, content["behaviors"])
	assert_eq(plans.size(), 4)
	for plan: Dictionary in plans:
		assert_true(RulesEngine.validate_plan(state, plan)["ok"], str(plan))
