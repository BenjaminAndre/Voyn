class_name FighterView
extends Node3D
## A placeholder 3D figure for one fighter: a shape by creature or Monster kind, a colour by Side,
## and a floating label with its name, HP, AP and MP. Client-only.

var fighter_id: int = -1
var _label: Label3D
var _preview: Label3D
var _body: MeshInstance3D
var _base_scale: Vector3 = Vector3.ONE


func setup(fighter: FighterState) -> void:
	fighter_id = fighter.id
	_body = MeshInstance3D.new()
	_body.mesh = _mesh_for(fighter.kind)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = _color_for(fighter)
	_body.material_override = material
	_body.position.y = 0.45
	add_child(_body)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.007
	_label.font_size = 36
	_label.outline_size = 10
	_label.position.y = 1.5
	add_child(_label)

	_preview = Label3D.new()
	_preview.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_preview.no_depth_test = true
	_preview.pixel_size = 0.009
	_preview.font_size = 40
	_preview.outline_size = 12
	_preview.position.y = 2.25
	_preview.visible = false
	add_child(_preview)
	refresh(fighter)


## Updates the label from the fighter's current numbers: a short name, HP and Shield.
func refresh(fighter: FighterState) -> void:
	set_hp_text(fighter.hp, fighter)


## Same, with an HP value that may be ahead of the fighter's own (during playback).
func set_hp_text(hp: int, fighter: FighterState) -> void:
	_label.text = "%s\n%d" % [fighter.name.trim_prefix("PH "), hp]
	var shield: int = Statuses.shield_amount(fighter)
	if shield > 0:
		_label.text += " +%d" % shield


## Shows what the plan preview says will happen to this fighter ("" hides it).
func set_preview(text: String, color: Color) -> void:
	_preview.visible = text != ""
	_preview.text = text
	_preview.modulate = color


func fade_out(duration: float) -> Tween:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), duration)
	tween.tween_callback(hide)
	return tween


func restore() -> void:
	scale = Vector3.ONE
	show()


func _mesh_for(kind: String) -> Mesh:
	match kind:
		"ph_tank":
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.8, 0.9, 0.8)
			return box
		"ph_striker":
			var prism: PrismMesh = PrismMesh.new()
			prism.size = Vector3(0.75, 1.0, 0.75)
			return prism
		"ph_archer":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.38
			sphere.height = 0.76
			return sphere
		"ph_brute":
			var big: BoxMesh = BoxMesh.new()
			big.size = Vector3(0.95, 1.1, 0.95)
			return big
		"ph_flier":
			var small: SphereMesh = SphereMesh.new()
			small.radius = 0.3
			small.height = 0.6
			return small
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 0.9
	return capsule


## The Side sets the colour (blue = us, red = them); the kind only sets the shape (R9.3).
func _color_for(fighter: FighterState) -> Color:
	return Palette.US if fighter.is_creature() else Palette.THEM
