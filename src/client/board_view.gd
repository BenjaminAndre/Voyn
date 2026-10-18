class_name BoardView
extends Node3D
## The 3D hex board (T12): tiles tinted by karma, pillars, fighters, highlight layers, forecast
## markers, a fixed orthographic camera, mouse picking, and a tween-only player for rules events.
## It reads state and events and never decides a rule (docs/architecture.md). Client-only.

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
## A banner text to show during resolution, e.g. the current phase.
signal banner(text: String)
signal land_changed(board_karma: int)
## Emitted just before each rules event plays (the resolution log listens).
signal event_played(event: Dictionary)

const TILE_SIZE: float = 1.0
const TILE_HEIGHT: float = 0.3
const PILLAR_HEIGHT: float = 1.1
const GAP: float = 0.94  # tiles are drawn slightly smaller than their cell, so edges show

## Karma tints (R9.3): purple for corruption, green for purity, stone for Neutral (see Palette).
const KARMA_COLORS: Array[Color] = Palette.TERRAIN
const PILLAR_COLOR: Color = Palette.PILLAR

var state: FightState
## Playback speed; 0 skips every wait (tests).
var animation_speed: float = 1.0

var _tiles: Array[MeshInstance3D] = []
var _tile_materials: Array[StandardMaterial3D] = []
var _fighters: Dictionary = {}
var _layers: Dictionary = {}
var _forecast_root: Node3D
var _camera: Camera3D
var _hovered: Vector2i = Vector2i(9999, 9999)
var _tile_mesh: ArrayMesh
var _slab_mesh: ArrayMesh


func _ready() -> void:
	_forecast_root = Node3D.new()
	add_child(_forecast_root)


## Builds the tiles, the pillars, the camera and the fighters for a fight.
func setup(new_state: FightState) -> void:
	state = new_state
	for child: Node in get_children():
		if child != _forecast_root:
			child.queue_free()
	_tiles.clear()
	_tile_materials.clear()
	_fighters.clear()
	_layers.clear()
	_tile_mesh = _hex_prism(TILE_SIZE * GAP, TILE_HEIGHT)
	_slab_mesh = _hex_prism(TILE_SIZE * GAP * 0.96, 0.03)
	for index: int in state.grid.size():
		var cell: Vector2i = state.grid.cell_at(index)
		var tile: MeshInstance3D = MeshInstance3D.new()
		tile.mesh = _tile_mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		tile.material_override = material
		tile.position = HexLayout.to_world(cell, TILE_SIZE)
		add_child(tile)
		_tiles.append(tile)
		_tile_materials.append(material)
		if state.walkable[index] == 0:
			var pillar: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(TILE_SIZE * 1.1, PILLAR_HEIGHT, TILE_SIZE * 1.1)
			pillar.mesh = box
			var pillar_material: StandardMaterial3D = StandardMaterial3D.new()
			pillar_material.albedo_color = PILLAR_COLOR
			pillar.material_override = pillar_material
			pillar.position = tile.position + Vector3(0, TILE_HEIGHT + PILLAR_HEIGHT * 0.5, 0)
			add_child(pillar)
	_build_camera()
	_build_light()
	for fighter: FighterState in state.fighters:
		var view: FighterView = FighterView.new()
		add_child(view)
		view.setup(fighter)
		_fighters[fighter.id] = view
	sync(state)


## Snaps every visual to `new_state`: tile tints, fighter positions, labels, who is on the board.
func sync(new_state: FightState) -> void:
	state = new_state
	for index: int in state.grid.size():
		_tile_materials[index].albedo_color = _karma_color(state.karma[index])
	for fighter: FighterState in state.fighters:
		var view: FighterView = _fighters[fighter.id]
		if fighter.on_board():
			view.restore()
			view.position = _stand_point(fighter.cell)
			view.refresh(fighter)
		else:
			view.hide()


func world_of(cell: Vector2i) -> Vector3:
	return HexLayout.to_world(cell, TILE_SIZE)


func fighter_view(id: int) -> FighterView:
	return _fighters.get(id)


# --- Overlays: reachable, target, area, threat, path, selected ---


## Highlights cells (indices) on a named layer, replacing what that layer showed.
func set_overlay(layer: String, cells: Array[int], color: Color) -> void:
	clear_overlay(layer)
	if cells.is_empty():
		return
	var root: Node3D = Node3D.new()
	add_child(root)
	_layers[layer] = root
	for index: int in cells:
		var slab: MeshInstance3D = MeshInstance3D.new()
		slab.mesh = _slab_mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		slab.material_override = material
		slab.position = HexLayout.to_world(state.grid.cell_at(index), TILE_SIZE) + Vector3(0, TILE_HEIGHT + 0.02 + 0.01 * _layers.size(), 0)
		root.add_child(slab)


func clear_overlay(layer: String) -> void:
	if _layers.has(layer):
		(_layers[layer] as Node3D).queue_free()
		_layers.erase(layer)


## Shows preview texts above fighters: {fighter id: {"text": String, "color": Color}}. Others are cleared.
func set_previews(texts: Dictionary) -> void:
	for id: int in _fighters.keys():
		var view: FighterView = _fighters[id]
		if texts.has(id):
			view.set_preview(str(texts[id]["text"]), texts[id]["color"])
		else:
			view.set_preview("", Color.WHITE)


func clear_overlays() -> void:
	for layer: String in _layers.keys():
		clear_overlay(layer)


## Forecast markers (R11.5, R9.3): a green cone on cells the next Land phase would purify, a red
## inverted cone on those it would corrupt. `changed` are cell indices; `next` the karma after.
func set_forecast(changed: PackedInt32Array, next: PackedInt32Array) -> void:
	for child: Node in _forecast_root.get_children():
		child.queue_free()
	for index: int in changed:
		var rising: bool = next[index] > state.karma[index]
		var marker: MeshInstance3D = MeshInstance3D.new()
		var cone: CylinderMesh = CylinderMesh.new()
		cone.height = 0.35
		cone.radial_segments = 3
		cone.rings = 1
		cone.top_radius = 0.0 if rising else 0.22
		cone.bottom_radius = 0.22 if rising else 0.0
		marker.mesh = cone
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Palette.PURIFY if rising else Palette.CORRUPT
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = material
		marker.position = HexLayout.to_world(state.grid.cell_at(index), TILE_SIZE) + Vector3(0.45, TILE_HEIGHT + 0.25, -0.35)
		_forecast_root.add_child(marker)


# --- Picking ---


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or state == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = pick_at_screen(event.position)
		if state.grid.has_cell(cell):
			cell_clicked.emit(cell)
	elif event is InputEventMouseMotion:
		var cell: Vector2i = pick_at_screen(event.position)
		if cell != _hovered:
			_hovered = cell
			if state.grid.has_cell(cell):
				cell_hovered.emit(cell)


## The cell under a screen position, found by casting a ray onto the tile-top plane.
func cell_at_screen(position: Vector2) -> Vector2i:
	var origin: Vector3 = _camera.project_ray_origin(position)
	var direction: Vector3 = _camera.project_ray_normal(position)
	if absf(direction.y) < 0.0001:
		return Vector2i(9999, 9999)
	var t: float = (TILE_HEIGHT - origin.y) / direction.y
	return HexLayout.from_world(origin + direction * t, TILE_SIZE)


## The cell a click or hover at a screen position means. A fighter's figure (body or label) counts
## as its own cell and wins over the tile drawn behind it; elsewhere it is the tile under the point.
func pick_at_screen(position: Vector2) -> Vector2i:
	var best: int = -1
	var best_distance: float = INF
	var reach: float = maxf(6.0, 0.6 * _pixels_per_unit())
	var ids: Array = _fighters.keys()
	ids.sort()
	for id: int in ids:
		var view: FighterView = _fighters[id]
		var fighter: FighterState = state.fighters[id]
		if not view.visible or not fighter.on_board():
			continue
		# The figure is a column from its feet to its label.
		var feet: Vector2 = _camera.unproject_position(view.position + Vector3(0, 0.1, 0))
		var top: Vector2 = _camera.unproject_position(view.position + Vector3(0, 1.6, 0))
		var distance: float = _distance_to_segment(position, feet, top)
		if distance <= reach and distance < best_distance:
			best = id
			best_distance = distance
	if best >= 0:
		return state.cell_of(state.fighters[best])
	return cell_at_screen(position)


func camera() -> Camera3D:
	return _camera


func _pixels_per_unit() -> float:
	return get_viewport().get_visible_rect().size.y / _camera.size


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


# --- Playing events (tweens only) ---


## Plays the rules events of one step in order, then snaps to `final_state`.
func play_events(events: Array, final_state: FightState) -> void:
	for event: Dictionary in events:
		event_played.emit(event)
		await _play(event, final_state)
	sync(final_state)


func _play(event: Dictionary, final_state: FightState) -> void:
	match str(event["type"]):
		"phase_started":
			banner.emit(str(event["name"]).replace("_", " ").capitalize())
			await _wait(0.3)
		"moved":
			await _slide(int(event["fighter"]), _cell_of(event["to"]), 0.22)
		"displaced":
			await _slide(int(event["fighter"]), _cell_of(event["to"]), 0.3)
		"ability_used":
			var user: FighterView = fighter_view(int(event["fighter"]))
			_float_text(user.position + Vector3(0, 1.9, 0), str(event["ability"]).capitalize(), Palette.TEXT_PLAIN)
			set_overlay("cast", [state.grid.index_of(_cell_of(event["cell"]))], Palette.CAST_FLASH)
			await _wait(0.35)
			clear_overlay("cast")
		"fizzled":
			var fizzler: FighterView = fighter_view(int(event["fighter"]))
			_float_text(fizzler.position + Vector3(0, 1.9, 0), "fizzled", Palette.TEXT_MUTED)
			await _wait(0.25)
		"move_blocked":
			var blocked: FighterView = fighter_view(int(event["fighter"]))
			_float_text(blocked.position + Vector3(0, 1.7, 0), "blocked", Palette.TEXT_MUTED)
		"damaged":
			var hit: FighterView = fighter_view(int(event["fighter"]))
			var amount: int = int(event["amount"]) - int(event["absorbed"])
			_float_text(hit.position + Vector3(0, 1.9, 0), "-%d" % amount if amount > 0 else "absorbed", Palette.TEXT_DAMAGE)
			hit.set_hp_text(int(event["hp"]), state.fighters[int(event["fighter"])])
			await _wait(0.25)
		"healed":
			var healed: FighterView = fighter_view(int(event["fighter"]))
			_float_text(healed.position + Vector3(0, 1.9, 0), "+%d" % int(event["amount"]), Palette.TEXT_PLAIN)
			healed.set_hp_text(int(event["hp"]), state.fighters[int(event["fighter"])])
			await _wait(0.2)
		"collided":
			var crashed: FighterView = fighter_view(int(event["fighter"]))
			_float_text(crashed.position + Vector3(0, 2.2, 0), "crash!", Palette.TEXT_DAMAGE)
			await _wait(0.15)
		"defeated":
			var gone: FighterView = fighter_view(int(event["fighter"]))
			_float_text(gone.position + Vector3(0, 2.2, 0), str(event["how"]), Palette.TEXT_PLAIN)
			var tween: Tween = gone.fade_out(0.35 * animation_speed) if animation_speed > 0.0 else null
			if tween != null:
				await tween.finished
			else:
				gone.hide()
		"karma_changed":
			var index: int = state.grid.index_of(_cell_of(event["cell"]))
			_tint(index, int(event["to"]))
		"land_phase":
			land_changed.emit(int(event["board_karma"]))
			banner.emit("The Land answers")
			await _wait(0.3)
		"status_applied":
			var tagged: FighterView = fighter_view(int(event["fighter"]))
			_float_text(tagged.position + Vector3(0, 2.1, 0), str(event["status"]), Palette.TEXT_PLAIN)
		"shield_changed":
			var shielded: FighterView = fighter_view(int(event["fighter"]))
			if int(event["shield"]) > 0:
				_float_text(shielded.position + Vector3(0, 2.1, 0), "shield %d" % int(event["shield"]), Palette.TEXT_PLAIN)


func _slide(id: int, cell: Vector2i, seconds: float) -> void:
	var view: FighterView = fighter_view(id)
	if view == null:
		return
	if animation_speed <= 0.0:
		view.position = _stand_point(state.grid.index_of(cell))
		return
	var tween: Tween = create_tween()
	tween.tween_property(view, "position", _stand_point(state.grid.index_of(cell)), seconds * animation_speed)
	await tween.finished


func _tint(index: int, karma: int) -> void:
	var target: Color = _karma_color(karma)
	if animation_speed <= 0.0:
		_tile_materials[index].albedo_color = target
		return
	var tween: Tween = create_tween()
	tween.tween_property(_tile_materials[index], "albedo_color", target, 0.25 * animation_speed)


func _float_text(at: Vector3, text: String, color: Color) -> void:
	if animation_speed <= 0.0:
		return
	var label: Label3D = Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	label.font_size = 36
	label.outline_size = 8
	label.position = at
	add_child(label)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", at.y + 0.8, 0.9 * animation_speed)
	tween.tween_property(label, "modulate:a", 0.0, 0.9 * animation_speed)
	tween.chain().tween_callback(label.queue_free)


func _wait(seconds: float) -> void:
	if animation_speed <= 0.0 or not is_inside_tree():
		return
	await get_tree().create_timer(seconds * animation_speed).timeout


# --- Building blocks ---


func _cell_of(pair: Variant) -> Vector2i:
	return Vector2i(int((pair as Array)[0]), int((pair as Array)[1]))


func _stand_point(cell_index: int) -> Vector3:
	return HexLayout.to_world(state.grid.cell_at(cell_index), TILE_SIZE) + Vector3(0, TILE_HEIGHT, 0)


func _karma_color(karma: int) -> Color:
	return KARMA_COLORS[clampi(karma, -2, 2) + 2]


func _build_camera() -> void:
	if _camera != null:
		_camera.queue_free()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var reach: float = float(_arena_radius()) * TILE_SIZE
	_camera.size = (reach * 2.0 + 4.0) * 1.35
	add_child(_camera)
	_camera.position = Vector3(0, 18, 14)
	_camera.look_at(Vector3(0, 0, 1.0), Vector3.UP)
	_camera.current = true


func _build_light() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var environment: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	environment.environment = env
	add_child(environment)


func _arena_radius() -> int:
	var radius: int = 0
	for cell: Vector2i in state.grid.cells:
		radius = maxi(radius, Hex.distance(Vector2i.ZERO, cell))
	return radius


## A flat-topped hex prism: a top face and six sides, centered on the origin.
static func _hex_prism(size: float, height: float) -> ArrayMesh:
	var corners: Array[Vector3] = HexLayout.corners(size)
	var top: Vector3 = Vector3(0, height, 0)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i: int in 6:
		var a: Vector3 = corners[i] + top
		var b: Vector3 = corners[(i + 1) % 6] + top
		# Godot front faces wind clockwise as seen from the front.
		surface.set_normal(Vector3.UP)
		surface.add_vertex(top)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(a)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(b)
		var low_a: Vector3 = corners[i]
		var low_b: Vector3 = corners[(i + 1) % 6]
		var normal: Vector3 = ((a + b) * 0.5 - Vector3(0, height, 0)).normalized()
		for vertex: Vector3 in [a, low_b, b, a, low_a, low_b]:
			surface.set_normal(normal)
			surface.add_vertex(vertex)
	return surface.commit()
