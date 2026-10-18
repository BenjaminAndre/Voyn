class_name DataFiles
extends RefCounted
## File access for game data. It lives outside src/rules/ because the rules engine
## never touches engine singletons such as FileAccess.


## Returns the file's text, or "" if it cannot be read.
static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Loads and validates data/combat/rules.json. Same result shape as RulesLoader.parse.
static func load_rules(path: String = "res://data/combat/rules.json") -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "rules": {}, "errors": ["file not found: %s" % path]}
	return RulesLoader.parse(read_text(path))
