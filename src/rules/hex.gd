class_name Hex
extends RefCounted
## Hex math on axial coordinates (q, r) stored as Vector2i, integers only (GDD R1, R7.5).
## Cube coordinates are x = q, z = r, y = -q - r, stored as Vector3i.

## R1.2 Direction order D0..D5. A tie between directions goes to the lowest index.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func to_cube(cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x, -cell.x - cell.y, cell.y)


static func from_cube(cube: Vector3i) -> Vector2i:
	return Vector2i(cube.x, cube.z)


## R1.1 Hex distance = (|dq| + |dr| + |dq + dr|) / 2. The sum is always even, so the shift is exact.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) >> 1


static func neighbor(cell: Vector2i, direction: int) -> Vector2i:
	return cell + DIRECTIONS[direction]


## The 6 neighbors in direction order (D0..D5). Includes cells outside any Arena.
static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		result.append(cell + direction)
	return result


static func opposite(direction: int) -> int:
	return (direction + 3) % 6


## R1.3 Cell order: ascending q, then ascending r. Usable with Array.sort_custom.
static func cell_less(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


static func sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(cell_less)


## All cells within `radius` of `center` (including it), in cell order.
static func disk(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dq: int in range(-radius, radius + 1):
		for dr: int in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			result.append(center + Vector2i(dq, dr))
	sort_cells(result)
	return result


## Cells at exactly `radius` from `center`, in cell order. Radius 0 is the center alone.
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in disk(center, radius):
		if distance(center, cell) == radius:
			result.append(cell)
	return result


## R7.5 Push direction: the Dk closest to the vector from `origin` to `target`
## (largest dot product in cube coordinates; tie -> lowest index). -1 if target is on the origin.
static func push_direction(origin: Vector2i, target: Vector2i) -> int:
	if origin == target:
		return -1
	var v: Vector3i = to_cube(target - origin)
	var best: int = 0
	var best_dot: int = 0
	for k: int in 6:
		var d: Vector3i = to_cube(DIRECTIONS[k])
		var dot: int = v.x * d.x + v.y * d.y + v.z * d.z
		if k == 0 or dot > best_dot:
			best_dot = dot
			best = k
	return best


## R7.5 Pull uses the opposite direction. -1 if target is on the origin.
static func pull_direction(origin: Vector2i, target: Vector2i) -> int:
	var push: int = push_direction(origin, target)
	if push < 0:
		return -1
	return opposite(push)


## Floor division for m > 0 using '/' on non-negative values only (docs/architecture.md).
static func floor_div(n: int, m: int) -> int:
	assert(m > 0, "floor_div needs m > 0")
	if n >= 0:
		@warning_ignore("integer_division")
		return n / m
	@warning_ignore("integer_division")
	return -((-n + m - 1) / m)
