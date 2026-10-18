extends Control
## The game's main scene (T13): loads PH Encounter 1, places the party, and runs the step loop. Each
## step is a planning window (a 16 s timer with Ready, plus a dev-only "untimed" switch), then the
## rules engine resolves everyone's plans and the board plays the events.
##
## The client decides no rule. Plans come from PlanBuilder, Monster plans from ScriptedChase, and
## every number on screen is the engine's. Single player controls every Creature; local co-op comes
## later.
##
## Dev option: `-- --screenshot=<path>` saves one frame as a PNG and quits (used to check the view).

const BUILD_INFO_PATH: String = "res://build_info.txt"
const ENCOUNTER_ID: String = "ph_encounter_1"

enum Mode { PLANNING, RESOLVING, ENDED }

const COLOR_REACH: Color = Color(0.3, 0.55, 1.0, 0.32)
const COLOR_PATH: Color = Color(1.0, 1.0, 1.0, 0.5)
const COLOR_TARGET: Color = Color(1.0, 0.9, 0.2, 0.42)
const COLOR_AREA: Color = Color(1.0, 0.5, 0.15, 0.55)
const COLOR_THREAT: Color = Color(0.9, 0.12, 0.2, 0.3)

var content: Dictionary = {}
var rules: Dictionary = {}
var state: FightState
var board: BoardView
var meter: LandMeter
var builder: PlanBuilder = PlanBuilder.new()
var mode: Mode = Mode.PLANNING
var selected: int = -1
var targeting: bool = false
var window_left: float = 0.0
var untimed: bool = false
var last_message: String = ""

var _step_label: Label
var _timer_bar: ProgressBar
var _ready_button: Button
var _untimed_check: CheckBox
var _threat_check: CheckBox
var _party_box: VBoxContainer
var _actions_box: VBoxContainer
var _banner: Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_details: Label
var _hint: Label
var _build_label: Label
var _group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	_build_ui()
	if not _load_content():
		return
	_start_fight(Time.get_ticks_msec() % 1000000)
	_maybe_screenshot()


func _process(delta: float) -> void:
	if mode != Mode.PLANNING or untimed or state == null:
		return
	window_left = maxf(0.0, window_left - delta)
	_timer_bar.value = window_left
	if window_left <= 0.0:
		resolve_step()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PLANNING:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			resolve_step()
		elif event.keycode == KEY_ESCAPE:
			clear_selected()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		clear_selected()


# --- Starting a fight ---


func _load_content() -> bool:
	var loaded: Dictionary = ContentLoader.load_all()
	var rules_result: Dictionary = DataFiles.load_rules()
	if not loaded["ok"] or not rules_result["ok"]:
		_set_hint("Content failed to load:\n" + "\n".join((loaded["errors"] as Array) + (rules_result["errors"] as Array)))
		return false
	content = loaded["content"]
	rules = rules_result["rules"]
	return true


## Builds the fight from the Encounter, places the party on the Arena's start cells in party order,
## starts it, and rebuilds the views.
func _start_fight(seed: int) -> void:
	var built: Dictionary = ContentLoader.fight_from(content, rules, ENCOUNTER_ID, seed)
	if not built["ok"]:
		_set_hint("Could not build the fight:\n" + "\n".join(built["errors"]))
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
	_begin_window()


func _build_views() -> void:
	if board != null:
		board.queue_free()
	board = BoardView.new()
	add_child(board)
	board.setup(state)
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	board.banner.connect(func(text: String) -> void: _banner.text = text)
	board.land_changed.connect(func(value: int) -> void: meter.set_values(value, value))
	meter.configure(state.collapse_at, state.bloom_at)


# --- The planning window ---


func _begin_window() -> void:
	mode = Mode.PLANNING
	builder.reset(state)
	targeting = false
	_banner.text = ""
	selected = -1  # nobody is selected: picking a Creature is what shows its move range
	window_left = float(int(rules["step_window_ms"])) / 1000.0
	_timer_bar.max_value = window_left
	_timer_bar.value = window_left
	_ready_button.disabled = false
	_refresh()


## Selects a Creature.
func select(id: int) -> void:
	if mode != Mode.PLANNING or not state.fighters[id].on_board() or not state.fighters[id].is_creature():
		return
	selected = id
	targeting = false
	_refresh()


## Chooses an ability for the selected Creature; a `self` ability is complete at once.
func choose_ability(ability_id: String) -> void:
	if mode != Mode.PLANNING or selected < 0:
		return
	if builder.unavailable_reason(selected, ability_id) != "":
		return
	if str(builder.draft(selected)["ability"]) == ability_id:
		builder.set_ability(selected, "")  # pressing it again unchooses it
		targeting = false
	else:
		builder.set_ability(selected, ability_id)
		targeting = not bool(builder.draft(selected)["has_target"])
	_refresh()


func set_order(ability_first: bool) -> void:
	if mode != Mode.PLANNING or selected < 0:
		return
	builder.set_order(selected, Plans.ORDER_ABILITY_FIRST if ability_first else Plans.ORDER_MOVE_FIRST)
	targeting = str(builder.draft(selected)["ability"]) != "" and not bool(builder.draft(selected)["has_target"])
	_refresh()


func clear_selected() -> void:
	if mode != Mode.PLANNING or selected < 0:
		return
	builder.clear(selected)
	targeting = false
	_refresh()


## A click on the board while planning: select a Creature, aim the chosen ability, or set a move.
func click_cell(cell: Vector2i) -> void:
	if mode != Mode.PLANNING or not state.grid.has_cell(cell):
		return
	if targeting and selected >= 0:
		if builder.set_target(selected, cell):
			targeting = false
			_set_hint("")
			_refresh()
			return
		_set_hint("That cannot be targeted from where this plan puts the Creature.")
	var occupant: FighterState = state.fighter_at(state.grid.index_of(cell))
	if occupant != null and occupant.is_creature():
		select(occupant.id)
		return
	if selected >= 0 and not targeting:
		if builder.set_path_to(selected, cell):
			_set_hint("")
		else:
			_set_hint("Out of reach this step.")
		_refresh()


func _on_cell_clicked(cell: Vector2i) -> void:
	click_cell(cell)


func _on_cell_hovered(cell: Vector2i) -> void:
	if mode != Mode.PLANNING or not targeting or selected < 0:
		board.clear_overlay("area")
		return
	if builder.target_cells(selected).has(state.grid.index_of(cell)):
		board.set_overlay("area", builder.area_cells(selected, cell), COLOR_AREA)
	else:
		board.clear_overlay("area")


# --- Resolving a step ---


## Ends the window: gathers every Side's plans, resolves the step, plays the events.
func resolve_step() -> void:
	if mode != Mode.PLANNING:
		return
	mode = Mode.RESOLVING
	board.clear_overlays()
	board.set_previews({})
	_ready_button.disabled = true
	var plans: Array = builder.plans()
	plans.append_array(ScriptedChase.plans(state, content["behaviors"]))
	var result: Dictionary = RulesEngine.resolve_step(state, plans)
	if not result["ok"]:
		_set_hint("The step could not be resolved: %s" % str(result["errors"]))
		mode = Mode.PLANNING
		_refresh()
		return
	await board.play_events(result["events"], result["state"])
	state = result["state"]
	_banner.text = ""
	if state.status == FightState.STATUS_ENDED:
		_end_fight()
	else:
		_begin_window()


## The result screen (R3.8): the outcome, Monsters Cleansed out of the total, the final board karma.
func _end_fight() -> void:
	mode = Mode.ENDED
	_banner.text = ""
	_refresh()
	_set_hint("")
	_end_title.text = _outcome_title(state.outcome)
	_end_details.text = result_details()
	_end_panel.show()


func _outcome_title(outcome: String) -> String:
	match outcome:
		"victory":
			return "Victory"
		"defeat":
			return "Defeat"
		"bloom":
			return "Bloom: the Land flourishes"
		"collapse":
			return "Collapse: everyone loses"
	return outcome.capitalize()


## "Monsters Cleansed: k/n", the final board karma and the number of steps played.
func result_details() -> String:
	var monsters: int = 0
	for fighter: FighterState in state.fighters:
		if not fighter.is_creature():
			monsters += 1
	return "Monsters Cleansed: %d/%d
Final board karma: %d (Collapse %d, Bloom +%d)
Steps: %d" % [
		state.cleansed_count, monsters, state.board_karma(), state.collapse_at, state.bloom_at, state.step]


## Starts a new fight from the same Encounter with a fresh seed.
func restart() -> void:
	_end_panel.hide()
	_start_fight(Time.get_ticks_msec() % 1000000)


# --- Showing it ---


func _refresh() -> void:
	_step_label.text = "Step %d" % state.step
	_update_party()
	_update_actions()
	_update_overlays()
	_update_preview()


func _update_party() -> void:
	for child: Node in _party_box.get_children():
		child.queue_free()
	for fighter: FighterState in state.fighters:
		if not fighter.is_creature():
			continue
		var card: Button = Button.new()
		card.toggle_mode = true
		card.button_group = _group
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size = Vector2(250, 62)
		card.text = _card_text(fighter)
		card.disabled = not fighter.on_board() or mode != Mode.PLANNING
		card.set_pressed_no_signal(fighter.id == selected)
		var id: int = fighter.id
		card.pressed.connect(func() -> void: select(id))
		_party_box.add_child(card)


func _card_text(fighter: FighterState) -> String:
	if not fighter.alive:
		return "%s\nDowned" % fighter.name
	var refill: int = (fighter.recharge_steps - state.step % fighter.recharge_steps) % fighter.recharge_steps
	var refill_text: String = "refills this step" if refill == 0 else "refill in %d" % refill
	var shield: int = Statuses.shield_amount(fighter)
	var line1: String = "%s   HP %d/%d%s" % [fighter.name, fighter.hp, fighter.max_hp, "  +%d" % shield if shield > 0 else ""]
	var line2: String = "AP %d/%d  MP %d/%d  (%s)" % [fighter.ap, fighter.max_ap, fighter.mp, fighter.max_mp, refill_text]
	var line3: String = "Plan: %s" % builder.summary(fighter.id) if mode == Mode.PLANNING else ""
	return "%s\n%s\n%s" % [line1, line2, line3]


func _update_actions() -> void:
	for child: Node in _actions_box.get_children():
		child.queue_free()
	if mode != Mode.PLANNING or selected < 0:
		return
	var fighter: FighterState = state.fighters[selected]
	var title: Label = Label.new()
	title.text = "%s: abilities" % fighter.name
	_actions_box.add_child(title)
	for ability_id: String in fighter.abilities:
		var ability: Dictionary = state.abilities[ability_id]
		var reason: String = builder.unavailable_reason(selected, ability_id)
		var button: Button = Button.new()
		button.toggle_mode = true
		button.text = "%s  (%d AP%s)" % [ability.get("name", ability_id), int(ability["ap_cost"]), ", cooldown %d" % int(ability["cooldown"]) if int(ability["cooldown"]) > 0 else ""]
		button.disabled = reason != ""
		button.tooltip_text = reason if reason != "" else _ability_tip(ability)
		button.set_pressed_no_signal(str(builder.draft(selected)["ability"]) == ability_id)
		button.pressed.connect(func() -> void: choose_ability(ability_id))
		_actions_box.add_child(button)
	var order: CheckBox = CheckBox.new()
	order.text = "Ability first, then move"
	order.set_pressed_no_signal(str(builder.draft(selected)["order"]) == Plans.ORDER_ABILITY_FIRST)
	order.toggled.connect(set_order)
	_actions_box.add_child(order)
	var clear: Button = Button.new()
	clear.text = "Clear plan (Esc)"
	clear.pressed.connect(clear_selected)
	_actions_box.add_child(clear)
	if targeting:
		_set_hint("Pick a yellow cell to aim at.")
	elif last_message == "":
		_set_hint("Click a creature, then a blue cell to move, or an ability then a target. Space = Ready.")


func _ability_tip(ability: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("range %d-%d" % [int(ability["min_range"]), int(ability["max_range"])])
	parts.append("phase %s" % str(ability["phase"]))
	if int(ability["karma"]) != 0:
		parts.append("karma %+d" % int(ability["karma"]))
	for effect: Dictionary in ability["effects"]:
		match str(effect["type"]):
			"damage":
				parts.append("damage %d" % int(effect["base"]))
			"push":
				parts.append("push %d" % int(effect["distance"]))
			"pull":
				parts.append("pull %d" % int(effect["distance"]))
			"shield":
				parts.append("shield %d" % int(effect["amount"]))
			"heal":
				parts.append("heal %d" % int(effect["amount"]))
			"apply_status":
				parts.append(str(effect["status"]))
	return ", ".join(parts)


func _update_overlays() -> void:
	board.clear_overlays()
	if mode != Mode.PLANNING:
		return
	var path_cells: Array[int] = []
	for id: int in builder.drafts.keys():
		for cell: Vector2i in builder.draft(id)["path"]:
			path_cells.append(state.grid.index_of(cell))
	board.set_overlay("path", path_cells, COLOR_PATH)
	if selected >= 0:
		if targeting:
			var targets: Array[int] = []
			for index: int in builder.target_cells(selected):
				targets.append(index)
			board.set_overlay("target", targets, COLOR_TARGET)
		else:
			board.set_overlay("reach", builder.reachable_cells(selected), COLOR_REACH)
	if _threat_check.button_pressed:
		var zone: Dictionary = {}
		for monster: FighterState in state.living(FighterState.SIDE_MONSTERS):
			for index: int in RulesEngine.threat_zone(state, monster.id):
				zone[index] = true
		var cells: Array[int] = []
		for index: int in zone.keys():
			cells.append(index)
		board.set_overlay("threat", cells, COLOR_THREAT)


## R9.1-R9.2: the preview is the real resolution of the Creatures' plans on a copy.
func _update_preview() -> void:
	var forecast: Dictionary = RulesEngine.forecast(state)
	board.set_forecast(forecast["changed"], forecast["next"])
	var after: int = int(forecast["board_karma_after"])
	var texts: Dictionary = {}
	if mode == Mode.PLANNING:
		var result: Dictionary = builder.preview()
		if not result.is_empty() and result["ok"]:
			after = (result["state"] as FightState).board_karma()
			var changes: Dictionary = builder.preview_changes(result)
			for id: int in changes.keys():
				var delta: int = int(changes[id]["delta"])
				var note: String = str(changes[id]["note"])
				var text: String = "%+d" % delta if delta != 0 else ""
				if note != "":
					text += (" " if text != "" else "") + note
				texts[id] = {"text": text, "color": Color(1.0, 0.55, 0.3) if delta < 0 else Color(0.5, 1.0, 0.55)}
	board.set_previews(texts)
	meter.set_values(state.board_karma(), after)


# --- Building the screen ---


func _build_ui() -> void:
	var top: HBoxContainer = HBoxContainer.new()
	top.position = Vector2(16, 8)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	meter = LandMeter.new()
	top.add_child(meter)
	_step_label = Label.new()
	top.add_child(_step_label)
	_timer_bar = ProgressBar.new()
	_timer_bar.custom_minimum_size = Vector2(150, 18)
	_timer_bar.show_percentage = false
	_timer_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_timer_bar)
	_ready_button = Button.new()
	_ready_button.text = "Ready (Space)"
	_ready_button.pressed.connect(resolve_step)
	top.add_child(_ready_button)
	_untimed_check = CheckBox.new()
	_untimed_check.text = "Untimed (dev)"
	_untimed_check.toggled.connect(func(on: bool) -> void: untimed = on)
	top.add_child(_untimed_check)
	_threat_check = CheckBox.new()
	_threat_check.text = "Threats"
	_threat_check.toggled.connect(func(_on: bool) -> void: _refresh())
	top.add_child(_threat_check)

	_party_box = VBoxContainer.new()
	_party_box.position = Vector2(16, 70)
	_party_box.add_theme_constant_override("separation", 6)
	add_child(_party_box)

	_actions_box = VBoxContainer.new()
	_actions_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_actions_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_actions_box.position = Vector2(16, -16)
	add_child(_actions_box)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 60
	add_child(_banner)

	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -34
	_hint.offset_bottom = -8
	add_child(_hint)

	_end_panel = PanelContainer.new()
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.13, 0.96)
	panel_style.set_content_margin_all(20)
	panel_style.set_corner_radius_all(6)
	_end_panel.add_theme_stylebox_override("panel", panel_style)
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var end_box: VBoxContainer = VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 12)
	_end_panel.add_child(end_box)
	_end_title = Label.new()
	_end_title.add_theme_font_size_override("font_size", 40)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(_end_title)
	_end_details = Label.new()
	_end_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_box.add_child(_end_details)
	var restart_button: Button = Button.new()
	restart_button.text = "Restart"
	restart_button.pressed.connect(restart)
	end_box.add_child(restart_button)
	_end_panel.hide()
	add_child(_end_panel)

	_build_label = Label.new()
	_build_label.text = _build_info()
	_build_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_build_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_build_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_build_label)


func _set_hint(text: String) -> void:
	last_message = text
	if _hint != null:
		_hint.text = text


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
