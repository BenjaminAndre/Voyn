extends GutTest
## Round 2, item 2.10 (GDD R9.3): secondary colours for the terrain, primary colours for the Sides,
## four blue shades for the plan, and no orange.

const PURPLE: Array[float] = [0.72, 0.85]
const GREEN: Array[float] = [0.25, 0.42]
const BLUE: Array[float] = [0.55, 0.68]


func _in(value: float, range: Array[float]) -> bool:
	return value >= range[0] and value <= range[1]


func test_corruption_is_purple_lighter_for_corrupted_and_darker_for_blighted() -> void:
	var blighted: Color = Palette.TERRAIN[0]
	var corrupted: Color = Palette.TERRAIN[1]
	assert_true(_in(blighted.h, PURPLE), "Blighted hue %f" % blighted.h)
	assert_true(_in(corrupted.h, PURPLE), "Corrupted hue %f" % corrupted.h)
	assert_gt(Palette.luminance(corrupted), Palette.luminance(blighted))


func test_purity_is_green_lighter_for_pure_and_darker_for_thriving() -> void:
	var pure: Color = Palette.TERRAIN[3]
	var thriving: Color = Palette.TERRAIN[4]
	assert_true(_in(pure.h, GREEN), "Pure hue %f" % pure.h)
	assert_true(_in(thriving.h, GREEN), "Thriving hue %f" % thriving.h)
	assert_gt(Palette.luminance(pure), Palette.luminance(thriving))


func test_neutral_is_plain_stone() -> void:
	var neutral: Color = Palette.TERRAIN[2]
	assert_lt(neutral.s, 0.1, "almost no saturation")
	assert_between(Palette.luminance(neutral), 0.4, 0.85)


func test_the_board_tints_tiles_with_the_terrain_palette() -> void:
	assert_eq(BoardView.KARMA_COLORS, Palette.TERRAIN)


func test_forecast_markers_and_the_land_meter_use_the_terrain_purple_and_green() -> void:
	assert_true(_in(Palette.CORRUPT.h, PURPLE))
	assert_true(_in(Palette.PURIFY.h, GREEN))
	assert_eq(LandMeter.COLOR_BLIGHT, Palette.CORRUPT)
	assert_eq(LandMeter.COLOR_PURE, Palette.PURIFY)


func test_sides_use_primary_colours() -> void:
	assert_true(_in(Palette.US.h, BLUE), "us = blue")
	assert_true(Palette.THEM.h < 0.03 or Palette.THEM.h > 0.97, "them = red")
	assert_between(Palette.NEUTRAL_SIDE.h, 0.12, 0.19, "neutral = yellow")


func test_plan_overlays_are_four_shades_of_blue_light_to_dark() -> void:
	assert_eq(Palette.US_SHADES.size(), 4)
	for shade: Color in Palette.US_SHADES:
		assert_true(_in(shade.h, BLUE), "shade hue %f" % shade.h)
	for i: int in range(1, 4):
		assert_lt(Palette.luminance(Palette.US_SHADES[i]), Palette.luminance(Palette.US_SHADES[i - 1]), "shade %d is darker than %d" % [i + 1, i])


func test_threat_zones_are_red() -> void:
	assert_true(Palette.THREAT.h < 0.03 or Palette.THREAT.h > 0.97)


func test_no_colour_in_the_palette_is_orange() -> void:
	var palette_script: Script = load("res://src/client/palette.gd")
	var constants: Dictionary = palette_script.get_script_constant_map()
	var checked: int = 0
	for name: String in constants.keys():
		var value: Variant = constants[name]
		var colors: Array[Color] = []
		if value is Color:
			colors.append(value)
		elif value is Array:
			for entry: Variant in value:
				if entry is Color:
					colors.append(entry)
		for color: Color in colors:
			checked += 1
			var orange: bool = color.h > 0.035 and color.h < 0.115 and color.s > 0.45 and color.v > 0.4
			assert_false(orange, "%s is orange" % name)
	assert_gt(checked, 15, "the scan saw the palette")


func test_overlay_colours_in_the_game_follow_the_scheme() -> void:
	var main_script: Script = load("res://src/client/main.gd")
	var constants: Dictionary = main_script.get_script_constant_map()
	assert_eq(constants["COLOR_REACH"], Palette.US_SHADES[0])
	assert_eq(constants["COLOR_PATH"], Palette.US_SHADES[1])
	assert_eq(constants["COLOR_AREA"], Palette.US_SHADES[3])
	assert_eq(constants["COLOR_THREAT"], Palette.THREAT)


# --- Fighters: the Side sets the colour, the kind sets the shape ---


func _view(kind: String, creature: bool) -> FighterView:
	var roster: Array = [
		TestFixtures.creature({"kind": "ph_tank", "name": "PH Tank"}),
		TestFixtures.monster([2, 0], {"kind": "ph_brute", "name": "PH Brute"}),
	]
	var state: FightState = TestFixtures.running(roster, [Vector2i(0, 0)])
	var fighter: FighterState = state.fighters[0] if creature else state.fighters[1]
	fighter.kind = kind
	var view: FighterView = FighterView.new()
	add_child_autofree(view)
	view.setup(fighter)
	return view


func _color_of(view: FighterView) -> Color:
	return ((view._body.material_override) as StandardMaterial3D).albedo_color


func _shape_of(view: FighterView) -> String:
	var mesh: Mesh = view._body.mesh
	return "%s %s" % [mesh.get_class(), str(mesh.get_aabb().size)]


func test_every_creature_is_our_blue_whatever_its_kind() -> void:
	for kind: String in ["ph_tank", "ph_striker", "ph_archer"]:
		assert_eq(_color_of(_view(kind, true)), Palette.US, kind)


func test_every_monster_is_their_red_whatever_its_kind() -> void:
	for kind: String in ["ph_brute", "ph_flier"]:
		assert_eq(_color_of(_view(kind, false)), Palette.THEM, kind)


func test_kinds_on_one_side_differ_by_shape() -> void:
	var creature_shapes: Dictionary = {}
	for kind: String in ["ph_tank", "ph_striker", "ph_archer"]:
		creature_shapes[_shape_of(_view(kind, true))] = true
	assert_eq(creature_shapes.size(), 3, "three creatures, three shapes")
	var monster_shapes: Dictionary = {}
	for kind: String in ["ph_brute", "ph_flier"]:
		monster_shapes[_shape_of(_view(kind, false))] = true
	assert_eq(monster_shapes.size(), 2)


func test_forecast_markers_use_the_terrain_colours() -> void:
	var roster: Array = [TestFixtures.creature(), TestFixtures.monster([2, 0])]
	var state: FightState = TestFixtures.running(roster, [Vector2i(0, 0)])
	var board: BoardView = BoardView.new()
	add_child_autofree(board)
	board.setup(state)
	var next: PackedInt32Array = state.karma.duplicate()
	next[3] = state.karma[3] + 1
	next[4] = state.karma[4] - 1
	board.set_forecast(PackedInt32Array([3, 4]), next)
	var colors: Array[Color] = []
	for marker: Node in board._forecast_root.get_children():
		colors.append(((marker as MeshInstance3D).material_override as StandardMaterial3D).albedo_color)
	assert_eq(colors, [Palette.PURIFY, Palette.CORRUPT])
