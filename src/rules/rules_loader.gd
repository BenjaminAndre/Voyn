class_name RulesLoader
extends RefCounted
## Parses data/combat/rules.json text into a Dictionary of ints (docs/architecture.md, determinism).
## Godot's JSON returns floats for every number, so each value is converted to int and anything
## that is not an exact integer is rejected. Unknown keys, missing keys and bad values are errors.

const KEYS: Array[String] = [
	"step_window_ms",
	"land_phase_every_steps",
	"keeper_recharge_steps",
	"engagement_mp_per_enemy",
	"collision_damage_per_cell",
	"crush_damage",
	"telegraph_min_delay",
	"blight_damage",
	"thrive_heal",
	"blightborn_power_pct",
	"land_sum_threshold",
	"height_step_mp",
	"fall_damage_per_level",
	"height_advantage_pct",
]

## Free-text documentation key allowed in data files; never copied into the result.
const DOC_KEY: String = "_doc"

## Largest magnitude a float holds exactly (2^53), so the float -> int conversion is lossless.
const MAX_EXACT: float = 9007199254740992.0


## Returns {"ok": bool, "rules": Dictionary (key -> int), "errors": Array[String]}.
static func parse(text: String) -> Dictionary:
	var errors: Array[String] = []
	var rules: Dictionary = {}

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		errors.append("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return _result(rules, errors)

	var data: Variant = json.data
	if not (data is Dictionary):
		errors.append("top level must be an object")
		return _result(rules, errors)
	var dict: Dictionary = data

	for key: Variant in dict.keys():
		var name: String = str(key)
		if name != DOC_KEY and not KEYS.has(name):
			errors.append("unknown key: %s" % name)

	for key: String in KEYS:
		if not dict.has(key):
			errors.append("missing key: %s" % key)
			continue
		var value: Variant = dict[key]
		if not (value is float or value is int):
			errors.append("%s must be a number" % key)
			continue
		var as_float: float = float(value)
		if as_float != floorf(as_float):
			errors.append("%s must be an integer, got %s" % [key, str(value)])
			continue
		if absf(as_float) > MAX_EXACT:
			errors.append("%s is out of range: %s" % [key, str(value)])
			continue
		rules[key] = int(as_float)

	if rules.has("telegraph_min_delay") and int(rules["telegraph_min_delay"]) < 1:
		errors.append("telegraph_min_delay must be >= 1")

	return _result(rules, errors)


static func _result(rules: Dictionary, errors: Array[String]) -> Dictionary:
	return {"ok": errors.is_empty(), "rules": rules if errors.is_empty() else {}, "errors": errors}
