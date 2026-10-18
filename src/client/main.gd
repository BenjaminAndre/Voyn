extends Control
## The game's main scene. T12 version: loads PH Encounter 1, places the party, starts the fight and
## shows the board, the Land meter and the build info. (T13 adds planning and the step loop.)
##
## Dev option: `-- --screenshot=<path>` saves one frame as a PNG and quits (used to check the view).

const BUILD_INFO_PATH: String = "res://build_info.txt"
const ENCOUNTER_ID: String = "ph_encounter_1"

var content: Dictionary = {}
var rules: Dictionary = {}
var state: FightState
var board: BoardView
var meter: LandMeter
var _build_label: Label
var _error_label: Label


func _ready() -> void:
	_build_label = Label.new()
	_build_label.text = _build_info()
	_build_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_build_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_build_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_build_label)

	if not _load_content():
		return
	_start_fight(Time.get_ticks_msec() % 1000000)
	_maybe_screenshot()


## Loads the data and the rules. Shows the errors on screen if either is broken.
func _load_content() -> bool:
	var loaded: Dictionary = ContentLoader.load_all()
	var rules_result: Dictionary = DataFiles.load_rules()
	if not loaded["ok"] or not rules_result["ok"]:
		_show_error("Content failed to load:\n" + "\n".join((loaded["errors"] as Array) + (rules_result["errors"] as Array)))
		return false
	content = loaded["content"]
	rules = rules_result["rules"]
	return true


## Builds the fight from the Encounter, places the party on the Arena's start cells in party order,
## starts it, and (re)builds the views.
func _start_fight(seed: int) -> void:
	var built: Dictionary = ContentLoader.fight_from(content, rules, ENCOUNTER_ID, seed)
	if not built["ok"]:
		_show_error("Could not build the fight:\n" + "\n".join(built["errors"]))
		return
	var fresh: FightState = built["state"]
	var arena: Dictionary = (content["arenas"] as Dictionary)[(content["encounters"] as Dictionary)[ENCOUNTER_ID]["arena"]]
	var starts: Array = arena["creature_start_cells"]
	var next_start: int = 0
	for fighter: FighterState in fresh.fighters:
		if fighter.is_creature():
			var pair: Array = starts[next_start]
			next_start += 1
			fresh = RulesEngine.place(fresh, fighter.id, Vector2i(int(pair[0]), int(pair[1])))["state"]
	state = RulesEngine.start_fight(fresh)["state"]
	_build_views()


func _build_views() -> void:
	if board != null:
		board.queue_free()
	board = BoardView.new()
	add_child(board)
	board.setup(state)
	if meter == null:
		meter = LandMeter.new()
		meter.position = Vector2(16, 12)
		add_child(meter)
	meter.configure(state.collapse_at, state.bloom_at)
	refresh_land()


## Updates the Land meter and the forecast markers from the current state.
func refresh_land() -> void:
	var forecast: Dictionary = RulesEngine.forecast(state)
	meter.set_values(state.board_karma(), int(forecast["board_karma_after"]))
	board.set_forecast(forecast["changed"], forecast["next"])


func _show_error(text: String) -> void:
	if _error_label == null:
		_error_label = Label.new()
		_error_label.position = Vector2(16, 16)
		add_child(_error_label)
	_error_label.text = text


func _build_info() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	var text: String = "v%s" % version
	if FileAccess.file_exists(BUILD_INFO_PATH):
		text += " " + FileAccess.get_file_as_string(BUILD_INFO_PATH).strip_edges()
	else:
		text += " dev"
	return text


func _maybe_screenshot() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			var path: String = argument.trim_prefix("--screenshot=")
			for i: int in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()
