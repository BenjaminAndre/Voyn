extends GutTest
## G1: the placeholder data in data/ (docs/gdd/90-placeholder-content.md) loads, passes the schemas,
## is cross-checked, matches the page where it matters, and builds PH Encounter 1.

const TMP: String = "user://content_test/"


func _load() -> Dictionary:
	var result: Dictionary = ContentLoader.load_all()
	assert_true(result["ok"], str(result["errors"]))
	return result["content"]


func _fight() -> FightState:
	var result: Dictionary = ContentLoader.fight_from(_load(), TestFixtures.rules(), "ph_encounter_1", 7)
	assert_true(result["ok"], str(result["errors"]))
	return result["state"]


# --- The real data ---


func test_the_placeholder_content_loads_and_validates() -> void:
	var content: Dictionary = _load()
	assert_eq((content["abilities"] as Dictionary).size(), 10)
	assert_eq((content["statuses"] as Dictionary).keys(), ["rooted"])
	assert_eq((content["behaviors"] as Dictionary).keys(), ["scripted_chase"])
	assert_eq((content["creatures"] as Dictionary).size(), 3)
	assert_eq((content["monsters"] as Dictionary).size(), 2)
	assert_eq((content["arenas"] as Dictionary).keys(), ["ph_nave"])
	assert_eq((content["encounters"] as Dictionary).keys(), ["ph_encounter_1"])


func test_the_manifest_lists_exactly_the_files_in_the_data_folders() -> void:
	var manifest: Dictionary = JSON.parse_string(DataFiles.read_text(ContentLoader.MANIFEST_PATH))
	for kind: String in ContentLoader.KINDS:
		var on_disk: Array[String] = []
		for file: String in DirAccess.get_files_at(ContentLoader.DATA_ROOT + kind):
			if file.ends_with(".json"):
				on_disk.append("%s/%s" % [kind, file])
		on_disk.sort()
		var listed: Array[String] = []
		for rel: Variant in manifest[kind]:
			listed.append(str(rel))
		listed.sort()
		assert_eq(listed, on_disk, "manifest section %s matches data/%s" % [kind, kind])


func test_creature_and_monster_stats_match_the_page() -> void:
	var content: Dictionary = _load()
	var tank: Dictionary = content["creatures"]["ph_tank"]
	assert_eq([tank["max_hp"], tank["max_ap"], tank["max_mp"], tank["power"], tank["recharge_steps"]], [160, 6, 3, 0, 4])
	assert_eq(tank["abilities"], ["shove", "bash", "guard"])
	var striker: Dictionary = content["creatures"]["ph_striker"]
	assert_eq([striker["max_hp"], striker["max_mp"], striker["power"], striker["recharge_steps"]], [100, 4, 10, 3])
	assert_eq(striker["abilities"], ["lunge", "whirl"])
	var archer: Dictionary = content["creatures"]["ph_archer"]
	assert_eq([archer["max_hp"], archer["recharge_steps"]], [90, 3])
	assert_eq(archer["abilities"], ["shot", "seed", "pin"])
	var brute: Dictionary = content["monsters"]["ph_brute"]
	assert_eq([brute["max_hp"], brute["max_mp"], brute["recharge_steps"]], [160, 2, 4])
	assert_eq(brute["traits"], ["heavy", "blightborn"])
	assert_eq(brute["behavior"], "scripted_chase")
	var flier: Dictionary = content["monsters"]["ph_flier"]
	assert_eq([flier["max_hp"], flier["max_ap"], flier["max_mp"], flier["recharge_steps"]], [70, 4, 4, 2])
	assert_eq(flier["traits"], ["nimble", "blightborn"])


func test_ability_numbers_match_the_page() -> void:
	var abilities: Dictionary = _load()["abilities"]
	var shove: Dictionary = abilities["shove"]
	assert_eq([shove["phase"], shove["ap_cost"], shove["cooldown"], shove["karma"]], ["dash", 2, 1, 0])
	assert_eq(shove["effects"], [{"type": "push", "distance": 2, "push_origin": "user"}, {"type": "damage", "base": 6}])
	var guard: Dictionary = abilities["guard"]
	assert_eq([guard["phase"], guard["target"], guard["affects"], guard["include_user"], guard["karma"], guard["cooldown"]], ["prep", "self", "allies", true, 1, 2])
	assert_eq(guard["area"], {"shape": "burst", "radius": 1})
	assert_eq(guard["effects"], [{"type": "shield", "amount": 20, "duration": 2}])
	var lunge: Dictionary = abilities["lunge"]
	assert_eq([lunge["min_range"], lunge["max_range"], lunge["line_only"], lunge["karma"]], [1, 2, true, -1])
	var whirl: Dictionary = abilities["whirl"]
	assert_eq([whirl["ap_cost"], whirl["target"], whirl["karma"], whirl["cooldown"]], [4, "self", -1, 2])
	var shot: Dictionary = abilities["shot"]
	assert_eq([shot["min_range"], shot["max_range"], shot["needs_los"], shot["karma"]], [2, 6, true, 0])
	var seed_ability: Dictionary = abilities["seed"]
	assert_eq([seed_ability["target"], seed_ability["phase"], seed_ability["karma"], seed_ability["effects"]], ["any_cell", "prep", 1, []])
	var pin: Dictionary = abilities["pin"]
	assert_eq(pin["effects"], [{"type": "damage", "base": 6}, {"type": "apply_status", "status": "rooted", "duration": 1, "magnitude": 0}])
	assert_eq([abilities["slam"]["effects"][0]["base"], abilities["slam"]["karma"]], [22, -1])
	assert_eq([abilities["peck"]["effects"][0]["base"], abilities["peck"]["max_range"]], [10, 2])
	assert_eq(abilities["bash"]["effects"][0]["base"], 18)


# --- The fight it builds ---


func test_ph_encounter_1_builds_the_fight_on_the_page() -> void:
	var state: FightState = _fight()
	assert_eq(state.status, FightState.STATUS_PLACEMENT)
	assert_eq(state.grid.size(), 91, "radius 5")
	assert_eq(state.fighters.size(), 7)
	var kinds: Array[String] = []
	for fighter: FighterState in state.fighters:
		kinds.append(fighter.kind)
	assert_eq(kinds, ["ph_tank", "ph_striker", "ph_archer", "ph_brute", "ph_brute", "ph_flier", "ph_flier"], "party order, then Encounter order")
	var spawns: Array[Vector2i] = []
	for id: int in range(3, 7):
		spawns.append(state.cell_of(state.fighters[id]))
	assert_eq(spawns, [Vector2i(0, -4), Vector2i(1, -4), Vector2i(2, -5), Vector2i(-1, -3)])
	assert_eq(state.fighters[3].behavior, "scripted_chase")
	assert_eq(state.fighters[0].behavior, "")
	assert_eq(state.collapse_at, -40)
	assert_eq(state.bloom_at, 40)
	assert_eq(state.board_karma(), -2, "the page's starting board karma")


func test_ph_nave_cells_match_the_page() -> void:
	var state: FightState = _fight()
	for cell: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(1, -2), Vector2i(-1, 2)]:
		var index: int = state.grid.index_of(cell)
		assert_eq(state.walkable[index], 0, "pillar at %s" % str(cell))
		assert_eq(state.blocks_los[index], 1)
	var around_spawn: int = 0
	var around_start: int = 0
	for cell: Vector2i in Hex.disk(Vector2i(1, -4), 1):
		assert_eq(state.karma[state.grid.index_of(cell)], Land.CORRUPTED, "Monster spawn ground %s" % str(cell))
		around_spawn += 1
	for cell: Vector2i in Hex.disk(Vector2i(-1, 4), 1):
		assert_eq(state.karma[state.grid.index_of(cell)], Land.PURE, "Creature start ground %s" % str(cell))
		around_start += 1
	assert_eq([around_spawn, around_start], [7, 7])
	for cell: Vector2i in [Vector2i(-4, 1), Vector2i(-4, 2)]:
		assert_eq(state.karma[state.grid.index_of(cell)], Land.BLIGHTED)
	for cell: Vector2i in [Vector2i(4, -1), Vector2i(4, -2)]:
		assert_eq(state.karma[state.grid.index_of(cell)], Land.PURE)
	var starts: Array[Vector2i] = []
	for index: int in state.start_cells:
		starts.append(state.grid.cell_at(index))
	var expected: Array[Vector2i] = [Vector2i(-2, 5), Vector2i(-1, 4), Vector2i(-1, 5), Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 3)]
	assert_eq(starts, expected)


func test_ph_encounter_1_is_playable_through_placement_and_a_first_step() -> void:
	var state: FightState = _fight()
	var cells: Array[Vector2i] = [Vector2i(-1, 4), Vector2i(0, 4), Vector2i(1, 3)]
	var started: FightState = TestFixtures.start(state, cells)
	var result: Dictionary = RulesEngine.resolve_step(started, [])
	assert_true(result["ok"], str(result["errors"]))
	assert_eq(result["state"].step, 2)
	assert_eq(result["state"].status, FightState.STATUS_FIGHTING)


func test_party_members_can_be_assigned_to_players() -> void:
	var assignment: Array[int] = [0, 1, 0]
	var result: Dictionary = ContentLoader.fight_from(_load(), TestFixtures.rules(), "ph_encounter_1", 1, assignment)
	assert_true(result["ok"])
	var players: Array[int] = []
	for id: int in 3:
		players.append(result["state"].fighters[id].player)
	assert_eq(players, [0, 1, 0])


func test_an_unknown_encounter_is_an_error() -> void:
	var result: Dictionary = ContentLoader.fight_from(_load(), TestFixtures.rules(), "nope", 1)
	assert_false(result["ok"])


# --- The loader's checks, on small data written to user:// ---


func _write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute((TMP + path).get_base_dir())
	var file: FileAccess = FileAccess.open(TMP + path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _manifest(overrides: Dictionary = {}) -> Dictionary:
	var manifest: Dictionary = {
		"abilities": ["abilities/bash.json"], "statuses": [], "behaviors": ["behaviors/chase.json"],
		"creatures": ["creatures/c.json"], "monsters": ["monsters/m.json"], "arenas": ["arenas/a.json"],
		"encounters": ["encounters/e.json"],
	}
	manifest.merge(overrides, true)
	return manifest


func _small_data() -> void:
	_write("abilities/bash.json", {
		"id": "bash", "phase": "strike", "ap_cost": 3, "cooldown": 0, "target": "enemy", "min_range": 1,
		"max_range": 1, "needs_los": false, "line_only": false, "area": {"shape": "single"},
		"affects": "enemies", "effects": [{"type": "damage", "base": 5}], "karma": -1,
	})
	_write("behaviors/chase.json", {"id": "chase", "kind": "scripted_chase"})
	_write("creatures/c.json", {"id": "c", "max_hp": 10, "max_ap": 3, "max_mp": 2, "power": 0, "recharge_steps": 1, "traits": [], "abilities": ["bash"]})
	_write("monsters/m.json", {"id": "m", "max_hp": 10, "max_ap": 3, "max_mp": 2, "power": 0, "recharge_steps": 1, "traits": [], "abilities": ["bash"], "behavior": "chase"})
	_write("arenas/a.json", {"id": "a", "radius": 3, "obstacles": [], "karma": [], "creature_start_cells": [[-2, 0]], "collapse_at": -9, "bloom_at": 9})
	_write("encounters/e.json", {"id": "e", "arena": "a", "monsters": [{"monster": "m", "cell": [2, 0]}], "party": ["c"]})
	_write("manifest.json", _manifest())


func _load_small() -> Dictionary:
	return ContentLoader.load_all(TMP + "manifest.json", TMP)


func _has(result: Dictionary, needle: String) -> bool:
	for message: String in result["errors"]:
		if message.contains(needle):
			return true
	return false


func test_the_small_data_set_loads() -> void:
	_small_data()
	var result: Dictionary = _load_small()
	assert_true(result["ok"], str(result["errors"]))
	var built: Dictionary = ContentLoader.fight_from(result["content"], TestFixtures.rules(), "e", 1)
	assert_true(built["ok"], str(built["errors"]))


func test_the_loader_rejects_bad_manifests_and_files() -> void:
	_small_data()
	_write("manifest.json", _manifest({"abilities": ["abilities/missing.json"]}))
	assert_true(_has(_load_small(), "file not found"))
	_write("manifest.json", {"abilities": []})
	assert_true(_has(_load_small(), "must be an array"))
	var extra: Dictionary = _manifest()
	extra["props"] = []
	_write("manifest.json", extra)
	assert_true(_has(_load_small(), "unknown section props"))
	_write("manifest.json", _manifest({"abilities": ["abilities/bash.json", "abilities/bash.json"]}))
	assert_true(_has(_load_small(), "duplicate id"))
	_write("abilities/bash.json", {"id": "smash", "phase": "strike"})
	_write("manifest.json", _manifest())
	assert_false(_load_small()["ok"], "schema errors")


func test_the_loader_rejects_an_id_that_does_not_match_the_file_name() -> void:
	_small_data()
	_write("creatures/c.json", {"id": "d", "max_hp": 10, "max_ap": 3, "max_mp": 2, "power": 0, "recharge_steps": 1, "traits": [], "abilities": ["bash"]})
	assert_true(_has(_load_small(), "must match the file name"))


func test_the_loader_checks_references() -> void:
	_small_data()
	_write("creatures/c.json", {"id": "c", "max_hp": 10, "max_ap": 3, "max_mp": 2, "power": 0, "recharge_steps": 1, "traits": [], "abilities": ["ghost"]})
	assert_true(_has(_load_small(), "unknown ability ghost"))
	_small_data()
	_write("encounters/e.json", {"id": "e", "arena": "nowhere", "monsters": [{"monster": "m", "cell": [2, 0]}], "party": ["c"]})
	assert_true(_has(_load_small(), "unknown arena nowhere"))
	_small_data()
	_write("monsters/m.json", {"id": "m", "max_hp": 10, "max_ap": 3, "max_mp": 2, "power": 0, "recharge_steps": 1, "traits": [], "abilities": ["bash"], "behavior": "ghost"})
	assert_true(_has(_load_small(), "unknown behavior ghost"))


func test_the_loader_enforces_the_monster_footprint_cap() -> void:
	_small_data()
	_write("abilities/ruin.json", {
		"id": "ruin", "phase": "strike", "ap_cost": 1, "cooldown": 0, "target": "enemy", "min_range": 1,
		"max_range": 1, "needs_los": false, "line_only": false, "area": {"shape": "burst", "radius": 1},
		"affects": "enemies", "effects": [], "karma": -1,
	})
	_write("monsters/m.json", {"id": "m", "max_hp": 10, "max_ap": 3, "max_mp": 2, "power": 0, "recharge_steps": 1, "traits": [], "abilities": ["ruin"], "behavior": "chase"})
	_write("manifest.json", _manifest({"abilities": ["abilities/bash.json", "abilities/ruin.json"]}))
	assert_true(_has(_load_small(), "footprint cap"))
