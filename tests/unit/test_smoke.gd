extends GutTest


func test_smoke_engine_runs() -> void:
	assert_eq(1 + 1, 2, "arithmetic works")


func test_smoke_rules_json_loads() -> void:
	var text: String = FileAccess.get_file_as_string("res://data/combat/rules.json")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "data/combat/rules.json parses to a Dictionary")
