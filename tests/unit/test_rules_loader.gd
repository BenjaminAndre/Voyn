extends GutTest
## T2: rules.json loader. Every value becomes an int; bad files are rejected with a message.


func _valid() -> Dictionary:
	var result: Dictionary = DataFiles.load_rules()
	assert_true(result["ok"], "the real rules.json must load: %s" % str(result["errors"]))
	var rules: Dictionary = result["rules"]
	return rules.duplicate()


func _parse(dict: Dictionary) -> Dictionary:
	return RulesLoader.parse(JSON.stringify(dict))


func _has_error(result: Dictionary, needle: String) -> bool:
	for message: String in result["errors"]:
		if message.contains(needle):
			return true
	return false


func test_loads_real_file_as_ints() -> void:
	var result: Dictionary = DataFiles.load_rules()
	assert_true(result["ok"])
	var rules: Dictionary = result["rules"]
	assert_eq(rules.size(), RulesLoader.KEYS.size())
	for key: String in RulesLoader.KEYS:
		assert_true(rules.has(key), "has %s" % key)
		assert_typeof(rules[key], TYPE_INT)
	assert_eq(rules["step_window_ms"], 8000)
	assert_eq(rules["land_sum_threshold"], 5)


func test_doc_key_is_allowed_and_dropped() -> void:
	var result: Dictionary = DataFiles.load_rules()
	var rules: Dictionary = result["rules"]
	assert_false(rules.has("_doc"))


func test_rejects_invalid_json() -> void:
	var result: Dictionary = RulesLoader.parse("{ not json")
	assert_false(result["ok"])
	assert_true(_has_error(result, "invalid JSON"))


func test_rejects_non_object() -> void:
	var result: Dictionary = RulesLoader.parse("[1, 2, 3]")
	assert_false(result["ok"])
	assert_true(_has_error(result, "top level"))


func test_rejects_missing_key() -> void:
	var dict: Dictionary = _valid()
	dict.erase("blight_damage")
	var result: Dictionary = _parse(dict)
	assert_false(result["ok"])
	assert_true(_has_error(result, "missing key: blight_damage"))


func test_rejects_unknown_key() -> void:
	var dict: Dictionary = _valid()
	dict["blihgt_damage"] = 10
	var result: Dictionary = _parse(dict)
	assert_false(result["ok"])
	assert_true(_has_error(result, "unknown key: blihgt_damage"))


func test_rejects_fractional_number() -> void:
	var dict: Dictionary = _valid()
	dict["thrive_heal"] = 8.5
	var result: Dictionary = _parse(dict)
	assert_false(result["ok"])
	assert_true(_has_error(result, "thrive_heal must be an integer"))


func test_rejects_non_number() -> void:
	var dict: Dictionary = _valid()
	dict["crush_damage"] = "15"
	var result: Dictionary = _parse(dict)
	assert_false(result["ok"])
	assert_true(_has_error(result, "crush_damage must be a number"))


func test_rejects_boolean() -> void:
	var dict: Dictionary = _valid()
	dict["crush_damage"] = true
	var result: Dictionary = _parse(dict)
	assert_false(result["ok"])
	assert_true(_has_error(result, "crush_damage must be a number"))


func test_rejects_out_of_range_number() -> void:
	var result: Dictionary = RulesLoader.parse(JSON.stringify(_valid()).replace("\"crush_damage\":15", "\"crush_damage\":1e300"))
	assert_false(result["ok"])
	assert_true(_has_error(result, "crush_damage is out of range"))


func test_rejects_telegraph_min_delay_below_one() -> void:
	var dict: Dictionary = _valid()
	dict["telegraph_min_delay"] = 0
	var result: Dictionary = _parse(dict)
	assert_false(result["ok"])
	assert_true(_has_error(result, "telegraph_min_delay must be >= 1"))


func test_failed_load_returns_no_rules() -> void:
	var dict: Dictionary = _valid()
	dict["telegraph_min_delay"] = 0
	var result: Dictionary = _parse(dict)
	var rules: Dictionary = result["rules"]
	assert_true(rules.is_empty())


func test_missing_file_is_an_error() -> void:
	var result: Dictionary = DataFiles.load_rules("res://data/combat/does_not_exist.json")
	assert_false(result["ok"])
	assert_true(_has_error(result, "file not found"))
