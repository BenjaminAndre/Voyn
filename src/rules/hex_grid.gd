class_name HexGrid
extends RefCounted
## The set of cells of an Arena, in cell order (R1.3), with precomputed neighbor indices.
## Per-cell data (karma, walkable, blocks_los) lives in packed int arrays indexed by cell index,
## so copying a fight state stays cheap (docs/architecture.md).

## Cells in cell order: ascending q, then ascending r. Do not modify after creation.
var cells: Array[Vector2i] = []

## For each cell index, the indices of its neighbors that exist in the Arena, in direction order.
## A missing neighbor (Arena edge or hole) is simply absent: it counts as 0 in sums (R11.4).
var neighbor_indices: Array[PackedInt32Array] = []

var _index: Dictionary = {}


## Builds a grid from any list of distinct cells. Returns null if a cell appears twice.
static func from_cells(source: Array[Vector2i]) -> HexGrid:
	var grid: HexGrid = HexGrid.new()
	grid.cells = source.duplicate()
	Hex.sort_cells(grid.cells)
	for i: int in grid.cells.size():
		if grid._index.has(grid.cells[i]):
			return null
		grid._index[grid.cells[i]] = i
	for cell: Vector2i in grid.cells:
		var found: PackedInt32Array = PackedInt32Array()
		for n: Vector2i in Hex.neighbors(cell):
			if grid._index.has(n):
				found.append(int(grid._index[n]))
		grid.neighbor_indices.append(found)
	return grid


## A regular hexagonal Arena of the given radius around (0, 0): 1 + 3r(r+1) cells.
static func hexagon(radius: int) -> HexGrid:
	return from_cells(Hex.disk(Vector2i.ZERO, radius))


func size() -> int:
	return cells.size()


func has_cell(cell: Vector2i) -> bool:
	return _index.has(cell)


## Index of a cell, or -1 if it is outside the Arena.
func index_of(cell: Vector2i) -> int:
	if _index.has(cell):
		return int(_index[cell])
	return -1


func cell_at(index: int) -> Vector2i:
	return cells[index]
