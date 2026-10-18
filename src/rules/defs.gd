class_name Defs
extends RefCounted
## Validators for the content definitions in data/ (schemas in docs/architecture.md, "Content
## schemas"). Each takes a parsed JSON value (floats are converted to ints) and returns
## {"ok": bool, "value": Dictionary (normalized, empty on failure), "errors": Array[String]}.
## Unknown and missing keys are errors. A free-text "_doc" key is allowed and dropped.

const DOC_KEY: String = "_doc"

const PHASES: Array[String] = ["prep", "dash", "strike"]
const TARGETS: Array[String] = ["any_cell", "empty_cell", "any_fighter", "enemy", "ally", "self"]
const AFFECTS: Array[String] = ["enemies", "allies", "all"]
const AREA_SHAPES: Array[String] = ["single", "burst", "line"]
## Effect types resolved so far. mutate and telegraph arrive with T10.
const EFFECT_TYPES: Array[String] = ["damage", "heal", "shield", "apply_status", "push", "pull"]
const PUSH_ORIGINS: Array[String] = ["user", "target"]
const STATUS_EFFECTS: Array[String] = ["shield", "rooted", "damage_taken_pct", "damage_dealt_pct"]
const BEHAVIOR_KINDS: Array[String] = ["scripted_chase"]

const ABILITY_KEYS: Array[String] = [
	"id", "name", "phase", "ap_cost", "cooldown", "target", "min_range", "max_range", "needs_los",
	"line_only", "area", "affects", "include_user", "effects", "karma",
]


static func ability(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	var dict: Dictionary = _object(raw, "ability", errors)
	if not errors.is_empty():
		return _fail(errors)
	_keys(dict, ABILITY_KEYS, ["include_user", "name"], "ability", errors)
	_string(dict, "id", "ability", errors, true)
	_enum(dict, "phase", PHASES, "ability", errors)
	_int(dict, "ap_cost", 0, "ability", errors)
	_int(dict, "cooldown", 0, "ability", errors)
	_enum(dict, "target", TARGETS, "ability", errors)
	_int(dict, "min_range", 0, "ability", errors)
	_int(dict, "max_range", 0, "ability", errors)
	if dict.get("min_range") is int and dict.get("max_range") is int and int(dict["max_range"]) < int(dict["min_range"]):
		errors.append("ability.max_range must be >= min_range")
	_bool(dict, "needs_los", "ability", errors)
	_bool(dict, "line_only", "ability", errors)
	if dict.has("include_user"):
		_bool(dict, "include_user", "ability", errors)
	else:
		dict["include_user"] = false
	_enum(dict, "affects", AFFECTS, "ability", errors)
	_int(dict, "karma", -100, "ability", errors)
	_area(dict, errors)
	_effects(dict, errors)
	if not errors.is_empty():
		return _fail(errors)
	return {"ok": true, "value": dict, "errors": errors}


static func status(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	var dict: Dictionary = _object(raw, "status", errors)
	if not errors.is_empty():
		return _fail(errors)
	_keys(dict, ["id", "name", "effect", "sign"], ["name"], "status", errors)
	_string(dict, "id", "status", errors, true)
	_enum(dict, "effect", STATUS_EFFECTS, "status", errors)
	if dict.has("sign") and not (dict["sign"] is int and [1, -1].has(int(dict["sign"]))):
		errors.append("status.sign must be 1 or -1")
	if not errors.is_empty():
		return _fail(errors)
	return {"ok": true, "value": dict, "errors": errors}


static func behavior(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	var dict: Dictionary = _object(raw, "behavior", errors)
	if not errors.is_empty():
		return _fail(errors)
	_keys(dict, ["id", "kind"], [], "behavior", errors)
	_string(dict, "id", "behavior", errors, true)
	_enum(dict, "kind", BEHAVIOR_KINDS, "behavior", errors)
	if not errors.is_empty():
		return _fail(errors)
	return {"ok": true, "value": dict, "errors": errors}


static func _area(dict: Dictionary, errors: Array[String]) -> void:
	if not dict.has("area") or not (dict["area"] is Dictionary):
		errors.append("ability.area must be an object")
		return
	var area: Dictionary = dict["area"]
	var shape: String = str(area.get("shape", ""))
	if not AREA_SHAPES.has(shape):
		errors.append("ability.area.shape must be one of %s" % str(AREA_SHAPES))
		return
	var wanted: Array[String] = ["shape"]
	if shape == "burst":
		wanted.append("radius")
		_int(area, "radius", 1, "ability.area", errors)
	elif shape == "line":
		wanted.append("length")
		_int(area, "length", 1, "ability.area", errors)
		if dict.get("line_only") != true:
			errors.append("ability.area line needs line_only = true")
	_keys(area, wanted, [], "ability.area", errors)


static func _effects(dict: Dictionary, errors: Array[String]) -> void:
	if not dict.has("effects") or not (dict["effects"] is Array):
		errors.append("ability.effects must be an array (it may be empty)")
		return
	var effects: Array = dict["effects"]
	for i: int in effects.size():
		var where: String = "ability.effects[%d]" % i
		if not (effects[i] is Dictionary):
			errors.append("%s must be an object" % where)
			continue
		var effect: Dictionary = effects[i]
		var type: String = str(effect.get("type", ""))
		if effect.has("chance"):
			errors.append("%s.chance is not supported yet (GDD R6.8 leaves open whether it rolls per effect or per fighter)" % where)
			continue
		if ["mutate", "telegraph"].has(type):
			errors.append("%s: effect type '%s' is not supported yet" % [where, type])
			continue
		match type:
			"damage":
				_keys(effect, ["type", "base"], [], where, errors)
				_int(effect, "base", 0, where, errors)
			"heal":
				_keys(effect, ["type", "amount"], [], where, errors)
				_int(effect, "amount", 0, where, errors)
			"shield":
				_keys(effect, ["type", "amount", "duration"], [], where, errors)
				_int(effect, "amount", 1, where, errors)
				_int(effect, "duration", 1, where, errors)
			"push", "pull":
				_keys(effect, ["type", "distance", "push_origin"], ["push_origin"], where, errors)
				_int(effect, "distance", 1, where, errors)
				if effect.has("push_origin"):
					_enum(effect, "push_origin", PUSH_ORIGINS, where, errors)
				else:
					effect["push_origin"] = "user"
			"apply_status":
				_keys(effect, ["type", "status", "duration", "magnitude"], [], where, errors)
				_string(effect, "status", where, errors, true)
				_int(effect, "duration", 1, where, errors)
				_int(effect, "magnitude", -1000, where, errors)
			_:
				errors.append("%s.type must be one of %s" % [where, str(EFFECT_TYPES)])


static func _object(raw: Variant, what: String, errors: Array[String]) -> Dictionary:
	var normalized: Variant = JsonInts.normalize(raw, what, errors)
	if not (normalized is Dictionary):
		errors.append("%s must be an object" % what)
		return {}
	var dict: Dictionary = (normalized as Dictionary).duplicate()
	dict.erase(DOC_KEY)
	return dict


static func _keys(dict: Dictionary, allowed: Array[String], optional: Array[String], where: String, errors: Array[String]) -> void:
	for key: Variant in dict.keys():
		if not allowed.has(str(key)):
			errors.append("%s: unknown key %s" % [where, str(key)])
	for key: String in allowed:
		if not dict.has(key) and not optional.has(key):
			errors.append("%s: missing key %s" % [where, key])


static func _string(dict: Dictionary, key: String, where: String, errors: Array[String], non_empty: bool = false) -> void:
	if not dict.has(key):
		return
	if not (dict[key] is String) or (non_empty and str(dict[key]) == ""):
		errors.append("%s.%s must be a non-empty string" % [where, key])


static func _int(dict: Dictionary, key: String, minimum: int, where: String, errors: Array[String]) -> void:
	if not dict.has(key):
		return
	if not (dict[key] is int):
		errors.append("%s.%s must be an integer" % [where, key])
	elif int(dict[key]) < minimum:
		errors.append("%s.%s must be >= %d" % [where, key, minimum])


static func _bool(dict: Dictionary, key: String, where: String, errors: Array[String]) -> void:
	if dict.has(key) and not (dict[key] is bool):
		errors.append("%s.%s must be true or false" % [where, key])


static func _enum(dict: Dictionary, key: String, allowed: Array[String], where: String, errors: Array[String]) -> void:
	if not dict.has(key):
		return
	if not (dict[key] is String) or not allowed.has(str(dict[key])):
		errors.append("%s.%s must be one of %s" % [where, key, str(allowed)])


static func _fail(errors: Array[String]) -> Dictionary:
	return {"ok": false, "value": {}, "errors": errors}
