class_name ContentLoader
extends RefCounted
## Loads the game content in data/ (abilities, statuses, behaviors, creatures, monsters, arenas,
## encounters) through data/manifest.json and builds a fight from an Encounter. It lives outside
## src/rules/ because it reads files. The manifest lists every file explicitly, because a web export
## cannot list a folder reliably; a test checks it against the folders.
##
## manifest.json: {"abilities": ["abilities/bash.json", ...], "statuses": [...], "behaviors": [...],
## "creatures": [...], "monsters": [...], "arenas": [...], "encounters": [...]}, paths relative to data/.
## Each file holds one object, and its `id` must equal the file name without ".json".

const DATA_ROOT: String = "res://data/"
const MANIFEST_PATH: String = "res://data/manifest.json"
const KINDS: Array[String] = ["abilities", "statuses", "behaviors", "creatures", "monsters", "arenas", "encounters"]


## Returns {"ok": bool, "content": {kind: {id: definition}}, "errors": Array[String]}.
## `data_root` is the folder the manifest's relative paths start from (a test can point it elsewhere).
static func load_all(manifest_path: String = MANIFEST_PATH, data_root: String = DATA_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var content: Dictionary = {}
	for kind: String in KINDS:
		content[kind] = {}

	var manifest: Variant = _read_json(manifest_path, errors)
	if not (manifest is Dictionary):
		errors.append("%s must be an object" % manifest_path)
		return {"ok": false, "content": content, "errors": errors}
	for key: Variant in (manifest as Dictionary).keys():
		if not KINDS.has(str(key)):
			errors.append("manifest: unknown section %s" % str(key))
	for kind: String in KINDS:
		var listed: Variant = (manifest as Dictionary).get(kind, null)
		if not (listed is Array):
			errors.append("manifest: section %s must be an array" % kind)
			continue
		for rel: Variant in listed:
			_load_file(content, kind, str(rel), data_root, errors)
	if errors.is_empty():
		_check_references(content, errors)
	return {"ok": errors.is_empty(), "content": content, "errors": errors}


## Builds a fight in its Placement phase from an Encounter: its Arena, its Monsters at their spawn
## cells, and its party as Creatures (party order). `players[i]` is the player who controls party
## member i (default 0, a solo player). Returns the RulesEngine.create result.
static func fight_from(content: Dictionary, rules: Dictionary, encounter_id: String, seed: int, players: Array[int] = []) -> Dictionary:
	var encounters: Dictionary = content["encounters"]
	if not encounters.has(encounter_id):
		return {"ok": false, "state": null, "errors": ["unknown encounter %s" % encounter_id] as Array[String]}
	var encounter: Dictionary = encounters[encounter_id]
	var arena_def: Dictionary = (content["arenas"] as Dictionary)[encounter["arena"]]
	var arena: Dictionary = {}
	for key: String in ["radius", "obstacles", "karma", "creature_start_cells", "collapse_at", "bloom_at"]:
		arena[key] = arena_def[key]

	var roster: Array = []
	var party: Array = encounter["party"]
	for i: int in party.size():
		var def: Dictionary = (content["creatures"] as Dictionary)[party[i]]
		roster.append(_roster_entry(def, "creature", players[i] if i < players.size() else 0))
	for entry: Dictionary in encounter["monsters"]:
		var def: Dictionary = (content["monsters"] as Dictionary)[entry["monster"]]
		var monster: Dictionary = _roster_entry(def, "monster", -1)
		monster["cell"] = entry["cell"]
		monster["behavior"] = def["behavior"]
		roster.append(monster)
	var defs: Dictionary = {"abilities": content["abilities"], "statuses": content["statuses"]}
	return RulesEngine.create(arena, roster, rules, seed, defs)


static func _roster_entry(def: Dictionary, side: String, player: int) -> Dictionary:
	return {
		"side": side, "player": player, "kind": def["id"], "name": def.get("name", def["id"]),
		"max_hp": def["max_hp"], "max_ap": def["max_ap"], "max_mp": def["max_mp"], "power": def["power"],
		"recharge_steps": def["recharge_steps"], "traits": def["traits"], "abilities": def["abilities"],
	}


static func _read_json(path: String, errors: Array[String]) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("file not found: %s" % path)
		return null
	var json: JSON = JSON.new()
	if json.parse(DataFiles.read_text(path)) != OK:
		errors.append("%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _load_file(content: Dictionary, kind: String, rel: String, data_root: String, errors: Array[String]) -> void:
	var path: String = data_root + rel
	var raw: Variant = _read_json(path, errors)
	if raw == null:
		return
	var result: Dictionary
	match kind:
		"abilities":
			result = Defs.ability(raw)
		"statuses":
			result = Defs.status(raw)
		"behaviors":
			result = Defs.behavior(raw)
		"creatures":
			result = Defs.creature(raw)
		"monsters":
			result = Defs.monster(raw)
		"arenas":
			result = Defs.arena(raw)
		"encounters":
			result = Defs.encounter(raw)
	for message: String in result["errors"]:
		errors.append("%s: %s" % [rel, message])
	if not result["ok"]:
		return
	var value: Dictionary = result["value"]
	var expected_id: String = rel.get_file().get_basename()
	if str(value["id"]) != expected_id:
		errors.append("%s: id %s must match the file name" % [rel, str(value["id"])])
		return
	if (content[kind] as Dictionary).has(expected_id):
		errors.append("%s: duplicate id %s" % [rel, expected_id])
		return
	content[kind][expected_id] = value


static func _check_references(content: Dictionary, errors: Array[String]) -> void:
	var abilities: Dictionary = content["abilities"]
	var statuses: Dictionary = content["statuses"]
	for id: String in abilities.keys():
		for effect: Dictionary in abilities[id]["effects"]:
			if effect["type"] == "apply_status" and not statuses.has(effect["status"]):
				errors.append("ability %s applies unknown status %s" % [id, str(effect["status"])])
	for id: String in (content["creatures"] as Dictionary).keys():
		for ability_id: String in content["creatures"][id]["abilities"]:
			if not abilities.has(ability_id):
				errors.append("creature %s: unknown ability %s" % [id, ability_id])
	for id: String in (content["monsters"] as Dictionary).keys():
		var monster: Dictionary = content["monsters"][id]
		if not (content["behaviors"] as Dictionary).has(monster["behavior"]):
			errors.append("monster %s: unknown behavior %s" % [id, str(monster["behavior"])])
		for ability_id: String in monster["abilities"]:
			if not abilities.has(ability_id):
				errors.append("monster %s: unknown ability %s" % [id, ability_id])
			elif not FightState.footprint_allowed_for_monster(abilities[ability_id]):
				errors.append("monster %s: ability %s breaks the Monster footprint cap (R11.2)" % [id, ability_id])
	for id: String in (content["encounters"] as Dictionary).keys():
		var encounter: Dictionary = content["encounters"][id]
		if not (content["arenas"] as Dictionary).has(encounter["arena"]):
			errors.append("encounter %s: unknown arena %s" % [id, str(encounter["arena"])])
		for entry: Dictionary in encounter["monsters"]:
			if not (content["monsters"] as Dictionary).has(entry["monster"]):
				errors.append("encounter %s: unknown monster %s" % [id, str(entry["monster"])])
		for creature_id: String in encounter["party"]:
			if not (content["creatures"] as Dictionary).has(creature_id):
				errors.append("encounter %s: unknown creature %s" % [id, creature_id])
