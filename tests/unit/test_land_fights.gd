extends GutTest
## T8: the Land in fights (GDD R11, R3.6, R3.8): Upkeep blight and thrive, the Land phase and its
## cadence, the forecast query, Collapse and Bloom checkpoints, the Monster footprint cap.

const FAR: Array = [4, -4]


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


## Same shape as the ability tests' helper, but the Land phase runs every step unless overridden.
func _setup(creatures: Array, monsters: Array, arena: Dictionary = {}, rules: Dictionary = {}) -> FightState:
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
	return TestFixtures.running(roster, cells, arena, 1, rules)


func _use(fighter: int, ability: String, target: Vector2i) -> Dictionary:
	return {"fighter": fighter, "ability": ability, "target_cell": [target.x, target.y]}


func _step(state: FightState, plans: Array = []) -> Dictionary:
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_true(result["ok"], str(result["errors"]))
	return result


func _types(events: Array, type: String) -> Array[Dictionary]:
	return TestFixtures.of_type(events, type)


func _karma(state: FightState, cell: Vector2i) -> int:
	return state.karma[state.grid.index_of(cell)]


func _create_with(defs: Dictionary, roster: Array, arena: Dictionary = {}) -> Dictionary:
	return RulesEngine.create(TestFixtures.arena(arena), roster, TestFixtures.rules(), 1, defs)


# --- The Monster footprint cap (R11.2) ---


func test_R11_2_monster_abilities_may_only_have_karma_0_or_minus_1_on_a_single_cell() -> void:
	var defs: Dictionary = TestFixtures.defs()
	var abilities: Dictionary = defs["abilities"]
	abilities["nip"] = TestFixtures.ability("nip", {"karma": 0})
	abilities["ruin_one"] = TestFixtures.ability("ruin_one", {"karma": -2})
	abilities["ruin_area"] = TestFixtures.ability("ruin_area", {"karma": -1, "area": {"shape": "burst", "radius": 1}})
	abilities["purge"] = TestFixtures.ability("purge", {"karma": 1})
	for id: String in ["bash", "nip"]:
		var ok: Dictionary = _create_with(defs, [TestFixtures.creature(), TestFixtures.monster([3, 0], {"abilities": [id]})])
		assert_true(ok["ok"], "%s is allowed: %s" % [id, str(ok["errors"])])
	for id: String in ["ruin_one", "ruin_area", "purge", "seed", "guard"]:
		var bad: Dictionary = _create_with(defs, [TestFixtures.creature(), TestFixtures.monster([3, 0], {"abilities": [id]})])
		assert_false(bad["ok"], "%s is rejected for a Monster" % id)
		assert_string_contains(str(bad["errors"]), "footprint cap")


func test_R11_2_creatures_are_not_capped() -> void:
	var roster: Array = [TestFixtures.creature({"abilities": ["seed", "whirl", "guard"]}), TestFixtures.monster([3, 0])]
	var result: Dictionary = _create_with(TestFixtures.defs(), roster)
	assert_true(result["ok"], str(result["errors"]))


func test_R11_6_the_arena_needs_collapse_and_bloom_thresholds() -> void:
	var roster: Array = [TestFixtures.creature(), TestFixtures.monster([3, 0])]
	for arena: Dictionary in [
		{"collapse_at": null}, {"bloom_at": null}, {"collapse_at": 5}, {"bloom_at": -5}, {"collapse_at": 0},
	]:
		var result: Dictionary = _create_with(TestFixtures.defs(), roster, arena)
		assert_false(result["ok"], "rejects %s" % str(arena))
	var bare: Dictionary = RulesEngine.create({"radius": 4, "creature_start_cells": [[0, 0]]}, roster, TestFixtures.rules(), 1, TestFixtures.defs())
	assert_false(bare["ok"], "no thresholds at all")


# --- Upkeep: blight and thrive on occupants (R3.6) ---


func test_R3_6_blighted_ground_hurts_whoever_stands_on_it_at_upkeep() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0)}], [{"cell": [1, 0]}], {"karma": [[0, 0, -2]]}, {"land_phase_every_steps": 1000})
	var result: Dictionary = _step(state)
	var hits: Array[Dictionary] = _types(result["events"], "damaged")
	assert_eq(hits.size(), 1)
	assert_eq(hits[0]["cause"], "blight")
	assert_eq(hits[0]["amount"], 10)
	assert_eq(hits[0]["phase"], "upkeep")
	assert_eq(result["state"].fighters[0].hp, 90)


func test_R3_6_blightborn_ignore_blighted_ground_and_thriving_ground_heals() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0)}], [{"cell": [1, 0], "max_hp": 100}, {"cell": [2, 0], "max_hp": 100}],
		{"karma": [[1, 0, -2], [2, 0, 2]]}, {"land_phase_every_steps": 1000})
	state.fighters[2].hp = 50
	var result: Dictionary = _step(state)
	var after: FightState = result["state"]
	assert_eq(after.fighters[1].hp, 100, "Blightborn: no blight damage")
	assert_eq(after.fighters[2].hp, 58, "thrive_heal = 8")
	assert_eq(_types(result["events"], "healed")[0]["cause"], "thrive")
	var full: Dictionary = _step(_setup([{"cell": _v(0, 0)}], [{"cell": [2, 0]}], {"karma": [[2, 0, 2]]}, {"land_phase_every_steps": 1000}))
	assert_eq(_types(full["events"], "healed").size(), 0, "nothing to heal at full HP")


func test_R7_3_a_shield_absorbs_blight_damage() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0)}], [{"cell": [1, 0]}], {"karma": [[0, 0, -2]]}, {"land_phase_every_steps": 1000})
	var events: Array[Dictionary] = []
	Statuses.apply_shield(state, state.fighters[0], 25, 3, 1, events)
	var after: FightState = _step(state)["state"]
	assert_eq(after.fighters[0].hp, 100)
	assert_eq(Statuses.shield_amount(after.fighters[0]), 15)


func test_R3_6_land_effects_use_the_karma_from_before_the_land_phase() -> void:
	# The creature's cell turns Blighted in this step's Land phase, but it only hurts at the next Upkeep.
	var state: FightState = _setup(
		[{"cell": _v(0, 0)}], [{"cell": FAR}], {"karma": [[0, 0, -1], [1, 0, -2]]})
	var step1: Dictionary = _step(state)
	assert_eq(_karma(step1["state"], _v(0, 0)), Land.BLIGHTED, "the Land phase blighted it")
	assert_eq(step1["state"].fighters[0].hp, 100, "no damage yet")
	var step2: Dictionary = _step(step1["state"])
	assert_eq(step2["state"].fighters[0].hp, 90)


func test_R7_4_blight_can_defeat_a_creature_in_upkeep() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "max_hp": 5}, {"cell": _v(-3, 0)}], [{"cell": FAR}],
		{"karma": [[0, 0, -2]]}, {"land_phase_every_steps": 1000})
	var result: Dictionary = _step(state)
	assert_false(result["state"].fighters[0].alive)
	assert_eq(_types(result["events"], "defeated")[0]["how"], "downed")
	assert_eq(result["state"].status, FightState.STATUS_FIGHTING)


func test_R7_4_the_last_creature_blighted_in_upkeep_is_a_defeat() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "max_hp": 5}], [{"cell": FAR}], {"karma": [[0, 0, -2]]}, {"land_phase_every_steps": 1000})
	var result: Dictionary = _step(state)
	assert_eq(result["state"].outcome, "defeat")
	assert_eq(_types(result["events"], "land_phase").size(), 0, "the fight ended before the Land phase")


# --- The Land phase (R11.4) ---


func test_R11_4_the_land_phase_follows_the_refills_and_lists_changed_cells_in_cell_order() -> void:
	var ring: Array = []
	for cell: Vector2i in Hex.ring(_v(0, 0), 1):
		ring.append([cell.x, cell.y, -2])
	var state: FightState = _setup([{"cell": _v(-4, 4)}], [{"cell": FAR}], {"karma": ring})
	var result: Dictionary = _step(state)
	var types: Array[String] = TestFixtures.event_types(result["events"])
	var land_index: int = types.find("land_phase")
	assert_gt(land_index, 0)
	assert_eq(types[land_index + 1], "karma_changed")
	var land: Dictionary = _types(result["events"], "land_phase")[0]
	assert_eq(land["phase"], "upkeep")
	assert_eq(land["board_karma"], -13, "the ring's empty middle corrupts: -12 + -1")
	assert_eq(_karma(result["state"], _v(0, 0)), Land.CORRUPTED)
	assert_eq(result["state"].board_karma(), -13)
	assert_eq(_types(result["events"], "karma_changed").size(), 1)


func test_R11_4_changed_cells_are_reported_in_cell_order() -> void:
	var state: FightState = _setup([{"cell": _v(-4, 4)}], [{"cell": FAR}], {"karma": _field(-1) + [[0, 0, -2]]})
	var cells: Array[Vector2i] = []
	for change: Dictionary in _types(_step(state)["events"], "karma_changed"):
		cells.append(Vector2i(int(change["cell"][0]), int(change["cell"][1])))
	assert_gt(cells.size(), 2)
	for i: int in range(1, cells.size()):
		assert_true(Hex.cell_less(cells[i - 1], cells[i]))


func _field(value: int) -> Array:
	var entries: Array = []
	for cell: Vector2i in Hex.disk(_v(0, 0), 4):
		entries.append([cell.x, cell.y, value])
	return entries


func test_R11_4_the_land_phase_runs_every_land_phase_every_steps_steps() -> void:
	var state: FightState = _setup([{"cell": _v(-4, 4)}], [{"cell": FAR}], {}, {"land_phase_every_steps": 2})
	var step1: Dictionary = _step(state)
	assert_eq(_types(step1["events"], "land_phase").size(), 0, "step 1")
	var step2: Dictionary = _step(step1["state"])
	assert_eq(_types(step2["events"], "land_phase").size(), 1, "step 2")
	var step3: Dictionary = _step(step2["state"])
	assert_eq(_types(step3["events"], "land_phase").size(), 0, "step 3")


func test_R11_4_a_land_phase_that_changes_nothing_still_reports_itself() -> void:
	var result: Dictionary = _step(_setup([{"cell": _v(-4, 4)}], [{"cell": FAR}]))
	assert_eq(_types(result["events"], "land_phase").size(), 1)
	assert_eq(_types(result["events"], "karma_changed").size(), 0)


# --- Forecast (R11.5) ---


func test_R11_5_forecast_says_what_the_next_land_phase_would_change() -> void:
	var state: FightState = _setup([{"cell": _v(-4, 4)}], [{"cell": FAR}], {"karma": _field(-1) + [[0, 0, -2]]})
	var forecast: Dictionary = RulesEngine.forecast(state)
	var changed: PackedInt32Array = forecast["changed"]
	assert_gt(changed.size(), 0)
	assert_eq(forecast["steps_until"], 0, "every step: this step's Upkeep")
	var result: Dictionary = _step(state)
	var reported: Array[int] = []
	for change: Dictionary in _types(result["events"], "karma_changed"):
		reported.append(state.grid.index_of(Vector2i(int(change["cell"][0]), int(change["cell"][1]))))
	var predicted: Array[int] = []
	for index: int in changed:
		predicted.append(index)
	assert_eq(reported, predicted, "the forecast matches what happens")
	assert_eq(forecast["board_karma_after"], result["state"].board_karma())


func test_R11_5_forecast_counts_steps_until_the_next_phase() -> void:
	var state: FightState = _setup([{"cell": _v(-4, 4)}], [{"cell": FAR}], {}, {"land_phase_every_steps": 3})
	assert_eq(RulesEngine.forecast(state)["steps_until"], 2, "at step 1: the phase is in step 3")
	var step2: FightState = _step(state)["state"]
	assert_eq(RulesEngine.forecast(step2)["steps_until"], 1)
	var step3: FightState = _step(step2)["state"]
	assert_eq(RulesEngine.forecast(step3)["steps_until"], 0)


# --- Collapse and Bloom (R3.8, R11.6) ---


func test_R3_8_collapse_ends_the_fight_when_board_karma_reaches_collapse_at() -> void:
	# Board karma -4; Bash's -1 footprint brings it to -5 = collapse_at.
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0]}, {"cell": FAR}],
		{"karma": [[-3, 3, -2], [-3, 2, -2]], "collapse_at": -5})
	assert_eq(state.board_karma(), -4)
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	var after: FightState = result["state"]
	assert_eq(after.outcome, "collapse")
	assert_eq(after.status, FightState.STATUS_ENDED)
	assert_eq(after.board_karma(), -5)
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_eq(types[types.size() - 1], "fight_ended")
	assert_eq(_types(result["events"], "land_phase").size(), 0, "stopped at the Strike checkpoint")
	assert_eq(after.step, 1, "the step did not finish")


func test_R3_8_collapse_beats_a_victory_won_on_the_same_blow() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0], "max_hp": 10}],
		{"karma": [[-3, 3, -2], [-3, 2, -2]], "collapse_at": -5})
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	assert_eq(_types(result["events"], "defeated")[0]["how"], "killed")
	assert_eq(result["state"].outcome, "collapse", "the Kill blights the cell: -4 - 2 - 1 <= -5")


func test_R3_8_bloom_wins_for_the_keepers_and_cleanses_every_remaining_monster() -> void:
	# Seed's +1 footprint on 7 Neutral cells brings board karma to +7 = bloom_at.
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["seed"]}], [{"cell": [1, 3]}, {"cell": [-3, 3]}],
		{"bloom_at": 7})
	var result: Dictionary = _step(state, [_use(0, "seed", _v(3, -2))])
	var after: FightState = result["state"]
	assert_eq(after.outcome, "bloom")
	assert_eq(after.cleansed_count, 2)
	for id: int in [1, 2]:
		assert_false(after.fighters[id].alive)
	var kinds: Array[String] = []
	for event: Dictionary in _types(result["events"], "defeated"):
		kinds.append(str(event["how"]))
	assert_eq(kinds, ["cleansed", "cleansed"])
	var types: Array[String] = TestFixtures.event_types(result["events"])
	assert_eq(types[types.size() - 1], "fight_ended")
	assert_eq(_types(result["events"], "fight_ended")[0]["outcome"], "bloom")
	assert_gte(after.board_karma(), 7)


func test_R3_8_a_normal_victory_still_ends_as_a_victory() -> void:
	var state: FightState = _setup(
		[{"cell": _v(0, 0), "abilities": ["bash"]}], [{"cell": [1, 0], "max_hp": 10}], {"karma": [[1, 0, 1]]})
	var result: Dictionary = _step(state, [_use(0, "bash", _v(1, 0))])
	assert_eq(result["state"].outcome, "victory")
	assert_eq(result["state"].cleansed_count, 1)


func test_R3_8_the_land_check_runs_whenever_the_outcome_is_checked() -> void:
	var state: FightState = _setup([{"cell": _v(0, 0)}], [{"cell": FAR}], {"collapse_at": -3})
	state.karma[state.grid.index_of(_v(-2, 2))] = -2
	state.karma[state.grid.index_of(_v(-3, 2))] = -2
	var events: Array[Dictionary] = []
	assert_true(Scheduler.check_outcome(state, events))
	assert_eq(state.outcome, "collapse")
	assert_eq(events[events.size() - 1]["outcome"], "collapse")
