class_name JsonInts
extends RefCounted
## Godot's JSON returns floats for every number. This converts a parsed JSON value to ints,
## recursively, and reports anything that is not an exact integer (docs/architecture.md, determinism).

## Largest magnitude a float holds exactly (2^53).
const MAX_EXACT: float = 9007199254740992.0


## Returns a copy of `value` with every number as an int. Non-integral or out-of-range numbers are
## reported in `errors` (with their path) and left as they are.
static func normalize(value: Variant, path: String, errors: Array[String]) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			out[key] = normalize((value as Dictionary)[key], "%s.%s" % [path, str(key)], errors)
		return out
	if value is Array:
		var list: Array = []
		for i: int in (value as Array).size():
			list.append(normalize((value as Array)[i], "%s[%d]" % [path, i], errors))
		return list
	if value is float:
		var number: float = value
		if number != floorf(number):
			errors.append("%s must be an integer, got %s" % [path, str(number)])
			return value
		if absf(number) > MAX_EXACT:
			errors.append("%s is out of range: %s" % [path, str(number)])
			return value
		return int(number)
	return value
