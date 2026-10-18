class_name LandMeter
extends Control
## The Land meter (GDD R9.3): one bar from `collapse_at` to `bloom_at`, with board karma now and
## after this step's Land phase. Always on screen.

const COLOR_BACK: Color = Color(0.12, 0.12, 0.14, 0.85)
const COLOR_BLIGHT: Color = Palette.CORRUPT
const COLOR_PURE: Color = Palette.PURIFY
const COLOR_NOW: Color = Palette.METER_NOW
const COLOR_AFTER: Color = Palette.METER_AFTER

var collapse_at: int = -1
var bloom_at: int = 1
var now: int = 0
var after: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(360, 44)


func configure(collapse: int, bloom: int) -> void:
	collapse_at = collapse
	bloom_at = bloom
	queue_redraw()


func set_values(board_karma_now: int, board_karma_after: int) -> void:
	now = board_karma_now
	after = board_karma_after
	queue_redraw()


func _draw() -> void:
	var bar: Rect2 = Rect2(8, 20, size.x - 16, 14)
	draw_rect(bar, COLOR_BACK)
	var zero_x: float = bar.position.x + bar.size.x * float(-collapse_at) / float(bloom_at - collapse_at)
	draw_rect(Rect2(bar.position.x, bar.position.y, zero_x - bar.position.x, bar.size.y), COLOR_BLIGHT.darkened(0.4))
	draw_rect(Rect2(zero_x, bar.position.y, bar.end.x - zero_x, bar.size.y), COLOR_PURE.darkened(0.5))
	draw_line(Vector2(zero_x, bar.position.y - 3), Vector2(zero_x, bar.end.y + 3), Color(0.8, 0.8, 0.8), 1.0)
	_tick(bar, now, COLOR_NOW, 3.0, 10.0)
	if after != now:
		_tick(bar, after, COLOR_AFTER, 2.0, 6.0)
	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(8, 14), "Collapse %d" % collapse_at, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_BLIGHT.lightened(0.5))
	draw_string(font, Vector2(size.x - 8, 14), "Bloom +%d" % bloom_at, HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, COLOR_PURE.lightened(0.3))
	draw_string(font, Vector2(size.x * 0.5 - 60, 14), "Land %d (next %d)" % [now, after], HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(1, 1, 1))


func _tick(bar: Rect2, value: int, color: Color, width: float, overshoot: float) -> void:
	var clamped: float = clampf(float(value), float(collapse_at), float(bloom_at))
	var x: float = bar.position.x + bar.size.x * (clamped - float(collapse_at)) / float(bloom_at - collapse_at)
	draw_line(Vector2(x, bar.position.y - overshoot * 0.4), Vector2(x, bar.end.y + overshoot * 0.4), color, width)
