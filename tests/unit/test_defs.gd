extends GutTest
## T7: content schemas for abilities, statuses and behaviors (docs/architecture.md, Content schemas).


func _raw_ability() -> Dictionary:
	return {
		"id": "bash", "name": "Bash", "phase": "strike", "ap_cost": 3, "cooldown": 0, "target": "enemy",
		"min_range": 1, "max_range": 1, "needs_los": false, "line_only": false,
		"area": {"shape": "single"}, "affects": "enemies", "include_user": false,
		"effects": [{"type": "damage", "base": 18}], "karma": -1,
	}


func _errors_contain(result: Dictionary, needle: String) -> bool:
	for message: String in result["errors"]:
		if message.contains(needle):
			return true
	return false


func test_a_valid_ability_passes_and_keeps_its_values() -> void:
	var result: Dictionary = Defs.ability(_raw_ability())
	assert_true(result["ok"], str(result["errors"]))
	assert_eq(result["value"]["id"], "bash")
	assert_eq(result["value"]["karma"], -1)


func test_json_floats_become_ints() -> void:
	var raw: Dictionary = _raw_ability()
	raw["ap_cost"] = 3.0
	raw["effects"] = [{"type": "damage", "base": 18.0}]
	var result: Dictionary = Defs.ability(JSON.parse_string(JSON.stringify(raw)))
	assert_true(result["ok"], str(result["errors"]))
	assert_typeof(result["value"]["ap_cost"], TYPE_INT)
	assert_typeof(result["value"]["effects"][0]["base"], TYPE_INT)


func test_fractional_numbers_are_rejected() -> void:
	var raw: Dictionary = _raw_ability()
	raw["ap_cost"] = 2.5
	var result: Dictionary = Defs.ability(raw)
	assert_false(result["ok"])
	assert_true(_errors_contain(result, "must be an integer"))


func test_empty_effects_are_allowed_for_footprint_only_abilities() -> void:
	var raw: Dictionary = _raw_ability()
	raw["effects"] = []
	assert_true(Defs.ability(raw)["ok"])


func test_include_user_defaults_to_false_and_name_is_optional() -> void:
	var raw: Dictionary = _raw_ability()
	raw.erase("include_user")
	raw.erase("name")
	var result: Dictionary = Defs.ability(raw)
	assert_true(result["ok"], str(result["errors"]))
	assert_eq(result["value"]["include_user"], false)


func test_doc_key_is_allowed_and_dropped() -> void:
	var raw: Dictionary = _raw_ability()
	raw["_doc"] = "notes"
	var result: Dictionary = Defs.ability(raw)
	assert_true(result["ok"])
	assert_false((result["value"] as Dictionary).has("_doc"))


func test_missing_and_unknown_keys_are_rejected() -> void:
	var missing: Dictionary = _raw_ability()
	missing.erase("karma")
	assert_true(_errors_contain(Defs.ability(missing), "missing key karma"))
	var unknown: Dictionary = _raw_ability()
	unknown["colour"] = "red"
	assert_true(_errors_contain(Defs.ability(unknown), "unknown key colour"))


func test_bad_values_are_rejected() -> void:
	var cases: Dictionary = {
		"phase": "later", "target": "everyone", "affects": "nobody", "ap_cost": -1,
		"needs_los": "yes", "min_range": 3, "id": "",
	}
	for key: String in cases.keys():
		var raw: Dictionary = _raw_ability()
		raw[key] = cases[key]
		assert_false(Defs.ability(raw)["ok"], "rejects %s = %s" % [key, str(cases[key])])


func test_max_range_cannot_be_below_min_range() -> void:
	var raw: Dictionary = _raw_ability()
	raw["min_range"] = 3
	raw["max_range"] = 2
	assert_true(_errors_contain(Defs.ability(raw), "max_range must be >= min_range"))


func test_areas_need_their_parameters() -> void:
	var burst: Dictionary = _raw_ability()
	burst["area"] = {"shape": "burst"}
	assert_false(Defs.ability(burst)["ok"])
	burst["area"] = {"shape": "burst", "radius": 2}
	assert_true(Defs.ability(burst)["ok"])
	var line: Dictionary = _raw_ability()
	line["area"] = {"shape": "line", "length": 3}
	assert_true(_errors_contain(Defs.ability(line), "line_only"), "a line needs line_only")
	line["line_only"] = true
	assert_true(Defs.ability(line)["ok"])
	var bad: Dictionary = _raw_ability()
	bad["area"] = {"shape": "cone"}
	assert_false(Defs.ability(bad)["ok"])


func test_effect_shapes_are_checked() -> void:
	var good: Array = [
		{"type": "damage", "base": 5}, {"type": "heal", "amount": 5},
		{"type": "shield", "amount": 20, "duration": 2},
		{"type": "apply_status", "status": "rooted", "duration": 1, "magnitude": 0},
	]
	var raw: Dictionary = _raw_ability()
	raw["effects"] = good
	assert_true(Defs.ability(raw)["ok"], str(Defs.ability(raw)["errors"]))
	for bad: Dictionary in [
		{"type": "damage"}, {"type": "damage", "base": -1}, {"type": "shield", "amount": 0, "duration": 2},
		{"type": "shield", "amount": 5, "duration": 0}, {"type": "apply_status", "status": "", "duration": 1, "magnitude": 0},
		{"type": "explode", "base": 1}, {"type": "damage", "base": 1, "extra": 1},
	]:
		var broken: Dictionary = _raw_ability()
		broken["effects"] = [bad]
		assert_false(Defs.ability(broken)["ok"], "rejects %s" % str(bad))


func test_effects_not_supported_yet_are_rejected_clearly() -> void:
	for type: String in ["mutate", "telegraph"]:
		var raw: Dictionary = _raw_ability()
		raw["effects"] = [{"type": type}]
		assert_true(_errors_contain(Defs.ability(raw), "not supported yet"), type)


func test_chance_is_not_supported_until_the_gdd_settles_it() -> void:
	var raw: Dictionary = _raw_ability()
	raw["effects"] = [{"type": "damage", "base": 5, "chance": 50}]
	var result: Dictionary = Defs.ability(raw)
	assert_false(result["ok"])
	assert_true(_errors_contain(result, "R6.8"))


func test_statuses() -> void:
	var good: Dictionary = Defs.status({"id": "rooted", "effect": "rooted", "sign": 1})
	assert_true(good["ok"], str(good["errors"]))
	assert_false(Defs.status({"id": "x", "effect": "rooted", "sign": 2})["ok"])
	assert_false(Defs.status({"id": "x", "effect": "burning", "sign": 1})["ok"])
	assert_false(Defs.status({"id": "x", "effect": "rooted"})["ok"])
	assert_false(Defs.status("rooted")["ok"], "not an object")


func test_behaviors() -> void:
	assert_true(Defs.behavior({"id": "scripted_chase", "kind": "scripted_chase"})["ok"])
	assert_false(Defs.behavior({"id": "x", "kind": "greedy"})["ok"], "greedy arrives with T14")
	assert_false(Defs.behavior({"id": "x"})["ok"])


func test_push_and_pull_effects_need_a_distance() -> void:
	for type: String in ["push", "pull"]:
		var raw: Dictionary = _raw_ability()
		raw["effects"] = [{"type": type, "distance": 2, "push_origin": "target"}]
		assert_true(Defs.ability(raw)["ok"], type)
		for bad: Dictionary in [{"type": type}, {"type": type, "distance": 0}, {"type": type, "distance": 1, "push_origin": "sky"}]:
			var broken: Dictionary = _raw_ability()
			broken["effects"] = [bad]
			assert_false(Defs.ability(broken)["ok"], "rejects %s" % str(bad))
