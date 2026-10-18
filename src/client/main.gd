extends Control
## Placeholder main scene: a title and the build info in the corner (docs/architecture.md, release
## pipeline). The CI workflow writes build_info.txt (short commit hash + UTC build date) before export.

const BUILD_INFO_PATH: String = "res://build_info.txt"


func _ready() -> void:
	var title: Label = Label.new()
	title.text = "Voyn"
	title.add_theme_font_size_override("font_size", 48)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(title)

	var info: Label = Label.new()
	info.text = _build_info()
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(info)


func _build_info() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	var text: String = "v%s" % version
	if FileAccess.file_exists(BUILD_INFO_PATH):
		text += " " + FileAccess.get_file_as_string(BUILD_INFO_PATH).strip_edges()
	else:
		text += " dev"
	return text
