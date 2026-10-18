extends GutTest
## T7: abilities (GDD R6, R7.1-R7.3, R3.6-R3.7): plan-time validity, phases, simultaneous Strike,
## Areas, statuses, Shield, footprints, cooldowns, and the `targets` and `threat_zone` queries.

const FAR: Array = [4, -4]


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


## creatures: [{"cell": Vector2i, ...roster overrides}], monsters: [{"cell": [q, r], ...overrides}].
## IDs: creatures first, then monsters, in the order given. Abilities go in each entry's "abilities".
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
	return TestFixtures.running(roster, cells, arena)


func _use(fighter: int, ability: String, target: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var plan: Dictionary = {"fighter": fighter, "ability": ability, "target_cell": [target.x, target.y]}
	plan.merge(extra, true)
	return plan


func _step(state: FightState, plans: Array) -> Dictionary:
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_true(result["ok"], str(result["errors"]))
	return result


func _codes(state: FightState, plan: Dictionary) -> Array:
	return RulesEngine.validate_plan(state, TestFixtures.with_from(state, plan))["errors"]


func _index(state: FightState, cell: Vector2i) -> int:
	return state.grid.index_of(cell)


func _types(events: Array, type: String) -> Array[Dictionary]:
	return TestFixtures.of_type(events, type)


func _single_hit_state(power: int = 0) -> FightState:
	return _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"], "power": power}],
		[{"cell": [1, 0]}, {"cell": FAR}])


# --- Plan-time validity (R6.1) ---


func test_R6_1_a_valid_plan_passes() -> void:
	var state: FightState = _single_hit_state()
	assert_eq(_codes(state, _use(0, "bash", _v(1, 0))), [])


func test_R6_1_each_check_has_its_own_code() -> void:
	var state: FightState = _single_hit_state()
	assert_true(_codes(state, _use(0, "bash", _v(2, 0))).has("out_of_range"))
	assert_true(_codes(state, _use(0, "bash", _v(0, 1))).has("bad_target"), "no enemy there")
	assert_true(_codes(state, _use(0, "bash", _v(9, 9))).has("bad_target"), "outside the Arena")
	var poor: FightState = _single_hit_state()
	poor.fighters[0].ap = 2
	assert_true(_codes(poor, _use(0, "bash", _v(1, 0))).has("not_enough_ap"))
	var cooling: FightState = _single_hit_state()
	cooling.fighters[0].cooldowns["bash"] = 5
	assert_true(_codes(cooling, _use(0, "bash", _v(1, 0))).has("on_cooldown"))


func test_R6_1_los_and_axis() -> void:
	var walled: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shot"]}], [{"cell": [3, 0]}, {"cell": FAR}], {"obstacles": [[2, 0]]})
	assert_true(_codes(walled, _use(0, "shot", _v(3, 0))).has("no_los"))
	var open: FightState = _setup([{"cell": _v(0, 0), "abilities": ["shot"]}], [{"cell": [3, 0]}, {"cell": FAR}])
	assert_eq(_codes(open, _use(0, "shot", _v(3, 0))), [])
	var off_axis: FightState = _setup([{"cell": _v(0, 0), "abilities": ["lunge"]}], [{"cell": [1, 1]}, {"cell": FAR}])
	assert_true(_codes(off_axis, _use(0, "lunge", _v(1, 1))).has("not_on_axis"))
	var on_axis: FightState = _setup([{"cell": _v(0, 0), "abilities": ["lunge"]}], [{"cell": [2, 0]}, {"cell": FAR}])
	assert_eq(_codes(on_axis, _use(0, "lunge", _v(2, 0))), [])


func test_R6_1_a_fighter_blocks_los() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shot"]}], [{"cell": [2, 0]}, {"cell": [3, 0]}])
	assert_eq(_codes(state, _use(0, "shot", _v(2, 0))), [])
	assert_true(_codes(state, _use(0, "shot", _v(3, 0))).has("no_los"), "the Monster at (2,0) is in the way")


func test_R6_1_plan_codes_for_unknown_or_foreign_abilities() -> void:
	var state: FightState = _single_hit_state()
	assert_true(_codes(state, _use(0, "nope", _v(1, 0))).has("unknown_ability"))
	assert_true(_codes(state, _use(0, "guard", _v(0, 0))).has("ability_not_known"), "exists, but not in its kit")
	var no_target: Dictionary = {"fighter": 0, "ability": "bash"}
	assert_true(_codes(state, no_target).has("missing_target_cell"))


func test_R6_1_a_self_ability_may_leave_out_its_target() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["guard"]}], [{"cell": FAR}])
	assert_eq(_codes(state, {"fighter": 0, "ability": "guard"}), [])


func test_R6_1_the_check_uses_the_cell_the_plan_moves_the_user_to() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [2, 0]}, {"cell": FAR}])
	assert_true(_codes(state, _use(0, "bash", _v(2, 0))).has("out_of_range"), "from where it stands now")
	var move_first: Dictionary = _use(0, "bash", _v(2, 0), {"move_path": [[1, 0]], "order": "move_first"})
	assert_eq(_codes(state, move_first), [], "move then strike")
	var ability_first: Dictionary = _use(0, "bash", _v(2, 0), {"move_path": [[1, 0]], "order": "ability_first"})
	assert_true(_codes(state, ability_first).has("out_of_range"), "strike then move")


func test_R6_1_ally_and_empty_cell_filters() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["mend"]}, {"cell": _v(1, 0)}], [{"cell": [0, 1]}, {"cell": FAR}])
	assert_eq(_codes(state, _use(0, "mend", _v(1, 0))), [])
	assert_true(_codes(state, _use(0, "mend", _v(0, 1))).has("bad_target"), "an enemy is not an ally")
	assert_true(_codes(state, _use(0, "mend", _v(0, 0))).has("out_of_range"), "not itself: range starts at 1")


# --- Damage numbers (R7.1) ---


func test_R7_1_damage_uses_power() -> void:
	var state: FightState = _single_hit_state(10)
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	var hits: Array[Dictionary] = _types(result["events"], "damaged")
	assert_eq(hits.size(), 1)
	assert_eq(hits[0]["amount"], 19, "floor(18 x 110 / 100)")
	assert_eq(hits[0]["absorbed"], 0)
	assert_eq(hits[0]["cause"], "ability")
	assert_eq(result["state"].fighters[1].hp, 81)


func test_R7_1_blightborn_bonus_stands_on_corrupted_or_blighted_ground() -> void:
	var clean: FightState = _setup([{"cell": _v(0, 0)}], [{"cell": [1, 0], "abilities": ["bash"]}, {"cell": FAR}])
	var dirty: FightState = _setup([{"cell": _v(0, 0)}], [{"cell": [1, 0], "abilities": ["bash"]}, {"cell": FAR}], {"karma": [[1, 0, -1]]})
	var plan: Dictionary = _use(1, "bash", _v(0, 0))
	assert_eq(_types(_step(clean, [plan])["events"], "damaged")[0]["amount"], 18)
	assert_eq(_types(_step(dirty, [plan])["events"], "damaged")[0]["amount"], 21, "floor(18 x 120 / 100)")


func test_R7_1_modifiers_add_into_one_sum() -> void:
	var state: FightState = _single_hit_state(10)
	state.fighters[1].statuses.append(TestFixtures.status("vulnerable", 50))
	assert_eq(_types(_step(state, [_use(0, "bash", _v(1, 0))])["events"], "damaged")[0]["amount"], 28, "floor(18 x 160 / 100)")
	var guarded: FightState = _single_hit_state()
	guarded.fighters[1].statuses.append(TestFixtures.status("guarded", 25))
	assert_eq(_types(_step(guarded, [_use(0, "bash", _v(1, 0))])["events"], "damaged")[0]["amount"], 13, "floor(18 x 75 / 100)")


func test_R7_1_damage_never_goes_below_zero() -> void:
	var state: FightState = _single_hit_state()
	state.fighters[1].statuses.append(TestFixtures.status("guarded", 150))
	assert_eq(_types(_step(state, [_use(0, "bash", _v(1, 0))])["events"], "damaged")[0]["amount"], 0)


func test_R7_2_heal_is_capped_at_max_hp() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["mend"]}, {"cell": _v(1, 0)}], [{"cell": FAR}])
	state.fighters[1].hp = 90
	var result: Dictionary = _step(state, [_use(0, "mend", _v(1, 0))])
	assert_eq(result["state"].fighters[1].hp, 100)
	assert_eq(_types(result["events"], "healed")[0]["hp"], 100)


# --- The Strike phase (R3.6, R3.7) ---


func test_R3_6_two_fighters_defeat_each_other_in_one_strike() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"], "max_hp": 10}, {"cell": _v(-3, 0)}],
		[{"cell": [1, 0], "abilities": ["bash"], "max_hp": 10}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0)), _use(1 + 1, "bash", _v(0, 0))])
	var after: FightState = result["state"]
	assert_false(after.fighters[0].alive, "the Creature is Downed")
	assert_false(after.fighters[2].alive, "the Monster is Killed")
	assert_eq(_types(result["events"], "damaged").size(), 2, "both hits landed")
	assert_eq(_types(result["events"], "defeated").size(), 2)
	assert_eq(after.status, FightState.STATUS_FIGHTING, "one fighter is left on each Side")
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_lt(types.rfind("damaged"), types.find("defeated"), "all damage lands before any defeat")


func test_R3_7_a_strike_fizzles_after_its_target_walked_away() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0]}, {"cell": FAR}])
	var plans: Array = [_use(0, "bash", _v(1, 0)), TestFixtures.move(1, [[2, 0]])]
	var result: Dictionary = _step(state, plans)
	var after: FightState = result["state"]
	var fizzles: Array[Dictionary] = _types(result["events"], "fizzled")
	assert_eq(fizzles.size(), 1)
	assert_eq(fizzles[0]["reason"], "bad_target", "an enemy-filtered ability fizzles")
	assert_eq(fizzles[0]["cell"], [1, 0])
	assert_eq(after.fighters[0].ap, 3, "the AP is still spent")
	assert_eq(after.fighters[1].hp, 100)
	assert_eq(_types(result["events"], "damaged").size(), 0)
	assert_eq(after.karma[_index(after, _v(1, 0))], 0, "a fizzled ability leaves no footprint")


func test_R3_7_a_strike_fizzles_when_its_user_stopped_short() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}, {"cell": _v(2, 0)}], [{"cell": [3, 0]}, {"cell": FAR}])
	var plan: Dictionary = _use(0, "bash", _v(3, 0), {"move_path": [[1, 0], [2, 0]], "order": "move_first"})
	assert_eq(_codes(state, plan), [], "valid when planned")
	var result: Dictionary = _step(state, [plan])
	assert_eq(_cell(result["state"], 0), _v(1, 0), "blocked by its ally")
	var fizzles: Array[Dictionary] = _types(result["events"], "fizzled")
	assert_eq(fizzles.size(), 1)
	assert_eq(fizzles[0]["reason"], "out_of_range")


func _cell(state: FightState, id: int) -> Vector2i:
	return state.cell_of(state.fighters[id])


func test_R3_7_ap_and_cooldown_are_spent_even_when_the_ability_fizzles() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["pin"]}], [{"cell": [3, 0]}, {"cell": FAR}])
	var plans: Array = [_use(0, "pin", _v(3, 0)), TestFixtures.move(1, [[4, -1]])]
	var result: Dictionary = _step(state, plans)
	assert_eq(_types(result["events"], "fizzled").size(), 1)
	assert_eq(result["state"].fighters[0].ap, 4)
	assert_eq(result["state"].fighters[0].cooldowns["pin"], 3, "step 1 + cooldown 2")


func test_R6_3_strike_numbers_come_from_the_start_of_strike() -> void:
	# A curse (Vulnerable +50) lands in the same Strike as a hit on the same target: the hit is
	# computed from the state at the start of Strike, so it is not boosted.
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}, {"cell": _v(1, 1), "abilities": ["curse"]}],
		[{"cell": [1, 0]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0)), _use(1, "curse", _v(1, 0))])
	assert_eq(_types(result["events"], "damaged")[0]["amount"], 18)
	assert_eq(result["state"].fighters[2].hp, 82)
	assert_true(Statuses.index_of(result["state"].fighters[2], "vulnerable") >= 0, "but the status was applied")


func test_R6_7_a_defeated_user_still_finishes_its_own_ability() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["whirl"], "max_hp": 5, "max_mp": 0}, {"cell": _v(-3, 0)}],
		[{"cell": [1, 0], "abilities": ["bash"]}, {"cell": [0, 1]}])
	var result: Dictionary = _step(state, [_use(0, "whirl", _v(0, 0)), _use(2, "bash", _v(0, 0))])
	var after: FightState = result["state"]
	assert_false(after.fighters[0].alive)
	assert_eq(after.fighters[2].hp, 84, "the whirl landed on the first Monster")
	assert_eq(after.fighters[3].hp, 84, "and on the second")


func test_R7_4_a_fighter_defeated_in_strike_loses_its_trail_move() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["smash"]}], [{"cell": [1, 0]}, {"cell": FAR}])
	var plans: Array = [_use(0, "smash", _v(1, 0)), TestFixtures.move(1, [[2, 0]], "ability_first")]
	var result: Dictionary = _step(state, plans)
	assert_false(result["state"].fighters[1].alive)
	assert_eq(_types(result["events"], "moved").size(), 0)
	assert_eq(_types(result["events"], "move_blocked").size(), 0)


func test_R6_2_an_ability_aimed_at_a_cell_hits_whoever_is_there() -> void:
	# Monster 1 leaves (1,0) and Monster 2 takes its place in Lead moves; the Strike aimed at (1,0)
	# hits the one standing there now.
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0]}, {"cell": [2, -1]}])
	var plans: Array = [
		_use(0, "bash", _v(1, 0)),
		TestFixtures.move(1, [[1, 1]]),
		TestFixtures.move(2, [[1, 0]]),
	]
	var result: Dictionary = _step(state, plans)
	var after: FightState = result["state"]
	assert_eq(after.fighters[1].hp, 100, "the Monster that left")
	assert_eq(after.fighters[2].hp, 82, "the Monster that arrived")
	assert_eq(_types(result["events"], "fizzled").size(), 0)


# --- Areas and affects (R6.2) ---


func test_R6_2_burst_hits_enemies_only_and_not_the_user() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["whirl"]}, {"cell": _v(-1, 0)}],
		[{"cell": [1, 0]}, {"cell": [0, 1]}, {"cell": [2, 0]}])
	var result: Dictionary = _step(state, [{"fighter": 0, "ability": "whirl"}])
	var after: FightState = result["state"]
	assert_eq(after.fighters[2].hp, 84)
	assert_eq(after.fighters[3].hp, 84)
	assert_eq(after.fighters[4].hp, 100, "two cells away")
	assert_eq(after.fighters[0].hp, 100, "not the user")
	assert_eq(after.fighters[1].hp, 100, "not its ally")


func test_R6_2_a_line_area_runs_away_from_the_user() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["sweep"]}],
		[{"cell": [1, 0]}, {"cell": [3, 0]}, {"cell": [0, 1]}])
	var result: Dictionary = _step(state, [_use(0, "sweep", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(after.fighters[1].hp, 90)
	assert_eq(after.fighters[2].hp, 90, "three cells from the target start: (1,0), (2,0), (3,0)")
	assert_eq(after.fighters[3].hp, 100, "off the line")


func test_R6_2_area_cells_are_kept_inside_the_arena_in_cell_order() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0), "abilities": ["seed"]}], [{"cell": FAR}])
	var ability: Dictionary = state.abilities["seed"]
	var edge: Array[int] = Abilities.area_cells(state, ability, _index(state, _v(0, 0)), _v(4, 0))
	assert_eq(edge.size(), 4, "a corner-side cell has 4 neighbors in a radius-4 hexagon, plus itself, minus the missing ones")
	var sorted: Array[int] = edge.duplicate()
	sorted.sort()
	assert_eq(edge, sorted)


# --- Prep and effects in order ---


func test_R6_6_guard_shields_allies_and_the_user_for_two_steps() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["guard"], "recharge_steps": 10}, {"cell": _v(-1, 0), "recharge_steps": 10}],
		[{"cell": [1, 0]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [{"fighter": 0, "ability": "guard"}])
	var after: FightState = result["state"]
	assert_eq(Statuses.shield_amount(after.fighters[0]), 20)
	assert_eq(Statuses.shield_amount(after.fighters[1]), 20)
	assert_eq(Statuses.shield_amount(after.fighters[2]), 0, "not the enemy")
	var shield_events: Array[Dictionary] = _types(result["events"], "shield_changed")
	assert_eq([shield_events[0]["fighter"], shield_events[1]["fighter"]], [0, 1], "roster order")
	assert_eq(after.fighters[0].statuses[0]["ends_step"], 3, "applied in step 1, lasts 2 steps")
	var step2: Dictionary = _step(after, [])
	assert_eq(Statuses.shield_amount(step2["state"].fighters[0]), 20, "still there after step 2")
	var step3: Dictionary = _step(step2["state"], [])
	assert_eq(Statuses.shield_amount(step3["state"].fighters[0]), 0, "gone in the Upkeep of step 3")
	var ended: Array[Dictionary] = _types(step3["events"], "status_ended")
	assert_eq(ended.size(), 2)
	assert_eq(ended[0]["phase"], "upkeep")


func test_R7_3_prep_runs_before_strike_so_a_shield_absorbs_the_same_step_hit() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["guard"]}, {"cell": _v(-1, 0)}],
		[{"cell": [-2, 0], "abilities": ["bash"]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [{"fighter": 0, "ability": "guard"}, _use(2, "bash", _v(-1, 0))])
	var hit: Dictionary = _types(result["events"], "damaged")[0]
	assert_eq(hit["amount"], 18)
	assert_eq(hit["absorbed"], 18)
	assert_eq(result["state"].fighters[1].hp, 100)
	assert_eq(Statuses.shield_amount(result["state"].fighters[1]), 2)


func test_R7_3_shield_absorbs_first_then_hp_and_is_removed_at_zero() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0)}], [{"cell": [1, 0]}])
	var events: Array[Dictionary] = []
	Statuses.apply_shield(state, state.fighters[0], 20, 2, 1, events)
	events.clear()
	Damage.apply(state, state.fighters[0], 30, "ability", events)
	assert_eq(state.fighters[0].hp, 90)
	assert_eq(events[0], {"type": "damaged", "fighter": 0, "amount": 30, "absorbed": 20, "cause": "ability", "hp": 90})
	assert_eq(Statuses.shield_amount(state.fighters[0]), 0)
	assert_eq(TestFixtures.event_types(events), ["damaged", "shield_changed", "status_ended"])


func test_R7_3_fixed_damage_is_absorbed_too() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0)}], [{"cell": [1, 0]}])
	var events: Array[Dictionary] = []
	Statuses.apply_shield(state, state.fighters[0], 5, 2, 1, events)
	Damage.apply(state, state.fighters[0], 10, "blight", events)
	assert_eq(state.fighters[0].hp, 95)


func test_R6_6_a_shield_never_stacks() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["guard"]}, {"cell": _v(-1, 0), "abilities": ["guard"]}],
		[{"cell": FAR}])
	var plans: Array = [{"fighter": 0, "ability": "guard"}, {"fighter": 1, "ability": "guard"}]
	var after: FightState = _step(state, plans)["state"]
	assert_eq(Statuses.shield_amount(after.fighters[0]), 20)
	assert_eq(after.fighters[0].statuses.size(), 1)


func test_R6_3_effects_resolve_in_listed_order_pin_damages_then_roots() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["pin"], "recharge_steps": 10}], [{"cell": [3, 0]}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "pin", _v(3, 0))])
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_lt(types.find("damaged"), types.find("status_applied"))
	var target: FighterState = result["state"].fighters[1]
	assert_eq(target.hp, 94)
	assert_eq(target.statuses[0]["name"], "rooted")
	assert_eq(target.statuses[0]["ends_step"], 2, "1 step: ends in the Upkeep of step 2")


func test_R4_5_rooted_blocks_planning_and_moving_during_the_next_step_then_expires() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["pin"], "recharge_steps": 10}], [{"cell": [3, 0]}, {"cell": FAR}])
	var step1: FightState = _step(state, [_use(0, "pin", _v(3, 0))])["state"]
	var plan: Dictionary = TestFixtures.move(1, [[2, 0]])
	assert_true(_codes(step1, plan).has("cannot_move"))
	var step2: Dictionary = _step(step1, [plan])
	assert_eq(_cell(step2["state"], 1), _v(3, 0), "it could not move")
	assert_eq(_types(step2["events"], "move_blocked")[0]["reason"], "rooted")
	assert_eq(Statuses.index_of(step2["state"].fighters[1], "rooted"), -1, "expired in step 2's Upkeep")
	assert_eq(_types(step2["events"], "status_ended")[0]["status"], "rooted")


func test_R6_6_reapplying_a_status_replaces_it() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0)}], [{"cell": [1, 0]}])
	var events: Array[Dictionary] = []
	Statuses.apply(state, state.fighters[1], "vulnerable", 50, 2, 0, events)
	Statuses.apply(state, state.fighters[1], "vulnerable", 25, 3, 0, events)
	assert_eq(state.fighters[1].statuses.size(), 1)
	assert_eq(state.fighters[1].statuses[0]["magnitude"], 25)
	assert_eq(state.fighters[1].statuses[0]["ends_step"], 4)


func test_R7_4_a_defeated_fighters_statuses_end_with_it() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0)}, {"cell": _v(-1, 0)}], [{"cell": [1, 0]}, {"cell": FAR}])
	var events: Array[Dictionary] = []
	Statuses.apply(state, state.fighters[2], "vulnerable", 50, 5, 0, events)  # applied by Creature 0
	Statuses.apply(state, state.fighters[0], "vulnerable", 50, 5, 2, events)  # applied by the Monster
	Defeat.apply(state, state.fighters[0], events)
	assert_eq(state.fighters[2].statuses.size(), 0, "what the defeated fighter applied is gone")
	assert_eq(state.fighters[0].statuses.size(), 0, "and so is what it carried")


func test_R6_1_cooldown_n_means_usable_again_n_steps_later() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["guard"]}], [{"cell": FAR}])
	var plan: Dictionary = {"fighter": 0, "ability": "guard"}
	var step2: FightState = _step(state, [plan])["state"]
	assert_eq(step2.step, 2)
	assert_true(_codes(step2, plan).has("on_cooldown"))
	var step3: FightState = _step(step2, [])["state"]
	assert_eq(step3.step, 3)
	assert_eq(_codes(step3, plan), [], "guard has cooldown 2: used in step 1, usable again in step 3")


# --- Footprints (R11.2) ---


func test_R11_2_a_footprint_only_ability_just_marks_its_area() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["seed"]}], [{"cell": FAR}], {"karma": [[3, 0, 2]]})
	var result: Dictionary = _step(state, [_use(0, "seed", _v(3, 0))])
	var after: FightState = result["state"]
	var changes: Array[Dictionary] = _types(result["events"], "karma_changed")
	assert_eq(changes.size(), 6, "the 7 cells of the burst, minus the one already at +2")
	assert_eq(after.karma[_index(after, _v(3, 0))], 2, "clamped")
	assert_eq(after.karma[_index(after, _v(2, 0))], 1)
	var cells: Array[Vector2i] = []
	for change: Dictionary in changes:
		cells.append(Vector2i(int(change["cell"][0]), int(change["cell"][1])))
	for i: int in range(1, cells.size()):
		assert_true(Hex.cell_less(cells[i - 1], cells[i]), "cell order")
	assert_eq(_types(result["events"], "ability_used").size(), 1)


func test_R11_3_the_footprint_comes_after_the_defeat() -> void:
	# A Monster on Pure ground is Cleansed (Renewal: +1), and then the strike's -1 footprint lands.
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0], "max_hp": 10}, {"cell": FAR}], {"karma": [[1, 0, 1]]})
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(_types(result["events"], "defeated")[0]["how"], "cleansed")
	assert_eq(after.cleansed_count, 1)
	var cell_changes: Array[Array] = []
	for change: Dictionary in _types(result["events"], "karma_changed"):
		if change["cell"] == [1, 0]:
			cell_changes.append([change["from"], change["to"]])
	assert_eq(cell_changes, [[1, 2], [2, 1]], "Renewal first, then the footprint")
	assert_eq(after.karma[_index(after, _v(1, 0))], 1)


func test_R11_3_a_kill_on_neutral_ground_blights_the_cell() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0], "max_hp": 10}, {"cell": FAR}])
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	assert_eq(_types(result["events"], "defeated")[0]["how"], "killed")
	assert_eq(result["state"].karma[_index(result["state"], _v(1, 0))], Land.BLIGHTED)


# --- Costs and events ---


func test_R6_1_a_used_ability_spends_its_ap() -> void:
	var state: FightState = _single_hit_state()
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	assert_eq(result["state"].fighters[0].ap, 3)
	assert_eq(_types(result["events"], "ap_spent")[0], {"type": "ap_spent", "fighter": 0, "amount": 3, "ap": 3, "step": 1, "phase": "strike"})
	var used: Dictionary = _types(result["events"], "ability_used")[0]
	assert_eq(used["ability"], "bash")
	assert_eq(used["cell"], [1, 0])


func test_events_of_a_phase_carry_that_phase() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["guard"]}], [{"cell": FAR}])
	var result: Dictionary = _step(state, [{"fighter": 0, "ability": "guard"}])
	assert_eq(_types(result["events"], "shield_changed")[0]["phase"], "prep")


func test_ability_state_is_copied_by_clone() -> void:
	var state: FightState = _single_hit_state()
	state.fighters[0].cooldowns["bash"] = 4
	var copy: FightState = state.clone()
	copy.fighters[0].cooldowns["bash"] = 9
	copy.fighters[0].statuses.append(TestFixtures.status("rooted"))
	assert_eq(state.fighters[0].cooldowns["bash"], 4)
	assert_eq(state.fighters[0].statuses.size(), 0)
	assert_same(copy.abilities, state.abilities)


func test_create_rejects_unknown_abilities() -> void:
	var roster: Array = [TestFixtures.creature({"abilities": ["bash", "nope"]}), TestFixtures.monster([3, 0])]
	var result: Dictionary = RulesEngine.create(TestFixtures.arena(), roster, TestFixtures.rules(), 1, TestFixtures.defs())
	assert_false(result["ok"])
	assert_string_contains(str(result["errors"]), "unknown ability nope")


func test_create_rejects_abilities_that_apply_unknown_statuses() -> void:
	var defs: Dictionary = TestFixtures.defs()
	(defs["statuses"] as Dictionary).erase("rooted")
	var roster: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0])]
	var result: Dictionary = RulesEngine.create(TestFixtures.arena(), roster, TestFixtures.rules(), 1, defs)
	assert_false(result["ok"])
	assert_string_contains(str(result["errors"]), "unknown status rooted")


# --- Queries ---


func test_targets_lists_the_valid_cells_from_a_planned_position() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["shot", "bash"]}], [{"cell": [2, 0]}, {"cell": [3, 0]}])
	var shot: PackedInt32Array = RulesEngine.targets(state, 0, "shot", _v(0, 0))
	assert_eq(shot, PackedInt32Array([_index(state, _v(2, 0))]), "(3,0) is behind the first Monster")
	var from_other_side: PackedInt32Array = RulesEngine.targets(state, 0, "shot", _v(5 - 5, 1))
	assert_true(from_other_side.size() <= 2)
	assert_eq(RulesEngine.targets(state, 0, "bash", _v(0, 0)).size(), 0, "no enemy adjacent")
	assert_eq(RulesEngine.targets(state, 0, "bash", _v(1, 0)), PackedInt32Array([_index(state, _v(2, 0))]), "adjacent from (1,0)")


func test_threat_zone_is_every_cell_it_could_reach_and_hit() -> void:
	var state: FightState = _setup(
		[{"cell": _v(-4, 4)}], [{"cell": [0, 0], "abilities": ["bash"], "max_mp": 2}, {"cell": [4, -4], "abilities": []}])
	var zone: PackedInt32Array = RulesEngine.threat_zone(state, 1)
	var expected: PackedInt32Array = PackedInt32Array()
	for cell: Vector2i in Hex.disk(_v(0, 0), 3):
		expected.append(_index(state, cell))
	expected.sort()
	assert_eq(zone, expected, "2 MP, then a range-1 hit: a radius-3 disk")


func test_threat_zone_ignores_friendly_expensive_and_cooling_abilities() -> void:
	var state: FightState = _setup(
		[{"cell": _v(-4, 4)}], [{"cell": [0, 0], "abilities": ["guard", "seed"]}, {"cell": [4, -4], "abilities": []}])
	assert_eq(RulesEngine.threat_zone(state, 1).size(), 0, "nothing hostile")
	var poor: FightState = _setup(
		[{"cell": _v(-4, 4)}], [{"cell": [0, 0], "abilities": ["bash"]}, {"cell": [4, -4], "abilities": []}])
	poor.fighters[1].ap = 2
	assert_eq(RulesEngine.threat_zone(poor, 1).size(), 0, "cannot afford it")
	var cooling: FightState = _setup(
		[{"cell": _v(-4, 4)}], [{"cell": [0, 0], "abilities": ["bash"]}, {"cell": [4, -4], "abilities": []}])
	cooling.fighters[1].cooldowns["bash"] = 5
	assert_eq(RulesEngine.threat_zone(cooling, 1).size(), 0, "on cooldown")


func test_threat_zone_follows_line_of_sight_and_blocked_movement() -> void:
	var state: FightState = _setup(
		[{"cell": _v(-4, 4)}],
		[{"cell": [0, 0], "abilities": ["shot"], "max_mp": 0}, {"cell": [4, -4], "abilities": []}],
		{"obstacles": [[1, 0], [1, -1], [0, -1], [-1, 0], [-1, 1], [0, 1]]})
	var zone: PackedInt32Array = RulesEngine.threat_zone(state, 1)
	assert_eq(zone.size(), 0, "walled in: every target in range is behind a wall (the first ring blocks LoS), and range is 2+")
