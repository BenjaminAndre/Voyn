class_name Los
extends RefCounted
## Line of sight (GDD R5), the exact integer algorithm from docs/architecture.md.
## No floats. Signed floor division goes through Hex.floor_div, never the language's '/'.
##
## `blocks` is a Callable(cell: Vector2i) -> bool that says whether a cell stops LoS: it is not
## `blocks_los`-clear, it holds a fighter, or it lies outside the Arena. It is asked only about
## cells strictly between A and B (R5.1); the endpoints never block themselves.

## Tiny integer nudge that breaks exact ties without changing any non-tie result.
const NUDGE: Vector3i = Vector3i(1, 2, -3)
const SCALE: int = 12


## R5.2, R5.3: true if the line A -> B is clear with the positive nudge or with the negative nudge.
## Symmetric: has_los(a, b) == has_los(b, a).
static func has_los(a: Vector2i, b: Vector2i, blocks: Callable) -> bool:
	if a == b or Hex.distance(a, b) == 1:
		return true
	return _line_clear(a, b, 1, blocks) or _line_clear(a, b, -1, blocks)


static func _line_clear(a: Vector2i, b: Vector2i, sign: int, blocks: Callable) -> bool:
	var n: int = Hex.distance(a, b)
	var d: int = SCALE * n
	var ca: Vector3i = Hex.to_cube(a)
	var cb: Vector3i = Hex.to_cube(b)
	var nudge: Vector3i = NUDGE * sign
	for i: int in range(1, n):
		var p: Vector3i = (ca * n + (cb - ca) * i) * SCALE + nudge
		var cell: Vector2i = Hex.from_cube(_cube_round(p, d))
		if blocks.call(cell):
			return false
	return true


## The cell nearest to p / d, in cube coordinates.
static func _cube_round(p: Vector3i, d: int) -> Vector3i:
	var rx: int = _div_round(p.x, d)
	var ry: int = _div_round(p.y, d)
	var rz: int = _div_round(p.z, d)
	var dx: int = absi(rx * d - p.x)
	var dy: int = absi(ry * d - p.y)
	var dz: int = absi(rz * d - p.z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector3i(rx, ry, rz)


## Round n / d to the nearest integer. The nudge guarantees it is never a tie.
static func _div_round(n: int, d: int) -> int:
	return Hex.floor_div(2 * n + d, 2 * d)
