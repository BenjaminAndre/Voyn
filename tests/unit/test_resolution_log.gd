extends GutTest
## Round 2, item 2.5: the resolution log, built from the event stream.

const FAR: Array = [4, -4]


func _v(q: int, r: int) -> Vector2i:
	return Vector2i(q, r)


func _state() -> FightState:
	var roster: Array = [
		TestFixtures.creature({"abilities": ["bash", "shove", "guard"], "name": "PH Tank", "recharge_steps": 10}),
		TestFixtures.monster([1, 0], {"abilities": ["bash"], "name": "PH Brute", "traits": ["blightborn"]}),
		TestFixtures.monster(FAR, {"name": "PH Flier"}),
	]
	return TestFixtures.running(roster, [_v(0, 0)], {"karma": [[-3, 3, -2]]}, 1, {"land_phase_every_steps": 1})


func _log_for(state: FightState, plans: Array) -> ResolutionLog:
	var result: Dictionary = TestFixtures.resolve(state, plans)
	assert_true(result["ok"], str(result["errors"]))
	var log: ResolutionLog = ResolutionLog.new()
	for event: Dictionary in result["events"]:
		log.add(event, state)
	return log


func _lines(log: ResolutionLog) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in log.entries:
		out.append(str(entry["text"]))
	return out


func test_a_step_lists_its_phases_in_order() -> void:
	var log: ResolutionLog = _log_for(_state(), [])
	var headings: Array[String] = []
	for entry: Dictionary in log.entries:
		if entry["kind"] == "heading":
			headings.append(str(entry["text"]))
	assert_eq(headings, ["Lead moves", "Prep", "Dash", "Strike", "Trail moves", "Upkeep"])
	assert_eq(log.entries[0]["kind"], "step")
	assert_eq(log.entries[0]["text"], "Step 1")


func test_moves_are_summed_into_one_line_per_fighter() -> void:
	var state: FightState = _state()
	var log: ResolutionLog = _log_for(state, [TestFixtures.move(0, [[0, -1], [0, -2]])])
	assert_true(_lines(log).has("Tank moves 2 cells"))
	var one: ResolutionLog = _log_for(state, [TestFixtures.move(0, [[-1, 0]])])
	assert_true(_lines(one).has("Tank moves 1 cell"))


func test_abilities_and_damage_read_in_plain_words() -> void:
	var state: FightState = _state()
	var log: ResolutionLog = _log_for(state, [{"fighter": 0, "ability": "bash", "target_cell": [1, 0]}])
	var lines: Array[String] = _lines(log)
	assert_true(lines.has("Tank uses bash"))
	assert_true(lines.has("Brute takes 18"))
	var text: String = log.text()
	assert_true(text.find("Strike:") < text.find("Tank uses bash"), "under the Strike heading")
	assert_true(text.find("Tank uses bash") < text.find("Trail moves:"))


func test_fizzles_and_blocks_are_logged() -> void:
	var state: FightState = _state()
	var plans: Array = [{"fighter": 0, "ability": "bash", "target_cell": [1, 0]}, TestFixtures.move(1, [[2, 0]])]
	var log: ResolutionLog = _log_for(state, plans)
	var joined: String = "\n".join(_lines(log))
	assert_string_contains(joined, "fizzles (bad target)")
	assert_string_contains(joined, "Brute moves 1 cell")
	var blocked: ResolutionLog = _log_for(state, [TestFixtures.move(0, [[1, 0]])])
	assert_string_contains("\n".join(_lines(blocked)), "Tank is blocked (occupied)")


func test_pushes_collisions_shields_and_statuses() -> void:
	var state: FightState = _state()
	var log: ResolutionLog = _log_for(state, [{"fighter": 0, "ability": "shove", "target_cell": [1, 0]}])
	var joined: String = "\n".join(_lines(log))
	assert_string_contains(joined, "Brute is displaced 2 cells")
	assert_string_contains(joined, "Brute takes 6")
	var guard: ResolutionLog = _log_for(_state(), [{"fighter": 0, "ability": "guard"}])
	assert_string_contains("\n".join(_lines(guard)), "Tank shield: 20")
	var walled: FightState = TestFixtures.running(
		[TestFixtures.creature({"abilities": ["shove"], "name": "PH Tank"}), TestFixtures.monster([1, 0], {"name": "PH Brute"}), TestFixtures.monster(FAR)],
		[_v(0, 0)], {"obstacles": [[2, 0]]}, 1, {"land_phase_every_steps": 1000})
	var crash: ResolutionLog = _log_for(walled, [{"fighter": 0, "ability": "shove", "target_cell": [1, 0]}])
	var crash_text: String = "\n".join(_lines(crash))
	assert_string_contains(crash_text, "Brute collides, 2 cells short")
	assert_string_contains(crash_text, "Brute takes 16 from collision")


func test_defeats_land_changes_and_refills() -> void:
	var state: FightState = TestFixtures.running(
		[TestFixtures.creature({"abilities": ["bash"], "name": "PH Tank"}), TestFixtures.monster([1, 0], {"name": "PH Brute", "max_hp": 10}), TestFixtures.monster(FAR, {"name": "PH Flier"})],
		[_v(0, 0)], {"karma": [[1, 0, 1]]}, 1, {"land_phase_every_steps": 1})
	var log: ResolutionLog = _log_for(state, [{"fighter": 0, "ability": "bash", "target_cell": [1, 0]}])
	var joined: String = "\n".join(_lines(log))
	assert_string_contains(joined, "Brute is Cleansed")
	assert_string_contains(joined, "cells change karma")


func test_the_land_phase_is_logged() -> void:
	var log: ResolutionLog = _log_for(_state(), [])
	assert_string_contains("\n".join(_lines(log)), "The Land answers: board karma")


func test_the_log_keeps_the_last_step_until_the_next_one_starts() -> void:
	var state: FightState = _state()
	var first: Dictionary = TestFixtures.resolve(state, [])
	var log: ResolutionLog = ResolutionLog.new()
	for event: Dictionary in first["events"]:
		log.add(event, state)
	assert_gt(log.entries.size(), 5)
	assert_eq(log.entries[0]["text"], "Step 1")
	var second: Dictionary = TestFixtures.resolve(first["state"], [])
	log.add(second["events"][0], first["state"])
	assert_eq(log.entries.size(), 1, "the first event of the next step replaces the old log")
	assert_eq(log.entries[0]["text"], "Step 2")


func test_events_that_say_nothing_new_add_no_lines() -> void:
	var state: FightState = _state()
	var log: ResolutionLog = ResolutionLog.new()
	log.add({"type": "ap_spent", "fighter": 0, "amount": 3, "ap": 3}, state)
	log.add({"type": "placed", "fighter": 0, "cell": [0, 0]}, state)
	assert_eq(log.entries.size(), 0)


func test_bbcode_escapes_brackets_and_text_has_headings() -> void:
	var log: ResolutionLog = _log_for(_state(), [])
	assert_string_contains(log.bbcode(), "[b]")
	assert_string_contains(log.text(), "Lead moves:")
	var odd: ResolutionLog = ResolutionLog.new()
	odd.entries.append({"kind": "line", "text": "a [b] c", "fighter": -1, "tag": "", "count": 0})
	assert_false(odd.bbcode().contains("a [b] c"))
