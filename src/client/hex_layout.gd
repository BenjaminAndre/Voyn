class_name HexLayout
extends RefCounted
## Where hex cells sit in the 3D world: flat-top hexes in the XZ plane, axial (q, r) as in the rules
## (R1.1). Client-only, so it may use floats. Tile centers are sqrt(3) x size apart.

const SQRT3: float = 1.7320508075688772


## The world position (y = 0) of a cell's center.
static func to_world(cell: Vector2i, size: float) -> Vector3:
	return Vector3(size * 1.5 * cell.x, 0.0, size * SQRT3 * (cell.y + cell.x * 0.5))


## The cell containing a world point (its XZ coordinates); the inverse of `to_world`.
static func from_world(point: Vector3, size: float) -> Vector2i:
	var q: float = (2.0 / 3.0 * point.x) / size
	var r: float = (-1.0 / 3.0 * point.x + SQRT3 / 3.0 * point.z) / size
	return _round(q, r)


## The six corners of a cell, relative to its center, in the XZ plane (circumradius = size).
static func corners(size: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i: int in 6:
		var angle: float = deg_to_rad(60.0 * i)
		result.append(Vector3(size * cos(angle), 0.0, size * sin(angle)))
	return result


static func _round(q: float, r: float) -> Vector2i:
	var x: float = q
	var z: float = r
	var y: float = -x - z
	var rx: float = roundf(x)
	var ry: float = roundf(y)
	var rz: float = roundf(z)
	var dx: float = absf(rx - x)
	var dy: float = absf(ry - y)
	var dz: float = absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))
