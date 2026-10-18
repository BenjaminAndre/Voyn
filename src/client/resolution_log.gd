class_name ResolutionLog
extends RefCounted
## The resolution log (round 2, item 2.5): each phase of a step and the events that happen in it, as
## short lines ("Lead moves: Tank moves 2 cells", "Strike: Brute takes 22"). Built from the event
## stream and nothing else, one event at a time as they play. It holds the last step until the next
## step's first event arrives. Client-only.
##
## An entry is {"kind": "step" | "heading" | "line", "text": String, "fighter": int, "tag": String,
## "count": int}. `tag` marks lines that grow as similar events arrive ("move", "karma").

const PHASE_TITLES: Dictionary = {
	"lead_move": "Lead moves",
	"prep": "Prep",
	"dash": "Dash",
	"strike": "Strike",
	"trail_move": "Trail moves",
	"upkeep": "Upkeep",
}

var entries: Array[Dictionary] = []


func clear() -> void:
	entries.clear()


## Adds the entry for one event. `state` only supplies names (fighters and abilities).
func add(event: Dictionary, state: FightState) -> void:
	match str(event["type"]):
		"step_started":
			clear()
			entries.append({"kind": "step", "text": "Step %d" % int(event["step"]), "fighter": -1, "tag": "", "count": 0})
		"phase_started":
			entries.append({"kind": "heading", "text": str(PHASE_TITLES.get(str(event["name"]), str(event["name"]))), "fighter": -1, "tag": "", "count": 0})
		"moved":
			_grow("move", int(event["fighter"]), state)
		"move_blocked":
			_line("%s is blocked (%s)" % [_name(state, int(event["fighter"])), str(event["reason"]).replace("_", " ")])
		"displaced":
			var cells: int = Hex.distance(_cell(event["from"]), _cell(event["to"]))
			_line("%s is displaced %d cell%s" % [_name(state, int(event["fighter"])), cells, "" if cells == 1 else "s"])
		"collided":
			_line("%s collides, %d cell%s short" % [_name(state, int(event["fighter"])), int(event["cells"]), "" if int(event["cells"]) == 1 else "s"])
		"ability_used":
			_line("%s uses %s" % [_name(state, int(event["fighter"])), _ability_name(state, str(event["ability"]))])
		"fizzled":
			_line("%s's %s fizzles (%s)" % [_name(state, int(event["fighter"])), _ability_name(state, str(event["ability"])), str(event["reason"]).replace("_", " ")])
		"damaged":
			_line(_damage_text(event, state))
		"healed":
			_line("%s heals %d" % [_name(state, int(event["fighter"])), int(event["amount"])])
		"shield_changed":
			_line("%s shield: %d" % [_name(state, int(event["fighter"])), int(event["shield"])])
		"status_applied":
			if str(event["status"]) == Statuses.SHIELD:
				return  # the shield_changed line already says it
			_line("%s is %s" % [_name(state, int(event["fighter"])), str(event["status"])])
		"status_ended":
			_line("%s: %s ends" % [_name(state, int(event["fighter"])), str(event["status"])])
		"defeated":
			_line("%s is %s" % [_name(state, int(event["fighter"])), str(event["how"]).capitalize()])
		"karma_changed":
			_grow("karma", -1, state)
		"land_phase":
			_line("The Land answers: board karma %d" % int(event["board_karma"]))
		"refilled":
			_line("%s recharges" % _name(state, int(event["fighter"])))
		"fight_ended":
			_line("The fight ends: %s" % str(event["outcome"]))


## The log as plain text, one entry per line (headings end with a colon).
func text() -> String:
	var lines: Array[String] = []
	for entry: Dictionary in entries:
		match str(entry["kind"]):
			"step":
				lines.append(str(entry["text"]))
			"heading":
				lines.append("%s:" % str(entry["text"]))
			_:
				lines.append("  " + str(entry["text"]))
	return "\n".join(lines)


## The log as BBCode for a RichTextLabel.
func bbcode() -> String:
	var lines: Array[String] = []
	for entry: Dictionary in entries:
		var text: String = str(entry["text"]).replace("[", "[lb]")
		match str(entry["kind"]):
			"step":
				lines.append("[b][color=#ffe27a]%s[/color][/b]" % text)
			"heading":
				lines.append("[b][color=#9ac8ff]%s[/color][/b]" % text)
			_:
				lines.append("   " + text)
	return "\n".join(lines)


func _line(text: String) -> void:
	entries.append({"kind": "line", "text": text, "fighter": -1, "tag": "", "count": 0})


## Adds a line, or grows the latest line of the same tag and fighter in this phase.
func _grow(tag: String, fighter: int, state: FightState) -> void:
	var index: int = entries.size() - 1
	while index >= 0 and str(entries[index]["kind"]) != "heading":
		var entry: Dictionary = entries[index]
		if str(entry["tag"]) == tag and int(entry["fighter"]) == fighter:
			entry["count"] = int(entry["count"]) + 1
			entry["text"] = _grown_text(tag, fighter, int(entry["count"]), state)
			return
		index -= 1
	var fresh: Dictionary = {"kind": "line", "text": "", "fighter": fighter, "tag": tag, "count": 1}
	fresh["text"] = _grown_text(tag, fighter, 1, state)
	entries.append(fresh)


func _grown_text(tag: String, fighter: int, count: int, state: FightState) -> String:
	if tag == "move":
		return "%s moves %d cell%s" % [_name(state, fighter), count, "" if count == 1 else "s"]
	return "%d cell%s change karma" % [count, "" if count == 1 else "s"]


func _damage_text(event: Dictionary, state: FightState) -> String:
	var who: String = _name(state, int(event["fighter"]))
	var amount: int = int(event["amount"])
	var absorbed: int = int(event["absorbed"])
	var cause: String = str(event["cause"])
	var through: int = amount - absorbed
	if through <= 0 and absorbed > 0:
		return "%s: the shield absorbs %d" % [who, absorbed]
	var text: String = "%s takes %d" % [who, through]
	if cause != "ability":
		text += " from %s" % cause
	if absorbed > 0:
		text += " (%d absorbed)" % absorbed
	return text


func _name(state: FightState, id: int) -> String:
	return state.fighters[id].name.trim_prefix("PH ")


func _ability_name(state: FightState, id: String) -> String:
	if state.abilities.has(id):
		return str((state.abilities[id] as Dictionary).get("name", id))
	return id


func _cell(pair: Variant) -> Vector2i:
	return Vector2i(int((pair as Array)[0]), int((pair as Array)[1]))
